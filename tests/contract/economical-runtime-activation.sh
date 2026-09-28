#!/usr/bin/env bash
# Contract for the reviewed GitOps state of the running economical platform:
# the shared EKS registration activates every business, environment-policy, and
# infrastructure Application. It replaced the quiescence contract once the
# economical runtime was rebuilt under the new names (microservice-app-ops spec
# 004 T021-T023; spec 009 T173). A future approved teardown reverses both in one
# reviewed change, as T170 did.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

render_kustomize() {
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

count() { grep -Ec "$1" "$ROOT/$2" || true; }

apps=clusters/eks-dev/activation-apps.yaml
environments=clusters/eks-dev/activation-environments.yaml
infrastructure=clusters/eks-dev/activation-infrastructure.yaml
for path in "$apps" "$environments" "$infrastructure"; do
  [[ -f "$ROOT/$path" ]] || fail "missing activation patch: $path"
  if grep -Eq '^  value: \[\]$' "$ROOT/$path"; then
    fail "$path is still quiescent"
  fi
done

# Business Applications: the four managed environments, each routed to the
# economical profile on this in-cluster destination.
[[ "$(count '^    - env:' "$apps")" == 4 ]] \
  || fail "$apps must activate exactly four environments"
[[ "$(count '^    - env: (dev|staging|prod|demo)$' "$apps")" == 4 ]] \
  || fail "$apps must activate exactly dev, staging, prod, and demo"
[[ "$(count '^      profile: economical$' "$apps")" == 4 ]] \
  || fail "every business activation must select the economical profile"
[[ "$(count '^      destination: eks-dev$' "$apps")" == 4 ]] \
  || fail "every business activation must name the eks-dev destination"
[[ "$(count '^      server: https://kubernetes.default.svc$' "$apps")" == 4 ]] \
  || fail "every business activation must target the in-cluster API server"

# Environment-policy Applications: the same four environments.
[[ "$(count '^    - env:' "$environments")" == 4 ]] \
  || fail "$environments must activate exactly four environments"
[[ "$(count '^    - env: (dev|staging|prod|demo)$' "$environments")" == 4 ]] \
  || fail "$environments must activate exactly dev, staging, prod, and demo"
[[ "$(count '^      server: https://kubernetes.default.svc$' "$environments")" == 4 ]] \
  || fail "every environment activation must target the in-cluster API server"

# Infrastructure Applications: exactly these controllers, each from its own
# directory into its own namespace. trivy-operator joins the thirteen the shared
# cluster ran before the quiescence, as tests/contract/security.sh requires.
expected=(
  "keda keda"
  "cert-manager cert-manager"
  "external-secrets external-secrets"
  "kyverno kyverno"
  "argo-rollouts argo-rollouts"
  "ebs-csi-driver kube-system"
  "prometheus observability"
  "grafana observability"
  "jaeger observability"
  "loki observability"
  "falco security"
  "kube-bench security"
  "kube-hunter security"
  "trivy-operator security"
  "aws-load-balancer-controller kube-system profiles/economical/aws-load-balancer-controller/destinations/eks-dev"
)
[[ "$(count '^    - name:' "$infrastructure")" == "${#expected[@]}" ]] \
  || fail "$infrastructure must activate exactly ${#expected[@]} controllers"
for entry in "${expected[@]}"; do
  read -r name namespace directory <<<"$entry"
  directory="${directory:-$name}"
  awk -v name="$name" -v ns="$namespace" -v dir="$directory" '
    $0 == "    - name: " name {
      getline path_line
      getline namespace_line
      if (path_line == "      path: infrastructure/" dir && namespace_line == "      namespace: " ns) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$ROOT/$infrastructure" \
    || fail "$infrastructure must activate $name from infrastructure/$directory into $namespace"
  [[ -f "$ROOT/infrastructure/$directory/kustomization.yaml" ]] \
    || fail "activated controller $name has no infrastructure/$directory/kustomization.yaml"
done
if grep -Eq 'name: (redis|sonarqube)$' "$ROOT/$infrastructure"; then
  fail "$infrastructure activates a retired or inactive capability"
fi

[[ -f "$ROOT/clusters/eks-dev/root-app.yaml" ]] \
  || fail "the EKS root registration must remain present"
grep -Eq 'path: clusters/eks-dev$' "$ROOT/clusters/eks-dev/root-app.yaml" \
  || fail "the root registration path changed"

render="$TMP_DIR/eks-dev.yaml"
render_kustomize "$ROOT/clusters/eks-dev" >"$render" \
  || fail "the active EKS registration does not render"
for name in apps environments infrastructure; do
  awk -v expected="$name" '
    BEGIN { found = 0; in_application_set = 0; in_metadata = 0 }
    /^kind: ApplicationSet$/ { in_application_set = 1; in_metadata = 0; next }
    in_application_set && /^metadata:$/ { in_metadata = 1; next }
    in_application_set && in_metadata && $0 == "  name: " expected {
      found = 1
      in_application_set = 0
      in_metadata = 0
    }
    in_application_set && /^kind: / {
      in_application_set = 0
      in_metadata = 0
    }
    END { exit(found ? 0 : 1) }
  ' "$render" || fail "rendered EKS registration is missing the $name ApplicationSet"
done

printf 'PASS: economical EKS GitOps activation is fully active.\n'

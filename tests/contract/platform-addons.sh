#!/usr/bin/env bash
# Static contract for the reusable, GitOps-managed platform foundation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*" >&2
}

render_kustomize() {
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "required file is missing: $1"
}

require_text() {
  local path="$1" pattern="$2" description="$3"
  rg -q -- "$pattern" "$ROOT/$path" || fail "$description ($path)"
}

reject_text() {
  local path="$1" pattern="$2" description="$3"
  if rg -q -- "$pattern" "$ROOT/$path"; then
    fail "$description ($path)"
  fi
}

require_resource() {
  local render="$1" kind="$2" name="$3"
  awk -v wanted_kind="$kind" -v wanted_name="$name" '
    /^---$/ { current_kind=""; in_metadata=0 }
    /^kind: / { current_kind=$2; in_metadata=0 }
    current_kind == wanted_kind && /^metadata:$/ { in_metadata=1; next }
    current_kind == wanted_kind && in_metadata && /^  name: / {
      name=$2
      gsub(/"/, "", name)
      if (name == wanted_name) found=1
      in_metadata=0
    }
    END { exit found ? 0 : 1 }
  ' "$render" || fail "$kind/$name is missing from $(basename "$render")"
}

check_checksum() {
  local directory="$1"
  require_file "$directory/SHA256SUMS"
  (
    cd "$ROOT/$directory"
    sha256sum -c SHA256SUMS >/dev/null
  ) || fail "checksum verification failed under $directory"
}

check_rendered_images() {
  local render="$1" image_ref
  while IFS= read -r image_ref; do
    image_ref="${image_ref%\"}"
    image_ref="${image_ref#\"}"
    [[ "$image_ref" == *@sha256:* ]] \
      || fail "rendered executable image is not digest-pinned: $image_ref"
  done < <(sed -nE 's/^[[:space:]-]*image:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$render")

  while IFS= read -r image_ref; do
    [[ "$image_ref" == *@sha256:* ]] \
      || fail "rendered image argument is not digest-pinned: $image_ref"
  done < <(rg -o -- '--[a-z0-9-]*image=[^[:space:]]+' "$render" | sed 's/^[^=]*=//')
}

declare -A VERSIONS=(
  [keda]="v2.20.1"
  [cert-manager]="v1.21.0"
  [external-secrets]="v2.9.0"
  [kyverno]="v1.18.2"
)

declare -A VENDOR_FILES=(
  [keda]="install.yaml"
  [cert-manager]="install.yaml"
  [external-secrets]="manifests.yaml"
  [kyverno]="install.yaml"
)

infrastructure_root_names=()
for addon_root in "$ROOT"/infrastructure/*/kustomization.yaml; do
  infrastructure_root_names+=("$(basename "$(dirname "$addon_root")")")
done
[[ "${#infrastructure_root_names[@]}" == "6" ]] \
  || fail "expected exactly six infrastructure roots, found ${#infrastructure_root_names[@]}"

for addon in keda cert-manager external-secrets kyverno; do
  [[ " ${infrastructure_root_names[*]} " == *" $addon "* ]] \
    || fail "infrastructure root is missing: $addon"
  require_file "infrastructure/$addon/kustomization.yaml"
  vendor_dir="infrastructure/$addon/vendor/${VERSIONS[$addon]}"
  require_file "$vendor_dir/${VENDOR_FILES[$addon]}"
  require_file "$vendor_dir/README.md"
  check_checksum "$vendor_dir"

  render="$TMP_DIR/$addon.yaml"
  render_kustomize "$ROOT/infrastructure/$addon" >"$render" \
    || fail "Kustomize render failed for $addon"
  [[ -s "$render" ]] || fail "$addon rendered no resources"
  check_rendered_images "$render"
done

[[ " ${infrastructure_root_names[*]} " == *" redis "* ]] \
  || fail "infrastructure root is missing: redis"
[[ " ${infrastructure_root_names[*]} " == *" sonarqube "* ]] \
  || fail "infrastructure root is missing: sonarqube"
require_file "infrastructure/redis/kustomization.yaml"
render_kustomize "$ROOT/infrastructure/redis" >"$TMP_DIR/redis.yaml" \
  || fail "Kustomize render failed for redis"
[[ -s "$TMP_DIR/redis.yaml" ]] || fail "redis rendered no resources"
check_rendered_images "$TMP_DIR/redis.yaml"

require_resource "$TMP_DIR/keda.yaml" Deployment keda-admission
require_resource "$TMP_DIR/keda.yaml" Deployment keda-metrics-apiserver
require_resource "$TMP_DIR/keda.yaml" Deployment keda-operator
require_resource "$TMP_DIR/keda.yaml" Deployment platform-autoscaling-check
require_resource "$TMP_DIR/keda.yaml" ScaledObject platform-autoscaling-check

require_resource "$TMP_DIR/cert-manager.yaml" Deployment cert-manager
require_resource "$TMP_DIR/cert-manager.yaml" Deployment cert-manager-cainjector
require_resource "$TMP_DIR/cert-manager.yaml" Deployment cert-manager-webhook
require_resource "$TMP_DIR/cert-manager.yaml" Issuer platform-selfsigned
require_resource "$TMP_DIR/cert-manager.yaml" Certificate platform-certificate-check

require_resource "$TMP_DIR/external-secrets.yaml" Deployment external-secrets
require_resource "$TMP_DIR/external-secrets.yaml" Deployment external-secrets-cert-controller
require_resource "$TMP_DIR/external-secrets.yaml" Deployment external-secrets-webhook
require_resource "$TMP_DIR/external-secrets.yaml" Namespace external-secrets

require_resource "$TMP_DIR/kyverno.yaml" Deployment kyverno-admission-controller
require_resource "$TMP_DIR/kyverno.yaml" Deployment kyverno-background-controller
require_resource "$TMP_DIR/kyverno.yaml" Deployment kyverno-cleanup-controller
require_resource "$TMP_DIR/kyverno.yaml" Deployment kyverno-reports-controller
require_resource "$TMP_DIR/kyverno.yaml" ClusterPolicy require-immutable-images
require_resource "$TMP_DIR/kyverno.yaml" ClusterPolicy require-health-probes

require_resource "$TMP_DIR/redis.yaml" Namespace redis
require_resource "$TMP_DIR/redis.yaml" ServiceAccount redis
require_resource "$TMP_DIR/redis.yaml" Deployment redis
require_resource "$TMP_DIR/redis.yaml" Service redis
require_resource "$TMP_DIR/redis.yaml" NetworkPolicy redis-default-deny
require_resource "$TMP_DIR/redis.yaml" NetworkPolicy redis-allow-business-services
require_text infrastructure/redis/deployment.yaml 'redis:7\.4\.9-alpine@sha256:[a-f0-9]{64}' \
  "Redis image is not versioned and digest-pinned"
require_text infrastructure/redis/deployment.yaml '^[[:space:]]+- ""$' \
  "Redis snapshot persistence is not explicitly disabled"
require_text infrastructure/redis/deployment.yaml 'appendonly' \
  "Redis append-only persistence is not explicitly disabled"
require_text infrastructure/redis/deployment.yaml 'emptyDir: \{\}' \
  "Redis data directory is not explicitly ephemeral"
require_text infrastructure/redis/deployment.yaml 'redis-cli' \
  "Redis protocol probes are missing"
require_text infrastructure/redis/README.md 'non-durable' \
  "Redis continuity risk is not documented"

if [[ "$(rg -c '^  validationFailureAction: Enforce$' \
    "$ROOT/infrastructure/kyverno/policies.yaml")" != "2" ]]; then
  fail "both Kyverno baseline policies must be in Enforce mode"
fi
require_text infrastructure/kyverno/policies.yaml 'background: true' \
  "Kyverno background reports are disabled"
require_text infrastructure/kyverno/policies.yaml 'admission: true' \
  "Kyverno admission default is not explicit"
require_text infrastructure/kyverno/policies.yaml 'emitWarning: false' \
  "Kyverno warning default is not explicit"
require_text infrastructure/kyverno/policies.yaml 'allowExistingViolations: true' \
  "Kyverno existing-violation default is not explicit"
require_text infrastructure/kyverno/kustomization.yaml 'strategy: None' \
  "Kyverno CRD conversion default is not explicit"
require_text infrastructure/kyverno/kustomization.yaml 'path: /metadata/labels' \
  "Kyverno empty CRD labels are not normalized"
require_text infrastructure/kyverno/policies.yaml 'microtodo-\*' \
  "Kyverno policies are not scoped to MicroTodoSuite namespaces"
require_text infrastructure/kyverno/policies.yaml '@sha256:' \
  "Kyverno immutable-image policy does not require a digest"
require_text infrastructure/kyverno/policies.yaml 'livenessProbe' \
  "Kyverno health policy does not require liveness probes"
require_text infrastructure/kyverno/policies.yaml 'readinessProbe' \
  "Kyverno health policy does not require readiness probes"

reject_text clusters/base/infrastructure.yaml 'directories:|infrastructure/\*' \
  "shared infrastructure still uses unsafe folder discovery"
require_text clusters/base/infrastructure.yaml 'elements: \[\]' \
  "shared infrastructure lacks an explicit empty activation default"
require_text clusters/base/infrastructure.yaml 'name: "infra-\{\{ \.name \}\}"' \
  "infrastructure Application naming is not driven by explicit values"
require_text clusters/base/infrastructure.yaml 'path: "\{\{ \.path \}\}"' \
  "infrastructure source path is not driven by explicit values"
require_text clusters/base/infrastructure.yaml 'namespace: "\{\{ \.namespace \}\}"' \
  "infrastructure namespace is not driven by explicit values"
if [[ "$(rg -c '^    - name: ' "$ROOT/clusters/local-kind/activation-infrastructure.yaml")" != "5" ]]; then
  fail "local infrastructure activation must contain exactly five entries"
fi
require_text clusters/base/infrastructure.yaml 'CreateNamespace=true' \
  "infrastructure applications do not create their destination namespace"
require_text clusters/base/infrastructure.yaml 'ServerSideApply=true' \
  "infrastructure applications do not use server-side apply"
require_text clusters/base/infrastructure.yaml 'prune: true' \
  "infrastructure applications do not prune"
require_text clusters/base/infrastructure.yaml 'selfHeal: true' \
  "infrastructure applications do not self-heal"
reject_text scripts/pilot/verify-platform.sh \
  'kubectl[^\n]*(apply|patch|scale|rollout|delete|create|replace)' \
  "platform verifier contains a direct managed-state mutation"
require_text scripts/pilot/lib/common.sh 'read-only kubectl only; refused verb' \
  "read-only kubectl wrapper does not reject mutating verbs"

require_text clusters/base/project.yaml 'group: apiregistration.k8s.io' \
  "APIService is missing from the exact cluster trust boundary"
require_text clusters/base/project.yaml 'kind: APIService' \
  "APIService kind is missing from the exact cluster trust boundary"
require_text clusters/base/project.yaml 'group: kyverno.io' \
  "Kyverno group is missing from the exact cluster trust boundary"
require_text clusters/base/project.yaml 'kind: ClusterPolicy' \
  "ClusterPolicy is missing from the exact cluster trust boundary"
reject_text clusters/base/project.yaml '^[[:space:]]+group:.*\*' \
  "cluster trust boundary contains a group wildcard"
reject_text clusters/base/project.yaml '^[[:space:]]+kind:.*\*' \
  "cluster trust boundary contains a kind wildcard"

for addon in keda cert-manager external-secrets kyverno redis; do
  first_party_files=("$ROOT/infrastructure/$addon/kustomization.yaml")
  [[ -f "$ROOT/infrastructure/$addon/capability-check.yaml" ]] \
    && first_party_files+=("$ROOT/infrastructure/$addon/capability-check.yaml")
  [[ -f "$ROOT/infrastructure/$addon/policies.yaml" ]] \
    && first_party_files+=("$ROOT/infrastructure/$addon/policies.yaml")
  if rg -n -i 'eks\.amazonaws|amazonaws\.com|azure\.com|azurecr\.io|workload\.identity|SecretStore|ClusterSecretStore|(^|[^[:alnum:]_])(aws|azure|eks|aks|ecr)([^[:alnum:]_]|$)' \
      "${first_party_files[@]}"; then
    fail "$addon first-party desired state contains a provider dependency"
  fi
done

require_text infrastructure/cert-manager/capability-check.yaml 'selfSigned: \{\}' \
  "cert-manager capability check is not provider-neutral"
reject_text infrastructure/cert-manager/capability-check.yaml \
  '^[[:space:]]+(acme|ca|vault|venafi):' \
  "cert-manager capability check uses a provider-backed issuer"

reject_text clusters/local-kind/activation-infrastructure.yaml \
  'argo-rollouts' "inactive Argo Rollouts placeholder is explicitly activated"
for registration in \
  clusters/local-kind/activation-infrastructure.yaml \
  clusters/eks-dev/activation-infrastructure.yaml \
  clusters/eks-dev/activation-infrastructure-retired.yaml; do
  reject_text "$registration" 'sonarqube' \
    "inactive SonarQube capability is explicitly activated"
done

render_kustomize "$ROOT/clusters/local-kind" >"$TMP_DIR/local-registration.yaml" \
  || fail "local cluster registration does not render"
require_resource "$TMP_DIR/local-registration.yaml" AppProject default
require_resource "$TMP_DIR/local-registration.yaml" AppProject microtodosuite
require_text clusters/base/project.yaml 'name: default' \
  "least-privilege bootstrap AppProject is missing"
require_text clusters/base/project.yaml 'description: MicroTodoSuite bootstrap root only' \
  "bootstrap AppProject is not explicitly restricted to the root"
require_text clusters/base/project.yaml 'namespace: kube-system' \
  "upstream add-on kube-system RBAC destination is missing"

for addon in keda cert-manager external-secrets kyverno redis; do
  require_text clusters/base/project.yaml "namespace: $addon" \
    "$addon destination is missing from the AppProject"
done

if [[ -f "$ROOT/infrastructure/argo-rollouts/kustomization.yaml" ]]; then
  fail "inactive Argo Rollouts placeholder became an infrastructure application"
fi

pass "platform add-on static contract"

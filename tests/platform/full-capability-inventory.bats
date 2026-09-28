#!/usr/bin/env bash
# Failing-first full-platform inventory contract (spec 009 T068, FR-023).
# This test is deliberately offline: it reads the lock, planned registrations,
# and Kustomize renders only. It does not require a cluster or cloud identity.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOCK="$ROOT/scripts/managed/full-profile-toolchain.lock"
KUSTOMIZE_BIN="${KUSTOMIZE_BIN:-kustomize}"

command -v "$KUSTOMIZE_BIN" >/dev/null || { printf 'FAIL: kustomize is required\n' >&2; exit 1; }
command -v jq >/dev/null || { printf 'FAIL: jq is required\n' >&2; exit 1; }

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "required file is missing: $1"
}

render() {
  "$KUSTOMIZE_BIN" build "$ROOT/$1"
}

planned_names() {
  awk '
    /^  plannedInfrastructure: \|$/ { in_inventory = 1; next }
    in_inventory && /^  [[:alnum:]][^:]*:/ { in_inventory = 0 }
    in_inventory && /^    - name: / { print $3 }
  ' "$1" | sort
}

planned_paths() {
  awk '
    /^  plannedInfrastructure: \|$/ { in_inventory = 1; next }
    in_inventory && /^  [[:alnum:]][^:]*:/ { in_inventory = 0 }
    in_inventory && /^      path: / { print $2 }
  ' "$1"
}

join_sorted() { printf '%s\n' "$@" | sort; }

# FR-023 plus the notification, audit, admission, ingress, and storage
# capabilities that make the FR verifiable. Alertmanager is rendered by the
# Prometheus root; PostgreSQL is rendered by the full-dev-only SonarQube root.
COMMON=(
  argocd-notifications argo-rollouts cert-manager chaos-mesh eck-operator
  elasticsearch external-secrets falco filebeat grafana istio jaeger keda kiali
  kibana kube-bench kube-hunter kyverno logstash opencost prometheus
  trivy-operator
)
EKS_ONLY=(aws-load-balancer-controller ebs-csi-driver karpenter)

for destination in eks-full-dev eks-full-staging eks-full-prod aks-dr; do
  inventory="$ROOT/clusters/$destination/planned-inventory.yaml"
  require_file "clusters/$destination/planned-inventory.yaml"
  [[ -f "$inventory" ]] || continue

  expected=("${COMMON[@]}")
  if [[ "$destination" == eks-* ]]; then
    expected+=("${EKS_ONLY[@]}")
  fi
  [[ "$destination" == eks-full-dev ]] && expected+=(sonarqube)

  actual="$(planned_names "$inventory")"
  wanted="$(join_sorted "${expected[@]}")"
  [[ "$actual" == "$wanted" ]] \
    || fail "$destination planned infrastructure must exactly match the FR-023/audit inventory"

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    require_file "$path/kustomization.yaml"
  done < <(planned_paths "$inventory")
done

# The exact version inventory is reviewed in research Decision 9. Keeping it in
# the lock makes a version change one deliberate, machine-readable edit.
declare -A EXPECTED_VERSION=(
  [argocd]=3.5.0
  [argo-rollouts]=1.9.1
  [aws-load-balancer-controller]=3.5.0
  [cert-manager]=1.21.0
  [external-secrets]=2.9.0
  [keda]=2.20.1
  [kyverno]=1.18.2
  [kube-prometheus]=0.18.0
  [istio]=1.30.3
  [kiali]=2.31.0
  [karpenter]=1.14.1
  [eck]=3.5.0
  [chaos-mesh]=2.8.4
  [opencost]=2.5.29
  [falco]=0.44.1
  [kube-bench]=0.16.0
  [kube-hunter]=0.6.8
  [grafana]=13.2.0
  [jaeger]=2.20.0
  [sonarqube]=26.8.0.126808-community
  [postgresql]=16.15-alpine3.24
  [trivy-operator]=0.34.0
)
for capability in "${!EXPECTED_VERSION[@]}"; do
  actual="$(jq -r --arg name "$capability" '.capabilities[] | select(.name == $name) | .version' "$LOCK")"
  [[ "$actual" == "${EXPECTED_VERSION[$capability]}" ]] \
    || fail "$capability must be locked at ${EXPECTED_VERSION[$capability]}, found: ${actual:-missing}"
done

# The lock is the complete source-to-mirror graph. Each row must be unique and
# immutable; a tag is metadata only and never the deployable identity.
image_count="$(jq '.images | length' "$LOCK")"
[[ "$image_count" -gt 0 ]] || fail "the platform image lock must not be empty"
[[ "$(jq '[.images[].id] | unique | length' "$LOCK")" == "$image_count" ]] \
  || fail "every locked platform image id must be unique"
[[ "$(jq '[.images[].mirrorTag] | unique | length' "$LOCK")" == "$image_count" ]] \
  || fail "every locked platform mirror tag must be unique"
jq -e 'all(.images[];
  (.id | type == "string" and length > 0) and
  (.upstreamRef | type == "string" and length > 0) and
  (.upstreamDigest | test("^sha256:[0-9a-f]{64}$")) and
  (.mirrorTag | type == "string" and length > 0))' "$LOCK" >/dev/null \
  || fail "every platform image must have an id, upstream ref, immutable digest, and mirror tag"
[[ "$(jq -r '.mirrorContract.ecrRepository' "$LOCK")" =~ /microtodosuite/platform$ ]] \
  || fail "the ECR mirror contract must name the single microtodosuite/platform repository"

# Every deployed third-party platform image must resolve to the reviewed lock
# digest and to the destination mirror, never directly to an upstream registry.
PLATFORM_ROOTS=(
  argo-rollouts aws-load-balancer-controller cert-manager chaos-mesh eck-operator
  elasticsearch external-secrets falco filebeat grafana istio jaeger karpenter
  keda kiali kibana kube-bench kube-hunter kyverno logstash opencost prometheus
  sonarqube trivy-operator
)
for component in "${PLATFORM_ROOTS[@]}"; do
  root="infrastructure/$component"
  require_file "$root/kustomization.yaml"
  [[ -f "$ROOT/$root/kustomization.yaml" ]] || continue
  if ! output="$(render "$root" 2>&1)"; then
    fail "$root must render: $output"
    continue
  fi
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    digest="${image##*@}"
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
      || { fail "$root renders a mutable image: $image"; continue; }
    jq -e --arg digest "$digest" 'any(.images[]; .upstreamDigest == $digest)' "$LOCK" >/dev/null \
      || fail "$root renders an image digest absent from the lock: $image"
    [[ "$image" =~ \.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/microtodosuite/platform@sha256:[0-9a-f]{64}$ ]] \
      || fail "$root must deploy its locked image from the ECR microtodosuite/platform mirror: $image"
  done < <(awk '$1 == "image:" && $2 != "" { gsub(/["'"'"']/, "", $2); print $2 }' <<<"$output" | sort -u)

  # One request and one limit each for CPU and memory per rendered image is the
  # minimum static resource budget. Capability-specific replica/storage limits
  # remain asserted below and in their focused tests.
  containers="$(awk '$1 == "image:" && $2 != "" { count++ } END { print count + 0 }' <<<"$output")"
  cpu="$(grep -cE '^ +cpu: ' <<<"$output" || true)"
  memory="$(grep -cE '^ +memory: ' <<<"$output" || true)"
  if (( containers > 0 )) && (( cpu < containers * 2 || memory < containers * 2 )); then
    fail "$root must request and limit CPU and memory for every rendered container ($containers images, $cpu cpu values, $memory memory values)"
  fi
done

# Stateful full roots select the encrypted cloud storage contract. EKS gp3 is
# declared encrypted by infrastructure/ebs-csi-driver; AKS uses encrypted
# Azure managed disks through managed-csi.
for destination in eks-full-dev eks-full-staging eks-full-prod; do
  for component in prometheus grafana elasticsearch; do
    path="infrastructure/profiles/full/$component/destinations/$destination"
    require_file "$path/kustomization.yaml"
    [[ -f "$ROOT/$path/kustomization.yaml" ]] || continue
    render "$path" | grep -q 'storageClassName: gp3' \
      || fail "$path must render retained gp3 storage"
  done
done
require_file infrastructure/profiles/full/sonarqube/destinations/eks-full-dev/kustomization.yaml
if [[ -f "$ROOT/infrastructure/profiles/full/sonarqube/destinations/eks-full-dev/kustomization.yaml" ]]; then
  render infrastructure/profiles/full/sonarqube/destinations/eks-full-dev | grep -q 'storageClassName: gp3' \
    || fail "full-dev SonarQube/PostgreSQL must render retained gp3 storage"
fi
for component in prometheus grafana elasticsearch; do
  path="infrastructure/profiles/full/$component/destinations/aks-dr"
  require_file "$path/kustomization.yaml"
  [[ -f "$ROOT/$path/kustomization.yaml" ]] || continue
  render "$path" | grep -q 'storageClassName: managed-csi' \
    || fail "$path must render retained Azure Disk storage through managed-csi"
done

# SonarQube/PostgreSQL is one shared full-dev tool, not one copy per cluster.
sonar_activations=0
for destination in eks-full-dev eks-full-staging eks-full-prod aks-dr; do
  inventory="$ROOT/clusters/$destination/planned-inventory.yaml"
  [[ -f "$inventory" ]] || continue
  count="$(planned_names "$inventory" | grep -cx sonarqube || true)"
  sonar_activations=$((sonar_activations + count))
  if [[ "$destination" != eks-full-dev && "$count" -ne 0 ]]; then
    fail "$destination must not activate the shared SonarQube/PostgreSQL tool"
  fi
done
[[ "$sonar_activations" -eq 1 ]] \
  || fail "exactly one full-dev SonarQube/PostgreSQL activation is required, found $sonar_activations"

# Karpenter is EKS-only and each of the three NodePools is independently capped
# at 8 vCPU (24 vCPU aggregate); AKS must not carry any Karpenter entry.
for destination in eks-full-dev eks-full-staging eks-full-prod; do
  path="infrastructure/profiles/full/karpenter/destinations/$destination"
  require_file "$path/kustomization.yaml"
  [[ -f "$ROOT/$path/kustomization.yaml" ]] || continue
  nodepools="$(render "$path" | grep -c '^kind: NodePool$' || true)"
  [[ "$nodepools" -eq 1 ]] || fail "$destination must render exactly one Karpenter NodePool"
  render "$path" | grep -qF '    cpu: "8"' \
    || fail "$destination Karpenter NodePool must cap Spot capacity at 8 vCPU"
done
if planned_names "$ROOT/clusters/aks-dr/planned-inventory.yaml" | grep -qx karpenter; then
  fail "AKS must not activate the AWS-only Karpenter capability"
fi

# Full-only platform capabilities must not leak into economical cluster roots.
for root in clusters/eks-dev/activation-infrastructure.yaml clusters/eks-dev-capacity-constrained/activation-infrastructure.yaml clusters/local-kind/activation-infrastructure.yaml; do
  [[ -f "$ROOT/$root" ]] || continue
  for capability in "${COMMON[@]}" "${EKS_ONLY[@]}" sonarqube; do
    if grep -qE "(^|[ /-])${capability}([ /:]|$)" "$ROOT/$root"; then
      fail "$root must not activate full-only capability $capability"
    fi
  done
done

if (( failures > 0 )); then
  printf 'FAIL: %d full-capability inventory violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: every full destination has the exact FR-023 inventory, versions, budgets, mirrored immutable images, encrypted storage, cloud-specific Karpenter scope, and one full-dev SonarQube activation.\n'

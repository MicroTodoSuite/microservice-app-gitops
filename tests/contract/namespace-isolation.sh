#!/usr/bin/env bash
# Static contract for feature 005 shared-cluster namespace isolation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*" >&2; }

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

require_render_text() {
  local render="$1" pattern="$2" description="$3"
  rg -q -- "$pattern" "$render" || fail "$description ($(basename "$render"))"
}

require_render_count() {
  local render="$1" pattern="$2" expected="$3" description="$4" actual
  actual="$(rg -c -- "$pattern" "$render" || true)"
  [[ "$actual" == "$expected" ]] ||
    fail "$description: expected $expected, found $actual ($(basename "$render"))"
}

check_rendered_images() {
  local render="$1" image_ref
  while IFS= read -r image_ref; do
    image_ref="${image_ref%\"}"
    image_ref="${image_ref#\"}"
    [[ "$image_ref" == *@sha256:* ]] ||
      fail "rendered image is mutable: $image_ref ($(basename "$render"))"
  done < <(sed -nE 's/^[[:space:]-]*image:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$render")
}

base_files=(
  environments/base/kustomization.yaml
  environments/base/limitrange.yaml
  environments/base/networkpolicy-default-deny.yaml
  environments/base/networkpolicy-allow-dns.yaml
  environments/base/networkpolicy-allow-intra-namespace.yaml
  environments/base/networkpolicy-allow-redis.yaml
  environments/base/redis-serviceaccount.yaml
  environments/base/redis-deployment.yaml
  environments/base/redis-service.yaml
  environments/base/role.yaml
  environments/base/external-secrets-serviceaccount.yaml
  environments/base/secretstore.yaml
  environments/base/external-secret.yaml
)
for file in "${base_files[@]}"; do
  require_file "$file"
done

require_text environments/base/networkpolicy-default-deny.yaml \
  'policyTypes:.*|Ingress|Egress' \
  "default deny does not declare ingress and egress isolation"
require_text environments/base/networkpolicy-allow-dns.yaml 'port: 53' \
  "DNS allowance does not target port 53"
require_text environments/base/networkpolicy-allow-dns.yaml \
  'kubernetes.io/metadata.name: kube-system' \
  "DNS allowance does not select kube-system"
require_text environments/base/networkpolicy-allow-intra-namespace.yaml \
  'podSelector: \{\}' \
  "same-namespace allowance is missing"
require_text environments/base/networkpolicy-allow-redis.yaml 'port: 6379' \
  "Redis allowance does not target port 6379"
for quantity in 'cpu: 25m' 'memory: 32Mi' 'cpu: 250m' 'memory: 256Mi' \
  'cpu: 500m' 'memory: 512Mi'; do
  require_text environments/base/limitrange.yaml "$quantity" \
    "LimitRange quantity drifted: $quantity"
done
require_text environments/base/redis-deployment.yaml \
  'redis:7\.4\.9-alpine@sha256:[a-f0-9]{64}' \
  "environment Redis image is not immutable"
require_text environments/base/redis-deployment.yaml \
  'automountServiceAccountToken: false' \
  "environment Redis mounts a Kubernetes API token"
reject_text environments/base/role.yaml \
  '(^|[[:space:]-])(\*|secrets|namespaces|resourcequotas|limitranges|networkpolicies|roles|rolebindings)([[:space:],]|$)' \
  "maintainer Role includes a wildcard, Secret, or isolation control"
require_text environments/base/role.yaml 'resources: \["deployments"\]' \
  "maintainer Role workload resources drifted"
require_text environments/base/role.yaml \
  'resources: \["configmaps", "services"\]' \
  "maintainer Role configuration resources drifted"
require_text environments/base/role.yaml 'resources: \["pods", "pods/log"\]' \
  "maintainer Role observation resources drifted"
if [[ "$(rg -c '^  - apiGroups:' "$ROOT/environments/base/role.yaml")" != 3 ]]; then
  fail "maintainer Role must contain exactly three reviewed rules"
fi
if rg -n 'microtodo-(dev|staging|prod)|ipBlock:|0\.0\.0\.0/0' \
    "$ROOT/environments/base"/networkpolicy-*.yaml; then
  fail "managed base contains a broad cross-environment or internet allowance"
fi

environments=(dev staging prod)
declare -A namespaces=(
  [dev]=microtodo-dev
  [staging]=microtodo-staging
  [prod]=microtodo-prod
)
declare -A cpu_requests=([dev]=550m [staging]=625m [prod]=700m)
declare -A cpu_limits=([dev]=2300m [staging]=2700m [prod]=3)
declare -A memory_requests=([dev]=896Mi [staging]=1Gi [prod]=1152Mi)
declare -A memory_limits=([dev]=2304Mi [staging]=2816Mi [prod]=3Gi)
declare -A pod_limits=([dev]=12 [staging]=14 [prod]=18)

for environment in "${environments[@]}"; do
  overlay="environments/$environment"
  for file in namespace.yaml resourcequota.yaml rolebinding.yaml kustomization.yaml; do
    require_file "$overlay/$file"
  done
  require_text "$overlay/kustomization.yaml" '../base' \
    "$environment does not reuse the managed environment base"
  require_text "$overlay/namespace.yaml" "name: ${namespaces[$environment]}" \
    "$environment namespace mapping drifted"
  require_text "$overlay/namespace.yaml" \
    "microtodosuite.io/environment: $environment" \
    "$environment namespace label drifted"
  require_text "$overlay/resourcequota.yaml" \
    "requests.cpu: \\\"?${cpu_requests[$environment]}\\\"?" \
    "$environment CPU request quota drifted"
  require_text "$overlay/resourcequota.yaml" \
    "limits.cpu: \\\"?${cpu_limits[$environment]}\\\"?" \
    "$environment CPU limit quota drifted"
  require_text "$overlay/resourcequota.yaml" \
    "requests.memory: \\\"?${memory_requests[$environment]}\\\"?" \
    "$environment memory request quota drifted"
  require_text "$overlay/resourcequota.yaml" \
    "limits.memory: \\\"?${memory_limits[$environment]}\\\"?" \
    "$environment memory limit quota drifted"
  require_text "$overlay/resourcequota.yaml" \
    "pods: \\\"?${pod_limits[$environment]}\\\"?" \
    "$environment pod quota drifted"
  require_text "$overlay/rolebinding.yaml" \
    "name: microtodosuite:${environment}-maintainers" \
    "$environment RoleBinding group drifted"
  reject_text "$overlay/rolebinding.yaml" \
    'system:authenticated|arn:aws:iam|kind: (User|ServiceAccount)' \
    "$environment RoleBinding has a broad or personal subject"

  render="$TMP_DIR/environment-$environment.yaml"
  render_kustomize "$ROOT/$overlay" >"$render" ||
    fail "$environment environment does not render"
  require_render_count "$render" '^kind: Namespace$' 1 \
    "$environment render must contain exactly one Namespace"
  require_render_count "$render" '^kind: ResourceQuota$' 1 \
    "$environment render must contain exactly one ResourceQuota"
  require_render_count "$render" '^kind: LimitRange$' 1 \
    "$environment render must contain exactly one LimitRange"
  require_render_count "$render" '^kind: Deployment$' 1 \
    "$environment render must contain exactly one Redis Deployment"
  require_render_count "$render" '^kind: Service$' 1 \
    "$environment render must contain exactly one Redis Service"
  require_render_count "$render" '^kind: SecretStore$' 1 \
    "$environment render must contain exactly one namespaced SecretStore"
  require_render_count "$render" '^kind: ExternalSecret$' 1 \
    "$environment render must contain exactly one ExternalSecret"
  require_render_text "$render" "namespace: ${namespaces[$environment]}" \
    "$environment resources are not namespace-scoped correctly"
  final_policy_count=4
  [[ "$environment" == dev ]] && final_policy_count=5
  require_render_count "$render" '^kind: NetworkPolicy$' "$final_policy_count" \
    "$environment steady state must contain default deny plus exact allowances"
  require_render_text "$render" 'name: default-deny' \
    "$environment steady state lacks ingress-and-egress default deny"
  require_render_text "$render" 'name: redis' \
    "$environment render lacks namespace-local Redis"
  require_render_text "$render" 'name: external-secrets-jwt' \
    "$environment render lacks its exact JWT synchronization ServiceAccount"
  require_render_text "$render" \
    "eks.amazonaws.com/role-arn: arn:aws:iam::995253610162:role/microtodosuite-${environment}-jwt-reader" \
    "$environment JWT ServiceAccount role mapping drifted"
  require_render_text "$render" \
    "key: microtodosuite/$environment/auth-api-secrets" \
    "$environment ExternalSecret reads the wrong source secret"
  check_rendered_images "$render"

  foundation_render="$TMP_DIR/environment-$environment-foundation.yaml"
  render_kustomize "$ROOT/tests/fixtures/namespace-isolation/foundation/$environment" \
    >"$foundation_render" || fail "$environment foundation fixture does not render"
  foundation_policy_count=3
  [[ "$environment" == dev ]] && foundation_policy_count=4
  require_render_count "$foundation_render" '^kind: NetworkPolicy$' \
    "$foundation_policy_count" \
    "$environment foundation must retain only its exact allow policies"
  if rg -q 'name: default-deny' "$foundation_render"; then
    fail "$environment foundation fixture activates default deny"
  fi
  require_render_count "$foundation_render" '^kind: Deployment$' 1 \
    "$environment foundation must retain its Redis Deployment"
done

reject_text environments 'kind: ClusterSecretStore' \
  "managed environments use a cluster-wide secret store"
require_text environments/base/secretstore.yaml 'serviceAccountRef:' \
  "namespaced SecretStore does not use ServiceAccount JWT authentication"
require_text environments/base/external-secret.yaml 'secretStoreRef:' \
  "ExternalSecret does not reference its namespaced SecretStore"
require_text environments/base/external-secret.yaml 'creationPolicy: Owner' \
  "ExternalSecret does not own its destination Secret"
require_text environments/base/external-secret.yaml 'secretKey: JWT_SECRET' \
  "ExternalSecret does not materialize the JWT_SECRET key"

# The approved production bound must fit steady workloads, the largest
# serialized service surge, and one bounded analysis Job.
prod_steady_cpu_requests=475
prod_steady_cpu_limits=2200
prod_steady_memory_requests=672
prod_steady_memory_limits=2176
largest_surge_cpu_requests=150
largest_surge_cpu_limits=500
largest_surge_memory_requests=256
largest_surge_memory_limits=512
analysis_cpu_requests=10
analysis_cpu_limits=50
analysis_memory_requests=16
analysis_memory_limits=32
(( prod_steady_cpu_requests + largest_surge_cpu_requests + analysis_cpu_requests <= 700 )) ||
  fail "production CPU-request quota cannot fit steady state plus one surge and analysis"
(( prod_steady_cpu_limits + largest_surge_cpu_limits + analysis_cpu_limits <= 3000 )) ||
  fail "production CPU-limit quota cannot fit steady state plus one surge and analysis"
(( prod_steady_memory_requests + largest_surge_memory_requests + analysis_memory_requests <= 1152 )) ||
  fail "production memory-request quota cannot fit steady state plus one surge and analysis"
(( prod_steady_memory_limits + largest_surge_memory_limits + analysis_memory_limits <= 3072 )) ||
  fail "production memory-limit quota cannot fit steady state plus one surge and analysis"

if [[ "$(rg --no-filename 'name: microtodosuite:(dev|staging|prod)-maintainers' \
    "$ROOT/environments"/{dev,staging,prod}/rolebinding.yaml | sort -u | wc -l)" != 3 ]]; then
  fail "environment RoleBindings do not contain exactly three distinct groups"
fi
for subject_environment in "${environments[@]}"; do
  for target_environment in "${environments[@]}"; do
    binding="environments/$target_environment/rolebinding.yaml"
    if [[ "$subject_environment" == "$target_environment" ]]; then
      require_text "$binding" \
        "name: microtodosuite:${subject_environment}-maintainers" \
        "$subject_environment maintainers are not bound in their own namespace"
    else
      reject_text "$binding" \
        "name: microtodosuite:${subject_environment}-maintainers" \
        "$subject_environment maintainers are bound into $target_environment"
    fi
  done
done
for environment in "${environments[@]}"; do
  require_text "environments/$environment/rolebinding.yaml" \
    'name: environment-workload-maintainer' \
    "$environment RoleBinding does not reference the bounded workload Role"
done
if rg -n '^kind: (ClusterRole|ClusterRoleBinding)$' \
    "$ROOT/environments"/{base,dev,staging,prod}; then
  fail "managed environment access escaped the namespace boundary"
fi

require_file clusters/local-kind/activation-infrastructure.yaml
require_file clusters/eks-dev/activation-infrastructure.yaml
require_file clusters/eks-dev/activation-infrastructure-retired.yaml
if [[ "$(rg -c '^    - env: (dev|staging|prod)$' \
    "$ROOT/clusters/eks-dev/activation-apps.yaml" || true)" != 3 ]]; then
  fail "managed business activation must list exactly dev, staging, and prod"
fi
if [[ "$(rg -c '^      server: https://kubernetes.default.svc$' \
    "$ROOT/clusters/eks-dev/activation-apps.yaml" || true)" != 3 ]]; then
  fail "every managed business activation must target the in-cluster API server"
fi
reject_text clusters/eks-dev/activation-apps.yaml \
  'env: local|env: production' \
  "managed business activation contains an unsupported environment"
if [[ "$(rg -c '^    - env:' \
    "$ROOT/clusters/eks-dev/activation-environments.yaml" || true)" != 3 ]]; then
  fail "managed environment activation contains an extra or missing element"
fi
if [[ "$(rg -c '^    - env: (dev|staging|prod)$' \
    "$ROOT/clusters/eks-dev/activation-environments.yaml" || true)" != 3 ]]; then
  fail "managed environment activation must list exactly dev, staging, and prod"
fi
if [[ "$(rg -c '^      server: https://kubernetes.default.svc$' \
    "$ROOT/clusters/eks-dev/activation-environments.yaml" || true)" != 3 ]]; then
  fail "every managed environment must target the in-cluster API server"
fi
reject_text clusters/eks-dev/activation-environments.yaml \
  'env: production|env: local' \
  "managed environment activation contains an unsupported environment"
require_text environments/base/kustomization.yaml \
  'networkpolicy-default-deny.yaml' \
  "steady-state environment root does not activate default deny"
if rg -n 'tests/fixtures/namespace-isolation' \
    "$ROOT/environments"/{base,dev,staging,prod}; then
  fail "verification fixtures are activated by steady-state environment desired state"
fi
reject_text clusters/base/infrastructure.yaml 'directories:|infrastructure/\*' \
  "infrastructure ApplicationSet still uses folder discovery"
require_text clusters/base/infrastructure.yaml 'elements: \[\]' \
  "infrastructure ApplicationSet lacks an empty explicit list default"
for name in keda cert-manager external-secrets kyverno redis; do
  require_text clusters/local-kind/activation-infrastructure.yaml \
    "name: $name" "local infrastructure list omits $name"
done
for name in keda cert-manager external-secrets kyverno argo-rollouts; do
  require_text clusters/eks-dev/activation-infrastructure.yaml \
    "name: $name" "managed final infrastructure list omits $name"
  require_text clusters/eks-dev/activation-infrastructure-retired.yaml \
    "name: $name" "post-retirement infrastructure list omits $name"
done
reject_text clusters/eks-dev/activation-infrastructure.yaml \
  'name: redis' "managed final infrastructure list retains shared Redis"
reject_text clusters/eks-dev/activation-infrastructure-retired.yaml \
  'name: redis' "post-retirement infrastructure list retains shared Redis"

for service in todos-api log-message-processor; do
  for environment in "${environments[@]}"; do
    overlay="apps/$service/overlays/$environment/kustomization.yaml"
    require_text "$overlay" 'REDIS_HOST' \
      "$service $environment overlay lacks a Redis endpoint override"
    require_text "$overlay" 'REDIS_HOST: redis' \
      "$service $environment overlay does not use namespace-local Redis"
    managed_render="$TMP_DIR/$service-$environment.yaml"
    render_kustomize "$ROOT/apps/$service/overlays/$environment" >"$managed_render"
    require_render_text "$managed_render" '^  REDIS_HOST: redis$' \
      "$service $environment render does not use namespace-local Redis"
    require_render_text "$managed_render" \
      'runtime-config.microtodosuite.io/revision: namespace-local-redis-v1' \
      "$service $environment render does not roll pods for its managed Redis endpoint"
    if rg -q 'REDIS_HOST: redis\.redis\.svc\.cluster\.local' "$managed_render"; then
      fail "$service $environment render retains the retired shared Redis endpoint"
    fi
  done
  local_render="$TMP_DIR/$service-local.yaml"
  render_kustomize "$ROOT/apps/$service/overlays/local" >"$local_render"
  require_render_text "$local_render" \
    'REDIS_HOST: redis.redis.svc.cluster.local' \
    "$service local Redis endpoint changed"
done

if ! git -C "$ROOT" diff --quiet HEAD -- environments/local; then
  fail "environments/local changed in managed namespace feature"
fi

for file in \
  scripts/managed/verify-namespace-isolation.sh \
  scripts/managed/lib/namespace-isolation.sh \
  scripts/managed/validate-namespace-isolation.sh \
  tests/contract/namespace-isolation-evidence.sh \
  docs/namespace-isolation.md \
  tests/fixtures/namespace-isolation/base/kustomization.yaml \
  tests/fixtures/namespace-isolation/overlays/dev/kustomization.yaml \
  tests/fixtures/namespace-isolation/overlays/staging/kustomization.yaml \
  tests/fixtures/namespace-isolation/overlays/prod/kustomization.yaml \
  tests/fixtures/namespace-isolation/quota-violation/kustomization.yaml; do
  require_file "$file"
done
require_text scripts/managed/verify-namespace-isolation.sh \
  '--expected-cluster-id' "observer does not bind evidence to an exact cluster identity"

if rg -n \
    'kubectl[^#\n]*(apply|create|patch|replace|scale|rollout|delete)|argocd[^#\n]*(sync|app set|app delete)' \
    "$ROOT/scripts/managed" | rg -v 'auth can-i'; then
  fail "managed observer contains a direct mutation command"
fi
require_text tests/fixtures/namespace-isolation/quota-violation/deployment.yaml \
  'cpu: 600m' "quota fixture does not exceed the 500m container maximum"
require_text tests/fixtures/namespace-isolation/quota-violation/deployment.yaml \
  'comparison-environment: microtodo-staging' \
  "quota fixture does not name a comparison outside microtodo-dev"
require_text tests/fixtures/namespace-isolation/quota-violation/deployment.yaml \
  'cpu: 25m' "quota fixture request does not remain within the approved minimum/default range"
if [[ "$(rg -c 'memory: (32|64)Mi' \
    "$ROOT/tests/fixtures/namespace-isolation/quota-violation/deployment.yaml")" != 2 ]]; then
  fail "quota fixture must keep both memory quantities within the 512Mi maximum"
fi
reject_text tests/fixtures/namespace-isolation/quota-violation/deployment.yaml \
  'memory: (513Mi|[1-9][0-9]*Gi)' \
  "quota fixture violates an unintended memory bound"

for fixture in \
  tests/fixtures/namespace-isolation/overlays/dev \
  tests/fixtures/namespace-isolation/overlays/staging \
  tests/fixtures/namespace-isolation/overlays/prod \
  tests/fixtures/namespace-isolation/quota-violation; do
  render="$TMP_DIR/$(basename "$fixture")-fixture.yaml"
  render_kustomize "$ROOT/$fixture" >"$render" || fail "$fixture does not render"
  require_render_text "$render" '@sha256:[a-f0-9]{64}' \
    "$fixture contains a mutable image"
  check_rendered_images "$render"
  require_render_text "$render" 'livenessProbe:' \
    "$fixture lacks the enforced liveness-probe contract"
  require_render_text "$render" 'readinessProbe:' \
    "$fixture lacks the enforced readiness-probe contract"
done

jq empty \
  "$ROOT/specs/005-namespace-isolation/contracts/namespace-isolation-evidence.schema.json" ||
  fail "evidence schema is not valid JSON"

pass "shared-cluster namespace isolation static contract"

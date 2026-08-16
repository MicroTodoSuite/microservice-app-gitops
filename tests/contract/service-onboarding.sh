#!/usr/bin/env bash
# Static contract for the four services added by feature 004.
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

services=(todos-api users-api frontend log-message-processor)
declare -A ports=(
  [todos-api]=8082
  [users-api]=8083
  [frontend]=8080
  [log-message-processor]=9090
)
declare -A health_paths=(
  [todos-api]='/metrics'
  [users-api]='/prometheus'
  [frontend]='/'
  [log-message-processor]='/metrics'
)

for service in "${services[@]}"; do
  for file in \
    "apps/$service/base/kustomization.yaml" \
    "apps/$service/base/deployment.yaml" \
    "apps/$service/base/service.yaml" \
    "apps/$service/base/serviceaccount.yaml" \
    "apps/$service/base/configmap.yaml" \
    "apps/$service/components/topology-economical/kustomization.yaml" \
    "apps/$service/components/topology-full/kustomization.yaml" \
    "apps/$service/topology/kustomization.yaml"; do
    require_file "$file"
  done

  require_text "apps/$service/base/serviceaccount.yaml" \
    'automountServiceAccountToken: false' \
    "$service ServiceAccount mounts a Kubernetes API token"
  require_text "apps/$service/base/deployment.yaml" \
    "containerPort: ${ports[$service]}" \
    "$service container port is wrong"
  for probe in startupProbe readinessProbe livenessProbe; do
    require_text "apps/$service/base/deployment.yaml" "$probe:" \
      "$service is missing $probe"
  done
  require_text "apps/$service/base/deployment.yaml" \
    "path: ${health_paths[$service]}" \
    "$service intrinsic health path is wrong"
  require_text "apps/$service/base/service.yaml" 'type: ClusterIP' \
    "$service is not exposed by ClusterIP"
  reject_text "apps/$service/base/service.yaml" 'NodePort|nodePort:' \
    "$service contains a NodePort"

  for environment in local dev staging prod; do
    overlay="apps/$service/overlays/$environment"
    require_file "$overlay/kustomization.yaml"
    render="$TMP_DIR/$service-$environment.yaml"
    render_kustomize "$ROOT/$overlay" >"$render" \
      || fail "$service $environment overlay does not render"
    [[ -s "$render" ]] || fail "$service $environment rendered no resources"
    require_render_text "$render" \
      "image: .*${service}@sha256:[a-f0-9]{64}" \
      "$service $environment image is not digest-selected"
    require_render_text "$render" \
      'app.kubernetes.io/part-of: microtodosuite' \
      "$service $environment is missing the suite label"
    require_render_text "$render" \
      'app.kubernetes.io/component: business-service' \
      "$service $environment is missing the component label"
  done
done

for service in todos-api users-api; do
  require_text "apps/$service/base/deployment.yaml" 'name: auth-api-secrets' \
    "$service does not reuse the auth-api JWT Secret"
  require_text "apps/$service/base/deployment.yaml" 'key: JWT_SECRET' \
    "$service JWT Secret key is wrong"
done

require_text apps/users-api/overlays/local/kustomization.yaml \
  'name: users-api[[:space:]]*$' \
  "users-api local replica mapping is missing"
require_text apps/users-api/overlays/local/kustomization.yaml 'count: 1' \
  "users-api local replica count is not one"
reject_text apps/users-api/base/deployment.yaml \
  'persistentVolumeClaim|volumeClaimTemplates' \
  "users-api silently adds persistence"
require_text apps/users-api/base/deployment.yaml \
  'data-continuity.microtodosuite.io/risk: pod-local-h2' \
  "users-api H2 risk is not surfaced"
require_text apps/users-api/base/configmap.yaml 'JAVA_TOOL_OPTIONS:' \
  "users-api legacy JVM is not explicitly bounded"
require_text apps/users-api/base/configmap.yaml '-Xmx256m' \
  "users-api heap bound is missing"
require_text apps/users-api/base/deployment.yaml \
  'runtime-config.microtodosuite.io/revision: users-api-jvm-bounds-v1' \
  "users-api ConfigMap rollout marker is missing"

for service in todos-api log-message-processor; do
  require_text "apps/$service/base/configmap.yaml" \
    'REDIS_HOST: "redis.redis.svc.cluster.local"' \
    "$service Redis endpoint differs from the platform contract"
  require_text "apps/$service/base/configmap.yaml" \
    'REDIS_PORT: "6379"' \
    "$service Redis port differs from the platform contract"
  require_text "apps/$service/base/configmap.yaml" \
    'REDIS_CHANNEL: "log_channel"' \
    "$service Redis channel differs from the platform contract"
done
require_text apps/todos-api/base/deployment.yaml \
  'data-continuity.microtodosuite.io/risk: process-local-todos' \
  "todos-api in-memory risk is not surfaced"

require_text apps/frontend/base/configmap.yaml \
  'AUTH_API_ADDRESS: "http://auth-api:8000"' \
  "frontend auth proxy address is wrong"
require_text apps/frontend/base/configmap.yaml \
  'TODOS_API_ADDRESS: "http://todos-api:8082"' \
  "frontend todos proxy address is wrong"
if rg -n '^kind: (Ingress|Gateway|HTTPRoute)$|type: NodePort|nodePort:' \
    "$ROOT/apps/frontend"; then
  fail "frontend invents a local exposure mechanism"
fi

require_text environments/local/kustomization.yaml 'namespace.yaml' \
  "local environment Namespace label is not registered"
require_text environments/local/kustomization.yaml 'networkpolicy-allow-redis.yaml' \
  "Redis egress policy is not registered"
require_text environments/local/networkpolicy-allow-redis.yaml '^[[:space:]]+- todos-api$' \
  "todos-api is not selected by Redis egress policy"
require_text environments/local/networkpolicy-allow-redis.yaml '^[[:space:]]+- log-message-processor$' \
  "log-message-processor is not selected by Redis egress policy"

require_text scripts/pilot/publish-services.sh 'assert_pilot_remote_safe' \
  "suite publisher does not enforce local-only push safety"
require_text scripts/pilot/publish-services.sh 'infra-redis' \
  "suite publisher lacks the Redis-first gate"
require_text scripts/pilot/publish-services.sh \
  '--exclude=clusters/local-kind/registration.yaml' \
  "suite publisher overwrites the machine-specific cluster registration"
require_text scripts/pilot/publish-services.sh \
  '--exclude=clusters/local-kind/root-app.yaml' \
  "suite publisher overwrites the machine-specific root endpoint"
require_text scripts/pilot/verify-services.sh 'expectedRevision' \
  "suite verifier lacks machine-readable revision evidence"
reject_text scripts/pilot/verify-services.sh \
  'kubectl[^\n]*(apply|patch|scale|rollout|delete|create|replace)' \
  "suite verifier contains a direct managed-state mutation"

new_desired_state=(
  "$ROOT/apps/todos-api"
  "$ROOT/apps/users-api"
  "$ROOT/apps/frontend"
  "$ROOT/apps/log-message-processor"
  "$ROOT/infrastructure/redis"
  "$ROOT/environments/local/namespace.yaml"
  "$ROOT/environments/local/networkpolicy-allow-redis.yaml"
  "$ROOT/scripts/pilot/publish-services.sh"
  "$ROOT/scripts/pilot/verify-services.sh"
)
if rg -n -i \
    'amazonaws|azure|azurecr|workload\.identity|(^|[^[:alnum:]_])(aws|eks|aks|ecr)([^[:alnum:]_]|$)' \
    "${new_desired_state[@]}"; then
  fail "new service foundation contains a cloud-provider dependency"
fi

# Shared-EKS delivery must be progressive, while the reusable/local registration
# stays free of an EKS-only ordering policy.
require_file bootstrap/argocd/kustomization.yaml
require_file clusters/eks-dev/rolling-sync-apps.yaml
require_text bootstrap/argocd/kustomization.yaml \
  'applicationsetcontroller\.enable\.progressive\.syncs: "true"' \
  "Argo CD progressive syncs are not enabled declaratively"
require_text bootstrap/argocd/kustomization.yaml \
  'microtodosuite\.io/progressive-syncs-revision:' \
  "ApplicationSet controller lacks a pod-template restart trigger"
require_text clusters/base/apps.yaml \
  'microtodosuite\.io/environment: "\{\{ \.env \}\}"' \
  "generated business Applications lack the environment label"
require_text clusters/eks-dev/kustomization.yaml 'rolling-sync-apps.yaml' \
  "shared EKS registration does not apply its RollingSync policy"
require_text clusters/eks-dev/rolling-sync-apps.yaml 'type: RollingSync' \
  "shared EKS registration is not configured for RollingSync"
if [[ "$(rg -c 'maxUpdate: 1' "$ROOT/clusters/eks-dev/rolling-sync-apps.yaml" || true)" != 3 ]]; then
  fail "RollingSync must serialize every environment step with maxUpdate 1"
fi
for environment in dev staging prod; do
  require_text clusters/eks-dev/rolling-sync-apps.yaml \
    "values: \\[\"$environment\"\\]" \
    "RollingSync omits or mislabels the $environment step"
done
require_text clusters/eks-dev/rolling-sync-apps.yaml \
  'path: /spec/template/spec/syncPolicy/automated' \
  "EKS RollingSync patch does not remove generated Application autosync"
require_text clusters/eks-dev/activation-apps.yaml 'value: \[\]' \
  "business activation must remain empty until all prerequisites pass"

# Every production overlay must select the economical topology and opt into a
# replica-based, metric-gated Rollout without duplicating its pod template.
managed_services=(auth-api todos-api users-api frontend log-message-processor)
for service in "${managed_services[@]}"; do
  component="apps/$service/components/strategy-canary"
  require_file "$component/kustomization.yaml"
  require_file "$component/rollout.yaml"
  require_file "$component/canary-service.yaml"
  require_text "apps/$service/topology/kustomization.yaml" \
    '../components/topology-economical' \
    "$service managed topology is not economical"
  reject_text "apps/$service/topology/kustomization.yaml" \
    'components/topology-full' \
    "$service managed topology still selects the full profile"
  require_text "apps/$service/overlays/prod/kustomization.yaml" \
    '../../components/strategy-canary' \
    "$service production overlay does not activate its Rollout component"
  require_text "$component/rollout.yaml" 'workloadRef:' \
    "$service Rollout does not reuse the base Deployment"
  require_text "$component/rollout.yaml" "canaryService: $service-canary" \
    "$service Rollout lacks its dedicated canary Service"
  require_text "$component/rollout.yaml" 'maxSurge: 1' \
    "$service Rollout surge is not bounded"
  require_text "$component/rollout.yaml" 'maxUnavailable: 0' \
    "$service Rollout permits avoidable unavailability"
  require_text "$component/rollout.yaml" 'setWeight: 50' \
    "$service Rollout cannot realize a live replica canary"
  require_text "$component/rollout.yaml" 'setWeight: 100' \
    "$service Rollout lacks its promotion step"
  require_text "$component/rollout.yaml" \
    'templateName: microtodosuite-canary-health' \
    "$service Rollout does not use the shared metric gate"
  require_text "$component/rollout.yaml" 'clusterScope: true' \
    "$service Rollout does not reference the cluster-scoped metric gate"

  prod_render="$TMP_DIR/$service-prod-rollout.yaml"
  render_kustomize "$ROOT/apps/$service/overlays/prod" >"$prod_render" ||
    fail "$service production Rollout overlay does not render"
  require_render_count "$prod_render" '^kind: Rollout$' 1 \
    "$service production render must contain one Rollout"
  require_render_text "$prod_render" "name: $service-canary" \
    "$service production render lacks its canary Service"
done

pass "remaining service onboarding static contract"

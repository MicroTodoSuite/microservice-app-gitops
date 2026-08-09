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

pass "remaining service onboarding static contract"

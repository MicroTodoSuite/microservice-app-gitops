#!/usr/bin/env bash
# Prove four add-ons and auth-api succeeded through the local GitOps path.
# This script is read-only: it uses get/wait/logs/port-forward and HTTP probes,
# retaining raw evidence under the ignored .local/ runtime directory.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

ADDON_APPLICATIONS=(
  infra-keda
  infra-cert-manager
  infra-external-secrets
  infra-kyverno
)

EXPECTED_DEPLOYMENTS=(
  keda/keda-admission
  keda/keda-metrics-apiserver
  keda/keda-operator
  keda/platform-autoscaling-check
  cert-manager/cert-manager
  cert-manager/cert-manager-cainjector
  cert-manager/cert-manager-webhook
  external-secrets/external-secrets
  external-secrets/external-secrets-cert-controller
  external-secrets/external-secrets-webhook
  kyverno/kyverno-admission-controller
  kyverno/kyverno-background-controller
  kyverno/kyverno-cleanup-controller
  kyverno/kyverno-reports-controller
  microtodo-local/auth-api
)

POLICIES=(
  require-immutable-images
  require-health-probes
)

for tool in git jq curl; do
  require_tool "$tool"
done

[[ -d "$BARE_REPO" ]] || die "pilot bare Git source not found: $BARE_REPO"
EXPECTED_SHA="$(git -C "$BARE_REPO" rev-parse main)"
[[ "$EXPECTED_SHA" =~ ^[a-f0-9]{40}$ ]] \
  || die "could not resolve the pilot main revision"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="$LOCAL_DIR/evidence/platform-addons/$RUN_ID"
mkdir -p "$EVIDENCE_DIR/applications" "$EVIDENCE_DIR/deployments" \
  "$EVIDENCE_DIR/capabilities" "$EVIDENCE_DIR/health"

PF_PID=""
cleanup_port_forward() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup_port_forward EXIT

wait_for_application() {
  local application="$1" deadline sync health revision
  deadline=$(( $(date +%s) + 600 ))
  while :; do
    sync="$(kro get application "$application" -n argocd \
      -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health="$(kro get application "$application" -n argocd \
      -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    revision="$(kro get application "$application" -n argocd \
      -o jsonpath='{.status.sync.revision}' 2>/dev/null || true)"
    if [[ "$sync" == Synced && "$health" == Healthy \
      && "$revision" == "$EXPECTED_SHA" ]]; then
      break
    fi
    if (( $(date +%s) > deadline )); then
      die "timed out waiting for $application (sync=$sync health=$health revision=${revision:0:12})"
    fi
    sleep 5
  done
  kro get application "$application" -n argocd -o json \
    >"$EVIDENCE_DIR/applications/$application.json"
  ok "$application is Synced+Healthy at ${EXPECTED_SHA:0:12}"
}

wait_for_deployment() {
  local entry="$1" namespace deployment desired available
  namespace="${entry%%/*}"
  deployment="${entry#*/}"
  kro wait deployment/"$deployment" -n "$namespace" \
    --for=condition=Available --timeout=300s >&2
  kro get deployment "$deployment" -n "$namespace" -o json \
    >"$EVIDENCE_DIR/deployments/${namespace}--${deployment}.json"
  desired="$(jq -r '.spec.replicas // 1' \
    "$EVIDENCE_DIR/deployments/${namespace}--${deployment}.json")"
  available="$(jq -r '.status.availableReplicas // 0' \
    "$EVIDENCE_DIR/deployments/${namespace}--${deployment}.json")"
  [[ "$desired" == "$available" ]] \
    || die "$namespace/$deployment has $available/$desired available replicas"
}

condition_is_true() {
  local file="$1" condition_type="$2"
  jq -e --arg condition_type "$condition_type" '
    any(.status.conditions[]?;
      .type == $condition_type and (.status | ascii_downcase) == "true")
  ' "$file" >/dev/null
}

wait_for_capability() {
  local kind="$1" name="$2" namespace="$3" condition_type="$4" output="$5"
  local deadline
  deadline=$(( $(date +%s) + 300 ))
  while :; do
    if kro get "$kind" "$name" -n "$namespace" -o json >"$output" 2>/dev/null \
      && condition_is_true "$output" "$condition_type"; then
      break
    fi
    if (( $(date +%s) > deadline )); then
      die "$kind/$namespace/$name did not report $condition_type=True"
    fi
    sleep 5
  done
}

log "expected local desired-state revision: $EXPECTED_SHA"
for application in "${ADDON_APPLICATIONS[@]}" auth-api-local; do
  wait_for_application "$application"
done

log "waiting for every expected controller and auth-api Deployment"
for entry in "${EXPECTED_DEPLOYMENTS[@]}"; do
  wait_for_deployment "$entry"
done
ok "all expected Deployments are Available"

wait_for_capability scaledobject platform-autoscaling-check keda Ready \
  "$EVIDENCE_DIR/capabilities/keda-scaledobject.json"
ok "KEDA ScaledObject is Ready"

wait_for_capability certificate platform-certificate-check cert-manager Ready \
  "$EVIDENCE_DIR/capabilities/cert-manager-certificate.json"
kro get secret platform-certificate-check-tls -n cert-manager -o jsonpath='{.metadata.name}' \
  >"$EVIDENCE_DIR/capabilities/cert-manager-secret-name.txt"
ok "cert-manager Certificate is Ready and produced its Secret"

wait_for_capability externalsecret auth-api-secrets microtodo-local Ready \
  "$EVIDENCE_DIR/capabilities/external-secret.json"
ESO_REASON="$(jq -r '.status.conditions[]? | select(.type == "Ready") | .reason' \
  "$EVIDENCE_DIR/capabilities/external-secret.json")"
[[ "$ESO_REASON" == SecretSynced ]] \
  || die "ExternalSecret Ready reason is $ESO_REASON, expected SecretSynced"
ok "External Secrets Operator synchronized auth-api-secrets"

for policy in "${POLICIES[@]}"; do
  policy_file="$EVIDENCE_DIR/capabilities/kyverno-$policy.json"
  deadline=$(( $(date +%s) + 300 ))
  while :; do
    if kro get clusterpolicy "$policy" -o json >"$policy_file" 2>/dev/null \
      && condition_is_true "$policy_file" Ready; then
      break
    fi
    if (( $(date +%s) > deadline )); then
      die "ClusterPolicy/$policy did not report Ready=True"
    fi
    sleep 5
  done
done
ok "Kyverno policies are Ready"

AUTH_POD="$(kro get pods -n microtodo-local \
  -l app.kubernetes.io/name=auth-api \
  -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$AUTH_POD" ]] || die "auth-api pod not found"
AUTH_POLICY_MARKER="$(kro get pod "$AUTH_POD" -n microtodo-local \
  -o jsonpath='{.metadata.annotations.policy\.microtodosuite\.io/baseline}' 2>/dev/null || true)"
[[ "$AUTH_POLICY_MARKER" == kyverno-v1 ]] \
  || die "auth-api pod was not rolled out with the Kyverno baseline marker"

REPORT_FILE="$EVIDENCE_DIR/capabilities/kyverno-policy-reports.json"
deadline=$(( $(date +%s) + 300 ))
while :; do
  kro get policyreport -n microtodo-local -o json >"$REPORT_FILE" 2>/dev/null || true
  reports_ready=true
  for policy in "${POLICIES[@]}"; do
    pass_count="$(jq -r --arg pod "$AUTH_POD" --arg policy "$policy" '
      [ .items[]?
        | select(.scope.kind == "Pod" and .scope.name == $pod)
        | .results[]?
        | select(.policy == $policy and .result == "pass") ]
      | length
    ' "$REPORT_FILE" 2>/dev/null || printf '0')"
    problem_count="$(jq -r --arg pod "$AUTH_POD" --arg policy "$policy" '
      [ .items[]?
        | select(.scope.kind == "Pod" and .scope.name == $pod)
        | .results[]?
        | select(.policy == $policy and
          (.result == "fail" or .result == "error")) ]
      | length
    ' "$REPORT_FILE" 2>/dev/null || printf '1')"
    if (( pass_count < 1 || problem_count > 0 )); then
      reports_ready=false
    fi
  done
  if [[ "$reports_ready" == true ]]; then
    break
  fi
  if (( $(date +%s) > deadline )); then
    die "Kyverno reports did not record passing auth-api results"
  fi
  sleep 5
done
ok "Kyverno reports pass for the newly admitted auth-api pod"

for namespace in keda cert-manager external-secrets kyverno microtodo-local; do
  kro get pods -n "$namespace" -o json >"$EVIDENCE_DIR/${namespace}-pods.json"
  if jq -e '
    any(.items[]?;
      (.status.phase == "Failed" or .status.phase == "Unknown" or
       .status.phase == "Pending") or
      any(.status.containerStatuses[]?.state.waiting.reason?;
        . == "CrashLoopBackOff" or . == "ImagePullBackOff" or
        . == "ErrImagePull" or . == "CreateContainerError"))
  ' "$EVIDENCE_DIR/${namespace}-pods.json" >/dev/null; then
    die "unhealthy pod state found in namespace $namespace"
  fi
done
ok "no final Pending, Failed, Unknown, crash-looping, or image-pull pod state"

log "starting read-only auth-api port-forward on :$PILOT_HEALTH_PORT"
kro port-forward -n microtodo-local svc/auth-api \
  "$PILOT_HEALTH_PORT:8000" >"$EVIDENCE_DIR/health/port-forward.log" 2>&1 &
PF_PID=$!
sleep 3

HEALTH_START="$(date +%s)"
for check_number in 1 2 3; do
  body_file="$EVIDENCE_DIR/health/response-$check_number.txt"
  metrics="$(curl -fsS -o "$body_file" \
    -w '%{http_code}\t%{time_total}' \
    "http://127.0.0.1:$PILOT_HEALTH_PORT/version")" \
    || die "auth-api health check $check_number failed"
  http_code="${metrics%%$'\t'*}"
  latency="${metrics#*$'\t'}"
  [[ "$http_code" == 200 ]] \
    || die "auth-api health check $check_number returned HTTP $http_code"
  jq -cn \
    --argjson check "$check_number" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson httpStatus "$http_code" \
    --arg latencySeconds "$latency" \
    --rawfile body "$body_file" \
    '{check:$check,timestamp:$timestamp,httpStatus:$httpStatus,
      latencySeconds:($latencySeconds | tonumber),body:$body}' \
    >>"$EVIDENCE_DIR/health/results.ndjson"
  log "health check $check_number: HTTP $http_code in ${latency}s"
  [[ "$check_number" == 3 ]] || sleep 30
done
HEALTH_ELAPSED=$(( $(date +%s) - HEALTH_START ))
(( HEALTH_ELAPSED >= 60 )) \
  || die "health observation window was only ${HEALTH_ELAPSED}s"
ok "three auth-api HTTP 200 responses over ${HEALTH_ELAPSED}s"

kro get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision' \
  >"$EVIDENCE_DIR/application-status.txt"

jq -n \
  --arg revision "$EXPECTED_SHA" \
  --arg context "$PILOT_KUBE_CONTEXT" \
  --arg authPod "$AUTH_POD" \
  --argjson healthWindowSeconds "$HEALTH_ELAPSED" \
  '{result:"pass",revision:$revision,context:$context,
    addOnApplications:["infra-keda","infra-cert-manager",
      "infra-external-secrets","infra-kyverno"],
    authApplication:"auth-api-local",authPod:$authPod,
    healthChecks:3,healthWindowSeconds:$healthWindowSeconds}' \
  >"$EVIDENCE_DIR/summary.json"

printf 'PLATFORM VERIFIED: four add-ons and auth-api are Synced, Healthy, and live.\n' >&2
printf 'Evidence: %s\n' "$EVIDENCE_DIR" >&2

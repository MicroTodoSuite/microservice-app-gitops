#!/usr/bin/env bash
# Observe feature-005 outcomes without changing GitOps-managed Kubernetes state.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$ROOT/scripts/managed/lib/namespace-isolation.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: verify-namespace-isolation.sh \
  --context <kube-context> \
  --expected-cluster-id <exact-kubeconfig-cluster-id> \
  --phase <baseline|foundation|default-deny|redis-retired|fixtures|final> \
  --expected-revision <40-hex-git-sha> \
  [--previous-evidence <preceding-phase-summary-json>] \
  [--cleanup-revision <40-hex-git-sha>] \
  [--output <new-or-empty-directory>]
USAGE
}

die_usage() {
  printf 'ERROR: %s\n' "$1" >&2
  usage
  exit 2
}

KUBE_CONTEXT=""
EXPECTED_CLUSTER_ID=""
PHASE=""
EXPECTED_REVISION=""
PREVIOUS_EVIDENCE=""
CLEANUP_REVISION=""
OUTPUT_DIR=""

while (($#)); do
  case "$1" in
    --context)
      (($# >= 2)) || die_usage "--context requires a value"
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    --expected-cluster-id)
      (($# >= 2)) || die_usage "--expected-cluster-id requires a value"
      EXPECTED_CLUSTER_ID="$2"
      shift 2
      ;;
    --phase)
      (($# >= 2)) || die_usage "--phase requires a value"
      PHASE="$2"
      shift 2
      ;;
    --expected-revision)
      (($# >= 2)) || die_usage "--expected-revision requires a value"
      EXPECTED_REVISION="$2"
      shift 2
      ;;
    --previous-evidence)
      (($# >= 2)) || die_usage "--previous-evidence requires a value"
      PREVIOUS_EVIDENCE="$2"
      shift 2
      ;;
    --cleanup-revision)
      (($# >= 2)) || die_usage "--cleanup-revision requires a value"
      CLEANUP_REVISION="$2"
      shift 2
      ;;
    --output)
      (($# >= 2)) || die_usage "--output requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die_usage "unknown argument: $1"
      ;;
  esac
done

[[ -n "$KUBE_CONTEXT" ]] || die_usage "--context is required"
[[ -n "$EXPECTED_CLUSTER_ID" ]] || die_usage "--expected-cluster-id is required"
case "$PHASE" in
  baseline|foundation|default-deny|redis-retired|fixtures|final) ;;
  "") die_usage "--phase is required" ;;
  *) die_usage "unsupported phase: $PHASE" ;;
esac
[[ "$EXPECTED_REVISION" =~ ^[0-9a-f]{40}$ ]] ||
  die_usage "--expected-revision must be a full lowercase Git SHA"

if [[ "$PHASE" != baseline ]]; then
  [[ -n "$PREVIOUS_EVIDENCE" ]] ||
    die_usage "--previous-evidence is required after baseline phase"
  [[ -f "$PREVIOUS_EVIDENCE" ]] ||
    die_usage "preceding phase summary does not exist: $PREVIOUS_EVIDENCE"
  case "$PHASE" in
    foundation) required_previous_phase=baseline ;;
    default-deny) required_previous_phase=foundation ;;
    redis-retired) required_previous_phase=default-deny ;;
    fixtures) required_previous_phase=redis-retired ;;
    final) required_previous_phase=fixtures ;;
  esac
  jq -e --arg phase "$required_previous_phase" --arg clusterId "$EXPECTED_CLUSTER_ID" \
    '.phase == $phase and .result == "PASS" and .clusterId == $clusterId and
      .commandAudit.mutatingCommands == 0 and .commandAudit.result == "PASS"' \
    "$PREVIOUS_EVIDENCE" >/dev/null ||
    die_usage "--previous-evidence is not the passing predecessor for this cluster"
fi
if [[ "$PHASE" == final ]]; then
  [[ "$CLEANUP_REVISION" =~ ^[0-9a-f]{40}$ ]] ||
    die_usage "--cleanup-revision is required for final and must be a full lowercase Git SHA"
elif [[ -n "$CLEANUP_REVISION" ]]; then
  die_usage "--cleanup-revision is accepted only for final"
fi

for tool in kubectl jq rg git python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'ERROR: required tool is unavailable: %s\n' "$tool" >&2
    exit 3
  }
done
python3 -c 'import jsonschema' >/dev/null 2>&1 || {
  printf 'ERROR: Python jsonschema is unavailable\n' >&2
  exit 3
}
[[ -f "$LIB" ]] || {
  printf 'ERROR: observer library is unavailable: %s\n' "$LIB" >&2
  exit 3
}

kubectl config get-contexts "$KUBE_CONTEXT" -o name 2>/dev/null | rg -qxF "$KUBE_CONTEXT" || {
  printf 'ERROR: kube context is unavailable: %s\n' "$KUBE_CONTEXT" >&2
  exit 3
}

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$ROOT/.local/evidence/namespace-isolation/$(date -u +%Y%m%dT%H%M%SZ)-$PHASE-$EXPECTED_REVISION"
fi
if [[ -e "$OUTPUT_DIR" ]] && [[ -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  die_usage "output directory exists and is not empty: $OUTPUT_DIR"
fi

# shellcheck source=scripts/managed/lib/namespace-isolation.sh
source "$LIB"
PHASE_EVIDENCE_JSON='{}'
initialize_evidence_directory

finish() {
  local exit_code="$1" result="$2" message="$3"
  if [[ "$result" == PASS ]] && ! command_audit_passes; then
    exit_code=9
    result=FAIL
    message="command audit found a managed-state mutation"
  fi
  write_phase_summary "$result" "$message" "$exit_code"
  printf '%s: %s\nEvidence: %s\n' "$result" "$message" "$OUTPUT_DIR" >&2
  exit "$exit_code"
}

collect_cluster_state || finish 3 FAIL "required cluster or ArgoCD state could not be observed"
collect_environment_state

context_server="$(jq -r '.clusters[0].cluster.server // ""' "$(evidence_file context.json)")"
context_cluster_id="$(jq -r '.contexts[0].context.cluster // ""' "$(evidence_file context.json)")"
if [[ "$context_cluster_id" != "$EXPECTED_CLUSTER_ID" ]]; then
  finish 3 FAIL "context cluster identity differs from --expected-cluster-id"
fi
if [[ ! "$context_server" =~ ^https://.+\.eks\.amazonaws\.com$ ]]; then
  finish 3 FAIL "context is not an AWS EKS endpoint"
fi
policy_agents_ready || finish 5 FAIL "a ready VPC CNI policy agent was not observed for every eligible node"

environment_apps="$(application_names_by_prefix env-)"
business_apps="$(application_names_by_label microtodosuite.io/business-service true)"
infrastructure_apps="$(application_names_by_prefix infra-)"
array_equals "$environment_apps" env-dev env-staging env-prod ||
  finish 4 FAIL "environment Application inventory is not exactly env-dev, env-staging, env-prod"
array_equals "$business_apps" || finish 4 FAIL "business-service Application inventory is not empty"
if [[ "$PHASE" == final ]]; then
  applications_at_revision "$CLEANUP_REVISION" ||
    finish 4 FAIL "environment Applications are not Synced/Healthy at the cleanup revision"
else
  applications_at_expected_revision ||
    finish 4 FAIL "environment Applications are not Synced/Healthy at the expected revision"
fi

if [[ "$PHASE" == baseline || "$PHASE" == foundation || "$PHASE" == default-deny ]]; then
  array_equals "$infrastructure_apps" \
    infra-cert-manager infra-external-secrets infra-keda infra-kyverno infra-redis ||
    finish 4 FAIL "foundation infrastructure inventory is not the exact five-entry allowlist"
else
  array_equals "$infrastructure_apps" "${CONTROLLER_APPS[@]}" ||
    finish 4 FAIL "post-retirement infrastructure inventory is not the exact four-controller allowlist"
fi

case "$PHASE" in
  baseline)
    [[ "$(default_deny_count)" == 0 ]] ||
      finish 5 FAIL "baseline unexpectedly contains managed default-deny policies"
    [[ "$(snapshot_dev_workloads)" != '[]' ]] ||
      finish 8 FAIL "no existing dev business workload is available for continuity baseline"
    finish 0 PASS "baseline prerequisites and dev continuity snapshot passed"
    ;;
  foundation)
    [[ "$(default_deny_count)" == 0 ]] ||
      finish 5 FAIL "foundation revision contains default deny"
    redis_instances_ready || finish 10 FAIL "one or more environment Redis instances are not Ready/PONG"
    compare_dev_baseline || finish 8 FAIL "dev workload state differs from baseline"
    finish 0 PASS "foundation, three Redis instances, and dev continuity passed"
    ;;
  default-deny)
    [[ "$(default_deny_count)" == 3 ]] ||
      finish 5 FAIL "default deny is not present exactly once in every managed namespace"
    redis_instances_ready || finish 10 FAIL "one or more environment Redis instances are not Ready/PONG"
    compare_dev_baseline || finish 8 FAIL "dev workload state differs from baseline"
    finish 0 PASS "default deny, Redis health, and dev continuity passed"
    ;;
  redis-retired)
    [[ ! -s "$(evidence_file shared-redis-namespace.json)" ]] ||
      finish 10 FAIL "shared redis namespace still exists"
    redis_instances_ready || finish 10 FAIL "an environment Redis instance regressed after retirement"
    compare_dev_baseline || finish 8 FAIL "dev workload state differs from baseline"
    finish 0 PASS "shared Redis retirement and replacement health passed"
    ;;
  fixtures)
    collect_rbac_matrix
    [[ "$(default_deny_count)" == 3 ]] || finish 5 FAIL "default deny is incomplete"
    probe_logs_fresh || finish 5 FAIL "probe logs do not contain a fresh observation from every environment"
    [[ "$(probe_unique_pair_count tcp-cross DENIED)" == 6 ]] ||
      finish 5 FAIL "the six unique directed cross-environment TCP denials are incomplete"
    [[ "$(probe_unique_pair_count redis-cross DENIED)" == 6 ]] ||
      finish 10 FAIL "the six unique directed cross-environment Redis denials are incomplete"
    [[ "$(probe_unique_source_count tcp-local ALLOWED)" == 3 ]] ||
      finish 5 FAIL "same-environment TCP success is incomplete"
    [[ "$(probe_unique_source_count dns ALLOWED)" == 3 ]] ||
      finish 5 FAIL "DNS success is incomplete"
    [[ "$(probe_unique_source_count redis-local ALLOWED)" == 3 ]] ||
      finish 10 FAIL "namespace-local Redis PONG evidence is incomplete"
    [[ "$(probe_log_count tcp-cross UNEXPECTED_ALLOWED)" == 0 ]] ||
      finish 5 FAIL "at least one cross-environment TCP connection was unexpectedly allowed"
    [[ "$(probe_log_count redis-cross UNEXPECTED_ALLOWED)" == 0 ]] ||
      finish 10 FAIL "at least one cross-environment Redis connection was unexpectedly allowed"
    pubsub_isolated || finish 10 FAIL "Redis Pub/Sub source isolation failed"
    resource_violation_observed || finish 6 FAIL "expected resource-limit rejection was not observed"
    comparison_environment_healthy ||
      finish 6 FAIL "staging Redis comparison workload is not Ready, restart-free, and PONG"
    jq -se 'length >= 28 and all(.result == "PASS")' \
      "$(evidence_file rbac-matrix.jsonl)" >/dev/null ||
      finish 7 FAIL "RBAC authorization matrix differs from the approved contract"
    compare_dev_baseline || finish 8 FAIL "dev workload state differs from baseline"
    PHASE_EVIDENCE_JSON="$(build_fixture_phase_evidence)" ||
      finish 9 FAIL "fixture evidence could not be serialized"
    finish 0 PASS "network, Redis, resource, RBAC, and continuity fixture checks passed"
    ;;
  final)
    for environment in "${ENVIRONMENTS[@]}"; do
      if jq -e '[.items[] | select(.metadata.labels["microtodosuite.io/feature"] == "namespace-isolation-005")] | length > 0' \
        "$(evidence_file "$environment-resources.json")" >/dev/null 2>&1; then
        finish 4 FAIL "verification fixture remains in $(namespace_for "$environment")"
      fi
    done
    [[ "$(default_deny_count)" == 3 ]] || finish 5 FAIL "default deny is incomplete after cleanup"
    redis_instances_ready || finish 10 FAIL "environment Redis health regressed after cleanup"
    [[ ! -s "$(evidence_file shared-redis-namespace.json)" ]] ||
      finish 10 FAIL "shared redis namespace returned after cleanup"
    compare_dev_baseline || finish 8 FAIL "dev workload state differs from baseline"
    jq -e '.continuitySamples | map(.phase) ==
      ["baseline", "foundation", "default-deny", "redis-retired", "fixtures"]' \
      "$PREVIOUS_EVIDENCE" >/dev/null ||
      finish 9 FAIL "preceding evidence does not contain the exact five-phase continuity chain"
    command_audit_passes || finish 9 FAIL "command audit found a managed-state mutation"
    write_final_evidence_summary ||
      finish 9 FAIL "final cumulative evidence could not be serialized"
    validate_final_evidence_summary || {
      mv "$OUTPUT_DIR/summary.json" "$(evidence_file invalid-summary.json)"
      finish 9 FAIL "final cumulative summary does not validate against schema v1.1.0"
    }
    printf 'PASS: final cumulative namespace-isolation evidence validates\nEvidence: %s\n' \
      "$OUTPUT_DIR" >&2
    exit 0
    ;;
esac

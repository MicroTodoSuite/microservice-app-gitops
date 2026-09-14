#!/usr/bin/env bash
# Read-only composite live evidence collector for feature 006 (Observability
# Platform Foundation), mirroring the read-only discipline and evidence
# format already established in scripts/managed/verify-namespace-isolation.sh
# and scripts/pilot/verify-platform.sh. Reports an explicit PASS/FAIL/BLOCKED
# verdict (spec 009, T148) instead of the "log a WARNING, print VERIFIED
# regardless" behavior this script had before.
#
# STATUS: skeleton only. This has NOT been run against a live cluster - the
# environment that wrote it has no eks-dev AWS/kubectl credentials (see
# specs/006-observability-platform-foundation/tasks.md, Notes). Whoever runs
# this against the real eks-dev cluster is the first live evidence for
# FR-015/SC-009, not this script's authorship.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTEXT="eks-dev"
NAMESPACE="microtodo-dev"
OBS_NAMESPACE="observability"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) CONTEXT="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="$ROOT/evidence/runs/${TIMESTAMP}-observability"
mkdir -p "$EVIDENCE_DIR/raw"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
kube() { kubectl --context "$CONTEXT" "$@"; }

# shellcheck source=scripts/managed/lib/verify-common.sh
source "$ROOT/scripts/managed/lib/verify-common.sh"

if ! require_live_context "$CONTEXT"; then
  record_check BLOCKED "live access to context '$CONTEXT' (no cluster reachable from this environment)"
  final_verdict
  exit $?
fi

log "Checking ArgoCD Application status for prometheus/grafana"
if kube get applications -n argocd -o json | tee "$EVIDENCE_DIR/raw/applications.json" \
  | jq -r '.items[] | select(.metadata.name | test("infra-prometheus|infra-grafana")) | "\(.metadata.name) sync=\(.status.sync.status) health=\(.status.health.status) revision=\(.status.sync.revision // .status.sync.comparedTo.source.targetRevision // "unknown")"'; then
  record_check PASS "ArgoCD Application status for prometheus/grafana"
else
  record_check FAIL "ArgoCD Application status for prometheus/grafana"
fi

log "Checking controller Deployments/StatefulSets in $OBS_NAMESPACE"
if kube get deployments,statefulsets -n "$OBS_NAMESPACE" -o wide | tee "$EVIDENCE_DIR/raw/controllers.txt" >/dev/null; then
  record_check PASS "controller Deployments/StatefulSets in $OBS_NAMESPACE"
else
  record_check FAIL "controller Deployments/StatefulSets in $OBS_NAMESPACE"
fi

log "Checking ServiceMonitor targets are Up"
if kube get servicemonitors -n "$OBS_NAMESPACE" -o name | tee "$EVIDENCE_DIR/raw/servicemonitors.txt" >/dev/null; then
  record_check PASS "ServiceMonitors are listable in $OBS_NAMESPACE"
else
  record_check FAIL "ServiceMonitors are listable in $OBS_NAMESPACE"
fi

log "Querying a live golden-signal metric (traffic) for auth-api"
if kube run --rm -i --restart=Never --context "$CONTEXT" prom-query-check \
  --image=curlimages/curl:8.11.1 -- \
  curl -sf "http://prometheus-k8s.$OBS_NAMESPACE.svc:9090/api/v1/query?query=workload:http_requests:rate5m%7Bworkload=%22auth-api%22%7D" \
  | tee "$EVIDENCE_DIR/raw/dashboard-query.json" >/dev/null; then
  record_check PASS "live Prometheus query for auth-api traffic"
else
  record_check FAIL "live Prometheus query for auth-api traffic"
fi

log "Evidence retained under $EVIDENCE_DIR"
log "Remaining checks (canary abort/promote, Slack alert firing/resolution,"
log "Jaeger trace retrieval, Loki log correlation) are added by this feature's"
log "later tasks (US2-US5); this run only covers User Story 1's scope."

final_verdict
exit $?

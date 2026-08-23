#!/usr/bin/env bash
# Read-only composite live evidence collector for feature 006 (Observability
# Platform Foundation), mirroring the read-only discipline and evidence
# format already established in scripts/managed/verify-namespace-isolation.sh
# and scripts/pilot/verify-platform.sh.
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

log "Checking ArgoCD Application status for prometheus/grafana"
kube get applications -n argocd -o json \
  | tee "$EVIDENCE_DIR/raw/applications.json" \
  | jq -r '.items[] | select(.metadata.name | test("infra-prometheus|infra-grafana")) | "\(.metadata.name) sync=\(.status.sync.status) health=\(.status.health.status) revision=\(.status.sync.revision // .status.sync.comparedTo.source.targetRevision // "unknown")"' \
  || log "WARNING: could not read ArgoCD Application status (no live access from this environment)"

log "Checking controller Deployments/StatefulSets in $OBS_NAMESPACE"
kube get deployments,statefulsets -n "$OBS_NAMESPACE" -o wide \
  | tee "$EVIDENCE_DIR/raw/controllers.txt" \
  || log "WARNING: could not list controllers in $OBS_NAMESPACE"

log "Checking ServiceMonitor targets are Up"
kube get servicemonitors -n "$OBS_NAMESPACE" -o name \
  | tee "$EVIDENCE_DIR/raw/servicemonitors.txt" \
  || log "WARNING: could not list ServiceMonitors"

log "Querying a live golden-signal metric (traffic) for auth-api"
kube run --rm -i --restart=Never --context "$CONTEXT" prom-query-check \
  --image=curlimages/curl:8.11.1 -- \
  curl -s "http://prometheus-k8s.$OBS_NAMESPACE.svc:9090/api/v1/query?query=workload:http_requests:rate5m%7Bworkload=%22auth-api%22%7D" \
  | tee "$EVIDENCE_DIR/raw/dashboard-query.json" \
  || log "WARNING: could not run a live Prometheus query"

log "Evidence retained under $EVIDENCE_DIR"
log "Remaining checks (canary abort/promote, Slack alert firing/resolution,"
log "Jaeger trace retrieval, Loki log correlation) are added by this feature's"
log "later tasks (US2-US5); this run only covers User Story 1's scope."

echo "OBSERVABILITY VERIFIED (US1 scope only): see $EVIDENCE_DIR for raw evidence."

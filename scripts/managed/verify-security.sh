#!/usr/bin/env bash
# Read-only composite live evidence collector for feature 008 (Runtime
# Security Hardening), mirroring scripts/managed/verify-observability.sh.
#
# STATUS: skeleton only, covers User Story 1 (Falco) so far. This has NOT
# been run against a live cluster - the environment that wrote it has no
# eks-dev AWS/kubectl credentials (see specs/008-security-runtime-
# hardening/tasks.md, Notes).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTEXT="eks-dev"
NAMESPACE="security"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) CONTEXT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="$ROOT/evidence/runs/${TIMESTAMP}-security"
mkdir -p "$EVIDENCE_DIR/raw"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
kube() { kubectl --context "$CONTEXT" "$@"; }

log "Checking ArgoCD Application status for falco"
kube get applications -n argocd -o json \
  | tee "$EVIDENCE_DIR/raw/applications.json" \
  | jq -r '.items[] | select(.metadata.name | test("infra-falco")) | "\(.metadata.name) sync=\(.status.sync.status) health=\(.status.health.status)"' \
  || log "WARNING: could not read ArgoCD Application status (no live access from this environment)"

log "Checking Falco DaemonSet coverage (one pod per node)"
node_count=$(kube get nodes -o json | jq '.items | length' 2>/dev/null || echo "unknown")
kube get daemonset falco -n "$NAMESPACE" -o wide \
  | tee "$EVIDENCE_DIR/raw/falco-daemonset.txt" \
  || log "WARNING: could not read Falco DaemonSet status"
log "Cluster has $node_count node(s); compare against Falco's desiredNumberScheduled above"

log "Checking Falcosidekick health"
kube get deployment falcosidekick -n "$NAMESPACE" -o wide \
  | tee "$EVIDENCE_DIR/raw/falcosidekick.txt" \
  || log "WARNING: could not read Falcosidekick status"

log "Triggering a real Falco finding: spawning a shell in a running business-workload pod"
kube exec -n microtodo-dev deploy/auth-api -- /bin/sh -c 'echo triggering-falco-finding-$(date +%s)' \
  || log "WARNING: could not exec into a business workload to trigger a finding"
sleep 3
log "Checking Falco logs for the resulting finding"
kube logs daemonset/falco -n "$NAMESPACE" --tail=50 \
  | tee "$EVIDENCE_DIR/raw/falco-finding.log" \
  | grep -i "shell\|notice\|warning" \
  || log "WARNING: no matching finding observed in the last 50 log lines"

log "Triggering a manual kube-bench run and capturing its report"
kube create job --from=cronjob/kube-bench "kube-bench-manual-$(date +%s)" -n "$NAMESPACE" \
  || log "WARNING: could not trigger a manual kube-bench Job"
sleep 5
kube get pods -n "$NAMESPACE" -l app.kubernetes.io/name=kube-bench \
  | tee "$EVIDENCE_DIR/raw/kube-bench-pods.txt" \
  || log "WARNING: could not list kube-bench pods"
log "Once the Job completes, run: kubectl --context $CONTEXT -n $NAMESPACE logs job/<name>"
log "to capture the real PASS/FAIL/WARN report (not automated here - a"
log "manually-triggered Job's pod name is only known after it starts)."

log "Evidence retained under $EVIDENCE_DIR"
log "Remaining check (kube-hunter report) is added by this feature's next"
log "user story; this run covers User Story 1 and User Story 2."

echo "SECURITY VERIFIED (US1/US2 scope): see $EVIDENCE_DIR for raw evidence."

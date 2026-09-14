#!/usr/bin/env bash
# Read-only composite live evidence collector for feature 008 (Runtime
# Security Hardening), mirroring scripts/managed/verify-observability.sh.
# Reports an explicit PASS/FAIL/BLOCKED verdict (spec 009, T148) instead of
# the "log a WARNING, print VERIFIED regardless" behavior this script had
# before.
#
# It only reads: it creates, execs into, and changes nothing (spec 009 T088).
# STATUS: not yet run against a live cluster - the environment that wrote it
# has no eks-dev AWS/kubectl credentials (see specs/008-security-runtime-
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

# shellcheck source=scripts/managed/lib/verify-common.sh
source "$ROOT/scripts/managed/lib/verify-common.sh"

if ! require_live_context "$CONTEXT"; then
  record_check BLOCKED "live access to context '$CONTEXT' (no cluster reachable from this environment)"
  final_verdict
  exit $?
fi

log "Checking ArgoCD Application status for falco"
if kube get applications -n argocd -o json | tee "$EVIDENCE_DIR/raw/applications.json" \
  | jq -r '.items[] | select(.metadata.name | test("infra-falco")) | "\(.metadata.name) sync=\(.status.sync.status) health=\(.status.health.status)"'; then
  record_check PASS "ArgoCD Application status for falco"
else
  record_check FAIL "ArgoCD Application status for falco"
fi

log "Checking Falco DaemonSet coverage (one pod per node)"
node_count=$(kube get nodes -o json | jq '.items | length' 2>/dev/null || echo "unknown")
if kube get daemonset falco -n "$NAMESPACE" -o wide | tee "$EVIDENCE_DIR/raw/falco-daemonset.txt" >/dev/null; then
  record_check PASS "Falco DaemonSet status ($node_count node(s) in cluster; compare against desiredNumberScheduled)"
else
  record_check FAIL "Falco DaemonSet status"
fi

log "Checking Falcosidekick health"
if kube get deployment falcosidekick -n "$NAMESPACE" -o wide | tee "$EVIDENCE_DIR/raw/falcosidekick.txt" >/dev/null; then
  record_check PASS "Falcosidekick Deployment status"
else
  record_check FAIL "Falcosidekick Deployment status"
fi

# Every check below only reads (spec 009 T088, research.md Decision 22). A
# finding or report that does not exist yet is BLOCKED, not triggered here:
# the triggers are checked-in Jobs under infrastructure/*/triggers/ that a
# reviewed commit activates and a revert removes.
log "Reading Falco findings from the last 24 hours on every Falco pod"
falco_rule="Search Private Keys or Passwords"
: >"$EVIDENCE_DIR/raw/falco-findings.log"
for pod in $(kube get pods -n "$NAMESPACE" -l app.kubernetes.io/name=falco -o name 2>/dev/null); do
  kube logs -n "$NAMESPACE" "$pod" --since=24h >>"$EVIDENCE_DIR/raw/falco-findings.log" 2>/dev/null || true
done
if grep -F "$falco_rule" "$EVIDENCE_DIR/raw/falco-findings.log" >/dev/null; then
  record_check PASS "Falco reported \"$falco_rule\" in the last 24 hours"
else
  record_check BLOCKED "no \"$falco_rule\" finding in the last 24 hours: activate infrastructure/falco/triggers through a reviewed commit, rerun, then revert it"
fi

# report_latest_job <component> <trigger path>: reads the newest Job the
# CronJob or its checked-in trigger created for <component>.
report_latest_job() {
  local component="$1" trigger="$2" job report="$EVIDENCE_DIR/raw/$1-report.log"
  job="$(kube get jobs -n "$NAMESPACE" -l "app.kubernetes.io/name=$component" \
    --sort-by=.metadata.creationTimestamp -o name 2>/dev/null | tail -n 1)"
  if [[ -z "$job" ]]; then
    record_check BLOCKED "no $component Job to read: wait for its schedule or activate $trigger through a reviewed commit, then revert it"
    return
  fi
  if kube logs -n "$NAMESPACE" "$job" >"$report" 2>&1 && [[ -s "$report" ]]; then
    record_check PASS "$component report read from $job"
  else
    record_check FAIL "$component report from $job is missing or empty"
  fi
}

log "Reading the latest kube-bench report"
report_latest_job kube-bench infrastructure/kube-bench/triggers

log "Reading the latest kube-hunter report"
report_latest_job kube-hunter infrastructure/kube-hunter/triggers

log "Checking Trivy Operator and the vulnerability reports it keeps (User Story 4)"
if kube get deployment trivy-operator -n "$NAMESPACE" -o wide | tee "$EVIDENCE_DIR/raw/trivy-operator.txt" >/dev/null; then
  record_check PASS "trivy-operator Deployment status"
else
  record_check FAIL "trivy-operator Deployment status"
fi
for scanned in microtodo-dev microtodo-staging microtodo-prod observability security; do
  if kube get vulnerabilityreports -n "$scanned" \
    -o custom-columns=NAME:.metadata.name,CRITICAL:.report.summary.criticalCount,HIGH:.report.summary.highCount \
    | tee "$EVIDENCE_DIR/raw/vulnerabilityreports-$scanned.txt" >/dev/null; then
    record_check PASS "vulnerability reports listed in $scanned"
  else
    record_check FAIL "vulnerability reports listed in $scanned"
  fi
done
log "Compare these counts with the Grafana vulnerability dashboard, and record"
log "the Slack notification for any image with HIGH or CRITICAL counts."

log "Evidence retained under $EVIDENCE_DIR"
log "This run covers all four user stories (Falco, kube-bench, kube-hunter, Trivy)."

final_verdict
exit $?

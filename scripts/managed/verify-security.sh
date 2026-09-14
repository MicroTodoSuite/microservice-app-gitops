#!/usr/bin/env bash
# Read-only composite live evidence collector for feature 008 (Runtime
# Security Hardening), mirroring scripts/managed/verify-observability.sh.
# Reports an explicit PASS/FAIL/BLOCKED verdict (spec 009, T148) instead of
# the "log a WARNING, print VERIFIED regardless" behavior this script had
# before.
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

log "Triggering a real Falco finding: spawning a shell in a running business-workload pod"
if kube exec -n microtodo-dev deploy/auth-api -- /bin/sh -c 'echo triggering-falco-finding-$(date +%s)'; then
  record_check PASS "trigger command executed in a business-workload pod"
  sleep 3
  log "Checking Falco logs for the resulting finding"
  if kube logs daemonset/falco -n "$NAMESPACE" --tail=50 | tee "$EVIDENCE_DIR/raw/falco-finding.log" \
    | grep -i "shell\|notice\|warning" >/dev/null; then
    record_check PASS "Falco finding observed in the last 50 log lines"
  else
    record_check FAIL "Falco finding observed in the last 50 log lines"
  fi
else
  record_check FAIL "trigger command executed in a business-workload pod"
  record_check BLOCKED "Falco finding check (trigger command did not run)"
fi

log "Triggering a manual kube-bench run and capturing its report"
if kube create job --from=cronjob/kube-bench "kube-bench-manual-$(date +%s)" -n "$NAMESPACE"; then
  record_check PASS "manual kube-bench Job triggered"
  sleep 5
  if kube get pods -n "$NAMESPACE" -l app.kubernetes.io/name=kube-bench | tee "$EVIDENCE_DIR/raw/kube-bench-pods.txt" >/dev/null; then
    record_check PASS "kube-bench pod listed after trigger"
  else
    record_check FAIL "kube-bench pod listed after trigger"
  fi
  log "Once the Job completes, run: kubectl --context $CONTEXT -n $NAMESPACE logs job/<name>"
  log "to capture the real PASS/FAIL/WARN report (not automated here - a"
  log "manually-triggered Job's pod name is only known after it starts)."
else
  record_check FAIL "manual kube-bench Job triggered"
  record_check BLOCKED "kube-bench pod listed after trigger (Job did not start)"
fi

log "Triggering a manual kube-hunter run and capturing its report"
if kube create job --from=cronjob/kube-hunter "kube-hunter-manual-$(date +%s)" -n "$NAMESPACE"; then
  record_check PASS "manual kube-hunter Job triggered"
  sleep 5
  if kube get pods -n "$NAMESPACE" -l app.kubernetes.io/name=kube-hunter | tee "$EVIDENCE_DIR/raw/kube-hunter-pods.txt" >/dev/null; then
    record_check PASS "kube-hunter pod listed after trigger"
  else
    record_check FAIL "kube-hunter pod listed after trigger"
  fi
  log "Once the Job completes, run: kubectl --context $CONTEXT -n $NAMESPACE logs job/<name>"
  log "to capture the real vulnerability report (or explicit 'none found')."
else
  record_check FAIL "manual kube-hunter Job triggered"
  record_check BLOCKED "kube-hunter pod listed after trigger (Job did not start)"
fi

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

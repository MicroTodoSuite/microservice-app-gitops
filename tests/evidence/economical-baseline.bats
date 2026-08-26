#!/usr/bin/env bash
# Economical baseline collector (spec 009, T031).
#
# SC-001 says every capability healthy before a stage is healthy after it. That
# is only checkable against a recorded baseline, so the collector must be honest
# in all four states: healthy, degraded, unreachable, and synced-to-the-wrong-
# revision. The last two matter most — an unreachable cluster and a stale
# revision are exactly the cases where a naive collector reports success.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COLLECTOR="$ROOT/scripts/managed/capture-economical-baseline.sh"
FIXTURES="$ROOT/tests/evidence/fixtures/economical"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

[[ -x "$COLLECTOR" ]] || { printf 'FAIL: collector is missing or not executable: %s\n' "$COLLECTOR" >&2; exit 1; }

# <fixture> <output> -> exit code of the collector
capture() {
  local fixture="$1" output="$2" rc=0
  ECONOMICAL_FIXTURE_DIR="$FIXTURES/$fixture" \
  PATH="$FIXTURES/$fixture/bin:$PATH" \
  WORKLOAD_NAMESPACES="microtodo-dev" \
    "$COLLECTOR" --output "$output" \
      --git-revision "$(cat "$FIXTURES/$fixture/git-revision.txt")" \
      --dev-plan-result "$(cat "$FIXTURES/$fixture/dev-plan-result.txt")" \
      >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

# --- healthy ---------------------------------------------------------------
rc="$(capture healthy "$TMP/healthy.json")"
[[ "$rc" -eq 0 ]] || fail "a healthy platform must be captured successfully (exit $rc)"
if [[ -f "$TMP/healthy.json" ]]; then
  jq -e '.result == "pass"' "$TMP/healthy.json" >/dev/null \
    || fail "a healthy platform must record result=pass"
  jq -e '.applications.total == 3 and .applications.healthy == 3' "$TMP/healthy.json" >/dev/null \
    || fail "the baseline must count every Application it observed"
  jq -e '.workloads.ready == 2 and (.workloads.notReady | length) == 0' "$TMP/healthy.json" >/dev/null \
    || fail "the baseline must record ready workloads"
  jq -e '(.endpoints.withoutAddresses | length) == 0' "$TMP/healthy.json" >/dev/null \
    || fail "the baseline must record endpoint readiness"
  jq -e '.namespaceIsolation.namespacesWithoutPolicy | length == 0' "$TMP/healthy.json" >/dev/null \
    || fail "the baseline must record namespace isolation"
  jq -e '.devPlan.clean == true' "$TMP/healthy.json" >/dev/null \
    || fail "the baseline must record the dev plan verdict"
  jq -e '.identities.awsAccountId == "916491575487"' "$TMP/healthy.json" >/dev/null \
    || fail "the baseline must record the AWS account it observed"
  # A baseline is comparison evidence; it must not carry secret material.
  grep -qiE '"(token|password|secret|key)":' "$TMP/healthy.json" \
    && fail "the baseline must not record secret material"
else
  fail "a healthy capture must write its baseline file"
fi

# --- degraded --------------------------------------------------------------
rc="$(capture degraded "$TMP/degraded.json")"
[[ "$rc" -ne 0 ]] || fail "a degraded platform must fail closed"
[[ -f "$TMP/degraded.json" ]] && {
  jq -e '.result == "degraded"' "$TMP/degraded.json" >/dev/null \
    || fail "a degraded platform must record result=degraded"
  jq -e '(.applications.exceptions | length) > 0' "$TMP/degraded.json" >/dev/null \
    || fail "a degraded platform must name the failing Application"
}

# --- unreachable -----------------------------------------------------------
# An unreachable cluster is missing evidence, never an implicit pass.
rc="$(capture unreachable "$TMP/unreachable.json")"
[[ "$rc" -ne 0 ]] || fail "an unreachable cluster must fail closed"
[[ -f "$TMP/unreachable.json" ]] && {
  jq -e '.result == "unreachable"' "$TMP/unreachable.json" >/dev/null \
    || fail "an unreachable cluster must record result=unreachable"
  jq -e '.result != "pass"' "$TMP/unreachable.json" >/dev/null \
    || fail "an unreachable cluster must never record a pass"
}

# --- revision mismatch -----------------------------------------------------
# Every Application must be synced to the revision under test; one lagging
# behind means the baseline describes a platform that is not what Git says.
rc="$(capture revision-mismatch "$TMP/mismatch.json")"
[[ "$rc" -ne 0 ]] || fail "a revision mismatch must fail closed"
[[ -f "$TMP/mismatch.json" ]] && {
  jq -e '.result == "revision-mismatch"' "$TMP/mismatch.json" >/dev/null \
    || fail "a revision mismatch must be reported as such"
  jq -e '(.applications.revisionMismatches | length) > 0' "$TMP/mismatch.json" >/dev/null \
    || fail "a revision mismatch must name the lagging Application"
}

# --- read-only guarantee ---------------------------------------------------
# The collector runs against the live economical platform; it must not contain
# a single mutating verb.
if grep -nE '(kubectl|KUBECTL_BIN)[^|]*\b(apply|create|patch|delete|scale|replace|edit|annotate|label)\b' "$COLLECTOR" >/dev/null; then
  fail "the collector must be strictly read-only"
fi
if grep -nE 'terraform[^|]*\b(apply|destroy|import|taint)\b' "$COLLECTOR" >/dev/null; then
  fail "the collector must never mutate Terraform state"
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d economical-baseline violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: the economical baseline is honest in healthy, degraded, unreachable and revision-mismatch states.\n'

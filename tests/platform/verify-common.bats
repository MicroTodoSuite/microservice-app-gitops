#!/usr/bin/env bash
# Unit test for scripts/managed/lib/verify-common.sh (spec 009, T148): proves
# the explicit PASS/FAIL/BLOCKED verdict aggregation actually distinguishes
# the three outcomes, replacing the warning-as-success behavior
# verify-observability.sh and verify-security.sh had before this feature.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
lib="$repo_root/scripts/managed/lib/verify-common.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

log() { :; } # silence record_check's log() call for this unit test
# shellcheck source=scripts/managed/lib/verify-common.sh
source "$lib"

# --- all PASS -> exit 0, "VERDICT: PASS" ------------------------------------
CHECK_RESULTS=()
record_check PASS "check one"
record_check PASS "check two"
code=0; output="$(final_verdict)" || code=$?
[[ "$code" -eq 0 ]] || fail "all-PASS run exited $code, expected 0"
[[ "$output" == "VERDICT: PASS (2 passed, 0 failed, 0 blocked)" ]] || fail "unexpected all-PASS output: $output"

# --- any FAIL -> exit 1, "VERDICT: FAIL", even with a PASS and a BLOCKED too
CHECK_RESULTS=()
record_check PASS "check one"
record_check BLOCKED "check two"
record_check FAIL "check three"
code=0; output="$(final_verdict)" || code=$?
[[ "$code" -eq 1 ]] || fail "mixed-with-FAIL run exited $code, expected 1"
[[ "$output" == "VERDICT: FAIL (1 passed, 1 failed, 1 blocked)" ]] || fail "unexpected FAIL output: $output"

# --- BLOCKED, no FAIL -> exit 2, "VERDICT: BLOCKED" -------------------------
CHECK_RESULTS=()
record_check PASS "check one"
record_check BLOCKED "check two"
code=0; output="$(final_verdict)" || code=$?
[[ "$code" -eq 2 ]] || fail "BLOCKED-no-FAIL run exited $code, expected 2"
[[ "$output" == "VERDICT: BLOCKED (1 passed, 0 failed, 1 blocked)" ]] || fail "unexpected BLOCKED output: $output"

# --- nothing recorded at all -> BLOCKED, never a silent PASS ---------------
CHECK_RESULTS=()
code=0; output="$(final_verdict)" || code=$?
[[ "$code" -eq 2 ]] || fail "empty-run exited $code, expected 2 (BLOCKED, not a silent PASS)"

# --- require_live_context: a context that does not exist on this machine
# fails fast without hanging, real kubectl, no mocking needed.
if command -v kubectl >/dev/null 2>&1; then
  if require_live_context "microtodosuite-nonexistent-context-for-this-test"; then
    fail "require_live_context reported success for a context that does not exist"
  fi
else
  printf 'SKIP: kubectl is not installed; require_live_context check skipped.\n' >&2
fi

printf 'PASS: verify-common correctly distinguishes PASS, FAIL, and BLOCKED, and never reports a silent PASS with nothing checked.\n'

#!/usr/bin/env bash
# Shared explicit-verdict helpers for the read-only live-evidence collectors
# (verify-observability.sh, verify-security.sh, verify-full-platform.sh).
# Mirrors the PASS/FAIL/BLOCKED vocabulary scripts/managed/lib/namespace-isolation.sh
# already established for feature 005, at the smaller scale these collectors
# need (spec 009, T148): every check is recorded as PASS, FAIL, or BLOCKED --
# never silently downgraded to a "WARNING" that the final line ignores.

CHECK_RESULTS=()

# record_check <PASS|FAIL|BLOCKED> <description>
record_check() {
  local result="$1" description="$2"
  CHECK_RESULTS+=("$result:$description")
  log "$result: $description"
}

# require_live_context <kube-context>
# A single, cheap connectivity probe run once per cluster: if it fails, every
# check for that context is BLOCKED (no live access from this environment),
# not individually re-diagnosed as if each were a distinct cluster fault.
require_live_context() {
  local context="$1"
  kubectl config get-contexts "$context" -o name >/dev/null 2>&1 \
    && kubectl --context "$context" get namespaces >/dev/null 2>&1
}

# final_verdict: aggregates CHECK_RESULTS and prints/returns the worst
# outcome. FAIL beats BLOCKED beats PASS; an empty result set is BLOCKED
# (nothing was actually checked), never a silent PASS.
final_verdict() {
  local fails=0 blocked=0 passes=0 entry
  for entry in "${CHECK_RESULTS[@]}"; do
    case "$entry" in
      FAIL:*) fails=$((fails + 1)) ;;
      BLOCKED:*) blocked=$((blocked + 1)) ;;
      PASS:*) passes=$((passes + 1)) ;;
    esac
  done
  if (( fails > 0 )); then
    printf 'VERDICT: FAIL (%d passed, %d failed, %d blocked)\n' "$passes" "$fails" "$blocked"
    return 1
  elif (( blocked > 0 || passes == 0 )); then
    printf 'VERDICT: BLOCKED (%d passed, 0 failed, %d blocked)\n' "$passes" "$blocked"
    return 2
  else
    printf 'VERDICT: PASS (%d passed, 0 failed, 0 blocked)\n' "$passes"
    return 0
  fi
}

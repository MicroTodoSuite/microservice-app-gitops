#!/usr/bin/env bash
# Regression test for scripts/managed/verify-observability.sh (spec 009, T148):
# proves the "log a WARNING, print VERIFIED regardless" bug is gone. Run for
# real with an unreachable context -- this environment genuinely has none --
# so a script that still hard-codes success would be caught here, not mocked
# around.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$repo_root/scripts/managed/verify-observability.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -x "$script" ]] || fail "verify-observability.sh is missing or not executable"

before_runs="$(find "$repo_root/evidence/runs" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

code=0
output="$(bash "$script" --context microtodosuite-nonexistent-context-for-this-test 2>&1)" || code=$?

[[ "$code" -ne 0 ]] || fail "exited 0 (success) against an unreachable context. Output:
$output"
grep -Fq 'VERDICT: BLOCKED' <<<"$output" || fail "missing an explicit BLOCKED verdict:
$output"
if grep -Fqi 'VERIFIED' <<<"$output"; then
  fail "still prints an unconditional VERIFIED banner:
$output"
fi

for dir in "$repo_root"/evidence/runs/*-observability; do
  [[ -d "$dir" ]] && rm -rf "$dir"
done
after_runs="$(find "$repo_root/evidence/runs" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
[[ "$after_runs" -eq "$before_runs" ]] || fail "left stray evidence directories behind after cleanup"

printf 'PASS: verify-observability.sh reports an explicit BLOCKED verdict (not a silent VERIFIED) against an unreachable context.\n'

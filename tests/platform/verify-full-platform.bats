#!/usr/bin/env bash
# Structural test for scripts/managed/verify-full-platform.sh (spec 009,
# T148). Runs the real script for real -- no mocked kubectl -- because the
# DESIRED half needs no cluster (kustomize renders and the activation-apps.yaml
# state are read directly), and this environment genuinely has no
# eks-full-{dev,staging,prod} kubectl context, so the LIVE half's BLOCKED
# outcome is exercised for real too, not simulated.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$repo_root/scripts/managed/verify-full-platform.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -x "$script" ]] || fail "verify-full-platform.sh is missing or not executable"

before_runs="$(find "$repo_root/evidence/runs" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

code=0
output="$(bash "$script" 2>&1)" || code=$?

# This environment has no eks-full-* kubectl context: the honest result today
# is DESIRED-only PASS plus a BLOCKED verdict, never a silent success.
[[ "$code" -eq 2 ]] || fail "expected exit 2 (BLOCKED, no live full-profile cluster access here); got $code. Output:
$output"

grep -Fq 'VERDICT: BLOCKED' <<<"$output" || fail "missing explicit BLOCKED verdict in output:
$output"

# The rollback anchor is offline and must always pass.
grep -Fq 'PASS: rollback anchor recorded' <<<"$output" || fail "rollback anchor check did not run or did not pass:
$output"

# All three full destinations report their real, current, pre-activation
# state -- zero activated business applications -- not an error.
for destination in eks-full-dev eks-full-staging eks-full-prod; do
  grep -Fq "PASS: $destination: zero business applications activated" <<<"$output" \
    || fail "$destination: expected the honest 'zero activated' PASS, not found:
$output"
  grep -Fq "BLOCKED: $destination: live cluster access" <<<"$output" \
    || fail "$destination: expected a BLOCKED live-access check, not found:
$output"
done

# Every service's full/<env> overlay is proven to render with a real pinned
# digest today, independent of activation or cluster access.
for service in auth-api todos-api users-api frontend log-message-processor; do
  for destination in eks-full-dev eks-full-staging eks-full-prod; do
    grep -Fq "PASS: $destination/$service: overlay renders with a pinned digest" <<<"$output" \
      || fail "$destination/$service: expected overlay-renders-with-digest PASS, not found:
$output"
  done
done

# No FAIL anywhere: every currently-checkable thing about the full profile's
# scaffold state is genuinely correct today.
if grep -Fq 'FAIL:' <<<"$output"; then
  fail "unexpected FAIL in an all-scaffold, nothing-activated run:
$output"
fi

# The script only ever writes its own timestamped evidence directory, cleaned
# up by this test, never anything pre-existing.
after_dirs=("$repo_root"/evidence/runs/*-full-platform)
[[ -d "${after_dirs[0]}" ]] || fail "expected a new -full-platform evidence directory"
for dir in "${after_dirs[@]}"; do
  rm -rf "$dir"
done
after_runs="$(find "$repo_root/evidence/runs" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
[[ "$after_runs" -eq "$before_runs" ]] || fail "left stray evidence directories behind after cleanup"

printf 'PASS: verify-full-platform.sh reports the honest DESIRED-only state (zero activation, every overlay pinned) plus an explicit BLOCKED verdict for the live half, with no unexpected FAIL.\n'

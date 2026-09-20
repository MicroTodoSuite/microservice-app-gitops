#!/usr/bin/env bash
# Production promotion must require explicit human approval before it can
# merge (FR-008). Branch protection alone only proves "some approver"; this
# contract proves a *designated* approver is required specifically for
# `apps/*/overlays/prod/**`, via CODEOWNERS plus "require review from code
# owners" -- not just the repo-wide one-approval rule that already applies to
# every path.
#
# This checks the static, repo-local half of the contract (CODEOWNERS itself).
# Whether GitHub actually enforces "require review from code owners" on `main`
# is live branch-protection state, not a file in this repository, and is
# recorded instead in docs/service-delivery.md and verified operationally.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEOWNERS="$ROOT/CODEOWNERS"

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

[[ -f "$CODEOWNERS" ]] || {
  fail "CODEOWNERS does not exist at the repository root"
  exit 1
}

pattern='apps/*/overlays/prod/**'
line="$(grep -F "$pattern" "$CODEOWNERS" || true)"

[[ -n "$line" ]] || fail "CODEOWNERS has no entry for '$pattern'"

if [[ -n "$line" ]]; then
  owners="$(awk '{$1=""; print}' <<<"$line" | xargs || true)"
  [[ -n "$owners" ]] || fail "the '$pattern' entry names no owner"
  for owner in $owners; do
    [[ "$owner" == @* ]] || fail "owner '$owner' is not a @user or @org/team handle"
  done
fi

if [[ "$failures" -gt 0 ]]; then
  printf 'FAIL: %d prod-overlay-approval check(s) failed.\n' "$failures" >&2
  exit 1
fi

echo "PASS: CODEOWNERS requires a designated approver for apps/*/overlays/prod/**."

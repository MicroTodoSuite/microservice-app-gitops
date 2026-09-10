#!/usr/bin/env bash
# Proves scripts/set-aws-account.sh moves this repository to another AWS
# account with one command, and refuses every input that would leave it
# inconsistent. Runs against a disposable copy; the checkout is never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="scripts/set-aws-account.sh"
CONFIG="config/aws-account.env"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "$ROOT/$SCRIPT" ]] || fail "$SCRIPT is missing or not executable"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
(cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 cp -a --parents -t "$work")
git -C "$work" init -q
git -C "$work" add -A

current="$(sed -n 's/^AWS_ACCOUNT_ID=\([0-9]*\)[[:space:]]*$/\1/p' "$work/$CONFIG")"
retired="$(sed -n 's/^RETIRED_AWS_ACCOUNT_IDS="\([0-9 ]*\)"[[:space:]]*$/\1/p' "$work/$CONFIG")"
next="222233334444"

refuses() {
  local label=$1
  shift
  if "$work/$SCRIPT" "$@" >/dev/null 2>&1; then
    fail "accepted $label"
  fi
  git -C "$work" diff --quiet || fail "refusing $label still modified files"
}

refuses "no argument"
refuses "a malformed account" 12345
refuses "the account already declared" "$current"
refuses "a documentation placeholder" 123456789012
for id in $retired; do
  refuses "retired account $id" "$id"
done

"$work/$SCRIPT" "$next" >/dev/null || fail "rejected the valid new account $next"

grep -qx "AWS_ACCOUNT_ID=$next" "$work/$CONFIG" \
  || fail "the declaration was not moved to $next"
sed -n 's/^RETIRED_AWS_ACCOUNT_IDS="\(.*\)"$/\1/p' "$work/$CONFIG" | tr ' ' '\n' | grep -qx "$current" \
  || fail "the previous account $current was not retired"
git -C "$work" diff --quiet -- config/aws-account-exceptions.txt \
  || fail "the script edited the exception list instead of the files"
git -C "$work" diff --quiet -- specs ':!specs/*/quickstart.md' evidence 2>/dev/null \
  || fail "the script rewrote a specification or evidence record"

"$work/tests/contract/aws-account-parameter.sh" >/dev/null \
  || fail "the repository is inconsistent after moving to $next"

printf 'PASS: one command moves the repository from %s to a new account; five invalid inputs are refused.\n' "$current"

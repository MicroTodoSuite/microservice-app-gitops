#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/managed/validate-full-profile-evidence.sh"
FIXTURES="$ROOT/tests/evidence/fixtures"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "$VALIDATOR" ]] || fail "validator is missing or not executable: $VALIDATOR"

"$VALIDATOR" "$FIXTURES/valid.json" \
  || fail "valid evidence fixture was rejected"

for fixture in \
  missing-required-field.json \
  account-mismatch.json \
  failed-check.json \
  missing-approval.json \
  checksum-mismatch.json
do
  if "$VALIDATOR" "$FIXTURES/$fixture" >/dev/null 2>&1; then
    fail "invalid fixture was accepted: $fixture"
  fi
done

printf 'PASS: full-profile evidence validation fixtures\n'

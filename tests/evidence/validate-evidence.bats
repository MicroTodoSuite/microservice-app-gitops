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

# A Terraform stage that carries its Infracost estimate and state backup is
# valid (T145).
"$VALIDATOR" "$FIXTURES/terraform-stage-valid.json" \
  || fail "valid Terraform-stage fixture was rejected"

for fixture in \
  missing-required-field.json \
  account-mismatch.json \
  failed-check.json \
  missing-approval.json \
  checksum-mismatch.json \
  missing-infracost.json \
  missing-state-backup.json
do
  if "$VALIDATOR" "$FIXTURES/$fixture" >/dev/null 2>&1; then
    fail "invalid fixture was accepted: $fixture"
  fi
done

# Freshness (T145) is bound-configured: a stale bundle passes with no bound but
# must be rejected once EVIDENCE_MAX_AGE_DAYS is set.
if EVIDENCE_MAX_AGE_DAYS=1 "$VALIDATOR" "$FIXTURES/stale-timestamp.json" >/dev/null 2>&1; then
  fail "stale evidence was accepted under EVIDENCE_MAX_AGE_DAYS"
fi

printf 'PASS: full-profile evidence validation fixtures\n'

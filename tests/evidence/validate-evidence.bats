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

# The positive controls must be fresh whenever the suite runs, or they age past
# CI's EVIDENCE_MAX_AGE_DAYS and the suite goes red on a calendar date rather
# than on a change. Each is rendered with generatedAt set to the current time
# and validated under a freshness bound (CI's, or one day when none is set).
# Artifact paths resolve against the repository root, so a copy in a temporary
# directory validates exactly like the committed fixture.
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

fresh_fixture() {
  python3 -c '
import datetime, json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    evidence = json.load(handle)
evidence["generatedAt"] = datetime.datetime.now(datetime.timezone.utc).strftime(
    "%Y-%m-%dT%H:%M:%SZ"
)
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(evidence, handle, indent=2)
' "$FIXTURES/$1" "$WORKDIR/$1"
  printf '%s\n' "$WORKDIR/$1"
}

BOUND="${EVIDENCE_MAX_AGE_DAYS:-1}"

EVIDENCE_MAX_AGE_DAYS="$BOUND" "$VALIDATOR" "$(fresh_fixture valid.json)" \
  || fail "valid evidence fixture was rejected"

# A Terraform stage that carries its Infracost estimate and state backup is
# valid (T145).
EVIDENCE_MAX_AGE_DAYS="$BOUND" "$VALIDATOR" "$(fresh_fixture terraform-stage-valid.json)" \
  || fail "valid Terraform-stage fixture was rejected"

# Each invalid fixture is checked with no freshness bound, so it is rejected for
# its own defect and never merely for being old.
for fixture in \
  missing-required-field.json \
  account-mismatch.json \
  failed-check.json \
  missing-approval.json \
  checksum-mismatch.json \
  missing-infracost.json \
  missing-state-backup.json
do
  if env -u EVIDENCE_MAX_AGE_DAYS "$VALIDATOR" "$FIXTURES/$fixture" >/dev/null 2>&1; then
    fail "invalid fixture was accepted: $fixture"
  fi
done

# Freshness (T145) is bound-configured: a stale bundle passes with no bound but
# must be rejected once EVIDENCE_MAX_AGE_DAYS is set. Its fixed 2000-01-01
# timestamp is deliberate and stays committed; accepting it without a bound
# proves the rejection below is about age alone.
env -u EVIDENCE_MAX_AGE_DAYS "$VALIDATOR" "$FIXTURES/stale-timestamp.json" >/dev/null \
  || fail "stale-timestamp fixture was rejected for a reason other than its age"
if EVIDENCE_MAX_AGE_DAYS=1 "$VALIDATOR" "$FIXTURES/stale-timestamp.json" >/dev/null 2>&1; then
  fail "stale evidence was accepted under EVIDENCE_MAX_AGE_DAYS"
fi

printf 'PASS: full-profile evidence validation fixtures\n'

#!/usr/bin/env bash
# Stage dependency evaluation (spec 009, T032).
#
# The whole rollout rests on one rule: a stage may only start when every stage
# it depends on has actually finished. The contract is deliberately narrow —
# `accepted` is the ONLY decision that unlocks a dependent. `approved` does not,
# because approval covers the reviewed inputs, not the execution or its evidence.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EVALUATOR="$ROOT/scripts/managed/evaluate-stage-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

[[ -x "$EVALUATOR" ]] || { printf 'FAIL: evaluator is missing or not executable: %s\n' "$EVALUATOR" >&2; exit 1; }

# Writes a minimal stage record: <file> <stage-id> <decision> [dependency...]
stage() {
  local file="$1" id="$2" decision="$3"; shift 3
  local deps='[]'
  if [[ "$#" -gt 0 ]]; then
    deps="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"
  fi
  jq -n --arg id "$id" --arg decision "$decision" --argjson deps "$deps" \
    '{stageId: $id, decision: $decision, dependsOn: $deps}' > "$file"
}

# <description> <expected-exit> <candidate> [record...]
expect() {
  local description="$1" expected="$2" candidate="$3"; shift 3
  local actual=0
  "$EVALUATOR" --candidate "$candidate" "$@" >/dev/null 2>&1 || actual=$?
  [[ "$actual" -eq "$expected" ]] \
    || fail "$description (expected exit $expected, got $actual)"
}

mkdir -p "$TMP/records"
R="$TMP/records"

stage "$R/foundational.json" foundational-compatibility accepted
stage "$R/economical.json"   economical-baseline        accepted foundational-compatibility
stage "$R/dependent.json"    full-aws-environments      pending  economical-baseline

expect "an accepted dependency unlocks its dependent" 0 full-aws-environments "$R"/*.json

# Every non-accepted decision must hold the dependent closed. `approved` is the
# one that matters most: it is the decision most likely to be mistaken for done.
for decision in pending approved blocked rejected rolled-back; do
  stage "$R/economical.json" economical-baseline "$decision" foundational-compatibility
  expect "a '$decision' dependency must not unlock its dependent" 1 \
    full-aws-environments "$R"/*.json
done

# A transitive failure must propagate: the direct dependency is accepted, but
# the stage IT depends on is not.
stage "$R/foundational.json" foundational-compatibility blocked
stage "$R/economical.json"   economical-baseline        accepted foundational-compatibility
expect "a blocked transitive dependency must not unlock a dependent" 1 \
  full-aws-environments "$R"/*.json

# A dependency that was never recorded is missing evidence, not implicit success.
stage "$R/foundational.json" foundational-compatibility accepted
stage "$R/economical.json"   economical-baseline        accepted foundational-compatibility
stage "$R/dependent.json"    full-aws-environments      pending  economical-baseline never-recorded
expect "an unrecorded dependency must not unlock a dependent" 1 \
  full-aws-environments "$R"/*.json

# A cycle must be reported rather than silently recursed into.
stage "$R/dependent.json"    full-aws-environments      pending  economical-baseline
stage "$R/economical.json"   economical-baseline        accepted full-aws-environments
expect "a dependency cycle must be rejected" 1 full-aws-environments "$R"/*.json

# The candidate itself must exist.
stage "$R/economical.json" economical-baseline accepted foundational-compatibility
expect "an unknown candidate stage must be rejected" 1 no-such-stage "$R"/*.json

# Two records claiming the same stage id make the decision ambiguous.
stage "$R/dependent.json"  full-aws-environments pending economical-baseline
stage "$R/duplicate.json"  economical-baseline   blocked foundational-compatibility
expect "a duplicated stage id must be rejected" 1 full-aws-environments "$R"/*.json
rm -f "$R/duplicate.json"

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d stage-dependency violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: only an accepted dependency chain unlocks a dependent stage.\n'

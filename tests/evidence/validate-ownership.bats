#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEMA="$ROOT/evidence/templates/infrastructure-ownership.schema.json"
INVENTORY="$ROOT/evidence/templates/infrastructure-ownership.json"
DUPLICATE_FIXTURE="$ROOT/tests/evidence/fixtures/ownership-duplicate-owner.json"

validate_schema() {
  python3 - "$SCHEMA" "$1" <<'PY'
import json
import sys
from jsonschema import Draft202012Validator

with open(sys.argv[1], encoding="utf-8") as schema_file:
    schema = json.load(schema_file)
with open(sys.argv[2], encoding="utf-8") as inventory_file:
    inventory = json.load(inventory_file)
Draft202012Validator(schema).validate(inventory)
PY
}

reject_duplicate_owners() {
  local inventory="$1"
  jq -e '
    [.resources | group_by(.resourceId)[] | select(length > 1) |
      {resourceId: .[0].resourceId, owners: ([.[].ownerState] | unique)}] |
    length == 0
  ' "$inventory" >/dev/null
}

validate_schema "$INVENTORY"
reject_duplicate_owners "$INVENTORY"

validate_schema "$DUPLICATE_FIXTURE"
if reject_duplicate_owners "$DUPLICATE_FIXTURE"; then
  printf 'FAIL: duplicate ownership fixture was accepted\n' >&2
  exit 1
fi

printf 'PASS: infrastructure inventory has exactly one owner per resource ID\n'

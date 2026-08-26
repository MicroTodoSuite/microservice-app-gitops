#!/usr/bin/env bash
# Stage dependency evaluation (spec 009, T035).
#
# Answers one question: may this stage start yet?
#
# Per the stage-gate contract, `accepted` is the ONLY decision that unlocks a
# dependent. `approved` deliberately does not: approval covers the reviewed
# inputs, while acceptance means the execution happened and its evidence passed.
# Conflating the two is how a stage advances on the strength of a plan nobody
# actually applied.
#
# Read-only: reads stage records, writes nothing but its own report.
set -euo pipefail

CANDIDATE=""
OUTPUT=""
RECORDS=()

usage() {
  cat >&2 <<'EOF'
Usage: evaluate-stage-gate.sh --candidate STAGE_ID [--output FILE] RECORD...

  --candidate  Stage that wants to start.
  --output     Optional JSON report path.
  RECORD       Stage record files: {stageId, decision, dependsOn[]}.

Exit 0 only when every transitive dependency is `accepted`.
EOF
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --candidate) [[ "$#" -ge 2 ]] || fail "--candidate requires a value"; CANDIDATE="$2"; shift 2 ;;
    --output)    [[ "$#" -ge 2 ]] || fail "--output requires a value";    OUTPUT="$2";    shift 2 ;;
    --help|-h)   usage; exit 0 ;;
    -*)          usage; fail "unknown argument: $1" ;;
    *)           RECORDS+=("$1"); shift ;;
  esac
done

[[ -n "$CANDIDATE" ]] || { usage; fail "--candidate is required"; }
[[ "${#RECORDS[@]}" -gt 0 ]] || fail "at least one stage record is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

for record in "${RECORDS[@]}"; do
  [[ -f "$record" ]] || fail "stage record does not exist: $record"
done

python3 - "$CANDIDATE" "$OUTPUT" "${RECORDS[@]}" <<'PY'
import json
import pathlib
import sys

candidate, output = sys.argv[1], sys.argv[2]
record_paths = sys.argv[3:]

UNLOCKING_DECISION = "accepted"
KNOWN_DECISIONS = {
    "pending", "approved", "accepted", "blocked", "rejected", "rolled-back",
}


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


stages: dict[str, dict] = {}
for path in record_paths:
    try:
        record = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read stage record {path}: {exc}")

    for field in ("stageId", "decision"):
        if field not in record:
            fail(f"stage record {path} has no {field}")

    stage_id = record["stageId"]
    decision = record["decision"]
    if decision not in KNOWN_DECISIONS:
        fail(f"stage record {path} has an unknown decision '{decision}'")

    # Two records claiming one stage id make its decision ambiguous, and the
    # ambiguity would silently resolve to whichever file was read last.
    if stage_id in stages:
        fail(
            f"stage '{stage_id}' is declared twice: "
            f"{stages[stage_id]['path']} and {path}"
        )

    stages[stage_id] = {
        "decision": decision,
        "dependsOn": list(record.get("dependsOn") or []),
        "path": path,
    }

if candidate not in stages:
    fail(f"candidate stage '{candidate}' has no record")

blockers: list[dict] = []
visiting: list[str] = []
resolved: set[str] = set()


def visit(stage_id: str) -> None:
    if stage_id in visiting:
        cycle = " -> ".join(visiting[visiting.index(stage_id):] + [stage_id])
        fail(f"dependency cycle: {cycle}")
    if stage_id in resolved:
        return

    visiting.append(stage_id)
    for dependency in stages[stage_id]["dependsOn"]:
        # An unrecorded dependency is missing evidence, not implicit success.
        if dependency not in stages:
            blockers.append({
                "stage": dependency,
                "decision": None,
                "reason": "no evidence record exists for this dependency",
                "requiredBy": stage_id,
            })
            continue

        visit(dependency)
        decision = stages[dependency]["decision"]
        if decision != UNLOCKING_DECISION:
            blockers.append({
                "stage": dependency,
                "decision": decision,
                "reason": f"decision is '{decision}'; only '{UNLOCKING_DECISION}' unlocks a dependent",
                "requiredBy": stage_id,
            })

    visiting.pop()
    resolved.add(stage_id)


visit(candidate)

unlocked = not blockers
report = {
    "candidate": candidate,
    "unlocked": unlocked,
    "unlockingDecision": UNLOCKING_DECISION,
    "evaluatedStages": sorted(resolved),
    "blockers": blockers,
}

if output:
    pathlib.Path(output).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

if not unlocked:
    for blocker in blockers:
        print(
            f"FAIL: '{candidate}' is blocked by '{blocker['stage']}': {blocker['reason']}",
            file=sys.stderr,
        )
    raise SystemExit(1)

print(f"PASS: every dependency of '{candidate}' is {UNLOCKING_DECISION}.")
PY

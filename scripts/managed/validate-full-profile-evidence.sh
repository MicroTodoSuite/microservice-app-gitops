#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEMA="$ROOT/specs/009-full-platform-rollout/contracts/full-profile-evidence.schema.json"

usage() {
  printf 'Usage: %s <evidence.json>\n' "${0##*/}" >&2
}

if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

EVIDENCE="$1"
if [[ ! -f "$EVIDENCE" ]]; then
  printf 'FAIL: evidence file does not exist: %s\n' "$EVIDENCE" >&2
  exit 1
fi

if [[ ! -f "$SCHEMA" ]]; then
  printf 'FAIL: evidence schema does not exist: %s\n' "$SCHEMA" >&2
  exit 1
fi

python3 - "$ROOT" "$SCHEMA" "$EVIDENCE" <<'PY'
import hashlib
import json
import pathlib
import sys

try:
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError as exc:
    raise SystemExit(f"FAIL: python jsonschema is required for offline validation: {exc}")


root = pathlib.Path(sys.argv[1]).resolve()
schema_path = pathlib.Path(sys.argv[2]).resolve()
evidence_path = pathlib.Path(sys.argv[3]).resolve()


def load_json(path: pathlib.Path) -> object:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"FAIL: cannot read JSON {path}: {exc}") from exc


schema = load_json(schema_path)
evidence = load_json(evidence_path)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
errors = sorted(validator.iter_errors(evidence), key=lambda item: list(item.absolute_path))
if errors:
    for error in errors:
        location = "/".join(str(part) for part in error.absolute_path) or "<root>"
        print(f"FAIL: schema {location}: {error.message}", file=sys.stderr)
    raise SystemExit(1)


artifact_paths: dict[str, pathlib.Path] = {}
for artifact in evidence["artifacts"]:
    declared_path = artifact["path"]
    if declared_path in artifact_paths:
        raise SystemExit(f"FAIL: duplicate artifact path: {declared_path}")

    candidate = pathlib.Path(declared_path)
    resolved = candidate.resolve() if candidate.is_absolute() else (root / candidate).resolve()
    if not resolved.is_file():
        raise SystemExit(f"FAIL: artifact does not exist: {declared_path}")

    digest = hashlib.sha256()
    try:
        with resolved.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise SystemExit(f"FAIL: cannot hash artifact {declared_path}: {exc}") from exc

    actual = digest.hexdigest()
    expected = artifact["sha256"]
    if actual != expected:
        raise SystemExit(
            f"FAIL: checksum mismatch for {declared_path}: expected {expected}, got {actual}"
        )
    artifact_paths[declared_path] = resolved


referenced_paths: set[str] = set()
for check_name in ("baseline", "rollback", "postBaseline"):
    referenced_paths.update(evidence[check_name]["evidence"])
for requirement in evidence["requirements"].values():
    referenced_paths.update(requirement["evidence"])

missing_artifacts = sorted(referenced_paths.difference(artifact_paths))
if missing_artifacts:
    raise SystemExit(
        "FAIL: evidence references paths absent from artifacts: " + ", ".join(missing_artifacts)
    )


decision = evidence["decision"]
if decision in {"approved", "accepted"}:
    failed_artifacts = [
        artifact["path"] for artifact in evidence["artifacts"] if artifact["result"] == "fail"
    ]
    failed_checks = [
        name
        for name in ("baseline", "rollback", "postBaseline")
        if evidence[name]["result"] != "pass"
    ]
    failed_requirements = [
        requirement_id
        for requirement_id, result in evidence["requirements"].items()
        if result["result"] != "pass"
    ]
    if failed_artifacts or failed_checks or failed_requirements:
        raise SystemExit(
            "FAIL: approved/accepted decision contains a failed or blocked result: "
            f"artifacts={failed_artifacts}, checks={failed_checks}, "
            f"requirements={failed_requirements}"
        )

if decision == "accepted":
    approvals = [
        artifact
        for artifact in evidence["artifacts"]
        if artifact["kind"] == "approval"
        and artifact["result"] == "pass"
        and artifact.get("approvedBy")
    ]
    if not approvals:
        raise SystemExit("FAIL: accepted evidence requires a passing named approval artifact")

print(f"PASS: {evidence_path} conforms to schema and all artifact checksums match")
PY

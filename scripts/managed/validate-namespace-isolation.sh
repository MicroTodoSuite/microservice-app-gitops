#!/usr/bin/env bash
# Render and schema-validate the GitOps roots touched by feature 005.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KUBECONFORM_BIN="${KUBECONFORM_BIN:-kubeconform}"
readonly KUBECONFORM_VERSION="v0.7.0"
readonly KUBERNETES_SCHEMA_VERSION="1.35.0"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

for tool in kubectl python3 "$KUBECONFORM_BIN"; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'ERROR: required validation tool is unavailable: %s\n' "$tool" >&2
    exit 1
  }
done

observed_version="$("$KUBECONFORM_BIN" -v 2>&1)"
[[ "$observed_version" == "$KUBECONFORM_VERSION" ]] || {
  printf 'ERROR: kubeconform version mismatch: expected %s, observed %s\n' \
    "$KUBECONFORM_VERSION" "$observed_version" >&2
  exit 1
}

roots=(
  clusters/local-kind
  clusters/eks-dev
  environments/local
  environments/dev
  environments/staging
  environments/prod
  tests/fixtures/namespace-isolation/overlays/dev
  tests/fixtures/namespace-isolation/overlays/staging
  tests/fixtures/namespace-isolation/overlays/prod
  tests/fixtures/namespace-isolation/quota-violation
  tests/fixtures/namespace-isolation/foundation/dev
  tests/fixtures/namespace-isolation/foundation/staging
  tests/fixtures/namespace-isolation/foundation/prod
)

for kustomization in "$ROOT"/infrastructure/*/kustomization.yaml \
  "$ROOT"/apps/*/overlays/*/kustomization.yaml; do
  roots+=("${kustomization#"$ROOT/"}")
  roots[-1]="${roots[-1]%/kustomization.yaml}"
done

for root in "${roots[@]}"; do
  output="$TMP_DIR/$(tr '/ ' '__' <<<"$root").yaml"
  kubectl kustomize "$ROOT/$root" >"$output"
  "$KUBECONFORM_BIN" \
    -strict \
    -ignore-missing-schemas \
    -kubernetes-version "$KUBERNETES_SCHEMA_VERSION" \
    -summary \
    "$output"
  printf 'validated %s\n' "$root"
done

python3 - "$ROOT/specs/005-namespace-isolation/contracts/namespace-isolation-evidence.schema.json" <<'PY'
import json
import sys

from jsonschema import Draft202012Validator

with open(sys.argv[1], encoding="utf-8") as schema_file:
    schema = json.load(schema_file)
Draft202012Validator.check_schema(schema)
PY

printf 'PASS: feature-005 renders and evidence schema validate\n'

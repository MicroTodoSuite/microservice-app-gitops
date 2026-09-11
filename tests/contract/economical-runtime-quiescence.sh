#!/usr/bin/env bash
# Contract for the reviewed GitOps state used before an economical runtime
# teardown.  The root registration remains present while its generated
# workloads and platform add-ons are intentionally quiesced.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

render_kustomize() {
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

require_quiescent_patch() {
  local path="$1"
  [[ -f "$ROOT/$path" ]] || fail "missing quiescence patch: $path"
  [[ "$(rg -c '^  value: \[\]$' "$ROOT/$path" || true)" == 1 ]] \
    || fail "$path must replace its generator elements with exactly value: []"
  if rg -n '^    - ' "$ROOT/$path"; then
    fail "$path still activates generator elements"
  fi
}

require_quiescent_patch clusters/eks-dev/activation-apps.yaml
require_quiescent_patch clusters/eks-dev/activation-environments.yaml
require_quiescent_patch clusters/eks-dev/activation-infrastructure.yaml

[[ -f "$ROOT/clusters/eks-dev/root-app.yaml" ]] \
  || fail "the EKS root registration must remain present"
rg -q 'path: clusters/eks-dev$' "$ROOT/clusters/eks-dev/root-app.yaml" \
  || fail "the root registration path changed during quiescence"

render="$TMP_DIR/eks-dev.yaml"
render_kustomize "$ROOT/clusters/eks-dev" >"$render" \
  || fail "the quiescent EKS registration does not render"
for name in apps environments infrastructure; do
  rg -q -U "kind: ApplicationSet\\nmetadata:\\n  name: $name$" "$render" \
    || fail "rendered EKS registration is missing the $name ApplicationSet"
done

printf 'PASS: economical EKS GitOps activation is quiescent and its root remains registered.\n'

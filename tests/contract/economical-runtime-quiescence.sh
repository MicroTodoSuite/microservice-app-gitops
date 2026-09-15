#!/usr/bin/env bash
# Contract for the reviewed GitOps state used before an economical runtime
# teardown. The root registration remains present while generated workloads
# are quiesced. External Secrets remains temporarily active until dependent
# ExternalSecret finalizers complete.
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
  [[ "$(grep -Ec '^  value: \[\]$' "$ROOT/$path" || true)" == 1 ]] \
    || fail "$path must replace its generator elements with exactly value: []"
  if grep -En '^    - ' "$ROOT/$path"; then
    fail "$path still activates generator elements"
  fi
}

require_quiescent_patch clusters/eks-dev/activation-apps.yaml
require_quiescent_patch clusters/eks-dev/activation-environments.yaml

infrastructure_patch="$ROOT/clusters/eks-dev/activation-infrastructure.yaml"
[[ -f "$infrastructure_patch" ]] || fail "missing infrastructure cleanup patch"
[[ "$(grep -Ec '^    - name: external-secrets$' "$infrastructure_patch" || true)" == 1 ]] \
  || fail "External Secrets must be the sole controller active during dependent cleanup"
[[ "$(grep -Ec '^    - name:' "$infrastructure_patch" || true)" == 1 ]] \
  || fail "no controller except External Secrets may remain active during dependent cleanup"
grep -Eq '^      path: infrastructure/external-secrets$' "$infrastructure_patch" \
  || fail "the cleanup controller must use the reviewed External Secrets path"
grep -Eq '^      namespace: external-secrets$' "$infrastructure_patch" \
  || fail "the cleanup controller must use the external-secrets namespace"

[[ -f "$ROOT/clusters/eks-dev/root-app.yaml" ]] \
  || fail "the EKS root registration must remain present"
grep -Eq 'path: clusters/eks-dev$' "$ROOT/clusters/eks-dev/root-app.yaml" \
  || fail "the root registration path changed during quiescence"

render="$TMP_DIR/eks-dev.yaml"
render_kustomize "$ROOT/clusters/eks-dev" >"$render" \
  || fail "the quiescent EKS registration does not render"
for name in apps environments infrastructure; do
  awk -v expected="$name" '
    BEGIN { found = 0; in_application_set = 0; in_metadata = 0 }
    /^kind: ApplicationSet$/ { in_application_set = 1; in_metadata = 0; next }
    in_application_set && /^metadata:$/ { in_metadata = 1; next }
    in_application_set && in_metadata && $0 == "  name: " expected {
      found = 1
      in_application_set = 0
      in_metadata = 0
    }
    in_application_set && /^kind: / {
      in_application_set = 0
      in_metadata = 0
    }
    END { exit(found ? 0 : 1) }
  ' "$render" || fail "rendered EKS registration is missing the $name ApplicationSet"
done

printf 'PASS: economical EKS GitOps activation is in dependency-cleanup quiescence.\n'

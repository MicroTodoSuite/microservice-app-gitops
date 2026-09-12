#!/usr/bin/env bash
# Karpenter render test (spec 009, T086). Offline by design: no live
# cluster is touched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

command -v kubeconform >/dev/null || { printf 'FAIL: kubeconform is required\n' >&2; exit 1; }
if ! command -v kustomize >/dev/null && ! command -v kubectl >/dev/null; then
  printf 'FAIL: standalone kustomize or kubectl is required\n' >&2
  exit 1
fi

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

render() {
  if command -v kustomize >/dev/null; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

validate() {
  local label="$1" path="$2" out
  out="$(render "$path" | kubeconform -strict -ignore-missing-schemas -summary 2>&1)" || {
    fail "$label does not render or does not pass kubeconform: $out"
    return
  }
  grep -q 'Invalid: 0, Errors: 0' <<<"$out" \
    || fail "$label has invalid or errored resources: $out"
}

validate "infrastructure/karpenter" "infrastructure/karpenter"
validate "the disabled node-provisioning roots (standalone)" "infrastructure/karpenter/node-provisioning"

karpenter_render="$(render infrastructure/karpenter)"
grep -q 'image: public.ecr.aws/karpenter/controller:1.14.1@sha256:' <<<"$karpenter_render" \
  || fail "the karpenter controller image must be pinned by digest"

# node-provisioning/ must stay excluded from the activated resource set —
# that is what makes it disabled by construction.
main_resources_block="$(awk '/^resources:/{f=1;print;next} f&&/^[a-zA-Z]/{f=0} f' \
  "$ROOT/infrastructure/karpenter/kustomization.yaml")"
if grep -q 'node-provisioning' <<<"$main_resources_block"; then
  fail "infrastructure/karpenter/kustomization.yaml's resources list must not reference node-provisioning/ (that is what makes it disabled by default)"
fi

# The CHANGEME markers must still be there — if someone quietly filled in a
# plausible-looking value without review, this regresses silently otherwise.
grep -q 'CHANGEME-full-cluster-name' <<<"$karpenter_render" \
  || fail "settings.clusterName must remain the CHANGEME placeholder until a real cluster registration sets it"

node_provisioning_render="$(render infrastructure/karpenter/node-provisioning)"
for marker in CHANGEME-full-cluster-name CHANGEME-karpenter-node-role-name; do
  grep -q "$marker" <<<"$node_provisioning_render" \
    || fail "infrastructure/karpenter/node-provisioning must still carry the $marker placeholder"
done

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d karpenter violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: karpenter renders valid, the controller image is digest-pinned, node-provisioning stays disabled by construction, and every CHANGEME placeholder is still unresolved.\n'

#!/usr/bin/env bash
# Delivered-scaffold mesh render guard (spec 009, T069/T083, US3).
#
# Offline by design: renders Kustomize and asserts on the output, exactly like
# tests/contract/*.sh do for the economical profile. No live cluster is
# touched, so this runs identically in CI and on a laptop with only Docker.
#
# This file keeps the assertions the Istio + Kiali scaffold already satisfies,
# so validate-gitops blocks any regression of them today. The complete T069
# contract lives in tests/platform/mesh-policy.bats and stays red until T083
# delivers destination ingress, certificates, and the exact-flow policies.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$ROOT/tests/fixtures/full-topology-mesh/dev"

command -v kubeconform >/dev/null || { printf 'FAIL: kubeconform is required\n' >&2; exit 1; }
if ! command -v kustomize >/dev/null && ! command -v kubectl >/dev/null; then
  printf 'FAIL: standalone kustomize or kubectl is required\n' >&2
  exit 1
fi

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

# Standalone kustomize is checksum-locked in CI (full-profile-toolchain.lock);
# kubectl's embedded kustomize is the documented local fallback (CLAUDE.md).
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

# --- schema-level render checks --------------------------------------------
validate "infrastructure/istio" "infrastructure/istio"
validate "infrastructure/kiali" "infrastructure/kiali"
validate "the full-topology mesh fixture" "$FIXTURE"

# --- mesh-wide mTLS ---------------------------------------------------------
istio_render="$(render infrastructure/istio)"
if ! grep -q '^kind: PeerAuthentication' <<<"$istio_render"; then
  fail "infrastructure/istio must define a PeerAuthentication"
fi
peer_auth_block="$(grep -A6 '^kind: PeerAuthentication' <<<"$istio_render")"
grep -q 'mode: STRICT' <<<"$peer_auth_block" \
  || fail "the mesh-wide PeerAuthentication must set mtls.mode: STRICT"
grep -q 'namespace: istio-system' <<<"$peer_auth_block" \
  || fail "the mesh-wide PeerAuthentication must live in the istio-system root namespace"

# --- Kiali has no public ingress --------------------------------------------
kiali_render="$(render infrastructure/kiali)"
if grep -q '^kind: Ingress' <<<"$kiali_render"; then
  fail "infrastructure/kiali must not render an Ingress (constitution principle 9/10)"
fi
kiali_service_block="$(grep -A10 '^kind: Service$' <<<"$kiali_render")"
if grep -qE 'type: (LoadBalancer|NodePort)' <<<"$kiali_service_block"; then
  fail "the Kiali Service must not be publicly reachable (LoadBalancer/NodePort)"
fi

# --- namespace mesh injection ------------------------------------------------
fixture_render="$(render "$FIXTURE")"
namespace_block="$(grep -A3 '^kind: Namespace' <<<"$fixture_render")"
# The vendored injector honours either selector: istio-injection: enabled, or
# istio.io/rev: default when istio-injection is absent. mesh-policy.bats pins
# the revision label; this guard only keeps the namespace meshed.
grep -qE 'istio-injection: enabled|istio\.io/rev: default' <<<"$namespace_block" \
  || fail "a full-topology namespace must select the vendored Istio sidecar injector"

# --- default-deny at L7 (AuthorizationPolicy) and L3/L4 (NetworkPolicy) ----
grep -q '^kind: AuthorizationPolicy' <<<"$fixture_render" \
  || fail "environments/full must add a default-deny AuthorizationPolicy"
awk '/^kind: AuthorizationPolicy/{f=1} f&&/^spec: \{\}/{found=1} /^---/{f=0}END{exit !found}' <<<"$fixture_render" \
  || fail "the default-deny AuthorizationPolicy must have an empty spec (deny-all)"

for flow in allow-dns allow-istiod-discovery; do
  grep -q "name: $flow" <<<"$fixture_render" \
    || fail "environments/full must define the $flow required-flow NetworkPolicy"
done

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d mesh-policy violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: istio and kiali render valid, mesh-wide mTLS is STRICT, Kiali has no public ingress, and the full-topology namespace fixture carries default-deny AuthorizationPolicy/NetworkPolicy plus sidecar injection.\n'

#!/usr/bin/env bash
# Mesh/network render test (spec 009, T069, US3).
#
# Offline by design: renders Kustomize and asserts on the output, exactly like
# tests/contract/*.sh do for the economical profile. No live cluster is
# touched, so this runs identically in CI and on a laptop with only Docker.
#
# T069 also names two things this file intentionally does NOT assert, because
# nothing in this PR implements them yet:
#   - AWS-controller NLB versus Terraform-owned static-public-IP Azure ingress
#     wiring — depends on infrastructure/aws-load-balancer-controller/, which
#     needs a real Terraform-output IRSA role ARN that does not exist until
#     Phase 4 (spec 009 T057-T062) applies a full-profile EKS cluster.
#   - Destination HTTP-01 versus production DNS-01 certificate separation —
#     depends on a cert-manager Issuer design decision not yet recorded
#     anywhere in this repository.
# Both remain unchecked in tasks.md; see the PR body for the same note.
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
grep -q 'istio-injection: enabled' <<<"$namespace_block" \
  || fail "a full-topology namespace must carry istio-injection: enabled"

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

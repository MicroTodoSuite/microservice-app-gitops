#!/usr/bin/env bash
# Mesh/network render test (spec 009, T069, US3).
#
# Offline by design: renders Kustomize and asserts on the output, exactly like
# tests/contract/*.sh do for the economical profile. No live cluster is
# touched, so this runs identically in CI and on a laptop with only Docker.
#
# This is the complete T069 contract. It stays red until T083 delivers the
# destination ingress, certificate, and exact-flow roots, so validate-gitops
# runs tests/platform/mesh-policy-scaffold.bats instead: the subset the Istio +
# Kiali scaffold already satisfies. Promote this file into that CI step, and
# delete the scaffold guard, in the pull request that makes it pass.
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

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "required file is missing: $1"
}

# Standalone kustomize is checksum-locked in CI (full-profile-toolchain.lock);
# kubectl's embedded kustomize is the documented local fallback (CLAUDE.md).
render() {
  if command -v kustomize >/dev/null; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

document() {
  awk -v kind="$1" -v name="$2" '
    function flush() {
      if (doc ~ ("\nkind: " kind "\n") && doc ~ ("\n  name: " name "\n")) printf "%s", doc
      doc = "\n"
    }
    BEGIN { doc = "\n" }
    /^---$/ { flush(); next }
    { doc = doc $0 "\n" }
    END { flush() }
  '
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

# --- namespace revision pin ---------------------------------------------------
fixture_render="$(render "$FIXTURE")"
namespace_block="$(document Namespace microtodo-full-dev <<<"$fixture_render")"
grep -q 'istio.io/rev: default' <<<"$namespace_block" \
  || fail "a full-topology namespace must pin the installed Istio revision with istio.io/rev: default"
if grep -q 'istio-injection:' <<<"$namespace_block"; then
  fail "a full-topology namespace must use the revision label, not the unversioned istio-injection label"
fi

# --- default-deny at L7 (AuthorizationPolicy) and L3/L4 (NetworkPolicy) ----
grep -q '^kind: AuthorizationPolicy' <<<"$fixture_render" \
  || fail "environments/full must add a default-deny AuthorizationPolicy"
awk '/^kind: AuthorizationPolicy/{f=1} f&&/^spec: \{\}/{found=1} /^---/{f=0}END{exit !found}' <<<"$fixture_render" \
  || fail "the default-deny AuthorizationPolicy must have an empty spec (deny-all)"

network_deny="$(document NetworkPolicy default-deny <<<"$fixture_render")"
[[ -n "$network_deny" ]] \
  || fail "environments/full must add a default-deny NetworkPolicy"
for direction in Ingress Egress; do
  grep -q -- "- $direction" <<<"$network_deny" \
    || fail "the default-deny NetworkPolicy must cover $direction"
done

for flow in \
  allow-dns \
  allow-ingress-gateway \
  allow-service-dependencies \
  allow-redis \
  allow-telemetry \
  allow-controller-webhook \
  allow-cloud-api; do
  grep -q "name: $flow" <<<"$fixture_render" \
    || fail "environments/full must define the $flow required-flow NetworkPolicy"
done

# The development fixture may name its own environment and shared platform
# namespaces, but never a peer business environment.
if grep -qE 'microtodo-(staging|prod)' <<<"$fixture_render"; then
  fail "the full-dev mesh policy must expose no cross-environment path"
fi

# The four HTTP services carry the active resilience policy. The Redis
# subscriber deliberately has no HTTP traffic object, but its Redis flow is
# covered by NetworkPolicy above.
for service in auth-api todos-api users-api frontend; do
  service_render="$(render "apps/$service/profiles/full/topology")"
  rule="$(document DestinationRule "$service" <<<"$service_render")"
  route="$(document VirtualService "$service" <<<"$service_render")"
  for field in 'mode: ISTIO_MUTUAL' 'connectionPool:' 'outlierDetection:'; do
    grep -qF -- "$field" <<<"$rule" \
      || fail "$service DestinationRule must declare $field"
  done
  for field in 'retries:' 'timeout:'; do
    grep -qF -- "$field" <<<"$route" \
      || fail "$service VirtualService must declare $field"
  done
done

# Ingress is cloud-specific. EKS uses the AWS controller to provision an NLB;
# AKS binds the existing Terraform-owned Standard public IP by exact name and
# resource group. Placeholder values are not an activatable contract.
for destination in eks-full-dev eks-full-staging eks-full-prod; do
  path="infrastructure/profiles/full/istio/destinations/$destination"
  require_file "$path/kustomization.yaml"
  [[ -f "$ROOT/$path/kustomization.yaml" ]] || continue
  ingress="$(render "$path" | document Service istio-ingressgateway)"
  grep -qF 'service.beta.kubernetes.io/aws-load-balancer-type: external' <<<"$ingress" \
    || fail "$destination Istio ingress must be owned by AWS Load Balancer Controller"
  grep -qF 'service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip' <<<"$ingress" \
    || fail "$destination Istio ingress must use NLB IP targets"
  grep -qF 'service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing' <<<"$ingress" \
    || fail "$destination Istio ingress must use the reviewed public NLB scheme"
done

AZURE_ISTIO=infrastructure/profiles/full/istio/destinations/aks-dr
require_file "$AZURE_ISTIO/kustomization.yaml"
if [[ -f "$ROOT/$AZURE_ISTIO/kustomization.yaml" ]]; then
  azure_ingress="$(render "$AZURE_ISTIO" | document Service istio-ingressgateway)"
  grep -qF 'service.beta.kubernetes.io/azure-pip-name:' <<<"$azure_ingress" \
    || fail "AKS Istio ingress must bind the Terraform-owned public IP by name"
  grep -qF 'service.beta.kubernetes.io/azure-load-balancer-resource-group:' <<<"$azure_ingress" \
    || fail "AKS Istio ingress must bind the Terraform-owned ingress resource group"
  if grep -qE 'pending|CHANGEME' <<<"$azure_ingress"; then
    fail "AKS Istio ingress must not contain an unverified static-IP placeholder"
  fi
fi

# Each destination has a separate HTTP-01 issuer/certificate. The common
# production hostname is a distinct DNS-01 component and must not create or
# depend on the shared application record.
for destination in eks-full-dev eks-full-staging eks-full-prod aks-dr; do
  cert_root="infrastructure/profiles/full/cert-manager/destinations/$destination"
  istio_root="infrastructure/profiles/full/istio/destinations/$destination"
  require_file "$cert_root/kustomization.yaml"
  require_file "$istio_root/kustomization.yaml"
  [[ -f "$ROOT/$cert_root/kustomization.yaml" && -f "$ROOT/$istio_root/kustomization.yaml" ]] || continue
  certs="$(render "$cert_root")"
  ingress_policy="$(render "$istio_root")"
  grep -q '^kind: ClusterIssuer$' <<<"$certs" \
    || fail "$destination must render its HTTP-01 ClusterIssuer"
  grep -q 'http01:' <<<"$certs" \
    || fail "$destination certificate must use HTTP-01"
  grep -q '^kind: Certificate$' <<<"$certs" \
    || fail "$destination must render its trusted ingress Certificate"
  gateway="$(document Gateway microtodosuite-ingress <<<"$ingress_policy")"
  [[ -n "$gateway" ]] || fail "$destination must render Gateway microtodosuite-ingress"
  grep -q 'credentialName:' <<<"$gateway" \
    || fail "$destination Gateway must terminate TLS with the cert-manager Secret"
  grep -q 'httpsRedirect: true' <<<"$gateway" \
    || fail "$destination Gateway must redirect plaintext by default"
  acme="$(document VirtualService acme-http01-exception <<<"$ingress_policy")"
  grep -qF 'prefix: /.well-known/acme-challenge/' <<<"$acme" \
    || fail "$destination plaintext exception must be limited to the ACME HTTP-01 path"
done

COMMON_CERT=infrastructure/profiles/full/cert-manager/components/common-certificate
require_file "$COMMON_CERT/kustomization.yaml"
if [[ -f "$ROOT/$COMMON_CERT/kustomization.yaml" ]]; then
  common="$(render "$COMMON_CERT")"
  grep -q 'dns01:' <<<"$common" \
    || fail "the common production certificate must use DNS-01"
  grep -qF -- '- app.microtodosuite.online' <<<"$common" \
    || fail "the DNS-01 certificate must cover only the common production hostname"
  if grep -q 'http01:' <<<"$common"; then
    fail "the common production certificate must not use destination HTTP-01"
  fi
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d mesh-policy violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: full namespaces pin the Istio revision; STRICT mTLS, exact default-deny/allow flows, resilient service routing, cloud-specific ingress, separated HTTP-01/DNS-01 certificates, trusted TLS, and non-public Kiali all render without cross-environment paths.\n'

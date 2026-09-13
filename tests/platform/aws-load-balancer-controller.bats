#!/usr/bin/env bash
# AWS Load Balancer Controller render test (spec 009, T083 — the AWS LB
# Controller third, distinct from tests/platform/mesh-policy.bats which
# covers the Istio/Kiali two-thirds). Offline by design: no live cluster is
# touched.
set -euo pipefail

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

out="$(render infrastructure/aws-load-balancer-controller | kubeconform -strict -ignore-missing-schemas -summary 2>&1)" || {
  fail "infrastructure/aws-load-balancer-controller does not render or does not pass kubeconform: $out"
}
grep -q 'Invalid: 0, Errors: 0' <<<"$out" \
  || fail "infrastructure/aws-load-balancer-controller has invalid or errored resources: $out"

render_out="$(render infrastructure/aws-load-balancer-controller)"

# Digest-pinned, not a mutable tag.
grep -q 'image: public.ecr.aws/eks/aws-load-balancer-controller@sha256:' <<<"$render_out" \
  || fail "the controller image must be pinned by digest"

# No invented IRSA role ARN: the ServiceAccount must carry no
# eks.amazonaws.com/role-arn annotation until a real one exists (Phase 4).
sa_block="$(grep -A15 '^kind: ServiceAccount$' <<<"$render_out")"
if grep -q 'eks.amazonaws.com/role-arn' <<<"$sa_block"; then
  fail "the aws-load-balancer-controller ServiceAccount must not carry an IRSA role-arn annotation until a real Terraform output exists"
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d aws-load-balancer-controller violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: aws-load-balancer-controller renders valid, image is digest-pinned, and no IRSA ARN was invented.\n'

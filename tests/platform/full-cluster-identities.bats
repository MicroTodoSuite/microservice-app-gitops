#!/usr/bin/env bash
# Destination-scoped identity and controller settings contract (spec 009 T083/T086).
# Offline by design: it renders Git only and never contacts AWS or Kubernetes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KUSTOMIZE_BIN="${KUSTOMIZE_BIN:-kustomize}"

command -v "$KUSTOMIZE_BIN" >/dev/null || {
  printf 'FAIL: kustomize is required\n' >&2
  exit 1
}
command -v kubeconform >/dev/null || {
  printf 'FAIL: kubeconform is required\n' >&2
  exit 1
}

failures=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

render_checked() {
  local label="$1" path="$2" output="$3" validation
  if [[ ! -f "$path/kustomization.yaml" ]]; then
    fail "$label overlay is missing: $path/kustomization.yaml"
    return 1
  fi
  if ! "$KUSTOMIZE_BIN" build "$path" >"$output"; then
    fail "$label overlay does not render"
    return 1
  fi
  validation="$(kubeconform -strict -ignore-missing-schemas -summary <"$output" 2>&1)" || {
    fail "$label overlay does not pass kubeconform: $validation"
    return 1
  }
  grep -q 'Invalid: 0, Errors: 0' <<<"$validation" || {
    fail "$label overlay has invalid or errored resources: $validation"
    return 1
  }
}

destinations=(eks-full-dev eks-full-staging eks-full-prod)
environments=(fdev fstg fprd)
logical_environments=(dev staging prod)
codes=(dev stg prd)

for index in "${!destinations[@]}"; do
  destination="${destinations[$index]}"
  environment="${environments[$index]}"
  logical_environment="${logical_environments[$index]}"
  code="${codes[$index]}"
  cluster="lex-mts-${environment}-eks-main"
  prefix="lex-mts-${environment}"
  combined="$(mktemp)"

  overlays=(
    "environment|environments/profiles/full/destinations/$destination"
    "karpenter|infrastructure/profiles/full/karpenter/destinations/$destination"
    "aws-load-balancer-controller|infrastructure/profiles/full/aws-load-balancer-controller/destinations/$destination"
    "prometheus|infrastructure/profiles/full/prometheus/destinations/$destination"
    "falco|infrastructure/profiles/full/falco/destinations/$destination"
    "trivy-operator|infrastructure/profiles/full/trivy-operator/destinations/$destination"
    "kyverno|infrastructure/profiles/full/kyverno/destinations/$destination"
  )

  for overlay in "${overlays[@]}"; do
    IFS='|' read -r capability relative_path <<<"$overlay"
    rendered="$(mktemp)"
    if render_checked "$destination/$capability" "$ROOT/$relative_path" "$rendered"; then
      cat "$rendered" >>"$combined"
    fi
    rm -f "$rendered"
  done

  expected_literals=(
    "$cluster"
    "$prefix-vpc-main"
    "$prefix-sqs-karpenter"
    "$prefix-role-node"
    "arn:aws:iam::575172595729:role/$prefix-role-jwt$code"
    "$prefix-sm-jwt$code"
    "arn:aws:iam::575172595729:role/$prefix-role-obssecret"
    "$prefix-sm-slackobs"
    "arn:aws:iam::575172595729:role/$prefix-role-secsecret"
    "$prefix-sm-slacksec"
    "arn:aws:iam::575172595729:role/$prefix-role-trivyecr"
    "arn:aws:iam::575172595729:role/$prefix-role-kyvernoecr"
    "arn:aws:iam::575172595729:role/$prefix-role-karpenter"
    "arn:aws:iam::575172595729:role/$prefix-role-lbcontrol"
  )
  for literal in "${expected_literals[@]}"; do
    grep -Fq "$literal" "$combined" \
      || fail "$destination render is missing exact rebuilt value $literal"
  done

  grep -Fq -- "--cluster-name=$cluster" "$combined" \
    || fail "$destination load balancer controller must receive its exact cluster name"
  grep -Fq -- '--aws-region=us-east-1' "$combined" \
    || fail "$destination load balancer controller must receive the explicit Region"
  grep -Fq -- "--aws-vpc-tags=Name=$prefix-vpc-main" "$combined" \
    || fail "$destination load balancer controller must discover its VPC by exact Name tag"
  if grep -Fq -- '--aws-vpc-id=' "$combined"; then
    fail "$destination load balancer controller must not pin a VPC ID that does not exist yet"
  fi

  nodepool="$(awk 'BEGIN { RS="---" } /kind: NodePool/ { print }' "$combined")"
  [[ "$(grep -c '^kind: NodePool$' "$combined")" -eq 1 ]] \
    || fail "$destination must render exactly one NodePool"
  grep -Fqx '    cpu: "8"' <<<"$nodepool" \
    || fail "$destination NodePool must enforce the 8-vCPU Spot ceiling"

  for other_environment in fdev fstg fprd; do
    if [[ "$other_environment" != "$environment" ]] \
        && grep -Fq "lex-mts-$other_environment-" "$combined"; then
      fail "$destination render leaks the $other_environment destination identity"
    fi
  done

  if grep -Eq 'CHANGEME|microtodosuite-full-(dev|prod)|microtodosuite-demo-full|916491575487|arn:aws:iam::575172595729:role/lex-mts-eco-' "$combined"; then
    fail "$destination render contains a placeholder, retired full-cluster value, retired account, or economical role ARN"
  fi

  rm -f "$combined"
done

# Existing economical composition remains protected by its checked-in golden renders.
if ! KUSTOMIZE_BIN="$KUSTOMIZE_BIN" "$ROOT/tests/profiles/validate-profile-routing.bats"; then
  fail "the economical golden render changed"
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d full-cluster identity violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: every full destination renders exact rebuilt identities and controller settings with an 8-vCPU ceiling, and economical golden renders are unchanged.\n'

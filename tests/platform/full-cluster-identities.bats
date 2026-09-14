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

destinations=(eks-full-dev eks-full-staging eks-full-prod)
environments=(fdev fstg fprd)
codes=(dev stg prd)
retired_account="916491575""487"

for index in "${!destinations[@]}"; do
  destination="${destinations[$index]}"
  environment="${environments[$index]}"
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

  karpenter_deployment="$(document Deployment karpenter <"$combined")"
  karpenter_service_account="$(document ServiceAccount karpenter <"$combined")"
  load_balancer_deployment="$(document Deployment aws-load-balancer-controller <"$combined")"
  load_balancer_service_account="$(document ServiceAccount aws-load-balancer-controller <"$combined")"
  ec2_node_class="$(document EC2NodeClass full-profile-spot <"$combined")"
  nodepool="$(document NodePool full-profile-spot <"$combined")"

  grep -Fq "eks.amazonaws.com/role-arn: arn:aws:iam::575172595729:role/$prefix-role-karpenter" <<<"$karpenter_service_account" \
    || fail "$destination Karpenter ServiceAccount must use its exact IRSA role"
  for setting in \
    "CLUSTER_NAME|$cluster" \
    "INTERRUPTION_QUEUE|$prefix-sqs-karpenter" \
    'AWS_REGION|us-east-1'; do
    name="${setting%%|*}"
    value="${setting#*|}"
    grep -A1 -F "name: $name" <<<"$karpenter_deployment" | grep -Fqx "          value: $value" \
      || fail "$destination Karpenter Deployment must set $name to $value"
  done
  grep -Fqx "  role: $prefix-role-node" <<<"$ec2_node_class" \
    || fail "$destination EC2NodeClass must use $prefix-role-node"
  [[ "$(grep -Fc "karpenter.sh/discovery: $cluster" <<<"$ec2_node_class")" -eq 2 ]] \
    || fail "$destination EC2NodeClass must select both security groups and subnets for $cluster"

  grep -Fq "eks.amazonaws.com/role-arn: arn:aws:iam::575172595729:role/$prefix-role-lbcontrol" <<<"$load_balancer_service_account" \
    || fail "$destination load balancer ServiceAccount must use its exact IRSA role"
  grep -Fq -- "--cluster-name=$cluster" <<<"$load_balancer_deployment" \
    || fail "$destination load balancer controller must receive its exact cluster name"
  grep -Fq -- '--aws-region=us-east-1' <<<"$load_balancer_deployment" \
    || fail "$destination load balancer controller must receive the explicit Region"
  grep -Fq -- "--aws-vpc-tags=Name=$prefix-vpc-main" <<<"$load_balancer_deployment" \
    || fail "$destination load balancer controller must discover its VPC by exact Name tag"
  if grep -Fq -- '--aws-vpc-id=' <<<"$load_balancer_deployment"; then
    fail "$destination load balancer controller must not pin a VPC ID that does not exist yet"
  fi

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

  if grep -Eq "CHANGEME|microtodosuite-full-(dev|prod)|microtodosuite-demo-full|$retired_account|arn:aws:iam::575172595729:role/lex-mts-eco-" "$combined"; then
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

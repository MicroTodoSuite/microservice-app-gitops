#!/usr/bin/env bash
# Rebuilt full-cluster root contract (spec 009 T050/T063/T065).
# Offline by design: it renders Git only and never contacts a cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

command -v kustomize >/dev/null || {
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

roots=(eks-full-dev eks-full-staging eks-full-prod)
environments=(fdev fstg fprd)
logical_environments=(dev staging prod)
retired_account='916491''575487'

for index in "${!roots[@]}"; do
  root="${roots[$index]}"
  environment="${environments[$index]}"
  logical_environment="${logical_environments[$index]}"
  cluster="lex-mts-${environment}-eks-main"
  directory="$ROOT/clusters/$root"
  render_file="$(mktemp)"

  kustomize build "$directory" >"$render_file" || {
    fail "$root does not render"
    continue
  }

  validation="$(kubeconform -strict -ignore-missing-schemas -summary <"$render_file" 2>&1)" || {
    fail "$root does not pass kubeconform: $validation"
  }
  grep -q 'Invalid: 0, Errors: 0' <<<"$validation" \
    || fail "$root has invalid or errored resources: $validation"

  grep -Fqx "  physicalCluster: $cluster" "$directory/registration.yaml" \
    || fail "$root registration must name $cluster"
  grep -Fqx "  physicalCluster: $cluster" "$directory/planned-inventory.yaml" \
    || fail "$root planned inventory must name $cluster"
  grep -Fqx "    microtodosuite.io/physical-cluster: $cluster" "$directory/planned-inventory.yaml" \
    || fail "$root planned inventory annotation must name $cluster"

  grep -Fqx '    server: https://kubernetes.default.svc' "$directory/root-app.yaml" \
    || fail "$root root Application must target only the in-cluster API"
  grep -Fqx "    path: clusters/$root" "$directory/root-app.yaml" \
    || fail "$root root Application must target its own Git root"

  for activation in activation-apps.yaml activation-environments.yaml activation-infrastructure.yaml; do
    grep -Eq '^[[:space:]]*value: \[\][[:space:]]*$' "$directory/$activation" \
      || fail "$root/$activation must keep its activation list empty"
  done

  [[ "$(grep -c 'elements: \[\]' "$render_file")" -eq 3 ]] \
    || fail "$root must render three empty ApplicationSet activation lists"

  grep -Fqx "      path: environments/profiles/full/destinations/$root" "$directory/planned-inventory.yaml" \
    || fail "$root must plan the destination-scoped $logical_environment environment overlay"
  for capability in karpenter aws-load-balancer-controller prometheus kyverno falco trivy-operator; do
    grep -Fqx "      path: infrastructure/profiles/full/$capability/destinations/$root" "$directory/planned-inventory.yaml" \
      || fail "$root must plan the destination-scoped $capability overlay"
  done

  if grep -Eq "CHANGEME|microtodosuite-full-(dev|prod)|microtodosuite-demo-full|${retired_account}|lex-mts-eco-" \
      "$directory/registration.yaml" "$directory/planned-inventory.yaml" "$directory/root-app.yaml"; then
    fail "$root still carries a placeholder, retired full-cluster name, retired account, or economical identity"
  fi

  rm -f "$render_file"
done

bootstrap_contract="$ROOT/tests/bootstrap/managed-cluster-bootstrap.bats"
grep -Fq -- '--cluster "lex-mts-fdev-eks-main"' "$bootstrap_contract" \
  || fail "the managed bootstrap contract must exercise the rebuilt fdev cluster name"
if grep -REq 'microtodosuite-full-(dev|prod)|microtodosuite-demo-full' \
    "$bootstrap_contract" "$ROOT/tests/bootstrap/fixtures"; then
  fail "managed bootstrap fixtures must not retain retired full-cluster names"
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d rebuilt full-cluster root violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: all rebuilt full-cluster roots use exact physical names, remain in-cluster and inactive, and plan only destination-scoped identity overlays.\n'

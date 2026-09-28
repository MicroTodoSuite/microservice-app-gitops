#!/usr/bin/env bash
# A pod receives its IRSA role once, when it is created: the EKS pod identity
# webhook copies the ServiceAccount's eks.amazonaws.com/role-arn into the pod as
# AWS_ROLE_ARN. Changing only the ServiceAccount annotation, as
# scripts/set-aws-account.sh does, leaves every running pod on the old role.
# After the 2026-09-28 account repoint the load balancer controller kept
# crash-looping on the lex-mts-eco-role-lbcontrol role of the retired account.
#
# This contract renders every infrastructure root the economical cluster
# activates and requires each Deployment whose ServiceAccount carries an IRSA
# role to carry the declared account in its pod template, as the annotation
# microtodosuite.io/aws-account. The account then lives in the pod template, so
# the next account change rolls these pods out through Git.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KUSTOMIZE_BIN="${KUSTOMIZE_BIN:-kustomize}"
ACTIVATION="clusters/eks-dev/activation-infrastructure.yaml"
ANNOTATION="microtodosuite.io/aws-account"

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

command -v yq >/dev/null || die "yq is required"
command -v "$KUSTOMIZE_BIN" >/dev/null || die "kustomize is required"

account="$(sed -n 's/^AWS_ACCOUNT_ID=\([0-9]*\)[[:space:]]*$/\1/p' "$ROOT/config/aws-account.env")"
[[ "$account" =~ ^[0-9]{12}$ ]] || die "config/aws-account.env does not declare the AWS account"

mapfile -t roots < <(yq -r '.[0].value[].path' "$ROOT/$ACTIVATION")
((${#roots[@]} > 0)) || die "$ACTIVATION activates no infrastructure root"

checked=0
for root in "${roots[@]}"; do
  if ! rendered="$("$KUSTOMIZE_BIN" build "$ROOT/$root" 2>&1)"; then
    fail "$root does not render: ${rendered%%$'\n'*}"
    continue
  fi

  # namespace/name of every ServiceAccount that carries an IRSA role.
  mapfile -t irsa < <(yq -r 'select(.kind == "ServiceAccount" and .metadata.annotations["eks.amazonaws.com/role-arn"] != null)
    | (.metadata.namespace // "") + "/" + .metadata.name' <<<"$rendered")
  ((${#irsa[@]} > 0)) || continue

  while IFS='|' read -r ns name sa value; do
    [[ -n "$name" ]] || continue
    key="$ns/${sa:-default}"
    grep -Fxq -- "$key" <<<"$(printf '%s\n' "${irsa[@]}")" || continue
    checked=$((checked + 1))
    if [[ -z "$value" ]]; then
      fail "$root: Deployment $ns/$name runs as IRSA ServiceAccount $key but its pod template has no $ANNOTATION annotation"
    elif [[ "$value" != "$account" ]]; then
      fail "$root: Deployment $ns/$name pod template says $ANNOTATION=$value, not the declared account $account"
    fi
  done < <(yq -r 'select(.kind == "Deployment")
    | [(.metadata.namespace // ""), .metadata.name, (.spec.template.spec.serviceAccountName // ""),
       (.spec.template.metadata.annotations["microtodosuite.io/aws-account"] // "")] | join("|")' <<<"$rendered")
done

((checked > 0)) || die "no Deployment in the activated roots runs as an IRSA ServiceAccount; the contract would pass vacuously"

if ((failures > 0)); then
  printf 'FAIL: %d IRSA Deployment(s) would keep a role from another account after an account change\n' "$failures" >&2
  exit 1
fi
printf 'PASS: %d IRSA Deployment(s) carry account %s in their pod template.\n' "$checked" "$account"

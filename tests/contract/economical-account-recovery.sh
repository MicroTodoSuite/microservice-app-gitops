#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The account is declared once, in config/aws-account.env; read it, never repeat it.
EXPECTED_ACCOUNT="$(sed -n 's/^AWS_ACCOUNT_ID=\([0-9]*\)[[:space:]]*$/\1/p' "$ROOT/config/aws-account.env")"
RETIRED_ACCOUNTS="$(sed -n 's/^RETIRED_AWS_ACCOUNT_IDS="\([0-9 ]*\)"[[:space:]]*$/\1/p' "$ROOT/config/aws-account.env")"
[[ "$EXPECTED_ACCOUNT" =~ ^[0-9]{12}$ ]] || fail "config/aws-account.env does not declare the AWS account"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_account() {
  local path="$1"
  grep -Fq "$EXPECTED_ACCOUNT" "$ROOT/$path" \
    || fail "$path does not reference the declared account $EXPECTED_ACCOUNT"
  local retired
  for retired in $RETIRED_ACCOUNTS; do
    if grep -Fq "$retired" "$ROOT/$path"; then
      fail "$path still references retired account $retired"
    fi
  done
}

for service in auth-api frontend log-message-processor todos-api users-api; do
  for environment in dev staging prod demo; do
    require_account "apps/$service/profiles/economical/overlays/$environment/kustomization.yaml"
  done
done

for path in \
  environments/dev/kustomization.yaml \
  environments/staging/kustomization.yaml \
  environments/prod/kustomization.yaml \
  environments/demo/kustomization.yaml \
  infrastructure/falco/falcosidekick-slack-secret.yaml \
  infrastructure/kyverno/kustomization.yaml \
  infrastructure/kyverno/policies.yaml \
  infrastructure/prometheus/alertmanager-config.yaml \
  docs/ci-ecr-oidc-role.md \
  docs/service-delivery.md \
  specs/005-namespace-isolation/quickstart.md \
  specs/006-observability-platform-foundation/quickstart.md \
  tests/bootstrap/managed-cluster-bootstrap.bats \
  tests/contract/namespace-isolation-evidence.sh \
  tests/contract/namespace-isolation.sh \
  tests/contract/platform-addons.sh \
  tests/evidence/economical-baseline.bats \
  tests/evidence/fixtures/economical/degraded/aws-identity.json \
  tests/evidence/fixtures/economical/healthy/aws-identity.json \
  tests/evidence/fixtures/economical/revision-mismatch/aws-identity.json \
  tests/evidence/fixtures/economical/unreachable/aws-identity.json
do
  require_account "$path"
done

for fixture in \
  already-bootstrapped \
  checksum-mismatch \
  third-mutation \
  unmerged-revision \
  valid \
  wrong-cluster
do
  account="$(tr -d '[:space:]' <"$ROOT/tests/bootstrap/fixtures/$fixture/account.txt")"
  [[ "$account" == "$EXPECTED_ACCOUNT" ]] \
    || fail "bootstrap fixture $fixture targets account $account"
done

printf 'PASS: active economical GitOps paths target replacement account %s.\n' \
  "$EXPECTED_ACCOUNT"

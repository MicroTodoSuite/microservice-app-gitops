#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPECTED_ACCOUNT="575172595729"
RETIRED_ACCOUNT="916491575487"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_account() {
  local path="$1"
  grep -Fq "$EXPECTED_ACCOUNT" "$ROOT/$path" \
    || fail "$path does not reference replacement account $EXPECTED_ACCOUNT"
  if grep -Fq "$RETIRED_ACCOUNT" "$ROOT/$path"; then
    fail "$path still references retired account $RETIRED_ACCOUNT"
  fi
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
  tests/contract/platform-addons.sh
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

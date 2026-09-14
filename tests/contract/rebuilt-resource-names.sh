#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPECTED_ACCOUNT="$(sed -n 's/^AWS_ACCOUNT_ID=\([0-9]*\)[[:space:]]*$/\1/p' "$ROOT/config/aws-account.env")"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ "$EXPECTED_ACCOUNT" =~ ^[0-9]{12}$ ]] \
  || fail "config/aws-account.env does not declare one AWS account"

# Specifications and captured evidence retain the names that were true when
# they were written. This scan covers current desired state, operator guidance,
# test expectations, and the reusable ownership template.
scan_paths=(apps clusters docs environments infrastructure tests evidence/templates)
retired_names=(
  microtodosuite-dev
  microtodosuite-github-ecr-publisher
  microtodosuite-dev-jwt-reader
  microtodosuite-staging-jwt-reader
  microtodosuite-prod-jwt-reader
  microtodosuite-demo-jwt-reader
  microtodosuite/dev/auth-api-secrets
  microtodosuite/staging/auth-api-secrets
  microtodosuite/prod/auth-api-secrets
  microtodosuite/demo/auth-api-secrets
  microtodosuite-observability-secrets-reader
  microtodosuite-security-secrets-reader
  microtodosuite-security-trivy-ecr-reader
  microtodosuite-kyverno-ecr-verifier
  microtodosuite/observability/alertmanager-slack-webhook
  microtodosuite/security/falcosidekick-slack-webhook
  microtodosuite/auth-api
  microtodosuite/frontend
  microtodosuite/log-message-processor
  microtodosuite/todos-api
  microtodosuite/users-api
)

for retired_name in "${retired_names[@]}"; do
  if grep -RFn --exclude-dir=vendor --exclude=rebuilt-resource-names.sh \
      --exclude=valid-v2.0.0-baseline.json -- "$retired_name" \
      "${scan_paths[@]/#/$ROOT/}" >/dev/null; then
    fail "current GitOps paths still reference retired name $retired_name"
  fi
done

declare -A repository_suffix=(
  [auth-api]=authapi
  [frontend]=frontend
  [log-message-processor]=logmsgproc
  [todos-api]=todosapi
  [users-api]=usersapi
)

for service in "${!repository_suffix[@]}"; do
  expected="${EXPECTED_ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/lex-mts-shd-ecr-${repository_suffix[$service]}"
  while IFS= read -r overlay; do
    grep -Fq -- "newName: $expected" "$overlay" \
      || fail "${overlay#$ROOT/} does not select $expected"
  done < <(find "$ROOT/apps/$service/profiles" -path '*/overlays/*/kustomization.yaml' -type f | sort)
  grep -Fq -- "- \"$expected*\"" "$ROOT/infrastructure/kyverno/policies.yaml" \
    || fail "Kyverno does not verify $expected"
done

declare -A environment_suffix=(
  [dev]=dev
  [staging]=stg
  [prod]=prd
  [demo]=dmo
)

for environment in "${!environment_suffix[@]}"; do
  manifest="$ROOT/environments/$environment/kustomization.yaml"
  suffix="${environment_suffix[$environment]}"
  grep -Fq -- "role/lex-mts-eco-role-jwt${suffix}" "$manifest" \
    || fail "$environment does not use its rebuilt JWT reader role"
  grep -Fq -- "key: lex-mts-eco-sm-jwt${suffix}" "$manifest" \
    || fail "$environment does not use its rebuilt JWT secret"
done

grep -Fq -- 'role/lex-mts-eco-role-obssecret' "$ROOT/infrastructure/prometheus/alertmanager-config.yaml" \
  || fail "Alertmanager does not use the rebuilt secret reader role"
grep -Fq -- 'key: lex-mts-eco-sm-slackobs' "$ROOT/infrastructure/prometheus/alertmanager-config.yaml" \
  || fail "Alertmanager does not use the rebuilt Slack secret"
grep -Fq -- 'role/lex-mts-eco-role-secsecret' "$ROOT/infrastructure/falco/falcosidekick-slack-secret.yaml" \
  || fail "Falcosidekick does not use the rebuilt secret reader role"
grep -Fq -- 'key: lex-mts-eco-sm-slacksec' "$ROOT/infrastructure/falco/falcosidekick-slack-secret.yaml" \
  || fail "Falcosidekick does not use the rebuilt Slack secret"
grep -Fq -- 'role/lex-mts-eco-role-trivyecr' "$ROOT/infrastructure/trivy-operator/kustomization.yaml" \
  || fail "Trivy Operator does not use the rebuilt ECR reader role"
grep -Fq -- 'role/lex-mts-eco-role-kyvernoecr' "$ROOT/infrastructure/kyverno/kustomization.yaml" \
  || fail "Kyverno does not use the rebuilt ECR verifier role"

printf 'PASS: current GitOps paths use the rebuilt cluster, ECR, IAM, and secret names.\n'

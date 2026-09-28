#!/usr/bin/env bash
# Failing-first cloud secret contract (spec 009 T070, FR-026).
# All assertions render Git only. Secret values are never read or required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KUSTOMIZE_BIN="${KUSTOMIZE_BIN:-kustomize}"

command -v "$KUSTOMIZE_BIN" >/dev/null || { printf 'FAIL: kustomize is required\n' >&2; exit 1; }

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "required file is missing: $1"
}

render() { "$KUSTOMIZE_BIN" build "$ROOT/$1"; }

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

require_pattern() {
  local label="$1" text="$2" pattern="$3"
  grep -qE -- "$pattern" <<<"$text" || fail "$label must match: $pattern"
}

require_text() {
  local label="$1" text="$2" expected="$3"
  grep -qF -- "$expected" <<<"$text" || fail "$label must contain: $expected"
}

reject_text() {
  local label="$1" text="$2" rejected="$3"
  if grep -qF -- "$rejected" <<<"$text"; then
    fail "$label must not contain: $rejected"
  fi
}

# T089 owns these cloud-specific ESO roots. Their existence prevents a shared
# base from silently authenticating to the wrong cloud.
require_file infrastructure/external-secrets/overlays/aws/kustomization.yaml
require_file infrastructure/external-secrets/overlays/azure/kustomization.yaml

# AWS workload identity and exact environment source mappings. The role and
# source names are the rebuilt destination-qualified outputs already established
# by the full-cluster identity contract.
DESTINATIONS=(eks-full-dev eks-full-staging eks-full-prod)
ENVIRONMENTS=(dev staging prod)
PREFIXES=(fdev fstg fprd)
JWT_CODES=(jwtdev jwtstg jwtprd)
for index in "${!DESTINATIONS[@]}"; do
  destination="${DESTINATIONS[$index]}"
  environment="${ENVIRONMENTS[$index]}"
  prefix="${PREFIXES[$index]}"
  jwt_code="${JWT_CODES[$index]}"

  env_path="environments/profiles/full/destinations/$destination"
  require_file "$env_path/kustomization.yaml"
  [[ -f "$ROOT/$env_path/kustomization.yaml" ]] || continue
  env_render="$(render "$env_path")"

  service_account="$(document ServiceAccount external-secrets-jwt <<<"$env_render")"
  require_text "$destination JWT reader" "$service_account" \
    "eks.amazonaws.com/role-arn: arn:aws:iam::575172595729:role/lex-mts-$prefix-role-$jwt_code"
  reject_text "$destination JWT reader" "$service_account" '000000000000'

  store="$(document SecretStore aws-secrets-manager <<<"$env_render")"
  require_text "$destination JWT SecretStore" "$store" 'service: SecretsManager'
  require_text "$destination JWT SecretStore" "$store" 'region: us-east-1'
  require_text "$destination JWT SecretStore" "$store" 'name: external-secrets-jwt'

  jwt="$(document ExternalSecret auth-api-secrets <<<"$env_render")"
  require_text "$destination JWT ExternalSecret" "$jwt" "key: lex-mts-$prefix-sm-$jwt_code"
  require_text "$destination JWT ExternalSecret" "$jwt" 'secretKey: JWT_SECRET'

  obs_path="infrastructure/profiles/full/prometheus/destinations/$destination"
  sec_path="infrastructure/profiles/full/falco/destinations/$destination"
  obs_render="$(render "$obs_path")"
  sec_render="$(render "$sec_path")"
  require_text "$destination Alertmanager mapping" \
    "$(document ExternalSecret alertmanager-slack-webhook <<<"$obs_render")" \
    "key: lex-mts-$prefix-sm-slackobs"
  require_text "$destination Falco mapping" \
    "$(document ExternalSecret falcosidekick-slack-webhook <<<"$sec_render")" \
    "key: lex-mts-$prefix-sm-slacksec"

  # Grafana is an operator-supplied admin value and therefore comes from the
  # approved external source, never the in-cluster Password generator. The
  # rebuilt layout renamed every AWS source to lex-mts-<env>-sm-<code> (the JWT
  # and Slack rows above); no IaC root owns the Grafana container yet (audit
  # 2026-09-27 D8), so its exact code is a maintainer decision and only the
  # destination-scoped convention is pinned here.
  grafana_path="infrastructure/profiles/full/grafana/destinations/$destination"
  require_file "$grafana_path/kustomization.yaml"
  [[ -f "$ROOT/$grafana_path/kustomization.yaml" ]] || continue
  grafana="$(render "$grafana_path" | document ExternalSecret grafana-admin-credentials)"
  require_pattern "$destination Grafana mapping" "$grafana" \
    "^ +key: lex-mts-$prefix-sm-[a-z0-9]+$"

  # Only the two production copies participate in JWT parity. Metadata names
  # the common value lineage and non-secret source version; it never hashes or
  # exports the JWT value.
  if [[ "$environment" == prod ]]; then
    require_text "$destination production JWT parity metadata" "$jwt" \
      'microtodosuite.io/parity-group: production-jwt'
    require_text "$destination production JWT parity metadata" "$jwt" \
      'microtodosuite.io/source-version-metadata: required'
  fi
done

# Azure uses its own SecretStore, federated ServiceAccount, and exact four-name
# Key Vault inventory. Microsoft documents client-id on the ServiceAccount and
# the fail-closed workload identity label on pods that consume the identity.
AZURE_ENV=environments/profiles/full/destinations/aks-dr
require_file "$AZURE_ENV/kustomization.yaml"
if [[ -f "$ROOT/$AZURE_ENV/kustomization.yaml" ]]; then
  azure_env="$(render "$AZURE_ENV")"
  azure_sa="$(document ServiceAccount external-secrets-jwt <<<"$azure_env")"
  require_text 'AKS workload identity' "$azure_sa" 'azure.workload.identity/client-id:'
  reject_text 'AKS workload identity' "$azure_sa" '00000000-0000-0000-0000-000000000000'
  reject_text 'AKS workload identity' "$azure_sa" 'eks.amazonaws.com/role-arn:'

  azure_store="$(document SecretStore azure-key-vault <<<"$azure_env")"
  require_text 'AKS Key Vault SecretStore' "$azure_store" 'authType: WorkloadIdentity'
  require_text 'AKS Key Vault SecretStore' "$azure_store" 'serviceAccountRef:'
  require_text 'AKS Key Vault SecretStore' "$azure_store" 'name: external-secrets-jwt'
  require_text 'AKS Key Vault SecretStore' "$azure_store" 'vaultUrl: https://'
  reject_text 'AKS Key Vault SecretStore' "$azure_store" 'pending'

  azure_jwt="$(document ExternalSecret auth-api-secrets <<<"$azure_env")"
  require_text 'AKS production JWT mapping' "$azure_jwt" \
    'key: microtodosuite-prod-auth-api-secrets'
  require_text 'AKS production JWT parity metadata' "$azure_jwt" \
    'microtodosuite.io/parity-group: production-jwt'
  require_text 'AKS production JWT parity metadata' "$azure_jwt" \
    'microtodosuite.io/source-version-metadata: required'
fi

declare -A AZURE_SECRET=(
  [alertmanager-slack-webhook]=microtodosuite-observability-alertmanager-slack-webhook
  [falcosidekick-slack-webhook]=microtodosuite-security-falcosidekick-slack-webhook
  [grafana-admin-credentials]=microtodosuite-observability-grafana-admin
)
declare -A AZURE_ROOT=(
  [alertmanager-slack-webhook]=infrastructure/profiles/full/prometheus/destinations/aks-dr
  [falcosidekick-slack-webhook]=infrastructure/profiles/full/falco/destinations/aks-dr
  [grafana-admin-credentials]=infrastructure/profiles/full/grafana/destinations/aks-dr
)
for external_secret in "${!AZURE_SECRET[@]}"; do
  root="${AZURE_ROOT[$external_secret]}"
  require_file "$root/kustomization.yaml"
  [[ -f "$ROOT/$root/kustomization.yaml" ]] || continue
  resource="$(render "$root" | document ExternalSecret "$external_secret")"
  require_text "AKS $external_secret mapping" "$resource" "key: ${AZURE_SECRET[$external_secret]}"
  require_text "AKS $external_secret mapping" "$resource" 'name: azure-key-vault'
  reject_text "AKS $external_secret mapping" "$resource" 'pending'
  reject_text "AKS $external_secret mapping" "$resource" 'name: aws-secrets-manager'
done

# SonarQube/PostgreSQL is a full-dev-only shared tool with two exact external
# sources and one narrowly scoped reader identity.
SONAR_ROOT=infrastructure/profiles/full/sonarqube/destinations/eks-full-dev
require_file "$SONAR_ROOT/kustomization.yaml"
if [[ -f "$ROOT/$SONAR_ROOT/kustomization.yaml" ]]; then
  sonar="$(render "$SONAR_ROOT")"
  # Same rebuilt convention as Grafana; the exact codes wait for the missing
  # full-dev secret-container owner (audit 2026-09-27 D8).
  require_pattern 'full-dev Sonar DB mapping' \
    "$(document ExternalSecret sonarqube-db <<<"$sonar")" \
    '^ +key: lex-mts-fdev-sm-[a-z0-9]+$'
  require_pattern 'full-dev Sonar admin mapping' \
    "$(document ExternalSecret sonarqube-admin <<<"$sonar")" \
    '^ +key: lex-mts-fdev-sm-[a-z0-9]+$'
  sonar_sa="$(document ServiceAccount sonarqube-external-secrets <<<"$sonar")"
  require_text 'full-dev Sonar reader' "$sonar_sa" 'eks.amazonaws.com/role-arn:'
  require_text 'full-dev Sonar reader' "$sonar_sa" 'lex-mts-fdev-role-'
fi
for destination in eks-full-staging eks-full-prod aks-dr; do
  if [[ -e "$ROOT/infrastructure/profiles/full/sonarqube/destinations/$destination" ]]; then
    fail "Sonar secret mappings must be full-dev-only, found destination $destination"
  fi
done

# Every Kubernetes-native secret generator in the full profile must be listed
# with its controller owner, consumers, rotation, and non-export boundary.
ALLOWLIST=infrastructure/external-secrets/generator-allowlist.yaml
require_file "$ALLOWLIST"
if [[ -f "$ROOT/$ALLOWLIST" ]]; then
  allowlist="$(<"$ROOT/$ALLOWLIST")"
  for field in generator consumers rotation exported; do
    require_text 'generator allowlist' "$allowlist" "$field:"
  done
  for owner in cert-manager istio eck argocd kubernetes; do
    require_text 'generator allowlist' "$allowlist" "owner: $owner"
  done
  if grep -qE '^ +exported: (true|yes)$' <<<"$allowlist"; then
    fail "the generator allowlist must mark every controller-owned value non-exportable"
  fi
  # Every in-cluster generator the full profile can render must be listed by
  # name. The local-only JWT generator (spec 003) is outside this profile.
  while IFS= read -r generator; do
    [[ -z "$generator" ]] && continue
    grep -qE "^ *(- )?generator: $generator$" <<<"$allowlist" \
      || fail "generator $generator must be listed in $ALLOWLIST with its owner, consumers, and rotation"
  done < <(find "$ROOT/infrastructure" "$ROOT/environments/profiles/full" "$ROOT"/apps/*/profiles/full \
      "$ROOT"/apps/*/components/topology-full -path '*/vendor' -prune -o -name '*.yaml' -print0 \
    | xargs -0 awk '
        /^---/ { kind = "" }
        /^kind: / { kind = $2 }
        kind == "Password" && /^  name: / { print $2; kind = "" }
      ' | sort -u)
fi

# Grafana and Sonar values are operator/admin values, not internal bootstrap
# material. Ad hoc generators or Kustomize secretGenerator blocks are denied.
for path in infrastructure/grafana infrastructure/sonarqube; do
  if grep -R -nE '^kind: (Password|ClusterGenerator)$|^[[:space:]]*secretGenerator:' "$ROOT/$path" \
      --exclude-dir=vendor; then
    fail "$path must use external cloud-secret references, not an ad hoc generator"
  fi
done
# ECK reads file-realm role definitions from a Secret. They name privileges and
# carry no credential, so they are the only committed Secrets with data.
NON_CREDENTIAL_SECRETS=(grafana-elasticsearch-roles jaeger-elasticsearch-roles)

# No committed Kubernetes Secret may carry a value. ExternalSecret spec.data is
# a list of remote references, not values, so only kind: Secret is inspected.
committed_secret_values() {
  awk '
    function flush() {
      if (kind == "Secret" && valued) print FILENAME ": Secret " name
      kind = ""; name = ""; valued = 0; section = 0
    }
    FNR == 1 { flush() }
    /^---/ { flush(); next }
    /^kind: / { kind = $2 }
    /^  name: / && name == "" { name = $2 }
    /^(data|stringData):/ { section = 1; if ($2 != "" && $2 != "{}") valued = 1; next }
    section && /^  [^ #]/ { valued = 1; next }
    /^[^ ]/ { section = 0 }
    END { flush() }
  ' "$@"
}
mapfile -t manifests < <(find "$ROOT/apps" "$ROOT/environments" "$ROOT/infrastructure" \
  -path '*/vendor' -prune -o -name '*.yaml' -print)
valued="$(committed_secret_values "${manifests[@]}")"
for allowed in "${NON_CREDENTIAL_SECRETS[@]}"; do
  valued="$(grep -vE ": Secret $allowed$" <<<"$valued" || true)"
done
if [[ -n "$valued" ]]; then
  printf '%s\n' "$valued" >&2
  fail "application/operator secret values must not be committed as Secret data or stringData"
fi

if (( failures > 0 )); then
  printf 'FAIL: %d cloud-secret contract violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: AWS IRSA and Azure workload identity resolve the exact JWT/notification/admin mappings, production JWT parity metadata is value-blind, Sonar is full-dev-only, and only allowlisted controller bootstrap material is generated in-cluster.\n'

#!/usr/bin/env bash
# Velero credentials and ownership policy contract (spec 012 T002, US2 and US4).
#
# Velero writes eco's backups to an Azure storage account that refuses
# shared keys (ops spec 005 FR-002). Its credentials file is a secret, so
# constitution principle 10 allows exactly one path for it: AWS Secrets
# Manager -> External Secrets -> the Secret cloud-credentials. This contract
# refuses every other path and keeps Velero on the eco cluster only:
#
#   - both Velero roots exist (the rest is vacuous without them);
#   - no tracked file of the Velero roots, and nothing under clusters/,
#     carries a client secret value, a storage account key, a connection
#     string, a SAS signature, a private key, or an Azure subscription or
#     tenant ID;
#   - no rendered Secret, and cloud-credentials is produced only by an
#     ExternalSecret;
#   - the location authorizes through Entra ID only;
#   - the velero ServiceAccount has no AWS role: only External Secrets reads
#     AWS, through velero-external-secrets;
#   - only clusters/eks-dev may activate Velero, only through the
#     destination root, and no full-profile or AKS root references it.
#
# Offline by design: it reads and renders Git and never contacts a cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLATTEN="$ROOT/tests/lib/yaml-flatten.awk"
CONTROLLER="infrastructure/velero"
DESTINATION="infrastructure/profiles/economical/velero/destinations/eks-dev"

if ! command -v kustomize >/dev/null && ! command -v kubectl >/dev/null; then
  printf 'FAIL: standalone kustomize or kubectl is required\n' >&2
  exit 1
fi

failures=0
checks=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
check() { checks=$((checks + 1)); }

render() {
  if command -v kustomize >/dev/null; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

field() { awk -F'\t' -v d="$2" -v p="$3" '$1 == d { k = $2; sub(/=.*/, "", k); if (k == p) { v = $2; sub(/^[^=]*=/, "", v); print v } }' "$1"; }
docs_of_kind() { awk -F'\t' -v kind="$2" '$2 == "kind=" kind { print $1 }' "$1"; }
doc() {
  awk -F'\t' -v kind="$2" -v name="$3" -v ns="${4:-}" '
    { k = $2; sub(/=.*/, "", k); v = $2; sub(/^[^=]*=/, "", v)
      if (k == "kind") K[$1] = v; else if (k == "metadata.name") N[$1] = v; else if (k == "metadata.namespace") S[$1] = v }
    END { for (d in K) if (K[d] == kind && N[d] == name && (ns == "" || S[d] == ns)) print d }' "$1"
}

# --- 1. both roots exist ---------------------------------------------------------
for root in "$CONTROLLER" "$DESTINATION"; do
  check
  [[ -f "$ROOT/$root/kustomization.yaml" ]] || fail "$root/kustomization.yaml is missing"
done

# --- 2. no secret material in tracked files ------------------------------------------
# Patterns are for values, never for the names External Secrets references.
guid='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
secret_patterns=(
  "AZURE_CLIENT_SECRET[[:space:]]*[=:][[:space:]]*[^[:space:]\"'{}]"
  "AZURE_STORAGE_ACCOUNT_ACCESS_KEY[[:space:]]*[=:][[:space:]]*[^[:space:]\"'{}]"
  '(AZURE_SUBSCRIPTION_ID|AZURE_TENANT_ID|subscriptionId|tenantId)[[:space:]]*[=:][[:space:]]*["'\'']?'"$guid"
  'AccountKey='
  'DefaultEndpointsProtocol='
  'SharedAccessSignature='
  '[?&]sig=[A-Za-z0-9%/+=]{16,}'
  'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'
)
scan_paths=()
for path in "$CONTROLLER" "infrastructure/profiles/economical/velero" clusters; do
  [[ -e "$ROOT/$path" ]] && scan_paths+=("$ROOT/$path")
done
for pattern in "${secret_patterns[@]}"; do
  check
  if ((${#scan_paths[@]} > 0)) && hits="$(grep -rnIE -- "$pattern" "${scan_paths[@]}" 2>/dev/null)"; then
    fail "committed secret material matching /$pattern/: ${hits//$ROOT\//}"
  fi
done

# --- 3. renders: no Secret, ExternalSecret-only credentials, Entra-only location ---
for root in "$CONTROLLER" "$DESTINATION"; do
  [[ -f "$ROOT/$root/kustomization.yaml" ]] || continue
  name="${root//\//_}"
  raw="$workdir/$name.yaml"
  flat="$workdir/$name.flat"
  if ! render "$ROOT/$root" >"$raw" 2>"$workdir/$name.err"; then
    fail "$root does not render: $(cat "$workdir/$name.err")"
    continue
  fi
  awk -f "$FLATTEN" "$raw" >"$flat"

  check
  [[ -z "$(docs_of_kind "$flat" Secret)" ]] || fail "$root must render no Secret: credentials come from External Secrets only"

  check
  v="$(doc "$flat" ServiceAccount velero velero)"
  if [[ -n "$v" ]] && [[ -n "$(field "$flat" "$v" 'metadata.annotations.eks.amazonaws.com/role-arn')" ]]; then
    fail "$root: the velero ServiceAccount must carry no AWS role; only velero-external-secrets reads AWS"
  fi

  check
  for d in $(docs_of_kind "$flat" BackupStorageLocation); do
    [[ "$(field "$flat" "$d" spec.config.useAAD)" == true ]] \
      || fail "$root: every BackupStorageLocation must set useAAD: \"true\""
    if awk -F'\t' -v d="$d" '$1 == d { k = $2; sub(/=.*/, "", k); if (tolower(k) ~ /^spec\.config\..*(key|sas|secret|subscriptionid)/) f = 1 } END { exit !f }' "$flat"; then
      fail "$root: a BackupStorageLocation carries a key, SAS, secret, or subscription setting; Entra ID is the only authorization"
    fi
  done

  check
  for d in $(docs_of_kind "$flat" ExternalSecret); do
    [[ "$(field "$flat" "$d" spec.secretStoreRef.name)" == aws-secrets-manager ]] \
      || fail "$root: every Velero ExternalSecret must read through the SecretStore aws-secrets-manager"
  done
done

check
if [[ -f "$workdir/${DESTINATION//\//_}.flat" ]]; then
  flat="$workdir/${DESTINATION//\//_}.flat"
  [[ -n "$(doc "$flat" ExternalSecret cloud-credentials velero)" ]] \
    || fail "$DESTINATION: cloud-credentials must be produced by the ExternalSecret cloud-credentials"
fi

# --- 4. ownership: eks-dev only, through the destination root ----------------------
check
while IFS= read -r hit; do
  [[ -n "$hit" ]] || continue
  file="${hit%%:*}"
  case "$file" in
    clusters/eks-dev/activation-infrastructure.yaml) ;;
    *) fail "only clusters/eks-dev/activation-infrastructure.yaml may reference Velero, found $hit" ;;
  esac
done < <(cd "$ROOT" && grep -rnIi 'velero' clusters 2>/dev/null || true)

activation="$ROOT/clusters/eks-dev/activation-infrastructure.yaml"
check
if grep -qi velero "$activation"; then
  grep -Eq "^[[:space:]]+path: $DESTINATION$" "$activation" \
    || fail "clusters/eks-dev must activate Velero only through $DESTINATION"
  grep -Eq '^[[:space:]]+path: infrastructure/velero$' "$activation" \
    && fail "clusters/eks-dev must not activate the provider-neutral controller root directly"
fi

check
if hits="$(cd "$ROOT" && grep -rlIi 'velero' infrastructure/profiles/full environments/profiles/full 2>/dev/null)"; then
  fail "no full-profile or AKS root may reference Velero: $hits"
fi

if ((failures > 0)); then
  printf 'eco-velero policy contract: %d failure(s) in %d checks\n' "$failures" "$checks" >&2
  exit 1
fi
printf 'PASS: Velero credentials come only through External Secrets, the location is Entra-only, no secret material is committed, and only eks-dev may activate Velero (%d checks).\n' "$checks"

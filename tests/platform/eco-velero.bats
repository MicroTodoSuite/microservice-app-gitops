#!/usr/bin/env bash
# Velero off-provider backup render contract (spec 012 T001, US1 and US3).
#
# Pins what T004 to T009 must deliver:
#
#   infrastructure/velero
#       provider-neutral controller root: the velero.io CRDs, the velero
#       namespace, and the velero Deployment running a digest-pinned v1.18.x
#       server with exactly one digest-pinned v1.14.x Azure plugin init
#       container, reading its credentials file from the Secret
#       cloud-credentials at /credentials/cloud. No location, Schedule,
#       Secret, or node agent.
#
#   infrastructure/profiles/economical/velero/destinations/eks-dev
#       the only place the eco values live: the Entra-only
#       BackupStorageLocation on the ops-owned velero-eco container, the
#       External Secrets path for the credentials file (IRSA ServiceAccount,
#       SecretStore, ExternalSecret), and the eco-daily and eco-weekly
#       Schedules.
#
# Offline by design: it renders Git and never contacts a cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLATTEN="$ROOT/tests/lib/yaml-flatten.awk"
CONTROLLER="infrastructure/velero"
DESTINATION="infrastructure/profiles/economical/velero/destinations/eks-dev"

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

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

account="$(sed -n 's/^AWS_ACCOUNT_ID=\([0-9]\{12\}\)$/\1/p' "$ROOT/config/aws-account.env")"
[[ -n "$account" ]] || fail "config/aws-account.env does not declare AWS_ACCOUNT_ID"

# Values of one flattened path in one document.
field() { awk -F'\t' -v d="$2" -v p="$3" '$1 == d { k = $2; sub(/=.*/, "", k); if (k == p) { v = $2; sub(/^[^=]*=/, "", v); print v } }' "$1"; }
# Index of the document with a kind, name, and (optional) namespace.
doc() {
  awk -F'\t' -v kind="$2" -v name="$3" -v ns="${4:-}" '
    { k = $2; sub(/=.*/, "", k); v = $2; sub(/^[^=]*=/, "", v)
      if (k == "kind") K[$1] = v; else if (k == "metadata.name") N[$1] = v; else if (k == "metadata.namespace") S[$1] = v }
    END { for (d in K) if (K[d] == kind && N[d] == name && (ns == "" || S[d] == ns)) print d }' "$1"
}
# Number of documents of one kind.
count_kind() { awk -F'\t' -v kind="$2" '$2 == "kind=" kind { n++ } END { print n + 0 }' "$1"; }
# Value of the list-item sibling that shares an item chain with a matched key.
sibling() {
  awk -F'\t' -v d="$2" -v kp="$3" -v kv="$4" -v vp="$5" '
    $1 != d { next }
    { k = $2; sub(/=.*/, "", k); v = $2; sub(/^[^=]*=/, "", v)
      if (k == kp && v == kv) c[$3] = 1; line[NR] = $3 "\t" k "\t" v }
    END { for (i in line) { split(line[i], f, "\t"); if (f[2] == vp && (f[1] in c)) print f[3] } }' "$1"
}

expect() { # label actual expected
  [[ "$2" == "$3" ]] || fail "$1: expected '$3', found '${2:-<none>}'"
}

# Render one root, flatten it, and validate it; prints nothing on success.
prepare() {
  local label="$1" name="$2"
  if [[ ! -f "$ROOT/$label/kustomization.yaml" ]]; then
    fail "$label/kustomization.yaml is missing"
    return 1
  fi
  if grep -q '^kind: Component' "$ROOT/$label/kustomization.yaml"; then
    fail "$label must be a Kustomize root, not a Component"
  fi
  render "$ROOT/$label" >"$workdir/$name.yaml" 2>"$workdir/$name.err" || {
    fail "$label does not render: $(cat "$workdir/$name.err")"
    return 1
  }
  awk -f "$FLATTEN" "$workdir/$name.yaml" >"$workdir/$name.flat"
  local validation
  validation="$(kubeconform -strict -ignore-missing-schemas -summary <"$workdir/$name.yaml" 2>&1)" \
    || fail "$label does not pass kubeconform: $validation"
  grep -q 'Invalid: 0, Errors: 0' <<<"$validation" \
    || fail "$label has invalid or errored resources: $validation"
  grep -q 'CHANGEME' "$workdir/$name.yaml" && fail "$label still carries a CHANGEME placeholder"
  return 0
}

digest='@sha256:[0-9a-f]{64}$'
# Kustomize's images transformer drops the tag when it pins a digest, so the
# render carries name@sha256 and the version pin is checked in the vendored
# source (vendor/v1.18.<patch>/ with the v1.18.x and v1.14.x tags) instead.
server_image="^(docker\.io/)?velero/velero(:v1\.18\.[0-9]+)?$digest"
plugin_image="^(docker\.io/)?velero/velero-plugin-for-microsoft-azure(:v1\.14\.[0-9]+)?$digest"

# Controller and destination share the Deployment checks: the destination
# composes the controller and must not alter its image or credentials wiring.
check_deployment() {
  local label="$1" flat="$2" d
  d="$(doc "$flat" Deployment velero velero)"
  if [[ -z "$d" ]]; then
    fail "$label must render the Deployment velero in namespace velero"
    return
  fi
  local images inits
  images="$(field "$flat" "$d" 'spec.template.spec.containers[].image')"
  [[ "$(grep -c . <<<"$images")" == 1 ]] || fail "$label: the velero Deployment must run exactly one container"
  grep -Eq "$server_image" <<<"$images" \
    || fail "$label: the server image must be velero/velero[:v1.18.<patch>]@sha256:<digest>, found '${images:-<none>}'"
  inits="$(field "$flat" "$d" 'spec.template.spec.initContainers[].image')"
  [[ "$(grep -c . <<<"$inits")" == 1 ]] \
    || fail "$label: the velero Deployment must have exactly one plugin init container, found '${inits:-<none>}'"
  grep -Eq "$plugin_image" <<<"$inits" \
    || fail "$label: the plugin must be velero/velero-plugin-for-microsoft-azure[:v1.14.<patch>]@sha256:<digest>, found '${inits:-<none>}'"
  expect "$label: velero serviceAccountName" \
    "$(field "$flat" "$d" 'spec.template.spec.serviceAccountName')" velero
  expect "$label: AZURE_CREDENTIALS_FILE" \
    "$(sibling "$flat" "$d" 'spec.template.spec.containers[].env[].name' AZURE_CREDENTIALS_FILE 'spec.template.spec.containers[].env[].value')" \
    /credentials/cloud
  expect "$label: the cloud-credentials volume's Secret" \
    "$(sibling "$flat" "$d" 'spec.template.spec.volumes[].name' cloud-credentials 'spec.template.spec.volumes[].secret.secretName')" \
    cloud-credentials
  expect "$label: the cloud-credentials mount path" \
    "$(sibling "$flat" "$d" 'spec.template.spec.containers[].volumeMounts[].name' cloud-credentials 'spec.template.spec.containers[].volumeMounts[].mountPath')" \
    /credentials
}

# --- controller root -----------------------------------------------------------
if prepare "$CONTROLLER" controller; then
  flat="$workdir/controller.flat"
  [[ -n "$(doc "$flat" Namespace velero)" ]] || fail "$CONTROLLER must render the velero Namespace"
  [[ -n "$(doc "$flat" ServiceAccount velero velero)" ]] || fail "$CONTROLLER must render the velero ServiceAccount"
  for crd in backups restores schedules backupstoragelocations volumesnapshotlocations \
             deletebackuprequests downloadrequests serverstatusrequests; do
    [[ -n "$(doc "$flat" CustomResourceDefinition "$crd.velero.io")" ]] \
      || fail "$CONTROLLER must serve the CRD $crd.velero.io"
  done
  check_deployment "$CONTROLLER" "$flat"
  for kind in BackupStorageLocation VolumeSnapshotLocation Schedule Secret DaemonSet ExternalSecret SecretStore; do
    [[ "$(count_kind "$flat" "$kind")" == 0 ]] \
      || fail "$CONTROLLER must stay provider-neutral and render no $kind"
  done
  [[ -f "$ROOT/$CONTROLLER/README.md" ]] || fail "$CONTROLLER/README.md must record the vendored render's provenance"
  vendored=("$ROOT/$CONTROLLER"/vendor/v1.18.*/manifests.yaml)
  if [[ ${#vendored[@]} != 1 || ! -f "${vendored[0]}" ]]; then
    fail "$CONTROLLER must vendor exactly one render under vendor/v1.18.<patch>/manifests.yaml"
  else
    version="$(basename "$(dirname "${vendored[0]}")")"
    [[ "$version" =~ ^v1\.18\.[0-9]+$ ]] || fail "$CONTROLLER vendors '$version', not v1.18.<patch>"
    grep -Eq "image: (docker\.io/)?velero/velero:$version\$" "${vendored[0]}" \
      || fail "$CONTROLLER: the vendored server image tag must match the vendored version $version"
    grep -Eq 'image: (docker\.io/)?velero/velero-plugin-for-microsoft-azure:v1\.14\.[0-9]+$' "${vendored[0]}" \
      || fail "$CONTROLLER: the vendored plugin image must be tagged v1.14.<patch>"
    grep -Fq "vendor/$version/manifests.yaml" "$ROOT/$CONTROLLER/kustomization.yaml" \
      || fail "$CONTROLLER/kustomization.yaml must include vendor/$version/manifests.yaml"
  fi
fi

# --- destination root ------------------------------------------------------------
if prepare "$DESTINATION" destination; then
  flat="$workdir/destination.flat"
  check_deployment "$DESTINATION" "$flat"

  # BackupStorageLocation: the ops-owned container, Entra ID only.
  b="$(doc "$flat" BackupStorageLocation default velero)"
  if [[ -z "$b" ]]; then
    fail "$DESTINATION must render the BackupStorageLocation default in namespace velero"
  else
    expect "location apiVersion" "$(field "$flat" "$b" apiVersion)" velero.io/v1
    expect "location provider" "$(field "$flat" "$b" spec.provider)" velero.io/azure
    expect "location default" "$(field "$flat" "$b" spec.default)" true
    expect "location accessMode" "$(field "$flat" "$b" spec.accessMode)" ReadWrite
    expect "location bucket" "$(field "$flat" "$b" spec.objectStorage.bucket)" velero-eco
    expect "location resourceGroup" "$(field "$flat" "$b" spec.config.resourceGroup)" lex-mts-eco-rg-backups
    expect "location storageAccount" "$(field "$flat" "$b" spec.config.storageAccount)" lexmtsecostbackups
    expect "location storageAccountURI" "$(field "$flat" "$b" spec.config.storageAccountURI)" \
      https://lexmtsecostbackups.blob.core.windows.net
    expect "location useAAD" "$(field "$flat" "$b" spec.config.useAAD)" true
    keys="$(awk -F'\t' -v d="$b" '$1 == d { k = $2; sub(/=.*/, "", k); if (k ~ /^spec\.config\./) { sub(/^spec\.config\./, "", k); print k } }' "$flat" | sort | tr '\n' ' ')"
    expect "location config keys" "$keys" "resourceGroup storageAccount storageAccountURI useAAD "
  fi
  [[ "$(count_kind "$flat" BackupStorageLocation)" == 1 ]] || fail "$DESTINATION must render exactly one BackupStorageLocation"
  [[ "$(count_kind "$flat" VolumeSnapshotLocation)" == 0 ]] || fail "$DESTINATION must render no VolumeSnapshotLocation"

  # Credentials path: IRSA ServiceAccount -> SecretStore -> ExternalSecret.
  s="$(doc "$flat" ServiceAccount velero-external-secrets velero)"
  if [[ -z "$s" ]]; then
    fail "$DESTINATION must render the ServiceAccount velero-external-secrets in namespace velero"
  else
    expect "velero-external-secrets IRSA role" \
      "$(field "$flat" "$s" 'metadata.annotations.eks.amazonaws.com/role-arn')" \
      "arn:aws:iam::$account:role/lex-mts-eco-role-velerosec"
  fi
  st="$(doc "$flat" SecretStore aws-secrets-manager velero)"
  if [[ -z "$st" ]]; then
    fail "$DESTINATION must render the SecretStore aws-secrets-manager in namespace velero"
  else
    expect "SecretStore apiVersion" "$(field "$flat" "$st" apiVersion)" external-secrets.io/v1
    expect "SecretStore service" "$(field "$flat" "$st" spec.provider.aws.service)" SecretsManager
    expect "SecretStore region" "$(field "$flat" "$st" spec.provider.aws.region)" us-east-1
    expect "SecretStore service account" \
      "$(field "$flat" "$st" spec.provider.aws.auth.jwt.serviceAccountRef.name)" velero-external-secrets
  fi
  e="$(doc "$flat" ExternalSecret cloud-credentials velero)"
  if [[ -z "$e" ]]; then
    fail "$DESTINATION must render the ExternalSecret cloud-credentials in namespace velero"
  else
    expect "ExternalSecret apiVersion" "$(field "$flat" "$e" apiVersion)" external-secrets.io/v1
    expect "ExternalSecret store kind" "$(field "$flat" "$e" spec.secretStoreRef.kind)" SecretStore
    expect "ExternalSecret store name" "$(field "$flat" "$e" spec.secretStoreRef.name)" aws-secrets-manager
    expect "ExternalSecret target" "$(field "$flat" "$e" spec.target.name)" cloud-credentials
    expect "ExternalSecret creationPolicy" "$(field "$flat" "$e" spec.target.creationPolicy)" Owner
    expect "ExternalSecret remote key for 'cloud'" \
      "$(sibling "$flat" "$e" 'spec.data[].secretKey' cloud 'spec.data[].remoteRef.key')" lex-mts-eco-sm-velero
    refresh="$(field "$flat" "$e" spec.refreshInterval)"
    [[ -n "$refresh" && ! "$refresh" =~ ^0+[smh]?$ ]] \
      || fail "ExternalSecret cloud-credentials needs a non-zero refreshInterval, found '${refresh:-<none>}'"
  fi

  # Schedules: name ; cron shape ; namespaces (sorted, space-joined)
  daily_cron='^[0-5]?[0-9] ([01]?[0-9]|2[0-3]) \* \* \*$'
  weekly_cron='^[0-5]?[0-9] ([01]?[0-9]|2[0-3]) \* \* [0-6]$'
  for spec in \
    "eco-daily;$daily_cron;microtodo-demo microtodo-dev microtodo-prod microtodo-staging " \
    "eco-weekly;$weekly_cron;* "; do
    IFS=';' read -r name cron namespaces <<<"$spec"
    d="$(doc "$flat" Schedule "$name" velero)"
    if [[ -z "$d" ]]; then
      fail "$DESTINATION must render the Schedule $name in namespace velero"
      continue
    fi
    expect "$name apiVersion" "$(field "$flat" "$d" apiVersion)" velero.io/v1
    grep -Eq "$cron" <<<"$(field "$flat" "$d" spec.schedule)" \
      || fail "$name has the wrong cron shape: '$(field "$flat" "$d" spec.schedule)'"
    expect "$name includedNamespaces" \
      "$(field "$flat" "$d" 'spec.template.includedNamespaces[]' | sort | tr '\n' ' ')" "$namespaces"
    expect "$name storageLocation" "$(field "$flat" "$d" spec.template.storageLocation)" default
    expect "$name ttl" "$(field "$flat" "$d" spec.template.ttl)" 720h0m0s
    expect "$name snapshotVolumes" "$(field "$flat" "$d" spec.template.snapshotVolumes)" false
    expect "$name defaultVolumesToFsBackup" "$(field "$flat" "$d" spec.template.defaultVolumesToFsBackup)" false
    field "$flat" "$d" 'spec.template.excludedResources[]' | grep -qx secrets \
      || fail "$name must exclude secrets from its backups"
    expect "$name useOwnerReferencesInBackup" "$(field "$flat" "$d" spec.useOwnerReferencesInBackup)" false
    expect "$name paused" "$(field "$flat" "$d" spec.paused)" false
  done
  expect "eco-weekly includeClusterResources" \
    "$(field "$flat" "$(doc "$flat" Schedule eco-weekly velero)" spec.template.includeClusterResources)" true
  [[ "$(count_kind "$flat" Schedule)" == 2 ]] || fail "$DESTINATION must render exactly the Schedules eco-daily and eco-weekly"
fi

if ((failures > 0)); then
  printf 'eco-velero render contract: %d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: Velero renders digest-pinned with the Azure plugin, an Entra-only location on velero-eco, credentials only through External Secrets, and two retained schedules.\n'

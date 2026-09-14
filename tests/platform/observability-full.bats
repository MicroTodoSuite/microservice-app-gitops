#!/usr/bin/env bash
# Full-profile observability render test (spec 009, T085, first slice):
# per-cloud Prometheus, Alertmanager, and Grafana roots with encrypted
# persistence (research.md Decision 21). Offline by design: no live cluster is
# touched.
set -euo pipefail

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

validate() {
  local label="$1" path="$2" out
  out="$(render "$path" | kubeconform -strict -ignore-missing-schemas -summary 2>&1)" || {
    fail "$label does not render or does not pass kubeconform: $out"
    return
  }
  grep -q 'Invalid: 0, Errors: 0' <<<"$out" \
    || fail "$label has invalid or errored resources: $out"
}

# Every storageClassName that carries a value. CRD schemas also contain the
# key, but as a mapping with nothing after the colon, so they never match.
storage_classes() {
  grep -E '^[[:space:]]*storageClassName:[[:space:]]*[^[:space:]]' \
    | awk '{ gsub(/"/, "", $2); print $2 }' | sort -u
}

# Print one rendered document by kind and metadata.name.
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

declare -A CLASS=([aws]=gp3 [azure]=managed-csi)

# --- EKS: the gp3 class every aws root relies on encrypts its volumes ------
storageclass_render="$(render infrastructure/ebs-csi-driver)"
gp3="$(document StorageClass gp3 <<<"$storageclass_render")"
grep -q 'provisioner: ebs.csi.aws.com' <<<"$gp3" \
  || fail "StorageClass gp3 must be provisioned by ebs.csi.aws.com"
grep -q 'encrypted: "true"' <<<"$gp3" \
  || fail "StorageClass gp3 must set encrypted: \"true\""

for cloud in aws azure; do
  class="${CLASS[$cloud]}"

  # --- Prometheus and Alertmanager --------------------------------------
  root="infrastructure/profiles/full/prometheus/$cloud"
  if [[ ! -f "$root/kustomization.yaml" ]]; then
    fail "$root is missing"
  else
    grep -qE '^[[:space:]]*-[[:space:]]*\.\./\.\./\.\./\.\./prometheus[[:space:]]*$' "$root/kustomization.yaml" \
      || fail "$root must take the economical infrastructure/prometheus root as its base"
    validate "$root" "$root"
    out="$(render "$root")"
    classes="$(storage_classes <<<"$out")"
    [[ "$classes" == "$class" ]] \
      || fail "$root must place every volume on $class, found: ${classes:-none}"

    prometheus="$(document Prometheus k8s <<<"$out")"
    grep -q 'volumeClaimTemplate:' <<<"$prometheus" \
      || fail "$root: Prometheus k8s must keep its data on a volume"
    grep -q "storageClassName: $class" <<<"$prometheus" \
      || fail "$root: Prometheus k8s must use the $class class"
    grep -qE '^  replicas: 1$' <<<"$prometheus" \
      || fail "$root: Prometheus k8s must keep one replica (research.md Decision 10)"

    alertmanager="$(document Alertmanager main <<<"$out")"
    grep -q 'volumeClaimTemplate:' <<<"$alertmanager" \
      || fail "$root: Alertmanager main must keep silences and its notification log on a volume"
    grep -q "storageClassName: $class" <<<"$alertmanager" \
      || fail "$root: Alertmanager main must use the $class class"
    grep -qE '^  replicas: 1$' <<<"$alertmanager" \
      || fail "$root: Alertmanager main must keep one replica (research.md Decision 10)"
  fi

  # --- Grafana -----------------------------------------------------------
  root="infrastructure/profiles/full/grafana/$cloud"
  if [[ ! -f "$root/kustomization.yaml" ]]; then
    fail "$root is missing"
  else
    grep -qE '^[[:space:]]*-[[:space:]]*\.\./\.\./\.\./\.\./grafana[[:space:]]*$' "$root/kustomization.yaml" \
      || fail "$root must take the economical infrastructure/grafana root as its base"
    validate "$root" "$root"
    out="$(render "$root")"
    classes="$(storage_classes <<<"$out")"
    [[ "$classes" == "$class" ]] \
      || fail "$root must place every volume on $class, found: ${classes:-none}"
    grep -q "storageClassName: $class" <<<"$(document PersistentVolumeClaim grafana-storage <<<"$out")" \
      || fail "$root: PersistentVolumeClaim grafana-storage must use the $class class"
  fi
done

# --- the economical roots stay as they are (FR-002) --------------------------
for component in prometheus grafana; do
  classes="$(render "infrastructure/$component" | storage_classes)"
  [[ "$classes" == "gp3" ]] \
    || fail "economical infrastructure/$component must keep its volumes on gp3, found: ${classes:-none}"
  if grep -q 'profiles/' "infrastructure/$component/kustomization.yaml"; then
    fail "economical infrastructure/$component must not include a full-profile root"
  fi
done
if document Alertmanager main <<<"$(render infrastructure/prometheus)" | grep -q 'volumeClaimTemplate:'; then
  fail "economical Alertmanager main must stay without a volume; the full-profile roots add it"
fi

if (( failures > 0 )); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: full-profile observability roots (prometheus, grafana) keep encrypted volumes on gp3 (aws) and managed-csi (azure)\n'

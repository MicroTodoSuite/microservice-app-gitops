#!/usr/bin/env bash
# Full-profile observability render test (spec 009, T085, research.md
# Decision 21): per-cloud Prometheus, Alertmanager, and Grafana roots with
# encrypted persistence (first slice), and the full-profile alerts with the
# monitors that scrape their sources (second slice). Offline by design: no live
# cluster is touched.
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

# --- full-profile alerts and the monitors that scrape their sources ---------
# Each entry is "<alert>|<selector its expression must contain>".
ALERTS=(
  'WorkloadHighP99Latency|workload:http_request_duration_seconds:p99_5m{revision="stable"} > 2'
  'KedaScaledObjectErrors|keda_scaled_object_errors_total'
  'ArgoCdApplicationUnhealthy|argocd_app_info{health_status=~"Degraded|Missing"}'
  'ArgoCdApplicationOutOfSync|argocd_app_info{sync_status="OutOfSync"}'
  'ExternalSecretNotReady|externalsecret_status_condition{condition="Ready",status="False"}'
  'CertificateNotReady|certmanager_certificate_ready_status{condition="False"}'
  'CertificateExpiresSoon|certmanager_certificate_expiration_timestamp_seconds'
  'KyvernoAdmissionDenied|kyverno_admission_requests_total{request_allowed="false"}'
  'FalcosidekickSlackDeliveryFailing|falcosecurity_falcosidekick_outputs_total{destination="slack",status="error"}'
)
# Each entry is "<kind>|<name>|<target namespace>|<port>|<honor labels>".
# KEDA, Argo CD, External Secrets, and cert-manager report a namespace label
# of the object they describe; without honorLabels, Prometheus renames it to
# exported_namespace and sets namespace to the controller's own namespace.
MONITORS=(
  'ServiceMonitor|keda-operator|keda|metrics|yes'
  'ServiceMonitor|argocd-metrics|argocd|metrics|yes'
  'ServiceMonitor|cert-manager|cert-manager|http-metrics|yes'
  'ServiceMonitor|kyverno-admission-controller|kyverno|metrics-port|no'
  'ServiceMonitor|falcosidekick|security|http|no'
  'PodMonitor|external-secrets|external-secrets|metrics|yes'
)

# Print one alerting rule: from "- alert: <name>" to the next rule.
alert_rule() {
  awk -v name="$1" '
    $0 ~ ("- alert: " name "$") { found = 1; print; next }
    found && /- (alert|record): / { exit }
    found { print }
  '
}

for cloud in aws azure; do
  root="infrastructure/profiles/full/prometheus/$cloud"
  [[ -f "$root/kustomization.yaml" ]] || continue
  out="$(render "$root")"
  rules="$(document PrometheusRule full-profile-alerts <<<"$out")"
  if [[ -z "$rules" ]]; then
    fail "$root must render PrometheusRule full-profile-alerts"
  else
    for entry in "${ALERTS[@]}"; do
      alert="${entry%%|*}" selector="${entry#*|}"
      rule="$(alert_rule "$alert" <<<"$rules")"
      if [[ -z "$rule" ]]; then
        fail "$root: alert $alert is missing"
        continue
      fi
      grep -qF -- "$selector" <<<"$rule" \
        || fail "$root: alert $alert must read $selector"
      grep -q 'workload' <<<"$rule" \
        || fail "$root: alert $alert must carry a workload label for the Slack route"
    done
  fi

  for entry in "${MONITORS[@]}"; do
    IFS='|' read -r kind name namespace port honor <<<"$entry"
    monitor="$(document "$kind" "$name" <<<"$out")"
    if [[ -z "$monitor" ]]; then
      fail "$root: $kind $name is missing"
      continue
    fi
    grep -qE '^  namespace: observability$' <<<"$monitor" \
      || fail "$root: $kind $name must live in observability"
    grep -A1 'matchNames:' <<<"$monitor" | grep -qE "^[[:space:]]+- $namespace$" \
      || fail "$root: $kind $name must select namespace $namespace"
    grep -qE "^[[:space:]]+port: $port$" <<<"$monitor" \
      || fail "$root: $kind $name must scrape port $port"
    if [[ "$honor" == yes ]]; then
      grep -qE '^[[:space:]]+honorLabels: true$' <<<"$monitor" \
        || fail "$root: $kind $name must set honorLabels: true so namespace names the object, not the controller"
    fi
  done
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
economical_prometheus="$(render infrastructure/prometheus)"
if document Alertmanager main <<<"$economical_prometheus" | grep -q 'volumeClaimTemplate:'; then
  fail "economical Alertmanager main must stay without a volume; the full-profile roots add it"
fi
for entry in "${ALERTS[@]}"; do
  alert="${entry%%|*}"
  if grep -qE -- "- alert: $alert$" <<<"$economical_prometheus"; then
    fail "economical infrastructure/prometheus must not carry the full-profile alert $alert"
  fi
done

if (( failures > 0 )); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: full-profile observability roots (prometheus, grafana) keep encrypted volumes on gp3 (aws) and managed-csi (azure) and carry the full-profile alerts with their monitors\n'

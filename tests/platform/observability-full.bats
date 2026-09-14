#!/usr/bin/env bash
# Full-profile observability render test (spec 009, T085, research.md
# Decision 21): per-cloud Prometheus, Alertmanager, and Grafana roots with
# encrypted persistence (first slice), the full-profile alerts with the
# monitors that scrape their sources (second slice), and Jaeger on the ECK
# Elasticsearch backend with 3-day retention (third slice). Offline by design:
# no live cluster is touched.
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
      # The expression itself must produce workload: either label_replace
      # sets it, or it reads a workload:* recording rule. Annotations that
      # merely print $labels.workload do not count.
      expr="$(awk '/^[[:space:]]+expr:/ { f = 1 } f && /^[[:space:]]+(for|labels|annotations):/ { exit } f' <<<"$rule")"
      grep -qE '"workload", "|workload:' <<<"$expr" \
        || fail "$root: alert $alert must set a workload label in its expression for the Slack route"
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
      grep -qE '^[[:space:]]+(- )?honorLabels: true$' <<<"$monitor" \
        || fail "$root: $kind $name must set honorLabels: true so namespace names the object, not the controller"
    fi
  done
done

# --- Jaeger on the ECK Elasticsearch backend ---------------------------------
ES_URL='https://platform-es-http.elasticsearch.svc:9200'
CLEANER_IMAGE='jaegertracing/jaeger-es-index-cleaner@sha256:387d6532670c097999e6851ac7e22980804d5a4742b7f7ea03013d3397606add'

for cloud in aws azure; do
  root="infrastructure/profiles/full/jaeger/$cloud"
  if [[ ! -f "$root/kustomization.yaml" ]]; then
    fail "$root is missing"
    continue
  fi
  grep -qE '^[[:space:]]*-[[:space:]]*\.\./\.\./\.\./\.\./jaeger[[:space:]]*$' "$root/kustomization.yaml" \
    || fail "$root must take the economical infrastructure/jaeger root as its base"
  validate "$root" "$root"
  out="$(render "$root")"

  # Spans live in Elasticsearch, so neither Badger nor a volume remains.
  if grep -q '^kind: PersistentVolumeClaim$' <<<"$out"; then
    fail "$root must not keep a PersistentVolumeClaim; spans live in Elasticsearch"
  fi
  if grep -qi 'badger' <<<"$out"; then
    fail "$root must not configure Badger storage"
  fi

  config="$(document ConfigMap jaeger-config <<<"$out")"
  for expected in \
    'elasticsearch:' \
    "- $ES_URL" \
    'username: jaeger' \
    'password_file: /etc/jaeger-elasticsearch/credentials/password' \
    'ca_file: /etc/jaeger-elasticsearch/ca/ca.crt'; do
    grep -qF -- "$expected" <<<"$config" \
      || fail "$root: jaeger-config must contain '$expected'"
  done
  for index in spans services dependencies sampling; do
    awk -v index_name="$index" '
      $0 ~ ("^[[:space:]]+" index_name ":$") { found = 1; next }
      found && /shards: 1$/ { shards = 1 }
      found && /replicas: 0$/ { replicas = 1 }
      found && /^[[:space:]]+[a-z_]+:$/ { found = 0 }
      END { exit !(shards && replicas) }
    ' <<<"$config" \
      || fail "$root: jaeger-config must give the $index index one shard and no replica (single-node Elasticsearch)"
  done

  deployment="$(document Deployment jaeger <<<"$out")"
  grep -q 'secretName: jaeger-elasticsearch-credentials' <<<"$deployment" \
    || fail "$root: Deployment jaeger must mount Secret jaeger-elasticsearch-credentials"
  grep -q 'secretName: jaeger-elasticsearch-ca' <<<"$deployment" \
    || fail "$root: Deployment jaeger must mount Secret jaeger-elasticsearch-ca"
  # Outside /etc/jaeger: that is the read-only jaeger-config mount, and a
  # mount point nested inside it would have to be created in a read-only
  # directory.
  grep -q 'mountPath: /etc/jaeger-elasticsearch/credentials$' <<<"$deployment" \
    || fail "$root: Deployment jaeger must mount the credentials at /etc/jaeger-elasticsearch/credentials"
  grep -q 'mountPath: /etc/jaeger-elasticsearch/ca$' <<<"$deployment" \
    || fail "$root: Deployment jaeger must mount the CA at /etc/jaeger-elasticsearch/ca"

  store="$(document SecretStore elasticsearch <<<"$out")"
  grep -q 'remoteNamespace: elasticsearch' <<<"$store" \
    || fail "$root: SecretStore elasticsearch must read the elasticsearch namespace through the Kubernetes provider"
  grep -A1 'serviceAccount:' <<<"$store" | grep -q 'name: jaeger-elasticsearch-reader' \
    || fail "$root: SecretStore elasticsearch must authenticate as ServiceAccount jaeger-elasticsearch-reader"
  grep -q 'key: jaeger-elasticsearch-user' <<<"$(document ExternalSecret jaeger-elasticsearch-credentials <<<"$out")" \
    || fail "$root: ExternalSecret jaeger-elasticsearch-credentials must copy Secret jaeger-elasticsearch-user"
  grep -q 'key: platform-es-http-certs-public' <<<"$(document ExternalSecret jaeger-elasticsearch-ca <<<"$out")" \
    || fail "$root: ExternalSecret jaeger-elasticsearch-ca must copy ECK's Secret platform-es-http-certs-public"

  cleaner="$(document CronJob jaeger-es-index-cleaner <<<"$out")"
  if [[ -z "$cleaner" ]]; then
    fail "$root: CronJob jaeger-es-index-cleaner is missing"
  else
    grep -qF "image: $CLEANER_IMAGE" <<<"$cleaner" \
      || fail "$root: jaeger-es-index-cleaner must run $CLEANER_IMAGE"
    grep -A2 'args:' <<<"$cleaner" | grep -qE '^[[:space:]]+- "?3"?$' \
      || fail "$root: jaeger-es-index-cleaner must keep 3 days of indices"
    grep -A3 'args:' <<<"$cleaner" | grep -qF -- "- $ES_URL" \
      || fail "$root: jaeger-es-index-cleaner must target $ES_URL"
    grep -A4 'name: ES_PASSWORD' <<<"$cleaner" | grep -q 'name: jaeger-elasticsearch-credentials' \
      || fail "$root: jaeger-es-index-cleaner must read ES_PASSWORD from Secret jaeger-elasticsearch-credentials"
    grep -A1 'name: ES_TLS_CA' <<<"$cleaner" | grep -q 'value: /etc/jaeger-elasticsearch/ca/ca.crt' \
      || fail "$root: jaeger-es-index-cleaner must verify Elasticsearch with the copied CA"
  fi

  # Egress to Elasticsearch's HTTP port, checked per policy: Jaeger and the
  # cleaner each need their own, so one policy cannot satisfy both.
  for entry in 'jaeger-allow-elasticsearch|jaeger' 'jaeger-es-index-cleaner-egress|jaeger-es-index-cleaner'; do
    policy_name="${entry%%|*}" pod="${entry#*|}"
    policy="$(document NetworkPolicy "$policy_name" <<<"$out")"
    if [[ -z "$policy" ]]; then
      fail "$root: NetworkPolicy $policy_name is missing"
      continue
    fi
    grep -A2 'podSelector:' <<<"$policy" | grep -qE "app.kubernetes.io/name: $pod$" \
      || fail "$root: NetworkPolicy $policy_name must select the $pod pods"
    grep -B8 'kubernetes.io/metadata.name: elasticsearch' <<<"$policy" | grep -qE '^[[:space:]]+- port: 9200$' \
      || fail "$root: NetworkPolicy $policy_name must allow egress to the elasticsearch namespace on port 9200"
  done
done

grep -A3 '"id": "jaeger-es-index-cleaner"' scripts/managed/full-profile-toolchain.lock \
  | grep -q '"upstreamDigest": "sha256:387d6532670c097999e6851ac7e22980804d5a4742b7f7ea03013d3397606add"' \
  || fail "the toolchain lock must pin jaeger-es-index-cleaner 2.20.0 by digest"

# --- the Jaeger user in infrastructure/elasticsearch -------------------------
es_out="$(render infrastructure/elasticsearch)"
es_cr="$(document Elasticsearch platform <<<"$es_out")"
grep -A1 'fileRealm:' <<<"$es_cr" | grep -q 'secretName: jaeger-elasticsearch-user' \
  || fail "Elasticsearch platform must load the file-realm Secret jaeger-elasticsearch-user"
grep -A1 'roles:' <<<"$es_cr" | grep -q 'secretName: jaeger-elasticsearch-roles' \
  || fail "Elasticsearch platform must load the role Secret jaeger-elasticsearch-roles"

roles="$(document Secret jaeger-elasticsearch-roles <<<"$es_out")"
for expected in 'jaeger_writer:' 'manage_index_templates' 'jaeger-span-*' 'jaeger-service-*' 'jaeger-dependencies-*' 'jaeger-sampling-*' 'delete_index'; do
  grep -qF -- "$expected" <<<"$roles" \
    || fail "Secret jaeger-elasticsearch-roles must contain '$expected'"
done
if grep -qiE 'password' <<<"$roles"; then
  fail "Secret jaeger-elasticsearch-roles must hold roles only, never a credential"
fi

user="$(document ExternalSecret jaeger-elasticsearch-user <<<"$es_out")"
grep -q 'type: kubernetes.io/basic-auth' <<<"$user" \
  || fail "ExternalSecret jaeger-elasticsearch-user must produce a kubernetes.io/basic-auth Secret for ECK's file realm"
grep -q 'roles: jaeger_writer' <<<"$user" \
  || fail "ExternalSecret jaeger-elasticsearch-user must grant only jaeger_writer"
grep -A2 'generatorRef:' <<<"$user" | grep -q 'kind: Password' \
  || fail "ExternalSecret jaeger-elasticsearch-user must take its password from a Password generator"

reader="$(document Role jaeger-elasticsearch-secret-reader <<<"$es_out")"
grep -qE '^[[:space:]]+- get$' <<<"$reader" \
  || fail "Role jaeger-elasticsearch-secret-reader must grant get"
if grep -qE '^[[:space:]]+- (list|watch|create|update|patch|delete|"\*")$' <<<"$reader"; then
  fail "Role jaeger-elasticsearch-secret-reader must grant get only"
fi
for name in jaeger-elasticsearch-user platform-es-http-certs-public; do
  grep -qE "^[[:space:]]+- $name$" <<<"$reader" \
    || fail "Role jaeger-elasticsearch-secret-reader must name Secret $name"
done
binding="$(document RoleBinding jaeger-elasticsearch-secret-reader <<<"$es_out")"
grep -A2 'kind: ServiceAccount' <<<"$binding" | grep -q 'name: jaeger-elasticsearch-reader' \
  && grep -A2 'kind: ServiceAccount' <<<"$binding" | grep -q 'namespace: observability' \
  || fail "RoleBinding jaeger-elasticsearch-secret-reader must bind observability/jaeger-elasticsearch-reader"

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
economical_jaeger="$(render infrastructure/jaeger)"
grep -q '^kind: PersistentVolumeClaim$' <<<"$economical_jaeger" \
  || fail "economical infrastructure/jaeger must keep its Badger volume"
if grep -q 'platform-es-http' <<<"$economical_jaeger"; then
  fail "economical infrastructure/jaeger must not point at Elasticsearch"
fi

if (( failures > 0 )); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: full-profile observability roots (prometheus, grafana) keep encrypted volumes on gp3 (aws) and managed-csi (azure) carry the full-profile alerts with their monitors, and store Jaeger spans in Elasticsearch for 3 days\n'

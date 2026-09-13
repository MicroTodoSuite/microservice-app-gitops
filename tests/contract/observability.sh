#!/usr/bin/env bash
# Static contract for the observability platform foundation (feature 006).
# Covers all five user stories: prometheus + grafana (US1), the canary gate
# and Slack alerting (US2/US3), Jaeger (US4), and Loki/Alloy (US5).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*" >&2
}

render_kustomize() {
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "required file is missing: $1"
}

# GNU grep, not ripgrep: the validate-gitops runner image ships grep but not
# ripgrep. -r lets the same helpers check a single file or a whole directory.
require_text() {
  local path="$1" pattern="$2" description="$3"
  grep -rEq -- "$pattern" "$ROOT/$path" || fail "$description ($path)"
}

reject_text() {
  local path="$1" pattern="$2" description="$3"
  if grep -rEq -- "$pattern" "$ROOT/$path"; then
    fail "$description ($path)"
  fi
}

# An approved economical teardown quiesces eks-dev by replacing every activation
# list with exactly `value: []` (spec 009 T170, clusters/README.md), a state that
# tests/contract/economical-runtime-quiescence.sh owns. Registration entries can
# be asserted only while the infrastructure list is active; a quiesced list is
# reported as skipped, never as a pass.
infrastructure_activation_is_quiesced() {
  local path="$ROOT/clusters/eks-dev/activation-infrastructure.yaml"
  [[ "$(grep -Ec '^  value: \[\]$' "$path" || true)" == 1 ]] \
    && ! grep -Eq '^    - ' "$path"
}

check_checksum() {
  local directory="$1"
  require_file "$directory/SHA256SUMS"
  (
    cd "$ROOT/$directory"
    sha256sum -c SHA256SUMS >/dev/null
  ) || fail "checksum verification failed under $directory"
}

check_rendered_images() {
  local render="$1" image_ref
  while IFS= read -r image_ref; do
    image_ref="${image_ref%\"}"
    image_ref="${image_ref#\"}"
    [[ "$image_ref" == *@sha256:* ]] \
      || fail "rendered executable image is not digest-pinned: $image_ref"
  done < <(sed -nE 's/^[[:space:]-]*image:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$render" | grep -v '^{{')
}

require_resource() {
  local render="$1" kind="$2" name="$3"
  awk -v wanted_kind="$kind" -v wanted_name="$name" '
    /^---$/ { current_kind=""; in_metadata=0 }
    /^kind: / { current_kind=$2; in_metadata=0 }
    current_kind == wanted_kind && /^metadata:$/ { in_metadata=1; next }
    current_kind == wanted_kind && in_metadata && /^  name: / {
      name=$2
      gsub(/"/, "", name)
      if (name == wanted_name) found=1
      in_metadata=0
    }
    END { exit found ? 0 : 1 }
  ' "$render" || fail "$kind/$name is missing from $(basename "$render")"
}

# A container passes only if its own list item (not a sibling container, and not
# initContainers) declares the probe. Rendered YAML sorts keys, so the item is
# read as a whole rather than assuming "- name:" comes first; comment and blank
# lines are skipped, since a source manifest may annotate a container between
# list items. POSIX awk only.
require_container_probes() {
  local file="$1" container="$2" probe
  for probe in livenessProbe readinessProbe startupProbe; do
    awk -v wanted="$container" -v probe="$probe" '
      function indent(s) { match(s, /^ */); return RLENGTH }
      function flush() { if (item_name == wanted && item_has) found = 1; item_name = ""; item_has = 0 }
      /^ *containers: *$/ { flush(); in_list = 1; list_indent = -1; next }
      in_list {
        if ($0 ~ /^ *(#|$)/) next
        i = indent($0)
        if (list_indent < 0) {
          if ($0 ~ /^ *- /) list_indent = i
          else { in_list = 0; next }
        }
        if (i < list_indent || (i == list_indent && $0 !~ /^ *- /)) { flush(); in_list = 0; next }
        if (i == list_indent) { flush(); line = $0; sub(/^ *- /, "", line) }
        else if (i == list_indent + 2) { line = $0; sub(/^ */, "", line) }
        else next
        if (line ~ /^name: /) { name = line; sub(/^name: */, "", name); gsub(/"/, "", name); item_name = name }
        if (index(line, probe ":") == 1) item_has = 1
      }
      END { flush(); exit found ? 0 : 1 }
    ' "$file" || fail "container $container in ${file#"$ROOT"/} is missing $probe"
  done
}

# --- Vendor bundle: prometheus only (grafana/loki/jaeger have no genuine
# upstream bundle to checksum; see their vendor/<version>/README.md) ---
require_file "infrastructure/prometheus/vendor/v0.18.0/README.md"
require_file "infrastructure/prometheus/vendor/v0.18.0/SHA256SUMS"
check_checksum "infrastructure/prometheus/vendor/v0.18.0"
require_file "infrastructure/grafana/vendor/v13.2.0/README.md"
require_file "infrastructure/jaeger/vendor/v2.20.0/README.md"
require_file "infrastructure/loki/vendor/v3.7.6/README.md"

# --- Render check ---
for component in prometheus grafana jaeger loki; do
  render="$TMP_DIR/$component.yaml"
  render_kustomize "$ROOT/infrastructure/$component" >"$render" \
    || fail "Kustomize render failed for $component"
  [[ -s "$render" ]] || fail "$component rendered no resources"
  check_rendered_images "$render"
done

# --- Prometheus resources ---
require_resource "$TMP_DIR/prometheus.yaml" Prometheus k8s
require_resource "$TMP_DIR/prometheus.yaml" Alertmanager main
require_resource "$TMP_DIR/prometheus.yaml" Deployment prometheus-operator
for wl in auth-api todos-api users-api log-message-processor frontend; do
  require_resource "$TMP_DIR/prometheus.yaml" ServiceMonitor "$wl"
  require_resource "$TMP_DIR/prometheus.yaml" ServiceMonitor "$wl-canary"
done
require_resource "$TMP_DIR/prometheus.yaml" PrometheusRule business-workload-golden-signals
require_resource "$TMP_DIR/prometheus.yaml" AlertmanagerConfig slack-golden-signals
require_resource "$TMP_DIR/prometheus.yaml" ExternalSecret alertmanager-slack-webhook
require_resource "$TMP_DIR/prometheus.yaml" SecretStore aws-secrets-manager

# --- Jaeger resources ---
require_resource "$TMP_DIR/jaeger.yaml" Deployment jaeger
require_resource "$TMP_DIR/jaeger.yaml" Service jaeger-collector
require_resource "$TMP_DIR/jaeger.yaml" Service jaeger-query
require_resource "$TMP_DIR/jaeger.yaml" PersistentVolumeClaim jaeger-storage
require_text infrastructure/jaeger/config.yaml 'receivers:' \
  "Jaeger must receive OTLP directly (no separate otel-collector component)"
require_text infrastructure/jaeger/config.yaml 'ttl:' \
  "Jaeger Badger storage must declare an explicit retention TTL"
require_text infrastructure/jaeger/config.yaml 'spans: 72h' \
  "Jaeger retention must match the Clarifications session's 3-day decision"
reject_text infrastructure/jaeger/jaeger-allinone.yaml 'kind: Ingress' \
  "Jaeger must not add a public Ingress (FR-017: port-forward only)"

# --- Loki + Alloy resources ---
require_resource "$TMP_DIR/loki.yaml" StatefulSet loki
require_resource "$TMP_DIR/loki.yaml" Deployment alloy
require_resource "$TMP_DIR/loki.yaml" ClusterRole microtodosuite-alloy-log-reader

# --- Liveness, readiness, and startup probes on every observability container
# (evolution plan section 10; spec 006 T050) ---
require_container_probes "$TMP_DIR/grafana.yaml" grafana
require_container_probes "$TMP_DIR/jaeger.yaml" jaeger
require_container_probes "$TMP_DIR/loki.yaml" loki
require_container_probes "$TMP_DIR/loki.yaml" alloy
require_container_probes "$ROOT/apps/frontend/base/deployment.yaml" nginx-metrics
require_text infrastructure/loki/config.yaml 'retention_enabled: true' \
  "Loki must have retention enabled, not unbounded storage"
require_text infrastructure/loki/config.yaml 'retention_period: 72h' \
  "Loki retention must match the Clarifications session's 3-day decision"
require_text infrastructure/loki/config.yaml 'reporting_enabled: false' \
  "Loki must not phone home anonymous usage analytics"
require_text infrastructure/loki/alloy-config.yaml 'stage.structured_metadata' \
  "trace_id/span_id must be structured metadata, not labels"
# trace_id/span_id must appear only inside stage.structured_metadata, never
# inside stage.labels (that would be an unbounded-cardinality Loki label).
# POSIX classes, not \s: mawk has no \s, never closed the stage.labels block,
# and flagged the trace_id that correctly sits in stage.structured_metadata.
if awk '/stage\.labels \{/{f=1} f && /trace_id/{found=1} f && /^[[:space:]]*\}[[:space:]]*$/{f=0} END{exit !found}' \
    "$ROOT/infrastructure/loki/alloy-config.yaml"; then
  fail "trace_id must never be promoted to a Loki label (unbounded cardinality)"
fi
for f in infrastructure/loki/loki.yaml infrastructure/loki/alloy.yaml; do
  reject_text "$f" 'kind: Ingress' \
    "$f must not add a public Ingress (FR-017: port-forward only)"
done

# --- Grafana wired to Jaeger and Loki ---
require_text infrastructure/grafana/datasources.yaml 'type: jaeger' \
  "Grafana must have a Jaeger datasource once Jaeger exists"
require_text infrastructure/grafana/datasources.yaml 'type: loki' \
  "Grafana must have a Loki datasource once Loki exists"

# --- auth-api OTLP wiring points at Jaeger directly ---
# Spec 010 moved the endpoint from auth-api's dev overlay into every service's
# base ConfigMap, so each environment inherits the same destination;
# tests/contract/service-tracing.sh checks the rendered overlays.
require_text apps/auth-api/base/configmap.yaml \
  'OTEL_EXPORTER_OTLP_ENDPOINT' \
  "auth-api's base ConfigMap must set the OTLP endpoint"
require_text apps/auth-api/base/configmap.yaml \
  'jaeger-collector\.observability\.svc' \
  "auth-api must point OTLP directly at Jaeger, not an otel-collector"

# --- Canary gate ---
require_text infrastructure/argo-rollouts/cluster-analysis-template.yaml \
  'prometheus:' \
  "canary analysis must use the Prometheus provider, not the old curl Job"
require_text infrastructure/argo-rollouts/cluster-analysis-template.yaml \
  'revision="canary"' \
  "canary analysis must scope its query to the canary revision"
for svc in auth-api todos-api users-api frontend log-message-processor; do
  require_text "apps/$svc/components/strategy-canary/rollout.yaml" \
    'name: workload' \
    "$svc's canary analysis args must pass the workload arg the template now expects"
  reject_text "apps/$svc/components/strategy-canary/rollout.yaml" \
    'target-url' \
    "$svc's canary analysis still passes the retired target-url arg"
done

# --- Secret hygiene: no committed Slack webhook value ---
reject_text infrastructure/prometheus/alertmanager-config.yaml \
  'hooks\.slack\.com/services' \
  "Slack webhook URL must never be a literal value in Git"

# --- Grafana resources ---
require_resource "$TMP_DIR/grafana.yaml" Deployment grafana
require_resource "$TMP_DIR/grafana.yaml" ConfigMap grafana-datasources
require_resource "$TMP_DIR/grafana.yaml" ConfigMap grafana-dashboards-golden-signals
require_resource "$TMP_DIR/grafana.yaml" NetworkPolicy grafana-default-deny

# --- Economical-profile substitutions: no ELK/Elasticsearch, no Ingress ---
for component in prometheus grafana; do
  reject_text "infrastructure/$component" 'kind: Elasticsearch|kind: Logstash|kind: Kibana|kind: Filebeat' \
    "$component must not depend on the full-profile ELK stack"
  reject_text "infrastructure/$component" 'kind: Ingress' \
    "$component must not add a public Ingress (FR-017: port-forward only)"
  reject_text "infrastructure/$component" 'kind: Certificate\b' \
    "$component must not request a TLS certificate for its UI (FR-017)"
done

# --- No unbounded-cardinality label usage in first-party rules ---
reject_text "infrastructure/prometheus/rules/golden-signals.yaml" \
  'user_id|todo_id|request_id' \
  "golden-signal rules must not group by unbounded-cardinality labels"

# --- Registration contract ---
registration="asserted"
if infrastructure_activation_is_quiesced; then
  registration="skipped, eks-dev infrastructure activation is quiesced"
  printf 'SKIP: registration contract: %s\n' "$registration" >&2
else
  for name in prometheus grafana jaeger loki; do
    require_text clusters/eks-dev/activation-infrastructure.yaml "name: $name$" \
      "eks-dev infrastructure activation omits $name"
    if [[ "$(grep -A2 "name: $name$" "$ROOT/clusters/eks-dev/activation-infrastructure.yaml" | grep -c 'namespace: observability')" -lt 1 ]]; then
      fail "eks-dev activation entry $name is not destined to the observability namespace"
    fi
  done
fi

require_text clusters/base/project.yaml 'namespace: observability' \
  "AppProject destinations omit the observability namespace"
reject_text clusters/base/project.yaml 'group: monitoring\.coreos\.com' \
  "Prometheus Operator CRDs are Namespaced-scope and must not appear in clusterResourceWhitelist"

# --- Secret hygiene: no committed Grafana admin password ---
reject_text infrastructure/grafana/admin-secret.yaml \
  'GF_SECURITY_ADMIN_PASSWORD: [^"{]' \
  "Grafana admin password must be ESO-generated, never a literal value"

pass "observability platform static contract (prometheus, grafana, jaeger, loki); registration $registration"

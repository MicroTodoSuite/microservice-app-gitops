#!/usr/bin/env bash
# Read-only full-profile cost allocation evidence collector (spec 009, T147,
# research.md Decision 24). One EKS cluster per environment
# (eks-full-{dev,staging,prod}), each pricing only itself, so cost is collected
# per destination rather than once for the platform.
#
# DESIRED half needs no cluster: it reads what this repository declares about
# the cost model -- which cluster each destination attributes its cost to, the
# node and Kubernetes state metrics OpenCost prices, the pod labels
# kube-state-metrics publishes so cost can be grouped by service and profile,
# and the dashboard that reads the result. LIVE needs a reachable cluster and
# is BLOCKED, per destination, when this environment cannot reach one, with
# explicit PASS/FAIL/BLOCKED throughout (scripts/managed/lib/verify-common.sh).
# A cost that was not observed is never reported as a pass.
#
# STATUS: the three full clusters carry no Argo CD yet (T063-T065), and this
# environment has no eks-full-* kubectl credentials, so today's real run is
# DESIRED-only PASS plus three BLOCKED LIVE checks. That is the honest result,
# not a placeholder.
#
# This collector reports; it does not adjudicate the manifests. The contract on
# what they must declare is tests/platform/opencost-allocation.bats.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICES=(auth-api todos-api users-api frontend log-message-processor)
DESTINATIONS=(eks-full-dev eks-full-staging eks-full-prod)
declare -A ENV_FOR=([eks-full-dev]=dev [eks-full-staging]=staging [eks-full-prod]=prod)
OPENCOST_NAMESPACE=opencost
OBS_NAMESPACE=observability

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# Print one rendered document by kind and metadata.name. Every check below
# reads the object it is about rather than the whole render: four other
# ServiceMonitors in this root also set honorLabels, so a render-wide search
# would report the OpenCost scrape as correct after it lost the setting.
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

# shellcheck source=scripts/managed/lib/verify-common.sh
source "$ROOT/scripts/managed/lib/verify-common.sh"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="$ROOT/evidence/runs/${TIMESTAMP}-full-profile-cost"
mkdir -p "$EVIDENCE_DIR/raw"

command -v kustomize >/dev/null 2>&1 && KUSTOMIZE_BIN=kustomize || KUSTOMIZE_BIN="kubectl kustomize"

# The USD-per-hour series OpenCost publishes once it has something to price.
# Names, labels and units are OpenCost's own (docs/integrations/metrics.md in
# opencost/opencost-website): node_cpu_hourly_cost is USD per vCPU-hour,
# node_ram_hourly_cost USD per GiB-hour, container_cpu_allocation cores, and
# container_memory_allocation_bytes bytes.
ALLOCATION_EXPR='container_cpu_allocation * on (node) group_left() avg by (node) (node_cpu_hourly_cost)'
ALLOCATION_EXPR+=' + container_memory_allocation_bytes / 1024 / 1024 / 1024'
ALLOCATION_EXPR+=' * on (node) group_left() avg by (node) (node_ram_hourly_cost)'

# --- DESIRED: what the repository declares, per destination -----------------
for destination in "${DESTINATIONS[@]}"; do
  registration="$ROOT/clusters/$destination/registration.yaml"
  cost_root="$ROOT/infrastructure/profiles/full/opencost/destinations/$destination"

  if [[ ! -f "$registration" ]]; then
    record_check FAIL "$destination: missing registration.yaml, so no cluster name to attribute cost to"
    continue
  fi
  physical="$(awk '$1 == "physicalCluster:" { print $2; exit }' "$registration")"
  if [[ -z "$physical" ]]; then
    record_check FAIL "$destination: registration.yaml declares no physicalCluster"
    continue
  fi

  if [[ ! -d "$cost_root" ]]; then
    record_check FAIL "$destination: missing $cost_root, so OpenCost would report the chart's default cluster"
    continue
  fi
  if ! render="$($KUSTOMIZE_BIN build "$cost_root" 2>"$EVIDENCE_DIR/raw/$destination-opencost-render.stderr")"; then
    record_check FAIL "$destination: the OpenCost destination root does not render"
    continue
  fi
  # The CLUSTER_ID every cost series this destination exports will carry.
  cluster_id="$(awk '
    /^ *- name: CLUSTER_ID$/ { getline; sub(/^ *value: /, ""); gsub(/"/, ""); print; exit }
  ' <<<"$render")"
  printf '%s\n' "$cluster_id" > "$EVIDENCE_DIR/raw/$destination-cluster-id.txt"
  if [[ "$cluster_id" == "$physical" ]]; then
    record_check PASS "$destination: cost is attributed to $physical (CLUSTER_ID matches the registration)"
  else
    record_check FAIL "$destination: CLUSTER_ID is '${cluster_id:-unset}' but the registration declares $physical, so cost would be filed under the wrong cluster"
  fi

  # Profile and service are pod labels, so a per-service cost only exists where
  # the workload carries them. opencost-allocation.bats is what guarantees the
  # label stays off the immutable selector; here it is only observed.
  environment="${ENV_FOR[$destination]}"
  for service in "${SERVICES[@]}"; do
    overlay="$ROOT/apps/$service/profiles/full/overlays/$environment"
    if [[ ! -d "$overlay" ]]; then
      record_check FAIL "$destination/$service: missing overlay $overlay"
      continue
    fi
    if overlay_render="$($KUSTOMIZE_BIN build "$overlay" 2>"$EVIDENCE_DIR/raw/$service-$destination-render.stderr")"; then
      if grep -qF 'microtodosuite.io/profile: full' <<<"$overlay_render"; then
        record_check PASS "$destination/$service: pods carry microtodosuite.io/profile: full"
      else
        record_check FAIL "$destination/$service: pods carry no profile label, so their cost cannot be grouped by profile"
      fi
    else
      record_check FAIL "$destination/$service: overlay does not render"
    fi
  done
done

# --- DESIRED: the priced inputs and the dashboard, declared once for every
# full cluster by the shared aws root, so they are read once, not per
# destination. -------------------------------------------------------------
if prometheus_render="$($KUSTOMIZE_BIN build "$ROOT/infrastructure/profiles/full/prometheus/aws" \
    2>"$EVIDENCE_DIR/raw/full-prometheus-render.stderr")"; then
  printf '%s\n' "$prometheus_render" > "$EVIDENCE_DIR/raw/full-prometheus.yaml"
  node_exporter="$(document DaemonSet node-exporter <<<"$prometheus_render")"
  kube_state="$(document Deployment kube-state-metrics <<<"$prometheus_render")"
  if [[ -n "$node_exporter" && -n "$kube_state" ]]; then
    record_check PASS "allocation sources: the full Prometheus root runs node-exporter and kube-state-metrics"
  else
    record_check FAIL "allocation sources: the full Prometheus root is missing an exporter OpenCost prices from"
  fi

  opencost_monitor="$(document ServiceMonitor opencost <<<"$prometheus_render")"
  if [[ -n "$opencost_monitor" ]] && grep -qF 'honorLabels: true' <<<"$opencost_monitor"; then
    record_check PASS "allocation sources: Prometheus scrapes the OpenCost exporter with honorLabels"
  else
    record_check FAIL "allocation sources: the OpenCost exporter is not scraped, or is scraped without honorLabels, which would file every cost under the opencost namespace"
  fi

  if grep -qF -- '--metric-labels-allowlist=pods=[app.kubernetes.io/name,microtodosuite.io/profile]' <<<"$kube_state"; then
    record_check PASS "allocation dimensions: kube-state-metrics publishes the service and profile pod labels"
  else
    record_check FAIL "allocation dimensions: kube-state-metrics publishes no service or profile pod label, so cost cannot be grouped by either"
  fi
else
  record_check FAIL "allocation sources: the full Prometheus root does not render"
fi

if grafana_render="$($KUSTOMIZE_BIN build "$ROOT/infrastructure/profiles/full/grafana/aws" \
    2>"$EVIDENCE_DIR/raw/full-grafana-render.stderr")"; then
  cost_dashboard="$(document ConfigMap grafana-dashboards-full-profile-cost <<<"$grafana_render")"
  grafana_deployment="$(document Deployment grafana <<<"$grafana_render")"
  if [[ -n "$cost_dashboard" ]] \
    && grep -qE '^ +name: grafana-dashboards-full-profile-cost$' <<<"$grafana_deployment"; then
    record_check PASS "cost dashboard: the full Grafana root renders grafana-dashboards-full-profile-cost and projects it"
  else
    record_check FAIL "cost dashboard: the full Grafana root does not render or does not project grafana-dashboards-full-profile-cost"
  fi
else
  record_check FAIL "cost dashboard: the full Grafana root does not render"
fi

# --- LIVE: the cost each destination is actually reporting ------------------
for destination in "${DESTINATIONS[@]}"; do
  if ! require_live_context "$destination"; then
    record_check BLOCKED "$destination: live cost allocation (no context reachable from this environment)"
    continue
  fi

  kube() { kubectl --context "$destination" "$@"; }

  if kube get deployment opencost -n "$OPENCOST_NAMESPACE" -o json \
      > "$EVIDENCE_DIR/raw/$destination-opencost-deployment.json" 2>/dev/null; then
    available="$(jq -r '.status.conditions[]? | select(.type == "Available") | .status' \
      "$EVIDENCE_DIR/raw/$destination-opencost-deployment.json" 2>/dev/null || true)"
    if [[ "$available" == "True" ]]; then
      record_check PASS "$destination: OpenCost is Available"
    else
      record_check FAIL "$destination: OpenCost is not Available (observed: ${available:-unknown})"
    fi
  else
    record_check FAIL "$destination: OpenCost Deployment not readable despite a reachable context"
  fi

  # A local port-forward, not a pod created for the query: it changes no
  # cluster state, and unlike the API server's service proxy it is not blocked
  # by the NetworkPolicy that guards Prometheus on 9090.
  log "$destination: querying live cost allocation through a local port-forward"
  prometheus_port=19091
  kube port-forward -n "$OBS_NAMESPACE" svc/prometheus-k8s "$prometheus_port:9090" \
    > "$EVIDENCE_DIR/raw/$destination-port-forward.log" 2>&1 &
  port_forward_pid=$!
  # shellcheck disable=SC2064
  trap "kill $port_forward_pid 2>/dev/null || true" EXIT
  prometheus_ready=false
  for _ in $(seq 1 20); do
    if curl -sf "http://127.0.0.1:$prometheus_port/-/ready" >/dev/null 2>&1; then
      prometheus_ready=true
      break
    fi
    sleep 0.5
  done

  if [[ "$prometheus_ready" != true ]]; then
    record_check BLOCKED "$destination: live cost allocation (Prometheus did not become reachable through the port-forward)"
  else
    query() {
      local name="$1" expression="$2"
      curl -sf -G "http://127.0.0.1:$prometheus_port/api/v1/query" \
        --data-urlencode "query=$expression" \
        -o "$EVIDENCE_DIR/raw/$destination-$name.json"
    }
    # The cluster this Prometheus is actually pricing, read from OpenCost
    # itself rather than assumed from the destination's name.
    expected="$(cat "$EVIDENCE_DIR/raw/$destination-cluster-id.txt" 2>/dev/null || true)"
    if query cluster-info 'kubecost_cluster_info'; then
      observed="$(jq -r '[.data.result[]?.metric.cluster] | unique | join(",")' \
        "$EVIDENCE_DIR/raw/$destination-cluster-info.json" 2>/dev/null || true)"
      if [[ -n "$observed" && "$observed" == "$expected" ]]; then
        record_check PASS "$destination: OpenCost reports cost for $observed, the cluster this destination declares"
      elif [[ -z "$observed" ]]; then
        record_check FAIL "$destination: OpenCost publishes no kubecost_cluster_info, so no cost is attributed yet"
      else
        record_check FAIL "$destination: OpenCost reports cost for '$observed' but this destination declares '$expected'"
      fi
    else
      record_check FAIL "$destination: kubecost_cluster_info query failed"
    fi

    # Cost by namespace, by service, and by profile: the dimensions FR-033
    # asks for. A query that answers with an empty result is reported as such,
    # because an empty cost is not an observed cost.
    declare -A COST_QUERIES=(
      [by-namespace]="sum by (namespace) ($ALLOCATION_EXPR)"
      [by-service]="sum by (label_app_kubernetes_io_name) (($ALLOCATION_EXPR) * on (namespace, pod) group_left(label_app_kubernetes_io_name) kube_pod_labels{label_microtodosuite_io_profile=\"full\"})"
      [by-profile]="sum by (label_microtodosuite_io_profile) (($ALLOCATION_EXPR) * on (namespace, pod) group_left(label_microtodosuite_io_profile) kube_pod_labels)"
    )
    for dimension in by-namespace by-service by-profile; do
      if query "cost-$dimension" "${COST_QUERIES[$dimension]}"; then
        samples="$(jq -r '.data.result | length' "$EVIDENCE_DIR/raw/$destination-cost-$dimension.json" 2>/dev/null || echo 0)"
        if [[ "${samples:-0}" -gt 0 ]]; then
          record_check PASS "$destination: live cost allocation $dimension ($samples series)"
        else
          record_check FAIL "$destination: live cost allocation $dimension returned no series"
        fi
      else
        record_check FAIL "$destination: live cost allocation $dimension query failed"
      fi
    done
  fi

  kill "$port_forward_pid" 2>/dev/null || true
  trap - EXIT
done

log "Evidence retained under $EVIDENCE_DIR"
final_verdict
exit $?

#!/usr/bin/env bash
# OpenCost allocation render test (spec 009 T144, research.md Decision 24):
# cost is allocated by cluster, environment, profile, namespace, and service in
# the full profile. OpenCost gets the node and Kubernetes state metrics its
# metrics reference requires, Prometheus scrapes OpenCost, each full cluster
# names itself, business pods carry their profile, and the cost dashboard
# queries every dimension. Offline by design: no live cluster is touched.
set -euo pipefail

command -v kubeconform >/dev/null || { printf 'FAIL: kubeconform is required\n' >&2; exit 1; }
if ! command -v kustomize >/dev/null && ! command -v kubectl >/dev/null; then
  printf 'FAIL: standalone kustomize or kubectl is required\n' >&2
  exit 1
fi
command -v python3 >/dev/null || { printf 'FAIL: python3 is required to parse the dashboard JSON\n' >&2; exit 1; }

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

render() {
  if command -v kustomize >/dev/null; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
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

validate() {
  local path="$1" out
  out="$(render "$path" | kubeconform -strict -ignore-missing-schemas -summary 2>&1)" || {
    fail "$path does not render or does not pass kubeconform: $out"
    return
  }
  grep -q 'Invalid: 0, Errors: 0' <<<"$out" || fail "$path has invalid or errored resources: $out"
}

DESTINATIONS=(eks-full-dev eks-full-staging eks-full-prod)
SERVICES=(auth-api todos-api users-api frontend log-message-processor)
ENVIRONMENTS=(dev staging prod)
NODE_EXPORTER_IMAGE='quay.io/prometheus/node-exporter@sha256:0f422f62c15f154af8d8572b23d623aebfb10cec73a5c654d18f911f3f9df241'
KUBE_STATE_METRICS_IMAGE='registry.k8s.io/kube-state-metrics/kube-state-metrics@sha256:6b2f0b6f2f86ac5b1aa883a033a8dd55bb96c16d191ec973393bdaadaddac914'
KUBE_RBAC_PROXY_IMAGE='quay.io/brancz/kube-rbac-proxy@sha256:53d5a3911ac076d000c92362d4939a3147ba21f231edf82926c82d16dbdd8850'
LABELS_ALLOWLIST='--metric-labels-allowlist=pods=[app.kubernetes.io/name,microtodosuite.io/profile]'

# Print the value of one environment variable of a rendered container.
env_value() {
  awk -v name="$1" '
    $0 ~ ("^ *- name: " name "$") { getline; sub(/^ *value: /, ""); gsub(/"/, ""); print; exit }
  '
}

# --- cluster: each full destination names its own cluster --------------------
shared_opencost="$(render infrastructure/opencost)"
[[ "$(document Deployment opencost <<<"$shared_opencost" | env_value CLUSTER_ID)" == default-cluster ]] \
  || fail "the shared infrastructure/opencost root must keep the chart's CLUSTER_ID, since it runs in every cluster"
for destination in "${DESTINATIONS[@]}"; do
  root="infrastructure/profiles/full/opencost/destinations/$destination"
  if [[ ! -f "$root/kustomization.yaml" ]]; then
    fail "$root must exist to name its cluster"
    continue
  fi
  grep -qE '^[[:space:]]*-[[:space:]]*\.\./\.\./\.\./\.\./\.\./opencost[[:space:]]*$' "$root/kustomization.yaml" \
    || fail "$root must take infrastructure/opencost as its base"
  validate "$root"
  physical="$(awk '$1 == "physicalCluster:" { print $2 }' "clusters/$destination/registration.yaml")"
  out="$(render "$root")"
  [[ "$(document Deployment opencost <<<"$out" | env_value CLUSTER_ID)" == "$physical" ]] \
    || fail "$root must set CLUSTER_ID to $physical, the physicalCluster of clusters/$destination/registration.yaml"
  # Nothing else differs from the shared root.
  [[ "$(sed "s/^\( *value: \)$physical\$/\1default-cluster/" <<<"$out")" == "$shared_opencost" ]] \
    || fail "$root must render infrastructure/opencost unchanged apart from CLUSTER_ID"
done

# --- allocation sources in the full Prometheus roots -------------------------
for cloud in aws azure; do
  root="infrastructure/profiles/full/prometheus/$cloud"
  out="$(render "$root")"
  exporter="$(document DaemonSet node-exporter <<<"$out")"
  if [[ -z "$exporter" ]]; then
    fail "$root must run the node-exporter DaemonSet OpenCost requires"
  else
    grep -qE '^  namespace: observability$' <<<"$exporter" || fail "$root: node-exporter must run in observability"
    for image in "$NODE_EXPORTER_IMAGE" "$KUBE_RBAC_PROXY_IMAGE"; do
      grep -qF "image: $image" <<<"$exporter" || fail "$root: node-exporter must run $image"
    done
  fi
  state="$(document Deployment kube-state-metrics <<<"$out")"
  if [[ -z "$state" ]]; then
    fail "$root must run the kube-state-metrics Deployment OpenCost requires"
  else
    grep -qE '^  namespace: observability$' <<<"$state" || fail "$root: kube-state-metrics must run in observability"
    for image in "$KUBE_STATE_METRICS_IMAGE" "$KUBE_RBAC_PROXY_IMAGE"; do
      grep -qF "image: $image" <<<"$state" || fail "$root: kube-state-metrics must run $image"
    done
    grep -qF -- "- $LABELS_ALLOWLIST" <<<"$state" \
      || fail "$root: kube-state-metrics must expose the service and profile pod labels ($LABELS_ALLOWLIST)"
  fi
  for monitor in node-exporter kube-state-metrics; do
    [[ -n "$(document ServiceMonitor "$monitor" <<<"$out")" ]] || fail "$root must scrape $monitor"
  done
  for rule in node-exporter-rules kube-state-metrics-rules; do
    [[ -z "$(document PrometheusRule "$rule" <<<"$out")" ]] || fail "$root must not add upstream PrometheusRule $rule"
  done
  opencost_monitor="$(document ServiceMonitor opencost <<<"$out")"
  if [[ -z "$opencost_monitor" ]]; then
    fail "$root must scrape OpenCost's exporter"
  else
    for expected in '- opencost' 'app.kubernetes.io/name: opencost' 'port: http' 'path: /metrics' 'honorLabels: true'; do
      grep -qF -- "$expected" <<<"$opencost_monitor" || fail "$root: ServiceMonitor opencost must set $expected"
    done
  fi
done
grep -qE '^  name: opencost$' <<<"$(document ServiceMonitor opencost <<<"$(render infrastructure/profiles/full/prometheus/destinations/eks-full-prod)")" \
  || fail "the full Prometheus destinations must inherit the OpenCost ServiceMonitor"
economical_prometheus="$(render infrastructure/prometheus)"
for pair in DaemonSet:node-exporter Deployment:kube-state-metrics ServiceMonitor:opencost; do
  if [[ -n "$(document "${pair%%:*}" "${pair#*:}" <<<"$economical_prometheus")" ]]; then
    fail "economical infrastructure/prometheus must not render ${pair%%:*} ${pair#*:}"
  fi
done

# --- profile, environment, namespace, and service on business pods ----------
for service in "${SERVICES[@]}"; do
  for environment in "${ENVIRONMENTS[@]}"; do
    overlay="apps/$service/profiles/full/overlays/$environment"
    deployment="$(document Deployment "$service" <<<"$(render "$overlay")")"
    template_labels="$(awk '/^  template:$/ { t = 1; next } t && /^      labels:$/ { l = 1; next } l && /^        / { print; next } l { exit }' <<<"$deployment")"
    selector="$(awk '/^  selector:$/ { s = 1; next } s && /^    / { print; next } s { exit }' <<<"$deployment")"
    grep -qE '^        microtodosuite.io/profile: full$' <<<"$template_labels" \
      || fail "$overlay: Deployment $service pods must carry microtodosuite.io/profile: full"
    grep -qE "^        app.kubernetes.io/name: $service$" <<<"$template_labels" \
      || fail "$overlay: Deployment $service pods must carry app.kubernetes.io/name: $service"
    if grep -qF 'microtodosuite.io/profile' <<<"$selector"; then
      fail "$overlay: Deployment $service must not select on microtodosuite.io/profile, which would change its immutable selector"
    fi
    grep -qE "^  namespace: microtodo-$environment$" <<<"$deployment" \
      || fail "$overlay: Deployment $service must run in microtodo-$environment"
  done
  # A negative check has to distinguish "the label is absent" from "nothing
  # rendered": inside a command substitution, set -e does not stop the script,
  # so a broken overlay would otherwise read as a clean pass.
  economical="apps/$service/profiles/economical/overlays/dev"
  if ! economical_out="$(render "$economical")"; then
    fail "$economical must render for its profile label to be checked"
  elif grep -qF 'microtodosuite.io/profile' <<<"$economical_out"; then
    fail "$economical must not carry the full profile label"
  fi
done

# --- cost dashboard, full Grafana only ---------------------------------------
DASHBOARD=infrastructure/grafana/dashboards/full-profile-cost.yaml
if [[ ! -f "$DASHBOARD" ]]; then
  fail "$DASHBOARD must hold the full-profile cost dashboard"
else
  expressions="$(python3 - "$DASHBOARD" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
match = re.search(r'full-profile-cost\.json: \|\n((?:    .*\n?|\n)+)', text)
if not match:
    sys.exit("no full-profile-cost.json key")
dashboard = json.loads("\n".join(line[4:] for line in match.group(1).splitlines()))
def walk(node):
    if isinstance(node, dict):
        if isinstance(node.get("expr"), str):
            print(node["expr"].replace("\n", " "))
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)
walk(dashboard)
PY
)" || fail "$DASHBOARD must hold valid dashboard JSON under full-profile-cost.json"
  # One panel query has to carry a whole dimension, not just mention its parts
  # somewhere in the dashboard. A pod label is only readable when the query
  # joins kube_pod_labels, so asserting the two names separately would pass on
  # a dashboard whose service panel had lost its join.
  queries() {
    local description="$1" expression needle matched
    shift
    while IFS= read -r expression; do
      matched=1
      for needle in "$@"; do
        [[ "$expression" == *"$needle"* ]] || { matched=0; break; }
      done
      [[ "$matched" == 1 ]] && return 0
    done <<<"$expressions"
    fail "$DASHBOARD: no single panel query $description (needs: $*)"
  }
  queries "names the cluster the cost belongs to" kubecost_cluster_info
  queries "prices the nodes" 'sum(node_total_hourly_cost)'
  queries "allocates compute cost by namespace" \
    'by (namespace)' container_cpu_allocation container_memory_allocation_bytes
  queries "allocates compute cost by service" \
    container_cpu_allocation kube_pod_labels label_app_kubernetes_io_name
  queries "allocates compute cost by profile" \
    container_cpu_allocation kube_pod_labels label_microtodosuite_io_profile
  queries "allocates volume cost by namespace" \
    'by (namespace)' pod_pvc_allocation pv_hourly_cost
fi
for cloud in aws azure; do
  root="infrastructure/profiles/full/grafana/$cloud"
  out="$(render "$root")"
  [[ -n "$(document ConfigMap grafana-dashboards-full-profile-cost <<<"$out")" ]] \
    || fail "$root must render ConfigMap grafana-dashboards-full-profile-cost"
  grep -qE '^ +name: grafana-dashboards-full-profile-cost$' <<<"$(document Deployment grafana <<<"$out")" \
    || fail "$root: Grafana must project grafana-dashboards-full-profile-cost into its dashboards volume"
done
if ! economical_grafana="$(render infrastructure/grafana)"; then
  fail "economical infrastructure/grafana must render for its dashboards to be checked"
elif grep -qF 'grafana-dashboards-full-profile-cost' <<<"$economical_grafana"; then
  fail "economical infrastructure/grafana must not render the full-profile cost dashboard"
fi

if (( failures > 0 )); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: the full profile allocates cost by cluster (per-destination CLUSTER_ID), environment and namespace (microtodo-<environment>), profile and service (pod labels exposed by kube-state-metrics), with node-exporter, kube-state-metrics, and OpenCost scraped and a cost dashboard querying every dimension\n'

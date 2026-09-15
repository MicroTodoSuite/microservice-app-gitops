#!/usr/bin/env bash
# Full-profile service runtime render test (spec 009, T090, research.md
# Decision 23): the probes and resource bounds the full overlays already render,
# business ServiceMonitors that scrape each full destination's own namespace
# (slice 1), disruption budgets with soft topology spread (slice 2), and
# bounded KEDA scaling with only the KEDA operator reaching Prometheus (slice 3),
# and default-off feature toggles beside the controlled ConfigMaps (slice 4).
# Offline by design: no live cluster is touched.
set -euo pipefail

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

SERVICES=(auth-api todos-api users-api frontend log-message-processor)
ENVIRONMENTS=(dev staging prod)

# --- pinned: probes and resource bounds already render -----------------------
# The prod Rollouts take their pod template from the Deployment (workloadRef),
# so the Deployment carries both in every environment.
for service in "${SERVICES[@]}"; do
  for environment in "${ENVIRONMENTS[@]}"; do
    overlay="apps/$service/profiles/full/overlays/$environment"
    if ! out="$(render "$overlay")"; then
      fail "$overlay must render"
      continue
    fi
    deployment="$(document Deployment "$service" <<<"$out")"
    if [[ -z "$deployment" ]]; then
      fail "$overlay must render Deployment $service"
      continue
    fi
    for probe in startupProbe readinessProbe livenessProbe; do
      grep -qE "^ +$probe:$" <<<"$deployment" || fail "$overlay: Deployment $service must define $probe"
    done
    containers="$(grep -cE '^ +(- )?image: ' <<<"$deployment" || true)"
    cpu="$(grep -cE '^ +cpu: ' <<<"$deployment" || true)"
    memory="$(grep -cE '^ +memory: ' <<<"$deployment" || true)"
    [[ "$cpu" == $((containers * 2)) && "$memory" == $((containers * 2)) ]] \
      || fail "$overlay: every container of Deployment $service must request and limit CPU and memory ($containers containers, $cpu cpu and $memory memory values)"
    if [[ "$environment" == prod ]]; then
      rollout="$(document Rollout "$service" <<<"$out")"
      if [[ -n "$rollout" ]]; then
        reference="$(awk '/^  workloadRef:$/ { f = 1; next } f && /^    / { print; next } { f = 0 }' <<<"$rollout")"
        grep -qE '^    kind: Deployment$' <<<"$reference" && grep -qE "^    name: $service$" <<<"$reference" \
          || fail "$overlay: Rollout $service must take its pod template from Deployment $service"
      fi
    fi
  done
done

# --- slice 1: business ServiceMonitors scrape their destination's namespace ---
# Print the namespaces a ServiceMonitor selects, one per line.
monitor_namespaces() {
  awk '/^    matchNames:$/ { f = 1; next } f && /^    - / { print $2; next } { f = 0 }'
}

economical="$(render infrastructure/prometheus)"
for service in "${SERVICES[@]}"; do
  # Economical production runs the canary, so its stable Services are scraped
  # beside dev's (spec 006 T023b); every full destination narrows the list to
  # its own namespace below.
  [[ "$(document ServiceMonitor "$service" <<<"$economical" | monitor_namespaces | paste -sd ' ' -)" == "microtodo-dev microtodo-prod" ]] \
    || fail "economical infrastructure/prometheus must keep ServiceMonitor $service on microtodo-dev and microtodo-prod"
done

for environment in "${ENVIRONMENTS[@]}"; do
  root="infrastructure/profiles/full/prometheus/destinations/eks-full-$environment"
  if ! out="$(render "$root")"; then
    fail "$root must render"
    continue
  fi
  for service in "${SERVICES[@]}"; do
    monitor="$(document ServiceMonitor "$service" <<<"$out")"
    if [[ -z "$monitor" ]]; then
      fail "$root must render ServiceMonitor $service"
      continue
    fi
    namespaces="$(monitor_namespaces <<<"$monitor" | paste -sd ' ' -)"
    [[ "$namespaces" == "microtodo-$environment" ]] \
      || fail "$root: ServiceMonitor $service must select only microtodo-$environment, found: ${namespaces:-none}"
    # The canary strategy is composed only in prod, so its monitors stay there.
    canary="$(document ServiceMonitor "$service-canary" <<<"$out" | monitor_namespaces | paste -sd ' ' -)"
    [[ "$canary" == microtodo-prod ]] \
      || fail "$root: ServiceMonitor $service-canary must keep selecting microtodo-prod, found: ${canary:-none}"
  done
done

# --- slice 2: disruption budgets and soft topology spread --------------------
# maxUnavailable 1 never blocks a drain of a single replica, and ScheduleAnyway
# leaves no pod Pending while a cluster runs one stable node (Decision 23).
POD_LABELS=(app.kubernetes.io/name app.kubernetes.io/part-of app.kubernetes.io/component)

# Print "key=value" for each label under the first matchLabels: block.
match_labels() {
  awk '
    /^ *matchLabels:$/ { if (seen) exit; seen = 1; match($0, /^ */); indent = RLENGTH; next }
    seen && match($0, /^ */) && RLENGTH > indent && /^ *[^ -][^:]*: / {
      line = $0; sub(/^ */, "", line); key = line; sub(/: .*/, "", key); value = line; sub(/^[^:]*: /, "", value)
      print key "=" value; next
    }
    seen { exit }
  ' | sort
}

for service in "${SERVICES[@]}"; do
  expected_labels="$(printf '%s\n' "app.kubernetes.io/component=business-service" "app.kubernetes.io/name=$service" "app.kubernetes.io/part-of=microtodosuite" | sort)"
  for environment in "${ENVIRONMENTS[@]}"; do
    overlay="apps/$service/profiles/full/overlays/$environment"
    out="$(render "$overlay" 2>/dev/null)" || continue
    budget="$(document PodDisruptionBudget "$service" <<<"$out")"
    if [[ -z "$budget" ]]; then
      fail "$overlay must render PodDisruptionBudget $service"
    else
      grep -qE '^  maxUnavailable: 1$' <<<"$budget" \
        || fail "$overlay: PodDisruptionBudget $service must set maxUnavailable: 1"
      if grep -qE '^  minAvailable:' <<<"$budget"; then
        fail "$overlay: PodDisruptionBudget $service must not set minAvailable, which blocks draining a single replica"
      fi
      [[ "$(match_labels <<<"$budget")" == "$expected_labels" ]] \
        || fail "$overlay: PodDisruptionBudget $service must select exactly the ${#POD_LABELS[@]} base pod labels of $service"
    fi
    deployment="$(document Deployment "$service" <<<"$out")"
    spread="$(awk '/^      topologySpreadConstraints:$/ { f = 1; next } f && /^      [ -]/ { print; next } f { exit }' <<<"$deployment")"
    for key in kubernetes.io/hostname topology.kubernetes.io/zone; do
      entry="$(awk -v key="$key" '
        /^      - / { if (block ~ ("topologyKey: " key "\n")) printf "%s", block; block = "" }
        { block = block $0 "\n" }
        END { if (block ~ ("topologyKey: " key "\n")) printf "%s", block }
      ' <<<"$spread")"
      if [[ -z "$entry" ]]; then
        fail "$overlay: Deployment $service must spread over $key"
        continue
      fi
      grep -qE '^ +maxSkew: 1$' <<<"$entry" || fail "$overlay: the $key spread of $service must set maxSkew: 1"
      grep -qE '^ +whenUnsatisfiable: ScheduleAnyway$' <<<"$entry" \
        || fail "$overlay: the $key spread of $service must set whenUnsatisfiable: ScheduleAnyway"
      grep -qE "^ +app.kubernetes.io/name: $service$" <<<"$entry" \
        || fail "$overlay: the $key spread of $service must select app.kubernetes.io/name: $service"
    done
    [[ "$(grep -cE '^ +topologyKey: ' <<<"$spread" || true)" == 2 ]] \
      || fail "$overlay: Deployment $service must declare exactly the hostname and zone spread constraints"
  done
  # The economical profile does not change (FR-002).
  economical_out="$(render "apps/$service/profiles/economical/overlays/dev")"
  if grep -qE '^kind: PodDisruptionBudget$' <<<"$economical_out"; then
    fail "apps/$service/profiles/economical/overlays/dev must not render a PodDisruptionBudget"
  fi
  if grep -qE '^ +topologySpreadConstraints:$' <<<"$economical_out"; then
    fail "apps/$service/profiles/economical/overlays/dev must not render topology spread constraints"
  fi
done

# --- slice 3: bounded KEDA scaling on request rate ---------------------------
# The four HTTP services scale on their recorded request rate; replicas leave
# Git so Argo CD's self-heal does not undo KEDA (Decision 23).
HTTP_SERVICES=(auth-api todos-api users-api frontend)
declare -A MIN_REPLICAS=(
  [auth-api:dev]=1 [auth-api:staging]=2 [auth-api:prod]=3
  [todos-api:dev]=1 [todos-api:staging]=1 [todos-api:prod]=1
  [users-api:dev]=1 [users-api:staging]=1 [users-api:prod]=1
  [frontend:dev]=1 [frontend:staging]=2 [frontend:prod]=2
)
PROMETHEUS_ADDRESS='http://prometheus-k8s.observability.svc:9090'

# Print the value of a "key: value" line, without surrounding quotes.
scalar() {
  awk -v key="$1" '
    $0 ~ ("^ *(- )?" key ": ") {
      value = $0; sub("^ *(- )?" key ": ", "", value)
      if (value ~ /^".*"$/ || value ~ /^'\''.*'\''$/) value = substr(value, 2, length(value) - 2)
      print value; exit
    }
  '
}

for service in "${HTTP_SERVICES[@]}"; do
  for environment in "${ENVIRONMENTS[@]}"; do
    overlay="apps/$service/profiles/full/overlays/$environment"
    out="$(render "$overlay" 2>/dev/null)" || continue
    scaled="$(document ScaledObject "$service" <<<"$out")"
    if [[ -z "$scaled" ]]; then
      fail "$overlay must render ScaledObject $service"
      continue
    fi
    if [[ "$environment" == prod ]]; then
      target_kind=Rollout target_api=argoproj.io/v1alpha1
    else
      target_kind=Deployment target_api=apps/v1
    fi
    reference="$(awk '/^  scaleTargetRef:$/ { f = 1; next } f && /^    / { print; next } { f = 0 }' <<<"$scaled")"
    [[ "$(scalar kind <<<"$reference")" == "$target_kind" && "$(scalar name <<<"$reference")" == "$service" \
       && "$(scalar apiVersion <<<"$reference")" == "$target_api" ]] \
      || fail "$overlay: ScaledObject $service must target $target_api $target_kind $service"
    expected_min="${MIN_REPLICAS[$service:$environment]}"
    grep -qE "^  minReplicaCount: $expected_min$" <<<"$scaled" \
      || fail "$overlay: ScaledObject $service must set minReplicaCount: $expected_min"
    grep -qE '^  maxReplicaCount: 5$' <<<"$scaled" \
      || fail "$overlay: ScaledObject $service must set maxReplicaCount: 5"
    [[ "$(grep -cE '^  - ' <<<"$(awk '/^  triggers:$/ { f = 1; next } f && /^  [ -]/ { print; next } f { exit }' <<<"$scaled")" || true)" == 1 ]] \
      || fail "$overlay: ScaledObject $service must have exactly one trigger"
    [[ "$(scalar type <<<"$scaled")" == prometheus ]] \
      || fail "$overlay: ScaledObject $service must use the prometheus trigger"
    [[ "$(scalar serverAddress <<<"$scaled")" == "$PROMETHEUS_ADDRESS" ]] \
      || fail "$overlay: ScaledObject $service must query $PROMETHEUS_ADDRESS"
    [[ "$(scalar query <<<"$scaled")" == "sum(workload:http_requests:rate5m{workload=\"$service\"})" ]] \
      || fail "$overlay: ScaledObject $service must query sum(workload:http_requests:rate5m{workload=\"$service\"}), found: $(scalar query <<<"$scaled")"
    [[ "$(scalar threshold <<<"$scaled")" == 10 ]] \
      || fail "$overlay: ScaledObject $service must scale at 10 requests per second per replica"
    # KEDA owns the count, so the target must not declare replicas in Git.
    if grep -qE '^  replicas:' <<<"$(document "$target_kind" "$service" <<<"$out")"; then
      fail "$overlay: $target_kind $service must not declare replicas, or Argo CD self-heal undoes KEDA"
    fi
  done
done

for environment in "${ENVIRONMENTS[@]}"; do
  if grep -qE '^kind: ScaledObject$' <<<"$(render "apps/log-message-processor/profiles/full/overlays/$environment")"; then
    fail "apps/log-message-processor/profiles/full/overlays/$environment must not scale: each Redis pub/sub subscriber processes every message"
  fi
done
for service in "${SERVICES[@]}"; do
  if grep -qE '^kind: ScaledObject$' <<<"$(render "apps/$service/profiles/economical/overlays/dev")"; then
    fail "apps/$service/profiles/economical/overlays/dev must not render a ScaledObject"
  fi
done

# Only the KEDA operator may reach Prometheus, and only on 9090: one ingress
# peer that selects its namespace and its pods together.
KEDA_PEER=$'    - namespaceSelector:\n        matchLabels:\n          kubernetes.io/metadata.name: keda\n      podSelector:\n        matchLabels:\n          app: keda-operator\n'
keda_rules() {
  awk '
    /^  ingress:$/ { f = 1; next }
    f && /^  - / { if (rule != "") print rule "\034"; rule = $0 "\n"; next }
    f && /^   / { rule = rule $0 "\n"; next }
    f { f = 0 }
    END { if (rule != "") print rule "\034" }
  ' | awk 'BEGIN { RS = "\034\n" } /kubernetes.io\/metadata.name: keda\n/ { printf "%s\034", $0 }'
}
for cloud in aws azure; do
  root="infrastructure/profiles/full/prometheus/$cloud"
  policy="$(document NetworkPolicy prometheus-k8s <<<"$(render "$root")")"
  rules="$(keda_rules <<<"$policy")"
  count="$(tr -cd '\034' <<<"$rules" | wc -c)"
  if [[ "$count" != 1 ]]; then
    fail "$root: NetworkPolicy prometheus-k8s must have exactly one ingress rule for the keda namespace, found $count"
  else
    rule="${rules%$'\034'}"
    [[ "$rule" == *"$KEDA_PEER"* ]] \
      || fail "$root: the keda ingress rule must select namespace keda and pods app: keda-operator in one peer"
    grep -qE '^    - port: 9090$' <<<"$rule" && [[ "$(grep -cE '^    - port: ' <<<"$rule")" == 1 ]] \
      || fail "$root: the keda ingress rule must open only port 9090"
  fi
done
if grep -q 'kubernetes.io/metadata.name: keda' <<<"$(document NetworkPolicy prometheus-k8s <<<"$(render infrastructure/prometheus)")"; then
  fail "economical infrastructure/prometheus must not admit keda"
fi

# --- slice 4: controlled configuration and default-off feature toggles ------
# Each service container reads its GitOps-controlled settings and a hashed
# feature-toggle ConfigMap; every toggle is FEATURE_<NAME>, "false", and
# documented (FR-034, Decision 23).
TOGGLE_CONTRACT=docs/feature-toggles.md

# Print one container's block, by container name, from a rendered Deployment.
container_block() {
  awk -v name="$1" '
    function check() { if (!done && block ~ ("\n(      - |        )name: " name "\n")) { printf "%s", block; done = 1 } }
    /^      containers:$/ { f = 1; block = ""; next }
    f && /^      - / { check(); block = "\n" $0 "\n"; next }
    f && /^        / { block = block $0 "\n"; next }
    f { check(); f = 0 }
    END { if (f) check() }
  '
}

# Print "name optional" for each configMapRef under a container's envFrom.
env_from_config_maps() {
  awk '
    /^      (- |  )envFrom:$/ { f = 1; next }
    f && /^        - configMapRef:$/ { if (name != "") print name, optional; name = ""; optional = "false"; next }
    f && /^            name: / { name = $2; next }
    f && /^            optional: / { optional = $2; next }
    f && /^        - / { next }
    f && /^          / { next }
    f { f = 0 }
    END { if (name != "") print name, optional }
  '
}

[[ -f "$TOGGLE_CONTRACT" ]] || fail "$TOGGLE_CONTRACT must document the feature-toggle contract"
for service in "${SERVICES[@]}"; do
  for environment in "${ENVIRONMENTS[@]}"; do
    overlay="apps/$service/profiles/full/overlays/$environment"
    out="$(render "$overlay" 2>/dev/null)" || continue
    toggles_names="$(awk '/^---$/ { k = "" } /^kind: / { k = $2 } k == "ConfigMap" && /^  name: / { print $2 }' <<<"$out" \
      | grep -E "^$service-feature-toggles-[a-z0-9]{10}$" || true)"
    if [[ "$(grep -c . <<<"$toggles_names" || true)" != 1 ]]; then
      fail "$overlay must render exactly one hashed ConfigMap $service-feature-toggles, found: ${toggles_names:-none}"
      continue
    fi
    toggles="$(document ConfigMap "$toggles_names" <<<"$out")"
    grep -qE "^    microtodosuite.io/feature-toggle-contract: $TOGGLE_CONTRACT$" <<<"$toggles" \
      || fail "$overlay: ConfigMap $toggles_names must carry microtodosuite.io/feature-toggle-contract: $TOGGLE_CONTRACT"
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      key="${entry%%:*}" value="${entry#*: }"
      [[ "$key" =~ ^FEATURE_[A-Z0-9_]+$ ]] || fail "$overlay: feature toggle $key must be named FEATURE_<NAME>"
      [[ "$value" == '"false"' || "$value" == "'false'" ]] \
        || fail "$overlay: feature toggle $key must default to \"false\", found: $value"
      grep -qE "^\| $service \| \`$key\` \| \`\"false\"\` \| [^|]*[^ |][^|]* \| [^|]*[^ |][^|]* \|$" "$TOGGLE_CONTRACT" 2>/dev/null \
        || fail "$overlay: feature toggle $key must have a row with its owner and purpose in $TOGGLE_CONTRACT"
    done < <(awk '/^data:$/ { f = 1; next } f && /^  [^ ]/ { sub(/^  /, ""); print; next } f { exit }' <<<"$toggles")
    sources="$(document Deployment "$service" <<<"$out" | container_block "$service" | env_from_config_maps)"
    grep -qx "$toggles_names false" <<<"$sources" \
      || fail "$overlay: container $service must read ConfigMap $toggles_names through envFrom, not optionally"
    grep -qx "$service-config false" <<<"$sources" \
      || fail "$overlay: container $service must keep reading its controlled ConfigMap $service-config"
  done
  if grep -qE "^  name: $service-feature-toggles" <<<"$(render "apps/$service/profiles/economical/overlays/dev")"; then
    fail "apps/$service/profiles/economical/overlays/dev must not render feature toggles"
  fi
done

if (( failures > 0 )); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: the five services render probes and bounded resources in every full overlay, each full destination scrapes its own business namespace, every full service has a one-pod disruption budget and a soft hostname and zone spread, and the four HTTP services scale between their replicas and 5 on request rate with only KEDA reaching Prometheus, and every full service reads a documented, default-off feature-toggle ConfigMap beside its controlled settings\n'

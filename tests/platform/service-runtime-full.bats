#!/usr/bin/env bash
# Full-profile service runtime render test (spec 009, T090, research.md
# Decision 23): the probes and resource bounds the full overlays already render,
# business ServiceMonitors that scrape each full destination's own namespace
# (slice 1), and disruption budgets with soft topology spread (slice 2).
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
  [[ "$(document ServiceMonitor "$service" <<<"$economical" | monitor_namespaces)" == microtodo-dev ]] \
    || fail "economical infrastructure/prometheus must keep ServiceMonitor $service on microtodo-dev"
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

if (( failures > 0 )); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: the five services render probes and bounded resources in every full overlay, each full destination scrapes its own business namespace, and every full service has a one-pod disruption budget and a soft hostname and zone spread\n'

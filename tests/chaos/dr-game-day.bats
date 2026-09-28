#!/usr/bin/env bash
# Disaster-recovery game-day scenario contract (spec 009 T123, US5).
#
# Pins what T135 must deliver under experiments/full-profile/: the five
# GitOps-owned scenarios of contracts/dr-game-day-contract.md, each bounded by
# an exact selector and duration, each carrying its abort boundary, each
# disabled until a reviewed commit activates it on its one approved full
# destination, and none ever reachable from the economical cluster.
#
# Scenario roots (one Kustomize root each, never a Component):
#
#   pod-termination   PodChaos pod-kill, mode one, one business service in
#                     microtodo-prod, <= 5m, on eks-full-prod
#   network-latency   NetworkChaos delay on one service path: source and
#                     target are two named business services in
#                     microtodo-prod, latency <= 5s, <= 5m, on eks-full-prod
#   redis-saturation  StressChaos on the microtodo-prod Redis only, <= 4
#                     workers, <= 5m, on eks-full-prod
#   aws-prod-outage   PodChaos pod-failure on the istio-system ingress
#                     gateway, <= 10m, on eks-full-prod; AKS survives
#   azure-outage      PodChaos pod-failure on the istio-system ingress
#                     gateway, <= 10m, on aks-dr; AWS production survives
#
# Every chaos resource carries the labels microtodosuite.io/experiment=<name>
# and microtodosuite.io/target-cluster=<root>. Every scenario also renders a
# ConfigMap <name>-steady-state whose data names the target cluster, the
# maximum duration, the abort procedure (git-revert), every abort condition
# of the contract, and the steady state that must hold before and after.
#
# Offline by design: it renders Git and never contacts a cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLATTEN="$ROOT/tests/lib/yaml-flatten.awk"
EXPERIMENTS="$ROOT/experiments/full-profile"

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

# Values of one flattened path in one document.
field() { awk -F'\t' -v d="$2" -v p="$3" '$1 == d { k = $2; sub(/=.*/, "", k); if (k == p) { v = $2; sub(/^[^=]*=/, "", v); print v } }' "$1"; }
# Every distinct path in one document that starts with a prefix.
paths_under() { awk -F'\t' -v d="$2" -v p="$3" '$1 == d { k = $2; sub(/=.*/, "", k); if (index(k, p) == 1) print k }' "$1" | sort -u; }

# Go duration (h/m/s only) to seconds; prints nothing for anything else.
seconds() {
  local value="$1" total=0 number unit
  [[ "$value" =~ ^([0-9]+h)?([0-9]+m)?([0-9]+s)?$ && -n "$value" ]] || return 0
  while [[ "$value" =~ ^([0-9]+)([hms])(.*)$ ]]; do
    number="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"; value="${BASH_REMATCH[3]}"
    case "$unit" in h) total=$((total + number * 3600)) ;; m) total=$((total + number * 60)) ;; s) total=$((total + number)) ;; esac
  done
  printf '%s\n' "$total"
}

# Latency (ms/s) to milliseconds; prints nothing for anything else.
milliseconds() {
  if [[ "$1" =~ ^([0-9]+)ms$ ]]; then printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$1" =~ ^([0-9]+)s$ ]]; then printf '%s\n' "$((BASH_REMATCH[1] * 1000))"
  fi
}

services=(auth-api todos-api users-api frontend log-message-processor)
is_service() { local s; for s in "${services[@]}"; do [[ "$1" == "$s" ]] && return 0; done; return 1; }

abort_conditions=(
  economical-regression
  selector-expansion
  both-destinations-unhealthy
  duration-exceeded
  release-digest-divergence
  telemetry-unavailable
  operator-abort
)

# name | kind | action | max seconds | target cluster | namespace | surviving destination
scenarios=(
  "pod-termination|PodChaos|pod-kill|300|eks-full-prod|microtodo-prod|"
  "network-latency|NetworkChaos|delay|300|eks-full-prod|microtodo-prod|"
  "redis-saturation|StressChaos||300|eks-full-prod|microtodo-prod|"
  "aws-prod-outage|PodChaos|pod-failure|600|eks-full-prod|istio-system|aks-dr"
  "azure-outage|PodChaos|pod-failure|600|aks-dr|istio-system|eks-full-prod"
)

# Chaos kinds the vendored Chaos Mesh actually serves.
served_kinds="$(render "$ROOT/infrastructure/chaos-mesh" \
  | awk '/^kind: CustomResourceDefinition/{c=1} c && /^    kind: /{print $2; c=0}' | sort -u)"

# --- every scenario root exists, renders, validates, and is bounded --------
for spec in "${scenarios[@]}"; do
  IFS='|' read -r name kind action max_seconds cluster namespace survivor <<<"$spec"
  directory="$EXPERIMENTS/$name"
  label="experiments/full-profile/$name"

  if [[ ! -f "$directory/kustomization.yaml" ]]; then
    fail "$label/kustomization.yaml is missing"
    continue
  fi
  if grep -q '^kind: Component' "$directory/kustomization.yaml"; then
    fail "$label must be a Kustomize root, not a Component"
  fi

  raw="$workdir/$name.yaml"
  flat="$workdir/$name.flat"
  render "$directory" >"$raw" 2>"$workdir/$name.err" || {
    fail "$label does not render: $(cat "$workdir/$name.err")"
    continue
  }
  awk -f "$FLATTEN" "$raw" >"$flat"

  validation="$(kubeconform -strict -ignore-missing-schemas -summary <"$raw" 2>&1)" \
    || fail "$label does not pass kubeconform: $validation"
  grep -q 'Invalid: 0, Errors: 0' <<<"$validation" \
    || fail "$label has invalid or errored resources: $validation"

  grep -q 'CHANGEME' "$raw" && fail "$label still carries a CHANGEME placeholder"
  grep -q '^kind: Secret$' "$raw" && fail "$label must not render a Secret"
  grep -Eq '^[[:space:]]+image:' "$raw" && fail "$label must not render a workload image"

  # A recurring or orchestrated experiment keeps firing after the Git revert
  # that is the only approved abort, so neither kind is allowed.
  if grep -Eq '^kind: (Schedule|Workflow)$' "$raw"; then
    fail "$label must not render a Schedule or Workflow: a revert is the abort and nothing may re-run afterwards"
  fi

  chaos_docs="$(awk -F'\t' '$2 ~ /^apiVersion=chaos-mesh\.org\// {print $1}' "$flat" | sort -u)"
  [[ -n "$chaos_docs" ]] || fail "$label renders no Chaos Mesh resource"
  count="$(wc -w <<<"$chaos_docs")"
  [[ "$count" -eq 1 ]] || fail "$label must render exactly one chaos resource, found $count"

  for doc in $chaos_docs; do
    rendered_kind="$(field "$flat" "$doc" kind)"
    [[ "$rendered_kind" == "$kind" ]] || fail "$label must render a $kind, found $rendered_kind"
    grep -Fqx "$rendered_kind" <<<"$served_kinds" \
      || fail "$label renders $rendered_kind, which the vendored Chaos Mesh does not serve"

    if [[ -n "$action" ]]; then
      [[ "$(field "$flat" "$doc" spec.action)" == "$action" ]] \
        || fail "$label must use action $action"
    fi

    [[ "$(field "$flat" "$doc" metadata.labels.microtodosuite.io/experiment)" == "$name" ]] \
      || fail "$label must label its chaos resource microtodosuite.io/experiment=$name"
    [[ "$(field "$flat" "$doc" metadata.labels.microtodosuite.io/target-cluster)" == "$cluster" ]] \
      || fail "$label must label its chaos resource microtodosuite.io/target-cluster=$cluster"

    # Duration: present, parseable, and inside the contract's maximum.
    duration="$(field "$flat" "$doc" spec.duration)"
    duration_seconds="$(seconds "$duration")"
    if [[ -z "$duration_seconds" || "$duration_seconds" -le 0 ]]; then
      fail "$label must set a positive h/m/s spec.duration, found '${duration:-none}'"
    elif [[ "$duration_seconds" -gt "$max_seconds" ]]; then
      fail "$label duration $duration exceeds the contract maximum of $((max_seconds / 60))m"
    fi

    # Selector: exactly one approved namespace and one exact label, nothing
    # that widens it.
    mapfile -t selected_namespaces < <(field "$flat" "$doc" 'spec.selector.namespaces[]')
    if [[ "${#selected_namespaces[@]}" -ne 1 || "${selected_namespaces[0]:-}" != "$namespace" ]]; then
      fail "$label must select exactly namespace $namespace, found: ${selected_namespaces[*]:-none}"
    fi
    widening="$(paths_under "$flat" "$doc" spec.selector. \
      | grep -Ev '^spec\.selector\.(namespaces\[\]|labelSelectors\..+)$' || true)"
    [[ -z "$widening" ]] || fail "$label selector may use only namespaces and labelSelectors, found: $(tr '\n' ' ' <<<"$widening")"
    label_keys="$(paths_under "$flat" "$doc" spec.selector.labelSelectors.)"
    [[ "$(wc -l <<<"$label_keys")" -eq 1 && -n "$label_keys" ]] \
      || fail "$label selector must use exactly one label"

    mode="$(field "$flat" "$doc" spec.mode)"
    case "$name" in
      pod-termination|network-latency|redis-saturation)
        [[ "$mode" == "one" ]] || fail "$label must use mode one, found '${mode:-none}'"
        ;;
      *)
        [[ "$mode" == "all" ]] || fail "$label must take every ingress gateway pod down (mode all), found '${mode:-none}'"
        ;;
    esac

    selected_name="$(field "$flat" "$doc" spec.selector.labelSelectors.app.kubernetes.io/name)"
    case "$name" in
      pod-termination)
        is_service "$selected_name" || fail "$label must target one business service by app.kubernetes.io/name, found '${selected_name:-none}'"
        ;;
      network-latency)
        is_service "$selected_name" || fail "$label source must be one business service by app.kubernetes.io/name, found '${selected_name:-none}'"
        latency_ms="$(milliseconds "$(field "$flat" "$doc" spec.delay.latency)")"
        if [[ -z "$latency_ms" || "$latency_ms" -le 0 || "$latency_ms" -gt 5000 ]]; then
          fail "$label must set a spec.delay.latency between 1ms and 5s"
        fi
        mapfile -t target_namespaces < <(field "$flat" "$doc" 'spec.target.selector.namespaces[]')
        if [[ "${#target_namespaces[@]}" -ne 1 || "${target_namespaces[0]:-}" != "$namespace" ]]; then
          fail "$label path target must select exactly namespace $namespace"
        fi
        target_name="$(field "$flat" "$doc" spec.target.selector.labelSelectors.app.kubernetes.io/name)"
        if ! is_service "$target_name" || [[ "$target_name" == "$selected_name" ]]; then
          fail "$label path target must be a second business service, found '${target_name:-none}'"
        fi
        [[ "$(field "$flat" "$doc" spec.target.mode)" == "all" ]] \
          || fail "$label path target must include every pod of the target service (target mode all)"
        target_widening="$(paths_under "$flat" "$doc" spec.target.selector. \
          | grep -Ev '^spec\.target\.selector\.(namespaces\[\]|labelSelectors\.app\.kubernetes\.io/name)$' || true)"
        [[ -z "$target_widening" ]] || fail "$label path target selector may use only its namespace and app.kubernetes.io/name"
        ;;
      redis-saturation)
        [[ "$selected_name" == "redis" ]] || fail "$label must target only the Redis workload (app.kubernetes.io/name=redis)"
        stressors="$(paths_under "$flat" "$doc" spec.stressors.)"
        [[ -n "$stressors" ]] || fail "$label must declare spec.stressors"
        while IFS= read -r workers_path; do
          [[ -z "$workers_path" ]] && continue
          workers="$(field "$flat" "$doc" "$workers_path")"
          if [[ ! "$workers" =~ ^[0-9]+$ || "$workers" -lt 1 || "$workers" -gt 4 ]]; then
            fail "$label $workers_path must be between 1 and 4, found '$workers'"
          fi
        done < <(grep -E '^spec\.stressors\.[a-z]+\.workers$' <<<"$stressors" || true)
        grep -Eq '^spec\.stressors\.[a-z]+\.workers$' <<<"$stressors" \
          || fail "$label must bound every stressor with workers"
        ;;
      aws-prod-outage|azure-outage)
        gateway="$(field "$flat" "$doc" spec.selector.labelSelectors.istio)"
        [[ "$gateway" == "ingressgateway" ]] || fail "$label must select only the Istio ingress gateway (istio=ingressgateway)"
        ;;
    esac
  done

  # --- steady state and abort boundary -------------------------------------
  steady_doc="$(awk -F'\t' -v n="$name-steady-state" '
    $2 == "kind=ConfigMap" { cm[$1] = 1 }
    $2 == ("metadata.name=" n) { named[$1] = 1 }
    END { for (d in cm) if (d in named) print d }' "$flat")"
  if [[ -z "$steady_doc" ]]; then
    fail "$label must render ConfigMap $name-steady-state"
  else
    [[ "$(field "$flat" "$steady_doc" data.targetCluster)" == "$cluster" ]] \
      || fail "$label steady state must name targetCluster $cluster"
    steady_max="$(seconds "$(field "$flat" "$steady_doc" data.maxDuration)")"
    [[ "$steady_max" == "$max_seconds" ]] \
      || fail "$label steady state must declare maxDuration $((max_seconds / 60))m"
    [[ "$(field "$flat" "$steady_doc" data.abortProcedure)" == "git-revert" ]] \
      || fail "$label steady state must declare abortProcedure git-revert"
    [[ -n "$(field "$flat" "$steady_doc" data.steadyState)" ]] \
      || fail "$label steady state must describe the steadyState that holds before and after"
    steady_raw="$(awk -v n="$name-steady-state" '
      function flush() { if (doc ~ /\nkind: ConfigMap\n/ && doc ~ ("\n  name: " n "\n")) printf "%s", doc; doc = "\n" }
      BEGIN { doc = "\n" } /^---$/ { flush(); next } { doc = doc $0 "\n" } END { flush() }' "$raw")"
    for condition in "${abort_conditions[@]}"; do
      grep -Eq "^[[:space:]]+- $condition\$" <<<"$steady_raw" \
        || fail "$label steady state abortConditions must list $condition"
    done
    if [[ -n "$survivor" ]]; then
      [[ "$(field "$flat" "$steady_doc" data.survivingDestination)" == "$survivor" ]] \
        || fail "$label steady state must name survivingDestination $survivor"
      [[ "$(seconds "$(field "$flat" "$steady_doc" data.recoveryObjective)")" == "600" ]] \
        || fail "$label steady state must declare recoveryObjective 10m"
    fi
  fi
done

# --- no unapproved scenario directory ---------------------------------------
if [[ -d "$EXPERIMENTS" ]]; then
  while IFS= read -r directory; do
    base="$(basename "$directory")"
    case "$base" in
      pod-termination|network-latency|redis-saturation|aws-prod-outage|azure-outage) ;;
      *) fail "experiments/full-profile/$base is not a scenario of the DR game-day contract" ;;
    esac
  done < <(find "$EXPERIMENTS" -mindepth 1 -maxdepth 1 -type d | sort)
  [[ ! -f "$EXPERIMENTS/kustomization.yaml" ]] \
    || fail "experiments/full-profile must not aggregate its scenarios in one kustomization"
fi

# --- disabled by default, never economical ---------------------------------
# Activation is a reviewed commit that names one scenario in the
# activation-infrastructure list of its own target root. Planned inventories
# are documentation and may mention a scenario; nothing else may.
active=0
while IFS=: read -r file _; do
  relative="${file#"$ROOT"/}"
  case "$relative" in
    clusters/eks-full-prod/activation-infrastructure.yaml|clusters/aks-dr/activation-infrastructure.yaml) ;;
    clusters/*/planned-inventory.yaml) continue ;;
    *) fail "$relative references experiments/full-profile; only the eks-full-prod or aks-dr activation list may activate a scenario"; continue ;;
  esac
  root_name="$(cut -d/ -f2 <<<"$relative")"
  while IFS= read -r referenced; do
    active=$((active + 1))
    for spec in "${scenarios[@]}"; do
      IFS='|' read -r name _ _ _ cluster _ _ <<<"$spec"
      if [[ "$referenced" == "$name" && "$cluster" != "$root_name" ]]; then
        fail "$relative activates $name, whose approved target is $cluster"
      fi
    done
  done < <(grep -oE 'experiments/full-profile/[a-z-]+' "$file" | cut -d/ -f3)
done < <(grep -rlE 'experiments/full-profile' "$ROOT/clusters" "$ROOT/infrastructure" "$ROOT/environments" "$ROOT/apps" 2>/dev/null \
  | sed 's/$/:/' || true)
[[ "$active" -le 1 ]] || fail "at most one game-day scenario may be active at a time, found $active"

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d DR game-day scenario violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: all five DR game-day scenarios render bounded, exactly selected, abortable by revert, and disabled outside one approved full destination.\n'

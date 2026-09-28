#!/usr/bin/env bash
# Static contract for service tracing (spec 010, T002).
#
# Every service in every economical environment receives the same tracing
# destination from its base ConfigMap, no overlay overrides it, and business
# pods may reach Jaeger's OTLP/gRPC port and nothing else
# (specs/010-service-tracing/contracts/tracing-configuration.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

command -v yq >/dev/null || { printf 'FAIL: yq is required\n' >&2; exit 1; }

render() {
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

ENDPOINT="http://jaeger-collector.observability.svc:4317"
SERVICES=(auth-api todos-api users-api frontend log-message-processor)
ENVIRONMENTS=(dev staging prod demo)

# --- Tracing destination for every service and economical environment -------
for service in "${SERVICES[@]}"; do
  for environment in "${ENVIRONMENTS[@]}"; do
    overlay="apps/$service/profiles/economical/overlays/$environment"
    if ! out="$(render "$overlay" 2>&1)"; then
      fail "$overlay does not render"
      continue
    fi

    container="select(.kind == \"Deployment\" and .metadata.name == \"$service\") | .spec.template.spec.containers[] | select(.name == \"$service\")"
    config_map="$(yq ea "$container | (.envFrom // [])[] | .configMapRef.name | select(. != null)" <<<"$out" | head -1)"
    if [[ -z "$config_map" ]]; then
      fail "$overlay: the $service container loads no ConfigMap through envFrom"
      continue
    fi

    endpoint="$(yq ea "select(.kind == \"ConfigMap\" and .metadata.name == \"$config_map\") | .data.OTEL_EXPORTER_OTLP_ENDPOINT // \"\"" <<<"$out")"
    [[ "$endpoint" == "$ENDPOINT" ]] \
      || fail "$overlay: ConfigMap $config_map must set OTEL_EXPORTER_OTLP_ENDPOINT=$ENDPOINT (found '${endpoint}')"

    name="$(yq ea "select(.kind == \"ConfigMap\" and .metadata.name == \"$config_map\") | .data.OTEL_SERVICE_NAME // \"\"" <<<"$out")"
    [[ "$name" == "$service" ]] \
      || fail "$overlay: ConfigMap $config_map must set OTEL_SERVICE_NAME=$service (found '${name}')"

    override="$(yq ea "[$container | (.env // [])[] | select(.name == \"OTEL_EXPORTER_OTLP_ENDPOINT\")] | length" <<<"$out")"
    [[ "$override" == "0" ]] \
      || fail "$overlay: the $service container must not override OTEL_EXPORTER_OTLP_ENDPOINT"
  done
done

# --- Egress from business pods to Jaeger, and nothing more --------------------
for environment in "${ENVIRONMENTS[@]}"; do
  root="environments/$environment"
  if ! out="$(render "$root" 2>&1)"; then
    fail "$root does not render"
    continue
  fi

  policy='select(.kind == "NetworkPolicy" and .metadata.name == "allow-tracing-egress")'
  count() { yq ea "[$1] | length" <<<"$out"; }
  value() { yq ea "$policy | $1" <<<"$out"; }

  if [[ "$(count "$policy")" != "1" ]]; then
    fail "$root must render exactly one allow-tracing-egress NetworkPolicy"
    continue
  fi

  [[ "$(value '.spec.policyTypes | join(",")')" == "Egress" ]] \
    || fail "$root: allow-tracing-egress must be an Egress-only policy"
  [[ "$(value '.spec.podSelector.matchLabels | to_entries | map(.key + "=" + .value) | join(",")')" == "app.kubernetes.io/component=business-service" ]] \
    || fail "$root: allow-tracing-egress must select exactly the business-service pods"
  [[ "$(value '.spec.egress | length')" == "1" ]] \
    || fail "$root: allow-tracing-egress must hold exactly one egress rule"
  [[ "$(value '.spec.egress[0].to | length')" == "1" ]] \
    || fail "$root: the tracing egress rule must have exactly one peer"
  [[ "$(value '.spec.egress[0].to[0] | keys | sort | join(",")')" == "namespaceSelector,podSelector" ]] \
    || fail "$root: the tracing peer must combine a namespace selector and a pod selector, and nothing else"
  [[ "$(value '.spec.egress[0].to[0].namespaceSelector.matchLabels | to_entries | map(.key + "=" + .value) | join(",")')" == "kubernetes.io/metadata.name=observability" ]] \
    || fail "$root: the tracing peer must select only the observability namespace"
  [[ "$(value '.spec.egress[0].to[0].podSelector.matchLabels | to_entries | map(.key + "=" + .value) | join(",")')" == "app.kubernetes.io/name=jaeger" ]] \
    || fail "$root: the tracing peer must select only the Jaeger pods"
  [[ "$(value '.spec.egress[0].ports | map(.protocol + "/" + (.port | tostring)) | join(",")')" == "TCP/4317" ]] \
    || fail "$root: the tracing egress rule must allow only TCP 4317"
done

# --- No Zipkin setting in any rendered application or environment (T017) ----
# The single exception is the frontend ZIPKIN_URL that the currently promoted
# frontend image still needs to start. T018 removes it once the T011 image is
# promoted everywhere; its failing-test commit deletes this exception, and the
# exception already fails here as stale the moment the value is gone.
T018_EXCEPTION='^  ZIPKIN_URL: http://127\.0\.0\.1:9411/api/v2/spans$'
exception_seen=0
while IFS= read -r root; do
  if ! out="$(render "$root" 2>&1)"; then
    fail "$root does not render"
    continue
  fi
  hits="$(grep -i 'zipkin' <<<"$out" || true)"
  if [[ "$root" == apps/frontend/* ]] && grep -Eq "$T018_EXCEPTION" <<<"$hits"; then
    exception_seen=1
    hits="$(grep -Ev "$T018_EXCEPTION" <<<"$hits" || true)"
  fi
  [[ -z "$hits" ]] || fail "$root renders a Zipkin setting: $(head -1 <<<"$hits")"
done < <(find apps environments -name kustomization.yaml -not -path '*/components/*' \
           -printf '%h\n' | sort -u)
if (( exception_seen == 0 )); then
  fail "no frontend render carries ZIPKIN_URL any more: remove the T018 exception from this contract"
fi

if (( failures > 0 )); then
  printf '\n%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: service tracing configuration (5 services, 4 economical environments, Jaeger egress only; no Zipkin setting beyond the T018 frontend exception)\n'

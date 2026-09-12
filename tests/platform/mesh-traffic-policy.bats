#!/usr/bin/env bash
# Per-service mesh traffic policy render test (spec 009, T083 — the
# DestinationRule/VirtualService half). Offline by design: renders each
# service's full-profile topology and asserts on the output. No live cluster.
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

# The four HTTP services get a full DestinationRule + VirtualService.
for svc in auth-api todos-api users-api frontend; do
  path="apps/$svc/profiles/full/topology"
  out="$(render "$path" | kubeconform -strict -ignore-missing-schemas -summary 2>&1)" || {
    fail "$svc full topology does not render or does not pass kubeconform: $out"
    continue
  }
  grep -q 'Invalid: 0, Errors: 0' <<<"$out" \
    || fail "$svc full topology has invalid or errored resources: $out"

  r="$(render "$path")"
  grep -q "^kind: DestinationRule" <<<"$r" \
    || fail "$svc full topology must include a DestinationRule"
  grep -q "^kind: VirtualService" <<<"$r" \
    || fail "$svc full topology must include a VirtualService"
  grep -q 'mode: ISTIO_MUTUAL' <<<"$r" \
    || fail "$svc DestinationRule must set tls mode ISTIO_MUTUAL"
  grep -q 'outlierDetection:' <<<"$r" \
    || fail "$svc DestinationRule must define outlierDetection"
  grep -q 'connectionPool:' <<<"$r" \
    || fail "$svc DestinationRule must define a connectionPool"
  grep -q 'retries:' <<<"$r" \
    || fail "$svc VirtualService must define retries"
  grep -qE '^\s+timeout:' <<<"$r" \
    || fail "$svc VirtualService must define a request timeout"
done

# log-message-processor is a Redis subscriber with no HTTP Service — it must
# NOT get a DestinationRule or VirtualService.
lmp="$(render apps/log-message-processor/profiles/full/topology)"
if grep -qE "^kind: (DestinationRule|VirtualService)" <<<"$lmp"; then
  fail "log-message-processor must not get a DestinationRule/VirtualService (no HTTP Service)"
fi

# The economical profile has no mesh (constitution principle 9) — no DR/VS
# may leak into it.
for svc in auth-api todos-api users-api frontend; do
  econ="$(render apps/$svc/profiles/economical/overlays/dev)"
  if grep -qE "^kind: (DestinationRule|VirtualService)" <<<"$econ"; then
    fail "$svc economical overlay must not contain any mesh traffic policy"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d mesh-traffic-policy violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: the four HTTP services each render a full-profile DestinationRule (ISTIO_MUTUAL, connection pool, outlier detection) and VirtualService (retries, timeout); log-message-processor renders neither; and no mesh policy leaks into the economical profile.\n'

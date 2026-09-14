#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
kustomize_bin="${KUSTOMIZE_BIN:-kustomize}"
http_services=(auth-api todos-api users-api frontend)
p99_services=(auth-api todos-api users-api)

command -v "$kustomize_bin" >/dev/null 2>&1 || {
  printf 'FAIL: kustomize is required; set KUSTOMIZE_BIN to the pinned binary.\n' >&2
  exit 1
}

analysis_templates="$repo_root/infrastructure/argo-rollouts/cluster-analysis-template.yaml"

for service in "${http_services[@]}"; do
  full_prod="$repo_root/apps/$service/profiles/full/overlays/prod"
  render="$(mktemp)"
  "$kustomize_bin" build "$full_prod" > "$render"

  # 10/25/50/100 weights, in that exact order.
  weights="$(grep -oE 'setWeight: [0-9]+' "$render" | awk '{print $2}' | paste -sd, -)"
  [[ "$weights" == "10,25,50,100" ]] || {
    printf 'FAIL: %s full canary weights are not exactly 10,25,50,100 in order: %s\n' "$service" "$weights" >&2
    exit 1
  }

  # Istio traffic routing, not the economical replica-weighted mechanism.
  grep -Fq 'trafficRouting:' "$render" || {
    printf 'FAIL: %s full canary has no trafficRouting.\n' "$service" >&2
    exit 1
  }
  grep -Fq 'canarySubsetName: canary' "$render" || {
    printf 'FAIL: %s is missing the canary subset wiring.\n' "$service" >&2
    exit 1
  }
  if grep -Fq 'canaryService:' "$render"; then
    printf 'FAIL: %s full canary must not use the economical canaryService mechanism.\n' "$service" >&2
    exit 1
  fi

  # Error-rate analysis (its own recording rule already windows over rate(...[5m]))
  # runs at every progressive weight step, not just once.
  health_count="$(grep -c 'templateName: microtodosuite-canary-health' "$render")"
  [[ "$health_count" -ge 3 ]] || {
    printf 'FAIL: %s is missing the error-rate analysis at each progressive step (found %s).\n' "$service" "$health_count" >&2
    exit 1
  }

  # p99 analysis only where the recording rule can produce a value; referencing
  # it for a workload with no latency histogram would gate on permanent "no
  # data" and block that service's canary forever.
  is_p99_service=0
  for p99_service in "${p99_services[@]}"; do
    [[ "$service" == "$p99_service" ]] && is_p99_service=1
  done
  latency_count="$(grep -c 'templateName: microtodosuite-canary-latency' "$render" || true)"
  if [[ "$is_p99_service" -eq 1 ]]; then
    [[ "$latency_count" -ge 3 ]] || {
      printf 'FAIL: %s is missing the p99 latency analysis at each progressive step (found %s).\n' "$service" "$latency_count" >&2
      exit 1
    }
  else
    [[ "$latency_count" -eq 0 ]] || {
      printf 'FAIL: %s has no latency histogram yet and must not reference the p99 template.\n' "$service" >&2
      exit 1
    }
  fi

  # Automatic abort + stable rollback are Argo Rollouts' default canary
  # behavior once an AnalysisRun fails; assert nothing here overrides it.
  if grep -Fq 'abortScaleDownDelaySeconds' "$render"; then
    printf 'FAIL: %s overrides the default abort/rollback behavior.\n' "$service" >&2
    exit 1
  fi

  unlink "$render"
done

# Missing-metric failure: both cluster-scope templates fail closed. failureLimit: 0
# means any non-success measurement -- including "no data" for a workload whose
# histogram does not exist yet -- aborts the rollout rather than passing it.
grep -A2 'name: canary-error-rate' "$analysis_templates" | grep -Fq 'failureLimit: 0' || {
  printf 'FAIL: canary-error-rate does not fail closed on a missing measurement.\n' >&2
  exit 1
}
grep -A2 'name: canary-p99-latency' "$analysis_templates" | grep -Fq 'failureLimit: 0' || {
  printf 'FAIL: canary-p99-latency does not fail closed on a missing measurement.\n' >&2
  exit 1
}

# log-message-processor is deliberately exempt (Redis Pub/Sub consumer, no HTTP
# Service to route Istio traffic to -- same reasoning topology-full already
# applies to its missing DestinationRule/VirtualService) and must keep the
# native replica-weighted canary, unchanged.
lmp_render="$(mktemp)"
"$kustomize_bin" build "$repo_root/apps/log-message-processor/profiles/full/overlays/prod" > "$lmp_render"
grep -Fq 'canaryService: log-message-processor-canary' "$lmp_render" || {
  printf 'FAIL: log-message-processor full/prod must keep the native canary.\n' >&2
  exit 1
}
if grep -Fq 'trafficRouting:' "$lmp_render"; then
  printf 'FAIL: log-message-processor must not gain Istio traffic routing.\n' >&2
  exit 1
fi
unlink "$lmp_render"

# Byte-identical economical native-canary golden output: the full-only Istio
# swap must not have changed anything economical/overlays/prod renders. This
# re-derives the same comparison tests/profiles/validate-profile-routing.bats
# makes, independently, so this file proves the guarantee on its own.
for service in auth-api todos-api users-api frontend log-message-processor; do
  economical="$repo_root/apps/$service/profiles/economical/overlays/prod"
  golden="$repo_root/tests/profiles/golden/economical/$service/prod.yaml"
  [[ -f "$golden" ]] || {
    printf 'FAIL: missing economical golden render for %s.\n' "$service" >&2
    exit 1
  }

  render="$(mktemp)"
  "$kustomize_bin" build "$economical" > "$render"
  golden_normalized="$(mktemp)"
  render_normalized="$(mktemp)"
  sed -E 's/@sha256:[a-f0-9]{64}/@sha256:<DIGEST>/g' "$golden" > "$golden_normalized"
  sed -E 's/@sha256:[a-f0-9]{64}/@sha256:<DIGEST>/g' "$render" > "$render_normalized"
  cmp -s "$golden_normalized" "$render_normalized" || {
    diff -u "$golden_normalized" "$render_normalized" >&2 || true
    printf 'FAIL: %s economical prod render changed after adding the full-only canary.\n' "$service" >&2
    exit 1
  }
  rm -f "$golden_normalized" "$render_normalized" "$render"
done

printf 'PASS: full/eks-full-prod canary weights 10/25/50/100, error-rate+p99 analyses wired where the metric exists, missing-metric fails closed, default abort/rollback untouched, log-message-processor stays on the native canary, and every economical golden render is unchanged.\n'

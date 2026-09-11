#!/usr/bin/env bash
# Chaos Mesh + OpenCost render test (spec 009, T087, US3).
#
# No existing test task is scoped narrowly enough for this pair — T068/T071
# cover it only as part of a much larger suite still blocked on Phase 4 and
# the ECR mirror. This is new, narrowly-scoped verification work in the same
# spirit as T069, not tied to a pre-existing task ID (see the tasks.md
# annotation on T087).
#
# Offline by design: renders Kustomize and asserts on the output, exactly
# like tests/platform/mesh-policy.bats. No live cluster is touched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

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

# --- schema-level render checks --------------------------------------------
validate "infrastructure/chaos-mesh" "infrastructure/chaos-mesh"
validate "infrastructure/opencost" "infrastructure/opencost"
validate "the disabled experiment roots (standalone)" "infrastructure/chaos-mesh/experiments"

# --- chaos-mesh: no committed secret material -------------------------------
chaos_mesh_render="$(render infrastructure/chaos-mesh)"
if grep -q '^kind: Secret' <<<"$chaos_mesh_render"; then
  fail "infrastructure/chaos-mesh must not render a Secret (chart defaults generate a fresh self-signed cert at render time — see vendor README)"
fi

# --- chaos-mesh: experiments are disabled by construction -------------------
# Only the resources: list matters here — the file's own comments legitimately
# mention "experiments" to explain the exclusion.
main_resources_block="$(awk '/^resources:/{f=1;print;next} f&&/^[a-zA-Z]/{f=0} f' \
  "$ROOT/infrastructure/chaos-mesh/kustomization.yaml")"
if grep -q 'experiments' <<<"$main_resources_block"; then
  fail "infrastructure/chaos-mesh/kustomization.yaml's resources list must not reference experiments/ (that is what makes them disabled by default)"
fi

# --- opencost: wired to the real Prometheus, not the chart's generic guess -
opencost_render="$(render infrastructure/opencost)"
grep -q 'prometheus-k8s.observability' <<<"$opencost_render" \
  || fail "infrastructure/opencost must point at prometheus-k8s.observability, this repository's real Prometheus"
if grep -q 'prometheus-server.prometheus-system' <<<"$opencost_render"; then
  fail "infrastructure/opencost must not use the chart's generic default Prometheus address"
fi

# --- no mutable image tag in either render ----------------------------------
for pair in "chaos-mesh:$chaos_mesh_render" "opencost:$opencost_render"; do
  name="${pair%%:*}"
  content="${pair#*:}"
  images="$(grep -oE 'image: "?[^" ]+"?' <<<"$content" | sed -E 's/^image: "?//; s/"$//' || true)"
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    if [[ ! "$image" =~ @sha256:[a-f0-9]{64}$ ]]; then
      fail "$name renders a non-digest-pinned image: $image"
    fi
  done <<<"$images"
done

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d chaos-mesh/opencost violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: chaos-mesh and opencost render valid, no secret material, experiments are disabled by construction, opencost targets the real Prometheus, and every image is digest-pinned.\n'

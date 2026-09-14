#!/usr/bin/env bash
# Read-only multi-cluster desired/live/failure/rollback evidence collector for
# the full profile (spec 009, T148). One EKS cluster per environment
# (eks-full-{dev,staging,prod}); unlike verify-namespace-isolation.sh (one
# shared economical cluster, three namespaces) this walks three separate
# cluster contexts, one per destination.
#
# DESIRED half needs no cluster: it reads what clusters/eks-full-<env>/
# activation-apps.yaml actually activates (Generator 2 of the base
# ApplicationSet, clusters/base/apps.yaml) and, if anything is activated,
# what apps/<service>/profiles/full/overlays/<env> declares as the digest to
# run. LIVE/FAILURE/ROLLBACK need a reachable cluster and are BLOCKED,
# per-destination, when this environment cannot reach one -- explicit
# PASS/FAIL/BLOCKED throughout (see scripts/managed/lib/verify-common.sh),
# never a silent success.
#
# STATUS: skeleton. Every full destination is EMPTY AT BOOTSTRAP by design
# (activation-apps.yaml's own comment) pending the T092/T111+ reviewed
# activation, and this environment has no eks-full-* kubectl credentials --
# so today's real run is DESIRED-only PASS plus three BLOCKED LIVE checks,
# which is the correct, honest result, not a placeholder.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICES=(auth-api todos-api users-api frontend log-message-processor)
DESTINATIONS=(eks-full-dev eks-full-staging eks-full-prod)
declare -A ENV_FOR=([eks-full-dev]=dev [eks-full-staging]=staging [eks-full-prod]=prod)

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# shellcheck source=scripts/managed/lib/verify-common.sh
source "$ROOT/scripts/managed/lib/verify-common.sh"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="$ROOT/evidence/runs/${TIMESTAMP}-full-platform"
mkdir -p "$EVIDENCE_DIR/raw"

command -v kustomize >/dev/null 2>&1 && KUSTOMIZE_BIN=kustomize || KUSTOMIZE_BIN="kubectl kustomize"

# --- ROLLBACK evidence: offline, always runs. The mechanism is a git revert
# of the promoting commit; record the exact commit this run observed. -------
if git -C "$ROOT" rev-parse HEAD > "$EVIDENCE_DIR/raw/observed-revision.txt" 2>/dev/null; then
  record_check PASS "rollback anchor recorded: git revert of $(cat "$EVIDENCE_DIR/raw/observed-revision.txt") reverts this observation's revision"
else
  record_check FAIL "could not resolve the observed git revision for the rollback anchor"
fi

for destination in "${DESTINATIONS[@]}"; do
  environment="${ENV_FOR[$destination]}"
  activation_file="$ROOT/clusters/$destination/activation-apps.yaml"

  # --- DESIRED: what Generator 2 of the base ApplicationSet actually
  # activates for this destination today. No cluster needed.
  if [[ ! -f "$activation_file" ]]; then
    record_check FAIL "$destination: missing activation-apps.yaml"
    continue
  fi

  elements="$(grep -E '^[[:space:]]*value:' "$activation_file" | head -1 | sed -E 's/^[[:space:]]*value:[[:space:]]*//')"
  if [[ "$elements" == "[]" ]]; then
    record_check PASS "$destination: zero business applications activated (pre-activation scaffold, expected)"
    activated_services=()
  else
    # Once activation lands this is where the desired app list is derived
    # from the real elements; until then there is nothing to parse. This is a
    # tooling gap to close alongside activation, not a platform failure --
    # BLOCKED, not FAIL.
    record_check BLOCKED "$destination: activation-apps.yaml has non-empty elements this collector does not yet know how to parse: $elements"
    activated_services=()
  fi

  # Even with zero activation, confirm the full overlay each service WOULD
  # promote to still renders and carries a real pinned digest, so the moment
  # activation lands there is a validated artifact waiting for it.
  for service in "${SERVICES[@]}"; do
    overlay="$ROOT/apps/$service/profiles/full/overlays/$environment"
    [[ -d "$overlay" ]] || { record_check FAIL "$destination: missing overlay $overlay"; continue; }
    if render="$($KUSTOMIZE_BIN build "$overlay" 2>"$EVIDENCE_DIR/raw/$service-$destination-render.stderr")"; then
      if grep -Eq '@sha256:[a-f0-9]{64}' <<<"$render"; then
        record_check PASS "$destination/$service: overlay renders with a pinned digest"
      else
        record_check FAIL "$destination/$service: overlay renders but has no pinned digest"
      fi
    else
      record_check FAIL "$destination/$service: overlay does not render"
    fi
  done

  # --- LIVE + FAILURE: needs a reachable cluster for this exact destination.
  if ! require_live_context "$destination"; then
    record_check BLOCKED "$destination: live cluster access (no context reachable from this environment)"
    continue
  fi

  kube() { kubectl --context "$destination" "$@"; }
  if kube get applications -n argocd -o json > "$EVIDENCE_DIR/raw/$destination-applications.json" 2>/dev/null; then
    record_check PASS "$destination: ArgoCD Applications listable"
    for service in "${activated_services[@]}"; do
      app_name="$service-$environment"
      status="$(jq -r --arg n "$app_name" \
        '.items[] | select(.metadata.name == $n) | "\(.status.sync.status)/\(.status.health.status)"' \
        "$EVIDENCE_DIR/raw/$destination-applications.json" 2>/dev/null || true)"
      if [[ "$status" == "Synced/Healthy" ]]; then
        record_check PASS "$destination/$app_name: Synced/Healthy"
      else
        record_check FAIL "$destination/$app_name: not Synced/Healthy (observed: ${status:-not found})"
      fi
    done
  else
    record_check FAIL "$destination: ArgoCD Applications not listable despite a reachable context"
  fi
done

log "Evidence retained under $EVIDENCE_DIR"
final_verdict
exit $?

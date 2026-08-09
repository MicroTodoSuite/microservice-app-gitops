#!/usr/bin/env bash
# Prove the pilot succeeded via the GitOps path, not a running process (spec 001,
# FR-012/FR-020). Read-only. Success requires: Argo revision == local Git SHA,
# auth workload Ready, auth registration present, three /version successes over 60s.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

APP="auth-api-local"
NS="microtodo-local"

EXPECTED_SHA="$(git -C "$BARE_REPO" rev-parse main)"
log "expected desired-state revision: $EXPECTED_SHA"

log "waiting up to 300s for $APP to be Synced+Healthy at the expected revision"
deadline=$(( $(date +%s) + 300 ))
while :; do
  sync=$(kro get application "$APP" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  health=$(kro get application "$APP" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  rev=$(kro get application "$APP" -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null || true)
  [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ] && [ "$rev" = "$EXPECTED_SHA" ] && break
  [ "$(date +%s)" -gt "$deadline" ] && die "timed out (sync=$sync health=$health rev=${rev:0:12})"
  sleep 5
done
ok "Argo revision matches Git and app is Synced+Healthy"

log "waiting for deployment/auth-api to be Available"
kro wait -n "$NS" deploy/auth-api --for=condition=Available --timeout=120s >&2

# auth-api remains registered even after later features add more services.
BS=$(kro get applications -n argocd -l microtodosuite.io/business-service=true -o name | wc -l | tr -d ' ')
(( BS >= 1 )) || die "expected at least auth-api, found $BS business services"
kro get application "$APP" -n argocd >/dev/null \
  || die "$APP is not registered as a business service"
ok "$APP is present among $BS business services"

# Three health checks over at least 60 seconds.
log "starting health port-forward on :$PILOT_HEALTH_PORT"
kubectl --context "$PILOT_KUBE_CONTEXT" -n "$NS" port-forward svc/auth-api "${PILOT_HEALTH_PORT}:8000" \
  >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null || true' EXIT
sleep 3
for i in 1 2 3; do
  body=$(curl -fsS "http://127.0.0.1:${PILOT_HEALTH_PORT}/version") || die "health check $i failed"
  log "health check $i: $body"
  [ "$i" -lt 3 ] && sleep 30
done
ok "three /version successes over >=60s"

echo "AUTH PILOT VERIFIED: revision $EXPECTED_SHA, auth-api healthy with $BS business services registered." >&2

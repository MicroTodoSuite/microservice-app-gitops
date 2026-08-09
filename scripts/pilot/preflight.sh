#!/usr/bin/env bash
# Verify the workstation can run the local pilot WITHOUT changing anything
# (spec 001, FR-019 / T009). Read-only. Exits non-zero on the first blocker.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

log "preflight: checking tools"
for t in bash git docker kind kubectl kustomize curl jq; do require_tool "$t"; done

log "preflight: checking docker daemon"
docker info >/dev/null 2>&1 || die "docker daemon not available" 5

log "preflight: checking loopback ports"
for p in "$PILOT_REGISTRY_PORT" "$PILOT_GIT_PORT" "$PILOT_HEALTH_PORT"; do
  if lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
    die "port $p is in use; free it before bootstrapping" 4
  fi
done

log "preflight: checking no cloud credentials are required"
[ -z "${AWS_ACCESS_KEY_ID:-}" ] || log "note: AWS_ACCESS_KEY_ID is set but the pilot will not use it"

# Machine-readable result on stdout.
jq -n \
  --arg result pass \
  --arg cluster "$PILOT_CLUSTER" \
  --argjson ports "{\"registry\":$PILOT_REGISTRY_PORT,\"git\":$PILOT_GIT_PORT,\"health\":$PILOT_HEALTH_PORT}" \
  '{result:$result, cluster:$cluster, reservedPorts:$ports}'
ok "preflight passed"

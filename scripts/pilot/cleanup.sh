#!/usr/bin/env bash
# Remove ONLY pilot-owned local resources (spec 001, US4). Not a deployment or
# rollback method; never touches a remote environment or unrelated context.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

if kind get clusters 2>/dev/null | grep -qx "$PILOT_CLUSTER"; then
  log "deleting kind cluster $PILOT_CLUSTER"; kind delete cluster --name "$PILOT_CLUSTER" >/dev/null
fi
if docker inspect "$PILOT_REGISTRY_NAME" >/dev/null 2>&1; then
  log "removing registry $PILOT_REGISTRY_NAME"; docker rm -f "$PILOT_REGISTRY_NAME" >/dev/null
fi
if [ -f "$LOCAL_DIR/git-http.pid" ]; then
  log "stopping local Git HTTP source"; kill "$(cat "$LOCAL_DIR/git-http.pid")" 2>/dev/null || true
fi
log "removing $LOCAL_DIR"; rm -rf "$LOCAL_DIR"
ok "pilot cleanup complete (local-only)"

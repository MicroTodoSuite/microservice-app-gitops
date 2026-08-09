#!/usr/bin/env bash
# Bring up the fully local pilot platform (spec 001, FR-001/FR-007/FR-017):
# loopback registry + machine-local Git HTTP source + kind cluster + vendored
# ArgoCD + root Application. Business-service discovery stays DISABLED, so at the
# end zero business workloads exist (pre-activation checkpoint).
#
# Bootstrap boundary: the ONLY direct kubectl mutations allowed are installing
# the vendored ArgoCD controller and creating the root Application. Everything
# else is reconciled by ArgoCD from the local Git source.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

mkdir -p "$LOCAL_GIT_DIR"

# 1) Loopback registry -------------------------------------------------------
if ! docker inspect "$PILOT_REGISTRY_NAME" >/dev/null 2>&1; then
  log "starting loopback registry on :$PILOT_REGISTRY_PORT"
  docker run -d --restart=always -p "127.0.0.1:${PILOT_REGISTRY_PORT}:5000" \
    --name "$PILOT_REGISTRY_NAME" registry:2 >/dev/null
else
  log "registry $PILOT_REGISTRY_NAME already running"
fi

# 2) Machine-local Git HTTP source ------------------------------------------
if [ ! -d "$BARE_REPO" ]; then
  log "initializing bare repo $BARE_REPO"
  git init --bare -b main "$BARE_REPO" >/dev/null
  printf '#!/bin/sh\nexec git update-server-info\n' > "$BARE_REPO/hooks/post-update"
  chmod +x "$BARE_REPO/hooks/post-update"
fi
log "seeding bare main from current checkout revision (agent tooling filtered)"
assert_pilot_remote_safe "$BARE_REPO"
# The repo carries developer tooling symlinks (.agents/.claude/.specify) that
# point at sibling repos. They are out-of-bounds for a standalone clone and
# ArgoCD rejects such symlinks. They are not GitOps manifests, so the pilot
# seeds a filtered tree without them via a disposable detached worktree.
SEED="$LOCAL_DIR/seed"
git -C "$REPO_ROOT" worktree remove --force "$SEED" >/dev/null 2>&1 || true
rm -rf "$SEED"; git -C "$REPO_ROOT" worktree prune
git -C "$REPO_ROOT" worktree add -q --detach "$SEED" HEAD
git -C "$SEED" rm -rq --ignore-unmatch .agents .claude/skills .specify >/dev/null 2>&1 || true
git -C "$SEED" -c user.email=pilot@local -c user.name=pilot commit -q \
  -m "pilot seed: exclude out-of-bounds tooling symlinks for ArgoCD" >/dev/null
git -C "$SEED" push --force "$BARE_REPO" HEAD:refs/heads/main >/dev/null 2>&1
git -C "$REPO_ROOT" worktree remove --force "$SEED" >/dev/null 2>&1 || true
git -C "$BARE_REPO" update-server-info

# Serve the bare repo over SMART HTTP (git http-backend). ArgoCD's go-git needs
# smart HTTP; a static/dumb server is not enough.
SMART_REFS="http://127.0.0.1:${PILOT_GIT_PORT}/microservice-app-gitops.git/info/refs?service=git-upload-pack"
if ! curl -fsS "$SMART_REFS" >/dev/null 2>&1; then
  log "starting local smart-HTTP Git source on :$PILOT_GIT_PORT"
  python3 "$(dirname "$0")/lib/git-http-server.py" "$LOCAL_GIT_DIR" "$PILOT_GIT_PORT" \
    >"$LOCAL_DIR/git-http.log" 2>&1 &
  echo $! > "$LOCAL_DIR/git-http.pid"
  sleep 2
fi
curl -fsS "$SMART_REFS" | grep -q "git-upload-pack" \
  || die "local smart-HTTP Git source is not advertising refs"
ok "local Git source reachable (smart HTTP)"

# 3) kind cluster ------------------------------------------------------------
if ! kind get clusters 2>/dev/null | grep -qx "$PILOT_CLUSTER"; then
  log "creating kind cluster $PILOT_CLUSTER"
  kind create cluster --config "$REPO_ROOT/bootstrap/local/kind-config.yaml" >/dev/null
fi
# Attach the registry to the kind network so nodes can reach it by name.
docker network connect kind "$PILOT_REGISTRY_NAME" >/dev/null 2>&1 || true

# 4) Bootstrap boundary: vendored ArgoCD ------------------------------------
log "BOOTSTRAP-EXCEPTION: installing vendored ArgoCD"
kustomize build "$REPO_ROOT/bootstrap/argocd" | kubectl --context "$PILOT_KUBE_CONTEXT" apply --server-side -f - >/dev/null
kro wait -n argocd deploy --all --for=condition=Available --timeout=300s >&2

# 5) Bootstrap boundary: root Application -----------------------------------
log "BOOTSTRAP-EXCEPTION: applying root Application"
kubectl --context "$PILOT_KUBE_CONTEXT" apply -f "$REPO_ROOT/clusters/local-kind/root-app.yaml" >/dev/null

log "waiting for ArgoCD to reconcile the platform from the local Git source"
sleep 20
kro get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' >&2 || true

# 6) Pre-activation proof: zero business services ---------------------------
COUNT=$(kro get applications -n argocd -l microtodosuite.io/business-service=true \
  -o name 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" = "0" ] || die "expected zero business services before activation, found $COUNT"
ok "pre-activation checkpoint: platform up from local Git source, zero business services"

mkdir -p "$LOCAL_DIR/bootstrap"
jq -n --arg repo "http://127.0.0.1:${PILOT_GIT_PORT}/microservice-app-gitops.git" \
      --arg registry "localhost:${PILOT_REGISTRY_PORT}" \
      --arg cluster "$PILOT_CLUSTER" \
  '{sourceReaderURL:$repo, registry:$registry, cluster:$cluster, businessServices:0}' \
  > "$LOCAL_DIR/bootstrap/summary.json"
ok "bootstrap complete — run scripts/pilot/publish-auth.sh next"

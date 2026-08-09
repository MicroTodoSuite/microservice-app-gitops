#!/usr/bin/env bash
# Build auth-api once, push it to the loopback registry, and commit its immutable
# digest + local activation to the machine-local Git source (spec 001, US1).
# ArgoCD reconciles automatically; this script never mutates the cluster.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

AUTH_API_SRC="${1:-$REPO_ROOT/../microservice-app-auth-api}"
[ -f "$AUTH_API_SRC/Dockerfile" ] || die "auth-api source not found at $AUTH_API_SRC"

REF="localhost:${PILOT_REGISTRY_PORT}/auth-api"

log "building auth-api once from $AUTH_API_SRC"
docker build -q -t "$REF:pilot" "$AUTH_API_SRC" >/dev/null

log "pushing to the loopback registry"
docker push -q "$REF:pilot" >/dev/null

# Resolve the registry-reported manifest digest (immutable evidence).
DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "$REF:pilot" | sed 's/.*@//')"
[[ "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] || die "could not resolve a manifest digest for $REF"
ok "image digest $DIGEST"

# Work in a disposable clone of the bare repo; push only to the local source.
WT="$LOCAL_DIR/publish-worktree"
rm -rf "$WT"
git clone -q "$BARE_REPO" "$WT"
cd "$WT"
git config user.email pilot@local
git config user.name "pilot"

# 1) Immutable digest into the local overlay (preserve newName).
( cd apps/auth-api/overlays/local && kustomize edit set image "auth-api=${REF}@${DIGEST}" )
# 2) Activate exactly the local environment.
cp clusters/local-kind/activation-templates/local/activation-apps.yaml \
   clusters/local-kind/activation-apps.yaml
cp clusters/local-kind/activation-templates/local/activation-environments.yaml \
   clusters/local-kind/activation-environments.yaml

# Contract check before committing.
kustomize build apps/auth-api/overlays/local >/dev/null || die "local overlay render failed"

git add -A
git commit -q -m "feat(pilot): activate auth-api local at ${DIGEST}"
assert_pilot_remote_safe "$BARE_REPO"
git push -q origin main
SHA="$(git rev-parse HEAD)"

mkdir -p "$LOCAL_DIR/publish"
jq -n --arg digest "$DIGEST" --arg sha "$SHA" \
  '{imageDigest:$digest, commit:$sha, remote:"pilot main"}' > "$LOCAL_DIR/publish/summary.json"
ok "published commit $SHA — ArgoCD will reconcile it automatically. Run scripts/pilot/verify.sh"

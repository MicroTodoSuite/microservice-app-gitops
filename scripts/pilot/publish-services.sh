#!/usr/bin/env bash
# Build the complete local service set and publish it through two pilot-only Git
# commits: Redis first, then all business services. This script never mutates a
# GitOps-managed Kubernetes object directly.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

SERVICES=(auth-api todos-api users-api frontend log-message-processor)
declare -A SOURCES=(
  [auth-api]="${AUTH_API_SRC:-$REPO_ROOT/../microservice-app-auth-api}"
  [todos-api]="${TODOS_API_SRC:-$REPO_ROOT/../microservice-app-todos-api}"
  [users-api]="${USERS_API_SRC:-$REPO_ROOT/../microservice-app-users-api}"
  [frontend]="${FRONTEND_SRC:-$REPO_ROOT/../microservice-app-frontend}"
  [log-message-processor]="${LOG_MESSAGE_PROCESSOR_SRC:-$REPO_ROOT/../microservice-app-log-message-processor}"
)
declare -A DIGESTS=()
declare -A SOURCE_REVISIONS=()

PUBLISH_DIR="$LOCAL_DIR/publish/services"
WT="$LOCAL_DIR/service-publish-worktree"
SNAPSHOT="$LOCAL_DIR/service-publish-snapshot"
REDIS_FORWARD_PORT="${PILOT_REDIS_FORWARD_PORT:-16379}"

wait_for_application_revision() {
  local application="$1" expected="$2" timeout="${3:-600}"
  local deadline sync health revision
  deadline=$(( $(date +%s) + timeout ))
  while :; do
    sync="$(kro get application "$application" -n argocd \
      -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health="$(kro get application "$application" -n argocd \
      -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    revision="$(kro get application "$application" -n argocd \
      -o jsonpath='{.status.sync.revision}' 2>/dev/null || true)"
    [[ "$sync" == Synced && "$health" == Healthy && "$revision" == "$expected" ]] && return 0
    (( $(date +%s) <= deadline )) \
      || die "timed out waiting for $application at $expected (sync=$sync health=$health revision=$revision)"
    sleep 5
  done
}

redis_ping() {
  local response="" pf
  kro port-forward -n redis svc/redis "$REDIS_FORWARD_PORT:6379" \
    >"$PUBLISH_DIR/redis-port-forward.log" 2>&1 &
  pf=$!
  for _ in {1..30}; do
    if (exec 8<>"/dev/tcp/127.0.0.1/$REDIS_FORWARD_PORT") 2>/dev/null; then
      exec 8>&-
      break
    fi
    kill -0 "$pf" 2>/dev/null || die "Redis port-forward exited before becoming ready"
    sleep 1
  done

  exec 9<>"/dev/tcp/127.0.0.1/$REDIS_FORWARD_PORT" \
    || die "could not connect to forwarded Redis service"
  printf '*1\r\n$4\r\nPING\r\n' >&9
  IFS= read -r -t 5 response <&9 || true
  exec 9>&- 9<&-
  kill "$pf" 2>/dev/null || true
  wait "$pf" 2>/dev/null || true
  response="${response%$'\r'}"
  printf '%s\n' "$response" >"$PUBLISH_DIR/redis-ping.txt"
  [[ "$response" == +PONG ]] || die "Redis protocol gate failed: $response"
}

copy_path() {
  local relative="$1"
  mkdir -p "$WT/$(dirname "$relative")"
  rsync -a --delete "$REPO_ROOT/$relative" "$WT/$(dirname "$relative")/"
}

snapshot_reviewed_tree() {
  rm -rf "$SNAPSHOT"
  mkdir -p "$SNAPSHOT"
  git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard -z \
    | rsync -a --from0 --files-from=- "$REPO_ROOT/" "$SNAPSHOT/"
  # These two value files are resolved for this exact machine during
  # bootstrap. A reviewed-tree refresh must not replace them with the portable
  # checked-in examples and strand the already-created root Application.
  rsync -a --delete --exclude=.git \
    --exclude=clusters/local-kind/registration.yaml \
    --exclude=clusters/local-kind/root-app.yaml \
    "$SNAPSHOT/" "$WT/"
}

mkdir -p "$PUBLISH_DIR"
require_tool docker
require_tool git
require_tool jq
require_tool rsync
[[ -d "$BARE_REPO" ]] || die "pilot Git source not found: $BARE_REPO"

images_json='{}'
sources_json='{}'
for service in "${SERVICES[@]}"; do
  source_dir="${SOURCES[$service]}"
  [[ -f "$source_dir/Dockerfile" ]] || die "$service Dockerfile not found at $source_dir"
  [[ -z "$(git -C "$source_dir" status --porcelain)" ]] \
    || die "$service source checkout is dirty: $source_dir"
  SOURCE_REVISIONS[$service]="$(git -C "$source_dir" rev-parse HEAD)"
  sources_json="$(jq --arg service "$service" \
    --arg revision "${SOURCE_REVISIONS[$service]}" \
    '. + {($service):$revision}' <<<"$sources_json")"

  ref="localhost:${PILOT_REGISTRY_PORT}/${service}"
  tag="$ref:pilot-${SOURCE_REVISIONS[$service]:0:12}"
  log "building $service from ${SOURCE_REVISIONS[$service]}"
  if ! docker build --progress=plain -t "$tag" "$source_dir" \
      >"$PUBLISH_DIR/build-$service.log" 2>&1; then
    tail -80 "$PUBLISH_DIR/build-$service.log" >&2 || true
    die "$service image build failed"
  fi
  log "pushing $service to the loopback registry"
  docker push "$tag" >"$PUBLISH_DIR/push-$service.log" 2>&1 \
    || die "$service image push failed"
  DIGESTS[$service]="$(docker image inspect "$tag" \
    --format '{{range .RepoDigests}}{{println .}}{{end}}' \
    | awk -F@ -v wanted="$ref" '$1 == wanted {print $2; exit}')"
  [[ "${DIGESTS[$service]}" =~ ^sha256:[a-f0-9]{64}$ ]] \
    || die "registry digest was not resolved for $service"
  images_json="$(jq --arg service "$service" --arg digest "${DIGESTS[$service]}" \
    '. + {($service):$digest}' <<<"$images_json")"
  ok "$service -> ${DIGESTS[$service]}"
done

rm -rf "$WT"
git clone -q "$BARE_REPO" "$WT"
git -C "$WT" config user.email pilot@local
git -C "$WT" config user.name pilot

# Commit 1: only Redis and the exact policy/project prerequisites. New business
# service directories are deliberately absent from this revision.
copy_path infrastructure/redis
copy_path clusters/base/project.yaml
copy_path environments/local/namespace.yaml
copy_path environments/local/networkpolicy-allow-redis.yaml
copy_path environments/local/kustomization.yaml
render_kustomize "$WT/infrastructure/redis" >/dev/null \
  || die "Redis Kustomize render failed"
render_kustomize "$WT/clusters/local-kind" >/dev/null \
  || die "local registration render failed after Redis registration"

git -C "$WT" add -A
if ! git -C "$WT" diff --cached --quiet; then
  git -C "$WT" commit -q -m "feat(pilot): register Redis before service consumers"
fi
assert_pilot_remote_safe "$BARE_REPO"
git -C "$WT" push -q origin main
REDIS_SHA="$(git -C "$WT" rev-parse HEAD)"
log "waiting for infra-redis at $REDIS_SHA"
wait_for_application_revision infra-redis "$REDIS_SHA"
kro wait -n redis deployment/redis --for=condition=Available --timeout=180s >&2
for service in todos-api users-api frontend log-message-processor; do
  if kro get application "$service-local" -n argocd >/dev/null 2>&1; then
    die "$service-local existed before the service publication commit"
  fi
done
redis_ping
ok "Redis-first gate passed at $REDIS_SHA with PONG"

# Commit 2: mirror the reviewed working tree, activate local, and select every
# image by its loopback registry digest.
snapshot_reviewed_tree
for service in "${SERVICES[@]}"; do
  set_overlay_image "$WT/apps/$service/overlays/local" "$service" \
    "localhost:${PILOT_REGISTRY_PORT}/$service" "${DIGESTS[$service]}"
done
cp "$WT/clusters/local-kind/activation-templates/local/activation-apps.yaml" \
  "$WT/clusters/local-kind/activation-apps.yaml"
cp "$WT/clusters/local-kind/activation-templates/local/activation-environments.yaml" \
  "$WT/clusters/local-kind/activation-environments.yaml"

for service in "${SERVICES[@]}"; do
  render="$(render_kustomize "$WT/apps/$service/overlays/local")" \
    || die "$service local overlay render failed"
  expected="localhost:${PILOT_REGISTRY_PORT}/$service@${DIGESTS[$service]}"
  grep -Fq "image: $expected" <<<"$render" \
    || die "$service render does not select $expected"
done
(cd "$WT" && bash tests/contract/platform-addons.sh)
(cd "$WT" && bash tests/contract/service-onboarding.sh)

git -C "$WT" add -A
if ! git -C "$WT" diff --cached --quiet; then
  git -C "$WT" commit -q -m "feat(pilot): onboard the complete local service set"
fi
assert_pilot_remote_safe "$BARE_REPO"
git -C "$WT" push -q origin main
SERVICE_SHA="$(git -C "$WT" rev-parse HEAD)"

for service in "${SERVICES[@]}"; do
  wait_for_application_revision "$service-local" "$SERVICE_SHA"
done

jq -n \
  --arg redisCommit "$REDIS_SHA" \
  --arg serviceCommit "$SERVICE_SHA" \
  --arg registry "localhost:${PILOT_REGISTRY_PORT}" \
  --argjson sourceRevisions "$sources_json" \
  --argjson imageDigests "$images_json" \
  '{redisCommit:$redisCommit,serviceCommit:$serviceCommit,registry:$registry,
    sourceRevisions:$sourceRevisions,imageDigests:$imageDigests}' \
  >"$PUBLISH_DIR/summary.json"

ok "published complete service set at $SERVICE_SHA"
printf 'SERVICE_PUBLISH_COMPLETE=%s\n' "$SERVICE_SHA"

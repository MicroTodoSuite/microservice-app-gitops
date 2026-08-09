#!/usr/bin/env bash
# Read-only composite evidence for Redis and the complete local business-service
# set. Kubernetes observations and port-forwards are non-mutating; functional
# writes are limited to application data through the services' public protocols.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

NS=microtodo-local
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EVIDENCE_DIR="$LOCAL_DIR/evidence/service-onboarding/$RUN_ID"
PUBLISH_SUMMARY="$LOCAL_DIR/publish/services/summary.json"

SERVICES=(auth-api todos-api users-api frontend log-message-processor)
APPLICATIONS=(infra-redis auth-api-local todos-api-local users-api-local frontend-local log-message-processor-local)
declare -A FORWARD_PORTS=(
  [auth-api]="${PILOT_AUTH_FORWARD_PORT:-18000}"
  [todos-api]="${PILOT_TODOS_FORWARD_PORT:-18002}"
  [users-api]="${PILOT_USERS_FORWARD_PORT:-18003}"
  [frontend]="${PILOT_FRONTEND_FORWARD_PORT:-18080}"
  [log-message-processor]="${PILOT_LOG_PROCESSOR_FORWARD_PORT:-19090}"
  [redis]="${PILOT_REDIS_FORWARD_PORT:-16379}"
)
declare -A TARGET_PORTS=(
  [auth-api]=8000
  [todos-api]=8082
  [users-api]=8083
  [frontend]=8080
  [log-message-processor]=9090
  [redis]=6379
)
declare -A NAMESPACES=(
  [auth-api]="$NS"
  [todos-api]="$NS"
  [users-api]="$NS"
  [frontend]="$NS"
  [log-message-processor]="$NS"
  [redis]=redis
)
PF_PIDS=()

cleanup() {
  local pid
  for pid in "${PF_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

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

start_forward() {
  local service="$1" namespace="${NAMESPACES[$1]}"
  local local_port="${FORWARD_PORTS[$1]}" target_port="${TARGET_PORTS[$1]}" pid
  kro port-forward -n "$namespace" "svc/$service" "$local_port:$target_port" \
    >"$EVIDENCE_DIR/port-forwards/$service.log" 2>&1 &
  pid=$!
  PF_PIDS+=("$pid")
  for _ in {1..30}; do
    if (exec 8<>"/dev/tcp/127.0.0.1/$local_port") 2>/dev/null; then
      exec 8>&-
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || die "$service port-forward exited before becoming ready"
    sleep 1
  done
  die "$service port-forward did not become ready"
}

http_capture() {
  local name="$1" expected="$2"
  shift 2
  local status
  status="$(curl -sS -o "$EVIDENCE_DIR/http/$name.body" -w '%{http_code}' "$@")" \
    || die "$name request failed"
  printf '%s\n' "$status" >"$EVIDENCE_DIR/http/$name.status"
  [[ "$status" == "$expected" ]] \
    || die "$name returned HTTP $status, expected $expected"
}

decode_jwt_payload() {
  local token="$1" segment padding
  segment="${token#*.}"
  segment="${segment%%.*}"
  case $(( ${#segment} % 4 )) in
    0) padding='' ;;
    2) padding='==' ;;
    3) padding='=' ;;
    *) return 1 ;;
  esac
  printf '%s%s' "$segment" "$padding" | tr '_-' '/+' | base64 -d
}

redis_ping() {
  local port="${FORWARD_PORTS[redis]}" response=""
  exec 9<>"/dev/tcp/127.0.0.1/$port" || die "could not reach forwarded Redis"
  printf '*1\r\n$4\r\nPING\r\n' >&9
  IFS= read -r -t 5 response <&9 || true
  exec 9>&- 9<&-
  response="${response%$'\r'}"
  printf '%s\n' "$response" | tee "$EVIDENCE_DIR/redis-ping.txt" >/dev/null
  [[ "$response" == +PONG ]] || die "Redis returned '$response' instead of PONG"
}

mkdir -p "$EVIDENCE_DIR"/{applications,deployments,pods,http,port-forwards,functional,policy}
[[ -f "$PUBLISH_SUMMARY" ]] || die "publication summary not found: $PUBLISH_SUMMARY"
EXPECTED_SHA="$(git --git-dir="$BARE_REPO" rev-parse main)"
PUBLISHED_SHA="$(jq -r '.serviceCommit' "$PUBLISH_SUMMARY")"
[[ "$EXPECTED_SHA" == "$PUBLISHED_SHA" ]] \
  || die "pilot Git is $EXPECTED_SHA but publication summary records $PUBLISHED_SHA"
printf '%s\n' "$EXPECTED_SHA" >"$EVIDENCE_DIR/expected-revision.txt"
cp "$PUBLISH_SUMMARY" "$EVIDENCE_DIR/publication-summary.json"

log "waiting for required Applications at $EXPECTED_SHA"
for application in "${APPLICATIONS[@]}"; do
  wait_for_application_revision "$application" "$EXPECTED_SHA"
  kro get application "$application" -n argocd -o json \
    >"$EVIDENCE_DIR/applications/$application.json"
done
kro get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision' \
  >"$EVIDENCE_DIR/application-status.txt"

business_count="$(kro get applications -n argocd \
  -l microtodosuite.io/business-service=true -o name | wc -l | tr -d ' ')"
[[ "$business_count" == 5 ]] || die "expected five business Applications, found $business_count"

log "waiting for Redis and all business Deployments"
kro wait -n redis deployment/redis --for=condition=Available --timeout=180s >&2
kro get deployment redis -n redis -o json >"$EVIDENCE_DIR/deployments/redis.json"
for service in "${SERVICES[@]}"; do
  kro wait -n "$NS" "deployment/$service" --for=condition=Available --timeout=300s >&2
  kro get deployment "$service" -n "$NS" -o json \
    >"$EVIDENCE_DIR/deployments/$service.json"
done

kro get pods -n redis -o json >"$EVIDENCE_DIR/pods/redis.json"
kro get pods -n "$NS" -o json >"$EVIDENCE_DIR/pods/business-services.json"
jq -e 'all(.items[];
  .status.phase == "Running" and
  all(.status.containerStatuses[]?; .ready == true and
    (.state.waiting.reason // "") != "CrashLoopBackOff"))' \
  "$EVIDENCE_DIR/pods/redis.json" >/dev/null \
  || die "a Redis pod is not Running and Ready"
jq -e --argjson names '[]' 'all(.items[];
  .status.phase == "Running" and
  all(.status.containerStatuses[]?; .ready == true and
    (.state.waiting.reason // "") != "CrashLoopBackOff"))' \
  "$EVIDENCE_DIR/pods/business-services.json" >/dev/null \
  || die "a business-service pod is not Running and Ready"

for service in "${SERVICES[@]}"; do
  digest="$(jq -r --arg service "$service" '.imageDigests[$service]' "$PUBLISH_SUMMARY")"
  expected_image="localhost:${PILOT_REGISTRY_PORT}/$service@$digest"
  desired_image="$(jq -r --arg service "$service" \
    '.spec.template.spec.containers[] | select(.name == $service) | .image' \
    "$EVIDENCE_DIR/deployments/$service.json")"
  [[ "$desired_image" == "$expected_image" ]] \
    || die "$service desired image is $desired_image, expected $expected_image"
  pod_json="$EVIDENCE_DIR/pods/$service.json"
  kro get pods -n "$NS" -l "app.kubernetes.io/name=$service" -o json >"$pod_json"
  jq -e --arg digest "$digest" \
    '.items | length == 1 and all(.[].status.containerStatuses[]?;
      .ready == true and (.imageID | contains($digest)))' "$pod_json" >/dev/null \
    || die "$service running image ID does not match published digest $digest"
done

redis_desired_image="$(jq -r '.spec.template.spec.containers[] | select(.name == "redis") | .image' \
  "$EVIDENCE_DIR/deployments/redis.json")"
[[ "$redis_desired_image" == 'redis:7.4.9-alpine@sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99' ]] \
  || die "Redis desired image is not the reviewed immutable digest"

for service in redis "${SERVICES[@]}"; do start_forward "$service"; done
redis_ping

http_capture auth-health 200 "http://127.0.0.1:${FORWARD_PORTS[auth-api]}/version"
http_capture users-health 200 "http://127.0.0.1:${FORWARD_PORTS[users-api]}/prometheus"
http_capture todos-health 200 "http://127.0.0.1:${FORWARD_PORTS[todos-api]}/metrics"
http_capture processor-health 200 "http://127.0.0.1:${FORWARD_PORTS[log-message-processor]}/metrics"
http_capture frontend-shell 200 "http://127.0.0.1:${FORWARD_PORTS[frontend]}/"
rg -q '<div id="app"></div>|<div id=app></div>' "$EVIDENCE_DIR/http/frontend-shell.body" \
  || die "frontend response is not the built application shell"

login_tmp="$EVIDENCE_DIR/functional/login-raw.tmp"
valid_status="$(curl -sS -o "$login_tmp" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  --data '{"username":"johnd","password":"foo"}' \
  "http://127.0.0.1:${FORWARD_PORTS[auth-api]}/login")"
[[ "$valid_status" == 200 ]] || die "valid auth-api login returned HTTP $valid_status"
TOKEN="$(jq -er '.accessToken | select(type == "string" and length > 20)' "$login_tmp")" \
  || die "valid login did not return an access token"
decode_jwt_payload "$TOKEN" >"$EVIDENCE_DIR/functional/login-claims.json" \
  || die "could not decode login token payload"
jq -e '.username == "johnd" and .firstname == "John" and .lastname == "Doe"' \
  "$EVIDENCE_DIR/functional/login-claims.json" >/dev/null \
  || die "login token does not contain users-api seed profile"
jq -n --argjson status "$valid_status" --arg user johnd \
  --argjson tokenLength "${#TOKEN}" \
  '{status:$status,user:$user,accessTokenPresent:true,accessTokenLength:$tokenLength}' \
  >"$EVIDENCE_DIR/functional/valid-login.json"
rm -f "$login_tmp"

invalid_status="$(curl -sS -o "$EVIDENCE_DIR/functional/invalid-login.body" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  --data '{"username":"johnd","password":"wrong"}' \
  "http://127.0.0.1:${FORWARD_PORTS[auth-api]}/login")"
printf '%s\n' "$invalid_status" >"$EVIDENCE_DIR/functional/invalid-login.status"
[[ "$invalid_status" == 401 ]] || die "invalid auth-api login returned HTTP $invalid_status, expected 401"

profile_status="$(curl -sS -o "$EVIDENCE_DIR/functional/users-profile.json" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:${FORWARD_PORTS[users-api]}/users/johnd")"
[[ "$profile_status" == 200 ]] || die "users-api profile returned HTTP $profile_status"
jq -e '.username == "johnd" and .firstname == "John" and .lastname == "Doe"' \
  "$EVIDENCE_DIR/functional/users-profile.json" >/dev/null \
  || die "users-api did not return the seeded johnd profile"
printf '%s\n' "$profile_status" >"$EVIDENCE_DIR/functional/users-profile.status"

todos_list_status="$(curl -sS -o "$EVIDENCE_DIR/functional/todos-list.json" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:${FORWARD_PORTS[todos-api]}/todos")"
[[ "$todos_list_status" == 200 ]] || die "todos-api list returned HTTP $todos_list_status"
jq -e 'type == "object" and length >= 3' "$EVIDENCE_DIR/functional/todos-list.json" >/dev/null \
  || die "todos-api did not return its seeded in-memory list"

processor_before="$(curl -sS "http://127.0.0.1:${FORWARD_PORTS[log-message-processor]}/metrics" \
  | awk '$1 == "log_messages_processed_total" {print $2; exit}')"
processor_before="${processor_before:-0}"
printf '%s\n' "$processor_before" >"$EVIDENCE_DIR/functional/processor-count-before.txt"
event_since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
todo_content="pilot-evidence-$RUN_ID"
create_status="$(curl -sS -o "$EVIDENCE_DIR/functional/todo-created.json" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  --data "{\"content\":\"$todo_content\"}" \
  "http://127.0.0.1:${FORWARD_PORTS[todos-api]}/todos")"
[[ "$create_status" == 200 ]] || die "todos-api create returned HTTP $create_status"
todo_id="$(jq -er --arg content "$todo_content" \
  'select(.content == $content) | .id' "$EVIDENCE_DIR/functional/todo-created.json")" \
  || die "todos-api create response did not contain the requested todo"
printf '%s\n' "$create_status" >"$EVIDENCE_DIR/functional/todo-created.status"

processor_pod="$(jq -r '.items[0].metadata.name' "$EVIDENCE_DIR/pods/log-message-processor.json")"
deadline=$(( $(date +%s) + 30 ))
event_found=false
while (( $(date +%s) <= deadline )); do
  kro logs -n "$NS" "$processor_pod" --since-time="$event_since" \
    >"$EVIDENCE_DIR/functional/processor-event.log" 2>&1 || true
  if rg -q "'opName': 'CREATE'.*'username': 'johnd'.*'todoId': ${todo_id}([,}])" \
      "$EVIDENCE_DIR/functional/processor-event.log"; then
    event_found=true
    break
  fi
  sleep 2
done
[[ "$event_found" == true ]] \
  || die "log-message-processor did not record the todos-api CREATE event for ID $todo_id"

processor_after="$(curl -sS "http://127.0.0.1:${FORWARD_PORTS[log-message-processor]}/metrics" \
  | awk '$1 == "log_messages_processed_total" {print $2; exit}')"
processor_after="${processor_after:-0}"
printf '%s\n' "$processor_after" >"$EVIDENCE_DIR/functional/processor-count-after.txt"
awk -v before="$processor_before" -v after="$processor_after" \
  'BEGIN { exit !(after > before) }' \
  || die "processor success metric did not increase ($processor_before -> $processor_after)"

frontend_login_tmp="$EVIDENCE_DIR/functional/frontend-login-raw.tmp"
frontend_login_status="$(curl -sS -o "$frontend_login_tmp" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  --data '{"username":"johnd","password":"foo"}' \
  "http://127.0.0.1:${FORWARD_PORTS[frontend]}/login")"
[[ "$frontend_login_status" == 200 ]] \
  || die "frontend-routed login returned HTTP $frontend_login_status"
FRONTEND_TOKEN="$(jq -er '.accessToken | select(type == "string" and length > 20)' "$frontend_login_tmp")" \
  || die "frontend-routed login returned no token"
jq -n --argjson status "$frontend_login_status" \
  --argjson tokenLength "${#FRONTEND_TOKEN}" \
  '{status:$status,accessTokenPresent:true,accessTokenLength:$tokenLength}' \
  >"$EVIDENCE_DIR/functional/frontend-login.json"
rm -f "$frontend_login_tmp"

frontend_todos_status="$(curl -sS -o "$EVIDENCE_DIR/functional/frontend-todos.json" -w '%{http_code}' \
  -H "Authorization: Bearer $FRONTEND_TOKEN" \
  "http://127.0.0.1:${FORWARD_PORTS[frontend]}/todos")"
[[ "$frontend_todos_status" == 200 ]] \
  || die "frontend-routed todo list returned HTTP $frontend_todos_status"
jq -e 'type == "object" and length >= 3' "$EVIDENCE_DIR/functional/frontend-todos.json" >/dev/null \
  || die "frontend-routed todo list is not functional"

kro get policyreport -n "$NS" -o json >"$EVIDENCE_DIR/policy/policyreports.json"
jq -e '[.items[].results[]? | select(.result == "fail" or .result == "error")] | length == 0' \
  "$EVIDENCE_DIR/policy/policyreports.json" >/dev/null \
  || die "Kyverno reports a fail/error result for the service namespace"

http_capture auth-health-final 200 "http://127.0.0.1:${FORWARD_PORTS[auth-api]}/version"

COMPLETED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --arg result pass \
  --arg expectedRevision "$EXPECTED_SHA" \
  --arg startedAt "$STARTED_AT" \
  --arg completedAt "$COMPLETED_AT" \
  --arg redisPing PONG \
  --argjson businessApplications "$business_count" \
  --argjson validLoginStatus "$valid_status" \
  --argjson invalidLoginStatus "$invalid_status" \
  --argjson usersProfileStatus "$profile_status" \
  --argjson todoListStatus "$todos_list_status" \
  --argjson todoCreateStatus "$create_status" \
  --arg todoId "$todo_id" \
  --arg processorBefore "$processor_before" \
  --arg processorAfter "$processor_after" \
  --argjson frontendLoginStatus "$frontend_login_status" \
  --argjson frontendTodosStatus "$frontend_todos_status" \
  '{result:$result,expectedRevision:$expectedRevision,startedAt:$startedAt,
    completedAt:$completedAt,businessApplications:$businessApplications,
    redis:{ping:$redisPing},auth:{validLoginStatus:$validLoginStatus,
    invalidLoginStatus:$invalidLoginStatus,finalHealthStatus:200},
    users:{profileStatus:$usersProfileStatus,dataMode:"pod-local H2 seed data"},
    todos:{listStatus:$todoListStatus,createStatus:$todoCreateStatus,id:$todoId,
    dataMode:"process-local memory"},processor:{metricBefore:$processorBefore,
    metricAfter:$processorAfter,eventMatched:true},frontend:{shellStatus:200,
    loginStatus:$frontendLoginStatus,todosStatus:$frontendTodosStatus,
    exposure:"local port-forward"},continuity:{redis:"ephemeral single node",
    todos:"process-local",users:"pod-local H2"}}' \
  >"$EVIDENCE_DIR/summary.json"

ok "evidence retained at $EVIDENCE_DIR"
echo "SERVICES VERIFIED: Redis and all five business services are Synced, Healthy, Ready, and functional."

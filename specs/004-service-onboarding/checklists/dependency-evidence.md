# Dependency Evidence: todos-api and users-api

**Recorded**: 2026-08-09
**Result**: CONFIRMED — todos-api does not call users-api directly
**Final local desired-state revision**: `831b0093745c0334baed3cca5f7765b074597ac8`
**todos-api source revision**: `d890de12fd1127960a4bc23634e17760b47fa4b2`
**todos-api image digest**: `sha256:a637e092c6c10260954231e736a41c203fc8a39206845f1112fdece744405990`

## Conclusion

The Eraser `todos-api -> users-api` edge does not describe the built service.
For authenticated todo operations, todos-api validates the auth-api-issued JWT
locally with the shared `JWT_SECRET`; it does not retrieve the user from
users-api. Todo state is process-local. CREATE and DELETE operations publish an
event to Redis, which log-message-processor consumes.

Redis is therefore todos-api's only required service endpoint in the onboarding
contract. The workload also consumes the shared JWT Secret, and its source has
an optional Zipkin telemetry destination, but neither is a direct users-api
business-service dependency.

## Revision and live-workload chain

| Link | Specific evidence | Finding |
| --- | --- | --- |
| Reviewed source -> image | [publication-summary.json](../../../.local/evidence/service-onboarding/20260809T183018Z/publication-summary.json) and [publish-services.sh](../../../scripts/pilot/publish-services.sh) | The evidence maps source `d890de12...` to the deployed todos-api digest `sha256:a637e092...`; the publisher rejects a dirty sibling checkout before recording that revision. |
| Desired state -> ArgoCD | [application-status-final.txt](../../../.local/evidence/service-onboarding/20260809T183018Z/application-status-final.txt) and [todos-api-local.json](../../../.local/evidence/service-onboarding/20260809T183018Z/applications/todos-api-local.json) | `todos-api-local` was Synced/Healthy under the shared ApplicationSet at the final local revision. |
| ArgoCD -> running container | [deployments/todos-api.json](../../../.local/evidence/service-onboarding/20260809T183018Z/deployments/todos-api.json) and [pods/todos-api.json](../../../.local/evidence/service-onboarding/20260809T183018Z/pods/todos-api.json) | The Deployment was Available and its Ready pod ran exactly `localhost:5001/todos-api@sha256:a637e092...`. |
| Runtime inputs | [deployments/todos-api.json](../../../.local/evidence/service-onboarding/20260809T183018Z/deployments/todos-api.json) and [configmap.yaml](../../../apps/todos-api/base/configmap.yaml) | The pod consumes `JWT_SECRET` plus `todos-api-config`. That ConfigMap contains `TODO_API_PORT`, `REDIS_HOST`, `REDIS_PORT`, and `REDIS_CHANNEL`; it contains no users-api address. |
| Todo behavior | [summary.json](../../../.local/evidence/service-onboarding/20260809T183018Z/summary.json), [todos-list.json](../../../.local/evidence/service-onboarding/20260809T183018Z/functional/todos-list.json), and [todo-created.json](../../../.local/evidence/service-onboarding/20260809T183018Z/functional/todo-created.json) | Authenticated list and create both returned HTTP 200, and the created todo had ID `5`; the summary records process-local memory. |
| Redis event path | [processor-event.log](../../../.local/evidence/service-onboarding/20260809T183018Z/functional/processor-event.log) and [summary.json](../../../.local/evidence/service-onboarding/20260809T183018Z/summary.json) | log-message-processor received the matching `CREATE`, `username: johnd`, `todoId: 5` event; its processed-message metric increased from 2.0 to 3.0. |
| Separate users-api path | [login-claims.json](../../../.local/evidence/service-onboarding/20260809T183018Z/functional/login-claims.json) and [users-profile.json](../../../.local/evidence/service-onboarding/20260809T183018Z/functional/users-profile.json) | users-api supplied the profile used during login/direct profile verification. This proves the separate `auth-api -> users-api` path, not a todos-api call. |

## Exact source behavior

The publication record ties the live image to
`microservice-app-todos-api@d890de12fd1127960a4bc23634e17760b47fa4b2`.
At that revision:

- `todoController.js:17-39` lists or creates todos from the controller's
  process-local cache using the username already present in the validated JWT;
- `todoController.js:53-63` serializes CREATE/DELETE metadata and invokes the
  Redis client's `publish` method;
- `server.js:24-41` constructs the Redis client from `REDIS_HOST` and
  `REDIS_PORT`;
- `server.js:80-98` validates JWTs and passes the Redis client/channel to the
  todo routes; and
- the repository contains no `USERS_API_ADDRESS`, users-api URL, users client,
  `axios`, or `fetch` call.

A code-graph outbound trace for `TodoController.create` reached only
`_getTodoData`, `_setTodoData`, and `_logOperation`; `_logOperation` publishes to
Redis. The list path reached only the local data helpers. No HTTP or cross-
service edge to users-api was present.

## Why the live run supports this conclusion

Runtime success alone cannot prove that a call never occurred, especially
because kind's default CNI does not enforce the declared NetworkPolicies. The
conclusion instead uses a closed revision chain:

1. the publisher records the exact clean todos-api source revision and digest;
2. ArgoCD and the pod evidence record that exact digest running;
3. the live Deployment records no users-api configuration;
4. the exact source contains no users-api client or call; and
5. the correlated live operation ends in a Redis event with the same todo ID.

Together, these files confirm the implemented path rather than merely failing
to observe a users-api request.

## Diagram disposition

The later Eraser correction should remove `todos-api -> users-api` from both
architecture diagrams. It should retain:

- `auth-api -> users-api` for profile-backed login;
- `frontend -> auth-api` and `frontend -> todos-api`;
- local JWT validation inside todos-api; and
- `todos-api -> Redis -> log-message-processor` for operation events.

No application, Kubernetes, Terraform, or Eraser resource was changed while
producing this evidence report.

## Evidence custody note

The desired state was committed to the machine-local pilot Git source, but the
raw `.local/evidence/` directory is intentionally ignored and is not tracked in
the hosted Git repository. This report preserves exact paths and conclusions;
it does not reclassify the raw artifacts as committed evidence.

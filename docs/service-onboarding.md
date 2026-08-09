# Complete Local Service Onboarding

Feature 004 adds todos-api, users-api, frontend, and log-message-processor to the
same `apps/*` discovery and environment activation contract already used by
auth-api. It also adds Redis to the existing `infrastructure/*` discovery path.
No second ApplicationSet or imperative deployment path exists.

## Runtime map

| Application | Port / health | Runtime dependencies | Local state |
| --- | --- | --- | --- |
| `auth-api-local` | 8000 `/version` | users-api, shared JWT key | none |
| `users-api-local` | 8083 `/prometheus` | shared JWT key | pod-local H2 seed rows |
| `todos-api-local` | 8082 `/metrics` | shared JWT key, Redis | process-local todo cache |
| `log-message-processor-local` | 9090 `/metrics` | Redis Pub/Sub | live subscription |
| `frontend-local` | 8080 `/` | auth-api, todos-api | static assets |
| `infra-redis` | 6379 `PING` | none | ephemeral `emptyDir` |

All business services use dedicated ServiceAccounts with automatic API-token
mounting disabled. Every Deployment has startup, readiness, and liveness checks.
Every active image is selected by immutable digest.

## Dependency ordering

`publish-services.sh` builds and pushes images before changing desired state,
then produces two commits only in `.local/git/microservice-app-gitops.git`:

1. Redis plus exact namespace/policy prerequisites.
2. The reviewed full tree, local activation, and all five service digests.

Between commits it waits for `infra-redis` at the first SHA, Deployment
availability, and a real `PONG`. It also asserts the four new service
Applications do not yet exist. This makes "Redis before consumers" an observed
state transition rather than a sync-wave intention.

The reviewed-tree mirror deliberately preserves
`clusters/local-kind/registration.yaml` and `root-app.yaml` from the
bootstrap-created pilot Git worktree. Those two files contain machine-specific
connection values and must not be replaced by the portable checked-in examples.

## Shared authentication

auth-api's local ExternalSecret remains the single owner of
`auth-api-secrets/JWT_SECRET`. users-api and todos-api reference that Secret and
key. They do not generate or store another value.

The acceptance flow uses the existing `johnd` seed and credential fixture:

1. auth-api signs an internal token and retrieves `/users/johnd` from users-api;
2. auth-api checks the existing credential allowlist and returns a login JWT;
3. the verifier decodes only the public claims and confirms the H2 seed profile;
4. users-api validates that token for direct profile lookup; and
5. todos-api validates it for protected todo operations.

An invalid password must still return HTTP 401.

## Redis event path

Both consumers use:

```text
redis.redis.svc.cluster.local:6379 / log_channel
```

The verifier records the processor success counter, creates a uniquely named
todo with the real login token, reads the returned ID, and requires both a
matching `CREATE` event in the current processor pod log and a higher processed
counter within 30 seconds.

## Frontend route

The canonical onboarding contract already permits a local port-forward. The
browser reaches only frontend's loopback-forwarded NGINX Service. NGINX resolves
and proxies the internal auth and todo service names, preserving same-origin
requests. A managed environment can later supply its exposure values without a
frontend-specific manifest fork.

## Verification standard

`verify-services.sh` fails unless all six required Applications observe the
exact current pilot Git SHA and report Synced/Healthy; all Deployments and Pods
are Ready; service image IDs match the publication digests; Redis returns
`PONG`; all intrinsic health paths respond; the synchronous and asynchronous
flows above pass; frontend shell/proxy checks pass; Kyverno has no fail/error
result; and auth-api is healthy again at the end.

The JWT value and signing secret are never written to evidence. Raw observations
and a machine-readable summary are retained below `.local/evidence/`.

## Explicit continuity limits

- Redis has no snapshot, append-only file, PVC, replica, backup, or failover.
- todos-api loses its cache when its pod is replaced and would diverge if scaled.
- users-api recreates H2 from `data.sql` for every pod and would diverge if
  scaled; it therefore stays at one replica in every inactive scaffold.
- users-api's legacy Java 8 process is explicitly memory-bounded because it did
  not reliably detect the local cgroup-v2 limit; this changes no H2 behavior.
- log-message-processor stays at one replica to avoid duplicate Pub/Sub work.

These are disclosed current-state risks, not accepted production guarantees.

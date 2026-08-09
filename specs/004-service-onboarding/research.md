# Research: Remaining Service Onboarding

## Decision 1: Reuse the freshly reverified pilot and settled contracts

**Decision**: Reuse the running `kind-microtodo-gitops-pilot` cluster, the
loopback registry and local Git reader, `clusters/base` ApplicationSets, and the
service/platform contracts from specs 001 and 003.

**Rationale**: Fresh observations on 2026-08-09 showed the node Ready and auth-api
plus KEDA, cert-manager, External Secrets, and Kyverno Synced/Healthy. Every
sibling service checkout was clean at a concrete `main` SHA. The user's request
explicitly forbids redesigning mechanisms already proved by those features.

**Alternatives considered**:

- Recreate the running cluster: rejected because a pilot is active and healthy.
- Add a second ApplicationSet or per-service Application: rejected because
  `apps/*` discovery already implements onboarding.
- Trust prior notes instead of live state: rejected because this work requires
  current, machine-local evidence.

## Decision 2: Run Redis as a provider-neutral ephemeral platform dependency

**Decision**: Add `infrastructure/redis` as a one-replica Deployment and
ClusterIP Service in namespace `redis`, with a dedicated tokenless service
account, protocol probes, bounded resources, explicit network-policy intent, and
an `emptyDir` data directory. Use `redis:7.4.9-alpine` at manifest digest
`sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99`.

**Rationale**: The image was already present on this machine as the official
`redis` repository digest and its binary reported Redis 7.4.9. Redis 2.x clients
in todos-api and log-message-processor use compatible baseline commands and
Pub/Sub. A direct Kubernetes workload is the smallest complete local dependency;
there is no upstream controller or release manifest to vendor. Explicitly
disabling snapshots and append-only persistence preserves the constitution's
documented continuity risk instead of creating an unapproved storage design.

**Alternatives considered**:

- A hosted Redis or cloud operator: rejected because it would require provider
  credentials and expand the architecture.
- A Helm chart with additional subcomponents: rejected because the pilot needs
  one Redis endpoint and the existing platform folder contract accepts a
  self-contained Kustomize root.
- A StatefulSet with PVC: rejected because durable storage and recovery semantics
  are not ratified and would conceal, not solve, the current continuity risk.
- A Redis sidecar per consumer: rejected because todos and the processor must
  share one Pub/Sub channel.

## Decision 3: Map source-proven runtime contracts without changing services

**Decision**:

| Service | Port | Intrinsic health | Required dependencies | Local state |
| --- | ---: | --- | --- | --- |
| `todos-api` | 8082 | `/metrics` | shared JWT Secret; `redis.redis.svc.cluster.local:6379`; channel `log_channel` | process-local todo cache |
| `users-api` | 8083 | `/prometheus` | shared JWT Secret | pod-local H2 seeded from `data.sql` |
| `frontend` | 8080 | `/` | `auth-api:8000`; `todos-api:8082`; syntactically valid optional Zipkin target | static assets only |
| `log-message-processor` | 9090 | `/metrics` | `redis.redis.svc.cluster.local:6379`; channel `log_channel` | none beyond live subscription |

The build inputs are the clean sibling commits:

| Service | Source commit |
| --- | --- |
| auth-api | `a182d557d8948284fc5e244fcaa70fd2f88fe404` |
| todos-api | `d890de12fd1127960a4bc23634e17760b47fa4b2` |
| users-api | `1f71fe7064fdb23de785378da32fa0ce3401781c` |
| frontend | `ba5b6c9c9f83978af0fb282775428f6ae5b0cea0` |
| log-message-processor | `eef67b4d1037a3de837420048e722363703188d3` |

The users-api image runs a legacy Java 8 service. The local kind node uses
cgroup v2, which that runtime did not reliably account for during live rollout:
the unbounded process crossed its 512 MiB pod limit during startup. Its base
ConfigMap therefore supplies explicit heap, metaspace, code-cache, direct-memory,
stack, and garbage-collector bounds. This is runtime containment only; it does
not alter the service's pod-local H2 data model.

**Rationale**: These values come from indexed source definitions, Dockerfiles,
and runtime configuration—not from generic service guesses. Each health endpoint
is served without invoking a second MicroTodoSuite business service.

**Alternatives considered**:

- Add new `/health` routes to sibling repositories: rejected because the source
  already exposes intrinsic successful endpoints and application changes are out
  of scope.
- Use TCP-only probes: rejected because the existing HTTP endpoints prove more
  than a listening socket.
- Scale users or todos horizontally: rejected because their current state models
  would diverge across replicas.

## Decision 4: Reuse one JWT signing Secret

**Decision**: users-api and todos-api read `auth-api-secrets/JWT_SECRET`, the
namespace-local Secret already generated once by auth-api's local ExternalSecret.
They do not create their own generators or secret values.

**Rationale**: auth-api signs both the login token and its internal users-api
lookup token. users-api and todos-api must validate those tokens with identical
key bytes. One ESO-owned target is already the established contract and all
three workloads share the environment namespace.

**Alternatives considered**:

- Independent Password generators: rejected because the tokens would fail
  signature verification.
- A checked-in local secret: rejected by the constitution and existing contract.
- Copying Secret values imperatively: rejected because it bypasses GitOps/ESO and
  exposes secret material.

## Decision 5: Frontend needs routing, but not a new local ingress mechanism

**Decision**: Keep frontend as a standard ClusterIP service and document a
read-only local port-forward. Its existing production NGINX configuration
continues to proxy same-origin `/login` to auth-api and `/todos` to todos-api via
cluster DNS. Future managed ingress remains an environment-owned exposure value
under the existing onboarding contract.

**Rationale**: Browsers cannot resolve cluster DNS directly, but they do not need
to: the user reaches NGINX, and NGINX resolves the internal upstreams. The
canonical contract already lists "Local port-forward or managed ingress" as
the exposure choice. Therefore the first user-facing service exercises an
existing seam and does not justify a NodePort, host mapping, or ingress
controller that would be local-only.

**Alternatives considered**:

- Add ingress-nginx now: rejected because TLS ingress is not needed for a
  loopback functional pilot and would add an unrequested platform capability.
- Expose backend services to the browser separately: rejected because it breaks
  same-origin routing and duplicates exposure configuration.
- Add a frontend-only NodePort: rejected because it is host/topology-specific and
  bypasses the environment-owned exposure contract.

## Decision 6: Stage Redis before service discovery can activate consumers

**Decision**: The publisher first commits only Redis plus its exact project and
environment policy prerequisites, waits for ArgoCD health and `PONG`, and only
then commits the four new service directories and immutable image selections.

**Rationale**: Sync-wave annotations cannot provide a durable cross-Application
runtime-readiness gate after Applications exist. Separate local Git revisions
make ordering observable, failure-isolated, and reversible.

The full-tree snapshot excludes the bootstrap-resolved local registration and
root Application files. Preserving those two machine values keeps the root and
its retained default AppProject on the same Git URL while every reusable
mechanism file still comes from the reviewed working tree.

**Alternatives considered**:

- One commit with sync waves: rejected because object ordering is not proof that
  Redis is ready before consumer processes connect.
- Init containers that wait forever: rejected because they duplicate dependency
  orchestration in every service and still do not prove the platform first.
- Directly create Redis before committing services: rejected by GitOps-only
  deployment.

## Decision 7: Prove behavior through one correlated evidence run

**Decision**: The verifier observes exact Argo revisions and pod images, then:

1. sends Redis `PING` and expects `PONG`;
2. checks each intrinsic HTTP endpoint;
3. performs valid and invalid auth-api logins;
4. uses the valid token to retrieve users-api's seeded `johnd` profile;
5. lists and creates todos with that token;
6. matches the returned todo ID to a subsequent processor log event and metric
   increase; and
7. repeats login and todo list through frontend's NGINX routes.

**Rationale**: This proves synchronous, asynchronous, secret-sharing, routing,
and data-seed behavior. Application status or container readiness alone cannot
support those claims.

**Alternatives considered**:

- Only curl health endpoints: rejected because that misses all cross-service
  behavior.
- Publish a synthetic event without todos-api: retained only as a diagnostic
  fallback, not acceptance, because it would not prove the real producer.
- Browser automation: rejected for this infrastructure feature because the same
  NGINX HTTP routes can be verified deterministically without adding a browser
  runtime; loading the real built shell is still required.

## Decision 8: Support the machine's embedded Kustomize

**Decision**: Pilot render helpers use standalone `kustomize` when present and
fall back to `kubectl kustomize`; image selection uses a narrow YAML edit helper
rather than depending on `kustomize edit`.

**Rationale**: Fresh verification found kubectl's embedded Kustomize 5.8.1 but no
standalone binary on PATH. The repository already uses the same render fallback
in its platform contract. Generalizing the helper keeps the quickstart reusable
without changing desired-state semantics.

**Alternatives considered**:

- Download a tool during every publish: rejected because it creates an
  unnecessary network prerequisite.
- Assume a prior shell PATH: rejected because the user required verification
  from the machine's current state.

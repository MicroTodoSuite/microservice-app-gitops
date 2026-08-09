---

description: "Dependency-ordered implementation tasks for Redis and the remaining local services"
---

# Tasks: Remaining Service Onboarding

**Input**: Design documents from `specs/004-service-onboarding/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`,
`contracts/remaining-service-registration.md`, and `quickstart.md`

**Tests**: Static contracts and live functional evidence are mandatory because
the feature specification explicitly rejects configuration-only success.

**Organization**: Tasks follow the four user stories and finish with one
cross-story publication/evidence phase. Redis's live gate precedes the service
commit by construction.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: May be implemented independently in different files after its phase
  prerequisite is complete.
- **[Story]**: `US1` Redis, `US2` users/auth, `US3` todos/processor, or `US4`
  frontend.

## Phase 1: Setup and Contract Tests

**Purpose**: Encode the expected extension before adding desired state.

- [x] T001 [P] [US1] Extend the active-platform count and add Redis render/image/resource assertions in `tests/contract/platform-addons.sh`
- [x] T002 [P] Create the failing four-service structure, labels, service-account, probes, immutable-image, shared-secret, routing, and provider-neutrality contract in `tests/contract/service-onboarding.sh`
- [x] T003 [P] Add the four concrete service mappings, Redis dependency rule, frontend port-forward decision, and continuity disclosures to `specs/001-local-gitops-pilot/contracts/service-onboarding-contract.md`

---

## Phase 2: Shared Foundations

**Purpose**: Prepare reusable helpers and exact cluster/environment seams needed
by more than one story.

**Critical**: Complete before service manifests or publication automation.

- [x] T004 Add standalone-or-embedded Kustomize rendering plus narrow immutable image editing helpers to `scripts/pilot/lib/common.sh`
- [x] T005 [P] Add and register the labeled `microtodo-local` Namespace plus Redis-consumer egress policy in `environments/local/namespace.yaml`, `environments/local/networkpolicy-allow-redis.yaml`, and `environments/local/kustomization.yaml`
- [x] T006 [P] Add only the exact `redis` destination namespace to `clusters/base/project.yaml`
- [x] T007 [P] Update local activation comments and operator wording for the complete discovered service set in `clusters/local-kind/activation-apps.yaml` and `clusters/local-kind/activation-templates/local/activation-apps.yaml`

**Checkpoint**: Shared registration, policy, and script seams are ready; no new
workload has been reconciled.

---

## Phase 3: User Story 1 - Provide Redis Before Its Consumers (Priority: P1)

**Goal**: Add one complete, immutable, ephemeral Redis platform dependency and a
publisher gate that proves it before service activation.

**Independent Test**: `infra-redis` is Synced/Healthy at its own local commit,
Deployment/Pod readiness passes, and a protocol ping returns `PONG` while none
of the four new service Applications exists.

- [x] T008 [P] [US1] Add Redis namespace, tokenless ServiceAccount, ClusterIP Service, and Kustomize entry point in `infrastructure/redis/namespace.yaml`, `infrastructure/redis/serviceaccount.yaml`, `infrastructure/redis/service.yaml`, and `infrastructure/redis/kustomization.yaml`
- [x] T009 [P] [US1] Add the single-replica digest-pinned Redis Deployment with disabled persistence, ephemeral data, bounded resources, and protocol probes in `infrastructure/redis/deployment.yaml`
- [x] T010 [P] [US1] Add provider-neutral ingress/default-deny policy intent and the explicit non-durable operating contract in `infrastructure/redis/networkpolicy.yaml` and `infrastructure/redis/README.md`
- [x] T011 [US1] Implement the Redis-only local Git commit, exact-revision Argo wait, Deployment wait, port-forward, and RESP `PONG` gate in `scripts/pilot/publish-services.sh`
- [x] T012 [US1] Run Redis and local-registration renders plus the Redis portion of `tests/contract/platform-addons.sh`, confirming the new tests pass without cluster mutation

**Checkpoint**: Redis desired state and its independent gate are complete.

---

## Phase 4: User Story 2 - Complete Users and Authentication Integration (Priority: P1)

**Goal**: Register users-api with its unchanged pod-local H2 architecture and
shared JWT key so auth-api's real login path works.

**Independent Test**: A known valid login returns a profile-backed JWT, invalid
login is rejected, and the valid token retrieves the matching seeded user.

- [x] T013 [P] [US2] Add users-api's labeled base ConfigMap, tokenless ServiceAccount, ClusterIP Service, and Deployment with shared JWT reference, intrinsic probes, one-replica-safe runtime, and explicit H2 annotation in `apps/users-api/base/`
- [x] T014 [P] [US2] Add users-api economical/full components and managed topology seam in `apps/users-api/components/` and `apps/users-api/topology/kustomization.yaml`
- [x] T015 [US2] Add users-api local plus provider-neutral inactive dev/staging/prod overlays, keeping one replica and no volume claim, in `apps/users-api/overlays/`
- [x] T016 [US2] Complete users-api shared-secret, no-PVC, one-replica, probe, and render assertions in `tests/contract/service-onboarding.sh`

**Checkpoint**: users-api is structurally ready for the final service commit and
does not imply persistence.

---

## Phase 5: User Story 3 - Process Authenticated Todo Events (Priority: P2)

**Goal**: Register the real Redis producer and consumer with compatible JWT,
endpoint, channel, health, and continuity contracts.

**Independent Test**: A real auth token lists/creates a todo and the processor
metric/log proves consumption of that create event.

- [x] T017 [P] [US3] Add todos-api's labeled base ConfigMap, tokenless ServiceAccount, ClusterIP Service, Deployment, shared JWT reference, Redis config, intrinsic probes, and in-memory risk annotation in `apps/todos-api/base/`
- [x] T018 [P] [US3] Add todos-api topology components plus local and provider-neutral inactive managed overlays with one replica in `apps/todos-api/components/`, `apps/todos-api/topology/`, and `apps/todos-api/overlays/`
- [x] T019 [P] [US3] Add log-message-processor's labeled base ConfigMap, tokenless ServiceAccount, ClusterIP Service, Deployment, Redis config, metrics port, and intrinsic probes in `apps/log-message-processor/base/`
- [x] T020 [P] [US3] Add log-message-processor topology components plus local and provider-neutral inactive managed overlays with one replica in `apps/log-message-processor/components/`, `apps/log-message-processor/topology/`, and `apps/log-message-processor/overlays/`
- [x] T021 [US3] Complete Redis endpoint/channel equality, shared JWT, one-replica state risk, probes, and render assertions for both services in `tests/contract/service-onboarding.sh`

**Checkpoint**: Both Redis consumers are structurally compatible with the
already-gated dependency.

---

## Phase 6: User Story 4 - Reach the Browser Application Locally (Priority: P2)

**Goal**: Register frontend as a standard service whose existing NGINX routes
backends internally while the user reaches only a local port-forward.

**Independent Test**: The built shell loads over the frontend Service and its
same-origin `/login` and authorized `/todos` routes return successful responses.

- [x] T022 [P] [US4] Add frontend's labeled base ConfigMap, tokenless ServiceAccount, ClusterIP Service, Deployment, backend Service addresses, and intrinsic probes in `apps/frontend/base/`
- [x] T023 [P] [US4] Add frontend topology components plus local and provider-neutral inactive managed overlays in `apps/frontend/components/`, `apps/frontend/topology/`, and `apps/frontend/overlays/`
- [x] T024 [US4] Complete frontend ClusterIP-only, no-Ingress/NodePort, backend address, probe, and render assertions in `tests/contract/service-onboarding.sh`

**Checkpoint**: All four new services satisfy the canonical reusable structure.

---

## Phase 7: Publication and Composite Evidence

**Purpose**: Generalize the existing pilot workflow, reconcile through local Git
in the required order, and prove every story live.

- [x] T025 Implement clean sibling-source validation, five-service Docker build/push, registry digest capture, and machine-readable publication summary in `scripts/pilot/publish-services.sh`
- [x] T026 Implement reviewed-worktree snapshotting, immutable overlay edits, local activation, static pre-commit renders, local-only push safety, and the final service commit in `scripts/pilot/publish-services.sh`
- [x] T027 Update `scripts/pilot/publish-auth.sh`, `scripts/pilot/preflight.sh`, and `scripts/pilot/bootstrap.sh` so fresh quickstart uses the suite publisher and works with embedded Kustomize without activating zero-digest services
- [x] T028 Implement exact-revision ArgoCD, Deployment, Pod, restart, running-image, Redis, and intrinsic HTTP evidence capture in `scripts/pilot/verify-services.sh`
- [x] T029 Implement valid/invalid login, JWT profile, todo list/create, processor metric/log correlation, frontend shell/proxy, and final auth-api checks in `scripts/pilot/verify-services.sh`
- [x] T030 Keep existing auth/platform verification meaningful in a five-service/five-platform pilot by updating `scripts/pilot/verify.sh`, `scripts/pilot/verify-platform.sh`, and their static expectations
- [x] T031 [P] Document the full local workflow, frontend route, source inputs, shared JWT behavior, and Redis/todos/H2 continuity warnings in `docs/service-onboarding.md`, `docs/local-pilot-quickstart.md`, and `AGENTS.md`
- [x] T032 Run `tests/contract/platform-addons.sh`, `tests/contract/service-onboarding.sh`, every active/inactive overlay render, shell syntax checks, `git diff --check`, and provider scans; fix all failures
- [x] T033 Run `scripts/pilot/publish-services.sh`, proving the Redis commit becomes live and returns `PONG` before the service commit is pushed, then wait for the final desired-state SHA
- [x] T034 Run `scripts/pilot/verify-services.sh`, inspect the timestamped raw evidence, re-check auth-api and every new application/pod live, and mark this task list complete only if every claim is evidenced

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Starts immediately; tests are expected to fail until their
  story manifests exist.
- **Shared Foundations (Phase 2)**: Depends on Setup and blocks all workload work.
- **Redis (Phase 3 / US1)**: Depends on Shared Foundations and blocks live
  reconciliation of US2-US4.
- **Users/Auth (Phase 4 / US2)**: Structurally depends on Shared Foundations and
  functionally depends on the existing auth-api/ESO contract.
- **Todos/Processor (Phase 5 / US3)**: Depends on Redis's declared contract; live
  acceptance depends on US2's issued token.
- **Frontend (Phase 6 / US4)**: Depends on the auth and todos Service contracts;
  its manifests remain independently renderable.
- **Publication/Evidence (Phase 7)**: Depends on all stories and performs the
  required live ordering: Redis commit/gate, then service commit, then evidence.

### User Story Dependencies

```text
US1 Redis -----------------+
                           +--> US3 todo event path --+
existing auth + US2 -------+                         +--> final evidence
existing auth + US2 ----------------> US4 routing ---+
```

- US1 is independently live-testable before any new service Application exists.
- US2 is independently testable through auth-api and users-api.
- US3 needs Redis and a token from US2 for its real producer/consumer path.
- US4 needs auth and todos upstreams for both proxy checks, while its shell and
  intrinsic health remain independently testable.

### Parallel Opportunities

- T001-T003 may proceed independently.
- T005-T007 touch separate foundation files.
- Within each service, base and topology files may be authored independently.
- T017-T020 split todos and processor paths across different directories.
- T022-T023 split frontend base from topology/overlays.
- Documentation T031 may proceed after the final command contracts are stable.

## Implementation Strategy

1. Encode contract failures before desired state.
2. Complete shared seams and Redis as the independently testable MVP.
3. Add users/auth, then the Redis producer/consumer pair, then frontend.
4. Generalize publication and verification without adding a cluster mutation
   path.
5. Pass all static checks.
6. Publish Redis and wait for live `PONG`.
7. Publish all services and run one correlated evidence set.

## Notes

- A checked box means the file or live outcome was actually verified, not merely
  drafted.
- Local pilot commits are required deployment inputs; hosted commits/pushes are
  outside this feature.
- If any live check fails, correct desired state in the disposable local clone or
  reviewed checkout and reconcile with another local commit; never repair the
  managed object directly.

# Feature Specification: Remaining Service Onboarding

**Feature Branch**: `004-service-onboarding`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "Onboard todos-api, users-api, frontend, and log-message-processor onto the existing local GitOps pilot; add Redis first, preserve documented continuity risks, use the existing onboarding contract, and prove every result live."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Provide Redis Before Its Consumers (Priority: P1)

As a platform operator, I can register a local Redis dependency through the same
GitOps-managed platform mechanism as the existing add-ons so that Redis-dependent
services never start against an absent dependency.

**Why this priority**: Both todos-api and log-message-processor require Redis;
their onboarding cannot be functionally correct until this shared dependency is
healthy and reachable.

**Independent Test**: Reconcile Redis alone, prove its platform application is
current and healthy at the local desired-state revision, prove its pod is ready,
and receive a successful ping response through its service.

**Acceptance Scenarios**:

1. **Given** the existing local cluster and platform registration mechanism,
   **When** the Redis desired state is published to the pilot Git source,
   **Then** a distinct Redis platform application becomes current and healthy
   before either Redis-dependent business service is activated.
2. **Given** the reconciled Redis service, **When** an operator sends a Redis
   protocol ping through the declared service, **Then** Redis returns `PONG`.
3. **Given** the platform's current continuity posture, **When** Redis is
   registered, **Then** its single-node, non-durable local behavior is disclosed
   and is not represented as production data continuity.

---

### User Story 2 - Complete Users and Authentication Integration (Priority: P1)

As a local pilot user, I can log in through auth-api and receive profile-backed
identity data from users-api, proving the first real business-service integration
rather than isolated health endpoints.

**Why this priority**: Authentication is the entry point for every protected
todo operation and validates shared secret configuration plus service discovery.

**Independent Test**: Reconcile users-api, submit one known seeded credential to
auth-api, and prove that a successful token contains the profile served by
users-api; an invalid credential must remain rejected.

**Acceptance Scenarios**:

1. **Given** users-api is current, healthy, and ready, **When** auth-api receives
   a valid seeded login, **Then** auth-api retrieves that user from users-api and
   returns a signed access token with the seeded profile fields.
2. **Given** auth-api and users-api share the established JWT secret contract,
   **When** a valid token is presented directly to users-api for its matching
   user, **Then** users-api returns that seeded user.
3. **Given** users-api uses pod-local H2 seed data, **When** it is onboarded,
   **Then** it remains a single replica with no newly invented persistent volume
   and the restart, scaling, and divergence risk is explicitly reported.
4. **Given** all remaining services and platform dependencies are reconciled,
   **When** auth-api is re-evaluated, **Then** auth-api remains current and healthy.

---

### User Story 3 - Process Authenticated Todo Events (Priority: P2)

As an authenticated pilot user, I can list and create todos while the log message
processor consumes the resulting event from Redis, proving both Redis consumers
perform their intended work.

**Why this priority**: A ready process is insufficient evidence for these
services; the required behavior crosses HTTP authentication, in-memory todo
state, Redis publication, and asynchronous consumption.

**Independent Test**: Use a real auth-api token to list and create a uniquely
identified todo, then observe the matching event in log-message-processor output
and an increment in its processed-message metric.

**Acceptance Scenarios**:

1. **Given** a token issued by auth-api, **When** the user requests todos-api's
   list endpoint, **Then** the service returns that user's seeded in-memory list.
2. **Given** Redis and log-message-processor are ready, **When** the user creates
   a uniquely identified todo, **Then** todos-api returns the created todo and
   log-message-processor records the corresponding Redis event.
3. **Given** the current todos-api architecture, **When** it is onboarded,
   **Then** its process-local todo data risk is disclosed and no unapproved
   persistence or horizontal-scaling behavior is added.

---

### User Story 4 - Reach the Browser Application Locally (Priority: P2)

As a local pilot user, I can reach the frontend through the exposure path already
allowed by the service-onboarding contract and use its same-origin backend routes.

**Why this priority**: The frontend is the first user-facing workload and must
prove more than an internal service health response.

**Independent Test**: Reach the frontend over the documented local port-forward,
load its rendered application shell, and call its `/login` and `/todos` proxy
paths successfully with real credentials and the resulting token.

**Acceptance Scenarios**:

1. **Given** the local contract already permits port-forward exposure, **When**
   the frontend is onboarded, **Then** it remains a normal reusable service with
   a cluster-internal Service and a documented operator-started port-forward;
   no local-only ingress controller, NodePort, or host binding is introduced.
2. **Given** the frontend's same-origin routing configuration, **When** a user
   logs in through the frontend route and then lists todos, **Then** those requests
   reach auth-api and todos-api and return successful functional responses.
3. **Given** a future managed environment needs external ingress, **When** that
   environment is registered, **Then** exposure remains an environment-owned
   value under the established contract rather than a frontend-only design fork.

### Edge Cases

- Redis is not ready when a dependent application begins reconciliation; the
  dependency must not be reported healthy merely because its process started.
- log-message-processor has started its metrics server but has not subscribed to
  Redis; verification must prove delivery of a uniquely identifiable message.
- A users-api pod restart recreates H2 seed state and discards any pod-local
  changes; evidence and documentation must continue to label this as a risk.
- A todos-api restart discards its process-local todo state; functional evidence
  must not imply durable storage.
- The optional tracing destination is absent; intrinsic health and business
  functions must remain verifiable without installing an unrequested tracing
  platform.
- A validly signed token requests a different users-api username; access remains
  denied by the existing service behavior.
- A local image is rebuilt at the same convenience tag; desired state must still
  select the registry-reported immutable digest.
- One application reaches a healthy state at an older revision; the evidence run
  must fail until every required application reports the exact current local Git
  revision.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST reuse the directory, discovery, cluster
  registration, environment activation, immutable image, health, secret, and
  verification rules in the existing service-onboarding contract.
- **FR-002**: The feature MUST NOT introduce a second business-service
  registration mechanism or a service-specific activation path.
- **FR-003**: Redis MUST be registered as a distinct GitOps-managed platform
  dependency through the existing folder-driven platform mechanism.
- **FR-004**: Redis MUST be current, healthy, ready, and respond to a protocol
  ping before todos-api or log-message-processor is accepted as onboarded.
- **FR-005**: Redis's local deployment MUST remain provider-neutral and MUST
  disclose its non-replicated, non-durable continuity limitation.
- **FR-006**: todos-api, users-api, frontend, and log-message-processor MUST each
  have the standard reusable service base plus local and inactive managed-
  environment overlay structure expected by the existing contract.
- **FR-007**: Each active service image MUST be selected by an immutable OCI
  digest obtained from the local pilot registry; a mutable tag alone is invalid.
- **FR-008**: Every service MUST use a dedicated service account without an
  automatically mounted Kubernetes API token unless source evidence requires API
  access.
- **FR-009**: Every service MUST declare startup, readiness, and liveness checks
  against an intrinsic endpoint that does not require another business service.
- **FR-010**: todos-api and users-api MUST consume the same namespace-local JWT
  secret contract already generated for auth-api; no duplicate random signing
  secret may be created.
- **FR-011**: todos-api and log-message-processor MUST use the same declared
  Redis service endpoint, port, and message channel.
- **FR-012**: users-api MUST use one local replica backed only by its existing
  pod-local H2 seed data; this feature MUST NOT add a persistent volume, external
  database, or undisclosed persistence behavior.
- **FR-013**: The pod-local H2 restart and replica-divergence risk MUST be stated
  in operator documentation and final evidence.
- **FR-014**: todos-api's process-local todo-state continuity limitation MUST be
  stated and MUST NOT be silently changed by this feature.
- **FR-015**: The frontend MUST preserve its same-origin proxy routes to auth-api
  and todos-api using service discovery names rather than browser-visible
  internal addresses.
- **FR-016**: Local frontend exposure MUST use the onboarding contract's existing
  port-forward option; the feature MUST NOT add an ingress controller, NodePort,
  or host-specific workload manifest solely for frontend.
- **FR-017**: The pilot publishing workflow MUST build each sibling service from
  its current checked-out source, push it only to the loopback pilot registry,
  record its immutable digest, and publish desired state only to the machine-
  local Git source.
- **FR-018**: GitOps-managed cluster state MUST change only through commits to the
  local pilot Git source and ArgoCD reconciliation; verification MUST contain no
  direct managed-state mutation.
- **FR-019**: A successful acceptance run MUST show auth-api and all four new
  business applications current and healthy at the exact local Git revision.
- **FR-020**: A successful acceptance run MUST show Redis current and healthy,
  and all Redis and business-service pods ready with no crash-looping container.
- **FR-021**: The acceptance run MUST include a real valid auth-api login that
  retrieves users-api seed data, plus a rejected invalid login.
- **FR-022**: The acceptance run MUST directly retrieve the matching seeded user
  from users-api with the issued token.
- **FR-023**: The acceptance run MUST list and create todos with the issued token
  and prove log-message-processor consumed the uniquely identified create event.
- **FR-024**: The acceptance run MUST load the frontend application shell and
  complete successful `/login` and authorized `/todos` requests through the
  frontend route.
- **FR-025**: Machine-readable and human-readable evidence MUST identify the
  expected Git revision, application sync/health values, pod readiness, image
  digests, HTTP status and response evidence, Redis ping, and event-consumption
  proof.
- **FR-026**: New desired state and pilot automation MUST NOT reference or require
  AWS, Azure, their registries, their identity systems, or their credentials.
- **FR-027**: Existing auth-api and platform add-on acceptance checks MUST remain
  valid after this feature extends the active platform and service sets.

### Key Entities

- **Service registration**: One discoverable service directory with a neutral
  base and destination-owned overlays; it maps a service name, ports, intrinsic
  health, configuration and secret interfaces, capacity, and immutable image.
- **Platform dependency registration**: One folder-discovered platform
  application with provider-neutral desired state, health evidence, and explicit
  dependency consumers.
- **Local image publication**: The source repository, loopback registry name,
  immutable manifest digest, and local desired-state commit that selects it.
- **Functional evidence run**: One immutable evidence set tying the expected
  desired-state revision to application state, pod state, synchronous HTTP
  behavior, Redis behavior, and asynchronous event consumption.
- **Continuity disclosure**: The explicit operational statement that Redis,
  todos-api state, and users-api H2 data are non-durable in this pilot.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Five business applications—auth-api plus the four newly onboarded
  services—report current and healthy at one exact desired-state revision in a
  single evidence run.
- **SC-002**: Redis reports current and healthy at that same revision, its pod is
  ready, and one protocol ping returns `PONG`.
- **SC-003**: Every business-service pod is ready, with its running image equal to
  the immutable digest recorded by local publication.
- **SC-004**: One valid login returns a usable access token backed by users-api's
  seeded profile, one invalid login is rejected, and direct profile lookup with
  the valid token succeeds.
- **SC-005**: One authorized todo list succeeds, one uniquely identified todo is
  created, and the corresponding event is observed by log-message-processor
  within 30 seconds.
- **SC-006**: The frontend application shell, frontend-routed login, and
  frontend-routed authorized todo list each return successful HTTP responses over
  the documented local exposure path.
- **SC-007**: The complete evidence command succeeds without direct mutation of
  any GitOps-managed Kubernetes resource and leaves its raw artifacts in a
  timestamped local evidence directory.
- **SC-008**: Static validation finds zero cloud-provider credential or endpoint
  dependencies in the new desired state and pilot workflow.
- **SC-009**: Documentation explicitly states the non-durable Redis, in-memory
  todos, and pod-local H2 limitations and does not claim production continuity.

## Assumptions

- The already-running kind pilot, loopback registry, local Git source, ArgoCD,
  External Secrets, and Kyverno are the verified starting foundation.
- The current checked-out sibling service sources and their Dockerfiles are the
  build inputs; this feature does not modify application source repositories.
- The existing auth-api credential allowlist and users-api `data.sql` seed rows
  remain the authoritative local functional-test fixtures.
- Optional Zipkin tracing remains unavailable in this feature; it is not an
  intrinsic health dependency and no tracing platform is added implicitly.
- Local exposure is operator initiated and temporary. Managed TLS ingress remains
  environment-owned under the existing contract and outside this local scope.
- The local environment runs one replica for each stateful-in-process business
  service so the pilot exposes, rather than conceals, its current continuity risk.

## Out of Scope

- Changing service business logic, credentials, API contracts, or event schemas.
- Adding durable Redis, a users database, persistent todo storage, replication,
  backup, or disaster-recovery claims.
- Adding a local ingress controller, service mesh, Zipkin, or cloud platform.
- Activating dev, staging, production, EKS, AKS, or any hosted registry.
- Replacing the existing ApplicationSet, Kustomize, External Secrets, or local
  publication mechanisms.

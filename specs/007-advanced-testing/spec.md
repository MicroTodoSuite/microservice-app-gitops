# Feature Specification: Advanced Test Gates — Contracts, Integration, E2E, Performance, DAST

**Feature Branch**: `007-advanced-testing`

**Created**: 2026-08-17

**Status**: Draft

**Input**: Author the remaining Section-9 test categories that the central CI
already assumes but does not yet run as suites: contract-first APIs
(OpenAPI/AsyncAPI + Spectral/Pact), integration against real dependencies
(Testcontainers), end-to-end user journeys, performance baselines, and dynamic
application security testing — and wire them so they become blocking gates per
the constitution, integrated into the central reusable workflow rather than
copy-pasted per repo.

## Current-State Grounding (verified on `origin/main`, 2026-08-17)

This feature does NOT repeat feature 006. What already exists on `main`:

- **Central reusable CI** (`.github/.github/workflows/ci.yml`, pinned `@0ea8003`):
  one `supply-chain` job that runs a single `test-command` + optional
  `source-audit-command`, builds one image, scans with Trivy (HIGH/CRITICAL,
  blocking), generates a Syft SBOM, and on reviewed `main` pushes to ECR via OIDC
  and signs with Cosign. Toolchains: Go 1.26.6, Node 24, Java 21, Python 3.13.
- **Unit tests exist and run** in all five services via their `test-command`:
  auth-api (`go test ./...`, Go + golang-jwt v5 + Echo v4), todos-api
  (`node --test`, Express 5), users-api (`./mvnw -B -ntp verify`, Spring Boot
  3.5 / Java 21, MockMvc), frontend (`vitest`, Vue 3 + Vite), log-message-processor
  (`pytest`, Python 3.13).
- **SonarQube** is wired but inactive (runs only when `sonar-host-url` + token are
  set; the self-hosted server is not deployed).

What is MISSING (this feature's scope):

- No contract artifacts anywhere (no OpenAPI, AsyncAPI, Spectral, or Pact).
- No integration suites against real dependencies (Testcontainers) beyond
  whatever `mvn verify` already covers for users-api.
- No end-to-end, performance, or DAST suites.
- The central workflow has no first-class way to run stack-level gates
  (e2e/perf/DAST); everything is folded into one per-service `test-command`.

## Clarifications

### Session 2026-08-17

- Q: Separate per-repo workflows or integrated into the central workflow for
  e2e/perf/DAST? → A: **Integrated** into the central reusable workflow. The
  workflow gains first-class, optional gate inputs so activation stays value-only
  and no logic is copy-pasted per repo. This changes `.github` (owned by the CI
  maintainer) and MUST be coordinated with that owner.
- Q: Relationship to feature 006 → A: 006's unit + remediation work is already on
  `main` (implemented directly, spec unmerged). 007 owns ONLY the higher Section-9
  categories (contract, integration, e2e, performance, DAST) and the central
  wiring that makes them blocking. It re-uses the current stacks on `main`; it
  does not re-migrate or re-remediate.
- Q: SonarQube activation → A: Out of scope (needs the self-hosted server, a
  platform concern). 007 ensures coverage reports are produced so the gate
  activates by value once the server exists.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Contract-first APIs verified in CI (Priority: P1)

As an API owner, each REST service and each event producer/consumer has a
versioned contract that is the source of truth, and CI rejects any implementation
that drifts from it.

**Independent Test**: Author a service's OpenAPI (and AsyncAPI where it uses the
event channel), enable the contract gate, introduce a deliberate breaking change,
confirm the gate fails, revert, confirm it passes.

**Acceptance Scenarios**:

1. **Given** a REST service, **When** its OpenAPI is authored and linted, **Then**
   Spectral passes and live responses conform to it.
2. **Given** the `log_channel` producer (todos-api) and consumer
   (log-message-processor), **When** their shared AsyncAPI is authored, **Then**
   published/consumed messages conform to the same versioned schema.
3. **Given** a conforming service, **When** a field is renamed to break the
   contract, **Then** the contract gate fails and blocks the change.

### User Story 2 - Integration against real dependencies (Priority: P1)

As a maintainer, cross-component behavior is proven against ephemeral real
dependencies, not mocks.

**Independent Test**: Run a service's integration suite against a disposable real
dependency in CI; confirm it fails when the real interaction breaks.

**Acceptance Scenarios**:

1. **Given** todos-api and log-message-processor, **When** their integration
   suites run against a disposable real Redis (Testcontainers), **Then** the
   publish/consume path over `log_channel` is exercised end to end.
2. **Given** users-api, **When** the full Spring context runs against its
   in-process datastore, **Then** the persistence path is exercised.
3. **Given** auth-api, **When** `/login` runs against a stubbed users-api HTTP
   boundary, **Then** the outbound call and token issuance are exercised.

### User Story 3 - End-to-end user journeys through the frontend (Priority: P2)

As a product owner, the primary journeys (sign in, create/list todos) are verified
through the real frontend against a running stack.

**Independent Test**: Run the e2e journeys against a docker-compose stack; confirm
they pass and a broken journey fails the gate.

**Acceptance Scenarios**:

1. **Given** the running stack, **When** the journeys execute through the frontend,
   **Then** they pass for correct behavior.
2. **Given** the e2e gate is enabled, **When** a primary journey breaks, **Then**
   the gate fails.

### User Story 4 - Performance baselines (Priority: P3)

As an operator, key endpoints have recorded throughput/latency baselines and a
defined regression fails the gate.

**Acceptance Scenarios**:

1. **Given** auth `/login` and todos CRUD, **When** the performance scenarios run,
   **Then** baselines are recorded and a defined regression fails the gate.

### User Story 5 - Dynamic application security testing (Priority: P3)

As a security owner, a running service is scanned dynamically and high-severity
findings fail the gate.

**Acceptance Scenarios**:

1. **Given** a running service, **When** the OWASP ZAP baseline scan runs, **Then**
   any high-severity finding fails the DAST gate.

### Edge Cases

- A gate is enabled before its suite exists: the run MUST fail visibly, never pass
  by running nothing.
- The `log_channel` producer and consumer schemas diverge: CI MUST fail rather
  than accept two incompatible messages.
- A stack-level gate (e2e/perf/DAST) has an unavailable dependency: it MUST
  provision a disposable stack rather than skip silently.
- A performance regression or a DAST high finding is real: it MUST block, not warn.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every REST service (auth-api, todos-api, users-api) MUST have a
  versioned OpenAPI contract that Spectral lints clean and against which live
  responses are verified in CI.
- **FR-002**: The `log_channel` event MUST have a single versioned AsyncAPI schema,
  shared and identical between the todos-api producer and the
  log-message-processor consumer, verified on both publish and consume.
- **FR-003**: Cross-service consumer/provider expectations MUST be verified with
  Pact (frontend→auth-api, frontend→todos-api, auth-api→users-api, todos-api↔
  log-message-processor).
- **FR-004**: Each service with a runtime dependency MUST have integration checks
  against a disposable real instance (Testcontainers Redis for todos-api and
  log-message-processor; full Spring context for users-api; stubbed users-api
  boundary for auth-api).
- **FR-005**: The suite MUST include end-to-end checks of the primary journeys
  through the frontend against a running stack.
- **FR-006**: The suite MUST include performance scenarios for key endpoints that
  record baselines and fail on a defined regression.
- **FR-007**: The suite MUST include a dynamic application security scan against a
  running service, failing on high-severity findings.
- **FR-008**: Each new gate MUST be integrated into the central reusable workflow
  as a first-class, optional, value-activated capability — never copy-pasted per
  repo — and MUST fail visibly if enabled without its artifacts.
- **FR-009**: A gate MUST be enabled for a service/stack only after its artifacts
  exist and pass locally; enabling without artifacts MUST fail.
- **FR-010**: This feature MUST build on the current `main` stacks and MUST NOT
  re-migrate frameworks, re-remediate dependencies, or change the GitOps
  delivery/promotion flow.
- **FR-011**: Coverage reports produced by the suites MUST be emitted so the
  SonarQube quality gate activates by value when its server exists.
- **FR-012**: All artifacts MUST be in English, delivered through short-lived
  branches and reviewed PRs, contract-first (constitution Principle 4).

### Key Entities

- **API Contract**: versioned OpenAPI (REST) or AsyncAPI (events), source of truth.
- **Contract Verification**: Spectral lint + response/message conformance + Pact.
- **Integration Suite**: checks against a disposable real dependency.
- **Stack Harness**: the docker-compose (or equivalent) that brings the services up
  for e2e/perf/DAST.
- **Gate Activation State**: per service/stack and per gate, enabled only when its
  artifacts exist (constitution: capability-gated, blocking when a harness exists).

## Success Criteria *(mandatory)*

- **SC-001**: Every REST service has an authored, linted OpenAPI; every event
  carrier shares one AsyncAPI; a deliberate drift fails CI.
- **SC-002**: Pact consumer/provider pairs verify in CI and fail on a breaking
  change.
- **SC-003**: Integration suites run against disposable real dependencies and fail
  when the real interaction breaks.
- **SC-004**: The primary journeys pass through the frontend under an active e2e
  gate, and a broken journey fails it.
- **SC-005**: Performance baselines exist and a defined regression fails the gate;
  a DAST high-severity finding fails the gate.
- **SC-006**: Every new gate is activated through the central reusable workflow by
  value only, with no per-repo logic duplication, and fails visibly when enabled
  empty.
- **SC-007**: No change to framework versions, dependency remediation already on
  main, or the GitOps delivery flow.

## Assumptions

- The central reusable workflow is the only mechanism; 007 extends it (with the CI
  maintainer's agreement) and supplies artifacts.
- Current stacks on main are kept: auth-api Go 1.26/Echo v4, todos-api Node
  24/Express 5, users-api Java 21/Spring Boot 3.5, frontend Vue 3/Vite/Vitest,
  log-message-processor Python 3.13.
- GitHub-hosted runners provide Docker for Testcontainers and the stack harness.
- Performance and DAST may run on a schedule (nightly) rather than every PR, given
  cost/time, while contract and integration run per PR.

### Dependencies

- Features 003 (reusable CI), 004 (onboarding), and the current `main` of the five
  service repos and `.github`.
- Constitution v2.0.0, Principle "Automate quality and supply-chain gates".
- The self-hosted SonarQube server (separate) for the coverage/quality gate.

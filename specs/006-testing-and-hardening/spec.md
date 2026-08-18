# Feature Specification: Service Test Suites, API Contracts, and Vulnerability Remediation

**Feature Branch**: `006-testing-and-hardening`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "Author the complete automated test suites and API contracts for the five MicroTodoSuite microservices and remediate the image vulnerabilities, so the quality/supply-chain gates that roadmap task 4 scaffolded as skippable become ACTIVE and the CI pipeline turns green end-to-end. Section-9 (Testing) and section-11 (security remediation) work; a new effort, not part of tasks 3/4."

## Clarifications

### Session 2026-08-09

- Q: Scope of this feature relative to the pipeline built in task 4 → A: This feature only ADDS test artifacts, API contracts, and dependency fixes to the service repositories and turns on the already-existing CI gates; it changes neither the reusable pipeline nor the GitOps manifests.
- Q: Which security work is included → A: CI-side only — remediating vulnerable dependencies so the image scan passes, and dynamic application security testing of the running service. Cluster-side runtime security (admission control, runtime detection, in-cluster scanning) is platform work (roadmap task 2) and is out of scope.
- Q: Contract authoring order → A: Contract-first is mandatory: the REST and event contracts are the source of truth, authored before/with the tests, and CI fails when the implementation drifts.

### Session 2026-08-16

- Q: The reusable gate jobs delivered by task 4 (spec 003) are pure `exit 1` placeholders with no test-execution step, so flipping `run-unit: true` cannot execute anything (contradicts SC-002/SC-003). How is this reconciled with FR-015 ("MUST NOT modify the reusable pipeline mechanism")? → A: FR-015 forbids **restructuring** the pipeline (jobs, inputs, promotion flow), not **completing the gate execution step that spec 003 explicitly deferred** ("a later feature will populate them and enable the corresponding gates", 003 FR-018). Resolution: each reusable gate job runs a convention-based entrypoint `ci/<gate>.sh` from the service repo; a missing script still fails visibly (enabled-but-empty, FR-012). This is a one-time, stack-agnostic change to `.github/.github/workflows/ci.yml` that adds no per-service pipeline knowledge — activation stays "author artifacts (tests + `ci/<gate>.sh`) + flip the switch", preserving the value-only-activation model (FR-014). The reusable job interface (inputs/outputs/`needs`) is unchanged.
- Q: `auth-api` uses `dep` (Gopkg.toml), not Go modules, and `github.com/dgrijalva/jwt-go` (deprecated, CVE-2020-26160); T006 assumes `go mod tidy` and a `x/crypto`-only bump. How is auth-api remediated? → A: Migrate auth-api to Go modules (mandatory for Go 1.23 + `go test ./...`), swap `dgrijalva/jwt-go` → `golang-jwt/jwt/v5` (drop-in API), and bump `golang.org/x/crypto`. This resolves the CVE at the source rather than carrying a `.trivyignore` exception for a deprecated library. T006 scope is widened accordingly.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unblock delivery: a service passes the active security and unit gates (Priority: P1)

As a service maintainer, I can make a service's image free of fixable high-severity vulnerabilities and cover its business logic with meaningful automated checks, so that the already-active security gate stops blocking it and the newly-activated unit gate proves the logic, letting the service build, sign, and promote end-to-end.

**Why this priority**: Today the pipeline is green through build, inventory, and signing but is blocked by the security scan finding real fixable vulnerabilities, so nothing promotes. Clearing that for a service is the single change that turns the whole delivery flow green and proves it works, and it establishes the template the other services follow.

**Independent Test**: Pick one service, remediate its flagged high/critical vulnerabilities and add real unit checks, enable its unit gate, and confirm a pipeline run is fully green — including the automated promotion pull request being opened — with the unit gate actually executing checks (not skipped, not empty).

**Acceptance Scenarios**:

1. **Given** a service whose image is flagged for fixable high or critical vulnerabilities, **When** its dependencies (and base image where applicable) are updated, **Then** the security scan reports zero fixable high or critical findings and no longer blocks the service.
2. **Given** a service with no meaningful automated checks, **When** unit checks for its business logic are added and the unit gate is enabled, **Then** the gate executes those checks and fails if any check fails.
3. **Given** a service that passes the active gates, **When** its trunk build completes, **Then** the delivery flow proceeds through signing and opens the automated promotion pull request.

---

### User Story 2 - Contract-first APIs verified in CI (Priority: P1)

As an API owner, I can define each service's request/response behavior and its event messages as versioned contracts that are the source of truth, and have continuous integration reject any implementation that drifts from them, so that consumers can rely on stable, documented interfaces.

**Why this priority**: The constitution mandates contract-first REST and event behavior, and no contracts exist today. Contracts are the foundation other tests and consumers depend on, so they rank alongside unblocking delivery.

**Independent Test**: Author a service's interface contract and its event contract, enable the contract gate, then introduce a deliberate implementation change that violates the contract and confirm the gate fails; revert and confirm it passes.

**Acceptance Scenarios**:

1. **Given** a REST service, **When** its interface contract is authored and the contract gate is enabled, **Then** the gate validates the contract's correctness and verifies the implementation conforms to it.
2. **Given** a service that publishes or consumes events, **When** its event contract is authored, **Then** the contract gate verifies the event messages conform to it.
3. **Given** a conforming service, **When** a change makes the implementation diverge from its contract, **Then** the contract gate fails and blocks the change.

---

### User Story 3 - Integration behavior verified against real dependencies (Priority: P2)

As a maintainer, I can verify a service against ephemeral, real instances of its runtime dependencies, so that cross-component behavior (data stores, the shared event channel) is proven, not mocked away.

**Why this priority**: Unit checks alone miss integration faults; several services fail only when talking to their real dependency. Valuable, but it builds on units and contracts being in place.

**Independent Test**: For a service with a runtime dependency, run its integration checks against a disposable real instance of that dependency in CI, enable the integration gate, and confirm it exercises the real interaction and fails when that interaction breaks.

**Acceptance Scenarios**:

1. **Given** a service that depends on a data store or the shared event channel, **When** integration checks run against a disposable real instance in CI, **Then** the checks exercise the real interaction end to end.
2. **Given** integration checks exist, **When** the integration gate is enabled, **Then** it executes them and fails when the real interaction breaks.

---

### User Story 4 - End-to-end user journeys verified through the frontend (Priority: P2)

As a product owner, I can confirm the primary user journeys work through the actual frontend against the running services, so that a release is validated the way a user experiences it.

**Why this priority**: End-to-end coverage catches wiring and cross-service faults nothing else does, but it depends on the individual services already being trustworthy.

**Independent Test**: Run the end-to-end journeys (for example, sign in and create/list items) against a running stack, enable the end-to-end gate, and confirm the journeys pass and fail meaningfully when a journey breaks.

**Acceptance Scenarios**:

1. **Given** the running stack, **When** the end-to-end journeys execute the primary flows through the frontend, **Then** they pass for correct behavior.
2. **Given** the end-to-end gate is enabled, **When** a primary journey breaks, **Then** the gate fails.

---

### User Story 5 - Performance baselines and dynamic security checks (Priority: P3)

As an operator, I can establish throughput/latency baselines for key endpoints and run dynamic security checks against a running service, so that regressions in performance or exploitable runtime weaknesses are caught before release.

**Why this priority**: Important for production readiness but the least blocking; it comes after correctness (units, contracts, integration, end-to-end) is established.

**Independent Test**: Run the performance scenarios for the key endpoints and the dynamic security scan against a running service, enable both gates, and confirm baselines are recorded and the gates fail on a defined regression or a detected high-severity issue.

**Acceptance Scenarios**:

1. **Given** key endpoints, **When** the performance scenarios run, **Then** throughput/latency baselines are recorded and the gate fails on a defined regression.
2. **Given** a running service, **When** the dynamic security scan runs, **Then** detected high-severity issues fail the gate.

---

### Edge Cases

- A flagged vulnerability has no fix available upstream; it must be handled as an accepted, documented exception rather than silently ignored or used to justify disabling the scan.
- A gate is enabled for a service before its artifacts exist; the run must fail visibly rather than report a passing gate that executed nothing.
- A contract is authored but the implementation was never conformant; CI must surface the drift rather than rubber-stamp the contract.
- A service has a dependency (event channel or data store) that is not available in the CI environment; its integration checks must provide a disposable real instance rather than being skipped silently.
- A dependency bump to clear a vulnerability breaks behavior; the service's own checks must catch the regression before promotion.
- Coverage is inflated by trivial or generated checks; coverage alone must not be accepted as evidence of meaningful verification.
- The worker service has no inbound business endpoint; its checks and any dynamic scan must target its actual interface (its metrics/health surface and its event handling) rather than a fabricated endpoint.

## Requirements *(mandatory)*

### Functional Requirements

#### Vulnerability remediation

- **FR-001**: Each service's image MUST be brought to zero fixable high or critical vulnerabilities as reported by the pipeline's security scan, by updating vulnerable dependencies and base images.
- **FR-002**: A vulnerability that has no upstream fix MUST be recorded as an explicit, justified, time-bounded exception rather than resolved by weakening or disabling the scan.
- **FR-003**: After remediation, the security gate MUST remain enforcing at high/critical for every service on subsequent changes.

#### Test suites (per service, all five)

- **FR-004**: Each service MUST have unit checks that exercise its business logic (not startup-only or trivial checks) and produce a coverage measurement.
- **FR-005**: Each service that has a runtime dependency MUST have integration checks that run against a disposable real instance of that dependency.
- **FR-006**: The suite MUST include end-to-end checks that exercise the primary user journeys through the frontend against a running stack.
- **FR-007**: The suite MUST include performance scenarios for key endpoints that record throughput/latency baselines and can fail on a defined regression.
- **FR-008**: The suite MUST include dynamic application security checks against a running service.

#### Contract-first APIs

- **FR-009**: Every REST service MUST have a versioned interface contract that is authored as the source of truth and validated for correctness in CI.
- **FR-010**: Every service that publishes or consumes events MUST have a versioned event contract validated in CI.
- **FR-011**: CI MUST verify the implementation conforms to its contracts and MUST fail when the implementation drifts.

#### Gate activation and reporting

- **FR-012**: Each quality gate (unit, integration, contract, end-to-end, performance, dynamic-security) MUST be turned on for a service only after that service's corresponding artifacts exist; enabling a gate without artifacts MUST fail visibly.
- **FR-013**: Coverage and code-quality results MUST be reported to the project's code-quality gate, and that gate MUST enforce the agreed quality threshold.
- **FR-014**: Turning a gate on MUST NOT require changing the reusable pipeline's structure — only the per-service switch and the presence of artifacts.

#### Scope guardrails

- **FR-015**: This feature MUST NOT modify the reusable pipeline mechanism, the GitOps delivery/promotion flow, or the service base/overlays delivered by roadmap tasks 3/4.
- **FR-016**: This feature MUST NOT include cluster-side runtime security (admission control, runtime detection, continuous in-cluster scanning); those remain platform work.
- **FR-017**: All artifacts MUST be in English and delivered through short-lived branches and reviewed pull requests.

### Key Entities *(include if feature involves data)*

- **Test Suite**: The set of automated checks for one service, organized by type (unit, integration, contract, end-to-end, performance, dynamic-security), each mapped to the pipeline gate that runs it.
- **API Contract**: The versioned, authoritative definition of a service's request/response behavior (REST) or event messages (pub/sub), against which the implementation is verified.
- **Coverage Measurement**: The recorded proportion of business logic exercised by a service's checks, reported to the code-quality gate.
- **Vulnerability Finding**: A reported issue in a service image, with severity, fix availability, and either a remediation (dependency/base-image update) or a justified documented exception.
- **Gate Activation State**: Per service and per gate, whether the gate is enabled, which is allowed only once the corresponding artifacts exist.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every service reports zero fixable high or critical vulnerabilities in the security gate; any remaining finding is an upstream-unfixable, documented exception.
- **SC-002**: At least one service reaches a fully green pipeline run — including the automated promotion pull request — with its security and unit gates active and actually executing checks.
- **SC-003**: All five services have meaningful unit checks with the unit gate active and a coverage measurement reported to the code-quality gate that meets the agreed threshold.
- **SC-004**: Every REST service has an authored interface contract and every event-carrying service has an authored event contract, with the contract gate active and proven to fail on a deliberate drift.
- **SC-005**: Every service with a runtime dependency has integration checks running against a disposable real instance, with the integration gate active.
- **SC-006**: The primary user journeys pass through the frontend under an active end-to-end gate, and the gate fails when a journey is broken.
- **SC-007**: Performance baselines exist for key endpoints and a dynamic security scan runs against a running service, both under active gates.
- **SC-008**: For every service and every gate, no gate is enabled without its artifacts present; a deliberate "enabled-but-empty" check fails visibly.
- **SC-009**: Zero changes are made to the reusable pipeline mechanism, the GitOps delivery flow, or the service base/overlays as part of this feature.

## Assumptions

- The reusable CI pipeline and its per-gate switches (delivered by roadmap task 4) exist in the service repositories and are the only mechanism used to run these gates; this feature supplies artifacts and flips switches, nothing more.
- The five services keep their current stacks and runtime dependencies (a Go auth service calling the user service for login only; a Node task service and a Python worker using the shared event channel; a Java user service with an in-process datastore; a Vue frontend proxying to the APIs); tests are authored in each service's native toolchain.
- The code-quality gate is a self-hosted server (team decision, both profiles); reporting coverage/quality to it requires that server to be reachable, which is activated separately — until then that specific gate stays visibly skipped while the other gates proceed.
- A meaningful coverage threshold is assumed at 70% of business-logic lines per service as a starting target, adjustable by the team during planning.
- Contracts use the standard formats for REST and for event-driven messaging; consumer/provider verification uses the standard contract-testing approach.
- Delivery is incremental: one service (the Go auth service) is completed first as the template — vulnerability fix, unit checks, and its interface contract — to prove a green end-to-end run, then the pattern is replicated across the other services and the heavier gates (end-to-end, performance, dynamic-security) are added last.

### Dependencies

- Roadmap task 4 (reusable CI with skippable gates) and task 3 (GitOps delivery), already in main.
- The project constitution, especially the principles on contract-first specifications, quality-and-supply-chain gates, and immutable promotion.
- The self-hosted code-quality server (scaffolded separately) for the coverage/quality gate.
- Upstream availability of fixed dependency/base-image versions for the flagged vulnerabilities.
- Out of band: the real cluster/registry (roadmap tasks 1/2) is needed to observe a promoted image actually deploy, but is not required to make the gates green in CI.

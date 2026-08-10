# Phase 0 Research: Testing, Contracts, and Vulnerability Remediation

All decisions ground in the verified stacks. No open `NEEDS CLARIFICATION`; the three product decisions were fixed in the spec's Clarifications, and the one tunable (coverage threshold) is set here.

## D1 — Unit test tooling per stack

- **Decision**: auth-api → `go test` + `testify` (coverage `go test -coverprofile`, `-covermode=atomic`); todos-api → **Jest** + `supertest` (lcov); users-api → **JUnit 5** + Spring Boot Test + MockMvc (JaCoCo XML); frontend → **Jest** + Vue Test Utils (Vue 2 preset, lcov); log-message-processor → **pytest** + `coverage.py` (Cobertura XML).
- **Rationale**: Each is the de-facto standard for its stack, integrates with the reusable `run-unit` gate, and emits a coverage format SonarQube ingests.
- **Alternatives**: Go stdlib-only (no testify) — rejected for ergonomics; Mocha for Node — rejected, Jest gives coverage out of the box.

## D2 — Coverage threshold

- **Decision**: **70%** of business-logic lines per service as the initial SonarQube quality-gate threshold; exclude generated/bootstrap code from the denominator.
- **Rationale**: Meaningful without being punitive on legacy demo code; team-tunable later.
- **Alternatives**: 80%+ — rejected initially given zero starting coverage; 0/advisory — rejected, defeats the gate.

## D3 — Integration testing

- **Decision**: **Testcontainers** for a disposable real **Redis** in todos-api (Node) and log-message-processor (Python); users-api runs full Spring context integration (its H2 is in-process, so a booted context + MockMvc is the real datastore path); auth-api integration stubs users-api at the HTTP boundary (its only dependency, used by `/login`).
- **Rationale**: Exercises the real event channel/datastore instead of mocks (FR-005) with no external infra.
- **Alternatives**: `fakeredis`/embedded mocks — rejected for integration (fine for unit only); shared CI Redis service container — acceptable fallback but Testcontainers is more hermetic.

## D4 — Contract-first: REST + events

- **Decision**: **OpenAPI 3.1** for the REST services (auth-api `/login` `/version`, todos-api `/todos` CRUD, users-api `/users`); **AsyncAPI 3** for the Redis `log_channel` (todos-api publishes, log-message-processor consumes). Contracts live in each repo under `contracts/`.
- **Rationale**: Standard formats; satisfies constitution P4 (contract-first) and the `run-contract` gate.
- **Alternatives**: Hand-written JSON schemas only — rejected, no lint/tooling ecosystem.

## D5 — Contract verification tooling

- **Decision**: **Spectral** to lint OpenAPI/AsyncAPI; **schema conformance** of live responses/messages against the contract (e.g. Schemathesis for OpenAPI, an AsyncAPI message validator for events); **Pact** for consumer/provider pairs — auth-api→users-api and frontend→(auth-api,todos-api) for REST, todos-api→log-message-processor over the event contract.
- **Rationale**: Lint catches malformed contracts; conformance catches implementation drift (FR-011); Pact catches cross-service breaking changes.
- **Alternatives**: Dredd — viable REST alternative to Schemathesis; kept as fallback. Pact optional for the first iteration if time-boxed (lint+conformance already fail on drift).

## D6 — Vulnerability remediation approach

- **Decision**: Fix at the dependency level first: auth-api `go get golang.org/x/crypto@latest && go mod tidy` (clears the 33H/2C set); todos-api/frontend `npm audit fix` + targeted bumps; users-api Maven version bumps; log-message-processor `pip` bumps in `requirements.txt`. Bump base images only when the finding is OS-level. Re-scan with `trivy fs`/`trivy image` locally before pushing. Any finding with no upstream fix → a documented, time-bounded entry in a `.trivyignore` with justification (never lower the gate severity or disable it).
- **Rationale**: FR-001/FR-002/FR-003; keeps the gate enforcing at HIGH/CRITICAL.
- **Alternatives**: `ignore-unfixed:true` already set (so only fixable ones block) — correct; broad `.trivyignore` — rejected (only per-CVE justified exceptions).

## D7 — E2E

- **Decision**: **Cypress** in the frontend repo, run against a **docker-compose** stack (frontend + auth + todos + users + redis) spun up in CI; cover login and create/list todos.
- **Rationale**: Frontend is the natural home; docker-compose gives a real running stack without a cluster.
- **Alternatives**: Playwright — equivalent; Cypress chosen per plan §9. Running against a kind cluster — heavier, unnecessary for e2e.

## D8 — Performance

- **Decision**: **Locust** scenarios for auth `/login` and todos CRUD, recording throughput/latency baselines; the `run-perf` gate fails on a defined regression vs the committed baseline.
- **Rationale**: FR-007; matches plan §9.
- **Alternatives**: k6 — equivalent; Locust chosen per plan.

## D9 — DAST

- **Decision**: **OWASP ZAP baseline** scan against a running service (per REST service; the worker's `/metrics` surface); high-severity alerts fail the `run-dast` gate.
- **Rationale**: FR-008; baseline scan is CI-friendly (no full active-attack time cost initially).
- **Alternatives**: ZAP full scan — slower; reserve for scheduled runs, not per-PR.

## D10 — Coverage/quality reporting to SonarQube

- **Decision**: Each unit gate emits its native coverage report; the `quality` job feeds them to the **self-hosted SonarQube** via the scanner already wired in `ci.yml`. Until the SonarQube server is deployed, `sonar-host-url` stays empty so the quality gate is visibly skipped; coverage is still produced and archived.
- **Rationale**: FR-013; consistent with the self-hosted decision (feature 003) and the value-only activation.
- **Alternatives**: SonarCloud — rejected by team decision.

## D11 — Gate activation discipline

- **Decision**: Turn on a service's `run-<gate>` in its caller **only after** that gate's artifacts exist and pass locally. Enabling early must fail visibly (the reusable gate already fails when enabled-but-empty). Order per service: unit → contract → integration → (e2e/perf/dast at stack level).
- **Rationale**: FR-012; avoids green-but-empty gates.

## D12 — Incremental sequence

- **Decision**: **auth-api is the template**: (1) bump crypto → Trivy green, (2) `go test` + coverage → `run-unit`, (3) OpenAPI + conformance → `run-contract`; prove a green pipeline + promotion PR. Then todos-api, users-api, log-message-processor (units+contracts+integration), then frontend + the stack-level e2e/perf/dast last.
- **Rationale**: Fastest path to a proven green end-to-end run; de-risks tooling once before replicating.

## D13 — Per-service dependency & scope map (verified)

| Service | Stack | Unit | Integration dep | Contracts | Notes |
| --- | --- | --- | --- | --- | --- |
| auth-api | Go/Echo | go test | stub users-api | OpenAPI | crypto CVEs to fix first; JWT sign/verify logic |
| todos-api | Node/Express | Jest | Redis (Testcontainers) | OpenAPI + AsyncAPI(pub) | publishes log_channel events |
| users-api | Java 8/Spring | JUnit+MockMvc | Spring context (H2) | OpenAPI | Java 8 limits some bumps |
| frontend | Vue 2 | Jest+VTU | — | — (consumer in Pact) | owns Cypress e2e; node-sass bump risk |
| log-message-processor | Python | pytest | Redis (Testcontainers) | AsyncAPI(consumer) | worker; DAST targets /metrics |

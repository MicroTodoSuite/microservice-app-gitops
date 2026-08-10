---
description: "Task list for Service Test Suites, API Contracts, and Vulnerability Remediation"
---

# Tasks: Service Test Suites, API Contracts, and Vulnerability Remediation

**Input**: Design documents from `/specs/006-testing-and-hardening/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: This feature IS the test-authoring work — the "test tasks" here ARE the deliverables (unit/integration/contract/e2e/perf/DAST suites), plus vulnerability remediation and gate activation.

**Multi-repo note**: All deliverables live in the five SERVICE repos. Each task tags its repo:
- `[svc:auth-api]` (Go), `[svc:todos-api]` (Node), `[svc:users-api]` (Java), `[svc:frontend]` (Vue), `[svc:log-message-processor]` (Python)
- The reusable pipeline (`.github`), GitOps manifests, and service base/overlays are NOT changed (FR-015/FR-016); only each service's `run-<gate>` switch flips.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Different repos/files, no unmet dependency → parallelizable
- **[Story]**: US1–US5 from spec.md; Setup/Foundational/Polish carry no story label

---

## Phase 1: Setup (shared conventions)

- [ ] T001 [P] Add `sonar-project.properties` to each of the 5 service repos (project key, sources, per-stack coverage report path, coverage gate 70% — research D2/D10)
- [ ] T002 [P] Define the vulnerability-exception format (CVE + justification + expiry) and add a documented, empty `.trivyignore` to each of the 5 repos (FR-002)
- [ ] T003 [P] Record the per-service testing/gate conventions in each repo `docs/testing.md` (contracts/ layout, gate-activation rule from `contracts/gate-activation-contract.md`)

---

## Phase 2: Foundational (blocking prerequisites)

- [ ] T004 Author the canonical `log_channel` AsyncAPI 3 message schema shared by publisher and consumer, committed to `[svc:todos-api]/contracts/asyncapi.yaml` and mirrored/referenced by `[svc:log-message-processor]/contracts/asyncapi.yaml` (must be identical — see `contracts/api-contract-inventory.md`)
- [ ] T005 [P] Add the e2e docker-compose stack (frontend + auth-api + todos-api + users-api + redis) in `[svc:frontend]/e2e/docker-compose.yml` for later e2e/DAST use

**Checkpoint**: Shared conventions and the cross-service event schema exist; stories can start.

---

## Phase 3: User Story 1 - Unblock delivery: security + unit gates (Priority: P1) 🎯 MVP

**Goal**: Zero fixable HIGH/CRITICAL per image + meaningful unit coverage; activate `run-unit`; prove a green end-to-end run incl. the promotion PR.

**Independent Test**: A service's image-scan is clean and its `run-unit` gate executes real tests; auth-api additionally reaches a fully green pipeline that opens the automated promotion PR (SC-001/SC-002/SC-003).

### Template first — auth-api

- [ ] T006 [US1] [svc:auth-api] Bump `golang.org/x/crypto` (+ `go mod tidy`); confirm `trivy fs --severity HIGH,CRITICAL .` reports 0 fixable (clears the 33H/2C set)
- [ ] T007 [US1] [svc:auth-api] Write `go test`+testify unit tests for the JWT sign/verify, login handler, and `/version` logic with `-coverprofile`; reach ≥70%
- [ ] T008 [US1] [svc:auth-api] Set `run-unit: true` in `.github/workflows/ci.yml`; merge and confirm a fully green pipeline including `release` + `promote-dev` opening the gitops promotion PR (MVP proof)

### Replicate across the other four [P]

- [ ] T009 [P] [US1] [svc:todos-api] Bump vulnerable npm deps (`npm audit fix` + targeted); `trivy fs` 0 fixable HIGH/CRITICAL
- [ ] T010 [P] [US1] [svc:todos-api] Jest+supertest unit tests for the todo controller/routes with lcov coverage ≥70%; set `run-unit: true`
- [ ] T011 [P] [US1] [svc:users-api] Bump Maven deps to clear fixable CVEs (within Java 8 limits; document unfixable as `.trivyignore` exceptions); trivy clean
- [ ] T012 [P] [US1] [svc:users-api] JUnit 5 + MockMvc unit tests for the user endpoints/JWT filter with JaCoCo ≥70%; set `run-unit: true`
- [ ] T013 [P] [US1] [svc:frontend] Bump npm deps; record upstream-unfixable Vue2/node-sass findings as documented `.trivyignore` exceptions; trivy clean of fixable
- [ ] T014 [P] [US1] [svc:frontend] Jest + Vue Test Utils unit tests for key components/store with lcov ≥70%; set `run-unit: true`
- [ ] T015 [P] [US1] [svc:log-message-processor] Bump `requirements.txt` deps; `trivy fs` 0 fixable HIGH/CRITICAL
- [ ] T016 [P] [US1] [svc:log-message-processor] pytest unit tests for the message handling with coverage.py XML ≥70%; set `run-unit: true`
- [ ] T017 [US1] Verify across all 5: image-scan green and `run-unit` active and actually executing (not skipped/empty) — SC-002/SC-003

**Checkpoint**: Every image is clean; every service has an active, real unit gate; auth-api promotes green.

---

## Phase 4: User Story 2 - Contract-first APIs verified in CI (Priority: P1)

**Goal**: OpenAPI (REST) + AsyncAPI (events) authored as source of truth; `run-contract` active; drift fails.

**Independent Test**: Contracts lint clean, implementation conforms, and a deliberate breaking change fails the gate (SC-004).

- [ ] T018 [US2] [svc:auth-api] Author `contracts/openapi.yaml` (`/login`, `/version`, `/metrics`); Spectral lint + response conformance; set `run-contract: true`
- [ ] T019 [P] [US2] [svc:todos-api] Author `contracts/openapi.yaml` (`/todos` CRUD, `/metrics`) + wire the T004 AsyncAPI publisher; lint + conformance; set `run-contract: true`
- [ ] T020 [P] [US2] [svc:users-api] Author `contracts/openapi.yaml` (`/users`, `/users/{username}`, `/actuator/health`); lint + conformance; set `run-contract: true`
- [ ] T021 [P] [US2] [svc:log-message-processor] Wire the T004 AsyncAPI consumer + message validation against `log_channel`; set `run-contract: true`
- [ ] T022 [P] [US2] [svc:frontend] Author Pact consumer contracts against auth-api and todos-api
- [ ] T023 [US2] Add Pact provider verification (auth-api←frontend; users-api←auth-api; todos-api←frontend) to each provider's contract gate
- [ ] T024 [US2] Verify a deliberate contract-breaking change turns `run-contract` red, then revert (SC-004)

**Checkpoint**: Every REST/event interface has an authoritative contract enforced in CI.

---

## Phase 5: User Story 3 - Integration against real dependencies (Priority: P2)

**Goal**: Integration checks against ephemeral real dependencies; `run-integration` active.

**Independent Test**: The real interaction is exercised in CI and fails when broken (SC-005).

- [ ] T025 [P] [US3] [svc:todos-api] Testcontainers Redis integration tests for the publish-to-`log_channel` path; set `run-integration: true`
- [ ] T026 [P] [US3] [svc:log-message-processor] Testcontainers Redis integration tests for the subscribe/consume path; set `run-integration: true`
- [ ] T027 [P] [US3] [svc:users-api] Full Spring context + MockMvc integration against the in-process H2 datastore; set `run-integration: true`
- [ ] T028 [US3] [svc:auth-api] Integration tests for `/login` against a stubbed users-api HTTP boundary; set `run-integration: true`
- [ ] T029 [US3] Verify each integration gate exercises the real dependency and fails when the interaction breaks (SC-005)

**Checkpoint**: Cross-component behavior is proven against real dependencies.

---

## Phase 6: User Story 4 - End-to-end user journeys (Priority: P2)

**Goal**: Cypress journeys through the frontend against the running stack; `run-e2e` active.

**Independent Test**: Primary journeys pass and a broken journey fails (SC-006).

- [ ] T030 [US4] [svc:frontend] Cypress specs for login and create/list todos against the T005 docker-compose stack in `[svc:frontend]/e2e/`
- [ ] T031 [US4] [svc:frontend] Set `run-e2e: true`; confirm journeys pass and a deliberately broken journey fails the gate (SC-006)

**Checkpoint**: The primary user journeys are verified through the real frontend.

---

## Phase 7: User Story 5 - Performance baselines and DAST (Priority: P3)

**Goal**: Locust baselines + OWASP ZAP baseline scans; `run-perf` and `run-dast` active.

**Independent Test**: A defined perf regression and any ZAP high-severity finding fail their gates (SC-007).

- [ ] T032 [P] [US5] [svc:auth-api] Locust `/login` scenario + committed baseline in `perf/`; set `run-perf: true`
- [ ] T033 [P] [US5] [svc:todos-api] Locust todos-CRUD scenario + baseline in `perf/`; set `run-perf: true`
- [ ] T034 [P] [US5] [svc:*] OWASP ZAP baseline config per REST service (and the worker's `/metrics`) in `zap/`; set `run-dast: true`
- [ ] T035 [US5] Verify a defined perf regression and a ZAP high-severity finding fail their gates (SC-007)

**Checkpoint**: Performance and dynamic-security regressions are caught pre-release.

---

## Phase 8: Polish & Cross-Cutting

- [ ] T036 [P] Confirm every service's coverage feeds the self-hosted SonarQube quality gate and the 70% threshold is enforced once the server is up (FR-013; stays visibly skipped until then)
- [ ] T037 [P] Verify SC-009: no changes to the reusable pipeline, GitOps flow, or service base/overlays; all artifacts in English
- [ ] T038 Verify SC-008 once per service (enabling a gate before its artifacts fails visibly), then run the full `quickstart.md`

---

## Dependencies & Execution Order

```text
Phase 1 Setup  ->  Phase 2 Foundational (T004 shared event schema, T005 e2e stack)
  -> US1 (P1, MVP): vuln + unit  [auth-api template T006-T008, then T009-T016 in parallel]
     -> US2 (P1): contracts       [needs T004 for the event contract]
     -> US3 (P2): integration     [builds on unit + Testcontainers]
     -> US4 (P2): e2e             [needs T005 stack + services trustworthy]
     -> US5 (P3): perf + dast     [needs a running stack; last]
        -> Phase 8 Polish
```

- **US1 auth-api (T006–T008) is the MVP**: proves the whole delivery flow green including promotion. Do it first, alone, before fanning out.
- US2 depends on T004 (shared `log_channel` schema).
- US4/US5 depend on T005 (docker-compose stack).

## Parallel Opportunities

- Setup: T001–T003 in parallel (different repos).
- US1: after auth-api template (T006–T008), T009–T016 run in parallel across the other four repos.
- US2: T019–T022 in parallel; T018 (auth-api) leads as the template.
- US3: T025–T027 in parallel.
- US5: T032–T034 in parallel.

## Implementation Strategy

### MVP (US1, auth-api)
1. T001–T005 (setup + foundational).
2. T006 (vuln fix) → T007 (unit) → T008 (enable + green promotion PR).
3. **Stop and validate**: a fully green pipeline that opens the gitops promotion PR — proves tests + delivery end to end.

### Incremental delivery
1. Foundation → US1 auth-api (MVP) → US1 the other four (units + vuln clean).
2. + US2 (contracts) → + US3 (integration) → + US4 (e2e) → + US5 (perf/DAST).
3. Each phase leaves every enabled gate green and real.

## Notes

- `[P]` = different repos/files; a service's own gate order is serial (unit → contract → integration).
- Never enable a gate without its artifacts (FR-012); never soften image-scan to pass (FR-003).
- Unfixable CVEs → documented, time-bounded `.trivyignore` exceptions only (FR-002).
- SonarQube quality gate stays visibly skipped until the self-hosted server (feature 003 scaffold) is deployed.

---
description: "Task list for Advanced Test Gates (contracts, integration, e2e, performance, DAST)"
---

# Tasks: Advanced Test Gates (007)

**Input**: design documents from `/specs/007-advanced-testing/`

**Prerequisites**: spec.md, plan.md

**Grounding**: builds on `origin/main` of each repo (feature 006's unit + remediation
is already there). Fetch and diff `origin/main` before touching any repo.

**Multi-repo tags**: `[svc:auth-api]` (Go), `[svc:todos-api]` (Node),
`[svc:users-api]` (Java), `[svc:frontend]` (Vue), `[svc:log-message-processor]` (Py),
`[.github]` (central reusable workflow, CI-maintainer owned).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: different repos/files, parallelizable.

---

## Phase 0: Central workflow interface (coordinate with CI maintainer)

- [ ] T001 [.github] Propose optional value-activated gate inputs on the reusable
  `ci.yml` for per-service gates (`contract-command`, `integration-command`) that
  run as guarded steps in `supply-chain`, failing visibly when set but empty.
- [ ] T002 [.github] Add a reusable `stack-tests.yml` (checkout → docker-compose up
  → run provided `e2e/perf/dast` command → teardown) for stack-level gates, invoked
  by a thin caller in the owning repo; per-PR for e2e, nightly `schedule` for perf/DAST.
- [ ] T003 Open a `.github` PR for T001/T002 and get the maintainer's review/merge
  BEFORE flipping any service gate that depends on it.

## Phase 1: Foundational (shared contract source)

- [ ] T004 Author the canonical `log_channel` AsyncAPI 3 schema; commit to
  `[svc:todos-api]/contracts/asyncapi.yaml` and mirror byte-identical in
  `[svc:log-message-processor]/contracts/asyncapi.yaml`.
- [ ] T005 [P] [svc:frontend] Add the e2e stack `compose.yaml` (frontend + auth +
  todos + users + redis) for later e2e/perf/DAST use.
- [ ] T006 [P] Add a shared Spectral ruleset reference and a `contracts/` convention
  note in each REST repo's `docs/`.

## Phase 2: US1 - Contract-first (P1)

- [ ] T007 [P] [svc:auth-api] Author `contracts/openapi.yaml` (`/login`,`/version`,
  `/metrics`); Spectral lint + response conformance; wire into the contract gate.
- [ ] T008 [P] [svc:todos-api] Author `contracts/openapi.yaml` (`/todos` CRUD,
  `/metrics`) + the T004 AsyncAPI producer binding; lint + conformance; wire gate.
- [ ] T009 [P] [svc:users-api] Author `contracts/openapi.yaml` (`/users`,
  `/users/{username}`, actuator); lint + conformance; wire gate.
- [ ] T010 [P] [svc:log-message-processor] Bind the T004 AsyncAPI consumer +
  message validation against `log_channel`; wire gate.
- [ ] T011 [P] [svc:frontend] Author Pact consumer contracts against auth-api and
  todos-api.
- [ ] T012 Add Pact provider verification (auth-api←frontend; users-api←auth-api;
  todos-api←frontend; log-message-processor↔todos-api over AsyncAPI).
- [ ] T013 Verify a deliberate contract-breaking change turns the contract gate red,
  then revert (SC-001/SC-002).

## Phase 3: US2 - Integration against real dependencies (P1)

- [ ] T014 [P] [svc:todos-api] Testcontainers Redis integration for the
  publish-to-`log_channel` path; wire the integration gate.
- [ ] T015 [P] [svc:log-message-processor] testcontainers-python Redis integration
  for the subscribe/consume path; wire the integration gate.
- [ ] T016 [P] [svc:users-api] `@SpringBootTest` full context + MockMvc against H2;
  ensure it runs in `mvn verify`.
- [ ] T017 [P] [svc:auth-api] `/login` integration against a stubbed users-api HTTP
  boundary.
- [ ] T018 Verify each integration gate exercises the real dependency and fails when
  the interaction breaks (SC-003).

## Phase 4: US3 - End-to-end (P2)

- [ ] T019 [svc:frontend] Playwright specs for sign-in and create/list todos against
  the T005 compose stack.
- [ ] T020 [svc:frontend] Thin caller invoking the central `stack-tests.yml` with the
  e2e command on PR; confirm journeys pass and a broken journey fails (SC-004).

## Phase 5: US4/US5 - Performance + DAST (P3)

- [ ] T021 [P] [svc:auth-api] Locust `/login` scenario + committed baseline.
- [ ] T022 [P] [svc:todos-api] Locust todos-CRUD scenario + baseline.
- [ ] T023 [P] OWASP ZAP baseline config per REST service (+ worker `/metrics`).
- [ ] T024 Nightly caller invoking `stack-tests.yml` for perf + DAST; verify a
  defined perf regression and a ZAP high finding fail their gates (SC-005).

## Phase 6: Polish & Cross-cutting

- [ ] T025 [P] Ensure each suite emits a coverage report consumed by SonarQube once
  its server exists (FR-011).
- [ ] T026 Verify SC-006 (every gate value-activated through the central workflow,
  no per-repo duplication) and SC-007 (no framework/remediation/GitOps changes).
- [ ] T027 Verify SC-009-style "enabled-but-empty fails visibly" once per gate.

## Dependencies & order

```text
Phase 0 (.github interface) ── blocks ──> flipping any gate that uses it
Phase 1 (T004 AsyncAPI, T005 compose) ── blocks ──> US1 event contract, US3/US4/US5
  US1 contract (P1) ─> US2 integration (P1) ─> US3 e2e (P2) ─> US4/US5 perf+DAST (P3)
                                                             ─> Phase 6 polish
```

## Notes

- Fetch `origin/main` and diff before each repo change (do not repeat 006's stale-base
  duplication).
- Contract lint is verifiable without Docker; integration/e2e/perf/DAST need Docker.
- `.github` changes require the CI maintainer's review; propose the interface, do not
  rewrite unilaterally.
- Never enable a gate without its artifacts; never soften Trivy/DAST to pass.

# Implementation Plan: Advanced Test Gates (007)

**Branch**: `007-advanced-testing` | **Date**: 2026-08-17 | **Spec**: [spec.md](./spec.md)

## Summary

Author the Section-9 test categories missing on `main` — contract, integration,
end-to-end, performance, DAST — for the five services on their current stacks, and
integrate them as first-class, value-activated gates in the central reusable
workflow. Contract and integration run per PR through each service's own toolchain;
end-to-end, performance, and DAST are stack-level and run against a docker-compose
harness, wired into the central workflow via new optional inputs/jobs (coordinated
with the CI maintainer). No framework re-migration, no dependency re-remediation,
no change to GitOps delivery.

## Verified stacks (from `origin/main`)

| Service | Runtime | Unit runner on main | Runtime dep |
| --- | --- | --- | --- |
| auth-api | Go 1.26.6, Echo v4, golang-jwt v5 | `go test ./...` | users-api (HTTP) |
| todos-api | Node 24, Express 5 | `node --test` | Redis (`log_channel` pub), users JWT |
| users-api | Java 21, Spring Boot 3.5.16, MockMvc | `./mvnw -B -ntp verify` | in-process H2 |
| frontend | Vue 3, Vite, Vitest | `vitest run` | auth-api, todos-api (proxy) |
| log-message-processor | Python 3.13 | `pytest` | Redis (`log_channel` sub) |

## Per-gate tooling (on the current stacks)

- **Contract (US1)**:
  - OpenAPI 3.1 in `contracts/openapi.yaml` for auth-api (`/login`,`/version`,
    `/metrics`), todos-api (`/todos` CRUD,`/metrics`), users-api (`/users`,
    `/users/{username}`, actuator). Lint with **Spectral** (Node CLI).
  - AsyncAPI 3 in `contracts/asyncapi.yaml` for `log_channel`, identical in
    todos-api (producer) and log-message-processor (consumer).
  - Conformance: Schemathesis (Python) or an OpenAPI response validator per stack;
    AsyncAPI message validation on both ends.
  - **Pact**: consumer tests in frontend (against auth/todos) and auth-api (against
    users); provider verification on each provider; todos↔log over the event
    contract. Pact broker optional; file-based pacts acceptable initially.
- **Integration (US2)**:
  - todos-api: **Testcontainers for Node** Redis; assert a create/delete publishes
    the correct `log_channel` message.
  - log-message-processor: **testcontainers-python** Redis; assert subscribe/consume
    of a published message.
  - users-api: `@SpringBootTest` full context + MockMvc against H2 (already partly
    covered by `mvn verify`; extend if needed).
  - auth-api: `/login` against a stubbed users-api HTTP server (`httptest`).
- **E2E (US3)**: **Playwright** (fits Vue 3 + Vite), specs for sign-in and
  create/list todos, run against a `docker-compose` stack (frontend + auth + todos
  + users + redis). Owned by the frontend repo.
- **Performance (US4)**: **Locust** scenarios for auth `/login` and todos CRUD with
  committed baselines; fail on a defined regression.
- **DAST (US5)**: **OWASP ZAP baseline** against the running REST services (and the
  worker's `/metrics`); high-severity findings fail.

## Central-workflow integration (the FR-008 decision)

The reusable `ci.yml` currently runs a single `test-command`. Extend it (with the
CI maintainer) so gates are value-activated, not per-repo copy:

1. **Contract + integration** run inside a service's own toolchain → fold into each
   caller's `test-command` (or add optional `contract-command` / `integration-command`
   inputs that run as guarded steps in `supply-chain`). No stack needed.
2. **E2E / performance / DAST** are stack-level → add to the central `.github` a
   reusable **`stack-tests.yml`** (or optional `e2e-command`/`perf-command`/
   `dast-command` inputs on a new job) that:
   - checks out the caller, brings up the docker-compose stack, runs the provided
     command, tears down;
   - is invoked by a thin caller in the owning repo (frontend for e2e; a designated
     repo for perf/DAST);
   - runs per PR for e2e, on a nightly `schedule` for perf/DAST.
3. Every gate fails visibly when enabled without its artifact (FR-008/FR-009),
   mirroring the existing fail-closed philosophy.

**Coordination**: changes to `.github` are owned by the CI maintainer (Esteban);
this plan proposes the interface and a PR, not a unilateral rewrite.

## Constitution Check (v2.0.0)

| Principle | Verdict | How this feature complies |
| --- | --- | --- |
| 3. Stable trunk | PASS | short-lived branches + reviewed PRs |
| 4. Authoritative specs (contract-first) | PASS — delivered here | OpenAPI/AsyncAPI authored as source of truth, drift fails CI |
| 6. Build-once, immutable promotion | PASS | unchanged; gates run before the existing publish/sign steps |
| 8. Quality & supply-chain gates | PASS — core | turns capability-gated categories into runnable, blocking gates |
| 10. Least privilege | PASS | no new cloud writes; DAST/perf run against ephemeral stacks |

## Constraints

- Docker required for integration, e2e, perf, DAST (Testcontainers + compose).
- Local verification: contract lint runs without Docker; integration/e2e/perf/DAST
  require Docker Desktop running.
- No change to framework versions, existing remediation, base/overlays, or GitOps.

## Complexity Tracking

| Risk | Why | Mitigation |
| --- | --- | --- |
| Stack-level gates in a per-service reusable workflow | e2e/perf/DAST need the whole stack, not one service | separate `stack-tests.yml` reusable + thin caller in the owning repo, still central |
| Pact broker infra | full Pact needs a broker | start file-based; add a broker later without changing suites |
| Perf/DAST time cost per PR | slow gates block iteration | schedule nightly; keep contract/integration per PR |
| `.github` is maintainer-owned | central change needs agreement | propose interface + PR; do not rewrite unilaterally |

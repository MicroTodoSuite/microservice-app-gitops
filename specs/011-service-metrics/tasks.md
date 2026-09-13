---

description: "Task list for service metrics through OpenTelemetry"
---

# Tasks: Service Metrics Through OpenTelemetry

**Input**: Design documents from `specs/011-service-metrics/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/preserved-series.md`, `contracts/business-metrics.md`,
`quickstart.md`

**Tests**: Required. FR-012 requires tests committed failing before each
implementation, and FR-013 requires live evidence for acceptance.

**Organization**: Tasks are grouped by user story. Tasks marked
`[in <repo> repo]` land in that repository's own pull request; every other
path is in `microservice-app-gitops`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: The user story the task belongs to (US1, US2)

---

## Phase 1: User Story 1 - Keep every golden signal working through the instrumentation change (Priority: P1) MVP

**Goal**: `auth-api`, `todos-api`, and `log-message-processor` record through
OpenTelemetry and expose exactly the preserved series.

**Independent Test**: Each service's metrics test renders `/metrics` and
matches `contracts/preserved-series.md`.

### Tests for User Story 1

> Write these tests first and commit them failing before T004 to T006.

- [ ] T001 [P] [US1] [in `todos-api` repo] Add failing tests in
  `test/metrics.test.js` that render `/metrics` and assert
  `todo_api_requests_total` with `method` and `status`, and
  `todo_api_request_duration_seconds_bucket`, `_sum`, and `_count` with
  `method` and the boundaries in `contracts/preserved-series.md`; that no
  `otel_scope_` label, `target_info`, or `todos_api_` runtime family appears;
  that `package.json` does not list `prom-client`; and that no source file
  requires `prom-client`
- [ ] T002 [P] [US1] [in `auth-api` repo] Add failing tests in
  `metrics_test.go` that render `/metrics` through the operational routes and
  assert `auth_api_requests_total` with `method` and `status`, and
  `auth_api_request_duration_seconds_bucket`, `_sum`, and `_count` with
  `method` and the contract boundaries; that no `otel_scope_` label,
  `target_info`, `go_*`, or `process_*` family appears; and that no non-test
  source registers a metric through `client_golang`'s `prometheus.New*`
  constructors
- [ ] T003 [P] [US1] [in `log-message-processor` repo] Add failing tests in
  `tests/test_metrics.py` that render the metrics endpoint and assert
  `log_messages_processed_total`, `log_messages_failed_total`, and
  `log_message_processing_duration_seconds_bucket`, `_sum`, and `_count` with
  the contract boundaries; that no `otel_scope_` label, `target_info`,
  `process_*`, or `python_*` family appears; and that `main.py` creates no
  `prometheus_client` `Counter` or `Histogram`

### Implementation for User Story 1

- [ ] T004 [US1] [in `todos-api` repo] Add `metrics.js` (a `MeterProvider`
  with `@opentelemetry/exporter-prometheus` 0.222.0 per research R1, the R3
  view, and the request counter and histogram), serve it from the existing
  `/metrics` route, remove `prom-client` from `server.js`, `package.json`, and
  `package-lock.json`, describe the change in `AGENTS.md` and `README.md`,
  and make T001 pass
- [ ] T005 [US1] [in `auth-api` repo] Add `metrics.go` (a `MeterProvider`
  with `go.opentelemetry.io/otel/exporters/prometheus` v0.67.0 on its own
  registry per R1, the R3 view, and the request instruments), use it in the
  metrics middleware and the `/metrics` route, remove the `client_golang`
  metric constructors, update `go.mod` and `go.sum`, describe the change in
  `AGENTS.md`, and make T002 pass
- [ ] T006 [US1] [in `log-message-processor` repo] Replace the
  `prometheus_client` instruments in `main.py` with an OpenTelemetry meter and
  `PrometheusMetricReader` on its own `CollectorRegistry` per R1 and R3, add
  `opentelemetry-exporter-prometheus==0.65b0` to `requirements.in`,
  regenerate the hashed `requirements.txt` with `pip-compile
  --generate-hashes` on Python 3.13, describe the change in `AGENTS.md` and
  `README.md`, and make T003 pass

**Checkpoint**: The three migrated services expose the preserved series
through OpenTelemetry; tracing tests still pass.

---

## Phase 2: User Story 2 - See business activity next to the golden signals (Priority: P2)

**Goal**: Todos created and deleted and sign-ins by outcome are counted and
shown in the Business row.

**Independent Test**: The service tests count known operations exactly; the
dashboard contract finds the Business row and its queries.

### Tests for User Story 2

> Write these tests first and commit them failing before T010 to T012.

- [ ] T007 [P] [US2] [in `todos-api` repo] Add failing tests in
  `test/metrics.test.js`: creating a todo increases
  `todo_api_todos_created_total` by one; deleting an existing todo increases
  `todo_api_todos_deleted_total` by one; deleting a missing id and a request
  rejected for a missing JWT change neither; and both series have no labels
- [ ] T008 [P] [US2] [in `auth-api` repo] Add failing tests in
  `metrics_test.go`: an accepted login increases
  `auth_api_sign_ins_total{outcome="accepted"}` by one, a wrong-credentials
  login increases `outcome="rejected"` by one, a login failing with a server
  error changes neither, and the series has only the `outcome` label
- [X] T009 [P] [US2] Add failing assertions to
  `tests/contract/observability.sh` that the rendered Grafana root's
  golden-signals dashboard contains a row titled `Business` and queries
  `todo_api_todos_created_total`, `todo_api_todos_deleted_total`, and
  `auth_api_sign_ins_total`, per `contracts/business-metrics.md`

### Implementation for User Story 2

- [ ] T010 [US2] [in `todos-api` repo] Add the two business counters to
  `metrics.js` and increment them in `todoController.js` per research R6, and
  make T007 pass
- [ ] T011 [US2] [in `auth-api` repo] Add the sign-in counter to `metrics.go`
  and increment it in the login handler per research R6, and make T008 pass
- [X] T012 [US2] Add the Business row and its two panels to
  `infrastructure/grafana/dashboards/golden-signals.yaml` per research R7, and
  make T009 pass

**Checkpoint**: Business metrics are counted in both services and visible in
the dashboard definition.

---

## Phase 3: Live Acceptance

**Purpose**: Prove the feature on the economical cluster once it is rebuilt
(governance program T031) and the new images are promoted.

- [ ] T013 Run `quickstart.md` section 3 on the rebuilt economical cluster:
  preserved families (SC-001), recording rules and the canary query (SC-002),
  business counts after known operations including the server-error sign-in
  (SC-003, SC-004), and the Business row (SC-005); retain the outputs under
  `evidence/runs/<timestamp>-service-metrics/`
- [ ] T014 Compare the T013 evidence and the service repositories' merged
  dependency manifests (SC-006) against FR-001 to FR-013 and SC-001 to SC-006
  in `specs/011-service-metrics/checklists/acceptance.md`, recording each
  requirement as met, unmet, or blocked with the evidence that shows it

---

## Dependencies & Execution Order

### Phase dependencies

```text
US1 (tests T001/T002/T003 -> implementation T004/T005/T006)
    -> US2 (tests T007/T008/T009 -> implementation T010/T011/T012)
        -> Live acceptance (T013 -> T014, after governance T031 and image promotion)
```

- Within each service repository, the US1 pair lands before the US2 pair,
  because the business counters use the meter T004 and T005 introduce.
- T009 and T012 (the dashboard) are independent of the service repositories.
- Test commits are never squashed into their implementation commits.

### Pull requests

| Repository | Tasks |
| --- | --- |
| `microservice-app-gitops` (specification) | spec, plan, tasks |
| `microservice-app-todos-api` | T001, T004, T007, T010 |
| `microservice-app-auth-api` | T002, T005, T008, T011 |
| `microservice-app-log-message-processor` | T003, T006 |
| `microservice-app-gitops` (dashboard) | T009, T012 |

## Parallel Opportunities

```text
T001 todos-api tests || T002 auth-api tests || T003 log-message-processor tests
T004 todos-api || T005 auth-api || T006 log-message-processor
T007 todos-api tests || T008 auth-api tests || T009 dashboard contract
T010 todos-api || T011 auth-api || T012 dashboard
```

## Implementation Strategy

### MVP first (User Story 1)

1. Land T001 to T006: the three services record through OpenTelemetry with no
   change to any series that rules, dashboards, or the canary gate read.
2. Stop and confirm each repository's CI is green before business metrics.

### Incremental delivery

1. US1: one pull request per service repository.
2. US2: business counters in the same service pull requests (after the US1
   pair) and the dashboard pull request in this repository.
3. Live acceptance once the cluster is rebuilt.

## Notes

- `users-api` and `frontend` have no tasks: they are documented exceptions
  (FR-010).
- Live tasks remain open until the economical cluster is rebuilt; a rendered
  configuration never ticks them.

---

description: "Task list for service tracing through OpenTelemetry"
---

# Tasks: Service Tracing Through OpenTelemetry

**Input**: Design documents from `specs/010-service-tracing/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/trace-context.md`, `contracts/tracing-configuration.md`,
`quickstart.md`

**Tests**: Required. FR-012 requires tests committed failing before each
implementation, and FR-014 requires live evidence for acceptance.

**Organization**: Tasks are grouped by user story. Tasks marked
`[in <repo> repo]` land in that repository's own pull request; every other
path is in `microservice-app-gitops`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: The user story the task belongs to (US1, US2, US3)

---

## Phase 1: Setup

**Purpose**: Record the register discrepancy this feature resolves before any
implementation.

- [X] T001 Add a reconciliation note under "Status at this revision" in
  `specs/009-full-platform-rollout/tasks.md` stating that T072 to T081
  delivered the health, correlation, and resilience contracts, that only
  `auth-api` exports OpenTelemetry traces, and that the tracing part is
  delivered by spec 010 (research.md R12); no task in spec 009 is unticked or
  reworded

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Give every service a reachable tracing destination. Nothing a
service emits can reach Jaeger until this lands.

- [X] T002 Add a failing render contract in `tests/contract/service-tracing.sh`
  that, for every service (`auth-api`, `todos-api`, `users-api`, `frontend`,
  `log-message-processor`) and every economical overlay (`dev`, `staging`,
  `prod`, `demo`), asserts the rendered Deployment receives
  `OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger-collector.observability.svc:4317`
  and `OTEL_SERVICE_NAME=<service>` and that no overlay overrides the
  endpoint, and that `environments/{dev,staging,prod,demo}` each render
  `allow-tracing-egress` exactly as `contracts/tracing-configuration.md`
  defines (one rule, one peer with both selectors, TCP 4317 only); run it in
  the `policy-contracts` job of `.github/workflows/validate-gitops.yml`
- [X] T003 Add `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_SERVICE_NAME` to
  `apps/{auth-api,todos-api,users-api,frontend,log-message-processor}/base/configmap.yaml`,
  remove the per-overlay `OTEL_EXPORTER_OTLP_ENDPOINT` env patches from
  `apps/auth-api/profiles/economical/overlays/{dev,demo}/kustomization.yaml`
  and `apps/auth-api/profiles/full/overlays/dev/kustomization.yaml`, add
  `environments/base/networkpolicy-allow-tracing-egress.yaml` and list it in
  `environments/base/kustomization.yaml`, and make T002 and
  `tests/contract/observability.sh` pass

**Checkpoint**: Every business pod in every economical environment has the
tracing destination and a network path to it; services that do not trace yet
are unaffected.

---

## Phase 3: User Story 1 - Follow a todo from the browser to the audit worker (Priority: P1) MVP

**Goal**: One connected trace for a todo operation across `frontend`,
`todos-api`, and `log-message-processor`, including the Redis message hop.

**Independent Test**: Create a todo through the frontend and retrieve one trace
containing spans from all three services, with the consumer span parented by
the producer span.

### Contracts for User Story 1 (contract-first)

- [X] T004 [P] [US1] [in `todos-api` repo] Replace `zipkinSpan` with optional
  `traceparent` (W3C pattern) and `tracestate` strings in
  `TodoOperationPayload` of `contracts/asyncapi.yaml`, update the consumer
  operation's description, and pass the repository's Spectral lint
  Delivered in MicroTodoSuite/microservice-app-todos-api#22.
- [X] T005 [P] [US1] [in `log-message-processor` repo] Apply the identical
  change to `contracts/asyncapi.yaml` and pass its Spectral lint
  Delivered in MicroTodoSuite/microservice-app-log-message-processor#23; the contract is byte-identical to todos-api's.

### Tests for User Story 1

> Write these tests first and commit them failing before T009 to T011.

- [X] T006 [P] [US1] [in `todos-api` repo] Add failing tests in
  `test/tracing.test.js` with an in-memory span exporter: a `/todos` request
  produces a `SERVER` span that continues an incoming `traceparent`;
  `/health/startup`, `/health/ready`, `/health/live`, and `/metrics` produce no
  spans; creating and deleting a todo produce a `PRODUCER` span named
  `log_channel publish` with the messaging attributes from
  `contracts/trace-context.md`, and the published message carries that span's
  `traceparent` and no `zipkinSpan`; no span attribute contains the JWT or the
  `Authorization` header; `package.json` depends on no `zipkin` package; and
  the runtime `COPY` in `Dockerfile` includes `tracing.js`. Update the tracer
  stubs in `test/routes.test.js`, `test/operational-contract.test.js`, and
  `test/integration/redis-publish.test.js` to the new controller signature
  Delivered in MicroTodoSuite/microservice-app-todos-api#22.
- [X] T007 [P] [US1] [in `log-message-processor` repo] Add failing tests in
  `tests/test_tracing.py` with an in-memory span exporter: a message with a
  valid `traceparent` produces a `CONSUMER` span named `log_channel process`
  whose parent is that context and whose messaging attributes match
  `contracts/trace-context.md`; a message without it, or with an invalid one,
  is processed and starts a new trace; a legacy `zipkinSpan` field is ignored;
  no exporter is created when `OTEL_EXPORTER_OTLP_ENDPOINT` is unset; and
  `requirements.in` lists neither `py-zipkin` nor `requests`. Replace the
  Zipkin tests in `tests/test_main.py` and the `zipkin_url` arguments in
  `tests/test_operational_contract.py`
  Delivered in MicroTodoSuite/microservice-app-log-message-processor#23.
- [X] T008 [P] [US1] [in `frontend` repo] Add failing assertions in
  `test/unit/operational-contract.test.js`: `nginx.conf.template` loads
  `modules/ngx_otel_module.so`, sets `otel_service_name frontend`, declares
  `otel_exporter` with the substituted endpoint, enables `otel_trace` with
  `otel_trace_context propagate` only in the `/login` and `/todos` locations,
  and has no `/zipkin` location; `entrypoint.sh` substitutes no `ZIPKIN_URL`,
  turns tracing off when `OTEL_EXPORTER_OTLP_ENDPOINT` is unset, and runs
  `nginx -t` when invoked with `-t`; `Dockerfile` runs on
  `nginxinc/nginx-unprivileged:alpine3.23-otel@sha256:1490cbf02ddba36ae75ef947b570166c805a178898ebfbc3bb889e7580820052`
  Delivered in MicroTodoSuite/microservice-app-frontend#27.

### Implementation for User Story 1

- [X] T009 [US1] [in `todos-api` repo] Add `tracing.js` (tracer provider with
  batch OTLP/gRPC export only when `OTEL_EXPORTER_OTLP_ENDPOINT` is set, W3C
  propagator, HTTP and Express instrumentations ignoring `/health/*` and
  `/metrics`), require it first in `server.js`, replace the Zipkin tracer in
  `server.js`, `routes.js`, and `todoController.js` with a `PRODUCER` span
  that injects its context into the audit message, copy `tracing.js` in the
  runtime stage of `Dockerfile`, pin the packages from research.md R4 and
  remove every `zipkin` package in `package.json` and `package-lock.json`,
  correct the Zipkin description in `AGENTS.md` and `README.md`, and make T004
  and T006 pass
  Delivered in MicroTodoSuite/microservice-app-todos-api#22.
- [X] T010 [US1] [in `log-message-processor` repo] Replace `py-zipkin` and
  `requests` with the OpenTelemetry packages from research.md R5 in
  `requirements.in`, regenerate the hashed `requirements.txt` with
  `pip-compile --generate-hashes` on Python 3.13, replace the Zipkin transport
  in `main.py` with a `CONSUMER` span that extracts the message's
  `traceparent`, remove `ZIPKIN_URL`, correct `AGENTS.md` and `README.md`, and
  make T005 and T007 pass
  Delivered in MicroTodoSuite/microservice-app-log-message-processor#23.
- [X] T011 [US1] [in `frontend` repo] Switch the runtime stage of `Dockerfile`
  to the `alpine3.23-otel` digest, add the module, exporter, service name, and
  per-location tracing to `nginx.conf.template`, remove the `/zipkin`
  location, make `entrypoint.sh` substitute `OTEL_EXPORTER_OTLP_ENDPOINT`,
  disable tracing when it is unset, and support `-t`, remove `ZIPKIN_URL` from
  `e2e/compose.yaml`, `config/index.js`, `README.md`, and `AGENTS.md`, and make
  T008 pass
  Delivered in MicroTodoSuite/microservice-app-frontend#27.
- [X] T012 [US1] Observe a local connected trace per `quickstart.md` section 2
  (Jaeger 2.20.0, Redis, the T009 `todos-api` image, and the T010
  `log-message-processor` image on one Docker network) and record in the
  `todos-api` and `log-message-processor` pull requests that one trace lists
  both services with the consumer span parented by the producer span
  Observed locally with the built images and recorded in MicroTodoSuite/microservice-app-log-message-processor#23 (both halves) and MicroTodoSuite/microservice-app-todos-api#22.

**Checkpoint**: The todo path is traced end to end in local verification; live
evidence waits for Phase 6.

---

## Phase 4: User Story 2 - Follow a login across the authentication path (Priority: P2)

**Goal**: One connected trace for a sign-in across `frontend`, `auth-api`, and
`users-api`.

**Independent Test**: Sign in through the frontend and retrieve one trace with
spans from all three services; a failed sign-in marks its span as an error.

### Tests for User Story 2

> Write these tests first and commit them failing before T015 and T016.

- [X] T013 [P] [US2] [in `auth-api` repo] Add failing tests in `main_test.go`
  with an in-memory span exporter: `/health/startup`, `/health/ready`,
  `/health/live`, and `/metrics` produce no spans; a `/login` request produces
  a `SERVER` span and a `CLIENT` span whose outgoing request to `users-api`
  carries a `traceparent` from the same trace; a rejected sign-in records HTTP
  status 401 on its `SERVER` span and leaves the span status unset, per the
  OpenTelemetry HTTP semantic conventions; no span attribute contains the
  password or a JWT
  Delivered in MicroTodoSuite/microservice-app-auth-api#26; the tests live in `tracing_test.go` beside `main_test.go`, in the same package.
- [X] T014 [P] [US2] [in `users-api` repo] Add failing tests in
  `src/test/java/com/elgris/usersapi/UsersApiApplicationTests.java` (and a
  focused `TracingConfigurationTests.java` beside it): no Zipkin exporter class
  is on the classpath; an OTLP span exporter is configured when
  `OTEL_EXPORTER_OTLP_ENDPOINT` is set and none when it is empty; requests to
  `/health/**` and `/prometheus` produce no spans while their
  `http.server.requests` metrics remain; a request with an incoming
  `traceparent` continues that trace. Remove the
  `management.zipkin.tracing.export.enabled=false` test property
  Delivered in MicroTodoSuite/microservice-app-users-api#27.

### Implementation for User Story 2

- [X] T015 [US2] [in `auth-api` repo] Pass `otelecho.WithSkipper` for
  `/health/*` and `/metrics` in `main.go`, correct the Zipkin description in
  `AGENTS.md` and `README.md`, and make T013 pass
  Delivered in MicroTodoSuite/microservice-app-auth-api#26; `README.md` never described tracing, so only `AGENTS.md` changed.
- [X] T016 [US2] [in `users-api` repo] Replace
  `opentelemetry-exporter-zipkin` with `opentelemetry-exporter-otlp` in
  `pom.xml`; replace `management.zipkin.tracing.endpoint` with
  `management.otlp.tracing.transport=grpc` in
  `src/main/resources/application.properties`; set
  `management.otlp.tracing.endpoint` from `OTEL_EXPORTER_OTLP_ENDPOINT` only
  when that variable has a value, through
  `src/main/java/com/elgris/usersapi/configuration/OtlpTracingEndpointEnvironmentPostProcessor.java`
  registered in `src/main/resources/META-INF/spring.factories` (research R6:
  an empty endpoint property still creates an exporter, which stops startup); add
  `src/main/java/com/elgris/usersapi/configuration/TracingConfiguration.java`,
  an auto-configuration registered in
  `src/main/resources/META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`
  that replaces Spring Boot's three tracing observation handlers with ones
  that ignore `/health/**` and `/prometheus` requests and the observations
  nested in them, so those requests keep their metrics (research R6, FR-013);
  correct `AGENTS.md` and `README.md`; and make T014 pass
  Delivered in MicroTodoSuite/microservice-app-users-api#27, as amended in #123 (research R6).

**Checkpoint**: The sign-in path is traced in each service's tests; live
evidence waits for Phase 6.

---

## Phase 5: User Story 3 - Every service reports, and no Zipkin remains (Priority: P3)

**Goal**: Uniform tracing across every economical environment with no Zipkin
dependency left anywhere.

**Independent Test**: The render contract proves every environment's
configuration is identical and Zipkin-free; a search of all six repositories
finds no Zipkin export path.

- [ ] T017 [US3] Extend `tests/contract/service-tracing.sh` with a failing
  assertion that no rendered application or environment contains `ZIPKIN_URL`
  or any other Zipkin setting (fails today on `apps/frontend/base/configmap.yaml`)
- [ ] T018 [US3] Remove `ZIPKIN_URL` from `apps/frontend/base/configmap.yaml`
  only after the T011 frontend image is promoted to every economical
  environment (the current image's `nginx.conf.template` needs the value to
  start), and make T017 pass
- [ ] T019 [US3] Run a case-insensitive search for `zipkin` across
  `microservice-app-gitops/{apps,environments,clusters,infrastructure}` and the
  five service repositories' `main` branches, excluding `CHANGELOG.md` and
  historical specifications and evidence, and record the result (SC-004) in
  the T018 pull request; any hit becomes a task before this one is ticked

**Checkpoint**: The desired state and all service code are Zipkin-free.

---

## Phase 6: Polish and Live Acceptance

**Purpose**: Prove the feature on the economical cluster once it is rebuilt
(governance program T031).

- [ ] T020 Run `quickstart.md` section 3 on the rebuilt economical cluster:
  service list (SC-003), todo trace (SC-001), sign-in trace (SC-002), attribute
  review (SC-006), and the backend-unavailable check through a reviewed commit
  and its revert (SC-005); retain the outputs under
  `evidence/runs/<timestamp>-service-tracing/`
- [ ] T021 Compare the T020 evidence against FR-001 to FR-014 and SC-001 to
  SC-007 in `specs/010-service-tracing/checklists/acceptance.md`, recording
  each requirement as met, unmet, or blocked with the evidence file that shows
  it

---

## Dependencies & Execution Order

### Phase dependencies

```text
Setup (T001)
    -> Foundational (T002 -> T003)
        -> US1 (contracts T004/T005 -> tests T006/T007/T008 -> implementation T009/T010/T011 -> T012)
        -> US2 (tests T013/T014 -> implementation T015/T016)
            -> US3 (T017 -> T018 after the frontend image is promoted -> T019)
                -> Live acceptance (T020 -> T021, after governance T031)
```

- T002 and T003 unblock every live observation but not the service repository
  work, which can proceed in parallel with them.
- US1 and US2 are independent of each other.
- Within each service repository: contract (where one exists), then the
  failing test commit, then the implementation commit, never squashed
  together.
- T018 depends on the release and promotion of the T011 frontend image, which
  runs through the existing CI and promotion path this feature does not change.

### Pull requests

| Repository | Tasks |
| --- | --- |
| `microservice-app-gitops` (specification) | spec, plan, tasks, T001 |
| `microservice-app-gitops` (configuration) | T002, T003 |
| `microservice-app-todos-api` | T004, T006, T009, part of T012 |
| `microservice-app-log-message-processor` | T005, T007, T010, part of T012 |
| `microservice-app-frontend` | T008, T011 |
| `microservice-app-auth-api` | T013, T015 |
| `microservice-app-users-api` | T014, T016 |
| `microservice-app-gitops` (cleanup) | T017, T018, T019 |

## Parallel Opportunities

```text
T004 todos-api contract || T005 log-message-processor contract
T006 todos-api tests || T007 log-message-processor tests || T008 frontend tests || T013 auth-api tests || T014 users-api tests
T009 todos-api || T010 log-message-processor || T011 frontend || T015 auth-api || T016 users-api
```

## Implementation Strategy

### MVP first (User Story 1)

1. T001, T002, T003.
2. T004 to T012: the todo path traced end to end, verified locally.
3. Stop and validate before US2.

### Incremental delivery

1. US2 closes the sign-in path.
2. US3 removes the last Zipkin setting after the frontend promotion.
3. Live acceptance once the economical cluster is rebuilt.

## Notes

- A task is ticked only against its located artifact; "observe" and "record"
  tasks need the run.
- No task changes metrics instrumentation (FR-013).
- No task changes the shared CI workflow, image promotion, Istio, or any
  component owned by another lane.

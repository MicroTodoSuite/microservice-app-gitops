# Feature Specification: Service Tracing Through OpenTelemetry

**Feature Branch**: `docs/service-tracing-spec` (specification); implementation
lands on short-lived branches in each affected repository

**Created**: 2026-09-12

**Status**: Draft

**Input**: User description: "Service tracing through OpenTelemetry to Jaeger for every MicroTodoSuite service (plan section 10: \"OpenTelemetry como capa única de instrumentación en cada servicio. Trazas hacia Jaeger.\"), economical profile first"

## Clarifications

### Session 2026-09-12

- Q: Does "OpenTelemetry como capa única de instrumentación" cover metrics too,
  or only traces? → A: Both, delivered in two features. This feature moves
  every service's tracing to OpenTelemetry and Jaeger. Re-expressing the
  existing Prometheus client metrics through OpenTelemetry, while Prometheus
  keeps scraping the same series that dashboards, alerts, and the canary gate
  already query, is a separate follow-up feature specified together with the
  business metrics plan section 10 also requires. The split keeps each change
  small and avoids breaking working metrics while tracing is cut over.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Follow a todo from the browser to the audit worker (Priority: P1)

As a developer investigating a slow or failing todo operation, I can open the
tracing backend and find one trace that shows the whole path of that
operation: the frontend that received it, the todos API that stored it, and
the log message processor that consumed the resulting audit message.

**Why this priority**: The todo operation is the only flow that crosses every
kind of boundary the suite has (web entry point, HTTP API, and asynchronous
message). If this flow is traced end to end, the instrumentation contract is
proven for every service type. Today three of these hops export to a Zipkin
endpoint that does not exist, so no trace of this flow can be seen at all.

**Independent Test**: With the tracing backend running, create a todo through
the frontend and retrieve the resulting trace; it contains spans from the
frontend, the todos API, and the log message processor, all sharing one trace
identifier, with the consumer's span connected to the publisher's span.

**Acceptance Scenarios**:

1. **Given** the frontend, todos API, and log message processor are deployed
   with tracing enabled, **When** a signed-in user creates a todo, **Then** the
   tracing backend shows one trace containing spans from all three services.
2. **Given** that trace exists, **When** the log message processor's span is
   inspected, **Then** its parent is the todos API span that published the
   audit message, not a new, unconnected trace.
3. **Given** a todo is deleted instead of created, **When** the operation
   completes, **Then** the same three-service trace shape appears.

---

### User Story 2 - Follow a login across the authentication path (Priority: P2)

As a developer, I can find one trace for a login that shows the frontend, the
authentication API, and the users API it calls, so a slow or failed login can
be attributed to the service that caused it.

**Why this priority**: The authentication API already emits traces, but the
users API still exports to Zipkin, so every login trace ends at that boundary.
Closing it completes the second and last synchronous path in the suite.

**Independent Test**: Sign in through the frontend and retrieve the resulting
trace; it contains spans from the frontend, the authentication API, and the
users API under one trace identifier.

**Acceptance Scenarios**:

1. **Given** the frontend, authentication API, and users API are deployed with
   tracing enabled, **When** a user signs in, **Then** one trace contains spans
   from all three services.
2. **Given** a sign-in fails because the credentials are wrong, **When** the
   trace is inspected, **Then** the authentication API's server span records
   HTTP status 401 and leaves its span status unset, as the OpenTelemetry HTTP
   semantic conventions require for 4xx server responses, and the trace still
   includes every service the request reached.

---

### User Story 3 - Every service reports to the tracing backend in every economical environment (Priority: P3)

As a platform operator, I can see all five services listed in the tracing
backend for each economical environment, and I can confirm that no service
still depends on the retired Zipkin tracing path.

**Why this priority**: Stories 1 and 2 prove the flows in one environment.
This story makes the capability uniform: the same instrumentation contract,
the same destination, and no leftover dependency on a backend that is not
deployed.

**Independent Test**: For an economical environment, generate traffic against
each service and confirm the tracing backend lists all five services; inspect
each service's configuration and code for any remaining Zipkin export path.

**Acceptance Scenarios**:

1. **Given** the economical `dev` environment is reconciled, **When** traffic
   reaches each of the five services, **Then** the tracing backend lists
   `frontend`, `auth-api`, `todos-api`, `users-api`, and
   `log-message-processor` as reporting services.
2. **Given** the `staging` and `prod` economical overlays are rendered,
   **When** their tracing configuration is compared with `dev`, **Then** every
   service points at the same tracing destination by the same contract.
3. **Given** the cutover is complete, **When** each service repository and the
   GitOps desired state are searched, **Then** no Zipkin exporter, Zipkin
   endpoint setting, or Zipkin-format trace field remains in use.

### Edge Cases

- If the tracing backend is unavailable or slow, every business request MUST
  still succeed with unchanged behavior; trace export is never on the request
  path.
- The environment namespaces deny all egress by default. Services MUST be able
  to reach the tracing backend, and only the tracing backend's trace-ingestion
  ports; no broader egress is opened.
- An audit message published by an older todos API revision without trace
  context MUST still be processed by the log message processor, which starts a
  new trace instead of failing.
- A request that arrives with no incoming trace context starts a new trace; a
  request that arrives with one continues it.
- Spans MUST NOT carry credentials: no password, JWT, authorization header, or
  secret value appears as a span attribute or event.
- Cutting a service over from Zipkin to OpenTelemetry is one revision per
  service; a service never exports to both as a steady state.
- The frontend's health and metrics endpoints are not traced, so probes and
  scrapes do not flood the tracing backend.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each of the five services (`frontend`, `auth-api`, `todos-api`,
  `users-api`, `log-message-processor`) MUST produce traces through
  OpenTelemetry as its single tracing instrumentation layer.
- **FR-002**: Every service MUST send its traces to the tracing backend
  already deployed for the economical profile (Jaeger, spec 006), selected by
  the standard OpenTelemetry endpoint configuration supplied by the GitOps
  overlays, not by a value compiled into the service.
- **FR-003**: Trace context MUST propagate using the W3C Trace Context standard
  on every synchronous hop: frontend to authentication API, frontend to todos
  API, and authentication API to users API.
- **FR-004**: The todo operation message that the todos API publishes and the
  log message processor consumes MUST carry the originating trace context, and
  the published message contract MUST be updated to describe that field before
  either service implements it, replacing the Zipkin-format field.
- **FR-005**: The log message processor MUST record its processing of a todo
  operation as a span that continues the publisher's trace when trace context
  is present, and MUST start a new trace when it is absent.
- **FR-006**: Every Zipkin exporter, Zipkin client library, Zipkin endpoint
  setting, and Zipkin proxy route MUST be removed from the five services and
  from the GitOps desired state once each service's cutover is complete.
- **FR-007**: Each service MUST identify itself in the tracing backend by its
  service name, matching the names in FR-001.
- **FR-008**: Trace export MUST be asynchronous and non-blocking: an
  unreachable tracing backend MUST NOT change any request's result or add
  request-path latency beyond normal batching.
- **FR-009**: The economical environment network policies MUST allow each
  business namespace to reach only the tracing backend's trace-ingestion
  endpoints in the `observability` namespace, and nothing else beyond what is
  already allowed.
- **FR-010**: Spans MUST NOT include credentials, tokens, authorization
  headers, or secret values.
- **FR-011**: Health, readiness, and metrics endpoints MUST NOT produce spans.
- **FR-012**: Each service repository MUST include automated tests, written
  and committed failing before the implementation, that prove its spans are
  created, its incoming context is continued, and its outgoing context is
  propagated; the GitOps repository MUST include a validation that fails when
  a business overlay lacks the tracing destination or when the tracing egress
  policy is missing or broader than FR-009 allows.
- **FR-013**: This feature MUST NOT change any service's existing metrics
  instrumentation or the metric series it exposes; moving metrics onto the same
  OpenTelemetry layer is a separate follow-up feature (see Clarifications).
- **FR-014**: Final acceptance MUST rest on live evidence from the economical
  cluster (retrieved traces for Stories 1 and 2 and the service list for Story
  3), never on rendered configuration alone.

### Key Entities

- **Trace**: The record of one user operation across services, identified by
  one trace identifier and made of spans.
- **Span**: One service's unit of work within a trace, with a service name,
  timing, status, and a parent link when it continues another span.
- **Trace context**: The standard identifiers carried on an HTTP request or in
  a todo operation message so the next service continues the same trace.
- **Todo operation message**: The asynchronous audit message published by the
  todos API and consumed by the log message processor, now carrying trace
  context instead of a Zipkin-format field.
- **Tracing destination**: The tracing backend's ingestion endpoint, supplied
  to each service by its environment overlay.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A todo created through the frontend produces one trace containing
  spans from 3 of 3 services on its path (frontend, todos API, log message
  processor), retrievable in the tracing backend within 2 minutes.
- **SC-002**: A sign-in through the frontend produces one trace containing
  spans from 3 of 3 services on its path (frontend, authentication API, users
  API), retrievable within 2 minutes.
- **SC-003**: 5 of 5 services appear as reporting services in the tracing
  backend for the economical `dev` environment after real traffic.
- **SC-004**: 0 Zipkin export paths remain across the five services and the
  GitOps desired state.
- **SC-005**: With the tracing backend stopped, 100% of a sample of 20 sign-ins
  and 20 todo operations still succeed.
- **SC-006**: 0 spans in the retrieved evidence traces contain a password,
  token, or authorization header.
- **SC-007**: Every service's tracing tests and the GitOps tracing validation
  pass in CI, and each failed before its implementation commit.

## Assumptions

- The economical profile comes first. The tracing backend is the Jaeger
  instance with embedded storage and 3-day retention from spec 006, per plan
  section 17. The full profile's tracing destination is planned with the full
  platform work in spec 009 and is out of scope here.
- The frontend participates through the web server that receives each
  browser request and forwards it to the APIs: that entry point starts or
  continues the trace. Instrumenting code that runs inside the user's browser
  is out of scope.
- All requests are traced (no sampling reduction) in the economical profile,
  whose traffic is low; the existing sampling setting in `users-api` keeps its
  current default of 100%.
- `auth-api` already exports OpenTelemetry traces (spec 006 US4); in this
  feature it only needs its tracing destination to be reachable and its
  propagation to the users API verified.
- Correlating log lines with trace identifiers beyond what `auth-api` already
  does, trace-based alerting, and dashboards built from traces are not part of
  plan section 10's tracing sentence and are out of scope.
- Live evidence depends on the economical cluster being rebuilt (governance
  program T031); until then, only repository tests and render validations can
  pass, and the live acceptance tasks stay open.
- Service code changes land in each service's own repository through its own
  pull request; this repository carries the specification, the GitOps
  configuration, the network policy, and the validation.
- Spec 009 marks T072 to T081 as delivered with OpenTelemetry wording, while
  only `auth-api` exports OpenTelemetry traces today; the plan for this feature
  reconciles those entries explicitly rather than editing them silently.

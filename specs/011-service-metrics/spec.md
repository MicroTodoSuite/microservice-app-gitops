# Feature Specification: Service Metrics Through OpenTelemetry

**Feature Branch**: `docs/service-metrics-spec` (specification); implementation
lands on short-lived branches in each affected repository

**Created**: 2026-09-13

**Status**: Draft

**Input**: User description: "Service metrics through OpenTelemetry, together with minimal business metrics, for the MicroTodoSuite services (plan section 10 requires OpenTelemetry as each service's single instrumentation layer, and technical and business metrics in Prometheus and Grafana), economical profile first, keeping the series Prometheus already queries"

## Clarifications

### Session 2026-09-12

- Q: Does "OpenTelemetry as the single instrumentation layer" cover metrics
  too? → A: Yes, delivered after tracing (spec 010) as this separate feature,
  which re-expresses the existing metrics through OpenTelemetry while
  Prometheus keeps the same series the dashboards, alerts, and canary gate
  already query.
- Q: Which business metrics? → A: A minimal set: todos created and deleted
  (todos API) and sign-ins that succeed and fail (authentication API), shown
  on a Grafana panel.

### Session 2026-09-13

- Q: How do OpenTelemetry metrics reach Prometheus? → A: Pull. Each service
  measures through OpenTelemetry and keeps exposing its metrics endpoint for
  the existing scrape; no push path, receiver, or new network access is
  added.
- Q: What about the users API (Spring Boot, measured through Micrometer) and
  the frontend (nginx, measured by an exporter sidecar), which have no direct
  OpenTelemetry metrics SDK? → A: Both stay as documented exceptions with
  their series unchanged: Micrometer is the users API's framework-native
  instrumentation facade, already bridged to OpenTelemetry for traces, and
  nginx has no OpenTelemetry metrics module. The authentication API, todos
  API, and log message processor move to OpenTelemetry.
- Q: Where are the business metrics shown? → A: In a "Business" row of the
  existing golden-signals dashboard. No new alert is added.
- Q: What happens to the default runtime metrics the current Prometheus
  clients expose (process, memory, garbage collection, event loop), which no
  rule, dashboard, or canary query uses? → A: They stop being exposed. Only
  the application series in use and the new business series remain.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Keep every golden signal working through the instrumentation change (Priority: P1)

An on-call operator keeps the same golden-signal dashboard, alerts, and
canary gate after the authentication API, todos API, and log message
processor change how they measure, without editing a query or noticing a gap.

**Why this priority**: The golden-signal rules, the Slack alerts, and the
canary gate that decides progressive releases already depend on these series.
Moving to OpenTelemetry is only acceptable if nothing that reads them breaks.

**Independent Test**: Scrape each migrated service before and after its
change and compare: every series the recording rules, dashboard, and canary
query use is present with the same name and label names, and the recording
rules return values for all three services.

**Acceptance Scenarios**:

1. **Given** a migrated service is running, **When** its metrics endpoint is
   scraped, **Then** every series listed in FR-003 for that service is present
   with its current name and label names.
2. **Given** the three migrated services receive traffic, **When** the
   golden-signal recording rules are evaluated, **Then** traffic, error rate,
   and latency return values for each of them as they did before.
3. **Given** a canary revision of a migrated service is running, **When** the
   canary gate queries its error-rate ratio, **Then** it receives a value and
   decides as it did before.

---

### User Story 2 - See business activity next to the golden signals (Priority: P2)

A product-minded operator opens the golden-signals dashboard and sees how
many todos are being created and deleted and how many sign-ins succeed and
fail, without reading logs.

**Why this priority**: Plan section 10 requires business metrics alongside
technical ones. The technical migration comes first because it protects what
already works; business metrics add new visibility on top of it.

**Independent Test**: Create and delete a known number of todos and perform a
known number of accepted and rejected sign-ins, then confirm the business
series and the dashboard row change by exactly those amounts.

**Acceptance Scenarios**:

1. **Given** the todos API is running, **When** a signed-in user creates a
   todo successfully, **Then** the todos-created count increases by one.
2. **Given** a todo exists, **When** it is deleted successfully, **Then** the
   todos-deleted count increases by one.
3. **Given** the authentication API is running, **When** a sign-in with valid
   credentials succeeds, **Then** the successful sign-ins count increases by
   one; **When** credentials are rejected, **Then** the failed sign-ins count
   increases by one.
4. **Given** those counts changed, **When** the dashboard's Business row is
   opened, **Then** its panels show the change within two scrape intervals.

---

### Edge Cases

- A request that fails (for example a todo creation that returns an error)
  MUST NOT count as a created or deleted todo.
- Deleting a todo that does not exist MUST NOT count as a deletion.
- A sign-in that fails because a dependency is unavailable (a server error)
  is not a rejected-credentials failure: it MUST NOT count as a failed
  sign-in, and it remains visible in the error-rate golden signal.
- Counters restart from zero when a pod restarts; queries use rates and
  increases, which tolerate resets.
- Probe and scrape requests MUST NOT count as business events.
- Business series MUST NOT carry user names, todo identifiers, todo content,
  or credentials as labels.
- If the metrics endpoint cannot be served, request handling MUST be
  unaffected.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The authentication API, todos API, and log message processor
  MUST record their technical and business metrics through the OpenTelemetry
  metrics API as their single metrics instrumentation layer. No metric MAY be
  recorded through a Prometheus client library's API; such a library MAY remain
  only where the OpenTelemetry exporter itself uses it to serve the metrics
  endpoint.
- **FR-002**: Each migrated service MUST keep serving its metrics on the same
  endpoint and port the existing scrape configuration reads; no scrape,
  network policy, or receiver change is part of this feature.
- **FR-003**: These series MUST keep their names and label names: the
  authentication API's `auth_api_requests_total` (`method`, `status`) and
  `auth_api_request_duration_seconds` histogram (`method`); the todos API's
  `todo_api_requests_total` (`method`, `status`) and
  `todo_api_request_duration_seconds` histogram (`method`); and the log
  message processor's `log_messages_processed_total`,
  `log_messages_failed_total`, and `log_message_processing_duration_seconds`
  histogram. Histogram bucket boundaries MUST stay as they are today.
- **FR-004**: The series in FR-003 MUST NOT gain labels that change the result
  of the existing recording rules, dashboard queries, or canary query.
- **FR-005**: Default runtime metrics (process, memory, garbage collection,
  event loop) MUST no longer be exposed by the three migrated services.
- **FR-006**: The todos API MUST count successfully created todos and
  successfully deleted todos as two business series.
- **FR-007**: The authentication API MUST count sign-ins by outcome: accepted,
  and rejected because the credentials were wrong.
- **FR-008**: Business series MUST NOT use user identity, todo identifiers,
  todo content, or credentials as labels.
- **FR-009**: The golden-signals dashboard MUST gain a Business row showing
  todos created and deleted and sign-ins accepted and rejected over time. No
  alert is added for business series.
- **FR-010**: The users API and the frontend MUST keep their current metrics
  instrumentation and series, recorded in this specification as justified
  exceptions to FR-001.
- **FR-011**: Tracing (spec 010) MUST keep working unchanged in every migrated
  service.
- **FR-012**: Each migrated service repository MUST include automated tests,
  written and committed failing before the implementation, that prove the
  FR-003 names, labels, and bucket boundaries, the absence of runtime metrics
  and of metrics recorded through a Prometheus client API, and the business
  counts; the
  GitOps repository MUST include a validation that fails when the Business
  row or its queries are missing.
- **FR-013**: Final acceptance MUST rest on live evidence from the economical
  cluster (scraped series, recording-rule results, the canary query, and the
  dashboard's Business row), never on rendered configuration alone.

### Key Entities

- **Technical request metric**: A per-service count of handled requests and a
  duration distribution, labelled by method and, for counts, status.
- **Processing metric**: The log message processor's counts of processed and
  failed messages and its processing-duration distribution.
- **Business metric**: A count of a domain event: a todo created, a todo
  deleted, a sign-in accepted, or a sign-in rejected.
- **Preserved series set**: The series in FR-003 that recording rules,
  dashboards, and the canary gate read.
- **Business row**: The golden-signals dashboard section that shows the
  business metrics.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After each service's change, 100% of its FR-003 series are
  present with the same names and label names when its metrics endpoint is
  scraped.
- **SC-002**: On the rebuilt economical cluster, the traffic, error-rate, and
  latency recording rules return values for the authentication API, todos
  API, and log message processor, and the canary gate's query returns a
  value for a canary revision.
- **SC-003**: Creating N todos and deleting M of them increases the created
  and deleted counts by exactly N and M.
- **SC-004**: K accepted and J rejected sign-ins increase the accepted and
  rejected counts by exactly K and J, and a sign-in failing on a server error
  changes neither.
- **SC-005**: The dashboard's Business row reflects those changes within two
  scrape intervals.
- **SC-006**: None of the three migrated services records a metric through a
  Prometheus client library's API; any remaining Prometheus client dependency
  is used only by the OpenTelemetry exporter to serve the endpoint.

## Assumptions

- The economical profile is delivered first; the full profile reuses the same
  service images and dashboards.
- Scrape scope is unchanged: the existing ServiceMonitors keep selecting the
  namespaces they select today, so business metrics are visible for the same
  environments as the technical ones.
- "Successful" means the API returned a success response for the operation;
  counting happens in the service, not by parsing logs.
- The OpenTelemetry metrics exporters' versions, naming configuration, and
  histogram views are planning decisions, verified against their sources.
- Removing the unused runtime metrics is a decided change, not a regression
  (Clarifications 2026-09-13).
- Live evidence waits for the economical cluster rebuild, as it does for
  specs 006, 008, and 010.

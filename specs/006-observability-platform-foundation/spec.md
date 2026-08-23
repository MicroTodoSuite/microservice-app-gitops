# Feature Specification: Observability Platform Foundation

**Feature Branch**: `feat/observability-platform-foundation`

**Created**: 2026-08-23

**Status**: Draft

**Input**: User description: "Add the MicroTodoSuite observability platform foundation on the live eks-dev cluster: deploy Prometheus and Grafana as the metrics backend with dashboards covering the four golden signals (latency, traffic, errors, saturation) for every business workload; deploy Alertmanager wired to notify a Slack channel on SLO-relevant alerts; deploy Jaeger as the distributed tracing backend; instrument auth-api with OpenTelemetry (traces, metrics, and structured JSON logs correlated by trace_id/span_id, replacing its current Zipkin exporter) as the proof-of-pattern service, following OpenTelemetry Semantic Conventions for span and metric naming; deploy an ELK stack with Filebeat as the log collector; and upgrade the existing Argo Rollouts ClusterAnalysisTemplate canary health check to query real Prometheus metrics instead of a synthetic curl probe. Everything must follow the same GitOps-only, pinned-and-vendored, Audit-before-Enforce, namespace-scoped economical profile already used for keda/cert-manager/external-secrets/kyverno, and must produce live evidence that every dashboard, alert route, trace, and log actually reflects real traffic from the running services."

## Clarifications

### Session 2026-08-23

- Q: Which log stack does this feature deploy — the full ELK stack `plan.md` describes in section 10, or a lighter alternative? → A: Neither an unqualified default nor full ELK. `plan.md` section 17's own economical-profile table (already formally adopted by `constitution.md` v2.0.0) specifies Loki (reusing the same Grafana already deployed for metrics) in place of ELK, and Jaeger with embedded storage and short retention in place of a Jaeger-on-Elasticsearch backend, specifically for the cost-optimized single-cluster profile this project runs under. This feature follows that already-decided economical-profile mapping rather than the full-profile ELK/Elasticsearch-backed Jaeger described in section 10.
- Q: How do operators reach the Grafana, Jaeger, and log-viewer UIs? → A: `kubectl port-forward` only, no public Ingress, matching the exact access pattern already established for the local pilot in `docs/local-pilot-quickstart.md`. Ingress with TLS and an authentication/SSO decision is out of scope for this feature and remains explicit follow-up work.
- Q: What exact signal, threshold, and window gate the metric-gated canary analysis? → A: HTTP 5xx error-rate ratio greater than 5% sustained over a 5-minute window. Error rate is chosen over latency because all five business workloads can emit it today without waiting for OpenTelemetry latency histograms, which only `auth-api` will have after this feature.
- Q: What retention window applies to logs and traces? → A: 3 days for both the log-storage component (Loki) and the tracing backend's embedded storage, consistent with the economical profile's "short retention" framing for Jaeger and sized for a single shared cluster rather than long-term archival.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the four golden signals for every business workload (Priority: P1)

As a platform operator, I can open a dashboard and see latency, traffic, error
rate, and saturation for every deployed business workload, built from metrics
the workloads actually emit while serving real requests.

**Why this priority**: Every other capability in this feature (metric-gated
canaries, alerting, and later SLOs) is built on top of a working metrics
backend. Without it, nothing else in this spec can be proven live.

**Independent Test**: Starting from the reconciled `eks-dev` platform, publish
the metrics-backend desired state, wait for it to become synchronized and
healthy, generate real traffic against a business workload, and observe its
four golden-signal panels populate with non-zero, changing values driven by
that traffic.

**Acceptance Scenarios**:

1. **Given** the metrics-backend desired state is committed to `gitops`,
   **When** ArgoCD reconciles it on `eks-dev`, **Then** the metrics controller
   and dashboard application both reach synchronized, healthy status with
   every expected deployment available.
2. **Given** the metrics backend is healthy, **When** a real request is sent
   to a business workload, **Then** a scrape of that workload's endpoint
   shows the request reflected in its latency, traffic, and error counters
   within one scrape interval.
3. **Given** the dashboard application is healthy, **When** an operator opens
   the golden-signal dashboard for any of the five business workloads,
   **Then** all four panels render data sourced from that workload's live
   metrics, not a placeholder or empty query.

---

### User Story 2 - Gate production canaries on real metrics instead of a synthetic probe (Priority: P2)

As a release manager, I can trust that a production canary rolls back
automatically when the new version's real error rate or latency crosses a
threshold, not only when a synthetic HTTP probe fails to connect.

**Why this priority**: The existing `ClusterAnalysisTemplate` already gates
production canaries, but only proves the pod answers HTTP — a version that
answers 200 while silently corrupting responses or degrading latency would
still be promoted. This is the highest-value use of the metrics backend,
directly hardening a control that is already in the promotion path today.

**Independent Test**: With the metrics backend live, publish a deliberately
degraded canary revision (HTTP 5xx error rate above 5%) for one business
workload behind a feature-flagged path, observe Argo Rollouts query the
updated analysis, and confirm it aborts and rolls back the canary without
human intervention.

**Acceptance Scenarios**:

1. **Given** the metrics backend is healthy and scraping a business
   workload, **When** the `ClusterAnalysisTemplate` runs during a canary
   step, **Then** it queries the canary revision's real HTTP 5xx error-rate
   ratio instead of issuing a synthetic HTTP probe.
2. **Given** a canary revision whose error-rate ratio exceeds 5% for 5
   consecutive minutes, **When** the analysis run evaluates it, **Then**
   the rollout is automatically aborted and rolled back, and the analysis
   failure is visible in the Rollout status.
3. **Given** a canary revision whose error-rate ratio stays at or below 5%,
   **When** the analysis run evaluates it, **Then** the rollout proceeds to
   full promotion exactly as the current synthetic probe allows today.

---

### User Story 3 - Get paged in Slack when a golden signal breaches its threshold (Priority: P3)

As an on-call operator, I receive a Slack notification when a business
workload's error rate, latency, or saturation crosses an actionable
threshold, without needing to watch a dashboard.

**Why this priority**: Dashboards require someone to be looking; alerting
closes that gap. It depends on the metrics backend from User Story 1 but
delivers independent value on its own once wired.

**Independent Test**: With the metrics backend live, trigger a real
threshold breach (e.g., drive sustained errors against one workload), and
observe a message land in the configured Slack channel referencing the
affected workload and the breached signal, without simulating the
notification.

**Acceptance Scenarios**:

1. **Given** the alerting component is synchronized and healthy, **When** a
   business workload's HTTP 5xx error-rate ratio stays above 5% for 5
   consecutive minutes, **Then** a firing alert appears in the alerting
   component within that window. Latency and saturation thresholds for the
   remaining golden signals are defined per-workload during planning, using
   the same actionable, sustained-window pattern.
2. **Given** an alert is firing, **When** the configured route evaluates it,
   **Then** a message is posted to the designated Slack channel identifying
   the workload, the breached signal, and the current value.
3. **Given** the breach condition clears, **When** the next evaluation runs,
   **Then** the alert resolves and, if configured, a resolution message is
   posted to the same channel.

---

### User Story 4 - Trace a real request end-to-end for the pilot service (Priority: P4)

As a developer debugging a slow or failing request, I can find its trace in
the tracing backend and see the request's path and timing through the pilot
service, correlated with the structured log lines it produced.

**Why this priority**: Tracing proves the instrumentation pattern this
feature establishes for future services, but a working metrics-and-alerting
foundation (Stories 1-3) delivers more immediate operational value on its
own, so tracing lands after them.

**Independent Test**: Send a real request to the instrumented pilot
service, retrieve its trace by ID from the tracing backend, and confirm the
same trace ID appears in that request's structured log entry.

**Acceptance Scenarios**:

1. **Given** the pilot service is instrumented and the tracing backend is
   healthy, **When** a real request is sent to the pilot service, **Then**
   a corresponding trace appears in the tracing backend with span names and
   attributes following OpenTelemetry Semantic Conventions.
2. **Given** that request produced a trace, **When** the pilot service's
   structured log output for the same request is inspected, **Then** it
   contains the same `trace_id` and `span_id` present in the trace.
3. **Given** the pilot service previously exported spans to Zipkin,
   **When** the cutover to OpenTelemetry is complete, **Then** no code path
   in the pilot service still exports to or depends on Zipkin.

---

### User Story 5 - Search centralized, correlated logs across the platform (Priority: P5)

As an operator investigating an incident, I can search structured logs from
business workloads in a centralized log viewer, filter by workload and time
range, and pivot from a log line to its trace.

**Why this priority**: Centralized logs are valuable for investigation but
are the slowest to pay back relative to metrics, canary gating, and
alerting, and depend on the log format work already done for tracing
correlation in Story 4.

**Independent Test**: Generate a real log line from a business workload,
find it in the centralized log viewer within the expected ingestion delay,
and confirm its fields (including `trace_id` where present) are searchable
and structured, not raw unparsed text.

**Acceptance Scenarios**:

1. **Given** the log-collection component runs on every node, **When** a
   business workload writes a structured log line, **Then** it appears in
   the centralized log viewer within the expected ingestion delay with its
   fields parsed and searchable.
2. **Given** a log line originated from a traced request, **When** it is
   viewed in the centralized log viewer, **Then** its `trace_id` field
   matches the trace visible in the tracing backend for that request.
3. **Given** the log-storage component approaches its configured retention
   limit, **When** the retention policy runs, **Then** older indices are
   pruned automatically rather than the component running out of disk.

### Edge Cases

- The metrics backend itself must reconcile before any workload it monitors
  needs it — a crash-looping metrics stack must never be reported as a
  passing canary gate or silently downgrade an unrelated release to healthy.
- A business workload that has not yet been migrated to emit the expected
  metrics MUST NOT cause the metric-gated analysis to pass by default; a
  missing series is a failed check, not an absence of evidence.
- Metric and log labels MUST NOT include unbounded-cardinality values (user
  IDs, todo IDs, request IDs, full URLs with path parameters) — only
  OpenTelemetry Semantic Conventions attributes and a bounded workload/
  environment/route label set are allowed, to keep the metrics backend's
  storage bounded on a single shared cluster.
- Until every service is instrumented, a trace that crosses from the pilot
  service into a still-uninstrumented downstream service will end at that
  boundary; this MUST be visible as a broken/incomplete trace, never
  silently completed or hidden.
- The Slack webhook used by the alerting component is a credential and MUST
  arrive through External Secrets Operator, never as a value committed to
  `gitops`.
- A burst of pod restarts (e.g., during a rollout or a CI-driven redeploy)
  must not make the log pipeline drop or duplicate log lines silently;
  ingestion gaps must be observable, not invisible.
- Cutting a service over from Zipkin to OpenTelemetry MUST be an atomic,
  single-revision change per service — a service MUST NOT dual-export to
  both backends as a steady state, only transiently during the cutover
  commit's rollout.
- If the observability platform itself becomes degraded, that MUST NOT
  block GitOps reconciliation of unrelated business workloads; observability
  is additive operational insight, not a hard runtime dependency for
  services that do not depend on it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The metrics backend, dashboard component, alerting component,
  tracing backend, and log-collection/storage/viewer components MUST each
  have a complete, pinned, locally vendored installation bundle with
  upstream provenance and a verified checksum, matching the pattern already
  used for `keda`, `cert-manager`, `external-secrets`, `kyverno`, and
  `argo-rollouts`.
- **FR-002**: Every managed change to any observability component MUST enter
  through a commit to `gitops` and automatic ArgoCD reconciliation on
  `eks-dev`; no direct cluster mutation is permitted outside the existing
  audited bootstrap exception.
- **FR-003**: The metrics backend MUST scrape every business workload
  (`auth-api`, `todos-api`, `users-api`, `frontend`, `log-message-processor`)
  and MUST expose, for each, the four golden signals: latency, traffic,
  error rate, and saturation.
- **FR-004**: The dashboard component MUST provide one golden-signal
  dashboard per business workload, each populated from that workload's live
  metrics.
- **FR-005**: The existing Argo Rollouts `ClusterAnalysisTemplate` MUST be
  updated to evaluate the canary revision's real HTTP 5xx error-rate ratio
  from the metrics backend, failing the analysis when that ratio exceeds 5%
  for 5 consecutive minutes, replacing the current synthetic HTTP probe as
  the production promotion gate.
- **FR-006**: The alerting component MUST define, at minimum, an HTTP 5xx
  error-rate rule per business workload that fires when the ratio exceeds
  5% for 5 consecutive minutes, plus at least one rule for each of the
  remaining golden signals (latency, traffic, saturation) with a threshold
  and window defined per-workload during planning, and MUST route every
  firing alert to a Slack channel via a webhook delivered through External
  Secrets Operator.
- **FR-007**: The pilot business workload (`auth-api`) MUST be instrumented
  with OpenTelemetry for traces, metrics, and structured JSON logs, using
  OpenTelemetry Semantic Conventions for span and metric naming, and MUST
  remove its existing Zipkin exporter as part of the same change.
- **FR-008**: The pilot workload's structured logs MUST include `trace_id`
  and `span_id` fields matching the identifiers of the trace produced for
  the same request.
- **FR-009**: The tracing backend MUST receive and render the pilot
  workload's spans using embedded storage (no Elasticsearch backend), retain
  traces for 3 days, and retain enough trace detail to inspect individual
  request paths and per-span timing within that window.
- **FR-010**: The log-collection component MUST run cluster-wide and ship
  structured logs from business workload pods to the log-storage component;
  the log-viewer component MUST make those logs searchable by workload,
  time range, and field, including `trace_id` where present. The log stack
  MUST be Loki (reusing the metrics backend's Grafana as its log viewer),
  per the economical-profile mapping in `plan.md` section 17, not the
  full-profile ELK stack described in section 10.
- **FR-011**: The log-storage component MUST enforce an explicit 3-day
  retention policy; unbounded log retention is forbidden.
- **FR-012**: No observability component MAY introduce a service mesh or
  mTLS dependency; the economical profile's prohibition on Istio applies to
  this feature exactly as it does to existing add-ons.
- **FR-013**: Every observability component MUST be namespace-scoped and
  ArgoCD-owned per the existing `eks-dev` infrastructure registration
  mechanism, added as explicit entries to the cluster's activation list
  (no folder is auto-discovered).
- **FR-014**: Any policy that begins enforcing behavior on business
  workloads as a result of this feature (if any) MUST follow Audit-before-
  Enforce, promoted to Enforce only in a separate, reviewed revision.
- **FR-015**: Final verification MUST capture live evidence — timestamped
  observations connecting a `gitops` revision to ArgoCD status, workload
  availability, a populated dashboard query result, a firing-and-resolved
  alert, a retrievable trace, and a searchable correlated log line — never a
  claim based on rendered manifests alone.
- **FR-016**: Repository validation MUST fail on unpinned component
  versions, missing vendor checksums, unbounded-cardinality label usage,
  hard-coded Slack webhook values, or a claimed capability without
  corresponding live evidence.
- **FR-017**: Grafana, the tracing backend's UI, and the log-viewer UI MUST
  be reached only through `kubectl port-forward`, matching the existing
  local-pilot access pattern; this feature MUST NOT add a public Ingress,
  TLS certificate, or authentication/SSO integration for any observability
  UI.

### Key Entities

- **Golden-signal dashboard**: A per-workload view over latency, traffic,
  error rate, and saturation, sourced from that workload's live metrics.
- **Metric-gated analysis**: The Argo Rollouts analysis run that queries
  real metrics for a canary revision and decides whether to promote or
  automatically roll it back.
- **Alert route**: A rule that evaluates a golden-signal threshold over a
  window and, when breached, delivers a Slack notification and later a
  resolution notification.
- **Instrumented request trace**: A single request's end-to-end span tree
  in the tracing backend, correlated by `trace_id`/`span_id` with that
  request's structured log entry.
- **Correlated log entry**: A structured, searchable log line shipped from
  a business workload pod, carrying trace identifiers when the originating
  request was traced.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All observability components report synchronized and healthy
  on `eks-dev` within 10 minutes of the final commit for this feature
  reaching `gitops`.
- **SC-002**: One hundred percent of expected observability controller
  deployments report all desired replicas available, with zero pending,
  failed, or crash-looping pods at final verification.
- **SC-003**: All five business workloads have a golden-signal dashboard
  showing non-zero, traffic-driven values within one scrape interval of a
  real request being sent.
- **SC-004**: A canary revision with an injected HTTP 5xx error-rate ratio
  above 5% is automatically aborted and rolled back by the metric-gated
  analysis within 5 minutes, with zero manual intervention.
- **SC-005**: A real threshold breach produces a Slack notification within
  5 minutes of the breach starting, and its resolution produces a second
  notification once the breach clears.
- **SC-006**: A real request to the pilot workload produces a trace in the
  tracing backend whose `trace_id` matches the `trace_id` field in that
  request's structured log entry, searchable in the log viewer.
- **SC-007**: Zero code paths in the pilot workload still export to Zipkin
  after the cutover.
- **SC-008**: Every retained vendor bundle matches its recorded SHA-256
  checksum, and all repository render and validation checks pass.
- **SC-009**: Live evidence connects every success claim above to the exact
  `gitops` revision and cluster observation it was drawn from; no capability
  is reported successful from configuration alone.

## Assumptions

- This feature targets the live `eks-dev` cluster and the `dev` namespace's
  business workloads first, mirroring how platform add-ons were first proven
  on a single environment before wider rollout; extending golden-signal
  *dashboards* and alert routing to `staging`/`prod` namespaces is explicit
  follow-up work, not part of this feature's success criteria. The single
  narrow exception is User Story 2: the metric-gated canary strategy only
  exists in the `prod` overlay today (`apps/*/components/strategy-canary`),
  so scraping the `prod` `*-canary` Services with a `revision=canary` label
  is in scope for the canary gate specifically, even though `prod` is a
  structurally disabled scaffold (`replicas: 0`) with no live series yet.
- `auth-api` is the sole OpenTelemetry pilot service for this feature. The
  remaining four business workloads continue emitting whatever telemetry
  they emit today (Zipkin or none) until a follow-up feature instruments
  them individually; this feature does not claim traces or Zipkin removal
  for any service other than `auth-api`.
- Log and trace retention is fixed at 3 days, a deliberate, disclosed
  trade-off for the single shared economical-profile cluster (short,
  bounded retention rather than long-term archival), the same kind of
  trade-off already accepted for Redis's ephemeral state.
- Grafana, the tracing backend's UI, and the log-viewer UI are reached only
  via `kubectl port-forward` in this feature, matching the local-pilot
  access pattern; a public Ingress with TLS and an authentication/SSO model
  is explicit follow-up work, not part of this feature.
- The Slack channel and its incoming webhook are provisioned out-of-band by
  a human operator; this feature only wires the already-provisioned webhook
  through External Secrets Operator, it does not create the Slack channel
  or app integration itself.
- Falco, `kube-bench`, and `kube-hunter` (constitution principle 10) are out
  of scope for this feature; they remain a separate, explicitly deferred
  security capability with its own future feature spec.
- The existing curl-based `ClusterAnalysisTemplate` is superseded by the
  metric-gated version introduced in User Story 2; the feature does not
  keep both as parallel, ambiguous gates.

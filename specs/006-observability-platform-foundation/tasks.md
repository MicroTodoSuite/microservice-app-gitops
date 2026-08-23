# Tasks: Observability Platform Foundation

**Input**: Design documents from `specs/006-observability-platform-foundation/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/observability-registration.md`, `quickstart.md`

**Tests**: Required by FR-016 and by the spec's demand for live evidence
rather than configuration-only success (FR-015, SC-009).

## Phase 1: Setup (Validation First)

**Purpose**: Encode the missing behavior as failing checks before filling the
new infrastructure folders.

- [ ] T001 Create the failing pinned-version, checksum (where a bundle
  exists), immutable-image, activation-list, no-Ingress/no-Elasticsearch, and
  label-cardinality checks in `tests/contract/observability.sh`
- [ ] T002 Create the read-only composite verifier skeleton and expected
  application/controller/capability inventory in
  `scripts/managed/verify-observability.sh`
- [ ] T003 [P] Confirm `--context`/`--namespace` override support exists (or
  add it) without changing the safe default in `scripts/managed/lib/common.sh`

---

## Phase 2: Foundational (Pinned Inputs and Trust Boundary)

**Purpose**: Retain verified inputs and extend the reusable ArgoCD boundary
before any capability resource is introduced.

**CRITICAL**: No live desired-state publication occurs until the retained
Prometheus bundle passes its checksum and all five Kustomize roots render
locally.

- [ ] T004 [P] Vendor `kube-prometheus` v0.16.0 (Prometheus Operator v0.82.0,
  Prometheus v3.5.0, Alertmanager v0.28.0) with provenance and checksum under
  `infrastructure/prometheus/vendor/v0.16.0/`
- [ ] T005 [P] Record Grafana 11.7.0 image source/digest provenance in
  `infrastructure/grafana/vendor/v11.7.0/README.md` (no bundle to checksum)
- [ ] T006 [P] Record Loki 3.6.0 and Grafana Alloy 1.5.0 image source/digest
  provenance in `infrastructure/loki/vendor/v3.6.0/README.md` (no bundle to
  checksum)
- [ ] T007 [P] Record Jaeger 1.65.0 (all-in-one) image source/digest
  provenance in `infrastructure/jaeger/vendor/v1.65.0/README.md` (no bundle to
  checksum)
- [ ] T008 [P] Record OpenTelemetry Collector Contrib 0.135.0 image source/
  digest provenance in `infrastructure/otel-collector/vendor/v0.135.0/README.md`
  (no bundle to checksum)
- [ ] T009 Confirm the `microtodosuite` AppProject's exact cluster-scoped
  resource allowlist in `clusters/base/project.yaml` already covers every
  Prometheus Operator CRD/kind this bundle introduces, and add only the exact
  missing kinds if not
- [ ] T010 Verify the five-element registration contract renders correctly
  against `clusters/base/infrastructure.yaml`'s explicit `list` generator
  with `tests/contract/observability.sh`

**Checkpoint**: The Prometheus bundle matches its recorded checksum, every
other component's provenance is recorded, and the AppProject can represent
the exact pinned renders without a wildcard.

---

## Phase 3: User Story 1 - See the four golden signals for every business workload (Priority: P1)

**Goal**: A healthy metrics backend and dashboard, scraping real traffic from
all five business workloads.

**Independent Test**: Render and publish the metrics-backend desired state,
observe it reach Synced/Healthy, send real traffic to a business workload,
and see its four golden-signal panels populate with non-zero, changing
values.

### Tests for User Story 1

- [ ] T011 [P] [US1] Extend `tests/contract/observability.sh` with expected
  Deployment/StatefulSet, image digest, and `ServiceMonitor` assertions for
  `prometheus` and `grafana`

### Implementation for User Story 1

- [ ] T012 [P] [US1] Add the complete Prometheus Operator install, `Prometheus`
  and namespace-scoped RBAC resources, and immutable image transforms in
  `infrastructure/prometheus/kustomization.yaml` and
  `infrastructure/prometheus/prometheus.yaml`
- [ ] T013 [P] [US1] Add one `ServiceMonitor` per business workload
  (`auth-api`, `todos-api`, `users-api`, `frontend`, `log-message-processor`)
  targeting their existing/added metrics endpoints in
  `infrastructure/prometheus/servicemonitors/business-workloads.yaml`
- [ ] T014 [P] [US1] Add a `PrometheusRule` defining traffic/error-rate/
  latency recording rules per business workload in
  `infrastructure/prometheus/rules/golden-signals.yaml`
- [ ] T014a [US1] Add saturation recording rules once a kubelet-cAdvisor or
  kube-state-metrics scrape target is live-verified on `eks-dev` (this
  environment has no live cluster access to confirm EKS exposes a scrapeable
  kubelet endpoint the way `kube-prometheus`'s bundled ServiceMonitor
  assumes); until then, saturation is a disclosed gap in the golden-signal
  dashboards, not silently approximated
- [ ] T015 [P] [US1] Add the Grafana Deployment/Service/ConfigMap, Prometheus
  datasource, and one golden-signal dashboard per business workload
  (image pinned by digest) in `infrastructure/grafana/`
- [ ] T016 [US1] [in `auth-api` repo] Add a request-duration Histogram
  alongside the existing `auth_api_requests_total` Counter in `main.go`,
  exposed on the existing `/metrics` endpoint
- [ ] T017 [US1] [in `todos-api` repo] Add a request-duration Histogram
  alongside the existing `todo_api_requests_total` Counter in `server.js`,
  exposed on the existing `/metrics` endpoint
- [ ] T018 [US1] [in `frontend` repo] Add an `nginx-prometheus-exporter`
  sidecar container to the Deployment overlay, without modifying the
  hardened `Dockerfile` or `nginx.conf.template` from the prior hardening work
- [ ] T019 [US1] Complete wait loops, dashboard-query evidence capture, and
  controller/availability checks for `prometheus` and `grafana` in
  `scripts/managed/verify-observability.sh`
- [ ] T020 [US1] Make the static contract pass for both rendered roots with
  `tests/contract/observability.sh`
- [ ] T021 [US1] Publish the Prometheus and Grafana installation desired
  state as staged commits on `feat/observability-platform-foundation`, open a
  PR, and after merge wait for both infrastructure Applications and all five
  `ServiceMonitor` targets to become Synced/Healthy/Up without direct cluster
  mutation

**Checkpoint**: All five business workloads have a live, traffic-driven
golden-signal dashboard.

---

## Phase 4: User Story 2 - Gate production canaries on real metrics instead of a synthetic probe (Priority: P2)

**Goal**: Replace the curl-based canary health check with a real Prometheus
error-rate gate.

**Independent Test**: Inject an elevated error rate into a canary revision
and confirm Argo Rollouts aborts and rolls it back automatically within 5
minutes; confirm a normal-error-rate canary still promotes.

### Tests for User Story 2

- [ ] T022 [P] [US2] Add PromQL-provider, threshold, and window assertions
  (5xx ratio > 5% over 5 minutes) to `tests/contract/observability.sh` for
  `infrastructure/argo-rollouts/cluster-analysis-template.yaml`

### Implementation for User Story 2

- [x] T023 [US2] Replace the `job`/curl provider in the
  `ClusterAnalysisTemplate` with a Prometheus provider querying the canary
  revision's 5xx-to-total ratio in
  `infrastructure/argo-rollouts/cluster-analysis-template.yaml`
- [x] T023a [US2] Label the five `*-canary` Services and add matching
  `ServiceMonitor`s with a `revision=canary` relabel so the canary query has
  a series to read; group the golden-signal recording rules by
  `(workload, revision)` accordingly
- [ ] T024 [US2] Publish the updated `ClusterAnalysisTemplate` as its own
  commit (done: `feat(canary): gate promotion on real Prometheus error rate`
  on `feat/observability-canary-and-alerting`) and wait for it to render and
  sync cleanly before any canary exercises it (live eks-dev step, not run
  from this environment)
- [ ] T025 [US2] Stage a fault-injection test path for one business workload's
  canary revision (elevated 5xx ratio, feature-flagged) and record the
  Rollout's automatic abort/rollback timing as evidence
- [ ] T026 [US2] Confirm a canary revision at or below the 5% threshold still
  promotes normally, and record that as evidence alongside the abort case

**Checkpoint**: Production canaries are gated by a real golden signal, not a
synthetic connectivity probe.

---

## Phase 5: User Story 3 - Get paged in Slack when a golden signal breaches its threshold (Priority: P3)

**Goal**: Firing and resolved Slack notifications for real threshold
breaches.

**Independent Test**: Drive a real, sustained error-rate breach against one
workload and observe a Slack message referencing the workload and signal,
followed by a resolution message once the breach clears.

### Tests for User Story 3

- [x] T027 [P] [US3] Add `AlertmanagerConfig`/route, ESO-secret-reference, and
  no-hard-coded-webhook assertions to `tests/contract/observability.sh`

### Implementation for User Story 3

- [x] T028 [P] [US3] Add the `ExternalSecret` referencing the pre-provisioned
  Slack webhook (delivered via ESO, never a literal value) in
  `infrastructure/prometheus/alertmanager-config.yaml`. The `SecretStore`
  behind it uses the same explicit, clearly-marked placeholder IRSA role ARN
  already used by `environments/base/external-secrets-serviceaccount.yaml`
  (not real yet; needs the actual IAM role from `microservice-app-ops`).
- [x] T029 [US3] Add the `AlertmanagerConfig` Slack route and error-rate/
  latency alert rules (error-rate fully specified at 5%/5min per the
  Clarifications session; latency uses a starting-default 1s threshold, not
  a measured baseline) in `infrastructure/prometheus/rules/golden-signals.yaml`
  and `infrastructure/prometheus/alertmanager-config.yaml`. Traffic and
  saturation alert rules remain follow-up work (saturation has no metric
  source yet per T014a).
- [ ] T030 [US3] Complete alert-firing/resolution evidence capture in
  `scripts/managed/verify-observability.sh`
- [ ] T031 [US3] Publish the Alertmanager routing commit on
  `feat/observability-platform-foundation`, wait for it to sync, and drive a
  real breach-and-recovery test against one workload, recording both Slack
  notifications as evidence

**Checkpoint**: A real threshold breach reaches an on-call operator without
anyone watching a dashboard.

---

## Phase 6: User Story 4 - Trace a real request end-to-end for the pilot service (Priority: P4)

**Goal**: `auth-api` requests are traceable end-to-end, correlated with
structured logs, with Zipkin fully removed.

**Independent Test**: Send a real request to `auth-api`, retrieve its trace
by ID in Jaeger, and confirm the same `trace_id` appears in that request's
structured log line.

### Tests for User Story 4

- [ ] T032 [P] [US4] Add OTLP-receiver, Jaeger-exporter, and no-Zipkin-
  dependency assertions to `tests/contract/observability.sh` for
  `infrastructure/otel-collector/` and `infrastructure/jaeger/`

### Implementation for User Story 4

- [ ] T033 [P] [US4] Add the Jaeger all-in-one Deployment with Badger PVC
  (3-day retention) and immutable image transform in
  `infrastructure/jaeger/jaeger-allinone.yaml`
- [ ] T034 [P] [US4] Add the OpenTelemetry Collector Deployment (OTLP
  receiver, Prometheus exporter, Jaeger OTLP exporter) and immutable image
  transform in `infrastructure/otel-collector/collector-config.yaml` and
  `infrastructure/otel-collector/deployment.yaml`
- [ ] T035 [US4] [in `auth-api` repo] Replace `tracing.go`'s Zipkin exporter
  with an OpenTelemetry Go SDK + OTLP exporter in a new `otel.go`, using
  OpenTelemetry Semantic Conventions for span names/attributes, and remove
  the Zipkin dependency from `go.mod`
- [ ] T036 [US4] [in `auth-api` repo] Emit structured JSON logs carrying
  `trace_id`/`span_id` for every request, replacing any unstructured log
  output in `main.go`
- [ ] T037 [US4] Add the `OTEL_EXPORTER_OTLP_ENDPOINT` env-var patch pointing
  `auth-api` at the in-cluster Collector Service in
  `apps/auth-api/overlays/dev/kustomization.yaml`
- [ ] T038 [US4] Complete trace-retrieval and Semantic-Convention-attribute
  evidence capture in `scripts/managed/verify-observability.sh`
- [ ] T039 [US4] Publish the Jaeger and OTel Collector installation commits,
  then the `auth-api` cutover commit (in its own repository/PR), and verify a
  real request produces a retrievable trace with zero remaining Zipkin
  code paths

**Checkpoint**: `auth-api` is fully cut over from Zipkin to OpenTelemetry,
proving the instrumentation pattern for future services.

---

## Phase 7: User Story 5 - Search centralized, correlated logs across the platform (Priority: P5)

**Goal**: Structured, searchable, trace-correlated logs across the platform,
with bounded retention.

**Independent Test**: Generate a real log line from a business workload, find
it in Grafana's Loki explore view within the expected ingestion delay, and
confirm its `trace_id` (where present) matches the corresponding Jaeger
trace.

### Tests for User Story 5

- [ ] T040 [P] [US5] Add DaemonSet-coverage, 3-day-retention, and
  no-unbounded-cardinality-label assertions to `tests/contract/observability.sh`
  for `infrastructure/loki/`

### Implementation for User Story 5

- [ ] T041 [US5] Add the Loki single-binary StatefulSet, 3-day retention
  configuration, PVC, and immutable image transform in
  `infrastructure/loki/loki.yaml`
- [ ] T042 [US5] Add the Grafana Alloy DaemonSet shipping business-workload
  pod logs to Loki, with immutable image transform, in
  `infrastructure/loki/alloy.yaml`
- [ ] T043 [US5] Add the Loki datasource to Grafana (reusing the existing
  Grafana instance as the log viewer, per the Clarifications decision) in
  `infrastructure/grafana/datasources.yaml`
- [ ] T044 [US5] Complete log-search and trace/log-correlation evidence
  capture in `scripts/managed/verify-observability.sh`
- [ ] T045 [US5] Publish the Loki installation commit on
  `feat/observability-platform-foundation`, wait for it to sync, and confirm
  a real log line is searchable and correlates by `trace_id` with its Jaeger
  trace

**Checkpoint**: An operator can search real logs and pivot to a trace without
leaving Grafana.

---

## Phase 8: Polish & Cross-Cutting Validation

**Purpose**: Re-run every static and live acceptance path and reconcile the
request against exact evidence.

- [ ] T046 Run `kustomize build` and `kubeconform` (when available) for all
  five components plus the updated `eks-dev` registration, run
  `tests/contract/observability.sh`, and run `git diff --check`
- [ ] T047 Run `scripts/managed/verify-observability.sh --context eks-dev
  --namespace microtodo-dev`, inspect ArgoCD application conditions and
  component logs for hidden degradation, and retain the final evidence set
  under `evidence/runs/<timestamp>-observability/`
- [ ] T048 Compare the pre-change baseline with the final live revision, five
  component statuses, controller availability, dashboard query results,
  canary abort/promote outcomes, alert firing/resolution, and trace/log
  correlation against FR-001 through FR-017 and SC-001 through SC-009 in
  `specs/006-observability-platform-foundation/checklists/acceptance.md`
- [ ] T049 Update `docs/platform-addons.md` or add
  `docs/observability-platform.md` documenting the five new components, the
  economical-profile Loki/Jaeger substitution, and the port-forward-only
  access model, mirroring how `003-platform-addons` documented its boundary

---

## Dependencies & Execution Order

### Phase dependencies

```text
Setup validation
    -> Pinned inputs and trust boundary
        -> US1 golden-signal dashboards (metrics backend must exist first)
            -> US2 metric-gated canary (needs US1's Prometheus + ServiceMonitors)
            -> US3 Slack alerting (needs US1's Prometheus + PrometheusRule)
                -> US4 tracing (independent of US2/US3, but after US1)
                    -> US5 logs (needs US4's trace_id convention for correlation)
                        -> Final static and live acceptance
```

- T001-T003 establish the validation and verifier plumbing.
- T004-T010 block every live publication.
- US1 (T011-T021) must land and be healthy before US2 or US3, since both
  query the Prometheus instance and `ServiceMonitor`/`PrometheusRule`
  resources US1 creates.
- US2 and US3 do not depend on each other and may proceed in parallel once
  US1 is healthy.
- US4 depends only on US1 being healthy (it needs the same Prometheus
  instance for its own metrics export path), not on US2/US3.
- US5 depends on US4 for the `trace_id` log-correlation convention
  (`auth-api`'s structured logging change in T036), so it is sequenced last.
- T046-T049 run only after the final source revision is healthy.

## Parallel Opportunities

```text
T004 Prometheus vendor || T005 Grafana provenance || T006 Loki/Alloy provenance || T007 Jaeger provenance || T008 OTel Collector provenance
T012 Prometheus root   || T015 Grafana root
T016 auth-api histogram || T017 todos-api histogram || T018 frontend sidecar
T033 Jaeger root       || T034 OTel Collector root
```

Tasks that publish commits to `eks-dev` or observe the shared live cluster
remain sequential within their own story.

## Implementation Strategy

**MVP scope**: User Story 1 alone (golden-signal dashboards) is a complete,
independently valuable increment — it closes the constitution's disclosed
"Prometheus/Grafana... not active on EKS" gap by itself, even before the
canary gate, alerting, tracing, or logs land.

1. Encode contract failures first.
2. Retain the Prometheus bundle checksum and record provenance for the
   hand-authored components.
3. Land User Story 1 and confirm live, traffic-driven dashboards for all
   five workloads — this is the foundation every later story queries.
4. Land User Story 2 (canary gate) and User Story 3 (alerting) in either
   order, or in parallel, once US1 is healthy.
5. Land User Story 4 (tracing) once US1 is healthy.
6. Land User Story 5 (logs) last, since it depends on US4's `trace_id`
   convention for correlation.
7. Close with full static and live acceptance evidence against every FR/SC.

## Notes

- This task list only authorizes commits on the short-lived
  `feat/observability-platform-foundation` branch (Trunk-Based Development);
  merge to `main` happens through a reviewed PR, never a direct push.
- `auth-api`, `todos-api`, and `frontend` code/overlay changes are scoped to
  their own repositories and their own short-lived branches; this repository
  only carries the GitOps-side registration and the overlay env-var patch.
- Missing or failed live evidence remains a failure; it must not be converted
  to a pass based on rendered configuration alone.
- No task in this list modifies `microservice-app-frontend`'s hardened
  `Dockerfile` or `nginx.conf.template` from the prior hardening work (T018
  adds a sidecar container only).

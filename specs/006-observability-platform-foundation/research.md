# Research: Observability Platform Foundation

## Existing instrumentation baseline (found in the repositories, not assumed)

**Decision**: Treat metrics collection as "wire up scraping for what already
exists, then close two small, specific gaps" rather than "add Prometheus
client libraries to five services from scratch."

**Rationale**: Direct inspection of each service repository shows four of
five business workloads already expose real Prometheus metrics:

| Service | Existing metrics | Traffic/errors | Latency | Gap |
| --- | --- | --- | --- | --- |
| `auth-api` | `prometheus/client_golang` v1.24.1, `/metrics`, `auth_api_requests_total{method,status}` CounterVec | Yes | No histogram | Add a request-duration Histogram |
| `todos-api` | `prom-client` 15.1.3, `/metrics`, `todo_api_requests_total{method,status}` Counter + default Node.js metrics | Yes | No histogram | Add a request-duration Histogram |
| `users-api` | Spring Boot Actuator + Micrometer (`micrometer-registry-prometheus`), endpoint at `/prometheus` (custom `management.endpoints.web.base-path=/`) | Yes | Yes (`http_server_requests_seconds` is automatic with Micrometer) | None |
| `log-message-processor` | `prometheus_client` 0.26.0, `log_messages_processed_total`/`log_messages_failed_total` Counters, `log_message_processing_duration_seconds` Histogram | Yes (as messages processed) | Yes | None |
| `frontend` | None in the current Dockerfile/nginx config | No | No | Needs an `nginx-prometheus-exporter` sidecar (already anticipated in `microservice-app-docs`'s own architecture notes, which describe "an nginx Prometheus exporter" as part of the implemented diagram) |

This also confirms `users-api` already runs Micrometer Tracing with a Brave
(Zipkin-format) bridge at 100% sampling (`management.tracing.sampling.
probability=1.0`), consistent with the suite-wide "everything speaks Zipkin
today" baseline this feature starts to retire, one service at a time,
starting with `auth-api`.

**Alternatives considered**: Instrumenting all five services with the full
OpenTelemetry SDK in this feature was rejected — the spec's Assumptions
section scopes OpenTelemetry tracing to the `auth-api` pilot only, and
reworking four already-working metrics integrations would be unrequested
scope creep with real regression risk against services that are otherwise
untouched. Adding only a Histogram (not a rewrite) to `auth-api`/`todos-api`
and a sidecar (not a code change) to `frontend` is the minimal change that
satisfies FR-003's four-golden-signal requirement for every workload.

## Metrics and alerting stack

**Decision**: `kube-prometheus` (the plain-YAML manifest project, not a Helm
chart) for Prometheus Operator + Prometheus + Alertmanager as CRDs.

**Rationale**: This project's established pattern (`cert-manager`, `kyverno`,
`external-secrets`, `keda`) is a single vendored upstream release bundle of
raw Kubernetes YAML, never Helm. `kube-prometheus` is the one CNCF-adjacent
project that ships Prometheus Operator, Prometheus, and Alertmanager as a
single tagged-release manifest set, matching that exact pattern, unlike the
`kube-prometheus-stack` Helm chart. Node-exporter and kube-state-metrics
(also bundled by `kube-prometheus`) are out of scope for this feature — the
spec's golden signals are workload-level, not node/cluster-level — and are
excluded from the vendored subset, noted as explicit future scope.

**Alternatives considered**: A hand-rolled Prometheus `Deployment` without
the Operator was rejected because `ServiceMonitor`/`PodMonitor`/`Alertmanager
Config` CRDs are the standard, most-recommended way to declare scrape targets
and alert routing declaratively and are what the canary `AnalysisTemplate`
(Argo Rollouts' own documented integration point) expects to query against.

## Grafana

**Decision**: Hand-authored `Deployment`/`Service`/`ConfigMap` manifests
(dashboards and datasources provisioned via ConfigMap, not the Grafana
Operator), image pinned by digest.

**Rationale**: Grafana has no equivalent single-file upstream release bundle
(it is normally installed via Helm or the Grafana Operator, both heavier
than this project's pattern). A plain `Deployment` with provisioning
ConfigMaps is the simplest option consistent with the project's no-Helm,
digest-pinned convention, and is exactly the same shape already used for
`infrastructure/redis/` in this repository.

## Logs: Loki, not ELK

**Decision**: Loki 3.6.0 in single-binary (monolithic) mode, with Grafana
Alloy as the log-shipping DaemonSet, and Grafana (already deployed for
metrics) reused as the log viewer.

**Rationale**: Resolved directly by the Clarifications session against
`plan.md` section 17's own economical-profile table, which names this exact
substitution (Loki reusing Grafana, replacing ELK) as the intended mapping
once the cost-optimized profile is adopted — which `constitution.md` v2.0.0
already did.

**Alternatives considered**: Promtail (Loki's historically bundled shipper)
was rejected in favor of Grafana Alloy because Promtail is in maintenance
mode upstream and Alloy is the actively maintained, currently recommended
replacement for new Loki deployments — the more current, better-supported
choice for a project that already treats "verify against what's actually
current" as a hard rule (see the Dockerfile-hardening table's repeated
"documented version didn't build/run" findings).

## Traces: Jaeger with embedded storage, not Elasticsearch

**Decision**: Jaeger 1.65.0 deployed all-in-one (collector, query, and UI in
one process), using Badger embedded storage on a PVC, not the Jaeger Operator
and not an Elasticsearch storage backend.

**Rationale**: Also resolved directly against `plan.md` section 17's
economical-profile row for traces ("Jaeger con almacenamiento embebido y
retención corta"). The Jaeger Operator and per-component (collector/query/
ingester) deployment model exist to scale traces independently at a volume
this single-pilot-service feature does not have; all-in-one is the
documented, supported Jaeger deployment mode for exactly this scale.

## Trace bridge: direct to Jaeger, no separate Collector

**Decision (amended during implementation)**: `auth-api` exports OTLP
directly to Jaeger's own OTLP receiver; no standalone OpenTelemetry Collector
`Deployment` is introduced.

**Original plan and why it changed**: The initial design (above sections)
called for a Collector in front of Jaeger, on the standard argument that it
decouples services from any one backend's wire format. Checking Jaeger's
actual current release during implementation (`docker buildx imagetools
inspect jaegertracing/jaeger:2.20.0`, and its real Dockerfile/config from the
`v2.20.0` tag) showed that Jaeger 2.x **is itself built on the OpenTelemetry
Collector core** and receives OTLP natively (`receivers: [otlp]` in its own
config) - the exact decoupling a separate Collector would add is already
inside Jaeger. Adding another Collector in front of it would just be an
OTLP-to-OTLP hop with no behavior difference, which contradicts the
economical profile's bias toward fewer components. Metrics do not need a
Collector either: `auth-api`'s `/metrics` endpoint is already scraped
directly by a `ServiceMonitor`, independent of the tracing path (see the
metrics-stack sections above), so nothing was bridging metrics through OTLP
in the first place.

**Future-service note**: if a later service's runtime cannot easily export
OTLP directly (e.g. it can only speak Zipkin natively, or several services
need shared sampling/redaction processing), reintroducing a Collector at
that point is a small, additive change - it does not require touching this
feature's Jaeger deployment.

## Canary gate: HTTP 5xx error-rate query

**Decision**: The `ClusterAnalysisTemplate`'s Job-based curl probe is replaced
with a Prometheus provider query: the ratio of 5xx to total requests for the
canary revision's `ServiceMonitor` labels, over a 5-minute window, failing at
5% per the Clarifications session.

**Rationale**: Argo Rollouts' Prometheus analysis provider is its
documented, most common metric-gated pattern; a `promql` ratio query over
labels Argo Rollouts already injects (`rollouts-pod-template-hash`) needs no
new instrumentation beyond what FR-003 already requires every workload to
expose.

**Alternatives considered**: Keeping the curl probe as a secondary check
alongside the metric gate was rejected per the spec's own Assumption that the
curl-based template is superseded, not run in parallel — two gates with
different failure semantics would make canary failures harder to diagnose,
not easier.

## Namespace and registration model

**Decision**: One new `observability` namespace hosts every component from
this feature; four separate ArgoCD Applications (`prometheus`, `grafana`,
`loki`, `jaeger`) are appended to `clusters/eks-dev/
activation-infrastructure.yaml`'s explicit element list.

**Rationale**: A single namespace keeps RBAC/NetworkPolicy surface small,
consistent with the cost-optimized profile's preference for fewer moving
parts, while five separate Applications preserve the existing 1:1
Application-to-capability granularity every other add-on in this repo
already uses (so a future `speckit-converge` pass or a rollback of one
component never has to disentangle it from the others).

# Data Model: Observability Platform Foundation

This repository stores desired state rather than business records. The
feature has six reviewable entities and explicit state transitions.

## ObservabilityComponent

Represents one GitOps-managed platform capability from this feature.

| Field | Meaning | Validation |
| --- | --- | --- |
| `name` | Stable folder and application identity | One of `prometheus`, `grafana`, `loki`, `jaeger` |
| `namespace` | Shared platform namespace | Equal to `observability` for all five |
| `release` | Pinned upstream version | Concrete version; no range or floating alias (see `plan.md` Technical Context for the five pins) |
| `bundlePath` | Retained install manifest, where a genuine upstream bundle exists | Under `infrastructure/prometheus/vendor/<release>/` only; `grafana`, `loki`, and `jaeger` are hand-authored (no upstream raw-YAML bundle exists for any of them outside Helm/an operator) and carry a provenance-only `vendor/<release>/README.md` instead |
| `bundleChecksum` | Download/render integrity, where a bundle exists | Lowercase SHA-256 matching the retained bytes (`prometheus` only) |
| `images` | Runtime artifacts | Every rendered image is pinned by immutable SHA-256 digest |
| `controllers` | Expected Deployments/StatefulSets/DaemonSets | Non-empty and fully Available at acceptance |

State transition:

```text
Pinned -> Rendered -> Committed -> Argo Synced -> Controllers Available
```

## BusinessWorkloadMetrics

Represents one business workload's contribution to the golden-signal
requirement (FR-003). Distinct from `ObservabilityComponent`: this entity
tracks existing/added instrumentation in service repositories this feature
does not own outright, only references.

| Field | Meaning | Validation |
| --- | --- | --- |
| `workload` | Service identity | One of `auth-api`, `todos-api`, `users-api`, `frontend`, `log-message-processor` |
| `metricsEndpoint` | Where Prometheus scrapes it | `/metrics` (`auth-api`, `todos-api`), `/prometheus` (`users-api`), its own metrics port (`log-message-processor`), the `nginx-prometheus-exporter` sidecar port (`frontend`) |
| `trafficSignal` | Counter already present or added | Present today for all five (four native, one via sidecar) |
| `errorSignal` | Error-rate label already present or added | Present today for all five |
| `latencySignal` | Histogram already present or added | Present today for `users-api`, `log-message-processor`; added by this feature for `auth-api`, `todos-api`; provided by the exporter for `frontend` |
| `saturationSignal` | Resource-usage signal | Sourced from container `resources.requests`/`limits` already declared in each Deployment, not new application code |
| `scrapeTarget` | How Prometheus finds it | One `ServiceMonitor` per workload in `infrastructure/prometheus/servicemonitors/` |

State transition:

```text
Metrics Endpoint Exists -> ServiceMonitor Scrapes It -> Series Non-Empty
        -> Golden-Signal Dashboard Panel Populated
```

A workload that never reaches "Series Non-Empty" under real traffic fails
SC-003 for that workload; a missing signal is a defect, not an acceptable
gap, once this feature claims that workload's dashboard is live.

## MetricGatedAnalysis

Represents the Argo Rollouts canary gate this feature upgrades.

| Field | Meaning | Validation |
| --- | --- | --- |
| `metric` | Query name | `canary-error-rate` |
| `provider` | Analysis backend | Prometheus (replaces the existing `job`/curl provider) |
| `query` | PromQL expression | 5xx-to-total request ratio for the canary revision's labels |
| `threshold` | Failure boundary | `> 0.05` |
| `window` | Sustained-breach duration | 5 minutes |
| `failureLimit` | Consecutive failures before abort | Matches the existing template's `failureLimit: 0` semantics — first breach fails the run |

State transition:

```text
Canary Pod Serving Traffic -> Metric Scraped -> Query Evaluated
        -> (Pass -> Promote) | (Fail -> Abort and Roll Back)
```

## AlertRoute

Represents one Alertmanager routing rule delivering a golden-signal breach to
Slack.

| Field | Meaning | Validation |
| --- | --- | --- |
| `workload` | Affected business workload | One of the five business workloads |
| `signal` | Which golden signal | `error-rate` (this feature defines the concrete rule), `latency`/`traffic`/`saturation` (thresholds defined per-workload during implementation, same routing mechanism) |
| `threshold`/`window` | Firing condition | `error-rate`: ratio `> 0.05` sustained 5 minutes |
| `receiver` | Delivery channel | Slack, via a webhook URL sourced from an `ExternalSecret`, never a literal value in Git |
| `resolvedNotification` | Recovery message | Enabled (Alertmanager's default `resolved` notification behavior) |

State transition:

```text
Rule Loaded -> Threshold Breached -> Alert Firing -> Slack Message Sent
        -> Breach Clears -> Alert Resolved -> Slack Resolution Sent
```

## InstrumentedTrace

Represents one `auth-api` request's trace, owned by the `auth-api`
repository's code but observed here through the tracing backend.

| Field | Meaning | Validation |
| --- | --- | --- |
| `traceId`/`spanId` | OpenTelemetry identifiers | Present in both the Jaeger-rendered trace and the corresponding structured log line |
| `spanName` | Per OpenTelemetry Semantic Conventions | e.g. `GET /login`, not a raw internal function name |
| `attributes` | Semantic Convention attributes only | No unbounded-cardinality values (user/todo/request IDs); see FR edge case on cardinality |
| `exportPath` | Where the span travels | `auth-api` SDK → OTLP → Jaeger (received natively; Jaeger 2.x is itself built on the OpenTelemetry Collector core, no separate Collector needed) |

## ReconciliationEvidence

An untracked, timestamped observation set produced by the verifier, mirroring
`003-platform-addons`'s evidence shape.

| Field | Meaning |
| --- | --- |
| `expectedRevision` | SHA at the `gitops` source ArgoCD reconciled |
| `applications` | App name, source revision, sync, and health for all five components |
| `deployments` | Desired, ready, and available replicas per expected controller |
| `dashboardQuery` | A real Prometheus/Grafana query result reflecting live traffic, per business workload |
| `canaryTest` | The injected-error-rate canary run's abort/rollback outcome |
| `alertTest` | The fired-and-resolved Slack notification pair |
| `traceLookup` | A retrieved Jaeger trace and its matching Loki log line by `trace_id` |

State transition:

```text
Started -> Revision Matched -> Applications Healthy -> Controllers Available
        -> Dashboards Populated -> Canary Test Passed -> Alert Test Passed
        -> Trace/Log Correlation Confirmed -> Complete
```

Evidence remains incomplete if any intermediate state times out or a claim
cannot be traced back to a live observation.

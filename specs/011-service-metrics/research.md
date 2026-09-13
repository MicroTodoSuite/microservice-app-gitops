# Research: Service Metrics Through OpenTelemetry

## Current state

| Service | Instrumentation today | Series read by rules, dashboard, or canary |
| --- | --- | --- |
| `auth-api` (Go) | `client_golang` v1.24.1 `CounterVec`/`HistogramVec` on the default registry, served by `promhttp.Handler()` | `auth_api_requests_total{method,status}`, `auth_api_request_duration_seconds_{sum,count}{method}` |
| `todos-api` (Node.js) | `prom-client` 15.1.3 on its own `Registry`, plus `collectDefaultMetrics({prefix: 'todos_api_'})` | `todo_api_requests_total{method,status}`, `todo_api_request_duration_seconds_{sum,count}{method}` |
| `log-message-processor` (Python) | `prometheus_client` 0.26.0 `Counter`/`Histogram` on the default `REGISTRY`, served by `generate_latest()` | `log_messages_processed_total`, `log_messages_failed_total`, `log_message_processing_duration_seconds_{sum,count}` |
| `users-api` (Java) | Micrometer Prometheus registry | `http_server_requests_seconds_{sum,count}{job="users-api",status}` |
| `frontend` (nginx) | `nginx-prometheus-exporter` sidecar | `nginx_http_requests_total{job="frontend",status}` |

The recording rules in `infrastructure/prometheus/rules/golden-signals.yaml`
read only the series above; the dashboard reads the recording rules; the
canary gate (`infrastructure/argo-rollouts/cluster-analysis-template.yaml`)
reads `workload:http_errors:ratio5m`. No query reads a runtime series
(`go_*`, `process_*`, `python_*`, `todos_api_*`).

## R1. Pull through the OpenTelemetry Prometheus exporter on the existing endpoint

**Decision**: Each migrated service records through an OpenTelemetry
`MeterProvider` whose reader is the language's OpenTelemetry Prometheus
exporter, and serves it on its current `/metrics` route and port:

- `auth-api`: `go.opentelemetry.io/otel/exporters/prometheus` v0.67.0 with
  `WithRegisterer(<own prometheus.Registry>)`, `WithoutScopeInfo()`, and
  `WithoutTargetInfo()`; `/metrics` serves `promhttp.HandlerFor` that registry.
  v0.67.0 is the release whose `go.mod` requires `go.opentelemetry.io/otel`
  v1.45.0, `sdk/metric` v1.45.0, and `client_golang` v1.24.1, the versions
  `auth-api` already uses (v0.68.0 requires v1.46.0).
- `todos-api`: `@opentelemetry/exporter-prometheus` 0.222.0 (depends on
  `@opentelemetry/sdk-metrics` 2.11.0, `core` and `resources` 2.11.0) with
  `preventServerStart: true`, `withoutScopeInfo: true`, and
  `withoutTargetInfo: true`; the Express `/metrics` route calls
  `exporter.getMetricsRequestHandler(req, res)`.
- `log-message-processor`: `opentelemetry-exporter-prometheus` 0.65b0
  (requires `opentelemetry-sdk` ~=1.44.0 and `prometheus-client` <1.0) with
  `PrometheusMetricReader(disable_target_info=True, scope_info_enabled=False,
  registry=<own CollectorRegistry>)`; the existing HTTP handler serves
  `generate_latest(<that registry>)`.

**Rationale**: Clarifications 2026-09-13 chose pull, which keeps the
ServiceMonitors, network policies, and Prometheus configuration untouched
(FR-002). Every option named above was read from the exporters' sources at
those versions (`exporters/prometheus/config.go`,
`opentelemetry-exporter-prometheus/src/export/types.ts`,
`opentelemetry/exporter/prometheus/__init__.py`).

**Alternatives considered**: Pushing OTLP to Prometheus's receiver
(`enableOTLPReceiver`, supported by Prometheus Operator v0.92.0 and
Prometheus 3.12), rejected by the maintainer because it changes Prometheus,
network policies, ServiceMonitors, and the translated names and labels.

## R2. Series names

**Decision**: Instruments are named so the exposition matches
`contracts/preserved-series.md` exactly: counters without the `_total` suffix
(the exporter appends it) and histograms named with their `_seconds` base
name and unit `s`. The failing tests (FR-012) assert the exposition text
itself, so any exporter naming behavior that differs (a duplicated unit
suffix, a missing `_total`) fails before the implementation lands.

**Rationale**: The exposition text is the contract the recording rules read;
testing the rendered text is stronger than trusting naming rules.

## R3. Histogram bucket boundaries

**Decision**: Explicit-bucket views keep today's boundaries:

- `auth-api` and `todos-api`: `[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]`
  (`client_golang` v1.24.1 `DefBuckets` and `prom-client` 15.1.3 defaults).
- `log-message-processor`: `[0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1, 2.5, 5, 7.5, 10]`
  (`prometheus_client` 0.26.0 `DEFAULT_BUCKETS`, without `+Inf`, which the
  exposition adds).

**Rationale**: OpenTelemetry's default explicit boundaries are different, so
without views every `_bucket` series would change (FR-003).

## R4. Labels

**Decision**: Attributes are exactly `method` and `status` (strings) on the
request counters and `method` on the duration histograms, as today; scope
labels (`otel_scope_*`) and `target_info` are disabled (R1); no resource
attribute becomes a label.

**Rationale**: FR-004. With them disabled, the preserved series carry the
same label sets as today.

## R5. Runtime metrics are dropped

**Decision**: `todos-api` removes `prom-client` and its default metrics;
`auth-api` serves its own registry, so `go_*` and `process_*` are no longer
exposed; `log-message-processor` serves its own `CollectorRegistry`, so the
default `REGISTRY`'s process, platform, and GC collectors are no longer
exposed.

**Rationale**: Clarifications 2026-09-13; no query reads them.

## R6. Business metrics

**Decision**:

- `todos-api`: counters `todo_api_todos_created_total` and
  `todo_api_todos_deleted_total`, with no attributes. The created count
  increases after the todo is stored, right before the handler answers. The
  deleted count increases only when the id existed before the deletion;
  deleting a missing id still answers 204, as today, but is not counted.
- `auth-api`: counter `auth_api_sign_ins_total` with one attribute, `outcome`,
  `accepted` when the handler returns the token and `rejected` when the login
  fails with `ErrWrongCredentials` (HTTP 401). Any other error (HTTP 500) is
  not counted.

**Rationale**: FR-006 to FR-008. Both handlers sit behind the JWT or login
routes, so probes and scrapes never reach them. The only label has two
values, and no identity is recorded.

## R7. Business row

**Decision**: `infrastructure/grafana/dashboards/golden-signals.yaml` gains a
`row` panel titled `Business` and two time-series panels: todos created and
deleted per five minutes (`sum(increase(todo_api_todos_created_total[5m]))`,
`sum(increase(todo_api_todos_deleted_total[5m]))`) and sign-ins per five
minutes by outcome (`sum by (outcome) (increase(auth_api_sign_ins_total[5m]))`).
They do not use the `$workload` variable. No alert rule is added.

**Rationale**: Clarifications 2026-09-13 (a row in the existing dashboard, no
alert); `increase` tolerates counter resets on pod restarts.

## R8. Documented exceptions

**Decision**: `users-api` keeps Micrometer and `frontend` keeps
`nginx-prometheus-exporter`; neither repository changes.

**Rationale**: Clarifications 2026-09-13. Micrometer is Spring Boot's
instrumentation facade and already feeds OpenTelemetry tracing through the
Micrometer Tracing bridge; nginx has no OpenTelemetry metrics module
(`ngx_otel_module` emits traces only).

## R9. Tracing stays separate

**Decision**: Metrics setup lives in its own module (`metrics.go`,
`metrics.js`, a metrics section in `main.py`) with its own `MeterProvider`;
the tracer providers from spec 010 are not touched.

**Rationale**: FR-011.

## R10. Validation

**Decision**: Each service repository adds a failing test first that renders
its `/metrics` output and asserts the preserved names, labels, bucket
boundaries, the absence of runtime and scope series, that no source file
records through the Prometheus client API, and (for `auth-api` and
`todos-api`) the business counts. This repository extends
`tests/contract/observability.sh` to require the Business row and its three
queries in the rendered Grafana root.

**Rationale**: FR-012; the same test-first pattern specs 008 and 010 used.

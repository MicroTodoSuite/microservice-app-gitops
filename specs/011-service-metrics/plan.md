# Implementation Plan: Service Metrics Through OpenTelemetry

**Branch**: `docs/service-metrics-spec` | **Date**: 2026-09-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/011-service-metrics/spec.md`

## Summary

Plan section 10 requires OpenTelemetry as each service's single
instrumentation layer and technical and business metrics in Prometheus and
Grafana. Spec 010 moved tracing; this feature moves the metrics of
`auth-api`, `todos-api`, and `log-message-processor` from their Prometheus
client libraries to the OpenTelemetry metrics API, served on the same
`/metrics` endpoints through the OpenTelemetry Prometheus exporter, so the
existing ServiceMonitors, recording rules, dashboard, and canary gate keep
reading the same series. It adds todos created and deleted (`todos-api`) and
sign-ins accepted and rejected (`auth-api`), and a Business row on the
golden-signals dashboard. `users-api` and `frontend` stay as documented
exceptions, and the unused runtime metrics are dropped (Clarifications).
Design decisions are in [research.md](research.md).

## Technical Context

**Language/Version**: Go (auth-api, per its `go.mod`); Node.js 24 with
Express 5.2.1 (todos-api); Python 3.13 (log-message-processor); Grafana
dashboard JSON and Kustomize 5.8.1 (GitOps)

**Primary Dependencies**: `go.opentelemetry.io/otel/exporters/prometheus`
v0.67.0 with `go.opentelemetry.io/otel/sdk/metric` v1.45.0 (paired with the
`otel` v1.45.0 and `client_golang` v1.24.1 already in `auth-api`);
`@opentelemetry/exporter-prometheus` 0.222.0 with `@opentelemetry/sdk-metrics`
2.11.0 (the OpenTelemetry JS line `todos-api` already uses);
`opentelemetry-exporter-prometheus` 0.65b0 (requires `opentelemetry-sdk`
~=1.44.0, already pinned, and `prometheus-client` <1.0, already 0.26.0)

**Storage**: N/A (Prometheus's existing storage)

**Testing**: `go test`, `node --test`, `pytest` in each service repository;
`tests/contract/observability.sh` in `validate-gitops`

**Target Platform**: Economical EKS cluster; service containers built by the
shared CI

**Project Type**: Multi-repository microservices with a GitOps desired-state repository

**Performance Goals**: Recording a measurement stays in-process and
allocation-bounded; the endpoint is rendered only when scraped

**Constraints**: Same endpoint, port, series names, label names, and bucket
boundaries as today (FR-002, FR-003); no scrape, network, or receiver change;
no user identity in labels (FR-008); tracing unchanged (FR-011)

**Scale/Scope**: 3 migrated services, 3 business series, 1 dashboard row,
2 documented exceptions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against `microservice-app-docs/constitution.md` 4.0.0.

| Principle | Result | Evidence in this plan |
| --- | --- | --- |
| 2. GitOps-only deployment | PASS | The dashboard row is a commit to this repository; service images arrive through the existing promotion path |
| 4. Authoritative specifications, contract-first | PASS | `contracts/preserved-series.md` and `contracts/business-metrics.md` fix names, labels, and buckets before any service changes |
| 6. Immutable build promotion | PASS | No change to how images are built or promoted |
| 8. Quality and supply-chain gates | PASS | Tests committed failing before each implementation; the dashboard contract runs in CI (R10) |
| 9. Observable and resilient operations | PASS | Delivers OpenTelemetry metrics and business metrics while keeping every golden signal and the canary gate intact |
| 10. Least privilege and secret hygiene | PASS | No new network path; business labels carry no identity (R6) |
| 11. Declarative, policy-controlled platform | PASS | Dashboard changes are Kustomize-managed ConfigMaps |
| 13. Traceable delivery | PASS | One pull request per repository, each naming its tasks |
| Economical profile | PASS | No new component; pull through existing scrapes |

Post-design re-check: PASS. The design adds no component, no privilege, and
no secret.

## Project Structure

### Documentation (this feature)

```text
specs/011-service-metrics/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── preserved-series.md
│   └── business-metrics.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code

```text
microservice-app-gitops/
├── infrastructure/grafana/dashboards/golden-signals.yaml   # Business row
└── tests/contract/observability.sh                         # Business row assertions

microservice-app-auth-api/
├── metrics.go                      # new: meter provider, Prometheus exporter on its own registry, views
├── metrics_test.go                 # new
├── main.go, operational.go         # middleware and /metrics use the meter; client_golang metrics removed
├── go.mod, go.sum
└── AGENTS.md

microservice-app-todos-api/
├── metrics.js                      # new: meter provider, exporter without its own server, views
├── test/metrics.test.js            # new
├── server.js, operational.js, todoController.js
├── package.json, package-lock.json # prom-client removed
└── AGENTS.md, README.md

microservice-app-log-message-processor/
├── main.py                         # OpenTelemetry meter; exporter on its own CollectorRegistry
├── tests/test_metrics.py           # new
├── requirements.in, requirements.txt
└── AGENTS.md, README.md
```

**Structure Decision**: Each service repository owns its instrumentation and
tests; this repository owns the specification, the contracts, the dashboard,
and its validation. Metrics setup lives in its own module beside the existing
tracing setup, so FR-011 is protected by construction.

## Complexity Tracking

No constitution violation. Two documented exceptions (FR-010): `users-api`
keeps Micrometer, Spring Boot's instrumentation facade already bridged to
OpenTelemetry for traces, and `frontend` keeps the nginx exporter sidecar,
because nginx has no OpenTelemetry metrics module.

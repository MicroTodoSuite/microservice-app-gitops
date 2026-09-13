# Data Model: Service Metrics Through OpenTelemetry

This feature adds no stored data. Its entities are metric series and one
dashboard row.

## PreservedSeries

A series the recording rules, dashboard, or canary gate already read.

| Field | Meaning | Validation |
| --- | --- | --- |
| `service` | Owning service | `auth-api`, `todos-api`, or `log-message-processor` |
| `name` | Exposition name | Exactly as in `contracts/preserved-series.md` |
| `type` | Counter or histogram | Unchanged from today |
| `labels` | Label names | Exactly as today; no `otel_scope_*`, no resource labels |
| `buckets` | Histogram boundaries | Exactly as today (research R3) |

State transition (per service):

```text
Recorded through a Prometheus client
    -> failing exposition test committed
    -> recorded through OpenTelemetry, same exposition
    -> scraped unchanged on the rebuilt cluster
```

## BusinessMetric

A count of one domain event.

| Field | Meaning | Validation |
| --- | --- | --- |
| `name` | Exposition name | `todo_api_todos_created_total`, `todo_api_todos_deleted_total`, or `auth_api_sign_ins_total` |
| `labels` | Label names | None for todos; `outcome` (`accepted` or `rejected`) for sign-ins |
| `increments when` | The counted event | See `contracts/business-metrics.md` |
| `never counts` | Excluded events | Failed operations, missing-id deletions, server-error sign-ins, probes, scrapes |

## RuntimeSeries (removed)

Default process, memory, garbage-collection, and event-loop series
(`go_*`, `process_*`, `python_*`, `todos_api_*`). After this feature, none is
exposed by the three migrated services.

## BusinessRow

| Field | Meaning | Validation |
| --- | --- | --- |
| `dashboard` | Where the row lives | `infrastructure/grafana/dashboards/golden-signals.yaml` |
| `panels` | Content | Todos created and deleted per 5 minutes; sign-ins per 5 minutes by outcome |
| `alerts` | Alerting | None |

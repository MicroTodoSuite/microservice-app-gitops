# Contract: Preserved Series

Each migrated service's `/metrics` exposition MUST contain these families,
with these label names and bucket boundaries, after it moves to
OpenTelemetry. `le` is the histogram bucket label the exposition format adds.

## auth-api

| Family | Type | Labels | Buckets (`le`, before `+Inf`) |
| --- | --- | --- | --- |
| `auth_api_requests_total` | counter | `method`, `status` | n/a |
| `auth_api_request_duration_seconds` | histogram (`_bucket`, `_sum`, `_count`) | `method` | `0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10` |

## todos-api

| Family | Type | Labels | Buckets (`le`, before `+Inf`) |
| --- | --- | --- | --- |
| `todo_api_requests_total` | counter | `method`, `status` | n/a |
| `todo_api_request_duration_seconds` | histogram (`_bucket`, `_sum`, `_count`) | `method` | `0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10` |

## log-message-processor

| Family | Type | Labels | Buckets (`le`, before `+Inf`) |
| --- | --- | --- | --- |
| `log_messages_processed_total` | counter | none | n/a |
| `log_messages_failed_total` | counter | none | n/a |
| `log_message_processing_duration_seconds` | histogram (`_bucket`, `_sum`, `_count`) | none | `0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1, 2.5, 5, 7.5, 10` |

## Forbidden in the three migrated expositions

- Any label starting with `otel_scope_`.
- The `target_info` family.
- Runtime families: `go_*`, `process_*`, `python_*`, `todos_api_*`.

## Unchanged by this feature

`users-api` (`http_server_requests_seconds_*`) and `frontend`
(`nginx_http_requests_total`) keep their current instrumentation (spec
FR-010). The ServiceMonitors, recording rules, and canary query are not
modified.

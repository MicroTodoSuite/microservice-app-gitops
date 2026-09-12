# Data Model: Service Tracing Through OpenTelemetry

## TraceContext

The identifiers that let the next service continue a trace.

| Field | Meaning | Validation |
| --- | --- | --- |
| `traceparent` | W3C trace context: version, trace id, parent span id, flags | Matches `^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$`; trace id and span id are not all zeros |
| `tracestate` | Optional vendor state that travels with `traceparent` | Present only when received or produced; never required |

Carried as HTTP headers on synchronous hops and as message fields on the todo
operation message. See [contracts/trace-context.md](contracts/trace-context.md).

## Span

| Field | Meaning | Validation |
| --- | --- | --- |
| `service.name` | Resource attribute naming the reporting service | One of `frontend`, `auth-api`, `todos-api`, `users-api`, `log-message-processor` |
| `kind` | Role of the span | `SERVER` for inbound HTTP, `CLIENT` for outbound HTTP, `PRODUCER` for the audit publish, `CONSUMER` for its processing |
| `parent` | The span this one continues | Present when a valid incoming `TraceContext` exists |
| `status` | Outcome | Follows the OpenTelemetry HTTP semantic conventions: `ERROR` for a 5xx server response and for a 4xx or 5xx client response; left unset for a 4xx server response such as a rejected sign-in, whose status code is still recorded; `ERROR` for a failed publish or message processing |
| attributes | OpenTelemetry semantic-convention attributes | MUST NOT include passwords, JWTs, `Authorization` headers, or secret values |

## TodoOperationMessage

The Redis audit message from `todos-api` to `log-message-processor`.

| Field | Meaning | Validation |
| --- | --- | --- |
| `opName` | `CREATE` or `DELETE` | Required, unchanged |
| `username` | User who performed the operation | Required, unchanged |
| `todoId` | Todo identifier | Required, unchanged |
| `correlationId` | `X-Request-Id` of the originating request | Optional, unchanged |
| `traceparent` | Trace context of the publishing span | Optional; W3C format when present |
| `tracestate` | Trace state of the publishing span | Optional |
| `zipkinSpan` | Retired Zipkin trace id | No longer produced; ignored if received from an older publisher |

## TracingConfiguration

Per service, supplied by GitOps. See
[contracts/tracing-configuration.md](contracts/tracing-configuration.md).

| Field | Meaning | Validation |
| --- | --- | --- |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Tracing destination | `http://jaeger-collector.observability.svc:4317` in every economical environment; unset disables export only |
| `OTEL_SERVICE_NAME` | Reported service name | Equals the service's name |
| excluded paths | Requests that produce no spans | Health, readiness, liveness, metrics, runtime configuration, and static content |

## TracingEgressPolicy

| Field | Meaning | Validation |
| --- | --- | --- |
| selected pods | Who may send | `app.kubernetes.io/component: business-service` |
| destination | Where to | Namespace `observability`, pods `app.kubernetes.io/name: jaeger` |
| port | What | TCP 4317 only |

## State transitions (per service)

```text
Zipkin export (or none)
    -> contract updated (todos-api, log-message-processor)
        -> failing tracing tests committed
            -> OpenTelemetry cutover in one revision (no dual export)
                -> image released and promoted through the existing path
                    -> spans visible in Jaeger (live evidence)
```

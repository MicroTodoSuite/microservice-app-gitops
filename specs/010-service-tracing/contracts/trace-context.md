# Contract: Trace Context and Spans

## Synchronous hops

| From | To | Carrier | Rule |
| --- | --- | --- | --- |
| Browser | `frontend` (nginx) | HTTP headers | Continue an incoming `traceparent` if present; otherwise start a trace |
| `frontend` | `auth-api` (`/login`) | HTTP headers | Inject `traceparent` (and `tracestate` when present) |
| `frontend` | `todos-api` (`/todos`) | HTTP headers | Inject `traceparent` (and `tracestate` when present) |
| `auth-api` | `users-api` | HTTP headers | Inject `traceparent` through the traced HTTP client |

Only W3C Trace Context is produced. `X-Request-Id` correlation continues to
work as it does today and is independent of tracing.

## Asynchronous hop

`todos-api` publishes and `log-message-processor` consumes the todo operation
message on the Redis channel named by `REDIS_CHANNEL` (`log_channel`).

```yaml
# AsyncAPI TodoOperationPayload, properties that change
traceparent:
  type: string
  pattern: '^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$'
  description: W3C trace context of the publishing span.
tracestate:
  type: string
  description: W3C trace state of the publishing span, when one exists.
# zipkinSpan is removed from the schema.
```

- The publisher injects the context of its `PRODUCER` span.
- The consumer extracts it and creates a `CONSUMER` span as its child.
- A message without `traceparent`, or with an invalid one, is processed
  normally and starts a new trace. A legacy `zipkinSpan` field is ignored.
- Both copies of the contract (`todos-api` and `log-message-processor`) stay
  identical.

## Spans each service MUST produce

| Service | Span | Kind | Required attributes |
| --- | --- | --- | --- |
| `frontend` | Proxied `/login` and `/todos` requests | `SERVER` | HTTP method, route, status code |
| `auth-api` | Each non-excluded request; the call to `users-api` | `SERVER`, `CLIENT` | HTTP method, route, status code |
| `todos-api` | Each non-excluded request | `SERVER` | HTTP method, route, status code |
| `todos-api` | `log_channel publish` | `PRODUCER` | `messaging.system=redis`, `messaging.destination.name=log_channel`, `messaging.operation.type=publish` |
| `users-api` | Each non-excluded request | `SERVER` | HTTP method, route, status code |
| `log-message-processor` | `log_channel process` | `CONSUMER` | `messaging.system=redis`, `messaging.destination.name=log_channel`, `messaging.operation.type=process` |

Span status follows the OpenTelemetry HTTP semantic conventions: `ERROR` for a
5xx server response and for a 4xx or 5xx client response, unset for a 4xx
server response such as a rejected sign-in (its status code is still recorded),
and `ERROR` for a failed publish or message processing. No span carries a password, a JWT,
an `Authorization` header, or any secret value.

## Requests that MUST NOT produce spans

| Service | Paths |
| --- | --- |
| `frontend` | `/health/*`, `/runtime-config.json`, `/nginx_status`, static files |
| `auth-api` | `/health/*`, `/metrics` |
| `todos-api` | `/health/*`, `/metrics` |
| `users-api` | `/health/**`, `/prometheus` |
| `log-message-processor` | Its operational HTTP server (not instrumented) |

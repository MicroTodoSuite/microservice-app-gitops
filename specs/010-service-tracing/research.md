# Research: Service Tracing Through OpenTelemetry

Every version, flag, and image below was checked on 2026-09-12 against its
upstream source, named next to the decision. Nothing is taken from memory.

## Baseline found in the repositories

| Service | Tracing today | Gap |
| --- | --- | --- |
| `auth-api` (Go) | OpenTelemetry SDK 1.45.0, OTLP/gRPC exporter, `otelecho` server spans, `otelhttp` client toward `users-api`, W3C propagator. Enabled only when `OTEL_EXPORTER_OTLP_ENDPOINT` is set | Server spans are also created for `/health/*` and `/metrics`; the endpoint is set only in the economical `dev` and `demo` overlays |
| `todos-api` (Node.js 24, Express 5) | `zipkin` 0.22.0 with CLS context, HTTP logger to `ZIPKIN_URL`, default `127.0.0.1:9411` | No OpenTelemetry; publishes a Zipkin trace id as `zipkinSpan` in the Redis message |
| `users-api` (Spring Boot 3.5.16, Java 21) | Micrometer Tracing with `micrometer-tracing-bridge-otel` and `opentelemetry-exporter-zipkin`, endpoint `ZIPKIN_URL` | Exports Zipkin format to an undeployed Zipkin |
| `log-message-processor` (Python 3.13) | `py-zipkin` 1.2.8; spans sent with `requests` to `ZIPKIN_URL` only when the message carries `zipkinSpan` | No OpenTelemetry; `requests` exists only for that transport |
| `frontend` (Vue 3 served by nginx) | None; nginx proxies `/zipkin` to `ZIPKIN_URL` (`127.0.0.1:9411` in GitOps) | No spans at the entry point; a dead proxy route |
| GitOps | Jaeger 2.20.0 all-in-one in `observability`, OTLP on 4317/4318, its NetworkPolicy admits 4317/4318 from any namespace | `environments/base/networkpolicy-default-deny.yaml` denies all egress; only DNS, same-namespace, and Redis egress are allowed, so no service can reach Jaeger |

## R1. One protocol, one endpoint, one place to configure it

**Decision**: Every service exports OTLP over gRPC to
`http://jaeger-collector.observability.svc:4317`, read from the standard
`OTEL_EXPORTER_OTLP_ENDPOINT` variable, with `OTEL_SERVICE_NAME` alongside it.
Both are set once in each service's base ConfigMap
(`apps/<service>/base/configmap.yaml`), which every Deployment already loads
through `envFrom`. The per-overlay `OTEL_EXPORTER_OTLP_ENDPOINT` patches in
`auth-api`'s `dev`, `demo`, and full `dev` overlays are removed. An unset
variable disables export and nothing else, which is the switch `auth-api`
already uses.

**Rationale**: `auth-api` already speaks OTLP/gRPC to 4317, so the other four
services join a path that exists. One port keeps the egress rule to a single
destination (R9). The base ConfigMap is the one place all four economical
environments (`dev`, `staging`, `prod`, `demo`) inherit from, which closes the
gap that `staging` and `prod` have no endpoint today. The full profile plans
Jaeger in the same `observability` namespace (`clusters/eks-full-dev/planned-inventory.yaml`),
so the same DNS name remains valid there.

**Alternatives considered**: OTLP/HTTP on 4318 (Spring Boot's default
transport) was rejected to keep one port and one protocol. Per-overlay values
were rejected because they already drifted: two economical environments have
none.

## R2. Propagation format

**Decision**: W3C Trace Context (`traceparent`, `tracestate`) on every hop.
No service produces B3 or Zipkin headers.

**Rationale**: It is the OpenTelemetry default, `auth-api` already configures
it, the nginx module propagates it (R3), and Spring Boot 3.5 consumes W3C by
default (`management.tracing.propagation.consume` defaults to
`[W3C, B3, B3_MULTI]`, Spring Boot 3.5 application properties appendix).

## R3. frontend: trace at the nginx entry point

**Decision**: Switch the runtime base image from
`nginxinc/nginx-unprivileged:alpine3.23` to its OpenTelemetry variant
`nginxinc/nginx-unprivileged:alpine3.23-otel`
(`sha256:1490cbf02ddba36ae75ef947b570166c805a178898ebfbc3bb889e7580820052`),
and load `ngx_otel_module`. Spans are created only in the `/login` and
`/todos` proxy locations with `otel_trace_context propagate`, so nginx starts
or continues the trace and injects `traceparent` toward the APIs. Health,
runtime-config, static files, and `/nginx_status` are not traced. The
`/zipkin` location and `ZIPKIN_URL` are removed. `entrypoint.sh` passes the
endpoint to the template and turns tracing off when
`OTEL_EXPORTER_OTLP_ENDPOINT` is unset (local compose).

**Verified**: Docker Hub lists the `-otel` tags; `docker run` of that digest
shows `nginx/1.31.2`, Alpine `3.23.5`, UID 101, and
`/etc/nginx/modules/ngx_otel_module.so`. The image the frontend pins today
(`sha256:6320020c...`) is also nginx 1.31.2 on Alpine 3.23.5, so the web server
version does not change. The module's directives (`otel_exporter { endpoint
host:port; }` for OTLP/gRPC, `otel_service_name`, `otel_trace` in
`http`/`server`/`location`, `otel_trace_context propagate`) are from
`https://nginx.org/en/docs/ngx_otel_module.html`.

**Alternatives considered**: Browser-side OpenTelemetry was rejected by the
spec's assumptions: the entry point is the frontend service the plan names,
and exporting from browsers would need a public OTLP route.

## R4. todos-api: OpenTelemetry SDK for Node.js without the all-in-one package

**Decision**: Add `@opentelemetry/api` 1.9.1, `@opentelemetry/sdk-trace-node`
2.11.0, `@opentelemetry/resources` 2.11.0, `@opentelemetry/core` 2.11.0,
`@opentelemetry/semantic-conventions` 1.43.0,
`@opentelemetry/exporter-trace-otlp-grpc` 0.222.0,
`@opentelemetry/instrumentation` 0.222.0,
`@opentelemetry/instrumentation-http` 0.222.0, and
`@opentelemetry/instrumentation-express` 0.70.0, pinned exactly as the
repository pins dependencies. A new `tracing.js` registers the provider and
instrumentations and is required on the first line of `server.js`, before
`express` or `http` load, and is copied into the runtime image. Incoming
`/health/*` and `/metrics` requests are ignored. The audit publish becomes a
`PRODUCER` span whose context is injected into the message (R8). The four
`zipkin*` packages are removed.

**Verified**: npm registry `dist-tags` for each package; the express
instrumentation README states support for `express >=4.0.0 <6` (Express 5.2.1
is in range); `engines` for these packages is `^18.19.0 || >=20.6.0` (Node 24
is in range).

**Alternatives considered**: `@opentelemetry/sdk-node` 0.222.0 was rejected
because it depends on `@opentelemetry/exporter-zipkin`, which would keep a
Zipkin library in the dependency tree against FR-006, and on every metrics and
logs exporter this feature does not use.

## R5. log-message-processor: OpenTelemetry SDK for Python

**Decision**: Replace `py-zipkin` and `requests` in `requirements.in` with
`opentelemetry-api`, `opentelemetry-sdk`, and
`opentelemetry-exporter-otlp-proto-grpc`, all 1.44.0, and regenerate the
hashed `requirements.txt` with `pip-compile --generate-hashes` on Python 3.13,
as its header records. Processing a message becomes a `CONSUMER` span whose
parent is extracted from the message's `traceparent`; a message without it
starts a new trace. The exporter is created only when
`OTEL_EXPORTER_OTLP_ENDPOINT` is set.

**Verified**: PyPI JSON for the three packages (1.44.0, `requires_python
>=3.10`); the gRPC exporter requires `grpcio>=1.66.2` on Python 3.13, and
`grpcio` 1.83.1 publishes a `cp313 manylinux x86_64` wheel, so the slim image
needs no compiler.

## R6. users-api: keep Micrometer Tracing, change only the exporter

**Decision** (amended during implementation, see below): Replace
`io.opentelemetry:opentelemetry-exporter-zipkin` with
`io.opentelemetry:opentelemetry-exporter-otlp` (version managed by the Spring
Boot 3.5.16 BOM) and replace `management.zipkin.tracing.endpoint` with
`management.otlp.tracing.transport=grpc`. An `EnvironmentPostProcessor` sets
`management.otlp.tracing.endpoint` from `OTEL_EXPORTER_OTLP_ENDPOINT` only when
the variable has a value. An auto-configuration replaces Spring Boot's three
tracing observation handlers with subclasses that do not support a
`/health/**` or `/prometheus` server request or any observation nested in one.
The test property that disabled Zipkin export is removed: Spring Boot tests
run with tracing off unless `@AutoConfigureObservability` turns it on.

**Verified**: Spring Boot 3.5 tracing reference names
`micrometer-tracing-bridge-otel` plus `opentelemetry-exporter-otlp` for OTLP;
the properties appendix lists `management.otlp.tracing.endpoint`,
`management.otlp.tracing.transport` (default `http`), and
`management.otlp.tracing.export.enabled`.

**To confirm during implementation**: that an empty endpoint leaves no
exporter active; if it does not, `management.otlp.tracing.export.enabled` is
bound to the endpoint's presence. The failing test written first decides it.

**Amendment (T014/T016)**: Two parts of the original decision do not hold in
Spring Boot 3.5.16 and Micrometer 1.15.12:

- `management.otlp.tracing.endpoint=${OTEL_EXPORTER_OTLP_ENDPOINT:}` resolves
  to an empty string when the variable is unset, and
  `OtlpTracingConfigurations.ConnectionDetails` is
  `@ConditionalOnProperty("management.otlp.tracing.endpoint")`, which matches
  any value other than `false`, so the OTLP/gRPC exporter is still created
  and rejects the empty endpoint: with tracing on, users-api fails to start
  (`IllegalArgumentException: Invalid endpoint, must start with http:// or
  https://`, observed with the T014 tests before the implementation).
  `management.otlp.tracing.export.enabled` cannot be derived from the
  variable's presence with a property placeholder, so the property is set in
  code only when the variable has a value.
- An `ObservationPredicate` that rejects an observation makes it a no-op for
  every handler, including the meter handler that records
  `http.server.requests`, so the probe and scrape series would disappear
  (FR-013). Filtering finished spans instead leaves the Spring Security
  observations nested in those requests as spans of their own. Spring Boot's
  `defaultTracingObservationHandler`, `propagatingReceiverTracingObservationHandler`,
  and `propagatingSenderTracingObservationHandler` beans are
  `@ConditionalOnMissingBean`, so replacing only those three leaves metrics
  untouched. Micrometer's `TracingAwareMeterObservationHandler` reads a
  tracing context when any observation stops, so a skipped observation keeps
  an empty one and its metrics are recorded without a span.

## R7. auth-api: only stop tracing probes and scrapes

**Decision**: Pass `otelecho.WithSkipper` to the existing middleware so
`/health/*` and `/metrics` create no spans. No other code change; the
repository's documentation that still describes Zipkin is corrected in the
same change.

**Verified**: `pkg.go.dev` for `otelecho` v0.70.0 lists `WithSkipper`.

## R8. Trace context in the todo operation message

**Decision**: The AsyncAPI `TodoOperationPayload` in both
`microservice-app-todos-api/contracts/asyncapi.yaml` and
`microservice-app-log-message-processor/contracts/asyncapi.yaml` replaces
`zipkinSpan` with an optional `traceparent` string in W3C format and an
optional `tracestate` string. The contract changes first, in both
repositories, before either implementation (constitution principle 4).

**Rationale**: Carrying the standard fields lets the same OpenTelemetry
propagator inject and extract them on both sides, with no custom encoding.
Keeping them optional preserves the existing rule that an older publisher's
message still processes.

## R9. Egress to the tracing backend

**Decision**: Add `environments/base/networkpolicy-allow-tracing-egress.yaml`:
pods labeled `app.kubernetes.io/component: business-service` may open TCP 4317
to pods labeled `app.kubernetes.io/name: jaeger` in the namespace labeled
`kubernetes.io/metadata.name: observability`, and nothing else.

**Rationale**: Default-deny already exists; this adds the narrowest allow rule
that R1 needs (constitution principle 10). The label is the one all five
business Deployments already carry (checked in every economical `dev` render),
and Jaeger's own policy already admits 4317 from any namespace, so no change is
needed on the receiving side.

## R10. Validation

**Decision**: Each service repository gets failing tests first, using its
existing runner (`node --test`, `pytest`, JUnit through Maven, `go test`,
`vitest` plus an nginx configuration check). GitOps gets
`tests/contract/service-tracing.sh`, run by `validate-gitops`, asserting for
every service and economical environment that the rendered Deployment receives
the endpoint and service name, that no `ZIPKIN` value remains in any rendered
application or environment, and that the egress policy exists exactly as R9
defines it.

## R11. Sampling and retention

**Decision**: The SDK default (parent-based, always on) everywhere;
`users-api` keeps `management.tracing.sampling.probability` at its current
default of 1.0. Retention stays Jaeger's 3 days from spec 006.

## R12. Reconciliation with spec 009

**Finding**: Spec 009 T072 to T081 are ticked with "OpenTelemetry" in their
text, but only `auth-api` exports OpenTelemetry traces. The operational
contracts they delivered (health, correlation ids, resilience) are real; the
tracing part is not. Spec 009's register gains a reconciliation note pointing
to this feature instead of silently unticking or rewording those tasks.

## R13. Delivery order

**Decision**: Contracts first (R8), then each service in its own repository,
then the GitOps configuration and egress policy. Any deployment order is safe:
export is non-blocking, so a service with tracing but no egress yet loses spans
and nothing else, and a policy without tracing services is inert. New service
images reach environments only through the existing release and promotion
path, which this feature does not change.

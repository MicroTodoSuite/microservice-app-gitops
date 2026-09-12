# Implementation Plan: Service Tracing Through OpenTelemetry

**Branch**: `docs/service-tracing-spec` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/010-service-tracing/spec.md`

## Summary

Plan section 10 requires OpenTelemetry as each service's instrumentation layer
and traces in Jaeger. Only `auth-api` meets it, and no service can reach Jaeger
because the environment namespaces deny all egress. This feature moves
`todos-api`, `users-api`, `log-message-processor`, and `frontend` from Zipkin to
OpenTelemetry, carries W3C trace context across every HTTP hop and the Redis
audit message, stops tracing probes and scrapes, gives every service the same
tracing destination from its base ConfigMap, and opens exactly one egress path
from business pods to Jaeger's OTLP/gRPC port. Metrics are untouched
(Clarifications, FR-013). Design decisions are in [research.md](research.md).

## Technical Context

**Language/Version**: Go (auth-api, per its `go.mod`); Node.js 24 with
Express 5.2.1 (todos-api); Java 21 with Spring Boot 3.5.16 (users-api);
Python 3.13 (log-message-processor); nginx 1.31.2 on Alpine 3.23 (frontend);
Kubernetes YAML with Kustomize 5.8.1 (GitOps)

**Primary Dependencies**: OpenTelemetry JS 2.11.0 / 0.222.0 and
`instrumentation-express` 0.70.0; OpenTelemetry Python 1.44.0 with the OTLP
gRPC exporter; `opentelemetry-exporter-otlp` through the Spring Boot BOM;
`otelecho` v0.70.0 (already present); `ngx_otel_module` in
`nginxinc/nginx-unprivileged:alpine3.23-otel`; Jaeger 2.20.0 (spec 006)

**Storage**: N/A (Jaeger's existing Badger storage, 3-day retention)

**Testing**: `node --test`, `pytest`, JUnit via Maven, `go test`, `vitest`,
`nginx -t` in the built image, Spectral for AsyncAPI, and
`tests/contract/service-tracing.sh` in `validate-gitops`

**Target Platform**: Economical EKS cluster (`microtodo-dev`, `-staging`,
`-prod`, `-demo` namespaces); service containers already built by the shared CI

**Project Type**: Multi-repository microservices with a GitOps desired-state repository

**Performance Goals**: No added request-path latency beyond batched,
asynchronous export (FR-008)

**Constraints**: GitOps-only changes; no Istio in the economical profile; no
Zipkin library left in any dependency tree; egress limited to Jaeger 4317;
existing metrics series unchanged

**Scale/Scope**: 5 services, 2 message-contract copies, 4 economical
environments, 1 NetworkPolicy

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against `microservice-app-docs/constitution.md` 4.0.0.

| Principle | Result | Evidence in this plan |
| --- | --- | --- |
| 2. GitOps-only deployment | PASS | Tracing configuration and the egress policy are commits to this repository; new service images arrive through the existing promotion path |
| 4. Authoritative specifications, contract-first | PASS | The AsyncAPI message change lands before either service implements it (R8) |
| 6. Immutable build promotion | PASS | No change to how images are built or promoted |
| 8. Quality and supply-chain gates | PASS | Every repository gets tests committed failing before implementation; the GitOps contract runs in CI (R10) |
| 9. Observable and resilient operations | PASS | This feature delivers the OpenTelemetry and Jaeger capability the principle names, with non-blocking export |
| 10. Least privilege and secret hygiene | PASS | One narrow egress rule (R9); spans never carry credentials (FR-010); no secret involved |
| 11. Declarative, policy-controlled platform | PASS | All platform changes are Kustomize resources owned by ArgoCD |
| 13. Traceable delivery | PASS | One pull request per repository, each naming its tasks |
| Economical profile | PASS | No mesh; Jaeger with embedded storage as plan section 17 defines |

Post-design re-check: PASS. The design adds no component, no privilege beyond
R9, and no new secret.

## Project Structure

### Documentation (this feature)

```text
specs/010-service-tracing/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── trace-context.md
│   └── tracing-configuration.md
├── checklists/requirements.md
└── tasks.md                      # produced by /speckit-tasks
```

### Source Code

```text
microservice-app-gitops/
├── apps/{auth-api,todos-api,users-api,frontend,log-message-processor}/base/configmap.yaml
│                                   # OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME; ZIPKIN_URL removed
├── apps/auth-api/profiles/{economical/overlays/{dev,demo},full/overlays/dev}/kustomization.yaml
│                                   # per-overlay OTLP env patch removed
├── environments/base/networkpolicy-allow-tracing-egress.yaml   # new
├── environments/base/kustomization.yaml
├── tests/contract/service-tracing.sh                           # new
├── .github/workflows/validate-gitops.yml
└── specs/009-full-platform-rollout/tasks.md                    # reconciliation note (R12)

microservice-app-auth-api/
├── main.go                         # otelecho.WithSkipper
├── main_test.go                    # probes and scrapes produce no spans
└── AGENTS.md, README.md            # Zipkin description corrected

microservice-app-todos-api/
├── contracts/asyncapi.yaml         # traceparent/tracestate replace zipkinSpan
├── tracing.js                      # new: provider, exporter, instrumentations
├── server.js, routes.js, todoController.js, Dockerfile, package.json, package-lock.json
└── test/{tracing.test.js,routes.test.js,operational-contract.test.js,integration/redis-publish.test.js}

microservice-app-log-message-processor/
├── contracts/asyncapi.yaml
├── main.py
├── requirements.in, requirements.txt
└── tests/{test_main.py,test_operational_contract.py}

microservice-app-users-api/
├── pom.xml
├── src/main/resources/application.properties
├── src/main/java/com/elgris/usersapi/configuration/TracingConfiguration.java   # new: ObservationPredicate
└── src/test/java/com/elgris/usersapi/UsersApiApplicationTests.java

microservice-app-frontend/
├── Dockerfile                      # alpine3.23-otel base
├── nginx.conf.template, entrypoint.sh
├── test/unit/operational-contract.test.js
└── e2e/compose.yaml, config/index.js, README.md, AGENTS.md   # Zipkin references removed
```

**Structure Decision**: Each service repository owns its instrumentation,
tests, and message contract copy; this repository owns the specification, the
shared tracing configuration, the network policy, and the render validation,
matching how spec 006 split `auth-api`'s pilot.

## Complexity Tracking

No constitution violations to justify.

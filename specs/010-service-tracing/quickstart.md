# Quickstart: Validating Service Tracing

## 1. Static checks (no cluster)

From `microservice-app-gitops`:

```bash
tests/contract/service-tracing.sh
tests/contract/observability.sh
```

Expected: both print `PASS`. The tracing contract confirms every service and
economical environment receives the endpoint and service name, no Zipkin
setting remains, and the egress policy matches
[contracts/tracing-configuration.md](contracts/tracing-configuration.md).

Each service repository, with its checked-in toolchain (shown with the official
containers the images already build from):

```bash
# todos-api
docker run --rm -v "$PWD":/src -w /src node:24-alpine3.22 sh -c 'npm ci && npm test'
# frontend
docker run --rm -v "$PWD":/src -w /src node:24-alpine3.22 sh -c 'npm ci && npm test'
docker build -t frontend:tracing .
docker run --rm -e AUTH_API_ADDRESS=http://auth-api:8000 -e TODOS_API_ADDRESS=http://todos-api:8082 \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger-collector.observability.svc:4317 \
  frontend:tracing -t   # entrypoint.sh renders the template, then runs nginx with -t
# log-message-processor
docker run --rm -v "$PWD":/src -w /src python:3.13-slim-trixie sh -c \
  'pip install -r requirements-dev.txt && python -m pytest'
# users-api
docker run --rm -v "$PWD":/src -w /src maven:3.9.12-eclipse-temurin-21 mvn -B test
# auth-api
docker run --rm -v "$PWD":/src -w /src golang:<go.mod version> go test ./...
```

Expected: all tests pass, including the tracing tests that failed before their
implementation commits. For `todos-api` and `log-message-processor`, the
Spectral lint of `contracts/asyncapi.yaml` passes.

## 2. Local connected trace (optional, no cluster)

Run Jaeger 2.20.0, Redis, `todos-api`, and `log-message-processor` on one
Docker network with `OTEL_EXPORTER_OTLP_ENDPOINT` pointing at Jaeger. Create a
todo with a valid JWT, then:

```bash
curl -s 'http://localhost:16686/api/traces?service=todos-api&limit=1' \
  | python3 -c 'import json,sys; t=json.load(sys.stdin)["data"][0]; print(sorted({p["serviceName"] for p in t["processes"].values()}))'
```

Expected: `['log-message-processor', 'todos-api']`.

## 3. Live acceptance (economical cluster, after it is rebuilt)

Read-only, no direct mutation:

```bash
kubectl -n observability port-forward svc/jaeger-query 16686:16686
kubectl -n microtodo-dev port-forward svc/frontend 8080:8080
```

1. Sign in and create a todo through `http://localhost:8080`.
2. `curl -s 'http://localhost:16686/api/services'` lists all five services
   (SC-003).
3. The newest `todos-api` trace contains `frontend`, `todos-api`, and
   `log-message-processor`, and the consumer span's parent is the producer
   span (SC-001).
4. The newest `users-api` trace contains `frontend`, `auth-api`, and `users-api`
   (SC-002).
5. No span attribute in those traces contains a password, token, or
   `Authorization` header (SC-006).
6. Backend-unavailable check (SC-005): a reviewed commit removes
   `allow-tracing-egress`; after ArgoCD syncs, 20 sign-ins and 20 todo
   operations all succeed; the commit is reverted.

Retain the outputs under `evidence/runs/<timestamp>-service-tracing/`.

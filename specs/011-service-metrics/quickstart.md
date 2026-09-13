# Quickstart: Service Metrics Through OpenTelemetry

## 1. Service tests (each repository)

```bash
# auth-api
docker run --rm -v "$PWD":/src -w /src golang:<go.mod version> go test ./...
# todos-api
docker run --rm -v "$PWD":/src -w /src node:24-alpine3.22 sh -c 'npm ci && npm test'
# log-message-processor
docker run --rm -v "$PWD":/src -w /src python:3.13-slim-trixie sh -c \
  'pip install --require-hashes -r requirements-dev.txt && python -m pytest'
```

Expected: every test passes, including the metrics tests that failed before
their implementation commits.

## 2. Local exposition check (optional, one container at a time)

Run one built service image and compare its exposition with
`contracts/preserved-series.md`:

```bash
curl -s localhost:<port>/metrics | grep -E '^# TYPE|^[a-z_]+(\{|\s)' | sort -u
curl -s localhost:<port>/metrics | grep -cE 'otel_scope_|^target_info|^(go|process|python|todos_api)_'   # expect 0
```

## 3. Live acceptance (rebuilt economical cluster)

Through Prometheus (port-forward only, spec 006 FR-017):

```promql
# SC-001: preserved families present
count by (__name__) ({__name__=~"auth_api_requests_total|auth_api_request_duration_seconds_(bucket|sum|count)|todo_api_requests_total|todo_api_request_duration_seconds_(bucket|sum|count)|log_messages_(processed|failed)_total|log_message_processing_duration_seconds_(bucket|sum|count)"})

# SC-002: recording rules and the canary query return values
workload:http_requests:rate5m
workload:http_errors:ratio5m
workload:http_request_duration_seconds:avg5m

# SC-003 and SC-004: business counts before and after a known number of operations
sum(todo_api_todos_created_total)
sum(todo_api_todos_deleted_total)
sum by (outcome) (auth_api_sign_ins_total)
```

Create N todos, delete M of them, perform K accepted and J rejected sign-ins,
and one sign-in while `users-api` is scaled to zero through a reviewed commit
and its revert; the counts change by exactly N, M, K, and J, and the
server-error sign-in changes neither outcome (SC-004). Open the golden-signals
dashboard's Business row and confirm it shows the change within two scrape
intervals (SC-005).

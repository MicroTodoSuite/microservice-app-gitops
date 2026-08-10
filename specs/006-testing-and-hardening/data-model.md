# Phase 1 Data Model: Testing, Contracts, and Remediation

Configuration/artifact entities this feature manipulates. No runtime database.

## Test Suite (per service)

| Field | Type | Constraint |
| --- | --- | --- |
| service | enum | auth-api \| todos-api \| users-api \| frontend \| log-message-processor |
| gate | enum | unit \| integration \| contract \| e2e \| perf \| dast |
| location | path | idiomatic per stack (`*_test.go`, `test/`, `src/test`, `tests/`, `e2e/`, `perf/`, `zap/`) |
| runner | tool | go test / Jest / JUnit / pytest / Cypress / Locust / ZAP |
| coverage-report | artifact | present for unit gate; native format (cover/lcov/JaCoCo/cobertura) |
| gate-enabled | bool | true only when artifacts exist and pass locally (D11) |

## API Contract

| Field | Type | Constraint |
| --- | --- | --- |
| service | enum | REST services and event-carrying services |
| kind | enum | openapi (REST) \| asyncapi (events) |
| version | semver | versioned; source of truth |
| location | path | `<repo>/contracts/openapi.yaml` / `asyncapi.yaml` |
| lint-status | pass/fail | Spectral |
| conformance | pass/fail | implementation verified against contract; fails on drift (FR-011) |
| consumer-provider | optional | Pact pair where a cross-service dependency exists |

## Coverage Measurement

| Field | Type | Constraint |
| --- | --- | --- |
| service | enum | one per service |
| percent | number | ≥ 70% business-logic lines (D2, tunable) |
| reported-to | ref | self-hosted SonarQube quality gate (skipped until server up) |

## Vulnerability Finding

| Field | Type | Constraint |
| --- | --- | --- |
| service | enum | one per image |
| id | string | CVE id |
| severity | enum | HIGH \| CRITICAL (gate scope) |
| fix-available | bool | — |
| resolution | enum | remediated (dep/base bump) \| documented-exception (upstream-unfixable, justified, time-bounded) |

Invariant: an active service has **zero** fixable HIGH/CRITICAL findings (FR-001); exceptions are only for `fix-available=false`.

## Gate Activation State

| Field | Type | Constraint |
| --- | --- | --- |
| service | enum | — |
| gate | enum | unit/integration/contract/e2e/perf/dast |
| enabled | bool | flips `run-<gate>` in the service caller; only after artifacts exist |
| enforcement | invariant | enabled-but-empty must fail visibly (FR-012) |

## Relationships

- Each **Test Suite**(unit) produces a **Coverage Measurement** → the code-quality gate.
- Each **API Contract** is verified by a contract **Test Suite**; a cross-service dependency adds a consumer/provider pair.
- Each **Vulnerability Finding** is either remediated or a documented exception before its service's gate is green.
- **Gate Activation State** transitions false→true only when the matching Test Suite/Contract artifacts exist.

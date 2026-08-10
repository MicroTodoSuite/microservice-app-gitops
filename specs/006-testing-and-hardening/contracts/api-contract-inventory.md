# Contract: API Contract Inventory (contract-first)

Contracts are authored first and are the source of truth; CI fails on drift (FR-009…FR-011).
Each lives in its service repo under `contracts/`.

## REST — OpenAPI 3.1

| Service | File | Key operations (from verified code) | Auth |
| --- | --- | --- | --- |
| auth-api | `contracts/openapi.yaml` | `POST /login`, `GET /version` (public), `GET /metrics` | `/login` issues JWT |
| todos-api | `contracts/openapi.yaml` | `GET/POST/DELETE /todos`, `GET /metrics` (public) | Bearer JWT (except `/metrics`) |
| users-api | `contracts/openapi.yaml` | `GET /users`, `GET /users/{username}`, `GET /actuator/health` | Bearer JWT (actuator open) |

## Events — AsyncAPI 3 (Redis `log_channel`)

| Service | File | Role | Message |
| --- | --- | --- | --- |
| todos-api | `contracts/asyncapi.yaml` | publisher | todo operation event (create/delete) on `log_channel` |
| log-message-processor | `contracts/asyncapi.yaml` | consumer/subscriber | same `log_channel` message schema |

Invariant: the todos-api publisher schema and the log-message-processor consumer schema for `log_channel` MUST be the same versioned message (verified via the shared AsyncAPI + a consumer/provider check).

## Cross-service consumer/provider (Pact)

| Consumer | Provider | Interaction |
| --- | --- | --- |
| auth-api | users-api | fetch user for `/login` |
| frontend | auth-api, todos-api | login + todos CRUD via nginx proxy |
| log-message-processor | todos-api | `log_channel` event schema (via AsyncAPI) |

## Conformance rules

1. Every REST service has an OpenAPI doc that Spectral lints clean.
2. Live responses conform to the OpenAPI (schema conformance); a divergence fails the contract gate.
3. `log_channel` messages conform to the AsyncAPI on both publish and consume.
4. A deliberate breaking change (e.g., renaming a field) MUST fail the contract gate.

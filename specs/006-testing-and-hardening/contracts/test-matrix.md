# Contract: Per-Service Test Matrix

Which artifact fills each gate, per service, and the reusable-CI switch that runs it.
`✔` = in scope for this feature; `—` = not applicable.

| Gate (caller switch) | auth-api (Go) | todos-api (Node) | users-api (Java) | frontend (Vue) | log-message-processor (Py) |
| --- | --- | --- | --- | --- | --- |
| image-scan (active) | bump `golang.org/x/crypto` | `npm audit fix` | Maven bumps | npm bumps (Vue2 limits) | pip bumps |
| unit (`run-unit`) | go test+testify | Jest+supertest | JUnit+MockMvc | Jest+Vue Test Utils | pytest |
| integration (`run-integration`) | stub users-api | Testcontainers Redis | Spring context (H2) | — | Testcontainers Redis |
| contract (`run-contract`) | OpenAPI | OpenAPI + AsyncAPI(pub) | OpenAPI | Pact consumer | AsyncAPI(consumer) |
| e2e (`run-e2e`) | — | — | — | Cypress (docker-compose stack) | — |
| perf (`run-perf`) | Locust /login | Locust todos CRUD | — | — | — |
| dast (`run-dast`) | ZAP baseline | ZAP baseline | ZAP baseline | ZAP baseline | ZAP baseline (/metrics) |
| quality (SonarQube) | coverage → Sonar (skipped until server up) | " | " | " | " |

Notes:
- e2e is owned by the frontend repo (one stack-level suite), not per-service.
- coverage reports feed the SonarQube quality gate for every service; that gate stays visibly skipped until the self-hosted server is deployed and `sonar-host-url` is set.
- auth-api is completed first as the template (image-scan + unit + contract) to prove a green end-to-end run.

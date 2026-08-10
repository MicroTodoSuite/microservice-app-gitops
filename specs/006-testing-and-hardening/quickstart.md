# Quickstart: Validate Tests, Contracts, and Remediation

How to prove each gate is real and green, per stack. Run locally first, then flip the
caller switch and confirm CI. Start with **auth-api** (the template).

## 0. Prerequisites
- Per-stack toolchains: Go, Node 20, JDK 8 + Maven, Python 3.11, Docker (Testcontainers, docker-compose).
- `trivy`, `spectral`, and (optional) `act` for local CI dry-runs.

## 1. Vulnerability remediation (image-scan → green)
```bash
# auth-api example
cd microservice-app-auth-api
go get golang.org/x/crypto@latest && go mod tidy
trivy fs --scanners vuln --severity HIGH,CRITICAL .   # expect: 0 fixable HIGH/CRITICAL
```
Pass when `trivy fs`/`trivy image` reports zero fixable HIGH/CRITICAL (remaining = documented `.trivyignore` exceptions only).

## 2. Unit + coverage (`run-unit`)
```bash
# per stack
go test ./... -coverprofile=coverage.out            # auth-api
npm test -- --coverage                               # todos-api / frontend
mvn -B test                                          # users-api (JaCoCo)
pytest --cov --cov-report=xml                         # log-message-processor
```
Pass when tests are green and coverage ≥ 70% of business logic. Then set `run-unit: true` in that service's caller.

## 3. Contract-first (`run-contract`)
```bash
spectral lint contracts/openapi.yaml                 # + contracts/asyncapi.yaml where present
# conformance: run the service and check live responses/messages against the contract
```
Pass when Spectral is clean AND conformance passes; then introduce a deliberate breaking change and confirm the gate **fails**; revert. Set `run-contract: true`.

## 4. Integration (`run-integration`)
```bash
# todos-api / log-message-processor: Testcontainers spins a real Redis
npm run test:integration        # todos-api
pytest tests/integration        # log-message-processor
mvn -B verify                   # users-api (full Spring context)
```
Pass when the real dependency interaction is exercised and fails when broken. Set `run-integration: true`.

## 5. E2E / perf / DAST (stack level, last)
```bash
docker compose up -d            # frontend + auth + todos + users + redis
npx cypress run                 # e2e (frontend repo)
locust -f perf/locustfile.py    # perf baselines
# ZAP baseline against a running service URL
```
Pass when primary journeys pass, baselines record, and ZAP high-severity findings fail the gate. Enable `run-e2e`/`run-perf`/`run-dast`.

## 6. Prove the end-to-end green run (auth-api)
After steps 1–3 on auth-api, merge to its main and confirm the CI run is fully green — including `release` and `promote-dev` opening the automated promotion PR in gitops (validates the GitHub App token path from task 4).

## What is intentionally NOT covered
- No pipeline/gitops/base-overlay changes (only test artifacts, contracts, dep bumps, switch flips).
- Cluster-side runtime security (Kyverno verify / Falco / in-cluster scanning) — platform task 2.
- SonarQube quality gate stays visibly skipped until the self-hosted server is deployed.

# Implementation Plan: Service Test Suites, API Contracts, and Vulnerability Remediation

**Branch**: `006-testing-and-hardening` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-testing-and-hardening/spec.md`

## Summary

Fill the quality/supply-chain gates that roadmap task 4 scaffolded as skippable: author real test suites and contract-first API definitions in the five service repos, remediate the image vulnerabilities blocking the Trivy gate, and flip each `run-*` switch on only once its artifacts exist. Deliver incrementally — **auth-api first** (bump `golang.org/x/crypto`, real `go test`, its OpenAPI contract) to prove a fully green end-to-end run including the promotion PR — then replicate across the other four services and add the heavier gates (e2e/perf/DAST) last. No change to the reusable pipeline, GitOps flow, or service base/overlays.

## Technical Context

**Languages/Stacks (verified)**: Go 1.23 + Echo (auth-api); Node 20 + Express (todos-api); Java 8 + Spring Boot + Maven (users-api); Vue 2 + webpack → nginx (frontend); Python 3.11 (log-message-processor, worker).

**Primary Dependencies / tooling per gate**:
- unit: `go test`+testify (go cover) · Jest+supertest (lcov) · JUnit+Spring Boot Test+MockMvc (JaCoCo) · Vue Test Utils+Jest (lcov) · pytest (coverage.py xml)
- integration: Testcontainers — Redis for todos-api & log-message-processor; full Spring context for users-api; auth-api uses a stubbed users-api
- contract: OpenAPI (REST) + AsyncAPI (Redis `log_channel` events) authored first; Spectral (lint) + schema conformance + Pact (consumer/provider: auth→users, frontend→auth/todos, todos↔log via AsyncAPI)
- e2e: Cypress over the frontend against a docker-compose stack
- performance: Locust scenarios (auth login, todos CRUD)
- dynamic-security: OWASP ZAP baseline against a running service
- vulnerability remediation: `go get -u`/`go mod tidy`, `npm audit fix`/bumps, Maven dependency bumps, `pip` bumps; base-image bumps where the finding is OS-level
- reporting: coverage → self-hosted SonarQube quality gate (server activated separately)

**Storage**: N/A (test artifacts + contracts committed to each service repo).

**Target Platform**: GitHub-hosted CI runners; artifacts run through the existing reusable `ci.yml` gates.

**Project Type**: Multi-repo test/quality authoring. Changes land in the **5 service repos** (`tests/`, `contracts/`, dependency bumps, and flipping `run-*` in each caller). SDD artifacts live in gitops `specs/006`.

**Performance/Quality targets**: unit coverage ≥ **70%** of business-logic lines per service (team-tunable); zero fixable HIGH/CRITICAL in Trivy; contract drift must fail CI; a defined perf regression and any ZAP high-severity finding must fail their gates.

**Constraints**: contract-first (constitution P4); do not touch the reusable pipeline, GitOps flow, or base/overlays; CI-side only (no cluster runtime security); English; short-lived branches + PRs; a gate is enabled only after its artifacts exist.

**Scale/Scope**: 5 services × up to 6 gate types + API contracts + dependency remediation. Sequenced auth-api → others.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | How this feature complies |
| --- | --- | --- |
| 3. Stable Trunk Development | **PASS** | Short-lived branches + reviewed PRs per service (FR-017). |
| 4. Authoritative Specifications (contract-first) | **PASS — this feature delivers it** | Authors OpenAPI + AsyncAPI as source of truth and verifies no drift in CI (FR-009…FR-011). |
| 6. Immutable Build Promotion | **PASS** | Unchanged; remediated images still promoted by digest. Trivy staying green keeps promotion honest. |
| 8. Quality and Supply-Chain Gates | **PASS — core of this feature** | Turns the scaffolded gates active with real artifacts; no "green gate that ran nothing" (FR-012). |
| 10. Least Privilege & Secret Hygiene | **PASS (CI-side)** | Dependency remediation (Trivy) + DAST are CI-side; ESO/RBAC/Falco unchanged. |
| 11. Declarative Platform | **N/A here** | No manifest/platform changes (FR-015/FR-016). |

No violations. Two items tracked below (SonarQube server dependency; legacy-stack remediation limits).

## Project Structure

### Documentation (this feature)

```text
specs/006-testing-and-hardening/
├── plan.md            # this file
├── research.md        # Phase 0: per-stack tooling + remediation + contract/e2e/perf/dast decisions
├── data-model.md      # Phase 1: entities (test suite, API contract, coverage, finding, gate state)
├── quickstart.md      # Phase 1: how to run/verify each gate locally + the green-run proof
├── contracts/
│   ├── api-contract-inventory.md    # which OpenAPI/AsyncAPI docs exist, per service
│   ├── test-matrix.md               # per service × gate: artifact + how CI runs it
│   └── gate-activation-contract.md  # rules for turning a run-* switch on
└── checklists/requirements.md
```

### Source Code (across the 5 service repositories)

```text
# each service repo (auth-api, todos-api, users-api, frontend, log-message-processor)
<repo>/
├── (dependency manifests bumped to clear CVEs: go.mod/package.json/pom.xml/requirements.txt)
├── contracts/
│   ├── openapi.yaml        # REST services
│   └── asyncapi.yaml       # services on the Redis log_channel (todos-api, log-message-processor)
├── test/ | *_test.go | src/test/... | tests/   # unit + integration, per stack idioms
├── e2e/                    # frontend repo: Cypress specs (+ docker-compose stack)
├── perf/                   # Locust scenarios
├── zap/                    # OWASP ZAP baseline config
└── .github/workflows/ci.yml   # flip run-<gate>: true as each artifact lands
```

**Structure Decision**: Multi-repo. All deliverables live in the five service repos; the reusable pipeline in `.github` and the gitops manifests are untouched. Only the per-service caller's `run-*` inputs change (value flips), never the reusable workflow.

## Complexity Tracking

| Deviation / risk | Why it exists | Mitigation |
| --- | --- | --- |
| Code-quality gate (SonarQube) can't run until the self-hosted server exists | Team chose self-hosted; server is scaffolded (feature 003) but not deployed | Author coverage reports now; the quality gate stays visibly skipped until the server is up, then activates by value (no pipeline change). |
| Legacy stacks limit remediation | frontend (Vue 2 / node-sass), users-api (Java 8) pin old, sometimes unpatchable deps | Bump what's fixable; record upstream-unfixable findings as documented exceptions (FR-002), never disable the scan. |
| Contract-first on pre-existing code | Implementations predate any contract | Author contracts to current behavior, then add conformance checks; treat genuine mismatches as bugs to fix, not contract fudging. |
| E2E/perf/DAST need a running stack | Heavier gates require the services up together | Use a docker-compose stack in CI; sequence these gates last, after unit/contract/integration are green. |

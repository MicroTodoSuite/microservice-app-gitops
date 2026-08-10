# Implementation Plan: Reusable CI and GitOps Delivery for All Services

**Branch**: `003-reusable-cicd-delivery` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-reusable-cicd-delivery/spec.md`

## Summary

Replace the five copy-pasted, Azure-imperative service pipelines with a single set of **reusable GitHub Actions workflows** hosted in the `.github` org repository and consumed by each service through a ~10-line caller. Each image is **built once**, scanned, inventoried (SBOM) and **signed keyless**, then promoted **by immutable digest** through dev → staging → prod via **automated pull requests to `microservice-app-gitops`** (using the existing `scripts/bump-image.sh` digest contract) — never by mutating a cluster. The full section-9 gate set is cabled as jobs, with dependency-free gates active and test/contract-dependent gates present-but-skippable. Finally, the four remaining services (`todos-api`, `users-api`, `frontend`, `log-message-processor`) are onboarded into gitops following the established `service-onboarding-contract.md`, with managed overlays left as inactive scaffolds. The cloud legs (ECR push, OIDC-to-AWS) are fully designed but inactive behind placeholders, exactly as task 3 left `ECR_REGISTRY_PLACEHOLDER`; validation runs today against GHCR.

## Technical Context

**Language/Version**: CI in GitHub Actions YAML (reusable `workflow_call`) + Bash composite steps. Service build toolchains (from verified Dockerfiles): Go 1.23.4 (auth-api), Node 20.18 (todos-api), Java 8 / Maven 3.9 (users-api), Node 14 build → nginx-unprivileged 1.27 (frontend), Python 3.11 (log-message-processor).

**Primary Dependencies**: GitHub Actions reusable workflows; `docker buildx`; Trivy (image scan); Syft (SBOM); Cosign (keyless/OIDC signing); SonarCloud (quality gate); semantic-release (version + changelog); `peter-evans/create-pull-request` (cross-repo promotion PR); gitops `scripts/bump-image.sh` (digest-only update). Deferred/skippable: Testcontainers, Spectral/Pact, Cypress/Playwright, Locust, OWASP ZAP.

**Storage**: Container registry as artifact store — GHCR now (active), ECR later (placeholder). No database.

**Testing**: Pipeline-level validation via `act` dry-runs and render/lint of workflows; gitops-side validation via `kustomize build` + `kubeconform` + secret scans. No service unit/integration tests authored in this feature (gates scaffolded, defaulted off).

**Target Platform**: GitHub-hosted `ubuntu-latest` runners; delivery target is the ArgoCD-reconciled kind cluster (local pilot) now, EKS later.

**Project Type**: Multi-repo CI/CD + GitOps delivery. Three surfaces: (1) `.github` reusable workflows, (2) five service repos (thin callers + retire legacy), (3) `microservice-app-gitops` (onboard four services).

**Performance Goals**: A service pipeline completes the active path (build → scan → SBOM → sign → open promotion PR) in a practical PR feedback window; promotion of an already-built digest requires no rebuild.

**Constraints**: GitOps-only (no CI-to-cluster mutation); immutable digest promotion (no `latest`); no static long-lived cloud credentials (OIDC only); no secret values in Git (ESO); all artifacts in English; cloud legs must activate by value change alone.

**Scale/Scope**: 5 service repos, 8 planned business-service slots, 3 reusable workflows, 4 service onboardings into gitops, 4 environments (local active; dev/staging/prod scaffolded).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | How this feature complies |
| --- | --- | --- |
| 2. GitOps-Only Deployment | **PASS** | CI opens PRs to gitops; no `kubectl apply`/cloud-CLI deploy. Legacy imperative `az containerapp update` is removed (FR-004/FR-009). |
| 3. Stable Trunk Development | **PASS** | Reusable workflows on trunk; promotion is reviewed PRs; short-lived branches (FR-029). |
| 4. Authoritative Specifications (contract-first) | **PARTIAL — tracked** | This feature adds no REST/event behavior; it scaffolds the contract-testing gate but does not author OpenAPI/AsyncAPI. Recorded in Complexity Tracking as deferred to a later feature. |
| 6. Immutable Build Promotion | **PASS** | Build once, sign one digest, promote same digest via gitops (FR-006/FR-008/FR-010). |
| 7. Progressive and Reversible Releases | **PARTIAL — tracked** | Prod approval gate delivered; metric-gated canary depends on the Argo Rollouts add-on (task 2), already scaffolded inactive in gitops. Rollback = git revert (FR-009). |
| 8. Quality and Supply-Chain Gates | **PASS (structurally)** | All gate categories cabled; dependency-free gates active, test gates present-but-skippable (FR-013–FR-018). |
| 10. Least Privilege and Secret Hygiene | **PASS** | OIDC (no static creds), least-privilege automation identity for PRs, ESO for JWT, no secrets in Git (FR-019/FR-020). |
| 11. Declarative and Policy-Controlled Platform | **PASS (produces evidence)** | Emits Kyverno-verifiable signature; in-cluster verification/runtime security owned by task 2 (FR-022). |

No unjustified violations. Two partials are deliberate scope boundaries recorded below.

## Project Structure

### Documentation (this feature)

```text
specs/003-reusable-cicd-delivery/
├── plan.md              # This file
├── research.md          # Phase 0: decisions (arch, registry, OIDC, signing, promotion, per-service facts)
├── data-model.md        # Phase 1: entities (workflow inputs, image identifier, promotion PR, gate, ...)
├── quickstart.md        # Phase 1: how to validate the pipeline + onboarding without cloud
├── contracts/
│   ├── reusable-ci-workflow.md      # inputs/secrets/outputs of ci.yml, release.yml, promote.yml
│   ├── promotion-flow.md            # build-once → digest → PR → ArgoCD → promote/rollback contract
│   └── service-onboarding-values.md # per-service value table (port/health/config/secret/deps)
└── checklists/
    └── requirements.md  # (from /speckit-specify)
```

### Source Code (across repositories)

```text
# Repo: .github (org reusable workflows) — PRIMARY new artifact
.github/
└── workflows/
    ├── ci.yml            # reusable workflow_call: build-once + gates + SBOM + sign; outputs digest
    ├── release.yml       # reusable: semantic-release (version + changelog)
    └── promote.yml       # reusable: open digest-bump PR to gitops (dev), promote staging/prod
# plus composite actions:
.github/actions/
    ├── setup-stack/      # per-language (go/node/java/python) build+test setup
    ├── sbom/             # Syft SBOM generation
    └── sign/             # Cosign keyless signing

# Repo: each service (auth-api, todos-api, users-api, frontend, log-message-processor)
.github/workflows/
    ├── ci.yml            # THIN caller: uses .github/ci.yml@vX with {service-name, language}
    └── release.yml       # THIN caller: uses .github/release.yml@vX
#   development.yml (legacy Azure imperative) -> DELETED (FR-027)

# Repo: microservice-app-gitops (onboard the 4 remaining services)
apps/todos-api/{base,components/topology-*,overlays/{local,dev,staging,prod}}/
apps/users-api/{base,components/topology-*,overlays/{local,dev,staging,prod}}/
apps/frontend/{base,components/topology-*,overlays/{local,dev,staging,prod}}/
apps/log-message-processor/{base,components/topology-*,overlays/{local,dev,staging,prod}}/
#   plus any shared local dependency (Redis) decision — see research.md
.github/workflows/validate-gitops.yml   # renders + kubeconform + secret scan (task-3 gap #3 lands here)
```

**Structure Decision**: Multi-repo. The reusable workflows are the center of gravity and live in `.github`; each service repo shrinks to thin callers; `microservice-app-gitops` gains four service definitions following the existing onboarding contract and a validation workflow. No new structure is invented in gitops — it reuses `apps/<svc>/{base,components,topology,overlays}` proven by auth-api.

## Complexity Tracking

| Deviation | Why needed | Why the stricter path is deferred, not skipped |
| --- | --- | --- |
| Contract-first OpenAPI/AsyncAPI (Principle 4) not authored | The five repos have zero API contracts today; authoring them for all services is a distinct initiative, not "refactor the pipelines". | The contract-testing gate is cabled and defaults skipped; a later feature authors the contracts and flips it on with no pipeline structural change (FR-016). |
| Metric-gated canary + Kyverno admission (Principles 7/11) not active | Argo Rollouts and Kyverno are platform add-ons owned by roadmap task 2 and not yet installed. | gitops already ships the canary component inactive; this feature produces the signature Kyverno will verify. Both activate when task 2 lands, by value/registration change only. |
| Test gates (unit/integration/e2e/perf/DAST) present but off | No tests exist in any service repo. | Gates are scaffolded and visibly skipped, not omitted; turning one on without artifacts fails visibly (FR-017). |
| Cloud legs (ECR/OIDC-AWS) inactive | Task 1 has not delivered ECR/EKS/OIDC. | Fully designed behind placeholders; GHCR validates the flow now; swap to ECR is a value change (FR-021, SC-009). |

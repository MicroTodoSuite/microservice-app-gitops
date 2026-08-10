---
description: "Task list for Reusable CI and GitOps Delivery for All Services"
---

# Tasks: Reusable CI and GitOps Delivery for All Services

**Input**: Design documents from `/specs/003-reusable-cicd-delivery/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: This feature deliberately does NOT author service unit/integration/
contract/e2e/perf/DAST tests (spec FR-018). "Validation" tasks below exercise the
pipeline and renders (actionlint, `act` dry-runs, `kustomize build`/`kubeconform`),
not new test suites.

**Multi-repo note**: Work spans three repos. Each task names its repo and path:
- `[.github]` → the `MicroTodoSuite/.github` org repo
- `[svc:<name>]` → that service's repo (e.g. `microservice-app-auth-api`)
- `[gitops]` → `microservice-app-gitops` (this repo)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no unmet dependency)
- **[Story]**: US1–US5 from spec.md; Setup/Foundational/Polish carry no story label

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare the org repo, identities, and external SaaS the pipelines need.

- [X] T001 [.github] Create reusable-workflow scaffolding: `.github/workflows/` and `.github/actions/` directories plus an `actionlint` config and a short `README` stub
- [X] T002 [P] [.github] Document the workflow version-pin policy (release tag `@vX` alias + optional SHA pin) from research D2 in `.github/README.md`
- [ ] T003 [P] [.github] Define and provision the least-privilege cross-repo automation identity (GitHub App or fine-grained token, `contents:write`+`pull_requests:write` on gitops only, research D9); store as org secrets `GITOPS_PROMOTE_APP_ID`/`GITOPS_PROMOTE_APP_KEY`
- [ ] T004 [P] [.github] Configure SonarCloud org + per-service project keys and store `SONAR_TOKEN` as an org secret (research D6)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared building blocks every story extends. **No user-story work may begin until this phase is complete.**

**⚠️ CRITICAL**: The reusable `ci.yml` backbone and composite actions are created here; stories add behavior onto them.

- [X] T005 [.github] Create composite action `setup-stack` (branches for `go`/`node`/`java`/`python`, fail-fast on unsupported) in `.github/actions/setup-stack/action.yml`
- [X] T006 [P] [.github] Create composite action `sbom` (Syft SPDX/CycloneDX, subject = image digest) in `.github/actions/sbom/action.yml`
- [X] T007 [P] [.github] Create composite action `sign` (Cosign keyless via OIDC, subject = image digest) in `.github/actions/sign/action.yml`
- [X] T008 [.github] Create the reusable `ci.yml` skeleton: `on: workflow_call` with the inputs/outputs from `contracts/reusable-ci-workflow.md` and the build-once core (`docker/build-push-action` → `image-digest`/`image-ref` outputs) in `.github/workflows/ci.yml` (depends on T005)
- [X] T009 [P] [gitops] Add the validation workflow `.github/workflows/validate-gitops.yml` (kustomize build all overlays + `kubeconform -strict` + committed-secret scan + tag/placeholder-in-active-overlay scan, no cluster creds) — research D15, closes task-3 gap

**Checkpoint**: `ci.yml` builds one image and emits a digest; composite actions exist; gitops PRs are guarded.

---

## Phase 3: User Story 1 - One reusable pipeline replaces copy-paste (Priority: P1) 🎯 MVP

**Goal**: Every service consumes one shared CI definition via a thin caller; legacy imperative pipelines are gone.

**Independent Test**: A service's `ci.yml` is a thin caller with no build/deploy logic; a single edit to `.github/ci.yml` changes all consumers; no `development.yml` remains (quickstart §1–§2, SC-001/SC-002/SC-010).

- [X] T010 [US1] Finalize centralization in `.github/workflows/ci.yml`: `service-name`+`language` inputs drive the run; unsupported `language` fails at `setup-stack` (FR-003)
- [X] T011 [P] [US1] [svc:auth-api] Replace `.github/workflows/development.yml` with a thin caller `.github/workflows/ci.yml` (`uses: MicroTodoSuite/.github/.github/workflows/ci.yml@v1`, `service-name: auth-api`, `language: go`) and delete the legacy file
- [X] T012 [P] [US1] [svc:todos-api] Same thin-caller replacement with `language: node` (also fix the `microservice-app-todo-api` typo where referenced)
- [X] T013 [P] [US1] [svc:users-api] Same thin-caller replacement with `language: java`
- [X] T014 [P] [US1] [svc:frontend] Same thin-caller replacement with `language: node`
- [X] T015 [P] [US1] [svc:log-message-processor] Same thin-caller replacement with `language: python`
- [X] T016 [US1] Validate centralization: `actionlint` on all callers, confirm zero build/deploy logic in callers, and confirm no `development.yml`/static-cloud-login/imperative-deploy remains in any service (quickstart §1–§2)

**Checkpoint**: Copy-paste retired; one pipeline definition governs all five services.

---

## Phase 4: User Story 2 - Build once and promote the same digest via Git (Priority: P1)

**Goal**: One build produces one immutable digest, promoted dev→staging→prod through gitops PRs, prod gated by approval, rollback by revert.

**Independent Test**: A merge yields one digest; an automated PR bumps only the dev overlay; staging/prod PRs copy the identical digest; prod needs approval; no cluster is mutated (quickstart §5, SC-003/SC-004/SC-005).

- [X] T017 [US2] Implement reusable `release.yml` (semantic-release → version + changelog + `released`/`version` outputs) in `.github/workflows/release.yml` (research D11)
- [X] T018 [US2] Implement reusable `promote.yml` in `.github/workflows/promote.yml`: clone gitops → `scripts/bump-image.sh <service> <env> <digest>` → `peter-evans/create-pull-request`; dev auto, staging/prod on request; per `contracts/promotion-flow.md`
- [X] T019 [US2] Wire each service caller to run `release.yml` then `promote.yml` (env=dev) on merge to main, passing `ci.yml`'s `image-digest`, in each `[svc:*]/.github/workflows/` (extends T011–T015)
- [ ] T020 [US2] [gitops] Add branch protection / ruleset so changes to `apps/*/overlays/prod/**` require approval before merge (FR-008); document in `docs/`
- [ ] T021 [US2] Validate: digest identical across dev/staging/prod PRs, each PR scoped to one overlay, concurrent promotions don't collide, zero cluster mutation (quickstart §5)

**Checkpoint**: The CI→ArgoCD delivery flow works build-once, digest-only, GitOps-only.

---

## Phase 5: User Story 3 - Full quality-and-supply-chain gate structure (Priority: P2)

**Goal**: Every constitution gate category is a stage; dependency-free gates enforce, test-dependent gates are present-but-skippable.

**Independent Test**: A run shows all gate categories; build/quality/scan run and can fail; unit/integration/contract/e2e/perf/dast show as skipped by default; enabling one without artifacts fails visibly (quickstart §4, SC-006).

- [X] T022 [US3] Add active gates to `.github/workflows/ci.yml`: code-quality (SonarCloud, requires `sonar-project-key`) and image-scan (Trivy on the built image, blocking) — FR-014
- [X] T023 [US3] Add skippable gate jobs to `.github/workflows/ci.yml`: `run-unit`/`run-integration`/`run-contract`/`run-e2e`/`run-perf`/`run-dast` (default false, visibly skipped, fail-fast when true with no artifacts) — FR-015/FR-017
- [ ] T024 [US3] Validate gate presence/visibility and fail-fast behavior via `act` dry-run and a forced `run-unit=true` no-artifact run (quickstart §4)

**Checkpoint**: The pipeline is structurally complete per §9 and honest about what it verifies.

---

## Phase 6: User Story 4 - Onboard the remaining services into gitops (Priority: P2)

**Goal**: todos-api, users-api, frontend, log-message-processor all use the same base/overlay onboarding contract with managed overlays inactive.

**Independent Test**: Each service renders and conforms; base is environment-neutral; active overlays use digests; managed overlays inactive; worker uses `/metrics` health; JWT services share one secret (quickstart §6, SC-008).

- [X] T025 [P] [US4] [gitops] Onboard `apps/todos-api/` (base + `components/topology-*` + `overlays/{local,dev,staging,prod}`) per `contracts/service-onboarding-values.md` (port 8082, health `/metrics`, Redis dep, JWT)
- [X] T026 [P] [US4] [gitops] Onboard `apps/users-api/` (port 8083, health `/actuator/health`, JWT, no runtime dep)
- [X] T027 [P] [US4] [gitops] Onboard `apps/frontend/` (port 8080, health `/`, `AUTH_API_ADDRESS`/`TODOS_API_ADDRESS` overlay values, no secret)
- [X] T028 [P] [US4] [gitops] Onboard `apps/log-message-processor/` (worker; Prometheus `/metrics` on `PORT` as intrinsic health, Redis dep, no inbound API) — FR-026
- [ ] T029 [US4] [gitops] Wire shared-JWT ESO in the `local` overlays of auth-api/todos-api/users-api so all three consume the same generated value (research D13) — depends on T025, T026
- [X] T030 [US4] [gitops] Document the shared local Redis dependency handling (kept out of `apps/<svc>`, environment/platform-owned) in `docs/` (research D14)
- [X] T031 [US4] [gitops] Validate: `kustomize build | kubeconform` for every new overlay, confirm managed overlays inactive and digest-only active overlays (quickstart §6)

**Checkpoint**: All business services travel the same delivery contract; only auth-api is activated locally.

---

## Phase 7: User Story 5 - Verifiable evidence without unbuilt infrastructure (Priority: P3)

**Goal**: Produce SBOM + keyless signature now; design ECR/OIDC legs fully but inactive, activatable by value change.

**Independent Test**: With cloud disabled the run still produces an SBOM and identity-based signature with no static creds; ECR/OIDC legs are gated and skipped; enabling later is value-only (quickstart §3, SC-007/SC-009).

- [X] T032 [US5] Wire the `sbom` and `sign` composite actions into `.github/workflows/ci.yml`'s active path (subject = image digest) — FR-019
- [X] T033 [US5] Add gated cloud legs to `.github/workflows/ci.yml`: OIDC-to-AWS (`aws-actions/configure-aws-credentials`, `id-token: write`) + ECR push, behind `cloud-enabled` (default false) — research D4/FR-020/FR-021
- [X] T034 [US5] [gitops] Confirm the GHCR→ECR switch is value-only: `newName` in overlays + `registry`/`cloud-enabled` workflow inputs, no structural edits (SC-009)
- [ ] T035 [US5] Validate: SBOM + signature produced for the digest, zero static credentials, cloud leg skipped when `cloud-enabled=false` (quickstart §3)

**Checkpoint**: Supply-chain evidence is emitted and cloud-ready; activation awaits tasks 1/2 by value change only.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T036 [P] [gitops] Update `README.md`/`AGENTS.md` and `docs/` to describe the CI→ArgoCD delivery flow and the four onboarded services
- [X] T037 [P] [.github] Add usage docs for the reusable workflows (inputs, pin policy, enabling a skipped gate) in `.github/README.md`; ensure all artifacts are English (FR-028)
- [ ] T038 Run the full `quickstart.md` end-to-end against GHCR with the cloud legs inactive and record results

---

## Dependencies & Execution Order

```text
Phase 1 Setup
  -> Phase 2 Foundational (ci.yml backbone + composite actions + gitops validation)
     -> US1 Centralization (P1, MVP)
        -> US2 Build-once/promote (P1)   [needs ci.yml digest output]
        -> US3 Gate structure (P2)       [extends ci.yml]
        -> US5 Evidence + cloud-inactive (P3) [extends ci.yml]
     -> US4 Onboard services (P2)        [gitops-only; parallel to the .github stories]
        -> Phase 8 Polish
```

- **US4 is largely independent** of the workflow stories (it changes gitops `apps/*`), so it can proceed in parallel with US1–US3/US5 once Foundational (T009 validation workflow) is done.
- **US2 depends on US1** (callers) and the `ci.yml` digest output (T008/T010).
- **US3 and US5 both extend `ci.yml`**; sequence T022→T023 then T032→T033 to avoid editing the same file simultaneously.

## Parallel Opportunities

- Setup: T002, T003, T004 in parallel.
- Foundational: T006, T007, T009 in parallel (T005 before T008).
- US1: T011–T015 in parallel (five different service repos).
- US4: T025–T028 in parallel (four different `apps/<svc>` trees); T029 after T025/T026.

## Implementation Strategy

### MVP (US1)

1. Phase 1 Setup → Phase 2 Foundational → Phase 3 US1.
2. **Stop and validate**: copy-paste retired, one edit propagates, no legacy imperative deploy. That alone retires the core debt.

### Incremental delivery

1. Foundation → US1 (centralization MVP).
2. + US2 → build-once/promote to gitops (the delivery mechanism).
3. + US3 → full honest gate structure.
4. + US4 → all services onboarded (can run in parallel from step 1).
5. + US5 → supply-chain evidence + cloud-ready-inactive.
6. Polish → docs + full quickstart validation.

## Notes

- `[P]` = different files/repos, no unmet dependency; never two edits to the same file at once (US3/US5 both touch `ci.yml` → keep serial).
- No service test suites or API contracts are authored here (FR-018); test gates ship scaffolded-and-skipped.
- Cloud push/deploy (ECR/EKS/OIDC) and Kyverno verification stay inactive; they belong to roadmap tasks 1 and 2 and activate by value change.
- Commit after each task or logical group; keep branches short-lived (FR-029).

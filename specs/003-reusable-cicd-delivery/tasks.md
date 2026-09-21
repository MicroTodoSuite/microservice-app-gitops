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

> **Reconciliation 2026-08-30.** T003 and T004 were ticked against verified
> evidence: the organization runs both GitHub Apps (`microtodo-gitops-promoter`,
> `microtodosuite-ci-release`) and SonarCloud with per-service project keys
> (`MicroTodoSuite_auth-api`) passed through the reusable `ci.yml`. The six that
> remain are real: T020 (no path-scoped ruleset exists on gitops, and its stated
> path is stale — prod overlays now live under `profiles/economical/overlays/`),
> T029 (only auth-api has a `local` ExternalSecret), and T021/T024/T035/T038,
> which require observed runs. Detail in
> `microservice-app-docs/full-platform/plan-reconciliation.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no unmet dependency)
- **[Story]**: US1–US5 from spec.md; Setup/Foundational/Polish carry no story label

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare the org repo, identities, and external SaaS the pipelines need.

- [X] T001 [.github] Create reusable-workflow scaffolding: `.github/workflows/` and `.github/actions/` directories plus an `actionlint` config and a short `README` stub
- [X] T002 [P] [.github] Document the workflow version-pin policy (release tag `@vX` alias + optional SHA pin) from research D2 in `.github/README.md`
- [X] T003 [P] [.github] Define and provision the least-privilege cross-repo automation identity (GitHub App or fine-grained token, `contents:write`+`pull_requests:write` on gitops only, research D9); store as org secrets `GITOPS_PROMOTE_APP_ID`/`GITOPS_PROMOTE_APP_KEY`
- [X] T004 [P] [.github] Configure SonarCloud org + per-service project keys and store `SONAR_TOKEN` as an org secret (research D6)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared building blocks every story extends. **No user-story work may begin until this phase is complete.**

**Critical**: The reusable `ci.yml` backbone and composite actions are created here; stories add behavior onto them.

- [X] T005 [.github] Create composite action `setup-stack` (branches for `go`/`node`/`java`/`python`, fail-fast on unsupported) in `.github/actions/setup-stack/action.yml`
- [X] T006 [P] [.github] Create composite action `sbom` (Syft SPDX/CycloneDX, subject = image digest) in `.github/actions/sbom/action.yml`
- [X] T007 [P] [.github] Create composite action `sign` (Cosign keyless via OIDC, subject = image digest) in `.github/actions/sign/action.yml`
- [X] T008 [.github] Create the reusable `ci.yml` skeleton: `on: workflow_call` with the inputs/outputs from `contracts/reusable-ci-workflow.md` and the build-once core (`docker/build-push-action` → `image-digest`/`image-ref` outputs) in `.github/workflows/ci.yml` (depends on T005)
- [X] T009 [P] [gitops] Add the validation workflow `.github/workflows/validate-gitops.yml` (kustomize build all overlays + `kubeconform -strict` + committed-secret scan + tag/placeholder-in-active-overlay scan, no cluster creds) — research D15, closes task-3 gap

**Checkpoint**: `ci.yml` builds one image and emits a digest; composite actions exist; gitops PRs are guarded.

---

## Phase 3: User Story 1 - One reusable pipeline replaces copy-paste (Priority: P1), MVP

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
- [X] T020 [US2] [gitops] Add branch protection / ruleset so changes to `apps/*/overlays/prod/**` require approval before merge (FR-008); document in `docs/`

  > **Delivered.** The task's stated path is stale (reconciliation note
  > above, 2026-08-30): prod overlays now live under
  > `apps/*/profiles/*/overlays/prod/**`, not `apps/*/overlays/prod/**`.
  > `CODEOWNERS` designates `@Juanmadiaz45`/`@EstebanGZam`/`@Tiago0507`
  > as owners of that corrected path, `tests/contract/prod-overlay-approval.sh`
  > verifies it (wired into `validate-gitops.yml`, and tightened 2026-09-21 to
  > assert the exact three owners rather than just any `@`-handle after a
  > Copilot review finding), and `docs/service-delivery.md` records the
  > design. `require_code_owner_reviews` was enabled on `main`'s live branch
  > protection 2026-09-21, confirmed via
  > `gh api repos/MicroTodoSuite/microservice-app-gitops/branches/main/protection`.
- [X] T021 [US2] Validate: digest identical across dev/staging/prod PRs, each PR scoped to one overlay, concurrent promotions don't collide, zero cluster mutation (quickstart §5)

  > **Delivered.** Audited the fifteen real `promote.yml` pull requests merged
  > 2026-09-14 (`gitops#150`-`#164`, five services x dev/staging/prod):
  > digest identical across all three environments for every service, each PR
  > touches exactly one overlay file, zero file-level collisions across the
  > sixteen-minute concurrent merge window, and zero CI path that mutates a
  > cluster. See `evidence/runs/20260920T231206Z-promotion-validation/README.md`.

**Checkpoint**: The CI→ArgoCD delivery flow works build-once, digest-only, GitOps-only.

---

## Phase 5: User Story 3 - Full quality-and-supply-chain gate structure (Priority: P2)

**Goal**: Every constitution gate category is a stage; dependency-free gates enforce, test-dependent gates are present-but-skippable.

**Independent Test**: A run shows all gate categories; build/quality/scan run and can fail; unit/integration/contract/e2e/perf/dast show as skipped by default; enabling one without artifacts fails visibly (quickstart §4, SC-006).

- [X] T022 [US3] Add active gates to `.github/workflows/ci.yml`: code-quality (SonarCloud, requires `sonar-project-key`) and image-scan (Trivy on the built image, blocking) — FR-014
- [X] T023 [US3] Add skippable gate jobs to `.github/workflows/ci.yml`: `run-unit`/`run-integration`/`run-contract`/`run-e2e`/`run-perf`/`run-dast` (default false, visibly skipped, fail-fast when true with no artifacts) — FR-015/FR-017
- [X] T024 [US3] Validate gate presence/visibility and fail-fast behavior via `act` dry-run and a forced `run-unit=true` no-artifact run (quickstart §4)

  > **Delivered, with a reconciliation and a real defect found and fixed.**
  > `run-unit` no longer exists (retired when the architecture moved to one
  > mandatory `test-command`); local `act` proved impractical (20+ minutes
  > pulling a runner image without finishing) and was abandoned for real
  > GitHub Actions runs instead. Found live: `test-command: ""` made "Run
  > repository tests" report `success` having tested nothing -- a real FR-017
  > violation. Fixed in `.github#27` (guard step, SDD test-then-feat pair in
  > `tests/workflows/reusable-workflow-contract.bats`), re-verified live
  > post-fix: the guard now fails and "Run repository tests" is correctly
  > skipped. Value-activated gates (`source-audit-command`,
  > `contract-command`, Sonar fail-closed) already skip/fail visibly, unaffected.
  > Also ran quickstart §1/§2/§6/§7 against current repos (T038's scope) since
  > they were exercised anyway. See
  > `evidence/runs/20260921T000000Z-gate-visibility-validation/README.md`.

**Checkpoint**: The pipeline is structurally complete per §9 and honest about what it verifies.

---

## Phase 6: User Story 4 - Onboard the remaining services into gitops (Priority: P2)

**Goal**: todos-api, users-api, frontend, log-message-processor all use the same base/overlay onboarding contract with managed overlays inactive.

**Independent Test**: Each service renders and conforms; base is environment-neutral; active overlays use digests; managed overlays inactive; worker uses `/metrics` health; JWT services share one secret (quickstart §6, SC-008).

- [X] T025 [P] [US4] [gitops] Onboard `apps/todos-api/` (base + `components/topology-*` + `overlays/{local,dev,staging,prod}`) per `contracts/service-onboarding-values.md` (port 8082, health `/metrics`, Redis dep, JWT)
- [X] T026 [P] [US4] [gitops] Onboard `apps/users-api/` (port 8083, health `/actuator/health`, JWT, no runtime dep)
- [X] T027 [P] [US4] [gitops] Onboard `apps/frontend/` (port 8080, health `/`, `AUTH_API_ADDRESS`/`TODOS_API_ADDRESS` overlay values, no secret)
- [X] T028 [P] [US4] [gitops] Onboard `apps/log-message-processor/` (worker; Prometheus `/metrics` on `PORT` as intrinsic health, Redis dep, no inbound API) — FR-026
- [X] T029 [US4] [gitops] Wire shared-JWT ESO in the `local` overlays of auth-api/todos-api/users-api so all three consume the same generated value (research D13) — depends on T025, T026

  > **Already implemented at the base-manifest layer; this closes the missing
  > overlay-level test and doc coverage the 2026-08-30 reconciliation flagged.**
  > `auth-api`'s `overlays/local` is the only one with an ESO `Password`
  > generator + `ExternalSecret` (`auth-api-secrets`/`JWT_SECRET`); `todos-api`
  > and `users-api`'s base `Deployment` already read that exact Secret by name
  > (a same-namespace reference needs no `ExternalSecret` of its own), and
  > `scripts/pilot/publish-services.sh` already publishes `auth-api` first so
  > the Secret exists before its consumers start. New:
  > `tests/contract/shared-jwt-local.sh` (wired into `validate-gitops.yml`)
  > guards both halves -- the shared source exists, and neither consumer
  > silently provisions its own -- and `docs/service-delivery.md`'s "Shared
  > JWT secret" section is rewritten from "tracked follow-up" to the resolved
  > design. **Flagged, not fixed (out of scope here)**: `tests/contract/service-onboarding.sh`
  > is broken on `main` (`apps/todos-api/topology/kustomization.yaml` no
  > longer exists; the tree moved to `profiles/economical|full/`) and is wired
  > into no CI workflow, so nothing catches it. It predates this task and
  > needs its own owner.
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
- [X] T035 [US5] Validate: SBOM + signature produced for the digest, zero static credentials, cloud leg skipped when `cloud-enabled=false` (quickstart §3)

  > **Delivered, with a reconciliation.** `cloud-enabled` no longer exists as
  > an input on `.github/workflows/ci.yml` -- once real AWS infrastructure
  > existed, the optional-cloud-leg design was retired and every run
  > unconditionally publishes to ECR via OIDC, so there is no disabled leg
  > left to prove is skipped. Audited a real push-to-main run
  > (`microservice-app-auth-api` run 34875097673, job 104080217231,
  > 2026-09-14): Syft SBOM produced and uploaded, two Sigstore transparency-log
  > entries confirm a keyless Cosign signature and SBOM attestation, signature
  > pushed to the real ECR, and the only AWS credential is an
  > OIDC `role-to-assume` (short-lived STS, GitHub-masked, never a stored
  > key -- `ci.yml` references no `secrets.AWS_*` anywhere). See
  > `evidence/runs/20260920T233500Z-sbom-signature-validation/README.md`.

**Checkpoint**: Supply-chain evidence is emitted and cloud-ready; activation awaits tasks 1/2 by value change only.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T036 [P] [gitops] Update `README.md`/`AGENTS.md` and `docs/` to describe the CI→ArgoCD delivery flow and the four onboarded services
- [X] T037 [P] [.github] Add usage docs for the reusable workflows (inputs, pin policy, enabling a skipped gate) in `.github/README.md`; ensure all artifacts are English (FR-028)
- [X] T038 Run the full `quickstart.md` end-to-end against GHCR with the cloud legs inactive and record results

  > **Delivered, with a reconciliation.** GHCR and a disableable cloud leg no
  > longer exist -- once real AWS infrastructure existed, every run
  > unconditionally publishes to ECR via OIDC (same reconciliation as T035).
  > Ran every section of `quickstart.md` that still applies against the
  > current repos rather than a GHCR/cloud-disabled mode that no longer
  > exists: §1 (workflow contract, actionlint), §2 (thin callers, no
  > `development.yml`, all five services), §3 (superseded by T035's real
  > SBOM/signature/OIDC evidence, stronger than the original dry-run intent),
  > §4 (T024, found and fixed a real gate-visibility defect), §5 (superseded
  > by T021's real fifteen-PR promotion audit), §6 (render/kubeconform for
  > all four onboarded services, shared-JWT), §7 (`validate-gitops.yml` runs
  > on every PR, structurally proven by this repository's own history). See
  > `evidence/runs/20260921T000000Z-gate-visibility-validation/README.md`.
- [X] T039 [P] [svc:all] Bump the five service repositories' `promote.yml` pin
  past `.github`#22. They pin `promote.yml@d0da1aef`, the commit before the one
  that made automated promotion pull requests carry the six sections
  `scripts/conventions/validate-pr.py` requires, so every promotion pull request
  is born with a red `conventions` check: gitops#191, #192, #193, #195, #196,
  and #198 all failed it, and their bodies were rewritten by hand on 2026-09-20.
  Verify with a promotion pull request opened by the bumped workflow whose
  `conventions` check passes without a hand edit.

  > **Delivered.** All five pins bumped (frontend#34, auth-api#33, users-api#33,
  > todos-api#30, log-message-processor#33), merged 2026-09-21. Verified with
  > gitops#213 (`promote(frontend): economical/staging`), opened by
  > `app/microtodo-gitops-promoter` after the bump: mechanical body untouched,
  > `conventions` check passes without a hand edit.

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

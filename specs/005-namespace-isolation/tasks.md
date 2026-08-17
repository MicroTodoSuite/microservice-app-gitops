# Tasks: Shared-Cluster Isolation and Environment Publication

**Input**: Design documents from `specs/005-namespace-isolation/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/`, and `quickstart.md`

**Tests**: Static, CI, Terraform, render, supply-chain, and live outcome tests are
required by the specification. No live item is complete without cited evidence.

**Organization**: Shared release prerequisites are foundational. User Story 5
is implemented first among equal P1 stories because the requested business
workloads must exist before continuity and isolation can be verified against
them. Story numbers remain identical to `spec.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel after its stated dependency because it changes a
  different repository or non-overlapping files.
- **[Story]**: Exact user story from `spec.md`.

## Phase 1: Setup and Evidence Contracts

**Purpose**: Preserve local work, lock exact baselines, and make later evidence
machine-valid before implementation changes begin.

- [X] T001 Record all eight repository branches, worktrees, clean/dirty state, remote `main` SHAs, five failing workflow URLs, live EKS context, AWS caller, Argo CD inventory, node allocatable capacity, and platform requests in `specs/005-namespace-isolation/checklists/acceptance.md`
- [X] T002 Update phase names, CLI options, release input handling, and non-mutating command guards in `scripts/managed/verify-namespace-isolation.sh`
- [X] T003 Update shared collection/redaction helpers for release, ESO, RollingSync, and Rollout evidence in `scripts/managed/lib/namespace-isolation.sh`
- [X] T004 [P] Add valid/invalid schema fixtures for version 2.0.0 in `tests/fixtures/namespace-isolation/evidence/`
- [X] T005 Update schema and observer contract coverage in `tests/contract/namespace-isolation-evidence.sh`
- [X] T006 Run the observer in `baseline` mode and cite its immutable output in `specs/005-namespace-isolation/checklists/acceptance.md`

---

## Phase 2: Foundational Release Prerequisites

**Purpose**: Establish reviewed AWS ownership, least-privilege identities,
truthful CI, and GitOps release controls while business activation remains empty.

**CRITICAL**: T007-T034 block every business Application.

### AWS source ownership and Terraform identity

- [X] T007 Open, review, and merge the existing `esteban/eks-dev-foundation` source into `microservice-app-ops/main`, recording the PR and merge SHA in `specs/005-namespace-isolation/checklists/acceptance.md`
- [X] T008 Document the exact missing Terraform-role permissions and a least-privilege remediation scoped to current foundation roles plus the new feature roles in `../microservice-app-ops/aws/environments/dev/backend/README.md`
- [X] T009 Repair the `microtodosuite-terraform-dev` execution policy through its reviewed bootstrap ownership path and record a successful `AWS_PROFILE=microtodosuite-terraform` check/refresh plan in `specs/005-namespace-isolation/checklists/acceptance.md`

### Terraform tests first

- [X] T010 [P] Add failing assertions for five additive neutral repositories and preservation of five legacy repositories in `../microservice-app-ops/aws/modules/environment-foundation/tests/ecr_irsa.tftest.hcl`
- [X] T011 [P] Add failing assertions for three write-only-generated secrets and exact-subject JWT reader roles in `../microservice-app-ops/aws/modules/environment-foundation/tests/managed_secrets.tftest.hcl`
- [X] T012 [P] Add failing assertions for GitHub OIDC main-branch trust and neutral-repository-only publisher permissions in `../microservice-app-ops/aws/modules/environment-foundation/tests/github_oidc.tftest.hcl`
- [X] T013 [P] Add failing assertions for Kyverno admission-controller IRSA and read-only neutral-ECR access in `../microservice-app-ops/aws/modules/environment-foundation/tests/kyverno-irsa.tftest.hcl`
- [X] T014 Extend shell contract checks for no static secret, no destructive ECR replacement, exact role subjects, and non-secret outputs in `../microservice-app-ops/tests/contract/aws-dev-foundation.sh`

### Terraform implementation

- [X] T015 Implement five immutable, encrypted, scan-on-push neutral repositories and lifecycle policies without changing `aws_ecr_repository.services` in `../microservice-app-ops/aws/modules/environment-foundation/ecr.tf`
- [X] T016 Implement three protected Secrets Manager entries, local ephemeral random passwords, write-only versions, exact OIDC trust subjects, and exact read policies in `../microservice-app-ops/aws/modules/environment-foundation/managed-secrets.tf`
- [X] T017 Implement the GitHub Actions OIDC provider, five-repository `main` trust conditions, and least-privilege ECR publisher/signature permissions in `../microservice-app-ops/aws/modules/environment-foundation/github-oidc.tf`
- [X] T018 Implement the Kyverno admission-controller IRSA role with neutral-ECR read-only verification permissions in `../microservice-app-ops/aws/modules/environment-foundation/kyverno-irsa.tf`
- [X] T019 Add typed feature inputs and validation for shared environments, service repositories, GitHub subjects, and secret version rotation in `../microservice-app-ops/aws/modules/environment-foundation/variables.tf`
- [X] T020 Expose only neutral repository URLs, secret names/ARNs, and IRSA role ARNs in `../microservice-app-ops/aws/modules/environment-foundation/outputs.tf`
- [X] T021 Wire new module inputs/outputs through `../microservice-app-ops/aws/environments/dev/foundation/main.tf`, `variables.tf`, `outputs.tf`, and `dev.tfvars.example`
- [X] T022 Run format, validate, module tests, contract tests, and a refresh-backed plan through `microtodosuite-terraform-dev`; require only expected additions and cite the plan in `specs/005-namespace-isolation/checklists/acceptance.md`
- [X] T023 Commit, push, and open the short-lived ops PR; after required review/checks, merge it and apply the exact reviewed saved plan through the intended Terraform role, recording caller, plan digest, apply result, and non-secret outputs in `specs/005-namespace-isolation/checklists/acceptance.md`

### Shared workflow safety

- [X] T024 Add reusable-workflow tests or static assertions proving PR runs cannot publish and push/sign depend on test, Trivy, and SBOM success in `../.github/tests/ci-contract.sh`
- [X] T025 Refactor the reusable pipeline into test -> one local build -> Trivy -> one SBOM -> AWS OIDC -> ECR push -> digest resolution -> Cosign sign in `../.github/.github/workflows/ci.yml`
- [X] T026 Add explicit service test/source-audit inputs, immutable commit-derived ECR handles, neutral repository input validation, and reviewed-main publication conditions in `../.github/.github/workflows/ci.yml`
- [X] T027 Run shared workflow contract validation, commit, push, open the organization workflow PR, obtain required review/checks, merge it, and record its immutable merge SHA in `specs/005-namespace-isolation/checklists/acceptance.md`

### GitOps prerequisite tests first

- [X] T028 Add failing contracts for progressive-sync enablement, EKS-only three-step RollingSync, `maxUpdate: 1`, and an empty activation list in `tests/contract/service-onboarding.sh`
- [X] T029 [P] Add failing add-on contracts for vendored Argo Rollouts 1.9.1, checksum, digest pin, namespace, controller health resources, and exact final infrastructure allowlist in `tests/contract/platform-addons.sh`
- [X] T030 [P] Add failing contracts for three namespaced ESO paths, exact IRSA annotations, no secret values, and no ClusterSecretStore in `tests/contract/namespace-isolation.sh`
- [X] T031 [P] Add failing contracts for five economical topology selections and five production Rollout/canary-Service/analysis renders in `tests/contract/service-onboarding.sh`
- [X] T032 [P] Add failing contracts for the approved quota table and steady-plus-largest-surge arithmetic in `tests/contract/namespace-isolation.sh`
- [X] T033 [P] Add failing Kyverno signature-policy contracts for neutral ECR, GitHub issuer/subjects, enforced failure action, and no broad bypass in `tests/contract/platform-addons.sh`
- [X] T034 Confirm T028-T033 fail for the intended missing capabilities while all pre-existing local-kind pilot contracts still pass; record results in `specs/005-namespace-isolation/checklists/acceptance.md`

**Checkpoint**: AWS prerequisites and truthful reusable CI exist; GitOps release
control tests fail only for capabilities not yet implemented; business activation
is still empty.

---

## Phase 3: User Story 5 - Publish One Verified Release Across All Environments (Priority: P1) 🎯

**Goal**: Produce five admissible artifacts, reconcile every deployment
prerequisite, then declare and progressively publish exactly fifteen Applications.

**Independent Test**: Five reviewed green commits map to five signed neutral-ECR
digests; all prerequisites are Ready with zero business Applications; one final
revision creates fifteen Applications and observed operations occur dev, then
staging, then prod with identical digests.

### Service fixes and tests

- [X] T035 [P] [US5] Add reproducible `go.mod`/`go.sum`, focused auth/user-service tests, patched Go toolchain/modules, and a non-root reproducible image build in `../microservice-app-auth-api/go.mod`, `go.sum`, `main_test.go`, `user_test.go`, and `Dockerfile`
- [X] T036 [P] [US5] Remove unused vulnerable production packages, update compatible Express/JWT/Redis dependencies, and add route/JWT/Redis regression tests in `../microservice-app-todos-api/package.json`, `package-lock.json`, and `test/`
- [X] T037 [P] [US5] Add an explicit Maven test/security update path while preserving the H2/API contract in `../microservice-app-users-api/pom.xml` and `src/test/java/com/elgris/usersapi/UsersApiApplicationTests.java`
- [X] T038 [P] [US5] Run lint/unit/source-lock audit, update vulnerable production dependencies without changing routes, and retain bundle dependency evidence in `../microservice-app-frontend/package.json`, `package-lock.json`, and `test/unit/`
- [X] T039 [P] [US5] Pin Python dependencies and add mock-based Redis/message/Zipkin/metrics tests without changing event behavior in `../microservice-app-log-message-processor/requirements.txt` and `tests/test_main.py`
- [X] T040 [US5] Pin the immutable shared workflow SHA and exact test/audit/repository inputs in all five `../microservice-app-*/.github/workflows/ci.yml` callers
- [X] T041 [US5] Run every service's local workflow-equivalent tests, dependency audit, Docker build, Trivy scan, and SBOM generation; record exact commands/results in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T042 [US5] Open five short-lived service PRs, obtain required review and green checks including the applicable Sonar/quality decision, merge only green descendants, and record PRs/merge SHAs in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T043 [US5] Observe five reviewed `main` publication runs and record tests, Trivy, SBOM, repository digest, keyless signature identity, and no publication from PR/failing baseline in `specs/005-namespace-isolation/checklists/acceptance.md`

### GitOps prerequisite implementation

- [X] T044 [US5] Patch `argocd-cmd-params-cm` and force a self-managed ApplicationSet-controller restart through a pod-template revision annotation in `bootstrap/argocd/kustomization.yaml`
- [X] T045 [US5] Vendor official Argo Rollouts 1.9.1, record upstream checksum, pin controller digest, and declare its namespace/root in `infrastructure/argo-rollouts/vendor/v1.9.1/`, `namespace.yaml`, and `kustomization.yaml`
- [X] T046 [US5] Add the bounded shared Job metric and canary health contract in `infrastructure/argo-rollouts/cluster-analysis-template.yaml`
- [X] T047 [US5] Annotate the Kyverno admission-controller ServiceAccount for its verifier IRSA and add enforcing approved-keyless-signature verification in `infrastructure/kyverno/kustomization.yaml` and `policies.yaml`
- [X] T048 [US5] Add reusable ESO ServiceAccount, SecretStore, and ExternalSecret resources in `environments/base/external-secrets-serviceaccount.yaml`, `secretstore.yaml`, `external-secret.yaml`, and `kustomization.yaml`
- [X] T049 [P] [US5] Inject exact dev JWT role ARN/source key values in `environments/dev/kustomization.yaml`
- [X] T050 [P] [US5] Inject exact staging JWT role ARN/source key values in `environments/staging/kustomization.yaml`
- [X] T051 [P] [US5] Inject exact prod JWT role ARN/source key values in `environments/prod/kustomization.yaml`
- [X] T052 [P] [US5] Replace dev ResourceQuota hard values with the approved table in `environments/dev/resourcequota.yaml`
- [X] T053 [P] [US5] Replace staging ResourceQuota hard values with the approved table in `environments/staging/resourcequota.yaml`
- [X] T054 [P] [US5] Replace prod ResourceQuota hard values with the approved table in `environments/prod/resourcequota.yaml`
- [X] T055 [P] [US5] Switch auth-api managed topology to economical and replace its inactive canary seam with workloadRef, canary Service, and analysis in `apps/auth-api/topology/kustomization.yaml` and `apps/auth-api/components/strategy-canary/`
- [X] T056 [P] [US5] Add the economical production canary component for todos-api in `apps/todos-api/topology/kustomization.yaml`, `components/strategy-canary/`, and `overlays/prod/kustomization.yaml`
- [X] T057 [P] [US5] Add the economical production canary component for users-api in `apps/users-api/topology/kustomization.yaml`, `components/strategy-canary/`, and `overlays/prod/kustomization.yaml`
- [X] T058 [P] [US5] Add the economical production canary component for frontend in `apps/frontend/topology/kustomization.yaml`, `components/strategy-canary/`, and `overlays/prod/kustomization.yaml`
- [X] T059 [P] [US5] Add the economical production canary component for log-message-processor in `apps/log-message-processor/topology/kustomization.yaml`, `components/strategy-canary/`, and `overlays/prod/kustomization.yaml`
- [X] T060 [US5] Add environment labels to the reusable app template and the EKS-only dev -> staging -> prod RollingSync strategy with `maxUpdate: 1` in `clusters/base/apps.yaml`, `clusters/eks-dev/rolling-sync-apps.yaml`, and `clusters/eks-dev/kustomization.yaml`
- [X] T061 [US5] Replace shared Redis with explicit Argo Rollouts in `clusters/eks-dev/activation-infrastructure.yaml` while keeping `clusters/local-kind/activation-infrastructure.yaml` unchanged
- [X] T062 [US5] Render/schema-validate all fifteen overlays, all three environment roots, Argo CD bootstrap, Argo Rollouts, and Kyverno; run every contract test and prove `clusters/eks-dev/activation-apps.yaml` remains empty
- [X] T063 [US5] Commit, push, open, review, and merge the GitOps prerequisite PR; wait for Argo CD and cite the exact revision, restarted progressive-sync controller, Rollouts CRDs/controller, five infrastructure Applications, three Ready ESO paths, new quotas, three Redis instances, and zero business Applications in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T064 [US5] Prove all three JWT destinations are non-empty and mutually distinct without printing values, and prove all six cross-environment source-secret reads are denied; cite redacted evidence in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T065 [US5] Prove Kyverno admits each approved signed neutral-ECR digest and rejects the GitOps-owned unsigned/wrong-identity fixture, then remove the fixture by Git revert and cite evidence in `specs/005-namespace-isolation/checklists/acceptance.md`

### Single activation and production evidence

- [X] T066 [US5] Replace registry placeholders/all-zero digests with the five exact neutral ECR URIs and identical per-service digests across all fifteen `apps/*/overlays/{dev,staging,prod}/kustomization.yaml` files
- [X] T067 [US5] Set dev, staging, and prod together in `clusters/eks-dev/activation-apps.yaml`; assert the render declares exactly fifteen generated Applications and no local-kind change
- [ ] T068 [US5] Commit, push, open, review, and merge the single activation PR; record its exact SHA and preserve the pre-merge dev continuity snapshot in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T069 [US5] Observe and record five serial Healthy dev operations before any staging operation, five serial Healthy staging operations before any prod operation, and five serial Healthy prod operations in `.local/evidence/namespace-isolation/`
- [X] T070 [US5] Verify all live business Pods are Ready, use the five reviewed image IDs, consume only same-environment secrets/Redis, and pass service health/contracts; cite results in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T071 [US5] Add only a production pod-template evidence annotation with unchanged digests in all five `apps/*/overlays/prod/kustomization.yaml`, merge the reviewed canary-evidence PR, and record five successful AnalysisRuns/Rollouts
- [ ] T072 [US5] Activate the failing analysis target through `tests/fixtures/namespace-isolation/canary-failure/`, observe Failed -> Aborted -> stable restored, recover by reviewed Git revert, and cite the exact revisions/events in `specs/005-namespace-isolation/checklists/acceptance.md`

**Checkpoint**: One reviewed release is running in all three environments with
identical signed digests; observed ordering and production canary/rollback are
proved live.

---

## Phase 4: User Story 1 - Layer Isolation Without Disrupting Development (Priority: P1)

**Goal**: Prove the layered controls and release caused no dev readiness,
restart, health, or required-connection regression.

**Independent Test**: Compare exact pre-prerequisite, pre-activation,
post-activation, post-canary, post-fixture, and final ten-minute dev samples.

- [X] T073 [US1] Extend continuity collection for five dev Applications, ready replicas, restarts, health endpoints, Redis, secret readiness, resource usage, and required connections in `scripts/managed/lib/namespace-isolation.sh`
- [X] T074 [US1] Add failing continuity-comparison coverage for readiness loss, restart deltas, wrong revisions, and failed required paths in `tests/contract/namespace-isolation-evidence.sh`
- [ ] T075 [US1] Run the complete continuity chain through final cleanup and cite zero policy/release-attributable loss in `specs/005-namespace-isolation/checklists/acceptance.md`

**Checkpoint**: Dev continuity is evidenced, not inferred from manifests.

---

## Phase 5: User Story 2 - Deny Cross-Environment Traffic by Default (Priority: P1)

**Goal**: Prove all directed cross-environment network and event paths are
denied while same-environment traffic, DNS, and Redis remain functional.

**Independent Test**: GitOps fixtures open new connections across all six
directions and unique Pub/Sub streams; all negatives and positives match.

- [X] T076 [P] [US2] Update Deployment-owned probe fixtures for live service/DNS targets and immutable images in `tests/fixtures/namespace-isolation/base/`
- [X] T077 [P] [US2] Update three environment fixture overlays and exact no-cross-environment selectors in `tests/fixtures/namespace-isolation/overlays/`
- [X] T078 [US2] Extend observer collection for six new-session denials, three same-environment calls, three DNS checks, six Redis denials, and three Pub/Sub isolation results in `scripts/managed/lib/namespace-isolation.sh`
- [ ] T079 [US2] Activate fixtures by reviewed Git commit, observe all directed outcomes live, and cite raw logs/timestamps in `specs/005-namespace-isolation/checklists/acceptance.md`

**Checkpoint**: Network and Redis isolation pass with positive controls.

---

## Phase 6: User Story 3 - Contain Resource Exhaustion (Priority: P2)

**Goal**: Prove one namespace cannot exceed its declared bound or disturb a
comparison environment.

**Independent Test**: A GitOps-owned Deployment exceeds one exact quota bound;
Kubernetes records the expected admission/ReplicaSet event while comparison
workloads retain readiness and restart counts.

- [X] T080 [P] [US3] Update the deliberate over-budget Deployment to exceed one approved dev bound deterministically in `tests/fixtures/namespace-isolation/quota-violation/deployment.yaml`
- [X] T081 [US3] Add event/pod-realization and comparison-environment assertions in `scripts/managed/lib/namespace-isolation.sh`
- [ ] T082 [US3] Activate the quota fixture by reviewed commit, capture the violated bound/event and unaffected staging/prod workloads, then remove it by Git revert and cite evidence in `specs/005-namespace-isolation/checklists/acceptance.md`

**Checkpoint**: Resource exhaustion is contained live.

---

## Phase 7: User Story 4 - Enforce Environment-Scoped Modification Rights (Priority: P2)

**Goal**: Prove exact Kubernetes group permissions while honestly retaining the
deferred AWS-principal mapping gap.

**Independent Test**: Every environment group is allowed only its workload
verbs in its own namespace, denied in the other two and on isolation controls;
an unbound subject is denied everywhere.

- [X] T083 [US4] Expand static Role/RoleBinding matrix coverage for all three groups, every namespace, protected isolation kinds, platform access, and an unbound subject in `tests/contract/namespace-isolation.sh`
- [X] T084 [US4] Extend read-only authorization-review collection and explicit principal-mapping status in `scripts/managed/lib/namespace-isolation.sh`
- [X] T085 [US4] Execute the complete Kubernetes group matrix live, cite results, and leave AWS-principal mapping acceptance unchecked in `specs/005-namespace-isolation/checklists/acceptance.md`

**Checkpoint**: Kubernetes RBAC is proved; deferred AWS identity mapping remains
an explicit acceptance blocker rather than a shared-role workaround.

---

## Phase 8: Polish, Cleanup, and Final Evidence

**Purpose**: Return fixtures to zero, validate every artifact, and publish an
accurate final report.

- [X] T086 [P] Update managed-cluster operator documentation, stage order, rollback rules, data-loss limits, and no-direct-mutation examples in `docs/namespace-isolation.md`
- [X] T087 [P] Update add-on and service-onboarding documentation for Argo Rollouts, neutral ECR, ESO, and RollingSync in `clusters/README.md` and `infrastructure/argo-rollouts/README.md`
- [X] T088 Run all GitOps contract tests, Kustomize renders, schema validation, local pilot contracts, Terraform tests, five service tests/builds, and shared workflow contract checks; cite the consolidated result in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T089 Verify all temporary canary/isolation/quota/signature fixtures are absent after Git revert and all twenty-three final Argo CD Applications (root, Argo CD, five infrastructure, three environment, fifteen business) are Synced/Healthy at expected revisions
- [ ] T090 Run the final observer phase and validate `summary.json` against `contracts/namespace-isolation-evidence.schema.json`; preserve raw evidence under `.local/evidence/namespace-isolation/`
- [ ] T091 Audit `specs/005-namespace-isolation/checklists/acceptance.md` so every checked item cites specific evidence, every unmet item remains unchecked with its blocker, and no secret value or unsupported claim appears
- [ ] T092 Commit and push only the intended feature artifacts on a clean short-lived GitOps branch, open the final evidence PR, and record PRs, live outcomes, rollback state, and the remaining maintainer-mapping blocker in `specs/005-namespace-isolation/checklists/acceptance.md`

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1**: starts immediately and locks evidence contracts.
- **Phase 2**: depends on Phase 1 and blocks every business Application.
- **Phase 3 / US5**: depends on all Phase 2 AWS, workflow, and static tests.
- **Phase 4 / US1**: uses the Phase 3 release as the continuity subject.
- **Phase 5 / US2**: depends on Phase 3 workloads and can run alongside Phase 4
  observation once activation is stable.
- **Phase 6 / US3**: depends on Phase 3 quotas/workloads and can run after the
  network fixture is cleaned up.
- **Phase 7 / US4**: depends only on reconciled RBAC but is scheduled after
  activation for the final live matrix.
- **Phase 8**: depends on all selected story evidence and cleanup reverts.

### User story dependency graph

```text
Foundation -> US5 publication -> US1 continuity
                         |-----> US2 network/event isolation
                         |-----> US3 resource containment
                         `-----> US4 live RBAC matrix
US1 + US2 + US3 + US4 + US5 -> Final cleanup/evidence
```

### Parallel opportunities

- T010-T013 Terraform tests target different files.
- T028-T033 GitOps contracts target separable capability groups.
- T035-T039 service remediation occurs in five different repositories.
- T049-T054 environment values target six independent files.
- T055-T059 production canary components target five independent service trees.
- T076-T077 fixture base/overlay work can proceed independently.

## Parallel Example: User Story 5

```text
Task T035: repair/authenticate auth-api gates in microservice-app-auth-api
Task T036: repair/authenticate todos-api gates in microservice-app-todos-api
Task T037: repair/authenticate users-api gates in microservice-app-users-api
Task T038: repair/authenticate frontend gates in microservice-app-frontend
Task T039: repair/authenticate log processor gates in microservice-app-log-message-processor
```

These branches may be developed independently after the immutable shared
workflow contract exists. Publication and GitOps activation remain serialized.

## Implementation Strategy

### Requested MVP

The practical MVP for this session is Phase 1 + Phase 2 + Phase 3 (US5): all
five services running as one progressive release in three already-isolated
namespaces. It is not accepted until production canary evidence passes.

### Complete acceptance

After the release is stable, execute US1-US4 evidence fixtures one at a time,
clean each with Git revert, validate the final schema, and report the deferred
AWS maintainer mapping as open unless separately authorized identities are
provided.

## Notes

- Every Kubernetes correction is GitOps; every AWS correction is Terraform.
- A merge/apply/deployment task is complete only after its required review and
  live evidence, not when a manifest exists locally.
- Never print JWT values or store them in Git, plan, state, logs, or evidence.
- Stop on unexpected Terraform destructive changes, failed quality gates,
  wrong image identity, out-of-order sync, readiness loss, or failed isolation.

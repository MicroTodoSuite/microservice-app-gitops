# Tasks: Local GitOps Pilot Reconciliation

**Input**: Design documents from `/specs/001-local-gitops-pilot/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/`, and `quickstart.md`

**Scope**: Close reconciliation report gaps 3 through 10 only. Preserve the
existing App-of-Apps, ApplicationSet, and `auth-api` base/overlay baseline. Do
not run implementation as part of task generation.

**Acceptance reconciliation (2026-08-09)**: Checkboxes now follow
[checklists/acceptance.md](./checklists/acceptance.md). A task is checked only
when its **DONE** row cites the specific source or retained evidence file that
proves it. Partial, open, and superseded tasks remain unchecked; the feature as
a whole remains only partially accepted.

**Tests**: The specification requires measurable clean-run, commit/revert,
uncommitted-edit, health, exactly-one-service, conformance, and operator
evidence. Test/harness tasks are therefore mandatory and appear before the
implementation they validate.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel because it changes different files and has no
  unmet dependency on another task in the same parallel group.
- **[Story]**: Maps the task to User Story 1 through 4 from `spec.md`.
- Every task names the exact repository path(s) it creates or changes.

## Phase 1: Setup (Shared Local-Pilot Assets)

**Purpose**: Establish tracked, pinned inputs and common test/script structure
without creating a cluster or changing desired state.

- [x] T001 Extend `.gitignore` for `.local/`, pilot port-forward state, temporary clones, and test scratch while retaining the transitional `apps/auth-api/base/secret-values.local.env` ignore until ESO conversion
- [ ] T002 Create `bootstrap/local/assets.lock` with verified versions, upstream references, platforms, file checksums, and OCI manifest/index digests for Kind, the node image, Distribution, the Git HTTP helper, ArgoCD, Dex, Redis, ESO, and every rendered controller image
- [x] T003 [P] Vendor Argo CD 3.5.0 into `bootstrap/argocd/vendor/v3.5.0/install.yaml`, `bootstrap/argocd/vendor/v3.5.0/SHA256SUMS`, and `bootstrap/argocd/vendor/v3.5.0/README.md`, then point `bootstrap/argocd/kustomization.yaml` at the local manifest
- [ ] T004 [P] Vendor External Secrets Operator 2.7.0 into `infrastructure/external-secrets/vendor/v2.7.0/`, record checksum/provenance in `infrastructure/external-secrets/vendor/v2.7.0/README.md`, and create `infrastructure/external-secrets/kustomization.yaml`
- [ ] T005 [P] Add the digest-pinned Kind and local-registry topology in `bootstrap/local/kind-config.yaml` and `bootstrap/local/registry/hosts.toml`, including loopback-only port mappings and the containerd registry alias before cluster creation
- [ ] T006 [P] Create strict-mode logging, redaction, exact-target, and assertion helpers in `scripts/pilot/lib/common.sh` and `tests/lib/assert.sh`

---

## Phase 2: Foundational (Blocking GitOps Platform)

**Purpose**: Provide the fully local source/registry, reusable cluster
registration, declarative controller/environment ownership, and audited
bootstrap that every story requires.

**CRITICAL**: No user-story task may activate `auth-api` until this phase proves
ESO healthy and proves zero business workloads exist.

- [ ] T007 [P] Write failing asset-lock, offline-availability, digest, and vendored-manifest contract checks in `tests/contract/local-assets.sh`
- [ ] T008 [P] Write the failing clean-bootstrap/idempotency test in `tests/integration/bootstrap-boundary.sh`, asserting only the two constitutionally allowed direct mutations, root/platform health, and zero business workloads
- [ ] T009 Implement host/resource/tool/port/Docker preflight and its JSON result contract in `scripts/pilot/preflight.sh`
- [ ] T010 Implement acquisition, checksum/digest verification, controller-image discovery, and one-time `auth-api` build in `scripts/pilot/acquire-assets.sh` using `bootstrap/local/assets.lock`
- [ ] T011 Implement safe lifecycle helpers for the bare repository, `post-update`, read-only HTTP source, loopback registry, Kind network, local `pilot` remote, and disposable worktree in `scripts/pilot/lib/runtime.sh`
- [ ] T012 Extract the retained root, self-management, infrastructure, environment, and Matrix application mechanism into `clusters/base/kustomization.yaml`, `clusters/base/apps.yaml`, `clusters/base/argocd.yaml`, `clusters/base/infrastructure.yaml`, and `clusters/base/environment.yaml`
- [ ] T013 Create a disabled-by-default, value-only registration in `clusters/local-kind/kustomization.yaml`, `clusters/local-kind/registration.yaml`, and `clusters/local-kind/root-app.yaml` for repository URL, revision, destination, namespace, environment, registry, and capacity
- [ ] T014 Replace the wildcard project with exact trust-boundary definitions in `clusters/base/projects/apps.yaml`, `clusters/base/projects/environment.yaml`, `clusters/base/projects/platform.yaml`, and `clusters/base/projects/default.yaml`, deriving platform kind permissions from the pinned render and forbidding `*/*`
- [ ] T015 Move namespace ownership into `clusters/base/environment/kustomization.yaml`, `resourcequota.yaml`, `limitrange.yaml`, `networkpolicy-default-deny.yaml`, `networkpolicy-allow-dns.yaml`, `networkpolicy-allow-health.yaml`, `serviceaccounts.yaml`, `roles.yaml`, and `rolebindings.yaml`
- [x] T016 Configure only implemented platform dependencies in `clusters/base/argocd.yaml` and `clusters/base/infrastructure.yaml`, make ArgoCD self-manage from vendored manifests, make ESO reconcile before workloads, and leave every placeholder add-on inactive
- [ ] T017 Implement `scripts/pilot/bootstrap.sh` to create the local source/registry/cluster, commit disabled connection values to `pilot main`, execute and audit only the vendored ArgoCD plus root-Application bootstrap exception, wait read-only for ArgoCD/environment/ESO health, and satisfy `tests/contract/local-assets.sh` plus `tests/integration/bootstrap-boundary.sh`

**Checkpoint**: The local repository and registry are machine-local, ArgoCD owns
all post-bootstrap state, ESO and environment controls are healthy, a rerun is
idempotent, and `auth-api` is absent.

---

## Phase 3: User Story 1 - Deploy auth-api from committed desired state (Priority: P1) MVP

**Goal**: Offer one immutable `auth-api` desired-state commit to the local Git
source and have ArgoCD alone make exactly that service synchronized, ready, and
healthy.

**Independent Test**: From the foundational checkpoint, run the publish and
verify interfaces. The recorded Git SHA must equal Argo's observed revision;
exactly one `auth-api` business workload must be ready; `/version` must succeed
three times over at least 60 seconds; no unsupported mutation may appear.

### Tests for User Story 1

- [ ] T018 [P] [US1] Write the failing `auth-api` base/local-overlay contract test in `tests/contract/auth-api-local.sh` for neutral base ownership, digest-only activation, ESO target compatibility, probes, labels, no-permission ServiceAccount, and exactly-one selection
- [ ] T019 [P] [US1] Write the failing end-to-end initial-deployment test in `tests/integration/initial-deploy.sh` for source availability, automatic Argo revision match, readiness, one-service count, repeated health, runtime locality, and prohibited-mutation audit

### Implementation for User Story 1

- [x] T020 [P] [US1] Normalize the retained workload in `apps/auth-api/base/deployment.yaml`, `service.yaml`, `configmap.yaml`, `serviceaccount.yaml`, and `kustomization.yaml`: English content, intrinsic probes, business-service labels, token-disabled account, neutral image key, and no Kind/capacity/provider values
- [ ] T021 [P] [US1] Create `apps/auth-api/overlays/local/kustomization.yaml`, `jwt-password.yaml`, `external-secret.yaml`, `configmap-patch.yaml`, and `deployment-patch.yaml` with local namespace/config/capacity, ESO `JWT_SECRET` output, and disabled all-zero digest placeholder that cannot be activated
- [x] T022 [US1] After T017 proves ESO healthy, remove `secretGenerator` and `generatorOptions` from `apps/auth-api/base/kustomization.yaml`, remove the transitional rule from `.gitignore`, and delete the ignored `apps/auth-api/base/secret-values.local.env` bridge without treating deletion as secret rotation
- [x] T023 [US1] Complete `clusters/base/apps.yaml` as the Matrix ApplicationSet that selects only `apps/*/overlays/{{ .environment }}`, uses exact application project/destination values, retains automated prune/self-heal, and labels generated business Applications for verification
- [x] T024 [P] [US1] Convert `scripts/bump-image.sh` to the digest-only contract: validate `sha256:[a-f0-9]{64}`, preserve `newName`, reject tags/placeholders/image IDs, render `newName@digest`, commit only, and never push or mutate a cluster
- [x] T025 [US1] Implement `scripts/pilot/publish-auth.sh` to push the acquired image locally, resolve the registry manifest/index digest, update and activate only the local overlay in the disposable pilot worktree, run contract checks, commit, and push only `pilot main`
- [ ] T026 [P] [US1] Implement schema-valid evidence/timeline/command-audit writers with secret redaction in `scripts/pilot/lib/evidence.sh` against `specs/001-local-gitops-pilot/contracts/pilot-evidence.schema.json`
- [x] T027 [US1] Implement `scripts/pilot/verify.sh` to compare local Git and Argo revisions, wait for sync/health/readiness, count exactly one labeled business service, perform three `/version` checks over 60 seconds, and retain all raw evidence
- [x] T028 [P] [US1] Document the historical JWT literal as compromised, list out-of-Git rotation actions and ownership, and explain the stable ESO target contract in `docs/secret-rotation.md` without reproducing the literal
- [ ] T029 [US1] Make `tests/contract/auth-api-local.sh` and `tests/integration/initial-deploy.sh` pass from a clean foundational checkpoint and store a schema-valid redacted example in `evidence/examples/initial-deploy/`

**Checkpoint**: User Story 1 is independently usable as the pilot MVP. The only
business service is `auth-api`, and its running state maps to the published
GitOps commit and immutable image digest.

---

## Phase 4: User Story 2 - Prove commit-only change and rollback (Priority: P2)

**Goal**: Prove uncommitted desired state has no effect and both an allowed
commit and a Git revert reconcile automatically within five minutes.

**Independent Test**: Starting from the healthy US1 checkpoint, a disposable
clone's uncommitted replica edit changes its render but not the served SHA,
Argo revision, or live replicas for 300 seconds. A later committed 1-to-2 replica
change reconciles, and its committed revert restores one replica, with linked
revision/timing evidence and no direct mutation.

### Tests for User Story 2

- [ ] T030 [P] [US2] Write the failing five-minute uncommitted-edit scenario in `tests/integration/uncommitted-edit.sh`
- [ ] T031 [P] [US2] Write the failing committed-change-and-revert scenario in `tests/integration/change-revert.sh`, including SHA lineage, two-replica convergence, one-replica restoration, and 300-second limits

### Implementation for User Story 2

- [ ] T032 [P] [US2] Implement `scripts/pilot/exercise-uncommitted.sh` with a disposable clone, divergent local render proof, five-minute unchanged-source/Argo/live observation, cleanup, and evidence output
- [ ] T033 [P] [US2] Implement `scripts/pilot/exercise-change-revert.sh` with an allowed replica commit, `pilot main` push, automatic convergence wait, normal `git revert`, second push, restoration wait, linked evidence, and explicit rejection of scale/patch/rollout-undo paths

**Checkpoint**: Git is proven authoritative for no-op uncommitted state, forward
change, and rollback rather than inferred from controller configuration.

---

## Phase 5: User Story 3 - Reuse the deployment contract (Priority: P3)

**Goal**: Prove seven additional service slots and future EKS registrations fit
the same hierarchy, value ownership, ApplicationSet, immutable promotion, and
verification mechanism without deploying another service.

**Independent Test**: Render the canonical `auth-api`, seven abstract service
slots, the local registration, and future EKS fixtures. All pass the same
contract; only declared service/environment/connection values differ; no fixture
becomes an active Application; production remains structurally disabled.

### Tests for User Story 3

- [ ] T034 [P] [US3] Write failing base/overlay ownership, label/health/secret, digest, and eight-slot render checks in `tests/conformance/service-contract.sh`
- [ ] T035 [P] [US3] Write failing shared-generator and value-only local/EKS registration checks in `tests/conformance/cluster-contract.sh`
- [ ] T036 [P] [US3] Write the failing multi-layer production gate in `tests/conformance/production-disabled.sh` for generator selection, exact AppProject namespace, and active-registration scanning

### Implementation for User Story 3

- [ ] T037 [P] [US3] Publish the ownership tables, onboarding procedure, and machine-replaceable Kustomize scaffold in `docs/service-onboarding.md` and `templates/service/base/` plus `templates/service/overlays/environment/`
- [ ] T038 [US3] Instantiate non-deployed `service-slot-02` through `service-slot-08` fixtures from the template under `tests/conformance/fixtures/service-slots/` without inventing real service identities
- [ ] T039 [P] [US3] Add value-only `local-kind`, `eks-dev`, `eks-staging`, and disabled `eks-prod` registration fixtures under `tests/conformance/fixtures/clusters/`
- [ ] T040 [US3] Implement all static and render assertions in `tests/conformance/service-contract.sh`, including rejection of base-owned environment values, committed secret material, tag-only images, missing intrinsic health, and fixture activation
- [ ] T041 [US3] Implement `tests/conformance/cluster-contract.sh` to prove every fixture reuses `clusters/base`, generates only its selected environment, preserves the promotion/verification mechanism, and changes only declared registration values
- [ ] T042 [US3] Remove `apps/auth-api/overlays/prod/resourcequota.yaml`, update `apps/auth-api/overlays/prod/kustomization.yaml`, `dev/kustomization.yaml`, and `staging/kustomization.yaml` as explicitly inactive digest-oriented managed-environment scaffolds, and keep all namespace policy under `clusters/base/environment/`
- [ ] T043 [US3] Document every blocking production prerequisite in `docs/production-readiness.md` and make `tests/conformance/production-disabled.sh` pass without enabling Argo Rollouts, metric providers, admission policy, or production dependencies
- [ ] T044 [US3] Implement the aggregate reusable-contract, secret/digest, AppProject wildcard, English-artifact, prohibited-mutation, and production gate runner in `scripts/pilot/conformance.sh`

**Checkpoint**: SC-007 has machine-checkable structural evidence for eight slots
and future cluster registrations, while the live pilot still has exactly one
business service and no production semantics.

---

## Phase 6: User Story 4 - Reproduce and diagnose the pilot (Priority: P4)

**Goal**: Give a first-time operator a short English workflow with explicit
preconditions, checkpoints, evidence, GitOps-preserving diagnostics, and safe
cleanup, then capture the required timing and operator evidence.

**Independent Test**: A clean-clone operator follows at most eight commands to a
passing health result within 20 minutes, can identify revision/sync/readiness/
health, receives actionable failure checkpoints without a direct-apply fallback,
and can remove only pilot-owned local resources. Three clean automated runs pass
within five minutes after source availability; two first-time operator records
score clarity at least 4/5.

### Tests for User Story 4

- [ ] T045 [US4] Write the failing clean-clone newcomer and evidence-schema test in `tests/integration/newcomer-workflow.sh`, enforcing command count, 20-minute elapsed time, local-only dependencies, expected checkpoints, troubleshooting guardrails, and exact cleanup targets

### Implementation for User Story 4

- [ ] T046 [US4] Implement `scripts/pilot/run-three-clean.sh` to repeat cleanup/bootstrap/publish/verify three times from retained local assets and aggregate source-to-sync/ready/healthy durations plus success rate
- [ ] T047 [P] [US4] Implement exact-target cleanup with pilot label/context/path validation and a recoverability report in `scripts/pilot/cleanup.sh`
- [x] T048 [P] [US4] Write the executable eight-command newcomer guide, expected checkpoints, read-only diagnostics, Git-fix/revert paths, and cleanup in `docs/local-pilot-quickstart.md`, and link it from `README.md`
- [ ] T049 [P] [US4] Create the first-time operator instructions and schema/template in `docs/operator-evaluation.md` and `evidence/operators/template.json`
- [ ] T050 [P] [US4] Document raw/summary retention, failure preservation, JSON-schema validation, secret redaction, and acceptance aggregation in `evidence/README.md`
- [ ] T051 [US4] Translate all retained Spanish comments, script messages, usage strings, and pilot documentation in `apps/auth-api/`, `clusters/`, `bootstrap/`, `scripts/`, and `README.md` to English without changing behavior beyond planned reconciliation
- [ ] T052 [US4] Execute three clean local runs through `scripts/pilot/run-three-clean.sh` and commit the schema-valid records under `evidence/runs/` only after checking that logs contain no secret values or unsupported mutation
- [ ] T053 [US4] Have two first-time operators execute `docs/local-pilot-quickstart.md` and commit their completed records under `evidence/operators/`, requiring no undocumented help, at most ten commands to health, correct state identification, and clarity ratings of at least 4/5
- [x] T054 [US4] Reconcile SC-001 through SC-009 against captured artifacts and record pass/fail plus evidence paths in `specs/001-local-gitops-pilot/checklists/acceptance.md` without converting missing runtime proof into a pass

**Checkpoint**: The pilot is reproducible, diagnosable, measurable, and safely
cleanable by someone without prior context.

---

## Phase 7: Polish & Cross-Cutting Validation

**Purpose**: Make contract drift visible before merge and perform the final
non-destructive acceptance review.

- [ ] T055 Add `.github/workflows/validate-gitops.yml` to run Kustomize renders, JSON-schema validation, shell tests, all conformance gates, asset-lock checks, secret-literal scans, and prohibited-mutation scans without cluster credentials or direct deployment
- [ ] T056 Run every contract/integration/conformance command documented in `specs/001-local-gitops-pilot/quickstart.md`, verify `git diff --check`, and record exact final results and any remaining blockers in `specs/001-local-gitops-pilot/checklists/acceptance.md`

---

## Dependencies & Execution Order

### Phase dependencies

```text
Phase 1 Setup
    -> Phase 2 Foundational
        -> US1 Deploy auth-api (MVP)
            -> US2 Commit/revert proof
            -> US3 Reuse conformance
            -> US4 Reproducibility evidence
                -> Phase 7 final validation
```

- **Setup** has no implementation dependency.
- **Foundational** depends on the locked/vendored Setup assets and blocks every
  user story.
- **US1** depends on healthy ESO and the zero-business-workload foundational
  checkpoint.
- **US2** depends on the healthy US1 state but is independently proven through
  disposable clones and its own evidence.
- **US3** depends on the canonical US1 base/local overlay as its reference
  instance; it never depends on or deploys another service.
- **US4** depends on the runnable US1 path; its final clean-run/operator evidence
  also consumes the US2 and US3 checks.
- **Polish** begins only after the selected stories' tests and evidence pass.

### Within-phase ordering

- Write each test task and confirm it fails for the expected missing behavior
  before implementing its paired scripts/manifests.
- Acquire and verify controller images before cluster creation.
- Reconcile ESO and observe it healthy before removing the ignored-file bridge
  or activating the `ExternalSecret` workload overlay.
- Create the environment namespace/policy before business Applications; do not
  rely on child-Application sync-wave annotations as a readiness guarantee.
- Resolve the registry manifest/index digest before committing active desired
  state.
- Make the forward commit healthy before creating its Git revert.
- Run fixture conformance without adding fixtures to an ApplicationSet path.

## Parallel Opportunities

### Setup and foundation

- T003, T004, T005, and T006 can run concurrently after the decisions in T002
  are fixed because they own separate paths.
- T007 and T008 can be authored concurrently before implementation.
- Manifest extraction (T012-T016) and host-side script foundations (T009-T011)
  can be split between contributors, then integrated in T017.

### User Story 1

```text
T018 auth-api contract test || T019 initial-deploy integration test
T020 reusable base          || T021 local overlay
T024 digest helper          || T026 evidence library || T028 rotation documentation
```

T025 integrates T021/T024 with the local runtime, and T027 integrates T026 with
the live cluster; T029 is the story checkpoint.

### User Story 2

```text
T030 uncommitted test       || T031 change/revert test
T032 uncommitted exercise   || T033 change/revert exercise
```

The two live exercises should run serially against a shared cluster unless each
is given its own clean pilot instance.

### User Story 3

```text
T034 service contract test  || T035 cluster contract test || T036 production gate test
T037 onboarding template    || T039 cluster fixtures
T040 service assertions     || T041 cluster assertions
```

T038 follows the completed template; T043 follows the production test; T044
aggregates every conformance path.

### User Story 4

```text
T047 cleanup script         || T048 quickstart || T049 operator form || T050 evidence policy
```

The real three-run and human-operator evidence tasks T052-T053 must use the
finished workflow and cannot be replaced by parallel synthetic records.

## Implementation Strategy

### MVP first

1. Complete Setup and Foundational phases.
2. Complete US1 through T029.
3. Stop and independently prove one commit, one Argo-observed revision, one
   ready business service, and repeated `/version` health.
4. Do not claim the full feature complete until US2-US4 evidence exists.

### Incremental delivery

1. **Foundation**: fully local source/registry plus audited controller/root
   bootstrap, ESO, and environment controls; no business service.
2. **US1 MVP**: immutable `auth-api` commit automatically reconciles and passes
   composite verification.
3. **US2**: authoritative uncommitted/change/revert proof.
4. **US3**: eight-slot and future-cluster reuse proof with production disabled.
5. **US4**: newcomer, three-run, operator, diagnostics, and cleanup evidence.
6. **Final validation**: enforce the same contracts in CI and reconcile all
   success criteria without running implementation shortcuts.

## Notes

- `[P]` never means two tasks may edit the same file concurrently.
- Local pilot commits and pushes are implementation behavior only; generating
  this task list performs neither.
- The old JWT literal remains compromised in history and requires external
  rotation even after T022 removes the transitional file bridge.
- Production, Argo Rollouts, full supply-chain policy, and additional business
  services remain inactive in this feature.
- Do not run `$speckit-implement` until this task list is reviewed and explicitly
  authorized.

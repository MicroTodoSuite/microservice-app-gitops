# Tasks: Shared-Cluster Namespace Isolation

**Input**: Design documents from `specs/005-namespace-isolation/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/`, `quickstart.md`

**Tests**: Static contract, schema, and live negative/positive tests are required
because the specification explicitly rejects manifest-only acceptance.

**Organization**: Tasks are grouped by user story. All boxes remain unchecked:
this turn produced planning artifacts only and did not implement or activate
namespace isolation.

## Phase 1: Authoritative and External Gates

**Purpose**: Prove that implementation is allowed and that the separately owned
cluster capabilities exist. A failed item stops all later tasks; it is not fixed
inside this feature.

- [ ] T001 Confirm `microservice-app-docs/main` contains the approved constitution v1.2.0 amendment, compare it byte-for-byte with `.specify/memory/constitution.md`, and record both revisions in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T002 Confirm the separately reviewed shared-cluster handoff and `clusters/eks-main` registration exist, verify their rendered/live state activates only the `dev|staging|prod` environment-policy list against `https://kubernetes.default.svc` and produces zero registration-generated business-service or infrastructure/add-on Applications, and record the owning revisions in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T003 Record read-only live evidence that the supported Amazon VPC CNI network-policy configuration and policy agent are enabled and ready on every eligible Linux EC2 node; stop if any node fails and update `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T004 Record the approved AWS-principal-to-group mappings for `microtodosuite:dev-maintainers`, `microtodosuite:staging-maintainers`, and `microtodosuite:prod-maintainers`, proving no principal receives an unintended environment group, in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T005 Capture the exact dev ArgoCD revision, applications, ready replicas, restart counts, health responses, requests/limits/use, and required connections without mutation; preserve raw observations under `.local/evidence/namespace-isolation/` and summarize them in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T006 Derive and review the three ResourceQuota/LimitRange budgets from allocatable capacity, system/platform use, dev demand, rollout surge, verification capacity, and disruption reserve; record the approved quantities and rationale in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T007 Resolve every required dev network allowance plus one immutable, pre-pulled or otherwise policy-compatible verification image digest; reject unknown endpoints, ports, selectors, or mutable tags and record the approved inputs in `specs/005-namespace-isolation/checklists/acceptance.md`

**Checkpoint**: Constitution, shared registration, CNI enforcement, identity,
dev continuity, capacity, dependency, and immutable-image gates are evidenced.
Until then, the implementation remains blocked.

---

## Phase 2: Test and Observer Foundations

**Purpose**: Encode the contract before adding managed environment desired state.

- [ ] T008 Create a failing static contract for exact namespace mapping, shared-base reuse, quota/limit fields, network invariants, RBAC groups/exclusions, immutable fixtures, local-environment preservation, and mutation-command rejection in `tests/contract/namespace-isolation.sh`
- [ ] T009 [P] Implement strict argument/context validation, phase dispatch, exit codes, timestamped output ownership, and executable mutation guards from the CLI contract in `scripts/managed/verify-namespace-isolation.sh`
- [ ] T010 [P] Implement read-only Kubernetes/Argo observation, redacted command logging, raw artifact custody, comparison helpers, JSON writing, and evidence-schema validation in `scripts/managed/lib/namespace-isolation.sh`
- [ ] T011 [P] Add operator-facing ownership, prerequisite, staged-rollout, rollback, evidence, and explicit non-guarantee guidance in `docs/namespace-isolation.md`
- [ ] T012 Run Bash syntax checks and the new static contract, confirm it fails only because the managed manifests and fixtures do not yet exist, and preserve the expected-failure output in the implementation review

**Checkpoint**: Tests fail for missing feature behavior, while observer code has
no managed-state mutation path.

---

## Phase 3: User Story 1 - Layer Isolation Without Disrupting Development (Priority: P1)

**Goal**: Reconcile namespace foundations and required allow rules before
default deny, with dev continuously matching its baseline.

**Independent Test**: All three environment Applications converge at the
foundation revision, default deny is absent, and dev loses zero ready replicas,
adds zero attributable restarts, and keeps every health/dependency check.

### Tests for User Story 1

- [ ] T013 [US1] Extend `tests/contract/namespace-isolation.sh` to require a common managed base while explicitly rejecting default deny from the Stage-1 render fixture
- [ ] T014 [P] [US1] Add expected foundation-phase evidence and dev baseline comparison cases to `scripts/managed/lib/namespace-isolation.sh`

### Implementation for User Story 1

- [ ] T015 [US1] Add the common LimitRange, DNS allowance, same-namespace allowance, and explicit custom workload Role—without default-deny activation—in `environments/base/kustomization.yaml`, `environments/base/limitrange.yaml`, `environments/base/networkpolicy-allow-dns.yaml`, `environments/base/networkpolicy-allow-intra-namespace.yaml`, and `environments/base/role.yaml`
- [ ] T016 [P] [US1] Add `microtodo-dev`, its evidence-approved ResourceQuota, exact dev maintainer RoleBinding, and only the approved required egress rules in `environments/dev/namespace.yaml`, `environments/dev/resourcequota.yaml`, `environments/dev/rolebinding.yaml`, `environments/dev/networkpolicy-allow-required-egress.yaml`, and `environments/dev/kustomization.yaml`
- [ ] T017 [P] [US1] Add `microtodo-staging`, its evidence-approved ResourceQuota, exact staging maintainer RoleBinding, and shared-base reference in `environments/staging/namespace.yaml`, `environments/staging/resourcequota.yaml`, `environments/staging/rolebinding.yaml`, and `environments/staging/kustomization.yaml`
- [ ] T018 [P] [US1] Add `microtodo-prod`, its evidence-approved ResourceQuota, exact prod maintainer RoleBinding, and shared-base reference in `environments/prod/namespace.yaml`, `environments/prod/resourcequota.yaml`, `environments/prod/rolebinding.yaml`, and `environments/prod/kustomization.yaml`
- [ ] T019 [US1] Make the Stage-1 render contract pass, run the pinned Kubernetes schema validator for all three overlays, and prove `environments/local` is byte-unchanged in `tests/contract/namespace-isolation.sh`
- [ ] T020 [US1] Reconcile the reviewed foundation revision through the normal PR/merge path, without manually syncing ArgoCD, and record exact `env-dev|env-staging|env-prod` revision/sync/health plus zero registration-generated business/infrastructure Application inventory under `.local/evidence/namespace-isolation/`
- [ ] T021 [US1] Run the observer's `foundation` phase against the recorded baseline, retain failures, and check the foundation/dev-continuity items only when `specs/005-namespace-isolation/checklists/acceptance.md` has live evidence

**Checkpoint**: Namespace foundations, budgets, RBAC, and explicit allow rules
are live; default deny is still absent; dev continuity passes.

---

## Phase 4: User Story 2 - Deny Cross-Environment Traffic by Default (Priority: P1)

**Goal**: Enforce ingress/egress default deny while retaining DNS and exact
same-environment/approved paths, then prepare six-direction live probes.

**Independent Test**: Every new directed connection among the three namespaces
is denied, while one same-environment connection and DNS resolution succeed in
each namespace.

### Tests for User Story 2

- [ ] T022 [US2] Change `tests/contract/namespace-isolation.sh` from the Stage-1 expectation to require one all-pod ingress/egress default deny in every managed render, exact DNS/same-environment rules, and zero broad cross-environment allowance
- [ ] T023 [P] [US2] Add table-driven checks for six unique denied directed pairs, three allowed same-environment pairs, three DNS successes, fresh connection timestamps, and CNI-agent completeness in `scripts/managed/lib/namespace-isolation.sh`

### Implementation for User Story 2

- [ ] T024 [US2] Add the common ingress-and-egress deny-all policy and reference it only in the Stage-2 revision through `environments/base/networkpolicy-default-deny.yaml` and `environments/base/kustomization.yaml`
- [ ] T025 [P] [US2] Add digest-pinned Deployment-owned probe server/client and ClusterIP Service resources in `tests/fixtures/namespace-isolation/base/`
- [ ] T026 [P] [US2] Add exact namespace/name/config overlays for dev, staging, and prod probes in `tests/fixtures/namespace-isolation/overlays/dev/kustomization.yaml`, `tests/fixtures/namespace-isolation/overlays/staging/kustomization.yaml`, and `tests/fixtures/namespace-isolation/overlays/prod/kustomization.yaml`
- [ ] T027 [US2] Make the final network static contract pass, schema-validate all steady-state and fixture renders, and prove probe images use the approved immutable digest in `tests/contract/namespace-isolation.sh`
- [ ] T028 [US2] Reconcile the reviewed default-deny revision through the normal PR/merge path only after the foundation checkpoint passes, then wait for all three environment Applications at the exact SHA
- [ ] T029 [US2] Run the observer's `default-deny` phase, require a real allowed and denied new-connection enforcement proof plus unchanged dev continuity, and revert the Stage-2 Git revision if any gate fails

**Checkpoint**: Default deny is live and enforced, required dev paths still work,
and the declarative six-direction fixtures are ready but not yet activated.

---

## Phase 5: User Story 3 - Contain Resource Exhaustion (Priority: P2)

**Goal**: Prove one environment cannot realize a workload beyond its approved
budget and another environment remains unaffected.

**Independent Test**: A GitOps-managed over-budget Deployment records the
expected quota/limit failure and excess pod absence while the comparison
environment remains ready, restart-stable, and healthy.

### Tests for User Story 3

- [ ] T030 [US3] Extend `tests/contract/namespace-isolation.sh` with positive quantity/order checks for every quota and LimitRange plus a fixture assertion that the requested violation exceeds exactly one approved bound
- [ ] T031 [P] [US3] Add Deployment/ReplicaSet/event realization checks and comparison-environment readiness/restart/health checks to `scripts/managed/lib/namespace-isolation.sh`

### Implementation for User Story 3

- [ ] T032 [US3] Add an opt-in, digest-pinned Deployment that deliberately exceeds the selected evidence-approved bound without requiring a direct API command in `tests/fixtures/namespace-isolation/quota-violation/kustomization.yaml` and `tests/fixtures/namespace-isolation/quota-violation/deployment.yaml`
- [ ] T033 [US3] Render and schema-validate the violation fixture, prove its expected pod request is above the named bound and its comparison workload is outside that namespace, and make the resource static contract pass in `tests/contract/namespace-isolation.sh`

**Checkpoint**: Resource-budget desired state and its negative fixture are
statically proven and ready for the combined live evidence revision.

---

## Phase 6: User Story 4 - Enforce Environment-Scoped Modification Rights (Priority: P2)

**Goal**: Prove each environment group has only its own workload permissions and
cannot change isolation controls.

**Independent Test**: The authorization matrix contains exactly three
own-environment workload allows, six cross-environment denies, isolation-control
denials for all groups, three unbound-subject denials, and the required ArgoCD
platform access observation.

### Tests for User Story 4

- [ ] T034 [US4] Extend `tests/contract/namespace-isolation.sh` to require exact distinct group subjects, namespaced RoleBindings, the approved workload API/resource/verb set, isolation-control and Secret exclusion, and no wildcard or `system:authenticated` grant
- [ ] T035 [P] [US4] Implement read-only authorization review collection for the 3-by-3 workload matrix, isolation controls, unbound subject, and ArgoCD platform principal in `scripts/managed/lib/namespace-isolation.sh`

### Implementation for User Story 4

- [ ] T036 [US4] Reconcile the reviewed workload Role verb/resource list with the approved access handoff, adjust only `environments/base/role.yaml` and the three environment RoleBindings as needed, and rerun the static matrix contract
- [ ] T037 [US4] Run the observer's RBAC checks against the live identity mapping, retain every raw authorization response, and stop rather than broadening a binding when observed access differs from the matrix

**Checkpoint**: Network, resource, and access isolation implementations are
ready for one correlated fixture run.

---

## Phase 7: Correlated Live Evidence, Cleanup, and Final Acceptance

**Purpose**: Activate only the declarative test fixtures, correlate all user
stories at one revision, remove fixtures by Git revert, and prove the steady
state.

- [ ] T038 Integrate phase results into schema-valid `summary.json`, enforce exact pair/group/environment completeness, zero mutation commands, and cleanup-revision semantics in `scripts/managed/verify-namespace-isolation.sh` and `scripts/managed/lib/namespace-isolation.sh`
- [ ] T039 Run Bash syntax, `tests/contract/namespace-isolation.sh`, existing `tests/contract/platform-addons.sh` and `tests/contract/service-onboarding.sh`, every managed/fixture render, the pinned schema validator, evidence-schema syntax/fixture validation, provider/secret/mutable-image scans, and `git diff --check`; fix every static failure
- [ ] T040 Create one minimal reviewed fixture-activation change that references the three network probe overlays and the quota-violation fixture from the appropriate environment Kustomizations, proving its diff contains no steady-state policy or real service/add-on activation
- [ ] T041 Reconcile the fixture activation through the normal PR/merge path, wait without manual sync for the exact fixture SHA, prove the only non-policy workloads are feature-005 fixtures, and preserve all Application, pod, Deployment, ReplicaSet, event, log, and dev-continuity observations
- [ ] T042 Run the observer's `fixtures` phase and accept it only if all six network denials, all six positive DNS/same-environment checks, the resource violation/comparison, full RBAC matrix, exact revisions, CNI agents, and dev continuity pass in one evidence set
- [ ] T043 Review `summary.json` against every raw artifact and `specs/005-namespace-isolation/contracts/namespace-isolation-evidence.schema.json`; retain a `FAIL` result unchanged if any raw observation disagrees
- [ ] T044 Remove only fixture activation with a reviewed `git revert`, wait for all three environment Applications to become Synced/Healthy at the cleanup SHA, and prove no probe or violation workload remains
- [ ] T045 Run the observer's `final` phase through the ten-minute continuity window, validate final evidence, and check acceptance items only when backed by the exact cleanup revision in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T046 Reconcile exact implemented paths, approved quota rationale, dependency allowances, identity groups, failure handling, and evidence location into `docs/namespace-isolation.md` and `specs/005-namespace-isolation/quickstart.md`
- [ ] T047 Re-run cross-artifact requirement/task traceability for FR-001 through FR-028 and SC-001 through SC-009, verify no unchecked prerequisite is reported as a pass, and record the final feature status in `specs/005-namespace-isolation/checklists/acceptance.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Authoritative/External Gates (Phase 1)**: Blocks every implementation task.
  Current repository evidence already shows T001-T004 are not yet satisfied.
- **Test/Observer Foundations (Phase 2)**: Begins only after Phase 1 and blocks
  managed manifest work.
- **US1 Foundation (Phase 3)**: Blocks default deny and all live negative tests.
- **US2 Network (Phase 4)**: Depends on a passing US1 live checkpoint and blocks
  fixture activation.
- **US3 Resource (Phase 5)**: Depends on the approved budgets from Phase 1 and
  the live foundation from US1; fixture authoring can proceed after those gates.
- **US4 RBAC (Phase 6)**: Depends on identity mapping and the live foundation;
  its observer logic can proceed in parallel with US3 fixture authoring.
- **Correlated Evidence (Phase 7)**: Depends on US1-US4 and performs the only
  fixture activation and final cleanup.

### User Story Dependencies

```text
external gates
      |
      v
US1 safe foundation
      |
      v
US2 default deny + network fixtures ----+
      |                                  |
      +--> US3 resource fixture ---------+--> correlated fixture revision
      |                                  |            |
      +--> US4 RBAC matrix --------------+            v
                                                   Git revert + final evidence
```

- US1 is independently accepted before default deny.
- US2 default-deny safety is independently accepted before fixture activation;
  its complete six-direction outcome is collected in the correlated run.
- US3 and US4 have independently inspectable outcomes within the same fixture
  evidence revision and do not depend on each other's implementation.
- No story can bypass Phase 1 by treating a manifest, branch, or local commit as
  live prerequisite evidence.

### Parallel Opportunities

- T009-T011 touch separate script/library/document files.
- T016-T018 create separate environment directories after T015 fixes the base
  contract.
- T025 and T026 separate fixture base from overlay values after the immutable
  image decision.
- T031 and T035 implement separate resource and authorization observers.
- Documentation may be drafted in parallel but is finalized only after command
  contracts and evidence paths are stable.

## Implementation Strategy

1. Close every external gate and preserve its evidence.
2. Write failing static/observer tests and prove there is no mutation path.
3. Deliver the namespace foundation without default deny and validate dev live.
4. Deliver default deny separately and validate dev plus real CNI enforcement.
5. Complete network/resource/RBAC fixtures and observers.
6. Activate fixtures in one reviewable revision and gather correlated evidence.
7. Revert fixtures, wait for cleanup convergence, and run final continuity.
8. Mark acceptance only from raw, schema-valid, exact-revision evidence.

## Notes

- A checked task means its named file or live result was actually verified.
- This task list does not authorize a push, PR, merge, AWS change, ArgoCD sync,
  or cluster mutation. Those actions still require the normal human review and
  repository permissions at execution time.
- If external prerequisites remain missing, keep this feature status blocked;
  do not add ops or cluster-registration implementation to these tasks.
- Empty staging/prod namespaces and temporary probes are not real workload
  activation.
- ResourceQuota reduces namespace blast radius but does not create dedicated
  nodes or eliminate the accepted shared-control-plane/noisy-neighbor risk.

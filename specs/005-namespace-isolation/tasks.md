# Tasks: Shared-Cluster Namespace Isolation

**Input**: Design documents from `specs/005-namespace-isolation/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/`, `quickstart.md`

**Tests**: Static contract, schema, and live negative/positive tests are required
because the specification explicitly rejects manifest-only acceptance.

**Organization**: Tasks are grouped by user story. Static implementation may
proceed after T001. The recorded operator decision allows policy-only foundation
activation while T004 and T005 remain explicit acceptance gaps; it does not
authorize maintainer access or business workloads. A checked box always cites
repository or live evidence.

## Phase 1: Authoritative and External Gates

**Purpose**: Prove that implementation is allowed and that the separately owned
cluster capabilities exist. Registration, CNI, capacity, and immutable inputs
gate foundation activation. Identity and business-workload continuity remain
required for their own final acceptance claims.

- [X] T001 Confirm `microservice-app-docs/main` contains the approved constitution v1.2.0 amendment, compare it byte-for-byte with `.specify/memory/constitution.md`, and record both revisions in `specs/005-namespace-isolation/checklists/acceptance.md` — Evidence: docs remote/local `615241ddf0280279d24c8df5faf5295bfed70ce0`; identical SHA-256 `14545ede9ee8d39b340b955e454c4500d3cdb30b108d74b3c1180534b6dbf3a4`
- [ ] T002 Confirm the existing `microtodosuite-dev` cluster and `clusters/eks-dev` registration are reviewed as the shared target, verify their rendered/live foundation state activates only the `dev|staging|prod` environment-policy list against `https://kubernetes.default.svc`, produces zero business-service Applications, and explicitly allowlists exactly `infra-keda|infra-cert-manager|infra-external-secrets|infra-kyverno|infra-redis`, then record the owning revisions in `specs/005-namespace-isolation/checklists/acceptance.md`
- [X] T003 Record read-only live evidence that the supported Amazon VPC CNI network-policy configuration and policy agent are enabled and ready on every eligible Linux EC2 node; stop if any node fails and update `specs/005-namespace-isolation/checklists/acceptance.md` — Evidence: on 2026-08-09 AWS reported VPC CNI `v1.23.0-eksbuild.1` `ACTIVE` with `enableNetworkPolicy=true`; `aws-node` desired/current/ready/available/updated was `2/2/2/2/2`, and both Linux-node pods had Ready `aws-node` and `aws-eks-nodeagent` containers with zero restarts
- [ ] T004 Record the approved AWS-principal-to-group mappings for `microtodosuite:dev-maintainers`, `microtodosuite:staging-maintainers`, and `microtodosuite:prod-maintainers`, proving no principal receives an unintended environment group, in `specs/005-namespace-isolation/checklists/acceptance.md`
- [ ] T005 Capture the exact dev ArgoCD revision, applications, ready replicas, restart counts, health responses, requests/limits/use, and required connections without mutation; preserve raw observations under `.local/evidence/namespace-isolation/` and summarize them in `specs/005-namespace-isolation/checklists/acceptance.md`
- [X] T006 Derive and review the policy-only ResourceQuota/LimitRange budgets from the observed 3860m CPU/14,549,840Ki memory allocatable envelope, 1226m/796Mi declared platform requests, three Redis instances, verification capacity, and disruption reserve; record exact quantities and the no-business-activation boundary in `specs/005-namespace-isolation/checklists/acceptance.md` — Evidence: exact budgets, 1550m/2048Mi aggregate request ceilings, inputs, reserve, and activation boundary are recorded in `research.md`, `docs/namespace-isolation.md`, and the checked acceptance item
- [ ] T007 Resolve every required dev network allowance plus immutable Redis/probe image digests and the namespace-local Redis endpoint contract; reject unknown endpoints, ports, selectors, mutable tags, or business-service activation and record the approved inputs in `specs/005-namespace-isolation/checklists/acceptance.md`

**Checkpoint**: Constitution is authoritative. Shared registration, durable CNI
configuration/enforcement, capacity, dependency, and immutable-image gates must
be evidenced before foundation activation. Deferred identity and unavailable
dev-business continuity evidence stay open and constrain the final claims.

---

## Phase 2: Test and Observer Foundations

**Purpose**: Encode the contract before adding managed environment desired state.

- [X] T008 Create a failing static contract for exact namespace mapping, shared-base reuse, quota/limit fields, network invariants, RBAC groups/exclusions, three environment-owned Redis instances, explicit infrastructure activation, immutable fixtures, local-environment preservation, and mutation-command rejection in `tests/contract/namespace-isolation.sh` — Evidence: initial execution failed only on missing `environments/base/kustomization.yaml`; final execution passes all named assertions
- [X] T009 [P] Implement strict argument/context validation, six-phase dispatch including `redis-retired`, exit codes, timestamped output ownership, and executable mutation guards from the CLI contract in `scripts/managed/verify-namespace-isolation.sh` — Evidence: Bash syntax, help, invalid-input exit 2, live fail-closed exit 4, six dispatch branches, and executable mutation scan passed
- [X] T010 [P] Implement read-only Kubernetes/Argo observation, Redis health/retirement/event isolation collection, redacted command logging, raw artifact custody, comparison helpers, JSON writing, and evidence-schema validation in `scripts/managed/lib/namespace-isolation.sh` — Evidence: identity-bound live run retained 33 raw commands with zero mutations; Bash/unit contracts pass for collectors, comparisons, phase summaries, cumulative composition, and Draft 2020-12 validation
- [X] T011 [P] Add operator-facing ownership, prerequisite, staged rollout, Redis migration, rollback, evidence, and explicit non-guarantee guidance in `docs/namespace-isolation.md` — Evidence: all named sections exist and distinguish foundation, deny, retirement, fixtures, and cleanup
- [X] T012 Run Bash syntax checks and the new static contract, confirm it fails only because the managed manifests and fixtures do not yet exist, and preserve the expected-failure output in the implementation review — Evidence: `bash -n` passed and the recorded red-phase output was `FAIL: required file is missing: environments/base/kustomization.yaml`

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

- [X] T013 [US1] Extend `tests/contract/namespace-isolation.sh` to require a common managed base while explicitly rejecting default deny from the Stage-1 render — Evidence: all three active foundation renders and fixtures contain the quota/RBAC/Redis/allow-rule base with zero `default-deny`; the deny manifest remains prepared for Stage 2
- [X] T014 [P] [US1] Add expected foundation-phase evidence and dev baseline comparison cases to `scripts/managed/lib/namespace-isolation.sh` — Evidence: `default_deny_count`, `redis_instances_ready`, `snapshot_dev_workloads`, and `compare_dev_baseline` are wired to the foundation gate

### Implementation for User Story 1

- [X] T015 [US1] Add the common LimitRange, DNS allowance, same-namespace allowance, explicit custom workload Role, and digest-pinned Redis ServiceAccount/Deployment/Service/policy—without default-deny activation—in `environments/base/kustomization.yaml`, `environments/base/limitrange.yaml`, `environments/base/networkpolicy-allow-dns.yaml`, `environments/base/networkpolicy-allow-intra-namespace.yaml`, `environments/base/networkpolicy-allow-redis.yaml`, `environments/base/redis-serviceaccount.yaml`, `environments/base/redis-deployment.yaml`, `environments/base/redis-service.yaml`, and `environments/base/role.yaml` — Evidence: every named resource renders/schema-validates in each namespace, and the foundation fixtures prove the complete base minus only the separately staged default-deny resource
- [X] T016 [P] [US1] Add `microtodo-dev`, its 400m/1200m CPU, 512Mi/1536Mi memory, 12-pod policy-only ResourceQuota, exact dev maintainer RoleBinding, and only approved egress rules in `environments/dev/namespace.yaml`, `environments/dev/resourcequota.yaml`, `environments/dev/rolebinding.yaml`, `environments/dev/networkpolicy-allow-required-egress.yaml`, and `environments/dev/kustomization.yaml` — Evidence: the Stage-1 render contains 12 schema-valid resources and the feature contract passes every exact value/selector assertion
- [X] T017 [P] [US1] Add `microtodo-staging`, its 500m/1500m CPU, 640Mi/2Gi memory, 14-pod policy-only ResourceQuota, exact staging maintainer RoleBinding, and shared-base reference in `environments/staging/namespace.yaml`, `environments/staging/resourcequota.yaml`, `environments/staging/rolebinding.yaml`, and `environments/staging/kustomization.yaml` — Evidence: the Stage-1 render contains 11 schema-valid resources and the feature contract passes every exact value/group assertion
- [X] T018 [P] [US1] Add `microtodo-prod`, its 650m/2 CPU, 896Mi/3Gi memory, 18-pod policy-only ResourceQuota, exact prod maintainer RoleBinding, and shared-base reference in `environments/prod/namespace.yaml`, `environments/prod/resourcequota.yaml`, `environments/prod/rolebinding.yaml`, and `environments/prod/kustomization.yaml` — Evidence: the Stage-1 render contains 11 schema-valid resources and the feature contract passes every exact value/group assertion
- [X] T019 [US1] Replace folder-wide infrastructure discovery with exact registration values in `clusters/base/infrastructure.yaml`, `clusters/local-kind/activation-infrastructure.yaml`, `clusters/eks-dev/activation-infrastructure.yaml`, and both registration Kustomizations; set managed todos-api/log-message-processor overlays to `REDIS_HOST=redis`; make the Stage-1 render/schema contract pass while proving `environments/local` and local Redis behavior are unchanged in `tests/contract/namespace-isolation.sh` — Evidence: both registrations render, explicit five/four lists pass, six managed overlays render `REDIS_HOST=redis`, local renders retain the FQDN, and `git diff --quiet HEAD -- environments/local` passes
- [ ] T020 [US1] Reconcile the reviewed foundation revision through the normal PR/merge path, without manually syncing ArgoCD, and record exact `env-dev|env-staging|env-prod` revision/sync/health, three Redis `PONG` results, zero business Applications, and the exact infrastructure inventory under `.local/evidence/namespace-isolation/`
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

- [ ] T022 [US2] Change `tests/contract/namespace-isolation.sh` from the Stage-1 expectation to require one all-pod ingress/egress default deny in every managed render, exact DNS/same-environment/Redis rules, namespace-local Redis endpoints, and zero broad cross-environment allowance — Pending: the foundation contract intentionally rejects active default deny
- [X] T023 [P] [US2] Add table-driven checks for six unique denied directed pod pairs, six denied directed Redis pairs, three allowed same-environment pairs, three DNS and Redis successes, three Pub/Sub source-isolation results, fresh connection timestamps, and CNI-agent completeness in `scripts/managed/lib/namespace-isolation.sh` — Evidence: exact unique-pair/source counters, 90-second freshness gate, source-only Pub/Sub parser, unexpected-allow rejection, and per-node policy-agent gate are wired into the fixtures phase

### Implementation for User Story 2

- [ ] T024 [US2] Add the common ingress-and-egress deny-all policy and reference it only in the Stage-2 revision through `environments/base/networkpolicy-default-deny.yaml` and `environments/base/kustomization.yaml` — Partial evidence: the reviewed deny manifest exists, but the Stage-1 Kustomization intentionally does not reference it
- [X] T025 [P] [US2] Add digest-pinned Deployment-owned probe server/client, Redis connection/PubSub clients, and ClusterIP Service resources in `tests/fixtures/namespace-isolation/base/` — Evidence: five-resource base renders with three probed Deployments, one Service, one ServiceAccount, immutable images, and Kyverno-compatible health probes
- [X] T026 [P] [US2] Add exact namespace/name/config overlays for dev, staging, and prod probes in `tests/fixtures/namespace-isolation/overlays/dev/kustomization.yaml`, `tests/fixtures/namespace-isolation/overlays/staging/kustomization.yaml`, and `tests/fixtures/namespace-isolation/overlays/prod/kustomization.yaml` — Evidence: all three overlays render with exact local and two foreign probe/Redis endpoints
- [ ] T027 [US2] Make the final network/Redis static contract pass, schema-validate all steady-state and fixture renders, and prove Redis/probe images use approved immutable digests in `tests/contract/namespace-isolation.sh` — Partial evidence: immutable fixture checks exist; final default-deny render checks resume in Stage 2
- [ ] T028 [US2] Reconcile the reviewed default-deny revision through the normal PR/merge path only after the foundation checkpoint passes, then wait for all three environment Applications at the exact SHA
- [ ] T029 [US2] Run the observer's `default-deny` phase, require real allowed/denied enforcement plus unchanged dev continuity, and revert the Stage-2 Git revision if any gate fails
- [ ] T030 [US2] Reconcile the reviewed managed infrastructure value that removes only `infra-redis`, run the observer's `redis-retired` phase, retain four healthy controller Applications and three healthy environment Redis instances, and revert the retirement revision if any gate fails

**Checkpoint**: Default deny is live and enforced, required dev paths still work,
shared `infra-redis` is retired, and declarative pod/Redis fixtures are ready
but not yet activated.

---

## Phase 5: User Story 3 - Contain Resource Exhaustion (Priority: P2)

**Goal**: Prove one environment cannot realize a workload beyond its approved
budget and another environment remains unaffected.

**Independent Test**: A GitOps-managed over-budget Deployment records the
expected quota/limit failure and excess pod absence while the comparison
environment remains ready, restart-stable, and healthy.

### Tests for User Story 3

- [X] T031 [US3] Extend `tests/contract/namespace-isolation.sh` with positive quantity/order checks for every quota and LimitRange plus a fixture assertion that the requested violation exceeds exactly one approved bound — Evidence: contract checks every quota/default/max and proves only the 600m CPU limit exceeds the 500m Container maximum while 25m/32Mi/64Mi remain in range
- [X] T032 [P] [US3] Add Deployment/ReplicaSet/event realization checks and comparison-environment Redis readiness/restart/`PONG` checks to `scripts/managed/lib/namespace-isolation.sh` — Evidence: fixture gate requires the dev Deployment and owned ReplicaSet, expected FailedCreate/max-CPU event, absent violation pod, and staging Redis Ready/restart-zero/PONG state

### Implementation for User Story 3

- [X] T033 [US3] Add an opt-in, digest-pinned Deployment that deliberately exceeds the selected evidence-approved bound without requiring a direct API command in `tests/fixtures/namespace-isolation/quota-violation/kustomization.yaml` and `tests/fixtures/namespace-isolation/quota-violation/deployment.yaml` — Evidence: opt-in dev fixture uses the approved digest and declares the expected LimitRange rejection annotation
- [X] T034 [US3] Render and schema-validate the violation fixture, prove its expected pod request is above the named bound and its comparison workload is outside that namespace, and make the resource static contract pass in `tests/contract/namespace-isolation.sh` — Evidence: kubeconform reports one valid resource; static checks prove the single CPU-max violation and no fixture reference exists in steady state

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

- [X] T035 [US4] Extend `tests/contract/namespace-isolation.sh` to require exact distinct group subjects, namespaced RoleBindings, the approved workload API/resource/verb set, isolation-control and Secret exclusion, and no wildcard or `system:authenticated` grant — Evidence: exact three-rule Role, three distinct groups, namespace scope, forbidden-resource, wildcard, broad-subject, and personal-ARN assertions all pass
- [X] T036 [P] [US4] Implement read-only authorization review collection for the 3-by-3 workload matrix, isolation controls, unbound subject, and ArgoCD platform principal in `scripts/managed/lib/namespace-isolation.sh` — Evidence: `collect_rbac_matrix` emits 28 expected/observed authorization records without changing a managed resource

### Implementation for User Story 4

- [ ] T037 [US4] Reconcile the reviewed workload Role verb/resource list with the approved access handoff, adjust only `environments/base/role.yaml` and the three environment RoleBindings as needed, and rerun the static matrix contract
- [ ] T038 [US4] Run the observer's RBAC checks against the live identity mapping, retain every raw authorization response, and stop rather than broadening a binding when observed access differs from the matrix

**Checkpoint**: Network, resource, and access isolation implementations are
ready for one correlated fixture run.

---

## Phase 7: Correlated Live Evidence, Cleanup, and Final Acceptance

**Purpose**: Activate only the declarative test fixtures, correlate all user
stories at one revision, remove fixtures by Git revert, and prove the steady
state.

- [X] T039 Integrate phase results into schema-valid `summary.json` v1.1.0, enforce exact pod/Redis pair, Pub/Sub/group/environment completeness, zero mutation commands, and cleanup-revision semantics in `scripts/managed/verify-namespace-isolation.sh` and `scripts/managed/lib/namespace-isolation.sh` — Evidence: exact predecessor chaining and final composition are implemented; `tests/contract/namespace-isolation-evidence.sh` produces and validates six phases, 6+6 pairs, 3 Pub/Sub sources, 28 RBAC checks, cleanup SHA, and zero mutations
- [X] T040 Run Bash syntax, `tests/contract/namespace-isolation.sh`, existing `tests/contract/platform-addons.sh` and `tests/contract/service-onboarding.sh`, every cluster/environment/app/fixture render, the pinned schema validator, evidence-schema syntax/fixture validation, provider/secret/mutable-image scans, and `git diff --check`; update legacy contracts only to distinguish local shared Redis from managed per-environment Redis and fix every static failure — Evidence: the complete chain, including `namespace-isolation-evidence.sh`, passed on 2026-08-09 with kubeconform v0.7.0/Kubernetes 1.35.0, zero invalid/errors, no mutable image/secret/provider finding, and clean whitespace
- [ ] T041 Create one minimal reviewed fixture-activation change that references the three network probe overlays and the quota-violation fixture from the appropriate environment Kustomizations, proving its diff contains no steady-state policy or real service/add-on activation
- [ ] T042 Reconcile the fixture activation through the normal PR/merge path, wait without manual sync for the exact fixture SHA, prove the only non-policy workloads are feature-005 fixtures, and preserve all Application, pod, Deployment, ReplicaSet, event, log, and dev-continuity observations
- [ ] T043 Run the observer's `fixtures` phase and accept it only if all six pod and six Redis network denials, all DNS/same-environment/Redis health checks, Pub/Sub separation, the resource violation/comparison, full RBAC matrix, exact revisions, CNI agents, and dev continuity pass in one evidence set
- [ ] T044 Review `summary.json` against every raw artifact and `specs/005-namespace-isolation/contracts/namespace-isolation-evidence.schema.json`; retain a `FAIL` result unchanged if any raw observation disagrees
- [ ] T045 Remove only fixture activation with a reviewed `git revert`, wait for all three environment Applications to become Synced/Healthy at the cleanup SHA, and prove no probe or violation workload remains
- [ ] T046 Run the observer's `final` phase through the ten-minute continuity window, validate final evidence, and check acceptance items only when backed by the exact cleanup revision in `specs/005-namespace-isolation/checklists/acceptance.md`
- [X] T047 Reconcile exact implemented paths, approved quota rationale, per-environment Redis migration, infrastructure allowlists, dependency allowances, identity groups, failure handling, and evidence location into `docs/namespace-isolation.md` and `specs/005-namespace-isolation/quickstart.md` — Evidence: runbook and quickstart contain the exact paths, staged five-to-four Redis migration, quantities, groups, gates, rollback, and ignored evidence location
- [ ] T048 Re-run cross-artifact requirement/task traceability for FR-001 through FR-033 and SC-001 through SC-010, verify no unchecked prerequisite is reported as a pass, and record the final feature status in `specs/005-namespace-isolation/checklists/acceptance.md` — Pending: the shared-cluster selection and staged task state changed for the foundation activation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Authoritative/External Gates (Phase 1)**: T001 blocks static implementation;
  T002, T003, T006, and T007 gate policy-only foundation activation. T004 and
  T005 remain required for RBAC and dev-business continuity acceptance.
- **Test/Observer Foundations (Phase 2)**: Begins after T001 and blocks managed
  manifest work; later live claims retain their task-specific external gates.
- **US1 Foundation (Phase 3)**: Static work may complete before external gates;
  live reconciliation blocks default deny and all live negative tests.
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
- No story may treat a manifest, branch, or local commit as live evidence.
  Explicitly deferred T004/T005 remain unchecked and constrain acceptance.

### Parallel Opportunities

- T009-T011 touch separate script/library/document files.
- T016-T018 create separate environment directories after T015 fixes the base
  contract.
- T025 and T026 separate fixture base from overlay values after the immutable
  image decision.
- T032 and T036 implement separate resource and authorization observers.
- Documentation may be drafted in parallel but is finalized only after command
  contracts and evidence paths are stable.

## Implementation Strategy

1. Verify T001, then write failing static/observer tests while external live
   gates are tracked explicitly.
2. Deliver the namespace/Redis foundation and explicit infrastructure
   activation values without default deny.
3. Close the foundation gates, while retaining deferred identity and unavailable
   dev-business continuity as explicit acceptance gaps.
4. Reconcile the foundation and validate dev plus three Redis instances live.
5. Deliver default deny, validate real CNI enforcement, and retire shared Redis.
6. Complete network/resource/RBAC/Redis fixtures and observers.
7. Activate fixtures in one reviewable revision and gather correlated evidence.
8. Revert fixtures, wait for cleanup convergence, and run final continuity.
9. Mark acceptance only from raw, schema-valid, exact-revision evidence.

## Notes

- A checked task means its named file or live result was actually verified.
- This task list does not authorize a push, PR, merge, AWS change, ArgoCD sync,
  or cluster mutation. Those actions still require the normal human review and
  repository permissions at execution time.
- If final-acceptance prerequisites remain missing, keep the feature status
  incomplete; do not add ops implementation to these tasks.
- Empty staging/prod namespaces and temporary probes are not real workload
  activation.
- ResourceQuota reduces namespace blast radius but does not create dedicated
  nodes or eliminate the accepted shared-control-plane/noisy-neighbor risk.

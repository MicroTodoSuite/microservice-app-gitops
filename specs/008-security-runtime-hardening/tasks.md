# Tasks: Runtime Security Hardening

**Input**: Design documents from `specs/008-security-runtime-hardening/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/security-registration.md`, `quickstart.md`

**Tests**: Required by FR-012 and by the spec's demand for live evidence
rather than configuration-only success (FR-011, SC-007).

## Phase 1: Setup (Validation First)

- [ ] T001 Create the failing pinned-version, digest-pinned-image,
  activation-list, read-only-RBAC, and no-enforcement checks in
  `tests/contract/security.sh`
- [ ] T002 Create the read-only composite verifier skeleton and expected
  application/controller inventory in `scripts/managed/verify-security.sh`

---

## Phase 2: Foundational (Namespace and Trust Boundary)

**CRITICAL**: No live desired-state publication occurs until all three
Kustomize roots render locally and the AppProject's existing generic RBAC
whitelist is confirmed to already cover this feature's needs (research.md
found no new entry is required).

- [ ] T003 Confirm the `microtodosuite` AppProject's existing generic
  `ClusterRole`/`ClusterRoleBinding` whitelist entries in
  `clusters/base/project.yaml` already cover Falco's and kube-bench/kube-
  hunter's RBAC (no CRDs are introduced by this feature); add only the
  exact missing kind if not
- [ ] T004 Verify the three-element registration contract renders correctly
  against `clusters/base/infrastructure.yaml`'s explicit `list` generator
  with `tests/contract/security.sh`

**Checkpoint**: The AppProject can represent every resource this feature
introduces without a wildcard, and no live publication has happened yet.

---

## Phase 3: User Story 1 - Get notified in Slack when a workload does something suspicious at runtime (Priority: P1)

**Goal**: Falco running on every node, forwarding real findings to Slack via
Falcosidekick.

**Independent Test**: Trigger a rule Falco's default ruleset flags inside a
running business-workload container and observe a Slack message within 1
minute identifying the pod, namespace, and rule.

### Tests for User Story 1

- [x] T005 [P] [US1] Add DaemonSet-coverage, modern-eBPF-driver, and
  Falcosidekick-Slack-wiring assertions to `tests/contract/security.sh` for
  `infrastructure/falco/`

### Implementation for User Story 1

- [x] T006 [P] [US1] Add the Falco DaemonSet (modern eBPF driver,
  least-privileged capabilities `[BPF, SYS_RESOURCE, PERFMON, SYS_PTRACE]`,
  default/community rules, image pinned by digest) in
  `infrastructure/falco/falco-daemonset.yaml`. Verified against the real
  Helm chart: no `hostPID` and no `ClusterRole` are actually needed for an
  explicit `modern_ebpf` driver choice (both were wrongly assumed in this
  task's original wording before implementation).
- [x] T007 [P] [US1] Add Falco's `falco.yaml` configuration (HTTP output
  enabled, pointing at Falcosidekick) in `infrastructure/falco/falco-config.yaml`
- [x] T008 [P] [US1] Add the Falcosidekick Deployment/Service (Slack output
  configured, image pinned by digest) in `infrastructure/falco/falcosidekick.yaml`
- [x] T009 [US1] Add the Slack webhook `ExternalSecret`/`SecretStore`
  (mirroring spec 006's Alertmanager pattern, same disclosed placeholder
  IRSA role ARN) in `infrastructure/falco/falcosidekick-slack-secret.yaml`
- [x] T010 [P] [US1] Record Falco 0.44.1 and Falcosidekick 2.34.1 image
  source/digest provenance in `infrastructure/falco/vendor/v0.44.1/README.md`
  (no bundle to checksum)
- [x] T011 [US1] Complete DaemonSet-coverage and triggered-finding evidence
  capture in `scripts/managed/verify-security.sh` (skeleton written; not yet
  run against a live cluster from this environment)
- [x] T012 [US1] Make the static contract pass for the rendered `falco` root
  with `tests/contract/security.sh`
- [ ] T013 [US1] Publish the Falco installation desired state as staged
  commits on `feat/security-falco`, open a PR, and after merge wait for the
  DaemonSet to cover every node and Falcosidekick to be healthy (live
  eks-dev step, not run from this environment)

**Checkpoint**: A deliberately triggered anomalous action produces a real
Slack notification within 1 minute.

---

## Phase 4: User Story 2 - Prove the cluster meets the CIS Kubernetes Benchmark (Priority: P2)

**Goal**: A scheduled kube-bench run producing a real `eks`-profile report.

**Independent Test**: Trigger a kube-bench Job manually and retrieve a
report with a real PASS/FAIL/WARN per applicable control and remediation
text for any FAIL.

### Tests for User Story 2

- [ ] T014 [P] [US2] Add `eks`-target-profile, read-only-RBAC, and
  `ttlSecondsAfterFinished`-cleanup assertions to `tests/contract/security.sh`
  for `infrastructure/kube-bench/`

### Implementation for User Story 2

- [ ] T015 [P] [US2] Add the kube-bench `CronJob` (`--benchmark eks-1.x`,
  image pinned by digest, `ttlSecondsAfterFinished`) and its read-only
  ServiceAccount/ClusterRole/ClusterRoleBinding in
  `infrastructure/kube-bench/cronjob.yaml`
- [ ] T016 [P] [US2] Record kube-bench v0.16.0 image source/digest
  provenance in `infrastructure/kube-bench/vendor/v0.16.0/README.md` (no
  bundle to checksum)
- [ ] T017 [US2] Complete kube-bench report-capture evidence in
  `scripts/managed/verify-security.sh`
- [ ] T018 [US2] Publish the kube-bench installation commit, wait for it to
  sync, manually trigger one Job run, and record its full report plus a
  remediation-or-exception disposition for every FAIL

**Checkpoint**: A real, complete CIS Benchmark report exists for `eks-dev`,
with no silently-dropped finding.

---

## Phase 5: User Story 3 - Prove the cluster has no obvious exploitable misconfiguration (Priority: P3)

**Goal**: A scheduled kube-hunter run producing a real internal-mode
vulnerability report.

**Independent Test**: Trigger a kube-hunter Job manually and retrieve a
report of real findings (or an explicit "none found"), with zero
disruption to any running business workload.

### Tests for User Story 3

- [ ] T019 [P] [US3] Add internal-mode, read-only-RBAC, and
  `ttlSecondsAfterFinished`-cleanup assertions to `tests/contract/security.sh`
  for `infrastructure/kube-hunter/`

### Implementation for User Story 3

- [ ] T020 [P] [US3] Add the kube-hunter `CronJob` (`--pod` internal mode,
  image pinned by digest, `ttlSecondsAfterFinished`) and its read-only
  ServiceAccount/ClusterRole/ClusterRoleBinding in
  `infrastructure/kube-hunter/cronjob.yaml`
- [ ] T021 [P] [US3] Record kube-hunter 0.6.8 image source/digest
  provenance in `infrastructure/kube-hunter/vendor/v0.6.8/README.md` (no
  bundle to checksum)
- [ ] T022 [US3] Complete kube-hunter report-capture evidence in
  `scripts/managed/verify-security.sh`
- [ ] T023 [US3] Publish the kube-hunter installation commit, wait for it to
  sync, manually trigger one Job run, and record its full report plus a
  remediation-or-exception disposition for every finding, confirming zero
  business-workload disruption

**Checkpoint**: A real vulnerability scan exists for `eks-dev`, run
non-destructively.

---

## Phase 6: Polish & Cross-Cutting Validation

- [ ] T024 Run `kustomize build` and `kubeconform` (when available) for all
  three components plus the updated `eks-dev` registration, run
  `tests/contract/security.sh`, and run `git diff --check`
- [ ] T025 Run `scripts/managed/verify-security.sh --context eks-dev`,
  inspect ArgoCD application conditions and component logs for hidden
  degradation, and retain the final evidence set under
  `evidence/runs/<timestamp>-security/`
- [ ] T026 Compare the pre-change baseline with the final live revision,
  three component statuses, Falco node coverage, the triggered finding's
  Slack delivery, and both audit reports against FR-001 through FR-012 and
  SC-001 through SC-007 in
  `specs/008-security-runtime-hardening/checklists/acceptance.md`
- [ ] T027 Document the three components, the `security` namespace
  boundary, and the Audit-only (no enforcement) scope in
  `docs/platform-addons.md` or a new `docs/security-runtime.md`, mirroring
  how `003-platform-addons` and `006-observability-platform-foundation`
  documented their own boundaries

---

## Dependencies & Execution Order

### Phase dependencies

```text
Setup validation
    -> Namespace and trust boundary
        -> US1 Falco + Falcosidekick (independent of US2/US3)
            -> US2 kube-bench (independent of US1/US3)
            -> US3 kube-hunter (independent of US1/US2)
                -> Final static and live acceptance
```

- T001-T002 establish the validation and verifier plumbing.
- T003-T004 confirm the trust boundary before any live publication.
- US1, US2, and US3 do not depend on each other - each is a self-contained
  Kustomize root with its own CronJob/DaemonSet and its own RBAC, and none
  reads another's output. They may be built and published in any order, or
  in parallel by different contributors.
- T024-T027 run only after the final source revision is healthy.

## Parallel Opportunities

```text
T006 Falco DaemonSet || T015 kube-bench CronJob || T020 kube-hunter CronJob
T010 Falco/Falcosidekick provenance || T016 kube-bench provenance || T021 kube-hunter provenance
```

Tasks that publish commits to `eks-dev` or observe the shared live cluster
remain sequential within their own story.

## Implementation Strategy

**MVP scope**: User Story 1 alone (Falco + Falcosidekick) is a complete,
independently valuable increment - it closes the always-on runtime
detection gap by itself, even before either audit tool lands.

1. Encode contract failures first.
2. Confirm the existing generic RBAC whitelist already covers this
   feature's needs.
3. Land User Story 1 (Falco/Falcosidekick) and confirm a real triggered
   finding reaches Slack.
4. Land User Story 2 (kube-bench) and User Story 3 (kube-hunter) in either
   order, or in parallel - neither depends on Falco or on each other.
5. Close with full static and live acceptance evidence against every FR/SC.

## Notes

- This task list only authorizes commits on the short-lived
  `feat/security-runtime-hardening` branch; merge to `main` happens through
  a reviewed PR, never a direct push.
- Falco's host-level access (specific Linux capabilities, not `hostPID`) is scoped to
  its own ServiceAccount/DaemonSet only; kube-bench/kube-hunter's RBAC stays
  strictly read-only with no standing privilege between scheduled runs.
- Missing or failed live evidence remains a failure; it must not be
  converted to a pass based on rendered configuration alone.
- No task in this list adds enforcement/blocking behavior for any of the
  three tools - detection and audit only, per FR-004/FR-007 and the spec's
  explicit scope boundary.

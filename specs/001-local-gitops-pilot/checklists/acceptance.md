# Acceptance Evidence: Local GitOps Pilot Reconciliation

**Recorded**: 2026-08-09
**Result**: PARTIAL — acceptance remains open
**Reviewed implementation commit**: `73f0e6562a98b90cf5f34c4035bb3c8124aa1093`

This checklist reconciles the original local-pilot specification and all 56
tasks against the retained initial-deploy, platform-add-on, and service-
onboarding evidence. It does not convert later feature success into proof of an
original criterion that measured a different scenario.

## Evidence custody and interpretation

The successful desired states were commits in the machine-local pilot Git
source:

- initial auth-only pilot: `a6f9c24119cc48f63a973c5704e992b1aef27191`;
- four platform add-ons: `111186a8d6bb4ea8d5a4a647fd9166bcd180caf2`;
- final service-onboarding run: `831b0093745c0334baed3cca5f7765b074597ac8`;
- deliberate replica change: `82ac4c020c23710076af671861553a46c46bbe1a`;
- deliberate Git revert: `b3ae23e9a1135efdd387c5669fb70ba794678410`.

The raw files under `.local/evidence/` are deliberately ignored by
`.gitignore`; `git ls-files .local/evidence` returns no files. They are retained
on this workstation and are cited exactly below, but they are not committed
repository evidence. The tracked platform-add-on acceptance report summarizes
its corresponding raw set. The deliberate change/revert and live-drift run is
instead stored in the trackable `evidence/runs/` path, but is still an
uncommitted worktree record in this checkout. This distinction keeps T052 open:
three clean pilot runs and their committed aggregate still do not exist.

Evidence aliases used below:

- **E1** — [initial-deploy summary](../../../.local/evidence/runs/20260809T045303Z-initial-deploy/summary.json)
- **E2** — [initial-deploy command audit](../../../.local/evidence/runs/20260809T045303Z-initial-deploy/command-log.txt)
- **E3** — [initial ArgoCD Application](../../../.local/evidence/runs/20260809T045303Z-initial-deploy/argo-application.json)
- **E4** — [initial workload snapshot](../../../.local/evidence/runs/20260809T045303Z-initial-deploy/workloads.json)
- **E5** — [initial health observations](../../../.local/evidence/runs/20260809T045303Z-initial-deploy/health.ndjson)
- **E6** — [tracked platform-add-on acceptance](../../003-platform-addons/checklists/acceptance.md)
- **E7** — [platform-add-on raw summary](../../../.local/evidence/platform-addons/20260809T165041Z/summary.json)
- **E8** — [platform-add-on Application status](../../../.local/evidence/platform-addons/20260809T165041Z/application-status.txt)
- **E9** — [final service-onboarding summary](../../../.local/evidence/service-onboarding/20260809T183018Z/summary.json)
- **E10** — [final service-onboarding Application status](../../../.local/evidence/service-onboarding/20260809T183018Z/application-status-final.txt)
- **E11** — [service publication and digest map](../../../.local/evidence/service-onboarding/20260809T183018Z/publication-summary.json)
- **E12** — [live todos-api Deployment](../../../.local/evidence/service-onboarding/20260809T183018Z/deployments/todos-api.json)
- **E13** — [live todos-api Pod](../../../.local/evidence/service-onboarding/20260809T183018Z/pods/todos-api.json)
- **E14** — [created todo response](../../../.local/evidence/service-onboarding/20260809T183018Z/functional/todo-created.json)
- **E15** — [correlated processor event](../../../.local/evidence/service-onboarding/20260809T183018Z/functional/processor-event.log)
- **E16** — [live ExternalSecret capability](../../../.local/evidence/platform-addons/20260809T165041Z/capabilities/external-secret.json)
- **E17** — [deliberate live-run evidence index](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/README.md)
- **E18** — [combined change/revert and self-heal summary](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/summary.json)
- **E19** — [Git-revert summary](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/git-revert-summary.json)
- **E20** — [two-replica change Application](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/change-application.json)
- **E21** — [one-replica revert Application](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/revert-application.json)
- **E22** — [revert convergence timeline](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/revert-timeline.ndjson)
- **E23** — [live-drift self-heal summary](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/self-heal-summary.json)
- **E24** — [direct drift mutation response](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/drift-mutation-response.json)
- **E25** — [ArgoCD detecting and auto-healing the drift](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/drift-after-injection-application.json)
- **E26** — [self-heal convergence timeline](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/self-heal-timeline.ndjson)
- **E27** — [post-self-heal Application](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/self-heal-application.json)
- **E28** — [deliberate run command audit](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/command-log.tsv)
- **E29** — [preserved timer-harness failure and Git-only recovery](../../../evidence/runs/20260809T185618Z-git-revert-self-heal/harness-recovery.json)

## Deliberate live-validation results

| Requested scenario | Result | Exact observation |
| --- | --- | --- |
| Git change and normal Git revert | **PASS** | E19-E22 record `831b0093...` at one replica, change `82ac4c02...` at two Ready replicas in 6,716 ms, and revert `b3ae23e9...` back to one Ready replica in 33,057 ms. Both reconciliations were automated, all three health checks returned HTTP 200, the reverted manifest blob equals the baseline blob, and the change/revert phase used zero direct cluster mutations. |
| Direct live-resource drift and ArgoCD self-heal | **PASS** | E23-E27 record the single authorized `kubectl scale` response at two replicas, the Application becoming OutOfSync/Progressing with `autoHealAttemptsCount: 1`, and automatic restoration to one replica plus Synced/Healthy in 2,559 ms at the unchanged `b3ae23e9...` source revision. E28 records no manual correction. |

E29 preserves an initial harness timer-unit error that occurred after the
forward change had already reconciled. Recovery continued from the observed
healthy two-replica state by Git revert only; no cluster correction was issued.
The raw change Application and Deployment timestamps remain the source for the
6,716 ms forward-convergence measurement.

## User-story disposition

| Story | Result | Evidence-backed disposition |
| --- | --- | --- |
| US1 — deploy auth-api from committed desired state | **PASS** | E1-E5 prove one digest-pinned `auth-api`, ArgoCD Synced/Healthy at the exact commit, three HTTP 200 checks over 60 seconds, all-local dependencies, and no unsupported mutation. |
| US2 — commit-only change and rollback | **PARTIAL** | E19-E22 now prove the committed replica change and live Git-revert restoration. E23-E27 additionally prove self-heal of direct live drift. The story's distinct five-minute uncommitted desired-state edit observation remains absent. |
| US3 — reuse the deployment contract | **PARTIAL** | Feature 004 reused the same mechanism for four additional real services (E9-E13), but the required seven abstract remaining slots and planned managed-environment fixtures were not tested. |
| US4 — reproduce and diagnose the pilot | **PARTIAL** | The current quickstart is short and GitOps-preserving, and E1 records four entered commands. No clean-clone newcomer test, three-clean-run aggregate, or two first-time operator records exist. |

## Functional requirement disposition

| Requirement | Result | Specific evidence and conclusion |
| --- | --- | --- |
| FR-001 | **PASS** | E1 records the local Git reader, local image, kind workload, and `allRuntimeAssetsLocal: true`. |
| FR-002 | **PASS** | E1 records `cloudCredentialsUsed: false`, `paidServicesUsed: false`, and `hostedRuntimeServicesUsed: false`. |
| FR-003 | **PASS** | E1 and E4 record exactly one business service, `auth-api`, in the original acceptance run. Later onboarding intentionally has five and does not rewrite that historical measurement. |
| FR-004 | **PASS** | E1 ties desired and observed state to `a6f9c241...`; E6 and E10 show later changes also converged at committed pilot revisions. |
| FR-005 | **PASS** | E1 and E3 record automatic ArgoCD reconciliation, revision equality, Synced, Healthy, and operation success. |
| FR-006 | **PASS** | E2 contains only the two allowed bootstrap mutations and read-only port-forward verification; E6 records no direct managed-state mutation during the add-on changes. |
| FR-007 | **PASS** | E2 identifies only vendored ArgoCD and the root Application as bootstrap exceptions; E1 records `unsupportedMutations: []`. |
| FR-008 | **OPEN** | E23-E27 prove automatic correction of direct live-resource drift, not the required claim that an uncommitted desired-state file edit has no effect. No five-minute uncommitted-edit record or `tests/integration/uncommitted-edit.sh` exists. |
| FR-009 | **PASS** | E19-E22 link the allowed replica change `82ac4c02...` and revert `b3ae23e9...` to automated ArgoCD operations, Ready replicas, HTTP 200 health, and 6,716 ms/33,057 ms convergence. |
| FR-010 | **PASS** | E1 records the deployed `auth-api@sha256:...` reference and digest; E6 later records Kyverno's immutable-image rule passing. |
| FR-011 | **PASS** | E1 and E5 record the documented loopback `/version` endpoint returning HTTP 200 three times without users-api. |
| FR-012 | **PASS** | E1 reports success only with revision equality, Synced/Healthy Argo state, one Ready replica, and passing health observations. |
| FR-013 | **PASS** | [auth-api base](../../../apps/auth-api/base/kustomization.yaml) and [local overlay](../../../apps/auth-api/overlays/local/kustomization.yaml) remain separate; E3 and E4 prove that exact overlay reconciled. |
| FR-014 | **OPEN** | E9 proves auth plus four onboarded services, not auth plus all seven remaining abstract slots. `tests/conformance/fixtures/service-slots/` does not exist. |
| FR-015 | **OPEN** | Inactive managed overlays exist, but no local/EKS cluster fixture or conformance result proves that only declared environment values change. |
| FR-016 | **PASS** | [service-onboarding-contract.md](../contracts/service-onboarding-contract.md) contains the ownership tables and the `auth-api` mapping. |
| FR-017 | **PASS** | E1 records the machine-local reader URL, loopback image, local runtime, and no hosted runtime dependency. |
| FR-018 | **PASS** | E16 records `ExternalSecret/auth-api-secrets` as Ready with `SecretSynced`; E6 records preservation of the stable Secret target and no committed secret-value claim. |
| FR-019 | **PASS** | [local-pilot-quickstart.md](../../../docs/local-pilot-quickstart.md) lists prerequisites, repositories, workstation limits, four top-level commands, checkpoints, verification, troubleshooting, and cleanup; [README.md](../../../README.md) links it. |
| FR-020 | **PASS** | E1 exposes the desired/observed revision, sync and health state, readiness, business-service count, and three health results. |
| FR-021 | **OPEN** | No evidence reruns the complete quickstart at the same selected revision and proves idempotent convergence. The three onboarding summaries use different revisions and start from an existing runtime. |
| FR-022 | **PASS** | [local-pilot-quickstart.md](../../../docs/local-pilot-quickstart.md) restricts repairs to commits or `git revert` and explicitly rejects direct managed-state mutation. |

Functional requirements: **18 PASS, 4 OPEN**.

## Success criterion disposition

| Criterion | Result | Specific evidence and conclusion |
| --- | --- | --- |
| SC-001 | **OPEN** | E1 proves four entered commands and 106 seconds from source availability to the final health result, but it does not identify a first-time teammate or prove no undocumented assistance. No operator record exists. |
| SC-002 | **OPEN** | E1 is one clean initial run. The service-onboarding runs at [18:17:40](../../../.local/evidence/service-onboarding/20260809T181740Z/summary.json), [18:29:13](../../../.local/evidence/service-onboarding/20260809T182913Z/summary.json), and E9 all pass, but they are incremental verification runs at different revisions on an existing cluster, not three clean pilot runs. |
| SC-003 | **PASS** | E1 proves the initial deployment maps to Git. E19-E22 prove the one-to-two replica change and one-replica rollback map to `82ac4c02...` and `b3ae23e9...`; E19 records zero direct cluster mutations in that phase. The later `kubectl scale` in E28 is the separately authorized self-heal experiment, not part of the change/rollback path. |
| SC-004 | **OPEN** | The requested direct live-drift scenario passes: E23-E27 prove ArgoCD restored an uncommitted live replica mutation in 2,559 ms with no Git revision change or manual correction. SC-004 as written, however, requires a different result: an uncommitted desired-state file edit must cause zero observed live change for a full five-minute window. That observation was not executed and cannot be inferred from self-heal. |
| SC-005 | **PASS** | E19-E22 expose both `82ac4c02...` and its revert `b3ae23e9...`, show automated reconciliation, restore one Ready replica and HTTP 200 health, and measure 33,057 ms from revert availability to the verified restored state, below five minutes. |
| SC-006 | **PASS** | E1 records `businessServiceCount: 1`; E5 records three successful `/version` checks spanning 60 seconds. |
| SC-007 | **OPEN** | E9 proves reuse for four additional real services, but not all seven requested remaining slots or planned managed-environment slots; the conformance fixtures and scripts named by the task plan do not exist. |
| SC-008 | **PASS** | E1 explicitly records zero cloud credentials, paid services, and hosted runtime services, with every runtime asset local. |
| SC-009 | **OPEN** | No two first-time operator records, state-identification results, or clarity ratings exist. |

Success criteria: **4 PASS, 5 OPEN**. The feature therefore remains partially
accepted even though its auth-only MVP passed live.

## Task reconciliation

Checkboxes in `tasks.md` may be checked only for rows classified **DONE** here.
**PARTIAL**, **OPEN**, and **SUPERSEDED** rows remain unchecked.

| Task | Result | Specific proving file or outstanding gap |
| --- | --- | --- |
| T001 | **DONE** | [.gitignore](../../../.gitignore) ignores `.local/` and scratch; E16 proves the later ESO conversion, after which the transitional secret-file rule was removed. |
| T002 | **OPEN** | `bootstrap/local/assets.lock` does not exist; no file proves the requested complete asset inventory and digest lock. |
| T003 | **DONE** | [ArgoCD provenance](../../../bootstrap/argocd/vendor/v3.5.0/README.md), [checksum](../../../bootstrap/argocd/vendor/v3.5.0/SHA256SUMS), and E2 prove the vendored bootstrap path was used. |
| T004 | **SUPERSEDED** | E6 proves ESO **2.9.0**, but T004 specifies 2.7.0 and paths under `vendor/v2.7.0`; the task is not true as written. |
| T005 | **PARTIAL** | [kind-config.yaml](../../../bootstrap/local/kind-config.yaml) and E1 prove kind plus a loopback registry, but `bootstrap/local/registry/hosts.toml` and the requested digest-pinned topology file do not exist. |
| T006 | **PARTIAL** | [common.sh](../../../scripts/pilot/lib/common.sh) provides strict helpers, but `tests/lib/assert.sh` does not exist. |
| T007 | **OPEN** | `tests/contract/local-assets.sh` does not exist. |
| T008 | **OPEN** | `tests/integration/bootstrap-boundary.sh` does not exist. |
| T009 | **PARTIAL** | [preflight.sh](../../../scripts/pilot/preflight.sh) implements tool, render, Docker, port, cloud-variable, and JSON checks, while E1 records CPU, memory, and disk facts. The preflight itself does not enforce the specified CPU, memory, or disk resource thresholds. |
| T010 | **OPEN** | `scripts/pilot/acquire-assets.sh` and the required asset lock do not exist. |
| T011 | **PARTIAL** | [bootstrap.sh](../../../scripts/pilot/bootstrap.sh) and [common.sh](../../../scripts/pilot/lib/common.sh) implement parts of the lifecycle, but `scripts/pilot/lib/runtime.sh` and the full disposable-worktree contract do not exist. |
| T012 | **PARTIAL** | The shared files under [clusters/base](../../../clusters/base/) reconcile live in E10, but the exact environment and split-project structure named by T012 was not implemented. |
| T013 | **PARTIAL** | [registration.yaml](../../../clusters/local-kind/registration.yaml) and activation files drive E10, but the registration does not itself carry every namespace, environment, registry, and capacity value named by T013. |
| T014 | **PARTIAL** | [project.yaml](../../../clusters/base/project.yaml) and E6 prove a clean wildcard scan, but the four split trust-boundary files named by T014 do not exist. |
| T015 | **PARTIAL** | [environments/local](../../../environments/local/) contains quota, limits, and network policy, but the requested base environment RBAC/service-account set is incomplete and lives at a different path. |
| T016 | **DONE** | E6's verified pre-change baseline records ArgoCD self-management, ESO 2.9.0 healthy before workloads, and the other add-on directories still inactive at that revision. |
| T017 | **PARTIAL** | E2 proves the two-mutation bootstrap boundary and E1 proves a passing live platform, but the asset-lock and bootstrap integration tests required by the task do not exist. |
| T018 | **OPEN** | `tests/contract/auth-api-local.sh` does not exist. |
| T019 | **OPEN** | `tests/integration/initial-deploy.sh` does not exist; E1 is runtime proof, not the requested test implementation. |
| T020 | **DONE** | [auth-api base](../../../apps/auth-api/base/) contains the neutral workload files; E4 proves one Ready digest-pinned live workload with the required labels and service account. |
| T021 | **PARTIAL** | [local overlay](../../../apps/auth-api/overlays/local/) and E16 prove the active digest/ESO outcome, but the exact `jwt-password.yaml`, config patch, and deployment patch files named by T021 do not exist. |
| T022 | **DONE** | [base kustomization](../../../apps/auth-api/base/kustomization.yaml) contains no secret generator or local values file; E16 proves the ESO target was Ready and synchronized. |
| T023 | **DONE** | [apps.yaml](../../../clusters/base/apps.yaml) contains the Matrix generator, labels, exact project/destination template, prune, and self-heal; E3 and E10 prove generated Applications reconciled. |
| T024 | **DONE** | [bump-image.sh](../../../scripts/bump-image.sh) accepts only nonzero `sha256` digests, preserves `newName`, renders, commits, and contains no cluster mutation; E11 records digest-selected publications. |
| T025 | **DONE** | The historical implementation at `6c2fbe9:scripts/pilot/publish-auth.sh` builds, pushes, resolves the registry digest, edits a disposable local clone, and pushes only pilot `main`; E1 proves that path produced the auth-only live revision. [publish-auth.sh](../../../scripts/pilot/publish-auth.sh) is now the feature-004 compatibility entry point. |
| T026 | **OPEN** | `scripts/pilot/lib/evidence.sh` does not exist; evidence writing is embedded elsewhere. |
| T027 | **DONE** | The historical verifier at `6c2fbe9:scripts/pilot/verify.sh`, E1, and E5 prove revision equality, exactly one business service, Ready auth-api, and three `/version` checks over 60 seconds. [verify.sh](../../../scripts/pilot/verify.sh) now preserves the auth check after feature 004 expanded the service set. |
| T028 | **DONE** | [secret-rotation.md](../../../docs/secret-rotation.md) documents the compromised literal, out-of-Git rotation, ESO ownership, and stable target without reproducing the literal. |
| T029 | **OPEN** | Both requested test files and `evidence/examples/initial-deploy/` are absent. |
| T030 | **OPEN** | `tests/integration/uncommitted-edit.sh` does not exist. |
| T031 | **OPEN** | `tests/integration/change-revert.sh` does not exist. |
| T032 | **OPEN** | `scripts/pilot/exercise-uncommitted.sh` and its five-minute evidence do not exist. |
| T033 | **OPEN** | `scripts/pilot/exercise-change-revert.sh` does not exist. E17-E22 are one deliberate live run, not the required reusable implementation. |
| T034 | **OPEN** | `tests/conformance/service-contract.sh` does not exist. |
| T035 | **OPEN** | `tests/conformance/cluster-contract.sh` does not exist. |
| T036 | **OPEN** | `tests/conformance/production-disabled.sh` does not exist. |
| T037 | **PARTIAL** | [service-onboarding.md](../../../docs/service-onboarding.md) contains ownership and onboarding guidance, but `templates/service/` does not exist. |
| T038 | **OPEN** | `tests/conformance/fixtures/service-slots/` does not exist. |
| T039 | **OPEN** | `tests/conformance/fixtures/clusters/` does not exist. |
| T040 | **OPEN** | The required service conformance script and fixture assertions do not exist. |
| T041 | **OPEN** | The required cluster conformance script and fixture assertions do not exist. |
| T042 | **PARTIAL** | [managed auth overlays](../../../apps/auth-api/overlays/) are inactive and the old prod quota is gone, but the exact environment-base ownership/conformance proof named by the task is absent. |
| T043 | **OPEN** | `docs/production-readiness.md` and the production-disabled test do not exist. |
| T044 | **OPEN** | `scripts/pilot/conformance.sh` does not exist. |
| T045 | **OPEN** | `tests/integration/newcomer-workflow.sh` does not exist. |
| T046 | **OPEN** | `scripts/pilot/run-three-clean.sh` does not exist. |
| T047 | **PARTIAL** | [cleanup.sh](../../../scripts/pilot/cleanup.sh) targets local pilot resources, but there is no retained exact-target/recoverability report and the stronger label/context checks named by T047 are absent. |
| T048 | **DONE** | [local-pilot-quickstart.md](../../../docs/local-pilot-quickstart.md) provides four commands, checkpoints, read-only diagnostics, Git correction/revert guidance, and cleanup; [README.md](../../../README.md) links it. |
| T049 | **OPEN** | `docs/operator-evaluation.md` and `evidence/operators/template.json` do not exist. |
| T050 | **OPEN** | `evidence/README.md` does not exist. |
| T051 | **PARTIAL** | The current pilot artifacts inspected are English, but no retained all-scope language scan proves every path named by the task. |
| T052 | **OPEN** | Only one clean initial run exists (E1); the three passing onboarding summaries are not clean runs, and E17 is a different scenario that is not a three-clean-run aggregate or yet committed evidence. |
| T053 | **OPEN** | No first-time operator records exist. |
| T054 | **DONE** | This checklist records SC-001 through SC-009, exact evidence paths, and open proof without turning missing runtime evidence into a pass. |
| T055 | **OPEN** | `.github/workflows/validate-gitops.yml` does not exist. |
| T056 | **PARTIAL** | Current platform/onboarding contracts exist, but the original quickstart still names absent acquisition, uncommitted-edit, change/revert, conformance, and three-clean-run commands; no file proves the complete planned suite ran. |

Task disposition: **12 DONE, 15 PARTIAL, 28 OPEN, 1 SUPERSEDED**.

## Cross-feature dependency finding

The final onboarding evidence also resolves the architecture question about the
drawn `todos-api -> users-api` edge. The detailed finding is retained in
[dependency-evidence.md](../../004-service-onboarding/checklists/dependency-evidence.md):
the running todos-api validates the JWT locally, stores todo data in process
memory, and publishes create/delete events to Redis. It has no direct users-api
call or users-api endpoint configuration.

## Closure decision

The original auth-only MVP and the committed change/Git-revert path are
accepted, including the local-only GitOps path, immutable artifact,
exactly-one-service observation, repeated health window, and bootstrap audit.
The separately requested live-drift self-heal also passes. The complete feature
is **not** accepted because US2's literal uncommitted desired-state observation,
full eight-slot/managed-environment conformance, three clean runs, and operator
evidence remain open. `spec.md` therefore remains Draft, and unchecked tasks
remain executable work rather than being retroactively waived. If the intended
SC-004 behavior is now live-resource self-heal rather than a five-minute
uncommitted desired-state no-op, that source-of-truth criterion needs an
explicit spec amendment; this checklist does not silently redefine it. If the
intended suite scope is now five business services rather than the eight slots
required by FR-014 and SC-007, that source-of-truth requirement likewise needs
an explicit spec amendment.

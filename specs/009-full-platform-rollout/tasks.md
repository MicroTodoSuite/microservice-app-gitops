---

description: "Dependency-ordered implementation tasks for the full multi-cloud platform rollout"
---

# Tasks: Full Multi-Cloud Platform Rollout

**Input**: Design documents from `/specs/009-full-platform-rollout/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/`, and `quickstart.md`

**Tests**: Tests and live failure-mode evidence are mandatory because FR-038, FR-047, FR-050, and SC-004 explicitly require runnable quality gates and behavior verification. Test tasks must fail for the missing behavior before their implementation task starts.

**Repository paths**: Paths without `../` are in `microservice-app-gitops`. Sibling repositories are referenced explicitly as `../microservice-app-ops`, `../.github`, `../microservice-app-<service>`, and `../microservice-app-docs`.

**Hard stop**: Any failed prerequisite, non-clean required plan, inaccessible backend, unexpected destroy/replacement, unapproved cost, quota excess, singleton duplication, economical regression, or missing evidence blocks all dependent tasks. Never use `-refresh=false` to turn a blocked plan into inferred evidence.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it changes different files and has no incomplete dependency.
- **[Story]**: Maps work to one independently testable user story.
- Every task names the concrete file or artifact it owns.

## Phase 1: Setup and Reproducible Evidence

**Purpose**: Establish clean cross-repository inputs, pinned tooling, and the machine-checkable evidence contract before implementation changes.

- [X] T001 Fetch every remote, record branch, HEAD, remote-main relation, and literal tracked/untracked status for all nine participating repositories in `evidence/runs/<timestamp>-setup/baseline/repositories.json`; fast-forward only a clean local `main` with no local-only commit, and otherwise stop without stashing, overwriting, or implicitly rebasing any work.
- [X] T002 [P] Create the exact CLI/controller/chart/action version and upstream-checksum allowlist in `scripts/managed/full-profile-toolchain.lock`, covering Terraform, AWS CLI, Azure CLI, kubectl, Kustomize 5.8.1, kubeconform 0.7.0, Infracost, Cosign, Syft, Trivy, crane/oras, every new vendored capability, and every third-party platform image with its immutable upstream digest plus planned ECR/ACR mirror coordinates.
- [X] T003 [P] Add valid and invalid evidence fixtures for required fields, account mismatch, failed checks, missing approval, and checksum mismatch in `tests/evidence/fixtures/` and a test runner in `tests/evidence/validate-evidence.bats`; run it and confirm it fails before T004.
- [X] T004 Implement offline JSON Schema and artifact-checksum validation in `scripts/managed/validate-full-profile-evidence.sh` against `specs/009-full-platform-rollout/contracts/full-profile-evidence.schema.json`, then make T003 pass.
- [X] T005 [P] Create the redacted evidence skeleton in `evidence/templates/full-profile-stage/evidence.json` and README guidance in `evidence/templates/full-profile-stage/README.md`; exclude state, plans containing sensitive values, kubeconfigs, tokens, private keys, and secret values from Git.
- [X] T006 [P] Encode the one-owner resource inventory from the ownership contract in `evidence/templates/infrastructure-ownership.json` and add its schema/duplicate-owner test in `tests/evidence/validate-ownership.bats`.
- [X] T007 [P] Add fixture-driven fail-closed tests for missing Azure CLI, wrong subscription, CIDR collision, missing provider registration, and missing backend locking in `../microservice-app-ops/tests/preflight/azure-dr-preflight.bats`; confirm failure before T008.
- [X] T008 Implement read-only authenticated Azure discovery and redacted output in `../microservice-app-ops/scripts/preflight/azure-dr.sh`, using the checksum-pinned CLI and comparing the real subscription with `AZURE_SUBSCRIPTION_ID_COLONIA`; make T007 pass without inventing subscription, tenant, region, VNet, quota, or backend values.
- [X] T009 [P] Add the cross-repository rollout index, stage owners, PR ordering, approval roles, and escalation path in `../microservice-app-docs/full-platform/rollout-index.md`.
- [X] T010 Run `jq`, placeholder, markdown-link, and `git diff --check` validation over `specs/009-full-platform-rollout/` and retain the result in `evidence/runs/<timestamp>-setup/desired/spec-validation.txt`.

**Checkpoint**: Evidence can be validated offline, tool inputs are pinned, and Azure discovery fails closed.

---

## Phase 2: Foundational Compatibility (Blocking)

**Purpose**: Introduce reusable contracts and concurrent profile rendering without changing the economical Terraform plan or GitOps output.

**⚠️ CRITICAL**: No new cloud foundation or full-profile activation starts until T030 passes.

### Tests first

- [X] T011 [P] Add failing Terraform tests for one-node bootstrap bounds, private EKS endpoint enabled plus reviewed public CIDRs, `direct-nat` versus `transit-egress` modes, opt-in EBS/Karpenter/AWS-load-balancer/VPC-CNI-NetworkPolicy prerequisites defaulting off, exact enabled `jsonencode({ enableNetworkPolicy = "true" })`, per-cluster encrypted Karpenter interruption queue/EventBridge wiring, zero NAT/EIP in transit spokes, private-subnet default routes through TGW, public load-balancer-only routes through the spoke IGW, exact public/private AWS load-balancer discovery tags, no public worker addresses, routes ready before nodes, and preserved default dev/demo values in `../microservice-app-ops/aws/modules/environment-foundation/tests/network_eks.tftest.hcl`.
- [X] T012 [P] Add failing Terraform tests for owner/consumer singleton behavior, exactly five unchanged service ECR repositories plus one dev-owned immutable/encrypted/scan-on-push/non-force-deletable `microtodosuite/platform` mirror repository, exact multi-issuer shared IRSA trust, GitHub-only publisher trust, a separate exact-workflow platform-mirror role scoped to that one repository, a consumer's cluster-qualified one-environment JWT reader with zero secret creation, dev-owned full-profile Grafana-admin/Sonar-DB/Sonar-admin containers populated only by `ephemeral "random_password"` into `secret_string_wo` with explicit non-secret rotation counters and no plan/state value (using the real local-only Random provider rather than mocking its ephemeral resource), an exact full-dev Sonar reader, and a separate DR seed role restricted to its four source ARNs plus the exact GitHub repository/environment/workflow identity in `../microservice-app-ops/aws/modules/environment-foundation/tests/github_oidc.tftest.hcl`, `ecr.tftest.hcl`, `kyverno_irsa.tftest.hcl`, `observability_security_irsa.tftest.hcl`, and `managed_secrets.tftest.hcl`.
  - Contracts live in `../microservice-app-ops/aws/modules/environment-foundation/tests/`:
    `ecr.tftest.hcl` (platform mirror), `multi_issuer_irsa.tftest.hcl` (shared IRSA trust),
    `managed_secrets.tftest.hcl` (tooling containers and the consumer JWT reader),
    `observability_security_irsa.tftest.hcl` (Sonar reader), `github_oidc.tftest.hcl` (DR seed).
- [X] T013 [P] Add failing root/workflow contract tests for unique backend keys, account/region/CIDRs, shared-resource consumer mode, no public `0.0.0.0/0`, destination-record inputs defaulting empty, canonical `microtodosuite.online` zone creation defaulting off at a separate address with zero legacy-zone replacement/destruction, pinned Terraform, plan/Infracost output, OIDC, and absence of unattended apply in `../microservice-app-ops/aws/environments/dev/foundation/tests/full-profile-compatibility.tftest.hcl` and `../microservice-app-ops/tests/workflows/foundation-checks.bats`.
- [X] T014 [P] Add a failing economical/full concurrent-render fixture and one-environment-full-root assertions in `tests/profiles/validate-profile-routing.bats`; snapshot the current economical service and native production-canary renders under `tests/profiles/golden/economical/` before moving paths.
- [X] T015 [P] Add failing CLI tests for `scripts/bump-image.sh <service> <environment> <profile> <destination> <digest>` in `tests/promotion/bump-image.bats`, including rejection of an invalid tuple and proof that only one overlay changes.
- [X] T016 [P] Add a failing static policy test in `tests/policy/no-imperative-managed-mutations.bats` that rejects post-bootstrap `kubectl apply|create|patch|delete|scale|run` in `scripts/managed/` while allowlisting only the two commands in the managed bootstrap helper.

### Implementation

- [X] T017 Generalize bootstrap min/desired/max, outbound mode, exact load-balancer subnet discovery tags, and `enable_full_profile_cluster_prerequisites` inputs in `../microservice-app-ops/aws/modules/environment-foundation/variables.tf`, `network.tf`, and `eks.tf`, defaulting the new prerequisite switch off and preserving current dev/demo values and dependency ordering.
- [X] T018 Implement opt-in cluster-specific EBS CSI, Karpenter controller/node identities plus encrypted interruption queue/EventBridge rules, VPC/cluster-scoped AWS Load Balancer Controller IRSA/discovery outputs, and VPC CNI `jsonencode({ enableNetworkPolicy = "true" })` in `../microservice-app-ops/aws/modules/environment-foundation/irsa.tf`, `karpenter.tf`, `eks.tf`, `outputs.tf`, and `versions.tf`; Terraform owns IAM/add-on prerequisites while GitOps owns both controllers and Karpenter NodePools.
  - **Deviation recorded during implementation**: the EBS CSI driver is *not* gated behind
    `enable_full_profile_cluster_prerequisites`. It became an unconditional baseline for both
    profiles in `microservice-app-ops` PR #21, because the in-tree AWS EBS provisioner no longer
    exists on Kubernetes 1.35 and the economical profile's own Prometheus/Grafana volumes depend
    on it. Karpenter and the AWS Load Balancer Controller remain opt-in as specified.
- [X] T019 Implement optional additional EKS issuer maps, the dev-owned immutable/encrypted/scan-on-push/non-force-deletable `microtodosuite/platform` ECR mirror and distinct exact-workflow mirror role, the separately addressed/default-off canonical `microtodosuite.online` hosted zone with no in-place rename or legacy-zone destruction, full-consumer JWT secret lookup/cluster-qualified reader roles, dev-owned full-profile Grafana-admin/Sonar-DB/Sonar-admin containers whose values flow only from Random provider 3.9.0 `ephemeral "random_password"` to AWS provider `secret_string_wo` with reviewed non-secret version counters, an exact full-dev Sonar External-Secrets reader, and an opt-in exact-workflow DR seed role limited to the prod-JWT/Alertmanager/Falco/Grafana ARNs in `../microservice-app-ops/aws/modules/environment-foundation/{variables,versions,ecr,route53,platform-mirror,managed-secrets,kyverno-irsa,observability-irsa,security-irsa,tooling-secrets,dr-secret-seed,outputs}.tf`; keep dev's existing five service repositories, resources, and policies unchanged when new inputs are empty, and never extend the GitHub publisher with EKS, platform-mirror, or secret-read trust.
  - All parts implemented and verified at zero dev resource changes against the real backend.
    The Grafana/Sonar values flow from a new `aws/modules/ephemeral-passwords` module into
    `secret_string_wo`, so no value reaches plan or state; the consumer JWT reader is
    cluster-qualified so two consumers of one environment cannot share an identity.
- [X] T020 [P] Move auth-api composition to `apps/auth-api/profiles/{economical,full}/overlays/{dev,staging,prod}/` while retaining shared files in `apps/auth-api/base/` and `apps/auth-api/components/`; make its golden renders pass.
- [X] T021 [P] Move frontend composition to `apps/frontend/profiles/{economical,full}/overlays/{dev,staging,prod}/` while retaining shared files in `apps/frontend/base/` and `apps/frontend/components/`; make its golden renders pass.
- [X] T022 [P] Move log-message-processor composition to `apps/log-message-processor/profiles/{economical,full}/overlays/{dev,staging,prod}/` while retaining shared files in its `base/` and `components/`; make its golden renders pass.
- [X] T023 [P] Move todos-api composition to `apps/todos-api/profiles/{economical,full}/overlays/{dev,staging,prod}/` while retaining shared files in its `base/` and `components/`; make its golden renders pass.
- [X] T024 [P] Move users-api composition to `apps/users-api/profiles/{economical,full}/overlays/{dev,staging,prod}/` while retaining shared files in its `base/` and `components/`; make its golden renders pass.
- [X] T025 Add `profile` and destination tuple handling to `clusters/base/apps.yaml`, `clusters/eks-dev/activation-apps.yaml`, `clusters/eks-dev-capacity-constrained/activation-apps.yaml`, and `clusters/local-kind/activation-apps.yaml`; retain every existing in-cluster destination and economical activation.
- [X] T026 Update `scripts/bump-image.sh` for the validated five-argument destination contract and make T015 pass without a global topology edit.
- [X] T027 Pin Kustomize/kubeconform downloads and checksums and add profile, ownership, mutable-image, secret, and imperative-mutation gates to `.github/workflows/validate-gitops.yml`; make T014 and T016 blocking CI jobs.
- [X] T028 Run all module/root Terraform tests plus all GitOps profile/policy tests, retain raw output under `evidence/runs/<timestamp>-foundational/`, and stop on any failure.
  - Collected by `scripts/managed/collect-foundational-evidence.sh` into
    `evidence/runs/20260824T233346Z-foundational/gates/`; all ten gates pass.
- [X] T029 Initialize the real dev backend with `dev.s3.tfbackend`, keep canonical-zone creation disabled, run a refreshed saved plan with `dev.tfvars`, display and externally retain the complete text proving exactly `0 to add, 0 to change, 0 to destroy`, and commit only its checksum plus redacted result in `evidence/runs/<timestamp>-foundational/infrastructure/dev-plan-summary.json`; stop and fix compatibility drift before proceeding.
  - `infrastructure/dev-plan-summary.json` records a literal `0 to add, 0 to change,
    0 to destroy`, derived from the plan JSON rather than its printed text. Only the
    checksum and redacted counts are committed; the full text is retained externally.
- [X] T030 Validate the foundational evidence bundle in `evidence/runs/<timestamp>-foundational/evidence.json`, obtain review for the exact branch head, merge through protected `main`, and recapture the unchanged economical golden renders and live ArgoCD health.
  - Bundle `evidence/runs/20260825T002553Z-foundational/` validates and records `approved`:
    all ten gates pass, the refreshed dev plan is exactly `0 to add, 0 to change,
    0 to destroy`, and the economical platform is 39/39 healthy. The superseded
    `20260824T233346Z-foundational` run is kept as the evidence that the live gate
    caught a real defect — `env-demo` had no JWT secret, remedied and applied through
    `microservice-app-ops#25`. `infra-loki` and `infra-prometheus` remain OutOfSync but
    Healthy and are recorded as advisories attributed to the platform add-on owner.
    Remaining: review and merge of the gitops PRs through protected `main`.

**Checkpoint**: Reusable Terraform/GitOps contracts exist, tests pass, and dev remains genuinely `0/0/0` before new full-profile work.

---

## Phase 3: User Story 1 — Preserve the Economical Platform (Priority: P1) 🎯 MVP

**Goal**: Make the working economical platform an enforced, measured invariant around every later stage.

**Independent Test**: Record a healthy baseline, fail a no-op candidate stage before activation, and prove the economical Terraform plan, ArgoCD revision/Application health, workloads, and endpoints remain unchanged.

### Tests first

- [X] T031 [P] [US1] Add fixture tests for healthy, degraded, unreachable, and revision-mismatch economical baselines in `tests/evidence/economical-baseline.bats`; confirm failure before T032.
- [X] T032 [P] [US1] Add a stage-dependency test proving `blocked` cannot unlock a dependent stage in `tests/evidence/stage-dependencies.bats`; confirm failure before T035.

### Implementation

- [X] T033 [US1] Implement a strictly read-only economical baseline collector in `scripts/managed/capture-economical-baseline.sh`, covering Git revision, AWS identity, EKS identity, ArgoCD Applications, pods, endpoints, namespace isolation, and refreshed dev drift; make T031 pass.
- [X] T034 [P] [US1] Document economical rollback ownership, abort criteria, and prohibited state/cluster actions in `../microservice-app-docs/full-platform/economical-safety-boundary.md`.
- [X] T035 [US1] Implement stage dependency evaluation in `scripts/managed/evaluate-stage-gate.sh`, validate against the JSON schema, and make T032 pass.
- [X] T036 [US1] Capture the authoritative pre-rollout economical baseline under `evidence/runs/<timestamp>-economical-baseline/` and stop if any Application, workload, endpoint, namespace-isolation check, or dev plan is unhealthy/non-empty.
- [X] T037 [US1] Exercise a deliberately blocked no-op stage fixture from `tests/evidence/fixtures/blocked-stage.json`, verify no activation occurs, and capture the identical post-baseline in `evidence/runs/<timestamp>-economical-rollback-drill/`.
- [ ] T038 [US1] Validate and review `evidence/runs/<timestamp>-economical-rollback-drill/evidence.json`; mark US1 accepted only if SC-001 and the non-retirement boundary pass.
  - Bundle `evidence/runs/20260825T015546Z-economical-rollback-drill/` validates and every
    mandatory check passes: the blocked stage did not unlock its dependent, and the pre/post
    baselines are identical (39/39 Applications synced and healthy, 23/23 workloads ready).
    Decision stops at `approved` on purpose — `accepted` requires a named human approval
    artifact, so an automated run cannot self-accept and unlock the whole downstream rollout.
    A maintainer flips it by adding their `approvedBy` approval artifact.

    A qualifying human approval now exists: PR #76 was approved by Tiago0507 on
    2026-08-26 and merged as 7b5bca0, and the approved head tree for both evidence
    bundles is byte-identical to the merged main tree, so the approval covers exactly
    the evidence being accepted. Recording it is still a maintainer's action, not an
    automated one — writing one's own acceptance is precisely what this gate exists to
    prevent. To close this task, add an artifact with `"kind": "approval"`,
    `"result": "pass"`, and your own `approvedBy` to the drill bundle's `artifacts`,
    then set `"decision": "accepted"` and re-run
    `scripts/managed/validate-full-profile-evidence.sh` on it.

**Checkpoint**: A failed future stage is mechanically unable to advance and cannot disturb the economical platform.

---

## Phase 4: User Story 2 — Isolated Full-Profile AWS Environments (Priority: P2)

**Goal**: Operate full dev, existing full staging, and full prod in dedicated AWS VPC/EKS/state/GitOps boundaries without duplicating shared resources or requesting quota increases.

**Independent Test**: Plan and operate each environment separately; verify one logical activation, non-overlapping networks, no inter-spoke route, exact shared ownership, bounded capacity, and unchanged economical health.

### Tests first

- [X] T039 [P] [US2] Add Terraform tests for one-EIP/one-NAT centralized egress, separate empty per-spoke TGW route tables, spoke-owned attachments/default/return routes, absent spoke-to-spoke routes, encrypted flow logs, and expected outputs in `../microservice-app-ops/aws/modules/centralized-egress/tests/centralized-egress.tftest.hcl`.
- [X] T040 [P] [US2] Add full-dev root tests for account `916491575487`, `us-east-1`, `10.40.0.0/16`, one-node bootstrap, private EKS endpoint plus exactly four reviewed public `/32` CIDRs, transit egress, enabled EBS/Karpenter/AWS-load-balancer/VPC-CNI-NetworkPolicy prerequisites, consumer mode, and one cluster-qualified dev JWT reader/zero secrets in `../microservice-app-ops/aws/environments/full-dev/foundation/tests/foundation.tftest.hcl`.
- [X] T041 [P] [US2] Add full-prod root tests for account `916491575487`, `us-east-1`, `10.30.0.0/16`, one-node bootstrap, private EKS endpoint plus exactly four reviewed public `/32` CIDRs, transit egress, enabled EBS/Karpenter/AWS-load-balancer/VPC-CNI-NetworkPolicy prerequisites, consumer mode, and one cluster-qualified prod JWT reader/zero secrets in `../microservice-app-ops/aws/environments/full-prod/foundation/tests/foundation.tftest.hcl`.
- [X] T042 [P] [US2] Add a demo-full regression/opt-in test for `10.20.0.0/16`, current one NAT, current two-node bootstrap, default prerequisites off, explicit staging EBS/Karpenter/AWS-load-balancer/VPC-CNI-NetworkPolicy prerequisites on, one cluster-qualified staging JWT reader/zero secrets, `create_shared_resources=false`, and exactly the four approved `/32` values in `../microservice-app-ops/aws/environments/demo-full/foundation/tests/full-staging-contract.tftest.hcl`.
- [X] T043 [P] [US2] Extend shared-resource tests with full-dev/full-staging/full-prod issuers and exact ServiceAccount subjects, the full-dev-only Sonar secret reader/two-secret boundary, the isolated DR seed workflow subject/four-secret boundary, and a distinct platform-mirror role limited to its exact workflow and the one `microtodosuite/platform` repository in `../microservice-app-ops/aws/modules/environment-foundation/tests/{ecr,github_oidc,observability_security_irsa,kyverno_irsa,managed_secrets}.tftest.hcl`; confirm consumers still create zero shared roles, ECR repositories, or secret containers.
- [X] T044 [P] [US2] Add managed-bootstrap fixture tests for wrong account, wrong cluster, unmerged revision, checksum mismatch, third mutation, and successful two-mutation transcript in `tests/bootstrap/managed-cluster-bootstrap.bats`.

### Implementation

- [X] T045 [US2] Implement the tested egress VPC, single NAT/EIP, Transit Gateway, isolated route tables, flow logs, KMS, and outputs in `../microservice-app-ops/aws/modules/centralized-egress/{variables,main,outputs,versions}.tf`; make T039 pass.
- [X] T046 [US2] Create the independent egress root and tests in `../microservice-app-ops/aws/shared/egress/`, including `egress.s3.tfbackend` that reuses dev's exact bucket/region/KMS ARN with key `shared/egress/terraform.tfstate`, and add a plan-only Terraform 1.15.8/Infracost matrix for egress/full-dev/full-prod/demo prerequisites in `../microservice-app-ops/.github/workflows/aws-full-foundation-checks.yml`.
- [X] T047 [P] [US2] Create the full-dev root in `../microservice-app-ops/aws/environments/full-dev/foundation/` with backend key `environments/full-dev/foundation/terraform.tfstate`, `10.40.0.0/16`, the exact four reviewed `/32` operator CIDRs, consumer mode, one On-Demand bootstrap node, spoke-owned TGW routes, opt-in EBS/Karpenter/AWS-load-balancer prerequisites, and cluster-specific dev JWT/IRSA outputs; make T040 pass.
- [X] T048 [P] [US2] Create the full-prod root in `../microservice-app-ops/aws/environments/full-prod/foundation/` with backend key `environments/full-prod/foundation/terraform.tfstate`, `10.30.0.0/16`, the exact four reviewed `/32` operator CIDRs, consumer mode, one On-Demand bootstrap node, spoke-owned TGW routes, opt-in EBS/Karpenter/AWS-load-balancer prerequisites, and cluster-specific prod JWT/IRSA outputs; make T041 pass.
- [X] T049 [US2] Assert the existing `../microservice-app-ops/aws/environments/demo-full/foundation/demo-full.s3.tfbackend` still uses the shared bucket/region/KMS and its own existing key; make T042 pass without renaming or replacing physical staging resources.
- [X] T050 [P] [US2] Create one-environment in-cluster roots in `clusters/eks-full-dev/`, `clusters/eks-full-staging/`, and `clusters/eks-full-prod/`, mapping staging to physical `microtodosuite-demo-full`, declaring each root's exact planned logical activation/capability inventory, and keeping both generated business and infrastructure activation lists empty at the recorded bootstrap revision.
- [X] T051 [US2] Implement the identity/revision/checksum-guarded two-mutation helper in `scripts/managed/bootstrap-cluster.sh`, update `docs/bootstrap-boundary.md`, and make T044 pass.

**Status at this revision**: T039-T051 are complete. Every root, module, cluster
root, and helper exists, is tested, and is inert: the three GitOps roots generate
zero Applications, and every full-profile switch on the live economical and
staging environments defaults off. Nothing has been applied to AWS.

T052 onward require live cloud reads, quota checks, refreshed plans against the
real backend, an external timestamped state backup, and exact-plan approval, in
the order egress -> full dev -> full prod -> staging prerequisites -> dev-owner
trust -> GitOps roots/bootstrap. Those are human-gated by design and are not
started here.

- [ ] T052 [US2] Run collision, EIP, On-Demand/Spot quota, EKS quota, AZ/type availability, backend uniqueness, and ownership discovery; store the redacted current snapshot in `evidence/runs/<timestamp>-aws-foundations/infrastructure/quotas.json` and stop on any mismatch.
- [ ] T053 [US2] Initialize and produce a refreshed saved plan plus Infracost for `../microservice-app-ops/aws/shared/egress/`; prove one EIP/NAT, no environment route sharing, no destroy, and record the single-AZ availability trade-off/cost acceptance.
- [ ] T054 [P] [US2] Initialize and produce a refreshed saved plan plus Infracost for `../microservice-app-ops/aws/environments/full-dev/foundation/`; prove zero singleton creation, correct state/CIDR/API access, no NAT/EIP, no destroy, and quota fit.
- [ ] T055 [P] [US2] Initialize and produce a refreshed saved plan plus Infracost for `../microservice-app-ops/aws/environments/full-prod/foundation/`; prove zero singleton creation, correct state/CIDR/API access, no NAT/EIP, no destroy, and quota fit.
- [ ] T056 [US2] First re-plan unchanged `../microservice-app-ops/aws/environments/demo-full/foundation/` and require exactly `0 to add, 0 to change, 0 to destroy`, account `916491575487`, and exactly the four approved `/32` CIDRs; only then enable staging's opt-in EBS/Karpenter/AWS-load-balancer/VPC-CNI-NetworkPolicy and cluster-qualified JWT reader inputs and produce a second saved plan/Infracost containing only those intended prerequisite additions/updates with no replacement/destroy.
- [ ] T057 [US2] After exact-plan approval, create an external timestamped state backup and apply only T053's saved egress plan; record plan SHA, backup path/checksum, approval, apply output, routes, flow logs, NAT health, and unchanged economical post-baseline in `evidence/runs/<timestamp>-aws-foundations/egress/`.
- [ ] T058 [US2] After exact-plan approval and external state backup, apply only T054's saved full-dev plan; record state/plan checksums, outputs, cluster identity, node readiness, TGW egress, and unchanged economical post-baseline in `evidence/runs/<timestamp>-aws-foundations/full-dev/`.
- [ ] T059 [US2] After exact-plan approval and external state backup, apply only T055's saved full-prod plan; record state/plan checksums, outputs, cluster identity, node readiness, TGW egress, and unchanged economical post-baseline in `evidence/runs/<timestamp>-aws-foundations/full-prod/`.
- [ ] T060 [US2] After exact-plan approval and an external demo-full state backup, apply only T056's second saved staging-prerequisite plan; then capture the three full EKS OIDC issuer ARNs/URLs from real Terraform outputs into non-secret owner inputs and update `../microservice-app-ops/aws/environments/dev/foundation/main.tf`, `variables.tf`, `dev.tfvars`, and `release-secrets.tf` so dev state alone extends shared Kyverno/notification trust and opts into the one platform mirror repository/role, write-only Grafana/Sonar secrets, the full-dev Sonar reader, and exact DR seed role; make T043 pass.
- [ ] T061 [US2] Produce and review the refreshed dev owner saved plan for T060; accept only exactly one new `microtodosuite/platform` repository, its separate exact-workflow mirror role, the intended shared-role trust-policy updates, Grafana/Sonar secret containers and write-only versions, full-dev Sonar reader, and four-ARN DR seed role with zero change to the five service repositories and zero shared resource replacement/destruction; attach Infracost/rollback evidence.
- [ ] T062 [US2] After exact-plan approval and an external dev state backup, apply only T061's saved plan; prove shared Kyverno/notification roles trust the original and three new exact issuers only for named ServiceAccounts, cluster-qualified JWT readers trust only their own issuer/environment, the Sonar reader trusts only full-dev's exact tooling ServiceAccount and two ARNs, the publisher remains GitHub-only, the platform-mirror role trusts only its approved workflow and writes only `microtodosuite/platform`, the seed role trusts only its approved workflow and reads only four ARNs, every new value is absent from state/plan/evidence, the five service repositories remain unchanged, and no wildcard subject was introduced.
- [ ] T063 [US2] Open, review, and merge the three empty full-cluster GitOps roots through protected `main`, retaining PR checks, approvals, reviewed head SHAs, merge SHAs, and economical golden/live health.
- [ ] T064 [US2] For each of `microtodosuite-demo-full`, `microtodosuite-full-dev`, and `microtodosuite-full-prod`, first prove whether ArgoCD already exists with valid prior bootstrap evidence; execute exactly the two audited mutations from `scripts/managed/bootstrap-cluster.sh` only when absent, otherwise perform read-only verification, retain a separate transcript, and do nothing else directly in the cluster.
- [ ] T065 [P] [US2] Verify each full ArgoCD root targets only its in-cluster API, generates no business workload or platform add-on before activation, and reports the reviewed `main` revision using read-only checks.
- [ ] T066 [US2] Run VPC/TGW reachability tests proving private full-dev/prod node egress through centralized NAT, public-subnet ingress readiness without public worker addresses, no dev-to-prod/staging/economical private route, and no staging topology change; record NAT/TGW/IGW routes, metrics, and flow-log evidence in `evidence/runs/<timestamp>-aws-foundations/network-isolation/`.
- [ ] T067 [US2] Validate `evidence/runs/<timestamp>-aws-foundations/evidence.json` against SC-002, SC-003, SC-012, SC-013, and SC-014, and accept US2 only after the economical post-baseline passes.

**Checkpoint**: Three isolated full AWS environments exist, but none hosts full workloads until US3 gates pass.

---

## Phase 5: User Story 3 — Complete Secure and Observable Platform (Priority: P3)

**Goal**: Run every required platform capability and service contract with TLS/mTLS, managed secrets, admission, telemetry, bounded scaling, runtime security, and cost allocation.

**Independent Test**: In full dev, send one service request and prove trusted ingress TLS, strict service identity, resilience behavior, probes, correlated metric/trace/log, alert delivery, policy denial, scaling, runtime detection, cost attribution, and controlled recovery without direct cluster mutation.

### Tests first

- [ ] T068 [P] [US3] Add a failing exact capability/version/resource-budget/image/storage inventory test in `tests/platform/full-capability-inventory.bats`, comparing every full root against FR-023 plus required audit/notification capabilities, requiring every GitOps-installed third-party platform image by immutable upstream digest and mirrored ECR digest, enforcing cloud-specific encrypted EKS/Azure Disk storage overlays for stateful capabilities, requiring exactly one SonarQube/PostgreSQL shared-tooling activation in full-dev and none elsewhere, applying cloud-specific Karpenter rules, and forbidding full-only capabilities in economical roots.
- [ ] T069 [P] [US3] Add failing mesh/network render tests for namespace revision labels, STRICT mTLS, default-deny AuthorizationPolicy and NetworkPolicy, explicit DNS/ingress/service-dependency/Redis/telemetry/controller-webhook/cloud-API flows with no cross-environment path, retries/timeouts/connection pools/outlier detection, AWS-controller NLB versus Terraform-owned static-public-IP Azure ingress wiring, destination HTTP-01 and production DNS-01 certificate separation, an HTTP exception limited to the ACME challenge path with all other plaintext redirected/rejected, trusted ingress TLS, and Kiali non-public access in `tests/platform/mesh-policy.bats`.
- [ ] T070 [P] [US3] Add failing cloud-secret tests for AWS IRSA and Azure workload identity/Key Vault references, exact JWT/Alertmanager/Falco/Grafana/Sonar source-name mappings, production JWT parity metadata, no ad hoc generator for application or operator-supplied runtime/admin values, an explicit generator/consumer/rotation allowlist limited to controller-owned TLS/service-account/internal-bootstrap material, exact full-dev-only Sonar reader scope, and no literal/exported values in `tests/platform/external-secrets.bats`.
- [ ] T071 [P] [US3] Add failing platform tests for unsigned/unmirrored/mutable images, wrong platform-mirror signature identity, incomplete OCI graph, alert, Falco trigger, ECK recovery, SonarQube/PostgreSQL readiness and retained-volume recovery, audit Jobs, bounded scaling, chaos activation, controlled non-secret runtime configuration, and auditable default-off feature toggles as GitOps-owned manifests in `tests/platform/{platform-image-supply-chain,failure-fixtures,runtime-config}.bats`.
- [ ] T072 [P] [US3] Add auth-api health, correlation, OpenTelemetry, timeout/retry/circuit-breaker, and metrics tests in `../microservice-app-auth-api/main_test.go` and `user_test.go`; confirm failure before T077.
- [ ] T073 [P] [US3] Add frontend health/config/correlation and failure UX tests in `../microservice-app-frontend/test/unit/operational-contract.test.js` and extend `../microservice-app-frontend/e2e/specs/todos.spec.js`; confirm failure before T078.
- [ ] T074 [P] [US3] Add log processor health, correlation, OpenTelemetry, Redis retry/backoff, and metrics tests in `../microservice-app-log-message-processor/tests/test_operational_contract.py` and `tests/integration/test_redis_consume.py`; confirm failure before T079.
- [ ] T075 [P] [US3] Add todos API health, correlation, OpenTelemetry, Redis timeout/retry/circuit-breaker, and metrics tests in `../microservice-app-todos-api/test/operational-contract.test.js` and `test/integration/redis-publish.test.js`; confirm failure before T080.
- [ ] T076 [P] [US3] Add users API Actuator startup/readiness/liveness, correlation, OpenTelemetry, authentication-path, and metrics tests in `../microservice-app-users-api/src/test/java/com/elgris/usersapi/UsersApiApplicationTests.java`; confirm failure before T081.

### Service implementation

- [ ] T077 [P] [US3] Implement the auth-api health/correlation/telemetry/resilience and externally supplied non-secret config/feature-toggle contract in `../microservice-app-auth-api/main.go`, `otel.go`, and `user.go`, update `contracts/openapi.yaml`, and make T072 pass.
- [ ] T078 [P] [US3] Implement the frontend runtime-config/default-off feature-toggle, health, correlation, and telemetry contract in `../microservice-app-frontend/src/http.js`, `src/main.js`, `entrypoint.sh`, and `nginx.conf.template`; make T073 pass.
- [ ] T079 [P] [US3] Implement the log processor health/correlation/telemetry/resilience and externally supplied non-secret config/feature-toggle contract in `../microservice-app-log-message-processor/main.py`, `requirements.in`, and `requirements-dev.in`, regenerate hashed lock files, update `contracts/asyncapi.yaml`, and make T074 pass.
- [ ] T080 [P] [US3] Implement the todos API health/correlation/telemetry/resilience and externally supplied non-secret config/feature-toggle contract in `../microservice-app-todos-api/server.js`, `routes.js`, and `todoController.js`, update OpenAPI/AsyncAPI contracts, and make T075 pass.
- [ ] T081 [P] [US3] Implement the users API health/correlation/telemetry/authentication and externally supplied non-secret config/feature-toggle contract in `../microservice-app-users-api/pom.xml`, `src/main/java/com/elgris/usersapi/UsersApiApplication.java`, `src/main/java/com/elgris/usersapi/api/{UsersController,CounterController}.java`, `src/main/java/com/elgris/usersapi/configuration/SecurityConfiguration.java`, `src/main/resources/{application.properties,logback-spring.xml}`, and `contracts/openapi.yaml`; make T076 pass.

### Platform implementation

- [ ] T082 [P] [US3] Implement and contract-test the exact-workflow OIDC platform-image mirror in `../.github/.github/workflows/mirror-platform-images.yml` and `../.github/tests/workflows/mirror-platform-images.bats`; copy every locked upstream digest to `microtodosuite/platform`, scan it, record source/mirror digests, and keyless-sign the complete graph without rebuilding or granting access to any service repository.
- [ ] T083 [US3] Vendor checksum-pinned AWS Load Balancer Controller 3.5.0, Istio 1.30.3, and Kiali 2.31.0 under `infrastructure/aws-load-balancer-controller/`, `infrastructure/istio/`, and `infrastructure/kiali/` using only locked mirrored ECR digests, a GitOps-owned EKS ServiceAccount annotated with the exact Terraform-output IRSA role ARN, cert-manager-managed webhook certificates, resource budgets, network policy, Prometheus integration, and no public Kiali ingress; add full-profile namespace labels, PeerAuthentication, AuthorizationPolicy, DestinationRule, VirtualService, ingress Gateway, trusted-certificate references, and default-deny plus exact required-flow NetworkPolicies under `environments/full/` and each service's `components/topology-full/`, and make T069 pass.
- [ ] T084 [P] [US3] Vendor checksum-pinned ECK 3.5.0 and add resource-bounded Elasticsearch, Kibana, Logstash, and Filebeat desired state under `infrastructure/{eck-operator,elasticsearch,kibana,logstash,filebeat}/` with cloud-specific encrypted retained-storage overlays (`gp3` on EKS and the Terraform-approved Azure Disk class on AKS); harden `infrastructure/sonarqube/` for its full-dev-only tooling role with SonarQube `26.8.0.126808-community`, PostgreSQL `16.15-alpine3.24`, mirrored manifest digests, encrypted retained gp3 PVCs, dedicated taint/toleration and GitOps-owned EC2NodeClass user data that sets `vm.max_map_count` without a privileged pod, probes, PDBs, NetworkPolicy, resource budget, backup/recovery tests, and rollback documentation.
- [ ] T085 [P] [US3] Complete Prometheus, Alertmanager, Grafana, Jaeger, and OpenTelemetry correlation under `infrastructure/{prometheus,grafana,jaeger}/`, including cloud-specific encrypted persistence for stateful components, error-rate/p99/scaling/platform/security rules, and External Secret-backed notifications.
- [ ] T086 [P] [US3] Vendor checksum-pinned Karpenter 1.14.1 under `infrastructure/karpenter/` and create per-cluster Spot-only NodePools/EC2NodeClasses with reviewed 2-vCPU/8-GiB allowlists, Terraform-output interruption queue, independent ceilings, disruption budgets, and aggregate <=24-vCPU Spot limit.
- [ ] T087 [P] [US3] Vendor checksum-pinned Chaos Mesh 2.8.4 and OpenCost 2.5.29 under `infrastructure/chaos-mesh/` and `infrastructure/opencost/`; add disabled experiment roots and cluster/environment/service cost labels.
- [ ] T088 [P] [US3] Harden `infrastructure/{kyverno,falco,kube-bench,kube-hunter}/` with immutable-digest and signature policies covering all business plus GitOps-installed platform namespaces, accepting only the approved service-CI or platform-mirror workflow identities while explicitly excluding Terraform-managed EKS system add-ons from namespaced admission scope; add unsigned/unmirrored/mutable/wrong-identity failure fixtures, resource bounds, exact RBAC, scheduled audit retention, and GitOps-owned trigger Jobs, remove imperative creation from `scripts/managed/verify-security.sh`, and make T071 pass.
- [ ] T089 [US3] Add cloud-specific SecretStore/ClusterSecretStore and ExternalSecret overlays in `infrastructure/external-secrets/overlays/{aws,azure}/` and service full overlays for the exact JWT/Alertmanager/Falco/Grafana names, replace the full-profile Grafana generator with a cloud-secret reference, add the full-dev Sonar DB/admin ExternalSecrets, and add External Secret-backed contextual ArgoCD Notifications reusing the approved notification secret in `infrastructure/argocd-notifications/`; use exact IRSA/workload-identity subjects and no committed value, and make T070 pass.
- [ ] T090 [US3] Add startup/readiness/liveness probes, requests/limits, PodDisruptionBudgets, topology spread, ServiceMonitors, full topology, KEDA ScaledObjects, resilience settings, controlled ConfigMaps, and documented default-off feature toggles for all five services under `apps/*/base/`, `components/topology-full/`, `profiles/full/overlays/*/`, and `environments/full/`; make the runtime-config portion of T071 pass.
- [ ] T091 [US3] Define explicit dependency-wave capability activation in `clusters/eks-full-{dev,staging,prod}/activation-infrastructure.yaml`, activate SonarQube/PostgreSQL only in full-dev after ingress/storage/secrets, and keep business activation separate; make T068 pass.
- [ ] T092 [US3] Run every service test/contract suite, all Kustomize/kubeconform/policy tests, image/secret scans, and resource-budget calculations; merge T082's reviewed organization-workflow PR through protected `main`, execute that exact revision for every locked third-party image before any EKS capability activation, and prove upstream-to-ECR digest mapping, complete OCI graph, scan pass, approved keyless signature identity, and absence of mutable/unmirrored references; retain redacted output in `evidence/runs/<timestamp>-full-platform-static/` and stop on any skip/failure.
- [ ] T093 [US3] Merge the full-dev platform dependency waves through reviewed GitOps PRs through the Istio NLB and capture its real hostname; implement validated optional records in `../microservice-app-ops/aws/modules/environment-foundation/route53.tf` and the dev root, inventory current registrar-hosted records, then use one reviewed saved plan/Infracost plus external backup/approval to create exactly one separately addressed `microtodosuite.online` Route 53 zone and only `full-dev.microtodosuite.online` and `sonar-full-dev.microtodosuite.online` CNAMEs to that NLB with zero legacy-zone replacement/destruction; change registrar delegation only to the exact Terraform output name servers, verify public NS/SOA agreement, wait read-only for both trusted HTTP-01 certificates, SonarQube/PostgreSQL, and every wave to become Synced/Healthy, and revert/stop on record loss, capacity, storage, CRD, policy, secret, TLS, DNS, or economical regression.
- [ ] T094 [US3] Activate one signed full-dev service through GitOps and collect ingress TLS, 100% sampled strict mTLS, enforced NetworkPolicy plus live `aws-eks-nodeagent --enable-network-policy=true`, denial, probes, correlated telemetry within five minutes, Alertmanager delivery within five minutes, contextual ArgoCD reconciliation-failure notification, KEDA/Karpenter scaling within five minutes, Falco/audit, OpenCost, ECK and Sonar retained-volume recovery, and rollback evidence.
- [ ] T095 [US3] Activate and accept all five full-dev services only after T094; verify service dependencies, isolation, resource ceilings, Spot interruption recovery, and unchanged economical health in `evidence/runs/<timestamp>-full-platform/full-dev-all-services/`.
- [ ] T096 [US3] Promote the identical accepted platform configuration through the full-staging Istio NLB, create only `full-staging.microtodosuite.online` through a reviewed dev-owner saved plan/Infracost plus external backup/approval, then promote the service digests through reviewed GitOps PRs; verify trusted TLS, physical `demo-full`, exact four `/32` API allowlist, mesh/security/observability behavior, and unchanged state ownership.
- [ ] T097 [US3] Promote the accepted platform configuration through the full AWS-production Istio NLB, create only `full-prod-aws.microtodosuite.online` through a reviewed dev-owner saved plan/Infracost plus external backup/approval, then promote the service digests with shared production traffic still disabled; verify trusted TLS, live capabilities, isolation, and capacity without creating `app.microtodosuite.online` latency records.
- [ ] T098 [US3] Validate `evidence/runs/<timestamp>-full-platform/evidence.json` against SC-004, SC-007, SC-008, SC-009, and SC-014 and accept US3 only after all success/failure/rollback and economical post-baseline checks pass.

**Checkpoint**: The complete full platform works on all AWS full clusters; public active-active traffic remains disabled.

---

## Phase 6: User Story 4 — Immutable Progressive Promotion and Rollback (Priority: P4)

**Goal**: Build one fully verified digest, promote it across profile/destination boundaries, canary it in AWS full production, and reverse failures through Git history.

**Independent Test**: Promote one service digest from full dev to staging to AWS production, force one canary analysis failure, verify automatic restoration within five minutes, then complete a healthy canary and prove every live digest/trace record.

### Tests first

- [ ] T099 [P] [US4] Add reusable-workflow contract tests and a five-service quality-gate matrix for required unit/integration/contract/E2E/performance/DAST coverage, Sonar fail-closed behavior, digest-only output, OIDC, short-lived GitHub App tokens supplied through the exact `RELEASE_APP_ID`/`RELEASE_APP_KEY` and `GITOPS_PROMOTE_APP_ID`/`GITOPS_PROMOTE_APP_KEY` caller secrets, exact destination tuples, and no cluster mutation in `../.github/tests/workflows/`.
- [ ] T100 [P] [US4] Add canary render tests for a full-only strategy at 10/25/50/100 traffic weights, five-minute error-rate and p99 analyses, missing-metric failure, automatic abort, stable rollback, and byte-identical economical native-canary golden output in `tests/promotion/full-production-canary.bats`.
- [ ] T101 [P] [US4] Add per-service workflow tests asserting every available unit/integration/contract/E2E/performance/DAST harness is blocking and each reusable workflow is pinned by full SHA in `tests/promotion/service-workflows.bats`.

### Implementation

- [ ] T102 [US4] Make `../.github/.github/workflows/ci.yml` fail closed for required Sonar/test inputs, retain build-once/Trivy/Syft/Cosign behavior, pin every Action by full SHA, and make the CI portion of T099 pass.
- [ ] T103 [P] [US4] Pin and validate the GitHub App installation-token paths in `../.github/.github/workflows/{release,promote}.yml`; add reviewed manifests for separate release and GitOps-promotion Apps, exact repository installations/permissions, selected-repository organization secret names, mode-`0600` private-key upload/cleanup, rotation, and fail-closed authority checks to `../microservice-app-docs/full-platform/github-app-authentication.md`; add a value-blind one-time Sonar administrator-rotation/forced-auth/five-project/analysis-only-token helper in `scripts/managed/bootstrap-sonarqube.sh` and its tests in `tests/promotion/bootstrap-sonarqube.bats`, without adding a PAT, leaving anonymous project access, or exposing either credential.
- [ ] T104 [US4] Extend `../.github/.github/workflows/promote.yml` with validated `profile`, `destination`, and strategy inputs, pinned Kustomize/checksum installation, exact-digest Cosign verification, and one-overlay PR behavior; make T099 pass.
- [ ] T105 [P] [US4] Wire auth-api's complete required gates and updated shared workflow SHAs in `../microservice-app-auth-api/.github/workflows/ci.yml`.
- [ ] T106 [P] [US4] Wire frontend's unit, conformance, Pact, full five-service stack E2E, performance, DAST, Sonar, and updated shared workflow SHAs in `../microservice-app-frontend/.github/workflows/{ci,conformance,pact,e2e,perf,dast}.yml`, extending `../microservice-app-frontend/e2e/` so the matrix covers every service interaction required for release.
- [ ] T107 [P] [US4] Wire log-message-processor's unit/integration/AsyncAPI/Sonar and updated shared workflow SHAs in `../microservice-app-log-message-processor/.github/workflows/ci.yml`.
- [ ] T108 [P] [US4] Wire todos-api's unit/integration/OpenAPI/AsyncAPI/Pact/Sonar and updated shared workflow SHAs in `../microservice-app-todos-api/.github/workflows/ci.yml`.
- [ ] T109 [P] [US4] Wire users-api's unit/integration/OpenAPI/Sonar and updated shared workflow SHAs in `../microservice-app-users-api/.github/workflows/ci.yml`.
- [ ] T110 [US4] Add p99 and error-rate fail-closed AnalysisTemplates in `infrastructure/argo-rollouts/cluster-analysis-template.yaml` and create full-only Istio traffic routing in `apps/*/components/strategy-canary-full/rollout.yaml`; reference it only from full AWS production, leave `components/strategy-canary/` economical output unchanged, and make T100 pass.
- [ ] T111 [US4] Run and review the five-service quality matrix plus all service/shared workflow tests; verify or create/install the two reviewed organization-owned GitHub Apps and upload the four exact selected-repository organization Actions secrets, run the value-blind Sonar bootstrap against `https://sonar-full-dev.microtodosuite.online`, immediately rotate default admin, force authentication, create the five fixed project keys and one analysis-only identity, set selected-repository `SONAR_HOST_URL`/`SONAR_TOKEN`, delete every local private-key/token file after metadata verification, and prove anonymous project access is denied plus a real fail-closed quality gate and short-lived installation-token/OIDC audit evidence; stop on insufficient authority and never substitute a PAT, then make T099/T101 pass before enabling promotion.
- [ ] T112 [US4] Build one reviewed service revision once; retain unit/integration/contract/E2E/performance/DAST, Sonar, Trivy, SBOM, signature, source SHA, ECR digest, and Kyverno admission evidence in `evidence/runs/<timestamp>-release/`.
- [ ] T113 [US4] Promote T112's exact digest through full dev and full staging rolling updates via reviewed GitOps PRs, proving no rebuild and exact live digest at both destinations in `evidence/runs/<timestamp>-release/dev-staging-promotion/`.
- [ ] T114 [US4] Enable the checked-in unhealthy-canary fixture by reviewed GitOps PR in full AWS production, prove error or p99 analysis aborts before the next step and restores stable within five minutes, then remove it by Git revert and retain results in `evidence/runs/<timestamp>-release/failed-canary/`.
- [ ] T115 [US4] Promote T112's exact digest through a healthy 10/25/50/100 full-production canary, record every AnalysisRun/traffic step/live digest in `evidence/runs/<timestamp>-release/healthy-canary/`, and keep public active-active routing disabled.
- [ ] T116 [US4] Revert the accepted promotion commit in a controlled rollback drill, prove the previous signed digest and endpoint health return, then restore forward through a reviewed PR without rebuilding and retain results in `evidence/runs/<timestamp>-release/rollback/`.
- [ ] T117 [US4] Validate `evidence/runs/<timestamp>-release/evidence.json` against SC-005 and SC-006 plus FR-037 through FR-043; accept US4 only after immutable identity, failure, rollback, and economical post-baseline evidence pass.

**Checkpoint**: One immutable digest has a proven promotion and rollback path through AWS production.

---

## Phase 7: User Story 5 — Active-Active Disaster Recovery (Priority: P5)

**Goal**: Operate an independently reconciled AKS destination with the production digest, prove controlled failover, and leave real traffic behind a separate approval.

**Independent Test**: With destination-specific test traffic, make AWS full production ineligible and prove AKS keeps reconciling and serves all eligible traffic within ten minutes while data loss/divergence is measured separately.

### Tests first

- [ ] T118 [P] [US5] Add Azure module tests for subscription/location guards, non-overlapping VNet/pod/service ranges, private node subnets, AKS 1.35 with Azure CNI Overlay and Cilium policy enforcement, workload identity/OIDC, an API allowlist equal to the four approved `/32` CIDRs and never `0.0.0.0/0`, an empty Key Vault with exact AKS-reader and GitHub-seed access boundaries but zero `azurerm_key_vault_secret` resources, ACR, encrypted storage, tags, and a Standard static ingress public IP with unique DNS label, dedicated resource group, narrowly scoped cluster-identity role assignment, and name/resource-group/address/FQDN outputs in `../microservice-app-ops/azure/modules/aks-foundation/tests/aks-foundation.tftest.hcl`.
- [ ] T119 [P] [US5] Add Azure DR root/backend tests for one unique locked state, consumer identity, exact non-secret Key Vault name mappings, no secret value/provider output/static credential, and active-active disabled by default in `../microservice-app-ops/azure/environments/dr/foundation/tests/foundation.tftest.hcl`.
- [ ] T120 [P] [US5] Add AKS root tests for independent in-cluster reconciliation, an activation-empty bootstrap revision followed by production/full activation, cloud-specific secret store and encrypted Azure Disk persistence, ACR digest references for every service and mirrored platform image except full-dev-only SonarQube/PostgreSQL, complete otherwise-equivalent capability inventory, exact static-public-IP Service annotations, a default-disabled common-certificate component, and audience-`sts.amazonaws.com` projected token plus `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_REGION=us-east-1`, and regional-STS settings only on the cert-manager DNS-01 path in `tests/profiles/aks-dr.bats`.
- [ ] T121 [P] [US5] Add shared-workflow tests for AWS/Azure OIDC service/platform OCI mirroring and DR secret seeding in `../.github/tests/workflows/{mirror-to-acr,mirror-platform-images,sync-dr-secrets}.bats`: require no Dockerfile/build, recursive signature/SBOM copy, equal manifest digests for the service artifact and complete locked platform graph, production-validated-only service input, approved platform-mirror identity, exact four-secret mapping, an in-process prod-JWT equality boolean with no value-derived digest, disabled shell tracing, early masking, no cache/artifact/value output, mode-`0600` temporary handling with cleanup trap, and no static credential.
- [ ] T122 [P] [US5] Add dev-owner tests for exactly one canonical `microtodosuite.online` Route 53 zone at its separate resource address, zero legacy-zone replacement/destruction, the four exact destination CNAME records plus `sonar-full-dev.microtodosuite.online`, HTTPS health checks, fail-closed provider-FQDN inputs, zero `app.microtodosuite.online` routing records when disabled, one AKS-issuer IAM OIDC provider, exact AWS-production/AKS cert-manager trust subjects with audience `sts.amazonaws.com`, and permissions restricted to the common hostname's ACME TXT record in `../microservice-app-ops/aws/modules/environment-foundation/tests/{route53,dns01_irsa}.tftest.hcl`.
- [ ] T123 [P] [US5] Add bounded selector/duration/abort/render tests for pod termination, network latency, Redis saturation, AWS-production outage, and Azure outage in `tests/chaos/dr-game-day.bats`.

### Implementation

- [ ] T124 [US5] Install/verify Azure CLI from the checksum-pinned artifact in `scripts/managed/full-profile-toolchain.lock`, then run `../microservice-app-ops/scripts/preflight/azure-dr.sh` against the real authenticated account, verify approved subscription/location/backend/VNet/quota/provider data, select collision-free VNet `10.50.0.0/16` only if live evidence permits it plus non-overlapping pod/service/DNS ranges, and retain redacted results; stop on any unresolved fact.
- [ ] T125 [US5] Implement direct AzureRM 5.0.1 AKS foundation resources with Azure CNI Overlay/Cilium using T124's verified ranges, bounded cluster autoscaler, empty Key Vault plus exact workload-reader/GitHub-seed identities and non-secret name outputs, and a Terraform-owned Standard static ingress public IP in a dedicated resource group with unique DNS label, narrowly scoped cluster-identity Network Contributor assignment, and name/resource-group/address/FQDN outputs in `../microservice-app-ops/azure/modules/aks-foundation/{variables,main,network,identity,registry,secrets,ingress,outputs,versions}.tf`; make T118 pass.
- [ ] T126 [US5] Create `../microservice-app-ops/azure/environments/dr/foundation/` with the verified non-secret values, distinct locked Azure Blob backend key, AKS 1.35, VNet, exact four-`/32` API allowlist, ACR, Key Vault, workload identities, static ingress public-IP/DNS-label inputs, and `enable_active_active=false`; add a plan-only Terraform 1.15.8/Azure-OIDC/Infracost workflow in `../microservice-app-ops/.github/workflows/azure-dr-foundation-checks.yml`, and make T119 pass.
- [ ] T127 [US5] Initialize the verified Azure backend and produce a refreshed saved plan plus Infracost; prove correct subscription/location, no unexpected destroy, quota/cost fit, no static secret, and accepted rollback before any apply, retaining only redacted plan metadata in `evidence/runs/<timestamp>-azure-foundation/infrastructure/`.
- [ ] T128 [US5] After exact-plan approval and an external timestamped Azure state backup, apply only T127's saved AKS plan; record plan/state checksums, identity, outputs, node readiness, ACR/Key Vault access boundaries, and unchanged economical post-baseline in `evidence/runs/<timestamp>-azure-foundation/live/`.
- [ ] T129 [US5] Create `clusters/aks-dr/` with independent in-cluster ArgoCD and an initially empty activation root that declares the planned production/full capability inventory, Azure secret-store overlay, ACR digest paths, exclusion of AWS-only Karpenter and full-dev-only SonarQube/PostgreSQL, and an Istio LoadBalancer Service bound to T125's exact public-IP name/resource group without activating them yet; add a default-disabled common-certificate component whose cert-manager-only contract requires the projected audience-`sts.amazonaws.com` token and `AWS_ROLE_ARN`/`AWS_WEB_IDENTITY_TOKEN_FILE`/`AWS_REGION`/regional-STS values but no static key, and make the bootstrap portion of T120 pass.
- [ ] T130 [US5] Merge the activation-empty AKS root through protected `main`, execute exactly the two audited bootstrap mutations for the verified AKS context, and prove independent empty-root sync/health/notifications with no workload/platform activation and no post-bootstrap direct mutation.
- [ ] T131 [US5] Implement the OIDC-authenticated no-rebuild service OCI graph mirror and extend `../.github/.github/workflows/mirror-platform-images.yml` to copy the complete already-signed locked platform graph from ECR to ACR in `../.github/.github/workflows/{mirror-to-acr,mirror-platform-images}.yml`; implement the no-persistence secret seed in `../.github/.github/workflows/sync-dr-secrets.yml`, integrate the service mirror and seed after successful AWS production promotion in `../.github/.github/workflows/promote.yml`, and make T121 pass.
- [ ] T132 [US5] Configure the least-privilege GitHub-to-Azure federated credentials, exact AWS DR seed-role subject, and repository environment approvals from Terraform/approved settings; verify no PAT, client secret, registry password, AWS access key, personal token, or secret value is maintained in GitHub configuration, and retain metadata-only proof in `evidence/runs/<timestamp>-azure-foundation/identity/github-federation.json`.
- [ ] T133 [US5] Run the reviewed DR seed workflow and verify only four Azure Key Vault secret names/versions exist plus an in-process true production-JWT equality result with no value-bearing or value-derived output; copy every locked signed platform OCI graph from ECR to ACR and prove complete digest/signature equality before activating AKS capabilities through a reviewed GitOps PR, then mirror T115's production service digest/signature/SBOM graph, verify ECR/ACR manifest digest equality and Cosign identity, and promote that exact digest to AKS by rolling GitOps PR only after platform health and External Secrets readiness, retaining redacted proof in `evidence/runs/<timestamp>-dr-game-day/aks-activation/`.
- [ ] T134 [US5] Verify the live AKS ingress address and provider FQDN equal T125's Terraform outputs, then add only the `full-prod-azure.microtodosuite.online` CNAME, Terraform-owned HTTPS health checks, the AKS-issuer IAM OIDC provider, and separate exact-subject AWS-production/AKS DNS-01 solver roles to dev owner state with `enable_active_active=false`; restrict both roles to `_acme-challenge.app.microtodosuite.online` TXT changes and minimum read/status actions, produce a refreshed saved plan and Infracost, obtain exact-plan/cost approval, create an external state backup, apply only that saved plan, wait for trusted AKS destination HTTP-01 TLS, and make T122 pass.
- [ ] T135 [US5] Implement disabled-by-default GitOps scenarios and steady-state assertions under `experiments/full-profile/{pod-termination,network-latency,redis-saturation,aws-prod-outage,azure-outage}/`; make T123 pass.
- [ ] T136 [US5] Execute pod, latency, Redis, and individual destination-outage experiments through reviewed Git activation/revert commits; collect read-only health, mesh, alert, trace/log/metric, release, and economical-baseline evidence in `evidence/runs/<timestamp>-dr-game-day/scenarios/`.
- [ ] T137 [US5] Run the approved complete-AWS-production-outage game day with destination-specific test traffic; prove AKS independent reconciliation and full eligible traffic within ten minutes, then restore AWS through the reviewed rollback and retain the UTC timeline in `evidence/runs/<timestamp>-dr-game-day/aws-outage/`.
- [ ] T138 [US5] Record every sampled Redis message, todo, and user as observed/lost/duplicate/divergent in `evidence/runs/<timestamp>-dr-game-day/continuity.json`, set `durabilityClaim` to `none`, and obtain operator acknowledgement.
- [ ] T139 [US5] After T137-T138, issue and verify trusted `app.microtodosuite.online` certificates sequentially through reviewed GitOps commits and T134's DNS-01 roles: annotate only the AWS-production cert-manager ServiceAccount with its role ARN, then enable only AKS cert-manager's exact projected-token/env contract with its separate role ARN; prove no shared application routing record, broad trust, or static credential exists, then produce the final dev-owner Route 53 saved plan and Infracost with `enable_active_active=true`, two health-evaluated latency CNAME records targeting the exact AWS/Azure provider FQDNs, and trusted HTTPS health checks, and require a separate named human approval for that exact plan and cost.
- [ ] T140 [US5] If and only if T139 receives separate exact-plan approval, create an external dev state backup, apply only that saved Route 53 plan, verify healthy latency routing and either-side failover, and retain immediate rollback evidence; otherwise record `traffic-disabled-ready` as the truthful outcome.
- [ ] T141 [US5] Validate `evidence/runs/<timestamp>-dr-game-day/evidence.json` against SC-010 and SC-011 plus the DR contract, and accept US5 only with independent reconciliation, digest equality, failover, continuity disclosure, rollback, and economical post-baseline proof.

**Checkpoint**: DR is proven. Real active-active traffic is either separately approved and verified or explicitly remains disabled-ready.

---

## Phase 8: User Story 6 — Auditable Stage Gates (Priority: P6)

**Goal**: Make cost, quota, security, health, failure, rollback, and economical-regression evidence complete and continuously reviewable for every stage.

**Independent Test**: Remove or corrupt one mandatory artifact from a completed stage and prove CI marks it blocked; restore the immutable artifact and prove the full cross-repository evidence matrix passes.

### Tests first

- [ ] T142 [P] [US6] Add tamper, stale-timestamp, failed-requirement, missing-Infracost, missing-state-backup, missing-human-approval, and economical-regression fixtures to `tests/evidence/validate-evidence.bats`; confirm they fail before T145.
- [ ] T143 [P] [US6] Add CI tests for recurring source/image/cluster vulnerability findings and actionable ownership in `../.github/tests/workflows/continuous-security.bats`.
- [ ] T144 [P] [US6] Add OpenCost allocation/label/query tests for cluster, environment, profile, namespace, and service in `tests/platform/opencost-allocation.bats`.

### Implementation

- [ ] T145 [US6] Extend `scripts/managed/validate-full-profile-evidence.sh` and `.github/workflows/validate-gitops.yml` to verify artifact hashes, freshness, requirement coverage, stage dependencies, cost/backup/approval fields, and economical pre/post parity; make T142 pass.
- [ ] T146 [US6] Add scheduled reusable source/image/cluster vulnerability assessment and issue-routing behavior in `../.github/.github/workflows/continuous-security.yml`, then wire the five service repositories and ops/GitOps callers; make T143 pass.
- [ ] T147 [US6] Complete OpenCost labels, Prometheus queries, Grafana dashboard, and evidence collector in `infrastructure/opencost/`, `infrastructure/grafana/dashboards/full-profile-cost.yaml`, and `scripts/managed/verify-full-profile-cost.sh`; make T144 pass.
- [ ] T148 [P] [US6] Implement read-only multi-cluster desired/live/failure/rollback evidence collection in `scripts/managed/verify-full-platform.sh`, replacing warning-as-success behavior in `scripts/managed/verify-observability.sh` and `verify-security.sh` with explicit pass/fail/blocked output.
- [ ] T149 [P] [US6] Add stage cost ceilings, actual spend review, availability trade-offs, ownership, and rollback decisions to `../microservice-app-docs/full-platform/stage-register.md` and live operational procedures to `../microservice-app-docs/full-platform/operations.md`.
- [ ] T150 [US6] Validate every completed stage bundle, recompute all hashes, and generate FR-001..FR-050 and SC-001..SC-014 coverage in `evidence/runs/<timestamp>-final/requirements-matrix.json`; no requirement may be inferred from configuration alone.
- [ ] T151 [US6] Deliberately corrupt a copy of one accepted bundle, prove CI/evaluator changes it to `blocked`, restore the original immutable artifact, and retain both results in `evidence/runs/<timestamp>-evidence-tamper-test/`.
- [ ] T152 [US6] Accept US6 only after 100% of Terraform stages have plan/quota/Infracost/cost-acceptance/backup/rollback evidence, every capability has success/failure proof, every stage's economical post-baseline passes, and the signed decision is recorded in `evidence/runs/<timestamp>-final/evidence.json`.

**Checkpoint**: A reviewer can reproduce why each stage advanced, stopped, or rolled back.

---

## Phase 9: Final Cross-Cutting Verification and Handoff

**Purpose**: Prove the integrated result, close documentation, and leave a clean protected-main lineage.

- [ ] T153 [P] Run every repository-owned source, contract, integration, E2E, performance, DAST, lint, build, and workflow-contract test from its checked-in command; retain actual output under `evidence/runs/<timestamp>-final/tests/` and fail on skipped mandatory gates.
- [ ] T154 [P] Run Terraform fmt/validate/test and refreshed drift plans for dev, demo-full, full-dev, full-prod, shared egress, and Azure DR; require zero unintended changes and report every intentional traffic-disabled state explicitly in `evidence/runs/<timestamp>-final/infrastructure/`.
- [ ] T155 [P] Render and kubeconform every GitOps root with the pinned toolchain; rerun ownership, profile, secret, service/platform digest and signature-identity, complete OCI-graph equality, capability, bootstrap, and no-imperative-mutation policies, retaining output in `evidence/runs/<timestamp>-final/desired/`.
- [ ] T156 Run read-only live acceptance across economical, three full EKS, and AKS destinations; verify ArgoCD revisions, Applications, workloads, ExternalSecret readiness and cross-cloud JWT behavior without reading values, identities, images, destination/common/Sonar TLS, the real blocking Sonar quality gate, EKS VPC-CNI and AKS Cilium NetworkPolicy enforcement, static AKS ingress binding, HTTP, Redis, telemetry, alerts, scaling, security, cost, and stability, retaining redacted output in `evidence/runs/<timestamp>-final/live/`.
- [ ] T157 Run secret/PII/state/kubeconfig/private-key scans over every participating repository and evidence directory after T153-T156 finish; remove only generated unsafe artifacts owned by this feature and document any external backup location without exposing it in `evidence/runs/<timestamp>-final/security/scan.txt`.
- [ ] T158 Update `../microservice-app-docs/full-platform/status.md`, `docs/profiles.md`, `clusters/README.md`, and `docs/bootstrap-boundary.md` with verified current state, exact trade-offs, data-continuity limits, traffic status, rollback, and operator commands in English.
- [ ] T159 Execute every command in `specs/009-full-platform-rollout/quickstart.md` that applies to the completed state, record literal output, and fix documentation or implementation until it is reproducible.
- [ ] T160 Audit the small cross-referenced PRs already merged in dependency order, verify every approval matched its reviewed head SHA and every merge used protected `main` without `--admin`, and record each merge SHA/rollback path in the final evidence bundle.
- [ ] T161 Re-run `speckit-analyze` after implementation convergence and resolve every CRITICAL/HIGH inconsistency before changing the specification status.
- [ ] T162 Change `specs/009-full-platform-rollout/spec.md` from `Draft` to `Complete` only if the final evidence matrix proves all acceptance criteria; otherwise leave it `Draft` and list exact blocked requirements in `../microservice-app-docs/full-platform/status.md`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: starts immediately; T003/T007 tests precede T004/T008.
- **Foundational (Phase 2)**: depends on Setup; T029's literal dev `0/0/0` result and T030 review block every user story.
- **US1 (Phase 3)**: depends on Foundational and establishes the baseline wrapper required by every later stage.
- **US2 (Phase 4)**: depends on US1. Static tests/roots may be prepared in parallel, but applies are ordered egress → full dev → full prod → staging prerequisites → dev-owner trust/platform mirror → GitOps roots/bootstrap.
- **US3 (Phase 5)**: depends on accepted US2 foundations/roots. Service code and platform manifests can be developed in parallel; live rollout is full dev → full staging → full prod.
- **US4 (Phase 6)**: depends on accepted US3 health/telemetry/admission contracts.
- **US5 (Phase 7)**: Azure foundation preparation may begin after Foundational, but DR promotion/game day depends on the production-validated US4 digest and accepted US3 platform. T140 always needs a separate human approval.
- **US6 (Phase 8)**: its validator foundation exists from Phase 1; final acceptance depends on every selected prior stage.
- **Final Verification (Phase 9)**: depends on all implemented story checkpoints; incomplete traffic approval is allowed only when truthfully reported as `traffic-disabled-ready`, not as active-active complete.

### User Story Dependencies

```text
Foundational
    └── US1 economical invariant
          └── US2 isolated AWS foundations
                └── US3 full platform
                      └── US4 immutable canary release
                            └── US5 AKS DR and game day

US6 evidence mechanics begin in Setup and evaluate every node above.
```

### Within Every Story

1. Write the named tests and observe the expected failure.
2. Implement only enough behavior to pass those tests.
3. Run static/local checks and review the exact diff.
4. Capture pre-stage economical baseline.
5. Produce desired-state/plan/quota/cost/rollback evidence.
6. Obtain required approval for the exact revision/plan.
7. Reconcile/apply only within the declared ownership boundary.
8. Capture live success and controlled failure evidence.
9. Exercise rollback and recapture the economical baseline.
10. Validate the evidence bundle before unlocking dependents.

## Parallel Opportunities

- T002, T003, T005, T006, T007, and T009 touch independent setup files.
- T011-T016 are independent test-first tasks.
- T020-T024 refactor separate service directories.
- T039-T044 test separate Terraform/GitOps/bootstrap contracts.
- T047 and T048 build separate roots after their shared module contract is stable.
- T054 and T055 are independent plans after egress outputs are available.
- T068-T076 add independent platform/service tests; T077-T081 implement separate repositories.
- T082, T084-T088 own different platform directories, but T091 controls their activation order.
- T105-T109 update separate service workflows.
- T118-T123 test separate Azure/GitOps/workflow/DNS/chaos contracts.
- T153-T155 verify separate concerns in parallel; T157 follows them so it scans every generated artifact.

## Implementation Strategy

### MVP: Preserve the working platform

Complete Phases 1-3 and stop. This delivers an enforceable economical safety boundary and validated planning machinery without creating full-profile resources.

### Incremental Delivery

1. Deliver US2 foundations with no workloads.
2. Prove one full-dev service and platform slice, then complete US3 full dev.
3. Promote the accepted slice to staging and production, still traffic-disabled.
4. Prove immutable canary promotion and rollback under US4.
5. Add independent AKS DR, mirror the complete signed platform graph and production service digest, and run the US5 game day.
6. Enable real active-active traffic only through T139-T140's separate approval.
7. Close US6 and final verification from actual evidence.

## Notes

- Commit after each task or small coherent group on a short-lived branch; do not mix unrelated repositories or stages in one PR.
- `[P]` never overrides a hard dependency, shared file conflict, cloud quota, or human gate.
- Terraform applies use only approved saved plans after a timestamped external state backup under `~/backups-microtodosuite/` (or a `no-prior-state` receipt for a genuinely new key). No task authorizes a convenience apply.
- The only direct managed-cluster mutations are the two bootstrap commands per new cluster. Test/chaos/audit resources are GitOps state.
- `GH_TOKEN` in workflow command environments is a short-lived GitHub App installation token, never a personal token.
- Do not mark a capability or story complete from rendered YAML, a clean exit code, or a summary alone; retain the actual desired/live/failure/rollback output.

# Acceptance Checklist: Shared-Cluster Namespace Isolation

**Purpose**: Record static and live evidence without converting manifest intent into a pass

**Created**: 2026-08-09

**Feature**: [spec.md](../spec.md)

## Authoritative Prerequisites

- [x] The implementation baseline records all eight repository worktrees and current remote trunks — Evidence: fresh `git fetch origin main` plus `git status --short --branch`/`git rev-parse` on 2026-08-11 produced the following exact inventory; every repository except the GitOps specification worktree was clean, and no existing change was discarded.

  | Repository | Local branch / HEAD | `origin/main` | Worktree |
  | --- | --- | --- | --- |
  | `microservice-app-ops` | `esteban/eks-dev-foundation` / `c5ecbda8656a72759111b8f6d6a4e6b531cb8df2` | `53bcf8482f79760befbe2075d8700dd895acdd55` | clean |
  | organization `.github` | `main` / `c98763e311cdfb5edc18dcb2455e75e001406145` | `c98763e311cdfb5edc18dcb2455e75e001406145` | clean |
  | `microservice-app-auth-api` | `main` / `e86dc1eb061925bc7d146154e52c5838c98f91ae` | same | clean |
  | `microservice-app-todos-api` | `main` / `e33b0ca8e1b9795197496958a35a33eb7bbceba3` | same | clean |
  | `microservice-app-users-api` | `main` / `56a1bcbb11bf7f53d929d691ff40287c8aa9fd07` | same | clean |
  | `microservice-app-frontend` | `main` / `c43ed0b9363be662d025533a67cbdde6fc3c6f89` | same | clean |
  | `microservice-app-log-message-processor` | `main` / `09f6256f1b4b2e909ace15674c6d3286aa5e32f5` | same | clean |
  | `microservice-app-gitops` | `esteban/namespace-foundation-evidence` / `f89675d86f493fae227ac703bca88592266d9bac` | `a06852d7960ef6a194f41f48d4ecbc860e182be3` | intentionally dirty with the in-progress feature 005 specification artifacts |
- [x] The five selected source baselines have exact failing workflow evidence — Evidence: public GitHub Actions metadata read on 2026-08-11 reports `completed/failure` for auth-api [run 31348454385](https://github.com/MicroTodoSuite/microservice-app-auth-api/actions/runs/31348454385), todos-api [run 31348457188](https://github.com/MicroTodoSuite/microservice-app-todos-api/actions/runs/31348457188), users-api [run 31348459707](https://github.com/MicroTodoSuite/microservice-app-users-api/actions/runs/31348459707), frontend [run 31348462148](https://github.com/MicroTodoSuite/microservice-app-frontend/actions/runs/31348462148), and log-message-processor [run 31348466593](https://github.com/MicroTodoSuite/microservice-app-log-message-processor/actions/runs/31348466593), each tied to the full baseline SHA above.
- [x] The pre-implementation live cluster, AWS caller, Argo CD inventory, and capacity are recorded without mutation — Evidence: read-only commands on 2026-08-11 selected context and cluster ID `arn:aws:eks:us-east-1:995253610162:cluster/microtodosuite-dev`; STS returned `arn:aws:sts::995253610162:assumed-role/microtodosuite-terraform-dev/botocore-session-1786486375`; both nodes were Ready with aggregate allocatable `3860m` CPU, `14549840Ki` memory, and 58 pods; current non-business Pods requested `1301m` CPU and `913408Ki` memory. The live inventory contained exactly root, self-managed Argo CD, three environment Applications, and five infrastructure Applications, all `Synced/Healthy` at `a06852d7960ef6a194f41f48d4ecbc860e182be3`, with zero business Applications.
- [x] The machine-valid baseline observer was executed against the exact shared EKS context — Evidence: `.local/evidence/namespace-isolation/20260811T224110Z-baseline-a06852d/summary.json` validates against evidence schema v2.0.0 and records phase `baseline`, expected revision `a06852d7960ef6a194f41f48d4ecbc860e182be3`, three `Synced/Healthy` environment Applications, three Ready/PONG environment Redis instances, zero business Applications, 46 audited commands, zero managed-state mutations, and zero Secret-value retrievals. Its truthful result is `BLOCKED`, with unreconciled release prerequisites and deferred AWS principal mappings named explicitly.
- [x] Constitution v2.0.0 is merged to `microservice-app-docs/main` — Evidence: PR [MicroTodoSuite/microservice-app-docs#2](https://github.com/MicroTodoSuite/microservice-app-docs/pull/2) merged on 2026-08-12 as `2c8624debc8231044425a818d6e1eef718d3c4d5`; the authoritative file declares version 2.0.0 and ratification date 2026-08-11.
- [x] `.specify/memory/constitution.md` is byte-identical to the authoritative file — Evidence: refreshed from `microservice-app-docs` merge `2c8624debc8231044425a818d6e1eef718d3c4d5` on 2026-08-16; `cmp` passed and both files had SHA-256 `4a09570871a73b72299ef65941910feab7f6dfd30297e98f8d4be054984fcb16`.
- [x] The AWS EKS foundation source is merged to `microservice-app-ops/main` — Evidence: PR [MicroTodoSuite/microservice-app-ops#14](https://github.com/MicroTodoSuite/microservice-app-ops/pull/14) merged on 2026-08-12 as `c1e0c539cb4e4649be31a64090d506ce9c9393c9`; its credential-free AWS validation run `31545921079` passed formatting, validation, six Terraform tests, and the shell contract.
- [x] The namespace-foundation evidence prerequisite is merged to `microservice-app-gitops/main` — Evidence: PR [MicroTodoSuite/microservice-app-gitops#7](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/7) was approved by `Tiago0507`, passed `render-and-validate`, and merged normally on 2026-08-16 as `1aeb5c73848fb3320e997a6930128af368905789`.
- [x] The existing `microtodosuite-dev` cluster and `clusters/eks-dev` root are reviewed as the shared-cluster target without replacement — Evidence: PR #6 encoded the operator decision, passed `validate-gitops`, was approved by `Tiago0507` at head `178725603e3bd294c552c7fb9d4067e6f30c4ed3`, and merged normally as `a06852d7960ef6a194f41f48d4ecbc860e182be3` on 2026-08-10; neither the EKS identity nor ArgoCD root path changed.
- [x] The shared `clusters/eks-dev` registration is reconciled and activates exactly dev, staging, and prod environment-policy entries — Evidence: `.local/evidence/namespace-isolation/20260810T042953Z-foundation-observation-a06852d/raw/applications.json` records exactly `env-dev`, `env-staging`, and `env-prod`, each `Synced/Healthy` at merge SHA `a06852d7960ef6a194f41f48d4ecbc860e182be3`; the same artifact contains zero business Applications.
- [x] Shared-cluster foundation registration yields zero business-service Applications and explicitly allowlists exactly four retained controller Applications plus `infra-redis` — Evidence: on 2026-08-09 the live Application inventory at `10d59e50591e66fa8e54f21814a1be29da6d7979` contained zero business Applications and exactly `infra-keda`, `infra-cert-manager`, `infra-external-secrets`, `infra-kyverno`, and `infra-redis`, all `Synced/Healthy`; PR #5 replaced folder discovery with the exact registration list.
- [x] VPC CNI network policy is enabled declaratively and proven on every eligible node — Evidence: on 2026-08-09 AWS `DescribeAddon` reported VPC CNI `v1.23.0-eksbuild.1` `ACTIVE` with `configurationValues.enableNetworkPolicy=true`; the `aws-node` DaemonSet reported desired/current/ready/available/updated `2/2/2/2/2`, and both eligible Linux nodes had Ready `aws-node` and `aws-eks-nodeagent` containers with zero restarts and enforcing mode `standard`.
- [x] The Terraform execution-role gap and least-privilege bootstrap remediation are documented — Evidence: `microservice-app-ops/aws/environments/dev/backend/namespace-isolation-terraform-execution-policy.json` scopes current-role refresh, five exact feature roles, and the exact GitHub OIDC provider; `jq empty` and `aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY` returned zero findings on 2026-08-16.
- [ ] The intended Terraform role completes a refresh-backed plan — Blocking evidence: `AWS_PROFILE=microtodosuite-terraform ./scripts/aws-dev-foundation.sh check` passed on 2026-08-16 as `arn:aws:sts::995253610162:assumed-role/microtodosuite-terraform-dev/*`, but the refresh-backed plan failed on missing `iam:ListRolePolicies` for `vpc-flow-log-role-5126a5ce9bc1bf72408e5cb1b7`; `iam:ListOpenIDConnectProviders` is also denied. The local `esteban-personal` user has only `IAMUserChangePassword`, so an account IAM administrator must attach the reviewed bootstrap policy before T009 can pass.
- [ ] AWS principal-to-group mappings are approved and observed for all three environment groups — Deferred evidence: live EKS access entries contain no `microtodosuite:*maintainers` group. The operator deferred mapping; the supplied Terraform role is intentionally not mapped to all three because that would erase the access boundary.
- [ ] Existing dev workloads, dependencies, resources, and health are recorded in a passing baseline — Unavailable evidence: the read-only observer at `.local/evidence/namespace-isolation/20260810T042953Z-foundation-observation-a06852d/summary.json` exited 8 with `no existing dev business workload is available for continuity baseline`. The live inventory has zero business Applications; platform and Redis continuity do not manufacture the missing business baseline.

## Static Desired-State Evidence

- [x] Dev, staging, and prod render successfully from the same managed base — Evidence: `tests/contract/namespace-isolation.sh` rendered all three from `environments/base` and passed on 2026-08-09; checksum-verified kubeconform v0.7.0 reported 12/11/11 valid resources and zero invalid/errors for the Stage-1 dev/staging/prod renders.
- [x] All three namespace names and labels match the fixed mapping — Evidence: the static contract asserted `microtodo-dev|staging|prod` and `microtodosuite.io/environment: dev|staging|prod` against the three namespace manifests and renders.
- [x] All three ResourceQuotas include CPU/memory requests/limits and pod count — Evidence: the passing static contract asserted dev `400m/1200m/512Mi/1536Mi/12`, staging `500m/1500m/640Mi/2Gi/14`, and prod `650m/2/896Mi/3Gi/18` in `environments/*/resourcequota.yaml`.
- [x] Quota values have a reviewed capacity and rollout-headroom rationale — Evidence: `docs/namespace-isolation.md` and `research.md` record the observed 3860m CPU/14,549,840Ki memory envelope, 1226m/796Mi platform requests, three Redis instances, fixture headroom, disruption reserve, and 1550m/2048Mi aggregate environment request ceilings; no business capacity is activated.
- [x] All three renders include bounded LimitRange defaults and maxima — Evidence: the passing contract asserted 25m/32Mi default requests, 250m/256Mi defaults, and 500m/512Mi maxima from `environments/base/limitrange.yaml` in each render.
- [x] The Stage-1 renders include DNS and same-namespace policy while excluding default deny, and the prepared Stage-2 policy declares ingress-and-egress deny — Evidence: the passing contract rejects `default-deny` from all three active foundation renders, retains the exact allow policies, and validates the separate `networkpolicy-default-deny.yaml` manifest for both policy directions.
- [x] Every additional allowance has exact source, destination, protocol, port, and owner evidence — Evidence: `networkpolicy-allow-dns.yaml`, `networkpolicy-allow-intra-namespace.yaml`, `networkpolicy-allow-redis.yaml`, and dev's `networkpolicy-allow-required-egress.yaml` contain only their documented pod/namespace selectors and TCP/UDP 53 or TCP 6379; the contract rejects environment selectors, IP blocks, and `0.0.0.0/0`.
- [x] All three RoleBindings use only their exact stable maintainer group — Evidence: the passing contract found exactly three distinct Group subjects, `microtodosuite:dev-maintainers`, `:staging-maintainers`, and `:prod-maintainers`, each in its corresponding overlay.
- [x] The custom Role excludes isolation controls, Secrets, and cluster-scoped resources — Evidence: `environments/base/role.yaml` has exactly three reviewed rules for Deployments, ConfigMaps/Services, and read-only Pods/logs; the passing contract rejects forbidden resources and any ClusterRole/ClusterRoleBinding.
- [x] Wildcard subjects/verbs/resources, `system:authenticated`, personal IAM ARNs, and broad cross-environment allowances are absent — Evidence: `tests/contract/namespace-isolation.sh` scans the base and all bindings/policies for these constructs and passed.
- [x] Verification images are selected by immutable digest — Evidence: every rendered feature fixture passed the all-images `@sha256:` assertion and kubeconform validation; the selected Redis 7.4.9 Alpine digest is `sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99`.
- [x] Each managed render contains exactly one digest-pinned Redis Deployment and Service in its own namespace — Evidence: the passing contract counted one Deployment and one Service named `redis` per environment render and rejected a mutable image.
- [x] Managed todos-api and log-message-processor overlays use namespace-local Redis while local overlays retain the local pilot endpoint — Evidence: the passing contract rendered all eight relevant paths, found `REDIS_HOST: redis` in dev/staging/prod and `redis.redis.svc.cluster.local` in local.
- [x] Shared-cluster infrastructure activation renders the exact five-entry foundation allowlist and the exact four-controller post-retirement allowlist — Evidence: the contract passed against `clusters/eks-dev/activation-infrastructure.yaml` and `activation-infrastructure-retired.yaml`; `clusters/base/infrastructure.yaml` rejects folder discovery, while local retains its five entries.
- [x] No managed business service or verification fixture is activated by this implementation — Evidence: the passing contract asserts `clusters/eks-dev/activation-apps.yaml` remains empty, the environment list contains only `dev|staging|prod`, and no steady-state environment references a verification fixture.
- [x] `environments/local` is unchanged and existing contract tests pass — Evidence: the feature contract's `git diff --quiet HEAD -- environments/local` assertion passed, as did `platform-addons.sh` and `service-onboarding.sh` on 2026-08-09.
- [x] All renders pass the implementation's pinned schema validator — Evidence: checksum-verified kubeconform v0.7.0 ran through `scripts/managed/validate-namespace-isolation.sh` against Kubernetes 1.35.0; every rendered core resource reported zero invalid and zero errors, with unprovided CRD schemas explicitly skipped.
- [x] Evidence JSON Schema and observer contracts are valid — Evidence: on 2026-08-11 `tests/contract/namespace-isolation-evidence.sh` returned `PASS: namespace-isolation evidence schema, redaction, and observer contracts`. It validates the v2.0.0 baseline fixture, requires the intentionally invalid secret-output fixture to fail, composes and schema-validates a blocked baseline, rejects unsigned release evidence, detects managed-state mutations and direct Secret retrieval, and preserves network/Redis/resource helper coverage. `bash -n` also passed for the verifier, shared library, and contract.

## Staged Live Evidence

- [x] Foundation revision converges in all three environment Applications before default deny — Evidence: `raw/applications.json` in the `20260810T042953Z-foundation-observation-a06852d` evidence run records all three `env-*` Applications `Synced/Healthy` at `a06852d7960ef6a194f41f48d4ecbc860e182be3`; the three namespace/resource artifacts record Active namespaces, exact quotas and LimitRanges, and zero `default-deny` policies.
- [ ] Dev loses zero ready replicas and adds zero attributable restarts after foundation convergence — Unavailable evidence: no dev business Deployment existed before or after the foundation; the observer retained this as a failed continuity gate rather than treating an empty set as success.
- [ ] Required dev connections and health checks pass after foundation convergence — Partial evidence: each environment Redis is healthy, but there is no active dev business service or owner-provided endpoint/connection baseline to test.
- [ ] Default-deny revision converges at the exact reviewed SHA
- [ ] Dev loses zero ready replicas and adds zero attributable restarts after default deny
- [ ] Six unique directed cross-environment TCP attempts are denied
- [ ] Three same-environment TCP attempts are allowed
- [ ] DNS succeeds in dev, staging, and prod
- [x] Redis is Ready and returns `PONG` in dev, staging, and prod — Evidence: the same evidence directory records `PONG` in `raw/dev-redis-ping.txt`, `raw/staging-redis-ping.txt`, and `raw/prod-redis-ping.txt`; live Deployments were `1/1` available and all three pods were Ready with zero restarts using the reviewed digest.
- [ ] Six unique directed cross-environment Redis attempts are denied
- [ ] A unique Redis Pub/Sub event is observed only in its source environment
- [ ] Shared `infra-redis` and namespace `redis` are removed while all four retained controllers remain healthy
- [ ] Deliberate over-budget Deployment cannot realize its excess pod and records the expected event
- [ ] Comparison-environment workload remains ready, restart-stable, and healthy during the violation
- [ ] RBAC matrix contains exactly three own-environment workload allows and six cross-environment denies
- [ ] All maintainer groups are denied isolation-control changes
- [ ] Unbound subject is denied in every managed namespace
- [ ] ArgoCD platform principal retains its required reconciliation capability

## Cleanup and Final Evidence

- [ ] Fixture activation is removed by reviewed Git revert
- [ ] All three environment Applications are Synced/Healthy at the cleanup revision
- [ ] No verification fixture remains in any managed namespace
- [ ] Dev remains ready, restart-stable, connected, and healthy for ten minutes after cleanup
- [ ] `summary.json` validates against the evidence schema — Static-only evidence: the cumulative evidence contract validates a synthetic complete shape; no live fixture/cleanup summary exists.
- [ ] Raw observations support every summarized result
- [ ] Command audit contains zero direct managed-state mutations — Partial evidence: the exact-revision foundation observation recorded 33 commands and zero entries with `mutating=true`; `summary.json` reports `commandAudit.mutatingCommands: 0` and `PASS`, but the final six-phase audit does not exist yet.
- [ ] Final result is `PASS` only after every item above is evidenced

## Current Status

**STAGE-1 FOUNDATION LIVE; LATER STAGES NOT AUTHORIZED BY CURRENT EVIDENCE.** PR
#6 reconciled the three Active namespaces, exact budgets and limits, scoped RBAC
objects, allow policies, and three healthy Redis instances through ArgoCD at
`a06852d7960ef6a194f41f48d4ecbc860e182be3`. Business applications and fixtures
remain inactive, all five platform Applications remain healthy, and the command
audit contains zero mutations. The observer correctly remains `FAIL` because no
pre-existing dev business workload can satisfy the continuity baseline. IAM
group mappings are also deferred. Default deny, shared-Redis retirement,
fixtures, live network/resource/RBAC tests, and final acceptance remain open.

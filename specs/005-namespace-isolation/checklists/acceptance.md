# Acceptance Checklist: Shared-Cluster Namespace Isolation

**Purpose**: Record static and live evidence without converting manifest intent into a pass

**Created**: 2026-08-09

**Feature**: [spec.md](../spec.md)

## Authoritative Prerequisites

- [x] Constitution v1.2.0 is merged to `microservice-app-docs/main` — Evidence: remote and local `main` both resolved to `615241ddf0280279d24c8df5faf5295bfed70ce0` on 2026-08-09.
- [x] `.specify/memory/constitution.md` is byte-identical to the authoritative file — Evidence: `cmp` passed and both files had SHA-256 `14545ede9ee8d39b340b955e454c4500d3cdb30b108d74b3c1180534b6dbf3a4`.
- [ ] The shared-cluster ops handoff supersedes the former dedicated-dev/full-profile contract — Blocking evidence: AWS reports only `microtodosuite-dev`, tagged `Environment=dev`; ops remains on `esteban/eks-dev-foundation` at `c38c853`.
- [ ] `clusters/eks-main` is reviewed, reconciled, and activates exactly the dev, staging, and prod environment-policy entries — Blocking evidence: identity-bound read-only observer run `.local/evidence/namespace-isolation/20260810T022337Z-identity-bound-prerequisite` exited 4 at revision `24c5c1a9f7b8c870dd0f5b1a11ce89326157c713`; `raw/applications.json` contains zero `env-*` Applications and the live root still targets `clusters/eks-dev`.
- [ ] Shared-cluster foundation registration yields zero business-service Applications and explicitly allowlists exactly four retained controller Applications plus `infra-redis` — Partial evidence: the same observer run records zero business Applications and the five expected healthy `infra-*` Applications, but live revision `24c5c1a...` obtains them through unreviewed folder discovery rather than reviewed `eks-main` values.
- [ ] VPC CNI network policy is enabled declaratively and proven on every eligible node — Partial evidence: `.local/evidence/namespace-isolation/20260810T022337Z-identity-bound-prerequisite/raw/aws-node-pods.json` records two of two Ready `aws-eks-nodeagent` containers and `aws-node-daemonset.json` records desired/ready/available `2/2/2`; Terraform and `DescribeAddon` contain no `enableNetworkPolicy=true`, and real connection enforcement is not yet tested.
- [ ] AWS principal-to-group mappings are approved and observed for all three environment groups — Blocking evidence: live EKS access entries contain no `microtodosuite:*maintainers` group.
- [ ] Existing dev workloads, dependencies, resources, and health are recorded in a passing baseline — Blocking evidence: observer summary `.local/evidence/namespace-isolation/20260810T022337Z-identity-bound-prerequisite/summary.json` is `FAIL`, binds the dedicated-dev cluster ARN, has an empty `devSnapshot`, and its three namespace GET artifacts record `NotFound` for `microtodo-dev|staging|prod`.

## Static Desired-State Evidence

- [x] Dev, staging, and prod render successfully from the same managed base — Evidence: `tests/contract/namespace-isolation.sh` rendered all three from `environments/base` and passed on 2026-08-09; kubeconform reported 13/12/12 valid resources and zero invalid/errors for dev/staging/prod.
- [x] All three namespace names and labels match the fixed mapping — Evidence: the static contract asserted `microtodo-dev|staging|prod` and `microtodosuite.io/environment: dev|staging|prod` against the three namespace manifests and renders.
- [x] All three ResourceQuotas include CPU/memory requests/limits and pod count — Evidence: the passing static contract asserted dev `400m/1200m/512Mi/1536Mi/12`, staging `500m/1500m/640Mi/2Gi/14`, and prod `650m/2/896Mi/3Gi/18` in `environments/*/resourcequota.yaml`.
- [x] Quota values have a reviewed capacity and rollout-headroom rationale — Evidence: `docs/namespace-isolation.md` and `research.md` record the observed 3860m CPU/14,549,840Ki memory envelope, 1226m/796Mi platform requests, three Redis instances, fixture headroom, disruption reserve, and 1550m/2048Mi aggregate environment request ceilings; no business capacity is activated.
- [x] All three renders include bounded LimitRange defaults and maxima — Evidence: the passing contract asserted 25m/32Mi default requests, 250m/256Mi defaults, and 500m/512Mi maxima from `environments/base/limitrange.yaml` in each render.
- [x] All three renders include ingress-and-egress default deny, DNS, and same-namespace policy — Evidence: the passing contract found one `default-deny` plus `allow-dns` and `allow-intra-namespace` in every steady-state render; foundation fixtures separately prove deny is absent before Stage 2.
- [x] Every additional allowance has exact source, destination, protocol, port, and owner evidence — Evidence: `networkpolicy-allow-dns.yaml`, `networkpolicy-allow-intra-namespace.yaml`, `networkpolicy-allow-redis.yaml`, and dev's `networkpolicy-allow-required-egress.yaml` contain only their documented pod/namespace selectors and TCP/UDP 53 or TCP 6379; the contract rejects environment selectors, IP blocks, and `0.0.0.0/0`.
- [x] All three RoleBindings use only their exact stable maintainer group — Evidence: the passing contract found exactly three distinct Group subjects, `microtodosuite:dev-maintainers`, `:staging-maintainers`, and `:prod-maintainers`, each in its corresponding overlay.
- [x] The custom Role excludes isolation controls, Secrets, and cluster-scoped resources — Evidence: `environments/base/role.yaml` has exactly three reviewed rules for Deployments, ConfigMaps/Services, and read-only Pods/logs; the passing contract rejects forbidden resources and any ClusterRole/ClusterRoleBinding.
- [x] Wildcard subjects/verbs/resources, `system:authenticated`, personal IAM ARNs, and broad cross-environment allowances are absent — Evidence: `tests/contract/namespace-isolation.sh` scans the base and all bindings/policies for these constructs and passed.
- [x] Verification images are selected by immutable digest — Evidence: every rendered feature fixture passed the all-images `@sha256:` assertion and kubeconform validation; the selected Redis 7.4.9 Alpine digest is `sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99`.
- [x] Each managed render contains exactly one digest-pinned Redis Deployment and Service in its own namespace — Evidence: the passing contract counted one Deployment and one Service named `redis` per environment render and rejected a mutable image.
- [x] Managed todos-api and log-message-processor overlays use namespace-local Redis while local overlays retain the local pilot endpoint — Evidence: the passing contract rendered all eight relevant paths, found `REDIS_HOST: redis` in dev/staging/prod and `redis.redis.svc.cluster.local` in local.
- [x] Shared-cluster infrastructure activation renders the exact five-entry foundation allowlist and the exact four-controller post-retirement allowlist — Evidence: the contract passed against `clusters/eks-dev/activation-infrastructure.yaml` and `activation-infrastructure-retired.yaml`; `clusters/base/infrastructure.yaml` rejects folder discovery, while local retains its five entries.
- [x] No managed business service or verification fixture is activated by this implementation — Evidence: the passing contract asserts `clusters/eks-dev/activation-apps.yaml` and `activation-environments.yaml` remain empty and rejects fixture references from every steady-state managed environment; no application activation file was changed.
- [x] `environments/local` is unchanged and existing contract tests pass — Evidence: the feature contract's `git diff --quiet HEAD -- environments/local` assertion passed, as did `platform-addons.sh` and `service-onboarding.sh` on 2026-08-09.
- [x] All renders pass the implementation's pinned schema validator — Evidence: checksum-verified kubeconform v0.7.0 ran through `scripts/managed/validate-namespace-isolation.sh` against Kubernetes 1.35.0; every rendered core resource reported zero invalid and zero errors, with unprovided CRD schemas explicitly skipped.
- [x] Evidence JSON Schema is valid — Evidence: Python jsonschema 4.26.0 `Draft202012Validator.check_schema` passed after `jq empty`; `tests/contract/namespace-isolation-evidence.sh` also composed a complete six-phase result and validated it with a FormatChecker against schema v1.1.0.

## Staged Live Evidence

- [ ] Foundation revision converges in all three environment Applications before default deny
- [ ] Dev loses zero ready replicas and adds zero attributable restarts after foundation convergence
- [ ] Required dev connections and health checks pass after foundation convergence
- [ ] Default-deny revision converges at the exact reviewed SHA
- [ ] Dev loses zero ready replicas and adds zero attributable restarts after default deny
- [ ] Six unique directed cross-environment TCP attempts are denied
- [ ] Three same-environment TCP attempts are allowed
- [ ] DNS succeeds in dev, staging, and prod
- [ ] Redis is Ready and returns `PONG` in dev, staging, and prod
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
- [ ] Command audit contains zero direct managed-state mutations — Partial evidence: the identity-bound prerequisite run recorded 33 read-only commands and `mutatingCommands: 0`; the final six-phase audit does not exist yet.
- [ ] Final result is `PASS` only after every item above is evidenced

## Current Status

**STATIC DESIRED STATE VALIDATED; LIVE ACTIVATION BLOCKED.** The constitution and
static implementation gates are evidenced. The read-only live observer failed
closed at the absent environment-Application inventory without mutation. The
shared-cluster handoff, policy-only registration, durable CNI configuration,
environment identity mappings, and dev continuity subject remain unsatisfied;
repository inference does not satisfy those live gates. Final traceability covers
all 33 functional requirements and 10 success criteria through 48 unique tasks:
30 static/implementation tasks are evidenced and 18 external/live tasks remain
open.

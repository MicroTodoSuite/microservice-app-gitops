# Research: Shared-Cluster Isolation and Managed-Environment Publication

**Date**: 2026-08-10
**Feature**: `005-namespace-isolation`

This research combines repository inspection, live read-only EKS/AWS/GitHub
evidence, and primary product documentation. It records the decisions required
to move from the already-reconciled namespace foundations to one verified
release of the five business services in dev, staging, and production.

## Live baseline

- The only EKS cluster is the existing `microtodosuite-dev` cluster, adopted as
  the shared cluster without physical rename. It runs Kubernetes 1.35 on two
  Linux nodes with combined allocatable capacity of `3860m` CPU,
  `14549840Ki` memory, and 58 pods.
- Existing platform and Redis pods request `1301m` CPU and approximately
  `892Mi` memory before business-service activation.
- `env-dev`, `env-staging`, and `env-prod` are Synced/Healthy. Each namespace has
  one Ready Redis pod and active default-deny policy. There are zero business
  Applications, zero managed ExternalSecrets, and zero Argo Rollouts CRDs.
- Amazon VPC CNI `v1.23.0-eksbuild.1` is active with network-policy enforcement
  enabled. That static prerequisite does not replace the required live traffic
  tests.
- Argo CD 3.5.0 exposes RollingSync in its ApplicationSet CRD, but
  `applicationsetcontroller.enable.progressive.syncs` is absent, so the live
  controller currently behaves as `AllAtOnce`.
- AWS has only the five empty `microtodosuite/dev/<service>` repositories. No
  neutral repository, JWT source secret, GitHub OIDC publisher, environment JWT
  reader role, or Kyverno ECR-verifier role exists.
- The Terraform configuration that owns the live AWS foundation is on the
  unmerged `microservice-app-ops` branch `esteban/eks-dev-foundation` at
  `c5ecbda`; remote `main` does not yet contain it.
- The intended Terraform role cannot currently plan the live foundation because
  its IAM policy lacks required read and narrowly scoped IAM lifecycle actions.
  The broader developer user can technically act, but is not an acceptable
  substitute for the reviewed Terraform execution path.
- All five recorded source baselines have failing CI. Four failed because a
  mutable shared-workflow tag resolved before the private-GHCR authentication
  repair; auth-api authenticated and then failed Trivy with 33 HIGH and two
  CRITICAL findings. No baseline is releasable.

## Decision 1: Preserve the existing GitOps and shared-cluster identities

**Decision**: Keep the physical cluster name `microtodosuite-dev`, the
`clusters/eks-dev` registration path, and the root Application unchanged. Every
Kubernetes change after bootstrap remains a Git commit reconciled by Argo CD.

**Rationale**: Renaming EKS means replacement, and renaming the live root path is
a separate migration with its own failure modes. Neither is necessary for
namespace isolation or application publication.

**Rejected**: Direct `kubectl apply`, Argo CD UI sync as a deployment path,
cluster replacement, or a second managed-cluster registration.

## Decision 2: Enable and scope ApplicationSet RollingSync declaratively

**Decision**:

1. Patch the self-managed Argo CD `argocd-cmd-params-cm` with
   `applicationsetcontroller.enable.progressive.syncs: "true"`.
2. Change a pod-template checksum annotation on the ApplicationSet controller so
   the ConfigMap-backed environment variable is actually reloaded.
3. Add an environment label to generated business Applications.
4. Add the RollingSync strategy only in the EKS registration, not the reusable
   base, with ordered `dev`, `staging`, and `prod` steps and `maxUpdate: 1` for
   each step.
5. Remove generated-Application automated sync for this registration. RollingSync
   initiates each sync and waits for every Application in the preceding group to
   become Healthy.

**Rationale**: The local-kind registration also consumes `clusters/base`; an
unconditional dev/staging/prod strategy would leave its `local` Application
unmatched. Serializing each five-Application group bounds surge and makes the
observed order unambiguous.

**Rejected**: Three separate activation commits, `AllAtOnce`, relying only on
sync-wave annotations, or a global strategy that breaks local-kind.

**Primary source**: [Argo CD 3.5 Progressive Syncs](https://argo-cd.readthedocs.io/en/release-3.5/operator-manual/applicationset/Progressive-Syncs/)

## Decision 3: Vendor Argo Rollouts 1.9.1 as an explicit add-on

**Decision**: Vendor the official Argo Rollouts v1.9.1 install manifest and
checksum under `infrastructure/argo-rollouts`, pin the controller image by
digest, and register `infra-argo-rollouts` explicitly after retiring shared
Redis. The final infrastructure inventory is KEDA, cert-manager, External
Secrets, Kyverno, and Argo Rollouts.

**Rationale**: Production release controls cannot reference absent CRDs or an
unmanaged controller. The repository already uses vendored, checksummed add-ons
and an exact infrastructure allowlist.

**Rejected**: A remote install URL, Helm at reconciliation time, folding the
controller into another add-on, or leaving the inactive auth-only seam in place.

**Primary sources**:

- [Argo Rollouts installation](https://argo-rollouts.readthedocs.io/en/stable/installation/)
- [Argo Rollouts v1.9.1 release](https://github.com/argoproj/argo-rollouts/releases/tag/v1.9.1)

## Decision 4: Use replica canaries with a deterministic canary health metric

**Decision**: Each production overlay opts into a service-specific Rollout
component that:

- reuses the base Deployment pod template with `workloadRef`;
- declares the existing production replica count on the Rollout and sets the
  referenced Deployment to zero during migration;
- uses `maxSurge: 1`, `maxUnavailable: 0`, and a 50-percent replica step;
- creates a dedicated `<service>-canary` Service selected by the Rollout;
- runs an inline AnalysisRun against that canary Service; and
- automatically aborts and restores the stable ReplicaSet when analysis fails.

A shared ClusterAnalysisTemplate uses the official Kubernetes Job metric
provider. Its digest-pinned curl container performs repeated failing-on-non-2xx
requests to the service-specific probe endpoint, has bounded resources, no
service-account token, and the probes required by the live Kyverno policy.

The five target paths are `/version:8000`, `/metrics:8082`,
`/prometheus:8083`, `/:8080`, and `/metrics:9090`.

**Rationale**: With one desired replica for three services, weights below 50
percent cannot create a live canary. A dedicated canary Service ensures the
metric reaches the new ReplicaSet rather than an arbitrary stable pod. A Job's
exit status is an Argo Rollouts metric and needs no absent Prometheus backend.

**Limit**: This is an availability metric, not an HTTP error-rate metric. The
feature must not claim request-rate observability that the cluster does not
have.

**Rejected**: Istio routing, the inactive auth-only Prometheus template,
unmeasured timed pauses, or concurrent production canaries.

**Primary sources**:

- [Replica-based canary](https://argo-rollouts.readthedocs.io/en/stable/features/canary/)
- [Analysis and automatic abort](https://argo-rollouts.readthedocs.io/en/stable/features/analysis/)
- [Job metric provider](https://argo-rollouts.readthedocs.io/en/stable/analysis/job/)

## Decision 5: Separate initial stable creation from canary acceptance

**Decision**: The one activation revision declares all fifteen Applications and
establishes the initial production stable ReplicaSets. Production is not
accepted yet. A later reviewed, same-digest GitOps revision changes only a
production pod-template evidence annotation so all five Rollouts execute their
canary steps and metrics. A second reviewed negative-gate fixture makes one
analysis target fail, proving `Failed -> Aborted -> stable restored`; its
recovery is a Git revert.

**Rationale**: Argo Rollouts intentionally skips canary steps on first creation
because there is no stable ReplicaSet. Pretending the initial creation ran a
canary would be false evidence.

**Rejected**: Seeding production before the declared activation, marking the
first creation as a canary, changing image digests only to force a test, or
imperatively restarting a Rollout.

**Primary source**: [Argo Rollouts getting started](https://argo-rollouts.readthedocs.io/en/stable/getting-started/)

## Decision 6: Resize quotas from checked-in replica arithmetic and live capacity

**Decision**: Keep all existing container requests/limits and use RollingSync
`maxUpdate: 1`. The exact steady-state totals, including Redis, are:

| Environment | Requests CPU | Limits CPU | Requests memory | Limits memory | Pods |
| --- | ---: | ---: | ---: | ---: | ---: |
| dev | 350m | 1600m | 512Mi | 1536Mi | 6 |
| staging | 425m | 1950m | 608Mi | 1920Mi | 8 |
| prod | 475m | 2200m | 672Mi | 2176Mi | 9 |

The largest serialized surge is one users-api pod (`150m/500m`,
`256Mi/512Mi`). Production also needs one analysis pod
(`10m/50m`, `16Mi/32Mi`). The approved quota targets are:

| Environment | Requests CPU | Limits CPU | Requests memory | Limits memory | Pods |
| --- | ---: | ---: | ---: | ---: | ---: |
| dev | 550m | 2300m | 896Mi | 2304Mi | 12 |
| staging | 625m | 2700m | 1Gi | 2816Mi | 14 |
| prod | 700m | 3 | 1152Mi | 3Gi | 18 |

The request ceilings total `1875m`; combined with the live platform request of
`1301m`, they leave `684m` allocatable CPU uncommitted. Expected steady state
leaves `1309m`. These are namespace ceilings, not reservations. The current
two-node cluster cannot promise full rescheduling after losing an entire node,
so the evidence must state that limitation rather than claim node-failure
capacity.

**Rationale**: Current CPU-limit quotas already reject the intended steady state
in every environment. The new values admit the largest serialized rollout and
test jobs without permitting every environment to consume the cluster.

**Rejected**: Keeping the failing quotas, adding all possible concurrent surges,
or representing ResourceQuota as reserved capacity.

## Decision 7: Keep managed secrets environment-local with ESO and IRSA

**Decision**: Extend the existing AWS foundation state with three protected
Secrets Manager entries and three exact-subject IRSA roles. Generate each JWT
independently with the AWS provider's ephemeral Secrets Manager random-password
resource and write it through `secret_string_wo`; neither plan nor state stores
the value. Each environment renders:

- ServiceAccount `external-secrets-jwt` annotated with only its role ARN;
- namespaced SecretStore `aws-secrets-manager` using JWT service-account auth;
- ExternalSecret `auth-api-secrets` materializing only `JWT_SECRET`.

Each IAM policy permits only `GetSecretValue` and `DescribeSecret` on one exact
secret ARN.

**Rationale**: A controller-wide role or shared source secret would allow one
environment's signing identity to escape its namespace boundary.

**Rejected**: Static AWS keys, Git values, ClusterSecretStore, shared JWT,
ordinary Terraform secret arguments, or the same IAM role in all namespaces.

**Primary sources**:

- [ESO AWS service-account authentication](https://external-secrets.io/latest/provider/aws-access/)
- [Terraform ephemeral values](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/ephemeral)
- [Terraform write-only arguments](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only)

## Decision 8: Add neutral ECR repositories without touching legacy repositories

**Decision**: Add exactly five repositories named `microtodosuite/<service>` to
the existing foundation module/state. Preserve the five empty
`microtodosuite/dev/*` resources unchanged. Neutral repositories use immutable
tags, scan-on-push, encryption, lifecycle policy, and `Environment=shared`.

**Rationale**: Renaming the existing Terraform resources would destroy and
replace them, while environment-qualified repositories contradict build-once
promotion.

**Rejected**: Reusing, renaming, or deleting the legacy repositories; separate
repos per environment; or mutable release tags.

## Decision 9: Use least-privilege OIDC identities for CI and Kyverno

**Decision**: Terraform creates:

- one GitHub Actions OIDC provider and publisher role trusted only for
  `refs/heads/main` in the five exact service repositories;
- ECR authorization plus push/signature operations only on the five neutral
  repositories; and
- one IRSA role for the Kyverno admission controller with read-only ECR access
  to verify signatures on those repositories.

Kyverno adds an enforcing keyless `verifyImages` rule limited to the neutral ECR
prefix, the GitHub OIDC issuer, the five allowed workflow subjects, and the
reviewed shared-workflow identity.

**Rationale**: The live cluster cannot verify private-ECR signatures without
registry read credentials, and CI must not use static AWS secrets.

**Rejected**: Developer credentials in GitHub, account-wide ECR writes,
controller write access, unsigned exceptions, or trusting arbitrary GitHub
workflows.

**Primary source**: [Kyverno keyless Sigstore verification](https://kyverno.io/docs/policy-types/cluster-policy/verify-images/sigstore/)

## Decision 10: Make the supply-chain workflow sequential and immutable

**Decision**: Replace mutable `ci.yml@v1` callers with an immutable shared
workflow revision. PR runs execute applicable tests, build once locally, scan
the exact local image with Trivy, and generate one SBOM. Only a reviewed `main`
run may assume the AWS publisher role, push that already-tested image under a
unique commit-derived handle, resolve the ECR manifest digest, attach the SBOM,
and keylessly sign the digest. A failed test or scan produces no ECR image.

**Rationale**: The current workflow pushes and signs in parallel with Trivy;
auth-api therefore produced a signature even though its scan failed. Four other
runs used a different implementation behind the same mutable tag.

**Rejected**: Publishing from PRs, building again for each environment, signing
before scan completion, mutable shared-workflow tags, or authenticating private
ECR jobs with long-lived secrets.

## Decision 11: Repair each service from its recorded baseline before release

**Decision**: Use one short-lived reviewed branch per service. Changes are
limited to tests, reproducible dependency declarations, dependency/security
updates, and build configuration required for truthful green gates. Preserve
REST, event, persistence, and business behavior.

Known starting work:

- auth-api: commit `go.mod`/`go.sum`, update the Go toolchain and vulnerable Go
  modules, and add focused tests;
- todos-api: remove unused vulnerable `prometheus-client`, update affected
  production dependencies, and add JWT/Redis/controller regression tests;
- users-api: run its existing Maven test explicitly and remediate the
  authenticated image scan findings;
- frontend: run lint/tests and include source-lock audit/SBOM evidence because
  runtime-image scanning cannot see bundled JavaScript provenance; and
- log-message-processor: pin dependencies and add mock-based processing and
  transport tests before evaluating authenticated Trivy results.

**Rationale**: The five baseline commits are evidence inputs, not releasable
artifacts. A minimal fix is the smallest change that makes the required gates
truthful, not a waiver for known critical findings.

## Decision 12: Stage prerequisites, then activate all services in one revision

**Decision**: The implementation order is:

1. merge the already-live AWS foundation source into `main`;
2. repair the Terraform execution role through its reviewed bootstrap path;
3. provision neutral ECR, OIDC publisher/verifier, JWT secrets, and reader roles;
4. merge the shared-workflow correction;
5. repair and merge five green service PRs, producing five signed ECR digests;
6. reconcile Argo CD progressive-sync support, Argo Rollouts, ESO resources,
   signature admission, quota changes, and shared-Redis retirement while the
   business activation list stays empty;
7. prove all prerequisite gates live;
8. merge one activation revision containing all three environment entries and
   all five digests; and
9. observe dev, then staging, then prod, followed by the same-digest canary and
   negative-gate evidence revisions and Git revert cleanup.

**Rationale**: This preserves the user's one-publication decision for business
services while preventing incomplete prerequisites from creating broken Pods.

**Rejected**: Activating services incrementally, using placeholder images or
secrets, or merging an activation revision before every gate is live.

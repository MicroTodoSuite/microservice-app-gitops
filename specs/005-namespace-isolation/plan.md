# Implementation Plan: Shared-Cluster Isolation and Environment Publication

**Branch**: `005-namespace-isolation` | **Date**: 2026-08-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-namespace-isolation/spec.md`

## Summary

Complete the cost-optimized shared-EKS architecture by preserving the three
Argo CD-owned isolated namespaces and publishing one reviewed build of
auth-api, todos-api, users-api, frontend, and log-message-processor to dev,
staging, and production. The final registration revision declares all fifteen
business Applications together. EKS-scoped ApplicationSet RollingSync then
reconciles one service at a time in dev, staging, and production order.

Before activation, merge the Terraform source that already owns the live AWS
foundation, restore the intended Terraform role's least-privilege execution
path, create five additive neutral ECR repositories, create three independent
JWT secret/IRSA paths, and create OIDC identities for CI publication and
Kyverno verification. Repair the shared CI workflow so tests, Trivy, and SBOM
complete before a reviewed `main` build is pushed and signed. Repair each of the
five failing source baselines in its own reviewed PR and record the five green
commits, runs, SBOMs, signatures, and digests.

Keep business activation empty while Argo CD progressive syncs, vendored Argo
Rollouts, External Secrets resources, signature admission, economical topology,
quota headroom, and shared-Redis retirement reconcile. Then activate the fifteen
Applications once, observe the required environment order, establish production
stable ReplicaSets, and run a same-digest evidence revision that exercises all
five canary metrics. A separate reviewed failure fixture proves automatic abort
and stable restoration; cleanup is a Git revert. Isolation, resource violation,
secret separation, Redis Pub/Sub separation, and dev continuity are verified
live and recorded in the acceptance checklist only with cited evidence.

## Technical Context

**Languages/versions**: Kubernetes YAML; Kustomize v5; Bash 5.3-compatible
observers; Terraform 1.15.8; AWS provider 6.58.0; service-native Go, Node,
Java, Vue/Node, and Python build tools as pinned by their owning repositories

**Primary dependencies**: Constitution v2.0.0; Argo CD 3.5.0; Argo Rollouts
1.9.1; External Secrets Operator 2.9.0; Kyverno 1.18.2; Amazon VPC CNI
1.23.0-eksbuild.1; AWS EKS 1.35; ECR; Secrets Manager; IAM OIDC/IRSA; GitHub
Actions OIDC; Trivy; Syft; Cosign

**Storage**: Existing encrypted S3 Terraform foundation state; Git desired
state; five private immutable ECR repositories; three protected Secrets Manager
entries; ephemeral namespace-local Redis and existing application-local data
risks; untracked raw evidence below `.local/evidence/namespace-isolation/`

**Testing**: Service tests and dependency audits; Docker build; Trivy; Syft;
Cosign/Kyverno verification; Terraform format/validate/test/plan; Kustomize
render; kubeconform; Bash contract tests; exact Argo CD revision/order; ESO
Ready and non-disclosing secret comparison; live Pod image IDs; six directed
network denials; Redis PONG/PubSub separation; deliberate quota violation;
RBAC authorization matrix when identity mapping becomes available; application
health; canary success and forced abort; continuity/restart comparison

**Target platform**: Existing shared multi-AZ AWS EKS cluster physically named
`microtodosuite-dev`, with namespaces `microtodo-dev`, `microtodo-staging`, and
`microtodo-prod`

**Project type**: Coordinated change across GitOps desired state, AWS Terraform,
organization reusable CI, and five existing application repositories

**Performance goals**: Each RollingSync Application becomes Healthy within ten
minutes; a failed group prevents later groups from syncing; a canary metric
finishes within two minutes; final continuity observation lasts ten minutes

**Constraints**: GitOps-only Kubernetes mutation; reviewed Terraform for AWS;
no static cloud credentials; no placeholder/mutable/all-zero images; no image
rebuild between environments; no service-mesh dependency; no application
behavior change; no business activation until all prerequisites are live; no
acceptance check without cited evidence

**Scale/scope**: One cluster; three environments; five services; fifteen
Applications; five neutral repositories; three source secrets; three JWT reader
roles; one CI publisher role; one Kyverno verifier role; five production
Rollouts; six directed cross-environment paths; three Redis streams; one quota
violation; one canary-failure fixture

## Prerequisite Gap Register

| Gate | Verified current state | Required resolution before activation |
| --- | --- | --- |
| AWS source ownership | Live foundation matches unmerged ops commit `c5ecbda`; ops `main` lacks it | Review and merge the existing foundation branch before extending its state |
| Terraform execution identity | `microtodosuite-terraform-dev` cannot read all managed IAM resources or create the narrowly scoped new roles | Amend its reviewed bootstrap/operator policy; plan/apply only through that role |
| Neutral registry | Only five empty `microtodosuite/dev/*` repositories exist | Add five neutral repositories without replacement or deletion |
| CI publication identity | No GitHub OIDC provider or ECR publisher exists | Terraform a branch- and repository-scoped publisher role |
| Secrets | Secrets Manager and managed namespace ESO objects are empty | Add three independent write-only-generated values, exact IRSA roles, stores, and ExternalSecrets; prove Ready and distinct |
| Source quality | All five recorded baseline CI runs failed | Merge one minimal green descendant PR per service; no failed baseline image is published |
| Workflow safety | Current workflow pushes/signs before all gates and callers use mutable `@v1` | Merge an immutable sequential workflow and pin all callers |
| Supply-chain admission | Kyverno enforces digest/probes only | Add private-ECR read IRSA and enforcing approved-keyless-signature verification |
| Progressive sync | Argo CD flag absent and live apps ApplicationSet has no strategy | Reconcile flag plus controller restart and EKS-only RollingSync strategy |
| Production controller | Argo Rollouts CRDs/controller absent | Vendor, checksum, pin, register, and verify Argo Rollouts 1.9.1 |
| Quota | Intended steady CPU limits exceed every current environment quota | Reconcile evidence-derived quota targets before Pods are declared |
| Topology | All managed topology seams still select the superseded full/Istio component | Select the economical component for all five services |
| Shared Redis | `infra-redis` and namespace `redis` remain live | Retire them only after three namespace Redis instances and clients are verified |
| First canary | A newly created Rollout skips canary analysis by design | Treat activation as stable bootstrap; require a later same-digest canary evidence revision |
| Maintainer identity | AWS-to-environment group mapping remains deferred | Keep reusable RBAC least-privilege; leave live maintainer-matrix acceptance open rather than map one ARN to all groups |
| Full quality/observability wording | Constitution requires applicable tests and SonarQube plus released-image gates; no current Sonar evidence exists | Determine and execute the applicable Sonar/quality gate before release, or stop for an authoritative governance decision; never silently waive it |

## Constitution Check

*GATE: the design is compliant, but activation is conditional on every concrete
gate below. Existing live state is not represented as compliant merely because
the plan contains remediation.*

| Principle | Design gate | Response |
| --- | --- | --- |
| 1. Environment Isolation | PASS | Existing namespaces retain quota, limits, RBAC, default deny, exact allowances, and environment-local Redis; release tests prove live containment. |
| 2. GitOps-Only Deployment | PASS | Every Kubernetes stage is a reviewed Git revision reconciled by Argo CD; observers are read-only. AWS changes remain Terraform-owned. |
| 3. Stable Trunk Development | PASS | AWS, shared workflow, five services, and GitOps use short-lived reviewed branches and green `main` descendants. |
| 4. Authoritative Specifications | PASS | Clarifications, this plan, research, contracts, tasks, and evidence remain the controlling record. |
| 5. Cost-Governed Design | PASS WITH DISCLOSED LIMIT | One shared cluster, serialized rollout, native canary, and no mesh implement v2.0.0; quotas do not claim full-node-loss capacity. |
| 6. Immutable Build Promotion | PASS AFTER GATE | Each service builds once; one signed digest is referenced in all three environments. |
| 7. Progressive and Reversible Releases | PASS AFTER GATE | RollingSync orders environments; production uses metric-gated Rollouts; failed desired state recovers by Git revert. |
| 8. Quality and Supply-Chain Gates | CONDITIONAL | Tests, Trivy, Syft, Cosign, and Kyverno are mandatory tasks. SonarQube/applicable test coverage is a hard pre-activation determination, not an assumed waiver. |
| 9. Observable and Resilient Operations | PASS FOR BOUNDED RELEASE CLAIM | Every service has startup/readiness/liveness probes and exported metrics; a Job metric gates canaries. No claim is made for absent full observability. Istio is superseded by the economical profile. |
| 10. Least Privilege and Secret Hygiene | PASS AFTER GATE | GitHub OIDC, exact IRSA subjects, namespaced ESO, private ECR verification, and no secret output implement the release trust paths. Mesh/mTLS is superseded by the no-mesh profile. |
| 11. Declarative and Policy-Controlled Platform | PASS | Terraform owns IAM/ECR/Secrets; Argo CD owns controllers, policies, and workloads. |
| 12. Proven DR and Disclosed Data Loss | PASS UNDER ADOPTED PROFILE | No AKS claim is made; process-local todos, pod-local H2, and ephemeral Redis limitations remain explicit. |

### Post-research re-check

Research resolved the RollingSync scope, first-Rollout behavior, canary metric,
quota arithmetic, secret generation, registry shape, and CI order. It also found
two blockers that remain deliberately open: the intended Terraform role lacks
permissions, and a current SonarQube gate has not been demonstrated. Tasks may
implement their remedies, but business activation MUST remain empty until the
live checks pass.

## Project Structure

### Specification artifacts

```text
specs/005-namespace-isolation/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── tasks.md
├── checklists/
│   ├── requirements.md
│   └── acceptance.md
└── contracts/
    ├── environment-isolation-contract.md
    ├── namespace-isolation-cli.md
    └── namespace-isolation-evidence.schema.json
```

### GitOps implementation

```text
bootstrap/argocd/                         # progressive-sync flag + rollout trigger
clusters/base/apps.yaml                   # environment label contract
clusters/eks-dev/                         # EKS-only RollingSync + final activation
infrastructure/argo-rollouts/             # vendored 1.9.1 controller + analysis
infrastructure/kyverno/                   # signed neutral-ECR admission
environments/base/                        # ESO resources and common policies
environments/{dev,staging,prod}/          # quota and exact IRSA values
apps/<service>/components/strategy-canary # five production Rollout components
apps/<service>/topology/                  # economical profile selection
apps/<service>/overlays/{dev,staging,prod}# identical URI/digest promotion
tests/contract/                           # render, ordering, add-on, signature contracts
tests/fixtures/namespace-isolation/       # network/resource/Redis evidence only
scripts/managed/                          # read-only evidence collection
```

### AWS infrastructure implementation

```text
microservice-app-ops/aws/modules/environment-foundation/
├── ecr.tf                 # additive neutral repositories
├── github-oidc.tf         # exact service main-branch publisher
├── managed-secrets.tf     # ephemeral JWT values + exact reader roles
├── kyverno-irsa.tf        # read-only private-ECR verifier
├── outputs.tf
└── tests/
```

### CI and service implementation

```text
MicroTodoSuite/.github/.github/workflows/ci.yml
microservice-app-<service>/.github/workflows/ci.yml
microservice-app-<service>/<minimal tests and dependency metadata>
```

**Structure decision**: Environment policy stays in environment Applications;
service delivery stays in the business ApplicationSet; controllers remain
explicit infrastructure Applications; AWS trust and registry resources remain
in the existing foundation state; source behavior stays in its owning service.

## Implementation Phases

### Phase A: Authoritative prerequisites and AWS ownership

1. Review/merge the existing AWS foundation branch so live state has a source
   on `main`.
2. Repair the intended Terraform role through its bootstrap policy path.
3. Add neutral ECR, GitHub OIDC publisher, Kyverno verifier IRSA, three JWT
   secrets, and three exact JWT reader roles.
4. Require a reviewed plan with additive operations only; apply that exact plan
   through the intended role and record non-secret outputs.

### Phase B: Truthful build and supply-chain gates

1. Change the shared workflow to test/build/scan/SBOM before push/sign and tag an
   immutable workflow revision.
2. Pin all five callers to that revision and add the applicable test commands.
3. Repair dependency/build findings in five isolated service PRs.
4. Merge only green PRs and record five reviewed `main` runs, SBOMs, scans,
   signatures, and ECR digests.

### Phase C: GitOps deployment prerequisites

1. Enable Argo CD progressive sync and prove the controller restarted with the
   flag.
2. Vendor/register Argo Rollouts and prove CRDs/controller health.
3. Reconcile ESO ServiceAccounts/Stores/ExternalSecrets and prove three distinct
   secrets without printing values.
4. Reconcile Kyverno verification and prove an invalid signature is denied
   through the GitOps fixture path.
5. Switch all managed service topology seams to economical.
6. Reconcile new quota values and prove capacity arithmetic.
7. Retire shared Redis after three local instances and client endpoints pass.
8. Keep `activation-apps.yaml` empty throughout this phase.

### Phase D: Single progressive business activation

1. Update all fifteen overlays with the five exact neutral ECR digests.
2. Merge one registration revision that lists dev, staging, and prod together.
3. Observe five dev Applications sync one at a time and become Healthy.
4. Observe the same for staging, then production; stop and revert on any gate
   failure.
5. Verify running Pod image IDs, endpoints, Redis dependencies, readiness, and
   restart deltas.

### Phase E: Production canary and isolation evidence

1. Merge the same-digest production pod-template evidence revision and observe
   five successful AnalysisRuns and Rollouts.
2. Merge the negative metric fixture, observe automatic abort and stable
   restoration, then recover by Git revert.
3. Activate isolation fixtures through GitOps and capture all network, Redis,
   resource, and continuity outcomes.
4. Revert fixtures, wait for exact cleanup revision convergence, and update the
   acceptance checklist with specific evidence only.

## Rollback and stop conditions

- Any Terraform plan containing an unexpected update, replacement, or deletion
  stops before apply.
- Any failed source, scan, SBOM, signature, Sonar/applicable-quality, or ECR gate
  prevents image publication or GitOps activation.
- Any non-Ready ExternalSecret, cross-environment secret access, missing CNI
  enforcement, failed Redis replacement, or insufficient quota blocks the final
  activation commit.
- Any RollingSync order violation, Application degradation, readiness loss,
  attributable restart, canary failure outside the intentional fixture, or
  isolation-test failure stops later stages and recovers through reviewed Git
  revert.
- Read-only diagnostics are allowed; `kubectl apply/create/patch/delete/scale`,
  imperative Argo sync, and cloud-CLI resource creation are prohibited.

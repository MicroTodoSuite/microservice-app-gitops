# Implementation Plan: Shared-Cluster Namespace Isolation

**Branch**: `005-namespace-isolation` | **Date**: 2026-08-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-namespace-isolation/spec.md`

## Summary

Add a reusable managed-environment isolation layer under `environments/base`
and value-owning `dev`, `staging`, and `prod` overlays. Each final render
contains an exact Namespace, evidence-sized ResourceQuota, bounded LimitRange,
default-deny ingress/egress, DNS and same-namespace allowances, exact approved
dependency allowances, a custom workload Role, an environment-specific group
RoleBinding, and one digest-pinned Redis instance owned by that namespace. The
existing local pilot remains unchanged.

Activation is intentionally staged across reviewed Git revisions. First prove
the authoritative constitution, shared `eks-main` registration, VPC CNI policy
enforcement, identity mapping, dev dependencies, dev health, and capacity.
Reconcile namespace foundations and required allow rules before adding default
deny. Refactor infrastructure discovery into an explicit per-cluster allowlist,
retain the four running controller add-ons, and remove only the shared
`infra-redis` after all three namespace-local Redis instances pass readiness and
`PONG`. Later activate digest-pinned Deployment-owned verification fixtures by
Git commit, observe all six directed network and Redis denials, Pub/Sub stream
separation, quota containment, and the RBAC matrix with a read-only verifier,
then remove the fixtures with `git revert`. Acceptance requires exact-revision
ArgoCD evidence and zero dev readiness loss or policy-attributable restarts.

This plan does not provision or register EKS, configure VPC CNI, map AWS
identities, install new controller add-ons, or activate real services. Those are
explicit prerequisites or later features. This feature does own the reusable
infrastructure-activation refactor needed to replace folder-wide discovery with
an exact allowlist; the external `eks-main` handoff still owns the shared-cluster
identity and root registration.

## Technical Context

**Language/Version**: Kubernetes YAML (`v1`, `apps/v1`,
`networking.k8s.io/v1`, `rbac.authorization.k8s.io/v1`); Kustomize
`kustomize.config.k8s.io/v1beta1`; Bash 5.3-compatible verification

**Primary Dependencies**: Constitution v1.2.0; existing ArgoCD 3.5.0
ApplicationSet/AppProject mechanism; separately registered EKS 1.35 shared
cluster; Amazon VPC CNI `v1.23.0-eksbuild.1` with network policy explicitly
enabled; kubectl 1.36.3 with embedded Kustomize 5.8.1; kubeconform v0.7.0
against Kubernetes 1.35.0 schemas; and an immutable verification image

**Current Tool Evidence**: `kubectl` 1.36.3 and embedded Kustomize 5.8.1 are
available in this checkout's shell; standalone `kustomize`, `kubeconform`, and
`argocd` CLIs are not installed globally. Implementation downloaded the
checksum-verified kubeconform v0.7.0 release to a temporary path and the
repository validator rejects any other version. Tool absence is handled
explicitly rather than hidden by a successful render or Markdown check.

**Storage**: Git desired state; untracked, timestamped raw and summarized
evidence under `.local/evidence/namespace-isolation/`; no application database
or persistent volume

**Testing**: Kustomize renders; schema validation; Bash static contract tests;
negative scans for wildcard RBAC, broad network allowances, mutation commands,
and local-pilot changes; live ArgoCD revision/sync/health; VPC CNI agent and
provider-resource observations; Deployment-owned connection probes; Kubernetes
events for quota/limit violations; authorization reviews; dev readiness,
restart, dependency, resource, and HTTP continuity samples; three Redis `PONG`
checks; six directed cross-environment Redis denials; Pub/Sub stream-separation
checks; evidence JSON Schema

**Target Platform**: One separately registered multi-AZ AWS EKS cluster with
Linux EC2 workers, one in-cluster ArgoCD reconciler, and three namespaces:
`microtodo-dev`, `microtodo-staging`, and `microtodo-prod`

**Project Type**: GitOps desired-state and acceptance-evidence repository; no
application source or Terraform changes

**Performance Goals**: Each staged revision reaches all three environment
Applications at the exact desired Git SHA within ten minutes; network probe
results appear within two minutes of fixture readiness; the final continuity
window lasts ten minutes after cleanup convergence

**Constraints**: GitOps-only after bootstrap; no direct managed-state mutation;
no default deny before CNI/dependency/health gates; no invented quota values;
no mutable fixture image; no broad cross-environment allowance; no wildcard or
personal identity subject; no real staging/prod workload activation; preserve
`environments/local` and existing pilot contracts; environment-policy activation
must produce zero business-service Applications and use an explicit five-entry
foundation infrastructure allowlist that becomes the exact four controller
Applications only after shared-Redis retirement

**Scale/Scope**: Three namespaces, one reusable isolation base, three resource
budgets, three maintainer bindings, three namespace-local Redis instances, six
directed negative network paths, six directed negative Redis paths, three
same-environment and three DNS positive paths, three Redis health checks, one
Pub/Sub separation matrix, one deliberate resource violation, one complete
authorization matrix, and one existing dev workload set

## Prerequisite Gap Register

Static implementation may proceed, but live activation and acceptance are
**BLOCKED** until the owning work below is reviewed. These are not tasks hidden
inside this feature.

| Gap | Current evidence | Required handoff |
| --- | --- | --- |
| Shared cluster contract is not reconciled | Live AWS and Kubernetes evidence on 2026-08-09 shows one cluster named and tagged `microtodosuite-dev`, while the ops handoff and GitOps root remain `eks-dev` rather than `eks-main` | Separate ops review explicitly accepts reuse/migration to the shared profile and publishes the revised handoff. |
| Shared GitOps registration is not policy-only | Live ArgoCD at revision `24c5c1a9f7b8c870dd0f5b1a11ce89326157c713` has zero environment/business Applications but auto-discovers `infra-keda`, `infra-cert-manager`, `infra-external-secrets`, `infra-kyverno`, and shared `infra-redis` | This feature replaces folder discovery with explicit per-cluster infrastructure values and removes only `infra-redis`; the external handoff supplies the reviewed `eks-main` root. |
| NetworkPolicy configuration is live but not declarative | Both `aws-node` pods are 2/2 Ready and include `aws-eks-nodeagent` with `NETWORK_POLICY_ENFORCING_MODE=standard`, but Terraform's `aws_eks_addon.vpc_cni` has no `configuration_values` and AWS `DescribeAddon` returns none | Ops-owned Terraform change records `enableNetworkPolicy=true`; live positive/negative probes still gate default deny. |
| Identity mapping is absent | Live access entries contain only the EKS service role, node role, and Terraform cluster-admin role; none maps the three maintainer groups | Cluster-access handoff maps approved AWS principals to exact environment groups without broadening bootstrap access. |
| Dev continuity subject is absent | Live ArgoCD has no business-service Application and the cluster has no `microtodo-dev` namespace, so the requested pre-existing dev workload baseline cannot yet be observed | Service activation remains forbidden here; acceptance must stay blocked unless a separately activated dev workload becomes an observable continuity subject. |

Verified authoritative evidence: remote `microservice-app-docs/main` and the
local docs checkout both resolve to
`615241ddf0280279d24c8df5faf5295bfed70ce0`; the authoritative and vendored
constitution files are byte-identical with SHA-256
`14545ede9ee8d39b340b955e454c4500d3cdb30b108d74b3c1180534b6dbf3a4`.

Static artifact work may proceed while gaps are open. No task may mark a live
criterion complete from repository inference.

## Constitution Check

*GATE: Design passes authoritative constitution v1.2.0. Static implementation
may proceed; live activation remains blocked by the prerequisite gap register.*

| Principle | Gate | Design response |
| --- | --- | --- |
| 1. Environment Isolation | PASS | Exact namespace quotas, limits, network policies, RBAC, and environment-local Redis implement the adopted shared-cluster allowance and retain its weaker-failure-domain warning. |
| 2. GitOps-Only Deployment | PASS | Every foundation, deny stage, fixture activation, and cleanup is a reviewed Git revision reconciled by ArgoCD; the verifier is observational. |
| 3. Stable Trunk Development | PASS | Planning is on short-lived `005-namespace-isolation`; implementation is split into small staged PRs rather than one long-lived activation branch. |
| 4. Authoritative Specifications | PASS | Spec, research, data model, contracts, plan, tasks, and evidence schema define the implementation and acceptance order. |
| 5. Cost-Governed Design | PASS | The authoritative amendment records the cost/isolation trade-off; this feature does not silently choose it. |
| 6. Immutable Build Promotion | PASS | The only new image is an opt-in verification image selected by immutable digest; service promotion is outside scope. |
| 7. Progressive and Reversible Releases | PASS | Policy rollout is staged and every failure recovers through Git revert; no service release strategy is changed. |
| 8. Quality and Supply-Chain Gates | PASS | Static contracts, schema checks, immutable fixture identity, live negative/positive tests, and evidence validation are required before acceptance. |
| 9. Observable and Resilient Operations | PASS UNDER ADOPTED PROFILE | Existing dev health and connection evidence gates every stage; no Istio is introduced because v1.2.0 supersedes that full-profile default. |
| 10. Least Privilege and Secret Hygiene | PASS | Custom namespace roles, exact groups, isolation-control exclusion, no wildcard subjects, and no secret values preserve least privilege. |
| 11. Declarative and Policy-Controlled Platform | PASS | ArgoCD owns namespace resources and per-environment Redis; Terraform retains EKS/CNI/IAM ownership and is only a prerequisite consumer. |
| 12. Proven DR and Disclosed Data Loss | PASS UNDER ADOPTED PROFILE | The feature makes no DR or dedicated-isolation claim; v1.2.0 explicitly replaces AKS DR with the accepted single-cluster risk. |

### Post-design re-check

The research and contracts preserve the same gate. In particular, they do not
smuggle VPC CNI configuration, EKS registration, IAM mapping, add-ons, or
service deployment into namespace manifests. The ArgoCD controller's existing
wildcard cluster role is disclosed as a platform-level risk outside the claim
made by environment RoleBindings. The registration prerequisite also prevents
the current app-list lockstep and automatic add-on discovery from broadening the
feature during activation.

## Project Structure

### Documentation created by this feature

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

### Planned implementation files

```text
environments/
├── base/
│   ├── kustomization.yaml
│   ├── limitrange.yaml
│   ├── networkpolicy-default-deny.yaml
│   ├── networkpolicy-allow-dns.yaml
│   ├── networkpolicy-allow-intra-namespace.yaml
│   ├── networkpolicy-allow-redis.yaml
│   ├── redis-deployment.yaml
│   ├── redis-service.yaml
│   ├── redis-serviceaccount.yaml
│   └── role.yaml
├── dev/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── resourcequota.yaml
│   ├── rolebinding.yaml
│   └── networkpolicy-allow-required-egress.yaml
├── staging/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── resourcequota.yaml
│   └── rolebinding.yaml
└── prod/
    ├── kustomization.yaml
    ├── namespace.yaml
    ├── resourcequota.yaml
    └── rolebinding.yaml

tests/
├── contract/
│   └── namespace-isolation.sh
└── fixtures/
    └── namespace-isolation/
        ├── base/
        │   ├── kustomization.yaml
        │   ├── probe-server-deployment.yaml
        │   ├── probe-server-service.yaml
        │   └── probe-client-deployment.yaml
        ├── overlays/
        │   ├── dev/kustomization.yaml
        │   ├── staging/kustomization.yaml
        │   └── prod/kustomization.yaml
        └── quota-violation/
            ├── kustomization.yaml
            └── deployment.yaml

scripts/managed/
├── lib/namespace-isolation.sh
└── verify-namespace-isolation.sh

docs/
└── namespace-isolation.md

clusters/
├── base/infrastructure.yaml
├── local-kind/activation-infrastructure.yaml
└── eks-dev/activation-infrastructure.yaml

apps/{todos-api,log-message-processor}/overlays/{dev,staging,prod}/
└── kustomization.yaml
```

**Structure Decision**: Managed environments share a Kustomize base but retain
concrete Namespace, ResourceQuota, RoleBinding, and evidenced network values in
their environment directories. Test fixtures are opt-in and never referenced by
the final steady-state overlays. Managed-cluster observation lives outside
`scripts/pilot` so local-pilot semantics are not conflated with EKS acceptance.
Redis is shared as manifest structure but instantiated by each environment
Application; the local pilot keeps its existing separate `infra-redis` path.

## Implementation Phases

### Phase A: Static contract and prerequisite evidence

Create failing static contract tests, the observer skeleton, and the acceptance
checklist. Resolve the exact allowed workload resource/verb list, immutable
probe image digest, schema validator, CNI observations, group mapping, dev
dependency inventory, capacity budget, and policy-only Application inventory.
No managed manifest activates while any required value is unknown or while the
registration would discover an unapproved business or infrastructure
Application.

Static work may continue while the shared-cluster, identity, and dev-continuity
handoffs remain open; no live activation may cross those gates.

### Phase B: Foundation revision

Implement the common LimitRange, DNS/same-environment rules, custom Role,
namespace-local Redis resources, and three environment overlays with namespaces,
evidence-approved quotas, RoleBindings, and exact dev allowances. The
default-deny file may exist for review but is not referenced by the base
Kustomization in this revision. Refactor infrastructure activation to an exact
registration-owned list while preserving the local pilot's five-item list and
the managed cluster's four controller items. Merge and wait for `env-dev`,
`env-staging`, and `env-prod` to converge through the separately completed
`eks-main` registration. Require all three Redis instances Ready and returning
`PONG`, then compare dev with baseline.

### Phase C: Default-deny revision

Reference default deny in the common base and update the static contract to
require it in all three renders. Merge only after Phase B passes. Wait for exact
revision, execute fresh positive and negative enforcement checks, and compare
dev again. Revert immediately on continuity failure.

### Phase D: Shared Redis retirement

After all three environment Redis instances pass, remove only `infra-redis`
from the managed cluster's explicit infrastructure list. Preserve the local
pilot's list and the four managed controller Applications. Wait for ArgoCD to
prune the shared Deployment, Service, and `redis` namespace at the exact Git
revision before fixtures proceed.

### Phase E: Evidence fixture revision

Activate the three probe overlays and one deliberately over-budget Deployment
by reviewed Git change. Collect cross-environment, DNS, same-environment, Redis
connection, Redis `PONG`, Pub/Sub separation, resource event,
comparison-workload, and RBAC matrix evidence. This phase is expected to show
the violating Deployment unable to realize its excess pod; it must not describe
that expected failure as an environment outage.

### Phase F: Cleanup and final acceptance

Use `git revert` on the fixture activation commit. Wait until the three
environment applications are Synced/Healthy at the cleanup SHA, prove all
fixtures absent, repeat dev continuity checks through the ten-minute final
window, validate `summary.json`, and complete the acceptance checklist.

## Evidence and Failure Policy

- Each phase writes a new evidence directory; failed evidence is retained.
- Application `Healthy` is necessary but never substitutes for CNI, resource,
  RBAC, or endpoint observations.
- Lack of metrics is recorded as unavailable and blocks any quota value whose
  rationale depends on those metrics.
- A static contract may pass before external prerequisites; live criteria remain
  unchecked.
- Direct mutation discovered in command audit fails acceptance even if the final
  cluster appears healthy.
- If a Git revert cannot restore convergence, the task is blocked for separate
  incident handling; direct repair is not authorized by this plan.

## Complexity Tracking

| Decision | Why needed | Simpler option rejected because |
| --- | --- | --- |
| Shared base plus three overlays | Prevent policy drift while preserving evidence-derived quota and identity values | Three copied environments would make future isolation changes inconsistent. |
| Environment-owned Redis in the shared base | Prevent Pub/Sub traffic from crossing environment boundaries | One `infra-redis` keeps event streams shared even when pod traffic policy is otherwise isolated. |
| Explicit infrastructure activation list | Retain four healthy controllers while retiring only shared Redis | Folder discovery cannot express a cluster-specific exclusion safely. |
| Multiple activation revisions | Required to prove allow rules and dev continuity before deny | One commit hides the dangerous intermediate state. |
| Declarative temporary fixtures | Live negative tests must obey GitOps-only | Imperative test pods would create untracked managed state. |
| Custom workload Role | Least privilege and self-escalation prevention | Built-in `admin` is broader and version-dependent. |
| External prerequisite gates | Ownership and truthfulness | Quietly editing ops/registration would exceed scope and conceal unsatisfied acceptance. |

No additional runtime service, controller, CRD, database, or cloud resource is
introduced by this feature.

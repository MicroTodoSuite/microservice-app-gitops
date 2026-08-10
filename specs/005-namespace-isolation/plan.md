# Implementation Plan: Shared-Cluster Namespace Isolation

**Branch**: `005-namespace-isolation` | **Date**: 2026-08-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-namespace-isolation/spec.md`

## Summary

Add a reusable managed-environment isolation layer under `environments/base`
and value-owning `dev`, `staging`, and `prod` overlays. Each final render
contains an exact Namespace, evidence-sized ResourceQuota, bounded LimitRange,
default-deny ingress/egress, DNS and same-namespace allowances, exact approved
dependency allowances, a custom workload Role, and an environment-specific
group RoleBinding. The existing local pilot remains unchanged.

Activation is intentionally staged across reviewed Git revisions. First prove
the authoritative constitution, shared `eks-main` registration, VPC CNI policy
enforcement, identity mapping, dev dependencies, dev health, and capacity.
Reconcile namespace foundations and required allow rules before adding default
deny. Later activate digest-pinned Deployment-owned verification fixtures by
Git commit, observe all six directed network denials, quota containment, and the
RBAC matrix with a read-only verifier, then remove the fixtures with `git
revert`. Acceptance requires exact-revision ArgoCD evidence and zero dev
readiness loss or policy-attributable restarts.

This plan does not provision or register EKS, configure VPC CNI, map AWS
identities, install add-ons, or activate real services. Those are explicit
prerequisites or later features. The external registration must first decouple
the current matching app/environment lists and automatic infrastructure
discovery so this feature can activate namespace policy without activating
services or add-ons.

## Technical Context

**Language/Version**: Kubernetes YAML (`v1`, `apps/v1`,
`networking.k8s.io/v1`, `rbac.authorization.k8s.io/v1`); Kustomize
`kustomize.config.k8s.io/v1beta1`; Bash 5.3-compatible verification

**Primary Dependencies**: Constitution v1.2.0; existing ArgoCD 3.5.0
ApplicationSet/AppProject mechanism; separately registered EKS 1.35 shared
cluster; Amazon VPC CNI `v1.23.0-eksbuild.1` with network policy explicitly
enabled; kubectl 1.36.3 with embedded Kustomize 5.8.1; an implementation-pinned
schema validator and immutable verification image

**Current Tool Evidence**: `kubectl` 1.36.3 and embedded Kustomize 5.8.1 are
available in this checkout's shell; standalone `kustomize`, `kubeconform`, and
`argocd` CLIs are not currently installed. Their absence does not change the
design and must be handled explicitly by implementation prerequisites rather
than hidden by a successful Markdown check.

**Storage**: Git desired state; untracked, timestamped raw and summarized
evidence under `.local/evidence/namespace-isolation/`; no application database
or persistent volume

**Testing**: Kustomize renders; schema validation; Bash static contract tests;
negative scans for wildcard RBAC, broad network allowances, mutation commands,
and local-pilot changes; live ArgoCD revision/sync/health; VPC CNI agent and
provider-resource observations; Deployment-owned connection probes; Kubernetes
events for quota/limit violations; authorization reviews; dev readiness,
restart, dependency, resource, and HTTP continuity samples; evidence JSON Schema

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
must produce zero business-service and zero infrastructure Applications

**Scale/Scope**: Three namespaces, one reusable isolation base, three resource
budgets, three maintainer bindings, six directed negative network paths, three
same-environment and three DNS positive paths, one deliberate resource
violation, one complete authorization matrix, and one existing dev workload set

## Prerequisite Gap Register

Implementation and especially live activation are **BLOCKED** until the owning
work below is reviewed. These are not tasks hidden inside this feature.

| Gap | Current evidence | Required handoff |
| --- | --- | --- |
| Constitution is not authoritative yet | v1.2.0 exists only in local docs commit `1c9f6e4` and this branch's vendored copy | Merge the approved docs amendment to `microservice-app-docs/main`, then merge the synchronized GitOps copy. |
| Shared cluster contract is not reconciled | Ops branch `esteban/eks-dev-foundation` models one dedicated `microtodosuite-dev` cluster and `clusters/eks-dev` under the former full profile | Separate ops review decides safe reuse/migration to the shared profile and publishes the revised handoff. |
| Shared GitOps registration is absent and current activation is unsafe for policy-only scope | `clusters/` contains only `local-kind`; `clusters/README.md` requires matching app/environment lists, and `clusters/base/infrastructure.yaml` auto-discovers all add-ons | Separate GitOps registration creates and live-validates `clusters/eks-main`, activates only the three environment-policy entries, and leaves business/infrastructure inventories empty without changing this isolation contract. |
| NetworkPolicy enforcement is unproven | VPC CNI 1.23.0 is declared but `enableNetworkPolicy` is not configured in Terraform | Ops-owned change enables the feature declaratively; live gate proves every eligible node's agent and real positive/negative connections. |
| Identity mapping is absent | GitOps has no managed-environment RoleBindings; ops access entries currently grant bootstrap cluster-admin only | Cluster-access handoff maps approved AWS principals to exact environment groups without broadening bootstrap access. |
| Dev dependency/capacity baseline is absent | No `environments/dev` desired state or managed-cluster evidence exists in this checkout | Read-only baseline records live workloads, connections, requests/limits/use, rollout headroom, and health before values are approved. |

Static artifact work may proceed while gaps are open. No task may mark a live
criterion complete from repository inference.

## Constitution Check

*GATE: Design passes constitution v1.2.0. Implementation remains blocked by the
prerequisite gap register and may not begin under authoritative v1.1.0.*

| Principle | Gate | Design response |
| --- | --- | --- |
| 1. Environment Isolation | PASS AFTER AMENDMENT MERGE | Exact namespace quotas, limits, network policies, and RBAC implement the adopted shared-cluster allowance and retain its weaker-failure-domain warning. |
| 2. GitOps-Only Deployment | PASS | Every foundation, deny stage, fixture activation, and cleanup is a reviewed Git revision reconciled by ArgoCD; the verifier is observational. |
| 3. Stable Trunk Development | PASS | Planning is on short-lived `005-namespace-isolation`; implementation is split into small staged PRs rather than one long-lived activation branch. |
| 4. Authoritative Specifications | PASS | Spec, research, data model, contracts, plan, tasks, and evidence schema define the implementation and acceptance order. |
| 5. Cost-Governed Design | PASS AFTER AMENDMENT MERGE | The explicit amendment records the cost/isolation trade-off; this feature does not silently choose it. |
| 6. Immutable Build Promotion | PASS | The only new image is an opt-in verification image selected by immutable digest; service promotion is outside scope. |
| 7. Progressive and Reversible Releases | PASS | Policy rollout is staged and every failure recovers through Git revert; no service release strategy is changed. |
| 8. Quality and Supply-Chain Gates | PASS | Static contracts, schema checks, immutable fixture identity, live negative/positive tests, and evidence validation are required before acceptance. |
| 9. Observable and Resilient Operations | PASS UNDER ADOPTED PROFILE | Existing dev health and connection evidence gates every stage; no Istio is introduced because v1.2.0 supersedes that full-profile default. |
| 10. Least Privilege and Secret Hygiene | PASS | Custom namespace roles, exact groups, isolation-control exclusion, no wildcard subjects, and no secret values preserve least privilege. |
| 11. Declarative and Policy-Controlled Platform | PASS | ArgoCD owns namespace resources; Terraform retains EKS/CNI/IAM ownership and is only a prerequisite consumer. |
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
```

**Structure Decision**: Managed environments share a Kustomize base but retain
concrete Namespace, ResourceQuota, RoleBinding, and evidenced network values in
their environment directories. Test fixtures are opt-in and never referenced by
the final steady-state overlays. Managed-cluster observation lives outside
`scripts/pilot` so local-pilot semantics are not conflated with EKS acceptance.

## Implementation Phases

### Phase A: Static contract and prerequisite evidence

Create failing static contract tests, the observer skeleton, and the acceptance
checklist. Resolve the exact allowed workload resource/verb list, immutable
probe image digest, schema validator, CNI observations, group mapping, dev
dependency inventory, capacity budget, and policy-only Application inventory.
No managed manifest activates while any required value is unknown or while the
registration would discover a business-service/infrastructure Application.

### Phase B: Foundation revision

Implement the common LimitRange, DNS/same-environment rules, custom Role, and
three environment overlays with namespaces, evidence-approved quotas,
RoleBindings, and exact dev allowances. The default-deny file may exist for
review but is not referenced by the base Kustomization in this revision. Merge
and wait for `env-dev`, `env-staging`, and `env-prod` to converge through the
separately completed `eks-main` registration. Compare dev with baseline.

### Phase C: Default-deny revision

Reference default deny in the common base and update the static contract to
require it in all three renders. Merge only after Phase B passes. Wait for exact
revision, execute fresh positive and negative enforcement checks, and compare
dev again. Revert immediately on continuity failure.

### Phase D: Evidence fixture revision

Activate the three probe overlays and one deliberately over-budget Deployment
by reviewed Git change. Collect cross-environment, DNS, same-environment,
resource event, comparison-workload, and RBAC matrix evidence. This phase is
expected to show the violating Deployment unable to realize its excess pod; it
must not describe that expected failure as an environment outage.

### Phase E: Cleanup and final acceptance

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
| Multiple activation revisions | Required to prove allow rules and dev continuity before deny | One commit hides the dangerous intermediate state. |
| Declarative temporary fixtures | Live negative tests must obey GitOps-only | Imperative test pods would create untracked managed state. |
| Custom workload Role | Least privilege and self-escalation prevention | Built-in `admin` is broader and version-dependent. |
| External prerequisite gates | Ownership and truthfulness | Quietly editing ops/registration would exceed scope and conceal unsatisfied acceptance. |

No additional runtime service, controller, CRD, database, or cloud resource is
introduced by this feature.

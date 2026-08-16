<!--
Sync Impact Report
- Version change: 1.2.0 -> 2.0.0
- Modified principles:
  - Cost-Governed Design: Infracost remains an infrastructure gate; OpenCost becomes claim-gated.
  - Quality and Supply-Chain Gates: defines the minimum release baseline and capability-gated tests.
  - Observable and Resilient Operations: probes/release health are baseline; the full stack is claim-gated.
  - Least Privilege and Secret Hygiene: defines the economical security baseline and claim-gated runtime tools.
- Added sections: economical-profile activation baseline and explicit deferred-capability governance.
- Removed sections: none.
- Follow-up TODOs: reconcile feature 005 and create separate specs for each deferred capability before claiming it.
-->

# MicroTodoSuite Constitution

Version: 2.0.0

Ratified: 2026-08-11

Assessment basis: `docs/MicroTodoSuite evolution plan.md`, `context-snapshot.xml`, and repository/live evidence through 2026-08-10.

## Purpose

This constitution defines the binding engineering and governance rules for evolving MicroTodoSuite from its current Azure Container Apps implementation toward the planned AWS EKS platform under the cost-optimized profile formally adopted below. It distinguishes enforceable direction from current fact: existing code is evidence, drift is debt, and an unimplemented plan item must never be represented as an available capability.

## Non-negotiable principles

### 1. Environment Isolation

**Use one AWS account with explicit environment isolation.** AWS environments MUST share one account and be isolated by dedicated clusters and VPCs, or by namespaces with ResourceQuotas, LimitRanges, NetworkPolicies, and RBAC only when the cost-optimized profile is formally adopted — Rationale: isolation must be structural and auditable rather than account sprawl or naming convention.

### 2. GitOps-Only Deployment

**Use GitOps as the only deployment path.** Every workload, platform add-on, configuration, and image change for a managed environment MUST be committed to `microservice-app-gitops` and reconciled by ArgoCD; direct `kubectl apply`, cloud-CLI application mutation, and CI-to-cluster deployment are forbidden — Rationale: Git history must be the complete, reversible record of desired state.

Exception: a documented, minimal, one-time bootstrap sequence MAY use direct
cluster mutation solely to install the GitOps controller itself and its
initial root Application, before any GitOps-managed state exists. This
exception MUST NOT be used for any other purpose, MUST be limited to the
smallest set of commands that installs the controller and hands control to
it, and MUST be recorded in bootstrap documentation so it remains auditable.

### 3. Stable Trunk Development

**Develop from a stable trunk.** Every repository MUST use `main`, short-lived branches, mandatory review and checks, and feature flags for incomplete behavior — Rationale: small integrations reduce merge risk without exposing unfinished work.

### 4. Authoritative Specifications

**Make version-controlled specifications authoritative.** Work MUST derive from the shared constitution and, as applicable, `specs/<feature>.md`, clarification decisions, `plan.md`, and `tasks.md`; REST and event behavior MUST be contract-first through OpenAPI and AsyncAPI, while small fixes MAY begin at tasks but never from an unrecorded prompt — Rationale: people, automation, and AI agents need the same reviewable source of truth.

### 5. Cost-Governed Design

**Measure cost without silently weakening the design.** Every Terraform change MUST produce Infracost evidence before apply. OpenCost MUST be installed and verified before the project claims runtime cost allocation or makes it an acceptance gate; its absence does not block a release that makes no runtime-cost claim and records the gap — Rationale: cost evidence must match the capability actually being asserted.

### 6. Immutable Build Promotion

**Build once and promote immutable evidence.** CI MUST build, test, scan, generate an SBOM, sign one immutable image digest, and promote that same digest through dev, staging, production, and DR using GitOps — Rationale: rebuilding or deploying `latest` breaks provenance and makes rollback unreliable.

### 7. Progressive and Reversible Releases

**Release progressively and reversibly.** Development and staging MAY roll, production MUST use metric-gated Argo Rollouts canaries with automatic rollback, DR MUST receive the production-validated version, and rollback MUST be a Git revert — Rationale: exposure and recovery must be controlled by measured health and recorded state.

### 8. Quality and Supply-Chain Gates

**Automate quality and supply-chain gates.** Every PR MUST run the test categories for which its owning specification defines a runnable contract. Every released image MUST, at minimum, pass source tests and Trivy, produce a Syft SBOM, receive a Cosign signature, and pass Kyverno admission. SonarQube, integration, E2E, performance, and DAST become blocking when a checked-in harness/profile exists or a feature depends on or claims that capability; any deferral MUST be explicit in the feature specification and current-state assessment — Rationale: release gates must be executable and truthful, while absent future tooling is never reported as passing.

### 9. Observable and Resilient Operations

**Design for observable, resilient, and healthy operation.** Every deployed service MUST have startup, readiness, and liveness probes plus a service-owned endpoint or metric used by release health gates. OpenTelemetry, Jaeger, Prometheus/Grafana, ELK/Filebeat, Alertmanager, and KEDA MUST exist before a feature depends on them or claims their telemetry, alerting, or scaling outcomes; otherwise their absence MUST remain a disclosed deferred capability. Istio is forbidden by the economical profile — Rationale: minimum health automation is immediate, while broader operational claims require live supporting systems.

### 10. Least Privilege and Secret Hygiene

**Enforce least privilege and secret hygiene.** CI cloud writes MUST use OIDC; workloads MUST use namespace-scoped RBAC and MUST use IRSA when calling AWS APIs; secrets MUST come through External Secrets; any ingress MUST use TLS; and released images MUST pass Trivy and Kyverno. Service-mesh mTLS is superseded by the economical profile. Falco, `kube-bench`, and `kube-hunter` become mandatory before runtime-threat, CIS-benchmark, or penetration-test coverage is claimed or depended upon, and remain explicitly deferred otherwise — Rationale: the activation baseline closes active credential and artifact paths without fabricating controls that are not installed.

### 11. Declarative and Policy-Controlled Platform

**Keep the platform declarative and policy-controlled.** Terraform MUST own VPC, EKS, IAM/IRSA, ECR, Route 53, and AKS foundations, while ArgoCD MUST own Istio/Kiali, KEDA, cert-manager, External Secrets, Kyverno, Chaos Mesh, Falco, OpenCost, and application manifests — Rationale: ownership boundaries prevent configuration drift and imperative recovery procedures.

### 12. Proven Disaster Recovery and Disclosed Data Loss

**Prove disaster recovery and disclose data loss.** AWS EKS MUST be primary, Azure AKS MUST be a synchronized active-active target routed by Route 53, Chaos Mesh game days MUST test failover, and Redis and business-data continuity limits MUST be explicit until durable replication exists — Rationale: an untested failover path or hidden state loss is not disaster recovery.

## Profile adoption: cost-optimized (economical)

Effective 2026-08-09, this project adopts the cost-optimized architecture
profile defined in `docs/MicroTodoSuite evolution plan.md` section 17,
superseding the full-profile default for AWS infrastructure.

- Development, staging, and production environments share a single AWS EKS
  cluster, isolated by Kubernetes namespace rather than by separate
  clusters or VPCs.
- Each environment namespace MUST have ResourceQuotas, LimitRanges,
  NetworkPolicies, and RBAC enforcing isolation, per principle 1's
  cost-optimized allowance.
- No Istio/service mesh is used; resilience patterns are implemented in
  service libraries, and canary deployment uses native Argo Rollouts
  replica-based traffic shifting rather than Istio percentage routing.
- No Azure AKS disaster-recovery target is provisioned under this profile;
  resilience relies on multi-AZ placement within the single cluster, with
  optional cold DR via Velero snapshots to S3.
- Node capacity SHOULD favor Spot instances for cost, reserving On-Demand
  capacity for evidence-gathering windows or genuinely stateful workloads.

This trades weaker workload isolation for materially lower cost. It is a
deliberate, informed trade-off, not an oversight, and is reversible via a
future amendment reverting to the full profile if isolation needs change.

Workload activation under this profile requires namespace isolation, GitOps-only reconciliation, immutable test/scan/SBOM/signature evidence, Kyverno admission, External Secrets and IRSA where applicable, explicit probes, native production canaries, and live acceptance evidence. Capability-gated controls above MUST have a versioned follow-up spec and owner before they are claimed; their documented absence is neither an implicit pass nor a blocker for an unrelated release.

## Current state vs. plan

Status meanings: **HONORED** = concrete implementation exists; **PARTIAL** = some required behavior exists; **ASPIRATIONAL** = no implementation evidence exists; **CONTRADICTED** = current behavior violates the planned rule.

| Plan principle or component | Status | Snapshot evidence and discrepancy |
| --- | --- | --- |
| Single AWS account and isolated dev/staging/prod | **PARTIAL** | The live shared EKS cluster has three ArgoCD-managed namespaces with quotas, limits, scoped RBAC objects, network-policy scaffolding, and per-environment Redis. Default deny, IAM group mappings, business workloads, and the live negative-test matrix remain incomplete. |
| GitOps-only delivery | **PARTIAL / LEGACY CONTRADICTION** | ArgoCD now reconciles the EKS platform and three environment Applications from `microservice-app-gitops`; business activation remains empty. Legacy Azure ops and Prometheus workflows still contain direct cloud mutations. |
| Trunk-Based Development and feature flags | **PARTIAL** | Repositories use `main`, PR triggers, and short-lived `feat/*` references, and ops documentation names trunk-based development. No feature-flag implementation or enforcement is present, and historical docs still describe GitHub Flow for application repositories. |
| Specification as source of truth | **PARTIAL** | GitOps features 001-005 include versioned specs, plans, tasks, contracts, and acceptance criteria. Coverage is not uniform across repositories, and feature 005 must be reconciled with this amendment before implementation resumes. |
| FinOps-informed design | **ASPIRATIONAL / DEFERRED** | No checked-in Infracost or live OpenCost evidence exists. Runtime-cost claims remain unavailable, while unrelated economical-profile activation is allowed only with this gap disclosed. |
| Planned repository topology | **PARTIAL** | The GitOps and organization `.github` shared-workflow repositories now exist alongside the service, ops, docs, Prometheus, and AI-agents repositories. Adoption and AI-agent assets remain incomplete. |
| Terraform cloud foundation | **PARTIAL / UNMERGED SOURCE** | A live multi-AZ EKS/VPC foundation, AWS remote state, two managed nodes, and VPC CNI network-policy enforcement exist. Their Terraform source remains on an unmerged ops branch; Infracost, workload IRSA, ECR activation, and Spot/Karpenter remain absent. |
| Kubernetes platform add-ons | **PARTIAL** | ArgoCD, KEDA, cert-manager, External Secrets Operator, and Kyverno are live and healthy, with Redis currently active per environment plus the pending shared instance. Argo Rollouts and a metric backend are absent; Chaos Mesh, Falco, and OpenCost remain deferred. |
| ArgoCD layout, promotion, rollback, and notifications | **PARTIAL** | The live root, infrastructure, and three environment Applications are Git-owned and Synced/Healthy, and the service matrix is deliberately empty. Business promotion, native rollout health, reviewed failure recovery, and notifications remain unverified. |
| Environment-specific deployment strategy | **ASPIRATIONAL / BLOCKED** | All five managed overlays exist, but zero business Applications are active. Argo Rollouts CRDs/controller and a valid analysis backend are absent, and the existing auth-only canary seam cannot provide acceptance evidence. |
| Reusable CI, OIDC, and artifact supply chain | **PARTIAL / RELEASE-BLOCKED** | Five services call the central workflow, which defines build-once digests, AWS OIDC, Trivy, Syft, and Cosign stages. Test execution is largely unwired, SonarQube is inactive, and successful image-specific baseline evidence plus Kyverno signature admission remain prerequisites to release. |
| Resilience and configuration patterns | **PARTIAL** | Services read environment variables, Terraform converts selected values to secret references, Todos retries Redis connections, and an ops workflow imperatively applies Azure's recommended resiliency policy. General service-library circuit breaker, bulkhead, and timeout behavior is not demonstrated; OpenFeature and Spring Cloud Config are absent. |
| Test strategy and quality reporting | **PARTIAL / RELEASE-BLOCKED** | The central workflow exposes explicit unit, integration, contract, E2E, performance, DAST, and Sonar gates, but most are fail-closed scaffolds without runnable suites. No business image has complete baseline release evidence. |
| Observability and workload health | **PARTIAL / DEFERRED** | Service manifests expose health/metric endpoints and declare probes, but no business workload is live in EKS and production rollout health is untested. OpenTelemetry, Jaeger, Prometheus/Grafana, Loki, and Alertmanager are not active on EKS and cannot be claimed. |
| Security controls | **PARTIAL / RELEASE-BLOCKED** | Namespace RBAC objects, External Secrets Operator, Kyverno, network-policy enforcement, and supply-chain stages now exist. EKS group mappings, workload IRSA/secret flow, verified signatures/admission, and ingress TLS remain incomplete; legacy Azure static credentials persist, while Falco and benchmark tools are deferred. |
| Change management and traceability | **PARTIAL / CONTRADICTED** | Semantic-release, semantic versions, release tags, and changelogs exist. Deployments nevertheless select `:latest`; PR rollback plans, spec-to-image traceability, immutable promotion, and GitOps `git revert` rollback are absent. |
| Cost-optimized resilience, chaos engineering, and cost controls | **PARTIAL** | Shared EKS, three bounded namespaces, VPC CNI enforcement, GitOps, selected add-ons, and per-environment Redis are live. Default-deny evidence, business activation, canaries, continuity, Spot capacity, resilience libraries, and FinOps evidence remain incomplete or explicitly deferred. |
| Data continuity | **CONTRADICTED AS A DR CAPABILITY; HONESTLY IDENTIFIED AS A RISK** | Redis is an unreplicated, unpersisted Pub/Sub service, Todos stores data in process memory, and Users uses pod-local H2 seed data. Restarts and scaling can lose or diverge state, so the code confirms the plan's warning but provides no continuity. |
| AI-agents repository | **PARTIAL** | The repository contains context documentation plus scripts to generate `AGENTS.md` files and index repositories. The advertised `.claude/agents`, `.claude/skills`, and `.claude/mcp` content does not appear in the snapshot, so specialized agents, Spec Kit skills, and MCP configuration are not delivered. |
| Suggested roadmap | **PARTIAL, MIGRATION ACTIVE** | AWS foundation, GitOps, namespace isolation scaffolding, core add-ons, shared CI, and service overlays now exist at different maturity levels. Business activation, progressive delivery, continuity, complete quality evidence, observability, chaos, and FinOps remain open. |

## Amendment process

1. Any contributor may propose an amendment through a pull request to `microservice-app-docs`; the PR MUST state the exact text changed, rationale, alternatives, affected repositories, compatibility impact, migration tasks, and rollback approach.
2. The PR MUST update the current-state assessment when it changes an architectural target or when new implementation evidence changes a status.
3. Approval MUST come from a maintainer of `microservice-app-docs`, a maintainer of `microservice-app-ops` or `microservice-app-gitops` for platform concerns, and a maintainer of every materially affected service; an AI agent may draft but may not approve an amendment.
4. An addition, change, profile switch, or retirement becomes effective only after those approvals and merge to `main`; the constitution version and ratification date MUST change in the same commit.
5. Retired principles MUST retain an auditable explanation in Git history and MUST include migration work for specifications, code, and GitOps state that depended on them.

## Governance

This constitution outranks feature specifications; approved feature specifications outrank plans and tasks; all of them outrank current code and deployed state. A conflicting feature specification MUST be changed to comply or blocked until a constitution amendment is approved first. Existing contradictory code creates remediation work and never establishes precedent or an implicit waiver. Ambiguity is resolved in a documented pull-request decision by the same maintainers required for an amendment, and no conversation, prompt, emergency command, or undocumented exception may override that decision hierarchy.

**Version**: 2.0.0 | **Ratified**: 2026-08-11 | **Last Amended**: 2026-08-11

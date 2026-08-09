<!--
Sync Impact Report
- Version change: 1.1.0 -> 1.2.0
- Modified principles: none.
- Added sections:
  - Profile adoption: cost-optimized (economical).
- Superseded defaults:
  - Section 17's shared-cluster, no-mesh, no-AKS, native-canary, and Spot-favored targets supersede the full-profile defaults.
- Removed sections: none.
- Follow-up TODOs:
  - Reconcile affected platform specifications and GitOps state with the adopted profile.
-->

# MicroTodoSuite Constitution

Version: 1.2.0

Ratified: 2026-08-09

Assessment basis: `docs/MicroTodoSuite evolution plan.md` and `context-snapshot.xml`.

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

**Measure cost without silently weakening the design.** Infracost and OpenCost MUST expose infrastructure-change and runtime cost, and any move to the cost-optimized profile MUST be an approved architectural amendment — Rationale: simplification must be an informed decision, not hidden scope erosion.

### 6. Immutable Build Promotion

**Build once and promote immutable evidence.** CI MUST build, test, scan, generate an SBOM, sign one immutable image digest, and promote that same digest through dev, staging, production, and DR using GitOps — Rationale: rebuilding or deploying `latest` breaks provenance and makes rollback unreliable.

### 7. Progressive and Reversible Releases

**Release progressively and reversibly.** Development and staging MAY roll, production MUST use metric-gated Argo Rollouts canaries with automatic rollback, DR MUST receive the production-validated version, and rollback MUST be a Git revert — Rationale: exposure and recovery must be controlled by measured health and recorded state.

### 8. Quality and Supply-Chain Gates

**Automate quality and supply-chain gates.** Each pull request MUST run applicable unit, integration, contract, end-to-end, performance, and DAST tests plus SonarQube and Trivy gates; Syft, Cosign, and Kyverno MUST protect released images — Rationale: unverified code or artifacts must not become deployable state.

### 9. Observable and Resilient Operations

**Design for observable, resilient, and healthy operation.** OpenTelemetry, Jaeger, Prometheus/Grafana, ELK/Filebeat, Alertmanager, explicit startup/readiness/liveness probes, Istio resilience, and KEDA scaling MUST cover every deployed service as applicable — Rationale: safe automation requires uniform telemetry, health signals, and bounded failure behavior.

### 10. Least Privilege and Secret Hygiene

**Enforce least privilege and secret hygiene.** CI MUST use OIDC, workloads MUST use namespace-scoped RBAC and IRSA, secrets MUST come through External Secrets, ingress MUST use TLS, internal traffic MUST use mTLS, and Trivy, Kyverno, Falco, `kube-bench`, and `kube-hunter` MUST be enforced — Rationale: static credentials, embedded secrets, and unaudited workloads are unacceptable trust shortcuts.

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

## Current state vs. plan

Status meanings: **HONORED** = concrete implementation exists; **PARTIAL** = some required behavior exists; **ASPIRATIONAL** = no implementation evidence exists; **CONTRADICTED** = current behavior violates the planned rule.

| Plan principle or component | Status | Snapshot evidence and discrepancy |
| --- | --- | --- |
| Single AWS account and isolated dev/staging/prod | **CONTRADICTED** | The infrastructure is one Azure Container Apps environment tagged as production; no AWS account configuration, shared EKS cluster, or dev/staging/prod namespace isolation is present. |
| GitOps-only delivery | **CONTRADICTED** | No `microservice-app-gitops` repository or ArgoCD configuration appears. Service workflows build and directly run `az containerapp update` and revision restart; their pull-request trigger also reaches the deploy step. Ops workflows directly apply Terraform and mutate resiliency policies. |
| Trunk-Based Development and feature flags | **PARTIAL** | Repositories use `main`, PR triggers, and short-lived `feat/*` references, and ops documentation names trunk-based development. No feature-flag implementation or enforcement is present, and historical docs still describe GitHub Flow for application repositories. |
| Specification as source of truth | **PARTIAL** | Repository `AGENTS.md` files state the rule, and this file establishes the Constitution stage. The snapshot contains no `specs/`, feature specs, clarifications, plans, tasks, version-controlled acceptance criteria, OpenAPI, AsyncAPI, Spectral, or Pact artifacts. |
| FinOps-informed design | **ASPIRATIONAL** | No checked-in Infracost or OpenCost configuration exists; a Git reference named `feat/infracost` is not an implementation. |
| Planned repository topology | **PARTIAL** | Auth, todos, users, frontend, log processor, ops, docs, Prometheus, and AI-agents repositories exist. The GitOps and organization-level shared-workflow repositories do not appear; AI-agents is only partially populated. |
| Terraform cloud foundation | **CONTRADICTED / PARTIAL** | Modular Terraform and Azure Blob remote state are real, but they create Azure Container Apps, ACR, Log Analytics, and one environment. The adopted target's single multi-AZ EKS/VPC foundation, AWS state, IAM/IRSA, ECR, Spot-oriented capacity, and Infracost are absent. |
| Kubernetes platform add-ons | **ASPIRATIONAL** | No Kubernetes manifests or configuration for Argo Rollouts, KEDA, cert-manager, External Secrets Operator, Kyverno, Chaos Mesh, Falco, or OpenCost exists; Istio/Kiali are no longer target add-ons under the adopted profile. |
| ArgoCD layout, promotion, rollback, and notifications | **CONTRADICTED** | There are no cluster folders, bases/overlays, auto-sync, dev-update PRs, staging/production promotion PRs, production approval, Git-revert rollback flow, or ArgoCD Slack notifications. Current pipelines deploy application images directly. |
| Environment-specific deployment strategy | **CONTRADICTED** | Azure Container Apps uses `revision_mode = "Single"`, sends 100% of traffic to the latest revision, and deploys `:latest`; no Argo Rollout, AnalysisTemplate, Prometheus gate, native replica-based canary steps, or distinct dev/staging/prod strategy exists. |
| Reusable CI, OIDC, and artifact supply chain | **PARTIAL / CONTRADICTED** | Per-repository GitHub Actions build images and semantic-release creates releases, but workflows are duplicated and use Azure credential, subscription, registry-admin, and GitHub token secrets. There is no shared workflow, AWS/Azure OIDC, build-once promotion, SonarQube, Trivy, Syft SBOM, Cosign signing, or signature admission. |
| Resilience and configuration patterns | **PARTIAL** | Services read environment variables, Terraform converts selected values to secret references, Todos retries Redis connections, and an ops workflow imperatively applies Azure's recommended resiliency policy. General service-library circuit breaker, bulkhead, and timeout behavior is not demonstrated; OpenFeature and Spring Cloud Config are absent. |
| Test strategy and quality reporting | **PARTIAL, NEARLY ABSENT** | Users API has one Spring context-load test and Maven packaging runs it; frontend has a lint command. Auth, Todos, frontend, log processor, Prometheus, and ops have no functional suites, several `npm test` scripts deliberately fail, and CI runs none of the planned unit, Testcontainers, contract, E2E, Locust, ZAP, coverage, or SonarQube gates. |
| Observability and workload health | **PARTIAL** | Prometheus metrics, a custom Prometheus image, Grafana, an nginx exporter, Zipkin tracing, stdout logging, and Azure Log Analytics exist. OpenTelemetry, short-retention Jaeger, business metrics, Loki, Alertmanager/Slack, and deployment probes are absent; only Users exposes an actuator health capability, which is not wired as a probe. |
| Security controls | **PARTIAL / CONTRADICTED** | JWT authentication and some Azure secret references exist. Static CI credentials, ACR admin access, source JWT fallbacks, Terraform's `PRFT` JWT default, Grafana password `12345`, public monitoring ingress, and unsigned `:latest` images contradict the target; External Secrets, RBAC/IRSA, explicit TLS/mTLS, Trivy, Kyverno, Falco, `kube-bench`, and `kube-hunter` are absent. |
| Change management and traceability | **PARTIAL / CONTRADICTED** | Semantic-release, semantic versions, release tags, and changelogs exist. Deployments nevertheless select `:latest`; PR rollback plans, spec-to-image traceability, immutable promotion, and GitOps `git revert` rollback are absent. |
| Cost-optimized resilience, chaos engineering, and cost controls | **ASPIRATIONAL** | This amendment adopts the cost-optimized profile, but the assessment snapshot contains no EKS, namespace quotas/policies/RBAC, multi-AZ or Velero recovery, Spot/Karpenter, native canaries, service-library resilience, Loki, short-retention Jaeger, SonarCloud, cluster-level Chaos Mesh evidence, OpenCost, or Infracost. Current Azure Container Apps remains a legacy state, not an implementation of the adopted profile. |
| Data continuity | **CONTRADICTED AS A DR CAPABILITY; HONESTLY IDENTIFIED AS A RISK** | Redis is an unreplicated, unpersisted Pub/Sub service, Todos stores data in process memory, and Users uses pod-local H2 seed data. Restarts and scaling can lose or diverge state, so the code confirms the plan's warning but provides no continuity. |
| AI-agents repository | **PARTIAL** | The repository contains context documentation plus scripts to generate `AGENTS.md` files and index repositories. The advertised `.claude/agents`, `.claude/skills`, and `.claude/mcp` content does not appear in the snapshot, so specialized agents, Spec Kit skills, and MCP configuration are not delivered. |
| Suggested roadmap | **PARTIAL, PRE-MIGRATION** | Legacy Terraform, container images, basic telemetry, semantic release, and agent-context scripts predate the target. Roadmap steps for AWS foundations, platform add-ons, GitOps, shared CI, target observability, multicloud, chaos, and FinOps remain undone; this constitution begins only the governance portion of step 6. |

## Amendment process

1. Any contributor may propose an amendment through a pull request to `microservice-app-docs`; the PR MUST state the exact text changed, rationale, alternatives, affected repositories, compatibility impact, migration tasks, and rollback approach.
2. The PR MUST update the current-state assessment when it changes an architectural target or when new implementation evidence changes a status.
3. Approval MUST come from a maintainer of `microservice-app-docs`, a maintainer of `microservice-app-ops` or `microservice-app-gitops` for platform concerns, and a maintainer of every materially affected service; an AI agent may draft but may not approve an amendment.
4. An addition, change, profile switch, or retirement becomes effective only after those approvals and merge to `main`; the constitution version and ratification date MUST change in the same commit.
5. Retired principles MUST retain an auditable explanation in Git history and MUST include migration work for specifications, code, and GitOps state that depended on them.

## Governance

This constitution outranks feature specifications; approved feature specifications outrank plans and tasks; all of them outrank current code and deployed state. A conflicting feature specification MUST be changed to comply or blocked until a constitution amendment is approved first. Existing contradictory code creates remediation work and never establishes precedent or an implicit waiver. Ambiguity is resolved in a documented pull-request decision by the same maintainers required for an amendment, and no conversation, prompt, emergency command, or undocumented exception may override that decision hierarchy.

**Version**: 1.2.0 | **Ratified**: 2026-08-09 | **Last Amended**: 2026-08-09

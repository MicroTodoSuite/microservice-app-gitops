# Implementation Plan: Full Multi-Cloud Platform Rollout

**Branch**: `feat/full-platform-rollout` | **Date**: 2026-08-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-full-platform-rollout/spec.md`

## Summary

Deliver the full MicroTodoSuite profile alongside the working economical profile: dedicated AWS EKS/VPC foundations for full development, staging, and production; an independently reconciled Azure AKS disaster-recovery destination; and the complete GitOps-managed mesh, security, observability, scaling, progressive-delivery, chaos, and cost stack. The existing `demo-full` foundation remains the physical full-staging destination. Full development and production use new state scopes and non-overlapping VPCs. They share a separately owned centralized egress VPC and Transit Gateway so the account consumes only its final available Elastic IP and creates no quota increase request.

Every stage is fail-closed. It begins with an economical-platform baseline and ends with static, Terraform, cost, live-success, failure-mode, rollback, and unchanged-baseline evidence. Existing AWS account singletons remain owned by dev state. New foundations consume them and expose cluster OIDC issuers; only dev state may extend the shared roles' exact trust policies. Dev state also owns one new, opt-in `microtodosuite/platform` mirror repository and a distinct exact-workflow role so every GitOps-installed third-party image can be scanned, signed, and deployed by immutable mirrored digest without changing the five existing service repositories. `microtodosuite.online` is the only canonical domain; dev creates it as a separately addressed, opt-in Route 53 zone after the compatibility gate, and registrar delegation must be verified without replacing the retained legacy zone. Production traffic and Route 53 active-active records remain disabled until a separate human approval follows the successful game day.

## Technical Context

**Language/Version**: Terraform HCL with Terraform `1.15.8`; Kubernetes YAML/Kustomize `5.8.1`; Bash; service runtimes already selected by the shared CI contract: Go `1.26.6`, Node.js `24`, Java `21`, and Python `3.13`

**Primary Dependencies**: AWS provider `6.58.0`, Random provider `3.9.0`, `terraform-aws-modules/vpc/aws` `6.6.1`, `terraform-aws-modules/eks/aws` `21.24.2`, AzureRM provider `5.0.1`, EKS and AKS Kubernetes `1.35`, ArgoCD `3.5.0`, Argo Rollouts `1.9.1`, AWS Load Balancer Controller `3.5.0`, Istio `1.30.3`, Kiali `2.31.0`, Karpenter `1.14.1`, ECK `3.5.0`, Chaos Mesh `2.8.4`, OpenCost chart `2.5.29`, SonarQube Community Build `26.8.0.126808-community`, PostgreSQL `16.15-alpine3.24`, and the currently vendored versions recorded in [research.md](./research.md)

**Storage**: Locked remote Terraform state in the existing encrypted AWS S3 backend with one distinct key per AWS root; an independently locked Azure Blob state key for AKS; encrypted EBS/Azure Disk volumes for platform state; application Redis, todo, and user data remain non-durable and unreplicated by explicit scope decision

**Testing**: `terraform fmt`, `terraform validate`, `terraform test`, saved remote-state `terraform plan`, Infracost, Kustomize rendering, kubeconform `0.7.0`, policy/ownership shell checks, service-owned unit/integration/contract/E2E/performance/DAST suites, Trivy, Syft, Cosign, Kyverno admission tests, ArgoCD/live health checks, telemetry correlation, scaling tests, canary rollback, chaos experiments, and a gated DR game day

**Target Platform**: AWS account `916491575487` in `us-east-1`; three dedicated full-profile EKS clusters plus the unchanged economical EKS cluster; one AKS 1.35 cluster in the approved existing Azure subscription and region discovered during implementation preflight; GitHub Actions and protected GitHub repositories

**Project Type**: Cross-repository infrastructure, GitOps, delivery-automation, and service operational-contract rollout

**Performance Goals**: Release-health metrics and correlated telemetry visible within 5 minutes; bounded workload/node scaling within 5 minutes; failed production canary restored within 5 minutes; approved AWS-outage failover completed within 10 minutes; production canary exposure at 10%, 25%, 50%, and 100%

**Constraints**: No economical-platform disruption or destructive state move; no duplicated account singleton; `microtodosuite.online` only for new DNS/certificates and no in-place rename or destruction of the legacy zone; registrar delegation must match Terraform outputs before DNS acceptance; no full managed control plane open to `0.0.0.0/0`; all full AWS roots and AKS initially use exactly the reviewed `/32` set `181.50.102.191/32`, `186.112.71.16/32`, `190.108.77.190/32`, and `200.3.193.225/32`, with staging required to retain it; no quota increase; at most one additional EIP; 16 On-Demand standard vCPU and 32 Spot standard vCPU current AWS quotas; GitOps-only after each two-mutation ArgoCD bootstrap; no maintained PAT or static cloud credential; no active-active traffic without a separate human approval; no false data-durability claim

**Scale/Scope**: Four independently reconciled full destinations (three EKS and one AKS), five business services, three logical environments, one unchanged economical cluster, nine participating repositories (GitOps, ops, organization workflows, five services, and docs), and the full platform capability set in FR-023

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Constitutional gate | Plan compliance | Evidence required before implementation advances |
| --- | --- | --- |
| Environment isolation | PASS: full dev, staging, and prod have dedicated EKS clusters and VPCs; AKS DR has its own VNet; egress transit routes do not permit spoke-to-spoke traffic. | State/VPC/VNet inventory, route tests, namespace RBAC and NetworkPolicy tests. |
| GitOps-only deployment | PASS: Terraform owns cloud foundations; each cluster receives only vendored ArgoCD plus its tracked root Application directly. Everything else is reconciled from Git. | Bootstrap transcript with exactly two mutations, ArgoCD revision/Application inventory, and a direct-mutation rejection audit. |
| Stable trunk | PASS: implementation is divided into short-lived, independently reviewable branches and protected-main merges. | Reviewed head SHA, required checks, approval, merge SHA, and rollback commit for each stage. |
| Authoritative specifications | PASS: this spec, plan, contracts, tasks, and analysis govern all participating repositories. | Cross-repository task/PR traceability to FR and SC identifiers. |
| Cost-governed design | PASS: every Terraform stage requires a saved plan, Infracost diff, current quota capture, explicit cost ceiling or human acceptance, and rollback before apply. | Stage-gate bundle satisfying `contracts/stage-gate-contract.md`. |
| Immutable build promotion | PASS: one ECR digest is tested, scanned, inventoried, signed, then copied without rebuild to ACR while preserving and verifying its manifest digest. | ECR/ACR digest equality, SBOM, signature, source SHA, and live image IDs. |
| Progressive and reversible releases | PASS: dev/staging roll, AWS production uses 10/25/50/100 Istio traffic steps with error-rate and p99 gates, AKS receives the validated digest by rolling update, and rollback is a Git revert. | AnalysisRun results, deliberate failure, automatic rollback timing, and Git revert drill. |
| Quality and supply-chain gates | PASS: existing runnable suites become blocking, missing required harnesses are implemented before promotion is enabled, and every GitOps-installed third-party platform image is digest-locked, mirrored, scanned, and signed by a distinct exact-workflow identity before activation. | Per-service test matrix plus upstream/ECR/ACR platform-image graph, Trivy, Syft, Cosign, SonarQube, and Kyverno evidence. |
| Observable and resilient operations | PASS: the full profile activates Istio/Kiali, Prometheus/Grafana/Alertmanager, OpenTelemetry/Jaeger, ECK-managed ELK/Filebeat, KEDA, and service-owned health/telemetry contracts. | One correlated request per service, alert delivery, resilience behavior, and failure-mode evidence. |
| Least privilege and secret hygiene | PASS: GitHub Apps and cloud OIDC replace PAT/static credentials; EKS uses exact-subject IRSA and AKS uses workload identity; External Secrets supplies values; TLS/mTLS and security controls fail closed. | Trust-policy assertions, token source, secret-reference audit, TLS/mTLS sampling, Falco/audit reports, and unsigned-image denial. |
| Declarative platform ownership | PASS: Terraform owns cloud network/cluster/IAM/registries/DNS; ArgoCD owns the declared Kubernetes capabilities and applications. | Ownership inventory with one owner per resource and zero post-bootstrap imperative apply/create/patch commands. |
| Proven DR and disclosed data loss | PASS: AKS reconciles independently, receives the production digest, and participates in a bounded game day before traffic approval; continuity is reported separately. | DR contract, game-day evidence, RTO result, digest equality, and explicit Redis/todo/user divergence report. |

No constitutional violation is accepted. Any failed row blocks its dependent stage.

## Project Structure

### Documentation (this feature)

```text
specs/009-full-platform-rollout/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── cluster-registration-contract.md
│   ├── dr-game-day-contract.md
│   ├── full-profile-evidence.schema.json
│   ├── infrastructure-ownership-contract.md
│   ├── release-promotion-contract.md
│   └── stage-gate-contract.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (participating repository roots)

```text
microservice-app-ops/
├── aws/modules/environment-foundation/
├── aws/modules/centralized-egress/
├── aws/environments/dev/foundation/
├── aws/environments/demo-full/foundation/
├── aws/environments/full-dev/foundation/
├── aws/environments/full-prod/foundation/
├── aws/shared/egress/
├── azure/modules/aks-foundation/
├── azure/environments/dr/foundation/
└── .github/workflows/

microservice-app-gitops/
├── apps/<service>/
│   ├── base/
│   ├── components/{strategy-canary,strategy-canary-full,topology-economical,topology-full}/
│   └── profiles/{economical,full}/overlays/{dev,staging,prod}/
├── bootstrap/argocd/
├── clusters/
│   ├── base/
│   ├── eks-dev/
│   ├── eks-full-dev/
│   ├── eks-full-staging/
│   ├── eks-full-prod/
│   └── aks-dr/
├── environments/
├── infrastructure/
│   ├── argocd-notifications/
│   ├── argo-rollouts/
│   ├── aws-load-balancer-controller/
│   ├── cert-manager/
│   ├── chaos-mesh/
│   ├── eck-operator/
│   ├── elasticsearch/
│   ├── external-secrets/
│   ├── falco/
│   ├── filebeat/
│   ├── grafana/
│   ├── istio/
│   ├── jaeger/
│   ├── karpenter/
│   ├── keda/
│   ├── kiali/
│   ├── kibana/
│   ├── kube-bench/
│   ├── kube-hunter/
│   ├── kyverno/
│   ├── logstash/
│   ├── loki/                       # economical-only existing capability
│   ├── opencost/
│   ├── prometheus/
│   ├── redis/
│   └── sonarqube/                  # full-dev-only shared CI tooling
├── scripts/managed/
├── evidence/templates/
└── .github/workflows/validate-gitops.yml

.github/
└── .github/workflows/{ci,release,promote,stack-tests,mirror-platform-images,mirror-to-acr,sync-dr-secrets}.yml

microservice-app-{auth-api,frontend,log-message-processor,todos-api,users-api}/
├── service source and tests
├── contracts/
└── .github/workflows/

microservice-app-docs/
└── full-platform operating, cost, bootstrap, promotion, and DR runbooks
```

**Structure Decision**: The GitOps repository owns the cross-repository specification and all desired Kubernetes state. `microservice-app-ops` owns only cloud foundations and cloud identity. The organization workflow repository owns reusable build/promotion behavior. Each service repository owns its health, resilience, configuration, telemetry, and test contract. Documentation records operator procedures and accepted trade-offs. Existing economical paths remain valid while profile-specific overlay paths allow the same logical environment to render concurrently for economical and full destinations.

## Delivery Sequence and Hard Gates

1. **Baseline and toolchain**: capture Git/AWS/cluster/economical health, resolve Azure identity from the real account, pin all downloaded artifacts with checksums, and establish the evidence schema. Stop if the baseline is unhealthy.
2. **Terraform compatibility and ownership**: add tests first, generalize bootstrap/egress and full-cluster prerequisite inputs behind defaults that preserve dev/demo, and introduce multi-cluster trust inputs owned only by dev state. A remote dev plan must be exactly `0 to add, 0 to change, 0 to destroy` before any new foundation work.
3. **Shared egress and AWS foundations**: first prove the unchanged `demo-full` baseline is `0/0/0`; then plan its explicit cluster-local EBS/Karpenter/secret-reader prerequisites separately. Plan the egress root, full dev, and full prod independently; prove no singleton duplication, quota fit, cost acceptance, no destroys, and state backups; then apply only approved saved plans in dependency order during implementation. `demo-full` remains full staging and keeps its current VPC, NAT, nodes, state, and four-CIDR allowlist.
4. **Profile-aware GitOps and bootstrap**: render economical and full overlays concurrently, register one logical environment per full root, merge each root to protected `main`, and perform exactly the two documented bootstrap mutations per new cluster. Stop if the economical ArgoCD revision or health regresses.
5. **Complete full platform and services**: create the single dev-owned platform mirror repository/role, copy every locked third-party image into it, scan and keyless-sign the complete graph, and make immutable mirrored ECR references plus their exact signature identity an activation gate. Then activate dependencies in waves, including External Secret-backed ArgoCD Notifications, the full-EKS-only AWS Load Balancer Controller, one shared self-hosted SonarQube/PostgreSQL instance in full-dev, and controlled runtime configuration. After each ingress load balancer exists, add its destination-specific validation record—and the full-dev Sonar record—from dev owner state before cert-manager/HTTP-01 and workload acceptance. Bootstrap the five Sonar projects and blocking analysis token without logging credentials. Then prove NLB-backed TLS ingress, mTLS, secrets, admission, probes, telemetry, alerting, scaling, runtime security, audit jobs, code-quality gating, and bounded chaos in full dev before staging or production activation. Full production uses a new full-only Istio canary component; the economical native canary render stays unchanged.
6. **Immutable delivery and production canary**: make every required runnable quality gate blocking, preserve a single digest, implement dual-profile promotion, and prove a failing 10/25/50/100 production canary rolls back within five minutes.
7. **AKS DR**: verify the approved Azure values, plan/apply its independent foundation with Azure workload identity, an empty Key Vault, and a Terraform-owned Standard static ingress public IP; bootstrap its own ArgoCD against an activation-empty root, seed the four-name runtime-secret inventory through value-blind AWS/Azure OIDC transfer, copy the complete already-signed platform graph and the production service OCI graph to ACR without rebuilding, and only then activate the platform bound to that exact address and prove secret readiness, JWT parity, graph/digest equality, and independent reconciliation.
8. **Routing and game day**: create destination endpoint records first, keep the active-active switch false, complete the approved bounded outage game day, and publish availability/continuity evidence. Then establish exact-subject, TXT-record-scoped DNS-01 federation and prove that both production destinations hold trusted certificates for the common application hostname. Enabling production traffic remains a final separate human-gated Terraform change.

Every stage uses a separate reviewed PR and can be reverted without destroying or mutating the economical platform. A failure stops all dependent stages.

## Post-Design Constitution Check

The Phase 1 artifacts preserve all pre-research PASS results. The data model gives every cloud/state/resource exactly one owner; the contracts make cost, quota, baseline, rollback, immutable-digest, bootstrap, and DR evidence machine-checkable; and the quickstart omits apply and direct managed-cluster mutation. No complexity exception or constitutional waiver is required.

## Complexity Tracking

No constitutional violations or unjustified complexity exceptions are present. The additional centralized-egress root is required by the observed EIP quota and is isolated from workload state; the cross-repository delivery is inherent in the approved feature rather than an avoidable layering choice.

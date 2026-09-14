# Research: Full Multi-Cloud Platform Rollout

## Evidence Baseline

The following facts were verified read-only on 2026-08-24 and are inputs to the design, not implementation claims:

- AWS STS resolved account `916491575487` in `us-east-1`.
- EKS clusters `microtodosuite-dev` and `microtodosuite-demo-full` exist.
- Four Elastic IP addresses are allocated against the regional default quota of five. Three NAT gateways belong to the economical VPC and one belongs to `demo-full`.
- Four `m7i-flex.large` instances are running: two in the economical VPC and two in the `demo-full` VPC.
- Standard On-Demand quota is 16 vCPU and standard Spot quota is 32 vCPU. The current nodes consume 8 On-Demand vCPU.
- `m7i-flex.large` is the approved 2-vCPU/8-GiB bootstrap type already encoded in both foundations.
- Terraform `1.15.8`, AWS CLI `2.36.19`, kubectl `1.36.3`, and GitHub CLI `2.46.0` are installed. Azure CLI, Helm, standalone Kustomize, and kubeconform are not installed locally.
- Azure subscription, tenant, location, identity, and backend values could not be verified because Azure CLI is absent. They remain fail-closed implementation inputs and must be read from the approved account or existing CI configuration, never invented.
- Read-only Secrets Manager metadata shows `microtodosuite/prod/auth-api-secrets`, `microtodosuite/observability/alertmanager-slack-webhook`, and `microtodosuite/security/falcosidekick-slack-webhook` each have an `AWSCURRENT` version. No value was read. `microtodosuite/observability/grafana-admin` does not yet exist and is an intentional dev-owner addition in this feature.
- GitHub CLI is authenticated as `EstebanGZam`, but read-only secret metadata for the five service repositories shows none of `RELEASE_APP_ID`, `RELEASE_APP_KEY`, `GITOPS_PROMOTE_APP_ID`, or `GITOPS_PROMOTE_APP_KEY` exists yet. The current reusable workflows already expect those exact caller-secret names.
- The existing self-hosted SonarQube manifests are intentionally inactive, still use mutable `sonarqube:community`/`postgres:16-alpine` tags, and no checked repository exposes `SONAR_HOST_URL` or `SONAR_TOKEN` metadata. The earlier reusable-delivery decision requires one self-hosted server for both profiles, so this rollout must activate it rather than silently substitute SonarCloud.
- `microtodosuite.online` is the confirmed canonical domain. Live DNS delegates it to `dns1.registrar-servers.com` and `dns2.registrar-servers.com`, and account `916491575487` has no Route 53 hosted zone for it. The dev state still owns the legacy `microtodosuite.abrdns.com` Route 53 zone. Canonical-zone creation must therefore use a distinct opt-in resource address and a reviewed registrar delegation; an in-place rename would propose destructive replacement and is forbidden.
- A read-only `terraform output -json` attempt against `demo-full` did not complete and was terminated without changing state. No design claim depends on that command.

## Decision 1: Preserve the economical platform as an independent rollback target

**Decision**: Do not rename, move, import, repurpose, destroy, or share state with the economical environment. Do not change its three-NAT topology as a way to recover EIPs. Every full-profile stage begins and ends with an economical health and drift snapshot.

**Rationale**: The economical platform is the working production baseline and the constitution explicitly withholds authority to retire it. Reducing its NAT gateways would mutate the baseline and make a full-profile failure harder to isolate.

**Alternatives rejected**:

- Reuse the economical cluster for full dev or prod: violates dedicated full-profile isolation.
- Reconfigure the economical VPC to one NAT: saves EIPs but changes the only working baseline.
- Move economical resources into new state: introduces destructive ownership risk with no functional benefit.

## Decision 2: Map logical destinations without renaming physical staging

**Decision**: Use these destination identities:

| Logical destination | Physical cluster | Network | State key |
| --- | --- | --- | --- |
| economical dev/staging/prod | `microtodosuite-dev` | existing economical VPC | existing dev key, unchanged |
| full dev | `microtodosuite-full-dev` | `10.40.0.0/16` | `environments/full-dev/foundation/terraform.tfstate` |
| full staging | `microtodosuite-demo-full` | existing `10.20.0.0/16` | existing `environments/demo-full/foundation/terraform.tfstate` |
| full prod | `microtodosuite-full-prod` | `10.30.0.0/16` | `environments/full-prod/foundation/terraform.tfstate` |
| shared AWS egress | no workload cluster | `10.60.0.0/24` | `shared/egress/terraform.tfstate` |
| Azure DR | `microtodosuite-aks-dr` | `10.50.0.0/16`, subject to live Azure collision check | distinct Azure Blob key resolved from the approved backend |

**Rationale**: `demo-full` already owns the staging CIDR and resources. A logical GitOps name can identify full staging without forcing Terraform replacements. The new CIDRs do not overlap the observed AWS VPCs; implementation must additionally check all AWS VPCs, peering/TGW routes, and the real Azure VNet inventory before plan.

All three full AWS control planes and the planned AKS control plane initially use the same reviewed operator allowlist: `181.50.102.191/32`, `186.112.71.16/32`, `190.108.77.190/32`, and `200.3.193.225/32`. This makes the new roots operable from the already approved locations without broadening access; staging must retain exactly that set, and no public managed control plane may use `0.0.0.0/0`.

**Alternative rejected**: Rename `demo-full` resources to `full-staging`. EKS/VPC names are replacement-sensitive and the rename provides no functional value.

## Decision 3: Reuse the AWS backend coordinates but isolate every state key

**Decision**: Reuse the verified backend values from `aws/environments/dev/foundation/dev.s3.tfbackend`: bucket `microtodosuite-tfstate-916491575487-us-east-1-dev`, region `us-east-1`, KMS key ARN `arn:aws:kms:us-east-1:916491575487:key/30da1308-c2d0-4d3c-8df1-b1c2c937a177`, `encrypt = true`, and `use_lockfile = true`. Create a backend file per new AWS root with those exact values and a unique key. Never create another backend bucket or KMS key.

**Rationale**: The backend was already bootstrapped for this account. Unique keys preserve ownership while reusing the approved encrypted storage boundary.

**Alternative rejected**: A bucket per environment. It duplicates account-level backend resources and was explicitly disallowed.

## Decision 4: Use centralized outbound egress for new full dev and prod

**Decision**: Create one separately owned egress VPC using the one remaining EIP and one NAT gateway. Attach the full-dev and full-prod VPCs through one Transit Gateway. In each spoke, private worker subnets route `0.0.0.0/0` to TGW; public load-balancer subnets retain a local Internet Gateway route solely for the internet-facing Istio NLB. Workers remain private, `map_public_ip_on_launch` remains false, and the spoke creates no NAT/EIP. Give each spoke and the egress attachment a dedicated TGW route table; spoke CIDRs are blackholed or absent from one another's route tables. The egress state owns the VPC, NAT, TGW, egress attachment, and empty per-spoke route tables. Each spoke state owns only its attachment, association, default-to-egress route, return routes for its own CIDR in the egress TGW/VPC route tables, and its private VPC default routes. Terraform orders those routes before EKS node creation. `demo-full` keeps its current direct NAT.

**Rationale**: AWS documents centralized outbound internet access through Transit Gateway and NAT Gateway. This design meets the one-EIP limit without a quota request and leaves the economical and staging VPCs unchanged. See [AWS Transit Gateway centralized outbound routing](https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html).

**Availability trade-off**: One egress NAT and one selected egress AZ are a shared failure domain for full dev and prod. The stage gate must record and explicitly accept this reduction. Flow logs, route tests, NAT metrics, and an egress failure drill are required.

**Alternatives rejected**:

- One NAT per new VPC: requires two EIPs when only one is available.
- Request a quota increase: the approved adaptation explicitly avoids quota administration.
- NAT instances: add patching, failover, source/destination-check, and supply-chain duties without improving the required function.
- Route new spokes through the economical NATs: couples new failures and traffic to the protected baseline.

## Decision 5: Separate stable bootstrap capacity from bounded Spot elasticity

**Decision**: Keep `demo-full` at its existing two On-Demand `m7i-flex.large` bootstrap nodes. Full dev and full prod each start with one On-Demand `m7i-flex.large` bootstrap node. EBS CSI, Karpenter, AWS Load Balancer Controller IAM/discovery, and VPC CNI NetworkPolicy enforcement are opt-in module prerequisites whose default is false, which preserves the dev and pre-change demo plans. The enabled VPC CNI add-on configuration is exactly `jsonencode({ enableNetworkPolicy = "true" })`, with live acceptance of `aws-eks-nodeagent --enable-network-policy=true`. New roots enable the prerequisites at creation; staging enables them later through its own reviewed plan without changing its existing nodes, NAT, VPC, state, or access CIDRs. Karpenter `1.14.1` runs on bootstrap capacity and provisions Spot-only 2-vCPU/8-GiB nodes from a reviewed diversified allowlist. Each cluster has an independent NodePool CPU/memory ceiling; the aggregate Spot ceiling must remain at or below 24 vCPU, leaving at least 8 vCPU of the observed 32-vCPU quota as failure/replacement headroom.

**Rationale**: The two new bootstrap nodes raise On-Demand usage from 8 to 12 vCPU, below the 16-vCPU quota. Spot uses a separate 32-vCPU quota and avoids the account's On-Demand Free Tier eligibility failure. Per-cluster NodePools prevent one environment from consuming another's budget. Karpenter remains a GitOps-owned controller; Terraform creates only its per-cluster IAM and discovery inputs.

**Availability trade-off**: Full dev and prod begin with one stable node each and rely on interruptible capacity for the complete stack. Pod disruption budgets, topology spread, interruption handling, consolidation bounds, and live eviction recovery are acceptance requirements. No claim of multi-node bootstrap HA is made.

**Alternatives rejected**:

- Larger On-Demand nodes: the account rejected non-Free-Tier-eligible On-Demand types.
- Two new two-node On-Demand groups: consumes the entire On-Demand quota and leaves no replacement headroom.
- Unlimited Karpenter pools: violates quota and environment isolation requirements.

## Decision 6: Preserve singleton ownership and extend trust only from dev state

**Decision**: All new AWS roots set `create_shared_resources = false` and use data sources for the five neutral service ECR repositories, GitHub Actions OIDC provider, publisher role, Kyverno verifier role, shared notification secret containers/readers, environment JWT secret containers, and the canonical public hosted zone after it exists. Dev state also creates exactly one new `microtodosuite/platform` ECR repository, one exact-workflow platform-mirror role, and—behind a separate default-off switch—exactly one `microtodosuite.online` Route 53 zone at a new resource address. The switch stays off through the foundational dev `0/0/0` compatibility gate. Enabling it later must create the canonical zone without renaming, replacing, or destroying the dev-owned legacy zone. Neither repository nor zone work transfers ownership to a consumer. Cluster-specific EKS OIDC providers, node roles, CNI/EBS/Karpenter roles, and environment JWT reader roles remain per-cluster resources. A consumer reader role has a cluster-qualified name, trusts only that cluster's exact External Secrets ServiceAccount subject, and can read only the dev-owned secret for its one logical environment.

After each new EKS foundation exists, its OIDC issuer ARN and URL are passed to the dev owner root. Dev state alone extends the shared Kyverno, observability, and security IRSA roles with a separate exact issuer/audience/service-account statement; the GitHub publisher role keeps only its GitHub OIDC trust. Consumer states never edit shared roles. A compatibility branch must preserve the current single-issuer JSON byte-for-byte until additional issuers are intentionally supplied, and the dev remote plan must first be `0/0/0`.

**Rationale**: Current shared IRSA role trust names only the economical cluster issuer. Looking up the role prevents duplication but does not make it usable by another issuer. Multi-issuer trust is therefore an owner-state change, not a consumer-state resource.

**Alternative rejected**: Create identically purposed per-cluster Kyverno roles. The approved ownership contract calls these account-level singletons, and duplicate global names would fail planning.

## Decision 7: Make topology a cluster-registration dimension

**Decision**: Move service overlay composition to `apps/<service>/profiles/<profile>/overlays/<env>`. The ApplicationSet activation record contains `env`, `profile`, and `server`; its path renders the selected profile and environment. Economical registration lists three environments with `profile: economical`. Each full root lists exactly one environment with `profile: full`. Local keeps its own explicit profile. The current native `strategy-canary` component remains the economical production strategy and retains a golden render. A separate `strategy-canary-full` component owns Istio traffic routing and is referenced only by full AWS production.

**Rationale**: The current global `apps/<service>/topology/kustomization.yaml` selects economical topology for every destination, so economical and full cannot coexist. Making profile registration data preserves shared bases and immutable digests while allowing concurrent renderings.

**Alternative rejected**: Flip the global topology file during promotion. It would change both profiles together and could disrupt the working baseline.

## Decision 8: Keep one independent ArgoCD per cluster

**Decision**: Each full root targets `https://kubernetes.default.svc`, activates only its owned environment, and reconciles `main`. Bootstrap is allowed only after that root is merged and consists of exactly: server-side apply of the vendored `bootstrap/argocd` render, then apply of the tracked root Application. The bootstrap helper records context, account/subscription, cluster UID, reviewed Git SHA, manifest checksum, commands, and results.

**Rationale**: In-cluster reconciliation avoids a central control-plane dependency during a cloud or cluster outage and matches the constitutional bootstrap exception.

**Alternative rejected**: Register all clusters into the economical ArgoCD. That reconciler would become a cross-environment and cross-cloud failure domain.

## Decision 9: Use supported Kubernetes and pinned platform versions

**Decision**: Keep EKS and AKS on Kubernetes `1.35`. Preserve existing GitOps pins unless a compatibility test requires a dedicated reviewed upgrade. Add new capabilities with exact versions and committed source/checksum metadata:

| Capability | Version decision |
| --- | --- |
| EKS | `1.35`; AWS provider `6.58.0`; EKS module `21.24.2`; existing pinned EKS add-ons and AL2023 AMI release |
| Ephemeral secret generation | Random provider `3.9.0`; `ephemeral "random_password"` into AWS provider `secret_string_wo` with an explicit persisted rotation counter |
| AKS | `1.35`; AzureRM `5.0.1`; direct `azurerm_kubernetes_cluster` in a local module; Azure CNI Overlay with the Cilium data plane/policy engine |
| ArgoCD | existing vendored `3.5.0` |
| Kustomize / kubeconform | `5.8.1` / `0.7.0` |
| AWS Load Balancer Controller | `3.5.0`, full EKS roots only |
| Istio / Kiali | `1.30.3` / `2.31.0` |
| Karpenter | `1.14.1` |
| ECK | `3.5.0` |
| Chaos Mesh | `2.8.4` |
| OpenCost chart | `2.5.29` |
| Shared code-quality tooling | SonarQube Community Build `26.8.0.126808-community`; PostgreSQL `16.15-alpine3.24`; exact multi-arch manifest digests resolved into the toolchain lock before render |
| Argo Rollouts | existing vendored `1.9.1` |
| cert-manager / External Secrets / KEDA / Kyverno | existing vendored `1.21.0` / `2.9.0` / `2.20.1` / `1.18.2` |
| Falco / kube-bench / kube-hunter | existing `0.44.1` / `0.16.0` / `0.6.8` |
| Prometheus operator / Grafana / Jaeger | existing `0.18.0` / `13.2.0` / `2.20.0` |

AWS lists EKS 1.35 in standard support, and Microsoft lists AKS 1.35 as GA; using one minor reduces manifest and CRD variance. Azure recommends Azure CNI Overlay for most AKS deployments and Cilium for policy enforcement, so the implementation preflight selects non-overlapping pod/service ranges from the real network inventory instead of embedding an unverified range. Istio 1.30 supports Kubernetes 1.32-1.36. AWS Load Balancer Controller 3.5.0 supports Kubernetes 1.22+ and recommends scoped IRSA. Random 3.9.0 exposes the supported ephemeral password resource used with Terraform/AWS write-only arguments. The official SonarQube image currently publishes the exact Community Build tag, and PostgreSQL 16.15 is the current supported 16.x patch. Sources: [EKS versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html), [AKS versions](https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions), [AKS pod-network planning](https://learn.microsoft.com/en-us/azure/aks/plan-pod-networking), [AKS NetworkPolicy](https://learn.microsoft.com/en-us/azure/aks/use-network-policies), [Istio supported releases](https://istio.io/latest/docs/releases/supported-releases/), [AWS Load Balancer Controller installation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/), [Random ephemeral password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/ephemeral-resources/password), [SonarQube official image](https://hub.docker.com/_/sonarqube/), [PostgreSQL 16.15](https://www.postgresql.org/docs/16/release-16-15.html), [Kustomize releases](https://github.com/kubernetes-sigs/kustomize/releases), and [kubeconform releases](https://github.com/yannh/kubeconform/releases).

**Alternatives rejected**:

- Floating `latest`, unpinned install scripts, or unverified Helm fetches: break reproducibility and supply-chain evidence.
- The deprecated monolithic Azure AKS Terraform module: direct AzureRM resources make ownership and upgrades explicit.
- Upgrade existing add-ons opportunistically: increases rollback scope unrelated to this feature.

## Decision 10: Build the full platform in dependency waves

**Decision**: Activate and accept capabilities in this order:

1. cluster primitives, storage CSI, Karpenter/AWS Load Balancer Controller IAM, namespaces, quotas, RBAC, and default-deny policy;
2. cert-manager, External Secrets, External Secret-backed ArgoCD Notifications, Kyverno, and Argo Rollouts;
3. AWS Load Balancer Controller 3.5.0 on EKS, followed by Istio base/control plane/ingress and Kiali, with namespace injection/revision labels and strict mTLS;
4. the single shared full-dev SonarQube/PostgreSQL tooling instance, encrypted persistent volumes, restricted Istio endpoint, and blocking quality-gate bootstrap;
5. Prometheus, Alertmanager, Grafana, OpenTelemetry service instrumentation, and Jaeger;
6. ECK operator, single-node resource-bounded Elasticsearch/Kibana/Logstash, and Filebeat DaemonSet;
7. KEDA, Falco, kube-bench, kube-hunter, OpenCost, and Chaos Mesh;
8. controlled non-secret runtime ConfigMaps/feature-toggle declarations, business workloads, and progressive-delivery objects.

Each capability has requests/limits, PodDisruptionBudget where meaningful, NetworkPolicy, resource quota impact, storage/retention limits, success test, failure-mode test, and rollback.

**Rationale**: Controllers and CRDs must be healthy before dependent custom resources appear. Resource-bounded single replicas preserve function within quota but intentionally reduce HA; that reduction is recorded per stage. ECK is the supported operator for Elasticsearch/Kibana/Beats on EKS and AKS; OpenCost reuses Prometheus. Sources: [Elastic Cloud on Kubernetes](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-overview.html/) and [OpenCost Helm installation](https://opencost.io/docs/installation/helm/).

The one full-dev SonarQube instance is an intentional shared CI failure domain: if it is unhealthy, releases block rather than bypass the quality gate. It uses encrypted retained storage, a dedicated elastic node contract, forced authentication, immediate default-admin rotation, backup/recovery evidence, and no anonymous project access. Hosting it in full-dev honors the existing one-server decision without adding a heavy tenant to or changing the protected economical render.

**Alternative rejected**: Install every controller in one ArgoCD revision. A CRD/controller failure would be hard to isolate and could exhaust bootstrap nodes.

## Decision 11: Use stable Istio ingress plus scoped ACME validation

**Decision**: Full clusters expose only the Istio ingress gateway. On full EKS, GitOps installs AWS Load Balancer Controller 3.5.0 with Terraform-owned, VPC/cluster-scoped IRSA and its Service integration provisions the Network Load Balancer. The Azure DR state creates a Standard, static public IP with a unique Azure DNS label in a dedicated ingress resource group, grants the AKS cluster identity Network Contributor only on that resource group, and outputs the public-IP name, resource group, address, and provider FQDN. The AKS Istio Service selects that exact address with `service.beta.kubernetes.io/azure-pip-name` and `service.beta.kubernetes.io/azure-load-balancer-resource-group`; neither the Service nor a script creates or owns the address.

After each load balancer exists, dev owner state creates CNAME validation records for `full-dev.microtodosuite.online`, `full-staging.microtodosuite.online`, `full-prod-aws.microtodosuite.online`, or `full-prod-azure.microtodosuite.online` against the observed AWS NLB hostname or Terraform output Azure public-IP FQDN. Before the first record or HTTP-01 challenge is accepted, the registrar must delegate `microtodosuite.online` to the exact four name servers output by the newly created Route 53 zone and public DNS must return those same authorities. Existing registrar-hosted records must be inventoried before delegation so no unrelated record is silently lost. cert-manager obtains each destination certificate through HTTP-01 and manages the AWS controller webhook certificate to avoid ArgoCD certificate drift.

Before the final shared production record can be planned, the AWS-production and AKS cert-manager installations must each hold a trusted certificate for `app.microtodosuite.online`. They obtain those certificates sequentially through Route 53 DNS-01 while `enable_active_active` remains false, so issuance does not require the shared application record to exist. Dev state owns the one AKS-issuer IAM OIDC provider and two distinct DNS-solver roles. Each trust policy permits only the exact production cert-manager service-account subject with audience `sts.amazonaws.com`; each permissions policy is limited to the hosted zone and the `_acme-challenge.app.microtodosuite.online` TXT record plus the minimum change-status/read operations. EKS uses IRSA. AKS mounts a short-lived projected service-account token for its public OIDC issuer and assumes its dedicated AWS role; no access key or cross-cloud long-lived secret exists. Certificate readiness is verified on both destinations before the final Route 53 plan.

All internal namespaces use `PeerAuthentication` STRICT, AuthorizationPolicy allowlists, DestinationRule connection pools/outlier detection, and VirtualService retries/timeouts. Kiali reads mesh telemetry but has no unauthenticated public ingress.

**Rationale**: Stable provider targets prevent ingress recreation from silently changing DNS. HTTP-01 keeps ordinary destination validation simple. Narrow DNS-01 federation solves the shared-hostname certificate problem before traffic is enabled without a maintained AWS credential in Azure or a temporary production routing record. Microsoft recommends named static public-IP annotations for AKS LoadBalancer Services; AKS exposes a public OIDC issuer that another cloud identity platform can validate, AWS IAM accepts standards-compliant public OIDC providers, and cert-manager supports Route 53 DNS-01 through `AssumeRoleWithWebIdentity`. Sources: [AKS static public IP](https://learn.microsoft.com/en-us/azure/aks/static-ip), [AKS OIDC issuer](https://learn.microsoft.com/en-us/azure/aks/use-oidc-issuer), [AWS IAM OIDC providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html), and [cert-manager Route 53 DNS-01](https://cert-manager.io/docs/configuration/acme/dns01/route53/).

**Alternative rejected**: Public service ingress per workload. It expands attack surface and bypasses mesh traffic controls.

## Decision 12: Keep Route 53 under dev ownership and traffic disabled by default

**Decision**: Dev state remains the only owner of the retained legacy `microtodosuite.abrdns.com` zone and becomes the only Terraform owner of a separately addressed `microtodosuite.online` zone, the four canonical destination-specific validation records, the shared-tooling record `sonar-full-dev.microtodosuite.online`, health checks, production DNS-solver identities, and latency routing. The old domain receives no new record or certificate and is not renamed or destroyed by this feature. Destination load-balancer targets are explicit reviewed inputs. `enable_active_active = false` is the default and produces no live shared production-routing record. After registrar delegation and both production endpoints' common-hostname certificates are verified, all gates pass, and a separate human approves the exact plan, the dev owner plan may add two health-evaluated latency CNAME records at `app.microtodosuite.online` for AWS production and Azure DR.

**Rationale**: This prevents duplicate hosted zones and makes the traffic switch a small, reviewable, reversible state change.

**Alternative rejected**: external-dns in every cluster. Multiple controllers would compete for the same zone and violate Terraform's declared Route 53 ownership.

## Decision 13: Build once and mirror complete signed OCI graphs

**Decision**: Shared CI remains the single build point. It publishes and signs one ECR digest. The DR promotion job authenticates to AWS and Azure with OIDC, copies the image manifest, layers, signature, attestation, and SBOM graph to ACR without rebuilding, verifies Cosign in ACR, and fails unless source and destination manifest digests match. AKS manifests use the ACR repository at that same digest.

Every GitOps-installed third-party platform image is independently enumerated in the committed toolchain lock. Before EKS activation, a dedicated exact-workflow OIDC role copies each upstream digest into `microtodosuite/platform`, scans it, records source and mirrored digests, and applies a keyless Cosign signature bound to the approved mirror workflow. Kyverno signature policy covers all business and GitOps-installed platform namespaces and accepts only the service CI identity or this platform-mirror identity; EKS-managed system add-ons are outside that namespaced admission scope and remain version-pinned by Terraform. After ACR exists and before AKS capability activation, the same workflow copies the complete already-signed platform OCI graph from ECR to ACR without rebuilding and verifies manifest/signature equality. A missing image, mutable reference, signature, attestation, or digest equality blocks activation.

**Rationale**: AKS should not depend on an expiring ECR image-pull secret or AWS availability. An ACR mirror gives cloud-local pulls while preserving artifact identity. The dedicated platform repository makes the signature policy enforceable for upstream images without mixing them into the five service repositories. Azure workload identity grants AKS pull access; GitHub federated identity grants only the mirror job's required ACR push scope.

**Alternatives rejected**:

- Rebuild in Azure: violates build-once provenance.
- Static Docker credentials or personal `GH_TOKEN`: violates short-lived identity requirements.
- Pull directly from private ECR in AKS: requires credential rotation and makes DR dependent on AWS registry reachability.

## Decision 14: Seed Azure runtime secrets without Terraform or Git custody

**Decision**: Terraform creates the Azure Key Vault, workload identities, and access boundaries but no `azurerm_key_vault_secret` value resource. Dev state remains the AWS owner of the production JWT, Alertmanager/Falco notification secret containers, and a new full-profile Grafana-admin secret container populated with Terraform `ephemeral "random_password"` values passed only to AWS Secrets Manager `secret_string_wo`, paired with an explicit non-secret `secret_string_wo_version` rotation counter. Terraform 1.15.8 re-evaluates the ephemeral value during the approved saved-plan apply and does not persist it in the plan or state; a version change is the only rotation trigger. A dedicated reusable secret-seeding workflow uses short-lived GitHub OIDC sessions to read exactly those four approved AWS Secrets Manager ARNs and write their values to four exact Azure Key Vault names. The production JWT is copied unchanged so a token remains cryptographically valid after a request moves between AWS and Azure; the operational values keep the same approved notification/admin contract. This follows Terraform's documented [ephemeral/write-only resource pattern](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/ephemeral).

Separately, dev state owns `microtodosuite/tooling/sonarqube-db` and `microtodosuite/tooling/sonarqube-admin`, both populated by the same ephemeral-random/write-only/version-counter pattern and readable only by the exact full-dev SonarQube External Secrets service account. They are not part of the Azure four-secret transfer. A one-time, value-blind Sonar bootstrap keeps the mounted/fetched administrator value and generated analysis token only in process, changes the default administrator credential immediately, creates the five fixed project keys plus an analysis-only service identity, streams the generated token directly into the selected-repository organization secret `SONAR_TOKEN`, and stores `https://sonar-full-dev.microtodosuite.online` as `SONAR_HOST_URL`. The server and PostgreSQL run only in full-dev as shared CI tooling; economical renders and AKS do not host copies.

| Purpose | AWS Secrets Manager source | Azure Key Vault target |
| --- | --- | --- |
| Production JWT | `microtodosuite/prod/auth-api-secrets` | `microtodosuite-prod-auth-api-secrets` |
| Alertmanager and ArgoCD notifications | `microtodosuite/observability/alertmanager-slack-webhook` | `microtodosuite-observability-alertmanager-slack-webhook` |
| Falcosidekick notifications | `microtodosuite/security/falcosidekick-slack-webhook` | `microtodosuite-security-falcosidekick-slack-webhook` |
| Full-profile Grafana administrator | `microtodosuite/observability/grafana-admin` | `microtodosuite-observability-grafana-admin` |

The AWS read role is separate from the publisher, trusts only the approved repository/environment and pinned reusable workflow identity, and can read only the four source ARNs. The Azure identity has only get/set data actions on the dedicated DR vault, which must contain exactly the four approved names. The workflow disables shell tracing, masks fetched values before any other operation, emits only names, versions, and an in-process equality boolean, keeps values only in process memory or a mode-`0600` ephemeral file when a CLI requires one, and removes that file on every exit. It never emits a value-derived digest. Tests reject command tracing, workflow artifacts/caches, Terraform secret resources, output values, and evidence containing secret material. Rotation reruns the same reviewed workflow and waits for External Secrets convergence before promotion.

The external inventory governs every application credential and operator-supplied runtime, notification, or administrator value. Kubernetes-native Secrets are limited to an explicit allowlist of controller-owned TLS, service-account, and internal bootstrap material produced and rotated by cert-manager, Istio, ECK, ArgoCD, or Kubernetes itself; tests record each generator and consumer and reject ad hoc password generators or exporting those values to Git, Terraform, logs, or evidence.

**Rationale**: Active-active authentication fails if each cloud signs or verifies JWTs with a different value. OIDC transfer preserves the one production value without storing plaintext in Terraform state, GitHub repository variables, artifacts, or Git. The same narrow mechanism eliminates in-cluster generated operational credentials from the full profile while leaving economical behavior unchanged.

**Alternative rejected**: Independent per-cloud JWT generation. It breaks tokens whenever latency routing changes destinations. Terraform-managed Key Vault secret values and manually copied credentials are also rejected because they create durable secret custody in state or operator history.

## Decision 15: Use GitHub Apps for repository writes and OIDC for cloud writes

**Decision**: Preserve the shared release workflow's GitHub App installation-token pattern and exact caller-secret names. If the Apps are absent, create two organization-owned Apps through reviewed manifests: a release App with metadata read plus contents/issues/pull-requests write installed only on the five service repositories, and a promotion App with metadata read plus contents/pull-requests write installed only on `microservice-app-gitops`. Store `RELEASE_APP_ID`/`RELEASE_APP_KEY` and `GITOPS_PROMOTE_APP_ID`/`GITOPS_PROMOTE_APP_KEY` as organization Actions secrets restricted to the five caller repositories. Never print or commit a private key; upload the one-time downloaded key from a mode-`0600` temporary file, verify secret metadata only, remove the file, and document rotation. Do not add a PAT. GitHub Actions assumes AWS and Azure roles through OIDC. Pin reusable workflows and third-party Actions by full commit SHA.

**Rationale**: The repository already implements the correct replacement for a manually maintained `GH_TOKEN`: short-lived GitHub App tokens. Two Apps keep release writes separate from cross-repository GitOps writes, while selected-repository organization secrets avoid five independent key copies. App creation/installation is a fail-closed implementation action: insufficient organization authority blocks the stage rather than falling back to a personal token.

## Decision 16: Promote profile and destination explicitly

**Decision**: The reusable promotion contract accepts `environment`, `profile`, and `destination`. One release can open coordinated GitOps PRs for economical and full dev without changing a global topology selector. Dev and staging use Deployments/rolling updates. Economical production retains its current native replica-based canary. AWS full prod alone uses the full-only Argo Rollouts component with Istio traffic routing at 10/25/50/100 and two fail-closed AnalysisTemplates: five-minute error-rate and p99 latency. AKS DR receives the already validated digest through rolling update.

**Rationale**: Environment alone no longer uniquely identifies a rendering. Explicit dimensions prevent a promotion intended for one platform from mutating the other.

**Alternative rejected**: Keep `scripts/bump-image.sh <service> <environment>` unchanged. It cannot select between concurrent economical and full overlays.

## Decision 17: Treat test and evidence actions as GitOps state

**Decision**: Chaos experiments, unsigned-image denial attempts, Falco trigger pods, audit jobs, and scaling load generators are checked-in, disabled-by-default manifests activated through reviewed Git commits and removed by Git revert. Verification scripts are read-only: `get`, `logs`, `describe`, HTTP/Prometheus queries, and evidence serialization. They must not run `kubectl apply/create/patch/delete/scale` after bootstrap.

**Rationale**: Existing skeleton scripts directly create audit jobs and must be corrected before use. A test is not exempt from the GitOps-only rule.

**Alternative rejected**: Treat imperative test resources as harmless. They create unmanaged desired state and make evidence irreproducible.

## Decision 18: Keep availability and data continuity separate

**Decision**: The game day measures endpoint availability, reconciliation independence, release identity, DNS convergence, and observed recovery time. It separately records Redis messages, todos, and users created before/during failover and reports every lost or divergent item. No RPO or durability guarantee is declared.

**Rationale**: All three data paths are explicitly non-durable or unreplicated in current scope. Active-active routing can prove stateless availability but cannot prove data continuity.

**Alternative rejected**: Add cross-cloud data replication within this feature. It changes application architecture and exceeds the approved scope.

## Decision 19: Make Azure discovery a hard implementation preflight

**Decision**: Before creating Azure files containing real values or running a plan, install a checksum-pinned Azure CLI, authenticate interactively or through the approved operator mechanism, run `az account show`, compare the subscription with `AZURE_SUBSCRIPTION_ID_COLONIA`, inspect existing regions/VNets/backend storage, and record only non-secret coordinates. Stop if the identity, location, address space, provider registration, quotas, or state backend cannot be verified.

**Rationale**: Azure facts are environment state, not design choices. Deferring their discovery to a fail-closed preflight is more accurate than inventing values in a plan.

**Alternative rejected**: Copy legacy Azure defaults without account verification. The repository's legacy roots are historical evidence, not proof of the current approved target.

## Decision 20: Use one machine-checkable stage-gate bundle

**Decision**: Each stage writes a JSON manifest conforming to `contracts/full-profile-evidence.schema.json` and links immutable raw artifacts: baseline, identities, plans, cost, quotas, approvals, Git SHAs, desired/live health, success/failure tests, rollback, and post-stage baseline. Missing, stale, or failed evidence makes the stage `blocked`; a summary cannot override it.

**Rationale**: The feature has many repositories and destinations. A stable evidence contract prevents configuration from being mistaken for a verified outcome.

## Decision 21: Complete full-profile observability through per-cloud roots

**Decision**: T085 adds full-profile Kustomize roots at `infrastructure/profiles/full/{prometheus,grafana,jaeger}/{aws,azure}/`. Each root takes the economical `infrastructure/<component>/` root as its base and patches only what the full profile changes, so the economical render stays unchanged and a full cluster's activation list (T091) names the root for its cloud.

- **Persistence.** Prometheus, Alertmanager, and Grafana keep their data on encrypted volumes of the destination cloud. EKS uses the GitOps-owned `gp3` StorageClass in `infrastructure/ebs-csi-driver/`, which sets `encrypted: "true"`. AKS uses the built-in `managed-csi` Azure Disk class; Azure encrypts every managed disk at rest with platform-managed keys. Alertmanager, which keeps silences and its notification log only in memory in the economical profile, gets a volume. Every component keeps one replica, per Decision 10.
- **Traces.** Jaeger stores spans in the ECK-managed Elasticsearch `platform` instead of embedded Badger, as evolution plan section 17 describes the full profile, so it needs no volume of its own. Each Jaeger index has one shard and no replica, because Elasticsearch runs one node. Jaeger authenticates as the dedicated file-realm user `jaeger` with the role `jaeger_writer`: cluster privileges `monitor` and `manage_index_templates`, and `create_index`, `write`, `read`, `view_index_metadata`, and `delete_index` on the `jaeger-span-*`, `jaeger-service-*`, `jaeger-dependencies-*`, and `jaeger-sampling-*` indices. An External Secrets Password generator creates the password in the cluster, and ECK hashes it from a `kubernetes.io/basic-auth` Secret carrying `username`, `password`, and `roles`; that password is controller-owned internal bootstrap material under FR-026, never committed and never an operator-supplied value.
  - ECK reads file-realm and role Secrets only from the Elasticsearch resource's namespace, so the generator, the user and role Secrets, and a Role that lets one `observability` ServiceAccount read only that user Secret and ECK's public HTTP CA Secret live in `infrastructure/elasticsearch/`, whose owner reviews the change. The full Jaeger roots copy the password and the CA into `observability` through a SecretStore on the External Secrets Kubernetes provider.
  - A daily CronJob in `observability` runs `jaeger-es-index-cleaner` 2.20.0, pinned by digest and added to the toolchain lock, and deletes Jaeger indices older than 3 days, the economical profile's retention. Jaeger 2.20.0 does not expire indices by itself.
  - Grafana links a trace to the logs Elasticsearch holds for it, through an Elasticsearch datasource with its own read-only user, delivered separately from the Jaeger backend. The file-realm user `grafana` has the role `grafana_logs_reader`: cluster `monitor` and `read` plus `view_index_metadata` on `filebeat-*`, the privileges Grafana's Elasticsearch data source documentation lists, over the indices Filebeat 9.4.4 writes by default (`filebeat-%{[agent.version]}`). Its user, role, and read-only Role follow the Jaeger pattern in `infrastructure/elasticsearch/`, and the full Grafana roots copy its password and the CA through their own SecretStore, `elasticsearch-grafana`, so the Jaeger and Grafana Applications never share a resource. The datasource `elasticsearch-logs` reads `filebeat-*` over TLS with both values expanded from mounted files (`$__file{...}`), and the Jaeger datasource's `tracesToLogsV2` targets it with `filterByTraceID`, which Grafana 13.2.0 turns into the phrase query `"${__span.traceId}"`. The full roots drop the Loki datasource, because the full profile sends logs to Elasticsearch. A trace finds its logs only for services that print the trace ID in their log lines; auth-api and users-api do today.
- **Rules.** Beside the existing error-rate alert, both full Prometheus roots add one small set of alerts, chosen by the maintainer as one alert per signal source. Each carries a `workload` label naming the affected object, which the existing Slack route groups and titles by:
  - p99 latency: `WorkloadHighP99Latency` when `workload:http_request_duration_seconds:p99_5m{revision="stable"}` stays above 2 seconds for 5 minutes, the canary gate's threshold;
  - scaling: `KedaScaledObjectErrors` when `keda_scaled_object_errors_total` keeps increasing for 10 minutes;
  - platform: `ArgoCdApplicationUnhealthy` (`argocd_app_info` health `Degraded` or `Missing` for 15 minutes), `ArgoCdApplicationOutOfSync` (`OutOfSync` for 30 minutes), `ExternalSecretNotReady` (`externalsecret_status_condition{condition="Ready",status="False"}` for 15 minutes), `CertificateNotReady` (`certmanager_certificate_ready_status{condition="False"}` for 15 minutes), and `CertificateExpiresSoon` (`certmanager_certificate_expiration_timestamp_seconds` less than 14 days away for 1 hour);
  - security: `KyvernoAdmissionDenied` when `kyverno_admission_requests_total{request_allowed="false"}` increases, and `FalcosidekickSlackDeliveryFailing` when `falcosecurity_falcosidekick_outputs_total{destination="slack",status="error"}` increases. Falco events already reach Slack through falcosidekick (spec 008) and are not alerted on twice; Trivy's alert already exists.

  Prometheus scrapes the sources through ServiceMonitors for `keda/keda-operator` (`metrics`), `argocd/argocd-metrics` (`metrics`), `cert-manager/cert-manager` (`http-metrics`), `kyverno/kyverno-svc-metrics` (`metrics-port`), and `security/falcosidekick` (`http`, `/metrics`), and a PodMonitor for the External Secrets controller (`metrics`), whose bundle ships no metrics Service. Metric names, labels, and label values come from the pinned upstream sources: KEDA 2.20.1 `pkg/metricscollector/prommetrics.go`, Argo CD 3.5.0 `controller/metrics/metrics.go`, External Secrets 2.9.0 `pkg/controllers/externalsecret/esmetrics/esmetrics.go` and `pkg/controllers/metrics/labels.go`, cert-manager 1.21.0 `internal/collectors/certificate_collector.go`, Kyverno 1.18.2 `pkg/metrics/admission.go`, and falcosidekick 2.34.1 `stats_prometheus.go` and `outputs/constants.go`.
- **Notifications.** Alerts keep the External Secret-backed Slack route and carry the cluster and the environment as Prometheus external labels, so each notification identifies its destination (FR-022, FR-030). Prometheus adds external labels to every alert it sends to Alertmanager. The values differ per cluster, so, as the maintainer chose, each full destination gets its own root at `infrastructure/profiles/full/prometheus/destinations/<destination>/`, based on its cloud's root, and its cluster registration names that path, the way business services use `profiles/full/overlays/<environment>/`. `cluster` is the registration's physical cluster name (`microtodosuite-full-dev`, `microtodosuite-demo-full`, `microtodosuite-full-prod`) and `environment` is `dev`, `staging`, or `prod`. A Component included by both cloud roots prefixes the Slack title with `[<environment> <cluster>]`. The AKS destination root follows once `clusters/aks-dr/` exists (T129).

**Rationale**: The economical roots are the protected rollback target (Decision 1); full-profile differences belong in separate roots rather than in patches to them. The roots sit outside the economical directories because Kustomize rejects a base directory that contains the root using it. Storage classes are the one persistence input that differs by cloud, and both clouds encrypt through their class without a per-cluster key value in Git.

**Alternatives rejected**:

- Patch storage, rules, or Jaeger storage into the economical roots: changes the economical render (FR-002).
- Authenticate Jaeger as the `elastic` superuser: breaks least privilege (FR-036).
- Roll indices over through an ILM policy (`rotation.auto_rollover`): the policy must exist before Jaeger starts, which needs an imperative Elasticsearch API call; the maintainer chose the index cleaner.
- Keep Badger in the full profile: evolution plan section 17 names embedded storage with short retention as the economical substitution.

## Decision 22: Harden admission and runtime security in four slices

**Decision**: T088 is delivered in four slices, each with its own failing test in `tests/platform/security-hardening.bats`. The maintainer chose the order 1, 2, 4, then 3, and a partial third slice (see below):

1. **Service CI signature identity.** `verify-approved-release-signatures` accepts the service CI's keyless identity through an anchored `subjectRegExp` limited to `https://github.com/MicroTodoSuite/.github/.github/workflows/ci.yml@` followed by a 40-character commit SHA, and keeps the exact GitHub issuer and, for each of the five services, its `githubWorkflowRepository`, `githubWorkflowRef: refs/heads/main`, and `githubWorkflowTrigger: push`. Fulcio puts a GitHub job's `job_workflow_ref` in the certificate SAN, so the SHA in an accepted identity is the one each service's reviewed `main` pins. The exact pin it replaces, `ci.yml@5c4e133fc528ef6ff596d146150321ca94760721`, already rejects every image the five services now sign through a newer `.github` revision, and would reject each later one.
2. **Read-only evidence.** `scripts/managed/verify-security.sh` stops creating Jobs and running commands in business pods. kube-bench, kube-hunter, and Falco triggers become checked-in manifests under `infrastructure/{kube-bench,kube-hunter,falco}/triggers/` that stay out of every parent kustomization until a reviewed commit adds them and a revert removes them (Decision 17). The kube-bench and kube-hunter triggers are Jobs with exactly their CronJob's job spec. The Falco trigger is a Job in `security` that runs `find /tmp -name id_rsa` from the already pinned kube-bench image (Alpine, with a real `find` binary) as a non-root user, which the stable Falco 0.44.1 rule "Search Private Keys or Passwords" (rules 5.1.0, priority WARNING) reports without a terminal or a shell in any business pod. The collector only reads: the latest audit Job's logs and the Falco pods' logs, reporting BLOCKED with the trigger path to activate when no run exists. The imperative-mutation policy test also catches `exec` and mutations behind shell wrappers such as `kube()`, which also flags the `kube run` Prometheus query in `scripts/managed/verify-observability.sh`; that query moves to a local `kubectl port-forward`, which changes no cluster state and, unlike the API server proxy, is not blocked by Prometheus's NetworkPolicy.
3. **Full-profile admission.** Digest and signature policies cover business and GitOps-installed platform namespaces, accept only the service CI identity or the platform-mirror workflow identity, and leave Terraform-managed EKS system add-ons outside their namespaced scope, with unsigned, unmirrored, mutable, and wrong-identity failure fixtures checked by the pinned Kyverno CLI wherever offline evaluation is possible.
   - Delivered partially, after slice 4: the immutable-digest policy over the platform namespaces and the fixtures the Kyverno CLI can evaluate offline. The mirror repository and the platform-mirror signature identity wait for others' decisions: the toolchain lock still names the mirror repository in the retired account `916491575487` (the full-profile account amendment), and `mirror-platform-images.yml` has no caller yet, so whether it signs as a dispatched workflow or as a called one, and therefore its certificate identity, is undecided (T082, T061). Kyverno's webhook excludes `kube-system` and `kyverno`, so the GitOps-installed components there (AWS Load Balancer Controller, Karpenter) stay outside admission.
   - The partial delivery is its own root, `infrastructure/profiles/full/kyverno/aws`, with `infrastructure/kyverno` as its base, so the economical cluster's policies do not change and the signature policy and the verifier's IRSA stay identical (maintainer decision). Its `require-immutable-images` rule matches `microtodo-*` plus every namespace a GitOps infrastructure root renders: today `argo-rollouts`, `cert-manager`, `chaos-mesh`, `elastic-system`, `elasticsearch`, `external-secrets`, `filebeat`, `istio-system`, `keda`, `kiali`, `kibana`, `logstash`, `observability`, `opencost`, `redis`, `security`, and `sonarqube`. The test derives that set from the renders, so a new root cannot stay outside the rule unnoticed. Three namespaces stay out: `kube-system`, the default namespace of the Terraform-managed EKS add-ons, and `kyverno`, both already excluded by Kyverno's webhook; and `argocd`, because the bootstrap installs Argo CD from `bootstrap/argocd` with tagged images, and denying its pods would stop the reconciliation that repairs the cluster.
   - The rule checks containers, init containers, and ephemeral containers (maintainer decision): a Kubernetes native sidecar is an init container, and Kyverno registers `pods/ephemeralcontainers` with its Pod webhook. Consequence: Istio 1.30.3 builds the injected proxy image as `<hub>/proxyv2:<tag>` (`pkg/kube/inject/inject.go`, `ProxyImage`), so full-profile business pods with sidecar injection are denied until the Istio root pins the proxy by digest (T069). No full-profile root is active yet.
   - Images that operators launch were checked: ECK pods take their digest-pinned `spec.image`; Trivy scan Jobs use `trivy.tag` with its digest; cert-manager's ACME solver is pinned; Trivy's node-collector image is a tag, but its infra-assessment and compliance scanners are disabled, so it never runs.
   - Offline fixtures run through the pinned Kyverno CLI 1.18.2 (`kyverno test`) against the rendered rule: a mutable container, a mutable init container (the Istio native sidecar), and a mutable ephemeral container are each denied; digest-only and tag-plus-digest images are admitted; `kube-system`, `kyverno`, and `argocd` are skipped. Unsigned, wrong-identity, and unmirrored fixtures need the registry and Rekor, so they wait with the mirror identity.
4. **Runtime audit.** Falco, kube-bench, and kube-hunter get exact RBAC and resource bounds, and audit Jobs are kept for 7 days (`ttlSecondsAfterFinished: 604800`), so each report stays readable until kube-hunter's next weekly run.
   - Exact RBAC means none: every pod in `infrastructure/{falco,kube-bench,kube-hunter}` and their triggers names a ServiceAccount its own root defines, never `default`; every such ServiceAccount and pod sets `automountServiceAccountToken: false`; and the roots render no Role, ClusterRole, RoleBinding, or ClusterRoleBinding, so no audit pod can call the Kubernetes API, which satisfies spec 008 FR-007 (minimum RBAC, no mutation).
   - Every container sets CPU and memory requests and limits.
   - kube-bench runs daily, so its CronJob keeps 7 successful Jobs (`successfulJobsHistoryLimit: 7`); otherwise the history limit, not the TTL, would delete reports after 3 days. kube-hunter runs weekly and keeps 3. The kube-bench and kube-hunter triggers keep exactly their CronJob's job spec, TTL included.

**Rationale**: Slice 1 comes first because the pinned identity would deny the promotions already opened for the economical profile as soon as its cluster reconciles again. A regular expression over the reusable workflow's path keeps the property the pin was meant to give (only the reviewed `main` of one of the five services, through the shared CI workflow, can produce an admitted image) without coupling every `.github` release to a GitOps change.

**Alternatives rejected**:

- Pin the new exact SHA: repeats the same breakage on the next `.github` release.
- Keep the imperative triggers in the collector: violates Decision 17 and makes evidence irreproducible.
- Keep audit Jobs for one hour or rely on the log pipeline alone: the economical log collector does not read the `security` namespace, so reports would be lost.

## Decision 23: Complete the full-profile service runtime in four slices

**Decision**: T090 is delivered in four slices, each a sequential GitOps pull request with its own failing test first in `tests/platform/service-runtime-full.bats`. T071's `runtime-config.bats` belongs to its owner, so the lane adds its own test and T071 stays annotated as not delivered here. The five services' full overlays already render startup, readiness, and liveness probes and CPU and memory requests and limits, and the prod Rollouts reference their Deployment through `workloadRef`; T083 already added Istio retries, timeouts, connection pools, and outlier detection. The test pins those instead of changing them.

1. **Business ServiceMonitors per destination.** Each `infrastructure/profiles/full/prometheus/destinations/eks-full-<environment>` root points the five business ServiceMonitors (`auth-api`, `todos-api`, `users-api`, `frontend`, `log-message-processor`) at `microtodo-<environment>`, the only business namespace its cluster holds. They inherit `microtodo-dev` from the economical root, so full staging would scrape no business target and full prod no stable one. The canary ServiceMonitors keep `microtodo-prod`, the only environment that composes the canary strategy, and the economical root does not change.
2. **Disruption and spread.** Every service's full topology adds a PodDisruptionBudget with `maxUnavailable: 1`, which never blocks a Karpenter drain of a single replica, and `topologySpreadConstraints` over `kubernetes.io/hostname` and `topology.kubernetes.io/zone` with `whenUnsatisfiable: ScheduleAnyway`, which leaves no pod Pending while a cluster runs one stable node (Decision 9) (maintainer decision).
3. **Bounded scaling.** KEDA ScaledObjects scale auth-api, todos-api, users-api, and frontend on their request rate through the Prometheus scaler, with `minReplicaCount` equal to each overlay's replicas and a bounded `maxReplicaCount`, targeting the Deployment in dev and staging and the Rollout in prod. The full Prometheus NetworkPolicy admits only the KEDA operator on port 9090. log-message-processor stays at one replica: it subscribes to a Redis pub/sub channel, so each extra replica would process every message again. No CPU scaler: the clusters run no metrics-server, and adding one is outside the plan (maintainer decision).
4. **Controlled configuration and feature toggles.** Each service gets a `<service>-feature-toggles` ConfigMap in the full profile that its Deployment reads. Every key must default to `"false"` and be documented with its owner and purpose, and changing one is a reviewed commit. No service has incomplete behavior today, so the ConfigMaps declare no key, and the test enforces the contract for any future one (maintainer decision). Non-secret runtime settings stay in the existing GitOps ConfigMaps.

**Rationale**: The ServiceMonitors come first because they correct a T085 defect and because the scaling slice reads the request-rate series they collect. A soft spread and `maxUnavailable: 1` keep the disruption budget meaningful once a service has two replicas without stalling consolidation or scheduling on the single-node bootstrap capacity.

**Alternatives rejected**:

- CPU scaling with metrics-server: adds a component the plan does not name.
- `minAvailable: 1` with `DoNotSchedule` spread: blocks every drain of a single replica and leaves pods Pending on one node.
- Toggles implemented in each service's code: five repositories of change with no incomplete behavior to protect.

## Resolved Unknowns

All product and architectural choices are resolved. The remaining Azure account values and stage cost ceilings are deliberately runtime facts requiring authenticated discovery or explicit human acceptance. Their absence does not authorize defaults; the stage contracts make them fail-closed implementation gates.

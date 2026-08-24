# Infrastructure Ownership Contract

## State Owners

| Resource class | Sole owner | Consumers |
| --- | --- | --- |
| AWS backend bucket and KMS key | existing dev backend root | all AWS Terraform roots via backend config |
| Five neutral ECR repositories | dev foundation state | all clusters and CI via outputs/data/permissions |
| `microtodosuite/platform` mirror ECR and exact-workflow mirror role | dev foundation state | full EKS pulls and approved ECR-to-ACR mirror workflow |
| GitHub Actions OIDC provider and ECR publisher role | dev foundation state | organization/service workflows |
| Kyverno verifier and shared notification/Grafana/Sonar reader roles/secret containers | dev foundation state | exact EKS OIDC issuers, service accounts, and DR seed workflow |
| Environment JWT secret containers and economical reader roles | dev foundation state | cluster-specific full reader roles consume one exact secret |
| Legacy `microtodosuite.abrdns.com` hosted zone | dev foundation state | no new consumers; retained without replacement until a separately approved cleanup |
| Canonical `microtodosuite.online` hosted zone, destination/tooling records, health checks | dev foundation state | ingress endpoints as input values after verified registrar delegation |
| AKS IAM OIDC provider and production DNS-01 solver roles | dev foundation state | exact AWS-production and AKS cert-manager service accounts only |
| DR secret-seed AWS role | dev foundation state | exact GitHub repository/environment and pinned reusable workflow; four source secret ARNs only |
| Economical VPC/EKS | dev foundation state | economical GitOps root only |
| Full staging VPC/EKS | demo-full foundation state | full-staging GitOps root only |
| Full dev VPC/EKS | full-dev foundation state | full-dev GitOps root only |
| Full prod VPC/EKS | full-prod foundation state | full-prod GitOps root only |
| TGW and centralized egress VPC/NAT | shared egress state | full-dev and full-prod route attachments |
| AKS, VNet, identities, empty Key Vault, ACR, and static ingress public IP | Azure DR state | AKS DR root and OIDC promotion/secret-seed workflows |

## Consumer Rules

- Consumer roots set `create_shared_resources = false`.
- Dev creates `microtodosuite.online` through a separate opt-in resource address; it MUST NOT rename, replace, or destroy the legacy `microtodosuite.abrdns.com` zone as part of canonical-zone creation.
- Data sources or typed remote-state outputs may read shared identifiers; consumers cannot declare the shared resources.
- No root imports, moves, or removes a resource owned by another state.
- A cross-state output contains identifiers only, not credentials or secret values.
- Terraform owns cloud secret containers and access policies, never Azure secret values; the OIDC seed workflow is the only approved cross-cloud value path and emits no value-bearing artifact.
- Shared role trust changes are applied from dev state after consumer cluster OIDC issuers exist.
- Full consumer states look up the dev-owned JWT secret for their one logical environment and create only a uniquely named, cluster-specific reader role with an exact issuer/subject; they create no secret or secret version.
- The GitHub publisher role remains trusted only by the approved GitHub Actions subjects and is never extended with an EKS issuer.
- The platform-mirror role is distinct from the service publisher and DR secret-seed roles, trusts only its pinned workflow identity, and writes only the one platform repository (plus the minimum read needed to copy the signed graph).
- Production DNS-01 roles are separate from the publisher role. They trust only the exact cert-manager subjects, use short-lived web identity, and may change only the common hostname's ACME TXT record in the existing zone.
- TGW route tables expose internet egress only; no full environment receives a route to another environment's CIDR.
- The egress state cannot own workload subnets, EKS resources, or application identity.
- The egress state owns the TGW/VPC/NAT and empty per-spoke route tables; each spoke state owns only its own attachment, association, default/return route resources, and orders them before worker creation.

## Plan Assertions

Every new/changed plan is rejected if it proposes:

- an ECR repository under `microtodosuite/<service>`;
- another platform mirror repository, a platform-mirror role outside dev state, or a mirror role with access to service repositories;
- another `token.actions.githubusercontent.com` OIDC provider;
- another shared publisher, Kyverno, observability, or security role/secret container;
- another environment JWT secret container or secret version;
- any Terraform-managed Azure Key Vault secret value, broad DR seed role, static cross-cloud credential, or value-bearing workflow artifact;
- a `microtodosuite.online` hosted zone outside dev state, more than one canonical zone, or replacement/destruction of the legacy `microtodosuite.abrdns.com` zone during canonical-zone creation;
- an AKS IAM OIDC provider or DNS-solver role outside dev state, a solver trust subject other than the exact production cert-manager service account, or DNS permissions beyond the approved ACME TXT record;
- a state key used by any other root;
- a route between environment spoke CIDRs;
- replacement/destruction of an economical or demo-full resource outside the stage scope;
- more than one new EIP or more than one new NAT gateway;
- a public EKS endpoint CIDR of `0.0.0.0/0`.

## Destruction Boundary

Rollback may remove only resources owned by the failed stage's state. Shared egress cannot be destroyed while an attachment/route remains. Dev shared resources and the economical state are never rollback targets for a consumer stage. Terraform state backups are external to the repository and their paths/checksums are recorded without committing the state.

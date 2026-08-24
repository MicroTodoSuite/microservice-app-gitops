# Feature Specification: AWS ALB Ingress Platform

**Feature Branch**: `main` (no feature branch created by this specification run)

**Created**: 2026-08-23

**Status**: Draft

**Input**: User description: "Provide a GitOps-managed mechanism for exposing HTTP(S) services in this cluster to the internet, using AWS Load Balancer Controller to provision real AWS Application Load Balancers from Kubernetes Ingress resources. Integrate with the cert-manager already deployed for automatic TLS certificate provisioning. Reuse the cluster-level platform add-on registration pattern, keep the controller available to every service, treat its IRSA role and AWS permissions as an explicit microservice-app-ops dependency, and prove the frontend is reachable externally over HTTPS with a valid certificate using live evidence."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Register one cluster-wide ingress capability (Priority: P1)

As a platform operator, I can activate one reusable ingress controller for the
shared EKS cluster through the same reviewed cluster registration that owns the
other platform add-ons, so every service can use it without installing or
copying a controller.

**Why this priority**: No service can expose an AWS Application Load Balancer
until the cluster has one healthy controller with a valid AWS identity and a
reviewed GitOps ownership boundary.

**Independent Test**: Render the registered cluster, confirm it declares one
additional platform add-on, reconcile a reviewed revision through ArgoCD, and
observe one healthy controller using its dedicated AWS identity without any
business-service Ingress being present.

**Acceptance Scenarios**:

1. **Given** the controller installation and cluster activation are committed,
   **When** ArgoCD reconciles the target revision, **Then** exactly one
   cluster-level controller application becomes synchronized, healthy, and
   available for all approved service namespaces.
2. **Given** the required IRSA role or trust relationship is absent or invalid,
   **When** activation readiness is evaluated, **Then** the dependency is
   reported as unsatisfied and the platform is not claimed ready.
3. **Given** a non-AWS cluster registration, **When** its desired state is
   rendered, **Then** the AWS-specific controller remains inactive unless that
   registration explicitly opts in.

---

### User Story 2 - Expose the frontend with one Ingress (Priority: P2)

As a service maintainer, I can add one environment-owned Ingress resource for
the frontend and obtain an internet-facing Application Load Balancer without
changing the frontend Service into a cloud-specific load-balancer service or
installing service-local infrastructure.

**Why this priority**: This is the smallest useful consumer of the shared
capability and proves the platform contract is actually reusable by a service.

**Independent Test**: Add one frontend Ingress in the selected environment,
reconcile it through ArgoCD, and observe that it receives an external address,
routes to healthy frontend targets, and requires no second controller or
service-local AWS credentials.

**Acceptance Scenarios**:

1. **Given** the controller and its AWS prerequisites are healthy, **When** one
   frontend Ingress is reconciled, **Then** one AWS Application Load Balancer
   is provisioned and reports healthy frontend targets.
2. **Given** the frontend Ingress is removed or reverted in Git, **When** ArgoCD
   reconciles the removal, **Then** the controller retires the no-longer-owned
   load-balancer resources without a direct cluster or AWS-console correction.
3. **Given** another service needs public HTTP(S) access, **When** it follows the
   documented Ingress contract, **Then** it can consume the existing controller
   without copying its installation or expanding its AWS identity.

---

### User Story 3 - Reach the frontend securely from the internet (Priority: P3)

As an external user, I can open the frontend through its public hostname over
HTTPS, receive a certificate trusted for that hostname, and be redirected from
unencrypted HTTP automatically.

**Why this priority**: A created load balancer is not a successful external
route until DNS, TLS, certificate issuance, target health, and the application
response all work together from outside the cluster.

**Independent Test**: From a network outside the EKS VPC, resolve the public
hostname, verify the certificate chain and hostname, confirm HTTP redirects to
HTTPS, and retrieve a successful frontend response while recording the exact
Git revision and live resource status.

**Acceptance Scenarios**:

1. **Given** public DNS and certificate prerequisites are ready, **When** an
   external client connects over HTTPS, **Then** certificate validation and
   hostname verification succeed and the frontend returns an HTTP 200 response.
2. **Given** an external client uses HTTP, **When** it requests the frontend
   hostname, **Then** it receives a redirect to the HTTPS URL and no application
   content is served over plaintext.
3. **Given** certificate issuance, DNS validation, or load-balancer provisioning
   is still pending or failed, **When** acceptance is evaluated, **Then** the
   feature remains failed or incomplete rather than passing from desired state.

### Edge Cases

- The IRSA role exists but its trust policy names a different cluster OIDC
  provider or service-account subject.
- The IRSA policy omits an Elastic Load Balancing, EC2 discovery, security-group,
  target-registration, or tagging action required by the pinned controller.
- The controller accidentally falls back to the node role or to a long-lived AWS
  credential instead of its dedicated service-account identity.
- Public subnets are missing the discovery tags or multi-Availability-Zone
  placement required for an internet-facing Application Load Balancer.
- The Ingress is reconciled before DNS or certificate validation completes and
  therefore has an address but cannot yet pass HTTPS acceptance.
- The certificate automation produces only a Kubernetes TLS Secret, which an
  AWS Application Load Balancer cannot attach directly, instead of an
  ALB-compatible certificate.
- The requested hostname has no authoritative public DNS zone, a conflicting
  record, or a certificate that does not cover the exact hostname.
- AWS load-balancer, target-group, security-group, public-address, or certificate
  quotas prevent provisioning.
- Frontend pods are healthy in Kubernetes but fail the load balancer's target
  health check because the path, port, or network policy is incorrect.
- More than one namespace attempts to join a shared load-balancer group without
  belonging to the same reviewed trust boundary.
- Removing the Ingress leaves externally billed AWS resources or DNS records
  behind, or deletion protection prevents GitOps reconciliation from completing.
- The controller, certificate, DNS record, and frontend response are healthy at
  different revisions, making the evidence set internally inconsistent.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST install AWS Load Balancer Controller once per
  opted-in AWS cluster as a reusable, GitOps-managed platform add-on rather than
  as a service-local component.
- **FR-002**: Cluster activation MUST use the existing explicit infrastructure
  registration values consumed by the shared ArgoCD ApplicationSet; adding an
  installation directory alone MUST NOT activate the controller.
- **FR-003**: The controller release inputs MUST be vendored with provenance and
  integrity evidence, and every executable image in rendered desired state MUST
  use an immutable digest.
- **FR-004**: The controller MUST expose one canonical Ingress class contract
  that approved services can reference without controller-specific duplication.
- **FR-005**: The controller MUST use a dedicated Kubernetes ServiceAccount
  bound to a dedicated IRSA role and MUST NOT use static AWS access keys, a
  Secret containing AWS credentials, or the worker-node role as a fallback.
- **FR-006**: The required IAM role, trust policy, permission policy, and typed
  role ARN output are an explicit cross-repository dependency owned by
  `microservice-app-ops`; this repository MUST NOT create or assume that IAM
  dependency already exists.
- **FR-007**: The cross-repository IAM contract MUST cover the exact AWS actions
  required by the selected controller release, including Elastic Load Balancing
  lifecycle operations and the EC2 discovery, security-group, target, and tag
  operations needed to provision and reconcile Application Load Balancers.
- **FR-008**: Activation and live acceptance MUST fail closed when the typed IRSA
  role output, cluster-specific OIDC trust, service-account subject, or required
  policy evidence cannot be verified.
- **FR-009**: AWS-owned network prerequisites, including public subnet discovery
  metadata and any public DNS or certificate resources outside Kubernetes, MUST
  be treated as `microservice-app-ops` contracts and not duplicated as literals
  in the reusable controller installation.
- **FR-010**: ArgoCD's project boundary MUST permit only the additional
  cluster-scoped resource kinds required by the rendered controller release; it
  MUST NOT introduce an unrestricted cluster-resource wildcard.
- **FR-011**: The frontend MUST be exposable in the selected environment through
  one environment-owned Kubernetes Ingress that routes to the existing frontend
  Service and does not require a Service of type LoadBalancer.
- **FR-012**: The frontend route MUST provision an internet-facing AWS
  Application Load Balancer and MUST report an external address plus healthy
  backend targets before it is considered available.
- **FR-013**: The public route MUST listen on HTTPS, redirect HTTP to HTTPS, and
  serve a publicly trusted certificate whose subject covers the exact frontend
  hostname.
- **FR-014**: Certificate issuance and renewal MUST be automatic. The chosen
  design MUST state and prove the ALB-compatible certificate handoff explicitly;
  it MUST NOT claim that a cert-manager-generated Kubernetes TLS Secret is
  directly consumed by an AWS Application Load Balancer.
- **FR-015**: The existing cert-manager installation MUST remain healthy and its
  precise role in the final certificate lifecycle MUST be documented and
  live-verifiable, with no duplicate or unused certificate represented as the
  certificate serving external users.
- **FR-016**: The public hostname MUST resolve through authoritative DNS to the
  provisioned load balancer, and DNS ownership and record lifecycle MUST have a
  declared GitOps/Terraform owner.
- **FR-017**: Network policy, security-group, and target registration behavior
  MUST allow only the traffic needed for the load balancer health check and
  frontend route without weakening unrelated namespace isolation.
- **FR-018**: Controller logs, Kubernetes events, Ingress status, AWS
  load-balancer state, target health, certificate state, and DNS state MUST make
  provisioning failures diagnosable without mutating managed resources.
- **FR-019**: Repository validation MUST cover release provenance, checksums,
  immutable images, explicit activation, exact ArgoCD permissions, the IRSA
  annotation contract, one-resource frontend exposure, HTTPS redirect settings,
  and the non-AWS registration remaining inactive.
- **FR-020**: Live verification MUST be read-only and MUST capture the expected
  Git revision, ArgoCD health, controller availability, service-account identity,
  Ingress address, AWS load-balancer state, target health, DNS resolution,
  certificate chain and expiry, HTTP redirect, and HTTPS frontend response.
- **FR-021**: No manifest render, successful Terraform plan, or healthy
  controller alone MAY satisfy external-access acceptance; all live evidence
  MUST refer to the same reviewed desired-state revision.
- **FR-022**: Rollback MUST be initiated by Git revert and reconciled by ArgoCD;
  direct `kubectl apply`, patch, scale, delete, or AWS-console mutation is outside
  the allowed recovery path.

### Key Entities

- **Cluster Ingress Capability**: The singleton controller installation,
  canonical Ingress class, ArgoCD application, and cluster activation values.
- **Controller Identity Contract**: The ServiceAccount subject, cluster OIDC
  trust, least-privilege IAM policy, and typed role ARN owned across the GitOps
  and operations repositories.
- **External Route**: One environment-owned Ingress connecting a public hostname
  and HTTPS listener to a namespaced Service and its health-check behavior.
- **Certificate Lifecycle**: The authoritative issuer or certificate manager,
  ALB-compatible certificate reference, hostname coverage, validation state,
  renewal state, and evidence that identifies the certificate actually served.
- **Public DNS Contract**: The authoritative zone, frontend record, load-balancer
  target, lifecycle owner, and propagation/validation status.
- **Live Acceptance Evidence**: Timestamped, revision-bound observations of
  GitOps convergence, AWS resources, TLS validation, DNS, targets, and real
  external HTTP(S) behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The opted-in EKS registration produces exactly one additional
  cluster ingress capability while a non-AWS registration produces none, and
  all repository contract and render checks pass.
- **SC-002**: Within 10 minutes of the reviewed controller revision being
  available to ArgoCD, its application is synchronized and healthy, all desired
  controller replicas are available, and zero controller pods are pending,
  failed, or crash-looping.
- **SC-003**: With all cross-repository prerequisites present, one frontend
  Ingress obtains a public load-balancer address and healthy targets within 15
  minutes of reconciliation, without a second controller or service-local AWS
  credential.
- **SC-004**: One hundred percent of three external HTTP probes are redirected
  to HTTPS, and one hundred percent of three external HTTPS probes validate the
  certificate hostname and trust chain and return the frontend successfully.
- **SC-005**: The certificate presented to external clients has the requested
  hostname, is within its validity period, and is linked by live evidence to the
  automatic issuance and renewal mechanism actually used by the load balancer.
- **SC-006**: Live evidence records the same reviewed Git revision for the
  controller, frontend route, and ArgoCD applications, and records timestamps
  for DNS, target-health, TLS, redirect, and response observations.
- **SC-007**: Static and live checks find zero stored AWS access keys, zero use of
  the worker-node role by the controller, zero unrestricted ArgoCD cluster-kind
  wildcards, and zero direct managed-state mutation in the verification path.
- **SC-008**: When any required IRSA, network, DNS, or certificate prerequisite
  is deliberately absent from the evidence set, readiness reports that exact
  dependency as unsatisfied and does not report the feature complete.
- **SC-009**: A second service can adopt the documented Ingress contract by
  adding only its route-specific desired state; no controller installation,
  cluster identity, or AWS policy copy is required.

## Assumptions

- The first live consumer is the frontend in the development environment; the
  controller contract remains reusable by staging, production, and other
  services, but this feature does not expose every environment automatically.
- The existing shared EKS cluster and its ArgoCD registration remain the target;
  the local kind pilot provides render/contract coverage only and does not try
  to provision AWS resources.
- `microservice-app-ops` owns EKS OIDC, IAM/IRSA, VPC/subnet metadata, Route 53,
  and AWS certificate resources. Any required change there is a separately
  reviewed cross-repository prerequisite, not an implicit change in this repo.
- The AWS Load Balancer Controller IRSA role and public DNS/certificate resources
  have not been proven to exist in this specification phase.
- A public hostname and authoritative DNS zone must be available before live
  HTTPS acceptance; no hostname is invented by this specification.
- The exact ALB-compatible certificate automation choice is resolved during
  clarification because AWS Application Load Balancers attach AWS-managed
  certificate references, while cert-manager's standard Ingress flow stores a
  certificate in a Kubernetes Secret.
- Existing service availability, namespace isolation, cert-manager health, and
  ArgoCD reconciliation must be preserved throughout activation and rollback.

# Feature Specification: Local Platform Add-ons Foundation

**Feature Branch**: `esteban/platform-addons`

**Created**: 2026-08-09

**Status**: Complete

**Input**: User description: "Verify the repository and live local pilot from scratch, then add KEDA, cert-manager, External Secrets Operator, and Kyverno as complete GitOps-managed platform add-ons; prove every add-on and auth-api healthy live; keep the foundation local, provider-neutral, reusable for future EKS registrations; and synchronize the local constitution with ratified version 1.1.0."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reconcile a complete local platform (Priority: P1)

As a platform operator, I can reconcile the four required platform add-ons from
the local desired-state source and see each capability become operational,
without applying managed resources directly to the cluster.

**Why this priority**: The add-ons are the foundation for autoscaling,
certificate lifecycle, secret delivery, and admission policy. Configuration
alone has no value unless the running cluster proves every controller works.

**Independent Test**: Starting from the verified pilot, publish one or more
local desired-state commits and observe four add-on applications at the exact
published revision. Each application is synchronized and healthy, all expected
controller workloads are available, and a capability-specific reconciled
resource proves that the controller is functioning.

**Acceptance Scenarios**:

1. **Given** the existing local pilot is reachable, **When** the add-on desired state is committed to its machine-local source, **Then** KEDA, cert-manager, External Secrets Operator, and Kyverno are each discovered through the shared infrastructure registration and reach synchronized, healthy status.
2. **Given** all four add-on applications are synchronized, **When** their live controller resources are inspected, **Then** every controller deployment is available and no required pod is pending, failed, or crash-looping.
3. **Given** the controllers are available, **When** their capability checks are inspected, **Then** an autoscaling resource is ready, a certificate is issued, the auth-api secret is synchronized, and an admission policy reports a passing result.

---

### User Story 2 - Preserve auth-api under admission policy (Priority: P2)

As a service operator, I can continue to deploy and call auth-api after Kyverno
begins enforcing the local platform baseline.

**Why this priority**: A healthy policy engine that prevents the existing pilot
service from reconciling would make the platform unusable.

**Independent Test**: After Kyverno and its enforced baseline policies are
healthy, publish a benign auth-api desired-state change, wait for ArgoCD to
reconcile the new revision and rollout, and call the live version endpoint three
times over at least 60 seconds.

**Acceptance Scenarios**:

1. **Given** Kyverno is enforcing the local baseline, **When** auth-api is reconciled at a newer committed revision, **Then** admission succeeds and the auth-api application returns to synchronized and healthy status.
2. **Given** the post-policy auth-api rollout is available, **When** the service version endpoint is called three times over at least 60 seconds, **Then** all three responses succeed with HTTP 200.
3. **Given** Kyverno has scanned auth-api, **When** the policy reports are inspected, **Then** the enforced immutable-image and health-probe rules pass for the workload.

---

### User Story 3 - Reuse the platform for future clusters (Priority: P3)

As a platform maintainer, I can register another cluster through the existing
registration mechanism and receive the same four add-ons without redesigning
their ownership or delivery model.

**Why this priority**: The local pilot must establish the reusable platform
boundary before dev, staging, and production clusters exist.

**Independent Test**: Render the shared registration and every infrastructure
folder without a live cloud account. The rendered desired state contains the
same complete add-on installations, has no AWS or Azure dependency, and requires
no edit to an add-on folder when a future registration is added.

**Acceptance Scenarios**:

1. **Given** a new value-only cluster registration, **When** it consumes the shared cluster base, **Then** the same infrastructure discovery mechanism produces the four add-on applications.
2. **Given** no cloud credentials or cloud services, **When** the local add-on foundation is rendered and reconciled, **Then** every required capability remains functional.
3. **Given** a future EKS environment is registered later, **When** its connection and environment values are supplied, **Then** the shared add-on installation paths and ownership boundaries do not require redesign.

### Edge Cases

- A running pilot may be based on an older local desired-state revision than the
  checkout; the observed source and cluster revision must be identified before
  publishing changes.
- A release bundle may contain cluster-scoped resources not allowed by the
  current ArgoCD project; the exact required kinds must be derived from the
  pinned render rather than covered by wildcards.
- CRDs can exist before their admission webhooks are ready; capability resources
  must reconcile only after the controller installation is available.
- An unavailable upstream download or container image must result in a visible
  failed validation, never a claim based only on manifests.
- One healthy controller must not mask another degraded controller; status is
  evaluated per add-on and per expected workload.
- A policy that rejects the already compliant auth-api workload must block
  completion until corrected through a desired-state commit.
- A pre-existing constitution copy that already matches version 1.1.0 must be
  reported as verified and left unchanged rather than rewritten cosmetically.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The implementation MUST capture the current checkout, pilot-owned local runtime, Kubernetes context, ArgoCD applications, auth-api readiness, local desired-state revision, and repeated live HTTP health before adding files.
- **FR-002**: If no pilot-owned local cluster is running, the implementation MUST follow the repository quickstart to bootstrap one and record elapsed time and intervention; an unrelated cluster MUST NOT satisfy this requirement.
- **FR-003**: Every managed cluster change MUST enter through a commit to the machine-local desired-state source and automatic ArgoCD reconciliation; no direct apply, patch, scale, or rollout command may change managed state.
- **FR-004**: KEDA, cert-manager, External Secrets Operator, and Kyverno MUST each have a complete, pinned, locally retained installation bundle with upstream provenance and a verified checksum.
- **FR-005**: The shared infrastructure registration MUST discover exactly one application for each of the four required add-ons while excluding vendor subdirectories from discovery.
- **FR-006**: Each add-on application MUST use automated pruning, self-healing, server-side application, and an explicit destination namespace through the reusable registration mechanism.
- **FR-007**: The ArgoCD project MUST allow only the exact cluster-scoped resource kinds required by the pinned add-on bundles and capability resources; cluster-wide group/kind wildcards are forbidden.
- **FR-008**: KEDA MUST deploy its operator, metrics API server, admission webhooks, CRDs, and required access controls, and a reconciled autoscaling resource MUST report ready without a cloud service.
- **FR-009**: cert-manager MUST deploy its controller, cainjector, webhook, CRDs, and required access controls, and a locally issued certificate MUST report ready.
- **FR-010**: External Secrets Operator MUST deploy its controller, certificate controller, webhook, CRDs, and required access controls, and the existing auth-api external secret MUST remain synchronized.
- **FR-011**: Kyverno MUST deploy its admission, background, cleanup, and reports controllers, CRDs, webhooks, and required access controls, and MUST enforce at least immutable images and workload health probes for MicroTodoSuite business workloads.
- **FR-012**: Capability resources MUST be ordered after their respective controller installations so transient webhook startup does not leave an application permanently degraded.
- **FR-013**: After Kyverno is healthy, auth-api MUST be reconciled from a newer desired-state commit that causes its pod template to be admitted again, then return to synchronized, healthy, and available state.
- **FR-014**: Final verification MUST capture per-application source revision, synchronization status, health status, expected deployment availability, capability-resource condition, pod state, and three auth-api HTTP 200 responses over at least 60 seconds.
- **FR-015**: The tracked platform foundation MUST contain no AWS or Azure account, credential, endpoint, registry, secret-store, identity, or cluster dependency.
- **FR-016**: A future cluster registration MUST consume the shared infrastructure mechanism without modifying any of the four add-on installation folders.
- **FR-017**: `.specify/memory/constitution.md` MUST be byte-equivalent in substance and version to the ratified `microservice-app-docs/constitution.md` version 1.1.0; if already equivalent, no content change is required.
- **FR-018**: Repository validation MUST fail on unpinned add-on versions, missing vendor checksums, cloud-provider references, render failures, missing expected controllers, or prohibited direct managed-state mutations.

### Key Entities

- **Platform add-on**: One cluster-level capability with a pinned release,
  retained installation bundle, destination namespace, expected controllers,
  and capability-specific readiness proof.
- **Cluster registration**: The value-only record that connects a cluster to the
  shared desired-state source and activates the reusable application and
  infrastructure generators.
- **Capability check**: A GitOps-managed resource whose live condition proves
  the corresponding controller does more than merely run a pod.
- **Reconciliation evidence**: Timestamped observations connecting a local Git
  revision to ArgoCD status, workload availability, capability conditions, and
  service health responses.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All four required add-on applications report synchronized and healthy at the expected local desired-state revision within 10 minutes of the final add-on commit reaching the local source.
- **SC-002**: One hundred percent of expected add-on controller deployments report all desired replicas available, with zero pending, failed, or crash-looping add-on pods at final verification.
- **SC-003**: Four independent capability checks pass live: one ready autoscaling resource, one ready certificate, one synchronized external secret, and one passing enforced admission-policy result.
- **SC-004**: After policy activation, auth-api returns to synchronized and healthy at a newer revision within five minutes and produces three HTTP 200 version responses over at least 60 seconds.
- **SC-005**: Static validation finds zero AWS or Azure runtime dependencies and zero cluster-wide ArgoCD resource wildcards in the platform foundation.
- **SC-006**: A render of the reusable local registration produces exactly the four required infrastructure applications without editing their installation directories.
- **SC-007**: Every retained release bundle matches its recorded SHA-256 checksum, and all repository render and policy-contract checks pass.
- **SC-008**: Live evidence connects every success claim to the exact local source revision; no application is reported successful from desired configuration alone.

## Assumptions

- The running `microtodo-gitops-pilot` cluster and its labeled local registry and
  Git source are pilot-owned and may be reused because they are reachable and
  were independently inspected in this session.
- A complete add-on installation means the full upstream controller, CRD,
  webhook, and access-control bundle plus a functional capability check; it does
  not mean enabling every optional integration.
- Local capability checks use only Kubernetes-native or self-contained sources;
  production certificate issuers, external event sources, and cloud secret
  stores are environment registrations that remain intentionally absent.
- The current auth-api image and secret contracts remain stable while the
  add-ons are introduced.
- Release upgrades are explicit future changes to pinned version directories,
  never floating references.

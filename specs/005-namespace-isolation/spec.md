# Feature Specification: Shared-Cluster Namespace Isolation

**Feature Branch**: `005-namespace-isolation`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "Establish namespace-based isolation for development, staging, and production on the single shared AWS EKS cluster under constitution v1.2.0. Enforce resource, network, and access boundaries through ArgoCD, prove isolation live, and preserve existing development workloads without disruption."

## Clarifications

### Session 2026-08-09

- Q: Does this feature provision or register the shared EKS cluster? → A: No. A
  reviewed `eks-main` registration and a policy-enforcing CNI are external
  prerequisites. This feature owns only in-cluster namespace isolation in the
  GitOps repository and MUST NOT edit Terraform.
- Q: Does this feature deploy platform add-ons or business services into all
  three environments? → A: No. It layers isolation around the existing dev
  workload and may use temporary, GitOps-managed verification fixtures. Real
  add-on and service activation in dev, staging, or prod is separate work.
- Q: How is a default-deny network posture introduced without interrupting dev?
  → A: The rollout first records the live dev dependency and health baseline,
  proves CNI enforcement, and reconciles required allow rules before enabling
  default deny. A failed gate blocks progression and is corrected by Git revert.
- Q: What identities receive environment access? → A: Stable, environment-
  specific Kubernetes groups are bound in GitOps. Mapping AWS principals to
  those groups belongs to the cluster-access handoff; reusable manifests MUST
  NOT contain personal IAM ARNs or grant one environment's group another
  environment's permissions.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Layer Isolation Without Disrupting Development (Priority: P1)

As a platform operator, I can reconcile the three environment boundaries in a
safe order while the existing development workload remains available, so that
adopting the shared-cluster profile does not turn policy rollout into an outage.

**Why this priority**: The shared cluster has a common failure domain. A default
deny policy or undersized quota applied without a verified baseline can break
the only running environment immediately.

**Independent Test**: Capture the current dev application revision, ready
replicas, restarts, health responses, resource use, and required connections;
reconcile the approved isolation layers through ArgoCD; then prove the same dev
workloads remain current, ready, restart-stable, and healthy throughout the
observation window.

**Acceptance Scenarios**:

1. **Given** the shared EKS cluster is registered and dev workloads are healthy,
   **When** the namespace foundations and explicit allow rules reconcile,
   **Then** dev retains every required connection and no ready replica is lost.
2. **Given** all prerequisite gates pass, **When** default-deny policies become
   active, **Then** dev remains healthy and all three environment applications
   report the exact reviewed Git revision.
3. **Given** a prerequisite or health gate fails, **When** the operator evaluates
   the rollout, **Then** later isolation stages remain inactive and recovery uses
   a Git revert rather than a direct cluster mutation.

---

### User Story 2 - Deny Cross-Environment Traffic by Default (Priority: P1)

As a service owner, I can trust that a pod in one environment cannot initiate
traffic to a pod in another environment unless a separately reviewed exception
exists, while same-environment service communication and DNS continue to work.

**Why this priority**: Namespace names alone provide no network isolation; live
enforcement is required to prevent accidental or compromised cross-environment
access.

**Independent Test**: Reconcile temporary test workloads through GitOps in dev,
staging, and prod, attempt every directed cross-environment connection, and
verify all six fail while DNS and one same-environment connection per namespace
succeed.

**Acceptance Scenarios**:

1. **Given** test endpoints in dev, staging, and prod, **When** each namespace
   initiates a new connection to each other namespace, **Then** every
   cross-environment connection is denied.
2. **Given** the default-deny posture, **When** a pod resolves cluster DNS and
   calls an allowed same-environment endpoint, **Then** both operations succeed.
3. **Given** a required platform dependency, **When** an exception is approved,
   **Then** it selects the exact source, destination, protocol, and port rather
   than broadly allowing another environment namespace.

---

### User Story 3 - Contain Resource Exhaustion (Priority: P2)

As a platform operator, I can bound each environment's aggregate and per-
container resource use, so a mistaken development workload cannot consume the
capacity reserved for staging or production.

**Why this priority**: Shared nodes make a noisy neighbor a real availability
risk even after network traffic is isolated.

**Independent Test**: Publish one intentionally over-budget verification
workload through the GitOps test path, observe the expected quota or limit
rejection, and prove workloads in another namespace retain their ready replicas,
restart counts, and health responses.

**Acceptance Scenarios**:

1. **Given** an environment quota, **When** a new workload would exceed its
   aggregate CPU, memory, or pod budget, **Then** Kubernetes prevents the excess
   pods from becoming admitted and the evidence identifies the violated bound.
2. **Given** a container omits resources or requests values outside its permitted
   range, **When** it is admitted, **Then** namespace defaults are applied or the
   invalid request is rejected according to the declared limits.
3. **Given** a resource violation in one namespace, **When** the attempt is
   observed, **Then** a different environment's baseline workload remains
   healthy and unchanged.

---

### User Story 4 - Enforce Environment-Scoped Modification Rights (Priority: P2)

As a maintainer, I can change permitted workloads only in the environment I am
assigned to, while isolation policy remains platform-owned, so access does not
silently become cluster-wide or self-escalating.

**Why this priority**: A shared control plane turns an overly broad binding into
access to every environment, regardless of the network and resource policies.

**Independent Test**: Evaluate the complete subject-by-namespace authorization
matrix and prove each environment maintainer group can modify the allowed
workload resource in its own namespace, is denied in the other two, cannot
change isolation controls, and an unbound subject is denied everywhere.

**Acceptance Scenarios**:

1. **Given** the dev maintainer group, **When** authorization is evaluated for an
   allowed workload change in dev, staging, and prod, **Then** only dev is
   allowed; the staging and prod groups follow the corresponding matrix.
2. **Given** any environment maintainer group, **When** it attempts to modify a
   Namespace, ResourceQuota, LimitRange, NetworkPolicy, Role, or RoleBinding,
   **Then** access is denied because those resources remain ArgoCD/platform-owned.
3. **Given** an unbound principal, **When** it attempts a namespaced mutation in
   any environment, **Then** access is denied.

### Edge Cases

- Existing dev requests or limits already exceed a proposed quota, or current
  headroom is too small for a rolling replacement; activation must stop before
  the quota is enforced.
- The VPC CNI version supports NetworkPolicy objects but its enforcement feature
  or node agent is disabled; rendered manifests are not acceptance evidence.
- A default-deny egress policy blocks DNS, registry access, telemetry, an AWS
  endpoint, or another existing dev dependency that was omitted from baseline
  discovery.
- A pre-existing TCP connection survives policy activation; network evidence
  must use new connections rather than treating an old session as enforcement.
- A quota-violating Deployment object is accepted but its ReplicaSet cannot
  create pods; evidence must inspect admission events and pod realization, not
  only the Deployment API response.
- A namespace has no business workload yet; its quota, limits, network policy,
  and RBAC still need live API and probe evidence before it is accepted.
- An external identity maps into more than one environment maintainer group;
  the resulting authorization must be reported rather than hidden by testing
  only one group at a time.
- A probe image cannot be pulled after egress isolation; verification assets
  must use an approved immutable image available before the deny stage.
- ArgoCD reports Healthy at an older revision; acceptance waits for the exact
  reviewed revision in every environment application.
- Cleanup of verification fixtures would exceed quota or leave stale Jobs;
  cleanup remains a Git revert and must itself converge before final evidence.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Implementation MUST NOT begin until the authoritative constitution
  v1.2.0 amendment is merged to `microservice-app-docs/main` and its vendored
  GitOps copy is synchronized.
- **FR-002**: The feature MUST target exactly one shared AWS EKS cluster and the
  namespaces `microtodo-dev`, `microtodo-staging`, and `microtodo-prod`.
- **FR-003**: The existing `microtodo-local` environment and its validated pilot
  behavior MUST remain unchanged by this managed-environment feature.
- **FR-004**: Every managed environment MUST be represented by declarative,
  version-controlled desired state discovered through the existing environment
  ApplicationSet; no second namespace delivery mechanism may be introduced.
- **FR-005**: Each managed environment MUST reconcile a Namespace,
  ResourceQuota, LimitRange, ingress-and-egress default-deny NetworkPolicy,
  explicit required allow policies, Role, and RoleBinding.
- **FR-006**: Shared isolation behavior MUST have one reusable definition, with
  environment-specific quota values and identity groups supplied as explicit
  reviewed values rather than copied policy forks.
- **FR-007**: Quotas MUST bound aggregate CPU requests, CPU limits, memory
  requests, memory limits, and non-terminal pod count in every environment.
- **FR-008**: Quota values MUST be derived from measured cluster allocatable
  capacity, current dev demand, rollout headroom, system reserve, and the agreed
  relative priority of dev, staging, and prod; this feature MUST NOT invent
  production values without that evidence.
- **FR-009**: LimitRanges MUST provide bounded CPU and memory defaults for
  containers that omit them and MUST reject per-container values above the
  environment's approved maximum.
- **FR-010**: The sum of approved environment budgets MUST leave documented
  capacity for `kube-system`, ArgoCD, platform controllers, node disruption, and
  evidence workloads; quota totals MUST NOT be represented as guaranteed node
  reservations.
- **FR-011**: Cross-environment pod traffic MUST be denied by default in both
  directions. Same-environment traffic, DNS, platform dependencies, ingress,
  telemetry, and external egress MUST remain denied unless an exact requirement
  is declared and approved.
- **FR-012**: Network exceptions MUST select the narrowest practical source,
  destination, protocol, and port and MUST NOT grant one complete environment
  namespace access to another.
- **FR-013**: Before any default-deny policy is activated, live evidence MUST
  prove that the cluster's CNI enforces NetworkPolicy on every eligible worker
  node and that the existing dev dependency inventory is complete enough for a
  no-disruption rollout.
- **FR-014**: Required dev allow rules MUST reconcile and pass health and
  connectivity checks before the dev default-deny policy is activated.
- **FR-015**: RBAC MUST bind stable, environment-specific maintainer groups and
  MUST deny each group workload modification in the other two environments.
- **FR-016**: Environment maintainer permissions MUST exclude changes to
  Namespace, ResourceQuota, LimitRange, NetworkPolicy, Role, and RoleBinding;
  those isolation controls remain owned by the ArgoCD platform path.
- **FR-017**: RBAC MUST contain no wildcard subject, no binding of all
  authenticated users, no personal IAM ARN in reusable manifests, and no
  cluster-wide workload modification grant for an environment maintainer.
- **FR-018**: The later cluster-access handoff MUST map each authorized AWS
  principal to only its approved Kubernetes group; absent mapping is a blocked
  live-acceptance prerequisite, not permission to broaden GitOps RBAC.
- **FR-019**: Namespace creation, policy changes, RBAC changes, verification
  fixture activation, and fixture cleanup MUST occur only through reviewed Git
  commits reconciled by ArgoCD.
- **FR-020**: Verification commands MAY read cluster state, logs, events,
  authorization results, and application endpoints, but MUST NOT apply, patch,
  create, replace, scale, or delete a GitOps-managed Kubernetes resource.
- **FR-021**: The live network test MUST attempt all six directed connections
  among dev, staging, and prod using new sessions, while also proving DNS and one
  allowed same-environment connection in each namespace.
- **FR-022**: The live resource test MUST deliberately exceed one declared
  namespace bound through the GitOps verification path and prove that an
  existing workload in another namespace remains unaffected.
- **FR-023**: The live RBAC test MUST cover every environment maintainer group
  against all three namespaces, isolation-control denial, the platform
  reconciler's required access, and at least one unbound subject.
- **FR-024**: A dev continuity baseline MUST record exact ArgoCD revision,
  application sync/health, ready replicas, container restart counts, health
  responses, resource usage, and required network paths before policy rollout.
- **FR-025**: Final evidence MUST correlate the reviewed Git revision with live
  namespace resources, quotas and usage, policy-enforcement prerequisites,
  network results, RBAC results, ArgoCD state, Kubernetes events, and the dev
  continuity comparison.
- **FR-026**: A failed prerequisite, sync, isolation, or continuity gate MUST
  stop the rollout and use a reviewed Git revert for recovery; it MUST NOT be
  repaired by direct cluster mutation.
- **FR-027**: This feature MUST NOT provision or register EKS, modify Terraform,
  install add-ons, deploy real services into staging or prod, change application
  source, add a service mesh, or claim multicluster or AKS disaster recovery.

### Key Entities

- **Environment namespace**: One of dev, staging, or prod, identified by a
  stable namespace name and environment labels and reconciled by its own ArgoCD
  environment application.
- **Resource budget**: The environment-specific aggregate CPU, memory, pod, and
  object bounds plus per-container defaults and maxima, justified by a recorded
  capacity baseline.
- **Network isolation policy set**: Default-deny ingress and egress plus exact
  allow rules for DNS, same-environment calls, platform dependencies, ingress,
  telemetry, or approved external destinations.
- **Environment access binding**: The relationship among one stable Kubernetes
  group, one namespace-scoped workload role, and one environment, excluding
  platform-owned isolation controls.
- **CNI enforcement gate**: Live proof that every eligible node runs the
  configured policy agent and that new connections are actually filtered.
- **Dev continuity baseline**: Before-and-after evidence for revision, health,
  ready replicas, restarts, resource use, and required connections.
- **Isolation evidence run**: One immutable observation set tying a Git revision
  to all resource, network, RBAC, ArgoCD, and no-disruption outcomes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Exactly three managed environment applications reconcile
  `microtodo-dev`, `microtodo-staging`, and `microtodo-prod` at one reviewed Git
  revision, and each live namespace contains the required quota, limit, network,
  and RBAC resource set.
- **SC-002**: All six directed cross-environment TCP connection attempts fail,
  while DNS resolution and one allowed same-environment TCP connection succeed
  in each of the three namespaces.
- **SC-003**: One deliberate over-budget workload fails to realize its excess
  pod with a quota or limit event, while the comparison environment loses zero
  ready replicas, adds zero container restarts, and continues returning healthy
  responses.
- **SC-004**: The 3-by-3 maintainer authorization matrix has exactly three
  allowed workload-modification cells—each group in its own namespace—and six
  cross-environment denials; all three groups are also denied modification of
  isolation controls, and an unbound subject is denied in all namespaces.
- **SC-005**: From the pre-change baseline through ten minutes after final policy
  convergence, existing dev workloads lose zero ready replicas, add zero
  policy-attributable restarts, and pass a health check before activation, after
  each staged policy commit, and at the end of the observation window.
- **SC-006**: Live evidence confirms NetworkPolicy enforcement on every eligible
  worker node before default deny and contains no direct command that mutates a
  GitOps-managed Kubernetes resource.
- **SC-007**: Every managed environment renders and schema-validates from the
  same reusable isolation contract with zero wildcard RBAC subjects, zero broad
  cross-environment allows, and zero environment-name drift.
- **SC-008**: Verification fixtures are activated and removed by Git commit and
  ArgoCD reconciliation, final applications return to Synced/Healthy at the
  cleanup revision, and the existing local pilot contracts still pass.

## Assumptions

- The constitution v1.2.0 amendment will be reviewed and merged before any
  implementation or activation from this specification.
- A separate cluster-registration change will provide one `eks-main` ArgoCD root
  that activates dev, staging, and prod against
  `https://kubernetes.default.svc`; this specification does not create it.
- The shared cluster uses Linux EC2 worker nodes and a supported policy-enforcing
  CNI configuration. Repository inspection currently proves only that VPC CNI
  is declared; live policy enforcement remains an acceptance gate.
- Existing dev workloads and their required connections are discoverable at
  implementation time and can be observed without mutating their desired state.
- Stable Kubernetes group names are a GitOps contract. AWS principal-to-group
  mappings remain outside this repository and must be completed before live RBAC
  acceptance.
- Empty staging and prod namespaces may host only temporary verification
  fixtures during this feature; that does not count as service activation.

## Out of Scope

- Provisioning, resizing, renaming, or destroying EKS, VPCs, nodes, ECR, IAM,
  access entries, or the VPC CNI add-on configuration.
- Creating the `eks-main` registration, performing the audited ArgoCD bootstrap,
  or promoting application images.
- Deploying platform add-ons or real business workloads into dev, staging, or
  prod.
- Defining application-specific ingress, external API, telemetry, secret-store,
  or database allow rules before their owning features provide exact contracts.
- Implementing Istio, mTLS through a service mesh, AKS DR, Velero, Karpenter,
  Spot node pools, resilience libraries, canary rollouts, or observability.
- Changing service code, API/event contracts, persistence, replicas, or business
  behavior.

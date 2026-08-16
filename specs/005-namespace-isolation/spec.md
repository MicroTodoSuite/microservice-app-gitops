# Feature Specification: Shared-Cluster Namespace Isolation

**Feature Branch**: `005-namespace-isolation`

**Created**: 2026-08-09

**Status**: In implementation

**Input**: User description: "Establish namespace-based isolation for development, staging, and production on the single shared AWS EKS cluster under constitution v2.0.0. Enforce resource, network, access, and Redis event-stream boundaries through ArgoCD, prove isolation live, and preserve existing development workloads without disruption."

## Clarifications

### Session 2026-08-09

- Q: Does this feature provision or register the shared EKS cluster? → A: No.
  The operator explicitly adopts the existing `microtodosuite-dev` EKS cluster
  and its live `clusters/eks-dev` root as the shared cluster for dev, staging,
  and prod. Their legacy names remain unchanged during this feature to avoid a
  control-plane replacement or a separate root-path migration. This feature
  does not change the cluster itself; infrastructure-as-code changes are limited
  to the three Secrets Manager entries and least-privilege IRSA paths selected
  for business-service activation.
- Q: What may the prerequisite registration activate for this feature? → A:
  Exactly the three environment-policy entries during isolation preparation.
  Business-service activation remains empty until images, secrets, quotas,
  network policy, and health gates are ready. The final reviewed activation
  change selects dev, staging, and prod together and declares all fifteen
  business-service Applications. The ApplicationSet reconciles them
  progressively by environment rather than concurrently. The four
  already-running controller Applications
  (`infra-keda`, `infra-cert-manager`, `infra-external-secrets`, and
  `infra-kyverno`) and the existing `infra-redis` remain explicitly allowlisted
  during the foundation and default-deny stages, while folder-wide
  infrastructure discovery is disabled. A later reviewed registration value
  removes only `infra-redis` after all three replacements pass. The current
  lockstep apps/environments wording and automatic infrastructure discovery
  must be decoupled before activation.
- Q: Does this feature deploy platform add-ons or business services into all
  three environments? → A: It installs no new controller add-on. After the
  isolation and deployment prerequisites pass, one reviewed GitOps publication
  declares auth-api, todos-api, users-api, frontend, and
  log-message-processor in dev, staging, and prod. The ApplicationSet then uses
  RollingSync to reconcile the dev group first, staging second, and prod last,
  advancing only when the preceding group is Healthy. This creates fifteen
  business-service Applications and intentionally expands the feature's former
  policy-only scope.
- Q: How is a default-deny network posture introduced without interrupting dev?
  → A: The rollout first records the live dev dependency and health baseline,
  proves CNI enforcement, and reconciles required allow rules before enabling
  default deny. A failed gate blocks progression and is corrected by Git revert.
- Q: What identities receive environment access? → A: Stable, environment-
  specific Kubernetes groups are bound in GitOps. Mapping AWS principals to
  those groups is explicitly deferred. Reusable manifests MUST NOT contain
  personal IAM ARNs or grant one environment's group another environment's
  permissions. The same AWS principal MUST NOT be mapped to all three groups as
  a shortcut; live RBAC acceptance remains incomplete until distinct approved
  mappings exist.
- Q: Does Redis remain one shared infrastructure instance? → A: No. The shared
  EKS cluster uses one environment-owned Redis instance inside each of
  `microtodo-dev`, `microtodo-staging`, and `microtodo-prod`. The managed
  registration MUST NOT create `infra-redis`; the existing local pilot may keep
  its local-only `infra-redis` contract. The business-service activation list
  remains empty only until the final progressive publication gate.

### Session 2026-08-10

- Q: How are the JWT signing secrets required by auth-api, todos-api, and
  users-api supplied? → A: AWS Secrets Manager holds one independently
  generated value per environment. Each namespace uses a least-privilege IRSA
  identity and namespaced SecretStore so External Secrets can materialize only
  its own `auth-api-secrets/JWT_SECRET`; no secret value is stored in Git or
  shared across environments.
- Q: Does one publication mean all fifteen workloads reconcile concurrently?
  → A: No. One reviewed Git revision declares all fifteen Applications, and
  ApplicationSet RollingSync reconciles environment groups in the order dev,
  staging, then prod. Each group must become Healthy before the next begins, and
  production must still satisfy the constitution's metric-gated canary rule.
- Q: Which ECR repository structure supplies the five service images? → A:
  Create one environment-neutral repository per service under
  `microtodosuite/<service>`. Each service image is built once, and the identical
  repository URI and digest are referenced from dev, staging, and prod. The
  existing empty `microtodosuite/dev/*` repositories are not reused or deleted.
- Q: Which source revisions become the five release images? → A: Start from
  the current `origin/main` heads: auth-api `e86dc1eb0619`, todos-api
  `e33b0ca8e1b9`, users-api `56a1bcbb11bf`, frontend `c43ed0b9363b`, and
  log-message-processor `09f6256f1b4b`. Diagnose and correct their currently
  failing CI in short-lived branches. Each image must come from the reviewed,
  green descendant commit for that service; no image may be published from a
  failing baseline commit.
- Q: How can production canary evidence be produced when Argo Rollouts skips
  analysis on a Rollout's first creation? → A: The single activation revision
  establishes the initial stable production ReplicaSets. Production is not
  accepted as released at that point. A later reviewed GitOps evidence revision
  changes only a pod-template evidence annotation while retaining the exact
  reviewed image digests, causing all five Rollouts to execute their metric
  gates. A reviewed negative-gate fixture MUST also prove automatic abort and
  stable restoration, followed by Git revert. No earlier production seed and no
  direct cluster mutation are permitted.

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
succeed. Publish a unique Redis event in each namespace and prove it is visible
only to the subscriber connected to that namespace's Redis instance.

**Acceptance Scenarios**:

1. **Given** test endpoints in dev, staging, and prod, **When** each namespace
   initiates a new connection to each other namespace, **Then** every
   cross-environment connection is denied.
2. **Given** the default-deny posture, **When** a pod resolves cluster DNS and
   calls an allowed same-environment endpoint, **Then** both operations succeed.
3. **Given** a required platform dependency, **When** an exception is approved,
   **Then** it selects the exact source, destination, protocol, and port rather
   than broadly allowing another environment namespace.
4. **Given** one Redis instance in each environment namespace, **When** a unique
   event is published in one environment, **Then** only that environment's
   subscriber observes it and the other two Redis instances remain independent.

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

---

### User Story 5 - Publish One Verified Release Across All Environments (Priority: P1)

As a platform operator, I can publish one verified image per service and declare
all three environments in one GitOps revision, while automated gates reconcile
dev, staging, and prod in order, so every environment runs identical artifacts
without exposing production to an unverified release.

**Why this priority**: The requested fifteen-Application activation expands the
isolation feature into a production release. Empty ECR repositories, failing CI,
missing secrets, insufficient quotas, or concurrent reconciliation would make
that release unsafe or non-functional.

**Independent Test**: Map five reviewed CI-green source commits to five signed
ECR digests; prove secrets, policies, quota headroom, and release controls are
Ready; reconcile the one activation revision; then observe dev, staging, and
prod become Healthy in order and verify every live image ID, same-environment
contract, and production canary result.

**Acceptance Scenarios**:

1. **Given** any service CI or artifact gate is failing, **When** activation is
   evaluated, **Then** the business-service list remains empty and no image from
   that failing commit is published.
2. **Given** five verified images and all namespace prerequisites, **When** the
   reviewed activation revision is merged, **Then** it declares exactly fifteen
   Applications and RollingSync reconciles dev before staging and staging before
   prod.
3. **Given** one environment group fails to become Healthy, **When** RollingSync
   evaluates the next step, **Then** later environments remain unapplied and
   recovery uses a reviewed Git revert.
4. **Given** the production step begins, **When** its canaries execute, **Then**
   metric analysis gates promotion and automatically aborts an unhealthy
   release.
5. **Given** final convergence, **When** live Pods and service contracts are
   inspected, **Then** all three environments use the same five digests,
   same-environment calls succeed, and cross-environment traffic remains denied.

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
- A future todos-api or log-message-processor overlay retains the former
  `redis.redis.svc.cluster.local` endpoint; static acceptance must reject the
  managed overlay before any business-service activation can expose events to
  the wrong environment.
- ArgoCD reports Healthy at an older revision; acceptance waits for the exact
  reviewed revision in every environment application.
- A new cluster registration reuses the current matching environment/app lists
  or folder-wide infrastructure discovery and unintentionally installs services
  or add-ons; the registration is rejected before namespace-policy activation.
- Cleanup of verification fixtures would exceed quota or leave stale Jobs;
  cleanup remains a Git revert and must itself converge before final evidence.
- A neutral ECR repository exists but its expected digest, signature, scan, or
  SBOM evidence is missing; activation remains blocked rather than falling back
  to a tag or rebuilding for another environment.
- A namespaced ExternalSecret is Ready but resolves the wrong environment's AWS
  secret; digest-only comparison and cross-environment IAM denial must detect
  the wiring error without printing either value.
- RollingSync creates all Application objects but a later environment begins
  reconciling before the prior group is Healthy; acceptance fails even if all
  Applications eventually become Healthy.
- A production Rollout becomes Healthy without executing its metric analysis,
  or the analysis provider is unavailable; production acceptance remains
  blocked.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Implementation MUST NOT begin until the authoritative constitution
  v2.0.0 amendment is merged to `microservice-app-docs/main` and its vendored
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
  explicit required allow policies, Role, RoleBinding, and one namespace-local
  Redis Deployment, ServiceAccount, Service, and Redis-specific policy set.
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
- **FR-010**: The sum of approved environment budgets MUST include each
  environment's Redis requests and rollout headroom while leaving documented
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
- **FR-019**: Namespace creation, policy changes, RBAC changes, Redis lifecycle,
  business-service activation, verification fixture activation, and fixture
  cleanup MUST occur only through reviewed Git commits reconciled by ArgoCD.
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
  network results, RBAC results, ArgoCD state, Kubernetes events, the dev
  continuity comparison, release source commits, CI runs, ECR digests, secret
  readiness, RollingSync order, and production canary results.
- **FR-026**: A failed prerequisite, sync, isolation, or continuity gate MUST
  stop the rollout and use a reviewed Git revert for recovery; it MUST NOT be
  repaired by direct cluster mutation.
- **FR-027**: This feature MUST NOT provision or register EKS, modify the VPC or
  node groups, install cluster-wide controllers or add-ons other than the
  constitution-required Argo Rollouts capability, change application source
  code, add a service mesh, or claim multicluster or AKS disaster recovery.
  Infrastructure-as-code changes are limited to FR-034 through FR-036, the ECR
  repositories in FR-039, and the least-privilege publisher and verifier
  identities in FR-044. The feature MUST activate exactly auth-api, todos-api,
  users-api, frontend, and log-message-processor in dev, staging, and prod after
  all deployment and isolation prerequisites pass.
- **FR-028**: The existing `clusters/eks-dev` shared registration MUST activate
  the three environment-policy Applications independently. During foundation
  and default-deny rollout it MUST produce zero business-service Applications,
  its infrastructure inventory MUST be an exact allowlist containing
  `infra-keda`, `infra-cert-manager`, `infra-external-secrets`, `infra-kyverno`,
  and the existing `infra-redis`; after the Redis retirement gate it MUST
  contain those four retained controllers plus `infra-argo-rollouts`, and no
  shared Redis. Folder-wide infrastructure discovery is forbidden. This feature
  MAY refactor the reusable infrastructure activation mechanism, but it MUST NOT
  create the EKS cluster or perform the audited root bootstrap.
- **FR-029**: Each managed namespace MUST contain exactly one independently
  addressed Redis instance; no Redis Service, endpoint, storage, or Pub/Sub
  stream may be shared across dev, staging, and prod.
- **FR-030**: The shared-cluster registration MUST retire or suppress the
  cluster-wide `infra-redis` Application and MUST prove no `redis` namespace or
  `infra-redis` Application is created on the shared EKS cluster. The existing
  local Kind pilot's `infra-redis` Application MUST remain unchanged.
- **FR-031**: The dev, staging, and prod overlays for todos-api and
  log-message-processor MUST resolve Redis through the namespace-local service
  name. The local overlay MAY retain the local pilot's cross-namespace Redis
  endpoint.
- **FR-032**: Live Redis verification MUST prove all three instances are Ready,
  return `PONG`, reject cross-environment connections, and keep a uniquely
  published event observable only in its source environment.
- **FR-033**: The managed business-service activation list MUST remain empty
  while any image, secret, quota, network-policy, or health prerequisite is
  incomplete. Once every prerequisite passes, a single reviewed GitOps change
  MUST set the list to dev, staging, and prod together, declaring exactly five
  business-service Applications per environment and fifteen in total.
- **FR-034**: AWS Secrets Manager MUST contain one independently generated JWT
  signing value for each of dev, staging, and prod. Secret values MUST NOT be
  committed to Git, exposed in evidence, or reused across environments.
- **FR-035**: Each managed namespace MUST use a least-privilege IRSA identity, a
  namespaced SecretStore, and an ExternalSecret to materialize
  `auth-api-secrets` with the `JWT_SECRET` key. Each identity MUST be authorized
  to read only its environment's source secret.
- **FR-036**: Secret synchronization MUST reach Ready before business-service
  activation. Live verification MUST prove all three destination Secrets exist,
  their values are non-empty and mutually distinct without printing them, and a
  namespace identity cannot read either other environment's source secret.
- **FR-037**: The business-service ApplicationSet MUST label generated
  Applications by environment and use RollingSync steps ordered dev, staging,
  and prod. A step MUST NOT advance until every Application in the preceding
  environment is Healthy; a failed step MUST leave later environments
  unapplied and trigger the reviewed Git-revert recovery path.
- **FR-038**: Production activation MUST use the constitution-required
  metric-gated Argo Rollouts canary and automatic rollback. A healthy
  ApplicationSet step alone MUST NOT count as production release evidence.
  Because Argo Rollouts intentionally skips canary steps when a Rollout has no
  stable ReplicaSet, the initial activation establishes the stable revision but
  MUST NOT complete production acceptance. Acceptance requires a later reviewed
  same-digest pod-template evidence revision that runs all five metric gates,
  plus a reviewed negative-gate revision that proves abort and stable restoration
  before recovery by Git revert.
- **FR-039**: Infrastructure as code MUST create exactly five
  environment-neutral ECR repositories named `microtodosuite/auth-api`,
  `microtodosuite/todos-api`, `microtodosuite/users-api`,
  `microtodosuite/frontend`, and `microtodosuite/log-message-processor`. This
  feature MUST NOT delete or repurpose the existing `microtodosuite/dev/*`
  repositories.
- **FR-040**: For each service, CI MUST build the selected source revision once,
  run the applicable tests and security scan, generate an SBOM, sign one
  immutable digest, and publish it to the service's neutral ECR repository. Dev,
  staging, and prod MUST reference the identical repository URI and digest; tags,
  registry placeholders, and the disabled all-zero digest are forbidden.
- **FR-041**: Business-service activation MUST remain blocked until all five
  digests exist in ECR and their required gate evidence is recorded. Live
  verification MUST prove each running Pod's image ID matches the reviewed
  digest without relying on a mutable tag.
- **FR-042**: The five current `origin/main` heads recorded in the 2026-08-10
  clarification are the release baselines. Existing CI failures MUST be
  diagnosed and corrected through short-lived branches and reviewed PRs in
  their owning service repositories; a failing baseline commit MUST NOT be
  published or activated.
- **FR-043**: Build and CI corrections MUST be the minimum necessary to make the
  existing gates truthful and green. Intentional API, event, persistence, or
  business-behavior changes remain forbidden. Final evidence MUST map each
  service to its reviewed green commit, successful workflow run, signed ECR
  digest, and identical three-environment GitOps references.
- **FR-044**: Terraform MUST create one GitHub Actions OIDC publisher role whose
  trust is limited to reviewed `main` revisions of the five exact service
  repositories and whose ECR permissions are limited to the five neutral
  repositories, plus one IRSA verifier role limited to read-only access required
  by Kyverno for those repositories. Kyverno MUST deny admission of an unsigned
  neutral-ECR business image or one signed by an unapproved workflow identity.
  Static AWS credentials, controller-wide write access, and signature-policy
  bypasses are forbidden.

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
- **Application activation state**: The external cluster-registration state in
  which `env-dev`, `env-staging`, and `env-prod` exist, the business-service
  Application declaration transitions in one Git revision from empty to exactly
  fifteen, RollingSync reconciles them progressively by environment, and the
  infrastructure inventory is an exact stage-specific allowlist: four retained
  controllers plus `infra-redis` before replacement verification, then those
  same four controllers plus `infra-argo-rollouts` after retirement.
- **Environment Redis instance**: One ephemeral, digest-pinned Redis Deployment
  and Service inside a managed environment namespace, with a namespace-local
  DNS endpoint and no cross-environment event or network path.
- **Environment JWT secret path**: One AWS Secrets Manager entry, one
  least-privilege IRSA identity, one namespaced SecretStore, and one
  ExternalSecret associated with exactly one managed environment.
- **Promoted service image**: One tested, scanned, SBOM-attested, signed image in
  an environment-neutral ECR repository, identified by the exact digest used in
  all three managed overlays.
- **Release source revision**: The reviewed, CI-green descendant of one recorded
  service baseline commit from which its promoted service image is built.

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
- **SC-009**: At final convergence, the shared cluster has exactly three managed
  environment-policy Applications and fifteen Synced/Healthy business-service
  Applications: the five named services in each of dev, staging, and prod. The
  activation is declared by one reviewed registration revision; ApplicationSet
  status and timestamps prove the order dev, staging, then prod, and production
  rollout evidence proves its metric gate and automatic rollback are active.
  The explicit infrastructure inventory contains exactly the four retained
  controllers plus `infra-argo-rollouts` after shared Redis retirement.
- **SC-010**: Exactly three Redis Deployments and Services exist on the shared
  cluster, one in each managed namespace; each returns `PONG`, all six directed
  cross-environment Redis connection attempts fail, and a unique event published
  to one instance is observed by zero subscribers connected to the other two.
- **SC-011**: Exactly three Ready ExternalSecrets materialize the required
  `auth-api-secrets/JWT_SECRET` contract without exposing secret values; digest
  comparison proves the three values differ, and all six cross-environment AWS
  secret-read attempts are denied.
- **SC-012**: Exactly five neutral ECR repositories contain one reviewed release
  digest per service; all fifteen Applications reference those five exact
  digests, and live Pod image IDs match them with zero placeholder registries,
  zero mutable tags, and zero disabled digests.
- **SC-013**: Five successful CI runs map one-to-one to five reviewed source
  commits and five signed ECR digests. No image push, GitOps activation, or
  production rollout occurs from any of the five failing baseline commits.

## Assumptions

- The constitution v2.0.0 amendment is reviewed, merged, and byte-synchronized
  before implementation; its exact revisions and digest are recorded in the
  acceptance checklist.
- The existing `clusters/eks-dev` ArgoCD root is the shared registration. It
  activates the dev, staging, and prod environment-policy list against
  `https://kubernetes.default.svc`; its business-service activation list remains
  empty through preparation and then selects all three environments in one
  reviewed publication whose ApplicationSet uses environment-ordered
  RollingSync. Its infrastructure list follows the staged five-foundation then
  five-post-retirement allowlist: shared Redis is replaced by Argo Rollouts.
  This specification does not perform root bootstrap or cluster renaming.
- The shared cluster uses Linux EC2 worker nodes and a supported policy-enforcing
  CNI configuration. Repository inspection currently proves only that VPC CNI
  is declared; live policy enforcement remains an acceptance gate.
- Existing dev workloads and their required connections are discoverable at
  implementation time and can be observed without mutating their desired state.
- Stable Kubernetes group names are a GitOps contract. AWS principal-to-group
  mappings remain outside this repository and must be completed before live RBAC
  acceptance.
- Staging and prod remain empty except for verification fixtures and their
  environment-owned Redis instances until the single-revision business-service
  declaration gate passes; reconciliation still advances progressively through
  dev, staging, and prod.
- AWS Secrets Manager entries and their least-privilege IAM roles are managed by
  the project's existing infrastructure-as-code path; only their non-secret
  identifiers and Kubernetes synchronization contracts belong in GitOps.
- The five neutral ECR repositories are managed by the same infrastructure-as-
  code path. The pre-existing empty `microtodosuite/dev/*` repositories remain
  unchanged and may be retired only by separate reviewed work.

## Out of Scope

- Provisioning, resizing, renaming, or destroying EKS, VPCs, nodes, access
  entries, or the VPC CNI add-on configuration. IAM and Secrets Manager changes
  are limited to the three least-privilege JWT secret paths required by FR-034
  through FR-036, and ECR changes are limited to the five neutral repositories
  required by FR-039.
- Replacing or renaming the existing shared registration or performing the
  audited ArgoCD bootstrap.
- Deploying cluster-wide platform add-ons or business services other than the
  five explicitly activated services.
- Defining application-specific ingress, external API, telemetry, or database
  allow rules before their owning features provide exact contracts. The JWT
  SecretStore contract in FR-034 through FR-036 is the sole secret-store
  exception.
- Implementing Istio, mTLS through a service mesh, AKS DR, Velero, Karpenter,
  Spot node pools, resilience libraries, or general observability. Argo Rollouts
  and the minimum release metric required by FR-038 are the sole release-control
  exceptions.
- Changing API/event contracts, persistence, replicas, or business behavior.
  Source changes are limited to the minimum reviewed build or CI corrections
  required by FR-042 and FR-043.

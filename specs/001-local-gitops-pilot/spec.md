# Feature Specification: Local GitOps Pilot

**Feature Branch**: `main` (no `before_specify` branch hook is configured)

**Created**: 2026-08-08

**Status**: Retired — purpose served, superseded by the cloud rollout

> **Decision, 2026-08-30 (maintainer).** The local pilot is considered finished.
> It existed to prove the GitOps loop end to end before anything was built in the
> cloud, and it did: `scripts/pilot/` (bootstrap, preflight, publish, verify,
> cleanup), `bootstrap/local/kind-config.yaml`, `clusters/local-kind/`, and the
> `20260809T185618Z-git-revert-self-heal` evidence run all exist and were used.
>
> Its 44 unchecked tasks are **not** delivered and are deliberately left
> unchecked rather than ticked: they are the formal evidence harness — an offline
> `assets.lock`, `scripts/pilot/run-three-clean.sh`, a newcomer-workflow test, a
> first-time-operator evaluation, and three recorded clean runs. That harness was
> superseded by the cloud rollout's own evidence contract in spec 009 before it
> was finished.
>
> Ticking them would misrepresent what was built. Retiring the specification
> records the truth: the pilot achieved its purpose, and the remaining scope was
> dropped by decision rather than completed.

**Input**: User description: "Provision a fully local Kubernetes pilot that deploys exactly `auth-api` from committed desired state in `microservice-app-gitops`, with ArgoCD reconciliation, reusable base and environment overlays, no direct cluster application path, and no cloud account, paid service, or hosted runtime dependency."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy auth-api from committed desired state (Priority: P1)

As a teammate with no prior project context, I can prepare the documented local environment from clean repository clones and see `auth-api` become healthy because the environment reconciles the committed desired state, without manually applying the workload to the cluster.

**Why this priority**: The pilot has value only if it proves that a real service can travel through the same commit-and-reconcile path intended for future environments.

**Independent Test**: On a supported workstation with the documented prerequisites, start from clean clones of the required repositories, follow only the quickstart, and verify that exactly one business service, `auth-api`, becomes reachable and healthy while the recorded deployment evidence identifies the Git revision that requested it.

**Acceptance Scenarios**:

1. **Given** a supported workstation with no AWS or Azure credentials and clean clones of the required repositories, **When** a teammate follows the documented quickstart, **Then** the local environment starts, ArgoCD reconciles the committed `auth-api` desired state, and the service health check passes at the documented local address.
2. **Given** a newly created local environment whose reconciler has not yet observed a commit declaring `auth-api`, **When** the environment is inspected, **Then** no `auth-api` workload is running.
3. **Given** committed desired state for `auth-api`, **When** the service becomes healthy, **Then** verification evidence shows exactly one business-service workload and identifies the corresponding repository revision without requiring a direct workload mutation command.

---

### User Story 2 - Prove commit-only change and rollback (Priority: P2)

As a maintainer, I can change an allowed `auth-api` deployment value and restore the prior value through repository commits, demonstrating that uncommitted edits and direct cluster application are not deployment paths.

**Why this priority**: An initial deployment alone does not prove that Git remains the authoritative and reversible source for subsequent changes.

**Independent Test**: Begin with a healthy `auth-api`, commit one visible environment-safe change, observe automatic reconciliation, then revert that commit and verify restoration. At each stage, compare the running state with the repository history.

**Acceptance Scenarios**:

1. **Given** a healthy reconciled deployment, **When** a permitted environment value is edited but not committed, **Then** the running environment does not change.
2. **Given** the same edit is committed and made available to the configured repository source, **When** automatic reconciliation completes, **Then** the running environment reflects that revision without a direct cluster application command.
3. **Given** the change has been reconciled, **When** a Git revert restoring the previous desired state is committed, **Then** automatic reconciliation restores the previously healthy state and the full sequence remains auditable in repository history.

---

### User Story 3 - Reuse the deployment contract (Priority: P3)

As a platform engineer, I can use the pilot's deployment contract for each remaining service and for later managed environments without redesigning the repository layout or replacing the commit-and-reconcile mechanism.

**Why this priority**: The pilot is intended to retire architectural risk cheaply; a local-only layout that must later be rewritten would not meet that purpose.

**Independent Test**: Review the onboarding contract against all seven remaining service slots and the planned managed-environment slots, and confirm that each fits the same base/overlay hierarchy by supplying only declared service and environment values.

**Acceptance Scenarios**:

1. **Given** the completed `auth-api` base and local overlay, **When** a reviewer evaluates onboarding for any of the seven remaining services, **Then** the same directory contract, reconciliation flow, and verification method apply without modifying the pilot's structural conventions.
2. **Given** the completed local overlay, **When** a reviewer evaluates a future managed cluster, **Then** the environment can be represented by another overlay that changes only declared environment-specific values and leaves the reusable base and deployment mechanism unchanged.
3. **Given** a service-specific value and an environment-specific value, **When** each is classified using the documented ownership rules, **Then** neither value is duplicated into or leaks across the wrong configuration layer.

---

### User Story 4 - Reproduce and diagnose the pilot (Priority: P4)

As a first-time operator, I can follow a short guide with explicit prerequisites, expected checkpoints, failure guidance, and cleanup instructions, so I can distinguish a successful GitOps deployment from a merely running local process.

**Why this priority**: Reproducibility by someone other than the author is necessary evidence that the pattern is usable by the team.

**Independent Test**: Give only the repositories and guide to a teammate who has not seen the pilot, and observe whether they complete the workflow within the target time without undocumented assistance.

**Acceptance Scenarios**:

1. **Given** a supported workstation and the documented prerequisites, **When** a first-time operator follows the quickstart, **Then** no more than ten user-entered commands are required from clean clones to a passing health check.
2. **Given** reconciliation or service health fails, **When** the operator follows the troubleshooting path, **Then** they can identify the failing checkpoint and are never instructed to bypass Git by applying desired state directly.
3. **Given** a completed or failed pilot run, **When** the operator follows cleanup instructions, **Then** pilot-owned local resources are removed without changing any remote environment.

### Edge Cases

- The local repository source is temporarily unavailable or ArgoCD cannot read the selected revision; the environment must remain visibly unsynchronized and must not offer a manual application fallback.
- A desired-state commit is invalid, references an unavailable image, or produces a failing health check; the run must not report success, and diagnostics must identify which checkpoint failed.
- The local workstation lacks the documented CPU, memory, disk, virtualization, or port availability; preflight checks must stop early with an actionable explanation.
- The working tree contains uncommitted desired-state changes; those changes must have no effect on the running environment.
- The local cluster is recreated while the desired-state history is retained; reconciliation must converge to the same selected revision without hand-applying `auth-api`.
- A direct cluster mutation is attempted; it must remain outside the supported workflow, must not become the recorded desired state, and must not be documented as a recovery method.
- `auth-api` is reachable but its intrinsic health check fails; the pilot must remain unsuccessful even if the workload process is running.
- `auth-api` login cannot reach `users-api`; this must not cause the deployment-health check to depend on deploying a second business service.
- A second MicroTodoSuite business service is present; verification must flag the pilot as outside its exactly-one-service scope.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pilot MUST run all cluster, reconciliation, repository-source, image-availability, and `auth-api` runtime capabilities on the developer's own machine.
- **FR-002**: The pilot MUST require no AWS account, Azure account, cloud credentials, paid service, hosted cluster, hosted registry, hosted secret store, or hosted runtime dependency.
- **FR-003**: The pilot MUST deploy exactly one MicroTodoSuite business service, `auth-api`; local platform components required to host and reconcile it MUST be identified separately and MUST NOT introduce another business-service workload.
- **FR-004**: The desired state for `auth-api` MUST be versioned in `microservice-app-gitops`, and every production-equivalent workload or configuration change in the pilot MUST correspond to a commit in that repository.
- **FR-005**: ArgoCD MUST automatically reconcile the local environment from the configured `microservice-app-gitops` repository source without requiring a person or delivery pipeline to apply the `auth-api` workload directly.
- **FR-006**: The supported workflow, scripts, and documentation MUST NOT use `kubectl apply`, another imperative cluster mutation, or CI-to-cluster delivery to create or update production-equivalent application state; read-only inspection is permitted.
- **FR-007**: Local bootstrap actions MAY establish only the disposable cluster, the reconciliation capability, and its repository connection; bootstrap MUST NOT create, patch, or configure `auth-api` outside the committed desired state, and the bootstrap boundary MUST be documented.
- **FR-008**: Uncommitted desired-state edits MUST NOT affect the running environment.
- **FR-009**: A committed allowed change and a committed Git revert MUST both be reconciled automatically and remain traceable to their respective repository revisions.
- **FR-010**: The selected `auth-api` artifact MUST be identified immutably in committed desired state; a floating `latest` reference MUST NOT be accepted as deployment evidence.
- **FR-011**: The pilot MUST make `auth-api` reachable at a documented local address and MUST evaluate a service-owned endpoint that can report success without another MicroTodoSuite business service running.
- **FR-012**: A run MUST be considered successful only when the committed revision is synchronized, the expected workload is ready, and the `auth-api` health check succeeds.
- **FR-013**: The GitOps repository MUST contain an environment-neutral base Kustomize configuration and a per-environment overlay contract that keeps local-only values out of the base.
- **FR-014**: The base and overlay contract MUST accommodate all eight MicroTodoSuite services without changing the repository hierarchy, reconciliation mechanism, promotion model, or verification model; onboarding another service may supply only its declared service-specific values.
- **FR-015**: The same `auth-api` base MUST be usable for local and future managed clusters without modification; a new environment may change only declared environment-specific values such as repository or cluster connection, immutable image selection, capacity limits, exposure, and environment-scoped configuration.
- **FR-016**: The repository MUST document which values belong to the reusable service base, which belong to a service definition, and which belong to an environment overlay, with an example mapping for `auth-api`.
- **FR-017**: Local repository access and image availability used during reconciliation MUST remain on the developer machine after initial acquisition so a running pilot does not depend on a hosted source or registry.
- **FR-018**: No production credential or secret value MAY be committed. Any demonstration-only secret material MUST be generated and retained locally, while committed desired state contains only the declarative reference needed by the workload.
- **FR-019**: The repository MUST provide a single newcomer quickstart that lists prerequisites, required repositories, the supported workstation profile, no more than ten user-entered commands, expected checkpoints, verification steps, troubleshooting, and cleanup.
- **FR-020**: Verification MUST expose the selected Git revision, reconciliation status, workload readiness, business-service count, and health result so an operator can prove the deployment path rather than infer it from a running process.
- **FR-021**: Re-running the quickstart against the same selected revision MUST converge safely without creating duplicate application resources or requiring manual repair.
- **FR-022**: Failure guidance MUST preserve the GitOps-only rule: desired-state corrections and rollbacks MUST be commits, and no documented workaround may mutate managed application state directly.

### Key Entities

- **Desired State Revision**: The auditable Git commit selected for reconciliation, including the immutable `auth-api` artifact reference and the environment overlay that should be active.
- **Reusable Service Base**: The environment-neutral declaration of a service's workload, network exposure, configuration contract, and health expectations; it remains unchanged when the target environment changes.
- **Service Definition**: The declared values that distinguish one MicroTodoSuite service from another, such as identity, artifact, network contract, and health contract, without altering the shared repository structure.
- **Environment Overlay**: The bounded set of values for one target environment, including destination, capacity, exposure, and environment-scoped configuration; it references rather than duplicates the reusable base.
- **Reconciliation Registration**: The association among repository source, desired-state path, selected revision, destination environment, and automatic synchronization policy.
- **Pilot Verification Record**: The evidence set containing desired-state revision, reconciliation status, expected and observed business-service count, workload readiness, health result, elapsed time, and whether any unsupported mutation was required.

### Scope Boundaries

**In scope**:

- A disposable local environment and its minimum reconciliation platform.
- Local acquisition or build of an immutable `auth-api` artifact.
- Committed `auth-api` base and local overlay desired state.
- Initial reconciliation, one committed change, one Git-revert rollback, health verification, reuse validation, documentation, troubleshooting, and cleanup.

**Out of scope**:

- Deploying any of the other seven MicroTodoSuite business services.
- Validating the `auth-api` login transaction, because it calls `users-api`; this pilot validates the deployment and intrinsic health of `auth-api` while preserving the exactly-one-service constraint.
- Provisioning AWS EKS, Azure AKS, cloud networking, cloud registries, cloud secret stores, production ingress, disaster recovery, or the complete production platform add-on set.
- Replacing service delivery workflows across all repositories or implementing application features inside `auth-api`.
- Treating a direct cluster mutation as deployment, rollback, repair, or successful pilot evidence.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A teammate with no prior project context can go from clean repository clones and installed prerequisites to a passing local `auth-api` health check in 20 minutes or less using no more than ten user-entered commands and no undocumented assistance.
- **SC-002**: In three consecutive clean pilot runs on the supported workstation profile, 100% of runs reach the synchronized, ready, and healthy state within five minutes after the desired-state commit becomes available to the local repository source.
- **SC-003**: Across initial deployment, one configuration change, and one rollback, 100% of observed production-equivalent state changes map to a Git commit and zero direct workload-application commands are required.
- **SC-004**: An uncommitted desired-state edit causes zero observed change during a five-minute observation window.
- **SC-005**: A Git revert restores the previously healthy state within five minutes after the revert commit becomes available, with both revisions visible in the verification record.
- **SC-006**: The pilot reports one and only one MicroTodoSuite business service, and its health endpoint succeeds in three consecutive checks over at least 60 seconds.
- **SC-007**: A conformance review covering all seven remaining service slots and all planned managed-environment slots finds zero required changes to the repository hierarchy, reconciliation mechanism, promotion model, or base/overlay ownership rules.
- **SC-008**: During the complete running pilot, zero cloud credentials, paid services, hosted clusters, hosted registries, hosted secret stores, or hosted runtime services are used.
- **SC-009**: At least two first-time operators can identify the active Git revision, reconciliation result, workload readiness, and health result from the documented verification output, and each rates the quickstart at least 4 out of 5 for clarity.

## Assumptions

- Initial internet access may be used to clone repositories and acquire public prerequisites or source dependencies. After acquisition, the running pilot's repository source, image availability, cluster, reconciliation, and service runtime remain on the developer machine; fully air-gapped installation media is not part of this feature.
- The supported acceptance-test workstation provides at least 4 logical CPU cores, 8 GiB of available memory, 20 GiB of free disk space, hardware virtualization support, and the ability to reserve the documented local ports.
- Exactly one service refers to MicroTodoSuite business services. The local cluster, ArgoCD, local repository source, networking, name resolution, and other minimum platform capabilities are supporting components rather than additional business services.
- The unavoidable bootstrap boundary exists only to create the disposable cluster and establish reconciliation. Application desired state begins only after that boundary and remains GitOps-managed.
- `auth-api` currently has an intrinsic endpoint capable of returning a successful response without invoking its `users-api`-dependent login flow. That endpoint is sufficient for this deployment pilot; exercising authentication behavior belongs to a later multi-service feature.
- A repository-source endpoint is an environment connection value. Using a local source for the pilot and an approved hosted source later does not change repository structure or the commit-and-reconcile mechanism.
- Destruction of the disposable local cluster is environment cleanup, not a deployment or rollback path for managed application state.

### Dependencies

- A readable clone of `microservice-app-gitops` containing this specification and the eventual desired-state commit.
- A readable clone of `microservice-app-auth-api` from which the immutable pilot artifact can be obtained locally.
- The project constitution, especially its GitOps-only, immutable-promotion, secret-hygiene, and declarative-platform rules.
- A workstation meeting the documented supported profile and permission to run local virtualization or container capabilities.

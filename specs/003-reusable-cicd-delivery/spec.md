# Feature Specification: Reusable CI and GitOps Delivery for All Services

**Feature Branch**: `003-reusable-cicd-delivery`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "Refactor MicroTodoSuite CI into centralized reusable GitHub Actions workflows and migrate all remaining services onto the ArgoCD GitOps delivery path (roadmap task 4). Centralize the copy-pasted per-repo pipelines into reusable workflows in the `.github` repo; build each image once and promote the same immutable digest through environments via automated pull requests to the gitops repo; cable the full section-9 quality-gate structure with dependency-free gates active and test-dependent gates scaffolded but skippable; and onboard the four remaining services into the gitops repository following the existing service-onboarding contract. The pending cloud infrastructure (ECR/EKS via roadmap task 1, Kyverno via task 2) does not exist yet, so the cloud path is designed fully but left inactive, exactly as the pilot left `ECR_REGISTRY_PLACEHOLDER`."

## Clarifications

### Session 2026-08-09

- Q: Registry/cloud handling while task 1 (ECR/EKS/OIDC) and task 2 (Kyverno) are undelivered → A: Design the cloud path fully (OIDC, ECR destination, Cosign keyless, Kyverno-verifiable signatures) but keep the actual cloud push/deploy legs inactive behind explicit gates/placeholders; everything else must be authored and dry-run/locally validatable now.
- Q: Depth of the section-9 quality gates in this feature → A: Cable all ten gate stages, keep the dependency-free gates (build, code-quality, image scan, SBOM, signing) active from day one, and keep the test/contract-dependent gates (unit, integration, contract, E2E, performance, DAST) present but skippable by input; do NOT author the tests or API contracts in this feature.
- Q: Ownership boundary with the security/platform teammate → A: CI-side security (image scan, code-quality gate, SBOM generation, image signing) belongs to this feature; cluster-side enforcement (signature verification/Kyverno, runtime security/Falco, continuous in-cluster scanning) belongs to the platform add-ons work (roadmap task 2) and is out of scope here.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One reusable pipeline replaces the copy-pasted per-repo workflows (Priority: P1)

As a platform engineer maintaining eight repositories, I can define the continuous-integration behavior once in the organization's shared workflow repository and have every service repository consume it through a minimal caller, so that a change to the pipeline is made in exactly one place instead of being copy-pasted and drifting across repositories.

**Why this priority**: The duplication is the core defect this feature exists to remove. Every other improvement (immutable promotion, gates, supply-chain evidence) is only sustainable if it lives in one shared definition rather than five near-identical copies. Delivering just this story already retires the copy-paste debt.

**Independent Test**: Replace one service's local pipeline with the thin caller that references the shared workflow, supplying only that service's identity and technology profile; confirm the pipeline runs end to end through the shared definition and that removing the shared definition's step is reflected in that service without editing the service repository.

**Acceptance Scenarios**:

1. **Given** the shared workflow repository defines the reusable continuous-integration workflow, **When** a service repository references it with only its service name and technology profile, **Then** the service's pipeline executes the shared behavior with no pipeline logic duplicated in the service repository.
2. **Given** two service repositories consuming the same reusable workflow, **When** a maintainer changes one step in the shared definition, **Then** both services receive the change on their next run without any edit to either service repository.
3. **Given** the historical per-repository pipeline that authenticated with static credentials and deployed imperatively to the legacy platform, **When** a service is migrated to the reusable workflow, **Then** the static-credential login and the imperative deploy step no longer exist in that service's pipeline.

---

### User Story 2 - Build once and promote the same immutable image through environments via Git (Priority: P1)

As a release owner, I can have an image built exactly once, published under an immutable content-addressed identifier, and promoted through development, staging, and production by committing that same identifier to the gitops repository, so that what runs in production is provably the same artifact that was tested, and any rollback is a Git revert.

**Why this priority**: This is the delivery mechanism the whole platform depends on and the behavior the current mutable-tag, imperative-deploy pipelines most directly violate. It is the connective tissue between CI and ArgoCD.

**Independent Test**: Merge a change in a service repository, observe that a single image is produced with an immutable identifier, that an automated pull request is opened against the gitops repository updating only the development environment's image identifier, and that promoting to staging and production reuses the identical identifier through separate pull requests, with production requiring explicit human approval.

**Acceptance Scenarios**:

1. **Given** a merge to the trunk of a service repository, **When** continuous integration completes, **Then** exactly one image is produced and referenced by an immutable content-addressed identifier, never by a moving tag.
2. **Given** a successfully built image, **When** the delivery step runs, **Then** an automated pull request is opened against the gitops repository that updates only the development environment overlay's image identifier and does not apply anything to any cluster.
3. **Given** an image already validated in development, **When** it is promoted to staging and production, **Then** each promotion is a pull request that copies the identical image identifier, and the production promotion cannot merge without explicit human approval.
4. **Given** a promoted change that must be undone, **When** the corresponding gitops commit is reverted, **Then** the environment returns to the previous desired state with no direct cluster mutation.

---

### User Story 3 - Full quality-and-supply-chain gate structure, honestly scoped (Priority: P2)

As an engineering lead, I can rely on the pipeline exposing the complete set of quality and supply-chain gates the constitution requires, with the gates that can run today enforced and the gates that depend on artifacts we have not written yet present but inert, so that the pipeline is structurally complete and honest about what it actually verifies.

**Why this priority**: The constitution mandates the full gate set, but the repositories currently have essentially no tests and no API contracts. Cabling every gate now — while only activating those with real inputs — delivers the required structure without pretending to verify things that do not exist, and without turning this feature into "write every test suite."

**Independent Test**: Inspect a pipeline run and confirm that every gate category defined by the constitution is represented as a stage; that the gates operating without pre-existing artifacts run and can fail the pipeline; and that the gates requiring tests or contracts are skipped by default via an explicit switch rather than silently absent.

**Acceptance Scenarios**:

1. **Given** the reusable pipeline, **When** it runs, **Then** every constitution-required gate category is present as a distinct stage in the run.
2. **Given** a gate that requires no pre-existing artifact (image build, code-quality analysis, image vulnerability scan, software-bill-of-materials generation, image signing), **When** the pipeline runs, **Then** that gate executes and a failure blocks promotion.
3. **Given** a gate that requires tests or API contracts that do not yet exist (unit, integration, contract, end-to-end, performance, dynamic security), **When** the pipeline runs with the default configuration, **Then** that gate is explicitly skipped through a documented switch and is not silently omitted.
4. **Given** a team later adds the missing tests or contracts, **When** they flip the corresponding switch on, **Then** that gate becomes enforced without changing the shared pipeline's structure.

---

### User Story 4 - Onboard the remaining services onto the GitOps delivery contract (Priority: P2)

As a platform engineer, I can bring the four remaining business services into the gitops repository using the same base/overlay onboarding contract the pilot established, so that all services share one delivery shape and none requires bespoke structure.

**Why this priority**: The pilot proved the contract with one service. The roadmap task is only complete when every service travels the same path; leaving four services on the legacy path would keep the divergence the feature is meant to end.

**Independent Test**: For each remaining service, add its desired state to the gitops repository following the onboarding contract and wire its repository to the reusable workflow; confirm each renders and conforms to the contract, that managed-environment overlays remain inactive scaffolds, and that no service introduces a structural exception.

**Acceptance Scenarios**:

1. **Given** the established onboarding contract, **When** a remaining service is added to the gitops repository, **Then** it uses the same base plus per-environment overlay shape with only its declared service-specific and environment-specific values differing.
2. **Given** a newly onboarded service, **When** its managed-environment overlays are inspected, **Then** they remain inactive scaffolds (no active cluster selects them) until the cloud infrastructure exists.
3. **Given** all business services onboarded, **When** the delivery contract is reviewed, **Then** every service uses the same reconciliation mechanism, immutable-promotion model, and verification model with no per-service structural change.
4. **Given** a service that is a background worker without an inbound network endpoint, **When** it is onboarded, **Then** its health is expressed through a mechanism appropriate to a worker rather than being forced into an inbound endpoint contract.

---

### User Story 5 - Produce cloud-ready, verifiable supply-chain evidence without depending on unbuilt infrastructure (Priority: P3)

As a security-conscious release owner, I can have the pipeline produce a signed, inventoried artifact using keyless identity and a design that targets the future managed registry and credential-less authentication, while the legs that require the not-yet-provisioned cloud remain inert, so that the moment the infrastructure lands, activation is a value change rather than a redesign.

**Why this priority**: The supply-chain evidence (inventory and signature) is what the platform's later admission control will verify, and credential-less authentication is a non-negotiable. But the registry, cluster, and admission controller are other roadmap tasks; this feature must be ready for them without being blocked by them.

**Independent Test**: Run the pipeline with the cloud legs inactive and confirm it still produces an artifact inventory and a signature verifiable by identity; inspect the configuration and confirm the managed-registry destination and credential-less authentication are defined but gated, mirroring the pilot's placeholder approach.

**Acceptance Scenarios**:

1. **Given** the pipeline running before the cloud infrastructure exists, **When** it completes, **Then** it produces an artifact inventory and an identity-based signature for the image without using any static long-lived credential.
2. **Given** the managed registry and credential-less cloud authentication are not yet available, **When** the pipeline runs, **Then** the legs that would push to the managed registry or authenticate to the cloud are inactive behind explicit placeholders and do not fail the run.
3. **Given** the future infrastructure becomes available, **When** the placeholders are filled with real values, **Then** the cloud legs activate with no change to the pipeline's structure or to any service's desired-state shape.
4. **Given** the signature the pipeline produces, **When** the platform's later admission control verifies signatures, **Then** the signature is in a form that admission control can verify (the verification itself being out of scope here).

---

### Edge Cases

- A service repository references a technology profile the reusable workflow does not support; the run must fail early with an explicit, actionable message rather than silently skipping the build.
- The automated promotion pull request cannot be opened against the gitops repository (permission or connectivity failure); continuous integration must report the failure and must never fall back to mutating a cluster directly.
- A promotion attempts to advance an image identifier that was never built or signed; the promotion must be rejected rather than deploying an unverified artifact.
- Two service pipelines finish close together and both open promotion pull requests against the gitops repository; each must update only its own service's overlay and must not clobber the other's change.
- A required active gate (image scan, code-quality, signing) fails; the image must not be promoted to any environment.
- A test-dependent gate is switched on before its tests exist; the pipeline must fail visibly rather than reporting a passing gate that ran nothing.
- The production promotion pull request is merged without the required approval; branch protection must prevent this, and the absence of that protection must be treated as a defect.
- A background-worker service has no inbound endpoint to probe; onboarding must not fabricate one or block the service from being delivered.
- The legacy imperative pipeline and the new reusable pipeline both exist during migration; only one delivery path may be authoritative for a given service at a time to avoid double deployment.

## Requirements *(mandatory)*

### Functional Requirements

#### Reusable pipeline centralization

- **FR-001**: Continuous-integration behavior MUST be defined once in the organization's shared workflow repository and consumed by service repositories through a caller that supplies only service-specific values (at minimum the service identity and its technology profile).
- **FR-002**: A change to the shared pipeline definition MUST take effect for every consuming service without editing any service repository.
- **FR-003**: The reusable pipeline MUST support the technology profiles present in the suite (a compiled-service profile, a JavaScript-service profile, a Java-service profile, and a scripting-language-service profile) selected by a declared input, and MUST fail explicitly for an unsupported profile.
- **FR-004**: Migrating a service to the reusable pipeline MUST remove that service's static-credential cloud login and its imperative cluster/platform deployment step.
- **FR-005**: The version of the shared workflow that a service consumes MUST be referenceable in a stable, auditable way so that consumers are not silently changed by unreviewed edits.

#### Build-once, immutable promotion, GitOps delivery

- **FR-006**: The pipeline MUST build each service image exactly once per release and reference it by an immutable content-addressed identifier; moving tags such as a "latest" tag MUST NOT be used as deployment evidence.
- **FR-007**: On a successful trunk build, the pipeline MUST open an automated pull request against the gitops repository that updates only the development environment overlay's image identifier for that service.
- **FR-008**: Promotion to staging and to production MUST reuse the identical image identifier and MUST occur through separate pull requests to the gitops repository; the production promotion MUST require explicit human approval before it can merge.
- **FR-009**: The pipeline MUST NOT apply, patch, scale, or otherwise mutate any cluster or managed platform directly; all environment change MUST flow through commits to the gitops repository, and rollback MUST be a Git revert.
- **FR-010**: The promotion update MUST honor the gitops repository's existing digest-only image-update contract, including its rejection of tags, placeholders, and non-immutable references.
- **FR-011**: A promotion of an image identifier that was not produced and signed by the pipeline MUST be rejected.
- **FR-012**: Concurrent promotion pull requests for different services MUST each modify only their own service's overlay without overwriting another service's desired state.

#### Quality and supply-chain gates

- **FR-013**: The reusable pipeline MUST represent every quality and supply-chain gate category the constitution requires as a distinct stage: unit-with-coverage, code-quality analysis, image vulnerability scan, software-bill-of-materials generation, image signing, integration, contract, end-to-end, performance, and dynamic application security testing.
- **FR-014**: Gates that require no pre-existing test or contract artifact (image build, code-quality analysis, image vulnerability scan, bill-of-materials generation, image signing) MUST be active by default, and a failure of any active gate MUST block promotion.
- **FR-015**: Gates that require tests or API contracts not yet present (unit, integration, contract, end-to-end, performance, dynamic security) MUST be present but skippable through an explicit per-gate switch that defaults to skipped, and skipping MUST be visible in the run rather than silent.
- **FR-016**: Enabling a currently skipped gate MUST NOT require changing the shared pipeline's structure, only flipping its switch and providing the required artifacts.
- **FR-017**: A gate switched on without the artifacts it needs MUST fail visibly rather than report success for work it did not perform.
- **FR-018**: This feature MUST NOT author the actual unit, integration, contract, end-to-end, performance, or dynamic-security tests, nor the API contracts; it only provides the stages that will run them.

#### Supply-chain evidence and cloud-readiness

- **FR-019**: The pipeline MUST produce, for each released image, a software bill of materials and an identity-based (keyless) signature, without using any static long-lived credential.
- **FR-020**: Authentication to the future cloud registry and cloud environment MUST be designed as credential-less (federated identity) with no static secrets committed or stored as long-lived credentials.
- **FR-021**: The managed registry destination and cloud authentication legs MUST be fully defined but inactive behind explicit placeholders while the cloud infrastructure does not exist, mirroring the pilot's placeholder approach, and MUST activate by value change alone when the infrastructure lands.
- **FR-022**: The signature the pipeline produces MUST be in a form the platform's later admission control can verify; performing that verification, and the runtime and continuous in-cluster security controls, are out of scope for this feature.

#### Service onboarding into gitops

- **FR-023**: Each remaining business service (the JavaScript task service, the Java user service, the web frontend, and the log-processing worker) MUST be added to the gitops repository using the established base-plus-overlay onboarding contract, changing only declared service-specific and environment-specific values and never the repository hierarchy, reconciliation mechanism, promotion model, or verification model.
- **FR-024**: Each onboarded service's managed-environment overlays MUST remain inactive scaffolds until a cluster registration selects them, consistent with the production gate already established.
- **FR-025**: Each onboarded service MUST carry the standard business-service labels, an appropriate health expression, and a least-privilege service identity as required by the onboarding contract.
- **FR-026**: A background-worker service without an inbound network endpoint MUST express health through a worker-appropriate mechanism and MUST NOT be forced into an inbound-endpoint health contract.
- **FR-027**: Every service repository MUST be wired to consume the reusable pipeline, and the correspondingly obsolete legacy per-repository pipeline MUST be retired so that only one delivery path is authoritative for each service.

#### Governance and consistency

- **FR-028**: All artifacts produced by this feature MUST be in English, consistent with the suite-wide rule.
- **FR-029**: The feature MUST preserve trunk-based development with short-lived branches and mandatory review on the pull requests it introduces.
- **FR-030**: The delivery design MUST remain valid for both the economical and full topologies the gitops repository already supports, without per-topology forks of a service's pipeline or desired-state shape.

### Key Entities *(include if feature involves data)*

- **Reusable CI Workflow**: The single shared definition of build, test, gate, and evidence behavior, parameterized by service identity and technology profile; the authoritative source consumed by all services.
- **Service Caller**: The minimal per-repository entry point that invokes the reusable workflow with that service's declared values and nothing more.
- **Immutable Image Identifier**: The content-addressed reference to a built image that is committed to desired state and promoted unchanged across environments.
- **Promotion Pull Request**: The reviewed, auditable change to the gitops repository that advances a service's image identifier in one environment; the only mechanism by which environment state changes.
- **Quality/Supply-Chain Gate**: A distinct pipeline stage in one of the constitution's required categories, each either active or explicitly skippable, whose failure (when active) blocks promotion.
- **Supply-Chain Evidence**: The per-image bill of materials and identity-based signature the pipeline produces for later verification.
- **Service Delivery Definition (gitops)**: The base-plus-overlay desired state for a service in the gitops repository, following the onboarding contract, with managed overlays as inactive scaffolds.
- **Technology Profile**: The declared classification of a service's stack that selects the appropriate build and test tooling within the reusable workflow.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Pipeline logic is defined in exactly one place; the number of copy-pasted pipeline definitions across the service repositories drops to zero, and each service repository's pipeline entry point is small enough to contain only declared values (no build, test, or deploy logic).
- **SC-002**: A single edit to the shared pipeline changes the behavior of all consuming services with zero edits to service repositories.
- **SC-003**: For every service, a release produces exactly one image referenced by an immutable identifier; zero moving-tag references are used as deployment evidence.
- **SC-004**: One hundred percent of environment changes across all services occur through gitops pull requests; zero direct cluster or platform mutations occur from continuous integration.
- **SC-005**: The same image identifier that is built appears unchanged in development, staging, and production promotions; production cannot be promoted without a recorded human approval.
- **SC-006**: Every constitution-required gate category is present as a stage in a pipeline run; the dependency-free gates run and can fail the run, and each skipped gate is explicitly and visibly marked as skipped rather than absent.
- **SC-007**: For every released image, a bill of materials and an identity-based signature are produced with zero static long-lived credentials in use.
- **SC-008**: All business services are delivered through the shared onboarding contract with zero per-service structural exceptions, and all managed-environment overlays remain inactive until a cluster registration selects them.
- **SC-009**: With the cloud infrastructure absent, the pipeline completes successfully with its cloud legs inactive; enabling the cloud path later requires only value changes (no structural edits) to activate registry, authentication, and managed deployment.
- **SC-010**: After migration, zero service repositories retain a static-credential cloud login or an imperative deployment step, and only one delivery path is authoritative per service.

## Assumptions

- The organization's shared workflow repository (`.github`) is the correct home for the reusable workflows and is writable by this work; it currently holds only profile and project assets and no reusable workflows.
- The gitops repository's existing onboarding contract, digest-only image-update helper, matrix ApplicationSet, and inactive managed-overlay scaffolds (with a registry placeholder) are the baseline this feature builds on and are not redesigned here.
- The five service repositories keep their current stacks (a compiled service, a JavaScript service, a Java service, a web frontend, and a scripting-language worker); their existing release-versioning mechanism is retained and extended to trigger the promotion pull request rather than being replaced.
- Roadmap task 1 (managed clusters, managed registry, and credential-less cloud authentication) and task 2 (platform add-ons including signature-verifying admission control and runtime security) are delivered separately; this feature designs against them but does not provision them and is not blocked by their absence.
- Cluster-side enforcement of the supply-chain evidence (signature verification, runtime security, continuous in-cluster scanning) is owned by the platform add-ons work and is out of scope here; this feature only produces the evidence.
- Authoring the actual test suites (unit, integration, contract, end-to-end, performance, dynamic security) and the API contracts is out of scope; a later feature will populate them and enable the corresponding gates.
- A publicly reachable, no-cost image registry usable for validation without the managed cloud is acceptable for exercising the build-once and promotion flow before the managed registry exists, provided the switch to the managed registry is a value change only.
- Opening automated pull requests across repositories requires a scoped automation identity with least-privilege permissions; provisioning that identity is part of this feature's setup.

### Dependencies

- The gitops repository (`microservice-app-gitops`) and its service-onboarding contract, digest-only update helper, and ApplicationSet mechanism established by roadmap task 3.
- The organization shared workflow repository (`.github`).
- The five service repositories (`auth-api`, `todos-api`, `users-api`, `frontend`, `log-message-processor`).
- The project constitution, especially the principles on GitOps-only deployment, immutable build promotion, quality and supply-chain gates, least privilege and secret hygiene, and authoritative specifications.
- Roadmap task 1 (managed registry, clusters, credential-less cloud authentication) and task 2 (admission control and runtime security) as future activators of the currently inactive cloud legs.

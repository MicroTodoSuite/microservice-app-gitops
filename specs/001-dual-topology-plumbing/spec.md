# Feature Specification: Dual-Topology Plumbing (economical & full)

**Feature Branch**: `001-dual-topology-plumbing`

**Created**: 2026-08-08

**Status**: Draft

**Input**: Make the GitOps repository serve BOTH solutions defined in the
evolution plan (§17): the economical version (single cluster, environments as
namespaces, no service mesh) and the full version (multi-cluster, environments
as clusters, Istio, Argo Rollouts canary), without forking the repo.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Retarget environments to clusters without rewriting apps (Priority: P1)

As a platform engineer, I can move from "environment = namespace in one cluster"
to "environment = its own cluster" by changing destination data only, never the
`base/` or `overlays/` of a service.

**Why this priority**: This is the single hardest seam between the two versions;
everything else is additive add-ons. Without it the repo is locked to one topology.

**Independent Test**: Change the destination server of an environment entry and
confirm the generated ArgoCD Application targets the new cluster, with no edits
to any `apps/<svc>/base` or `overlays` file.

**Acceptance Scenarios**:

1. **Given** the economical topology, **When** ArgoCD reconciles, **Then** it
   generates one Application per {service × environment} all targeting the local
   cluster in namespaces `microtodo-{env}` (same behavior as before this feature).
2. **Given** an environment entry pointed at a remote cluster URL, **When**
   ArgoCD reconciles, **Then** the Application for that environment targets the
   remote cluster, with no changes to the service's base/overlays.

### User Story 2 - Toggle version-specific behavior from one place per service (Priority: P2)

As a platform engineer, I can switch a service between economical and full
behavior (e.g. Istio sidecar injection) by editing a single file, reusing the
same `base/`.

**Why this priority**: Prevents the economical/full split from duplicating
manifests, which is exactly the copy-paste problem the migration exists to remove.

**Independent Test**: Flip one line in `topology/kustomization.yaml` and confirm
all three environment overlays render with the alternate topology.

**Acceptance Scenarios**:

1. **Given** the economical component selected, **When** rendering any overlay,
   **Then** the workload has `sidecar.istio.io/inject: "false"` and a
   `topology: economical` label.
2. **Given** the full component selected, **When** rendering any overlay,
   **Then** the workload has `sidecar.istio.io/inject: "true"` and a
   `topology: full` label — from the same base.

### User Story 3 - Select deployment strategy per environment and version (Priority: P3)

As a platform engineer, I can express the rollout strategy as a reusable module:
rolling for dev/staging, canary for prod, native (replica-based) in the
economical version and Istio-based in the full version.

**Why this priority**: Deployment strategy is the other axis that differs between
versions (§6); modeling it as a component keeps it out of the shared base.

**Independent Test**: Render the prod overlay with the canary component and
confirm an Argo Rollouts `Rollout` (referencing the base workload) plus an
`AnalysisTemplate` are produced, while dev/staging still render a `Deployment`.

**Acceptance Scenarios**:

1. **Given** dev or staging, **When** rendering, **Then** the workload is a
   standard `Deployment` (rolling update).
2. **Given** prod with the canary component, **When** rendering, **Then** a
   `Rollout` with progressive steps is produced without duplicating the pod spec.

### Edge Cases

- What happens if an environment entry omits its destination server? The
  generator must fail closed (no default silently targeting the wrong cluster).
- How does the repo behave when the canary component is selected but the Argo
  Rollouts controller is not installed? Activation MUST be explicit so the
  running economical deployment is never broken by an unschedulable CRD.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The apps ApplicationSet MUST derive each Application's destination
  (cluster server + namespace) from externalized environment data, not from
  values hardcoded in the generator template.
- **FR-002**: Adding or repointing a cluster MUST NOT require editing any
  `apps/<service>/base` or `apps/<service>/overlays` file.
- **FR-003**: The economical topology MUST remain the active, running default;
  this feature MUST NOT change the live behavior of the economical deployment.
- **FR-004**: Version-specific workload behavior MUST be expressed as Kustomize
  Components reused across all environments of a service.
- **FR-005**: Selecting economical vs full for a service MUST be a single-file
  change per service (`topology/kustomization.yaml`).
- **FR-006**: The prod deployment strategy MUST be expressible as a canary
  `Rollout` that reuses the base pod template (no duplication).
- **FR-007**: Canary activation MUST be explicit and MUST NOT be applied to a
  cluster lacking the Argo Rollouts controller.

### Key Entities

- **Environment entry**: `{ name, server, namespacePrefix }` — the mapping from a
  logical environment to a physical destination. The whole economical/full
  difference for targeting lives here.
- **Topology component**: economical | full — reusable workload behavior fragment.
- **Strategy component**: rolling (base) | canary — reusable rollout fragment.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Moving one environment from a namespace target to a remote-cluster
  target requires editing exactly one data entry and zero service manifests.
- **SC-002**: Switching a service economical↔full is one line in one file.
- **SC-003**: All three overlays render valid Kubernetes manifests under both
  topology components (schema-validated).
- **SC-004**: The economical deployment running in the local cluster is byte-for
  -byte unchanged in behavior after this feature (same pods, same selectors).

## Assumptions

- Real EKS/ECR/IRSA values (tasks 1-2) do not exist yet; remote-cluster entries
  are prepared with placeholders and validated by schema, not by live sync.
- The Argo Rollouts controller is not yet installed in the local cluster; the
  canary component is delivered as an activatable module, not wired into the
  running overlays.
- Istio is a full-version add-on owned by task 2; the full topology component
  only sets the injection contract, it does not install the mesh.

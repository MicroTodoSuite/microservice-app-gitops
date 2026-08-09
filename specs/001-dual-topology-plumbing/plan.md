# Implementation Plan: Dual-Topology Plumbing

**Branch**: `001-dual-topology-plumbing` | **Date**: 2026-08-08 | **Spec**: ./spec.md

## Summary

Make the GitOps repo serve both the economical and full solutions without
forking, by adding three seams: (1) externalized destinations in the apps
ApplicationSet so environments can be namespaces or clusters, (2) Kustomize
Components with a single per-service topology switch, and (3) a canary strategy
Component that reuses the base workload. The economical version stays the live
default; full-version pieces are prepared and schema-validated, not activated.

## Technical Context

**Language/Version**: Kubernetes manifests, Kustomize v5, ArgoCD v3.5.0 CRDs
(Application, ApplicationSet, AppProject), Argo Rollouts CRDs (Rollout,
AnalysisTemplate).

**Primary Dependencies**: kustomize, kubeconform, ArgoCD ApplicationSet
controller, Argo Rollouts controller (for canary activation only).

**Storage**: N/A (declarative manifests; state is Git + etcd).

**Testing**: `kustomize build` + `kubeconform -strict` for all overlays under
both topology components; live regression on the local kind cluster for the
economical path (same Applications, same pods).

**Target Platform**: local kind now; AWS EKS (+ Azure AKS in full) later.

**Project Type**: GitOps configuration repository.

**Constraints**: MUST NOT change live economical behavior (FR-003); canary MUST
NOT be applied without its controller (FR-007); no manifest duplication.

## Constitution Check

No ratified constitution exists yet (template only). Applied the plan's guiding
principles instead: GitOps as the only delivery path, trunk-based development,
economical/full parity as a cost decision not a rewrite. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/001-dual-topology-plumbing/
├── spec.md
├── plan.md      # this file
└── tasks.md
```

### Source Code (repository root)

```text
apps/auth-api/
├── base/                       # unchanged shared manifests
├── components/
│   ├── topology-economical/    # Component: no mesh (US2)
│   ├── topology-full/          # Component: Istio injection (US2)
│   └── strategy-canary/        # Component: Rollout + AnalysisTemplate (US3)
├── topology/                   # single per-service switch (US2)
└── overlays/{dev,staging,prod} # env-only; reference topology
clusters/
├── local-kind/apps.yaml        # ApplicationSet with externalized environments (US1)
└── README.md                   # economical vs full topology guide
```

**Structure Decision**: The `base/` stays the single source of shared truth.
Everything that differs between versions is a Component; everything that differs
between destinations is an environment data entry in the ApplicationSet. Overlays
carry only environment differences (namespace, replicas, image tag) and delegate
version differences to `topology/`.

## Complexity Tracking

| Decision | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| `topology/` indirection layer | Single-file version switch per service (SC-002) | Putting the component in each overlay = 3 edits per switch, drift risk |
| Externalized environment list | Retarget without touching services (FR-002) | Hardcoded destination in the template locks the repo to one topology |
| Rollout via `workloadRef` | Reuse base pod template (FR-006) | A full Rollout copy duplicates the pod spec = the copy-paste we remove |

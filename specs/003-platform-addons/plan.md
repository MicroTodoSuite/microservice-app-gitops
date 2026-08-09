# Implementation Plan: Local Platform Add-ons Foundation

**Branch**: `esteban/platform-addons` | **Date**: 2026-08-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-platform-addons/spec.md`

## Summary

Complete the reusable infrastructure discovery seam with four fully vendored
and checksum-pinned platform installations: KEDA 2.20.1, cert-manager 1.21.0,
External Secrets Operator 2.9.0, and Kyverno 1.18.2. Kustomize pins every
runtime image by immutable multi-platform digest, adds a controller-specific
capability check, and gives ArgoCD only the additional exact cluster-scoped
kinds present in the pinned renders. A contract test verifies provenance,
renderability, digest usage, provider neutrality, and generator coverage. A
read-only pilot verifier records ArgoCD revision/status, controller deployment
availability, capability conditions, policy reports, auth-api readiness, and
three live HTTP responses over at least 60 seconds.

The live machine already has a pilot-owned cluster, registry, and local Git
reader. The implementation therefore reuses that runtime, publishes desired
state only to its machine-local Git source, and validates the transition from
the older pilot layout to the current shared ApplicationSet layout. No direct
managed-state mutation is introduced.

## Technical Context

**Language/Version**: Kubernetes YAML; Kustomize API v1beta1; Bash 5-compatible verification scripts

**Primary Dependencies**: Kubernetes 1.36.1 live pilot, kubectl 1.36.3, Kustomize 5.8.1, ArgoCD 3.5.0, KEDA 2.20.1, cert-manager 1.21.0, External Secrets Operator 2.9.0, Kyverno 1.18.2

**Storage**: Versioned manifest bundles in Git; untracked runtime evidence under `.local/evidence/platform-addons/`

**Testing**: Kustomize renders, SHA-256 verification, kubeconform where available, Bash contract checks, read-only kubectl/ArgoCD observations, repeated curl health checks

**Target Platform**: Local kind Kubernetes cluster on Linux; provider-neutral Kubernetes for later registered clusters

**Project Type**: GitOps desired-state repository; no application runtime code

**Performance Goals**: All four add-ons converge within 10 minutes of the final local desired-state commit; auth-api returns healthy within five minutes of the post-policy commit

**Constraints**: GitOps-only after the audited bootstrap boundary; no AWS/Azure dependency; no secret values; no floating image references; no cluster-wide AppProject wildcard; full upstream controller/CRD/webhook bundles retained locally; live success evidence required

**Scale/Scope**: Four cluster add-ons, fifteen expected controller deployments including the existing auth-api deployment, three capability resources, two enforced policies, one local cluster, and the shared registration mechanism used by future clusters

## Constitution Check

*GATE: Passed before research and re-checked after design.*

| Principle | Gate | Design response |
| --- | --- | --- |
| Environment Isolation | PASS | Capability checks remain in add-on namespaces; business policy matches only `microtodo-*`. |
| GitOps-Only Deployment | PASS | Only committed local-source changes reconcile managed state; verification is read-only. |
| Stable Trunk Development | PASS | Work remains on the existing short-lived `esteban/platform-addons` branch. |
| Authoritative Specifications | PASS | Spec, plan, research, contracts, quickstart, and tasks precede implementation. |
| Cost-Governed Design | PASS | Local checks use one replica and bounded upstream resource defaults; no managed service is introduced. |
| Immutable Build Promotion | PASS | Every add-on and probe image is rendered by digest; auth-api remains digest-pinned. |
| Progressive and Reversible Releases | PASS | Add-ons and Kyverno policy are staged in separate local commits; rollback is a Git revert. |
| Quality and Supply-Chain Gates | PASS | Release checksums, provenance, immutable images, and enforced Kyverno rules are tested. |
| Observable and Resilient Operations | PASS | Controller availability and capability conditions are captured; KEDA and health probes are active. |
| Least Privilege and Secret Hygiene | PASS | No secret values are stored; ESO's live auth-api contract is revalidated; exact AppProject kinds are used. |
| Declarative and Policy-Controlled Platform | PASS | All four add-ons are ArgoCD-owned under `infrastructure/`. |
| Proven DR and Disclosed Data Loss | PASS | No DR claim or data-continuity change is made in this feature. |

Post-design re-check: PASS. The capability resources and verification contract
do not add a direct deployment path, cloud dependency, wildcard permission, or
secret value.

## Project Structure

### Documentation (this feature)

```text
specs/003-platform-addons/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── platform-addon-registration.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
clusters/base/
├── infrastructure.yaml          # shared add-on discovery
└── project.yaml                 # exact cluster-scoped permissions

infrastructure/
├── keda/
│   ├── kustomization.yaml
│   ├── capability-check.yaml
│   └── vendor/v2.20.1/{install.yaml,README.md,SHA256SUMS}
├── cert-manager/
│   ├── kustomization.yaml
│   ├── capability-check.yaml
│   └── vendor/v1.21.0/{install.yaml,README.md,SHA256SUMS}
├── external-secrets/
│   ├── kustomization.yaml
│   └── vendor/v2.9.0/{manifests.yaml,README.md,SHA256SUMS}
└── kyverno/
    ├── kustomization.yaml
    ├── policies.yaml
    └── vendor/v1.18.2/{install.yaml,README.md,SHA256SUMS}

apps/auth-api/overlays/local/
└── kustomization.yaml            # post-policy pod-template admission marker

scripts/pilot/
├── lib/common.sh                 # context override support
└── verify-platform.sh            # read-only composite live evidence

tests/contract/
└── platform-addons.sh            # static provenance/render/provider contract
```

**Structure Decision**: Keep each add-on as a self-contained Kustomize root so
the existing `infrastructure/*` Git directory generator remains the only
registration mechanism. Version directories are explicitly excluded from
application discovery. Capability resources sit beside, not inside, vendor
bundles so upstream files remain byte-verifiable.

## Complexity Tracking

No constitution violation or exception is required.

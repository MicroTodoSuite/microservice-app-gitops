# Tasks: Local Platform Add-ons Foundation

**Input**: Design documents from `specs/003-platform-addons/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/platform-addon-registration.md`, `quickstart.md`

**Tests**: Required by FR-018 and by the user's demand for live evidence rather
than configuration-only success.

## Phase 1: Setup (Validation First)

**Purpose**: Encode the missing behavior as failing checks before filling the
placeholder infrastructure folders.

- [x] T001 Create the failing provenance, checksum, full-bundle, immutable-image, exact-permission, provider-neutrality, and four-application render checks in `tests/contract/platform-addons.sh`
- [x] T002 Create the read-only composite verifier skeleton and expected application/controller/capability inventory in `scripts/pilot/verify-platform.sh`
- [x] T003 Allow an explicitly supplied pilot context without changing the safe default in `scripts/pilot/lib/common.sh`

---

## Phase 2: Foundational (Pinned Inputs and Trust Boundary)

**Purpose**: Retain verified inputs and extend the reusable ArgoCD boundary
before any capability resource is introduced.

**CRITICAL**: No live desired-state publication occurs until the retained
bundles pass checksums and all four Kustomize roots render locally.

- [x] T004 [P] Vendor KEDA 2.20.1 with provenance and checksum under `infrastructure/keda/vendor/v2.20.1/`
- [x] T005 [P] Vendor cert-manager 1.21.0 with provenance and checksum under `infrastructure/cert-manager/vendor/v1.21.0/`
- [x] T006 [P] Record the existing External Secrets Operator 2.9.0 bundle checksum and chart-index provenance in `infrastructure/external-secrets/vendor/v2.9.0/`
- [x] T007 [P] Vendor Kyverno 1.18.2 with provenance and checksum under `infrastructure/kyverno/vendor/v1.18.2/`
- [x] T008 Add only `apiregistration.k8s.io/APIService` and `kyverno.io/ClusterPolicy` to the exact cluster resource whitelist in `clusters/base/project.yaml`
- [x] T009 Verify the shared four-folder discovery and vendor exclusion contract in `clusters/base/infrastructure.yaml` with `tests/contract/platform-addons.sh`

**Checkpoint**: Every retained release bundle matches its recorded checksum,
and the AppProject can represent the exact pinned renders without a wildcard.

---

## Phase 3: User Story 1 - Reconcile a complete local platform (Priority: P1)

**Goal**: Produce four complete, immutable, functional add-on Kustomize roots.

**Independent Test**: Render all four roots, publish the staged local desired
state, and observe four Synced/Healthy Applications, all expected Deployments
Available, plus Ready KEDA/cert-manager/ESO/Kyverno capability conditions.

### Tests for User Story 1

- [x] T010 [P] [US1] Extend `tests/contract/platform-addons.sh` with exact expected Deployment, image digest, sync-wave, and capability-resource assertions for all four folders

### Implementation for User Story 1

- [x] T011 [P] [US1] Add the complete KEDA install, four immutable image transforms, and functional ScaledObject check in `infrastructure/keda/kustomization.yaml` and `infrastructure/keda/capability-check.yaml`
- [x] T012 [P] [US1] Add the complete cert-manager install, immutable controller/ACME solver references, and self-signed certificate check in `infrastructure/cert-manager/kustomization.yaml` and `infrastructure/cert-manager/capability-check.yaml`
- [x] T013 [P] [US1] Add the immutable ESO 2.9.0 image transform while preserving the auth-api secret contract in `infrastructure/external-secrets/kustomization.yaml`
- [x] T014 [P] [US1] Add the complete Kyverno install, five immutable image transforms, and initial Audit-mode capability policies in `infrastructure/kyverno/kustomization.yaml` and `infrastructure/kyverno/policies.yaml`
- [x] T015 [US1] Complete wait loops, raw evidence writers, controller availability checks, capability checks, pod-state checks, and revision matching in `scripts/pilot/verify-platform.sh`
- [x] T016 [US1] Make the static contract pass for all four rendered add-on roots with `tests/contract/platform-addons.sh`
- [x] T017 [US1] Publish the KEDA, cert-manager, ESO, and Kyverno installation desired state as staged commits to `.local/git/microservice-app-gitops.git` branch `main`, then wait for every infrastructure Application, controller, and Audit policy report to become Synced/Healthy/Available without direct cluster mutation

**Checkpoint**: All four full controller installations are live through ArgoCD;
KEDA, cert-manager, and ESO capability checks pass before policy enforcement.

---

## Phase 4: User Story 2 - Preserve auth-api under admission policy (Priority: P2)

**Goal**: Enforce the local policy baseline and prove a newly admitted auth-api
rollout remains healthy.

**Independent Test**: Kyverno policies reach Ready, a later auth-api pod-template
commit creates an admitted pod, both report results pass, ArgoCD returns the app
to Synced/Healthy, and `/version` returns HTTP 200 three times over 60 seconds.

### Tests for User Story 2

- [x] T018 [P] [US2] Add Enforce-mode, namespace-scope, immutable-image, liveness/readiness-probe, and background-report assertions to `tests/contract/platform-addons.sh`

### Implementation for User Story 2

- [x] T019 [US2] Promote the verified digest and health-probe ClusterPolicies from Audit to Enforce while retaining post-controller sync ordering in `infrastructure/kyverno/policies.yaml`
- [x] T020 [US2] Publish the Kyverno enforcement commit to `.local/git/microservice-app-gitops.git` branch `main` and wait for both ClusterPolicies to report Ready before changing auth-api
- [x] T021 [US2] Add a stable policy-baseline pod-template annotation in `apps/auth-api/overlays/local/kustomization.yaml` so the subsequent desired-state commit forces fresh admission
- [x] T022 [US2] Publish the post-policy auth-api commit to `.local/git/microservice-app-gitops.git` branch `main`, wait for a new available ReplicaSet and matching ArgoCD revision, and prove both Kyverno report results pass through `scripts/pilot/verify-platform.sh`
- [x] T023 [US2] Run three live auth-api `/version` probes over at least 60 seconds and retain their timestamps, status codes, latencies, and bodies under `.local/evidence/platform-addons/`

**Checkpoint**: Kyverno is enforcing, not auditing, and auth-api is freshly
admitted, Synced, Healthy, Available, policy-compliant, and live.

---

## Phase 5: User Story 3 - Reuse the platform for future clusters (Priority: P3)

**Goal**: Prove the shared platform is provider-neutral and registration-driven.

**Independent Test**: The local registration render yields exactly four
infrastructure Applications; add-on folders contain no provider dependency; and
all controller installation paths remain unchanged for a new registration.

### Tests for User Story 3

- [x] T024 [P] [US3] Add reusable-registration, exact-four-application, no-AWS/Azure-dependency, and no-provider-SecretStore/issuer assertions to `tests/contract/platform-addons.sh`

### Implementation for User Story 3

- [x] T025 [P] [US3] Document the provider-neutral controller boundary and future registration extension points in `docs/platform-addons.md`
- [x] T026 [US3] Render `clusters/local-kind` and every `infrastructure/*` root, prove the exact registration contract, and make the User Story 3 checks pass in `tests/contract/platform-addons.sh`

**Checkpoint**: Adding a cluster registration consumes the shared four-add-on
mechanism without copying or redesigning an installation folder.

---

## Phase 6: Polish & Cross-Cutting Validation

**Purpose**: Re-run every static and live acceptance path and reconcile the
request against exact evidence.

- [x] T027 Verify `.specify/memory/constitution.md` is byte-identical to `../microservice-app-docs/constitution.md` version 1.1.0 and leave it unchanged if already equal
- [x] T028 Run `kustomize build` and kubeconform when available for all four add-ons plus the local registration, run `tests/contract/platform-addons.sh`, and run `git diff --check`
- [x] T029 Run `scripts/pilot/verify-platform.sh` against `kind-microtodo-gitops-pilot`, inspect ArgoCD application conditions and add-on logs for hidden degradation, and retain the final untracked evidence set
- [x] T030 Record why conditional bootstrap was or was not required and compare the verified pre-change baseline with the final live revision, four add-on statuses, controller availability, capability conditions, policy reports, auth-api rollout, and HTTP results against FR-001 through FR-018 and SC-001 through SC-008 in `specs/003-platform-addons/checklists/acceptance.md`

---

## Dependencies & Execution Order

### Phase dependencies

```text
Setup validation
    -> Pinned inputs and trust boundary
        -> US1 complete controller platform
            -> US2 Kyverno enforcement and auth-api re-admission
                -> US3 provider-neutral reuse proof
                    -> Final static and live acceptance
```

- T001-T003 establish the validation and context plumbing.
- T004-T009 block every live publication.
- T011-T014 own separate add-on folders and may proceed in parallel after their
  matching vendor task; T015 integrates the live inventory.
- T017 is serialized because all Applications share one local cluster.
- T019-T020 must complete before T021-T023 so Kyverno is active before the
  auth-api pod template changes.
- T024-T026 are static reuse checks and do not modify the live cluster.
- T027-T030 run only after the final source revision is healthy.

## Parallel Opportunities

```text
T004 KEDA vendor || T005 cert-manager vendor || T006 ESO provenance || T007 Kyverno vendor
T011 KEDA root   || T012 cert-manager root    || T013 ESO root       || T014 Kyverno root
T024 reuse tests || T025 platform documentation
```

Tasks that publish commits or observe the shared cluster remain sequential.

## Implementation Strategy

1. Encode contract failures first.
2. Retain and checksum all upstream inputs.
3. Build and statically validate one self-contained root per add-on.
4. Reconcile complete controllers and non-policy capability checks.
5. Activate Kyverno enforcement as its own rollback point.
6. Force and verify a post-policy auth-api admission as a later commit.
7. Close with provider-neutrality, render, live revision, and repeated HTTP
   evidence.

## Notes

- Local pilot commits are runtime evidence and remain in the machine-local bare
  repository; this task list does not authorize committing the developer branch.
- A live Kubernetes 1.36 pass closes this pilot's compatibility risk but does not
  extend the upstream KEDA/Kyverno support matrices.
- Missing or failed live evidence remains a failure; it must not be converted to
  a pass based on rendered configuration.

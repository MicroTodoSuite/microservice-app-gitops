# Acceptance Evidence: Local Platform Add-ons Foundation

**Recorded**: 2026-08-09  
**Result**: PASS  
**Live context**: `kind-microtodo-gitops-pilot`  
**Final local source revision**: `111186a8d6bb4ea8d5a4a647fd9166bcd180caf2`

This record is based on commands run against this machine during the feature
implementation. It does not use `docs/reconciliation-notes-v2.md` as evidence.

## Conditional bootstrap decision

The repository checkout began clean on branch `esteban/platform-addons` at
`239b6a8`. A pilot-owned runtime was already present and reachable:

- kind control plane: `microtodo-gitops-pilot-control-plane`;
- Kubernetes context: `kind-microtodo-gitops-pilot`;
- node: Ready, Kubernetes 1.36.1;
- loopback registry: `kind-registry` on `127.0.0.1:5001`;
- machine-local Git source: `microtodo-git-source` on `127.0.0.1:8081`; and
- pilot ownership label: `io.microtodosuite.local-gitops-pilot=true` on the
  local registry and Git source.

The conditional in FR-002 therefore did not apply. `scripts/pilot/bootstrap.sh`
was not run, bootstrap elapsed time is **N/A**, and no bootstrap success or
intervention claim is made.

One 10.338-second Docker restart of the existing kind control-plane container
was required during migration recovery so ArgoCD could recreate its automatic
`default` project. This was not a bootstrap and did not directly apply, patch,
scale, restart, or delete a GitOps-managed Kubernetes workload.

## Verified pre-change baseline

| Area | Direct observation before publication |
| --- | --- |
| Checkout | Clean branch `esteban/platform-addons`, HEAD `239b6a8`; hosted `origin/main` pointed to the same commit. |
| Local desired state | Bare `main` was `a6f9c24119cc48f63a973c5704e992b1aef27191`, older than the checkout. |
| ArgoCD | `argocd`, `auth-api-local`, `environment`, `external-secrets`, and `root` were all Synced/Healthy at `a6f9c241...`. |
| auth-api | Deployment was 1/1 Available, using `localhost:5001/auth-api@sha256:ba9e69e7d03dfc5d34fe69c5188451aac3c8e4301e73168ef152b57e95ced02e`. |
| Secret delivery | `ExternalSecret/auth-api-secrets` was Ready=True with reason `SecretSynced`. |
| HTTP | Three direct `/version` probes returned HTTP 200 and body `Auth API, written in Go`; observed latencies were approximately 0.0026s, 0.0018s, and 0.0018s. |
| Infrastructure tree | ESO 2.9.0 and its Kustomization already existed. KEDA, cert-manager, and Kyverno contained only `.keep` placeholders. Argo Rollouts remained an inactive placeholder. |
| Constitution | `.specify/memory/constitution.md` already matched the ratified sibling copy at version 1.1.0 and was left unchanged. |

## Existing work versus feature work

| Capability | Already existed | Added or completed here |
| --- | --- | --- |
| Registration | Shared ApplicationSet scaffolding | Exact four-root discovery contract, vendor and Argo Rollouts exclusions, `infra-<folder>` naming checks, destination permissions, and a permanent least-privilege root project. |
| KEDA | Placeholder directory | Full 2.20.1 bundle, four digest-pinned images, operator/metrics/admission controllers, and a live ScaledObject/HPA capability check. |
| cert-manager | Placeholder directory | Full 1.21.0 bundle, four digest-pinned image references including ACME solver, controller/cainjector/webhook, and a self-signed Certificate capability check. |
| ESO | Full 2.9.0 manifest and live operator | Verified checksum/provenance, immutable image transform, self-contained ordered Namespace, and preservation of auth-api's existing ExternalSecret contract. |
| Kyverno | Placeholder directory | Full 1.18.2 bundle, five digest-pinned images, four controllers, strict CRD normalization, and two scoped Enforce-mode ClusterPolicies. |
| auth-api compatibility | Healthy pre-policy workload | Preserved its immutable Deployment selector and added a stable pod-template marker to force fresh post-policy admission. |
| Verification | auth-api-only pilot verifier | Four-add-on static contract plus a read-only composite live verifier with retained revision, workload, capability, policy-report, pod-state, and HTTP evidence. |
| Documentation | Pilot quickstart and bootstrap boundary | Full Spec Kit lifecycle artifacts and `docs/platform-addons.md` describing the reusable provider-neutral boundary. |

## Retained upstream inputs

All four checksum validations passed.

| Add-on | Version | Retained bundle SHA-256 |
| --- | --- | --- |
| KEDA | 2.20.1 | `11c2c88a126c33d21a81315c9462ba410e27a87598b5ddae7a1fdd6eff376ef7` |
| cert-manager | 1.21.0 | `6e499c3f1ab356abe79a7853911f80cb09c213885bfdf81092fdff142ba63c4a` |
| External Secrets Operator | 2.9.0 | `c3edcbf5184a31f3b2249ae303403ed5bbe59a7c7b9b2b791eaba019c73079b1` |
| Kyverno | 1.18.2 | `3dcd43eaf11f0719084217148cd0c82a8fa49faa9b1a783ea5bea2cf84041bda` |

## Reconciliation timeline

Every desired-state change below was a commit to the machine-local bare Git
source followed by automatic ArgoCD reconciliation. No direct managed-state
`kubectl apply`, patch, scale, rollout, create, replace, or delete command was
used.

| UTC event | Evidence |
| --- | --- |
| 16:44:37 | Audit-stage normalization commit `1705b394...` was created. |
| 16:45:05 | auth-api and all four add-on Applications were Synced/Healthy at `1705b394...` (28 seconds after commit). |
| 16:47:06 | Kyverno Enforce commit `4f5567af...` was created. |
| 16:48:10 | Kyverno was Synced/Healthy; both policies were `Enforce`, Ready=True (64 seconds after commit). |
| 16:49:06 | Post-policy auth-api rollout commit `111186a8...` was created. |
| 16:50:04 | New ReplicaSet `auth-api-6f5f7c8bb9` and Pod `auth-api-6f5f7c8bb9-qw77d` were created with marker `kyverno-v1`. |
| 16:50:11 | auth-api returned to Synced/Healthy at `111186a8...` (65 seconds after commit). |
| 16:50:41-16:51:49 | The composite verifier passed and retained its raw evidence. |

### Migration defects found and corrected

The older live registration exposed two real handoff defects:

1. Pruning the legacy ESO Application removed its namespace and webhook before
   auth-api's ExternalSecret finalizer completed. A Git commit made the ESO
   Namespace self-contained at sync wave -1; ESO recreated its webhook and the
   finalizer chain completed without a direct cluster patch.
2. The root Application pruned the `default` AppProject it still depended on.
   Desired state now permanently retains and restricts that project. Restarting
   the kind control plane caused ArgoCD to recreate the automatic project; root
   immediately narrowed it from Git and returned to Synced/Healthy.

The live install also identified and corrected exact desired-state gaps: KEDA
and cert-manager require narrowly named RBAC objects in `kube-system`, and the
API server normalizes empty labels and defaults on Kyverno's newer CRDs and
ClusterPolicies. These corrections are explicit desired state rather than broad
ArgoCD difference ignores.

## Final live evidence

### ArgoCD Applications

All Applications had an empty conditions list and the same source revision.

| Application | Sync | Health | Revision |
| --- | --- | --- | --- |
| `auth-api-local` | Synced | Healthy | `111186a8d6bb4ea8d5a4a647fd9166bcd180caf2` |
| `infra-keda` | Synced | Healthy | `111186a8d6bb4ea8d5a4a647fd9166bcd180caf2` |
| `infra-cert-manager` | Synced | Healthy | `111186a8d6bb4ea8d5a4a647fd9166bcd180caf2` |
| `infra-external-secrets` | Synced | Healthy | `111186a8d6bb4ea8d5a4a647fd9166bcd180caf2` |
| `infra-kyverno` | Synced | Healthy | `111186a8d6bb4ea8d5a4a647fd9166bcd180caf2` |

`argocd`, `env-local`, and `root` were also Synced/Healthy at the same revision.

### Workloads and capabilities

| Capability | Deployment availability | Functional condition |
| --- | --- | --- |
| KEDA | 4/4 expected Deployments had 1/1 available replicas. | ScaledObject Ready=True (`ScaledObjectReady`), Active=True; HPA `keda-hpa-platform-autoscaling-check` exists. |
| cert-manager | 3/3 expected Deployments had 1/1 available replicas. | Certificate Ready=True; TLS Secret `platform-certificate-check-tls` exists. |
| ESO | 3/3 expected Deployments had 1/1 available replicas. | ExternalSecret Ready=True, reason `SecretSynced`. |
| Kyverno | 4/4 expected Deployments had 1/1 available replicas. | Both ClusterPolicies are Enforce and Ready=True. |
| auth-api | Deployment had 1/1 available replicas. | New Pod Running/Ready with immutable image and `kyverno-v1` marker. |

Every final add-on and auth-api Pod was Running and Ready. The focused final
five-minute controller log scan found no warning, error, fatal, or panic entry.
Earlier install-time connection, optimistic-lock, and discovery retries ceased
after their dependent controllers became ready. ESO's recorded restarts
predated convergence; KEDA's one operator restart ended with exit code 0.

Kyverno reports for `auth-api-6f5f7c8bb9-qw77d` contained:

| Policy | Rule | Result |
| --- | --- | --- |
| `require-immutable-images` | `require-sha256-digest` | pass |
| `require-health-probes` | `require-liveness-and-readiness` | pass |

### HTTP observation window

| Check | UTC timestamp | HTTP | Latency | Body |
| --- | --- | --- | --- | --- |
| 1 | 16:50:48 | 200 | 0.011237s | `Auth API, written in Go` |
| 2 | 16:51:19 | 200 | 0.001945s | `Auth API, written in Go` |
| 3 | 16:51:49 | 200 | 0.002233s | `Auth API, written in Go` |

The measured observation window was 61 seconds. Raw evidence is retained in the
ignored local runtime directory:
`.local/evidence/platform-addons/20260809T165041Z/`.

## Repository validation

- `kubectl kustomize` (embedded Kustomize 5.8.1) rendered KEDA, cert-manager,
  ESO, Kyverno, and `clusters/local-kind` successfully.
- `./tests/contract/platform-addons.sh`: PASS.
- Bundle SHA-256 checks: PASS for all four retained bundles.
- Provider-dependency scan of first-party desired state: clean.
- Exact cluster-scoped AppProject wildcard scan: clean.
- `bash -n` for the verifier, shared pilot helpers, and contract: PASS.
- `git diff --check`: PASS.
- Standalone `kustomize` and `kubeconform` were not installed, so those optional
  executables were not claimed as run.
- Constitution comparison: byte-identical, SHA-256
  `267979bfe81e2d0db1ddc4ef9340d1f89aef3e3b2f9beb7dbb1577e77c172c30`,
  version 1.1.0.

## Functional requirement disposition

| Requirement | Result | Evidence |
| --- | --- | --- |
| FR-001 | PASS | Checkout, runtime ownership, context, Argo state, auth readiness, local revision, and three live baseline HTTP calls were inspected before publication. |
| FR-002 | N/A (condition false) | A pilot-owned cluster was already running; no bootstrap claim was made. |
| FR-003 | PASS | All managed changes were local Git commits reconciled automatically; the verifier enforces read-only kubectl verbs. |
| FR-004 | PASS | Four pinned full bundles, provenance notes, and matching checksums are retained. |
| FR-005 | PASS | Static discovery finds exactly KEDA, cert-manager, ESO, and Kyverno; live ArgoCD generated exactly those four infrastructure Applications. |
| FR-006 | PASS | Shared template uses prune, self-heal, server-side apply, namespace creation, and explicit destination namespaces. |
| FR-007 | PASS | Exact cluster kinds include Namespace, CRD, cluster RBAC, admission webhooks, APIService, and ClusterPolicy; no group/kind wildcard exists. |
| FR-008 | PASS | Three KEDA controllers plus capability Deployment are Available; ScaledObject is Ready/Active. |
| FR-009 | PASS | Three cert-manager controllers are Available; Certificate and TLS Secret are ready. |
| FR-010 | PASS | Three ESO controllers are Available; auth-api ExternalSecret remains SecretSynced. |
| FR-011 | PASS | Four Kyverno controllers are Available; both scoped baseline policies are Enforce/Ready. |
| FR-012 | PASS | Capability resources use post-controller sync wave 1 and reconciled successfully. |
| FR-013 | PASS | Commit `111186a8...` created a newly admitted ReplicaSet/Pod and auth-api returned to Synced/Healthy. |
| FR-014 | PASS | Composite evidence retains revision, statuses, deployments, capabilities, pod state, policy reports, and three HTTP 200 responses over 61 seconds. |
| FR-015 | PASS | First-party platform and documentation scan contains no provider runtime dependency or provider store/issuer. |
| FR-016 | PASS | Four installation folders are consumed only through the shared folder-driven ApplicationSet; registration extension points are documented. |
| FR-017 | PASS | Local constitution was already byte-identical to ratified 1.1.0 and was not rewritten. |
| FR-018 | PASS | Contract rejects missing bundles/checksums, mutable images, incomplete controller inventory, render errors, wildcards, provider dependencies, incorrect policy mode, and mutating verifier commands. |

## Success criterion disposition

| Criterion | Result | Measurement |
| --- | --- | --- |
| SC-001 | PASS | All four add-ons reached Synced/Healthy 28 seconds after the final Audit-stage normalization commit. |
| SC-002 | PASS | 14/14 expected platform Deployments were fully Available; zero final Pending/Failed/Unknown/crash-loop/image-pull Pods. |
| SC-003 | PASS | ScaledObject, Certificate, ExternalSecret, and enforced Kyverno report checks all passed live. |
| SC-004 | PASS | auth-api returned to Synced/Healthy 65 seconds after its post-policy commit and returned three HTTP 200 responses over 61 seconds. |
| SC-005 | PASS | Provider scan and cluster wildcard scan both returned zero findings. |
| SC-006 | PASS | Exactly four active infrastructure roots and four live generated infrastructure Applications were observed without changing an add-on folder per registration. |
| SC-007 | PASS | Four SHA-256 validations, five renders, and the full policy/static contract passed. |
| SC-008 | PASS | Every final live Application and retained verifier artifact points to `111186a8d6bb4ea8d5a4a647fd9166bcd180caf2`. |

## Compatibility note

KEDA 2.20.1 logs that it has not been upstream-tested on Kubernetes 1.36.1.
This local run supplies direct compatibility evidence for the pilot, but it does
not extend the upstream support matrix. Version upgrades remain explicit,
checksum-reviewed changes.

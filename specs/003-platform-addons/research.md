# Research: Local Platform Add-ons Foundation

## Decision 1: Reuse the independently verified running pilot

**Decision**: Reuse the running `microtodo-gitops-pilot` kind cluster, its
pilot-labeled local registry and Git reader, and the local bare repository after
capturing fresh baseline evidence.

**Rationale**: The user made clean bootstrap conditional on no pilot-owned local
cluster running. The node is Ready, ArgoCD is reachable, the existing source
revision equals the applications' observed revision, auth-api is 1/1 Available,
its ExternalSecret is Ready, and three new HTTP probes returned 200 over roughly
60 seconds. Reuse avoids an unnecessary destructive teardown.

**Alternatives considered**:

- Delete and recreate the existing cluster: rejected because the condition was
  false and cleanup would destroy material local evidence without need.
- Trust previous evidence files: rejected because the user explicitly required
  observations from this machine and session.

## Decision 2: Use current stable upstream release bundles

**Decision**:

| Add-on | Release | Bundle source | Bundle SHA-256 |
| --- | --- | --- | --- |
| KEDA | 2.20.1 | `https://github.com/kedacore/keda/releases/download/v2.20.1/keda-2.20.1.yaml` | `11c2c88a126c33d21a81315c9462ba410e27a87598b5ddae7a1fdd6eff376ef7` |
| cert-manager | 1.21.0 | `https://github.com/cert-manager/cert-manager/releases/download/v1.21.0/cert-manager.yaml` | `6e499c3f1ab356abe79a7853911f80cb09c213885bfdf81092fdff142ba63c4a` |
| External Secrets Operator | 2.9.0 | Official Helm chart render documented by the existing vendor folder | `c3edcbf5184a31f3b2249ae303403ed5bbe59a7c7b9b2b791eaba019c73079b1` |
| Kyverno | 1.18.2 | `https://github.com/kyverno/kyverno/releases/download/v1.18.2/install.yaml` | `3dcd43eaf11f0719084217148cd0c82a8fa49faa9b1a783ea5bea2cf84041bda` |

**Rationale**: KEDA 2.20.1 and Kyverno 1.18.2 are the latest stable patch
releases exposed by their official release pages; cert-manager 1.21.0 is the
current supported release and explicitly supports/tested Kubernetes 1.33-1.36;
the official External Secrets chart index published 2.9.0 on 2026-08-08 with
chart digest `da2d5c126a103b4c1b16a9dc1c168c4332a3687144e88ac070e594f81a0b6578`.

KEDA 2.20 and Kyverno 1.18 document tested Kubernetes ranges ending at 1.35,
while the local node is 1.36.1. That gap is retained as an explicit risk and is
closed for this pilot only by the required live reconciliation and capability
checks; it is not converted into a general upstream-support claim.

**Alternatives considered**:

- Floating latest manifests or remote Kustomize bases: rejected because they
  are not reproducible and make Git cease to be the complete desired state.
- Pre-release KEDA or Kyverno versions for a wider speculative range: rejected
  because a stable release plus live proof is lower risk than unratified code.
- Re-render all add-ons from Helm: rejected because official static release
  bundles exist for three add-ons and the existing ESO bundle already records
  its exact chart-render command.

## Decision 3: Pin every executable image by multi-platform digest

**Decision**: Keep versioned upstream names for readability and use Kustomize
image transforms to render the following immutable index digests:

| Image | Digest |
| --- | --- |
| `ghcr.io/kedacore/keda:2.20.1` | `sha256:8888d1896d316c9e087ce0ca3b72bd945dfbad6f3ef2d64ca24ee394feccc023` |
| `ghcr.io/kedacore/keda-metrics-apiserver:2.20.1` | `sha256:ba32172082a2ff935d5b62ffa0bd0698424d373b55c5cae0846db057e237b28e` |
| `ghcr.io/kedacore/keda-admission-webhooks:2.20.1` | `sha256:0350cbb59471123623134801a3e9a753c90e0945bb4eb7e36086746fc4b35fb8` |
| `registry.k8s.io/pause:3.10.1` | `sha256:278fb9dbcca9518083ad1e11276933a2e96f23de604a3a08cc3c80002767d24c` |
| `quay.io/jetstack/cert-manager-controller:v1.21.0` | `sha256:e370f7800a53078e9d74324287a7d52b553864e55f5b4e521f911c3f6c7da203` |
| `quay.io/jetstack/cert-manager-cainjector:v1.21.0` | `sha256:ad1dcc5b2fccc420f9b3fbee7ce8a869450c540fd4f2f41de2d95b1ca0c4d701` |
| `quay.io/jetstack/cert-manager-webhook:v1.21.0` | `sha256:c33cca307541e2d58861a55b1af5f390b7e19c8741e48b433693b73a7cce88b3` |
| `quay.io/jetstack/cert-manager-acmesolver:v1.21.0` | `sha256:33ebbc2688578e37bd48dcc5b6b1f1362c919dff44fe5e5f602532a2d37d514f` |
| `ghcr.io/external-secrets/external-secrets:v2.9.0` | `sha256:44eb290f1c7f5d8f4eec2168cea4a6cfbc72a955c6781eb835e1c40700475dbd` |
| `reg.kyverno.io/kyverno/kyverno:v1.18.2` | `sha256:0a540e2ddf74d0d2d3d45f9ef248d7dbc96576accdbcc6a2dd7eaff9fea56504` |
| `reg.kyverno.io/kyverno/background-controller:v1.18.2` | `sha256:d62566ce41bd0d4a32bf2cf44b9ebfc02c36374f821f83070890287f62f68671` |
| `reg.kyverno.io/kyverno/cleanup-controller:v1.18.2` | `sha256:b0395d29ae332276e6910eb40418be9bc127c068d659f90aa1bcddd6be99ccb4` |
| `reg.kyverno.io/kyverno/reports-controller:v1.18.2` | `sha256:f09cf305170014e191b94e1c54f5be73163d8824eefad49349675c4efe43159a` |
| `reg.kyverno.io/kyverno/kyvernopre:v1.18.2` | `sha256:cd8cb4a31d25b3992734fb8f24a90ef691c90ce49338c89bea96792160eacb98` |

**Rationale**: Multi-platform index digests preserve portability while
preventing a tag from changing the running artifact. cert-manager's ACME solver
appears in a controller argument rather than a pod image field, so it requires
an explicit deployment patch in addition to image transforms.

**Alternatives considered**:

- Version tags only: rejected because the repository convention requires
  immutable image evidence.
- Architecture-specific digests: rejected because they would unnecessarily
  prevent reuse on ARM clusters.

## Decision 4: Prove capability, not only controller liveness

**Decision**:

- KEDA manages a one-replica, digest-pinned pause Deployment and a cron-backed
  ScaledObject constrained to one replica; the ScaledObject must be Ready.
- cert-manager manages a self-signed namespaced Issuer and Certificate; the
  Certificate must be Ready and its Secret must exist.
- ESO retains the already useful Password generator plus ExternalSecret path;
  the auth-api ExternalSecret must stay Ready/SecretSynced.
- Kyverno installs two ClusterPolicies scoped to `microtodo-*` Pods, requiring
  digest-pinned images plus liveness and readiness probes. They begin in Audit
  mode to prove policy reconciliation and background reports without coupling
  controller installation to admission. A later, separate commit promotes both
  to Enforce before auth-api is re-admitted. The policies must be Ready and
  their auth-api report results must pass in both stages.

**Rationale**: Available Deployments show process health but not a working
reconciliation API. These small, self-contained resources exercise each
controller without an AWS/Azure service or credential.

**Alternatives considered**:

- Controller pods only: rejected as configuration-level evidence.
- External Kafka, ACME, or cloud secret stores: rejected because they violate
  local/provider-neutral scope.
- Stopping at Kyverno Audit mode: rejected because it would not prove the
  existing service survives actual admission enforcement.

## Decision 5: Reconcile in dependency-safe stages

**Decision**: Vendor and validate statically first. Publish KEDA,
cert-manager, and the ESO digest hardening; wait for their applications and
capability resources. Publish Kyverno with Audit policies; wait for controller,
policy, and report readiness. Promote those same policies to Enforce in a
separate commit. Finally publish a benign auth-api pod-template annotation to
force a new admission and rollout, then run the composite verification.

Within each add-on, upstream installation resources use Argo sync wave 0 and
capability/policy resources use wave 1. The root AppProject uses wave -2.

**Rationale**: Admission and certificate resources can fail if submitted before
their webhooks have a serving certificate. Separate Git revisions also make the
Kyverno compatibility proof and rollback point auditable.

**Alternatives considered**:

- One monolithic commit: rejected because it cannot isolate a policy-induced
  failure or demonstrate the requested post-Kyverno auth-api resync.
- Direct manual sync: rejected by the GitOps-only constitution.

## Decision 6: Preserve one reusable registration mechanism

**Decision**: Keep the existing `infrastructure/*` directory generator and
exclude vendor directories. No provider-specific overlay is added to an add-on
folder. A future cluster consumes `clusters/base`; only its registration values
and environment activation differ.

**Rationale**: Controller installation is cluster-generic. Provider-specific
issuers, event sources, and external secret stores are environment-owned values
added when those environments exist; their extension points are already the
native CRDs installed here, so no delivery redesign is required.

**Alternatives considered**:

- Copy add-on manifests per cluster: rejected because it creates version and
  ownership drift.
- Put AWS SecretStore or issuer examples in the shared folders: rejected because
  the user forbids AWS/Azure dependencies in this local foundation.

# Research: Local GitOps Pilot Reconciliation

**Date**: 2026-08-08

This research resolves the technical choices needed for reconciliation gaps 3
through 10 while preserving the existing App-of-Apps, ApplicationSet, and
`auth-api` base/overlay implementation baseline.

## Decision 1: Machine-local Git source

**Decision**: Create an ignored bare repository under `.local/git/`, push pilot
commits to it through a filesystem remote named `pilot`, and expose it read-only
to ArgoCD through a digest-pinned static HTTP server attached to the Kind Docker
network. Enable the bare repository's standard `post-update` hook so every push
runs `git update-server-info`. Do not replace or push the normal `origin`.

The bootstrap records the server's local network endpoint in a machine-specific
desired-state commit before applying the root Application. The source is
unauthenticated and loopback/network-local by design; it is not a production Git
server.

**Rationale**: Git's dumb-HTTP protocol supports read-only fetches from files
prepared by `update-server-info`. A bare repository plus a static server avoids
a database, account, SSH key, web UI, and separate application lifecycle. The
writer still uses normal commits and `git push`, while ArgoCD sees only committed
state. This is the smallest source that proves the intended commit/reconcile
boundary.

**Alternatives considered**:

- `git-http-backend`: retains the same repository contract and is the defined
  serving fallback if the pinned ArgoCD integration test rejects dumb HTTP, but
  it otherwise adds CGI server configuration without pilot value.
- Gitea or Forgejo: robust but adds credentials, application state, a database,
  and newcomer setup not needed for one local reader/writer.
- Hosted GitHub: contradicts the fully local running-pilot requirement.
- Mounting the working tree into ArgoCD: makes uncommitted files observable and
  breaks the commit-only acceptance criterion.

**Primary sources**:

- [Git `update-server-info`](https://git-scm.com/docs/git-update-server-info)
- [Git hooks and `post-update`](https://git-scm.com/docs/githooks#_post_update)
- [Git HTTP backend](https://git-scm.com/docs/git-http-backend.html)
- [ArgoCD repository access](https://argo-cd.readthedocs.io/en/latest/user-guide/private-repositories/)

## Decision 2: Local OCI registry and acquired assets

**Decision**: Follow Kind's local-registry topology with OCI Distribution 3.1.1,
bound to `127.0.0.1:5001`, attached to the Kind network as `kind-registry`, and
configured through a pre-created containerd `hosts.toml`. Pin Kind 0.32.0 and
its Kubernetes 1.36.1 node image by the published digest. Record every helper,
controller, and workload image source and manifest/index digest in
`bootstrap/local/assets.lock` before a clean run.

The acquisition step may use the internet. Once it succeeds, cluster creation,
Git serving, registry serving, reconciliation, controller restart, and
`auth-api` execution must work from machine-local assets.

**Rationale**: Kind documents the local Distribution-registry alias from host
`localhost:5001` to `kind-registry:5000`. Committing the local registry hosting
ConfigMap through ArgoCD, rather than applying it directly, preserves the
bootstrap boundary. Kind 0.32.0's node image is multi-architecture, digest
pinned, and includes network-policy support needed by the environment contract.

**Alternatives considered**:

- `kind load docker-image`: relies on Kind-specific node seeding, leaves the
  desired image location unexplained for EKS, and does not prove a registry
  contract.
- Docker Hub, GHCR, or ECR: creates a hosted runtime dependency; ECR also
  requires an AWS account.
- A registry deployed inside Kubernetes: introduces a bootstrapping cycle for
  platform and workload images.

**Primary sources**:

- [Kind local registry](https://kind.sigs.k8s.io/docs/user/local-registry/)
- [Kind working offline](https://kind.sigs.k8s.io/docs/user/working-offline/)
- [Kind 0.32.0 release and node digest](https://github.com/kubernetes-sigs/kind/releases/tag/v0.32.0)
- [OCI Distribution local deployment](https://distribution.github.io/distribution/about/deploying/)
- [OCI Distribution 3.1.1 release](https://github.com/distribution/distribution/releases/tag/v3.1.1)

## Decision 3: Vendor controller manifests and mirror their images

**Decision**: Keep the baseline Argo CD 3.5.0 pin, vendor its official
`install.yaml` plus checksum/provenance notes under
`bootstrap/argocd/vendor/v3.5.0/`, and change Kustomize to reference the local
file. Mirror every image referenced by the rendered installer to the local
registry by digest and override source names through Kustomize.

Vendor the selected ESO 2.7.0 installation under
`infrastructure/external-secrets/`, render it with server-side apply enabled,
and mirror all of its runtime images in the same asset lock. The exact
AppProject cluster-resource allowlist is generated from these vendored renders,
reviewed, and checked for drift.

**Rationale**: Vendoring YAML removes reconciliation-time access to
`raw.githubusercontent.com`, but it is incomplete unless every referenced image
is also available locally. Checksums, source URLs, acquisition date, versions,
and image digests make the local cache auditable and repeatable.

**Alternatives considered**:

- Remote Kustomize URLs: keep a hosted dependency in controller installation
  and self-management.
- Floating `stable`/`latest`: prevents repeatable acquisition and privilege
  review.
- Helm repositories at runtime: move the hosted dependency instead of removing
  it.

**Primary sources**:

- [ArgoCD installation guidance](https://argo-cd.readthedocs.io/en/latest/getting_started/)
- [Pinned Argo CD 3.5.0 installer](https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.0/manifests/install.yaml)
- [ESO 2.7.0 release](https://github.com/external-secrets/external-secrets/releases/tag/v2.7.0)
- [ESO installation guidance](https://external-secrets.io/latest/introduction/getting-started/)

## Decision 4: Reusable cluster registration and overlay selection

**Decision**: Extract the repeated ArgoCD application mechanism into
`clusters/base`. Use a Matrix ApplicationSet whose first child supplies exact
registration values (`cluster`, `environment`, `server`, `namespace`,
`repoURL`, `revision`) and whose Git-directory child selects only
`apps/*/overlays/{{ .environment }}`. `clusters/local-kind` patches values to
`environment: local`; the committed default remains disabled until the pilot
activation commit supplies its local source and immutable image.

Future `clusters/eks-dev` and similar directories reuse the base and change only
connection/environment values. `goTemplateOptions: ["missingkey=error"]` stays
enabled.

**Rationale**: Matrix child parameters can constrain the Git generator without
copying the whole ApplicationSet. The local cluster can never discover `dev`,
`staging`, or `prod`, while a newly added service with a conforming local overlay
is still discovered automatically.

**Alternatives considered**:

- Keep `apps/*/overlays/*`: deploys every environment into one cluster.
- Hardcode `apps/*/overlays/local` in a copied ApplicationSet: fixes the pilot
  but repeats the mechanism for every cluster.
- Add exclusion patterns: future overlays can be exposed accidentally.
- Use the cluster-secret generator: adds central multi-cluster registration
  state that the in-cluster pilot does not otherwise need.

**Primary sources**:

- [ApplicationSet Git generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)
- [ApplicationSet Matrix generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Matrix/)
- [ApplicationSet specification](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/applicationset-specification/)

## Decision 5: Immutable artifact and rollback contract

**Decision**: Retain the neutral `auth-api` image match key in the base. Every
active overlay must set:

```yaml
images:
  - name: auth-api
    newName: <environment-registry>/auth-api
    digest: sha256:<64-lowercase-hex-characters>
```

Change `scripts/bump-image.sh` to accept only a manifest/index digest, preserve
`newName`, render and verify `newName@digest`, commit the change, and never push
or mutate a cluster. Local publishing pushes the resulting commit only to the
`pilot` remote. Promotion copies an existing digest; rollback uses `git revert`.

**Rationale**: OCI digests identify content; tags are movable pointers. The Git
revert produces a new auditable commit restoring the previous desired digest,
which ArgoCD can reconcile automatically.

**Alternatives considered**:

- Semantic or Git-SHA tags: useful labels but still mutable references.
- Tag plus digest: Kubernetes pulls the digest, but retaining tag mutation makes
  the contract harder to validate; version metadata can live in annotations and
  evidence instead.
- `kubectl rollout undo`: bypasses the authoritative desired-state history.
- Rebuild per environment: violates build-once promotion.

**Primary sources**:

- [Kubernetes image names and digests](https://kubernetes.io/docs/concepts/containers/images/#image-names)
- [Kustomize image transformation](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- [OCI descriptor digests](https://github.com/opencontainers/image-spec/blob/main/descriptor.md#digests)
- [Git revert](https://git-scm.com/docs/git-revert)

## Decision 6: ESO secret contract

**Decision**: Keep the Deployment's stable `auth-api-secrets/JWT_SECRET`
reference. Remove `secretGenerator` and the ignored file dependency only after
ESO is healthy. In `overlays/local`, declare an ESO `Password` generator with
`spec.secretKeys: [JWT_SECRET]` and an `ExternalSecret` targeting
`auth-api-secrets`, using `refreshPolicy: CreatedOnce` for the disposable pilot.

For EKS, retain the same Deployment and target Secret interface. Replace only
the provider-side overlay with an AWS Secrets Manager `SecretStore` and
`ExternalSecret.data` mapping authenticated through pod identity/IRSA. The
historical literal is compromised and must be rotated anywhere it was used;
tree cleanup is not rotation.

**Rationale**: ESO generates demonstration material locally without committing
it or mutating the workload imperatively. Custom generator output keys preserve
the existing workload interface. The same reconciler and target contract work
with AWS later.

**Alternatives considered**:

- Ignored Kustomize env file: absent from ArgoCD's clean repository clone and
  therefore cannot render.
- Committed Fake provider data: still commits secret material.
- `kubectl create secret`: outside the amended bootstrap exception.
- Vault or LocalStack: adds a runtime and setup without improving this one-key
  pilot contract.
- SOPS/Sealed Secrets: introduces a different controller from the required ESO
  path.

**Primary sources**:

- [ESO Password generator](https://external-secrets.io/latest/api/generator/password/)
- [ExternalSecret API](https://external-secrets.io/latest/api/externalsecret/)
- [AWS Secrets Manager provider](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [AWS identity/IRSA access](https://external-secrets.io/latest/provider/aws-access/)
- [Git ignore semantics](https://git-scm.com/docs/gitignore)

## Decision 7: Environment ownership and ArgoCD privilege

**Decision**: Move ResourceQuota, LimitRange, default-deny/allow-required
NetworkPolicies, and operator/verifier RBAC to `clusters/base/environment`.
Move replicas and CPU/memory requests/limits into the environment overlay. Keep
the service's no-permission ServiceAccount in the base with
`automountServiceAccountToken: false`. Remove Kind-specific pull-policy comments
and values from the base.

Split the wildcard AppProject into exact trust boundaries for applications,
environment policy, and platform controllers. Constrain the `default` project
after root reconciliation. Forbid wildcard repositories, destinations, and
resource kinds; derive platform kinds from the pinned render.

**Rationale**: Quotas, limit defaults, network boundaries, and namespace RBAC
govern an environment shared by services. Duplicating them per service creates
ownership conflicts. Platform controllers need different privileges from a
business workload, so one wildcard project cannot express least privilege.

**Alternatives considered**:

- Leave quota under `auth-api`: makes one service own shared namespace policy.
- Keep one wildcard project: grants business Applications platform-controller
  authority.
- Render NetworkPolicy without enforcement: produces paper compliance only;
  tests must prove allowed and denied traffic with the pinned Kind node.

**Primary sources**:

- [Kustomize bases and overlays](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- [ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [ArgoCD Projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)

## Decision 8: Reuse and conformance contract

**Decision**: Treat `auth-api` as the canonical instance of a documented,
machine-checked service contract. Define allowed base, service, overlay, and
cluster-registration values. Render seven abstract fixtures named
`service-slot-02` through `service-slot-08`; do not invent service identities.
Render local and future-EKS registration fixtures and compare their hierarchy,
generator, promotion, labels, health, and ownership contracts.

**Rationale**: The repository evidence identifies fewer than eight named
services, but the feature specification requires eight slots. Abstract fixtures
prove the mechanism and value boundaries without deploying or falsely naming
business services.

**Alternatives considered**:

- Copy `auth-api` seven times as active Applications: violates exactly-one
  deployment and invents service facts.
- Manual design review only: cannot enforce future repository changes.
- A heavily parameterized Helm chart: replaces the adopted Kustomize mechanism.

**Primary source**:

- [Kustomize composition and overlays](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

## Decision 9: Evidence harness and newcomer workflow

**Decision**: Provide Bash entry points under `scripts/pilot/` and keep the
newcomer path to eight commands from clone through health. Scripts emit a JSON
summary, NDJSON timeline, Argo Application status, Kubernetes workload state,
health observations, Git history, and a complete command log for every run.

Start reconciliation timing only when `git ls-remote` proves the target commit
is available. Require the Argo Application's observed revision to match, wait
for Deployment availability, count exactly one workload labeled
`app.kubernetes.io/component=business-service`, and make three `/version`
requests spanning at least 60 seconds. Separate exercises prove five minutes of
uncommitted non-effect, a committed replica change, and a Git revert. Two human
operator records cover the qualitative criterion.

**Rationale**: A running pod is not proof of the deployment path. Correlated Git,
Argo, workload, timing, and health data directly addresses every measurable
criterion and exposes unsupported mutation rather than hiding it.

**Alternatives considered**:

- Screenshots: difficult to validate, compare, or automate.
- Argo UI-only instructions: add manual steps and do not create structured
  evidence.
- A manual `kubectl apply` recovery path: invalidates the pilot.

**Primary sources**:

- [ArgoCD Application status and CLI](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_app_get/)
- [`kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/)
- [`kubectl port-forward`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/)
- [Kubernetes JSONPath](https://kubernetes.io/docs/reference/kubectl/jsonpath/)

## Decision 10: Production stays structurally disabled

**Decision**: Preserve `overlays/prod` only as a clearly inactive scaffold. The
local Matrix generator selects only `local`, the local application project
permits only `microtodo-local`, and conformance rejects any active registration
for `prod`. `docs/production-readiness.md` lists immutable promotion, ESO,
namespace controls, Argo Rollouts, metric analysis, supply-chain/admission
policy, and required platform dependencies as blocking prerequisites.

**Rationale**: A Sync Window or comment does not prove production safety. Three
independent structural checks keep premature production semantics out of the
pilot while retaining the future overlay slot.

**Alternatives considered**:

- Delete the production scaffold: hides rather than documents the future
  contract.
- Rely on an Argo Sync Window: controls timing, not readiness prerequisites.
- Leave production discoverable but unhealthy: still creates production-like
  state and violates exactly-one/local scope.

**Primary sources**:

- [ArgoCD Sync Windows](https://argo-cd.readthedocs.io/en/stable/user-guide/sync_windows/)
- [Argo Rollouts canary strategy](https://argo-rollouts.readthedocs.io/en/stable/features/canary/)
- [Argo Rollouts metric analysis](https://argo-rollouts.readthedocs.io/en/stable/features/analysis/)


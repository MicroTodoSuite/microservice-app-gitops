# Platform Add-ons

MicroTodoSuite installs four platform add-ons through the same reusable ArgoCD
registration mechanism used by business services. The shared desired state is
fully local and provider-neutral: it does not require a hosted control plane,
registry, secret backend, certificate authority, workload identity, or cloud
account.

## Installed foundation

| ArgoCD Application | Pinned release | Destination | Local capability proof |
| --- | --- | --- | --- |
| `infra-keda` | KEDA 2.20.1 | `keda` | `ScaledObject/platform-autoscaling-check` is Ready |
| `infra-cert-manager` | cert-manager 1.21.0 | `cert-manager` | a self-signed Certificate is Ready and has produced its Secret |
| `infra-external-secrets` | External Secrets Operator 2.9.0 | `external-secrets` | auth-api's ExternalSecret is Ready with reason `SecretSynced` |
| `infra-kyverno` | Kyverno 1.18.2 | `kyverno` | both baseline ClusterPolicies are Ready and report passing results for auth-api |

Every executable image is selected by an immutable digest. Every retained
upstream manifest has a checksum and provenance note under
`infrastructure/<add-on>/vendor/<version>/`. The retained file is not edited;
Kustomize transformations beside it express repository-owned changes.

## Registration and reconciliation

`clusters/base/infrastructure.yaml` discovers each direct Kustomize root under
`infrastructure/` and creates an Application named `infra-<folder>`. Vendor
subdirectories and the inactive `argo-rollouts` placeholder are explicitly
excluded. Each generated Application:

- reads the repository URL and revision injected by the cluster registration;
- deploys to the in-cluster Kubernetes API and its dedicated namespace;
- belongs to the exact `microtodosuite` AppProject boundary;
- enables automated prune and self-heal; and
- uses namespace creation and server-side apply for complete upstream bundles.

The bootstrap root remains in a separate, least-privilege `default` project.
That project can manage only the repository's root ConfigMap, AppProject,
Application, and ApplicationSet resources in `argocd`. Retaining it in desired
state prevents the root from pruning its own reconciliation prerequisite.

All changes, including rollback, follow the same path:

```text
reviewed repository change -> commit -> registered Git source -> ArgoCD reconciliation
```

Do not apply, patch, scale, or restart a managed Kubernetes workload directly.
Use a follow-up commit or `git revert` and let ArgoCD reconcile it.

## Provider-neutral boundary

The shared `infrastructure/` roots own only controller installation, CRDs,
cluster RBAC, admission webhooks, immutable images, and provider-neutral
capability checks. They deliberately do not own:

- external secret stores or credentials;
- external certificate issuers or trust material;
- provider identities or workload-identity bindings;
- provider registry endpoints; or
- account, region, subscription, or tenant values.

Those values are destination configuration. When a managed environment needs a
store, issuer, identity, or registry, its registration and environment-owned
resources supply that binding while consuming the unchanged shared controller
installation. This keeps credentials and destination policy out of the reusable
mechanism and avoids copying an add-on folder per cluster.

## Registering another cluster

A new cluster registration is a sibling of `clusters/local-kind` and consumes
`../base`. It contributes values and activation only:

1. Add its `cluster-registration` ConfigMap with the reachable Git source and
   reviewed revision.
2. Add activation patches listing the environments hosted by that cluster.
3. Add any destination-owned store, issuer, identity, or registry binding as a
   registration/environment resource; do not edit an `infrastructure/` root.
4. Create the root Application once through that cluster's audited bootstrap
   boundary.
5. Verify the generated infrastructure Applications and capabilities before
   activating business services.

The shared ApplicationSet then discovers the same four paths and installs the
same pinned controllers. Moving from one registered environment to the next is
a values-and-activation change, not a new platform layout.

## Validation

Static validation is cluster-free:

```bash
./tests/contract/platform-addons.sh
```

It verifies retained checksums, complete controller inventory, immutable image
references, exact cluster-scoped permissions, four-root discovery,
provider-neutral first-party resources, Kyverno enforcement, and all Kustomize
renders.

The composite live verifier is read-only and retains raw evidence under
`.local/evidence/platform-addons/<timestamp>/`:

```bash
PILOT_CLUSTER=microtodo-gitops-pilot \
PILOT_KUBE_CONTEXT=kind-microtodo-gitops-pilot \
  ./scripts/pilot/verify-platform.sh
```

Passing requires all four infrastructure Applications and auth-api to be
Synced and Healthy at the machine-local Git revision; every expected Deployment
to be Available; all four capability checks to pass; both Kyverno report
results for the freshly admitted auth-api Pod to pass; no unhealthy final pod
state; and three HTTP 200 responses over at least 60 seconds.

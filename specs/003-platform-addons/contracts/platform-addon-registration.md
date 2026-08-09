# Platform Add-on Registration Contract

## Discovery contract

The shared `clusters/base/infrastructure.yaml` generator discovers direct
children of `infrastructure/` and excludes all `vendor` descendants. For this
feature the generated applications are exactly:

| Application | Source path | Destination namespace |
| --- | --- | --- |
| `infra-keda` | `infrastructure/keda` | `keda` |
| `infra-cert-manager` | `infrastructure/cert-manager` | `cert-manager` |
| `infra-external-secrets` | `infrastructure/external-secrets` | `external-secrets` |
| `infra-kyverno` | `infrastructure/kyverno` | `kyverno` |

Every generated Application must:

- use the registration-injected repository URL and revision;
- target the registration's Kubernetes API server through the shared template;
- enable automated prune and self-heal;
- use `CreateNamespace=true` and `ServerSideApply=true`;
- remain in the exact `microtodosuite` AppProject trust boundary.

## Add-on folder contract

Every direct infrastructure folder must contain:

- `kustomization.yaml` as the only ArgoCD entry point;
- one retained upstream bundle under `vendor/<version>/`;
- `vendor/<version>/README.md` with source, version, regeneration or download
  command, and upgrade procedure;
- `vendor/<version>/SHA256SUMS` matching the retained bundle;
- immutable image transforms for every executable image;
- optional first-party capability or policy resources outside `vendor/`.

Vendor manifests are never edited after their checksum is recorded. Required
customization is expressed by Kustomize transforms or patches beside the
bundle.

## Live controller contract

The expected Deployment names are fixed by the pinned releases:

| Namespace | Deployments |
| --- | --- |
| `keda` | `keda-admission`, `keda-metrics-apiserver`, `keda-operator`, `platform-autoscaling-check` |
| `cert-manager` | `cert-manager`, `cert-manager-cainjector`, `cert-manager-webhook` |
| `external-secrets` | `external-secrets`, `external-secrets-cert-controller`, `external-secrets-webhook` |
| `kyverno` | `kyverno-admission-controller`, `kyverno-background-controller`, `kyverno-cleanup-controller`, `kyverno-reports-controller` |

Passing means `.status.availableReplicas == .spec.replicas` for every listed
Deployment and no add-on pod is Pending, Failed, Unknown, or CrashLoopBackOff.

## Capability contract

- KEDA: `ScaledObject/keda/platform-autoscaling-check` has Ready=True.
- cert-manager: `Certificate/cert-manager/platform-certificate-check` has
  Ready=True and Secret `platform-certificate-check-tls` exists.
- External Secrets: `ExternalSecret/microtodo-local/auth-api-secrets` has
  Ready=True and reason `SecretSynced`.
- Kyverno: ClusterPolicies `require-immutable-images` and
  `require-health-probes` have Ready=True. Reports associated with the current
  auth-api Pod contain pass results for both policies and no fail/error result.

## Auth-api compatibility contract

After both Kyverno policies are Ready:

1. a committed pod-template annotation change causes a new auth-api ReplicaSet;
2. the auth-api Application observes that newer local Git SHA;
3. the new Deployment is Available and its pod is admitted;
4. both policy rules report pass for the pod; and
5. `/version` returns HTTP 200 three times over at least 60 seconds.

## Provider-neutrality contract

The shared add-on folders and capability resources must not contain an AWS or
Azure account identifier, endpoint, region, registry, credential, workload
identity, SecretStore, ClusterSecretStore, or certificate issuer dependency.
Future provider-specific resources are registration/environment values and do
not change this controller-installation contract.

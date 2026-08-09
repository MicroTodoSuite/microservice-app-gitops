# Data Model: Local Platform Add-ons Foundation

This repository stores desired state rather than business records. The feature
still has four reviewable entities and explicit state transitions.

## PlatformAddon

Represents one GitOps-managed cluster capability.

| Field | Meaning | Validation |
| --- | --- | --- |
| `name` | Stable folder and application identity | One of `keda`, `cert-manager`, `external-secrets`, `kyverno` |
| `namespace` | Exclusive controller namespace | Equal to `name` |
| `release` | Pinned upstream semantic version | Concrete version; no range or floating alias |
| `bundlePath` | Retained install manifest | Must remain under `infrastructure/<name>/vendor/<release>/` |
| `bundleChecksum` | Download/render integrity | Lowercase SHA-256 matching the retained bytes |
| `images` | Runtime artifacts | Every rendered executable image contains an immutable SHA-256 digest |
| `controllers` | Expected Deployments | Non-empty and fully Available at acceptance |
| `capabilityCheck` | Functional controller resource | Must expose a live Ready/Pass condition |

State transition:

```text
Pinned -> Rendered -> Committed -> Argo Synced -> Controllers Available -> Capability Ready
```

Any checksum, render, sync, availability, or capability failure stops the
transition and prevents a success claim.

## ClusterRegistration

Represents the values a cluster contributes to the shared delivery mechanism.

| Field | Meaning | Validation |
| --- | --- | --- |
| `repoURL` | Desired-state source reachable by ArgoCD | Local pilot URL now; concrete registered URL later |
| `revision` | Desired-state branch/ref | Explicit, never an uncommitted worktree |
| `server` | Kubernetes destination | Registration value, not embedded in add-on folders |
| `environments` | Activated application/environment set | Empty until reviewed activation |

Relationship: one ClusterRegistration consumes the shared infrastructure
generator, which produces exactly one Application per PlatformAddon.

## CapabilityCheck

Represents live proof that a controller reconciles its API.

| Add-on | Resource | Passing state |
| --- | --- | --- |
| KEDA | `ScaledObject/keda/platform-autoscaling-check` | Ready=True and target Deployment Available |
| cert-manager | `Certificate/cert-manager/platform-certificate-check` | Ready=True and target Secret exists |
| External Secrets | `ExternalSecret/microtodo-local/auth-api-secrets` | Ready=True with reason SecretSynced |
| Kyverno | two ClusterPolicies plus auth-api PolicyReport results | Policies Ready=True; applicable results pass with zero fail/error |

## ReconciliationEvidence

An untracked, timestamped observation set produced by the verifier.

| Field | Meaning |
| --- | --- |
| `expectedRevision` | SHA at the machine-local Git source |
| `applications` | App name, source revision, sync, and health |
| `deployments` | Desired, ready, and available replicas per expected controller |
| `capabilities` | Raw conditions for all four checks |
| `pods` | Final add-on and auth-api pod status |
| `healthChecks` | Timestamp, HTTP status, latency, and body for each auth-api call |

State transition:

```text
Started -> Revision Matched -> Applications Healthy -> Controllers Available
        -> Capabilities Ready -> Auth API Healthy -> Complete
```

Evidence remains incomplete if any intermediate state times out.

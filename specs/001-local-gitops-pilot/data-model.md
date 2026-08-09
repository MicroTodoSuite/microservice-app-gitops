# Data Model: Local GitOps Pilot

The pilot stores no application database. This model defines the declarative
records and evidence objects that implementation and conformance checks must
keep consistent.

## 1. Acquired Asset

Represents one prerequisite available on the developer machine before the
offline-capable running phase.

| Field | Type | Rules |
| --- | --- | --- |
| `name` | string | Unique stable identifier, such as `kind-node` or `argocd-controller`. |
| `kind` | enum | `binary`, `manifest`, or `oci-image`. |
| `version` | string | Exact upstream version; never `latest`, `stable`, or `HEAD`. |
| `source` | string | Auditable upstream URL/reference used only during acquisition. |
| `sha256` | string | File checksum or OCI manifest/index digest. |
| `localReference` | string | Local filesystem or registry reference used during the running pilot. |
| `platform` | string/null | `linux/amd64`, `linux/arm64`, multi-platform, or not applicable. |
| `verifiedAt` | RFC 3339 timestamp | Time acquisition validation succeeded. |

**Validation**:

- Every runtime image in the rendered ArgoCD, ESO, helper, and workload
  manifests has exactly one matching asset entry.
- OCI entries use a manifest or index digest, not a local image/config ID.
- A clean run fails before cluster creation if an entry is absent locally or its
  digest differs.

## 2. Local Repository Source

Represents the machine-local copy of `microservice-app-gitops` observed by
ArgoCD.

| Field | Type | Rules |
| --- | --- | --- |
| `barePath` | local path | Must be under ignored `.local/git/`. |
| `writerRemote` | string | Exactly `pilot`; points to `barePath`, never hosted `origin`. |
| `readerURL` | HTTP URL | Loopback/Kind-network-local endpoint committed in registration state. |
| `branch` | string | `main`. |
| `offeredRevision` | 40-character Git SHA | Current `refs/heads/main` exposed to ArgoCD. |
| `serverImageDigest` | OCI digest | Must match the acquired asset lock. |
| `updateHookEnabled` | boolean | Must be true before the first push. |

**Invariant**: only committed objects reachable from `offeredRevision` may be
served. The operator's ordinary working tree and uncommitted files are not
mounted into ArgoCD.

## 3. Environment Registration

Supplies only environment/connection values to the shared cluster base.

| Field | Type | Rules |
| --- | --- | --- |
| `cluster` | string | Stable cluster identifier, for example `local-kind`. |
| `environment` | string | `disabled` before activation; `local` for this pilot. `prod` is forbidden in any active pilot registration. |
| `repositoryURL` | URL | Machine-local HTTP URL for the pilot; approved hosted URL for a future managed cluster. |
| `revision` | string | `main` for the pilot remote; an explicit approved revision policy later. |
| `destinationServer` | URL | In-cluster Kubernetes API for the pilot; registered EKS endpoint later. |
| `namespace` | DNS label | Exactly `microtodo-local` for this pilot. |
| `imageRegistry` | registry path | `localhost:5001` for Kind; ECR endpoint later. |
| `capacityProfile` | object | Environment-selected replicas, requests, and limits. |
| `activeInfrastructure` | string list | Explicit allowlist; pilot includes only implemented required controllers. |

**Relationships**:

- One registration instantiates one shared cluster base.
- One active registration selects all conforming service overlays for exactly
  its `environment`.
- `local-kind` selects one active business-service overlay in this feature.

## 4. Reconciliation Registration

The rendered ArgoCD association among source, revision, path, project, and
destination.

| Field | Type | Rules |
| --- | --- | --- |
| `applicationName` | string | Deterministic `<service>-<environment>` for business services. |
| `repositoryURL` | URL | Equal to the active Environment Registration. |
| `targetRevision` | string | Equal to the active registration revision. |
| `sourcePath` | path | `apps/<service>/overlays/<environment>` or an explicitly allowed platform/environment path. |
| `project` | string | Exact least-privilege AppProject for the trust boundary. |
| `destinationServer` | URL | Equal to registration. |
| `destinationNamespace` | string | Exact permitted namespace. |
| `automated` | boolean | Must be true with prune and self-heal for active pilot Applications. |

**Invariant**: no active pilot business Application may select `dev`,
`staging`, or `prod`.

## 5. Service Definition

Describes values that legitimately distinguish a service while preserving the
repository hierarchy and deployment mechanism.

| Field | Type | Rules |
| --- | --- | --- |
| `name` | DNS label | Matches directory, workload, Service, image match key, and required labels. |
| `containerPort` | integer | Declared once in the service base. |
| `servicePort` | integer | Declared once in the service base. |
| `healthPath` | absolute path | Intrinsic; cannot require another business service. |
| `configKeys` | string list | Names only; environment values are not placed in the base. |
| `secretContracts` | list | Secret name/key interfaces only; no provider or value. |
| `labels` | object | Includes name, part-of, and `component=business-service`. |
| `serviceAccount` | string | Dedicated account with token automount disabled unless explicitly justified. |

For `auth-api`: ports are `8000`, the health path is `/version`, configuration
keys are `AUTH_API_PORT` and `USERS_API_ADDRESS`, and the secret interface is
`auth-api-secrets/JWT_SECRET`.

## 6. Reusable Service Base

The Kustomize resources shared by every environment for one service.

**Owns**:

- Deployment identity, selector, container/Service ports, intrinsic probes,
  stable configuration and Secret interfaces, common labels, security context,
  and no-permission ServiceAccount.

**Must not own**:

- Namespace, cluster endpoint, repository URL, image registry, tag/digest,
  replicas, requests/limits, exposure, environment configuration values,
  provider-specific secrets, ResourceQuota, LimitRange, NetworkPolicy, or
  environment operator RBAC.

**Invariant**: the same base path renders under local and future managed
overlays without editing files in the base.

## 7. Environment Overlay

The bounded environment-specific transformation of one service base.

| Field | Type | Rules |
| --- | --- | --- |
| `environment` | string | Directory basename and registration match. |
| `namespace` | string | Must equal the registration namespace. |
| `imageName` | registry path | Environment-owned registry/repository. |
| `imageDigest` | OCI digest | Required for any active overlay; all-zero and tag-only references forbidden. |
| `replicas` | positive integer | Selected by capacity profile. |
| `requests` / `limits` | resource quantities | Selected by capacity profile; must satisfy environment LimitRange/Quota. |
| `configValues` | map | Environment values only; must match declared config keys. |
| `exposure` | object | Local-only access or approved managed ingress settings. |
| `secretSource` | resource reference | ESO generator/provider; target Secret contract must match the base. |

## 8. Secret Contract

Stable interface between the workload and a reconciled secret source.

| Field | Pilot value | Future EKS value |
| --- | --- | --- |
| Target Secret | `auth-api-secrets` | `auth-api-secrets` |
| Target key | `JWT_SECRET` | `JWT_SECRET` |
| Reconciler | ESO 2.7.0 | ESO approved managed version |
| Source | ESO `Password` generator | AWS Secrets Manager through `SecretStore` |
| Authentication | None; local generator | Pod identity/IRSA |
| Refresh policy | `CreatedOnce` | Approved rotation policy |
| Value in Git | Never | Never |

**State transition**: `ControllerAbsent -> ControllerHealthy -> SourceDeclared ->
TargetReady -> WorkloadReady`. `SourceDeclared` must not be activated before
`ControllerHealthy` is observed.

## 9. Desired State Revision

| Field | Type | Rules |
| --- | --- | --- |
| `commit` | Git SHA | Available from the local source before timing begins. |
| `parent` | Git SHA | Makes change/revert lineage auditable. |
| `purpose` | enum | `bootstrap-registration`, `deploy`, `change`, or `revert`. |
| `service` | string/null | `auth-api` for workload revisions. |
| `environment` | string | `local` for workload revisions. |
| `imageDigest` | OCI digest/null | Required for deploy/promotion revisions. |
| `createdAt` | Git timestamp | Captured in evidence. |

**Invariant**: the Argo Application observed revision must equal the offered
revision before readiness or health can count as success.

## 10. Pilot Verification Record

One immutable evidence summary per scenario/run, conforming to
`contracts/pilot-evidence.schema.json`.

**Required relationships**:

- References one desired and one Argo-observed revision; both must match for a
  successful steady state.
- Contains source-availability, sync, ready, and healthy timestamps sufficient
  to calculate the five-minute thresholds.
- Contains exactly one observed business-service identity: `auth-api`.
- Contains at least three successful health observations spanning 60 seconds.
- Contains a complete command audit and an empty unsupported-mutation list.
- Links raw Argo, workload, Git, and health evidence stored in the same run
  directory.

**Lifecycle**:

```text
created
  -> assets-verified
  -> source-available
  -> argocd-synced
  -> workload-ready
  -> health-observed
  -> passed

Any failed precondition or timeout -> failed (never coerced to passed)
```

## 11. Operator Evaluation

Manual record for one first-time operator.

| Field | Type | Rules |
| --- | --- | --- |
| `operatorId` | pseudonymous string | Must not contain credentials or secrets. |
| `priorContext` | boolean | Must be false for SC-009 evidence. |
| `startedAt` / `completedAt` | timestamps | Demonstrates elapsed newcomer time. |
| `enteredCommandCount` | integer | At most 10 through first passing health. |
| `undocumentedAssistance` | string list | Must be empty for acceptance. |
| `identifiedRevision` / `identifiedSync` / `identifiedReadiness` / `identifiedHealth` | booleans | All true for acceptance. |
| `clarityRating` | integer | 1 through 5; at least 4 for acceptance. |

## 12. Production Readiness Gate

Represents prerequisites that must all be true before any production
registration becomes active.

Required booleans are: digest-only promotion, ESO-backed secret resolution,
environment quota/limits/network/RBAC, Argo Rollouts controller, Rollout
workload, metric AnalysisTemplate and provider, required supply-chain/admission
policy, and required production platform dependencies.

**Invariant**: conformance fails if `environment=prod` is active while any gate
field is false or absent. This feature intentionally leaves the gate closed.


# Data Model: Shared-Cluster Namespace Isolation

This feature has no application database. Its model consists of declarative
Kubernetes desired state and immutable acceptance evidence.

## Relationship Overview

```text
SharedClusterRegistration (external prerequisite)
├── activates 3 EnvironmentNamespaces
├── activates 0 BusinessApplications
└── retains 4 ControllerInfrastructureApplications

EnvironmentNamespaces
    ├── consumes 1 ManagedIsolationBase
    ├── owns 1 ResourceBudget
    ├── owns 1 EnvironmentAccessBinding
    ├── owns 1 EnvironmentRedisInstance
    ├── owns 0..N ExactNetworkAllowances
    └── produces observations in 1 IsolationEvidenceRun

CniEnforcementGate (external capability, live evidence)
└── must pass before DefaultDenyActivation

DevContinuityBaseline
└── compared with staged and final DevContinuitySamples
```

## SharedClusterRegistration (External Prerequisite)

| Field | Required value | Rule |
| --- | --- | --- |
| `name` | `eks-main` | One shared economical-profile cluster registration. |
| `server` | `https://kubernetes.default.svc` | ArgoCD reconciles its own cluster. |
| `environmentActivation` | `[dev, staging, prod]` | Produces exactly the three environment-policy Applications. |
| `businessApplicationActivation` | `[]` | Real service activation is later dev-first work. |
| `infrastructureActivation` | `[keda, cert-manager, external-secrets, kyverno]` | Exact retained controller list; no folder discovery and no Redis. |
| `repositoryRevision` | reviewed immutable Git identity | No live parameter override. |

The current shared base does not yet expose this independent activation state:
app/environment lists are documented as matching, and infrastructure is
folder-discovered automatically. The separate registration work must close that
gap before this entity can satisfy the contract.

## ManagedIsolationBase

Reusable Kustomize desired state consumed by all managed environments.

| Field | Type | Rule |
| --- | --- | --- |
| `limitRange` | reference | Exactly one common CPU/memory default and maximum contract. |
| `defaultDeny` | reference | Selects all pods for both ingress and egress. |
| `dnsAllowance` | reference | Allows only required TCP/UDP DNS traffic to the cluster DNS namespace/selector contract. |
| `sameEnvironmentAllowance` | reference | Selects pods only inside the current namespace; never another environment. |
| `workloadRole` | reference | Custom namespaced role with explicit API groups, resources, and verbs. |
| `redisResources` | reference set | One immutable Deployment, ServiceAccount, Service, and policy contract rendered into the consuming namespace. |
| `namespace` | absent | The base does not own a concrete namespace name. |
| `quotaValues` | absent | Numeric budgets belong to environment overlays. |
| `subjects` | absent | Identity groups belong to environment overlays. |

### Invariants

- The base renders no `Namespace`, `ResourceQuota`, or `RoleBinding` without an
  environment overlay.
- No resource contains `microtodo-dev`, `microtodo-staging`, or
  `microtodo-prod` as a behavioral fork.
- The base contains no cloud account, IAM ARN, registry endpoint, mutable image
  reference, or secret value.
- The Redis image is selected by immutable digest and never points to the
  legacy shared `redis` namespace.

## EnvironmentNamespace

| Field | Dev | Staging | Prod | Rule |
| --- | --- | --- | --- | --- |
| `environment` | `dev` | `staging` | `prod` | Closed set; exactly three values. |
| `namespace` | `microtodo-dev` | `microtodo-staging` | `microtodo-prod` | Derived, immutable mapping. |
| `environmentLabel` | `dev` | `staging` | `prod` | `microtodosuite.io/environment-name`. |
| `managedLabel` | `true` | `true` | `true` | `microtodosuite.io/environment`. |
| `maintainerGroup` | `microtodosuite:dev-maintainers` | `microtodosuite:staging-maintainers` | `microtodosuite:prod-maintainers` | One distinct group per namespace. |
| `resourceBudget` | reference | reference | reference | Exact evidence-derived values. |
| `networkAllowances` | list | list | list | Empty except for approved exact dependencies. |
| `redisInstance` | `redis.microtodo-dev.svc` | `redis.microtodo-staging.svc` | `redis.microtodo-prod.svc` | Exactly one namespace-local instance. |
| `applicationName` | `env-dev` | `env-staging` | `env-prod` | Derived by the current ApplicationSet. |

### Validation Rules

- Namespace and label environment values must agree.
- An overlay may reference only `../base` plus its own resources and patches.
- A maintainer group may appear as a workload-role subject in exactly one
  environment.
- `microtodo-local` is not a member of this entity set.

## ResourceBudget

| Field | Type | Validation |
| --- | --- | --- |
| `requestsCpu` | Kubernetes quantity | Positive; not lower than measured steady demand plus approved rollout headroom. |
| `limitsCpu` | Kubernetes quantity | Greater than or equal to `requestsCpu`. |
| `requestsMemory` | Kubernetes quantity | Positive; includes measured steady demand and approved rollout headroom. |
| `limitsMemory` | Kubernetes quantity | Greater than or equal to `requestsMemory`. |
| `pods` | integer | Positive; covers steady pods, rollout surge, and verification allowance. |
| `containerDefaultRequestCpu` | quantity | Positive and no greater than container default limit. |
| `containerDefaultRequestMemory` | quantity | Positive and no greater than container default limit. |
| `containerDefaultLimitCpu` | quantity | No greater than the per-container CPU maximum. |
| `containerDefaultLimitMemory` | quantity | No greater than the per-container memory maximum. |
| `containerMaxCpu` | quantity | No greater than the environment aggregate CPU limit. |
| `containerMaxMemory` | quantity | No greater than the environment aggregate memory limit. |
| `evidenceReference` | relative path/identifier | Points to the reviewed capacity baseline that justified the values. |

### Cross-Budget Invariants

- The three environment budgets plus recorded system/platform/disruption reserve
  do not exceed the approved capacity envelope used for activation.
- Quota totals are documented as admission ceilings, not dedicated reservation.
- A value change requires a new capacity baseline and reviewed Git change.

## EnvironmentRedisInstance

| Field | Type | Validation |
| --- | --- | --- |
| `environment` | environment name | Matches the owning namespace. |
| `namespace` | namespace name | One of the three managed namespaces; never `redis`. |
| `deployment` | `redis` | Exactly one replica with Recreate strategy. |
| `service` | `redis:6379/TCP` | Namespace-local ClusterIP; service and container ports match. |
| `image` | immutable image reference | Redis 7.4.9 selected by digest. |
| `resources` | request/limit set | 25m/32Mi requests and 250m/128Mi limits, included in the environment quota. |
| `storage` | `emptyDir` | Explicitly ephemeral; no durability claim. |
| `clients` | pod selector set | todos-api and log-message-processor in the same namespace. |
| `health` | observation | Deployment Available and `PING` returns `PONG`. |
| `eventIsolation` | observation matrix | A unique event is observed only by the subscriber connected to the same instance. |

### Invariants

- Exactly three managed Redis Deployments and Services exist, one per
  environment namespace.
- The shared EKS cluster has no `infra-redis` Application and no `redis`
  namespace after migration.
- Managed todos-api and log-message-processor overlays use `REDIS_HOST=redis`;
  the inactive application list remains empty in this feature.
- The local pilot's Redis path and endpoint remain byte-unchanged.

## ExactNetworkAllowance

| Field | Type | Validation |
| --- | --- | --- |
| `name` | DNS label | Unique within the environment. |
| `sourcePodSelector` | label selector | Narrowest known workload selector; empty only for a reviewed whole-environment requirement such as DNS. |
| `destinationNamespaceSelector` | label selector | Must not select another complete environment namespace. |
| `destinationPodSelector` | label selector | Required for in-cluster platform dependencies. |
| `ipBlock` | CIDR plus exclusions | Used only when selectors cannot express an approved external destination. |
| `protocol` | `TCP` or `UDP` | Explicit; no omitted protocol. |
| `ports` | non-empty list | Exact ports; no unrestricted port set. |
| `direction` | `Ingress` or `Egress` | Explicit. |
| `owner` | feature/spec reference | Identifies the requirement that introduced the allowance. |
| `evidence` | observation reference | Shows the path is required and works after policy activation. |

### Invariants

- Default deny exists independently from every allowance.
- No allowance selects `microtodosuite.io/environment: "true"` as a broad
  destination.
- An application-specific allowance is not added until its owning feature
  supplies the endpoint and port contract.

## EnvironmentAccessBinding

| Field | Type | Validation |
| --- | --- | --- |
| `namespace` | namespace name | One of the exact managed namespaces. |
| `group` | Kubernetes group string | Exact environment maintainer group; never `system:*`. |
| `roleName` | string | Common custom workload role. |
| `allowedResources` | set | Explicit namespaced workload/config resources only. |
| `allowedVerbs` | set | Exact verbs needed by the approved workload contract. |
| `excludedResources` | set | Includes Namespace, ResourceQuota, LimitRange, NetworkPolicy, Role, RoleBinding, Secret, and cluster-scoped resources. |
| `identityMappingEvidence` | observation reference | Confirms approved AWS principals map to only the intended group. |

### Authorization Matrix

| Subject group | dev | staging | prod |
| --- | --- | --- | --- |
| `microtodosuite:dev-maintainers` | allow workload contract | deny | deny |
| `microtodosuite:staging-maintainers` | deny | allow workload contract | deny |
| `microtodosuite:prod-maintainers` | deny | deny | allow workload contract |
| unbound subject | deny | deny | deny |

All three maintainer groups are denied isolation-control modification in every
namespace. ArgoCD and approved cluster administrators are separately authorized
platform principals and are reported separately in evidence.

## CniEnforcementGate

| Field | Type | Rule |
| --- | --- | --- |
| `provider` | string | `amazon-vpc-cni` for the planned shared cluster. |
| `version` | string | Live version; must satisfy the provider-supported network-policy range. |
| `configurationEnabled` | boolean | Must be `true`. |
| `eligibleNodes` | list | Every Linux EC2 workload node in scope. |
| `agentReadyByNode` | map(node, boolean) | Every eligible node must report ready. |
| `policyEndpointAvailable` | boolean | Required provider CRD/controller evidence is present. |
| `positiveProbe` | observation | One explicitly allowed new TCP connection succeeds. |
| `negativeProbe` | observation | One explicitly denied new TCP connection fails. |
| `result` | `PASS` or `FAIL` | `PASS` is required before default deny. |

## DevContinuitySample

| Field | Type | Rule |
| --- | --- | --- |
| `phase` | enum | `baseline`, `foundation`, `default-deny`, `fixtures`, or `final`. |
| `observedAt` | RFC 3339 timestamp | Chronological. |
| `expectedRevision` | full Git SHA | Must match the current rollout stage. |
| `applications` | list | Includes every existing dev Application in scope. |
| `readyReplicas` | map(workload, integer) | Must not fall below baseline desired readiness. |
| `restartCounts` | map(container, integer) | Final minus baseline must be zero for policy-attributable restarts. |
| `healthChecks` | list | Each contains endpoint, status, and latency. |
| `resourceUse` | observation | CPU/memory usage where metrics are available; absence is explicit. |
| `requiredConnections` | list | Each declared path has a pass/fail result. |

## IsolationEvidenceRun

| Field | Type | Rule |
| --- | --- | --- |
| `schemaVersion` | semantic version | Starts at `1.0.0`. |
| `feature` | string | `005-namespace-isolation`. |
| `constitutionVersion` | string | Exactly `1.2.0`. |
| `expectedRevision` | full Git SHA | Revision containing active isolation and fixtures. |
| `cleanupRevision` | full Git SHA | Revision after fixture revert and final convergence. |
| `cluster` | CNI gate summary | Identifies cluster without storing credentials. |
| `applicationInventory` | categorized arrays | Exactly three environment-policy, zero business-service, exactly four retained controller infrastructure Applications, and no `infra-redis`. |
| `environments` | array | Exactly dev, staging, and prod live observations. |
| `redisIsolation` | object | Three Ready/PONG instances, six denied directed cross-environment Redis paths, and Pub/Sub separation. |
| `crossEnvironmentTests` | array | Exactly six unique directed denied pairs. |
| `sameEnvironmentTests` | array | Exactly three allowed pairs. |
| `dnsTests` | array | Exactly three successful checks. |
| `resourceViolation` | object | Expected violated bound, event, and unaffected comparison environment. |
| `rbacChecks` | array | Full matrix plus isolation-control, unbound-subject, and platform checks. |
| `devContinuity` | array | Baseline, staged, and final samples. |
| `commandAudit` | object | Zero managed-state mutation commands. |
| `result` | `PASS` or `FAIL` | `PASS` only when every required result and cleanup passes. |

### Lifecycle

```text
PLANNED
  -> BLOCKED_PREREQUISITE (constitution, registration, CNI, identity, or baseline missing)
  -> FOUNDATION_RECONCILED
  -> DEFAULT_DENY_RECONCILED
  -> SHARED_REDIS_RETIRED
  -> FIXTURES_RECONCILED
  -> TESTED
  -> CLEANUP_RECONCILED
  -> ACCEPTED

Any failed gate -> REVERTING -> CLEANUP_RECONCILED or BLOCKED
```

`ACCEPTED` is impossible from static manifests alone.

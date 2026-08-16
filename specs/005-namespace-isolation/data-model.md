# Data Model: Shared-Cluster Isolation and Release Evidence

## 1. SharedClusterRegistration

The existing Argo CD root registration for the adopted shared EKS cluster.

| Field | Rule |
| --- | --- |
| `physicalClusterName` | `microtodosuite-dev`; immutable in this feature |
| `registrationPath` | `clusters/eks-dev` |
| `destinationServer` | `https://kubernetes.default.svc` |
| `environmentElements` | exactly dev, staging, prod |
| `businessElements` | empty until `ReadyForActivation`, then all three environments in one revision |
| `infrastructureElements` | foundation: four retained controllers + shared Redis; final: four retained controllers + Argo Rollouts |
| `revision` | reviewed full Git SHA observed by Argo CD |

State transition:

```text
FoundationOnly -> DeploymentPrerequisitesReady -> FifteenDeclared
```

The transition to `FifteenDeclared` is forbidden if any release gate is open.

## 2. EnvironmentBoundary

One Argo CD-owned isolation unit.

| Field | Dev | Staging | Prod |
| --- | --- | --- | --- |
| `environment` | `dev` | `staging` | `prod` |
| `namespace` | `microtodo-dev` | `microtodo-staging` | `microtodo-prod` |
| `application` | `env-dev` | `env-staging` | `env-prod` |
| `maintainerGroup` | `microtodosuite:dev-maintainers` | `microtodosuite:staging-maintainers` | `microtodosuite:prod-maintainers` |
| `jwtServiceAccount` | `external-secrets-jwt` | same | same |
| `jwtStore` | `aws-secrets-manager` | same | same |
| `jwtDestinationSecret` | `auth-api-secrets` | same | same |
| `redisService` | `redis:6379` | `redis:6379` | `redis:6379` |

Required owned resources are Namespace, ResourceQuota, LimitRange, Role,
RoleBinding, default-deny and exact allow NetworkPolicies, Redis Deployment,
ServiceAccount and Service, ESO ServiceAccount, SecretStore, and ExternalSecret.

## 3. ResourceBudget

Aggregate namespace ceiling plus per-container LimitRange.

| Environment | `requests.cpu` | `limits.cpu` | `requests.memory` | `limits.memory` | `pods` |
| --- | ---: | ---: | ---: | ---: | ---: |
| dev | `550m` | `2300m` | `896Mi` | `2304Mi` | 12 |
| staging | `625m` | `2700m` | `1Gi` | `2816Mi` | 14 |
| prod | `700m` | `3` | `1152Mi` | `3Gi` | 18 |

Validation rules:

- every steady workload including Redis fits;
- the largest one-service surge fits;
- production also fits one bounded AnalysisRun Job;
- all business Applications are serialized with `maxUpdate: 1`;
- hard quotas are not described as reserved node capacity; and
- final evidence includes live `used` values and cluster allocatable values.

## 4. EnvironmentSecretPath

An independently generated, non-exported JWT value and its least-privilege read
path.

| Field | Rule |
| --- | --- |
| `environment` | one of dev, staging, prod |
| `sourceName` | `microtodosuite/<env>/auth-api-secrets` |
| `generation` | AWS-provider ephemeral random password |
| `storage` | `aws_secretsmanager_secret_version.secret_string_wo` |
| `readerRole` | `microtodosuite-<env>-jwt-reader` |
| `trustedSubject` | `system:serviceaccount:microtodo-<env>:external-secrets-jwt` |
| `allowedActions` | `GetSecretValue`, `DescribeSecret` only |
| `destination` | `microtodo-<env>/auth-api-secrets`, key `JWT_SECRET` |

State transition:

```text
Absent -> TerraformManaged -> StoreValidated -> ExternalSecretReady -> Consumed
```

Evidence stores only readiness, length/digest comparisons, and authorization
results. It never stores the value.

## 5. NeutralImageRepository

One additive Terraform-owned private ECR repository per business service.

| Field | Rule |
| --- | --- |
| `name` | `microtodosuite/<service>` |
| `services` | auth-api, todos-api, users-api, frontend, log-message-processor |
| `tagMutability` | immutable |
| `scanOnPush` | true |
| `encryption` | enabled |
| `environmentTag` | `shared` |
| `legacyRepository` | corresponding `microtodosuite/dev/<service>` remains untouched |

## 6. ReleaseArtifact

The build-once evidence promoted to all environments.

| Field | Rule |
| --- | --- |
| `service` | one of the five exact business services |
| `baselineCommit` | clarification-recorded source SHA |
| `releaseCommit` | reviewed green descendant on `main` |
| `workflowRevision` | immutable shared-workflow SHA |
| `workflowRun` | successful reviewed-main GitHub Actions run |
| `tests` | applicable service tests completed |
| `trivy` | gate passed before push |
| `sbom` | one retained SBOM for the built artifact |
| `repository` | corresponding neutral ECR URI |
| `digest` | one `sha256:<64hex>` manifest digest |
| `signature` | approved GitHub OIDC keyless signature |
| `references` | same URI/digest in dev, staging, and prod |

State transition:

```text
FailingBaseline -> ReviewedFix -> GatesPassed -> Pushed -> Signed -> Admissible
```

No transition after `GatesPassed` may rebuild the image.

## 7. ProgressiveApplicationSet

The EKS-specific release ordering contract.

| Field | Rule |
| --- | --- |
| `generatedCount` | 15 after activation |
| `environmentLabel` | exact dev, staging, or prod |
| `steps` | dev -> staging -> prod |
| `maxUpdate` | 1 in every step |
| `healthGate` | all Applications in prior step Healthy |
| `automatedSync` | absent for generated EKS Applications; RollingSync initiates operations |

Per-environment state:

```text
Pending -> SyncingOne -> GroupHealthy -> NextEnvironmentEligible
               \-> Failed -> LaterGroupsBlocked -> GitRevert
```

## 8. ProductionRollout

One native replica-based canary for each production service.

| Field | Rule |
| --- | --- |
| `service` | one of the five business services |
| `workloadRef` | corresponding base Deployment |
| `replicas` | existing production overlay count |
| `maxSurge` / `maxUnavailable` | 1 / 0 |
| `canaryWeight` | 50 percent, then 100 percent |
| `canaryService` | `<service>-canary` |
| `analysis` | shared Job metric against the canary Service |
| `failureBehavior` | abort and restore stable ReplicaSet |

State transition:

```text
InitialCreation -> StableBootstrap
StableBootstrap -> CanaryReplica -> MetricRunning -> Promoted
                                      \-> MetricFailed -> Aborted -> StableRestored
```

`InitialCreation -> StableBootstrap` is not canary acceptance.

## 9. IsolationEvidenceRun

Immutable summary plus raw observations for one staged revision chain.

Required sections:

- exact GitOps and source revisions;
- environment and business Application inventories/order;
- quota hard/used and deliberate violation;
- CNI/node policy-agent state;
- six cross-environment and three same-environment/DNS results;
- Redis PONG, directed denials, and Pub/Sub separation;
- ESO readiness, non-empty/distinct comparison, and cross-role denials;
- five release artifacts and live Pod image IDs;
- five successful canary analyses and one intentional abort/restoration;
- RBAC matrix or explicit deferred-mapping blocker;
- dev continuity ready/restart/health comparison; and
- zero mutating observer commands.

State transition:

```text
Baseline -> Prerequisites -> Activated -> CanaryProven -> Fixtures -> Cleanup
```

Each transition requires the preceding schema-valid PASS summary on the same
cluster and exact revision chain.

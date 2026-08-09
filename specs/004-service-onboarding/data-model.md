# Data Model: Remaining Service Onboarding

This GitOps repository models desired state, publication evidence, and observed
reconciliation rather than durable business records.

## PlatformDependency

Represents one shared runtime required by business services.

| Field | Meaning | Validation |
| --- | --- | --- |
| `name` | Folder, Application, workload, and Service identity | `redis` |
| `namespace` | Platform-owned destination | `redis` |
| `version` | Runtime version verified from the selected image | `7.4.9` |
| `image` | Executable artifact | Official repository plus immutable SHA-256 digest |
| `endpoint` | Stable in-cluster address | `redis.redis.svc.cluster.local:6379` |
| `consumers` | Allowed business workloads | `todos-api`, `log-message-processor` |
| `storageMode` | Continuity behavior | `ephemeral`; no PVC, snapshot, or AOF |
| `health` | Intrinsic protocol proof | startup/readiness/liveness `PING`; acceptance `PONG` |

State transition:

```text
Rendered -> Local Commit -> Argo Synced -> Deployment Available -> PONG
```

The service publication transition cannot begin until Redis reaches `PONG`.

## ServiceRegistration

Represents one business workload consumed by the shared apps ApplicationSet.

| Field | Meaning | Validation |
| --- | --- | --- |
| `name` | Directory, workload, Service, image key, and label | DNS-compatible and identical across layers |
| `sourceCommit` | Sibling repository build input | Concrete clean `main` SHA captured at publication |
| `port` | Container and Service contract | Matches source listener |
| `healthPath` | Dependency-free health endpoint | Successful without another business service |
| `config` | Non-secret runtime contract | Key names in base; destination-neutral or overlay values |
| `secretRefs` | Existing secret interfaces | Names and keys only; never values |
| `dependencies` | Required in-cluster endpoints | Declared before acceptance |
| `imageDigest` | Selected runtime artifact | Registry-reported `sha256:<64hex>` |
| `replicas` | Local process count | One for all four local services |
| `stateRisk` | Existing non-durable behavior | Explicit for users and todos; never represented as persistence |

State transition:

```text
Source Verified -> Image Built -> Registry Digest -> Local Commit
               -> Argo Synced -> Deployment Available -> Functional Check
```

## SharedJwtContract

Represents the single signing-key interface required by the synchronous service
chain.

| Field | Value |
| --- | --- |
| ESO owner | auth-api local ExternalSecret |
| Secret | `auth-api-secrets` in the active environment namespace |
| Key | `JWT_SECRET` |
| Issuer/consumer | auth-api |
| Validators | users-api and todos-api |
| Stored in Git | never |

Relationship: one SharedJwtContract is referenced by three ServiceRegistrations.
Independent generators are invalid because their values would differ.

## ImagePublication

Represents one build and push performed before service reconciliation.

| Field | Meaning |
| --- | --- |
| `service` | Stable business service name |
| `sourcePath` | Verified sibling checkout |
| `sourceCommit` | Exact Git SHA used by Docker build |
| `registry` | Loopback pilot registry only |
| `convenienceTag` | Push handle; never desired state |
| `digest` | Registry-reported immutable manifest identifier |
| `desiredStateCommit` | Local Git SHA selecting that digest |

## FunctionalEvidenceRun

Represents one timestamped acceptance attempt.

| Field | Meaning |
| --- | --- |
| `expectedRevision` | Current SHA of the pilot bare repository |
| `applications` | Required app names with revision, sync, health, conditions |
| `deployments` | Desired/ready/available replicas and running images |
| `pods` | Phase, readiness, restart counts, and image IDs |
| `redisPing` | Raw Redis response |
| `healthChecks` | Status, body excerpt, and timestamp per service |
| `login` | Valid/invalid status and token presence; secret never captured |
| `profile` | Seeded users-api response for the token subject |
| `todos` | List response and created todo response |
| `processor` | Metric before/after and matching event log line |
| `frontend` | Shell, proxied login, and proxied todo results |
| `continuity` | Explicit Redis/todos/H2 risk statements |

State transition:

```text
Started -> Revision Matched -> Applications Healthy -> Pods Ready
        -> Intrinsic Health Passed -> Auth/Users Passed -> Todo Event Passed
        -> Frontend Routes Passed -> Complete
```

Any timeout or mismatched revision/image leaves the run incomplete.

# Contract: Service and Environment Onboarding

This contract makes the retained `apps/<service>/base` plus
`apps/<service>/overlays/<environment>` shape reusable for all eight
MicroTodoSuite service slots and future managed clusters. It changes values,
never the repository hierarchy, ApplicationSet mechanism, promotion model, or
verification model.

## Directory contract

Every business service has exactly this shape:

```text
apps/<service>/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── serviceaccount.yaml
│   └── configmap.yaml                # only when the service has non-secret config
└── overlays/
    ├── local/
    │   ├── kustomization.yaml
    │   └── external-secret.yaml      # when the service consumes a secret
    ├── dev/
    ├── staging/
    └── prod/
```

Only an overlay selected by an active cluster registration is deployable. A
directory's existence is not an activation mechanism.

## Required service inputs

Onboarding supplies these values without changing the contract:

| Input | Owner | Constraint |
| --- | --- | --- |
| Service name | Service definition | DNS-compatible; equals directory, workload, Service, neutral image key, and name label. |
| Container and Service ports | Service definition/base | Stable network contract. |
| Intrinsic health path | Service definition/base | Must return success without another MicroTodoSuite business service. |
| Config key names | Service definition/base | Names only; environment values stay in overlays. |
| Secret name/key interfaces | Service definition/base | References only; no provider or value. |
| Common labels | Shared contract/base | Includes `app.kubernetes.io/name`, `part-of=microtodosuite`, and `component=business-service`. |
| Security context | Shared contract/base | Least privilege; any exception documented per service. |
| Service account | Shared contract/base | Dedicated and `automountServiceAccountToken: false` unless Kubernetes API access is justified. |

## Required environment inputs

| Input | Owner | Constraint |
| --- | --- | --- |
| Environment and namespace | Cluster registration/overlay | Overlay basename equals selected environment; namespace equals exact project destination. |
| Registry/repository | Overlay | Supplied with Kustomize `newName`; never hardcoded in base. |
| OCI digest | Overlay | `sha256:` plus 64 lowercase hexadecimal characters; required when active. |
| Replica count | Overlay | Positive and compatible with environment quota. |
| CPU/memory requests and limits | Overlay | Compatible with environment LimitRange and ResourceQuota. |
| Config values | Overlay | Only declared keys; local/managed values must not leak into base. |
| Exposure | Overlay/environment | Local port-forward or managed ingress settings. |
| Secret source | Overlay/environment | ESO generator/provider; target name/key equals the base interface. |

## Environment-owned resources

The following resources are forbidden under `apps/<service>` because they
govern a namespace or platform shared by services:

- Namespace
- ResourceQuota
- LimitRange
- default-deny and shared allow NetworkPolicies
- operator/verifier Roles and RoleBindings
- ArgoCD AppProjects
- CRDs and platform controllers
- cluster/repository registrations

They live under `clusters/base/environment`, a concrete cluster overlay, or the
explicit platform path.

## `auth-api` mapping

| Contract field | `auth-api` value | Layer |
| --- | --- | --- |
| Service name | `auth-api` | Service definition/base |
| Container/Service port | `8000` | Base |
| Intrinsic health path | `/version` | Base |
| Required config keys | `AUTH_API_PORT`, `USERS_API_ADDRESS` | Names in base; values in overlay |
| Optional config key | `ZIPKIN_URL` | Name in service documentation; value only when platform exists |
| Secret interface | `auth-api-secrets/JWT_SECRET` | Reference in base |
| Local secret source | ESO `Password` with `JWT_SECRET` output | Local overlay |
| Future managed source | AWS Secrets Manager mapping through ESO | Managed overlay |
| Neutral image key | `auth-api` | Base |
| Registry and digest | `localhost:5001/auth-api@sha256:...` | Local overlay |
| Replicas/resources | Local capacity profile | Local overlay |
| Namespace policy | `microtodo-local` environment resources | Cluster/environment layer |

`USERS_API_ADDRESS` may refer to a non-running endpoint in this exactly-one
service pilot because `/version` does not invoke it. Login is not an acceptance
health path.

## Remaining service mappings

Feature 004 completes the business-service set without changing this contract.

| Contract field | `todos-api` | `users-api` | `frontend` | `log-message-processor` |
| --- | --- | --- | --- | --- |
| Container/Service port | `8082` | `8083` | `8080` | `9090` |
| Intrinsic health path | `/metrics` | `/prometheus` | `/` | `/metrics` |
| Secret interface | `auth-api-secrets/JWT_SECRET` | `auth-api-secrets/JWT_SECRET` | none | none |
| Required service | `redis.redis.svc.cluster.local:6379` | none | `auth-api:8000`, `todos-api:8082` | `redis.redis.svc.cluster.local:6379` |
| Local replicas | 1 | 1 | 1 | 1 |
| Continuity limit | process-local todo cache | pod-local H2 seed data | static assets | live Redis subscription |

auth-api remains the single owner of the local ExternalSecret target. Both JWT
validators reference that target; independent generators are forbidden because
their values would differ.

Redis is a platform dependency discovered from `infrastructure/redis`, not a
business-service sidecar. Its local single-node data is intentionally
non-durable and does not establish a production persistence or DR design. It
must reconcile and answer `PONG` at an earlier local Git revision before the two
Redis consumers are activated.

users-api preserves its current H2 behavior: each pod creates the seed data from
its image. No volume or database is implied, and restarts or multiple replicas
can recreate or diverge state. todos-api likewise preserves its process-local
cache and stays at one local replica.

## User-facing exposure mapping

The existing exposure input is sufficient for frontend. Locally, an operator
port-forwards the ClusterIP Service and the frontend's NGINX process proxies
same-origin `/login` and `/todos` requests to internal Services. No local
Ingress, Gateway, NodePort, or host binding is part of the service registration.
Managed TLS ingress remains an environment-owned value under this same contract.

## Cluster registration contract

Every cluster directory reuses `clusters/base` and changes only:

- cluster name;
- selected environment;
- repository endpoint and revision;
- destination Kubernetes endpoint and namespace;
- image registry endpoint;
- environment capacity/exposure values; and
- explicit active platform dependencies.

The shared Matrix ApplicationSet, App-of-Apps flow, automated sync/prune/heal,
directory pattern, labels, and evidence mechanism must not be copied and edited.

Example value-only mapping:

| Value | `local-kind` | Future `eks-dev` fixture |
| --- | --- | --- |
| Environment | `local` | `dev` |
| Repository | machine-local HTTP | approved Git repository endpoint |
| Destination | `https://kubernetes.default.svc` | registered EKS endpoint |
| Namespace | `microtodo-local` | `microtodo-dev` |
| Registry | `localhost:5001` | account/region ECR endpoint |
| Image selection | OCI digest | the same promoted OCI digest |

## Conformance rules

`tests/conformance/service-contract.sh` must fail when any of these is true:

1. A service lacks `base/kustomization.yaml` or the selected overlay.
2. An active overlay does not render.
3. A base contains namespace, registry, digest/tag, replicas, resources,
   provider-specific secrets, or environment-wide policy.
4. An active overlay uses a tag without a digest, `latest`, or an all-zero
   placeholder digest.
5. A business workload lacks the three standard labels, an intrinsic health
   probe, or a token-disabled ServiceAccount.
6. A Secret value or secretGenerator literal/env file is committed.
7. An overlay's ESO target differs from the base Secret name/key contract.
8. The ApplicationSet would generate more or less than the intended environment
   for the supplied registration.

The fixture suite renders the canonical `auth-api` instance and seven abstract
slots (`service-slot-02` through `service-slot-08`). Fixtures are never selected
by an active ApplicationSet and do not claim that those are real service names.

`tests/conformance/cluster-contract.sh` must prove that local and future EKS
fixtures differ only in the declared registration values. It must fail on a
copied/replaced generator or hierarchy change.

## Promotion and rollback contract

- Build once and obtain the OCI manifest/index digest.
- Commit the digest to the source environment overlay.
- Promote by copying the exact digest value; if registries differ, verify that
  the destination manifest/index digest is identical.
- Make rollback only by committing `git revert` of the desired-state change.
- Never document `kubectl apply`, `set image`, `rollout undo`, manual Argo sync,
  or CI-to-cluster mutation as a supported change path.

## Production gate

The `prod` overlay is a non-active scaffold. No cluster registration may select
it until every item in `docs/production-readiness.md` is satisfied and reviewed.
The local project permits only `microtodo-local`, and
`tests/conformance/production-disabled.sh` rejects `environment: prod` in any
active pilot registration.

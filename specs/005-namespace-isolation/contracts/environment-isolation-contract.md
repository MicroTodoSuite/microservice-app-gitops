# Contract: Managed Environment Isolation

## Purpose

This contract defines the reusable desired-state and live-evidence boundary for
`dev`, `staging`, and `prod` on the one shared EKS cluster. It does not activate
the cluster or authorize Terraform, AWS, ArgoCD UI, or direct Kubernetes changes.

## Ownership

| Concern | Owner | This feature's behavior |
| --- | --- | --- |
| VPC, EKS, nodes, VPC CNI add-on, IAM, ECR | `microservice-app-ops` / Terraform | Read-only prerequisite evidence; no edits. |
| ArgoCD bootstrap and shared identity | Existing `clusters/eks-dev` registration | Reuse the live root and physical cluster without renaming or bootstrap changes. |
| Infrastructure ApplicationSet activation values | This GitOps feature | Use an exact per-cluster list; retain four controllers plus shared Redis through replacement verification, then remove only shared Redis. |
| Namespace, quota, limits, network policy, namespace RBAC | This GitOps feature | Declarative paths below. |
| Environment Redis | This GitOps feature | One immutable, ephemeral instance in each managed namespace. |
| AWS principal-to-Kubernetes-group mapping | Cluster-access handoff | Required live evidence; no personal ARN in environment manifests. |
| New platform add-ons and business-service workloads | Their own feature specs | No activation in this feature. |
| Verification fixtures | This feature | Opt-in Git resources, activated and removed through reviewed revisions. |

## Directory and Render Contract

The planned final layout is:

```text
environments/
├── base/
│   ├── kustomization.yaml
│   ├── limitrange.yaml
│   ├── networkpolicy-default-deny.yaml
│   ├── networkpolicy-allow-dns.yaml
│   ├── networkpolicy-allow-intra-namespace.yaml
│   ├── networkpolicy-allow-redis.yaml
│   ├── redis-deployment.yaml
│   ├── redis-service.yaml
│   ├── redis-serviceaccount.yaml
│   └── role.yaml
├── dev/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── resourcequota.yaml
│   ├── rolebinding.yaml
│   └── networkpolicy-allow-required-egress.yaml  # only evidenced rules
├── staging/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── resourcequota.yaml
│   └── rolebinding.yaml
└── prod/
    ├── kustomization.yaml
    ├── namespace.yaml
    ├── resourcequota.yaml
    └── rolebinding.yaml
```

`networkpolicy-default-deny.yaml` exists in the final base but is introduced in
a later rollout revision than the prerequisite allow rules. No environment may
replace the common default deny, LimitRange, same-namespace allowance, DNS
allowance, or Role with a divergent copy.

Each final steady-state environment render MUST contain exactly:

- one Namespace with the exact mapping below;
- one ResourceQuota with evidence-approved CPU, memory, and pod bounds;
- one LimitRange with CPU/memory defaults and maxima;
- one ingress-and-egress default-deny NetworkPolicy;
- one DNS allowance;
- one same-namespace allowance;
- zero or more exact environment-specific allowances;
- one custom workload Role; and
- one RoleBinding to the exact environment group;
- one Redis Deployment and ServiceAccount;
- one namespace-local Redis ClusterIP Service; and
- one Redis-specific ingress policy.

| Environment | Namespace | ArgoCD Application | Maintainer group |
| --- | --- | --- | --- |
| `dev` | `microtodo-dev` | `env-dev` | `microtodosuite:dev-maintainers` |
| `staging` | `microtodo-staging` | `env-staging` | `microtodosuite:staging-maintainers` |
| `prod` | `microtodo-prod` | `env-prod` | `microtodosuite:prod-maintainers` |

The Application names and namespace derivation come from the existing
`clusters/base/environments.yaml` ApplicationSet. The `clusters/eks-dev`
registration MUST activate all three with
`server: https://kubernetes.default.svc`, keep business-service activation
empty, and retain the exact five-entry foundation infrastructure list until
environment Redis is verified. The later retirement revision removes only
shared Redis. This feature does not bootstrap or rename the cluster.

## Static Invariants

- Every overlay renders with `kubectl kustomize` and schema-validates with the
  implementation's pinned validator.
- The three overlays consume the same base.
- Namespace names, labels, RoleBinding subjects, and ArgoCD destination mapping
  agree with the table above.
- ResourceQuota covers `requests.cpu`, `limits.cpu`, `requests.memory`,
  `limits.memory`, and `pods` with positive values.
- LimitRange defines container default requests, default limits, and maxima for
  CPU and memory.
- Default deny selects all pods for both `Ingress` and `Egress`.
- DNS rules do not use an unrestricted egress block.
- Each managed render contains exactly one Redis Deployment and Service in the
  rendered namespace, selected by immutable digest.
- Managed todos-api and log-message-processor overlays resolve
  `REDIS_HOST=redis`; their local overlays retain the local pilot endpoint.
- Cross-environment allowances, wildcard RBAC subjects/resources/verbs,
  `system:authenticated`, personal IAM ARNs, direct secret values, mutable image
  tags, and cloud credentials are absent.
- `environments/local` has no diff from its pre-feature revision.
- The live Application inventory contains exactly `env-dev`, `env-staging`, and
  `env-prod` from the managed activation scope, zero business-service
  Applications, and an exact stage-specific infrastructure allowlist: the four
  retained controllers plus `infra-redis` before Redis retirement, then only
  the four controllers afterward. Pre-existing dev workloads are inventoried
  separately and remain continuity subjects.

## Staged Activation Contract

### Stage 0: prerequisites and baseline

Required evidence:

- authoritative constitution is v1.2.0;
- the existing `clusters/eks-dev` registration is reviewed as the shared target, with
  three environment Applications, no business Applications, and the exact four
  retained controller Applications plus the existing `infra-redis`;
- CNI enforcement gate passes on every eligible node;
- identity group mapping is confirmed before RBAC acceptance; the foundation
  may leave the stable groups unmapped under the recorded deferral;
- dev Applications are current and healthy;
- current dev requests, limits, ready replicas, restarts, health paths, and
  required network connections are recorded; and
- proposed quota values leave documented rollout and platform reserve.

Any CNI, registration, capacity, or immutable-input failure blocks Stage 1.
Deferred identity mapping blocks only the RBAC acceptance claim and MUST NOT be
worked around by mapping one principal to every environment.

### Stage 1: foundation and allow rules

A reviewed Git revision reconciles Namespace, ResourceQuota, LimitRange, RBAC,
DNS, same-namespace policy, namespace-local Redis, and exact required dev
allowances. Default deny is not active in this revision. All three environment
applications and Redis instances must converge, every instance must return
`PONG`, and dev continuity must match baseline before Stage 2.

### Stage 2: default deny

A later reviewed Git revision adds default deny to the managed base. The
operator waits for exact-revision convergence and records dev continuity again.
Any loss of readiness, new attributable restart, or failed required connection
causes a Git revert before fixtures are activated.

### Stage 3: shared Redis retirement

A later reviewed Git revision removes only `redis` from the managed cluster's
explicit infrastructure list. The four controller Applications remain
Synced/Healthy, `infra-redis` and namespace `redis` disappear through ArgoCD
pruning, and all three environment Redis instances remain Ready.

### Stage 4: verification fixtures

A later reviewed Git revision references the opt-in fixtures. The fixture image
must be immutable, available before egress deny, and run as Deployment-owned
pods. The resulting logs and Kubernetes events must prove:

- six directed cross-environment connections denied;
- three same-environment connections allowed;
- DNS allowed in all three namespaces;
- three Redis `PONG` checks;
- six directed cross-environment Redis connections denied;
- one unique Pub/Sub event observed only in its source environment;
- one over-budget Deployment cannot realize its excess pod;
- the comparison environment remains healthy; and
- the complete RBAC authorization matrix.

### Stage 5: cleanup

`git revert` removes fixture activation. Final acceptance waits until all three
environment applications are Synced/Healthy at the cleanup revision, no fixture
workload remains, and dev continuity still matches baseline.

## Live Evidence Contract

The verifier writes one directory below
`.local/evidence/namespace-isolation/<timestamp>/` containing at minimum:

```text
summary.json
command-log.txt
applications/
cluster/
environments/
network/
redis/
rbac/
resource/
dev-continuity/
```

`summary.json` MUST validate against
[`namespace-isolation-evidence.schema.json`](namespace-isolation-evidence.schema.json).
Raw files preserve the API observations and logs used by each summary result.

## Failure and Rollback Contract

- A failed gate sets the run result to `FAIL`; evidence is not rewritten to hide
  the failure.
- Desired-state recovery is a reviewed Git revert of the failing stage.
- The operator may use read-only diagnostics, logs, events, and health calls.
- The operator MUST NOT use `kubectl apply`, `create`, `patch`, `replace`,
  `scale`, `rollout`, `delete`, or an ArgoCD UI mutation to repair the cluster.
- A revert is not complete until ArgoCD reports the cleanup revision and dev
  continuity is rechecked.

## Explicit Non-Guarantees

This contract does not claim separate failure domains, dedicated CPU/node
reservation, protection from control-plane failure, protection from a privileged
cluster administrator or compromised ArgoCD controller, layer-7 policy, service
mesh mTLS, durable Redis data, or disaster recovery. Redis instances isolate
event streams but remain ephemeral. Those limits are part of the accepted
cost-optimized trade-off or separate specifications.

# Contract: Shared-Cluster Isolation and Managed Release

## Scope

This contract governs the single shared EKS cluster adopted by constitution
v1.2.0. It covers the three namespace boundaries and the one reviewed release
of auth-api, todos-api, users-api, frontend, and log-message-processor across
dev, staging, and production.

## Exact environment mapping

| Environment | Namespace | Environment Application | Maintainer group | JWT source |
| --- | --- | --- | --- | --- |
| dev | `microtodo-dev` | `env-dev` | `microtodosuite:dev-maintainers` | `microtodosuite/dev/auth-api-secrets` |
| staging | `microtodo-staging` | `env-staging` | `microtodosuite:staging-maintainers` | `microtodosuite/staging/auth-api-secrets` |
| prod | `microtodo-prod` | `env-prod` | `microtodosuite:prod-maintainers` | `microtodosuite/prod/auth-api-secrets` |

The physical cluster and GitOps root retain their legacy identifiers
`microtodosuite-dev` and `clusters/eks-dev`.

## Namespace boundary invariants

Every managed environment render MUST contain exactly one:

- Namespace with the exact mapping above;
- ResourceQuota with all five required bounds;
- LimitRange with default requests, default limits, minima, and maxima;
- workload-maintainer Role and exact group RoleBinding;
- ingress-and-egress default-deny policy;
- DNS, same-namespace, and Redis-specific exact allow rules;
- namespace-local Redis Deployment, ServiceAccount, and Service;
- `external-secrets-jwt` ServiceAccount;
- namespaced `aws-secrets-manager` SecretStore; and
- `auth-api-secrets` ExternalSecret.

No managed render may contain a wildcard RBAC subject/resource/verb, personal
IAM ARN, broad other-environment selector, shared Redis endpoint, literal secret
value, or mutable image.

## Resource budget contract

| Environment | Requests CPU | Limits CPU | Requests memory | Limits memory | Pods |
| --- | ---: | ---: | ---: | ---: | ---: |
| dev | `550m` | `2300m` | `896Mi` | `2304Mi` | `12` |
| staging | `625m` | `2700m` | `1Gi` | `2816Mi` | `14` |
| prod | `700m` | `3` | `1152Mi` | `3Gi` | `18` |

These ceilings admit steady state plus the largest serialized one-service surge;
production also admits one bounded AnalysisRun Job. They are not dedicated node
reservations and do not guarantee complete rescheduling after loss of one of the
two workers.

## AWS secret contract

- Terraform creates three independent Secrets Manager secrets and versions.
- Secret values are generated ephemerally and supplied only through a write-only
  provider argument.
- Each source secret has one IAM role trusted by one exact Kubernetes
  service-account subject.
- Each policy allows only `secretsmanager:GetSecretValue` and
  `secretsmanager:DescribeSecret` on one exact ARN.
- ESO materializes `auth-api-secrets/JWT_SECRET` only in the matching namespace.
- Evidence may compare hashes or lengths but MUST NOT print or persist values.
- All six attempts to read another environment's source secret MUST be denied.

## Registry and artifact contract

Exactly five additive private repositories exist:

```text
microtodosuite/auth-api
microtodosuite/todos-api
microtodosuite/users-api
microtodosuite/frontend
microtodosuite/log-message-processor
```

The existing empty `microtodosuite/dev/*` repositories remain unchanged.

For each service, one reviewed green `main` run MUST:

1. run applicable tests;
2. build the image once locally;
3. pass Trivy against that exact image;
4. produce one retained SBOM;
5. assume AWS through the exact GitHub OIDC publisher role;
6. push the already-tested image once;
7. resolve its ECR manifest digest; and
8. keylessly sign that exact digest.

Dev, staging, and prod MUST reference the same repository URI and digest. A PR
run, failing run, rebuilt artifact, unsigned digest, unapproved workflow
identity, mutable tag, placeholder registry, or all-zero digest is ineligible.

Kyverno MUST enforce digest use, probes, and approved keyless signatures for
neutral-ECR business images before activation.

## ApplicationSet release contract

Before activation, the business generator's list is empty. The final activation
revision adds all three `{env, server}` objects together. Matrix discovery then
declares exactly fifteen Applications.

Each generated EKS Application has label
`microtodosuite.io/environment=<env>`. EKS-only RollingSync has three ordered
steps and `maxUpdate: 1`:

```text
dev -> staging -> prod
```

The next environment is ineligible until every Application in the current
environment is Healthy. A failed group leaves later groups unapplied and starts
the reviewed Git-revert recovery path. Local-kind remains outside this strategy.

## Infrastructure inventory contract

Before shared-Redis retirement, the exact list is:

```text
infra-keda
infra-cert-manager
infra-external-secrets
infra-kyverno
infra-redis
```

After all three local Redis instances pass and before business activation, the
exact list is:

```text
infra-keda
infra-cert-manager
infra-external-secrets
infra-kyverno
infra-argo-rollouts
```

Folder discovery is forbidden. The local-kind Redis registration is unchanged.

## Production Rollout contract

All five production overlays render one Rollout plus one dedicated canary
Service. The Rollout reuses the Deployment pod template, serializes with
`maxSurge: 1`/`maxUnavailable: 0`, exposes a live canary at 50 percent, and
blocks on an inline Job metric targeting that canary Service.

The initial creation establishes the first stable ReplicaSet and is not canary
evidence. Production acceptance additionally requires:

- a reviewed same-digest pod-template evidence revision;
- five successful AnalysisRuns associated with five promoted Rollouts;
- one reviewed negative metric revision;
- observed `AnalysisRun Failed`, `Rollout Aborted`, and stable restoration; and
- recovery by Git revert with all five original digests retained.

## Staged activation contract

### Stage 0: baseline

Record constitution, cluster identity, node/CNI state, Argo CD inventory,
namespace resources, quotas/usage, Redis health, dev readiness/restarts, and all
open prerequisites. Zero business Applications is required.

### Stage 1: AWS and supply chain

Merge the live foundation source, repair the Terraform role, and apply a reviewed
additive plan for ECR, secrets, and identities. Merge the sequential shared
workflow and five green service PRs. Record five admissible release artifacts.

### Stage 2: deployment prerequisites

Reconcile progressive-sync support, Argo Rollouts, ESO resources, signature
admission, economical topology, quota changes, and shared-Redis retirement. Zero
business Applications remains required. All three ExternalSecrets and Redis
instances must be Ready.

### Stage 3: single activation

One reviewed revision declares all fifteen Applications and the five release
digests. Observe dev, staging, and prod in order; any failure blocks the next
group and is reverted.

### Stage 4: production evidence

Run the same-digest successful canary revision, the intentional negative gate,
and Git-revert recovery.

### Stage 5: isolation fixtures

Activate GitOps-owned fixtures and prove six directed network denials, three
same-environment paths, DNS, three Redis PONGs, six Redis denials, three isolated
Pub/Sub streams, one quota rejection, comparison-environment continuity, and the
RBAC matrix when approved mappings exist.

### Stage 6: cleanup

Git revert removes fixtures. All Applications return to the exact cleanup
revision, workloads remain Healthy, and acceptance evidence is schema-valid.

## Failure and mutation contract

- Every failed gate remains recorded as FAIL; evidence is never rewritten.
- Recovery of managed state is a reviewed Git revert.
- Observers may read Kubernetes, Argo CD, AWS metadata, GitHub results, logs,
  events, authorization results, and endpoints.
- Observers MUST NOT apply, create, patch, replace, scale, edit, or delete a
  GitOps-managed Kubernetes resource.
- AWS resource creation MUST NOT use ad hoc AWS CLI calls; only the reviewed
  Terraform state owner may create or change it.

## Explicit non-guarantees

This contract does not promise separate cluster/VPC failure domains, dedicated
node reservation, complete one-node-loss rescheduling, durable Redis, durable
todos or H2 state, layer-7 network policy, service-mesh mTLS, full Prometheus or
logging coverage, AKS DR, or protection from a compromised cluster
administrator/Argo CD controller. Those limitations remain disclosed rather
than being converted into acceptance claims.

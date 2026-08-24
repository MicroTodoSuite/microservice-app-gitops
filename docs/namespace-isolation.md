# Managed Namespace Isolation and Release Runbook

Feature 005 implements the cost-optimized shared-cluster boundary for
`microtodo-dev`, `microtodo-staging`, and `microtodo-prod`. Argo CD owns every
Namespace, quota, limit, NetworkPolicy, Role, RoleBinding, environment Redis
instance, External Secrets resource, business workload, and verification
fixture. No managed object is created or changed with an imperative `kubectl`
command.

This document is an operator runbook, not permission to skip a release gate.
The acceptance source is
`specs/005-namespace-isolation/checklists/acceptance.md`; an unchecked item is a
failed or unavailable outcome, never an implied pass.

## Ownership

This repository owns:

- one reusable managed-environment base and three value-only overlays;
- exact infrastructure, environment, and business-application activation lists;
- namespace-local Redis and AWS Secrets Manager consumption contracts;
- Argo CD RollingSync and production Argo Rollouts policy;
- enforcing immutable-image, health-probe, and signature admission policy;
- read-only evidence collection; and
- opt-in network, resource, RBAC, and release verification fixtures.

The ops repository owns EKS capacity, VPC CNI network-policy enforcement, ECR,
Secrets Manager source secrets, GitHub and workload IAM roles, and EKS access
entries. Service repositories own tests and the one-build supply-chain pipeline
that publishes a reviewed digest, SBOM, and keyless signature. The reviewed
cluster registration owns the root Application.

## Shared environment boundary

Every environment renders these resources from `environments/base`:

- a bounded Container LimitRange;
- ingress-and-egress default deny;
- DNS egress limited to kube-system CoreDNS on TCP/UDP 53;
- same-namespace ingress and egress;
- Redis ingress limited to same-namespace pods on TCP 6379;
- a namespaced External Secrets ServiceAccount, SecretStore, and ExternalSecret;
- a custom workload-maintainer Role that excludes Secrets and isolation controls;
- one ephemeral, single-replica Redis Deployment and ClusterIP Service using a
  digest-pinned image.

The overlays add the Namespace, ResourceQuota, exact JWT reader role/source key,
and one environment-specific group binding:

| Environment | Namespace | CPU requests | CPU limits | Memory requests | Memory limits | Pods | Group |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| dev | `microtodo-dev` | 550m | 2300m | 896Mi | 2304Mi | 12 | `microtodosuite:dev-maintainers` |
| staging | `microtodo-staging` | 625m | 2700m | 1Gi | 2816Mi | 14 | `microtodosuite:staging-maintainers` |
| prod | `microtodo-prod` | 700m | 3 CPU | 1152Mi | 3Gi | 18 | `microtodosuite:prod-maintainers` |

These are admission ceilings, not reserved node capacity. They include the
reviewed economical steady state, one serialized production canary surge, the
bounded analysis Job, and namespace Redis. `maxUpdate: 1` serializes Applications
within every RollingSync environment step and avoids concurrent quota surges.
Capacity must be remeasured before increasing replicas or rollout concurrency.

Redis is intentionally ephemeral. Per-environment instances prevent Pub/Sub
events from crossing environments, but they do not provide persistence,
failover, backups, or a continuity guarantee.

## Exact infrastructure registration

`clusters/base/infrastructure.yaml` accepts only reviewed
`{name,path,namespace}` entries and never scans `infrastructure/*`.

- `clusters/local-kind/activation-infrastructure.yaml` retains the local pilot
  entries, including its shared Redis.
- `clusters/eks-dev/activation-infrastructure.yaml` retains the complete
  twelve-controller target profile.
- `clusters/eks-dev-capacity-constrained/activation-infrastructure.yaml`
  is the active replacement-cluster recovery profile and declares only KEDA,
  cert-manager, External Secrets Operator, Kyverno, and Argo Rollouts.
- The former shared `infra-redis` Application is absent from the managed list;
  Argo CD prunes it only when the reviewed prerequisite revision reconciles.

The physical EKS name and `clusters/eks-dev` registration are historical
identifiers. The root Application keeps the same object identity but selects a
sibling capacity profile through reviewed Git. The cluster remains the shared
target for all three namespaces.

## Release controls

Argo CD Progressive Syncs is enabled through its self-managed ConfigMap and a
pod-template revision annotation. The EKS-only ApplicationSet strategy orders
dev, then staging, then prod, with `maxUpdate: 1`; generated business
Applications do not use independent automated sync.

Production overlays use Argo Rollouts with the economical topology. Each
Rollout owns the base Deployment through `workloadRef`, maintains a dedicated
canary Service, allows one surge pod with zero unavailable replicas, and runs a
bounded HTTP Job analysis before promotion. The first creation of a Rollout has
no stable ReplicaSet and therefore cannot prove a canary; a later unchanged-
digest pod-template evidence revision supplies the required successful canary
observation.

Kyverno requires every business Pod to use an immutable digest, define
liveness/readiness probes, and carry a valid keyless signature from the pinned
organization workflow invoked by the exact service repository on `main`.

## Mandatory GitOps sequence

### 0. Establish AWS and release prerequisites

Before merging a GitOps prerequisite revision:

1. apply the reviewed least-privilege Terraform execution policy through the
   account's IAM bootstrap owner;
2. run a refresh-backed saved Terraform plan as
   `microtodosuite-terraform-dev` and stop on any replacement, deletion, or
   unrelated node update;
3. merge and apply exactly the reviewed plan that creates five neutral ECR
   repositories, three independent write-only secrets, exact JWT reader roles,
   the GitHub publisher role/provider, and the Kyverno verifier role;
4. merge only green service PRs; and
5. observe each `main` workflow publish one tested, scanned, SBOM-recorded,
   signed digest to its neutral repository.

Never print a JWT value or store one in Git, a plan file, Terraform state,
workflow logs, or evidence.

### 1. Reconcile GitOps prerequisites with activation empty

Merge a reviewed revision that keeps
`clusters/eks-dev/activation-apps.yaml` empty while enabling Progressive Syncs,
Argo Rollouts, External Secrets, final quotas, default deny, signature policy,
and the five-entry controller inventory. Wait for the exact revision and prove:

- the ApplicationSet controller restarted with Progressive Syncs enabled;
- Argo Rollouts CRDs/controller and the shared ClusterAnalysisTemplate are ready;
- all three ExternalSecrets are Ready and their destination values are non-empty
  and mutually distinct without revealing them;
- all three namespace Redis Deployments are Ready and return `PONG`;
- shared Redis is pruned while all five retained controllers are Healthy; and
- zero business Applications exist.

Any failed secret, admission, DNS, Redis, or controller gate blocks activation.

### 2. Activate one release in all environments

Replace every registry placeholder with the five published neutral ECR URIs
and exact digests. A service uses the same digest in dev, staging, and prod.
Set all three environment elements together in
`clusters/eks-dev/activation-apps.yaml` in one reviewed revision. Confirm the
render declares exactly fifteen Applications before merge.

Observe five serialized Healthy dev operations before staging begins, five
serialized Healthy staging operations before prod begins, and five serialized
Healthy production operations. Preserve the pre-activation and post-activation
dev readiness, restart, health, secret, Redis, and resource samples.

### 3. Prove production canary success and failure recovery

After the first production ReplicaSets are stable, change only a reviewed
production pod-template evidence annotation while preserving all five digests.
Require five successful AnalysisRuns. Then activate the GitOps-owned failing
analysis fixture, observe `Failed -> Aborted -> stable restored`, and recover
with a reviewed `git revert`.

### 4. Prove isolation and containment

Activate only the reviewed fixtures under
`tests/fixtures/namespace-isolation`. Acceptance requires six denied directed
cross-environment TCP paths, six denied Redis paths, three DNS successes, three
same-environment successes, isolated Pub/Sub events, the expected quota
admission failure, an unchanged comparison environment, and the full RBAC
matrix.

Remove every fixture with a reviewed Git revert and wait for exact-revision
convergence before the final observation.

## Read-only observer

The observer always requires an explicit kube context and full Git SHA:

```bash
scripts/managed/verify-namespace-isolation.sh \
  --context <reviewed-eks-context> \
  --expected-cluster-id <reviewed-kubeconfig-cluster-id> \
  --phase baseline \
  --expected-revision <40-hex-sha>
```

Later phases consume the immediately preceding summary so the continuity chain
cannot be reset between observations:

```bash
scripts/managed/verify-namespace-isolation.sh \
  --context <reviewed-eks-context> \
  --expected-cluster-id <reviewed-kubeconfig-cluster-id> \
  --phase fixtures \
  --expected-revision <40-hex-sha> \
  --previous-evidence .local/evidence/namespace-isolation/<previous-run>/summary.json
```

Raw objects, events, logs, authorization responses, command audit, and
`summary.json` remain in the ignored
`.local/evidence/namespace-isolation/` directory. The observer has no sync,
rollout, or managed-resource mutation path.

## Failure and rollback

Stop at the first failed gate. Preserve the failed evidence directory and link
it from the checklist. Recovery is a reviewed `git revert` of the failing
desired-state revision, followed by exact-revision convergence and a repeat of
the preceding passing observation.

Do not broaden a NetworkPolicy, Role, quota, signature identity, or IAM trust to
make a test green. Identify the exact omitted dependency, review the narrow
change, and repeat the staged evidence sequence.

## Accepted limitations

Namespace isolation does not create dedicated nodes, VPCs, control planes, IAM
accounts, storage, or cryptographic pod identity. ResourceQuota bounds admitted
namespace demand but cannot eliminate every node-level noisy-neighbor effect.
NetworkPolicy controls pod traffic but does not encrypt it. Redis remains a
single ephemeral replica per environment. The Job metric proves bounded HTTP
availability, not an aggregate request error rate. These are explicit tradeoffs
of the constitution v2.0.0 cost-optimized profile.

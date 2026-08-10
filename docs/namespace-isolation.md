# Managed Namespace Isolation

Feature 005 implements the cost-optimized shared-cluster boundary for
`microtodo-dev`, `microtodo-staging`, and `microtodo-prod`. The boundary is
declarative: ArgoCD owns every Namespace, quota, limit, network policy, RBAC
object, environment Redis instance, and temporary verification fixture.

This document is an operator runbook, not permission to activate an unreviewed
cluster registration. The acceptance source is
`specs/005-namespace-isolation/checklists/acceptance.md`; an unchecked item is a
failed or unavailable gate, never an implied pass.

## Ownership and non-goals

This repository owns:

- one reusable managed-environment base and three value-only overlays;
- exact infrastructure activation lists;
- the namespace-local Redis endpoint contract;
- read-only evidence collection; and
- opt-in network and resource verification fixtures.

The ops repository owns EKS capacity, the VPC CNI add-on configuration, worker
nodes, EKS access entries, and AWS-principal-to-Kubernetes-group mapping. The
reviewed cluster registration owns the root Application. This feature neither
provisions EKS nor changes Terraform.

Business-service activation remains empty. In particular, this feature does
not activate auth-api, todos-api, users-api, frontend, or
log-message-processor in any managed namespace. Changes to the inactive
todos-api and log-message-processor overlays only make their future Redis
endpoint namespace-local.

## Desired state

Every managed environment's final steady state renders the following common
resources from `environments/base`:

- one bounded Container LimitRange;
- ingress-and-egress default deny, added only in the Stage-2 revision;
- DNS allowance limited to kube-system CoreDNS on TCP/UDP 53;
- same-namespace ingress and egress;
- Redis ingress limited to same-namespace pods on TCP 6379;
- a custom workload-maintainer Role that excludes Secrets and every isolation
  control; and
- one ephemeral, single-replica Redis Deployment and ClusterIP Service using a
  digest-pinned image.

The overlays add the Namespace, ResourceQuota, and one environment-specific
group binding:

| Environment | Namespace | CPU requests | CPU limits | Memory requests | Memory limits | Pods | Group |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| dev | `microtodo-dev` | 400m | 1200m | 512Mi | 1536Mi | 12 | `microtodosuite:dev-maintainers` |
| staging | `microtodo-staging` | 500m | 1500m | 640Mi | 2Gi | 14 | `microtodosuite:staging-maintainers` |
| prod | `microtodo-prod` | 650m | 2 CPU | 896Mi | 3Gi | 18 | `microtodosuite:prod-maintainers` |

These are policy ceilings, not reserved node capacity. They were derived from
the observed two-node envelope of 3860m allocatable CPU and 14,549,840Ki
allocatable memory, the 1226m/796Mi declared platform requests, three Redis
instances, fixture capacity, rollout headroom, and a disruption reserve. Their
request ceilings total 1550m CPU and 2048Mi memory. Business-service activation
must remeasure and review the budgets rather than treating these policy-only
values as permanent production sizing.

Redis intentionally remains ephemeral. This feature separates Pub/Sub traffic
between environments; it does not add persistence, failover, backups, or a
continuity guarantee.

## Explicit infrastructure registration

`clusters/base/infrastructure.yaml` accepts only a list of reviewed
`{name,path,namespace}` values. It does not scan `infrastructure/*`.

- `clusters/local-kind/activation-infrastructure.yaml` retains the validated
  local five-entry list, including local `infra-redis`.
- `clusters/eks-dev/activation-infrastructure.yaml` is the safe managed
  foundation value: four retained controllers plus the existing shared Redis.
- `clusters/eks-dev/activation-infrastructure-retired.yaml` is the
  post-migration value: the same four controllers and no shared Redis.

The retirement file is not selected by the registration until the replacement
gate passes. This prevents a merge that removes the only live Redis before all
three environment instances are Ready and return `PONG`. The existing
`clusters/eks-dev` registration is the reviewed shared-cluster path for this
rollout; its legacy name is retained to preserve the live ArgoCD root.

## Mandatory activation sequence

### 0. Prerequisites and baseline

Before any environment Application is activated, record all of these with exact
revisions and raw evidence:

1. constitution v1.2.0 is authoritative and byte-synchronized;
2. reuse of the existing `microtodosuite-dev` cluster and `clusters/eks-dev`
   registration as the shared-cluster target is reviewed;
3. the managed registration activates exactly three environment-policy entries,
   zero business-service entries, and the explicit five-entry foundation
   infrastructure list;
4. network policy is enabled in the ops-owned VPC CNI configuration and every
   eligible Linux EC2 node has a Ready policy agent;
5. approved AWS principals map to exactly one of the three maintainer groups;
6. any existing dev workloads have a baseline covering revision, ready
   replicas, restart counts, health, resources, and required connections; and
7. capacity and every required dev egress destination are approved.

The operator decision for the foundation revision defers item 5 because no
environment maintainer access is being granted yet; it remains a blocking RBAC
acceptance item. The live cluster currently has no managed dev business service,
so item 6 is recorded as unavailable rather than inferred. Neither exception
authorizes business-service activation or permits one AWS principal to be mapped
to all three groups.

### 1. Foundation revision

The first reviewed revision activates the Namespace, quota, limit, RBAC, exact
allow rules, and three namespace-local Redis instances without default deny.
Wait for all three environment Applications at the exact revision. Require one
Ready Redis replica and `PONG` in each namespace, zero business Applications,
the five-entry infrastructure inventory, and an unchanged dev baseline.

The repository contains the prepared default-deny manifest, but the foundation
Kustomization does not reference it. The later reviewed Stage-2 revision adds
that single reference. Do not collapse the foundation and deny changes into one
revision.

### 2. Default-deny revision

A second reviewed revision adds the common default-deny policy. Wait for exact
ArgoCD convergence, then prove fresh cross-environment connections fail while
DNS and same-environment connections work. Repeat the dev continuity comparison.
Any missing allow rule or workload regression fails this stage.

### 3. Shared Redis retirement

After the three replacement Redis instances remain Ready and return `PONG`, a
separate reviewed registration change selects the retired four-entry
infrastructure value. Wait for ArgoCD pruning to remove `infra-redis` and the
`redis` namespace, while retaining all four controller Applications and all
three environment Redis instances.

### 4. Correlated fixtures

Activate only the overlays under `tests/fixtures/namespace-isolation` in one
minimal reviewed Git change. They contain Deployment-owned clients and servers,
one subscriber per namespace, and one dev Deployment whose 600m CPU limit
deliberately exceeds the 500m Container maximum. They do not activate a
business service.

Acceptance requires six unique denied directed TCP pairs, six unique denied
directed Redis pairs, three DNS successes, three same-environment TCP successes,
three local Redis successes, three source-only Pub/Sub observations, the
expected LimitRange event and absent violation pod, the full authorization
matrix, and an unchanged comparison environment.

### 5. Cleanup and final observation

Remove only the fixture-activation revision with a reviewed Git revert. Wait
for the three environment Applications to reach the cleanup SHA and prove no
feature-005 fixture remains. Observe continuity for ten more minutes before
marking final acceptance.

## Read-only observer

The observer always requires an explicit kube context and full Git SHA:

```bash
scripts/managed/verify-namespace-isolation.sh \
  --context <reviewed-eks-context> \
  --expected-cluster-id <reviewed-kubeconfig-cluster-id> \
  --phase baseline \
  --expected-revision <40-hex-sha>
```

Each later phase requires the immediately preceding passing summary, which
carries the original baseline and cumulative continuity samples:

```bash
scripts/managed/verify-namespace-isolation.sh \
  --context <reviewed-eks-context> \
  --expected-cluster-id <reviewed-kubeconfig-cluster-id> \
  --phase fixtures \
  --expected-revision <40-hex-sha> \
  --previous-evidence .local/evidence/namespace-isolation/<redis-retired-run>/summary.json
```

Raw Kubernetes/ArgoCD objects, events, logs, authorization responses, command
audit, and `summary.json` are retained in a timestamped ignored directory under
`.local/evidence/namespace-isolation/`. Failed evidence is never deleted or
rewritten as a pass.

The observer may query API objects, logs, events, metrics, authorization, and
Redis `PING`. It has no sync, rollout, or managed-resource mutation path. Desired
state changes and recovery occur only through reviewed Git history reconciled
by ArgoCD.

## Failure and rollback

Stop at the first failed gate. Preserve the failed observation directory and
link it from the acceptance checklist. Recovery is a reviewed `git revert` of
the failing desired-state revision. Wait for ArgoCD to reconcile the revert SHA
and re-run the preceding passing phase before proposing another change.

Do not broaden a NetworkPolicy or Role merely to make a test green. First
identify the exact omitted dependency or identity contract, review the narrow
change, and repeat the staged evidence sequence.

## Accepted limitations

Namespace isolation does not create dedicated nodes, VPCs, control planes, IAM
accounts, storage, or cryptographic pod identity. ResourceQuota bounds admitted
namespace demand but cannot eliminate every node-level noisy-neighbor effect.
NetworkPolicy controls pod traffic but does not encrypt it. Redis remains a
single ephemeral replica per environment. These are explicit tradeoffs of the
constitution v1.2.0 cost-optimized profile.

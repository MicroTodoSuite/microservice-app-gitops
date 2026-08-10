# Research: Shared-Cluster Namespace Isolation

## Decision 1: Treat NetworkPolicy enforcement as an external activation gate

**Decision**: Render and statically validate standard Kubernetes
`NetworkPolicy` resources in this repository, but block default-deny activation
until live evidence proves that every eligible shared-cluster worker runs the
policy agent with enforcement enabled. The verification fixtures use
Deployment-owned pods and new TCP connections.

**Rationale**:

- Kubernetes accepts `NetworkPolicy` objects even when the cluster networking
  plugin does not enforce them. A successful render, sync, or API read therefore
  does not prove isolation.
- The sibling AWS foundation pins VPC CNI `v1.23.0-eksbuild.1`, which is newer
  than AWS's current minimum for native standard network policy support.
- The same Terraform resource does not set `configuration_values` or otherwise
  expose `enableNetworkPolicy: "true"`. AWS documents that new EKS clusters do
  not enable this feature by default, so the current repository evidence is
  insufficient for live acceptance.
- AWS documents that VPC CNI standard policy enforcement applies to Linux EC2
  nodes and to pods owned by a Deployment. The planned probes therefore do not
  rely on standalone pods or Fargate behavior.
- Existing connections can give misleading results during policy rollout. Each
  network assertion opens a new TCP session after convergence.

**Alternatives rejected**:

- Accepting manifests or ArgoCD Healthy status as network proof: neither tests
  packet enforcement.
- Enabling VPC CNI through a direct AWS CLI, Helm, or `kubectl edit` command:
  that would create infrastructure or add-on drift outside GitOps/Terraform
  ownership.
- Installing a second policy engine from this feature: add-on installation is
  explicitly out of scope and running two engines against the same policies can
  leave conflicting rules.

**Repository evidence**:

- `microservice-app-ops/aws/modules/environment-foundation/eks.tf` declares the
  managed VPC CNI add-on without policy configuration.
- `microservice-app-ops/aws/modules/environment-foundation/variables.tf` pins
  `v1.23.0-eksbuild.1`.
- `environments/local/networkpolicy-default-deny.yaml` already warns that the
  local kind CNI does not enforce its policy intent.

**Primary sources**:

- [Amazon EKS: limit pod traffic with network policies](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html)
- [Amazon EKS: configure VPC CNI network policy](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## Decision 2: Reuse one managed isolation base and three value-owning overlays

**Decision**: Add a reusable `environments/base` Kustomize root for common
LimitRange, default-deny, DNS, same-namespace network, and workload-maintainer
Role behavior. `environments/dev`, `environments/staging`, and
`environments/prod` each own their Namespace, ResourceQuota, RoleBinding, and
any exact environment-specific allow policy. The current `environments/local`
root remains independent and unchanged.

**Rationale**:

- `clusters/base/environments.yaml` already discovers only explicitly activated
  `environments/<env>` paths, so a non-activated `base` directory does not create
  a fourth managed environment.
- Common policy in one root prevents three copies from drifting while preserving
  environment-owned values where capacity and identity legitimately differ.
- The local pilot has different capacity and CNI behavior. Retrofitting it onto
  the managed base would expand scope and could invalidate already proven local
  contracts.

**Alternatives rejected**:

- Copying the seven local files three times: this would reproduce exactly the
  structural drift the current environment ApplicationSet was designed to
  avoid.
- Converting `environments/local` into the common base: local's explicitly
  non-enforcing network posture and small quota are not managed-cluster values.
- Generating namespaces in Terraform: namespace policy is in-cluster desired
  state and belongs to ArgoCD under the constitution.

## Decision 3: Stage allow rules before default deny using separate Git changes

**Decision**: Use a minimum three-stage live sequence:

1. capture dev health, dependency, resource, and CNI evidence;
2. reconcile namespaces, budgets, RBAC, DNS/same-namespace policy, and every
   evidenced dev allow rule, then re-check dev;
3. reconcile default-deny ingress and egress, then run isolation and continuity
   checks.

Verification fixtures are activated by a later reviewed commit and removed by
`git revert`. Every stage must converge before the next begins.

**Rationale**:

- A default-deny egress policy also denies DNS unless an explicit DNS rule is
  present.
- Applying allow and deny resources in one unsafely ordered sync can create a
  brief outage even if the final render is correct. Separate reviewed revisions
  make the intermediate state visible and reversible.
- ArgoCD already uses automated prune/self-heal and exact revision evidence; the
  repository's operating model is commit-based rollback, not object repair.

**Alternatives rejected**:

- One large activation commit: it cannot demonstrate that required allow rules
  were healthy before deny took effect.
- Syncing manually from the ArgoCD UI or patching resources: this makes the
  environment diverge from the reviewable Git sequence.
- A temporary allow-all rule during rollout: it creates an unmeasured window in
  which cross-environment access remains possible.

## Decision 4: Derive quota values from live capacity and workload evidence

**Decision**: The implementation records cluster allocatable capacity, system
and platform use, current dev requests/limits/use, rollout surge, evidence
workload capacity, and a disruption reserve before approving numeric quota
values. Each environment then receives aggregate CPU and memory requests and
limits plus a pod-count ceiling. A common LimitRange supplies bounded container
defaults and maxima.

**Rationale**:

- Kubernetes ResourceQuota limits aggregate namespace consumption but does not
  reserve node capacity. If the sum of quotas exceeds real capacity, namespaces
  can still contend on a first-come basis.
- Quota changes do not evict already-created pods, but an undersized quota can
  prevent replacement or rollout pods from being created. A continuity check
  must include rollout headroom, not just current usage.
- CPU/memory quota can reject new pods that omit requests or limits. LimitRange
  defaults prevent accidental omission while its maxima bound one container.
- A Deployment that exceeds quota may be created while its ReplicaSet reports
  failed pod creation. The resource-violation verifier must inspect events and
  realized pods rather than expecting only an API rejection.

**Alternatives rejected**:

- Reusing the local `1/2 CPU`, `1/2 GiB`, ten-pod values: those are pilot values
  with no relationship to the managed cluster or production priority.
- Dividing node capacity equally by three: dev, staging, prod, controllers, and
  rollout reserve have different needs, and quota is not a reservation.
- Treating quotas as full noisy-neighbor protection: CPU throttling, scheduling,
  priority, and node pools need separate controls outside this feature.

**Primary sources**:

- [Kubernetes ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Kubernetes LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)

## Decision 5: Bind stable groups to a custom namespace workload role

**Decision**: Use the stable groups
`microtodosuite:dev-maintainers`,
`microtodosuite:staging-maintainers`, and
`microtodosuite:prod-maintainers`. Each environment RoleBinding references one
group and one custom namespace Role. The Role grants only the approved workload
resource verbs and excludes Namespace, ResourceQuota, LimitRange,
NetworkPolicy, Role, RoleBinding, Secret, and any cluster-scoped resource.

The successful RBAC matrix is evidence of containment, not permission to bypass
GitOps. Human environment changes still travel through Git review and ArgoCD.
AWS identity-to-group mapping remains part of the external cluster-access
handoff.

**Rationale**:

- A RoleBinding grants within one namespace; a ClusterRoleBinding would broaden
  the same permissions cluster-wide.
- Stable group subjects keep personal IAM ARNs and account-specific identities
  out of reusable manifests.
- Excluding the isolation resources prevents an environment maintainer from
  lifting its own quota, deleting default deny, or granting broader access.
- The vendored ArgoCD application controller currently has a wildcard
  ClusterRoleBinding. It is an explicitly authorized platform principal; this
  feature does not claim that namespace RoleBindings sandbox the controller.
  Git review, AppProject destinations, and the controller's platform ownership
  remain separate controls.

**Alternatives rejected**:

- Binding individual users or IAM ARNs: identity values are cluster-specific and
  create repeated edits during team changes.
- Binding the built-in `admin` role: its evolving permission set is broader than
  the exact environment workload contract.
- Binding `system:authenticated` or a cluster-wide maintainer group: either
  breaks environment isolation.
- Refactoring ArgoCD's upstream wildcard controller role here: controller
  hardening spans every add-on and application and requires a separate feature
  with its own conformance evidence.

**Primary source**:

- [Kubernetes RBAC authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

## Decision 6: Make verification fixtures declarative and observers read-only

**Decision**: Store opt-in, digest-pinned test Deployments and Services under
`tests/fixtures/namespace-isolation`. They are not referenced by normal
environment overlays. A reviewed evidence commit activates them; a Git revert
removes them. The managed verifier only reads Applications, namespaces, nodes,
DaemonSets, resources, events, logs, authorization checks, and health endpoints
and writes untracked evidence under `.local/evidence/namespace-isolation/`.

**Rationale**:

- `kubectl run`, `apply`, `create`, and `delete` would violate the GitOps-only
  path even for short-lived probes.
- Deployment-owned probes match the VPC CNI enforcement constraint and can run
  their checks autonomously, leaving results in logs for read-only collection.
- Opt-in fixtures prevent permanent test pods from consuming environment quota.
- A machine-readable summary plus raw observations can tie every result to the
  exact desired-state and cleanup revisions.

**Alternatives rejected**:

- `kubectl exec` into application containers: it changes runtime process state,
  depends on application tooling, and is less reproducible than declarative
  probes.
- Permanent verification workloads: they consume scarce shared capacity and
  enlarge the production attack surface.
- A script that edits Kustomizations or commits automatically: humans must review
  the exact activation and cleanup changes; the verifier remains observational.

## Decision 7: Keep cluster registration and CNI configuration outside this feature

**Decision**: This feature can merge static policy and verification contracts,
but live activation waits for separately reviewed prerequisites:

1. constitution v1.2.0 is merged in `microservice-app-docs`;
2. the AWS foundation is reconciled from its current dedicated-dev/full-profile
   contract to the shared-cluster profile, including verified CNI enforcement;
3. `clusters/eks-main` consumes reusable registration wiring, activates only the
   `dev`, `staging`, and `prod` environment-policy list against the in-cluster
   API, and keeps business-service and infrastructure/add-on activation empty;
   and
4. approved AWS principals map to the stable Kubernetes groups.

**Rationale**:

- Current GitOps `main` contains only `clusters/local-kind`, although
  `clusters/README.md` names `eks-main` as the later economical registration.
- `clusters/README.md` currently requires matching app/environment activation
  lists, while `clusters/base/infrastructure.yaml` automatically discovers every
  `infrastructure/*` root. Consuming that base unchanged would deploy services
  and all current add-ons merely by registering the cluster, which violates this
  feature's policy-only scope and the requested dev-first follow-on sequence.
- The sibling ops branch currently publishes a dev-only handoff for
  `microtodosuite-dev` and `clusters/eks-dev`; that contract predates the adopted
  shared profile.
- Changing Terraform, EKS access entries, or the cluster registration would mix
  infrastructure and namespace-isolation ownership and violate the requested
  scope.

**Alternatives rejected**:

- Silently treating the current dev foundation as the shared production
  cluster. Reuse may be economical, but renaming, capacity, identity, API
  exposure, CNI, and production suitability require an explicit review outside
  this feature.
- Reusing matching application/environment activation or automatic
  infrastructure discovery for `eks-main`. Namespace policy must be activatable
  without installing add-ons or real services; the registration feature must
  provide that separation before this feature goes live.

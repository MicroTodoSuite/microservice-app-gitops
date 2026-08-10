# Planned Execution Guide: Shared-Cluster Namespace Isolation

This guide describes the implementation workflow defined by feature 005. The
observer and manifests named below are planned artifacts and are not available
until their tasks are implemented. Do not use this document to mutate a cluster
before the prerequisite checklist is complete.

## 1. Confirm authoritative prerequisites

Before any managed namespace activation, confirm all of the following:

- `microservice-app-docs/main` contains constitution v1.2.0 and its approved
  cost-optimized profile adoption;
- the GitOps vendored constitution is byte-identical;
- a separate reviewed registration provides `clusters/eks-main`, activates only
  the dev, staging, and prod environment-policy list against
  `https://kubernetes.default.svc`, and yields zero business-service and zero
  infrastructure/add-on Applications;
- the ops-owned EKS/VPC CNI configuration has network policy enabled
  declaratively;
- every eligible Linux EC2 worker has a ready policy agent;
- approved AWS principals map to the exact environment groups;
- existing dev workloads are healthy; and
- the checkout is clean and on a short-lived implementation branch.

If any item is missing, static design work may continue, but stop before live
activation.

## 2. Run static checks after implementation

Render each managed environment without contacting a cluster:

```bash
kubectl kustomize environments/dev
kubectl kustomize environments/staging
kubectl kustomize environments/prod
```

Run the feature contract and existing local contracts:

```bash
tests/contract/namespace-isolation.sh
tests/contract/platform-addons.sh
tests/contract/service-onboarding.sh
```

Validate the planning contract and repository whitespace:

```bash
jq empty specs/005-namespace-isolation/contracts/namespace-isolation-evidence.schema.json
git diff --check
```

Implementation must also run the selected pinned Kubernetes schema validator.
`kubeconform` is not installed in the current shell, so a successful local render
alone is not the schema-validation gate.

## 3. Record the baseline

After the prerequisites are live, record the exact desired-state SHA:

```bash
git rev-parse HEAD
```

Run the planned observer with the exact managed-cluster context and full SHA:

```bash
scripts/managed/verify-namespace-isolation.sh \
  --context <eks-main-context> \
  --phase baseline \
  --expected-revision <40-hex-git-sha>
```

Review the resulting directory under
`.local/evidence/namespace-isolation/`. Do not continue unless the CNI,
identity, dev health, dev dependency, and capacity baseline gates all pass.

## 4. Reconcile the foundation revision

The first implementation PR contains Namespace, ResourceQuota, LimitRange,
Role/RoleBinding, DNS, same-environment, and evidenced dev allow rules. It does
not activate default deny.

After review and merge, wait for ArgoCD to observe that exact SHA; the observer
does not request a sync:

```bash
scripts/managed/verify-namespace-isolation.sh \
  --context <eks-main-context> \
  --phase foundation \
  --expected-revision <foundation-commit-sha> \
  --baseline <baseline-summary-json>
```

Stop and revert the Git change if any environment application fails to converge
or dev differs from baseline.

## 5. Reconcile default deny

A second reviewed PR adds the common default-deny policy to all three managed
renders. After merge and convergence, run:

```bash
scripts/managed/verify-namespace-isolation.sh \
  --context <eks-main-context> \
  --phase default-deny \
  --expected-revision <default-deny-commit-sha> \
  --baseline <baseline-summary-json>
```

The phase must prove real positive and negative new connections and unchanged
dev health. A present `NetworkPolicy` object is not sufficient.

## 6. Activate and observe verification fixtures

A third reviewed PR references the opt-in fixture overlays and the deliberate
quota violation. All fixtures are Deployments with an implementation-approved
immutable image. After ArgoCD reaches the fixture revision, run:

```bash
scripts/managed/verify-namespace-isolation.sh \
  --context <eks-main-context> \
  --phase fixtures \
  --expected-revision <fixture-activation-commit-sha> \
  --baseline <baseline-summary-json>
```

Required outcomes are six denied cross-environment paths, three allowed local
paths, three successful DNS checks, the expected quota event with no excess pod,
an unaffected comparison environment, and the complete RBAC matrix.

## 7. Revert fixtures and finalize

Remove only the fixture activation through a reviewed Git revert:

```bash
git revert <fixture-activation-commit-sha>
```

After that revert is reviewed, merged, and reconciled, run the final phase:

```bash
scripts/managed/verify-namespace-isolation.sh \
  --context <eks-main-context> \
  --phase final \
  --expected-revision <isolation-revision-sha> \
  --cleanup-revision <fixture-revert-commit-sha> \
  --baseline <baseline-summary-json>
```

Final success requires no fixture workload, all environment applications at the
cleanup revision, ten minutes of stable dev continuity, a zero-mutation command
audit, and schema-valid evidence.

## Prohibited shortcuts

Do not use any of the following to implement, test, repair, or clean up this
feature:

- `kubectl apply`, `create`, `patch`, `replace`, `scale`, `rollout`, `delete`, or
  `edit` against managed resources;
- ArgoCD UI/CLI sync or live parameter overrides;
- AWS CLI or console changes to VPC CNI, EKS access, nodes, or IAM;
- mutable image tags for probes; or
- broad allow-all policy while troubleshooting.

Read-only API queries, logs, events, authorization reviews, port-forwards, and
application health requests are allowed when the observer records them.

## Stop Conditions

| Observation | Required response |
| --- | --- |
| Constitution v1.2.0 is not merged | Stop before implementation; do not treat the vendored draft as authority. |
| `eks-main` registration or identity mapping is missing | Stop live work and complete the separately owned handoff. |
| Registration would mirror environment activation into apps or auto-discover infrastructure | Stop before root activation; the registration feature must decouple those inventories first. |
| VPC CNI agent/configuration is absent on any eligible node | Stop before default deny; fix through the ops-owned declarative path. |
| Dev dependency inventory is incomplete | Do not guess an allow rule; gather owner evidence first. |
| Proposed quota lacks rollout/system reserve | Reject the values and repeat capacity review. |
| Dev loses readiness, restarts, or health | Mark failure and revert the responsible Git stage. |
| One cross-environment path succeeds | Mark network isolation failed; retain evidence and revert. |
| Authorization differs from the expected matrix | Mark RBAC failed; do not broaden a binding to make the test pass. |
| Fixture cleanup does not converge | Acceptance remains blocked; do not delete objects directly. |

## Expected steady state

After successful cleanup, the shared cluster contains the three managed
namespaces and their steady-state isolation controls. It contains no feature-005
probe or quota-violation workload. Existing dev workloads remain healthy;
staging and prod contain no real service or add-on merely because their
namespace policy exists.

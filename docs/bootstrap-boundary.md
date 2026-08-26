# Bootstrap Boundary

Constitution principle 2 forbids direct `kubectl apply` to managed application
state. Establishing the reconciler itself is the one unavoidable exception, and
this document defines its exact, minimal boundary (spec 001, FR-007).

## What the bootstrap MAY do (allowlist)

`scripts/pilot/bootstrap.sh` — and nothing else — may:

1. Create the disposable local platform: the loopback registry, the machine-local
   Git HTTP source, and the kind cluster.
2. Install the **vendored** ArgoCD controller and wait for it to be ready.
3. Create the **root** Application that points ArgoCD at the local Git source.

Each of these is logged. After step 3, ArgoCD owns all state.

`scripts/pilot/bootstrap.sh --root-only` may idempotently re-offer that same
tracked root Application after an ordinary Git commit has already aligned the
machine connection values. This remains inside item 3: it changes no child
Application or workload and is not a deployment recovery path.

For a managed EKS cluster that does not yet contain ArgoCD, the same boundary
permits exactly two direct mutations, and only after the cluster registration
and root source revision are merged to the protected `main` branch:

1. server-side apply the checksum-pinned render from `bootstrap/argocd`; and
2. apply that cluster's tracked `clusters/<cluster>/root-app.yaml` object.

The first mutation creates the reconciler. The second gives that reconciler its
reviewed Git root. Readiness waits and observations between or after those two
actions are read-only. No child Application, platform add-on, environment
resource, or business workload may be applied directly.

### The enforced form: `scripts/managed/bootstrap-cluster.sh`

For the managed clusters this boundary is no longer a convention that a careful
operator follows; it is a script that refuses. The helper runs every check
before the first mutation, so a refusal leaves the cluster untouched rather than
half-bootstrapped:

| Check | The mistake it catches |
| --- | --- |
| `aws sts get-caller-identity` equals `--expected-account` | The two applies land on a real cluster, in the wrong account, and nothing reports an error. |
| `kubectl config current-context` contains `--cluster` | Same failure, one account over: the right manifests on the wrong cluster. |
| `--revision` is an ancestor of the protected ref | ArgoCD is handed a Git root nobody reviewed, and then reconciles that unreviewed state indefinitely. |
| Rendered `bootstrap/argocd` matches `bootstrap/argocd/render.sha256` | The install being applied is not the reviewed one. |
| `mutate()` refuses past `MUTATION_LIMIT=2` | The boundary quietly becomes three applies, then four. |

The mutation cap lives inside the single function permitted to change cluster
state, not in argument parsing, so it holds regardless of how a mutation is
reached. Passing `--extra-apply` is refused outright before any check runs.

Every run writes a transcript of `READ` and `MUTATION` lines. A successful
bootstrap of an empty cluster records exactly two `MUTATION` lines; a cluster
that already has ArgoCD records zero, because re-running is a read-only
verification and not a recovery path.

`tests/bootstrap/managed-cluster-bootstrap.bats` exercises all of it against
fixtures. Each guard has been verified by mutation: removing the checksum
comparison, the merged-revision check, or the mutation cap each fails the test
written for it.

## What the bootstrap MUST NOT do

- Create, patch, scale, or configure any `auth-api` (or other business) workload.
  Business services are activated only by a commit to the local Git source
  (`scripts/pilot/publish-auth.sh`), never by the bootstrap.
- Apply platform add-ons (ESO, etc.) directly — ArgoCD deploys those from Git.
- Use any hosted source for ongoing reconciliation.

## Why the two applies are acceptable

They create only the reconciliation capability and its repository connection,
not desired application state. The moment desired state exists (a commit), it
is reconciled — never hand-applied. This reasoning applies equally to the local
pilot and the managed-cluster two-mutation bootstrap above. Cluster destruction
(`cleanup.sh`) is environment teardown, not a deployment or rollback path.

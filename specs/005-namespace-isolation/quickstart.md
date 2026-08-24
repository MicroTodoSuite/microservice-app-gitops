# Quickstart: Publish the Shared-Cluster Environments Safely

This runbook is an execution order, not permission to skip review. Kubernetes
managed state changes only after commits merge and Argo CD reconciles them. AWS
resources change only through the reviewed Terraform state owner.

## 1. Confirm clean repositories and exact baselines

```bash
git -C ../microservice-app-ops status --short --branch
git -C ../microservice-app-gitops status --short --branch
git -C ../microservice-app-auth-api status --short --branch
git -C ../microservice-app-todos-api status --short --branch
git -C ../microservice-app-users-api status --short --branch
git -C ../microservice-app-frontend status --short --branch
git -C ../microservice-app-log-message-processor status --short --branch
```

Do not discard an existing worktree change. The five release descendants must
trace to the baselines recorded in `spec.md`.

## 2. Capture the live read-only baseline

```bash
CONTEXT='arn:aws:eks:us-east-1:916491575487:cluster/microtodosuite-dev'
CLUSTER_ID="$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${CONTEXT}')].context.cluster}")"
REVISION="$(git rev-parse origin/main)"

scripts/managed/verify-namespace-isolation.sh \
  --context "$CONTEXT" \
  --expected-cluster-id "$CLUSTER_ID" \
  --phase baseline \
  --expected-revision "$REVISION"
```

The baseline must show three environment Applications, zero business
Applications, active network-policy enforcement, and every open prerequisite.

## 3. Merge AWS source ownership before extending it

The live foundation currently belongs to the unmerged
`esteban/eks-dev-foundation` branch in `microservice-app-ops`. Review and merge
that branch first. Then create the feature's short-lived infrastructure branch
from the new `origin/main`.

Do not implement the new resources directly from the older ops `main`; that
would omit the state owner that already created the cluster.

## 4. Validate the intended Terraform execution path

```bash
cd ../microservice-app-ops
export AWS_PROFILE=microtodosuite-terraform

./scripts/aws-dev-foundation.sh check
./scripts/aws-dev-foundation.sh init
./scripts/aws-dev-foundation.sh validate
./scripts/aws-dev-foundation.sh test
./scripts/aws-dev-foundation.sh plan
```

The plan must be reviewed and additive. Any unexpected update, replacement, or
deletion stops the run. The current role is known to fail before the planned
least-privilege bootstrap-policy repair; do not fall back to the broad developer
user to bypass that gate.

Applying a saved plan is a separate reviewed operator boundary. Record the exact
plan artifact and caller identity; never create ECR, IAM, or Secrets Manager
resources with ad hoc AWS CLI commands.

## 5. Repair and pin the shared CI workflow

The organization workflow must implement this closed sequence:

```text
test -> build once -> Trivy -> SBOM -> assume AWS OIDC -> push -> resolve digest -> sign
```

PRs stop before AWS publication. Only reviewed `main` commits publish. Each
service caller pins the final workflow commit SHA, never mutable `@v1`.

## 6. Produce five reviewed release artifacts

Use one short-lived PR per service. Do not combine service behavior changes with
the security/build fixes. A release manifest is complete only when it records,
for all five services:

- baseline and reviewed green commit;
- successful workflow URL and immutable workflow revision;
- applicable tests and Trivy result;
- SBOM artifact;
- neutral ECR repository and manifest digest; and
- successful keyless signature verification.

No GitOps image value changes while any row is incomplete.

## 7. Reconcile GitOps prerequisites with activation still empty

The prerequisite GitOps revision contains:

- the Argo CD progressive-sync flag and controller rollout annotation;
- vendored Argo Rollouts 1.9.1;
- ESO ServiceAccounts, SecretStores, and ExternalSecrets;
- Kyverno private-ECR signature verification;
- economical topology selections;
- evidence-derived quotas;
- five production Rollout components; and
- replacement of shared Redis in the infrastructure allowlist by Argo Rollouts.

`clusters/eks-dev/activation-apps.yaml` remains empty in this revision.

After Argo CD reconciles it, verify read-only:

```bash
kubectl --context "$CONTEXT" get applications -n argocd
kubectl --context "$CONTEXT" get applicationsets -n argocd
kubectl --context "$CONTEXT" get externalsecrets,secretstores -A
kubectl --context "$CONTEXT" get rollout,analysisrun -A
kubectl --context "$CONTEXT" get resourcequota -A
kubectl --context "$CONTEXT" get pods -A
```

Secret verification must not print secret values. Shared `infra-redis` and
namespace `redis` may disappear only after the three environment-local Redis
instances remain Ready and return PONG.

## 8. Activate all fifteen Applications in one reviewed revision

The activation diff does exactly two release operations:

1. replace every managed overlay placeholder with its neutral ECR URI and exact
   service digest, identical in dev/staging/prod; and
2. set the business activation list to dev, staging, and prod together.

Argo CD then controls the order. Do not invoke `argocd app sync` or mutate an
Application. Observe dev become Healthy one Application at a time, then staging,
then production.

```bash
kubectl --context "$CONTEXT" get applications -n argocd -o json \
  | jq '[.items[] | {name:.metadata.name,environment:.metadata.labels["microtodosuite.io/environment"],sync:.status.sync.status,health:.status.health.status,revision:.status.sync.revision}] | sort_by(.name)'
```

Any degraded Application, wrong digest, out-of-order operation, readiness loss,
or new attributable restart stops the run and is recovered by reviewed Git
revert.

## 9. Prove the production canaries honestly

Initial Rollout creation is stable bootstrap, not canary evidence. Merge a
reviewed same-digest revision that changes only the production evidence
annotation, then observe five successful AnalysisRuns.

Next merge the reviewed negative metric fixture, observe failed AnalysisRun,
aborted Rollout, and stable restoration, then recover by Git revert. Never use
`kubectl argo rollouts promote`, `abort`, or `restart` for acceptance.

## 10. Run isolation fixtures and cleanup

Activate network/resource/Redis fixtures by reviewed Git commit. The observer
must prove all directed denials, positive controls, Pub/Sub separation, quota
containment, and comparison-environment continuity. Remove fixtures with Git
revert and wait for cleanup convergence.

```bash
scripts/managed/verify-namespace-isolation.sh \
  --context "$CONTEXT" \
  --expected-cluster-id "$CLUSTER_ID" \
  --phase final \
  --expected-revision <fixture-revision> \
  --cleanup-revision <cleanup-revision> \
  --previous-evidence <fixtures-summary.json> \
  --release-evidence <release-manifest.json>
```

## 11. Update acceptance evidence

For each verified checklist item, cite the exact evidence directory/file,
revision, workflow run, AWS plan/apply record, or live object observation. Leave
deferred AWS maintainer-principal mappings unchecked. A manifest, render, or
intent statement is never substituted for a requested live outcome.

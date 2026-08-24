# Creating a new environment

An environment in the economical profile is a **namespace** on the shared EKS
cluster, described entirely by Git. Creating one is declarative and repeatable:
a thin overlay over the shared base plus the same immutable image digest, so a
new environment is a bit-for-bit replica that passes the same checks as dev.

The environment name is the only parameter. Three layers cooperate; each is
list/parameter driven and each keeps a human review/apply/merge gate — nothing
provisions cloud infrastructure or mutates a cluster unattended.

```
scripts/new-environment.sh <env>        →  GitOps: manifests + activation   (this repo)
shared_environments += <env>            →  AWS:    JWT secret + IRSA role    (microservice-app-ops, terraform apply)
scripts/add-promotion-jobs.sh <env>     →  CI:     promote-<env> jobs        (service repos, permanent envs only)
```

## 1. GitOps layer (this repo)

```bash
scripts/new-environment.sh <env>            # e.g. qa, demo, preview-42
scripts/new-environment.sh <env> --from dev # template env (default: dev)
scripts/new-environment.sh <env> --dry-run  # preview without writing
scripts/new-environment.sh <env> --delete   # remove; ArgoCD prunes on merge
```

It generates, from the template environment:

- `environments/<env>/` — namespace, ResourceQuota, LimitRange, NetworkPolicies,
  RBAC, and the ExternalSecret wiring (retargeted to `microtodosuite/<env>/...`
  and role `microtodosuite-<env>-jwt-reader`).
- `apps/<service>/overlays/<env>/` for every service — only the namespace
  changes; the **immutable digest is copied unchanged** from the template.
- Activation entries in `clusters/eks-dev/activation-apps.yaml` and
  `activation-environments.yaml`, and a matching `RollingSync` wave in
  `rolling-sync-apps.yaml`.

Then validate and open a PR:

```bash
kubectl kustomize clusters/eks-dev >/dev/null
kubectl kustomize environments/<env> >/dev/null
git checkout -b env/<env> && git add -A && git commit -m "feat(env): add <env> environment"
```

With auto-sync active, merging the PR makes ArgoCD create the namespace and the
five services on the same digest.

## 2. AWS layer (microservice-app-ops) — the one non-GitOps dependency

Each environment reads its `JWT_SECRET` from AWS Secrets Manager through an IRSA
role scoped to `system:serviceaccount:microtodo-<env>:external-secrets-jwt`. The
Terraform is already list-driven: add the name to `shared_environments` in
`aws/environments/dev/foundation/dev.tfvars` and apply.

```hcl
shared_environments = ["dev", "staging", "prod", "<env>"]
```

```bash
cd aws/environments/dev/foundation
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars   # creates the secret + jwt-reader role for <env>
```

`terraform apply` stays a human step by design — provisioning IAM roles and
secrets is never unattended.

### Self-contained demo without Terraform

For a throwaway demo where you cannot run Terraform, replace the ExternalSecret
with a literal Secret in `environments/<env>` (mark it demo-only). The app pods
run regardless; only the end-to-end `/login` needs a `JWT_SECRET` matching the
other services.

## 3. CI layer (service repos) — permanent environments only

An **ephemeral** environment (demo, preview) needs nothing here: it is created
ad-hoc from dev's current digest. A **permanent** environment that must sit in
the promotion chain also needs a `promote-<env>` job in each service caller:

```bash
scripts/add-promotion-jobs.sh <env> --after staging   # injects promote-<env> before gate-prod
```

This edits `../microservice-app-*/.github/workflows/ci.yml`, opening one PR per
service.

## Orchestrator

`scripts/add-environment.sh <env>` runs all three layers and opens the PRs in
each repo. It still stops at review/apply/merge — the automation removes the
copy-paste toil, not the human decisions.

## Teardown

```bash
scripts/new-environment.sh <env> --delete      # GitOps prune on merge
# shared_environments -= <env>  then terraform apply   # AWS
```

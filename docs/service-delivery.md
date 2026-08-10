# Service Delivery (all business services)

How every MicroTodoSuite business service is delivered through GitOps, and the
shared dependencies that are deliberately kept out of `apps/<service>`.

## Onboarded services

All service slots share one shape (`apps/<service>/{base,components,topology,overlays}`),
proven by `auth-api`. The **authoritative per-service values** (ports, health
paths, config keys, secrets, dependencies) live in
[docs/service-onboarding.md](./service-onboarding.md); this document only covers
how those services are *delivered*. `log-message-processor` is a worker with no
business HTTP API but exposes a Prometheus metrics endpoint, which is its
intrinsic health path — no inbound endpoint is fabricated.

## Delivery flow (CI → ArgoCD)

Build once → push by immutable digest → CI opens a pull request to this repo that
bumps the environment overlay digest (via `scripts/bump-image.sh`) → ArgoCD
reconciles. Promotion to staging/prod copies the identical digest; prod requires
approval; rollback is `git revert`. No CI step mutates a cluster. See
`specs/003-reusable-cicd-delivery/contracts/promotion-flow.md`.

## Shared JWT secret

`auth-api`, `todos-api`, and `users-api` all consume `JWT_SECRET` and must share
the **same value** so a token issued by `auth-api` verifies in the others. Each
service's local overlay currently provisions its own ESO `Password` generator,
which is correct when a service is activated in isolation. **Co-activating all
three locally requires a single shared source** (for example a Kubernetes-provider
`SecretStore` reading one owner Secret, or one shared Secret name consumed by all
three); this is a tracked follow-up. Managed environments map all three to the
same AWS Secrets Manager key through ESO. No JWT value is ever committed.

## Redis (shared dependency, not a business service)

`todos-api` and `log-message-processor` require Redis (Pub/Sub log channel).
Redis is a shared platform dependency, **not** a ninth business service, so it is
deliberately kept out of `apps/<service>` (the onboarding contract forbids
service-owned shared infrastructure). Provisioning Redis for a managed
environment is platform work; activating todos-api or log-message-processor
locally also requires a Redis instance in `microtodo-local`. The service
definitions onboarded here render and conform independently; their local
activation (and thus a running Redis) is optional and deferred.

## Managed overlays and the real dev cluster

`staging` and `prod` overlays are inactive scaffolds (placeholder registry +
all-zero digest) until their foundations exist.

The **`dev`** environment is now wired to real AWS (task-1 dev foundation,
`ops @ esteban/eks-dev-foundation`, account `995253610162`, `us-east-1`):

- **Cluster registration**: [`clusters/eks-dev/`](../clusters/eks-dev) — the real
  EKS cluster, reconciling from this hosted GitHub repo, activating `env=dev`
  (economical growth to staging/prod as namespaces is a value change; see its
  `activation-templates/economical/`). It stays **inactive** until ArgoCD is
  bootstrapped in the cluster and `root-app.yaml` is applied.
- **Registry**: `dev` overlays now point at the real ECR
  `995253610162.dkr.ecr.us-east-1.amazonaws.com/microtodosuite/dev/<service>`
  (IMMUTABLE, scan-on-push). The digest stays all-zero until the CI promotion
  flow writes a real one.

**Still blocking a live dev deploy** (both external to this repo):

1. The task-1 dev foundation must be `terraform apply`-ed (confirm it is live).
2. A GitHub Actions → ECR **OIDC push role** must exist — it is not in the
   foundation yet. See [docs/ci-ecr-oidc-role.md](./ci-ecr-oidc-role.md).

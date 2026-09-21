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

### Production approval (FR-008)

The repo-wide branch protection rule (`required_approving_review_count: 1`)
already requires an approval on every pull request, including one that only
touches `apps/*/profiles/*/overlays/prod/**`. That rule alone lets any collaborator
approve a production change, which is not the same as an *explicit* human
approval for production specifically. `CODEOWNERS` designates
`@Juanmadiaz45`, `@EstebanGZam`, and `@Tiago0507` -- the same three humans
already required to approve production deploys on every service repo's `prod`
GitHub Environment -- as owners of `apps/*/profiles/*/overlays/prod/**`. Branch
protection on `main` must have `require_code_owner_reviews` enabled; that live
setting is not included in this pull request and remains open. Until it is
enabled, a production overlay pull request can still merge after any ordinary
approval. `tests/contract/prod-overlay-approval.sh`
verifies the static half of this (`CODEOWNERS` names a `@`-owner for the
pattern); the live branch-protection setting is GitHub state, not a file, and
is verified operationally (`gh api repos/MicroTodoSuite/microservice-app-gitops/branches/main/protection`).

## Shared JWT secret

`auth-api`, `todos-api`, and `users-api` all consume `JWT_SECRET` and must share
the **same value** so a token issued by `auth-api` verifies in the others
(research D13, `specs/003-reusable-cicd-delivery/research.md`). Locally,
`auth-api`'s `overlays/local` is the **only** one that generates a value: its
ESO `Password` generator plus `ExternalSecret` write it into `auth-api-secrets`
(key `JWT_SECRET`). `todos-api` and `users-api` never provision a generator or
`ExternalSecret` of their own -- their base `Deployment` reads
`auth-api-secrets`/`JWT_SECRET` directly by name, a same-namespace Kubernetes
Secret reference that needs no ExternalSecret on their side. One generated
value, three consumers.

This makes activation order matter locally: `auth-api-secrets` must exist
before `todos-api` or `users-api` can start, which is why
`scripts/pilot/publish-services.sh` always publishes `auth-api` before the
other services. `tests/contract/shared-jwt-local.sh` guards both halves of the
design -- the shared source exists, and neither consumer silently duplicates
it. Managed environments map all three to the same AWS Secrets Manager key
through ESO. No JWT value is ever committed.

## Redis (shared dependency, not a business service)

`todos-api` and `log-message-processor` require Redis (Pub/Sub log channel).
Redis is a shared platform dependency, **not** a ninth business service, so it is
deliberately kept out of `apps/<service>` (the onboarding contract forbids
service-owned shared infrastructure). Provisioning Redis for a managed
environment is platform work; activating todos-api or log-message-processor
locally also requires a Redis instance in `microtodo-local`. The service
definitions onboarded here render and conform independently; their local
activation (and thus a running Redis) is optional and deferred.

## Managed overlays and the shared EKS cluster

The `clusters/eks-dev` registration targets the in-cluster API of the shared
`lex-mts-eco-eks-main` EKS cluster in AWS account `575172595729`, region
`us-east-1`. The legacy GitOps directory is retained across the physical
rebuild, while
the registration activates dev, staging, and prod as isolated namespaces.

All managed overlays use the environment-neutral private repository
`575172595729.dkr.ecr.us-east-1.amazonaws.com/microtodosuite/<service>`. A
service is built once by its reviewed `main` workflow, then the same signed
immutable digest is pinned in dev, staging, and prod. Environment-specific
Secrets Manager readers remain separate IRSA roles even though the artifact is
shared.

ArgoCD is installed once through the audited bootstrap boundary and receives
only the tracked root Application. From that point onward, platform add-ons,
environment policy, and all fifteen business Applications are reconciled from
this repository; CI and operators never apply workloads directly.

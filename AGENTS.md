# AGENTS.md — microservice-app-gitops

## Overview

GitOps source of truth for MicroTodoSuite. ArgoCD reconciles this repo into the
cluster: every deployment is a commit here, every rollback is a `git revert`.
Nothing is applied to a cluster by hand except the audited bootstrap boundary.

## Stack

Kubernetes manifests + Kustomize v5. ArgoCD v3.5.0 and External Secrets Operator
v2.9.0, both vendored and pinned. Argo Rollouts CRDs for the canary Component
(activation only). Pilot scripts are Bash. No application code.

## Commands

```bash
# Render + schema-validate an environment (no cluster needed)
kustomize build apps/auth-api/overlays/local | kubeconform -strict -ignore-missing-schemas -summary

# Fully local pilot (see docs/local-pilot-quickstart.md)
./scripts/pilot/preflight.sh
./scripts/pilot/bootstrap.sh      # local registry + Git source + kind + vendored ArgoCD
./scripts/pilot/publish-auth.sh   # build+push auth-api, commit its immutable digest locally
./scripts/pilot/verify.sh         # prove Synced/Healthy, one service, 3x health
./scripts/pilot/cleanup.sh        # remove only pilot-owned local resources

# Digest-only image update (never a tag)
scripts/bump-image.sh auth-api <env> sha256:<64hex>
```

## Structure

- `bootstrap/argocd/` — vendored pinned ArgoCD; applied once, then self-managed.
- `bootstrap/local/` — kind + loopback registry config for the pilot.
- `clusters/base/` — reusable delivery mechanism (AppProject + ApplicationSets).
- `clusters/<cluster>/` — value-only registration: repo endpoint + activated envs.
- `environments/<env>/` — environment-owned namespace policy (quota/limits/netpol).
- `infrastructure/<addon>/` — ArgoCD-owned add-ons; External Secrets is vendored.
- `apps/<service>/base` — environment-neutral manifests; `components/` — version
  fragments; `topology/` — single per-service economical↔full switch;
  `overlays/<env>/` — environment-owned values (namespace, capacity, digest).
- `scripts/pilot/` — pilot lifecycle; `scripts/bump-image.sh` — digest bump.
- `specs/`, `docs/` — Spec-Driven Development artifacts and pilot documentation.

## Conventions

- All artifacts in English (suite-wide rule).
- GitOps-only: no `kubectl apply`/patch/scale to managed state; corrections are
  commits or `git revert`. The only exception is the audited bootstrap boundary
  (docs/bootstrap-boundary.md).
- No secret value in Git: the Secret contract `auth-api-secrets/JWT_SECRET` is
  filled in-cluster by ESO (docs/secret-rotation.md).
- Images are pinned by immutable digest, never tags (`newName@sha256:...`).
- Version differences live in Components; destination differences live in the
  cluster registration — never in a service base/overlays.
- Trunk-based development, short-lived branches, feature specs under `specs/`.

## Notes for the infrastructure integration

- Managed environments (dev/staging/prod on EKS, aks-dr) are inactive scaffolds;
  they activate when a cluster registration lists them (roadmap task 1 delivers
  the clusters and ECR). `newName` becomes the ECR repo; the ESO store becomes
  AWS Secrets Manager via IRSA.
- Platform add-on folders under `infrastructure/` are owned by ArgoCD; their
  content (Istio, KEDA, cert-manager, Kyverno) is roadmap task 2.

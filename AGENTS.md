# AGENTS.md — microservice-app-gitops

## Overview

GitOps source of truth for MicroTodoSuite. ArgoCD reconciles this repo into the
cluster: every deployment is a commit here, every rollback is a `git revert`.
Nothing is applied to a cluster by hand except the audited bootstrap boundary.

## Stack

Kubernetes manifests + Kustomize v5. ArgoCD v3.5.0 and External Secrets Operator
v2.9.0, both vendored and pinned. Redis 7.4.9 is the local shared dependency.
Argo Rollouts CRDs remain an inactive canary seam. Pilot scripts are Bash. No
application code lives here.

## Commands

```bash
# Render + schema-validate an environment (no cluster needed)
kubectl kustomize apps/auth-api/overlays/local | kubeconform -strict -ignore-missing-schemas -summary

# Fully local pilot (see docs/local-pilot-quickstart.md)
./scripts/pilot/preflight.sh
./scripts/pilot/bootstrap.sh      # local registry + Git source + kind + vendored ArgoCD
./scripts/pilot/publish-services.sh # Redis first, then five digest-pinned services
./scripts/pilot/verify-services.sh  # Argo/pods plus real cross-service behavior
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
- `infrastructure/<capability>/` — ArgoCD-owned controllers and Redis dependency.
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

## Notes for infrastructure integration

- Managed environment overlays remain inactive scaffolds. A reviewed cluster
  registration and immutable destination image values activate them; this local
  workflow requires no hosted credential or registry.
- Direct Kustomize roots under `infrastructure/` are owned by ArgoCD. Redis is
  intentionally ephemeral until a separate continuity design is ratified.

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
<<<<<<< Updated upstream
=======
- Write everything in English — branch names, commit messages, pull-request titles and bodies, review comments, code comments, documentation, and specification text. No bilingual sections. Changing this rule takes a recorded decision in `microservice-app-docs`, not a remark in conversation.
>>>>>>> Stashed changes
- Open every pull request through `.github/pull_request_template.md` and follow `microservice-app-docs/docs/Pull request and task tracking conventions.md`: one concern per short-lived `<type>/<summary>` branch, a Conventional Commit title with a scope, and every template section filled. Constitution principle 13 makes this binding, not advisory.
- Keep the Spec-Driven Development commit pair intact: `test(<scope>): specify ...` must be committed failing before `feat(<scope>): implement ...`. Never squash the pair; the failing-test commit is the evidence the cycle was followed.
- Track every task. Name in the pull-request body the task IDs it advances, qualified by repository and spec, and update `tasks.md` in that same pull request rather than a follow-up. Mark a task `[X]` only after locating and inspecting its named artifact — never from a summary, a green check, a rendered manifest, or recollection. Annotate partial delivery instead of ticking it; work no register covers either gains a task or records in the PR body why none applies.
- Reconcile, never quietly edit, when a register and reality disagree: a specification that pins a version nobody shipped is a maintainer decision, and `microservice-app-docs/full-platform/plan-reconciliation.md` is the worked example.
- Never merge with `--admin`, force-push to `main`, disable a branch protection rule to land your own work, or approve your own pull request. As an AI agent you may open, describe, and update a pull request; you may never approve one and never author an acceptance or approval artifact — only a named human unlocks a gate.
- Report outcomes faithfully in commits and pull-request bodies: name what is red, say what was skipped, and correct an earlier claim that turns out to be wrong rather than leaving the record wrong.

## Notes for infrastructure integration

- Managed environment overlays remain inactive scaffolds. A reviewed cluster
  registration and immutable destination image values activate them; this local
  workflow requires no hosted credential or registry.
- Direct Kustomize roots under `infrastructure/` are owned by ArgoCD. Redis is
  intentionally ephemeral until a separate continuity design is ratified.

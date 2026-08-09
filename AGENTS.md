# AGENTS.md — microservice-app-gitops

## Overview

GitOps source of truth for MicroTodoSuite. ArgoCD reconciles this repo into the
cluster: every deployment is a commit here, every rollback is a `git revert`.
Nothing is applied to a cluster by hand.

## Stack

Kubernetes manifests + Kustomize v5. ArgoCD v3.5.0 (App-of-Apps + ApplicationSets).
Argo Rollouts CRDs for the canary strategy (activation only). No application code.

## Commands

```bash
# Render + schema-validate every environment (no cluster needed)
for e in dev staging prod; do
  kustomize build apps/auth-api/overlays/$e | kubeconform -strict -summary
done

# Local end-to-end (kind)
kind create cluster --name microtodo
kustomize build bootstrap/argocd | kubectl apply --server-side -f -
kubectl -n argocd wait deploy --all --for=condition=Available --timeout=300s
docker build -t auth-api:0.1.0-local ../microservice-app-auth-api
kind load docker-image auth-api:0.1.0-local --name microtodo
kubectl apply -f clusters/local-kind/root-app.yaml   # the only manual apply

# Promote / roll back
scripts/bump-image.sh <service> <env> <tag>   # then: git push
git revert <commit>                            # then: git push
```

## Structure

- `bootstrap/argocd/` — pinned ArgoCD install; applied once, then self-managed.
- `clusters/<cluster>/` — App-of-Apps root, AppProject, and the ApplicationSets
  that generate one Application per add-on and per {service × environment}.
- `infrastructure/<addon>/` — platform add-ons (task 2 fills the content).
- `apps/<service>/base` — shared manifests; `components/` — version-specific
  fragments; `topology/` — single per-service economical↔full switch;
  `overlays/{dev,staging,prod}` — environment-only differences.
- `scripts/bump-image.sh` — manual image bump (replaced by CI PR in roadmap #4).
- `specs/` — Spec-Driven Development artifacts (English).

## Conventions

- All artifacts in English (suite-wide rule).
- Economical topology (single cluster, environments as namespaces) is the live
  default; full topology (multi-cluster + Istio) is prepared, not activated.
- Version differences live in Components, destination differences live in the
  ApplicationSet environment list — never in a service's base/overlays.
- Trunk-based development, short-lived branches, feature specs under `specs/`.

## Notes for the infrastructure integration

- Image references use local tags; they become ECR URLs when task 1 delivers the
  registry (set the registry once in `base`, overlays keep only the tag).
- The committed test JWT Secret is replaced by an `ExternalSecret` once External
  Secrets Operator (task 2) and its IRSA role (task 1) exist.
- `destination.server` is `https://kubernetes.default.svc` while ArgoCD runs in
  the same cluster it deploys to (economical); full version registers remote
  clusters and sets per-environment servers in the ApplicationSet list.

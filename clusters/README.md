# clusters/

Each folder represents one cluster and is reconciled by ArgoCD running inside
that same cluster. It holds the App-of-Apps root, AppProject, and
ApplicationSets that generate the infrastructure, environment-policy, and
business-service Applications for that cluster.

The registration seam is intentionally small:

- `registration.yaml` contributes only the reviewed Git `repoURL` and
  `revision` values;
- `activation-apps.yaml` and `activation-environments.yaml` inject matching
  `{ env, server }` lists; and
- `activation-infrastructure.yaml` injects an exact reviewed
  `{ name, path, namespace }` list; and
- the shared templates derive the namespace as `microtodo-{{ .env }}`.

Infrastructure is never activated by folder discovery. The local registration
explicitly retains its five validated entries, including local Redis. A managed
registration retains that five-entry list during environment-Redis migration
and switches to the reviewed four-controller list only after replacement
readiness and protocol checks pass.

Because every reconciler targets its own cluster, every activation uses
`server: https://kubernetes.default.svc`. A raw EKS or AKS API endpoint and
certificate authority are used only for operator access and the audited,
one-time bootstrap of that cluster's root Application.

## Economical version (active)

One shared cluster (`eks-main` after its separate handoff) runs one ArgoCD
instance and hosts multiple environments as namespaces. Its app activation
stays empty for feature 005 while its environment activation carries this list:

```yaml
- env: dev
  server: https://kubernetes.default.svc
- env: staging
  server: https://kubernetes.default.svc
- env: prod
  server: https://kubernetes.default.svc
```

The shared templates derive `microtodo-dev`, `microtodo-staging`, and
`microtodo-prod`; namespace is not a registration input.

## Full version (prepared, not active)

Environments become separate clusters. Future sibling registrations such as
`eks-dev`, `eks-staging`, `eks-prod`, and `aks-dr` each consume `../base`, run
their own ArgoCD, and activate only the environment that cluster owns. For
example, `clusters/eks-dev` injects this value into both activation patches:

```yaml
- env: dev
  server: https://kubernetes.default.svc
```

This requires no edits to `apps/<service>/base` or its environment overlays.
The `aks-dr` registration also reconciles locally and consumes the reviewed
production overlay with the same promoted OCI digest when DR activation is
approved; tag equality is not the promotion guarantee.

The full version also flips each service's `topology/kustomization.yaml` to the
`topology-full` component (Istio) — see `apps/auth-api/topology/`.

## Why there is no centralized ArgoCD hub

Running a central reconciler only in `eks-prod` would make that cluster a single
point of failure for disaster recovery. If production were unavailable,
`aks-dr` would also lose the reconciler needed to converge its desired state.
Per-cluster ArgoCD keeps each cluster autonomous: a surviving DR cluster can
continue pulling and reconciling the reviewed Git revision even while
`eks-prod` is down.

## Current registration wiring

Each sibling registration consumes `../base`, patches the three independent
activation lists, and replaces only the repository URL and revision fields from
its ConfigMap. `clusters/eks-dev` remains a registration-only foundation until
the separate shared-cluster handoff is reviewed; feature 005 does not create
`clusters/eks-main` or bootstrap its root Application.

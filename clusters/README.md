# clusters/

Each folder is one cluster ArgoCD deploys to. It holds the App-of-Apps root, the
AppProject, and the ApplicationSets that generate the add-on and service
Applications for that cluster.

## Economical version (active)

One cluster (`local-kind`, later `eks-main`). Environments are namespaces of that
single cluster. In `local-kind/apps.yaml`, every environment entry targets
`https://kubernetes.default.svc` with a different namespace:

```yaml
- env: dev     { server: https://kubernetes.default.svc, namespace: microtodo-dev }
- env: staging { server: https://kubernetes.default.svc, namespace: microtodo-staging }
- env: prod    { server: https://kubernetes.default.svc, namespace: microtodo-prod }
```

## Full version (prepared, not active)

Environments become separate clusters. Two data-only changes, zero edits to any
`apps/<service>/base` or `overlays`:

1. Register the remote clusters in ArgoCD (once):
   ```bash
   argocd cluster add <eks-dev-context>
   argocd cluster add <eks-staging-context>
   argocd cluster add <eks-prod-context>
   ```
2. Point each environment entry at its cluster's API server:
   ```yaml
   - env: dev     { server: https://<eks-dev-endpoint>,     namespace: auth-api }
   - env: staging { server: https://<eks-staging-endpoint>, namespace: auth-api }
   - env: prod    { server: https://<eks-prod-endpoint>,    namespace: auth-api }
   ```

`aks-dr` (disaster recovery) is added as an extra entry that receives the same
tag as prod. Endpoints come from task 1 (Terraform) and are placeholders until
then.

The full version also flips each service's `topology/kustomization.yaml` to the
`topology-full` component (Istio) — see `apps/auth-api/topology/`.

# Vendored External Secrets Operator v2.9.0

`manifests.yaml` is the External Secrets Operator install, rendered from the
upstream Helm chart and vendored so the pilot deploys it without a hosted
dependency (spec 001, FR-017).

Regenerate with the exact pinned version:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm template external-secrets external-secrets/external-secrets \
  --version 2.9.0 --namespace external-secrets \
  --include-crds --set installCRDs=true \
  > manifests.yaml
```

Upgrading means re-rendering a new pinned version into a sibling `vX.Y.Z/`
folder and pointing `infrastructure/external-secrets/kustomization.yaml` at it.

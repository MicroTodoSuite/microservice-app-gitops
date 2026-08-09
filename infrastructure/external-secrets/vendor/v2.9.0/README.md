# Vendored External Secrets Operator v2.9.0

`manifests.yaml` is the External Secrets Operator install, rendered from the
upstream Helm chart and vendored so the pilot deploys it without a hosted
dependency (spec 001, FR-017).

The official chart index published chart 2.9.0 with application version v2.9.0
and chart digest
`da2d5c126a103b4c1b16a9dc1c168c4332a3687144e88ac070e594f81a0b6578`.

Regenerate with the exact pinned version:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm template external-secrets external-secrets/external-secrets \
  --version 2.9.0 --namespace external-secrets \
  --include-crds --set installCRDs=true \
  > manifests.yaml
sha256sum -c SHA256SUMS
```

The retained render checksum was verified on 2026-08-09. The parent
Kustomization converts the controller image to its immutable multi-platform
digest without changing this file.

Upgrading means re-rendering a new pinned version into a sibling `vX.Y.Z/`
folder and pointing `infrastructure/external-secrets/kustomization.yaml` at it.

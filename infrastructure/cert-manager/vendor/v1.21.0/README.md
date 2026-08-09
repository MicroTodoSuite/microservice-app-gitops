# Vendored cert-manager v1.21.0

`install.yaml` is the complete cert-manager v1.21.0 static release bundle,
including CRDs, controller, cainjector, webhook, RBAC, and services.

Source:

```text
https://github.com/cert-manager/cert-manager/releases/download/v1.21.0/cert-manager.yaml
```

Refresh and verify the retained bytes with:

```bash
curl -fL \
  https://github.com/cert-manager/cert-manager/releases/download/v1.21.0/cert-manager.yaml \
  -o install.yaml
sha256sum -c SHA256SUMS
```

The recorded checksum was verified on 2026-08-09. Runtime images, including the
ACME solver reference carried in a controller argument, are converted to
immutable multi-platform digests by the parent Kustomization. The vendor file
remains byte-for-byte unchanged.

Upgrade by retaining a new official bundle in a sibling version directory,
recording its checksum and image digests, updating the Kustomize resource and
solver patch, and proving the static and live certificate contracts.

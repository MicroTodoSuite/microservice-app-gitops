# Vendored Kyverno v1.18.2

`install.yaml` is the complete Kyverno v1.18.2 static release bundle, including
CRDs, admission, background, cleanup, and reports controllers, webhooks, RBAC,
services, and certificate bootstrap resources.

Source:

```text
https://github.com/kyverno/kyverno/releases/download/v1.18.2/install.yaml
```

Refresh and verify the retained bytes with:

```bash
curl -fL \
  https://github.com/kyverno/kyverno/releases/download/v1.18.2/install.yaml \
  -o install.yaml
sha256sum -c SHA256SUMS
```

The checksum above matches the SHA-256 published for the release asset and was
verified again on 2026-08-09. Runtime controller images are converted to
immutable multi-platform digests by `infrastructure/kyverno/kustomization.yaml`.

Upgrade by retaining the new official bundle in a sibling `vX.Y.Z` directory,
recording its checksum and image digests, updating the Kustomize resource, and
proving controller, policy, and auth-api compatibility before removing the
prior version.

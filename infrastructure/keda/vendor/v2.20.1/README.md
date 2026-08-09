# Vendored KEDA v2.20.1

`install.yaml` is the complete KEDA v2.20.1 static release bundle, including
CRDs, the operator, metrics API server, admission webhook, RBAC, services, and
API registration.

Source:

```text
https://github.com/kedacore/keda/releases/download/v2.20.1/keda-2.20.1.yaml
```

Refresh and verify the retained bytes with:

```bash
curl -fL \
  https://github.com/kedacore/keda/releases/download/v2.20.1/keda-2.20.1.yaml \
  -o install.yaml
sha256sum -c SHA256SUMS
```

The recorded checksum was verified on 2026-08-09. Runtime images are converted
to immutable multi-platform digests by `infrastructure/keda/kustomization.yaml`;
the vendor file remains unchanged so its checksum stays independently useful.

Upgrade by retaining the new official bundle in a sibling `vX.Y.Z` directory,
recording its checksum and image digests, changing the Kustomize resource, and
proving the static and live contracts before removing the prior version.

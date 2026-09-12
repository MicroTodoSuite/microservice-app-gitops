# Vendored ECK (Elastic Cloud on Kubernetes) v3.5.0

`crds.yaml` and `operator.yaml` are the two complete upstream static release
files (CRDs and operator, ECK ships them separately, unlike cert-manager's
single-file bundle).

Source (`capabilities[].eck`):

```text
https://download.elastic.co/downloads/eck/3.5.0/crds.yaml
sha256: 0e126dbd003f8f98c9b84f2af6263b5ac8a00b52cd9a6d6da225aa3af66cc13c
https://download.elastic.co/downloads/eck/3.5.0/operator.yaml
sha256: 450f59d5026341226c54bbd3fafb68adcf99de8c674b47e32c22fae8aa183bf7
```

Refresh and verify with:

```bash
curl -fL -o crds.yaml https://download.elastic.co/downloads/eck/3.5.0/crds.yaml
curl -fL -o operator.yaml https://download.elastic.co/downloads/eck/3.5.0/operator.yaml
sha256sum -c SHA256SUMS
```

The recorded checksums were verified on 2026-09-12. Both files remain
byte-for-byte unchanged; the parent Kustomization pins the operator image to
its immutable digest.

`operator.yaml` includes an empty `elastic-webhook-server-cert` Secret (no
`data`/`stringData` keys) — the operator generates and populates its own
webhook certificate at runtime; unlike Chaos Mesh, this chart has no
cert-manager integration to prefer instead, and there is no secret *value*
committed here, only the placeholder object the operator expects to already
exist.

Upgrade by re-downloading into a new version directory, recording the new
checksums, and re-running `tests/platform/eck.bats`.

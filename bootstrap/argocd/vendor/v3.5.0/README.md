# Vendored Argo CD v3.5.0

`install.yaml` is the upstream Argo CD v3.5.0 install manifest, vendored so the
local pilot reconciles without a hosted dependency (spec 001, FR-017).

- **Upstream**: https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.0/manifests/install.yaml
- **Integrity**: verify before use with `shasum -a 256 -c SHA256SUMS`.

Upgrading Argo CD means vendoring a new pinned version in a sibling `vX.Y.Z/`
folder, updating `SHA256SUMS`, and pointing `bootstrap/argocd/kustomization.yaml`
at it — never fetching a floating manifest at apply time.

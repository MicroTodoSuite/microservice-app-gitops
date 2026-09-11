# Vendored Istio v1.30.3

`install.yaml` is the complete `default` profile output of `istioctl manifest
generate` for Istio v1.30.3: CRDs, `istiod`, `istio-ingressgateway`, RBAC, and
webhooks. Unlike a single-file upstream release (cert-manager, Kyverno),
Istio's release artifact is the `istioctl` binary itself; the install manifest
is generated, not downloaded, so the exact command is the reproduction
contract.

Source (`scripts/managed/full-profile-toolchain.lock`, `capabilities[].istio`):

```text
https://github.com/istio/istio/releases/download/1.30.3/istio-1.30.3-linux-amd64.tar.gz
sha256: 55ada076ba1b37af49e8a24e5e539b4abccabdb33894c923279edd293eea3993
```

Refresh and verify with:

```bash
curl -fL -o istio-1.30.3-linux-amd64.tar.gz \
  https://github.com/istio/istio/releases/download/1.30.3/istio-1.30.3-linux-amd64.tar.gz
echo "55ada076ba1b37af49e8a24e5e539b4abccabdb33894c923279edd293eea3993  istio-1.30.3-linux-amd64.tar.gz" | sha256sum -c
tar -xzf istio-1.30.3-linux-amd64.tar.gz
./istio-1.30.3/bin/istioctl manifest generate --set profile=default > install.yaml
sha256sum -c SHA256SUMS
```

Generated on a `linux-amd64` runner (matched here via `docker run --platform
linux/amd64 ubuntu:24.04`) to reproduce the exact toolchain-lock platform
rather than a host-native build. Runtime images (`pilot`, `proxyv2`) are
converted to immutable digests by the parent Kustomization; the vendored file
remains byte-for-byte the generator's output.

`istioctl manifest generate` does not emit the `istio-system` Namespace or any
NetworkPolicy — those are repository-owned files alongside this vendor
directory (`../namespace.yaml`, `../network-policy.yaml`), following the same
split already used by `infrastructure/external-secrets/`.

The manifest contains one additional image reference, `busybox:1.28`, inside
the `istio-sidecar-injector` ConfigMap's inert `grpc-simple` injection-template
string (an opt-in template our default profile never activates). It is text
data, not a scheduled container, so Kustomize's image transformer correctly
leaves it untouched; it needs no digest pin here.

Upgrade by regenerating into a new version directory with the command above,
recording the new checksum, updating the parent Kustomization's image digests,
and re-running `tests/platform/mesh-policy.bats`.

# Vendored Chaos Mesh v2.8.4

`install.yaml` is `helm template` output of the official Chaos Mesh Helm
chart, with images pinned to their immutable digest from
`scripts/managed/full-profile-toolchain.lock` by the parent Kustomization.
`values.yaml` is the exact override file used to produce it.

Source (`capabilities[].chaos-mesh`):

```text
https://charts.chaos-mesh.org/chaos-mesh-2.8.4.tgz
sha256: ae4abd385649771300e4d33a44627c0df3618be0780c385bf30cc2fdf2ad93fa
```

Refresh and verify with:

```bash
curl -fL -o chaos-mesh-2.8.4.tgz https://charts.chaos-mesh.org/chaos-mesh-2.8.4.tgz
echo "ae4abd385649771300e4d33a44627c0df3618be0780c385bf30cc2fdf2ad93fa  chaos-mesh-2.8.4.tgz" | sha256sum -c
tar -xzf chaos-mesh-2.8.4.tgz
helm template chaos-mesh chaos-mesh --namespace chaos-mesh --include-crds \
  -f values.yaml \
  --api-versions cert-manager.io/v1 \
  | sed -E 's/rollme: "[A-Za-z0-9]{5}"/rollme: "vendored"/' \
  > install.yaml
sha256sum -c SHA256SUMS
```

Generated via `docker run --platform linux/amd64 alpine/helm:3.16.4` to match
the toolchain-lock platform.

**`--api-versions cert-manager.io/v1` is required, not optional — found by
applying the render to a live cluster, not by reading the chart.**
`templates/cert-manager-certs.yaml` picks its Certificate/Issuer `apiVersion`
by probing `.Capabilities.APIVersions.Has(...)` against whichever cert-manager
API versions the chart *thinks* are installed, falling through v1 → v1beta1 →
v1alpha3 → v1alpha2 in that order. `helm template` run offline (no live
cluster, as every vendor step in this repository does) reports zero installed
API versions unless told otherwise, so without this flag the chart silently
picks its last, oldest fallback — `cert-manager.io/v1alpha2`, an API version
cert-manager v1.21.0 (the version this repository vendors, `infrastructure/cert-manager/`)
no longer serves at all. The first live-cluster apply attempt failed outright:
`no matches for kind "Certificate" in version "cert-manager.io/v1alpha2"`.
Confirmed the fix by grepping the render for every `apiVersion: cert-manager`
line — all four now read `v1` — and by a second live apply that succeeded.

**Two more chart quirks required action, not just documentation.**

1. The chart's `controller-manager-deployment.yaml` and
   `chaos-daemon-daemonset.yaml` templates hard-code
   `rollme: {{ randAlphaNum 5 | quote }}` — a restart-forcing pod annotation
   with a fresh random value on every single render, no values toggle to
   disable it. Rendering twice and diffing confirmed it is the *only*
   non-deterministic byte in the chart's output. The `sed` step above pins it
   to a fixed placeholder so the vendored file — and its checksum — are
   reproducible. The value is inert (nothing reads it back); this only
   affects whether re-vendoring reproduces the same bytes.
2. With chart defaults, `helm template` emits a `chaos-mesh-chaosd-client-certs`
   Secret containing a **freshly self-signed certificate generated at render
   time** (`chaosDaemon.mtls.enabled` and `controllerManager.chaosdSecurityMode`
   both default `true`, and the chart's own comment says it "does not support
   use specified ca and cert for mtls"). That is exactly the kind of committed
   secret material `tests/contract/*.sh`'s secret-scanning guards reject, and
   it would also make the vendor file irreproducible by construction — every
   re-render mints a different certificate. Both are disabled in
   `values.yaml`; confirmed zero `kind: Secret` resources in the render.
   Chaos Mesh is disabled-by-default in this repository already (see the
   parent `kustomization.yaml`), so losing daemon-to-controller mTLS costs
   nothing today; wiring a cert-manager-issued replacement is separate,
   explicit follow-up work if and when the experiment roots this vendors
   activate for real (spec 009 T135).

The webhook's own certificate (the one this chart *does* let you delegate,
unlike the two above) uses cert-manager (`webhook.certManager.enabled: true`),
matching the ownership pattern already established by every other vendored
component: ArgoCD owns Chaos Mesh, and its webhook cert comes from the
cert-manager Issuer/Certificate CRs cert-manager itself already owns.

The toolchain lock also pins `chaos-mesh-kernel` and `chaos-mesh-dlv`
(debug-build variants); neither appears in this render — confirmed by
`grep -c` against the vendored file — because nothing in this chart's default
values enables the debug/dlv profile that would reference them. No digest pin
needed for an image that never gets scheduled.

**Applying this bundle client-side fails on three CRDs, unrelated to anything
above.** `schedules.chaos-mesh.org`, `workflownodes.chaos-mesh.org`, and
`workflows.chaos-mesh.org` embed enough nested OpenAPI schema that
`kubectl apply`'s `last-applied-configuration` annotation exceeds
Kubernetes' 262144-byte annotation limit —
`metadata.annotations: Too long: may not be more than 262144 bytes`. This is
a `kubectl apply` client-side-apply limitation, not a defect in these CRDs
themselves: `kubectl apply --server-side` (which carries no such annotation)
applies the identical bundle cleanly, confirmed live. Whichever cluster
registration eventually activates `infrastructure/chaos-mesh/` needs
ArgoCD's `ServerSideApply=true` sync option for this reason.

Upgrade by regenerating into a new version directory with the command above,
recording the new checksum, and re-running
`tests/platform/chaos-mesh-opencost.bats`.

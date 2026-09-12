# Vendored AWS Load Balancer Controller v3.5.0

`install.yaml` is the complete static release bundle: CRDs, controller,
RBAC, and cert-manager-issued webhook certificate. Unlike Istio/Kiali/Chaos
Mesh (Helm/istioctl-generated), this is a single-file upstream release, same
pattern as `infrastructure/cert-manager/`.

Source (`capabilities[].aws-load-balancer-controller`):

```text
https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v3.5.0/v3_5_0_full.yaml
sha256: 709fa64150df430895d215ad80dd89dff7e1bead9e28f62ab5a1aac212c44cee
```

Refresh and verify with:

```bash
curl -fL -o install.yaml \
  https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v3.5.0/v3_5_0_full.yaml
sha256sum -c SHA256SUMS
```

The recorded checksum was verified on 2026-09-12. The vendor file remains
byte-for-byte unchanged; the parent Kustomization pins the runtime image to
its immutable digest.

**Not activated: the ServiceAccount carries no IRSA role ARN.** T083 asks for
"a GitOps-owned EKS ServiceAccount annotated with the exact Terraform-output
IRSA role ARN." That ARN does not exist — it is produced only after a real
full-profile EKS cluster is applied (spec 009, Phase 4, T057-T062), and this
vendor step deliberately does not invent one, for the same reason
`infrastructure/opencost/`'s `CLUSTER_ID` is left unset: a placeholder value
here would be exactly the kind of "ad hoc ... operator-supplied runtime
value" T070 explicitly tests against. Confirmed live, on a local `kind`
cluster with no AWS credentials at all: the controller CrashLoopBackOffs
before it ever reaches the missing-IRSA-ARN problem, because it cannot even
initialize an AWS client outside EC2/EKS —

```
{"level":"error","logger":"setup","msg":"unable to initialize AWS cloud",
 "error":"failed to introspect region from EC2Metadata, specify --aws-region
 instead if EC2Metadata is unavailable: ... dial tcp 169.254.169.254:80:
 connect: connection refused"}
```

— so this addon cannot be meaningfully proven live outside a real EC2/EKS
environment; the render/policy test is the extent of local verification.
Once a real full-profile EKS cluster exists (Phase 4), region discovery
succeeds automatically and the remaining requirement is the ServiceAccount's
IRSA role ARN.

Upgrade by re-downloading into a new version directory, recording the new
checksum, and re-running `tests/platform/aws-load-balancer-controller.bats`.

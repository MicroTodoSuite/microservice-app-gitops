# Vendored Karpenter v1.14.1

`install.yaml` is `helm template` output of the official Karpenter Helm
chart (an OCI artifact, not an HTTPS `.tgz`). `crds.yaml` is the companion
`karpenter-crd` chart's output. `values.yaml` is the exact override file used
to produce `install.yaml`.

Source (`capabilities[].karpenter`, both OCI references):

```text
oci://public.ecr.aws/karpenter/karpenter:1.14.1
sha256: 91434e00fb102d6ee0d1bd34a4457a32fe01a8fa833fe1a2a37da4f50272079b
oci://public.ecr.aws/karpenter/karpenter-crd:1.14.1
sha256: c05c566740802506a34f3500b33e2fa3c9254f60469e84e5e294a3bd8adefb9f
```

Refresh and verify with:

```bash
helm pull oci://public.ecr.aws/karpenter/karpenter --version 1.14.1
helm pull oci://public.ecr.aws/karpenter/karpenter-crd --version 1.14.1
# helm pull prints the digest of what it fetched; compare by eye against the
# two sha256 values above (helm has no --verify-digest flag for OCI pulls).
tar -xzf karpenter-1.14.1.tgz && tar -xzf karpenter-crd-1.14.1.tgz
helm template karpenter karpenter --namespace kube-system -f values.yaml > install.yaml
helm template karpenter-crd karpenter-crd --namespace kube-system > crds.yaml
sha256sum -c SHA256SUMS
```

Generated via `docker run --platform linux/amd64 alpine/helm:3.16.4` to match
the toolchain-lock platform. Rendered twice and diffed byte-for-byte
identical for both charts. The chart's own default values already pin the
controller image to the exact digest in the toolchain lock
(`public.ecr.aws/karpenter/controller:1.14.1@sha256:445b...`) — confirmed by
grep, not assumed — so no Kustomize `images:` transform is needed, the same
situation as `infrastructure/opencost/`.

**This chart cannot render at all without `settings.clusterName` — unlike
every other vendored component, there is no way to defer this decision.**
`templates/deployment.yaml` enforces it: `required "Chart cannot be
installed without a valid settings.clusterName!"`. `values.yaml` sets it to
the literal placeholder `CHANGEME-full-cluster-name`, the same
unmistakably-inert-marker convention already used in
`infrastructure/chaos-mesh/experiments/` — deliberately not a plausible real
value, so nobody mistakes the rendered Deployment for something that could
run correctly as committed. `eksControlPlane: true` is set because the real
target is always EKS; `settings.interruptionQueue` and
`settings.clusterEndpoint` are left at their chart defaults (empty string) —
the chart itself treats both as genuinely optional ("interruption handling
is disabled if not specified"; endpoint "will be discovered during startup"),
so no placeholder was needed for either.

**Whichever cluster registration eventually activates this addon must patch
three things via Kustomize, not edit this vendor file:** the real
`settings.clusterName` (a `CHANGEME` string is not a value, it is a marker
that nothing has decided this yet), `settings.interruptionQueue` (a
Terraform output — an SQS queue ARN — that does not exist until Phase 4
applies), and the IRSA role ARN on the `karpenter` ServiceAccount (same
constraint as `infrastructure/aws-load-balancer-controller/`).

**Confirmed live, on a local `kind` cluster with no AWS credentials at all:**
one replica reached `Running` (the second correctly stayed `Pending` —
the chart's own topology spread constraint needs two zones, and a
single-node kind cluster genuinely has only one; not a defect), then
panicked immediately:

```
panic: unable to determine region from IMDS: operation error ec2imds:
GetRegion, exceeded maximum number of attempts, 3, request send failed,
Get "http://169.254.169.254/latest/dynamic/instance-identity/document":
dial tcp 169.254.169.254:80: connect: connection refused
```

The same IMDS-region-discovery dependency that stops
`infrastructure/aws-load-balancer-controller/` from running outside EC2/EKS
stops this too — so, like that addon, this cannot be meaningfully proven
live outside a real EC2/EKS environment; the render/policy test is the
extent of local verification.

Upgrade by regenerating into a new version directory with the commands
above, recording the new checksums, and re-running
`tests/platform/karpenter.bats`.

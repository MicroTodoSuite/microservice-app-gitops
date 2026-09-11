# Vendored OpenCost v2.5.29

`install.yaml` is `helm template` output of the official OpenCost Helm chart.
`values.yaml` is the exact override file used to produce it. Unlike Chaos
Mesh, this chart's own default `values.yaml` already pins both images to the
exact digests in `scripts/managed/full-profile-toolchain.lock`
(`opencost/opencost:1.121.1@sha256:5005...` and
`opencost/opencost-ui:1.121.1@sha256:a2ea...`) — confirmed by grepping the
render, not assumed — so no Kustomize `images:` digest transform is needed
here, unlike every other vendored component in this repository.

Source (`capabilities[].opencost`):

```text
https://github.com/opencost/opencost-helm-chart/releases/download/opencost-2.5.29/opencost-2.5.29.tgz
sha256: 65edf913738a9810ee940a24efcd265ff4a0f22235fa3cc483e1ebd5c121d0bc
```

Refresh and verify with:

```bash
curl -fL -o opencost-2.5.29.tgz \
  https://github.com/opencost/opencost-helm-chart/releases/download/opencost-2.5.29/opencost-2.5.29.tgz
echo "65edf913738a9810ee940a24efcd265ff4a0f22235fa3cc483e1ebd5c121d0bc  opencost-2.5.29.tgz" | sha256sum -c
tar -xzf opencost-2.5.29.tgz
helm template opencost opencost --namespace opencost -f values.yaml > install.yaml
sha256sum -c SHA256SUMS
```

Generated via `docker run --platform linux/amd64 alpine/helm:3.16.4` to match
the toolchain-lock platform. Rendered twice and diffed byte-for-byte identical
— no chart-side non-determinism here, unlike Chaos Mesh's `rollme` annotation.

The only override from chart defaults: `opencost.prometheus.internal` points
at this repository's real Prometheus (`prometheus-k8s.observability:9090`,
verified by rendering `infrastructure/prometheus/` and reading its actual
Service name/namespace/port), not the chart's generic default guess
(`prometheus-server.prometheus-system:80`).

**Cost labels (T087) are mostly already free, one is deliberately left
undecided.** OpenCost allocates cost by Kubernetes namespace and pod labels
it reads directly from the cluster — no extra configuration makes namespace
("environment": `microtodo-dev`, etc.) or `app.kubernetes.io/name`
("service") show up as cost dimensions; every workload in this repository
already carries those. The one dimension OpenCost cannot infer on its own is
"cluster" (`opencost.exporter.defaultClusterId`, `CLUSTER_ID` env var) — this
chart is one shared Kustomize root meant to run identically in every
full-profile cluster (dev/staging/prod), the same pattern
`infrastructure/<addon>/` already uses for every other add-on, so hard-coding
one cluster's name here would silently mislabel the other two. Which
mechanism supplies that value per cluster — a registration-level Kustomize
patch, once a real `clusters/eks-full-*/activation-infrastructure.yaml` entry
exists for this addon — is a decision for that follow-up, not this vendor
step.

Upgrade by regenerating into a new version directory with the command above,
recording the new checksum, and re-running
`tests/platform/chaos-mesh-opencost.bats`.

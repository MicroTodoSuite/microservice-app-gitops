# Vendored kube-prometheus v0.18.0 (cost allocation sources)

This directory retains a second **scoped subset** of the same official
`kube-prometheus` v0.18.0 release source that
`infrastructure/prometheus/vendor/v0.18.0/` retains: the two exporters
OpenCost reads, and nothing else. It is vendored here, beside the component
that consumes it, because Kustomize refuses to load a file outside the
kustomization directory that names it.

Source:

```text
https://github.com/prometheus-operator/kube-prometheus/archive/refs/tags/v0.18.0.tar.gz
sha256:24379eb37cc54f73e96c7a39cdaa28ae9f4670ad6e0e932ea8b524c1fefdaacd
```

That archive checksum is the one `scripts/managed/full-profile-toolchain.lock`
already records for this release, so both subsets come from one verified
download.

## What is retained and why

`infrastructure/prometheus/vendor/v0.18.0/README.md` excludes
`nodeExporter-*.yaml` and `kubeStateMetrics-*.yaml` because the economical
profile's golden signals are workload-level, and retaining upstream's rules
without their exporters would alert on metrics nothing scrapes. That reasoning
still holds for the economical profile, which does not include this component.

The full profile has a requirement the economical profile does not: OpenCost's
metrics reference (`docs/integrations/metrics.md` in `opencost/opencost-website`)
lists both exporters as required for OpenCost to function properly. Cost per
node comes from `node_cpu_seconds_total`, `node_memory_MemTotal_bytes`,
`node_filesystem_size_bytes`, and `node_filesystem_free_bytes`; cost per
workload comes from `kube_node_status_capacity`,
`kube_node_status_allocatable`, `kube_pod_container_resource_requests`,
`kube_pod_container_resource_limits`, `kube_persistentvolumeclaim_info`, and
`kube_persistentvolumeclaim_resource_requests_storage_bytes`. Without them
OpenCost has no prices to allocate, so FR-033 cannot be met.

- `nodeExporter-*.yaml` - the DaemonSet, its ClusterRole/ClusterRoleBinding,
  ServiceAccount, Service, ServiceMonitor, and NetworkPolicy.
- `kubeStateMetrics-*.yaml` - the Deployment, its ClusterRole/ClusterRoleBinding,
  ServiceAccount, Service, ServiceMonitor, and NetworkPolicy.

## What is deliberately excluded

`nodeExporter-prometheusRule.yaml` (26 alerts) and
`kubeStateMetrics-prometheusRule.yaml` (4 alerts) are excluded. These exporters
are added to satisfy OpenCost's documented input requirement, not to introduce
thirty node and cluster alerts nobody asked for; the evolution plan's
observability scope names no such alert, and every alert that reaches Slack in
this profile is the reviewed set in `../../../alerts/rules.yaml`. Adding them
would be a scope decision, not a side effect of a cost feature.

Both NetworkPolicies are retained as upstream wrote them: they admit only pods
labelled `app.kubernetes.io/name: prometheus` in the same namespace, on port
9100 for node-exporter and ports 8443 and 9443 for kube-state-metrics, which is
exactly this repository's Prometheus and nothing else.

## Refresh and verify

```bash
curl -fL \
  https://github.com/prometheus-operator/kube-prometheus/archive/refs/tags/v0.18.0.tar.gz \
  -o /tmp/kube-prometheus-v0.18.0.tar.gz
sha256sum /tmp/kube-prometheus-v0.18.0.tar.gz  # must match the checksum above
tar -xzf /tmp/kube-prometheus-v0.18.0.tar.gz -C /tmp
# re-copy only the files listed above from /tmp/kube-prometheus-0.18.0/manifests/
sha256sum -c SHA256SUMS
```

The checksums in `SHA256SUMS` were computed from this retained subset and
verified on 2026-09-18. Every manifest keeps its upstream `namespace: monitoring`
reference and its upstream image tags; `../../kustomization.yaml` retargets the
namespace to `observability` and converts the tags to immutable digests, rather
than editing the retained files.

Upgrade together with `infrastructure/prometheus/vendor/`: both subsets are one
release, and an exporter from another release is not covered by the
compatibility table that release publishes.

# Vendored kube-prometheus v0.18.0 (scoped subset)

This directory retains a **scoped subset** of the official `kube-prometheus`
v0.18.0 release source, not the full stack. `kube-prometheus` v0.18.0 is
compatible with Kubernetes 1.32-1.36 per its own published compatibility
table, covering the live `eks-dev` cluster's version.

Source:

```text
https://github.com/prometheus-operator/kube-prometheus/archive/refs/tags/v0.18.0.tar.gz
```

## What is retained and why

- `setup/` - all ten CRDs (`Alertmanager`, `AlertmanagerConfig`, `PodMonitor`,
  `Probe`, `Prometheus`, `PrometheusAgent`, `PrometheusRule`, `ScrapeConfig`,
  `ServiceMonitor`, `ThanosRuler`) plus the upstream `namespace.yaml`. The
  Prometheus Operator expects its full CRD set installed even though this
  feature only instantiates `Prometheus`, `Alertmanager`, `ServiceMonitor`,
  `PrometheusRule`, and `AlertmanagerConfig`.
- `prometheusOperator-*.yaml` - the Operator controller itself (Deployment,
  RBAC, ServiceAccount, Service, its own ServiceMonitor/PrometheusRule).
- `prometheus-*.yaml` - the `Prometheus` custom resource and its supporting
  RBAC/PodDisruptionBudget/NetworkPolicy/Service resources.
- `alertmanager-*.yaml` - the `Alertmanager` custom resource and its
  supporting Secret/PodDisruptionBudget/NetworkPolicy/Service resources.

## What is deliberately excluded

`prometheus-roleSpecificNamespaces.yaml` and
`prometheus-roleBindingSpecificNamespaces.yaml` are also excluded: they are
upstream's example for a *restricted* per-namespace discovery mode, an
alternative to the broader `prometheus-clusterRole`/`prometheus-
clusterRoleBinding` this subset already retains. Rewriting their originally
distinct target namespaces (`default`, `kube-system`) to this project's
single `observability` namespace via Kustomize's namespace transformer
produces two identically-named RoleBindings - a real render conflict
verified with `kubectl kustomize infrastructure/prometheus`, not a
hypothetical one - so they were dropped rather than worked around.

`grafana-*.yaml` (this project hand-authors its own Grafana per
`specs/006-observability-platform-foundation/research.md`), `kubeStateMetrics-*.yaml`,
`nodeExporter-*.yaml`, `blackboxExporter-*.yaml`, `prometheusAdapter-*.yaml`,
`kubernetesControlPlane-*.yaml`, and `kubePrometheus-prometheusRule.yaml` are
all excluded. This feature's spec scopes golden signals to the five business
workloads, not node/cluster/control-plane metrics; retaining those files
without their exporters would install `PrometheusRule` objects that alert on
metrics nothing scrapes.

## Refresh and verify

```bash
curl -fL \
  https://github.com/prometheus-operator/kube-prometheus/archive/refs/tags/v0.18.0.tar.gz \
  -o /tmp/kube-prometheus-v0.18.0.tar.gz
tar -xzf /tmp/kube-prometheus-v0.18.0.tar.gz -C /tmp
# re-copy only the files listed above from /tmp/kube-prometheus-0.18.0/manifests/
sha256sum -c SHA256SUMS
```

The checksums in `SHA256SUMS` were computed directly from this retained
subset and verified on 2026-08-23. All manifests keep their upstream
`namespace: monitoring` reference; `infrastructure/prometheus/kustomization.yaml`
retargets them to `observability` with Kustomize's namespace transformer
rather than editing the retained files. Runtime images are converted to
immutable digests by the same kustomization, never edited in place here.

Upgrade by retaining the new official subset in a sibling `vX.Y.Z` directory,
recording its checksum and image digests, updating the Kustomize resource,
and proving Operator/Prometheus/Alertmanager health before removing the
prior version.

# kube-bench v0.16.0 image provenance

kube-bench has no upstream raw-YAML installation bundle to vendor as a
whole; it publishes example Job manifests directly in its repository
instead. This directory records image provenance; `infrastructure/
kube-bench/cronjob.yaml` is adapted from kube-bench's own real
`job-eks.yaml` for this exact tag (source noted in the manifest's own
comment), wrapped in a `CronJob` for this feature's recurring-schedule
requirement.

Source image:

```text
docker.io/aquasec/kube-bench:v0.16.0
```

Multi-platform digest (verified 2026-08-23 via
`docker buildx imagetools inspect aquasec/kube-bench:v0.16.0`):

```text
sha256:75506f222d1eb6ce2a751a5533bdc0a3b54c898e2e49e7751d0ee22cfb862679
```

## What was verified against the real upstream job and Dockerfile

- `hostPID: true` is genuinely required (unlike Falco in this same
  feature's `infrastructure/falco/`): kube-bench inspects the kubelet
  process's live command-line flags for several CIS controls.
- No `ServiceAccount`/`ClusterRole` is needed: the official `job-eks.yaml`
  uses none - kube-bench reads host files directly via the mounted
  `hostPath` volumes, making no Kubernetes API calls for this benchmark.
- `--targets node,policies,managedservices,controlplane --benchmark
  eks-1.5.0` is copied verbatim from the real upstream example for this
  exact kube-bench version; the `controlplane` target is intentionally
  included even on EKS - the `eks-1.5.0` benchmark's control-plane section
  checks customer-configurable settings (e.g. audit logging), not anything
  requiring direct access to the AWS-managed control plane itself.
- The image's own `ENTRYPOINT`/`CMD` (`entrypoint.sh install`) is
  intentionally bypassed by this manifest's explicit `command:`, matching
  the real upstream job, which does the same.

Refresh by re-running the same `imagetools inspect` command against a newer
tag, re-diffing this repo's `cronjob.yaml` against the current upstream
`job-eks.yaml`, and updating this file.

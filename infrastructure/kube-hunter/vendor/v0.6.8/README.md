# kube-hunter 0.6.8 image provenance

kube-hunter has no upstream raw-YAML installation bundle to vendor as a
whole; it publishes an example `job.yaml` directly in its repository
instead. This directory records image provenance; `infrastructure/
kube-hunter/cronjob.yaml` is adapted from that real job for this exact
version (source noted in the manifest's own comment), wrapped in a
`CronJob` for this feature's recurring-schedule requirement.

Source image:

```text
docker.io/aquasec/kube-hunter:0.6.8
```

Multi-platform digest (verified 2026-08-23 via
`docker buildx imagetools inspect aquasec/kube-hunter:0.6.8`):

```text
sha256:e64fe49f059f513a09c772a8972172b2af6833d092c06cc311171d7135e4525a
```

## What was verified against the real upstream job, Dockerfile, and README

- `command: ["kube-hunter"], args: ["--pod"]` is copied verbatim from the
  real upstream `job.yaml` for this exact version - internal/passive mode,
  no `--active` flag (which would attempt real exploitation, explicitly out
  of scope for this feature).
- Unlike Falco and kube-bench in this same feature, kube-hunter needs no
  host access at all: no `hostPID`, no `hostPath` mounts, no elevated Linux
  capabilities, and no `ServiceAccount`/`ClusterRole` - the real upstream
  job has none of these.
- The upstream image's Dockerfile has no `USER` directive (defaults to
  root), but kube-hunter's own README explicitly says the example job uses
  "default Kubernetes pod access settings" and suggests running as a
  non-root user as a safe modification - this manifest does exactly that
  (`runAsNonRoot`, dropped capabilities), backed by that explicit upstream
  suggestion, not an unverified guess.
- The Dockerfile's `tcpdump`/`ebtables` packages and the optional ARP/DNS
  spoof plugins are unrelated to the plain `--pod` hunt this feature uses;
  they are not invoked here.

Refresh by re-running the same `imagetools inspect` command against a newer
tag, re-diffing this repo's `cronjob.yaml` against the current upstream
`job.yaml`, and updating this file.

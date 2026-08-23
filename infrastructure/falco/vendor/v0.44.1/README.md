# Falco 0.44.1 and Falcosidekick 2.34.1 image provenance

Neither Falco nor Falcosidekick ship an upstream raw-YAML installation
bundle (both are normally installed via the `falcosecurity/charts` Helm
chart). This directory records image provenance only; manifests are
hand-authored in `infrastructure/falco/`, adapted from that chart's real
`values.yaml`/`pod-template.tpl` for this exact release (verified 2026-08-23
via the chart's `falco-9.1.0` tag, which packages Falco 0.44.1).

Source images:

```text
docker.io/falcosecurity/falco:0.44.1
docker.io/falcosecurity/falcosidekick:2.34.1
```

Multi-platform digests (verified via `docker buildx imagetools inspect`):

```text
falco:        sha256:d0cfe422d6ac0e0f20857798f46c7d7273210e1b064b22821e4e6e7f843cde6b
falcosidekick: sha256:d4f0d7c538ede3fe4a491143c45c0787bf4fc24e6fcac6d39dff6721d75a9419
```

## What was verified against the real Helm chart (not assumed)

- The modern eBPF driver's least-privileged mode grants exactly
  `[BPF, SYS_RESOURCE, PERFMON, SYS_PTRACE]`, never `privileged: true`
  (that combination is chart-reserved for the `kmod`/`auto` driver kinds
  this feature does not use).
- No `ClusterRole`/`ClusterRoleBinding` is needed for an explicit
  `modern_ebpf` driver choice - the chart only adds one for `driver.kind:
  auto`'s dynamic config-map fallback.
- The chart sets no `hostPID` anywhere for the Falco pod.
- `http_output`/`json_output` are the real config keys for forwarding to
  Falcosidekick; `SLACK_WEBHOOKURL` is Falcosidekick's real env var
  (confirmed in its own README) and `/healthz` is its real health endpoint.

Refresh by re-running the same `imagetools inspect` commands against newer
tags, re-diffing this repo's manifests against the current chart release,
and updating both this file and the `images:`/inline digests in
`infrastructure/falco/*.yaml`.

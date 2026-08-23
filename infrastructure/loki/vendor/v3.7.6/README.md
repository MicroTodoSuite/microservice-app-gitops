# Loki 3.7.6 and Grafana Alloy 1.18.1 image provenance

Neither Loki (single-binary mode) nor Grafana Alloy ship an upstream
raw-YAML installation bundle (both are normally installed via Helm charts).
This directory records image provenance only; manifests are hand-authored
in `infrastructure/loki/`.

Source images:

```text
docker.io/grafana/loki:3.7.6
docker.io/grafana/alloy:v1.18.1
```

Multi-platform digests (verified 2026-08-23 via
`docker buildx imagetools inspect`):

```text
loki:  sha256:efd47c67f9bac88ca29bcf8cb997d9ab29d1848bd0aff579282295542a745952
alloy: sha256:0f4434c92b3e6cdac38bb129b344e1790c246f7b6e2eaffcc16a5fa363240e33
```

`infrastructure/loki/config.yaml` is adapted from Loki's real
`cmd/loki/loki-local-config.yaml` reference config for this tag (retention
and storage paths changed, analytics reporting disabled). `infrastructure/
loki/alloy-config.yaml` follows Alloy's documented `loki.source.kubernetes`
+ `loki.process` + `loki.write` component pattern for shipping Kubernetes
pod logs without a privileged DaemonSet.

Refresh by re-running the same `imagetools inspect` commands against newer
tags and updating both this file and the `images:` transforms in
`infrastructure/loki/kustomization.yaml`.

# Grafana 13.2.0 image provenance

Grafana has no upstream raw-YAML installation bundle (it is normally
installed via its Helm chart or the Grafana Operator, both of which this
project's no-Helm convention avoids). This directory records image
provenance only; the actual `Deployment`/`Service`/`ConfigMap` manifests are
hand-authored in `infrastructure/grafana/`.

Source image:

```text
docker.io/grafana/grafana:13.2.0
```

Multi-platform digest (verified 2026-08-23 via
`docker buildx imagetools inspect grafana/grafana:13.2.0`):

```text
sha256:3fd54ae1214669f8355f065ec9f6445d5279a3d77095ab048ca045685272429b
```

Refresh by re-running the same `imagetools inspect` command against a newer
tag and updating both this file and the `images:` transform in
`infrastructure/grafana/kustomization.yaml`.

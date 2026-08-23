# Jaeger 2.20.0 image provenance

Jaeger v2 is built on the OpenTelemetry Collector core and ships as a single
binary/image (no separate collector/query/ingester images, no Jaeger
Operator needed for this scale). It has no upstream raw-YAML installation
bundle to vendor; this directory records image provenance only. The
`config-badger.yaml` referenced below is this project's own trimmed copy of
the real upstream all-in-one config for this exact tag (source noted in
`infrastructure/jaeger/jaeger-allinone.yaml`'s own comment), not a vendored
release artifact.

Source image:

```text
docker.io/jaegertracing/jaeger:2.20.0
```

Multi-platform digest (verified 2026-08-23 via
`docker buildx imagetools inspect jaegertracing/jaeger:2.20.0`):

```text
sha256:46a886260e04002d8f45e213fc39063fa11a50446048fdaa64786fc0840cb9f8
```

Refresh by re-running the same `imagetools inspect` command against a newer
tag and updating both this file and the `images:` transform in
`infrastructure/jaeger/kustomization.yaml`.

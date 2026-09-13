# Vendored Trivy Operator v0.34.0 (static bundle)

Unlike Falco, kube-bench, and kube-hunter, Trivy Operator publishes a raw-YAML
installation bundle, so this directory retains it unchanged and checksum-pinned,
the same way `infrastructure/prometheus/vendor/v0.18.0/` retains kube-prometheus
(spec 008 User Story 4, `specs/008-security-runtime-hardening/research.md`).

Source, at release tag `v0.34.0` (2026-08-24, the latest non-prerelease on
2026-09-13):

```text
https://github.com/aquasecurity/trivy-operator/blob/v0.34.0/deploy/static/trivy-operator.yaml
```

The release's own `checksums.txt` covers only the `trivy_operator_*` binary
archives, not this manifest, so `SHA256SUMS` was computed from the retained
file on 2026-09-13.

## Images

Multi-platform digests, verified on 2026-09-13 with
`docker buildx imagetools inspect`:

```text
mirror.gcr.io/aquasec/trivy-operator:0.34.0  sha256:0e4f11e9632f34097f259f3a59d34bab4eea8cee9aef510d15cdfc7481d5e49c
mirror.gcr.io/aquasec/trivy:0.74.0           sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969
```

`ghcr.io/aquasecurity/trivy:0.74.0` resolves to the same Trivy digest.

## What the Kustomize root changes

`infrastructure/trivy-operator/kustomization.yaml` leaves this file untouched
and, on the rendered output:

- retargets every namespaced resource to `security` and drops the bundle's
  `trivy-system` Namespace;
- sets `OPERATOR_NAMESPACE` and `OPERATOR_TARGET_NAMESPACES` in the container
  env, which the namespace transformer does not rewrite;
- keeps only the vulnerability scanner enabled and limits scanning to one Job
  at a time;
- pins the operator image by digest through `images:` and the Trivy scanner
  image by digest through `trivy.tag`, which the operator joins to
  `trivy.repository` as `repository:tag`;
- annotates the `trivy-operator` ServiceAccount, which scan Jobs also run as,
  with the read-only ECR role from `microservice-app-ops`;
- adds a startup probe on the operator's existing `/healthz/` endpoint.

## Refresh and verify

```bash
gh api -H "Accept: application/vnd.github.raw" \
  "repos/aquasecurity/trivy-operator/contents/deploy/static/trivy-operator.yaml?ref=v0.34.0" \
  > trivy-operator.yaml
sha256sum -c SHA256SUMS
```

Upgrade by retaining the new bundle in a sibling `vX.Y.Z` directory, recording
its checksum and image digests, and updating the Kustomize resource and patches.

# Argo Rollouts 1.9.1 vendor record

`install.yaml` is the unmodified upstream release asset from:

```text
https://github.com/argoproj/argo-rollouts/releases/download/v1.9.1/install.yaml
```

Verify it before rendering:

```bash
sha256sum -c SHA256SUMS
```

The root Kustomization replaces the controller tag with the reviewed immutable
multi-architecture index digest. The upstream file does not create its target
namespace, so `../../namespace.yaml` owns that resource explicitly.

# Velero

This Argo CD-owned root installs Velero v1.18.3 with the Microsoft Azure
object-store plugin v1.14.3 from a checksum-verified vendored render, and pins
both images to their immutable image-index digests (spec 012, FR-001 to FR-005).
It is provider-neutral: it renders no BackupStorageLocation,
VolumeSnapshotLocation, Schedule, Secret, or node agent. Every economical value
lives in `infrastructure/profiles/economical/velero/destinations/eks-dev`, the
only root any registration may activate, and only `clusters/eks-dev` may do so
(FR-014). See `docs/eco-velero-backups.md` for the credentials path and the
operator procedures.

## Versions

The plugin README's compatibility table at tag `v1.14.3` pairs plugin `v1.14.x`
with Velero `v1.18.x`. Both are the latest releases on 2026-09-22 (Velero
`v1.18.3`, published 2026-09-21; plugin `v1.14.3`, published 2026-09-21).

| Image | Tag | Index digest |
| --- | --- | --- |
| `velero/velero` | `v1.18.3` | `sha256:b839e52bc2c69eb3b5a84b010b8b3c7f714f3c5ef50b77ec7770a382a8f2e0ab` |
| `velero/velero-plugin-for-microsoft-azure` | `v1.14.3` | `sha256:77aa9463fba56325775264872ec0e7692e7e5fe693be701c219441401b6de973` |

The digests were read from Docker Hub with `crane digest` on 2026-09-22.

## Provenance of `vendor/v1.18.3/manifests.yaml`

The render is the byte-for-byte output of the official Velero CLI v1.18.3
(`velero-v1.18.3-linux-amd64.tar.gz`, SHA-256
`50012eda7424b0b94f53da563e2a48442d92a53c142c814b78e380a34139a98c`, matching the
release's `CHECKSUM` file):

```bash
velero install \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.14.3 \
  --no-secret --no-default-backup-location --use-volume-snapshots=false \
  --dry-run -o yaml > manifests.yaml
sha256sum -c SHA256SUMS
```

It holds the 13 `velero.io` CRDs, the `velero` Namespace, the `velero`
ServiceAccount and its ClusterRoleBinding, and the `velero` Deployment with the
Azure plugin as its only init container. `--provider` is omitted because the
installer rejects it together with `--no-default-backup-location` and
`--use-volume-snapshots=false`; the provider is a property of the destination
root's BackupStorageLocation. The render checksum was verified on 2026-09-22.

`--no-secret` keeps every Secret out of Git, and with it the installer also
drops its credentials wiring. `kustomization.yaml` restores exactly that
wiring from `pkg/install/deployment.go` at `v1.18.3` — the Secret
`cloud-credentials` mounted at `/credentials` with mode `0444`, and
`AZURE_CREDENTIALS_FILE=/credentials/cloud` — without editing the vendored
file. It also adds the platform sync-wave annotation and labels to the vendored
Namespace instead of declaring a second one, and lowers its Pod Security level
from the installer's `privileged` (needed only by the node agent's hostPath
mounts, which this root never renders) to `baseline`.

The vendored ClusterRoleBinding grants the `velero` ServiceAccount
`cluster-admin`, as every upstream Velero install does, because backup and
restore read and write every resource type.

Upgrading means rendering a new pinned version into a sibling `vX.Y.Z/` folder,
re-reading both digests, pointing `kustomization.yaml` at it, and re-running
`tests/platform/eco-velero.bats` and `tests/policy/eco-velero-credentials.bats`.

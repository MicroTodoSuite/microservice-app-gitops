# Implementation Plan: Velero Off-Provider Backups of the Economical Cluster

**Spec**: [spec.md](spec.md) · **Tasks**: [tasks.md](tasks.md) · **Companion**:
`microservice-app-ops` spec 005 (`specs/005-eco-off-provider-backups/`, branch
`test/eco-off-provider-backups`), which owns the Azure store, Velero's Azure
identity, the Secrets Manager container, and the IRSA role.

## Summary

ArgoCD installs Velero `v1.18.x` with the Azure plugin `v1.14.x` on the `eco`
cluster from a vendored, digest-pinned render. A destination root for `eks-dev`
adds the one BackupStorageLocation (`velero-eco` in `lexmtsecostbackups`,
Entra ID authorization only), the External Secrets path for Velero's credentials
file, and two Schedules. Nothing in Git holds a credential; nothing activates
until ops spec 005 is applied and a human writes the secret value.

## Technical context

| Item | Choice | Source |
| --- | --- | --- |
| Kustomize | v5, as the repository lock (kustomize 5.8.1, kubeconform 0.7.0 locally) | `AGENTS.md` |
| ArgoCD | v3.5.0, `infrastructure` ApplicationSet with an explicit list generator | `clusters/base/infrastructure.yaml` |
| External Secrets | v2.9.0, `external-secrets.io/v1`, AWS provider with JWT (IRSA) auth | `infrastructure/external-secrets`, `environments/base/secretstore.yaml` |
| Velero | Server `v1.18.x` (latest `v1.18.3`, 2026-09-21) | `vmware-tanzu/velero` releases |
| Azure plugin | `v1.14.x` (latest `v1.14.3`, 2026-09-21), compatible with Velero `v1.18.x` | Plugin README compatibility table at tag `v1.14.3` |
| Store | `lex-mts-eco-rg-backups` / `lexmtsecostbackups` / `velero-eco` | Ops spec 005 FR-001, FR-004 |
| Credentials | Secrets Manager `lex-mts-eco-sm-velero`, IRSA `lex-mts-eco-role-velerosec` for `system:serviceaccount:velero:velero-external-secrets` | Ops spec 005 FR-019, FR-020 |

## Repository layout

```text
infrastructure/velero/                                   # controller root (T004–T006)
  README.md                                              # provenance of the vendored render
  kustomization.yaml                                     # namespace + vendor + image digests
  namespace.yaml
  vendor/v1.18.<patch>/manifests.yaml                    # CRDs, RBAC, Deployment
infrastructure/profiles/economical/velero/destinations/eks-dev/   # destination root (T007–T010)
  kustomization.yaml
  backupstoragelocation.yaml
  external-secrets-serviceaccount.yaml
  secretstore.yaml
  externalsecret.yaml
  schedules.yaml
tests/platform/eco-velero.bats                           # render contract (T001)
tests/policy/eco-velero-credentials.bats                 # policy contract (T002)
docs/eco-velero-backups.md                               # operator document (T011)
```

The split mirrors `infrastructure/aws-load-balancer-controller` and
`infrastructure/profiles/economical/aws-load-balancer-controller/destinations/eks-dev`:
the controller stays provider-neutral, and every destination value lives in one
destination root.

## Design

### Controller

The vendored render comes from the official Velero Helm chart or from
`velero install --dry-run -o yaml` at the pinned version, with the Azure plugin as
its only init container, no node agent, and no default BackupStorageLocation or
VolumeSnapshotLocation. The README records the exact command (FR-005). The
`images:` block of the Kustomization pins both images by digest after the digest
is read from the registry at implementation time; the tag stays for readability.

The Deployment keeps Velero's default credentials wiring: the Secret
`cloud-credentials` is mounted at `/credentials`, and `AZURE_CREDENTIALS_FILE`
points at `/credentials/cloud`. Velero `v1.18.3`'s installer uses exactly these
names (`pkg/install/deployment.go`), so the External Secrets target matches it
without customization.

### Storage location

`storageAccountURI` is set so the plugin never calls Azure Resource Manager to
discover the endpoint; `resourceGroup` and `storageAccount` stay because the
plugin marks them required. `subscriptionId` is omitted: it is optional, it would
be an identifier in Git, and the credentials file already carries
`AZURE_SUBSCRIPTION_ID`.

### Credentials path

```text
human ──writes──▶ Secrets Manager lex-mts-eco-sm-velero   (ops FR-019)
                   │  IRSA lex-mts-eco-role-velerosec      (ops FR-020)
SecretStore aws-secrets-manager (velero) ◀── SA velero-external-secrets
                   │
ExternalSecret cloud-credentials ──▶ Secret cloud-credentials / key cloud
                                           │
                     Deployment velero mounts /credentials/cloud
```

The secret value is the plugin's credentials file for ops decision D1:
`AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`,
`AZURE_CLIENT_SECRET`, `AZURE_RESOURCE_GROUP`, and
`AZURE_CLOUD_NAME=AzurePublicCloud`. Rotation is a human write to Secrets
Manager; External Secrets refreshes the Secret, and Velero is restarted through a
reviewed commit only if the plugin does not re-read the file.

### Schedules

| Schedule | Cron (UTC) | Namespaces | Cluster resources | TTL |
| --- | --- | --- | --- | --- |
| `eco-daily` | daily, off the hour | the four `microtodo-*` environments | only those tied to included objects (Velero default) | `720h0m0s` |
| `eco-weekly` | weekly | `*` | `true` | `720h0m0s` |

Both exclude `secrets`, take no snapshot and no file-system backup, and set
`useOwnerReferencesInBackup: false`, because ArgoCD prunes a removed Schedule and
Velero would otherwise delete every backup it owns.

### Activation and lifecycle

Activation is one list element in `clusters/eks-dev/activation-infrastructure.yaml`
(name `velero`, path the destination root, namespace `velero`). It is a separate
commit (T012) because merging it changes a live environment, which conventions §6
reserves for a named human, and because it depends on ops spec 005 being applied.
While the economical activation lists are empty (runtime quiescence), T012 waits
for the reactivation (`feat/reactivate-economical-activation`, PR #227) to land.
The quiescence order gains Velero before External Secrets (T014).

## Verification strategy

- **Offline, every pull request**: the render contract and the policy contract,
  wired into `validate-gitops.yml` in the commit that introduces them.
- **Before implementation**: both contracts fail because neither root exists,
  which is the evidence of the first pull request.
- **Live, after activation**: the location's phase, the first backup's phase, and
  the objects in `velero-eco` (T013); a selective restore (T015).

## Documentation consulted (2026-09-22)

- `microsoft-learn` MCP, `microsoft_docs_search`: "Back up and restore workload
  clusters by using Velero" (AKS on Windows Server: credentials file variables
  `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`,
  `AZURE_CLIENT_SECRET`, `AZURE_RESOURCE_GROUP`, `AZURE_CLOUD_NAME`, and the
  `resourceGroup`/`storageAccount`/`subscriptionId` location settings);
  "Prevent Shared Key authorization for an Azure Storage account" (requests
  authorized with Shared Key fail with 403 once `allowSharedKeyAccess` is false);
  "Authorize access to blobs by using Microsoft Entra ID".
- `aws-knowledge` MCP, `search_documentation`: "IAM Roles for Service Accounts"
  (the `eks.amazonaws.com/role-arn` annotation and injected web identity).
- Vendor sources, because neither required documentation server covers Velero
  (permitted by `microservice-app-ai-agents/rules/mcp.md` when named):
  `vmware-tanzu/velero-plugin-for-microsoft-azure` README at `v1.14.3`
  (compatibility table, `Storage Blob Data Contributor` with `useAAD`) and
  `backupstoragelocation.md` (`useAAD`, `storageAccountURI`,
  `storageAccountKeyEnvVar`); `vmware-tanzu/velero` `v1.18` docs
  `api-types/schedule.md` (`useOwnerReferencesInBackup`, `ttl`,
  `includedNamespaces`, `excludedResources`) and
  `api-types/backupstoragelocation.md` (`credential`, `accessMode`, `default`);
  `pkg/install/deployment.go` at `v1.18.3` (`cloud-credentials`, `/credentials`,
  `AZURE_CREDENTIALS_FILE`); GitHub releases API for the latest versions.

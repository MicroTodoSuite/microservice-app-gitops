# Velero Off-Provider Backups of the Economical Cluster

Spec 012 (`specs/012-eco-velero-offsite-backups/`), companion of
`microservice-app-ops` spec 005, which owns every Azure and AWS resource named
here. The economical profile has no functional component in Azure: Azure holds
only the backup store, on the Azure for Students subscription (maintainer
decision, 2026-09-21).

## What runs where

| Piece | Where | Owner |
| --- | --- | --- |
| Velero v1.18.3 and the Azure plugin v1.14.3 | `infrastructure/velero` | ArgoCD (this repository) |
| Backup location, credentials path, schedules | `infrastructure/profiles/economical/velero/destinations/eks-dev` | ArgoCD (this repository) |
| Storage account `lexmtsecostbackups`, container `velero-eco`, resource group `lex-mts-eco-rg-backups` | Azure for Students | Terraform (ops spec 005 FR-001, FR-004) |
| Velero's Entra principal, `Storage Blob Data Contributor` on `velero-eco` | Microsoft Entra ID | Terraform (ops spec 005 FR-012, decision D1) |
| Secrets Manager container `lex-mts-eco-sm-velero` | AWS `us-east-1` | Terraform (ops spec 005 FR-019); value written by a human |
| IRSA role `lex-mts-eco-role-velerosec` | AWS IAM | Terraform (ops spec 005 FR-020) |

Only `clusters/eks-dev/activation-infrastructure.yaml` may activate the
destination root, and only in its own reviewed commit merged by a named human
(spec 012 T012). Until then nothing in this document runs.

## Credentials path

```text
human ──writes──▶ Secrets Manager lex-mts-eco-sm-velero   (ops FR-019)
                   │  IRSA lex-mts-eco-role-velerosec      (ops FR-020)
SecretStore aws-secrets-manager (velero) ◀── SA velero-external-secrets
                   │
ExternalSecret cloud-credentials ──▶ Secret cloud-credentials / key cloud
                                           │
                     Deployment velero mounts /credentials/cloud
                     (AZURE_CREDENTIALS_FILE)
```

The secret value is the Azure plugin's credentials file: one `NAME=value` line
per variable, stored as the plain-text value of `lex-mts-eco-sm-velero`. For
ops decision D1's recommended form, an Entra application with a client secret,
the variables are:

| Variable | Meaning |
| --- | --- |
| `AZURE_SUBSCRIPTION_ID` | The Azure for Students subscription |
| `AZURE_TENANT_ID` | Its Microsoft Entra tenant |
| `AZURE_CLIENT_ID` | Velero's application (client) ID |
| `AZURE_CLIENT_SECRET` | Velero's client secret |
| `AZURE_RESOURCE_GROUP` | `lex-mts-eco-rg-backups` |
| `AZURE_CLOUD_NAME` | `AzurePublicCloud` |

None of these values is ever committed, printed in a pull request, or pasted
into an issue. The storage account refuses Shared Key authorization (ops spec
005 FR-002), so the location sets `useAAD: "true"` and carries no account key,
SAS token, or subscription ID. `storageAccountURI` points the plugin straight
at `https://lexmtsecostbackups.blob.core.windows.net`, so Velero's principal
needs no Azure Resource Manager permission beyond its container role.

Neither the `velero` ServiceAccount nor the Velero pod has an AWS identity;
only `velero-external-secrets` reads AWS, and only that one secret.

## Rotation

1. Create the new client secret for Velero's Entra application (ops spec 005
   procedure) without deleting the old one.
2. A human writes the complete new credentials file to `lex-mts-eco-sm-velero`.
3. External Secrets refreshes `cloud-credentials` within its `refreshInterval`
   (1 hour).
4. Confirm the location stays `Available` (read-only check below). If the
   plugin keeps the old file, restart Velero through a reviewed commit that
   changes a pod-template annotation in the destination root; never with
   `kubectl rollout restart`.
5. Delete the old client secret in Entra ID.

## Latest successful backup (ops spec 005 FR-022)

Read-only; it lists the most recent `Completed` backup with its completion time:

```bash
kubectl -n velero get backups.velero.io \
  -o jsonpath='{range .items[?(@.status.phase=="Completed")]}{.status.completionTimestamp}{"\t"}{.metadata.name}{"\n"}{end}' \
  | sort | tail -1
kubectl -n velero get backupstoragelocations.velero.io default \
  -o jsonpath='{.status.phase}{"\n"}'
```

The economical `down` procedure records that name and time in its lifecycle
bundle. Backups written before `down` stay in `velero-eco`; after `up`, Velero's
backup sync lists them again.

## Selective restore used by the drill

The drill (spec 012 T015, ops spec 005 T030) restores one namespace of an
`eco-daily` backup into a scratch namespace, never over a live one:

```bash
velero restore create drill-<date> \
  --from-backup <eco-daily-backup-name> \
  --include-namespaces microtodo-dev \
  --namespace-mappings microtodo-dev:velero-drill-<date>
velero restore describe drill-<date> --details
```

A restore creates cluster objects outside Git, so it is run only as the
recorded drill or as a declared recovery, by a named human, and its scratch
namespace is removed when the evidence is recorded. The restored objects carry
no Secret (the schedules exclude `secrets`), so workloads that need one stay
pending until External Secrets provides it; that is expected.

## Schedules

| Schedule | Cron (UTC) | Scope | Retention |
| --- | --- | --- | --- |
| `eco-daily` | `30 2 * * *` | `microtodo-dev`, `microtodo-staging`, `microtodo-prod`, `microtodo-demo` | 30 days |
| `eco-weekly` | `0 4 * * 0` | every namespace and cluster-scoped resources | 30 days |

Both exclude Secrets, take no volume snapshot and no file-system backup, and set
`useOwnerReferencesInBackup: false`, so ArgoCD pruning a Schedule never deletes
its backups.

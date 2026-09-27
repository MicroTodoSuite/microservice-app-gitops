# Feature Specification: Velero Off-Provider Backups of the Economical Cluster

**Feature Branch**: `test/eco-velero-offsite-backups`

**Created**: 2026-09-22

**Status**: Draft — specification and failing contracts only

**Companion**: `microservice-app-ops` spec 005
(`specs/005-eco-off-provider-backups/`, branch `test/eco-off-provider-backups`),
which owns the Azure storage account, the Azure identity Velero writes with, the
AWS Secrets Manager container that holds Velero's credentials, and the IRSA role
External Secrets reads it with.

**Input**: The maintainer chose option A on 2026-09-21: the economical profile
keeps its optional cold disaster recovery in Azure as backup storage only.
The constitution's economical baseline names it — "optional cold DR via Velero
backups to an off-provider store in Azure, so that a lost AWS account does not
take the backups with it" — and ADR-0001 lists "Blob containers holding
Terraform state replicas and Velero backups of `eco`" under "Off-provider
backups". This specification is the GitOps half: Velero on the `eco` cluster,
installed and reconciled by ArgoCD, writing scheduled backups to the ops-owned
`velero-eco` container.

## Context

The `eco` cluster (`lex-mts-eco-eks-main`, registered as `clusters/eks-dev`) has
no cluster backup today. Every Kubernetes object it runs is either rendered from
this repository or produced in-cluster from AWS (External Secrets, the load
balancer controller), so a lost AWS account leaves nothing but Git to rebuild
from. Velero closes the gap the constitution names; ops spec 005 provides the
store, and this specification provides the controller, its storage location, its
credentials path, and its schedules.

Velero is a platform add-on, so constitution principle 11 makes ArgoCD its owner
and principle 2 forbids installing it any other way. Its credentials are a
secret, so principle 10 requires them to arrive through External Secrets.

## Clarifications

### Session 2026-09-22

- **Q**: Does this work belong in a new GitOps specification or in the tasks of
  ops spec 005?
  **A**: A new GitOps specification, this one. Three reasons. Constitution
  principles 2 and 11 make this repository the only source of desired cluster
  state and ArgoCD the owner of every add-on, so the tasks that change it belong
  to a register in this repository. Conventions §7 requires `tasks.md` to be
  updated in the same pull request that delivers a task, which a GitOps pull
  request cannot do for a register in `microservice-app-ops`. Conventions §8
  gives each repository its own pull request, each naming the other; ops spec
  005 already names this specification as `specs/012-eco-velero-offsite-backups/`.
- **Q**: Which Velero and plugin versions?
  **A**: Velero server `v1.18.x` with `velero-plugin-for-microsoft-azure`
  `v1.14.x`. The plugin's compatibility table at tag `v1.14.3` pairs `v1.14.x`
  with Velero `v1.18.x`; `v1.18.3` and `v1.14.3` are the latest releases on
  2026-09-22. Images are pinned by digest, never by tag alone.
- **Q**: How does Velero authenticate to Azure?
  **A**: Through Microsoft Entra ID, never a storage account key: the storage
  account refuses Shared Key authorization (ops spec 005 FR-002), and the
  BackupStorageLocation sets `useAAD: "true"`, which needs
  `Storage Blob Data Contributor` on the container (ops spec 005 FR-012). The
  credential type is ops decision D1; its recommended form is an Entra
  application with a client secret, whose credentials file reaches the cluster
  only through External Secrets.
- **Q**: Why does the BackupStorageLocation set `storageAccountURI`?
  **A**: Without it, the plugin fetches the blob endpoint through an Azure
  Resource Manager call on the storage account, which a principal scoped to one
  container cannot make. With it, Velero talks to the blob endpoint directly and
  its role assignment stays on the `velero-eco` container only.
- **Q**: How do the credentials reach the cluster?
  **A**: A human writes Velero's credentials file into the AWS Secrets Manager
  secret `lex-mts-eco-sm-velero` (ops spec 005 FR-019, PC-IAC-016). A
  namespace-scoped SecretStore in `velero` reads it through the IRSA role
  `lex-mts-eco-role-velerosec` (ops spec 005 FR-020), bound to the ServiceAccount
  `velero-external-secrets`, and an ExternalSecret writes it to the Secret
  `cloud-credentials`, key `cloud` — the Secret and key the Velero Deployment
  mounts at `/credentials/cloud` as `AZURE_CREDENTIALS_FILE`. No credential, key,
  subscription ID, or tenant ID is ever committed.
- **Q**: Which namespaces are backed up?
  **A**: The four economical environment namespaces, `microtodo-dev`,
  `microtodo-staging`, `microtodo-prod`, and `microtodo-demo`, daily; and every
  namespace with cluster-scoped resources, weekly, so that the ArgoCD and
  platform objects of a lost cluster can be inspected and restored selectively.
- **Q**: Are volumes backed up?
  **A**: No, not in this feature. No economical namespace declares a
  PersistentVolumeClaim, Redis is ephemeral by design (constitution principle
  12), and the cluster runs on AWS, so neither Azure disk snapshots nor the
  file-system node agent has anything to protect. The schedules set
  `snapshotVolumes: false` and `defaultVolumesToFsBackup: false`, and no
  node-agent DaemonSet is rendered. Decision G2 records it.
- **Q**: Do backups carry Secrets?
  **A**: No. Every Secret in `eco` is either produced by External Secrets from
  AWS Secrets Manager, which a human re-populates in a replacement account
  (PC-IAC-016), or generated in-cluster. The schedules exclude `secrets`, so the
  Azure store never holds a secret value. Decision G3 records it.
- **Q**: Where does Velero run, and where must it never run?
  **A**: Only on the `eco` cluster, through `clusters/eks-dev`. The full profile's
  recovery design is spec 009 user story 5 and does not include this root; no
  full-profile or AKS registration may reference it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Velero runs on eco, owned by ArgoCD, with the Azure plugin (Priority: P1)

A platform operator can rely on Velero being installed on the `eco` cluster by
ArgoCD alone, from a pinned, digest-addressed render, with the Azure object-store
plugin, and removed again by reverting the commit that activated it.

**Independent Test**: `tests/platform/eco-velero.bats` renders
`infrastructure/velero` and the `eks-dev` destination root offline and checks
the controller, the CRDs, the plugin, and the pinned digests.

**Acceptance Scenarios**:

1. **Given** the `infrastructure/velero` root, **When** it is rendered, **Then**
   it serves the Velero CRDs, the `velero` namespace, and one `velero`
   Deployment whose server image is `velero/velero:v1.18.x@sha256:...` and whose
   only plugin init container is
   `velero/velero-plugin-for-microsoft-azure:v1.14.x@sha256:...`.
2. **Given** the controller root, **When** it is rendered, **Then** it carries no
   BackupStorageLocation, no Secret, no Schedule, and no destination value, so
   it stays provider-neutral like every other controller root.
3. **Given** the activation of `eks-dev`, **When** Velero is activated, **Then**
   it is one element of the `infrastructure` ApplicationSet list pointing at the
   destination root, and no other cluster registration references Velero.

### User Story 2 - Credentials arrive only through External Secrets (Priority: P1)

A security reviewer can confirm that Velero's Azure credentials never touch Git:
they are read from AWS Secrets Manager by External Secrets through IRSA and
written in-cluster to the Secret Velero mounts.

**Independent Test**: `tests/policy/eco-velero-credentials.bats` scans the Velero
roots and their renders for secret material and checks that the only source of
`cloud-credentials` is an ExternalSecret.

**Acceptance Scenarios**:

1. **Given** the destination root, **When** it is rendered, **Then** it renders no
   `Secret`, and the ExternalSecret `cloud-credentials` maps the remote key
   `lex-mts-eco-sm-velero` to the Secret key `cloud` through the SecretStore
   `aws-secrets-manager`.
2. **Given** the SecretStore, **When** it authenticates, **Then** it uses the
   ServiceAccount `velero-external-secrets`, annotated with the IRSA role
   `lex-mts-eco-role-velerosec`; the `velero` ServiceAccount itself has no AWS
   role.
3. **Given** every tracked file of the Velero roots, **When** it is scanned,
   **Then** it contains no client secret, storage account key, SAS token,
   connection string, private key, or Azure subscription or tenant ID.

### User Story 3 - Scheduled backups land in the off-provider store (Priority: P1)

A platform operator can rely on scheduled backups of the economical namespaces
being written to the `velero-eco` container, retained for 30 days, and never
deleted as a side effect of ArgoCD pruning a Schedule.

**Independent Test**: the render contract checks the BackupStorageLocation and
both Schedules; after activation, T013 observes the location `Available` and one
`Completed` backup in the container.

**Acceptance Scenarios**:

1. **Given** the BackupStorageLocation `default`, **When** it is rendered,
   **Then** it uses provider `velero.io/azure`, bucket `velero-eco`, resource
   group `lex-mts-eco-rg-backups`, storage account `lexmtsecostbackups`,
   `storageAccountURI: https://lexmtsecostbackups.blob.core.windows.net`, and
   `useAAD: "true"`, with no key-based or SAS setting.
2. **Given** the Schedule `eco-daily`, **When** it fires, **Then** it backs up
   exactly the four economical environment namespaces to `default`, without
   Secrets or volumes, with `ttl: 720h0m0s`.
3. **Given** the Schedule `eco-weekly`, **When** it fires, **Then** it backs up
   every namespace with cluster-scoped resources, without Secrets or volumes,
   with `ttl: 720h0m0s`.
4. **Given** ArgoCD prunes a Schedule, **When** the Schedule is deleted, **Then**
   its backups remain, because `useOwnerReferencesInBackup` is `false`.

### User Story 4 - Velero follows the economical lifecycle (Priority: P2)

A platform operator can run the economical `down` and `up` transitions without
Velero blocking them or leaving the last backup unknown.

**Acceptance Scenarios**:

1. **Given** the dependency-cleanup phase of the runtime quiescence, **When**
   only External Secrets is retained, **Then** Velero was already removed, so no
   ExternalSecret of Velero's holds a finalizer against a departing controller.
2. **Given** an economical `down`, **When** it records the lifecycle bundle,
   **Then** the name and completion time of the latest successful backup are
   available to it (ops spec 005 FR-022), from `docs/eco-velero-backups.md`'s
   read-only procedure.

### Edge Cases

- The Secrets Manager secret is still empty: the ExternalSecret reports
  `SecretSyncedError`, the Deployment's volume is missing, and the location is
  `Unavailable`. The activation task (T012) therefore waits for the human write.
- The Azure tenant forbids app registrations (ops D1 risk): the credential type
  changes before activation; the External Secrets path stays.
- A new `eco` cluster after `up`: backups written before `down` remain in the
  container and are listed again by Velero's backup sync.
- Two clusters writing the same container: forbidden. Only `eks-dev` may
  activate this root.

## Requirements *(mandatory)*

### Functional Requirements

**Controller root (`infrastructure/velero`)**

- **FR-001**: `infrastructure/velero` MUST be a Kustomize root (not a
  Component) that renders the vendored Velero `v1.18.x` release: the `velero`
  namespace, the CRDs `backups`, `restores`, `schedules`,
  `backupstoragelocations`, `volumesnapshotlocations`, `deletebackuprequests`,
  `downloadrequests`, and `serverstatusrequests` in `velero.io`, the `velero`
  ServiceAccount and its RBAC, and the `velero` Deployment.
- **FR-002**: The Deployment's server container MUST use
  `velero/velero:v1.18.<patch>@sha256:<64 hex>` and it MUST have exactly one
  init container, `velero/velero-plugin-for-microsoft-azure:v1.14.<patch>@sha256:<64 hex>`.
- **FR-003**: The Deployment MUST mount the Secret `cloud-credentials` at
  `/credentials` and set `AZURE_CREDENTIALS_FILE=/credentials/cloud`.
- **FR-004**: The controller root MUST render no BackupStorageLocation,
  VolumeSnapshotLocation, Schedule, Secret, or node-agent DaemonSet.
- **FR-005**: The vendored render MUST record its provenance — the chart or CLI
  version and command that produced it — in the root's README, as the other
  vendored controllers do.

**Destination root (`infrastructure/profiles/economical/velero/destinations/eks-dev`)**

- **FR-006**: The destination root MUST compose `infrastructure/velero` and add
  only the `eks-dev` values: the BackupStorageLocation, the credentials path,
  and the Schedules.
- **FR-007**: The BackupStorageLocation `default` in `velero` MUST set
  `provider: velero.io/azure`, `default: true`, `accessMode: ReadWrite`,
  `objectStorage.bucket: velero-eco`, and `config` of exactly
  `resourceGroup: lex-mts-eco-rg-backups`, `storageAccount: lexmtsecostbackups`,
  `storageAccountURI: https://lexmtsecostbackups.blob.core.windows.net`, and
  `useAAD: "true"`; it MUST NOT set `storageAccountKeyEnvVar`, a SAS token key,
  or `subscriptionId`.
- **FR-008**: The destination root MUST render the ServiceAccount
  `velero-external-secrets` in `velero`, annotated
  `eks.amazonaws.com/role-arn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/lex-mts-eco-role-velerosec`,
  with the account from `config/aws-account.env`.
- **FR-009**: It MUST render the SecretStore `aws-secrets-manager`
  (`external-secrets.io/v1`) in `velero`, provider `aws`, service
  `SecretsManager`, region `us-east-1`, authenticated through
  `auth.jwt.serviceAccountRef.name: velero-external-secrets`.
- **FR-010**: It MUST render the ExternalSecret `cloud-credentials` in `velero`
  that reads `remoteRef.key: lex-mts-eco-sm-velero` through that SecretStore into
  `secretKey: cloud` of the target Secret `cloud-credentials`, with
  `creationPolicy: Owner` and a non-zero `refreshInterval`.
- **FR-011**: It MUST render the Schedule `eco-daily` with a daily cron
  expression, `template.includedNamespaces` of exactly `microtodo-dev`,
  `microtodo-staging`, `microtodo-prod`, and `microtodo-demo`, and the Schedule
  `eco-weekly` with a weekly cron expression, `includedNamespaces: ["*"]`, and
  `includeClusterResources: true`.
- **FR-012**: Both Schedules MUST set `template.storageLocation: default`,
  `template.ttl: 720h0m0s`, `template.snapshotVolumes: false`,
  `template.defaultVolumesToFsBackup: false`, `template.excludedResources`
  containing `secrets`, `useOwnerReferencesInBackup: false`, and
  `paused: false`.
- **FR-013**: The destination root MUST render no Secret and no
  VolumeSnapshotLocation, and the `velero` ServiceAccount MUST carry no
  `eks.amazonaws.com/role-arn` annotation.

**Ownership and activation**

- **FR-014**: Velero MUST be activated only by one element of
  `clusters/eks-dev/activation-infrastructure.yaml` whose `path` is the
  destination root and whose `namespace` is `velero`; no other file under
  `clusters/`, and no full-profile or AKS root under `infrastructure/profiles/full`
  or `environments/profiles/full`, MAY reference Velero.
- **FR-015**: Activating Velero MUST NOT be part of this feature's first
  implementation pull request; it is its own reviewed commit (T012), merged by a
  named human, after ops spec 005's storage and security roots are applied and
  the Secrets Manager value is written.
- **FR-016**: The economical runtime quiescence MUST remove Velero no later than
  the phase that retains External Secrets alone, and its contract MUST say so.

**Secret hygiene**

- **FR-017**: No tracked file under `infrastructure/velero`,
  `infrastructure/profiles/economical/velero`, or `clusters/` MAY contain an
  `AZURE_CLIENT_SECRET` value, an Azure subscription or tenant ID, a storage
  account key, a connection string, a SAS signature, or a private key.

**Documentation**

- **FR-018**: `docs/eco-velero-backups.md` MUST describe the credentials path,
  the rotation procedure, the read-only way to list the latest successful backup
  for ops spec 005 FR-022, and the selective restore used by the drill.

### Key Entities

- **Controller root** `infrastructure/velero`: the provider-neutral, vendored,
  digest-pinned Velero install.
- **Destination root** `infrastructure/profiles/economical/velero/destinations/eks-dev`:
  the only place the Azure location, the credentials path, and the Schedules live.
- **BackupStorageLocation** `default`: the ops-owned `velero-eco` container.
- **ExternalSecret** `cloud-credentials`: the only way the credentials file enters
  the cluster.
- **Schedules** `eco-daily` and `eco-weekly`.

## Success Criteria *(mandatory)*

- **SC-001**: `tests/platform/eco-velero.bats` passes offline (FR-001 to FR-013).
- **SC-002**: `tests/policy/eco-velero-credentials.bats` passes offline (FR-004,
  FR-007, FR-010, FR-013, FR-014, FR-017).
- **SC-003**: After activation, the Application `infra-velero` is Synced and
  Healthy, the location `default` is `Available`, and the first `eco-daily`
  backup is `Completed` with its objects in `velero-eco` (T013, observed).
- **SC-004**: One selective restore of a backup into a scratch namespace of
  `eco` succeeds, and ops spec 005 T030 records it in its drill.

## Decisions for the maintainer

- **G1 — New GitOps specification.** Recommended and taken in this draft; see the
  first clarification. The alternative, tasks in ops spec 005, would leave every
  GitOps pull request unable to update its own register.
- **G2 — No volume backups.** Recommended: no node agent and no snapshots until an
  economical namespace declares a PersistentVolumeClaim. Ops spec 005's recovery
  table lists "file-system volume data" under a 24-hour RPO; with no volume in
  `eco`, that row protects nothing, and the ops register should say so.
- **G3 — Backups without Secrets.** Recommended: exclude `secrets`, so the Azure
  store holds no secret value and a replacement account is re-populated by a human.
  The alternative stores the JWT secrets in Azure and makes the container a
  secret store in its own right.
- **G4 — Schedules and retention.** Recommended: `eco-daily` for the four
  environment namespaces and `eco-weekly` for the whole cluster, both kept 30 days
  (ops D5).
- **G5 — Namespace names.** Ops spec 005 user story 2 names the namespaces `dev`,
  `staging`, `prod`, and `demo`; the real economical namespaces are
  `microtodo-dev`, `microtodo-staging`, `microtodo-prod`, and `microtodo-demo`
  (`environments/*/kustomization.yaml`). This specification uses the real names;
  the ops text is a discrepancy to reconcile, not to edit silently.

## Out of Scope

- The Azure storage account, containers, identities, role assignments, the AWS
  Secrets Manager container and IRSA role (ops spec 005).
- Replicating Terraform state (ops spec 005 user story 1) and the restore drill's
  Terraform half (ops spec 005 T030).
- Velero on any full-profile or AKS cluster, and the ACR mirror (spec 009 US5).
- Volume snapshots and file-system backups (G2).
- A Velero backup taken automatically before every economical `down`.
- Any manifest, activation, or live change while this specification is in draft.

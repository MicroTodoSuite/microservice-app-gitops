---

description: "Task list for Velero off-provider backups of the economical cluster"
---

# Tasks: Velero Off-Provider Backups of the Economical Cluster

**Input**: Design documents from `specs/012-eco-velero-offsite-backups/`

**Prerequisites**: `spec.md`, `plan.md`; ops spec 005
(`microservice-app-ops` `specs/005-eco-off-provider-backups/`) for every Azure
and AWS resource named here.

**Tests**: Required. Both contracts are committed failing before T004 to T010,
and user story 3 needs observed live evidence (conventions §7.6).

**Organization**: Tasks are grouped by user story. Every path is in
`microservice-app-gitops`; prerequisites owned by `microservice-app-ops` are
named with their ops task and are ticked only in that repository.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: The user story the task belongs to (US1 to US4)

---

## Phase 1: Contracts (blocking)

> Commit both contracts failing, wired into `validate-gitops.yml`, before any
> manifest.

- [X] T001 [P] [US1] [US3] Add the failing render contract
  `tests/platform/eco-velero.bats`: `infrastructure/velero` and
  `infrastructure/profiles/economical/velero/destinations/eks-dev` render and
  pass `kubeconform -strict`; the controller root serves the `velero.io` CRDs,
  the `velero` namespace, and the `velero` Deployment with the digest-pinned
  `v1.18.x` server and the single digest-pinned `v1.14.x` Azure plugin init
  container, mounts `cloud-credentials` at `/credentials`, and sets
  `AZURE_CREDENTIALS_FILE=/credentials/cloud`; the controller root renders no
  location, Schedule, Secret, or DaemonSet; the destination root renders the
  BackupStorageLocation of FR-007, the IRSA ServiceAccount, SecretStore, and
  ExternalSecret of FR-008 to FR-010, and the Schedules of FR-011 and FR-012.
  Wire it into the `policy-contracts` job. Committed failing on 2026-09-22:
  both roots are absent.
- [X] T002 [P] [US2] [US4] Add the failing policy contract
  `tests/policy/eco-velero-credentials.bats`: both roots exist; their tracked
  files and renders carry no secret material (FR-017); no `Secret` is rendered;
  `cloud-credentials` comes only from an ExternalSecret; the location uses
  Entra ID only (FR-007); the `velero` ServiceAccount has no AWS role (FR-013);
  no registration other than `clusters/eks-dev`, and no full-profile or AKS
  root, references Velero (FR-014). Wire it into the `policy-contracts` job.
  Committed failing on 2026-09-22: both roots are absent.

---

## Phase 2: User Story 1 - Velero runs on eco, owned by ArgoCD, with the Azure plugin (Priority: P1)

**Goal**: A provider-neutral, vendored, digest-pinned Velero controller root.

**Independent Test**: the controller part of `tests/platform/eco-velero.bats`.

- [X] T003 [US1] Verify, at implementation time and through the documentation
  MCP servers or the vendor sources the pull request names, the Velero `v1.18.x`
  and plugin `v1.14.x` patch releases, their compatibility, and both image
  digests; record them in the pull request. Delivered 2026-09-22: Velero
  `v1.18.3` and plugin `v1.14.3` (compatibility table at plugin tag `v1.14.3`),
  index digests recorded in `infrastructure/velero/README.md` and PR #230.
- [X] T004 [US1] Vendor the Velero `v1.18.<patch>` render into
  `infrastructure/velero/vendor/v1.18.<patch>/manifests.yaml` (CRDs, RBAC,
  ServiceAccount, Deployment with the Azure plugin init container, no node agent,
  no default location), and record its provenance in
  `infrastructure/velero/README.md` (FR-001, FR-004, FR-005). Delivered
  2026-09-22: `vendor/v1.18.3/manifests.yaml` with `SHA256SUMS`, rendered by
  `velero install --no-secret` (the README records the command and why the
  credentials wiring is restored by a Kustomize patch).
- [ ] T005 [US1] Add `infrastructure/velero/namespace.yaml` and
  `infrastructure/velero/kustomization.yaml` with the `images:` digest pins of
  both images (FR-002, FR-003). Partial, not ticked: `kustomization.yaml`
  with both digest pins and the credentials wiring is delivered (2026-09-22),
  but there is no `namespace.yaml`: the vendored render already contains the
  `velero` Namespace, so a second one would collide, and `kustomization.yaml`
  patches the vendored one instead (sync wave, platform labels, Pod Security
  `baseline`). Ticking needs a maintainer to accept that in place of the named
  file, or to amend this task.
- [X] T006 [US1] Add the destination root
  `infrastructure/profiles/economical/velero/destinations/eks-dev/kustomization.yaml`
  composing the controller root (FR-006). Delivered 2026-09-22.

---

## Phase 3: User Story 2 - Credentials arrive only through External Secrets (Priority: P1)

**Goal**: Velero's credentials file reaches the cluster from Secrets Manager only.

**Independent Test**: `tests/policy/eco-velero-credentials.bats` and the
credentials part of the render contract.

**Prerequisites**: ops spec 005 FR-019 (`lex-mts-eco-sm-velero`) and FR-020
(`lex-mts-eco-role-velerosec`) exist in `microservice-app-ops`; the secret value is
written by a human.

- [X] T007 [US2] Add `external-secrets-serviceaccount.yaml`, `secretstore.yaml`,
  and `externalsecret.yaml` to the destination root (FR-008 to FR-010).
  Delivered 2026-09-22; nothing reaches the cluster until T012.

---

## Phase 4: User Story 3 - Scheduled backups land in the off-provider store (Priority: P1)

**Goal**: One Entra-only location and two retained Schedules.

**Independent Test**: the location and Schedule part of the render contract;
T013 after activation.

- [X] T008 [US3] Add `backupstoragelocation.yaml` to the destination root
  (FR-007). Delivered 2026-09-22.
- [X] T009 [US3] Add `schedules.yaml` with `eco-daily` and `eco-weekly` to the
  destination root (FR-011, FR-012). Delivered 2026-09-22.
- [ ] T010 [US3] Run both contracts green, `kubectl kustomize ... | kubeconform
  -strict -ignore-missing-schemas -summary` on both roots, and the existing
  `validate-gitops.yml` jobs; quote the output in the pull request. Partial,
  not ticked (2026-09-22): both contracts and both root renders pass, and every
  other job passes except `tests/platform/security-hardening.bats`, which
  derives the full-profile `require-immutable-images` namespaces from every
  root under `infrastructure/` and so demands `velero` in
  `infrastructure/profiles/full/kyverno`, which T002's contract forbids
  (FR-014). The two contracts conflict; a maintainer decides which changes
  (PR #230).
- [X] T011 [P] [US3] [US4] Write `docs/eco-velero-backups.md` (FR-018).
  Delivered 2026-09-22.
- [ ] T012 [US3] In its own commit and pull request, merged by a named human,
  add the `velero` element to `clusters/eks-dev/activation-infrastructure.yaml`
  (FR-014, FR-015). Preconditions: ops spec 005's workload and security roots are
  applied, the secret value is written, and the economical activation lists are
  active again (gitops PR #227 or its successor).
- [ ] T013 [US3] Observe and record in
  `docs/evidence/eco-velero-first-backup-<date>.md`: `infra-velero` Synced and
  Healthy, the location `default` `Available`, the first `eco-daily` backup
  `Completed`, and its objects listed in `velero-eco` (SC-003).

---

## Phase 5: User Story 4 - Velero follows the economical lifecycle (Priority: P2)

**Goal**: Velero never blocks `down`, and the last backup is always known.

- [ ] T014 [US4] Extend the economical runtime quiescence procedure and
  `tests/contract/economical-runtime-quiescence.sh` so Velero is removed no later
  than the phase that retains External Secrets alone (FR-016).
- [ ] T015 [US4] Run one selective restore of an `eco-daily` backup into a
  scratch namespace, record it in the evidence file of T013, and hand the result
  to ops spec 005 T030 (SC-004).

---

## Dependencies

- T001 and T002 precede T004 to T010.
- T003 precedes T004 and T005; T004 to T006 precede T007 to T009.
- T012 depends on T010, on ops spec 005 being applied, and on a human decision.
- T013 depends on T012; T015 depends on T013.

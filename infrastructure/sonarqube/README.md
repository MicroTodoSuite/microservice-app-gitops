# infrastructure/sonarqube (self-hosted SonarQube add-on)

Self-hosted **SonarQube** is the code-quality gate for **both** deployment
profiles (economical and full). This is a team decision that overrides the plan
§17 default (which mapped SonarCloud to the economical profile); see the GitOps
delivery spec, research decision D6
(`specs/003-reusable-cicd-delivery/research.md`).

## Why one instance serves both profiles

SonarQube is a **CI-time** tool: analysis runs in the GitHub Actions pipeline and
reports to a SonarQube **server** over the network. It is not per-environment, so
a **single** server serves every service and every environment. The economical
and full profiles differ only in *where* that server is hosted, not in the CI
contract — the reusable `ci.yml` always targets it via `SONAR_HOST_URL`.

## Ownership and status

- **Owner**: platform (ArgoCD-managed add-on), consistent with constitution
  principle 11 — same ownership as Istio/KEDA/Kyverno.
- **Status**: manifests present but **INACTIVE**. The shared infrastructure
  ApplicationSet has an empty activation default, and current cluster
  registrations omit `infrastructure/sonarqube`. The CI quality gate also stays
  visibly skipped until `sonar-host-url` is set.

## What's in this folder

- `namespace.yaml`, `serviceaccount.yaml`
- `db-secret.yaml` — ESO-generated PostgreSQL password (no secret in Git)
- `postgres.yaml` — PostgreSQL `16.15-alpine3.24` (Deployment + Service + 10Gi PVC)
- `sonarqube.yaml` — SonarQube `26.8.0.126808-community` (Deployment + Service +
  data/extensions PVCs), health on `/api/system/status`
- `pdb.yaml` — a PodDisruptionBudget per singleton
- `network-policy.yaml` — default-deny plus the exact DB/HTTP/DNS flows
- `backup-cronjob.yaml` — nightly `pg_dump` to a retained backup PVC
- `kustomization.yaml` — pins both images by the toolchain-lock digest

## Hardening (spec 009, T084) and what stays deferred

Done here, verified live on a local `kind` cluster (SonarQube reached "Web
Server is operational" running Community Edition 26.8.0.126808; PostgreSQL
16.15 Running; ESO generated the DB password; a manually triggered backup Job
produced a 5.4 MiB dump):

- **Digests pinned** to the exact toolchain-lock versions.
- **No privileged pod.** The old privileged `init-sysctl` container is gone.
  SonarQube's embedded Elasticsearch needs `vm.max_map_count >= 262144` at the
  NODE level; on a real full-dev cluster that comes from a Karpenter tooling
  NodePool's EC2NodeClass userData (Phase-4 work in
  `infrastructure/karpenter/node-provisioning/` — it needs the real cluster
  name), and the pods carry the matching
  `microtodosuite.io/tooling=sonarqube:NoSchedule` toleration. On the local
  kind node the default `vm.max_map_count` is already 262144, which is why the
  privileged container was safe to drop.
- **PodDisruptionBudgets, NetworkPolicy, backup CronJob** as described above.

Deferred to the activating registration (cloud-specific, cannot be expressed
in this provider-neutral base):

- The **gp3-encrypted retained StorageClass** overlay (`gp3` on EKS, the
  approved Azure Disk class on AKS) — the PVCs here use the cluster default.
- The **ingress/TLS exposure** so cloud CI runners can reach `:9000`.
- The **tooling NodePool + EC2NodeClass** (taint + `vm.max_map_count`
  userData) — belongs with Karpenter, Phase-4.

## Backup and recovery

`backup-cronjob.yaml` runs `pg_dump` nightly at 02:00 UTC to
`sonar-<timestamp>.sql.gz` on the `sonarqube-db-backup` PVC (retained
separately from the live DB volume), pruning dumps older than 14 days. Trigger
one on demand with `kubectl -n sonarqube create job --from=cronjob/sonarqube-db-backup <name>`.

To recover into a fresh, empty database:

```bash
# 1. Scale SonarQube down so nothing writes during restore.
kubectl -n sonarqube scale deploy/sonarqube --replicas=0
# 2. Copy the chosen dump out of the backup PVC (via a throwaway pod that
#    mounts it) and stream it back into PostgreSQL:
gunzip -c sonar-<timestamp>.sql.gz \
  | kubectl -n sonarqube exec -i deploy/sonarqube-postgres -- \
      psql -U sonar -d sonar
# 3. Scale SonarQube back up.
kubectl -n sonarqube scale deploy/sonarqube --replicas=1
```

The `pg_dump` step is verified live; the restore path above is the documented
procedure (a full restore drill belongs to the Phase-4 live acceptance run,
not this provider-neutral base).

## How to activate (on a tooling/management cluster)

1. Add an exact `sonarqube` entry to the intended tooling/management cluster's
   `activation-infrastructure.yaml`; do not change the shared empty default.
2. Add the deferred cloud-specific pieces (gp3 StorageClass overlay, ingress/
   TLS exposure, tooling NodePool) as registration-level patches — see the
   hardening section above; the digests are already pinned in `kustomization.yaml`.
3. Create a SonarQube token and set org var `SONAR_HOST_URL` + secret
   `SONAR_TOKEN`; the CI quality gate then activates for every service.

## Activation (value-only, like the ECR/registry switch)

1. Deploy the SonarQube server here (platform work) and expose it in-cluster.
2. Set the org/repo variable `SONAR_HOST_URL` to the server URL and the secret
   `SONAR_TOKEN` to a server token.
3. The reusable CI quality gate activates automatically for every service — no
   pipeline structural change (spec 003, FR-016).

## Resource note (why this is real infrastructure)

SonarQube is stateful and memory-heavy (JVM + embedded Elasticsearch, ~4 GiB RAM
recommended) and requires a PostgreSQL database, persistent volumes, and backups.
On the economical single cluster it is a large tenant; size the node/quota
accordingly.

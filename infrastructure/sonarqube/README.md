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
- `postgres.yaml` — PostgreSQL 16 (Deployment + Service + 10Gi PVC)
- `sonarqube.yaml` — SonarQube (Deployment + Service + data/extensions PVCs +
  `vm.max_map_count` init), health on `/api/system/status`
- `kustomization.yaml` — with the pre-activation TODOs (pin image digests, add
  Ingress/TLS exposure, confirm sysctl handling)

## How to activate (on a tooling/management cluster)

1. Add an exact `sonarqube` entry to the intended tooling/management cluster's
   `activation-infrastructure.yaml`; do not change the shared empty default.
2. Complete the `kustomization.yaml` TODOs (digests, exposure).
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

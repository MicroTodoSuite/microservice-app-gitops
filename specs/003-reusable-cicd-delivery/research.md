# Phase 0 Research: Reusable CI and GitOps Delivery

All decisions below resolve the Technical Context. No `NEEDS CLARIFICATION` markers remain; the three product-level decisions were fixed in the spec's Clarifications section.

## D1 — Reusable workflow architecture

- **Decision**: Use GitHub Actions `workflow_call` reusable workflows in the `.github` repo, consumed by each service via a thin caller. Parameterize by `service-name` and `language` inputs; factor repeated steps into composite actions (`setup-stack`, `sbom`, `sign`).
- **Rationale**: `workflow_call` is the native GitHub mechanism for centralization; a single edit propagates to all consumers (FR-002). Composite actions keep `ci.yml` readable and let per-language logic live in one place.
- **Alternatives considered**: (a) A shared action-only approach — rejected: harder to express job-level structure/gates. (b) A generator that writes per-repo workflows — rejected: reintroduces drift, the exact defect being removed.

## D2 — Reusable workflow versioning

- **Decision**: Consumers pin the reusable workflow by immutable ref: a release tag (`@v1`) that is itself a moving alias updated deliberately, plus optional commit-SHA pinning for high-assurance consumers. Document the pin policy.
- **Rationale**: Satisfies FR-005 (stable, auditable reference; no silent changes). Mirrors the repo's immutable-by-digest philosophy applied to workflow refs.
- **Alternatives considered**: `@main` — rejected: unreviewed edits would silently change every consumer.

## D3 — Registry now vs later (cloud-inactive)

- **Decision**: Publish to **GHCR** now (`ghcr.io/microtodosuite/<service>`), resolving and promoting by manifest **digest**. Design ECR as the destination behind an `ECR_REGISTRY_PLACEHOLDER`-style value; switching registries is a value change to the overlay `newName` and a workflow input. Never push a `latest` tag as deployment evidence.
- **Rationale**: GHCR needs no cloud account, supports OCI + Cosign keyless via GitHub OIDC, and lets the end-to-end build-once/promote flow be validated today (SC-009). Matches how task 3 left the gitops overlays.
- **Alternatives considered**: Wait for ECR — rejected: blocks all end-to-end validation on another team's task. Local registry only — rejected: doesn't exercise a hosted registry's digest semantics.

## D4 — Cloud authentication (credential-less)

- **Decision**: Design AWS auth as GitHub OIDC → IAM role (`aws-actions/configure-aws-credentials` with `role-to-assume`, `id-token: write`), no static keys. Keep the AWS steps gated behind a `push-to-ecr`/`cloud-enabled` input defaulting false until task 1 delivers the role. GHCR auth uses the built-in `GITHUB_TOKEN`.
- **Rationale**: FR-020 forbids static long-lived credentials; OIDC is the standard. Gating keeps the run green pre-infra (FR-021).
- **Alternatives considered**: Static `AWS_ACCESS_KEY_ID` secrets (the current Azure pattern) — rejected by constitution Principle 10.

## D5 — Supply-chain evidence (SBOM + signing)

- **Decision**: Generate SBOM with **Syft** (SPDX/CycloneDX) and attach it; sign the image **digest** with **Cosign keyless** (Fulcio/Rekor via GitHub OIDC). Both run on the active path with no pre-existing artifacts required.
- **Rationale**: FR-019; produces exactly what a later Kyverno `verifyImages` policy checks (FR-022). Keyless avoids managing signing keys.
- **Alternatives considered**: Cosign with a long-lived key pair — rejected: key management + static secret. Skip SBOM until ECR — rejected: SBOM is registry-independent.

## D6 — Quality gate: self-hosted SonarQube (both profiles)

- **Decision**: Use **self-hosted SonarQube** for **both** profiles (economical and full). One org-wide server (SonarQube is CI-time, not per-environment); the reusable `ci.yml` targets it via `SONAR_HOST_URL`, and the gate stays visibly skipped until the server exists (activated by value, like the ECR switch). The server is an ArgoCD-managed platform add-on scaffolded at `infrastructure/sonarqube/`. Trivy image scan remains a gate on the built image.
- **Rationale**: Team decision (2026-08-09), taken with the cost/ops trade-off understood: it prioritizes code staying in-house, custom rules, and one consistent tool across both profiles over the zero-infra convenience of SonarCloud.
- **Governance note**: This **overrides the plan §17 default** (SonarCloud for the economical profile). To keep SDD integrity, record the change in `microservice-app-docs` (§17 table) so the plan and implementation agree; the switch does not weaken design (it adds control/cost), so it is not the "move to the cost-optimized profile" that constitution principle 5 gates.
- **Alternatives considered**: SonarCloud (SaaS, zero infra, free for education) — the plan's economical default; rejected by the team in favor of a single self-hosted instance for both profiles. Kept trivially reachable: setting `sonar-host-url` empty would fall back to a hosted server, but the team chose self-hosted uniformly.

## D7 — Skippable gate mechanism

- **Decision**: Each test/contract gate is its own job guarded by a boolean input (`run-unit`, `run-integration`, `run-contract`, `run-e2e`, `run-perf`, `run-dast`) defaulting `false`. A skipped job appears in the run as skipped (visible, not absent). A job turned on with no artifacts fails fast with an explicit message (FR-017).
- **Rationale**: FR-013–FR-016; structurally complete, honest about what runs.
- **Alternatives considered**: Commenting gates out — rejected: not visible, structure lost. `continue-on-error` — rejected: hides real failures.

## D8 — Promotion PR mechanism (CI → gitops)

- **Decision**: `promote.yml` checks out gitops, runs the existing `scripts/bump-image.sh <service> dev <digest>` (digest-only, commit-only), and opens a PR with `peter-evans/create-pull-request`. Dev PR is automatic; staging/prod are separate PRs copying the identical digest. Prod merge is blocked by branch protection requiring approval. No cluster is touched.
- **Rationale**: Reuses the proven, constitution-compliant helper (FR-010); keeps GitOps-only (FR-009); satisfies build-once/same-digest (FR-006/FR-008).
- **Alternatives considered**: ArgoCD Image Updater auto-writeback — rejected: less reviewable than an explicit PR and weaker on the manual-prod-approval requirement. Direct commit to gitops main — rejected: bypasses review (Principle 3).

## D9 — Cross-repo PR authentication (least privilege)

- **Decision**: Use a dedicated **GitHub App** (or a fine-grained token) scoped to `contents:write` + `pull_requests:write` on `microservice-app-gitops` only, stored as an org secret consumed by `promote.yml`. Not a broad PAT.
- **Rationale**: FR-020 least privilege; the default `GITHUB_TOKEN` cannot open PRs in another repo.
- **Alternatives considered**: Classic PAT with `repo` scope — rejected: over-privileged. `GITHUB_TOKEN` — rejected: no cross-repo write.

## D10 — Digest resolution (build once)

- **Decision**: Build+push with `docker/build-push-action` and capture the pushed manifest digest from its `outputs.digest`; pass that digest to signing, SBOM subject, and the promotion PR. The digest is the single artifact identity across all environments.
- **Rationale**: Guarantees the promoted reference equals the built/signed artifact (FR-006/FR-011).

## D11 — semantic-release integration

- **Decision**: Keep semantic-release (already in every repo via `.releaserc`) in reusable `release.yml`; it computes version + changelog. The version is metadata/label; the **digest** remains the deployment identity. Successful release triggers `promote.yml`.
- **Rationale**: Preserves existing versioning (Assumption) while fixing the deploy path; avoids ripping out a working release mechanism.
- **Alternatives considered**: Replace semantic-release — rejected: unnecessary scope.

## D12 — Per-service technical facts (verified from source)

Extracted from Dockerfiles and application code:

| Service | Stack | Port (env) | Intrinsic health | Config keys (names) | Secret | Runtime deps |
| --- | --- | --- | --- | --- | --- | --- |
| auth-api | Go 1.23 | 8000 (`AUTH_API_PORT`) | `/version` | `AUTH_API_PORT`, `USERS_API_ADDRESS`, `ZIPKIN_URL?` | `JWT_SECRET` | users-api (login only; not for `/version`) |
| todos-api | Node 20 | 8082 (`TODO_API_PORT`) | `/metrics` (only unauth route) | `TODO_API_PORT`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_CHANNEL`, `ZIPKIN_URL?` | `JWT_SECRET` | Redis |
| users-api | Java 8 / Spring | 8083 (`SERVER_PORT`) | `/actuator/health` (or `/prometheus`) | `SERVER_PORT`, `SPRING_APPLICATION_NAME`, `ZIPKIN_URL?` | `JWT_SECRET` | none (in-mem H2) |
| frontend | Vue → nginx 1.27 | 8080 | `/` | `AUTH_API_ADDRESS`, `TODOS_API_ADDRESS`, `ZIPKIN_URL?` | none | auth-api, todos-api (nginx proxy) |
| log-message-processor | Python 3.11 | `PORT` (no default) | `/metrics` (prometheus http server) | `PORT`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_CHANNEL`, `ZIPKIN_URL?` | none | Redis |

- **Note (worker health)**: log-message-processor has no business HTTP API but *does* expose a Prometheus `/metrics` HTTP endpoint via `start_http_server(PORT)`. That endpoint is its intrinsic health path, resolving the "worker without endpoint" edge case (FR-026) without fabricating one.

## D13 — Shared JWT secret across services

- **Decision**: `auth-api`, `todos-api`, and `users-api` all read `JWT_SECRET` and must share the **same** value (tokens auth-api signs must verify in the others). Locally, provision one shared ESO `Password` source (one generated secret) referenced by all three overlays' ExternalSecrets, rather than three independent random secrets. Managed environments map all three to the **same** AWS Secrets Manager key via ESO.
- **Rationale**: Independent random secrets would make login-issued tokens fail verification downstream. Preserves the base Secret contract (`<svc>-secrets/JWT_SECRET`) while sharing the value.
- **Alternatives considered**: Per-service independent secrets — rejected: breaks cross-service JWT validation.

## D14 — Redis dependency for todos-api and log-message-processor

- **Decision**: Treat Redis as a shared local/platform dependency, **not** a business service. It is out of this feature's build/promotion scope. For managed environments Redis provisioning is platform work; for any local activation of todos/log-processor, document a minimal in-cluster Redis as a shared dependency (kept out of `apps/<svc>` per the onboarding contract's environment-owned rule). This feature onboards the service *definitions*; activating them locally (and thus needing Redis running) is optional and deferred.
- **Rationale**: Keeps managed overlays inactive scaffolds (FR-024); avoids expanding scope into infra. Business-service count/verification stays honest.
- **Alternatives considered**: Bundling Redis into todos-api base — rejected: violates the onboarding contract (shared dependency, not service-owned).

## D15 — gitops validation workflow

- **Decision**: Add `.github/workflows/validate-gitops.yml` in the gitops repo: `kustomize build` every overlay, `kubeconform` schema-validate, scan for committed secret literals and prohibited image tags/placeholders in active overlays. Runs on PR, no cluster credentials.
- **Rationale**: Closes task-3 validation gap #3; guards the onboarding of four services against drift; enforces the digest/secret rules in CI.
- **Alternatives considered**: Rely on manual `kustomize build` — rejected: not enforced.

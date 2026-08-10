# Quickstart: Validate Reusable CI + GitOps Delivery (no cloud)

This proves the feature works end to end **before** ECR/EKS/OIDC (task 1) or
Kyverno (task 2) exist. It validates structure, the build-once/promote flow via
GHCR, and the four service onboardings. It does not require an AWS/Azure account.

## Prerequisites

- The pilot prerequisites (`docs/local-pilot-quickstart.md`): docker, kind,
  kubectl, kustomize, git, jq.
- `act` (to dry-run reusable workflows locally) — optional but recommended.
- `cosign`, `syft`, `trivy`, `kubeconform` on PATH for the gate checks.
- Read access to the five service repos and write access to `.github` and gitops.

## 1. Reusable workflows render and lint (contract)

Expected: `ci.yml`, `release.yml`, `promote.yml` exist under `.github/workflows/`
and are valid reusable (`on: workflow_call`) workflows; composite actions exist
under `.github/actions/`.

```bash
# In the .github repo
actionlint .github/workflows/*.yml
# Confirm each declares workflow_call and the documented inputs/outputs.
```

Pass when: each workflow declares `workflow_call`, the inputs from
`contracts/reusable-ci-workflow.md`, and `ci.yml` exposes `image-digest`.

## 2. A service consumes the reusable workflow (US1)

Expected: each service repo's `.github/workflows/ci.yml` is a thin caller and the
legacy `development.yml` is gone.

```bash
# In a service repo
test ! -f .github/workflows/development.yml   # legacy removed (FR-027)
grep -q "uses: .*/.github/.github/workflows/ci.yml@" .github/workflows/ci.yml
```

Pass when: caller contains only `uses` + `with{service-name,language}` + secrets,
no build/test/deploy logic (SC-001).

## 3. Build-once + evidence via GHCR (US2/US5, active path)

Dry-run or run the active path for one service (e.g. auth-api):

```bash
act -W .github/workflows/ci.yml \
  --input service-name=auth-api --input language=go \
  --input registry=ghcr.io/microtodosuite
```

Pass when: exactly one image is built and pushed; a `sha256:` digest is emitted;
Trivy scan runs (blocking); a Syft SBOM and a Cosign keyless signature are
produced for that digest; no static cloud credential is used; the AWS/ECR leg is
skipped because `cloud-enabled=false` (SC-003/SC-007/SC-009).

## 4. Skippable gates are visible, not absent (US3)

Pass when: a run shows unit/integration/contract/e2e/perf/dast jobs as **skipped**
(default), while build/quality/scan/sbom/sign **ran**. Flip `run-unit=true` with
no tests present and confirm the job **fails visibly** (FR-017), not silently.

## 5. Promotion opens a scoped PR to gitops (US2)

```bash
act -W .github/workflows/promote.yml \
  --input service-name=auth-api --input environment=dev \
  --input image-digest=sha256:<64hex>
```

Pass when: the run invokes `scripts/bump-image.sh auth-api dev sha256:...`, opens
a PR against gitops changing only `apps/auth-api/overlays/dev/kustomization.yaml`,
and touches no cluster (FR-009/FR-012). Confirm staging/prod are separate PRs
copying the identical digest and that prod requires approval (SC-005).

## 6. Four services onboarded into gitops (US4)

For each new service, render and conformance-check:

```bash
# In the gitops repo
for s in todos-api users-api frontend log-message-processor; do
  kustomize build apps/$s/overlays/local | kubeconform -strict -ignore-missing-schemas -summary
done
```

Pass when: each renders; base is environment-neutral (no namespace/registry/
digest/replicas/resources in base); active overlays use a digest (not a tag);
managed overlays remain inactive scaffolds; log-message-processor uses `/metrics`
worker health; the three JWT services share one secret value (SC-008, D13).

## 7. gitops validation workflow (task-3 gap closed)

Pass when: `.github/workflows/validate-gitops.yml` runs `kustomize build` +
`kubeconform` + secret/tag scans on a gitops PR and fails on a committed secret
or a tag/placeholder in an active overlay.

## What is intentionally NOT validated here

- Real ECR push / EKS deploy / AWS OIDC (task 1) — legs designed but inactive.
- Kyverno signature verification / Falco / in-cluster scanning (task 2).
- Actual unit/integration/contract/e2e/perf/DAST tests and API contracts
  (deferred; gates scaffolded only).

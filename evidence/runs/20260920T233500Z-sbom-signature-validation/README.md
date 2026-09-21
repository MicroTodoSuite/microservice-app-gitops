# SBOM, keyless signature, and zero static credentials (T035)

Task **T035** of `specs/003-reusable-cicd-delivery`: validate that a build
produces an SBOM and a keyless signature for its digest, with zero static
credentials, and that the cloud leg is skipped when disabled.

## Reconciliation: the "cloud-enabled" toggle no longer exists

`quickstart.md` §3 describes an older design: a `cloud-enabled` input that
gates an optional AWS/ECR leg, defaulting to a GHCR-only dry run. Today's
`.github/workflows/ci.yml` has no such input (`grep -c cloud-enabled
ci.yml` = 0) -- once real AWS infrastructure existed (ops task 1), the
"cloud legs may not exist yet" design was retired, and every run
unconditionally publishes to the real ECR via OIDC. There is no longer a
disabled cloud leg to prove is skipped; the intent behind SC-007/SC-009 (no
static credential, signature/SBOM independent of the cloud leg's existence)
is validated below against the architecture as it actually exists now.

## Evidence: a real, recent push-to-main run

Audited `microservice-app-auth-api` run
[34875097673](https://github.com/MicroTodoSuite/microservice-app-auth-api/actions/runs/34875097673)
(`ci / supply-chain`, job
[104080217231](https://github.com/MicroTodoSuite/microservice-app-auth-api/actions/runs/34875097673/job/104080217231)),
2026-09-14T17:32Z -- the same commit that produced the
`sha256:b8aba84e88ec6593cd99631977664ed5ec1900fe80e0b98aa02404ff680abf8b`
digest promoted through dev/staging/prod audited in T021's evidence. Full
step log in `job-log.txt`.

| Check | Result |
| --- | --- |
| Exactly one image built | `containerimage.digest: sha256:7381a02b4fc8b6a0ba777a0d87ffdaf53ce302482b41eeadf373fc14f5215aaa` (buildx metadata, one digest) |
| SBOM produced | `anchore/sbom-action` step "Executing Syft..." ran and uploaded an artifact (`actions/upload-artifact`) |
| Keyless signature produced | Two Sigstore transparency-log entries recorded: `tlog entry created with index: 2833434947` and `...2833435053` (one for the SBOM attestation attach, one for the image signature), both through `sigstore/cosign-installer` -- no key material anywhere |
| Signature pushed | `Pushing signature to: 575172595729.dkr.ecr.us-east-1.amazonaws.com/microtodosuite/auth-api` |
| Zero static credentials | `aws-actions/configure-aws-credentials` step shows `role-to-assume: arn:aws:iam::575172595729:role/microtodosuite-github-ecr-publisher` -- an OIDC role assumption, not a stored key. `grep -n 'AWS_ACCESS_KEY_ID\|AWS_SECRET_ACCESS_KEY'` finds only GitHub's automatic `***` masking of the short-lived STS credentials the OIDC exchange minted for this run; no `secrets.AWS_*` reference exists anywhere in `ci.yml` (`grep -c 'secrets\.AWS' ci.yml` = 0) |
| Cloud leg | Unconditional (see reconciliation above); nothing to prove skipped |

## Result

| | |
| --- | --- |
| SBOM produced for the digest | pass |
| Keyless signature produced for the digest | pass |
| Static credential anywhere in the path | none found |
| Cloud-leg skip toggle | retired; cloud is now the only, unconditional path |
| Result | `pass` (against today's architecture; quickstart §3's literal `cloud-enabled` toggle is stale) |

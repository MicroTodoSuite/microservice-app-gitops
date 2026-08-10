# Contract: Gate Activation

Rules for turning a reusable-CI `run-<gate>` switch on in a service caller.

## Preconditions to enable a gate

1. The gate's artifacts exist in the repo and **pass locally** (tests green / contract lints + conforms / scan clean).
2. For coverage-bearing gates (unit), a coverage report is produced.
3. The change to flip the switch is a value-only edit in `<repo>/.github/workflows/ci.yml`
   (`run-<gate>: true`); the reusable workflow is never edited.

## Invariants

- **No green-but-empty gate**: enabling a gate without artifacts must fail visibly
  (the reusable gate already fails when enabled-but-empty). Verified once per service
  by intentionally enabling before artifacts and observing failure.
- **image-scan stays enforcing** at HIGH/CRITICAL for every service; it is never
  softened to make a build pass.
- **Contract drift fails**: after enabling `run-contract`, a deliberate breaking
  change must turn the gate red.

## Per-service order

`image-scan (already active, make green)` → `run-unit` → `run-contract` →
`run-integration` → stack-level `run-e2e` / `run-perf` / `run-dast`.

## Definition of done (per service)

- Trivy: zero fixable HIGH/CRITICAL (or documented exceptions only).
- Enabled gates all execute real artifacts and are green.
- Coverage produced and (once the SonarQube server exists) meets the threshold.
- One service (auth-api) additionally proves a full green pipeline run that opens
  the automated promotion PR.

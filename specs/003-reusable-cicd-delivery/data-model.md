# Phase 1 Data Model: Reusable CI and GitOps Delivery

These are the configuration/flow entities the feature manipulates. There is no runtime database; "entities" are the shapes of workflow inputs, artifacts, and desired-state records.

## Reusable CI Workflow (`.github/workflows/ci.yml`)

The single authoritative pipeline definition.

| Field | Type | Constraint |
| --- | --- | --- |
| `service-name` | input string | DNS-compatible; equals gitops `apps/<service>` and the neutral image key |
| `language` | input enum | one of `go` \| `node` \| `java` \| `python` (frontend uses `node`) |
| `dockerfile` | input string | default `Dockerfile` |
| `registry` | input string | default `ghcr.io/microtodosuite`; ECR value later |
| `cloud-enabled` | input bool | default `false`; gates OIDC-to-AWS + ECR push |
| `run-unit` / `run-integration` / `run-contract` / `run-e2e` / `run-perf` / `run-dast` | input bool | each default `false` (skippable gates) |
| `sonar-project-key` | input string | required for the code-quality gate |
| Secrets | `SONAR_TOKEN`, `GITOPS_APP_ID`/`GITOPS_APP_KEY` (or PR token) | least-privilege; provided by caller via `secrets: inherit` |
| Output `image-digest` | output string | `sha256:<64 hex>`; the single artifact identity |
| Output `image-ref` | output string | `<registry>/<service>@<digest>` |

**State/flow**: build → (active gates: quality, scan, SBOM, sign) → publish digest output. Skippable gates run only when their input is true; a true input with missing artifacts fails the job.

## Service Caller (`<service-repo>/.github/workflows/ci.yml`)

| Field | Type | Constraint |
| --- | --- | --- |
| `uses` | ref | `MicroTodoSuite/.github/.github/workflows/ci.yml@vX` (immutable pin, D2) |
| `with.service-name` | string | the service's name |
| `with.language` | enum | the service's stack |
| `secrets` | `inherit` | forwards org/repo secrets |

Constraint: contains **no** build/test/deploy logic (SC-001). Legacy `development.yml` is deleted (FR-027).

## Immutable Image Identifier

| Field | Type | Constraint |
| --- | --- | --- |
| `digest` | string | `sha256:` + 64 lowercase hex; from registry manifest (D10) |
| `registry` | string | environment-owned (`newName`); never in base |
| `ref` | string | `<registry>/<service>@<digest>`; the only deployable reference |

Rejected values: any tag, `latest`, image ID, or the all-zero placeholder (enforced by `bump-image.sh`).

## Promotion Pull Request

| Field | Type | Constraint |
| --- | --- | --- |
| `service` | string | target `apps/<service>` |
| `environment` | enum | `dev` (auto) \| `staging` \| `prod` (manual approval) |
| `digest` | string | identical across environments for one release |
| `target-repo` | string | `microservice-app-gitops` |
| `change-scope` | invariant | modifies only that service's overlay `kustomization.yaml` |
| `approval` | policy | `prod` requires branch-protection approval before merge |

Invariant: opening/merging a promotion PR never mutates a cluster (FR-009).

## Quality / Supply-Chain Gate

| Field | Type | Constraint |
| --- | --- | --- |
| `category` | enum | unit, quality, image-scan, sbom, sign, integration, contract, e2e, perf, dast |
| `active-by-default` | bool | true for {build, quality, image-scan, sbom, sign}; false otherwise |
| `blocking` | bool | active gate failure blocks promotion |
| `visibility` | enum | `run` \| `skipped` (never absent) |

## Supply-Chain Evidence

| Field | Type | Constraint |
| --- | --- | --- |
| `sbom` | artifact | Syft SPDX/CycloneDX, subject = image digest |
| `signature` | artifact | Cosign keyless (Fulcio/Rekor), subject = image digest |
| `verifiable-by` | reference | future Kyverno `verifyImages` (out of scope, FR-022) |

## Service Delivery Definition (gitops)

Per onboarded service, following `service-onboarding-contract.md`:

| Field | Owner | Source (verified) |
| --- | --- | --- |
| service name, port, health path, config-key names, secret interface | base | D12 table |
| topology component (economical/full) | components | reuse auth-api pattern |
| namespace, replicas, capacity, registry `newName`, digest | overlay | environment-owned |
| local secret source (shared JWT via ESO) | local overlay | D13 |
| managed overlays | scaffold | inactive until registration selects (FR-024) |

## Technology Profile

| Value | Build | Test tooling (when gates on) |
| --- | --- | --- |
| `go` | `go build` (auth-api) | `go test`, coverage |
| `node` | `npm ci` (todos-api, frontend) | Jest |
| `java` | Maven package (users-api) | JUnit |
| `python` | pip/venv (log-message-processor) | pytest |

Image build itself is uniform via `docker buildx` against each repo's Dockerfile; only test/lint differ by profile.

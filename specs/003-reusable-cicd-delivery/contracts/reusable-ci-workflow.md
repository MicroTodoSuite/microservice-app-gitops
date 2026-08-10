# Contract: Reusable Workflows (`.github`)

Three reusable `workflow_call` workflows. Consumers reference them by immutable pin (`@vX`). All inputs/outputs are stable; adding an input must be backward compatible.

## `ci.yml`

**Inputs**

| Name | Type | Default | Required | Meaning |
| --- | --- | --- | --- | --- |
| `service-name` | string | — | yes | Service identity; matches `apps/<service>` and image key |
| `language` | string | — | yes | `go` \| `node` \| `java` \| `python` |
| `dockerfile` | string | `Dockerfile` | no | Build file path |
| `registry` | string | `ghcr.io/microtodosuite` | no | Image destination host/namespace |
| `cloud-enabled` | boolean | `false` | no | Enable OIDC-to-AWS + ECR push leg |
| `sonar-project-key` | string | — | no* | Required when quality gate runs |
| `run-unit` | boolean | `false` | no | Enable unit+coverage gate |
| `run-integration` | boolean | `false` | no | Enable Testcontainers gate |
| `run-contract` | boolean | `false` | no | Enable Spectral/Pact gate |
| `run-e2e` | boolean | `false` | no | Enable Cypress/Playwright gate |
| `run-perf` | boolean | `false` | no | Enable Locust gate |
| `run-dast` | boolean | `false` | no | Enable OWASP ZAP gate |

**Secrets**: `SONAR_TOKEN` (quality gate), `GITOPS_PROMOTE_APP_ID` + `GITOPS_PROMOTE_APP_KEY` (or `GITOPS_PROMOTE_TOKEN`) forwarded to promotion. `id-token: write` permission required for keyless signing and (when enabled) AWS OIDC.

**Outputs**

| Name | Meaning |
| --- | --- |
| `image-digest` | `sha256:<64 hex>` of the pushed manifest |
| `image-ref` | `<registry>/<service-name>@<digest>` |

**Job order (active path bold)**: **checkout** → **setup-stack(language)** → unit? → **quality (Sonar)** → **build+push (buildx, digest out)** → **image-scan (Trivy, blocking)** → **sbom (Syft)** → **sign (Cosign keyless)** → integration? / contract? / e2e? / perf? / dast? → publish outputs.

**Invariants**: no cluster mutation; no `latest` as evidence; a `true` gate with missing artifacts fails; unsupported `language` fails at setup-stack.

## `release.yml`

**Inputs**: `node-version` (default 22). **Secrets**: release token.
**Behavior**: run semantic-release → version + changelog + tag. **Output**: `released` (bool), `version`.

## `promote.yml`

**Inputs**

| Name | Type | Required | Meaning |
| --- | --- | --- | --- |
| `service-name` | string | yes | Target `apps/<service>` |
| `environment` | string | yes | `dev` \| `staging` \| `prod` |
| `image-digest` | string | yes | `sha256:...` to write |
| `gitops-repo` | string | no | default `MicroTodoSuite/microservice-app-gitops` |

**Secrets**: `GITOPS_PROMOTE_*` (least-privilege: contents+PR write on gitops only).

**Behavior**: clone gitops → `scripts/bump-image.sh <service> <env> <digest>` → open PR. `dev` auto-opened after CI; `staging`/`prod` opened on request; `prod` cannot merge without approval (branch protection).

**Invariants**: modifies only `apps/<service>/overlays/<env>/kustomization.yaml`; never pushes to a cluster; rejects a digest not produced by CI.

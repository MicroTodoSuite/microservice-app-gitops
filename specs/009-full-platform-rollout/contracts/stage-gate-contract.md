# Stage Gate Contract

## Purpose

Prevent a full-profile stage from advancing on configuration-only evidence or at the expense of the economical platform.

## Required Inputs

Each stage declares:

- immutable `stage_id`, dependency stage IDs, repositories, Terraform states, clusters, namespaces, and capabilities in scope;
- pre-stage economical Git revision, ArgoCD revision/Application health, workload readiness, endpoint checks, and Terraform drift status;
- authenticated cloud identities and current quotas;
- exact saved Terraform plan and `terraform show -json` output when cloud resources change;
- Infracost output, a numeric cost ceiling, and comparison against that ceiling, or an explicit human cost acceptance;
- all availability reductions, including centralized egress and single-bootstrap-node reliance;
- rollback trigger, owner, exact Git/state action, expected duration, and verification commands;
- required success, failure-mode, and post-stage baseline tests.

## Mandatory Rules

1. AWS identity must be account `916491575487`; the Azure subscription must equal the authenticated approved value.
2. Every Terraform plan must use the correct initialized remote backend, a saved plan file, and current refresh. A failed or inaccessible backend is `blocked`, never clean.
3. An unexpected destroy, replacement, singleton creation, control-plane `0.0.0.0/0`, duplicate state key, quota excess, or unaccepted cost excess is `blocked`.
4. Dev-owner compatibility work cannot proceed to any consumer environment until dev reports exactly `0 to add, 0 to change, 0 to destroy`.
5. A cloud-resource apply may use only the reviewed saved plan after an external timestamped state backup under `~/backups-microtodosuite/` and explicit approval. A new plan invalidates the approval. A genuinely empty/new state records a signed `no-prior-state` receipt in that directory instead of inventing a backup.
6. Post-bootstrap Kubernetes changes must be merged GitOps desired state. Direct `kubectl apply/create/patch/delete/scale` is a gate failure.
7. Desired state, live healthy behavior, controlled failure behavior, rollback, and the unchanged economical baseline must all pass.
8. A stage may be `accepted` only when its JSON bundle validates against `full-profile-evidence.schema.json` and all referenced artifact checksums match.
9. The final active-active plan is blocked until `microtodosuite.online` is delegated to the exact Terraform-owned Route 53 name servers, both production ingresses already present trusted certificates for `app.microtodosuite.online`, the AKS ingress binding matches the Terraform-owned static public-IP outputs, and DNS-01 trust/permissions tests prove exact subjects and ACME-TXT-only scope.
10. Azure workload activation is blocked until the OIDC seed run proves the exact approved secret-name inventory, an in-process AWS/Azure production-JWT equality result, no Terraform-managed Key Vault values, no static credential, and no value-bearing log, digest, cache, artifact, plan, state, or evidence output.
11. A full EKS capability cannot activate until every referenced third-party image is locked by upstream digest, mirrored to `microtodosuite/platform`, scanned, and signed by the exact approved platform-mirror workflow identity. AKS capability activation additionally requires the complete signed ECR graph in ACR with equal manifest digests and no mutable or unmirrored reference.

## Decisions

| Decision | Meaning | May unlock dependents? |
| --- | --- | --- |
| `pending` | Evidence is still being collected. | No |
| `approved` | Human approval exists for the exact reviewed inputs; execution/evidence remains. | No |
| `accepted` | All mandatory evidence passes. | Yes |
| `blocked` | A mandatory prerequisite or check is missing/failing. | No |
| `rejected` | Scope, cost, risk, or trade-off was not accepted. | No |
| `rolled-back` | The stage was reversed and the baseline was revalidated. | No; requires a new gate instance. |

## Minimum Artifact Set

```text
evidence/runs/<timestamp>-<stage-id>/
├── evidence.json
├── baseline/
│   ├── git-revisions.json
│   ├── economical-argocd.json
│   ├── economical-workloads.json
│   ├── economical-http.json
│   └── terraform-drift.txt
├── identity/
│   ├── aws.json
│   └── azure.json                 # when Azure is in scope
├── infrastructure/
│   ├── backend.json
│   ├── quotas.json
│   ├── plan.txt                  # redacted human-readable actions/counts only
│   ├── plan-summary.json          # redacted addresses/actions/counts only
│   ├── infracost.json
│   ├── ownership.json
│   └── state-backup.json
├── desired/
│   ├── gitops-render.txt
│   └── revisions.json
├── live/
│   ├── applications.json
│   ├── workloads.json
│   └── functional.json
├── failure/
│   └── results.json
├── rollback/
│   └── results.json
└── post-baseline/
    └── economical.json
```

Secret values, tokens, kubeconfigs, private keys, state files, binary plans, full unredacted plan JSON, and unredacted provider configuration are forbidden in Git evidence. Full plans/state backups remain external; Git records only their SHA-256, storage location reference, resource addresses/actions/counts, and redacted outputs.

# Foundational compatibility evidence — 20260824T233346Z

Stage 2 of `specs/009-full-platform-rollout`. Produced by
`scripts/managed/collect-foundational-evidence.sh`, which runs every gate,
plans against the real dev backend, and reads live cluster state. It never
applies.

## Result: `blocked`

The two gates this stage owns both pass. The stage is blocked only on a
pre-existing live defect it did not cause.

| Gate | Result |
| --- | --- |
| 10 foundational test suites (gitops + ops) | pass |
| Refreshed dev plan — `0 to add, 0 to change, 0 to destroy` | pass |
| Live ArgoCD health | **degraded — 37/39 synced, 38/39 healthy** |

## Why the plan is genuinely clean

`infrastructure/dev-plan-summary.json` records zero changed resources, derived
from the plan JSON rather than from its printed text. The only diff is the
`foundation_contract` **output**, which stores a richer reviewable inventory and
changes no infrastructure.

The full plan text is not committed. Only its SHA-256 and the redacted counts
are, because a plan can echo tagged resource contents.

## The three live exceptions

| Application | State | Cause | Owner |
| --- | --- | --- | --- |
| `env-demo` | Degraded | The `demo` environment exists in GitOps but not in the ops foundation, so `microtodosuite/demo/auth-api-secrets` does not exist and its ExternalSecret reports `SecretSyncedError`. | Infrastructure |
| `infra-loki` | OutOfSync (Healthy) | `StatefulSet/loki` differs from desired state after the compactor fix. | Observability |
| `infra-prometheus` | OutOfSync (Healthy) | Service monitors differ from desired state. | Observability |

None is attributable to this stage: every change in it is Terraform that has
not been applied, plus GitOps composition whose economical renders are proven
byte-identical.

`env-demo` is the actionable one. The demo environment was added to GitOps in
`microservice-app-gitops#56` without the matching `shared_environments` entry in
`microservice-app-ops`, so no JWT secret or reader role was ever created for it.
The remedy is a reviewed one-line `dev.tfvars` change plus its own approved
apply; it is deliberately not folded into this stage, because it would stop the
dev plan being clean and destroy the very property this stage exists to prove.

## Reproducing

```
scripts/managed/collect-foundational-evidence.sh --external-dir <dir> --kube-context <context>
```

Re-run it after the `env-demo` remedy is applied to obtain an `approved`
decision.

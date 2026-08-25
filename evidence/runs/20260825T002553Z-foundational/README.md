# Foundational compatibility evidence — 20260825T002553Z

Stage 2 of `specs/009-full-platform-rollout`. Produced by
`scripts/managed/collect-foundational-evidence.sh`, which runs every gate, plans
against the real dev backend, and reads live cluster state. It never applies.

## Result: `approved`

| Gate | Result |
| --- | --- |
| 10 foundational test suites (gitops + ops) | pass |
| Refreshed dev plan | pass — `0 to add, 0 to change, 0 to destroy` |
| Live economical platform health | pass — 39/39 healthy |

The dev plan is now clean with **no output diff either**: the richer
`foundation_contract` inventory was persisted during the `env-demo` apply, so
this run shows a completely empty change set.

The full plan text is not committed. Only its SHA-256 and the redacted counts
are, because a plan can echo tagged resource contents.

## Supersedes the blocked run

`../20260824T233346Z-foundational/` recorded `blocked` on the same gates. That
run is kept deliberately: it is the evidence that the live gate caught a real
defect rather than waving the stage through.

It found `env-demo` Degraded because the demo environment existed in GitOps
(`microservice-app-gitops#56`) but never got its JWT secret in the ops
foundation. The remedy — `microservice-app-ops#25`, adding `demo` to
`shared_environments` — was reviewed, applied as its own exact plan
(`4 to add, 0 to change, 0 to destroy`), and the ExternalSecret reached
`SecretSynced` on the next reconcile.

## Remaining platform advisories

`infra-loki` and `infra-prometheus` are `OutOfSync` but **Healthy**, from an
immutable `StatefulSet` field that ArgoCD will not reconcile automatically. They
are recorded as attributed advisories, not as this stage's verdict: they belong
to the platform add-on owner and predate this work.

The verdict is scoped to the economical platform — the business services and
environment policy applications — because that is the rollback target the
rollout must never regress, and the only thing this stage could plausibly have
broken. One degraded service or environment still blocks the stage.

## Reproducing

```
scripts/managed/collect-foundational-evidence.sh --external-dir <dir> --kube-context <context>
```

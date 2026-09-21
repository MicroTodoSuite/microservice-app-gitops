# Promotion validation (T021)

Task **T021** of `specs/003-reusable-cicd-delivery`: validate that promotion
via `promote.yml` is digest-identical across dev/staging/prod, each promotion
PR is scoped to exactly one overlay, concurrent promotions do not collide, and
no CI step mutates a cluster.

This is a **read-only audit of the fifteen promotion pull requests
`promote.yml` actually opened and GitHub actually merged** on 2026-09-14 for
the five-service economical release (`gitops#150`-`#164`), not a freshly
staged drill. The org already ran the real thing; re-running it purely to
produce a new artifact would be wasted signal.

## Digest identity across dev → staging → prod

| Service | Dev PR | Staging PR | Prod PR | Digest |
| --- | --- | --- | --- | --- |
| auth-api | [#150](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/150) | [#152](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/152) | [#160](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/160) | `sha256:b8aba84e88ec6593cd99631977664ed5ec1900fe80e0b98aa02404ff680abf8b` |
| todos-api | [#151](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/151) | [#154](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/154) | [#164](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/164) | `sha256:82d121a8741b794b4a8b2e07483af55de1d6de148d496de5480e39e972cc11ad` |
| frontend | [#153](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/153) | [#156](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/156) | [#163](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/163) | `sha256:ff9f348fe90afc3438c77b29aa6a61595dd6733b4c9975a4e4e3f2656e814b85` |
| log-message-processor | [#155](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/155) | [#157](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/157) | [#162](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/162) | `sha256:b6bc3d24b1d96be4423e94e10655aee79e4df36388fa1d3f5387ca8d375a9684` |
| users-api | [#158](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/158) | [#159](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/159) | [#161](https://github.com/MicroTodoSuite/microservice-app-gitops/pull/161) | `sha256:82c4ea7911297129da943a5b7f8ae95e42cc40bb7689e856cb5f067faef67aa1` |

Every row's three PRs carry the exact same digest. Retrieved from each PR's
own title via `gh pr list --state merged --search "promote in:title"`
(`raw-merged-promotions.json`), and independently confirmed against the
actual committed content of each of the fifteen `kustomization.yaml` files
(`gh pr diff <n>` for every PR, saved verbatim in `all-diffs.txt`): the
`+    digest: sha256:...` line merged into each file matches its PR's title
exactly, for all fifteen. A title could in principle differ from what was
actually merged; the diff content is what was actually merged, and it agrees.
No digest was rebuilt between dev, staging, and prod.

## Each PR scoped to exactly one overlay

`gh pr view <n> --json files` for all fifteen PRs (`raw-files-by-pr.txt`)
shows each PR changes exactly one file:
`apps/<service>/profiles/economical/overlays/<env>/kustomization.yaml`. The
fifteen file paths are pairwise distinct across the fifteen PRs -- no two
promotion PRs ever touched the same file. `gh pr diff 153` (`sample-diff.txt`)
shows the change itself is a single-line digest replacement, nothing else.

## Concurrent promotions do not collide

All fifteen PRs merged within a sixteen-minute window (18:30:10Z-18:44:35Z on
2026-09-14, per each PR's `mergedAt`). Because every PR's diff is confined to
its own service+environment file (previous section), fifteen concurrent
merges produced zero conflicts and zero collisions by construction: there is
no shared file for two promotions to race on.

## Zero cluster mutation

Structural, not per-PR: `grep -rl 'kubectl apply|kubectl patch|kubectl scale'
.github/workflows/ tests/ scripts/` matches only
`scripts/managed/bootstrap-cluster.sh`, the documented, audited bootstrap
boundary (`docs/bootstrap-boundary.md`) that never runs from a pull-request
workflow. No workflow that runs on a promotion PR (`validate-gitops.yml`) ever
invokes `kubectl apply`/`patch`/`scale`; reconciliation happens out-of-band,
by ArgoCD watching `main`, after human approval merges the PR.

## Result

| | |
| --- | --- |
| PRs audited | 15 (5 services x dev/staging/prod) |
| Digest identical dev->staging->prod | 5/5 services |
| PRs scoped to exactly one overlay file | 15/15 |
| File-level collisions across concurrent merges | 0 |
| CI paths that mutate a cluster | 0 (only the audited bootstrap boundary, never PR-triggered) |
| Result | `pass` |

# Gate presence, visibility, and fail-fast behavior (T024)

Task **T024** of `specs/003-reusable-cicd-delivery`: validate gate
presence/visibility and fail-fast behavior via `act` dry-run and a forced
`run-unit=true` no-artifact run (`quickstart.md` §4).

## Reconciliation: the described mechanism no longer exists

`quickstart.md` §4 describes a `run-unit=true` boolean toggle with individually
skippable unit/integration/contract/e2e/perf/dast jobs inside `ci.yml`. Today's
`ci.yml` has no `run-unit` input at all (`grep -c run-unit ci.yml` = 0): the
architecture moved to one mandatory `test-command` per caller (always runs,
never skippable) plus separate value-activated gates
(`contract-command`, `sonar-project-key`/`sonar-required`) that skip via `if:`
when unset. `act` itself proved impractical here: dry-running this reusable
workflow locally requires emulating/pulling a multi-GB runner image, which
took over 20 minutes without completing on this workstation and was abandoned
in favor of triggering the real thing directly.

## What was actually validated instead

Rather than a local `act` dry-run against a retired input, this validates the
*intent* T024 and FR-017 exist to serve -- gates fail visibly, never pass
having done nothing -- against the architecture as it exists now, using real
GitHub Actions runs (disposable draft PRs, closed without merging once
observed) rather than a local emulator.

### A real defect was found and fixed

`test-command` is `required: true` with no default, but nothing stopped a
caller from satisfying that requirement with an empty string, and
`run: ${{ inputs.test-command }}` with an empty resolved value is a no-op
shell script that **succeeds**. Confirmed live before any fix, disposable PR
[MicroTodoSuite/.github#25](https://github.com/MicroTodoSuite/.github/pull/25)
(closed without merging): a run with `test-command: ""` reported

```
"Run repository tests": conclusion "success"
```

Fixed in [MicroTodoSuite/.github#27](https://github.com/MicroTodoSuite/.github/pull/27):
a guard step now fails closed before "Run repository tests" runs. Confirmed
live after the fix, disposable PR
[MicroTodoSuite/.github#26](https://github.com/MicroTodoSuite/.github/pull/26)
(closed without merging): the same input now reports

```
"Reject an empty test-command": conclusion "failure"
"Run repository tests": conclusion "skipped"
```

with the annotation:

```
::error::test-command must not be empty or blank -- an empty run: step
succeeds having tested nothing (FR-017: a gate must fail visibly, never pass
silently)
```

A permanent static contract
(`tests/workflows/reusable-workflow-contract.bats` in `.github`) guards this
going forward, following the SDD test-then-feat pair.

### Value-activated gates remain visibly skippable

`source-audit-command` and `contract-command` are legitimately optional
(`default: ""`) and each carries an `if: inputs.<name> != ''` guard, so a
caller that does not set them sees the step reported as **skipped** in the
Actions UI, never silently absent from the log. `sonar-required` (T102) fails
closed the same way when Sonar is required but unconfigured -- already proven
by the existing `reusable-workflow-contract.bats` assertion
(`"the SonarQube quality gate is required but not configured"`).

## The rest of quickstart.md, run against today's repos

Since T038 also asks for a full quickstart pass, the still-applicable
sections were run here rather than deferred:

| Section | Check | Result |
| --- | --- | --- |
| §1 | `actionlint .github/workflows/ci.yml,release.yml,promote.yml` | clean (unrelated findings in `conventions.yml`/`iac-checks.yml` are an actionlint schema-lag false positive for `job.workflow_repository`/`job.workflow_sha`, not in scope here; `promote.yml`'s SC2016 info-level hits are intentional single-quoting to keep literal backticks in PR-body markdown) |
| §1 | `ci.yml`/`release.yml`/`promote.yml` declare `workflow_call` | all three, confirmed |
| §2 | No `development.yml` remains; each service is a thin `uses:` caller | confirmed for all five services against `origin/main`, all pinned to the same SHA `c9cd8d96c2c679b7c3c59fcede62084c40648f84` |
| §6 | `kustomize build apps/<svc>/overlays/local \| kubeconform -strict` for todos-api/users-api/frontend/log-message-processor | all four: `Valid: 4, Invalid: 0, Errors: 0` |
| §6 | Base is environment-neutral (no namespace/digest/replicas in `base/`) | confirmed, no matches |
| §6 | log-message-processor uses `/metrics` health | confirmed |
| §6 | Three JWT services share one secret value | confirmed by `tests/contract/shared-jwt-local.sh` (T029) |
| §7 | `validate-gitops.yml` runs on every PR and includes a committed-secret scan | structural: proven by every merged PR in this repository's history, including this one |

## Result

| | |
| --- | --- |
| `run-unit`/skippable-job toggle from quickstart §4 | retired; reconciled above |
| Value-activated gates (`source-audit-command`, `contract-command`, Sonar) skip visibly | pass |
| Required gate (`test-command`) can be silently satisfied by nothing | **found: yes** -> fixed in `.github#27`, re-verified live |
| Remaining quickstart sections (1, 2, 6, 7) against current repos | pass |
| Result | `pass` (with one real defect found and fixed, not merely validated) |

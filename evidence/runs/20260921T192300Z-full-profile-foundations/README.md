# Full-profile AWS foundations: preflight and per-root results (T052-T060)

Tasks from `specs/009-full-platform-rollout/tasks.md`. This run records what
the full profile really did on AWS account 575172595729 in `us-east-1`, so the
register can be reconciled against reality rather than against intent.

Everything here is derived from primary evidence held outside Git:

- `~/backups-microtodosuite/full-bringup-20260914T213039Z/` -- the first
  creation of 2026-09-14: per-root `plan.log`, `plan.json`, `apply.log`,
  `*.tfplan`, and `no-prior-state` receipts.
- `microservice-app-ops/.aws-profile-plans/full-up-20260921T*` -- the
  2026-09-21 lifecycle re-up bundles: saved plans, plan JSON, `checksums.sha256`,
  and `metadata.tsv`.
- `~/backups-microtodosuite/575172595729/<timestamp>/` -- the per-root state
  backups the lifecycle wrapper wrote before each apply.
- `~/backups-microtodosuite/lead-briefs/t052-t060-facts.md` -- the lead's
  verified facts brief of 2026-09-21, from read-only discovery.

## Redaction

No secret, no state content, no resource ID, and no ARN is recorded, and no
plan JSON is copied wholesale (plan JSON can hold sensitive values). Each
summary carries only plan action counts, the apply result line, the saved-plan
SHA-256, the backup path, and the Infracost figure. The only account-bound
value present is the account ID that `config/aws-account.env` already declares.

## Files

| File | Contents |
| --- | --- |
| `infrastructure/preflight.json` | T052: quotas, usage before the up, AZ offering, CIDR match against the live VPCs, ownership, and state object counts |
| `shd-networking/summary.json` | T053/T054: the hub networking root |
| `fdev/networking/`, `fstg/networking/`, `fprd/networking/` | T055/T057: the three spokes |
| `fdev/security/`, `fstg/security/`, `fprd/security/` | T058/T059: the three security roots |
| `fdev/workload/`, `fstg/workload/`, `fprd/workload/` | T060: the three workload roots |
| `fdev/security-irsa/`, `fstg/security-irsa/`, `fprd/security-irsa/` | T060: the three IRSA passes |

## Two distinct events, not one

**First creation, 2026-09-14.** Every root was applied from no prior state;
each root's directory holds a `no-prior-state` receipt rather than a state
backup, because there was nothing to back up. Apply results: hub networking 24
added; spoke networking 28 each; spoke security 31 each; workload 26 each;
security-irsa 15 each. The runtime was then brought down through the lifecycle
on 2026-09-15; the persistent spoke networking and security roots stayed.

**Lifecycle re-up, 2026-09-21,** in three passes:

| Bundle | Pass | Result |
| --- | --- | --- |
| `full-up-20260921T192817Z` | hub-first | 24 creates planned, **22 of 24 applied** |
| `full-up-20260921T195633Z` | cluster-first | 101 creates (shd 2, spokes 7 each, workloads 26 each), `EXIT=0` |
| `full-up-20260921T210444Z` | complete | security-irsa 15 creates each (45); every other root no-op; `EXIT=0` |

The hub half-apply was not a code fault: the hub flow-log group already existed
as an untagged orphan, created 2026-09-15T21:31:43Z by flow-log delivery after
the down. It was exported to
`~/backups-microtodosuite/orphan-shd-flowlog-loggroup-20260921T194943Z/` and
deleted by the maintainer. The root cause is fixed by
`microservice-app-ops` specs/003 T017 (ops#129, ops#130).

The `<env>/security` roots carry no 2026-09-21 entry on purpose: the lifecycle
never plans them. They are persistent and stayed in place from 2026-09-14.

## Approval

Every apply on 2026-09-21 was an exact-plan apply of a saved plan, under the
maintainer's **standing authorization of 2026-09-20** for exact-plan approval.
The saved-plan SHA-256 in each summary is the one recorded in that bundle's
`checksums.sha256`, which is what makes "exact plan" checkable after the fact.

## Infracost

Recorded in the facts brief for the cluster-first pass only: hub USD 73/month,
each spoke USD 36.50/month, each workload USD 144.90/month. No figure was
recorded for the 2026-09-14 creation or for the hub-first and complete passes,
and none is invented here.

## Result

| | |
| --- | --- |
| T052 | delivered -- `infrastructure/preflight.json` |
| T053-T060 | delivered -- see the per-root summaries and the register annotations |
| T063-T067 | **not done** -- no GitOps roots, no ArgoCD bootstrap, no reachability tests |
| Result | `pass` for the foundations; the platform layer above them is still open |

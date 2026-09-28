# Advanced testing gates: contracts, integration, and central-workflow discipline (T011-T013, T018, T026, T027)

Tasks from `specs/007-advanced-testing/tasks.md`, all real work per the
2026-08-30 reconciliation (not bookkeeping debt).

## T011 / T012: the missing Pact contracts

Only `frontend<->todos-api` existed. Authored the two missing consumer
contracts from real, verified service behavior (built and ran `auth-api` and
`users-api` locally with Docker to capture the exact `POST /login` and
`GET /users/{username}` request/response shapes, not guessed):

- `frontend-auth-api.json` (frontend consumes auth-api's `/login`)
- `auth-api-users-api.json` (auth-api itself consumes users-api's
  `/users/{username}` for its own login flow -- a service-to-service pact,
  not frontend-driven)

`log-message-processor<->todos-api` needed no new Pact contract: it is
already covered by the AsyncAPI producer/consumer binding (T004/T010), the
correct mechanism for a non-HTTP interaction.

`e2e/pact/verify.sh` (frontend repo) now verifies all three contracts in one
gate run. Ran the real five-service `e2e/compose.yaml` stack locally and
executed it directly:

```
pact provider verification OK: todos-api (frontend-todos-api.json)
pact provider verification OK: auth-api (frontend-auth-api.json)
pact provider verification OK: users-api (auth-api-users-api.json)
pact provider verification OK: all consumer contracts satisfied
```

3 interactions, 0 failures. Also confirmed green in real CI:
`microservice-app-frontend` PR #35, jobs `ci/supply-chain`, `pact/stack-tests`,
`conformance/stack-tests`, and `e2e/stack-tests` all passed.

See `microservice-app-frontend` PR #35.

## T013: a deliberate contract break turns the gate red (SC-001/SC-002)

Corrupted `auth-api-users-api.json`'s expected `lastname` from `"Bar"` to
`"WRONG-VALUE"` and re-ran `verify.sh` against the live stack:

```
* Expected "WRONG-VALUE" but got "Bar" at $.lastname
1 interaction, 1 failure
```

Script exit code: `1` (captured directly, not through a pipe). Reverted the
corruption and re-ran: exit code `0`, `1 interaction, 0 failures`. Full
before/after output in `pact-break-revert.txt`.

## T018: each integration gate exercises the real dependency and fails when it breaks (SC-003)

For all four integration gates (T014-T017), ran the real baseline (green),
introduced one targeted regression in the actual interaction code (not the
test), confirmed a real failure, then reverted and confirmed green again.
Full transcripts in `integration-gate-breaks.txt`.

| Service | Real dependency | Regression introduced | Result |
| --- | --- | --- | --- |
| todos-api | Testcontainers Redis (real container, real pub/sub) | Renamed the `CREATE` event's `opName` constant | `AssertionError: expected a CREATE event on log_channel` |
| log-message-processor | testcontainers-python Redis (real container, real pub/sub) | Removed the `logger(message)` call from the consume path | `assert metrics.processed.count == 1` fails (0 != 1) |
| users-api | `@SpringBootTest` + MockMvc + real H2 | Corrupted the real H2 seed row (`data.sql`: `admin`'s firstname `Foo` -> `BROKEN`) | `JSON path "$.firstname" expected:<Foo> but was:<BROKEN>` |
| auth-api | Real HTTP boundary (`httptest` server) + real retry/circuit-breaker logic | Off-by-one in the retry loop (`attempt <= maxRetries` -> `attempt < maxRetries`) | `FAIL: transient_error_is_retried` -- fewer real HTTP attempts than the interaction requires |

Each regression was reverted immediately after capturing the failure; all
four repos are clean (`git status --short` empty) and green again.

## T026: SC-006 (central workflow, no per-repo duplication) and SC-007 (no framework/GitOps changes)

Compared all five services' `ci.yml` callers on `origin/main` byte-for-byte:
identical job structure (`ci`, `release`, `promote-dev`, `promote-staging`,
`gate-prod`, `promote-prod`), differing only in `with:` *values*
(service-name, language, test-command, contract-command, ECR path, Sonar
key). Zero per-repo custom step duplication -- every gate (build, test, scan,
SBOM, sign, contract lint, Sonar, release, promote) lives only in the central
`.github` reusable workflows.

The five stack-level gates in the frontend repo (`e2e.yml`, `perf.yml`,
`dast.yml`, `conformance.yml`, `pact.yml`) each contain a single `uses:
.../stack-tests.yml` call, differing only in `gate-name`/`stack-command`.

SC-007: this task's own changes touch only `e2e/pact/` (frontend), a new
contract file and a wired self-test in `.github` -- no unit-test framework,
no vulnerability-remediation file (spec 006), and no GitOps manifest changed.

## T027: "enabled-but-empty fails visibly" once per gate

`sonar-required` (T102) already fail-closes when Sonar is required but
unconfigured -- pre-existing, verified by
`tests/workflows/reusable-workflow-contract.bats`. `source-audit-command` and
`contract-command` are genuinely optional (`default: ""`, `if:`-guarded) and
correctly show as **skipped**, not silently absent, which is the *correct*
behavior for an intentionally-disabled optional gate.

Auditing the two *required* gate-command inputs (no default, meant to always
run) found the real failure mode T027 exists to catch, in **two** places, not
one:

1. `ci.yml`'s `test-command` (gitops spec 003 T024): confirmed live, an empty
   value made "Run repository tests" report `success` having tested nothing.
   Fixed in `MicroTodoSuite/.github#27`.
2. `stack-tests.yml`'s `stack-command`, which backs five separate gates
   (e2e/perf/dast/pact/conformance) across the frontend repo -- the exact
   same shape, found while specifically checking T027's "once per gate"
   requirement. Confirmed live: empty value succeeded before the fix. Fixed
   in `MicroTodoSuite/.github#29`.

Both fixes follow the SDD test-then-feat pair (new bats contracts:
`tests/workflows/reusable-workflow-contract.bats` and the new
`tests/workflows/stack-tests-contract.bats`, the latter now wired into a
self-test workflow so it actually runs on every relevant PR) and were
re-verified live on real GitHub Actions after the fix, via disposable draft
PRs closed without merging once observed.

## Result

| | |
| --- | --- |
| T011/T012 | delivered -- 3/3 Pact contracts, 0 failures, real CI green |
| T013 | delivered -- real break/revert with exit-code evidence |
| T018 | delivered -- 4/4 integration gates proven to exercise and detect breaks in their real dependency |
| T026 | delivered -- zero per-repo gate duplication confirmed across all 5 services + 5 stack gates |
| T027 | delivered -- 2 real "enabled-but-empty" defects found and fixed (not just 1 checked) |
| Result | `pass` |

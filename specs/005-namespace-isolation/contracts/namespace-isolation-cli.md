# Contract: Namespace Isolation Observer CLI

## Command

The implementation will provide one read-only observer:

```text
scripts/managed/verify-namespace-isolation.sh \
  --context <kube-context> \
  --phase <baseline|foundation|default-deny|fixtures|final> \
  --expected-revision <40-hex-git-sha> \
  [--baseline <baseline-summary-json>] \
  [--cleanup-revision <40-hex-git-sha>] \
  [--output <directory>]
```

## Inputs

| Option | Required | Rule |
| --- | --- | --- |
| `--context` | yes | Exact explicit kube context; the script never relies on the ambient current context. |
| `--phase` | yes | One of the five closed values. |
| `--expected-revision` | yes | Full 40-character lowercase Git SHA. |
| `--baseline` | foundation and later | Existing successful baseline summary for before/after comparison. |
| `--cleanup-revision` | final only | Full SHA expected after fixture revert. |
| `--output` | no | Defaults to a new timestamped directory under `.local/evidence/namespace-isolation/`. Existing non-empty output is rejected. |

## Behavior

The observer MUST:

- enable strict Bash mode and reject missing tools/arguments before cluster
  access;
- confirm the named context points to the expected shared cluster identity;
- use explicit `--context` and namespaces in every Kubernetes command;
- collect live API objects, events, logs, metrics when available, authorization
  results, and application endpoint results;
- wait only for observed state and never request a sync or rollout;
- preserve every raw observation used to compute `summary.json`;
- validate `summary.json` against the evidence schema when a JSON Schema
  validator is available, and fail closed when final acceptance cannot validate;
- write `PASS` only when every phase-specific gate succeeds; and
- exit nonzero on a failed gate without deleting evidence.

The observer MUST NOT invoke or embed any command that mutates managed state,
including Kubernetes `apply`, `create`, `patch`, `replace`, `scale`, `rollout`,
`delete`, `edit`, or ArgoCD sync/terminate operations.

## Phase Outputs

| Phase | Required result |
| --- | --- |
| `baseline` | Constitution/registration/CNI/identity prerequisites plus dev application, readiness, restart, health, resource, and connection baseline. |
| `foundation` | All three environment foundations at the expected revision; default deny absent; dev matches baseline. |
| `default-deny` | Default deny present/enforced; required dev paths pass; dev matches baseline. |
| `fixtures` | Six denied cross-environment paths, three allowed local paths, three DNS successes, expected quota violation, RBAC matrix, and unaffected comparison environment. |
| `final` | Fixtures absent, applications at cleanup revision, dev still matches baseline, complete command audit, schema-valid final summary. |

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | All checks required for the selected phase passed. |
| `2` | Usage or input validation failure. |
| `3` | Tool, context, or prerequisite unavailable. |
| `4` | ArgoCD revision/sync/health gate failed. |
| `5` | CNI or network isolation gate failed. |
| `6` | Resource isolation gate failed. |
| `7` | RBAC gate failed. |
| `8` | Dev continuity gate failed. |
| `9` | Evidence serialization or schema validation failed. |

## Safety Audit

The static contract test scans the observer and documentation for managed-state
mutation verbs. Any match must be reviewed as either a prohibited command or an
explicit prose guard; executable mutation is always a failure.

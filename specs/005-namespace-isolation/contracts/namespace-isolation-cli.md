# Contract: Namespace Isolation and Release Observer CLI

## Command

```text
scripts/managed/verify-namespace-isolation.sh \
  --context <kube-context> \
  --expected-cluster-id <exact-kubeconfig-cluster-id> \
  --phase <baseline|prerequisites|activated|canary|fixtures|final> \
  --expected-revision <40-hex-git-sha> \
  [--previous-evidence <preceding-summary-json>] \
  [--release-evidence <release-manifest-json>] \
  [--cleanup-revision <40-hex-git-sha>] \
  [--output <directory>]
```

## Inputs

| Option | Required | Rule |
| --- | --- | --- |
| `--context` | yes | Explicit context; ambient context is never trusted |
| `--expected-cluster-id` | yes | Exact reviewed kubeconfig cluster identifier |
| `--phase` | yes | One of the six closed phase values |
| `--expected-revision` | yes | Full lowercase Git SHA expected in Argo CD |
| `--previous-evidence` | prerequisites and later | Passing summary from the immediately preceding phase on the same cluster |
| `--release-evidence` | activated and later | Schema-valid mapping for five source commits, runs, ECR digests, SBOMs, scans, and signatures |
| `--cleanup-revision` | final only | Git-revert cleanup SHA |
| `--output` | no | New timestamped directory below `.local/evidence/namespace-isolation/`; non-empty destinations are rejected |

## Safety behavior

The observer MUST:

- use strict Bash mode and fail closed on missing tools or inputs;
- use explicit context and namespace on every Kubernetes command;
- compare the selected cluster identifier byte-for-byte and confirm it is the
  reviewed EKS target;
- collect raw observations before producing summaries;
- wait for observed state but never request sync, rollout, promotion, abort, or
  mutation;
- redact secret values and compare only non-reversible digests/lengths;
- require the exact predecessor chain
  `baseline -> prerequisites -> activated -> canary -> fixtures -> final`;
- validate release and summary JSON before a PASS result; and
- exit nonzero without deleting evidence when any gate fails.

The observer MUST NOT execute Kubernetes mutation verbs, Argo CD sync/terminate
operations, Terraform apply, AWS resource-creation calls, GitHub merge actions,
or secret-value reads that would print content.

## Phase output contract

| Phase | Required result |
| --- | --- |
| `baseline` | Constitution/cluster/CNI baseline; three Healthy environment Applications; zero business Applications; shared Redis still explicit; quota and dev continuity snapshot; all open gates recorded |
| `prerequisites` | Five post-retirement infrastructure Applications including Argo Rollouts; progressive-sync controller flag live; three Ready ESO paths with distinct non-empty values; exact quotas; three Redis instances and no shared Redis; five admissible signed release artifacts; zero business Applications |
| `activated` | Exactly fifteen business Applications at the expected revision; timestamp/order evidence proves dev then staging then prod; all Pods Ready with exact reviewed image IDs; initial production stable Rollouts identified without falsely claiming canary execution |
| `canary` | Five same-digest successful AnalysisRuns/Rollouts plus one intentional failed metric, aborted Rollout, stable restoration, and cleanup Git revert |
| `fixtures` | Six network and six Redis denials; three same-environment, DNS, Redis, and Pub/Sub successes; expected quota violation; unaffected comparison environment; RBAC matrix or explicit deferred-mapping blocker |
| `final` | Fixtures absent; all Applications at cleanup revision and Healthy; exact digests unchanged; continuity window passed; command audit and schema valid |

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | All selected-phase gates passed |
| `2` | Usage or input validation failure |
| `3` | Tool, context, or prerequisite unavailable |
| `4` | Argo CD revision, order, sync, or health failure |
| `5` | CNI or network isolation failure |
| `6` | Resource budget or deliberate violation failure |
| `7` | RBAC or IRSA authorization failure |
| `8` | Workload continuity or endpoint failure |
| `9` | Evidence serialization/schema failure |
| `10` | Redis health/routing/event isolation failure |
| `11` | ESO secret readiness/separation failure |
| `12` | CI, ECR, SBOM, scan, digest, signature, or Pod image-ID failure |
| `13` | RollingSync or production canary/rollback failure |

## Evidence layout

```text
.local/evidence/namespace-isolation/<timestamp>/
├── summary.json
├── command-log.txt
├── applications/
├── aws/
├── canary/
├── cluster/
├── continuity/
├── environments/
├── images/
├── network/
├── rbac/
├── redis/
├── resource/
└── secrets/
```

The static contract test scans executable observer content for mutation verbs.
Explicit prose prohibitions are allowed; executable mutation is always a test
failure.

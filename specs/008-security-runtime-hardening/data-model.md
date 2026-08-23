# Data Model: Runtime Security Hardening

This repository stores desired state rather than business records. The
feature has four reviewable entities and explicit state transitions.

## SecurityComponent

Represents one GitOps-managed platform capability from this feature.

| Field | Meaning | Validation |
| --- | --- | --- |
| `name` | Stable folder and application identity | One of `falco`, `kube-bench`, `kube-hunter` |
| `namespace` | Dedicated security namespace | Equal to `security` for all three |
| `release` | Pinned upstream version | Concrete version; no range or floating alias (Falco 0.44.1, kube-bench v0.16.0, kube-hunter 0.6.8) |
| `bundlePath` | Retained install manifest | None - no genuine upstream bundle exists for any of the three; each has a provenance-only `vendor/<release>/README.md` instead |
| `images` | Runtime artifacts | Every rendered image is pinned by immutable SHA-256 digest |
| `controllers` | Expected DaemonSet/CronJob | Falco: DaemonSet, one pod per node, Available. kube-bench/kube-hunter: CronJob present and scheduled, most recent Job run Complete |

State transition:

```text
Pinned -> Rendered -> Committed -> Argo Synced -> Controller(s) Available
```

## RuntimeFinding

Represents one Falco detection event.

| Field | Meaning | Validation |
| --- | --- | --- |
| `rule` | Which Falco rule fired | One of the default/community ruleset's rule names |
| `pod`/`namespace`/`process` | Where and what triggered it | Populated from the syscall event's container context |
| `deliveredTo` | Slack delivery outcome | Message present in the configured channel within 1 minute (SC-002) |

State transition:

```text
Syscall Observed -> Rule Matched -> Falco Output Emitted
        -> Falcosidekick Forwarded -> Slack Message Delivered
```

## AuditReport

Represents one completed kube-bench or kube-hunter run.

| Field | Meaning | Validation |
| --- | --- | --- |
| `tool` | Which audit | `kube-bench` or `kube-hunter` |
| `runAt` | When the Job executed | Timestamp of the CronJob-triggered Job |
| `findings` | Per-control (kube-bench) or per-vulnerability (kube-hunter) results | Real PASS/FAIL/WARN or severity value, never a placeholder |
| `disposition` | What happened to each finding | Remediated, or a `DocumentedException` (see below) |

State transition:

```text
CronJob Triggers -> Job Runs -> Report Produced -> Job Completes and Cleans Up (ttlSecondsAfterFinished)
        -> Findings Reviewed -> Each Finding Remediated or Excepted
```

A report that never completes (crashed/timed-out Job) is a failed run, not
an implicit "no findings" (per the spec's edge cases).

## DocumentedException

Represents a finding from any of the three tools that is not remediated.

| Field | Meaning | Validation |
| --- | --- | --- |
| `finding` | Which Falco rule, CIS control, or kube-hunter vulnerability | References the specific `RuntimeFinding` or `AuditReport` entry |
| `justification` | Why it is not remediated | Explicit, non-empty |
| `reviewBy` | Time-bound review date | A concrete future date, not open-ended |

## ReconciliationEvidence

An untracked, timestamped observation set produced by the verifier,
mirroring `006-observability-platform-foundation`'s evidence shape.

| Field | Meaning |
| --- | --- |
| `expectedRevision` | SHA at the `gitops` source ArgoCD reconciled |
| `applications` | App name, source revision, sync, and health for all three components |
| `daemonsetCoverage` | Falco pod count vs. node count |
| `triggeredFinding` | The injected anomalous action and its delivered Slack message |
| `benchReport` | The kube-bench run's per-control results |
| `hunterReport` | The kube-hunter run's per-vulnerability results |

State transition:

```text
Started -> Revision Matched -> Applications Healthy -> Falco Covers Every Node
        -> Triggered Finding Delivered -> Bench Report Captured
        -> Hunter Report Captured -> Complete
```

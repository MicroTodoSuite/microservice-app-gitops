# Data Model: Runtime Security Hardening

This repository stores desired state rather than business records. The
feature has four reviewable entities and explicit state transitions.

## SecurityComponent

Represents one GitOps-managed platform capability from this feature.

| Field | Meaning | Validation |
| --- | --- | --- |
| `name` | Stable folder and application identity | One of `falco`, `kube-bench`, `kube-hunter`, `trivy-operator` (amended 2026-09-13) |
| `namespace` | Dedicated security namespace | Equal to `security` for all four |
| `release` | Pinned upstream version | Concrete version; no range or floating alias (Falco 0.44.1, kube-bench v0.16.0, kube-hunter 0.6.8, Trivy Operator 0.34.0 with Trivy 0.74.0) |
| `bundlePath` | Retained install manifest | Falco, kube-bench, and kube-hunter have no genuine upstream bundle and keep a provenance-only `vendor/<release>/README.md`; Trivy Operator's upstream static bundle is retained under `vendor/v0.34.0/` with `SHA256SUMS` |
| `images` | Runtime artifacts | Every rendered image is pinned by immutable SHA-256 digest |
| `controllers` | Expected DaemonSet/CronJob/Deployment | Falco: DaemonSet, one pod per node, Available. kube-bench/kube-hunter: CronJob present and scheduled, most recent Job run Complete. Trivy Operator: Deployment Available, no scan Job left after completion |

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

## VulnerabilityReport

Represents Trivy's current result for one workload container image (amended
2026-09-13).

| Field | Meaning | Validation |
| --- | --- | --- |
| `namespace`/`workload`/`container` | What was scanned | One of the five suite namespaces |
| `image` | Image reference scanned | The running image, including its digest when the workload pins one |
| `counts` | Vulnerabilities per severity | Real CRITICAL/HIGH/MEDIUM/LOW/UNKNOWN counts from a completed scan |
| `updatedAt` | When the scan completed | Replaced when the report expires (24 hours) or the image changes |
| `disposition` | What happened to HIGH/CRITICAL entries | Remediated, or a `DocumentedException` |

State transition:

```text
Workload Running -> Scan Job Created -> Image Pulled Through Registry Identity
        -> Report Written -> Metrics Exposed -> Alert Evaluated -> Slack Notified (HIGH/CRITICAL)
        -> Findings Reviewed -> Each HIGH/CRITICAL Remediated or Excepted
```

A scan Job that fails (image pull denied, database download blocked,
timeout) leaves no fresh report and is a failed scan, not an image without
vulnerabilities.

## DocumentedException

Represents a finding from any tool in this feature that is not remediated
(for Trivy, a HIGH or CRITICAL vulnerability).

| Field | Meaning | Validation |
| --- | --- | --- |
| `finding` | Which Falco rule, CIS control, kube-hunter vulnerability, or image CVE | References the specific `RuntimeFinding`, `AuditReport`, or `VulnerabilityReport` entry |
| `justification` | Why it is not remediated | Explicit, non-empty |
| `reviewBy` | Time-bound review date | A concrete future date, not open-ended |

## ReconciliationEvidence

An untracked, timestamped observation set produced by the verifier,
mirroring `006-observability-platform-foundation`'s evidence shape.

| Field | Meaning |
| --- | --- |
| `expectedRevision` | SHA at the `gitops` source ArgoCD reconciled |
| `applications` | App name, source revision, sync, and health for all four components |
| `daemonsetCoverage` | Falco pod count vs. node count |
| `triggeredFinding` | The injected anomalous action and its delivered Slack message |
| `benchReport` | The kube-bench run's per-control results |
| `hunterReport` | The kube-hunter run's per-vulnerability results |
| `vulnerabilityReports` | One report per workload image in the suite namespaces, with counts per severity |
| `vulnerabilityAlert` | A HIGH/CRITICAL notification delivered to Slack |
| `vulnerabilityDashboard` | Dashboard counts compared with the reports |

State transition:

```text
Started -> Revision Matched -> Applications Healthy -> Falco Covers Every Node
        -> Triggered Finding Delivered -> Bench Report Captured
        -> Hunter Report Captured -> Vulnerability Reports Captured
        -> Vulnerability Alert Delivered -> Complete
```

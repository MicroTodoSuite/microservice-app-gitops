# Implementation Plan: Runtime Security Hardening

**Branch**: `feat/security-runtime-hardening` | **Date**: 2026-08-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/008-security-runtime-hardening/spec.md`

## Summary

Close constitution principle 10's three explicitly claim-gated/deferred
capabilities on the live `eks-dev` cluster: Falco (0.44.1, modern eBPF
driver) as an always-on runtime detector with findings forwarded to the same
Slack channel spec 006 already wired, via Falcosidekick (2.34.1); kube-bench
(v0.16.0) as a scheduled CIS Benchmark audit using the `eks` target profile
(the control plane is AWS-managed and not directly auditable); and
kube-hunter (0.6.8) as a scheduled internal (non-destructive) vulnerability
scan. All three are namespace-scoped, digest-pinned, and registered through
`eks-dev`'s explicit activation list, matching every existing add-on's
pattern. None of the three has a genuine upstream raw-YAML bundle (Falco and
kube-bench/kube-hunter are normally installed via Helm chart or ad-hoc
`kubectl run`), so manifests are hand-authored with the same digest-pinning
discipline as `infrastructure/grafana`/`loki`/`jaeger`.

## Technical Context

**Language/Version**: Kubernetes YAML; Kustomize v5

**Primary Dependencies**: Falco 0.44.1 (modern eBPF driver, default/community
rules), Falcosidekick 2.34.1 (Slack output), kube-bench v0.16.0 (`eks` target
profile), kube-hunter 0.6.8 (internal/passive mode) - all real current
releases, verified via the GitHub API and `docker buildx imagetools inspect`

**Storage**: None - Falco is stateless (forwards findings, does not persist
them); kube-bench/kube-hunter Jobs write their report to stdout/logs, kept
only as long as the Job's pod (`ttlSecondsAfterFinished`), consistent with
this feature not claiming a findings-archival capability.

**Testing**: Kustomize render + `kubeconform`, SHA-256/provenance
verification for hand-authored components, a Bash contract script (mirroring
`tests/contract/observability.sh`) checking pinned versions, RBAC read-only
scope, CronJob schedule presence, and Falco driver/rule configuration; a
read-only live verification script capturing a real triggered Falco
finding delivered to Slack and real kube-bench/kube-hunter report output.

**Target Platform**: Live `eks-dev` EKS cluster - Falco runs on every node
(DaemonSet, needed for host-level syscall visibility); kube-bench and
kube-hunter run as scheduled Jobs against the cluster, not per-node.

**Project Type**: GitOps desired-state repository only; no service-repo code
change (unlike spec 006's `auth-api` instrumentation).

**Performance Goals**: Falco Synced/Healthy on every node within 10 minutes
of the final commit (SC-001); a triggered finding reaches Slack within 1
minute (SC-002); each kube-bench/kube-hunter run completes and produces a
report within its Job's `activeDeadlineSeconds`.

**Constraints**: GitOps-only; no Istio/service mesh; Audit-only (detection,
never enforcement) for all three tools per FR-004/the spec's explicit scope
boundary; kube-bench/kube-hunter RBAC MUST be read-only with no standing
privileged workload after the Job completes; no ingress/TLS work (nothing to
protect yet, per the spec's Assumptions); Falco's Slack delivery MUST use
the same ESO/SecretStore pattern as spec 006, never a committed webhook.

**Scale/Scope**: One new namespace (`security`), three new ArgoCD-owned
infrastructure Applications (`falco`, `kube-bench`, `kube-hunter`), zero
service-repo changes.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Gate | Design response |
| --- | --- | --- |
| Environment Isolation | PASS | New components live in one namespace-scoped `security` namespace on the existing `eks-dev` cluster; no new cluster or VPC. |
| GitOps-Only Deployment | PASS | Every component ships as a hand-authored, digest-pinned Kustomize root reconciled by ArgoCD; no direct cluster mutation outside the audited bootstrap boundary. |
| Stable Trunk Development | PASS | Work proceeds on the short-lived `feat/security-runtime-hardening` branch. |
| Authoritative Specifications | PASS | spec → clarify → this plan → tasks precede any manifest change. |
| Cost-Governed Design | PASS | Falco's DaemonSet is the only per-node cost; kube-bench/kube-hunter are ephemeral Jobs with no standing cost between scheduled runs. |
| Immutable Build Promotion | PASS | No service image is built by this feature; only third-party security-tool images, each pinned by digest. |
| Progressive and Reversible Releases | PASS | Each component lands as its own commit; Falco stays Audit-only (detection, not blocking), so no release path is put at risk. |
| Quality and Supply-Chain Gates | PASS | All images are digest-pinned; provenance is recorded even where no genuine upstream bundle exists to checksum. |
| Observable and Resilient Operations | PASS | This feature closes constitution principle 10's own disclosed gap for these three tools; Istio remains untouched and unused. |
| Least Privilege and Secret Hygiene | PASS | kube-bench/kube-hunter RBAC is read-only and Job-scoped (no standing privilege); Falco's Slack webhook is ESO-delivered, never committed. Falco's DaemonSet needs specific Linux capabilities (`BPF`, `SYS_RESOURCE`, `PERFMON`, `SYS_PTRACE`) and read-only host mounts (`/proc`, `/boot`, `/lib/modules`, `/usr`, `/etc`) to read node syscalls via the modern eBPF driver - verified against the real Falco Helm chart, this needs neither `hostPID` nor a fully `privileged` container, and is scoped to Falco's own ServiceAccount only. |
| Declarative and Policy-Controlled Platform | PASS | All three components are ArgoCD-owned under `infrastructure/`, added to the existing `eks-dev` activation list. |
| Proven DR and Disclosed Data Loss | PASS | No DR claim is made; this feature has no persistent state to lose. |

Post-design re-check: PASS. Phase 1 design (below) introduces no enforcement
behavior, no new standing privileged workload beyond Falco's own necessary
host access, and no ingress/TLS surface.

## Project Structure

### Documentation (this feature)

```text
specs/008-security-runtime-hardening/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── security-registration.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
clusters/eks-dev/
└── activation-infrastructure.yaml   # three new entries, namespace security

infrastructure/
├── falco/
│   ├── kustomization.yaml
│   ├── falco-daemonset.yaml          # DaemonSet, modern eBPF driver, image pinned by digest
│   ├── falco-config.yaml             # falco.yaml + default/community rules reference
│   ├── falcosidekick.yaml            # Deployment + Service, image pinned by digest
│   ├── falcosidekick-slack-secret.yaml # ExternalSecret/SecretStore (mirrors spec 006's pattern)
│   └── vendor/v0.44.1/README.md      # image source/digest provenance only, no bundle
├── kube-bench/
│   ├── kustomization.yaml
│   ├── cronjob.yaml                  # CronJob, eks target profile, read-only RBAC
│   └── vendor/v0.16.0/README.md
└── kube-hunter/
    ├── kustomization.yaml
    ├── cronjob.yaml                  # CronJob, internal/passive mode, read-only RBAC
    └── vendor/v0.6.8/README.md

scripts/managed/
└── verify-security.sh                # read-only composite live evidence

tests/contract/
└── security.sh                       # static provenance/render/RBAC/no-enforcement contract
```

**Structure Decision**: Reuse the exact `infrastructure/<capability>/` +
explicit `activation-infrastructure.yaml` registration pattern established by
`003-platform-addons` and reused by `006-observability-platform-foundation`,
one Kustomize root per component. None of the three tools has a genuine
upstream raw-YAML bundle (Falco and the Aqua tools are normally installed
via Helm chart or a one-off `kubectl run`), so all manifests are
hand-authored with digest-pinning discipline and provenance-only vendor
READMEs, matching `infrastructure/grafana`/`loki`/`jaeger`'s precedent set
in spec 006. A dedicated `security` namespace (not `observability`) keeps
this feature's RBAC/NetworkPolicy surface separate from the metrics/logs/
traces stack, since Falco's host-level access needs are a materially
different trust boundary than anything in `observability`.

## Complexity Tracking

No constitution violation or exception is required. Falco's host-level
access (specific Linux capabilities plus read-only host mounts, not
`hostPID` or `privileged: true` - verified against the real Falco Helm
chart) is inherent to a runtime syscall detector's function, not a design
choice to justify away; it is scoped to Falco's own ServiceAccount/
DaemonSet only, and does not extend to kube-bench/kube-hunter's Job RBAC,
which stays read-only.

# Research: Runtime Security Hardening

## Falco driver: modern eBPF, not the kernel module

**Decision**: Falco 0.44.1 with the modern eBPF probe (`driver.kind:
modern_ebpf` / the `--modern-bpf` mode), not the classic kernel module or
the older (non-CO-RE) eBPF probe.

**Rationale**: Resolved directly in the Clarifications session. The
classic kernel-module driver must be compiled against the exact kernel
version each node runs; on an EKS node group where Karpenter/managed node
groups can roll nodes to newer AMIs at any time, that driver would silently
stop working on a kernel it wasn't built for. The modern eBPF probe uses
CO-RE (Compile Once - Run Everywhere) and works across the standard range
of kernels EKS's Amazon Linux 2/2023 AMIs ship, without per-node
compilation, and is Falco's own current recommended default.

**Alternatives considered**: The classic (non-CO-RE) eBPF probe was
considered and rejected - it still requires driver artifacts matched to
specific kernel versions, just via a probe object instead of a compiled
module, keeping the same node-upgrade fragility the modern eBPF driver
specifically solves.

## Falco deployment shape: DaemonSet, genuinely needed here (unlike Alloy)

**Decision**: Falco runs as a `DaemonSet`, one pod per node, with `hostPID:
true` and the specific Linux capabilities its eBPF driver needs.

**Rationale**: This is the one place in this suite's observability/security
work where a DaemonSet is actually correct, in contrast to spec 006's
Alloy, which deliberately avoided one. Alloy's `loki.source.kubernetes`
reads logs through the Kubernetes API (a control-plane-mediated view);
Falco reads raw kernel syscalls, which only exist on the node where the
syscall happened, so it has no API-mediated equivalent - it must run
somewhere on every node.

## Falco → Slack: Falcosidekick, matching definitions.md's own documented tool

**Decision**: Falcosidekick 2.34.1 receives Falco's output over HTTP and
forwards findings to Slack, using a webhook delivered through the same ESO/
SecretStore pattern spec 006 established for Alertmanager's Slack route.

**Rationale**: This project's own `definitions.md` already documents
Falcosidekick by name as "the component that takes Falco's alerts and
forwards them to other systems (Slack, Elasticsearch, PagerDuty, etc.)" -
this is not a tool choice invented for this feature, it is what the
project's own glossary already named as the intended integration.

**Alternatives considered**: Having Falco call a Slack webhook directly
(some Falco output configs support a raw HTTP output) was considered and
rejected - Falcosidekick is purpose-built for exactly this fan-out, handles
Slack's specific message formatting, and is the documented, supported path
rather than a bespoke one.

## kube-bench target: the `eks` profile, not the generic CIS profile

**Decision**: kube-bench v0.16.0 runs with `--benchmark eks-1.x` (the `eks`
target profile bundled with kube-bench), not the generic upstream
Kubernetes CIS profile.

**Rationale**: Resolved in the Clarifications session. `eks-dev`'s control
plane (API server, etcd, scheduler, controller-manager) is fully managed by
AWS and not reachable or inspectable from inside the cluster - the generic
CIS profile's control-plane checks would all fail or error out not because
of a real misconfiguration, but because the check target doesn't exist from
this vantage point. The `eks` profile is kube-bench's own answer to exactly
this: it evaluates only the worker-node and cluster-policy checks that
apply to a managed-control-plane cluster, so every FAIL it reports is a real
finding, not noise from an inapplicable check.

## kube-bench and kube-hunter deployment shape: scheduled Jobs, not DaemonSets

**Decision**: Both run as Kubernetes `CronJob`s (a `Job` per scheduled run),
not as long-running Deployments or DaemonSets, with
`ttlSecondsAfterFinished` cleanup and no privileged standing workload
between runs.

**Rationale**: Both tools are point-in-time audits, not continuously running
detectors (unlike Falco) - the spec's Assumptions already frame their
interval as a planning-phase decision. A `CronJob` is the standard
Kubernetes-native pattern for "run this periodically, then stop," and
matches FR-007's requirement that neither tool leaves a standing privileged
workload after it completes. kube-bench specifically needs to read
per-node kubelet configuration; this is done via a single Job whose pod is
scheduled onto (and reads config from) one representative node per run,
which is kube-bench's own documented Kubernetes deployment pattern, rather
than fanning out to every node like Falco must.

## Namespace: `security`, not `observability`

**Decision**: A new, dedicated `security` namespace hosts all three
components, separate from spec 006's `observability` namespace.

**Rationale**: Falco's DaemonSet needs `hostPID` and elevated Linux
capabilities that nothing in `observability` needs; keeping that trust
boundary in its own namespace with its own scoped RBAC/NetworkPolicy keeps
the blast radius of a Falco misconfiguration from touching the metrics/
logs/traces stack, and vice versa. This mirrors the existing convention of
one namespace per meaningfully distinct concern (`keda`, `cert-manager`,
`external-secrets`, `kyverno`, `observability` are all already separate).

## No genuine upstream bundle: hand-authored, digest-pinned, like spec 006's pattern

**Decision**: None of Falco, Falcosidekick, kube-bench, or kube-hunter ships
a raw-YAML installation bundle worth vendoring; all four are normally
installed via Helm chart (Falco/Falcosidekick) or a one-off `kubectl run`
(kube-bench/kube-hunter, per their own documented quickstart). Manifests
are hand-authored here with the same digest-pinning discipline as
`infrastructure/grafana`/`loki`/`jaeger`, and `vendor/<version>/README.md`
records image provenance only.

**Rationale**: Consistent with the precedent spec 006 already established
and validated for exactly this situation (no Helm, no operator, but a real
tool with real digest-pinned images).

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

**Decision**: Falco runs as a `DaemonSet`, one pod per node, with the
specific Linux capabilities its modern eBPF driver needs
(`[BPF, SYS_RESOURCE, PERFMON, SYS_PTRACE]`) and read-only host mounts for
`/proc`, `/boot`, `/lib/modules`, `/usr`, `/etc` - not `hostPID` and not a
fully `privileged` container (verified against the real Falco Helm chart's
`pod-template.tpl`, which sets neither for this driver choice).

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

**Decision**: kube-bench v0.16.0 runs with `--benchmark eks-1.5.0` and
`--targets node,policies,managedservices,controlplane` (the exact
invocation from kube-bench's own real `job-eks.yaml` for this version), not
the generic upstream Kubernetes CIS profile. `controlplane` stays in the
targets list even on EKS: that section of the `eks-1.5.0` benchmark checks
customer-configurable settings (e.g. audit logging), not anything requiring
direct access to the AWS-managed control plane itself, so it is not one of
the inapplicable checks this decision is about.

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
workload after it completes. kube-bench specifically needs `hostPID: true`
to inspect the kubelet process's live command-line flags for several CIS
controls (a real, verified need, unlike the `hostPID` this feature's own
earlier draft wrongly assumed Falco needed); it reads kubelet/API-server
config through mounted host paths and makes no Kubernetes API calls, so it
needs no `ServiceAccount`/`ClusterRole` at all - confirmed directly against
kube-bench's own real `job-eks.yaml`, which uses neither. This is kube-bench's
own documented Kubernetes deployment pattern, rather
than fanning out to every node like Falco must.

## Namespace: `security`, not `observability`

**Decision**: A new, dedicated `security` namespace hosts all three
components, separate from spec 006's `observability` namespace.

**Rationale**: Falco's DaemonSet needs Linux capabilities and host mounts
that nothing in `observability` needs; keeping that trust
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

## Trivy in the cluster: Trivy Operator 0.34.0 from its static bundle (amended 2026-09-13)

**Decision**: Trivy Operator 0.34.0 (released 2026-08-24, the latest
non-prerelease), running Trivy 0.74.0, from the upstream
`deploy/static/trivy-operator.yaml` at tag `v0.34.0`, vendored under
`infrastructure/trivy-operator/vendor/v0.34.0/` with a `SHA256SUMS` computed
at vendoring time. The release's own `checksums.txt` covers only the
operator binaries, not the static manifest, so the repository's checksum
records the reviewed file. Images are pinned by digest:
`mirror.gcr.io/aquasec/trivy-operator:0.34.0@sha256:0e4f11e9632f34097f259f3a59d34bab4eea8cee9aef510d15cdfc7481d5e49c`
and Trivy
`mirror.gcr.io/aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969`
(the same digest as `ghcr.io/aquasecurity/trivy:0.74.0`). The Trivy image is
set through `trivy.repository` and `trivy.tag` in the
`trivy-operator-trivy-config` ConfigMap, not a Pod spec, so its digest pin is
confirmed by rendering during implementation.

**Rationale**: Unlike Falco, kube-bench, and kube-hunter, Trivy Operator
publishes a raw-YAML bundle, so it follows the checksum-pinned vendoring of
`infrastructure/prometheus` rather than hand-authored manifests. The bundle
contains 12 CRDs, the operator Deployment, its ServiceAccount, RBAC, two
ConfigMaps, two Secrets, a metrics Service, and a `trivy-system` Namespace;
the Kustomize root drops that Namespace and sets `security`.

**Alternatives considered**: The Helm chart, rejected by this repository's
no-Helm convention; a hand-authored operator, rejected because an upstream
bundle exists.

## Trivy scanner scope and sizing (amended 2026-09-13)

**Decision**: In the `trivy-operator` ConfigMap, keep
`OPERATOR_VULNERABILITY_SCANNER_ENABLED: "true"` and set
`OPERATOR_CONFIG_AUDIT_SCANNER_ENABLED`, `OPERATOR_RBAC_ASSESSMENT_SCANNER_ENABLED`,
`OPERATOR_INFRA_ASSESSMENT_SCANNER_ENABLED`, `OPERATOR_EXPOSED_SECRET_SCANNER_ENABLED`,
`OPERATOR_CLUSTER_COMPLIANCE_ENABLED`, and `OPERATOR_SBOM_GENERATION_ENABLED`
to `"false"`. Set `OPERATOR_TARGET_NAMESPACES` to
`microtodo-dev,microtodo-staging,microtodo-prod,observability,security` (the
documented MultiNamespace install mode) and
`OPERATOR_CONCURRENT_SCAN_JOBS_LIMIT` from the upstream `"10"` to `"1"`. Keep
`OPERATOR_VULNERABILITY_SCANNER_SCAN_ONLY_CURRENT_REVISIONS: "true"`,
`OPERATOR_SCANNER_REPORT_TTL: "24h"`, `OPERATOR_SCAN_JOB_TIMEOUT: "5m"`, and
the upstream scan-job resources (requests 100m CPU and 100M memory, limits
500m and 500M).

**Rationale**: Clarifications 2026-09-13. Every other scanner either overlaps
kube-bench and kube-hunter or adds jobs and reports the economical
two-node cluster (`m7i-flex.large`) does not need; one scan at a time keeps
the peak bounded. The 24-hour report TTL gives SC-008 its window. Whether
vulnerability reports still populate with SBOM generation off is confirmed
by the rendered configuration and by the first live scan (T038).

## Trivy access to private ECR images (amended 2026-09-13)

**Decision**: A read-only IRSA role in `microservice-app-ops`
(`security-irsa.tf`) trusted only by
`system:serviceaccount:security:trivy-operator`, with ECR pull permissions
only, and the ServiceAccount annotated with its ARN.

**Rationale**: The business images are in private ECR. The node role has
`AmazonEC2ContainerRegistryPullOnly`, but the managed node group sets
`http_put_response_hop_limit = 1`, so pods cannot use the node's
credentials. Trivy Operator's managed-registries documentation prescribes an
IAM service account with ECR read access for Amazon ECR. Scan Jobs run in
the operator namespace with the operator's ServiceAccount:
`pkg/plugins/trivy/image.go` builds the Job with
`ServiceAccountName: ctx.GetServiceAccountName()`, which is
`OPERATOR_SERVICE_ACCOUNT` (default `trivy-operator`). The role follows the
existing Falcosidekick secrets-reader role's pattern and test file.

**Alternatives considered**: Filesystem scanning, where the kubelet pulls
the image and a root scan pod reads its filesystem inside each business
namespace, rejected because it runs root pods among business workloads and
needs egress opened there for the vulnerability database; image pull secrets
with static credentials, rejected by FR-017.

## Trivy findings: metrics, alert, and dashboard (amended 2026-09-13)

**Decision**: The operator's metrics endpoint (`:8080`, Service
`trivy-operator` port `metrics`) exposes `trivy_image_vulnerabilities` with
`severity`, `namespace`, `resource_name`, and image labels
(`OPERATOR_METRICS_FINDINGS_ENABLED: "true"`), with per-CVE series left off
(`OPERATOR_METRICS_VULN_ID_ENABLED: "false"`) to bound cardinality. A
ServiceMonitor in `infrastructure/prometheus/servicemonitors/` scrapes it, a
PrometheusRule in `infrastructure/prometheus/rules/` fires when a running
image has HIGH or CRITICAL vulnerabilities, and a small hand-authored
dashboard ConfigMap in `infrastructure/grafana/dashboards/` shows counts by
severity, namespace, and image.

**Rationale**: Clarifications 2026-09-13; this reuses spec 006's Prometheus,
Grafana, and Alertmanager with no new runtime component. The alert reaches
Slack only because spec 006 T053 sets `alertmanagerConfigMatcherStrategy`
to `None`: with the operator's `OnNamespace` default, the Slack route would
require `namespace="observability"`, while these alerts carry the scanned
workload's namespace. The public Grafana dashboard 17813 for Trivy Operator
was last updated in 2023, so a small dashboard for the metric this feature
uses is authored instead. The operator's `probes` port answers `/healthz/`
and `/readyz/`, so the startup probe convention (spec 006 T051, spec 008
T029) applies to it.

## Trivy network access (amended 2026-09-13)

**Decision**: A default-deny NetworkPolicy for the operator and its scan
Jobs in `security`, allowing DNS to `kube-system`, HTTPS egress (the
Kubernetes API, ECR, and the `mirror.gcr.io` vulnerability database), and
ingress to the metrics port from the Prometheus pods in `observability`.

**Rationale**: It follows Falcosidekick's policy shape. Scan Jobs download
the vulnerability database over HTTPS; blocking that would fail every scan
(a visible failure per the edge cases, but still a failure).

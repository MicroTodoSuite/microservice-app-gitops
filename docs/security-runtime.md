# Runtime Security

The economical profile runs its runtime security tools in the `security`
namespace. They are installed through the same activation-list registration as
the platform add-ons (`docs/platform-addons.md`) and the observability platform
(`docs/observability-platform.md`), and implement the runtime part of evolution
plan section 11: Falco for runtime detection, kube-bench and kube-hunter for
periodic audits, and Trivy scanning continuously in the cluster. Specification:
`specs/008-security-runtime-hardening`.

## Installed components

| Kustomize root | Pinned release | What runs | When | Findings |
| --- | --- | --- | --- | --- |
| `infrastructure/falco` | Falco 0.44.1 and Falcosidekick 2.34.1 | DaemonSet `falco` with the modern eBPF driver, the default rules, and the `container` plugin; Deployment `falcosidekick` | continuously | JSON output to Falcosidekick, which posts to Slack |
| `infrastructure/kube-bench` | kube-bench 0.16.0 | CronJob `kube-bench`: `kube-bench run --targets node,policies,managedservices,controlplane --benchmark eks-1.5.0` | `0 3 * * *` (daily) | Job log with PASS, FAIL, and WARN per CIS control and its remediation |
| `infrastructure/kube-hunter` | kube-hunter 0.6.8 | CronJob `kube-hunter`: `kube-hunter --pod` (internal, passive mode) | `0 4 * * 0` (weekly) | Job log listing discovered vulnerabilities with severity, or none |
| `infrastructure/trivy-operator` | Trivy Operator 0.34.0 running Trivy 0.74.0 | Deployment `trivy-operator`, vulnerability scanner only, one scan Job at a time | when a workload image changes, and when its 24-hour report expires | `VulnerabilityReport` resources, `trivy_image_vulnerabilities` metrics, the Trivy dashboard in Grafana, and the `RunningImageHighOrCriticalVulnerabilities` Slack alert |

Every executable image is selected by an immutable digest. Trivy Operator's
upstream static bundle is vendored unchanged with `SHA256SUMS` under
`infrastructure/trivy-operator/vendor/v0.34.0/`. Falco, Falcosidekick,
kube-bench, and kube-hunter publish no raw-manifest bundle for these releases,
so `infrastructure/<component>/vendor/<version>/README.md` records image
provenance and the adapted upstream job or chart values, and the manifests
beside it are repository-owned.

## The `security` namespace boundary

- Every resource these roots own is namespaced in `security`, and the
  `microtodosuite` AppProject allows that destination. The Trivy bundle's own
  `trivy-system` namespace is removed.
- Falco watches every node, because a DaemonSet is the only way to see
  syscalls. kube-bench needs `hostPID` and read-only host paths to inspect the
  kubelet, and makes no Kubernetes API calls, so it has no ServiceAccount token
  mounted. kube-hunter needs no host access and no RBAC; it only reaches the
  cluster's Service network.
- Trivy Operator scans only `microtodo-dev`, `microtodo-staging`,
  `microtodo-prod`, `observability`, and `security`. A workload outside those
  namespaces, such as `kube-system`, is not scanned; that is the decided
  boundary, not a way to hide a finding.
- Completed kube-bench and kube-hunter Jobs are removed after one hour
  (`ttlSecondsAfterFinished: 3600`), so no privileged workload stays behind.
- Falcosidekick, kube-hunter, and Trivy Operator and its scan Jobs each carry a
  default-deny NetworkPolicy plus the specific allowances they need.
- No component adds a service mesh or an mTLS dependency (spec 008 FR-009).

## Audit-only scope

Every tool here detects and reports; none enforces. Falco runs in audit mode:
it raises findings and sends them to Slack but blocks nothing. kube-bench and
kube-hunter read configuration and write a report. Trivy Operator adds no
admission webhook and never blocks, mutates, or restarts a workload. Any future
enforcement is a separate, reviewed change (spec 008 FR-004,
Audit-before-Enforce).

A finding is not dismissed by narrowing scope. Every HIGH or CRITICAL
vulnerability, and every finding from the other tools, ends in a remediation or
an explicit, justified, time-bounded exception (spec 008 FR-010).

## Secrets and identities

- Falcosidekick's Slack webhook comes from AWS Secrets Manager through an
  ExternalSecret and `SecretStore/aws-secrets-manager` in `security`, which
  authenticates as the ServiceAccount `security-external-secrets-jwt` with the
  IRSA role `microtodosuite-security-secrets-reader`. No webhook value is
  committed.
- Trivy Operator's ServiceAccount, which its scan Jobs also use, assumes the
  IRSA role `microtodosuite-security-trivy-ecr-reader` to pull the suite's
  private ECR images, because the nodes do not let pods reach instance metadata.
- Both roles are defined in `microservice-app-ops` under
  `aws/modules/environment-foundation/security-irsa.tf`.

## Registration and reconciliation

The components are activated through `clusters/eks-dev/activation-infrastructure.yaml`
with destination `security`, never discovered from the folder layout. Changes
and rollbacks follow the same path as every add-on: a reviewed commit, then
ArgoCD reconciliation, never a direct `kubectl apply`.

While `eks-dev` is quiesced (every activation list is exactly `value: []`, spec
009 T170), nothing in this document runs, and the static contract reports its
registration check as skipped rather than passed.

## Validation

Static validation is cluster-free:

```bash
./tests/contract/security.sh
```

It renders the four roots and checks the vendored checksum and digest-pinned
images; Falco's modern eBPF driver without `privileged`, `hostPID`, or a
ClusterRole; Falcosidekick's Slack webhook from the ExternalSecret; kube-bench's
`eks-1.5.0` profile and kube-hunter's passive `--pod` mode, both without a
ClusterRole or a Job left behind; Trivy Operator's `security`-only render,
scanner and namespace settings, and ECR reader role; liveness, readiness, and
startup probes on Falcosidekick and Trivy Operator; and the registration
contract.

The read-only live verifier collects evidence under
`evidence/runs/<timestamp>-security/`:

```bash
./scripts/managed/verify-security.sh --context eks-dev
```

It only reads: the Falco pods' logs from the last 24 hours, and the logs of the
newest kube-bench and kube-hunter Jobs. When there is no finding or no run yet,
it reports BLOCKED and names the trigger to activate; it never creates a Job or
runs a command inside a pod (spec 009 T088).

Triggers are checked-in Jobs that no kustomization includes:
`infrastructure/kube-bench/triggers/` and `infrastructure/kube-hunter/triggers/`
repeat their CronJob's job spec, and `infrastructure/falco/triggers/` runs
`find /tmp -name id_rsa` in its own non-root Job, which Falco's stable rule
"Search Private Keys or Passwords" reports. To collect evidence, add `- triggers`
to that component's `kustomization.yaml` resources in a reviewed pull request,
let ArgoCD sync, run the collector, and revert the commit
(`specs/008-security-runtime-hardening/quickstart.md`). The collector has not
run against a cluster yet; live acceptance for spec 008 waits for the
economical cluster to be rebuilt.

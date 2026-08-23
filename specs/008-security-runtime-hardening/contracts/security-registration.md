# Security Registration Contract

## Discovery contract

`clusters/base/infrastructure.yaml`'s `infrastructure` ApplicationSet uses a
`list` generator with an empty base element list; folder discovery is
intentionally forbidden. Activation happens only through `clusters/eks-dev/
activation-infrastructure.yaml`'s `op: replace` patch. This feature appends
three elements to that patch:

| Application (`infra-{{name}}`) | Source path | Destination namespace |
| --- | --- | --- |
| `infra-falco` | `infrastructure/falco` | `security` |
| `infra-kube-bench` | `infrastructure/kube-bench` | `security` |
| `infra-kube-hunter` | `infrastructure/kube-hunter` | `security` |

Every generated Application inherits from the shared template: the
registration-injected repository URL/revision, the in-cluster Kubernetes API
as destination, automated prune and self-heal, `CreateNamespace=true`,
`argocd.argoproj.io/sync-wave: "0"` (alongside every other platform add-on),
and membership in the `microtodosuite` AppProject trust boundary.

## AppProject impact

Falco's DaemonSet needs a `ClusterRole`/`ClusterRoleBinding` (already
generically whitelisted, same as every other add-on's RBAC) and no CRDs of
its own. kube-bench/kube-hunter's Jobs need only namespace-scoped `Role`/
`RoleBinding` plus a `ClusterRole`/`ClusterRoleBinding` limited to read-only
verbs on nodes/pods (also covered by the existing generic RBAC whitelist
entries). No new `clusterResourceWhitelist` entry is required.

## Component folder contract

Every component folder must contain:

- `kustomization.yaml` as the only ArgoCD entry point;
- no upstream bundle under `vendor/<version>/` (none of the three tools has
  one) - instead `vendor/<version>/README.md` records image source and
  digest provenance only;
- immutable image transforms (digest, never a tag) for every executable
  image;
- no `Ingress`, `Certificate`, or auth-proxy resource (nothing in this
  feature exposes an external endpoint);
- no enforcement/blocking configuration - Falco stays in alert-only output
  mode, and kube-bench/kube-hunter never mutate cluster state (FR-004,
  FR-007).

## Live controller contract

| Namespace | Expected controllers |
| --- | --- |
| `security` | `falco` (DaemonSet, one pod per node), `falcosidekick` (Deployment), `kube-bench` (CronJob), `kube-hunter` (CronJob) |

Passing means: Falco's DaemonSet has `.status.numberReady ==
.status.desiredNumberScheduled` with no pod Pending/Failed/CrashLoopBackOff;
`falcosidekick`'s Deployment has all desired replicas Available; both
CronJobs exist with a valid schedule and their most recent triggered Job
completed (`.status.succeeded == 1`) without leaving a running pod behind.

## Capability contract

- Falco: a deliberately triggered anomalous action (e.g. `kubectl exec` an
  interactive shell into a running business-workload pod) produces a Falco
  finding identifying the exact rule, pod, and namespace.
- Falcosidekick: that same finding produces a real Slack message in the
  channel spec 006 already uses, within 1 minute.
- kube-bench: a triggered (or scheduled) run produces a report with a real
  PASS/FAIL/WARN status for every `eks` target profile control, plus
  remediation text for any FAIL.
- kube-hunter: a triggered (or scheduled) run produces a report of real
  discovered vulnerabilities (or an explicit "none found") with severity,
  with zero disruption to any running business workload.

## Provider-neutrality and cost contract

No component introduces a new AWS IAM role, IRSA binding, managed AWS
security service (GuardDuty, Security Hub, Inspector), or Azure dependency.
Falco's Slack webhook is delivered the same way spec 006's Alertmanager
webhook is (ExternalSecret/SecretStore, currently a disclosed placeholder
IRSA role ARN pending the real IAM role from `microservice-app-ops`). No
component depends on Istio or any service-mesh resource. kube-bench and
kube-hunter's Jobs use `ttlSecondsAfterFinished` so no cost is incurred
between scheduled runs.

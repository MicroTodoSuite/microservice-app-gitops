# Observability Registration Contract

## Discovery contract

`clusters/base/infrastructure.yaml`'s `infrastructure` ApplicationSet uses a
`list` generator with an empty base element list — its own comment states
plainly that "folder discovery is intentionally forbidden: adding a directory
must never activate a controller or shared dependency implicitly." Activation
happens only through `clusters/eks-dev/activation-infrastructure.yaml`'s
`op: replace` patch over that element list. This feature appends four
elements to that patch (it does not touch any other cluster's registration):

| Application (`infra-{{name}}`) | Source path | Destination namespace |
| --- | --- | --- |
| `infra-prometheus` | `infrastructure/prometheus` | `observability` |
| `infra-grafana` | `infrastructure/grafana` | `observability` |
| `infra-loki` | `infrastructure/loki` | `observability` |
| `infra-jaeger` | `infrastructure/jaeger` | `observability` |

Every generated Application inherits from the shared template:

- the registration-injected repository URL and revision;
- the in-cluster Kubernetes API as destination;
- automated prune and self-heal;
- `CreateNamespace=true`;
- `argocd.argoproj.io/sync-wave: "0"` (before business applications at wave
  1, alongside every other platform add-on);
- membership in the exact `microtodosuite` AppProject trust boundary — this
  feature's Kyverno review MUST confirm no new cluster-scoped resource kind
  is introduced beyond what the pinned bundles already require, or the
  AppProject's exact-kind allowlist needs a corresponding, reviewed addition.

## Component folder contract

Every component folder must contain:

- `kustomization.yaml` as the only ArgoCD entry point;
- one retained upstream bundle under `vendor/<version>/` for `prometheus`
  only (`kube-prometheus` ships a genuine tagged-release manifest artifact);
  `grafana`, `loki`, and `jaeger` are hand-authored/
  first-party — no upstream raw-YAML bundle exists for any of them outside
  Helm or an operator, which this project's no-Helm convention avoids — and
  are exempt from the vendor-bundle requirement, matching the precedent
  already set by `infrastructure/redis` in `003-platform-addons`;
- `vendor/<version>/README.md` with image source and digest provenance for
  every component, and additionally the regeneration/download command for
  `prometheus`'s bundle;
- `vendor/<version>/SHA256SUMS` matching the retained bundle, for
  `prometheus` only;
- immutable image transforms (digest, never a tag) for every executable
  image, vendored or first-party;
- no `Ingress`, `Certificate`, or auth-proxy resource for any observability
  UI (Grafana, Jaeger, or the log viewer) — access is `kubectl port-forward`
  only per FR-017;
- no `Elasticsearch`, `Logstash`, `Kibana`, or `Filebeat` resource anywhere
  under `infrastructure/loki/` or `infrastructure/jaeger/`.

Vendor manifests are never edited after their checksum is recorded. Required
customization (namespace, resource limits, storage class, digest pins) is
expressed by Kustomize transforms or patches beside the bundle, exactly as
`003-platform-addons` established.

## Live controller contract

| Namespace | Expected controllers |
| --- | --- |
| `observability` | `prometheus-operator`, `prometheus-<instance>` (StatefulSet), `alertmanager-<instance>` (StatefulSet), `grafana`, `loki` (StatefulSet), `grafana-alloy` (DaemonSet), `jaeger` |

Passing means `.status.availableReplicas == .spec.replicas` (or the
StatefulSet/DaemonSet equivalent) for every listed controller and no pod is
Pending, Failed, Unknown, or CrashLoopBackOff.

## Capability contract

- Prometheus: a live query against `up{namespace="microtodo-dev"}` returns a
  non-empty result for all five business-workload targets.
- Grafana: the golden-signal dashboard for each business workload renders
  panel data sourced from a real, recent Prometheus query (not "No data").
- Alertmanager: an injected test condition produces one firing notification
  and, once cleared, one resolved notification in the configured Slack
  channel.
- Loki: a log line written by a business workload pod is retrievable by
  workload label within the ingestion delay documented in `quickstart.md`.
- Jaeger: a trace for a real `auth-api` request is retrievable by its
  `trace_id`, and that same `trace_id` appears in the correlated Loki log
  line.
- Argo Rollouts `ClusterAnalysisTemplate`: an injected canary revision with a
  5xx ratio above 5% is aborted and rolled back within 5 minutes; a canary
  revision at or below that ratio promotes normally.

## Business-workload metrics contract

- `auth-api`, `todos-api`: existing `/metrics` endpoint gains a request-
  duration Histogram alongside the existing Counter; no existing metric name
  or label is removed or renamed.
- `users-api`, `log-message-processor`: no code change; existing Micrometer/
  `prometheus_client` instrumentation already satisfies FR-003.
- `frontend`: gains an `nginx-prometheus-exporter` sidecar container in its
  Deployment (owned by that repository's overlay, not by this repository's
  `infrastructure/` folders); `frontend`'s own image and `Dockerfile` from
  the prior hardening work are not modified.
- No metric or log label introduced by any of the above may carry
  unbounded-cardinality values (user ID, todo ID, request ID, full path with
  parameters).

## Provider-neutrality and cost contract

No component introduces a new AWS IAM role, IRSA binding, managed AWS
observability service (CloudWatch, AMP, AMG, X-Ray), or Azure dependency.
Every PVC uses the cluster's existing default `gp3` StorageClass. No
component depends on Istio or any service-mesh resource.

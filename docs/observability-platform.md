# Observability Platform

The economical profile runs one observability stack in the `observability`
namespace. It is installed through the same activation-list registration as the
platform add-ons (`docs/platform-addons.md`) and implements evolution plan
section 10 with the substitutions that section 17 allows for the economical
profile. Specifications: `specs/006-observability-platform-foundation`
(platform), `specs/010-service-tracing` (traces), and
`specs/011-service-metrics` (service and business metrics).

## Installed components

| Kustomize root | Pinned release | What runs | Storage and retention |
| --- | --- | --- | --- |
| `infrastructure/prometheus` | kube-prometheus v0.18.0 (Prometheus Operator v0.92.0, Prometheus v3.12.0, Alertmanager v0.33.0) | the operator, Prometheus `k8s` with one replica, Alertmanager `main`, ServiceMonitors for the five business workloads and their canary Services, golden-signal recording rules and alerts, and the Trivy vulnerability alert | 10Gi `gp3` volume, 15 days |
| `infrastructure/grafana` | Grafana 13.2.0 | Deployment `grafana` with Prometheus, Loki, and Jaeger datasources and the golden-signals and Trivy vulnerability dashboards, provisioned from ConfigMaps | not applicable |
| `infrastructure/jaeger` | Jaeger 2.20.0 all-in-one | Deployment `jaeger`, receiving OTLP directly on `jaeger-collector` (gRPC 4317, HTTP 4318) and serving its UI on `jaeger-query` (16686) | embedded Badger storage on `jaeger-storage`, spans kept 72 hours |
| `infrastructure/loki` | Loki 3.7.6 and Grafana Alloy 1.18.1 | StatefulSet `loki` in single-binary mode, and Deployment `alloy`, which tails the suite's pods in `microtodo-dev` through the Kubernetes API (no DaemonSet, no hostPath) | filesystem storage on a 10Gi `gp3` volume, 72 hours |

The canary gate lives with Argo Rollouts: `infrastructure/argo-rollouts/cluster-analysis-template.yaml`
defines `ClusterAnalysisTemplate/microtodosuite-canary-health`.

Every executable image is selected by an immutable digest. The kube-prometheus
bundle is vendored unchanged with `SHA256SUMS` under
`infrastructure/prometheus/vendor/v0.18.0/`. Grafana, Jaeger, and Loki publish no
raw-manifest bundle, so `infrastructure/<component>/vendor/<version>/README.md`
records image provenance and the manifests beside it are repository-owned.

## Signals

- **Metrics.** Each business workload exposes `/metrics`, and the ServiceMonitors
  scrape it, together with a separate `revision="canary"` series from each
  canary Service. Recording rules produce `workload:http_requests:rate5m`,
  `workload:http_errors:ratio5m`, and
  `workload:http_request_duration_seconds:avg5m`. `auth-api`, `todos-api`, and
  `log-message-processor` record through OpenTelemetry's Prometheus exporter
  and add the business counters `todo_api_todos_created_total`,
  `todo_api_todos_deleted_total`, and `auth_api_sign_ins_total{outcome}`.
  `users-api` (Micrometer) and `frontend` (nginx exporter) are the documented
  exceptions in spec 011.
- **Traces.** Every service's base ConfigMap sets
  `OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger-collector.observability.svc:4317`,
  so each environment inherits the same destination. Services propagate W3C
  trace context and export OTLP over gRPC straight to Jaeger; there is no
  separate OpenTelemetry Collector. Probe and scrape requests create no spans.
- **Logs.** Alloy ships pod logs to Loki. `trace_id` and `span_id` become
  structured metadata, never labels, so they add no label cardinality. Logs are
  read in Grafana through the Loki datasource.
- **Alerts.** PrometheusRules fire in Alertmanager `main`, and
  `AlertmanagerConfig/slack-golden-signals` routes them to `#microtodosuite-alerts`,
  grouped by `workload` and `alertname`, with resolved notifications.
  Alertmanager sets `alertmanagerConfigMatcherStrategy: None`; with the default
  `OnNamespace`, alerts that carry no `namespace` label never match the route.
- **Canary gate.** `microtodosuite-canary-health` reads
  `workload:http_errors:ratio5m{revision="canary"}` every 30 seconds, three
  times, and fails the analysis when the ratio exceeds 0.05 (5% over the rule's
  5-minute window).
- **Probes.** Grafana, Jaeger, Loki, Alloy, and the frontend's `nginx-metrics`
  sidecar declare liveness, readiness, and startup probes, like the five
  business services.

## Economical-profile substitutions

| Full profile (spec 009) | Economical profile |
| --- | --- |
| Logs to Elasticsearch, Logstash, and Kibana, collected by Filebeat | Logs to Loki, collected by Grafana Alloy |
| Jaeger with an Elasticsearch backend | Jaeger all-in-one with embedded Badger storage and 72-hour retention |
| Prometheus, Alertmanager, and Grafana on encrypted volumes of the destination cloud | Prometheus and Grafana on `gp3` volumes; Alertmanager keeps silences in memory |
| mTLS through Istio | No service mesh |

Both profiles run one replica of each component: spec 009 `research.md`
Decision 10 trades high availability for the account's quota.

The full-profile roots (`infrastructure/elasticsearch`, `logstash`, `kibana`,
`filebeat`, `istio`) stay inert in the economical profile.
`tests/contract/observability.sh` rejects Elasticsearch, Logstash, Kibana, and
Filebeat resources in the Prometheus and Grafana roots.

## Full-profile roots

Spec 009 T085 completes this stack for the full profile
(`specs/009-full-platform-rollout/research.md` Decision 21). Each full-profile
root takes the economical `infrastructure/<component>/` root as its base and
changes only what the full profile needs, so the economical render does not change. No cluster activates
them yet; each full cluster's activation list (spec 009 T091) names the root for
its cloud.

| Root | Cloud | What it changes |
| --- | --- | --- |
| `infrastructure/profiles/full/prometheus/aws` | EKS | adds a 1Gi `gp3` volume to Alertmanager `main`; Prometheus keeps its 10Gi `gp3` volume |
| `infrastructure/profiles/full/prometheus/azure` | AKS | moves the Prometheus volume to `managed-csi` and adds a 1Gi `managed-csi` volume to Alertmanager `main` |
| `infrastructure/profiles/full/grafana/aws` | EKS | nothing yet; Grafana keeps its 2Gi `gp3` volume |
| `infrastructure/profiles/full/grafana/azure` | AKS | moves `grafana-storage` to `managed-csi` |

On EKS, `infrastructure/ebs-csi-driver` declares `gp3` with `encrypted: "true"`.
On AKS, `managed-csi` is the built-in Standard SSD Azure Disk class, and Azure
encrypts managed disks at rest with platform-managed keys. With a volume,
Alertmanager keeps its silences and notification log across restarts.
`tests/platform/observability-full.bats` checks both clouds and that the
economical roots stay as they are.

Both full Prometheus roots also include the Component
`infrastructure/profiles/full/prometheus/components/alerts`, which adds
`PrometheusRule/full-profile-alerts` and the monitors that scrape its sources.
Every alert sets `workload` to the object it is about, so the existing Slack
route groups and titles it.

| Alert | Source and condition | Severity |
| --- | --- | --- |
| `WorkloadHighP99Latency` | `workload:http_request_duration_seconds:p99_5m{revision="stable"}` above 2 seconds for 5 minutes, the production canary threshold | warning |
| `KedaScaledObjectErrors` | `keda_scaled_object_errors_total` increasing for 10 minutes | warning |
| `ArgoCdApplicationUnhealthy` | `argocd_app_info` health `Degraded` or `Missing` for 15 minutes | critical |
| `ArgoCdApplicationOutOfSync` | `argocd_app_info` `OutOfSync` for 30 minutes | warning |
| `ExternalSecretNotReady` | `externalsecret_status_condition{condition="Ready",status="False"}` for 15 minutes | warning |
| `CertificateNotReady` | `certmanager_certificate_ready_status{condition="False"}` for 15 minutes | warning |
| `CertificateExpiresSoon` | `certmanager_certificate_expiration_timestamp_seconds` less than 14 days away for 1 hour | critical |
| `KyvernoAdmissionDenied` | `kyverno_admission_requests_total{request_allowed="false"}` increasing | warning |
| `FalcosidekickSlackDeliveryFailing` | `falcosecurity_falcosidekick_outputs_total{destination="slack",status="error"}` increasing | critical |

Prometheus scrapes those sources through ServiceMonitors for `keda/keda-operator`,
`argocd/argocd-metrics`, `cert-manager/cert-manager`,
`kyverno/kyverno-svc-metrics`, and `security/falcosidekick`, and a PodMonitor for
the External Secrets controller, whose bundle ships no metrics Service. The KEDA,
Argo CD, cert-manager, and External Secrets monitors set `honorLabels: true`:
those exporters report the namespace of the object a series describes, which
Prometheus would otherwise rename to `exported_namespace`. Falco events are not
alerted on again; falcosidekick already sends them to Slack.

The rest of T085 lands in the same roots: Jaeger on the Elasticsearch backend
with trace-to-log correlation in Grafana, and notifications that name the cluster
and environment.

## Access model

Grafana, the Jaeger UI, and the log view are reached only through
`kubectl port-forward` (spec 006 FR-017), the access pattern the local pilot
uses. No component adds an Ingress, a TLS certificate, or an authentication or
SSO integration; those belong to the full profile.

```bash
kubectl --context eks-dev -n observability port-forward svc/grafana 3000:3000
kubectl --context eks-dev -n observability port-forward svc/jaeger-query 16686:16686
kubectl --context eks-dev -n observability port-forward svc/prometheus-k8s 9090:web
```

The Grafana administrator password is generated inside the cluster by an
External Secrets `Password` generator into Secret `grafana-admin-credentials`;
no value is committed. Grafana, Jaeger, Loki, and Alloy each carry a
default-deny NetworkPolicy plus the specific allowances they need (for example
`jaeger-allow-otlp-and-query` and `loki-allow-ingestion-and-query`).

## Secrets and identities

The Slack webhook never appears in Git. `ExternalSecret/alertmanager-slack-webhook`
reads `microtodosuite/observability/alertmanager-slack-webhook` from AWS Secrets
Manager through `SecretStore/aws-secrets-manager`, which authenticates as the
ServiceAccount `observability-external-secrets-jwt`. That ServiceAccount assumes
the IRSA role `microtodosuite-observability-secrets-reader`, defined in
`microservice-app-ops` under
`aws/modules/environment-foundation/observability-irsa.tf`. The observability
roots own no other AWS identity.

## Registration and reconciliation

`clusters/eks-dev/activation-infrastructure.yaml` names `prometheus`,
`grafana`, `jaeger`, and `loki`, each destined for `observability`, and the
`microtodosuite` AppProject allows that namespace. The Prometheus Operator CRDs
are namespaced and therefore stay out of the AppProject's cluster-resource
allowlist. Changes and rollbacks follow the same path as every add-on: a
reviewed commit, then ArgoCD reconciliation, never a direct `kubectl apply`.

While `eks-dev` is quiesced (every activation list is exactly `value: []`, spec
009 T170), nothing in this document runs, and the static contract reports its
registration check as skipped rather than passed.

## Validation

Static validation is cluster-free:

```bash
./tests/contract/observability.sh
./tests/contract/service-tracing.sh
```

`observability.sh` renders the four roots and checks the vendored checksum,
digest-pinned images, the expected resources, the three probes on Grafana,
Jaeger, Loki, Alloy, and `nginx-metrics`, Slack routing, retention, the port-forward-only boundary, secret hygiene, the canary
template, the dashboard ConfigMaps, and the registration contract.
`service-tracing.sh` checks that every service in every economical environment
takes the Jaeger OTLP endpoint from its base ConfigMap, that no overlay
overrides it, and that business pods may reach Jaeger's OTLP/gRPC port and
nothing else there.

The read-only live verifier collects evidence under
`evidence/runs/<timestamp>-observability/`:

```bash
./scripts/managed/verify-observability.sh --context eks-dev
```

It is still a skeleton that has not run against a cluster. Live acceptance for
specs 006, 010, and 011 waits for the economical cluster to be rebuilt.

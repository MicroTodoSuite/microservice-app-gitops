# Implementation Plan: Observability Platform Foundation

**Branch**: `feat/observability-platform-foundation` | **Date**: 2026-08-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/006-observability-platform-foundation/spec.md`

## Summary

Deploy the economical-profile observability stack from `plan.md` sections 10
and 17 onto the live `eks-dev` cluster: Prometheus Operator (managing
Prometheus and Alertmanager as CRDs), Grafana, Loki with Grafana Alloy as its
log shipper, and Jaeger with embedded storage, all vendored and
checksum-pinned exactly like `keda`/`cert-manager`/`external-secrets`/
`kyverno`. Four of the five business workloads already expose real Prometheus
metrics today (discovered in this repository, not assumed); the gap is a
missing latency histogram in two of them and a missing exporter for
`frontend`, not building metrics from scratch. `auth-api` is instrumented with
the OpenTelemetry Go SDK, replacing its Zipkin exporter, exporting OTLP
directly to Jaeger (Jaeger 2.x is itself built on the OpenTelemetry Collector
core and receives OTLP natively, so no separate Collector component is
needed for a single pilot service - a correction made during implementation
after verifying Jaeger's real current architecture, see research.md), and
the existing Argo Rollouts `ClusterAnalysisTemplate` is updated to query real
error-rate metrics instead of its synthetic curl probe.

## Technical Context

**Language/Version**: Kubernetes YAML; Kustomize v5; Go 1.26 (`auth-api`
instrumentation change only, no other service code changes in this feature,
matching its own `go.mod`)

**Primary Dependencies**: kube-prometheus v0.18.0 (Prometheus Operator
v0.92.0, Prometheus v3.12.0, Alertmanager v0.33.0 - real current releases,
verified via the GitHub API and `docker buildx imagetools inspect`), Grafana
13.2.0, Loki 3.7.6 (single-binary/monolithic mode), Grafana Alloy 1.18.1 (log
shipper, DaemonSet), Jaeger 2.20.0 (all-in-one, Badger embedded storage,
OTLP-native), OpenTelemetry Go SDK 1.45.0 + `otelecho`/`otelhttp` (contrib
v0.70.0)

**Storage**: Prometheus TSDB on a namespace-scoped PVC (short retention, sized
for metrics only); Loki filesystem storage on a PVC (3-day retention per
FR-011); Jaeger Badger embedded storage on a PVC (3-day retention per FR-009);
Grafana's own SQLite state on a small PVC for dashboard provisioning
durability. No new AWS service is introduced; all PVCs use the EKS cluster's
existing default `gp3` StorageClass.

**Testing**: Kustomize render + `kubeconform`, SHA-256 vendor-checksum
verification, a Bash contract script (mirroring
`tests/contract/platform-addons.sh`) checking pinned versions, checksums,
absence of Elasticsearch/ELK references, absence of Ingress/TLS resources for
observability UIs, and label-cardinality rules; a read-only live verification
script capturing ArgoCD status, a real Prometheus query result, a fired-and-
resolved test alert, a retrieved Jaeger trace, and a Loki log search — the
same evidence discipline as `003-platform-addons`'s pilot verifier.

**Target Platform**: Live `eks-dev` EKS cluster, `dev` namespace business
workloads as the metrics/alerting/tracing/logging source; a single new
`observability` namespace hosts every platform component from this feature.

**Project Type**: GitOps desired-state repository (this repo) plus one
minimal, non-OTel Prometheus-client change to two existing service repos
(`auth-api`, `todos-api`) and one full OpenTelemetry cutover in a third
(`auth-api` again, for tracing/logs). No new service or repository is
created.

**Performance Goals**: All observability components synchronized and healthy
within 10 minutes of the final commit reaching `gitops` (SC-001); canary
abort within 5 minutes of a 5xx ratio exceeding 5% (SC-004); Slack alert
within 5 minutes of a breach (SC-005).

**Constraints**: GitOps-only; no Istio/service mesh; no public Ingress, TLS
certificate, or auth/SSO for any observability UI (`kubectl port-forward`
only, per FR-017); Loki not ELK, Jaeger with embedded storage not
Elasticsearch (per the Clarifications session, grounded in `plan.md` section
17's economical-profile table); 3-day retention for logs and traces; no
unbounded-cardinality metric or log labels; Slack webhook only via External
Secrets Operator, never committed; any new admission policy MUST go through
Audit before Enforce.

**Scale/Scope**: One new namespace, four new ArgoCD-owned infrastructure
Applications (`prometheus`, `grafana`, `loki`, `jaeger`),
one updated `ClusterAnalysisTemplate`, one existing service (`auth-api`) fully
instrumented with OpenTelemetry, two existing services (`auth-api`,
`todos-api`) gaining a small latency histogram alongside their existing
Prometheus counters, one existing service (`frontend`) gaining an
`nginx-prometheus-exporter` sidecar. `users-api` and `log-message-processor`
need no code change — their existing Micrometer/Prometheus-client
instrumentation already covers the required golden signals.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Gate | Design response |
| --- | --- | --- |
| Environment Isolation | PASS | All new components live in one namespace-scoped `observability` namespace on the existing `eks-dev` cluster; no new cluster or VPC. |
| GitOps-Only Deployment | PASS | Every component ships as a vendored Kustomize root reconciled by ArgoCD; no direct cluster mutation outside the audited bootstrap boundary. |
| Stable Trunk Development | PASS | Work proceeds on the short-lived `feat/observability-platform-foundation` branch, mirroring `feat/`/`chore/` naming already used for this contributor's Dockerfile-hardening work. |
| Authoritative Specifications | PASS | spec → clarify → this plan → tasks precede any manifest or code change. |
| Cost-Governed Design | PASS | Single-binary Loki, all-in-one Jaeger, and 3-day retention are chosen specifically to minimize resource footprint on the shared bootstrap node group; no managed AWS observability service is introduced. |
| Immutable Build Promotion | PASS | `auth-api`'s instrumentation change goes through the existing CI→SBOM→Cosign→Kyverno chain like any other change; no new image-build path is introduced. |
| Progressive and Reversible Releases | PASS | Each component lands as its own commit; the `ClusterAnalysisTemplate` change is a separate, revertible commit from the add-on installs it depends on. |
| Quality and Supply-Chain Gates | PASS | Vendored bundles are checksum-verified; `auth-api`'s CI already runs Trivy/SBOM/Cosign/Kyverno on every change, including this one. |
| Observable and Resilient Operations | PASS | This feature exists to close exactly this principle's disclosed gap ("OpenTelemetry, Jaeger, Prometheus/Grafana, Loki, and Alertmanager are not active on EKS"). Istio remains untouched and unused. |
| Least Privilege and Secret Hygiene | PASS | The Slack webhook is delivered only through External Secrets Operator; no observability component gains a new AWS IAM/IRSA role in this feature (none needs one). |
| Declarative and Policy-Controlled Platform | PASS | All four components are ArgoCD-owned under `infrastructure/`, added to the existing `eks-dev` activation list, matching the existing ownership boundary exactly. |
| Proven DR and Disclosed Data Loss | PASS | No DR claim is made; 3-day retention and PVC-backed (not replicated) storage are explicitly disclosed constraints, not hidden gaps. |

Post-design re-check: PASS. Phase 1 design (below) introduces no Ingress, no
new IAM role, no Elasticsearch dependency, and no cluster-wide wildcard
permission; every new component is namespace-scoped and GitOps-owned.

## Project Structure

### Documentation (this feature)

```text
specs/006-observability-platform-foundation/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── observability-registration.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
clusters/eks-dev/
└── activation-infrastructure.yaml   # five new entries appended, namespace observability

infrastructure/
├── prometheus/
│   ├── kustomization.yaml
│   ├── prometheus.yaml               # Prometheus + Alertmanager custom resources
│   ├── alertmanager-config.yaml      # AlertmanagerConfig, Slack route via ESO secret ref
│   ├── rules/
│   │   └── golden-signals.yaml       # PrometheusRule: error-rate/latency/saturation/traffic
│   ├── servicemonitors/
│   │   └── business-workloads.yaml   # ServiceMonitor per business workload
│   └── vendor/v0.16.0/{manifests.yaml,README.md,SHA256SUMS}
├── grafana/
│   ├── kustomization.yaml
│   ├── deployment.yaml               # image pinned by digest
│   ├── dashboards/
│   │   └── golden-signals-*.json     # one per business workload
│   └── datasources.yaml              # Prometheus + Loki + Jaeger datasources
├── loki/
│   ├── kustomization.yaml
│   ├── loki.yaml                     # single-binary StatefulSet, image pinned by digest
│   ├── alloy.yaml                    # DaemonSet log shipper, image pinned by digest
│   └── vendor/v3.7.6/README.md       # image source/digest provenance only, no bundle
└── jaeger/
    ├── kustomization.yaml
    ├── jaeger-allinone.yaml          # image pinned by digest, Badger PVC, OTLP-native
    ├── config.yaml                   # trimmed real upstream all-in-one config
    └── vendor/v2.20.0/README.md      # image source/digest provenance only, no bundle

apps/auth-api/
├── base/ (unchanged: Deployment env vars for OTLP endpoint added via overlay)
└── overlays/dev/
    └── kustomization.yaml             # OTEL_EXPORTER_OTLP_ENDPOINT patch, points at Jaeger directly

infrastructure/argo-rollouts/
└── cluster-analysis-template.yaml    # updated: Prometheus error-rate query replaces curl

scripts/pilot/ (or scripts/managed/, matching existing convention)
└── verify-observability.sh           # read-only composite live evidence

tests/contract/
└── observability.sh                  # static provenance/render/no-ELK/no-Ingress contract

# In the auth-api repo (separate repository, referenced not owned here):
# tracing.go removed, replaced by otel.go (SDK init, OTLP exporter, Semantic Conventions)
# main.go: /metrics histogram added, otelecho middleware added, structured JSON logging with trace_id/span_id
```

**Structure Decision**: Reuse the exact `infrastructure/<capability>/` +
explicit `activation-infrastructure.yaml` registration pattern already
established by `003-platform-addons`, one Kustomize root per component so
ArgoCD keeps a 1:1 Application-to-capability mapping. Only Prometheus
Operator (via `kube-prometheus`) ships a genuine upstream release-manifest
bundle worth vendoring under `vendor/<version>/`; Grafana, Loki (single-
binary mode), and Jaeger (all-in-one mode) have no equivalent upstream
bundle — each is normally installed via Helm or an operator this project's
no-Helm convention avoids — so their manifests are
hand-authored in this repo with the same digest-pinning discipline used
elsewhere (`newName@sha256:...`, never a tag), and their `vendor/<version>/
README.md` records image source and digest provenance only, not a bundle
checksum. `auth-api`'s code change is scoped to that repository and only
referenced here through the overlay env-var patch that points it directly at Jaeger's
OTLP receiver.

## Complexity Tracking

No constitution violation or exception is required.

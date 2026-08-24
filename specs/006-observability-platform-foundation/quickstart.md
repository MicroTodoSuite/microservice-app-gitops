# Quickstart: Validate the Observability Platform Foundation

Run from the repository root. Unlike `003-platform-addons`'s disposable local
`kind` pilot, this feature targets the real, live `eks-dev` cluster
(`ops @ main`, account `916491575487`, `us-east-1`).
Every step below either renders/observes read-only, or is a normal committed
PR to `main` that ArgoCD reconciles — never a direct `kubectl apply` against
the managed cluster.

## 1. Static contract

```bash
./tests/contract/observability.sh
```

Expected: all five Kustomize roots (`prometheus`, `grafana`, `loki`, `jaeger`,
`jaeger`) render, vendor bundle checksums match where a bundle
exists, every rendered image is pinned by digest, the infrastructure
ApplicationSet's activation list contains exactly the five expected new
elements at namespace `observability`, no `Ingress`/`Certificate` resource
exists for any observability UI, and no `Elasticsearch`/`Logstash`/`Kibana`/
`Filebeat` resource exists anywhere under `infrastructure/loki/` or
`infrastructure/jaeger/`.

Optional schema validation when `kubeconform` is installed:

```bash
for addon in prometheus grafana loki jaeger; do
  kustomize build "infrastructure/$addon" |
    kubeconform -strict -ignore-missing-schemas -summary
done
```

## 2. Get read access to the live cluster

```bash
aws eks update-kubeconfig \
  --name "$(terraform -chdir=../microservice-app-ops/aws/environments/dev/foundation output -raw cluster_name)" \
  --region us-east-1 \
  --alias eks-dev
```

## 3. Publish through a short-lived branch and PR (Trunk-Based Development)

```bash
git checkout -b feat/observability-platform-foundation
# stage changes per tasks.md, one reviewable commit per stage:
#   1. infrastructure/prometheus (Operator + Prometheus + Alertmanager CRs, ServiceMonitors, rules)
#   2. infrastructure/grafana (datasources, golden-signal dashboards)
#   3. infrastructure/loki (Loki + Alloy)
#   4. infrastructure/jaeger (all-in-one, Badger storage, OTLP-native)
#   5. clusters/eks-dev/activation-infrastructure.yaml (append the four entries)
#   6. infrastructure/argo-rollouts/cluster-analysis-template.yaml (Prometheus provider)
git push -u origin feat/observability-platform-foundation
gh pr create --fill --base main
```

Each stage must be Synced and Healthy on `eks-dev` before the next commit
lands, exactly like `003-platform-addons`'s staged rollout. Merge to `main`
only after CI and review pass; ArgoCD reconciles automatically, no manual
apply.

For `auth-api`'s OpenTelemetry cutover, open a separate short-lived branch in
the `auth-api` repository (`feat/otel-instrumentation`), following the
service's own CI/release path; this repository only carries the overlay
env-var patch pointing it at the in-cluster OTLP Collector endpoint.

## 4. Composite live verification

```bash
scripts/managed/verify-observability.sh --context eks-dev --namespace microtodo-dev
```

Expected final line:

```text
OBSERVABILITY VERIFIED: five components Synced/Healthy; dashboards,
canary gate, alert route, and trace/log correlation are live.
```

Raw evidence is retained under `evidence/runs/<timestamp>-observability/`,
matching the existing `evidence/runs/` convention.

## 5. Read-only spot checks

```bash
kubectl --context eks-dev get applications -n argocd
kubectl --context eks-dev get pods -n observability
kubectl --context eks-dev get servicemonitor -n observability
kubectl --context eks-dev get alertmanagerconfig -n observability
kubectl --context eks-dev get prometheusrule -n observability

# A real Prometheus query over live traffic (port-forward first):
kubectl --context eks-dev -n observability port-forward svc/prometheus-k8s 9090:web &
curl -s 'http://localhost:9090/api/v1/query?query=up{namespace="microtodo-dev"}' | jq .

# Grafana, Jaeger, and the Loki-backed log view: port-forward only, no Ingress.
kubectl --context eks-dev -n observability port-forward svc/grafana 3000:3000 &
kubectl --context eks-dev -n observability port-forward svc/jaeger-query 16686:16686 &
```

## 6. Prove the canary gate and alert route with a real breach

```bash
# Inject a synthetic elevated error rate against auth-api's canary revision
# (see tasks.md for the exact fault-injection task), then watch:
kubectl --context eks-dev argo rollouts get rollout auth-api -n microtodo-dev --watch
```

Expected: the Rollout aborts and rolls back within 5 minutes of the injected
5xx ratio exceeding 5%, and the same breach produces a Slack message in the
configured channel within 5 minutes.

Any non-Synced/non-Healthy application, unavailable controller, empty
dashboard query, missing alert, or unretrievable trace/log is a failed run.
Correct desired state by commit or `git revert`; never bypass ArgoCD with
apply, patch, scale, or rollout commands.

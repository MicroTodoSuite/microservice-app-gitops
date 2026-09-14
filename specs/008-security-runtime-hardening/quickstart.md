# Quickstart: Validate Runtime Security Hardening

Run from the repository root. Targets the real, live `eks-dev` cluster, same
as `006-observability-platform-foundation`. Every step either renders/
observes read-only, or is a normal committed PR to `main` that ArgoCD
reconciles - never a direct `kubectl apply` against the managed cluster.

## 1. Static contract

```bash
./tests/contract/security.sh
```

Expected: all four Kustomize roots (`falco`, `kube-bench`, `kube-hunter`,
`trivy-operator`)
render, every rendered image is pinned by digest, the infrastructure
ApplicationSet's activation list contains exactly the three expected new
elements at namespace `security`, kube-bench/kube-hunter RBAC contains no
write verb, and no `Ingress`/`Certificate` resource exists anywhere in this
feature.

Optional schema validation when `kubeconform` is installed:

```bash
for addon in falco kube-bench kube-hunter trivy-operator; do
  kustomize build "infrastructure/$addon" |
    kubeconform -strict -ignore-missing-schemas -summary
done
```

## 2. Publish through a short-lived branch and PR (Trunk-Based Development)

```bash
git checkout -b feat/security-runtime-hardening
# stage changes per tasks.md, one reviewable commit per stage:
#   1. infrastructure/falco (DaemonSet, modern eBPF driver, Falcosidekick, Slack ExternalSecret)
#   2. infrastructure/kube-bench (CronJob, eks target profile, read-only RBAC)
#   3. infrastructure/kube-hunter (CronJob, internal mode, read-only RBAC)
#   4. clusters/eks-dev/activation-infrastructure.yaml (append the three entries)
git push -u origin feat/security-runtime-hardening
gh pr create --fill --base main
```

Each stage must be Synced and Healthy on `eks-dev` before the next commit
lands, exactly like `006-observability-platform-foundation`'s staged
rollout.

## 3. Composite live verification

```bash
scripts/managed/verify-security.sh --context eks-dev
```

Expected final line:

```text
SECURITY VERIFIED: falco/kube-bench/kube-hunter Synced/Healthy; a real
finding reached Slack; both audit reports captured.
```

Raw evidence is retained under `evidence/runs/<timestamp>-security/`.

## 4. Read-only spot checks

```bash
kubectl --context eks-dev get applications -n argocd
kubectl --context eks-dev get pods -n security -o wide
kubectl --context eks-dev get cronjobs -n security
kubectl --context eks-dev get jobs -n security
```

## 5. Prove a real Falco finding reaches Slack

Amended by spec 009 T088: nothing is run inside a business pod. In a
reviewed pull request, add `- triggers` to the resources of
`infrastructure/falco/kustomization.yaml`; ArgoCD then runs the
`falco-evidence-trigger` Job, which executes `find /tmp -name id_rsa`. After it
syncs:

```bash
kubectl --context eks-dev -n security logs -l app.kubernetes.io/name=falco --since=15m --prefix \
  | grep "Search Private Keys or Passwords"
./scripts/managed/verify-security.sh --context eks-dev
```

Expected: a Falco finding from the stable rule "Search Private Keys or
Passwords" naming the `falco-evidence-trigger` pod and the `security`
namespace within seconds, and a corresponding Slack message in the configured
channel within 1 minute. Revert the activation commit afterwards.

## 6. Prove the audit reports are real

Amended by spec 009 T088: no Job is created by hand. Either read the
newest scheduled run, or activate the checked-in triggers by adding
`- triggers` to the resources of `infrastructure/kube-bench/kustomization.yaml`
and `infrastructure/kube-hunter/kustomization.yaml` in a reviewed pull request,
and revert it once the reports are read:

```bash
kubectl --context eks-dev -n security get jobs
kubectl --context eks-dev -n security logs job/kube-bench-evidence
kubectl --context eks-dev -n security logs job/kube-hunter-evidence
./scripts/managed/verify-security.sh --context eks-dev
```

Expected: kube-bench's log shows a real PASS/FAIL/WARN per `eks` target
profile control; kube-hunter's log shows a real vulnerability report (or an
explicit "none found"). Neither run leaves a running pod behind once its
Job's `ttlSecondsAfterFinished` elapses.

Any non-Synced/non-Healthy application, missing Falco pod on a node, a
Job that never completes, or a report that is empty/placeholder is a
failed run. Correct desired state by commit or `git revert`; never bypass
ArgoCD with apply, patch, scale, or rollout commands.

## 7. Prove continuous vulnerability scanning (amended 2026-09-13)

```bash
kubectl --context eks-dev get deploy trivy-operator -n security
for ns in microtodo-dev microtodo-staging microtodo-prod observability security; do
  kubectl --context eks-dev get vulnerabilityreports -n "$ns" \
    -o custom-columns=NAME:.metadata.name,CRITICAL:.report.summary.criticalCount,HIGH:.report.summary.highCount
done
kubectl --context eks-dev get jobs -n security   # no completed scan Job left behind
```

Expected: one report per workload container image in each namespace, and
the same counts on the Grafana vulnerability dashboard (port-forward only,
spec 006 FR-017). For an image with a HIGH or CRITICAL count above zero,
the Slack channel shows the notification naming its namespace, workload,
and image. Record each HIGH or CRITICAL entry as remediated or as a
documented exception (FR-010, SC-011).

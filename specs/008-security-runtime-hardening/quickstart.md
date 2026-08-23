# Quickstart: Validate Runtime Security Hardening

Run from the repository root. Targets the real, live `eks-dev` cluster, same
as `006-observability-platform-foundation`. Every step either renders/
observes read-only, or is a normal committed PR to `main` that ArgoCD
reconciles - never a direct `kubectl apply` against the managed cluster.

## 1. Static contract

```bash
./tests/contract/security.sh
```

Expected: all three Kustomize roots (`falco`, `kube-bench`, `kube-hunter`)
render, every rendered image is pinned by digest, the infrastructure
ApplicationSet's activation list contains exactly the three expected new
elements at namespace `security`, kube-bench/kube-hunter RBAC contains no
write verb, and no `Ingress`/`Certificate` resource exists anywhere in this
feature.

Optional schema validation when `kubeconform` is installed:

```bash
for addon in falco kube-bench kube-hunter; do
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

```bash
# Pick any running business-workload pod and trigger a rule Falco's
# default ruleset flags (spawning an interactive shell is one of the
# most reliable defaults):
kubectl --context eks-dev -n microtodo-dev exec -it deploy/auth-api -- /bin/sh -c 'echo triggering-falco-finding'
kubectl --context eks-dev -n security logs daemonset/falco --tail=20
```

Expected: a Falco finding referencing the exact pod/namespace within
seconds, and a corresponding Slack message in the configured channel within
1 minute.

## 6. Prove the audit reports are real

```bash
kubectl --context eks-dev -n security create job --from=cronjob/kube-bench kube-bench-manual-$(date +%s)
kubectl --context eks-dev -n security create job --from=cronjob/kube-hunter kube-hunter-manual-$(date +%s)
# wait for each Job to complete, then:
kubectl --context eks-dev -n security logs job/<the-job-name>
```

Expected: kube-bench's log shows a real PASS/FAIL/WARN per `eks` target
profile control; kube-hunter's log shows a real vulnerability report (or an
explicit "none found"). Neither run leaves a running pod behind once its
Job's `ttlSecondsAfterFinished` elapses.

Any non-Synced/non-Healthy application, missing Falco pod on a node, a
Job that never completes, or a report that is empty/placeholder is a
failed run. Correct desired state by commit or `git revert`; never bypass
ArgoCD with apply, patch, scale, or rollout commands.

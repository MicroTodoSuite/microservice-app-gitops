# Local GitOps Pilot — Quickstart

Bring up a **fully local** pilot that deploys exactly `auth-api` from committed
desired state, reconciled by ArgoCD from a machine-local Git source. No cloud
account, hosted registry, or hosted runtime is used.

## Prerequisites

- Linux/macOS with Docker, and: `git`, `kind`, `kubectl`, `kustomize`, `curl`,
  `jq`, `python3`.
- Free loopback ports `5001` (registry), `8081` (Git source), `18000` (health).
- ≥ 4 CPUs, 8 GiB RAM, 20 GiB disk.

## Required repositories (clone side by side)

```bash
git clone https://github.com/MicroTodoSuite/microservice-app-gitops.git
git clone https://github.com/MicroTodoSuite/microservice-app-auth-api.git
cd microservice-app-gitops
```

## Commands

```bash
./scripts/pilot/preflight.sh        # 1. verify the workstation (read-only)
./scripts/pilot/bootstrap.sh        # 2. local registry + Git source + kind + ArgoCD
./scripts/pilot/publish-auth.sh     # 3. build+push auth-api, commit its digest locally
./scripts/pilot/verify.sh           # 4. prove Synced/Healthy, one service, 3x health
```

## Checkpoints

| Checkpoint | Expected observation |
| --- | --- |
| Preflight | Supported host, tools present, ports free, Docker ready. |
| Bootstrap boundary | Command log shows only the ArgoCD install and root Application applies. |
| Pre-activation | ArgoCD reads the local Git source; **zero** business workloads. |
| Publish | One immutable image digest and one commit on the local `pilot main`. |
| Reconciliation | `auth-api-local` is `Synced`/`Healthy` at the published SHA — no manual sync. |
| Workload | One ready `auth-api` Deployment in `microtodo-local`; ESO created its Secret. |
| Health | `http://127.0.0.1:18000/version` succeeds three times over ≥ 60s. |

## Prove commit-only change and rollback

Everything is a commit to the local source; ArgoCD reconciles automatically.

```bash
# forward change: bump replicas in a disposable clone of .local/git, push to main
# rollback: git revert that commit and push — never kubectl scale / rollout undo
```

## Troubleshooting (without bypassing GitOps)

- **ArgoCD OutOfSync / unhealthy** → inspect with read-only `kubectl get/describe/logs`
  and Argo status; fix desired state with a commit or `git revert`. Never
  `kubectl apply`, `patch`, `scale`, or `rollout undo`.
- **Image cannot be pulled** → check the loopback registry and that the overlay
  uses `newName@sha256:...`. Never `kind load` or a floating tag as a fix.
- **Secret not ready** → inspect the ESO Application, `Password`, and
  `ExternalSecret`. Correct via commit; never `kubectl create secret`.

## Cleanup

```bash
./scripts/pilot/cleanup.sh          # removes only the pilot cluster, registry, and .local/
```

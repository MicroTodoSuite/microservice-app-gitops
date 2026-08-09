# Local GitOps Pilot — Quickstart

Bring up the complete MicroTodoSuite application locally from committed desired
state reconciled by ArgoCD. The pilot uses only a loopback registry, a
machine-local Git reader, kind, and the checked-out service sources. It requires
no hosted runtime, provider account, or provider credential.

## Prerequisites

- Linux/macOS with Docker and `bash`, `git`, `kind`, `kubectl`, `curl`, `jq`,
  `python3`, and `rsync`.
- Standalone Kustomize is optional; scripts fall back to kubectl's embedded
  Kustomize.
- Free loopback ports `5001` (registry), `8081` (Git), `18000`, `18002`,
  `18003`, `18080`, `19090`, and `16379` (temporary evidence forwards).
- At least 4 CPUs, 8 GiB RAM, and 20 GiB disk.

## Required repositories

Clone these repositories side by side, then run commands from GitOps:

```bash
git clone https://github.com/MicroTodoSuite/microservice-app-gitops.git
git clone https://github.com/MicroTodoSuite/microservice-app-auth-api.git
git clone https://github.com/MicroTodoSuite/microservice-app-todos-api.git
git clone https://github.com/MicroTodoSuite/microservice-app-users-api.git
git clone https://github.com/MicroTodoSuite/microservice-app-frontend.git
git clone https://github.com/MicroTodoSuite/microservice-app-log-message-processor.git
cd microservice-app-gitops
```

Every service checkout must be clean. The publisher records each source commit
and refuses a dirty source so its image evidence is reproducible.

## Commands

```bash
./scripts/pilot/preflight.sh
./scripts/pilot/bootstrap.sh
./scripts/pilot/publish-services.sh
./scripts/pilot/verify-services.sh
```

The publisher preserves the bootstrap-resolved local registration and root Git
URL when it mirrors the reviewed tree. If the root bootstrap object itself must
be idempotently re-offered after those committed values are aligned, the audited
boundary command is `./scripts/pilot/bootstrap.sh --root-only`.

`publish-auth.sh` remains as a compatibility alias and now delegates to
`publish-services.sh`; auth-only activation would leave the other discovered
services at disabled image placeholders.

If reusing the pilot created before the current default cluster name, pass its
verified context:

```bash
PILOT_KUBE_CONTEXT=kind-microtodo-gitops-pilot \
  ./scripts/pilot/publish-services.sh
PILOT_KUBE_CONTEXT=kind-microtodo-gitops-pilot \
  ./scripts/pilot/verify-services.sh
```

## Checkpoints

| Checkpoint | Expected observation |
| --- | --- |
| Preflight | Required local tools, ports, Docker, and rendering work. |
| Bootstrap boundary | Only vendored ArgoCD and the root Application are applied directly. |
| Pre-activation | ArgoCD reads local Git; zero business workloads exist. |
| Image publication | Five clean source SHAs map to five loopback registry digests. |
| Redis commit | `infra-redis` alone reaches Synced/Healthy and returns `PONG`; no new service Application exists yet. |
| Service commit | Five business Applications select immutable digests at one local Git SHA. |
| Live evidence | All pods are Ready; auth/users/todos/processor/frontend functional checks pass. |

## Frontend access

For interactive use, keep this read-only forward open:

```bash
kubectl --context kind-microtodo-gitops-pilot \
  -n microtodo-local port-forward svc/frontend 18080:8080
```

Open `http://127.0.0.1:18080/`. NGINX inside frontend routes `/login` and
`/todos` to internal Services. The local pilot intentionally adds no Ingress,
Gateway, NodePort, or host-bound workload.

## Evidence

The composite verifier retains raw ArgoCD Applications, Deployments, Pods,
running image IDs, health responses, Redis ping, sanitized login results, seeded
profile response, todo responses, processor metric/log correlation, frontend
proxy results, and Kyverno reports under:

```text
.local/evidence/service-onboarding/<timestamp>/
```

Success is never inferred from a render or configuration file.

## Continuity warning

This pilot preserves the current application architecture:

- Redis is one ephemeral node with snapshots and append-only persistence off.
- todos-api stores todos in process memory.
- users-api loads seed rows into pod-local H2.
- log-message-processor has one subscriber because multiple Pub/Sub subscribers
  would each receive the event.

Restarts can lose or recreate state, and scaling stateful-in-process services can
diverge. The pilot proves integration, not durable storage or disaster recovery.

## Troubleshooting without bypassing GitOps

- Inspect ArgoCD, Deployments, Pods, Events, and logs with read-only commands.
- Fix desired state in a local Git commit or use `git revert`; do not apply,
  patch, scale, restart, create, replace, or delete a managed resource directly.
- For an image pull failure, verify the loopback registry and exact digest; do
  not substitute a floating tag or load an image imperatively.
- For JWT failure, inspect ExternalSecret readiness and Secret references without
  printing the value; never create or copy the Secret manually.

## Cleanup

```bash
./scripts/pilot/cleanup.sh
```

Cleanup targets only pilot-owned local resources.

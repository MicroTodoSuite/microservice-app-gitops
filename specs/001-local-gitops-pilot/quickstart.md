# Quickstart Design: Local GitOps Pilot

> This is the target acceptance workflow defined by the plan. The scripts below
> are implementation deliverables in `tasks.md`; this document must be rerun and
> updated with captured output before the feature can be accepted.

## Outcome

Starting from two clean clones, a first-time teammate will use eight entered
commands to reach a synchronized, ready, and repeatedly healthy `auth-api`.
ArgoCD will observe a commit from a machine-local `microservice-app-gitops`
remote. No workload manifest is applied directly, and no cloud credential,
hosted runtime source, hosted registry, or paid service is used.

## Supported workstation

- Linux on `amd64` or `arm64`, cgroup v2, and Docker Engine available to the
  current user.
- At least 4 logical CPUs, 8 GiB available RAM, and 20 GiB free disk.
- Initial internet access for the two clones and asset acquisition. After
  acquisition, the running pilot remains machine-local.
- Bash, Git, Docker, Kind 0.32.0, a Kubernetes 1.36-compatible `kubectl`, `curl`,
  and `jq` installed. The preflight verifies exact compatibility before making
  changes.
- Loopback ports `5001` (registry), `8081` (Git source inspection), and `18000`
  (temporary health port-forward) available.
- No AWS CLI, Azure CLI, AWS/Azure credentials, Kubernetes cloud context, or
  paid account is required.

The tracked asset lock selects the Kind node, ArgoCD, ESO, local registry, Git
source helper, and all controller images by digest. Do not substitute floating
versions.

## Required repositories

- `microservice-app-gitops`: desired state, local platform, and pilot scripts.
- `microservice-app-auth-api`: source used to build the one pilot business
  service.

The following clone URLs match the configured project remotes. Place the two
repositories next to each other.

## Eight-command path to health

Run each numbered line as one entered command:

1. Clone the GitOps repository.

   ```bash
   git clone https://github.com/MicroTodoSuite/microservice-app-gitops.git
   ```

2. Clone `auth-api`.

   ```bash
   git clone https://github.com/MicroTodoSuite/microservice-app-auth-api.git
   ```

3. Enter the GitOps checkout.

   ```bash
   cd microservice-app-gitops
   ```

4. Verify the supported host profile without changing the cluster.

   ```bash
   ./scripts/pilot/preflight.sh
   ```

5. Acquire and verify all assets, including one local `auth-api` build.

   ```bash
   ./scripts/pilot/acquire-assets.sh ../microservice-app-auth-api
   ```

6. Create the local source/registry/cluster, execute the audited ArgoCD/root
   bootstrap exception, and wait for ArgoCD plus ESO. At this checkpoint,
   `auth-api` must not exist.

   ```bash
   ./scripts/pilot/bootstrap.sh
   ```

7. Push the built image locally, commit its immutable digest and local activation
   to the pilot Git remote, and let ArgoCD reconcile automatically.

   ```bash
   ./scripts/pilot/publish-auth.sh
   ```

8. Require revision match, Argo sync/health, Deployment readiness, exactly one
   business service, and three `/version` successes spanning at least 60 seconds.

   ```bash
   ./scripts/pilot/verify.sh
   ```

The eighth command must finish in 20 minutes or less from the first clone on the
supported profile. Reconciliation timing begins only when the publish command
proves its commit is available from the local source; it must be healthy within
five minutes of that timestamp.

## Expected checkpoints

| Checkpoint | Required observation |
| --- | --- |
| Preflight | Supported host, compatible tools, sufficient resources, free ports, Docker ready. |
| Acquisition | Every locked asset is local and digest verified; `auth-api` was built once. |
| Bootstrap source | Bare repository exposes only committed `pilot/main`; source/registry endpoints are local. |
| Bootstrap boundary | Command log contains only the minimal ArgoCD install and root Application mutations allowed by Constitution 1.1.0. |
| Pre-activation | Root, self-managed ArgoCD, environment policy, and ESO are healthy; zero `auth-api` business workloads exist. |
| Publish | Output gives one immutable image digest and one Git commit available from the local source. |
| Reconciliation | `auth-api-local` is `Synced` and `Healthy` at the published SHA without a manual sync. |
| Workload | One ready `auth-api` Deployment exists in `microtodo-local`; total business-service count is exactly one. |
| Health | `http://127.0.0.1:18000/version` succeeds three times over at least 60 seconds. |
| Evidence | A schema-valid run directory contains Git, Argo, workload, health, timing, dependency, and command-audit records. |

## Full acceptance exercises

These are not needed to reach the first health check and do not change the
eight-command count above.

Prove an uncommitted edit has no effect for five minutes:

```bash
./scripts/pilot/exercise-uncommitted.sh
```

Prove a committed replica change and a committed Git revert both reconcile
within five minutes:

```bash
./scripts/pilot/exercise-change-revert.sh
```

Render the eight service slots and future-cluster fixtures, validate ownership,
least privilege, digest/secret rules, and prove production is disabled:

```bash
./scripts/pilot/conformance.sh
```

Run the three-clean-cluster timing criterion from retained local assets:

```bash
./scripts/pilot/run-three-clean.sh
```

Two first-time operators must also complete
`docs/operator-evaluation.md`; automation cannot manufacture their timing,
assistance, identification, or clarity-rating evidence.

## Evidence location

Each run writes:

```text
evidence/runs/<UTC-run-id>/
├── summary.json
├── timeline.ndjson
├── argo-application.json
├── workloads.json
├── health.json
├── git-log.txt
└── command-log.txt
```

`summary.json` must validate against
`contracts/pilot-evidence.schema.json`. A failed run is retained as failed; do
not edit evidence to make it pass.

## Troubleshooting without bypassing GitOps

### Preflight or acquisition fails

Read the failing check and correct only the workstation prerequisite. Do not
create a partial cluster. A missing/corrupt asset is reacquired and reverified;
it is never replaced with `latest`.

### ArgoCD cannot read the local repository

Inspect the local Git-source container, `git ls-remote` result, root Application
status, and command log. If the local endpoint changed, use the supported script
to create and push a new connection-values commit, then let ArgoCD retry. Do not
apply child Applications or workloads manually.

### ESO or `auth-api-secrets` is not ready

Inspect the ESO Application, controller logs, `Password`, `ExternalSecret`, and
target Secret metadata with read-only commands. Correct a manifest through a
commit to the pilot remote. Never use `kubectl create secret`; the previously
committed JWT literal is compromised and must be rotated outside Git.

### The image cannot be pulled

Verify the local registry is running, the manifest/index digest exists, the
Kind registry alias matches the tracked configuration, and the overlay uses
`newName@sha256:...`. Correct acquisition/registry state and commit a valid
digest if desired state was wrong. Never use `kind load`, `kubectl set image`,
or a floating tag as the recovery path.

### Argo is OutOfSync or the workload is unhealthy

Use the evidence output plus read-only Application, event, pod, probe, and log
inspection. Fix desired state with a normal commit or revert the bad commit and
push it to `pilot main`. Do not use manual Argo sync, `kubectl apply`, patch,
scale, or rollout undo to claim success.

### More than one business service is found

The run is invalid. Inspect the active registration and generated Applications,
correct the generator/registration through Git, and rerun from a clean cluster.

## Cleanup

After saving evidence, remove only pilot-owned local resources:

```bash
./scripts/pilot/cleanup.sh
```

The cleanup script verifies the exact Kind cluster, labeled helper containers,
and `.local/` path before deletion. It must not select or change any cloud or
unrelated Kubernetes context. Cleanup is not a deployment or rollback method.


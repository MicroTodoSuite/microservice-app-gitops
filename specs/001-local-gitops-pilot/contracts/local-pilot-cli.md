# Contract: Local Pilot Command Interface

These are implementation contracts for future scripts. They are not claims that
the scripts already exist at planning time.

Every script uses Bash strict mode, writes human-readable English checkpoints to
standard error, writes machine-readable results to the documented output path,
and exits non-zero without reporting success when a required checkpoint fails.

## Global safety rules

- The ordinary checkout's hosted `origin` is read-only to pilot scripts.
- Local desired-state commits are created in an ignored disposable worktree and
  pushed only to the filesystem remote named `pilot`.
- A script must verify that `pilot` resolves inside `.local/git/` before pushing.
- No script rebases, force-pushes, rewrites history, or pushes secrets.
- No script mutates a GitOps-managed workload through Kubernetes or Argo APIs.
- Only `bootstrap.sh` may execute the constitutional direct-mutation allowlist:
  install the vendored ArgoCD controller, wait for its CRD/controller readiness,
  and create the initial root Application. Each invocation is logged.
- Cleanup may delete pilot-owned Kind/Docker/local files; it is not a deployment
  or rollback method and never touches a remote environment.
- Read-only `kubectl get`, `wait`, `logs`, `describe`, `auth can-i`, and
  `port-forward` operations are permitted for evidence and diagnostics.

## `scripts/pilot/preflight.sh`

**Input**: no positional arguments.

**Checks**:

- Linux `amd64` or `arm64`, cgroup v2, virtualization/container capability.
- At least 4 logical CPUs, 8 GiB available memory, and 20 GiB free disk.
- Required verified tools and compatible versions: Bash, Git, Docker, Kind,
  `kubectl`, `curl`, and `jq`.
- Docker daemon availability.
- Loopback ports required by the registry, Git source, and health forward are
  free.
- GitOps checkout resolves to this repository and has no unsupported local
  changes for acquisition/bootstrap inputs.
- No AWS/Azure credential or CLI is required or read.

**Output**: one JSON object on stdout with `result`, detected versions,
resources, architecture, and reserved ports.

**Exit codes**: `0` pass; `2` unsupported host; `3` missing/incompatible tool;
`4` insufficient resources/occupied port; `5` Docker unavailable.

## `scripts/pilot/acquire-assets.sh <auth-api-repository>`

**Precondition**: preflight passed; initial internet access is allowed.

**Behavior**:

1. Validate the supplied repository is `microservice-app-auth-api` and contains
   the reviewed Dockerfile and `/version` source route.
2. Verify vendored ArgoCD and ESO manifest checksums/provenance.
3. Pull every helper, Kind-node, ArgoCD, ESO, and dependency image declared in
   `bootstrap/local/assets.lock` and verify its digest/platform.
4. Build `auth-api` once from the supplied checkout, tag it only as an
   acquisition handle, and record its local image result for later registry
   push. The deployed reference is not selected until the registry reports the
   manifest/index digest.
5. Prove all declared assets are now machine-local.

**Output**: `.local/acquisition/summary.json` plus command log. No Git commit,
push, cluster, or workload is created.

## `scripts/pilot/bootstrap.sh`

**Preconditions**: preflight and acquisition passed.

**Behavior**:

1. Start the digest-pinned loopback registry and bare-Git HTTP source.
2. Initialize `.local/git/microservice-app-gitops.git`, enable `post-update`, add
   the `pilot` filesystem remote in an ignored disposable worktree, and seed its
   `main` from the selected source checkout revision.
3. Commit/push machine connection values with business-service discovery still
   disabled.
4. Create the digest-pinned Kind cluster from the tracked configuration and
   mirror all platform images into the local registry.
5. Execute and log only the amended-constitution bootstrap allowlist for the
   vendored ArgoCD controller and initial root Application.
6. Wait read-only for root sync, ArgoCD self-management, the environment
   Application, and ESO to become healthy.
7. Prove no `auth-api` business workload exists before activation.

**Output**: `.local/bootstrap/summary.json` containing the source revision,
reader URL, registry endpoint, cluster identity, logged bootstrap mutations, and
platform readiness.

**Idempotency**: rerunning against the same selected source revision converges
without duplicate resources. A changed local endpoint requires a new ordinary
connection-values commit before the root is offered again.

## `scripts/pilot/publish-auth.sh`

**Preconditions**: bootstrap passed; ESO is healthy; the acquired `auth-api`
image is present.

**Behavior**:

1. Push the acquired image to `localhost:5001/auth-api`.
2. Resolve and validate the registry-reported manifest/index digest.
3. In the disposable pilot worktree, replace the inactive placeholder with
   `newName` plus digest, replace the transitional ignored-file generator with
   the ESO local resources if not already present, and activate only
   `environment: local`.
4. Render and run contract checks.
5. Create one clear desired-state commit and push only `pilot main`.
6. Print the commit SHA that ArgoCD must observe. Do not wait by mutating ArgoCD;
   reconciliation remains automatic.

**Output**: `.local/publish/summary.json` containing image digest, commit SHA,
remote, and source-availability time.

## `scripts/bump-image.sh <service> <environment> <digest>`

**Contract change**: retain the existing helper but make it digest-only.

- Accept only `sha256:[a-f0-9]{64}`.
- Reject `latest`, tags, all-zero placeholders, local image IDs, and config
  digests.
- Preserve the overlay's `newName`; update only `images[].digest`.
- Render and assert the final reference is `newName@digest`.
- Create a commit but never push and never invoke cluster/Argo mutation.
- Promotion mode copies an existing source-overlay digest; it does not accept a
  rebuilt artifact.

## `scripts/pilot/verify.sh [--output <directory>]`

**Behavior**:

- Obtain expected SHA from the local Git source.
- Wait no more than 300 seconds for `auth-api-local` to report that exact
  revision as `Synced` and `Healthy`.
- Wait no more than 300 seconds for `deployment/auth-api` to be Available.
- Count unique workloads carrying
  `app.kubernetes.io/component=business-service`; require exactly `auth-api`.
- Establish a loopback port-forward to `service/auth-api` and request `/version`
  three times spanning at least 60 seconds; require three HTTP successes.
- Capture Argo, workload, Git, health, elapsed-time, cloud-dependency, and
  command-audit evidence conforming to `pilot-evidence.schema.json`.

**Success rule**: synced revision match AND ready workload AND exactly-one count
AND three passing health checks AND no unsupported mutation. A merely running
process is not success.

## `scripts/pilot/exercise-uncommitted.sh`

Use a new disposable clone of the local bare repository. Change local replicas
from 1 to 2 without committing, prove the render differs, then observe for 300
seconds that the served SHA, Argo revision, and live replica count remain
unchanged. Remove the disposable clone and emit a verification record. Never
touch the operator's ordinary checkout.

## `scripts/pilot/exercise-change-revert.sh`

Use a disposable clone of the local bare repository. Commit/push an allowed
replica change to `pilot main`, wait for the matching Argo SHA and two ready
replicas, create a normal `git revert`, push it, and wait for the revert SHA and
one ready replica. Both transitions must complete within 300 seconds and produce
linked evidence. No `kubectl scale`, `set image`, or `rollout undo` is allowed.

## `scripts/pilot/run-three-clean.sh`

Run acquisition verification, cleanup, bootstrap, publish, and verify for three
clean disposable clusters against retained local assets. Aggregate success rate
and source-to-healthy durations. This is an acceptance harness, not part of the
eight-command newcomer path.

## `scripts/pilot/conformance.sh`

Run service-slot, cluster-registration, production-disabled, secret-literal,
digest-only, English-artifact, AppProject-wildcard, vendored-asset, and prohibited
mutation scans. Render the canonical `auth-api`, seven abstract service slots,
and local/future-EKS fixtures without deploying fixtures.

## `scripts/pilot/cleanup.sh`

Delete only the explicitly named pilot Kind cluster, pilot registry/source
containers, port-forward process, and `.local/` runtime directory after verifying
their pilot labels/paths. Preserve committed evidence by default. Print what was
removed and whether it was local-only. Never operate on a context or container
not owned by this pilot.

## Evidence and logging

Each state-changing local command is written to `command-log.txt` with timestamp,
phase, exit code, and classification (`acquisition`, `bootstrap-exception`,
`git-desired-state`, `read-only-verification`, or `cleanup`). Arguments that could
contain generated secret material are redacted before logging.

The audit must reject mutating `kubectl` verbs outside the exact bootstrap
allowlist. A rejected or unexpected command makes the run fail even if the
service becomes healthy.


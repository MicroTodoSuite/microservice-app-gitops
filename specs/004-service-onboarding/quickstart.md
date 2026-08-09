# Quickstart: Publish and Verify the Complete Local Service Set

Run from the repository root. The commands below build local images, commit only
to the pilot-owned bare Git source, or observe runtime state. They never apply or
patch a GitOps-managed resource directly.

## 1. Static validation

```bash
./tests/contract/platform-addons.sh
./tests/contract/service-onboarding.sh
```

Expected: Redis and all four service roots render, executable images are
immutable, probes and tokenless service accounts are present, shared JWT and
Redis interfaces match, frontend remains ClusterIP/port-forward based, and new
artifacts contain no provider dependency.

## 2. Build, publish, and reconcile in dependency order

The currently running pilot uses the older context name captured by the fresh
baseline. A newly bootstrapped pilot may use the script default instead.

```bash
PILOT_KUBE_CONTEXT=kind-microtodo-gitops-pilot \
  ./scripts/pilot/publish-services.sh
```

The script:

1. builds auth-api plus the four remaining sibling sources;
2. pushes each convenience tag only to `localhost:5001` and records its digest;
3. commits Redis to `.local/git/microservice-app-gitops.git`;
4. waits until `infra-redis` is Synced/Healthy and answers `PONG`;
5. commits the complete service tree with immutable digests to the same local
   `main`; and
6. prints the final local desired-state SHA.

No hosted remote is changed.

## 3. Composite live evidence

```bash
PILOT_KUBE_CONTEXT=kind-microtodo-gitops-pilot \
  ./scripts/pilot/verify-services.sh
```

Expected final line:

```text
SERVICES VERIFIED: Redis and all five business services are Synced, Healthy, Ready, and functional.
```

Raw evidence is retained under
`.local/evidence/service-onboarding/<timestamp>/`.

## 4. User-facing local route

The verifier starts and stops its own temporary forward. For interactive use:

```bash
kubectl --context kind-microtodo-gitops-pilot \
  -n microtodo-local port-forward svc/frontend 18080:8080
```

Then open `http://127.0.0.1:18080/`. This is the existing local exposure contract;
no ingress controller or NodePort is installed.

## 5. Read-only spot checks

```bash
kubectl --context kind-microtodo-gitops-pilot get applications -n argocd
kubectl --context kind-microtodo-gitops-pilot get pods -n microtodo-local
kubectl --context kind-microtodo-gitops-pilot get pods -n redis
kubectl --context kind-microtodo-gitops-pilot get deployments -n microtodo-local
kubectl --context kind-microtodo-gitops-pilot get deployment,service -n redis
```

Correct any failure with a reviewed local Git commit or revert. Never repair a
managed object with apply, patch, scale, rollout, create, replace, or delete.

## Continuity warning

This pilot deliberately preserves the current architecture: Redis is ephemeral,
todos are process-local, and users-api recreates H2 seed data per pod. A restart
can lose or recreate state, and multiple replicas can diverge or duplicate work.
These checks prove integration behavior, not production durability or DR.

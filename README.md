# microservice-app-gitops

GitOps source of truth for MicroTodoSuite. **Nothing is applied to a cluster by
hand: every deployment is a commit here, reconciled by ArgoCD; every rollback is
a `git revert`.**

## Local pilot (start here)

A fully local, four-command pilot that deploys `auth-api` from committed desired
state — no cloud account, hosted registry, or hosted runtime.

See **[docs/local-pilot-quickstart.md](docs/local-pilot-quickstart.md)**:

```bash
./scripts/pilot/preflight.sh
./scripts/pilot/bootstrap.sh
./scripts/pilot/publish-auth.sh
./scripts/pilot/verify.sh
```

## Layout

```
bootstrap/argocd/       Vendored, pinned ArgoCD; applied once, then self-managed.
bootstrap/local/        kind + loopback registry config for the pilot.
clusters/base/          Reusable delivery mechanism (projects, ApplicationSets).
clusters/<cluster>/     Value-only registration: repo endpoint + activated envs.
environments/<env>/     Environment-owned namespace policy (quota, limits, netpol).
infrastructure/<addon>/ Platform add-ons owned by ArgoCD (ESO is vendored here).
apps/<service>/base/    Environment-neutral service manifests.
apps/<service>/components/  Version fragments (topology-economical/full, canary).
apps/<service>/topology/    Single per-service economical↔full switch.
apps/<service>/overlays/<env>/  Environment-owned values (namespace, capacity, digest).
scripts/pilot/          Pilot lifecycle (preflight, bootstrap, publish, verify, cleanup).
scripts/bump-image.sh   Digest-only image update helper.
specs/                  Spec-Driven Development artifacts (English).
```

## Dual topology (economical & full)

The repo serves both plan profiles without forking:

- **Economical** (active): one cluster, environments as namespaces. Each cluster
  registration lists its environments with `server: kubernetes.default.svc`.
- **Full**: environments become separate clusters; the same registration lists
  each environment's remote API server. Service `base`/`overlays` never change.
  Per-service `topology/` selects the `topology-full` (Istio) component.

See [clusters/README.md](clusters/README.md).

## Ownership rules

- **Reusable base** (`apps/<svc>/base`): what the service IS, environment-neutral.
- **Environment overlay** (`apps/<svc>/overlays/<env>`): namespace, capacity,
  registry, immutable digest.
- **Environment policy** (`environments/<env>`): quota, limits, network policy.
- **Cluster registration** (`clusters/<cluster>`): endpoints and activated envs.
- Secrets: never committed; provided in-cluster by ESO (see
  [docs/secret-rotation.md](docs/secret-rotation.md)).

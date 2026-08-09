# Deployment Profiles: full (default) and economical

The plan (§17) defines two cost profiles. This repo supports **both** and lets you
switch between them. **The default is the full (expensive) profile**, as the
constitution assumes; the economical profile is available as a deliberate switch.

Governance: making the economical profile *available* needs no amendment. Actually
*running* a managed environment in economical mode is "moving to the cost-optimized
profile" and, per constitution principles 1 and 5, requires an approved amendment
in `microservice-app-docs` first.

## What differs between the profiles

| Aspect | Full (default) | Economical |
| --- | --- | --- |
| Clusters | separate EKS per env (+ AKS DR) | one cluster, envs as namespaces |
| Service mesh | Istio (sidecar injection) | none |
| Canary | Istio traffic-based | Argo Rollouts replica-based |
| Logs / traces | ELK / full Jaeger | Loki / embedded Jaeger |
| Registry | ECR + ACR | ECR only |

## Where you switch it (the switch points)

Switching is coordinated data/component changes, not a single magic toggle,
because the profiles genuinely differ in infrastructure:

1. **Mesh / per-workload (the one-line switch)**:
   `apps/<service>/topology/kustomization.yaml` selects `topology-full` (default)
   or `topology-economical`. This flips every **managed** environment at once.
2. **Cluster topology**: which `clusters/<cluster>` registrations exist and the
   `server` in each environment entry — remote clusters (full) vs
   `kubernetes.default.svc` + namespaces (economical). See `clusters/README.md`.
3. **Canary style**: `apps/<service>/overlays/prod` selects
   `components/strategy-canary` (replica-based; Istio adds traffic routing).
4. **Add-ons**: content under `infrastructure/` (Istio/ELK for full; Loki for
   economical) — owned by roadmap task 2.

## The local pilot is always economical

`apps/<service>/overlays/local` is pinned to `topology-economical` directly and
does **not** follow the managed default, because Istio and multi-cluster cannot
run on a single local kind cluster. Switching the managed profile never affects
the local pilot.

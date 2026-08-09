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
2. **Cluster topology**: which `clusters/<cluster>` registrations exist and
   which environments each registration activates. Every cluster runs its own
   ArgoCD and therefore uses `server: https://kubernetes.default.svc`. The full
   profile has one registration per isolated environment cluster; the
   economical profile activates multiple environment namespaces in one
   registration. See `clusters/README.md`.
3. **Canary style**: `apps/<service>/overlays/prod` selects
   `components/strategy-canary` (replica-based; Istio adds traffic routing).
4. **Add-ons**: content under `infrastructure/` (Istio/ELK for full; Loki for
   economical) — owned by roadmap task 2.

## The local pilot is always economical

`apps/<service>/overlays/local` is pinned to `topology-economical` directly and
does **not** follow the managed default, because Istio and multi-cluster cannot
run on a single local kind cluster. Switching the managed profile never affects
the local pilot.

## ArgoCD ownership and disaster recovery

ArgoCD is deliberately per-cluster in both profiles. `eks-dev`, `eks-staging`,
`eks-prod`, and `aks-dr` each bootstrap and run their own reconciler against the
in-cluster Kubernetes API. Terraform cluster endpoints and certificate
authorities are operator/bootstrap inputs; they are not ApplicationSet remote
destinations.

A centralized ArgoCD hub in `eks-prod` would make production a control-plane
dependency for every other cluster. If `eks-prod` failed, `aks-dr` would lose
the reconciler needed to take over at the same moment it was needed most. The
per-cluster topology removes that single point of failure and lets the DR
cluster continue reconciling from the reviewed Git source independently.

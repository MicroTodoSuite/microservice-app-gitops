# Implementation Plan: Remaining Service Onboarding

**Branch**: `esteban/platform-addons` | **Date**: 2026-08-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-service-onboarding/spec.md`

## Summary

Extend the already proven folder-discovered GitOps pilot without changing its
registration design. Add a provider-neutral, single-node Redis 7.4.9 workload
as `infrastructure/redis`, pinned to the locally verified multi-platform digest
and intentionally backed only by `emptyDir`. Add standard base, topology
components, local overlay, and inactive managed overlays for todos-api,
users-api, frontend, and log-message-processor. All active application images
are built from the clean sibling repositories, pushed to the loopback registry,
and selected by registry-reported digest.

The rollout uses two local-source commits. Redis is committed, reconciled,
proven Healthy, and answered with `PONG` first. A second commit activates all
service manifests with their immutable digests. A read-only composite verifier
then ties every ArgoCD application and running image to the exact local Git SHA,
checks every pod and intrinsic health endpoint, exercises auth-api -> users-api,
uses the issued token with users-api and todos-api, proves the todos Redis event
was consumed, and exercises frontend's same-origin `/login` and `/todos` routes
over the contract's existing local port-forward exposure.

## Technical Context

**Language/Version**: Kubernetes YAML; Kustomize API v1beta1/v1alpha1; Bash 5.3-compatible pilot automation

**Primary Dependencies**: Kubernetes 1.36.1 live kind node, kubectl 1.36.3 with embedded Kustomize 5.8.1, ArgoCD 3.5.0, existing External Secrets and Kyverno applications, Docker-compatible loopback registry, Redis 7.4.9

**Storage**: Git desired state; loopback OCI registry; Redis `emptyDir`; todos-api process memory; users-api pod-local H2 seed data; untracked timestamped evidence under `.local/evidence/service-onboarding/`

**Testing**: Kustomize renders, Bash static contracts, immutable-image and provider-neutrality scans, ArgoCD revision/sync/health observations, Deployment and Pod readiness, Redis protocol ping, live HTTP requests, JWT-backed profile and todo calls, Redis event/log correlation, and metric deltas

**Target Platform**: Existing local kind cluster on Linux; provider-neutral Kubernetes desired state reusable by later registrations

**Project Type**: GitOps desired-state repository with local build/publish and read-only acceptance automation; no application source changes

**Performance Goals**: Redis becomes Synced/Healthy and answers `PONG` within five minutes of its commit; all five business applications converge within ten minutes of the service commit; the emitted todo event appears within 30 seconds

**Constraints**: GitOps-only after bootstrap; no direct mutation of managed resources; no AWS/Azure endpoint, registry, identity, credential, or secret value; every active image digest-pinned; one local replica for each process-local state holder; no invented persistence; no local ingress controller; preserve Kyverno admission compatibility

**Scale/Scope**: One Redis platform application, four new business applications, five total business applications including auth-api, six functional paths (Redis, auth, users, todos, processor, frontend), one kind cluster, and the existing shared registration mechanism

## Constitution Check

*GATE: Passed before research and re-checked after design.*

| Principle | Gate | Design response |
| --- | --- | --- |
| Environment Isolation | PASS | Business services stay in `microtodo-local`; Redis has its own labeled platform namespace and explicit traffic policy intent. |
| GitOps-Only Deployment | PASS | Only two commits to the pilot-owned local Git source change managed state; all cluster checks are observational or application-protocol tests. |
| Stable Trunk Development | PASS | Work extends the current short-lived platform branch; no hosted commit or push is part of the pilot workflow. |
| Authoritative Specifications | PASS | This spec, plan, research, data model, registration contract, quickstart, and generated tasks precede implementation. |
| Cost-Governed Design | PASS | Redis and each stateful-in-process service use one bounded local replica; no managed service is introduced. |
| Immutable Build Promotion | PASS | Every business image uses the local registry's manifest digest and Redis uses a verified public manifest digest. |
| Progressive and Reversible Releases | PASS | Redis is a separate first commit and gate; the service set is a second commit; each can be reverted in local Git. |
| Quality and Supply-Chain Gates | PASS | Static contracts reject tags, provider dependencies, missing probes, missing service accounts, and contract drift; Kyverno remains enforced. |
| Observable and Resilient Operations | PASS | Every workload has startup/readiness/liveness checks, metrics or intrinsic health, bounded resources, and live functional evidence. |
| Least Privilege and Secret Hygiene | PASS | Dedicated tokenless service accounts are used; users and todos reuse the existing ESO-generated JWT Secret without storing its value. |
| Declarative and Policy-Controlled Platform | PASS | Redis is folder-discovered under `infrastructure/`; services are folder-discovered under `apps/`; ArgoCD owns both. |
| Proven DR and Disclosed Data Loss | PASS | Redis ephemerality, todos process memory, and users H2 reseeding are explicit; no durability or DR claim is made. |

Post-design re-check: PASS. The frontend exposure decision uses the already
ratified local port-forward seam and adds no ingress design. The Redis and
service manifests remain provider-neutral and do not weaken the enforced
Kyverno baseline.

## Project Structure

### Documentation (this feature)

```text
specs/004-service-onboarding/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── remaining-service-registration.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
infrastructure/redis/
├── kustomization.yaml
├── namespace.yaml
├── serviceaccount.yaml
├── deployment.yaml
├── service.yaml
├── networkpolicy.yaml
└── README.md

apps/
├── todos-api/
├── users-api/
├── frontend/
└── log-message-processor/
    # each service contains:
    ├── base/{kustomization.yaml,deployment.yaml,service.yaml,serviceaccount.yaml,configmap.yaml}
    ├── components/{topology-economical,topology-full}/kustomization.yaml
    ├── topology/kustomization.yaml
    └── overlays/{local,dev,staging,prod}/kustomization.yaml

environments/local/
├── namespace.yaml                    # reusable environment label
└── networkpolicy-allow-redis.yaml    # only declared Redis consumers

clusters/base/
└── project.yaml                      # exact Redis namespace destination

scripts/pilot/
├── lib/common.sh                     # render/image-edit helpers
├── publish-services.sh               # staged Redis then suite publication
├── publish-auth.sh                   # compatibility wrapper
├── verify-services.sh                # composite read-only evidence
├── verify.sh                         # auth verification valid in multi-service pilot
└── bootstrap.sh                      # embedded-Kustomize fallback

tests/contract/
├── platform-addons.sh                # five active infrastructure roots incl. Redis
└── service-onboarding.sh             # service, secret, image, probe, and provider contract

docs/
├── local-pilot-quickstart.md
└── service-onboarding.md
```

**Structure Decision**: Every new business workload reproduces the established
auth-api base/component/topology/overlay seam, so the unchanged `apps/*` matrix
generator creates its Application. Redis is a direct `infrastructure/*`
Kustomize root, so the unchanged platform generator creates `infra-redis`.
Local port-forward remains environment-owned exposure; no frontend-specific
cluster path is added.

## Reconciliation Sequence

1. Render and statically validate Redis plus all four service registrations.
2. Build all five current service sources once, push to the loopback registry,
   and record registry-reported immutable digests without changing cluster state.
3. Commit Redis and the exact AppProject destination to local pilot `main`.
4. Wait for `infra-redis` at that SHA, its Deployment availability, and `PONG`.
5. Copy the reviewed desired-state tree into the disposable local clone, restore
   the current auth digest or select the just-built auth digest, set all remaining
   image digests, activate `local`, commit, and push only to local pilot `main`.
6. Wait for auth-api and all four new service Applications at the final SHA.
7. Run the composite evidence flow and retain every raw observation.

## Complexity Tracking

No constitution violation or exception is required. The additional publishing
and verification scripts generalize existing pilot operations; they do not add
a deployment mechanism.

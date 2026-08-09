# Implementation Plan: Local GitOps Pilot Reconciliation

**Branch**: `main` | **Date**: 2026-08-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-local-gitops-pilot/spec.md`

## Summary

Keep the working App-of-Apps root, ApplicationSet discovery pattern, and
`auth-api` Kustomize base/overlay split, then close only reconciliation gaps 3
through 10. The reconciled pilot will use a machine-local Git remote and OCI
registry, a dedicated `local` overlay selected by a reusable cluster
registration, digest-only image selection, External Secrets Operator (ESO),
environment-owned namespace controls, least-privilege ArgoCD projects, and a
scripted evidence workflow. Production remains inactive until its constitutional
rollout and policy prerequisites exist.

The ignored secret values file introduced during reconciliation is a temporary
bridge only. ArgoCD cannot read ignored workstation files from a clean clone, so
implementation must install ESO first and then replace that bridge with a
GitOps-managed `Password` generator and `ExternalSecret` while preserving the
workload's `auth-api-secrets/JWT_SECRET` interface.

## Reconciliation Scope

| Report gap | Planned closure |
| --- | --- |
| 3. Fully local sources | Serve a local bare Git repository read-only over HTTP, run a host-local OCI Distribution registry, vendor pinned controller manifests, and pre-acquire every runtime image by digest. |
| 4. Local vs. managed environments | Add `overlays/local`, introduce a reusable cluster-registration base, and constrain `local-kind` to the `local` overlay only. |
| 5. Immutable artifacts | Commit `newName` plus `sha256` digest, reject tag-only updates, and prove change and Git-revert convergence. |
| 6. Secret hygiene | Reconcile pinned ESO first, generate pilot material locally through ESO, and retain the same Secret name/key for a future AWS provider. |
| 7. Configuration ownership and privilege | Move capacity to overlays; move quota, limits, policy, and RBAC to the environment layer; tighten AppProjects; remove Kind assumptions from the base. |
| 8. Eight-service reuse | Define a machine-checkable service/environment contract and render `auth-api` plus seven abstract service slots without deploying them. |
| 9. Newcomer workflow and evidence | Supply an English quickstart, preflight, deterministic scripts, structured run evidence, timing exercises, and operator evaluation records. |
| 10. Production disabled | Make production impossible to select from the pilot and test the rollout/policy prerequisite gate. |

Gaps 1 and 2 are not replanned. The specification is now on `main`, and
Constitution 1.1.0 permits only the documented minimal one-time controller and
root-Application bootstrap. All state after that handoff remains ArgoCD-owned.

## Technical Context

**Language/Version**: Bash 5-compatible shell scripts; Kubernetes YAML;
Kustomize API `v1beta1` rendered with the `kubectl`-bundled Kustomize 5.8.1

**Primary Dependencies**: Docker Engine; Kind 0.32.0 with
`kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5`;
Argo CD 3.5.0; External Secrets Operator 2.7.0; OCI Distribution 3.1.1;
Git 2.x; `kubectl` 1.36-compatible; `curl`; `jq`

**Storage**: Git-tracked desired state and evidence; ignored `.local/` storage
for the bare pilot remote, disposable worktrees, registry data, command logs,
and port-forward process state

**Testing**: Kustomize renders; shell/static conformance checks; ApplicationSet
generation and ArgoCD reconciliation checks; Kubernetes readiness inspection;
three HTTP health checks over at least 60 seconds; uncommitted-edit, commit, and
Git-revert exercises; three clean-run timing captures; two manual first-time
operator evaluations

**Target Platform**: A Linux developer workstation with Docker and cgroup v2,
on either `amd64` or `arm64`; one disposable single-node Kind cluster

**Project Type**: Declarative GitOps repository with shell-based local bootstrap,
validation, and evidence tooling

**Performance Goals**: Reach a passing health check within 20 minutes and eight
newcomer-entered commands; reconcile each available desired-state commit within
five minutes; restore the prior healthy digest/configuration within five minutes
of a revert; pass three clean runs; preserve a 60-second three-check health
window

**Constraints**: Exactly one MicroTodoSuite business service; no AWS/Azure
credentials, paid or hosted runtime dependency after initial acquisition, or
direct workload mutation; localhost-only exposed helper ports; no `latest` or
tag-only deployed image; no secret value in Git; production registration stays
disabled; supported host has at least 4 logical CPUs, 8 GiB available RAM, and
20 GiB free disk

**Scale/Scope**: One local cluster, one active environment, one deployed service,
two local infrastructure controllers (ArgoCD and ESO), one local Git source, one
local registry, seven non-deployed service-slot fixtures, and future cluster
registration fixtures

## Constitution Check

*GATE: Must pass before Phase 0 research and after Phase 1 design.*

| Constitutional rule | Pre-design result | Design requirement |
| --- | --- | --- |
| Environment isolation | PASS | The sole business namespace is environment-owned and includes ResourceQuota, LimitRange, enforced NetworkPolicy, and namespace RBAC. No dev/staging/prod namespaces are co-deployed. |
| GitOps-only deployment | PASS | The only direct mutations are the audited one-time ArgoCD installation and initial root Application allowed by Constitution 1.1.0. Workloads, ESO, policies, and later changes are commits reconciled by ArgoCD. |
| Stable trunk | PASS | The pilot remote advances `main` with short, auditable local commits. Scripts never rewrite history or push the hosted `origin`. |
| Authoritative specifications | PASS | `spec.md`, this plan, research, data model, contracts, quickstart, and generated tasks drive implementation. |
| Cost-governed design | PASS within pilot boundary | The pilot uses only declared local resources and records workstation requirements. It neither adopts nor claims a managed cost profile; production remains disabled. |
| Immutable build promotion | PASS | Active overlays require an OCI manifest or index digest. The same digest is copied during promotion; tag-only input is rejected. |
| Progressive and reversible releases | PASS within pilot boundary | Development-style local reconciliation is permitted, rollback is a Git revert, and production is gated until Argo Rollouts and metric analysis exist. |
| Quality and supply-chain gates | PASS within pilot boundary | Bootstrap assets and deployed images are digest locked and verified. The pilot does not claim production supply-chain completion, and the production gate records the remaining CI/signing/admission prerequisites. |
| Observable and healthy operation | PASS | Existing startup/readiness/liveness probes stay in the reusable base; evidence records Argo sync, readiness, and repeated intrinsic health. Full production observability remains outside this pilot and cannot be advertised as delivered. |
| Least privilege and secret hygiene | PASS | ESO owns the generated Secret, no secret literal enters Git, service accounts receive no Kubernetes API token by default, namespace controls are present, and AppProjects use exact repositories/destinations/kind allowlists. |
| Declarative platform ownership | PASS | After the amended bootstrap boundary, ArgoCD owns itself, ESO, namespace policy, and `auth-api`. Placeholder add-ons remain disabled. |
| Disaster recovery | PASS as out of scope | No production or DR capability is activated or claimed; future environment fixtures only prove the registration contract. |

### Post-Phase 1 Re-check

PASS. The data model and contracts preserve the same gates: the bootstrap
allowlist contains only controller/root installation, the service CLI publishes
only to the local `pilot` remote, the evidence schema records any unsupported
mutation, ESO preserves the stable Secret contract, and conformance explicitly
fails an active production registration. No constitutional waiver is required.

## Project Structure

### Documentation (this feature)

```text
specs/001-local-gitops-pilot/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── local-pilot-cli.md
│   ├── pilot-evidence.schema.json
│   └── service-onboarding-contract.md
└── tasks.md
```

### Repository layout after implementation

```text
apps/
└── auth-api/
    ├── base/                         # retained environment-neutral workload
    └── overlays/
        ├── local/                    # sole active pilot overlay
        ├── dev/                      # inactive managed-environment scaffold
        ├── staging/                  # inactive managed-environment scaffold
        └── prod/                     # inactive and production-gated scaffold

bootstrap/
├── argocd/
│   └── vendor/v3.5.0/                # verified upstream manifest + provenance
└── local/
    ├── assets.lock                   # versions, source refs, and OCI digests
    ├── kind-config.yaml
    ├── registry/hosts.toml
    └── git-source/                   # pinned static HTTP source configuration

clusters/
├── base/
│   ├── apps.yaml                     # reusable Matrix ApplicationSet
│   ├── environment.yaml
│   ├── infrastructure.yaml
│   ├── argocd.yaml
│   ├── projects/
│   └── environment/                  # quota, limits, NetworkPolicy, RBAC
└── local-kind/
    ├── kustomization.yaml            # registration values only
    ├── registration.yaml
    └── root-app.yaml

infrastructure/
└── external-secrets/                 # pinned, vendored ESO installation

templates/
└── service/                           # machine-replaceable onboarding scaffold

scripts/
├── bump-image.sh                     # digest-only desired-state commit helper
└── pilot/
    ├── preflight.sh
    ├── acquire-assets.sh
    ├── bootstrap.sh
    ├── publish-auth.sh
    ├── verify.sh
    ├── exercise-uncommitted.sh
    ├── exercise-change-revert.sh
    ├── run-three-clean.sh
    ├── conformance.sh
    └── cleanup.sh

tests/conformance/
├── service-contract.sh
├── cluster-contract.sh
├── production-disabled.sh
└── fixtures/
    ├── service-slots/                 # seven abstract, non-deployed slots
    └── clusters/                      # local and future EKS registrations

tests/integration/
├── bootstrap-boundary.sh
├── initial-deploy.sh
├── uncommitted-edit.sh
├── change-revert.sh
└── newcomer-workflow.sh

evidence/
├── README.md
├── operators/
└── runs/                              # committed acceptance records

docs/
├── local-pilot-quickstart.md
├── operator-evaluation.md
└── production-readiness.md
```

**Structure Decision**: Retain `apps/<service>/base` and
`apps/<service>/overlays/<environment>` as the service contract. Extract only
the repeated cluster mechanism into `clusters/base`; each concrete cluster is a
Kustomize overlay containing repository, revision, destination, namespace,
environment, image-registry, and capacity values. Namespace-wide policy belongs
to the cluster/environment tree, never to `auth-api`. Runtime state stays under
ignored `.local/`; only deliberately selected evidence is committed.

## Implementation Sequence

1. Add the asset lock, vendored manifests, preflight, local Git source, local
   registry, and audited bootstrap while retaining the existing root skeleton.
2. Reconcile and verify ESO before removing the ignored-file secret bridge.
3. Extract the cluster base, add the disabled-by-default local registration,
   split AppProjects, and move environment-owned policy.
4. Add the `auth-api` local overlay with digest-only activation and update the
   image helper to commit/push only to the local pilot remote.
5. Add service/cluster/production conformance checks and seven abstract slots.
6. Add evidence scripts, English quickstart/troubleshooting/cleanup, three-run
   capture, and operator evaluation forms.
7. Execute every success criterion, commit admissible evidence, and leave
   production inactive.

The ESO sequencing is deliberate: one root-reconciled commit installs the
controller; a later desired-state commit removes `secretGenerator`, introduces
the `Password` and `ExternalSecret`, and activates `auth-api`. Parent sync-wave
annotations alone are not treated as proof that independently reconciled child
Applications are ready.

## Risk Controls

- Prove ArgoCD 3.5.0 can fetch the chosen bare-repository HTTP endpoint before
  building the rest of the workflow. If the Git client's dumb-HTTP integration
  test fails, keep the same bare repository and URL contract but replace only
  the serving adapter with `git-http-backend`; do not introduce a hosted source.
- Derive the platform AppProject resource allowlist from rendered vendored
  manifests and fail conformance on `*/*`; do not guess controller privileges.
- Require Kind's network-policy-capable pinned node and include a positive and
  negative enforcement test; a rendered NetworkPolicy alone is insufficient.
- Treat the previously committed JWT literal as compromised permanently.
  Rotation occurs outside Git; neither tree cleanup nor history preservation is
  presented as rotation.
- Resolve and record manifest/index digests after pushing. Reject local image IDs,
  config digests, tags, and all-zero placeholders as deployment evidence.
- Use the OCI index digest for multi-platform images and verify equal digests if
  a later environment copies an artifact between registries.
- Bind the unauthenticated local Git and registry ports to loopback and attach
  their containers only to the Kind network. These are pilot-only connections;
  EKS registrations use approved TLS and identity controls.
- Never let scripts push `origin`, apply workload YAML, run rollout undo, or use
  manual sync as a success path. The command log makes violations visible.

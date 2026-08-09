# GitOps Pilot Reconciliation Assessment

- **Assessment date**: 2026-08-08
- **Implementation assessed**: `main` at `4fade6d`
- **Prior specification assessed**: `esteban/local-pilot-spec` at `aa93f80`
- **Constitution assessed**: MicroTodoSuite Constitution 1.0.0

## Executive verdict

The teammate setup is a useful partial implementation, but it does **not** satisfy the local GitOps pilot specification and is **not** compliant with the constitution as committed.

The strongest reusable pieces are the ArgoCD App-of-Apps skeleton, the application directory generator, and the `auth-api` base/overlay split. All three application overlays render successfully with the Kustomize version bundled in the installed `kubectl` client. The manifests also define startup, readiness, and liveness probes against the service-owned `/version` endpoint.

Those strengths do not close the acceptance gap. The current tree explicitly documents two direct `kubectl apply` operations, continuously depends on hosted GitHub as ArgoCD's source, commits a JWT secret literal, deploys mutable image tags, conflates the local pilot with `dev`, `staging`, and `prod`, lacks a current quickstart or verification record, and puts environment-owned settings in the service base. A successful deployment reported by a teammate is useful testimony, but it is not evidence for the specification's measured success criteria.

No success criterion can be marked passed from the repository evidence. Five criteria fail because required implementation or documentation is absent or contradictory; four cannot be verified without the runtime evidence required by the criterion.

## Assessment scope and evidence

The assessment used:

- The complete tracked tree and Git history of `main` through `4fade6d`.
- The prior specification at `../gitops-pilot-spec-review/specs/001-local-gitops-pilot/spec.md`.
- The constitution resolved through `../gitops-pilot-spec-review/.specify/memory/constitution.md`.
- Read-only Kustomize renders of the `dev`, `staging`, and `prod` overlays.

No cluster state, ArgoCD status, workload logs, timing records, or teammate test notes were supplied or queried. Therefore, deployment and timing claims that require runtime observation are classified as **cannot verify**, not inferred from declarative configuration.

The current `main` checkout does not contain `.specify/memory/constitution.md`, the feature specification, `plan.md`, or `tasks.md`. The specification branch and `main` have unrelated Git histories: `git merge-base main esteban/local-pilot-spec` returns no common ancestor. The constitution was therefore read from the review worktree symlink, not from `main`.

## 1. Success criteria reconciliation

| Criterion | Result | Repository evidence and conclusion |
| --- | --- | --- |
| **SC-001**: first-time teammate reaches healthy `auth-api` in at most 20 minutes and 10 commands | **FAIL** | Current `README.md` contains only its title (`README.md:1`). There is no current prerequisite list, cluster creation sequence, health command, expected checkpoints, troubleshooting, or cleanup. A 75-line guide existed at `5a3162f` but was deleted by `4fade6d`; deleted documentation does not make the current checkout reproducible. |
| **SC-002**: three clean local runs synchronize, become ready, and become healthy within five minutes from a commit reaching the local repository source | **FAIL** | There is no local repository source. The root Application, AppProject, self-management Application, application generator, and infrastructure generator hardcode hosted GitHub (`clusters/local-kind/root-app.yaml:15`, `project.yaml:13`, `argocd.yaml:13`, `apps.yaml:18,31`, and `infrastructure.yaml:15,30`). No record of three runs or their elapsed time exists. |
| **SC-003**: initial deployment, one change, and one rollback all map to commits, with no direct workload application | **CANNOT VERIFY** | Automated sync, prune, and self-heal are configured (`clusters/local-kind/root-app.yaml:21-24`; `apps.yaml:37-40`). Git history contains an image bump (`4a6801c`) and a revert (`c42fb66`). There is no record showing that the initial state, bump, and revert were each observed in the cluster. The direct bootstrap applies are a separate constitutional failure described below. |
| **SC-004**: an uncommitted edit causes no change during five minutes | **CANNOT VERIFY** | ArgoCD points to remote `main`, so the structure suggests that a local uncommitted edit is not its source. No five-minute observation or verification record exists. |
| **SC-005**: a Git revert restores the prior healthy state within five minutes | **CANNOT VERIFY** | The bump and revert commits prove repository history only. There is no ArgoCD revision/status capture, health result, or elapsed-time record proving cluster restoration. |
| **SC-006**: exactly one business service and three successful health checks over at least 60 seconds | **CANNOT VERIFY** | The tracked workload manifests contain only `auth-api`, and all three health probes use `/version` (`apps/auth-api/base/deployment.yaml:28-46`). However, `apps.yaml:17-21` discovers all three overlays, producing three `auth-api` Applications with six desired replicas in total. There is no business-service count report or record of three health checks over 60 seconds. |
| **SC-007**: conformance review finds zero structural or ownership changes for seven services and future managed environments | **FAIL** | No conformance review exists. The base commits a local secret (`base/kustomization.yaml:11-19`), fixes resource limits in the base (`base/deployment.yaml:47-53`), and carries a kind-specific image policy (`base/deployment.yaml:15`). The production namespace quota is owned by the `auth-api` overlay rather than the environment (`overlays/prod/kustomization.yaml:8-10`). The cluster generator deploys every overlay to the same in-cluster destination and explicitly says it must be copied, filtered, and changed for EKS (`clusters/local-kind/apps.yaml:5-7`). |
| **SC-008**: no cloud credentials, paid services, hosted clusters, registries, secret stores, or runtime services | **FAIL** | Cloud credentials and a hosted registry are not required by the checked-in application manifests, but hosted GitHub is a continuous reconciliation dependency. ArgoCD also fetches its installation manifest from `raw.githubusercontent.com` (`bootstrap/argocd/kustomization.yaml:13`). This is not the fully local repository and reconciliation path required by the criterion. |
| **SC-009**: two first-time operators can identify revision, reconciliation, readiness, and health, rating clarity at least 4/5 | **FAIL** | The current repository provides neither the instructions nor the verification output needed for the task, and contains no first-time operator results or ratings. |

### Supporting behavior that is present but is not acceptance evidence

- `apps/auth-api/base` and all three overlays render without Kustomize errors.
- The ArgoCD root Application enables automated pruning and self-healing.
- The application ApplicationSet discovers `apps/*/overlays/*`, so adding a directory can generate another Application without editing the generator.
- `auth-api` has explicit startup, readiness, and liveness probes and bounded CPU/memory settings.
- Git history contains a desired-state change followed by a Git revert.

These facts justify retaining parts of the implementation, but none substitutes for the measured outcomes required by the specification.

## 2. Constitution compliance

### Pilot-relevant principles

| Constitutional requirement | Result | Explicit deviation |
| --- | --- | --- |
| **GitOps-only deployment** (`constitution.md:19-21`) | **FAIL** | `bootstrap/argocd/kustomization.yaml:4-7` instructs `kustomize build ... | kubectl apply`, and `clusters/local-kind/root-app.yaml:1-4` instructs a second direct `kubectl apply`. The constitution forbids direct `kubectl apply` without a bootstrap exception. Automatic ArgoCD management after those commands does not erase the violation. |
| **Authoritative specifications** (`constitution.md:27-29,98-100`) | **FAIL** | The teammate implementation is on `main`, while the constitution and feature specification exist only in a separate unrelated-history branch. `main` contains no spec, plan, or tasks from which the implementation could have been derived. Existing code cannot supersede the specification under the governance rule. |
| **Environment isolation** (`constitution.md:15-17`) | **FAIL** | The setup represents dev, staging, and production as namespaces in one cluster. Only production has a ResourceQuota, and there are no LimitRanges, NetworkPolicies, or namespace RBAC controls. There is no recorded formal adoption of the cost-optimized namespace profile. |
| **Immutable build promotion** (`constitution.md:35-37`) | **FAIL** | All overlays deploy `0.1.0-local` by mutable tag (`overlays/*/kustomization.yaml`), and `scripts/bump-image.sh:10-24` accepts and commits an arbitrary tag. No image digest, build-once evidence, signature, or same-digest promotion is encoded. |
| **Progressive and reversible releases** (`constitution.md:39-41`) | **FAIL** | A repository revert exists, but no cluster restoration evidence exists. The production overlay uses a standard Deployment; no Argo Rollout, metric gate, or automatic rollback is configured. The `infrastructure/argo-rollouts` directory is only an empty placeholder. |
| **Observable and healthy operation** (`constitution.md:47-49`) | **FAIL overall; health-probe portion present** | Startup, readiness, and liveness probes are correctly declared, but the required operational telemetry, alerting, scaling, and resilience platform is not present. Empty infrastructure placeholders are not implemented capabilities. |
| **Least privilege and secret hygiene** (`constitution.md:51-53`) | **FAIL** | `apps/auth-api/base/kustomization.yaml:11-19` commits `JWT_SECRET=local-dev-secret-not-for-prod`, and the rendered Secret contains that value. The AppProject permits every namespace and every cluster-scoped resource kind (`clusters/local-kind/project.yaml:14-19`). External Secrets and namespace-scoped RBAC are absent. |
| **Declarative and policy-controlled platform** (`constitution.md:55-57`) | **FAIL** | ArgoCD does declaratively own application state after bootstrap, but ArgoCD and the root Application are installed imperatively. Platform add-on directories contain only `.keep` files. The repository therefore has wiring and placeholders, not the constitutionally required platform ownership. |

### Other governance observations

- Repository history alone cannot verify mandatory reviews, required checks, short-lived branches, or feature-flag governance.
- The current setup does not implement the constitution's supply-chain, cost, disaster-recovery, or full production-platform requirements. Those items are outside the narrow local-pilot scope, but the repository must not describe their placeholder directories as delivered capabilities.
- The project convention requires English artifacts. The teammate manifests, comments, script usage/errors, and commit messages are predominantly Spanish. This is a concrete repository-convention violation even though it is not a separate constitutional principle.

## 3. Reusability assessment

### What is reusable

The directory shape is a credible starting convention:

```text
apps/<service>/base/
apps/<service>/overlays/<environment>/
clusters/<cluster>/
```

The wildcard application generator is service-name agnostic, Kustomize selectors render correctly, and replicas, namespaces, and image tags are already separated into overlays. These parts can remain as the implementation baseline.

### Why it is not reusable to the specification's standard

1. **There is no reusable workload component or service contract.** The only base is `apps/auth-api/base`, which hardcodes the service name, port, probes, configuration names, downstream address, labels, image name, and secret. Another service must create and edit a new set of manifests. The ApplicationSet is reusable; the base manifests themselves are not reusable unchanged for the other seven services.
2. **Local-only values leak into the base.** The committed demo secret, `IfNotPresent` policy justified by `kind load`, and fixed CPU/memory values live in the environment-neutral base. The spec explicitly treats capacity limits as environment-specific.
3. **There is no local overlay.** Local tags are stored in the `dev`, `staging`, and `prod` overlays, so the disposable pilot and future managed environments are conflated.
4. **Every cluster receives every overlay.** `clusters/local-kind/apps.yaml:17-36` scans all service/environment combinations and sends all of them to the same cluster. Its comments acknowledge that EKS needs a copied generator with filtering and a changed destination. The EKS-ready form is described, not implemented or proven.
5. **Environment-owned policy is attached to one service.** `apps/auth-api/overlays/prod/resourcequota.yaml` governs the shared production namespace. If seven more services follow the same structure, they either duplicate the same quota or implicitly make `auth-api` own a platform concern. Quotas, LimitRanges, NetworkPolicies, and RBAC belong under the cluster/environment layer.
6. **Repository and destination values are duplicated rather than parameterized.** The hosted repository URL appears in seven fields across five cluster files, and the in-cluster destination and namespace naming convention are embedded in the generator. Moving between local, EKS, and AKS requires coordinated file edits rather than changing one environment registration.
7. **Artifact promotion is tag-based.** The current overlay and bump script cannot prove that the same immutable build moves from development to staging and production.
8. **The real-cluster claim is not reproducible from Git.** The base image is `auth-api:placeholder`, overlays select `auth-api:0.1.0-local`, and the base assumes an image preloaded into kind. No registry location or digest explains how a clean non-kind cluster obtains that artifact. Any manual node image seeding would be outside the recorded desired state.

The correct conclusion is that the repository contains a reusable **shape and controller skeleton**, not the reusable, environment-neutral deployment contract required by FR-013 through FR-016 and SC-007.

## 4. Recommendation

### **(b) Accept the setup with specific adjustments needed to meet the specification and constitution**

Accept the App-of-Apps, ApplicationSet, and Kustomize base/overlay skeleton as the implementation baseline. Do **not** accept the pilot as complete and do not retroactively document the current state as if it already met the specification.

The following adjustments are mandatory before acceptance:

1. **Reconcile the source of truth into `main`.** Bring the constitution and feature specification into the implementation history deliberately, then create `plan.md` and `tasks.md` for the remaining work. Account explicitly for the unrelated histories; do not let the existing implementation silently override the spec.
2. **Remove the two direct-apply deployment instructions.** Seed ArgoCD and the root Application through a governed, reproducible cluster-bootstrap mechanism owned by the foundation. If the team intends to retain a one-time `kubectl apply` exception, the constitution must be amended and approved first; under Constitution 1.0.0 the current commands are prohibited.
3. **Make the running pilot fully local.** Provide a repository source and image source on the developer machine, parameterize ArgoCD's repository endpoint, and vendor or pre-acquire the pinned ArgoCD installation artifact so reconciliation does not continuously depend on GitHub or another hosted service.
4. **Separate local from managed environments.** Add a dedicated local overlay and make each cluster registration select only its intended overlay. The local pilot must not deploy development, staging, and production simultaneously. Future EKS cluster entries must change only registered environment values, not the generator contract.
5. **Use immutable artifacts.** Record an image digest in desired state, promote the same digest, and make the update workflow reject floating or tag-only references. Preserve Git revert as the rollback operation and capture the reconciled revision before and after rollback.
6. **Remove committed secret material.** Replace the base `secretGenerator` literal with a declarative external-secret reference. Generate demonstration material on the developer machine and keep it outside Git; use the same reference contract with the future approved managed secret provider.
7. **Correct configuration ownership.** Move CPU/memory limits to environment overlays; move ResourceQuota, LimitRange, NetworkPolicy, and RBAC to the cluster/environment layer; remove kind-specific assumptions from the service base; and tighten AppProject source, destination, namespace, and cluster-resource permissions.
8. **Define and test the eight-service contract.** Add a shared component or documented service template that identifies required service-specific inputs and environment-specific inputs. Validate all seven remaining service slots by rendering or contract checks without deploying them, and prove that a future EKS registration needs no hierarchy or reconciliation-mechanism change.
9. **Restore an English newcomer workflow and evidence harness.** Document prerequisites, supported workstation resources, at most ten commands, checkpoints, health access, troubleshooting without direct apply, and cleanup. Record three clean runs, reconciliation time, the uncommitted-edit observation, change and revert timings, exactly-one-service evidence, three health checks over 60 seconds, and two first-time operator results.
10. **Do not expose production semantics prematurely.** Keep production out of the pilot generator until required namespace controls, immutable promotion, Argo Rollouts canary behavior, policy gates, and required platform dependencies exist. Placeholder directories must remain labeled as unimplemented.

After these adjustments, rerun every success criterion and store the evidence in the repository. Until that evidence exists, the teammate's successful deployment should be treated as a useful demonstration of the controller skeleton, not as acceptance of the specified pilot.

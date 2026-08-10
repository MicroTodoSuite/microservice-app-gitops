# Acceptance Checklist: Shared-Cluster Namespace Isolation

**Purpose**: Record static and live evidence without converting manifest intent into a pass

**Created**: 2026-08-09

**Feature**: [spec.md](../spec.md)

## Authoritative Prerequisites

- [ ] Constitution v1.2.0 is merged to `microservice-app-docs/main`
- [ ] `.specify/memory/constitution.md` is byte-identical to the authoritative file
- [ ] The shared-cluster ops handoff supersedes the former dedicated-dev/full-profile contract
- [ ] `clusters/eks-main` is reviewed, reconciled, and activates exactly dev, staging, and prod
- [ ] VPC CNI network policy is enabled declaratively and proven on every eligible node
- [ ] AWS principal-to-group mappings are approved and observed for all three environment groups
- [ ] Existing dev workloads, dependencies, resources, and health are recorded in a passing baseline

## Static Desired-State Evidence

- [ ] Dev, staging, and prod render successfully from the same managed base
- [ ] All three namespace names and labels match the fixed mapping
- [ ] All three ResourceQuotas include CPU/memory requests/limits and pod count
- [ ] Quota values have a reviewed capacity and rollout-headroom rationale
- [ ] All three renders include bounded LimitRange defaults and maxima
- [ ] All three renders include ingress-and-egress default deny, DNS, and same-namespace policy
- [ ] Every additional allowance has exact source, destination, protocol, port, and owner evidence
- [ ] All three RoleBindings use only their exact stable maintainer group
- [ ] The custom Role excludes isolation controls, Secrets, and cluster-scoped resources
- [ ] Wildcard subjects/verbs/resources, `system:authenticated`, personal IAM ARNs, and broad cross-environment allowances are absent
- [ ] Verification images are selected by immutable digest
- [ ] `environments/local` is unchanged and existing contract tests pass
- [ ] All renders pass the implementation's pinned schema validator
- [ ] Evidence JSON Schema is valid

## Staged Live Evidence

- [ ] Foundation revision converges in all three environment Applications before default deny
- [ ] Dev loses zero ready replicas and adds zero attributable restarts after foundation convergence
- [ ] Required dev connections and health checks pass after foundation convergence
- [ ] Default-deny revision converges at the exact reviewed SHA
- [ ] Dev loses zero ready replicas and adds zero attributable restarts after default deny
- [ ] Six unique directed cross-environment TCP attempts are denied
- [ ] Three same-environment TCP attempts are allowed
- [ ] DNS succeeds in dev, staging, and prod
- [ ] Deliberate over-budget Deployment cannot realize its excess pod and records the expected event
- [ ] Comparison-environment workload remains ready, restart-stable, and healthy during the violation
- [ ] RBAC matrix contains exactly three own-environment workload allows and six cross-environment denies
- [ ] All maintainer groups are denied isolation-control changes
- [ ] Unbound subject is denied in every managed namespace
- [ ] ArgoCD platform principal retains its required reconciliation capability

## Cleanup and Final Evidence

- [ ] Fixture activation is removed by reviewed Git revert
- [ ] All three environment Applications are Synced/Healthy at the cleanup revision
- [ ] No verification fixture remains in any managed namespace
- [ ] Dev remains ready, restart-stable, connected, and healthy for ten minutes after cleanup
- [ ] `summary.json` validates against the evidence schema
- [ ] Raw observations support every summarized result
- [ ] Command audit contains zero direct managed-state mutations
- [ ] Final result is `PASS` only after every item above is evidenced

## Current Status

**NOT READY FOR IMPLEMENTATION OR LIVE ACCEPTANCE.** The planning artifacts are
complete, but the authoritative amendment, shared registration, CNI enforcement,
identity mappings, and dev baseline remain external gates. No checkbox in this
file is satisfied by the current documentation-only work.

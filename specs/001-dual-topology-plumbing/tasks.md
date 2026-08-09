---
description: "Task list for dual-topology plumbing"
---

# Tasks: Dual-Topology Plumbing

**Input**: Design documents from `/specs/001-dual-topology-plumbing/`

**Prerequisites**: plan.md, spec.md

**Tests**: Schema validation (`kubeconform`) and live regression on kind. No unit
test framework applies to declarative manifests.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] T001 Create feature branch `001-dual-topology-plumbing` and directory scaffold
- [X] T002 [P] Add `AGENTS.md` (+ `CLAUDE.md` symlink) per ai-agents convention

## Phase 2: Foundational

- [X] T003 Author SDD artifacts (spec.md, plan.md, tasks.md) in English

## Phase 3: User Story 2 - Topology components (Priority: P2) 🎯

**Goal**: One-file version switch per service, reusing base.

- [X] T004 [US2] Create Component `apps/auth-api/components/topology-economical/`
- [X] T005 [US2] Create Component `apps/auth-api/components/topology-full/`
- [X] T006 [US2] Create single-switch `apps/auth-api/topology/kustomization.yaml`
- [X] T007 [US2] Repoint overlays `dev|staging|prod` to `../../topology`
- [X] T008 [US2] Validate all overlays render under both components

**Checkpoint**: Economical and full behavior selectable from one file.

## Phase 4: User Story 1 - Externalized destinations (Priority: P1) 🎯 MVP

**Goal**: Environment→destination mapping externalized in the ApplicationSet.

- [X] T009 [US1] Rewrite `clusters/local-kind/apps.yaml` to matrix(git apps/*, list envs)
- [X] T010 [US1] Encode economical environments (local server, namespace targets)
- [X] T011 [US1] Document full-version retargeting in `clusters/README.md`
- [X] T012 [US1] Live regression on kind: same 3 auth-api Applications, same pods

**Checkpoint**: Retargeting is data-only; economical behavior unchanged.

## Phase 5: User Story 3 - Canary strategy component (Priority: P3)

**Goal**: Rollout strategy as a reusable, activatable module.

- [X] T013 [US3] Create Component `strategy-canary/` (Rollout via workloadRef + steps)
- [X] T014 [US3] Add `AnalysisTemplate` template (Prometheus-gated, not wired yet)
- [X] T015 [US3] Schema-validate with `-ignore-missing-schemas`; keep prod on Deployment
- [X] T016 [US3] Document activation (install argo-rollouts, opt-in in prod overlay)

## Phase 6: Polish

- [X] T017 Validate every overlay with `kubeconform -strict`
- [X] T018 Commit on feature branch and open PR (trunk-based short-lived branch)

## Dependencies & Execution Order

- Setup (P1) → Foundational (P3) → US2 (topology layer) → US1 (targeting) → US3.
- US2 precedes US1 because overlays must reference `topology/` before targeting is
  validated end-to-end; US3 builds on the topology layer but stays inactive.

## Notes

- Economical stays live throughout (FR-003). Full/canary pieces are prepared and
  schema-checked only. Activation of the full version is a later roadmap step and
  depends on infrastructure (tasks 1-2).

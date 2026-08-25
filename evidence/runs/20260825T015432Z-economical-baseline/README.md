# Authoritative pre-rollout economical baseline

Task **T036** of `specs/009-full-platform-rollout`. This is the state SC-001 is
measured against for the rest of the rollout.

Captured by `scripts/managed/capture-economical-baseline.sh`, which is strictly
read-only and fails closed.

| | |
| --- | --- |
| Revision under test | `7c8cf51a` (`origin/main`, what ArgoCD reconciles) |
| ArgoCD Applications | **39/39 synced, 39/39 healthy** |
| Workloads ready | 23/23 |
| Endpoints with addresses | 23/23 |
| Namespaces without a NetworkPolicy | none |
| Refreshed dev plan | clean |
| Result | `pass` |

The revision matters: an Application synced to anything other than the revision
under test means the baseline describes a platform that is not what Git says
exists. The first capture attempt was rejected for exactly that reason — it was
given an unmerged branch head rather than the revision ArgoCD tracks.

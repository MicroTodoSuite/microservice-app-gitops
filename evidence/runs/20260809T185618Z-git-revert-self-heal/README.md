# Git Revert and Live-Drift Self-Heal Evidence

**Run ID**: `20260809T185618Z-git-revert-self-heal`

**Context**: `kind-microtodo-gitops-pilot`

**Application**: `argocd/auth-api-local`

**Workload**: `microtodo-local/Deployment/auth-api`

**Result**: PASS for both deliberately executed live scenarios

## Git revert scenario

The pilot began healthy at revision
`831b0093745c0334baed3cca5f7765b074597ac8`, with one desired, Ready, and
available replica. Commit `82ac4c020c23710076af671861553a46c46bbe1a`
changed only the local overlay replica count from one to two and was pushed to
the machine-local pilot Git source. ArgoCD automatically reconciled that
revision, the Deployment reached two desired, Ready, and available replicas,
and `/version` returned HTTP 200. The recorded convergence was 6,716 ms.

A normal `git revert` produced
`b3ae23e9a1135efdd387c5669fb70ba794678410` and was pushed to the same source.
ArgoCD automatically reconciled the revert, restored one desired, Ready, and
available replica, and `/version` again returned HTTP 200. The recorded
convergence was 33,057 ms, below the 300,000 ms limit. The baseline and reverted
manifest blob are both `368e088e13d5b47d4995bf8053ba29eda491a203`.
No direct cluster mutation occurred during this scenario.

Primary records:

- [scenario summary](summary.json)
- [Git-revert summary](git-revert-summary.json)
- [change commit](change-commit.txt) and [revert commit](revert-commit.txt)
- [change Application](change-application.json) and [Deployment](change-deployment.json)
- [revert timeline](revert-timeline.ndjson), [Application](revert-application.json), and [Deployment](revert-deployment.json)
- [command log](command-log.tsv)

## Direct live-drift self-heal scenario

At the committed revert revision, the one authorized drift injection ran
`kubectl scale deployment/auth-api --replicas=2`. The mutation response records
`spec.replicas: 2`, while Git remained at
`b3ae23e9a1135efdd387c5669fb70ba794678410`. ArgoCD then reported the
Application `OutOfSync` and `Progressing`, started an automated operation with
`autoHealAttemptsCount: 1`, and restored the Deployment to one desired, Ready,
and available replica. The Application returned to `Synced` and `Healthy` at
the unchanged source revision in 2,559 ms; `/version` returned HTTP 200. No
manual correction was issued.

Primary records:

- [self-heal summary](self-heal-summary.json)
- [mutation response](drift-mutation-response.json) and [post-injection Deployment](drift-after-injection-deployment.json)
- [post-injection Application](drift-after-injection-application.json)
- [self-heal timeline](self-heal-timeline.ndjson), [Application](self-heal-application.json), and [Deployment](self-heal-deployment.json)
- [final Application](final-application.json), [Deployment](final-deployment.json), and [Git log](final-git-log.txt)

This live-drift test proves ArgoCD self-heal behavior. It does not replace the
literal SC-004 test in `spec.md`, which separately requires an uncommitted edit
in a disposable desired-state clone to produce no live change for five minutes.

## Preserved harness incident

The initial polling harness used a nanosecond timestamp as if it were
milliseconds and exited after its first forward-change poll. By then the
forward commit had already reconciled to two healthy replicas. The failure is
retained in [harness-recovery.json](harness-recovery.json). Recovery continued
from that observed state using only `git revert`; no `kubectl` correction was
used. The forward-change duration is derived from the recorded push timestamp
and the Deployment's `Available` transition timestamp. The failed harness's
single [change timeline](change-timeline.ndjson) sample retains the incorrect
epoch unit for auditability and is not used for the acceptance measurement.

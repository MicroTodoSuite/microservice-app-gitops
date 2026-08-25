# Economical rollback drill

Tasks **T037** and **T038**. Proves a failed stage is mechanically unable to
advance, and that attempting one disturbs nothing.

## What was exercised

A deliberately `blocked` no-op stage (`tests/evidence/fixtures/blocked-stage.json`)
with a dependent that wants to start:

```
FAIL: 'full-aws-environments' is blocked by 'no-op-blocked-drill':
      decision is 'blocked'; only 'accepted' unlocks a dependent
```

No activation occurred.

## Continuity

`baselines/pre.json` and `baselines/post.json` are **identical** apart from
their capture timestamps — `baselines/diff.txt` is empty. 39/39 Applications
synced and healthy before and after; 23/23 workloads ready before and after.

## Decision: `approved`, not `accepted`

Every mandatory check passes, so this bundle is complete. It stops at
`approved` on purpose.

`accepted` is the only decision that unlocks a dependent, and the validator
requires a **named human approval artifact** to record it. That gate exists so
an automated run cannot self-accept its own work and thereby unlock the entire
downstream rollout — which would make the gate decorative.

To accept: a maintainer adds an `approval` artifact with their `approvedBy`
identity and sets the decision to `accepted`. Until then `economical-invariant`
holds every dependent stage closed, which was verified explicitly.

# Feature Toggles

The full profile keeps incomplete behavior behind auditable, default-off
feature toggles, and lets a service's configuration change without rebuilding
its image (spec 009 FR-034, T090, `research.md` Decision 23). The economical
profile has no feature toggles.

## Where toggles live

- Each service's full topology component,
  `apps/<service>/components/topology-full/`, generates a
  `<service>-feature-toggles` ConfigMap with Kustomize's `configMapGenerator`,
  annotated `microtodosuite.io/feature-toggle-contract: docs/feature-toggles.md`.
- The service's own container reads it through `envFrom`, beside its existing
  `<service>-config` ConfigMap, which keeps holding the non-secret runtime
  settings that GitOps controls.
- The generated name carries a hash of the content. Changing a toggle therefore
  changes the pod template, so the service rolls out again (through its canary
  in prod) and reads the new value, with no image rebuild.

## The contract

Every key in a `<service>-feature-toggles` ConfigMap:

1. is named `FEATURE_<NAME>` in upper case, which the service reads as an
   environment variable;
2. defaults to `"false"` in Git, so incomplete behavior ships switched off;
3. has one row in the register below with its service, owner, and purpose.

Turning a toggle on for an environment is a reviewed pull request that patches
that environment's full overlay; turning it off again is a revert. No toggle
is changed in a cluster by hand.

`tests/platform/service-runtime-full.bats` enforces the contract on every full
overlay of the five services.

## Register

No service has incomplete behavior today, so no toggle is declared.

| Service | Key | Default | Owner | Purpose |
| --- | --- | --- | --- | --- |

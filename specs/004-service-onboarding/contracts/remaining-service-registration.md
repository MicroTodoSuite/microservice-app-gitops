# Remaining Service Registration Contract

This contract specializes, but does not replace, the canonical
`specs/001-local-gitops-pilot/contracts/service-onboarding-contract.md`.

## Discovery and activation

- Every direct `apps/<service>` child is discovered by the existing apps Matrix
  ApplicationSet.
- The existing local environment activation produces one Application named
  `<service>-local` in `microtodo-local`.
- No direct Application, second ApplicationSet, per-service activation list,
  NodePort, or direct cluster mutation is allowed.
- Redis is discovered by the existing `infrastructure/*` generator as
  `infra-redis` and targets namespace `redis`.
- Redis must pass its live gate at an earlier local Git revision before any new
  service directory is committed to the pilot source.

## Required service mappings

| Contract field | todos-api | users-api | frontend | log-message-processor |
| --- | --- | --- | --- | --- |
| Port | 8082 | 8083 | 8080 | 9090 |
| Intrinsic health | `/metrics` | `/prometheus` | `/` | `/metrics` |
| Secret | `auth-api-secrets/JWT_SECRET` | `auth-api-secrets/JWT_SECRET` | none | none |
| Required endpoint | Redis | none | auth-api and todos-api | Redis |
| Local replicas | 1 | 1 | 1 | 1 |
| Local exposure | internal | internal | operator port-forward | internal |
| Continuity disclosure | process-local todos | pod-local H2 seed data | none | Redis subscription only |

Every service must have:

- a base Deployment, ClusterIP Service, dedicated ServiceAccount, and ConfigMap;
- common `name`, `part-of=microtodosuite`, and `component=business-service`
  labels generated without selector drift;
- `automountServiceAccountToken: false`;
- startup, readiness, and liveness checks using the intrinsic health path;
- a neutral base image key and an overlay-owned registry plus digest;
- bounded local resources compatible with the environment quota;
- economical/full topology components and a managed topology seam identical in
  role to auth-api's existing structure;
- local, dev, staging, and prod overlays, with inactive managed values remaining
  provider-neutral placeholders.

## Redis contract

`infrastructure/redis` must render exactly one Deployment and Service named
`redis`, plus a dedicated ServiceAccount, namespace ownership, and network policy
intent. The rendered container image must be immutable. Passing live state is:

- `infra-redis` reports the exact expected revision, Synced, and Healthy;
- `Deployment/redis` has one desired, ready, and available replica;
- the Redis pod is Ready and not restarting in a failure loop; and
- a RESP `PING` through `Service/redis` returns `PONG`.

The workload intentionally uses one replica, disables RDB/AOF persistence, and
uses only ephemeral data storage. It must not be described as durable or HA.

## Shared JWT contract

auth-api remains the single local ESO target owner. users-api and todos-api read
the same Secret and key by reference. No other Password generator,
ExternalSecret target, literal, or copy operation is permitted.

Passing behavior requires:

1. auth-api creates an internal users-api token signed with the shared key;
2. users-api validates it and returns the matching H2-seeded profile;
3. auth-api returns a login token signed with the same key; and
4. todos-api validates that login token.

## Frontend exposure and routing contract

The local user starts a port-forward from loopback to `Service/frontend:8080`.
The frontend NGINX process owns same-origin routing:

- `/login` -> `http://auth-api:8000/login`
- `/todos` -> `http://todos-api:8082/todos`

The browser receives only the loopback frontend origin. Internal Service names
remain server-side. Managed ingress remains an environment-owned value already
covered by the canonical onboarding contract and is not activated here.

## Live evidence contract

A passing verifier must retain raw evidence and fail unless:

- `auth-api-local`, `todos-api-local`, `users-api-local`, `frontend-local`, and
  `log-message-processor-local` are Synced/Healthy at the exact pilot SHA;
- `infra-redis` is Synced/Healthy at that SHA;
- all five service Deployments and Redis are Available and their pods Ready;
- each running service image matches its published digest;
- Redis answers `PONG`;
- all four new intrinsic endpoints return success;
- valid login, direct profile lookup, authorized todo list/create, matching
  processor event, and frontend-routed login/list all succeed;
- invalid login remains rejected; and
- auth-api still returns its intrinsic health response at the end.

No status inferred from rendered configuration counts as live evidence.

## Provider-neutrality contract

New service, Redis, environment policy, publication, and verification artifacts
must contain no cloud account, region, registry, workload identity, endpoint, or
credential dependency. Future destination values may be supplied through the
existing environment registration and overlay contracts without changing this
service or platform design.

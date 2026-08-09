# Redis Platform Dependency

This folder is the provider-neutral, ArgoCD-owned Redis endpoint required by
todos-api and log-message-processor. The shared infrastructure directory
generator creates `infra-redis`; no separate registration mechanism exists.

## Runtime contract

- Redis binary version: 7.4.9
- Image: official `redis` repository, selected by immutable manifest digest
- Address: `redis.redis.svc.cluster.local:6379`
- Pub/Sub channel: `log_channel` (declared by each consumer)
- Replicas: one
- Health: Redis protocol `PING` / `PONG`

## Continuity limit

This pilot Redis is deliberately non-durable. RDB snapshots and AOF are disabled,
the data directory is an `emptyDir`, and there is no replication, backup, or
failover claim. Pod replacement can lose all Redis state. This preserves the
constitution's disclosed data-continuity risk; a durable design requires a
separate ratified feature.

## Upgrade procedure

1. Select a concrete Redis version from the official image repository.
2. Resolve and record its immutable multi-platform manifest digest.
3. Render this Kustomize root and run `tests/contract/platform-addons.sh`.
4. Publish the change through local Git, then require Synced/Healthy, pod
   readiness, and `PONG` before allowing consumers to reconcile.

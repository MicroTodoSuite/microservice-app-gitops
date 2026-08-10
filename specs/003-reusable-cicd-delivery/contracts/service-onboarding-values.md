# Contract: Per-Service Onboarding Values

Values (only) to instantiate each service under `apps/<service>/` following
`specs/001-local-gitops-pilot/contracts/service-onboarding-contract.md`. The
hierarchy, ApplicationSet, promotion, and verification mechanisms never change.
Facts verified from each repo's Dockerfile and application code.

## Value table

| Field (owner) | auth-api | todos-api | users-api | frontend | log-message-processor |
| --- | --- | --- | --- | --- | --- |
| Language | Go | Node | Java/Spring | Vue→nginx | Python |
| Container port (base) | 8000 | 8082 | 8083 | 8080 | value of `PORT` |
| Port env key | `AUTH_API_PORT` | `TODO_API_PORT` | `SERVER_PORT` | (static 8080) | `PORT` |
| Intrinsic health (base) | `/version` | `/metrics` | `/actuator/health` | `/` | `/metrics` |
| Config keys (names, base) | `AUTH_API_PORT`,`USERS_API_ADDRESS`,`ZIPKIN_URL?` | `TODO_API_PORT`,`REDIS_HOST`,`REDIS_PORT`,`REDIS_CHANNEL`,`ZIPKIN_URL?` | `SERVER_PORT`,`SPRING_APPLICATION_NAME`,`ZIPKIN_URL?` | `AUTH_API_ADDRESS`,`TODOS_API_ADDRESS`,`ZIPKIN_URL?` | `PORT`,`REDIS_HOST`,`REDIS_PORT`,`REDIS_CHANNEL`,`ZIPKIN_URL?` |
| Secret interface (base) | `auth-api-secrets/JWT_SECRET` | `todos-api-secrets/JWT_SECRET` | `users-api-secrets/JWT_SECRET` | none | none |
| Shared-JWT (D13) | yes | yes | yes | n/a | n/a |
| Runtime dependency | users-api (login only) | Redis | none | auth-api, todos-api | Redis |
| Neutral image key (base) | `auth-api` | `todos-api` | `users-api` | `frontend` | `log-message-processor` |
| Registry `newName` (overlay) | GHCR now / ECR later | same | same | same | same |
| Managed overlays | inactive scaffold | inactive scaffold | inactive scaffold | inactive scaffold | inactive scaffold |

## Notes

- **frontend** carries no secret and no `configmap` secret; its API addresses are
  environment-owned overlay values injected into the nginx template.
- **log-message-processor** is a worker but exposes a Prometheus HTTP server on
  `PORT`; `/metrics` is its intrinsic health path (satisfies the worker-health
  rule without fabricating an API).
- **users-api** health uses `/actuator/health` (actuator is exposed and
  unsecured in `application.properties`); `/prometheus` is an alternative.
- **Redis** is a shared dependency, not a business service; it stays out of
  `apps/<svc>` (environment/platform-owned). See research D14.
- **Shared JWT**: auth-api, todos-api, users-api overlays reference the same
  generated/managed JWT value so issued tokens verify across services (D13).
- Each base carries the three standard labels, the intrinsic probe, and a
  token-disabled ServiceAccount, exactly like auth-api.

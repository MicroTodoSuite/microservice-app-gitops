# Secret Handling and Rotation

## Principle

No secret value is ever committed (constitution principle 10, spec 001 FR-018).
The Git repository contains only the **reference contract**: the workload reads a
Secret named `auth-api-secrets`, key `JWT_SECRET`. How that Secret is filled is
environment-specific and always in-cluster.

## Local pilot

External Secrets Operator's `Password` generator creates a random value in the
cluster, and an `ExternalSecret` writes it into `auth-api-secrets`
(`apps/auth-api/overlays/local/external-secret.yaml`). Nothing secret touches Git.

## Managed environments (future)

The same Secret contract is filled by an ESO `SecretStore` backed by AWS Secrets
Manager (via IRSA, delivered by roadmap task 1). Only the `SecretStore` and
`ExternalSecret` source differ; the Deployment is unchanged.

## Compromised historical literal

Earlier history committed a demonstration literal
(`JWT_SECRET=local-dev-secret-not-for-prod`). Treat it as **compromised**:

- It must never be reused as a real signing key in any environment.
- Rotation happens outside Git — generate a new value in the target secret store;
  the pilot already generates a fresh value per cluster via the `Password`
  generator, so recreating the pilot cluster rotates the local secret.

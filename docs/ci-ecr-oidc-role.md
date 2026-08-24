# GitHub Actions to AWS OIDC role for ECR publication

The Terraform-owned AWS foundation provides a dedicated GitHub Actions OIDC
publisher for the five business-service repositories. It is separate from the
EKS OIDC provider used by in-cluster IRSA workloads.

## Current contract

- AWS account: `916491575487`
- Region: `us-east-1`
- Role: `arn:aws:iam::916491575487:role/microtodosuite-github-ecr-publisher`
- Provider: `https://token.actions.githubusercontent.com`
- Terraform owner:
  `microservice-app-ops/aws/modules/environment-foundation/github-oidc.tf`
- Allowed subjects: the `main` branch of `auth-api`, `todos-api`, `users-api`,
  `frontend`, and `log-message-processor` repositories only
- Allowed registry scope:
  `916491575487.dkr.ecr.us-east-1.amazonaws.com/microtodosuite/<service>`

The reusable organization workflow validates the exact repository URI and role
ARN before assuming the role. Pull-request runs test, build, scan, and generate
an SBOM without publishing. A reviewed `main` push may assume the role, push the
already-tested image, resolve its immutable digest, attach the SBOM attestation,
and sign the digest with the GitHub Actions OIDC identity.

No static AWS credential belongs in GitHub secrets or this repository. Changes
to the provider, trust policy, permissions, or ECR repositories are made only
through the owning Terraform state; service workflows consume the resulting ARN
and never create AWS resources.

## Read-only verification

```bash
aws iam get-role \
  --profile microtodosuite-terraform \
  --role-name microtodosuite-github-ecr-publisher \
  --query 'Role.[Arn,AssumeRolePolicyDocument]'

aws ecr describe-repositories \
  --profile microtodosuite-terraform \
  --region us-east-1 \
  --query 'repositories[?starts_with(repositoryName, `microtodosuite/`)].repositoryUri'
```

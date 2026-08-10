# Missing piece: GitHub Actions → AWS OIDC role for ECR push

The task-1 dev foundation (`ops @ esteban/eks-dev-foundation`) creates EKS, ECR,
VPC and **IRSA** (pods → AWS). It does **not** create the identity that lets the
**CI pipeline push images to ECR**. IRSA is for in-cluster pods via the EKS OIDC
provider; GitHub Actions needs a **separate GitHub OIDC provider + IAM role**.

Until this exists, the task-4 CI cloud leg (`cloud-enabled: true`) cannot
authenticate to AWS. Everything else (build, GHCR, scan, SBOM, sign, promotion
PR) already works without it.

## What must be created (in the `ops` repo, AWS account 995253610162)

1. A GitHub OIDC identity provider for `token.actions.githubusercontent.com`
   (one per account; skip if it already exists).
2. An IAM role that trusts that provider, restricted to the MicroTodoSuite org's
   repositories, allowed to push to the dev ECR repositories only.
3. Expose its ARN so GitHub can assume it: set repo/org **variable**
   `AWS_CI_ROLE_ARN` and `AWS_REGION=us-east-1`.

## Ready-to-use Terraform (drop into ops, e.g. `aws/modules/ci-ecr-oidc/`)

```hcl
variable "github_org"   { type = string, default = "MicroTodoSuite" }
variable "account_id"   { type = string, default = "995253610162" }
variable "aws_region"   { type = string, default = "us-east-1" }
variable "ecr_prefix"   { type = string, default = "microtodosuite/dev" }

# 1) GitHub OIDC provider (create once per account; import if it already exists).
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# 2) Role assumable by GitHub Actions from any repo in the org, on any branch.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/*:*"]  # tighten to :ref:refs/heads/main if desired
    }
  }
}

resource "aws_iam_role" "ci_ecr_push" {
  name               = "microtodosuite-ci-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# 3) Push/pull to the dev ECR repositories, plus the account-wide auth token.
data "aws_iam_policy_document" "ecr_push" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    effect  = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/${var.ecr_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "ci_ecr_push" {
  role   = aws_iam_role.ci_ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

output "ci_ecr_role_arn" { value = aws_iam_role.ci_ecr_push.arn }
```

## Wire it into task-4 CI

Once the role exists, set in GitHub (org or per-repo):

- variable `AWS_CI_ROLE_ARN` = the module's `ci_ecr_role_arn` output
- variable `AWS_REGION` = `us-east-1`

and flip the caller/reusable input `cloud-enabled: true` with
`registry: 995253610162.dkr.ecr.us-east-1.amazonaws.com/microtodosuite/dev`.
The reusable `ci.yml` already contains the `configure-aws-credentials` (OIDC) and
`amazon-ecr-login` steps behind that flag.

## Notes

- Scope can be tightened from `repo:ORG/*:*` to specific repos and
  `:ref:refs/heads/main` once the flow is proven.
- This role is **CI-only** (push). Pods still pull via the node role's ECR
  PullOnly permission already present in the foundation.
- Owner: coordinate with whoever owns task 1 — this can live in the same ops
  foundation or as this small standalone module.
```

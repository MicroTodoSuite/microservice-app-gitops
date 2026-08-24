# Quickstart: Implement and Verify the Full Platform

This guide is for the implementation phase. It deliberately contains no `terraform apply` command and no post-bootstrap direct Kubernetes mutation. Applies, bootstrap mutations, and the final traffic switch are separate human-gated tasks in `tasks.md`.

## 1. Establish the workspace and immutable baseline

Use sibling-repository paths explicitly:

```bash
export MTS_ROOT="/home/esteban/Documents/University/Tenth semester/plataformas-ii/MicroTodoSuite"
export OPS_ROOT="$MTS_ROOT/microservice-app-ops"
export GITOPS_ROOT="$MTS_ROOT/microservice-app-gitops"
export FEATURE_DIR="$GITOPS_ROOT/specs/009-full-platform-rollout"

for repo in \
  microservice-app-ops \
  microservice-app-gitops \
  .github \
  microservice-app-auth-api \
  microservice-app-frontend \
  microservice-app-log-message-processor \
  microservice-app-todos-api \
  microservice-app-users-api \
  microservice-app-docs
do
  git -C "$MTS_ROOT/$repo" status --short --branch
done
```

Stop on an unexpected dirty file, divergent branch, or unresolved merge. Existing local work belongs to its owner and must not be stashed, overwritten, committed, or pushed implicitly.

Capture the authenticated AWS identity and current quota/address baseline:

```bash
aws sts get-caller-identity
aws ec2 describe-account-attributes --attribute-names max-elastic-ips
aws ec2 describe-addresses --region us-east-1
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A
aws service-quotas get-service-quota --service-code ec2 --quota-code L-34B43A08
aws eks list-clusters --region us-east-1
```

The account ID must be `916491575487`. Stop if it differs, if the quotas are below the accepted plan values, or if an unplanned VPC/cluster consumes a selected CIDR.

Before Azure work, install Azure CLI from a checksum-verified official artifact, authenticate, and capture:

```bash
az account show --output json
az account list-locations --output json
az network vnet list --output json
az storage account list --output json
az aks get-versions --location "$AZURE_LOCATION" --output json
```

`AZURE_LOCATION` and the subscription ID must come from the authenticated approved account/CI configuration. Do not infer them from this guide. Stop if `az account show` does not match `AZURE_SUBSCRIPTION_ID_COLONIA`.

## 2. Validate the specification artifacts

```bash
cd "$GITOPS_ROOT"
.specify/scripts/bash/check-prerequisites.sh --json --require-plan --include-tasks
jq empty "$FEATURE_DIR/contracts/full-profile-evidence.schema.json"
rg -n "NEEDS CLARIFICATION|\[FEATURE\]|\[DATE\]|\[###" "$FEATURE_DIR" \
  --glob '!**/checklists/requirements.md'
```

The final `rg` command must produce no output.

## 3. Prove Terraform compatibility before new roots

Use Terraform `1.15.8`, the checked-in lock files, and the exact backend configuration already owned by dev.

```bash
terraform version
terraform -chdir="$OPS_ROOT/aws/modules/environment-foundation" fmt -check -recursive
terraform -chdir="$OPS_ROOT/aws/modules/environment-foundation" init -backend=false -input=false
terraform -chdir="$OPS_ROOT/aws/modules/environment-foundation" validate
terraform -chdir="$OPS_ROOT/aws/modules/environment-foundation" test

terraform -chdir="$OPS_ROOT/aws/environments/dev/foundation" init \
  -backend-config=dev.s3.tfbackend -reconfigure -input=false
terraform -chdir="$OPS_ROOT/aws/environments/dev/foundation" plan \
  -input=false -var-file=dev.tfvars -out=tfplan-dev
terraform -chdir="$OPS_ROOT/aws/environments/dev/foundation" show -no-color tfplan-dev
```

The dev plan must literally end with `0 to add, 0 to change, 0 to destroy`. A nonzero exit, backend error, refresh-disabled plan, or summary-only assertion is not acceptable. Remove the local saved plan after its external evidence checksum is recorded; never commit it.

## 4. Validate every new AWS plan independently

Backend files must reuse the exact dev bucket, region, and KMS ARN and use these distinct keys:

```text
shared/egress/terraform.tfstate
environments/full-dev/foundation/terraform.tfstate
environments/full-prod/foundation/terraform.tfstate
```

For each root, initialize non-interactively, save a refreshed plan, render both text and JSON, and run Infracost. Example for full dev:

```bash
terraform -chdir="$OPS_ROOT/aws/environments/full-dev/foundation" init \
  -backend-config=full-dev.s3.tfbackend -reconfigure -input=false
terraform -chdir="$OPS_ROOT/aws/environments/full-dev/foundation" validate
terraform -chdir="$OPS_ROOT/aws/environments/full-dev/foundation" test
terraform -chdir="$OPS_ROOT/aws/environments/full-dev/foundation" plan \
  -input=false -var-file=full-dev.tfvars -out=tfplan-full-dev
terraform -chdir="$OPS_ROOT/aws/environments/full-dev/foundation" show \
  -no-color tfplan-full-dev
terraform -chdir="$OPS_ROOT/aws/environments/full-dev/foundation" show \
  -json tfplan-full-dev > /tmp/microtodosuite-full-dev-plan.json
infracost breakdown --path /tmp/microtodosuite-full-dev-plan.json \
  --format json --out-file /tmp/microtodosuite-full-dev-infracost.json
```

The binary plan and full plan JSON remain external because provider values may be sensitive. Commit only a whitelisted/redacted resource-address/action/count summary plus the external artifacts' SHA-256 values.

Repeat only with the root's exact backend/variable names. Plans must show:

- account `916491575487`, region `us-east-1`, and the approved CIDR;
- no `0.0.0.0/0` EKS public-access CIDR;
- zero shared ECR/OIDC/shared-role/hosted-zone creations;
- no unexpected destroy or replacement;
- at most one EIP/NAT in the shared egress root and none in full-dev/full-prod;
- one stable `m7i-flex.large` bootstrap node desired for each new cluster;
- bounded per-cluster Karpenter IAM/discovery outputs;
- an accepted cost/quota/rollback bundle.

No apply follows until the exact saved plan is approved and the external state backup task passes.

## 5. Render GitOps for both profiles

Install Kustomize `5.8.1` and kubeconform `0.7.0` from their release artifacts and verify published checksums. Then run the repository validator added by the implementation tasks. Its underlying render loop is:

```bash
cd "$GITOPS_ROOT"
while IFS= read -r kdir; do
  kustomize build "$kdir" \
    | kubeconform -strict -ignore-missing-schemas -summary
done < <(
  find apps clusters environments bootstrap infrastructure \
    -name kustomization.yaml -not -path '*/components/*' -printf '%h\n' \
    | sort -u
)
```

Also run the implemented profile/ownership checks. They must prove:

- the economical golden renders are unchanged;
- every full root activates exactly one environment and selects `profile: full`;
- every generated destination is in-cluster;
- full roots contain every required capability and economical roots contain no full-only capability;
- every GitOps-installed third-party image is present in the committed lock by
  upstream digest, mirrored into the dev-owned `microtodosuite/platform`
  repository, scanned, and signed by the exact platform-mirror workflow before
  EKS activation;
- manifests contain only the approved mirrored digest references and secret
  references;
- no validation or evidence script contains post-bootstrap `kubectl apply/create/patch/delete/scale`.

## 6. Verify service and shared workflow gates

Run the exact commands declared by each repository's workflow, not a generic `npm test`. The current primary commands are:

```bash
git -C "$MTS_ROOT/microservice-app-auth-api" diff --check
git -C "$MTS_ROOT/microservice-app-frontend" diff --check
git -C "$MTS_ROOT/microservice-app-log-message-processor" diff --check
git -C "$MTS_ROOT/microservice-app-todos-api" diff --check
git -C "$MTS_ROOT/microservice-app-users-api" diff --check
```

The implementation tasks update each `.github/workflows/ci.yml` and service-owned test harness so all required categories are runnable and blocking. Verify the merged workflow runs rather than claiming success from package placeholders. Confirm the five callers receive the exact selected-repository organization secrets `RELEASE_APP_ID`, `RELEASE_APP_KEY`, `GITOPS_PROMOTE_APP_ID`, and `GITOPS_PROMOTE_APP_KEY`; repository-write jobs must mint installation tokens from the two restricted GitHub Apps, and cloud-write jobs use OIDC. Do not configure a personal `GH_TOKEN`.

## 7. Bootstrap only after protected-main merge

For each new cluster, the implementation helper must first verify that the reviewed root commit is contained in `origin/main`, validate the expected cloud identity and cluster UID, and then display the two literal mutations for operator review. The only permitted mutations are:

```text
kustomize build bootstrap/argocd | kubectl --context <context> apply --server-side -f -
kubectl --context <context> apply -f clusters/<cluster-root>/root-app.yaml
```

Do not run either command from this planning guide. The implementation task records them, their input checksums, and their results. All subsequent platform/workload activation is by reviewed commit and ArgoCD reconciliation.

## 8. Collect read-only live evidence after GitOps reconciliation

The implemented evidence collector may use read-only commands such as:

```bash
kubectl --context <context> get applications -n argocd -o json
kubectl --context <context> get nodes,pods -A -o wide
kubectl --context <context> get peerauthentication,authorizationpolicy -A -o yaml
kubectl --context <context> get externalsecret,secretstore,clustersecretstore -A -o yaml
kubectl --context <context> get rollouts,analysisruns -A -o yaml
kubectl --context <context> get nodepools,ec2nodeclasses -A -o yaml
kubectl --context <context> logs -n <namespace> <pod>
curl --fail --show-error --silent https://<destination-fqdn>/<health-path>
```

Failure probes and load generators are GitOps-owned disabled manifests. Enable them in a reviewed branch/PR, observe them read-only, and remove them by Git revert. Never substitute `kubectl create`, `run`, `patch`, `scale`, or `delete`.

## 9. Validate the evidence bundle

After each stage, validate `evidence.json` against:

```text
specs/009-full-platform-rollout/contracts/full-profile-evidence.schema.json
```

Recompute every listed SHA-256, confirm all required FR/SC entries pass, and confirm the post-stage economical baseline equals or improves on the pre-stage baseline. A failed or missing artifact sets the stage to `blocked`.

## 10. Stop before production traffic

AKS readiness, four-name Key Vault inventory plus an in-process production-JWT equality result, equal ECR/ACR service digests and complete signed platform graphs, and a successful game day do not enable real traffic. Bootstrap AKS first against its activation-empty root; copy and verify the complete platform graph in ACR before a reviewed GitOps PR activates capabilities. Evidence may contain secret names/versions and the equality boolean, never a secret or value-derived digest. Before producing the final routing plan, verify that `microtodosuite.online` delegates to the exact Terraform-owned Route 53 name servers, the AKS Istio Service is bound to the Terraform-owned Standard static public IP, and both production destinations already present trusted certificates for `app.microtodosuite.online`, issued through the scoped DNS-01 identities while no shared application record exists. `enable_active_active` stays false until a separate human approves the exact final Route 53 saved plan. The economical platform remains live and is not retired by this feature.

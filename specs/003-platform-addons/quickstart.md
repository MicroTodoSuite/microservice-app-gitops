# Quickstart: Validate the Platform Add-ons Foundation

Run from the repository root. These commands render or observe; they do not
apply managed state directly.

## 1. Static contract

```bash
./tests/contract/platform-addons.sh
```

Expected: all four Kustomize roots render, bundle checksums match, rendered
images are immutable, the infrastructure generator produces the four expected
applications, exact AppProject kinds cover the renders, and provider scans are
clean.

Optional schema validation when `kubeconform` is installed:

```bash
for addon in keda cert-manager external-secrets kyverno; do
  kustomize build "infrastructure/$addon" |
    kubeconform -strict -ignore-missing-schemas -summary
done
```

## 2. Publish through the local GitOps source

Use a disposable clone of `.local/git/microservice-app-gitops.git`. Copy only
the reviewed checkout tree into that clone, preserve the live registration URL,
activate the local environment, retain the current auth-api digest, commit, and
push to its local `main`. Do not push this pilot-only activation commit to a
hosted remote and do not run a cluster mutation command.

Stage the desired state in this order:

1. KEDA, cert-manager, and ESO hardening/capability resources.
2. Kyverno installation and Audit-mode capability policies.
3. Promotion of the verified Kyverno policies to Enforce.
4. The auth-api pod-template compatibility annotation.

Each stage must become healthy before the next local commit.

## 3. Composite live verification

The current machine's verified pilot uses the older cluster name, so pass its
context explicitly. A new bootstrap uses the script default.

```bash
PILOT_KUBE_CONTEXT=kind-microtodo-gitops-pilot \
  ./scripts/pilot/verify-platform.sh
```

Expected final line:

```text
PLATFORM VERIFIED: four add-ons and auth-api are Synced, Healthy, and live.
```

Raw evidence is retained under `.local/evidence/platform-addons/<timestamp>/`.

## 4. Read-only spot checks

```bash
kubectl --context kind-microtodo-gitops-pilot get applications -n argocd
kubectl --context kind-microtodo-gitops-pilot get deployments -n keda
kubectl --context kind-microtodo-gitops-pilot get deployments -n cert-manager
kubectl --context kind-microtodo-gitops-pilot get deployments -n external-secrets
kubectl --context kind-microtodo-gitops-pilot get deployments -n kyverno
kubectl --context kind-microtodo-gitops-pilot get scaledobject -n keda
kubectl --context kind-microtodo-gitops-pilot get certificate -n cert-manager
kubectl --context kind-microtodo-gitops-pilot get externalsecret -n microtodo-local
kubectl --context kind-microtodo-gitops-pilot get clusterpolicy
kubectl --context kind-microtodo-gitops-pilot get policyreport -n microtodo-local
```

Any non-Synced/non-Healthy application, unavailable Deployment, failed
capability condition, or policy fail/error is a failed run. Correct desired
state by commit or revert; never bypass ArgoCD with apply, patch, scale, or
rollout commands.

# Cluster Registration Contract

## Registration Shape

Each managed cluster owns one Kustomize root containing:

- `registration.yaml` with the canonical repository URL and protected `main` revision;
- `activation-environments.yaml` with only the namespaces owned by that cluster;
- `activation-apps.yaml` with explicit `env`, `profile`, and in-cluster `server` values;
- `activation-infrastructure.yaml` with an explicit ordered capability list;
- `root-app.yaml` targeting the root path in the same repository;
- rolling-sync policy where multiple environments are intentionally activated.

After workload activation begins, full roots must satisfy this logical form:

```yaml
cluster: <physical-cluster-name>
destinationServer: https://kubernetes.default.svc
activations:
  - env: <dev|staging|prod>
    profile: full
    server: https://kubernetes.default.svc
```

`clusters/eks-full-staging` is the logical root for physical cluster `microtodosuite-demo-full`; Terraform resources and state retain the physical name.

The protected-main bootstrap revision is the only activation-empty state: its registration declares the exact planned logical environment and capability inventory but both activation lists render no workload or platform Application. A later reviewed GitOps commit may activate that declared inventory only after its prerequisite gates pass.

The activated AKS DR root uses production configuration with `profile: full` and `environment: prod`, but the destination identity and promotion strategy remain `aks-dr` and `dr-rolling`.

## Invariants

1. Every generated Application destination is `https://kubernetes.default.svc`.
2. A full root contains zero logical environment activations only at its recorded bootstrap revision and exactly one thereafter; no revision may contain more than one.
3. The service ApplicationSet path includes both profile and environment; no global topology selector exists.
4. Infrastructure is allowlisted. Directory discovery cannot activate controllers.
5. Bootstrap revisions activate no capability but declare the complete planned inventory; accepted full roots activate all applicable FR-023 capabilities, while economical roots do not include Istio, Kiali, ECK/ELK/Filebeat, Chaos Mesh, OpenCost, or Karpenter.
6. Registration files contain no endpoint certificate, token, kubeconfig, cloud credential, webhook, or secret value.
7. ArgoCD notifications reference an External Secret, never a literal webhook.
8. Root Applications use automated prune/self-heal and a bounded retry policy.
9. Bootstrap occurs only after the root revision is merged to protected `main`.
10. The AKS root binds the Istio LoadBalancer Service to the Terraform-output public-IP name and resource group; it cannot request an unowned dynamic address.
11. Only the AKS cert-manager controller may mount the audience-`sts.amazonaws.com` projected token used for the common-hostname DNS-01 solver, and no AWS access key may appear in desired state.

## Bootstrap Contract

For a cluster without ArgoCD, exactly two direct mutations are allowed:

1. server-side apply the checksum-pinned render from `bootstrap/argocd`;
2. apply that cluster's tracked `root-app.yaml`.

All waits and observations are read-only. The transcript records:

- AWS account or Azure subscription;
- region, cluster name, cluster UID, and kube context;
- reviewed PR, merge SHA, and `origin/main` containment check;
- SHA-256 of every vendored bootstrap input and final render;
- literal two mutation commands and exit codes;
- ArgoCD readiness and root sync/health/revision.

Any third direct mutation invalidates bootstrap acceptance.

## Static Acceptance

- Every kustomization renders with pinned Kustomize.
- kubeconform validates built-in schemas and the committed CRD schema set.
- A policy check asserts one activation per full root and rejects remote destinations.
- An inventory check compares the explicit capability list with the required profile list.
- An economical golden render is byte-compared before and after the profile-path migration, excluding documented ordering-only normalization.

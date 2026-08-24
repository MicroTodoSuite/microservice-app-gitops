# Release Promotion Contract

## Inputs

```yaml
service: auth-api | frontend | log-message-processor | todos-api | users-api
sourceSha: <40-hex reviewed main SHA>
imageDigest: sha256:<64-hex>
imageRef: 916491575487.dkr.ecr.us-east-1.amazonaws.com/microtodosuite/<service>@<digest>
environment: dev | staging | prod
profile: economical | full
destination: eks-dev | eks-full-dev | eks-full-staging | eks-full-prod | aks-dr
strategy: rolling | istio-canary | dr-rolling
```

The tuple `(environment, profile, destination)` must be one of the registered destinations. AKS DR accepts only `environment=prod`, `profile=full`, `destination=aks-dr`, and `strategy=dr-rolling`; there is no separate `dr` workload overlay.

## Pre-Promotion Gates

The exact artifact must have passing evidence for:

- repository source tests and dependency audit;
- every checked-in unit, integration, OpenAPI/AsyncAPI, Pact, E2E, performance, and DAST harness required by the service contract;
- blocking SonarQube quality gate;
- Trivy scan with the approved threshold;
- Syft SBOM attached to the digest;
- keyless Cosign signature and attestation whose GitHub OIDC identity matches the approved workflow;
- Kyverno verification policy in the target profile;
- source SHA and digest provenance.

An absent required harness/configuration is a failed gate, not a skipped success.

## Promotion Rules

1. CI builds exactly once and publishes the neutral ECR digest from reviewed `main`.
2. Repository writes use a short-lived GitHub App installation token. Cloud writes use OIDC. A PAT/static cloud credential is forbidden.
3. The promotion helper updates exactly one service/profile/environment overlay per requested destination and opens a reviewed GitOps PR.
4. Economical and full promotions may use the same digest concurrently; neither may edit the other's topology path.
5. Dev and staging use rolling updates.
6. Economical production retains its golden native replica-based canary. AWS full production alone uses the full-only Argo Rollouts component plus Istio at 10%, 25%, 50%, and 100%. Error-rate and p99-latency analyses run at each pause and fail closed when data is absent.
7. A failed production analysis stops exposure and restores stable service within five minutes.
8. Only a production-validated digest may advance to DR.
9. The DR job copies the complete OCI graph from ECR to ACR without a build, verifies signature/attestation in ACR, and asserts equal manifest digest before opening the AKS GitOps PR.
10. An AKS workload PR cannot open until every locked third-party platform-image graph is already mirrored from ECR to ACR, verified complete, and referenced by immutable ACR digest in the accepted AKS platform revision.
11. AKS DR uses rolling update; it does not repeat the production canary.

## Traceability Output

Every promotion records specification/requirement IDs, source repository/SHA, workflow run, test artifacts, ECR and ACR references, signature identity, GitOps PR/merge SHA, ArgoCD revision, live pod image IDs, strategy/analysis results, and rollback revision.

## Rollback

- Workload desired state is reversed by reviewed Git revert.
- A production analysis failure may automatically select the stable ReplicaSet, but the desired-state correction remains a Git revert/roll-forward PR.
- Rollback never rebuilds an image, edits a running workload directly, or rewrites another profile's overlay.
- The rollback is accepted only after live digest, endpoint health, ArgoCD health, and economical baseline checks pass.

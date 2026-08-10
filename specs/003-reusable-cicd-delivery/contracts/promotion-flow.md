# Contract: Build-Once → Digest → GitOps Promotion → Rollback

## End-to-end flow

```text
merge to main (service repo)
  │
  ├─ ci.yml (reusable)
  │    build ONCE → push → digest
  │    quality (Sonar) · scan (Trivy) · SBOM (Syft) · sign (Cosign keyless)
  │    output: image-digest
  │
  ├─ release.yml (reusable)  → version + changelog
  │
  └─ promote.yml (reusable, env=dev)
       bump-image.sh <svc> dev <digest>  → PR to gitops   [auto]
                                                │ merge (review)
                                                ▼
                                   ArgoCD reconciles dev   (self-heal/prune)
  ── promote staging ──  PR copying the IDENTICAL digest      [manual open]
  ── promote prod    ──  PR copying the IDENTICAL digest      [manual open + APPROVAL]
  ── rollback        ──  git revert of the gitops commit      [no cluster mutation]
```

## Rules (testable)

1. **Build once**: exactly one image per release; the digest emitted by CI is the only reference committed to any environment. No environment triggers a rebuild.
2. **Same digest across envs**: the string committed to `dev`, `staging`, `prod` overlays is byte-identical for one release. If registries differ (GHCR→ECR later), the destination manifest digest MUST be verified identical before promotion.
3. **Digest-only**: promotion uses `scripts/bump-image.sh`, which rejects tags, `latest`, image IDs, and the all-zero placeholder.
4. **PR-only, scoped**: each promotion is a PR touching only `apps/<service>/overlays/<env>/kustomization.yaml`. Concurrent promotions for different services never collide.
5. **Prod approval**: the prod PR cannot merge without a recorded human approval (branch protection). Absence of that protection is a defect.
6. **No CI-to-cluster**: no step runs `kubectl apply`, `kustomize build | apply`, `az containerapp`, `argocd app sync`, or any cluster/platform mutation.
7. **Rollback = revert**: undo is a `git revert` in gitops; ArgoCD reconciles the prior desired state. No `rollout undo`/manual sync is a supported path.
8. **Unverified digest rejected**: promoting a digest not produced+signed by CI fails.

## Validation hooks (gitops repo)

`validate-gitops.yml` on every gitops PR: `kustomize build` all overlays, `kubeconform -strict`, reject committed secret literals, reject tag/placeholder in an *active* overlay. Runs without cluster credentials.

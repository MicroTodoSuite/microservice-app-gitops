# microservice-app-gitops

Fuente de verdad de los despliegues de MicroTodoSuite. **Nada se aplica al
clúster a mano: todo cambio es un commit aquí, y ArgoCD lo reconcilia.**

```
commit en main ──► ArgoCD detecta el diff ──► clúster = lo que dice Git
rollback = git revert
```

## Estructura

```
bootstrap/argocd/        Instalación de ArgoCD (pinneada). Se aplica 1 vez;
                         después ArgoCD se auto-gestiona desde aquí.
clusters/local-kind/     Qué corre en el clúster: root-app (App-of-Apps),
                         AppProject, y los ApplicationSets de infra y apps.
                         Al pasar a AWS se replica como clusters/eks-*/.
infrastructure/          Add-ons de plataforma (KEDA, cert-manager, ...).
                         El contenido lo llena la tarea 2 — ver su README.
apps/<servicio>/         base/ (manifiestos comunes) + overlays/{dev,staging,prod}
                         (namespace, réplicas, tag de imagen por ambiente).
scripts/bump-image.sh    Bump manual del tag (en el punto 4 lo reemplaza el
                         PR automático desde CI).
```

Versión económica (actual): los ambientes son namespaces (`microtodo-dev`,
`microtodo-staging`, `microtodo-prod`) de un solo clúster. Los `base/` no
cambian al escalar a la versión completa (multiclúster).

## Cómo levantarlo en local (kind)

```bash
# 1. Clúster local
kind create cluster --name microtodo

# 2. Bootstrap de ArgoCD (única vez)
kustomize build bootstrap/argocd | kubectl apply --server-side -f -
kubectl -n argocd wait deploy --all --for=condition=Available --timeout=300s

# 3. Imagen del piloto (auth-api) cargada en kind
docker build -t auth-api:0.1.0-local ../microservice-app-auth-api
kind load docker-image auth-api:0.1.0-local --name microtodo

# 4. App-of-Apps raíz: el ÚNICO manifiesto que se aplica a mano
kubectl apply -f clusters/local-kind/root-app.yaml

# 5. UI de ArgoCD
kubectl -n argocd port-forward svc/argocd-server 8080:443 &
# usuario: admin — contraseña:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

## Flujo de despliegue y promoción

1. **Dev**: `scripts/bump-image.sh auth-api dev <tag>` + `git push` → ArgoCD
   sincroniza `microtodo-dev` solo.
2. **Staging/Prod**: PR que copia el tag ya probado al overlay siguiente
   (prod requiere aprobación manual del PR).
3. **Rollback**: `git revert <commit>` + push. Nada de kubectl.

## Validación estática (sin clúster)

```bash
for env in dev staging prod; do
  kustomize build apps/auth-api/overlays/$env | kubeconform -strict -summary
done
```

## Estado / pendientes de otras tareas del roadmap

- `infrastructure/*` son placeholders → los llena la **tarea 2**.
- `images:` usa tags locales → cambiarán a la URL del ECR cuando la **tarea 1**
  entregue el registro. ARNs de IRSA y endpoint EKS: ver `infrastructure/README.md`.
- El bump manual será reemplazado por el PR automático de CI (**punto 4**).

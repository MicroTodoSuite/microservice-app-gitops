# infrastructure/ — Add-ons de plataforma

**Contrato entre la tarea 3 (cableado GitOps) y la tarea 2 (add-ons).**

Cada carpeta es un add-on. El ApplicationSet `infrastructure`
(`clusters/local-kind/infrastructure.yaml`) genera automáticamente una
Application de ArgoCD por carpeta: **llenar una carpeta con manifiestos es
suficiente para que se despliegue**. No hay que tocar nada más.

## Qué va en cada carpeta (responsable: tarea 2)

- Manifiestos YAML planos, un `kustomization.yaml`, o un chart de Helm
  (`Chart.yaml` + `values.yaml`). ArgoCD detecta la herramienta solo.
- Versiones **pinneadas** (nunca `latest` ni `stable`).
- Si un add-on depende de otro (ej. algo que usa CRDs de cert-manager),
  usar `argocd.argoproj.io/sync-wave` en sus recursos para ordenar.

## Add-ons previstos (plan §4, versión económica)

| Carpeta | Add-on | Prerrequisito en `ops` (tarea 1) |
| --- | --- | --- |
| `cert-manager/` | TLS automático | rol IRSA para Route53 (DNS-01) |
| `external-secrets/` | Secretos desde AWS Secrets Manager | rol IRSA de lectura de secretos |
| `keda/` | Autoscaling por eventos | — |
| `kyverno/` | Policy-as-code | — |
| `argo-rollouts/` | Canary (económica: por réplicas, sin Istio) | — |

En la versión completa se añaden `istio/`, `chaos-mesh/`, `falco/`, `opencost/`
creando la carpeta correspondiente; el ApplicationSet las recoge automáticamente.

## Valores que este repo necesita de la tarea 1 (placeholders hoy)

- ARNs de los roles IRSA (cert-manager, external-secrets)
- URL del registro ECR (para los `images:` de los overlays de `apps/`)
- Endpoint del clúster EKS (para registrar el clúster en ArgoCD)

#!/usr/bin/env bash
# Bump manual del tag de imagen de un servicio en un ambiente.
# Placeholder del punto 3: en el punto 4 del roadmap, esto lo hará un PR
# automático abierto por el reusable workflow de CI tras publicar la imagen.
#
# Uso: scripts/bump-image.sh <servicio> <ambiente> <tag>
# Ej.:  scripts/bump-image.sh auth-api dev 1.2.3
set -euo pipefail

SERVICE="${1:?uso: bump-image.sh <servicio> <ambiente> <tag>}"
ENVIRONMENT="${2:?uso: bump-image.sh <servicio> <ambiente> <tag>}"
TAG="${3:?uso: bump-image.sh <servicio> <ambiente> <tag>}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$REPO_ROOT/apps/$SERVICE/overlays/$ENVIRONMENT"

[ -d "$OVERLAY" ] || { echo "❌ No existe el overlay $OVERLAY" >&2; exit 1; }

cd "$OVERLAY"
kustomize edit set image "$SERVICE=$SERVICE:$TAG"

cd "$REPO_ROOT"
git add "apps/$SERVICE/overlays/$ENVIRONMENT/kustomization.yaml"
git commit -m "chore($SERVICE): bump $ENVIRONMENT a $TAG"

echo "✅ $SERVICE@$ENVIRONMENT -> $TAG (commit creado; haz 'git push' para que ArgoCD lo despliegue)"

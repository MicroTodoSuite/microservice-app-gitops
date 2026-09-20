#!/usr/bin/env bash
# D13 (specs/003-reusable-cicd-delivery/research.md): auth-api, todos-api, and
# users-api must all verify the same JWT_SECRET value locally. One shared
# ESO-generated source -- not three independent random secrets, which would
# make a token auth-api issues fail verification in the other two.
#
# auth-api's local overlay owns the one Password generator and ExternalSecret
# (auth-api-secrets/JWT_SECRET); todos-api and users-api read that exact
# Secret by name from their base Deployment (a same-namespace Kubernetes
# Secret reference needs no ExternalSecret of its own). This guards both
# halves: the shared source exists, and it is never silently duplicated.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() {
  local path="$1" pattern="$2" description="$3"
  rg -q -- "$pattern" "$ROOT/$path" || fail "$description ($path)"
}
reject_text() {
  local path="$1" pattern="$2" description="$3"
  [[ ! -f "$ROOT/$path" ]] || rg -q -- "$pattern" "$ROOT/$path" &&
    fail "$description ($path)"
  return 0
}

require_text apps/auth-api/overlays/local/kustomization.yaml \
  'external-secret\.yaml' \
  "auth-api local overlay does not activate the shared JWT ExternalSecret"
require_text apps/auth-api/overlays/local/external-secret.yaml \
  'kind: Password' \
  "auth-api local overlay does not generate the shared JWT source"
require_text apps/auth-api/overlays/local/external-secret.yaml \
  'name: auth-api-secrets' \
  "auth-api local overlay does not target the shared Secret name"

for service in todos-api users-api; do
  require_text "apps/$service/base/deployment.yaml" 'name: auth-api-secrets' \
    "$service does not read the shared auth-api JWT Secret"
  require_text "apps/$service/base/deployment.yaml" 'key: JWT_SECRET' \
    "$service JWT Secret key is wrong"

  [[ ! -f "$ROOT/apps/$service/overlays/local/external-secret.yaml" ]] ||
    fail "$service must not provision its own local JWT ExternalSecret (D13: shared, not duplicated)"
  reject_text "apps/$service/overlays/local/kustomization.yaml" \
    'external-secret|generators\.external-secrets\.io' \
    "$service local overlay must not duplicate the shared JWT generator"
done

echo "PASS: auth-api, todos-api, and users-api share one local JWT source (D13)."

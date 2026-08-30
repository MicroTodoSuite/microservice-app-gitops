#!/usr/bin/env bash
# Digest-only image update for one validated deployment destination.
#
# Usage: scripts/bump-image.sh <service> <environment> <profile> <destination> <digest>
# Example: scripts/bump-image.sh auth-api dev economical eks-dev sha256:6a5e9f...
#
# Contract:
# - Accepts only sha256:[a-f0-9]{64}; rejects tags, `latest`, the all-zero
#   placeholder, and local image IDs, because only a registry-reported manifest
#   digest is immutable deployment evidence (FR-010).
# - Preserves the overlay's newName (registry location is environment-owned).
# - Rewrites exactly the digest line, leaving formatting and comments intact.
# - Renders and asserts the final reference is newName@digest.
# - Creates a commit; NEVER pushes and NEVER mutates a cluster.
set -euo pipefail

err() { echo "ERROR: $*" >&2; exit 1; }

USAGE="usage: bump-image.sh <service> <environment> <profile> <destination> <digest>"
SERVICE="${1:?$USAGE}"
ENVIRONMENT="${2:?$USAGE}"
PROFILE="${3:?$USAGE}"
DESTINATION="${4:?$USAGE}"
DIGEST="${5:?$USAGE}"
KUSTOMIZE_BIN="${KUSTOMIZE_BIN:-kustomize}"

case "$SERVICE" in
  auth-api|frontend|log-message-processor|todos-api|users-api) ;;
  *) err "unsupported service '$SERVICE'." ;;
esac

case "$ENVIRONMENT:$PROFILE:$DESTINATION" in
  local:economical:local-kind)
    OVERLAY_REL="apps/$SERVICE/overlays/local"
    ;;
  dev:economical:eks-dev|staging:economical:eks-dev|prod:economical:eks-dev)
    OVERLAY_REL="apps/$SERVICE/profiles/economical/overlays/$ENVIRONMENT"
    ;;
  dev:full:eks-full-dev|staging:full:eks-full-staging|prod:full:eks-full-prod|prod:full:aks-dr)
    OVERLAY_REL="apps/$SERVICE/profiles/full/overlays/$ENVIRONMENT"
    ;;
  *)
    err "unregistered environment/profile/destination tuple '$ENVIRONMENT/$PROFILE/$DESTINATION'."
    ;;
esac

# --- digest validation (reject anything that is not an immutable digest) ---
[[ "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] \
  || err "'$DIGEST' is not sha256:<64 hex chars>. Tags and image IDs are rejected."
[[ "$DIGEST" == "sha256:$(printf '0%.0s' {1..64})" ]] \
  && err "the all-zero placeholder digest cannot be activated."

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$REPO_ROOT/$OVERLAY_REL"
[[ -d "$OVERLAY" ]] || err "overlay not found: $OVERLAY"
command -v "$KUSTOMIZE_BIN" >/dev/null 2>&1 \
  || err "kustomize is required; set KUSTOMIZE_BIN to the pinned binary."

# --- preserve newName, update only the digest ---
KUSTOMIZATION="$OVERLAY/kustomization.yaml"
NEW_NAME="$(awk '/newName:/ {print $2; exit}' "$KUSTOMIZATION")"
[[ -n "$NEW_NAME" ]] || err "overlay has no images[].newName; refusing to guess a registry."

# Replace the digest in place rather than through `kustomize edit set image`.
#
# `kustomize edit` parses and re-emits the whole kustomization, so it reorders
# every block into flow style, drops the comments that record why an overlay is
# configured the way it is, and duplicates comment blocks it has already moved.
# A promotion is a digest swap; it has no business rewriting the file around it.
DIGEST_LINES="$(grep -cE '^[[:space:]]*(- )?digest: sha256:[0-9a-f]{64}[[:space:]]*$' "$KUSTOMIZATION" || true)"
[[ "$DIGEST_LINES" -eq 1 ]] \
  || err "expected exactly one images[].digest line in $OVERLAY_REL/kustomization.yaml, found $DIGEST_LINES; refusing to guess which image to promote."

CURRENT_DIGEST="$(grep -oE 'sha256:[0-9a-f]{64}' "$KUSTOMIZATION" | head -1)"
if [[ "$CURRENT_DIGEST" == "$DIGEST" ]]; then
  echo "OK: $OVERLAY_REL is already at $DIGEST; nothing to promote."
  exit 0
fi

sed -i "s|${CURRENT_DIGEST}|${DIGEST}|" "$KUSTOMIZATION"

# --- render and assert the final reference ---
RENDERED="$("$KUSTOMIZE_BIN" build "$OVERLAY" | grep -E '^\s+image: ' | head -1 | awk '{print $2}')"
[[ "$RENDERED" == "$NEW_NAME@$DIGEST" ]] \
  || err "rendered image '$RENDERED' does not equal '$NEW_NAME@$DIGEST'."

cd "$REPO_ROOT"
git add "$OVERLAY_REL/kustomization.yaml"
git commit -m "chore($SERVICE): promote $PROFILE/$ENVIRONMENT to $DESTINATION at $DIGEST"

echo "OK: $SERVICE@$PROFILE/$ENVIRONMENT@$DESTINATION -> $NEW_NAME@$DIGEST (commit created; push is a separate, deliberate step)"

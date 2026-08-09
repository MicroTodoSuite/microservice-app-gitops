#!/usr/bin/env bash
# Digest-only image update for one service in one environment (spec 001, T024).
#
# Usage: scripts/bump-image.sh <service> <environment> <digest>
# Example: scripts/bump-image.sh auth-api local sha256:6a5e9f...
#
# Contract:
# - Accepts only sha256:[a-f0-9]{64}; rejects tags, `latest`, the all-zero
#   placeholder, and local image IDs, because only a registry-reported manifest
#   digest is immutable deployment evidence (FR-010).
# - Preserves the overlay's newName (registry location is environment-owned).
# - Renders and asserts the final reference is newName@digest.
# - Creates a commit; NEVER pushes and NEVER mutates a cluster.
set -euo pipefail

err() { echo "ERROR: $*" >&2; exit 1; }

SERVICE="${1:?usage: bump-image.sh <service> <environment> <digest>}"
ENVIRONMENT="${2:?usage: bump-image.sh <service> <environment> <digest>}"
DIGEST="${3:?usage: bump-image.sh <service> <environment> <digest>}"

# --- digest validation (reject anything that is not an immutable digest) ---
[[ "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] \
  || err "'$DIGEST' is not sha256:<64 hex chars>. Tags and image IDs are rejected."
[[ "$DIGEST" == "sha256:$(printf '0%.0s' {1..64})" ]] \
  && err "the all-zero placeholder digest cannot be activated."

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$REPO_ROOT/apps/$SERVICE/overlays/$ENVIRONMENT"
[[ -d "$OVERLAY" ]] || err "overlay not found: $OVERLAY"

# --- preserve newName, update only the digest ---
NEW_NAME="$(awk '/newName:/ {print $2; exit}' "$OVERLAY/kustomization.yaml")"
[[ -n "$NEW_NAME" ]] || err "overlay has no images[].newName; refusing to guess a registry."

(cd "$OVERLAY" && kustomize edit set image "$SERVICE=$NEW_NAME@$DIGEST")

# --- render and assert the final reference ---
RENDERED="$(kustomize build "$OVERLAY" | grep -E '^\s+image: ' | head -1 | awk '{print $2}')"
[[ "$RENDERED" == "$NEW_NAME@$DIGEST" ]] \
  || err "rendered image '$RENDERED' does not equal '$NEW_NAME@$DIGEST'."

cd "$REPO_ROOT"
git add "apps/$SERVICE/overlays/$ENVIRONMENT/kustomization.yaml"
git commit -m "chore($SERVICE): set $ENVIRONMENT image to $DIGEST"

echo "OK: $SERVICE@$ENVIRONMENT -> $NEW_NAME@$DIGEST (commit created; push is a separate, deliberate step)"

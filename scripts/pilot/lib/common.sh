#!/usr/bin/env bash
# Shared helpers for the local pilot scripts (spec 001). Sourced, not executed.
# Strict mode, English checkpoints to stderr, machine output to documented paths.
set -euo pipefail

# Repository root (two levels up from scripts/pilot/lib).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export REPO_ROOT

# Pilot-owned constants. Everything the pilot creates carries these names so
# cleanup can target them exactly and never touch unrelated resources.
export PILOT_CLUSTER="${PILOT_CLUSTER:-microtodo-pilot}"
export PILOT_REGISTRY_NAME="${PILOT_REGISTRY_NAME:-microtodo-pilot-registry}"
export PILOT_REGISTRY_PORT="${PILOT_REGISTRY_PORT:-5001}"
export PILOT_GIT_PORT="${PILOT_GIT_PORT:-8081}"
export PILOT_HEALTH_PORT="${PILOT_HEALTH_PORT:-18000}"
export PILOT_KUBE_CONTEXT="${PILOT_KUBE_CONTEXT:-kind-${PILOT_CLUSTER}}"
export LOCAL_DIR="${REPO_ROOT}/.local"
export LOCAL_GIT_DIR="${LOCAL_DIR}/git"
export BARE_REPO="${LOCAL_GIT_DIR}/microservice-app-gitops.git"
export PILOT_WORKTREE="${LOCAL_DIR}/worktree"

log()  { echo "[$(_ts)] $*" >&2; }
ok()   { echo "[$(_ts)] OK: $*" >&2; }
die()  { echo "[$(_ts)] ERROR: $*" >&2; exit "${2:-1}"; }
# Timestamp without new Date() dependency issues in shell (date is fine here).
_ts() { date -u +%H:%M:%S; }

require_tool() { command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1" 3; }

# Render with a standalone Kustomize binary when one is installed, otherwise use
# kubectl's embedded Kustomize. Both paths are read-only.
render_kustomize() {
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

# Replace only images[].newName and images[].digest for one service overlay.
# This avoids a network/tool download solely for `kustomize edit` while keeping
# the existing digest-only contract explicit and narrow.
set_overlay_image() {
  local overlay="$1" service="$2" new_name="$3" digest="$4"
  local file="$overlay/kustomization.yaml" tmp

  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] \
    || die "invalid immutable digest for $service: $digest"
  [[ -f "$file" ]] || die "overlay kustomization not found: $file"
  tmp="$(mktemp)"

  if ! awk -v target="$service" -v replacement_name="$new_name" \
      -v replacement_digest="$digest" '
    /^images:[[:space:]]*$/ { in_images=1; print; next }
    in_images && /^[^[:space:]]/ { in_images=0 }
    in_images && /^[[:space:]]*- name:[[:space:]]*/ {
      current=$0
      sub(/^[[:space:]]*- name:[[:space:]]*/, "", current)
      selected=(current == target)
    }
    selected && /^[[:space:]]+newName:[[:space:]]*/ {
      match($0, /^[[:space:]]*/)
      $0=substr($0, RSTART, RLENGTH) "newName: " replacement_name
      changed_name=1
    }
    selected && /^[[:space:]]+digest:[[:space:]]*/ {
      match($0, /^[[:space:]]*/)
      $0=substr($0, RSTART, RLENGTH) "digest: " replacement_digest
      changed_digest=1
      selected=0
    }
    { print }
    END { exit (changed_name && changed_digest) ? 0 : 42 }
  ' "$file" >"$tmp"; then
    rm -f "$tmp"
    die "could not locate the $service image entry in $file"
  fi

  mv "$tmp" "$file"
}

# Read-only kubectl bound to the pilot context. Refuses mutating verbs so the
# GitOps-only rule is enforced by construction (spec 001, FR-006).
kro() {
  local verb="${1:-}"
  case "$verb" in
    get|wait|logs|describe|top|version|config|port-forward|auth) : ;;
    *) die "read-only kubectl only; refused verb: $verb" 7 ;;
  esac
  kubectl --context "$PILOT_KUBE_CONTEXT" "$@"
}

# Assert the filesystem remote resolves inside .local/git before any push
# (spec 001 CLI contract global safety rule).
assert_pilot_remote_safe() {
  case "$1" in
    "$LOCAL_GIT_DIR"/*) : ;;
    *) die "refusing to push: '$1' is outside $LOCAL_GIT_DIR" ;;
  esac
}

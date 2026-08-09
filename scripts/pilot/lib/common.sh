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

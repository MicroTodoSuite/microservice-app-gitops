#!/usr/bin/env bash
# Static contract for runtime security hardening (feature 008).
# Covers User Story 1 (Falco + Falcosidekick). kube-bench/kube-hunter are
# added by later tasks in specs/008-security-runtime-hardening/tasks.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*" >&2
}

render_kustomize() {
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "required file is missing: $1"
}

require_text() {
  local path="$1" pattern="$2" description="$3"
  rg -q -- "$pattern" "$ROOT/$path" || fail "$description ($path)"
}

reject_text() {
  local path="$1" pattern="$2" description="$3"
  if rg -q -- "$pattern" "$ROOT/$path"; then
    fail "$description ($path)"
  fi
}

check_rendered_images() {
  local render="$1" image_ref
  while IFS= read -r image_ref; do
    image_ref="${image_ref%\"}"
    image_ref="${image_ref#\"}"
    [[ "$image_ref" == *@sha256:* ]] \
      || fail "rendered executable image is not digest-pinned: $image_ref"
  done < <(sed -nE 's/^[[:space:]-]*image:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$render" | grep -v '^{{')
}

require_resource() {
  local render="$1" kind="$2" name="$3"
  awk -v wanted_kind="$kind" -v wanted_name="$name" '
    /^---$/ { current_kind=""; in_metadata=0 }
    /^kind: / { current_kind=$2; in_metadata=0 }
    current_kind == wanted_kind && /^metadata:$/ { in_metadata=1; next }
    current_kind == wanted_kind && in_metadata && /^  name: / {
      name=$2
      gsub(/"/, "", name)
      if (name == wanted_name) found=1
      in_metadata=0
    }
    END { exit found ? 0 : 1 }
  ' "$render" || fail "$kind/$name is missing from $(basename "$render")"
}

# --- Vendor provenance: none of the three tools has a genuine upstream
# bundle to checksum (all normally installed via Helm chart) ---
require_file "infrastructure/falco/vendor/v0.44.1/README.md"

# --- Render check ---
for component in falco; do
  render="$TMP_DIR/$component.yaml"
  render_kustomize "$ROOT/infrastructure/$component" >"$render" \
    || fail "Kustomize render failed for $component"
  [[ -s "$render" ]] || fail "$component rendered no resources"
  check_rendered_images "$render"
done

# --- Falco resources ---
require_resource "$TMP_DIR/falco.yaml" DaemonSet falco
require_resource "$TMP_DIR/falco.yaml" Deployment falcosidekick
require_resource "$TMP_DIR/falco.yaml" Service falcosidekick
require_resource "$TMP_DIR/falco.yaml" ExternalSecret falcosidekick-slack-webhook
require_resource "$TMP_DIR/falco.yaml" SecretStore aws-secrets-manager

# --- Falco driver: modern eBPF least-privileged, never full privileged ---
require_text infrastructure/falco/falco-daemonset.yaml '\-\-modern-bpf' \
  "Falco must use the modern eBPF driver (Clarifications session decision)"
require_text infrastructure/falco/falco-daemonset.yaml 'add: \["BPF", "SYS_RESOURCE", "PERFMON", "SYS_PTRACE"\]' \
  "Falco must use the least-privileged modern eBPF capability set, not privileged: true"
reject_text infrastructure/falco/falco-daemonset.yaml '^\s*privileged: true\s*$' \
  "Falco must never run as a fully privileged container"
reject_text infrastructure/falco/falco-daemonset.yaml 'hostPID' \
  "Falco does not need hostPID (verified against the real Helm chart)"

# --- No ClusterRole for Falco (only needed for driver.kind: auto, unused here) ---
reject_text infrastructure/falco/falco-daemonset.yaml 'kind: ClusterRole' \
  "Falco with an explicit modern_ebpf driver needs no ClusterRole"

# --- Falcosidekick wired to Slack via ESO, never a literal webhook ---
require_text infrastructure/falco/falcosidekick-slack-secret.yaml 'SLACK_WEBHOOKURL' \
  "Falcosidekick's Slack env var must be sourced from the ExternalSecret"
reject_text infrastructure/falco/falcosidekick-slack-secret.yaml 'hooks\.slack\.com/services' \
  "Slack webhook URL must never be a literal value in Git"
require_text infrastructure/falco/falco-config.yaml 'http_output:' \
  "Falco must forward findings to Falcosidekick over HTTP"
require_text infrastructure/falco/falco-config.yaml 'json_output: true' \
  "Falco must enable json_output for Falcosidekick per the real chart's own note"

# --- No enforcement: detection/audit only (FR-004) ---
for f in infrastructure/falco/falco-daemonset.yaml infrastructure/falco/falcosidekick.yaml; do
  reject_text "$f" 'kind: Ingress' \
    "$f must not add a public Ingress"
done

# --- Registration contract ---
require_text clusters/eks-dev/activation-infrastructure.yaml 'name: falco' \
  "eks-dev infrastructure activation omits falco"
if [[ "$(rg -A2 "name: falco$" "$ROOT/clusters/eks-dev/activation-infrastructure.yaml" | rg -c 'namespace: security')" -lt 1 ]]; then
  fail "eks-dev activation entry falco is not destined to the security namespace"
fi
require_text clusters/base/project.yaml 'namespace: security' \
  "AppProject destinations omit the security namespace"

pass "runtime security hardening static contract (falco)"

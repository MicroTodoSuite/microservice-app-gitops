#!/usr/bin/env bash
# Per-service workflow contract (spec 009, T101). Requires the five service
# repos and .github checked out as siblings of this repo (the same layout
# ../.github/.github/workflows/stack-tests.yml's stack-repos input already
# assumes for the frontend e2e/perf/dast/pact/conformance gates) -- run this
# from a workspace that has them, not gitops alone.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
workspace_root="$(cd "$repo_root/.." && pwd)"
matrix="$workspace_root/.github/tests/workflows/quality-gate-matrix.yaml"

declare -A REPO_DIR=(
  [auth-api]="$workspace_root/microservice-app-auth-api"
  [todos-api]="$workspace_root/microservice-app-todos-api"
  [users-api]="$workspace_root/microservice-app-users-api"
  [frontend]="$workspace_root/microservice-app-frontend"
  [log-message-processor]="$workspace_root/microservice-app-log-message-processor"
)

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$matrix" ]] || fail "missing ../.github/tests/workflows/quality-gate-matrix.yaml -- clone .github as a sibling of gitops."

assert_pinned_and_blocking() {
  local file="$1" label="$2"

  while IFS= read -r line; do
    local ref
    ref="$(sed -E 's/.*uses:[[:space:]]*//' <<<"$line" | awk '{print $1}')"
    [[ "$ref" == ./* ]] && continue
    [[ "$ref" =~ @[0-9a-f]{40}$ ]] || fail "$label: unpinned action or reusable workflow: $ref"
  done < <(grep -E '^\s*(-\s*)?uses:' "$file")

  grep -Fq 'continue-on-error: true' "$file" && fail "$label: a gate is marked continue-on-error, so it does not block."

  return 0
}

for service in "${!REPO_DIR[@]}"; do
  dir="${REPO_DIR[$service]}"
  [[ -d "$dir" ]] || fail "missing sibling checkout for $service: $dir"

  ci="$dir/.github/workflows/ci.yml"
  [[ -f "$ci" ]] || fail "$service: missing .github/workflows/ci.yml"
  assert_pinned_and_blocking "$ci" "$service/ci.yml"

  grep -Fq "service-name: $service" "$ci" || fail "$service/ci.yml: service-name does not match its own repository."

  # Cross-check against the quality-gate matrix T099 defines: every gate the
  # matrix marks "required" for this service must actually be wired as a
  # non-empty ci.yml input, not left to the reusable workflow's default skip.
  # frontend satisfies "contract" through its separate conformance.yml/pact.yml
  # gates (Schemathesis + Pact against the live stack), not ci.yml's inline
  # contract-command -- those two files are asserted below instead.
  contract_required="$(grep -A8 "^  $service:" "$matrix" | grep -E '^\s*contract:' | awk '{print $2}')"
  if [[ "$contract_required" == "required" && "$service" != "frontend" ]]; then
    grep -Eq 'contract-command:\s*\S' "$ci" || fail "$service/ci.yml: quality-gate-matrix.yaml requires contract, but contract-command is not wired."
  fi

  sonar_required="$(grep -A8 "^  $service:" "$matrix" | grep -E '^\s*sonar:' | awk '{print $2}')"
  if [[ "$sonar_required" == "required" ]]; then
    grep -Eq 'sonar-project-key:\s*\S' "$ci" || fail "$service/ci.yml: quality-gate-matrix.yaml requires sonar, but sonar-project-key is not wired."
    grep -Eq 'sonar-host-url:\s*\S' "$ci" || fail "$service/ci.yml: quality-gate-matrix.yaml requires sonar, but sonar-host-url is not wired."
  fi

  e2e_required="$(grep -A8 "^  $service:" "$matrix" | grep -E '^\s*e2e:' | awk '{print $2}')"
  perf_required="$(grep -A8 "^  $service:" "$matrix" | grep -E '^\s*performance:' | awk '{print $2}')"
  dast_required="$(grep -A8 "^  $service:" "$matrix" | grep -E '^\s*dast:' | awk '{print $2}')"

  for gate_pair in "e2e:$e2e_required" "perf:$perf_required" "dast:$dast_required"; do
    gate_name="${gate_pair%%:*}"
    gate_value="${gate_pair##*:}"
    gate_file="$dir/.github/workflows/$gate_name.yml"
    if [[ "$gate_value" == "required" ]]; then
      [[ -f "$gate_file" ]] || fail "$service: quality-gate-matrix.yaml requires $gate_name, but .github/workflows/$gate_name.yml is missing."
      assert_pinned_and_blocking "$gate_file" "$service/$gate_name.yml"
    fi
  done
done

# Contract-conformance-deep-layer and Pact are frontend-owned gates (T099/US1);
# assert they exist and are pinned/blocking wherever the matrix expects them.
for extra in conformance pact; do
  file="${REPO_DIR[frontend]}/.github/workflows/$extra.yml"
  [[ -f "$file" ]] || fail "frontend: missing .github/workflows/$extra.yml"
  assert_pinned_and_blocking "$file" "frontend/$extra.yml"
done

printf 'PASS: every service ci.yml is SHA-pinned and blocking, wires every gate quality-gate-matrix.yaml marks required, and frontend'"'"'s e2e/perf/dast/pact/conformance gates are present, pinned, and blocking.\n'

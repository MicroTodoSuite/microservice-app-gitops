#!/usr/bin/env bash
# Offline controlled runtime configuration contract (spec 009 T071/T090,
# FR-034). This slice is already implementable without a live cluster and is
# therefore suitable for blocking validate-gitops now.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KUSTOMIZE_BIN="${KUSTOMIZE_BIN:-kustomize}"
CONTRACT="$ROOT/docs/feature-toggles.md"

command -v "$KUSTOMIZE_BIN" >/dev/null || { printf 'FAIL: kustomize is required\n' >&2; exit 1; }

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
render() { "$KUSTOMIZE_BIN" build "$ROOT/$1"; }

document() {
  awk -v kind="$1" -v name="$2" '
    function flush() {
      if (doc ~ ("\nkind: " kind "\n") && doc ~ ("\n  name: " name "\n")) printf "%s", doc
      doc = "\n"
    }
    BEGIN { doc = "\n" }
    /^---$/ { flush(); next }
    { doc = doc $0 "\n" }
    END { flush() }
  '
}

container_block() {
  awk -v name="$1" '
    function check() {
      if (!done && block ~ ("\n(      - |        )name: " name "\n")) { printf "%s", block; done = 1 }
    }
    /^      containers:$/ { active = 1; block = ""; next }
    active && /^      - / { check(); block = "\n" $0 "\n"; next }
    active && /^        / { block = block $0 "\n"; next }
    active { check(); active = 0 }
    END { if (active) check() }
  '
}

config_map_names() {
  awk '
    /^---$/ { kind = "" }
    /^kind: / { kind = $2 }
    kind == "ConfigMap" && /^  name: / { print $2 }
  '
}

[[ -f "$CONTRACT" ]] || fail "docs/feature-toggles.md must document the toggle register and activation/revert process"
if [[ -f "$CONTRACT" ]]; then
  for phrase in \
    'defaults to `"false"` in Git' \
    'reviewed pull request' \
    'turning it off again is a revert' \
    '| Service | Key | Default | Owner | Purpose |'; do
    grep -qF -- "$phrase" "$CONTRACT" || fail "docs/feature-toggles.md must contain: $phrase"
  done
fi

SERVICES=(auth-api todos-api users-api frontend log-message-processor)
ENVIRONMENTS=(dev staging prod)
for service in "${SERVICES[@]}"; do
  base="$ROOT/apps/$service/base/configmap.yaml"
  [[ -f "$base" ]] || { fail "apps/$service/base/configmap.yaml is missing"; continue; }
  grep -q "name: $service-config" "$base" \
    || fail "$service must keep its controlled non-secret ConfigMap named $service-config"
  if grep -qE '(^|_)(PASSWORD|SECRET|TOKEN|API_KEY):' "$base"; then
    fail "$service controlled ConfigMap must not contain a secret-bearing key"
  fi

  component="$ROOT/apps/$service/components/topology-full/kustomization.yaml"
  [[ -f "$component" ]] || { fail "$service full topology component is missing"; continue; }
  grep -q 'configMapGenerator:' "$component" \
    || fail "$service full topology must generate an auditable feature-toggle ConfigMap"
  grep -q "name: $service-feature-toggles" "$component" \
    || fail "$service full topology must own $service-feature-toggles"
  grep -q 'microtodosuite.io/feature-toggle-contract: docs/feature-toggles.md' "$component" \
    || fail "$service feature toggles must link to docs/feature-toggles.md"

  for environment in "${ENVIRONMENTS[@]}"; do
    overlay="apps/$service/profiles/full/overlays/$environment"
    if ! output="$(render "$overlay" 2>&1)"; then
      fail "$overlay must render: $output"
      continue
    fi

    toggle_name="$(config_map_names <<<"$output" | grep -E "^$service-feature-toggles-[a-z0-9]{10}$" || true)"
    [[ "$(grep -c . <<<"$toggle_name" || true)" -eq 1 ]] \
      || { fail "$overlay must render exactly one hashed $service-feature-toggles ConfigMap"; continue; }

    toggles="$(document ConfigMap "$toggle_name" <<<"$output")"
    grep -q 'microtodosuite.io/feature-toggle-contract: docs/feature-toggles.md' <<<"$toggles" \
      || fail "$overlay toggle ConfigMap must link to the reviewed register"

    # If a service declares a toggle, every key is explicit, default-off, and
    # registered with an owner and purpose. An empty set is valid when the
    # service has no incomplete behavior.
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      key="${line%%:*}"
      value="${line#*: }"
      [[ "$key" =~ ^FEATURE_[A-Z0-9_]+$ ]] \
        || fail "$overlay toggle key must match FEATURE_<NAME>, found: $key"
      [[ "$value" == '"false"' || "$value" == "'false'" ]] \
        || fail "$overlay toggle $key must default to \"false\", found: $value"
      grep -qE "^\| $service \| \`$key\` \| \`\"false\"\` \| [^|]*[^ |][^|]* \| [^|]*[^ |][^|]* \|$" "$CONTRACT" \
        || fail "$overlay toggle $key must be registered with owner and purpose"
    done < <(awk '/^data:$/ { active = 1; next } active && /^  [^ ]/ { sub(/^  /, ""); print; next } active { exit }' <<<"$toggles")

    deployment="$(document Deployment "$service" <<<"$output")"
    container="$(container_block "$service" <<<"$deployment")"
    grep -qF "name: $service-config" <<<"$container" \
      || fail "$overlay service container must consume $service-config"
    grep -qF "name: $toggle_name" <<<"$container" \
      || fail "$overlay service container must consume the hashed toggle ConfigMap"
    if grep -A2 -F "name: $service-config" <<<"$container" | grep -q 'optional: true'; then
      fail "$overlay controlled ConfigMap must be required"
    fi
    if grep -A2 -F "name: $toggle_name" <<<"$container" | grep -q 'optional: true'; then
      fail "$overlay feature-toggle ConfigMap must be required"
    fi
  done

  economical="$(render "apps/$service/profiles/economical/overlays/dev")"
  if config_map_names <<<"$economical" | grep -q "^$service-feature-toggles"; then
    fail "$service economical profile must not receive full-profile feature toggles"
  fi
done

if (( failures > 0 )); then
  printf 'FAIL: %d runtime-configuration violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: every full service consumes controlled non-secret configuration and an auditable hashed feature-toggle ConfigMap; declared toggles are documented and default off, with no economical-profile leak.\n'

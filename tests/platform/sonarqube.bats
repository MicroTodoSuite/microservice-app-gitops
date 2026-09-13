#!/usr/bin/env bash
# SonarQube hardening render test (spec 009, T084 — the SonarQube half,
# distinct from tests/platform/eck.bats which covers the ECK half). Offline
# by design: no live cluster is touched.
set -euo pipefail

command -v kubeconform >/dev/null || { printf 'FAIL: kubeconform is required\n' >&2; exit 1; }
if ! command -v kustomize >/dev/null && ! command -v kubectl >/dev/null; then
  printf 'FAIL: standalone kustomize or kubectl is required\n' >&2
  exit 1
fi

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

render() {
  if command -v kustomize >/dev/null; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

out="$(render infrastructure/sonarqube | kubeconform -strict -ignore-missing-schemas -summary 2>&1)" || {
  fail "infrastructure/sonarqube does not render or does not pass kubeconform: $out"
}
grep -q 'Invalid: 0, Errors: 0' <<<"$out" \
  || fail "infrastructure/sonarqube has invalid or errored resources: $out"

r="$(render infrastructure/sonarqube)"

# --- digests pinned, exact versions from the toolchain lock -----------------
grep -q 'image: sonarqube@sha256:9026624a61cd25542a402a9e7213dd7dbb39724ac9597e331e6b85362558c079' <<<"$r" \
  || fail "SonarQube image must be pinned to the toolchain-lock digest"
grep -q 'image: postgres@sha256:cf78e76683b9ca8c5733cbbdce6c9262b45b6767934dd0a95e671f9a0fc20685' <<<"$r" \
  || fail "PostgreSQL image must be pinned to the toolchain-lock digest"
if grep -qE 'image: (sonarqube|postgres):' <<<"$r"; then
  fail "no SonarQube/PostgreSQL image may use a mutable tag"
fi

# --- no privileged pod (T084: vm.max_map_count set at node level) ----------
if grep -q 'privileged: true' <<<"$r"; then
  fail "the SonarQube stack must not run any privileged container (vm.max_map_count is a node-level concern)"
fi

# --- PodDisruptionBudgets for both singletons ------------------------------
pdb_count="$(grep -c '^kind: PodDisruptionBudget' <<<"$r" || true)"
[[ "$pdb_count" -eq 2 ]] \
  || fail "expected 2 PodDisruptionBudgets (sonarqube + postgres), found $pdb_count"

# --- default-deny NetworkPolicy present ------------------------------------
grep -q 'name: default-deny' <<<"$r" \
  || fail "the sonarqube namespace must carry a default-deny NetworkPolicy"

# --- dedicated tooling toleration on server and DB -------------------------
toleration_count="$(grep -c 'key: microtodosuite.io/tooling' <<<"$r" || true)"
[[ "$toleration_count" -ge 2 ]] \
  || fail "SonarQube and PostgreSQL must both tolerate the dedicated tooling taint, found $toleration_count"

# --- backup CronJob present ------------------------------------------------
grep -q '^kind: CronJob' <<<"$r" \
  || fail "a pg_dump backup CronJob must exist (T084 backup/recovery)"
grep -q 'pg_dump' <<<"$r" \
  || fail "the backup CronJob must run pg_dump"

# --- no committed DB password value ----------------------------------------
if grep -iE 'POSTGRES_PASSWORD:[[:space:]]*["'\'']?[A-Za-z0-9]{6,}' <<<"$r" | grep -vi 'secretKeyRef\|valueFrom\|key:\|name:' >/dev/null; then
  fail "no database password value may be rendered inline (must come from the ESO Secret)"
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d sonarqube violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: sonarqube and postgres are digest-pinned to the locked versions, no privileged container remains, both singletons have PDBs and tolerate the tooling taint, a default-deny NetworkPolicy and a pg_dump backup CronJob exist, and no DB password is committed.\n'

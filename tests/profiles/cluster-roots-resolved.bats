#!/usr/bin/env bash
# Every managed cluster root must render with its registration fully applied.
# The base ApplicationSets carry `registration-revision` and `registration.invalid`
# placeholders that each root's `replacements` must overwrite. A root that misses
# one still renders and still validates, and ArgoCD then fails at runtime with
# "unable to resolve 'registration-revision' to a commit SHA" (found on the three
# full clusters during gitops spec 009 T065, 2026-09-22).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
kustomize_bin="${KUSTOMIZE_BIN:-kustomize}"
command -v "$kustomize_bin" >/dev/null 2>&1 || {
  printf 'FAIL: kustomize is required; set KUSTOMIZE_BIN to the pinned binary.\n' >&2
  exit 1
}

failures=0
checked=0
for root in "$repo_root"/clusters/*/; do
  name="$(basename "$root")"
  [[ "$name" == "base" ]] && continue
  [[ -f "$root/kustomization.yaml" && -f "$root/registration.yaml" ]] || continue
  rendered="$("$kustomize_bin" build "$root")" || {
    printf 'FAIL: clusters/%s does not render\n' "$name" >&2
    failures=$((failures + 1))
    continue
  }
  checked=$((checked + 1))
  if leftovers="$(grep -nE 'registration-revision|registration\.invalid' <<<"$rendered")"; then
    printf 'FAIL: clusters/%s leaves registration placeholders unresolved:\n%s\n' "$name" "$leftovers" >&2
    failures=$((failures + 1))
  fi
done

[[ "$checked" -gt 0 ]] || { printf 'FAIL: no registered cluster root was checked\n' >&2; exit 1; }
[[ "$failures" -eq 0 ]] || { printf 'FAIL: %d cluster root(s) with unresolved registration\n' "$failures" >&2; exit 1; }
printf 'cluster-roots-resolved: OK — %d registered cluster roots render with no registration placeholder left\n' "$checked"

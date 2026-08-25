#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
kustomize_bin="${KUSTOMIZE_BIN:-kustomize}"
services=(auth-api frontend log-message-processor todos-api users-api)
environments=(dev staging prod)

command -v "$kustomize_bin" >/dev/null 2>&1 || {
  printf 'FAIL: kustomize is required; set KUSTOMIZE_BIN to the pinned binary.\n' >&2
  exit 1
}

for service in "${services[@]}"; do
  for environment in "${environments[@]}"; do
    economical="$repo_root/apps/$service/profiles/economical/overlays/$environment"
    full="$repo_root/apps/$service/profiles/full/overlays/$environment"
    golden="$repo_root/tests/profiles/golden/economical/$service/$environment.yaml"

    [[ -f "$economical/kustomization.yaml" ]] || {
      printf 'FAIL: missing economical overlay %s\n' "$economical" >&2
      exit 1
    }
    [[ -f "$full/kustomization.yaml" ]] || {
      printf 'FAIL: missing full overlay %s\n' "$full" >&2
      exit 1
    }
    [[ -f "$golden" ]] || {
      printf 'FAIL: missing economical golden render %s\n' "$golden" >&2
      exit 1
    }

    economical_render="$(mktemp)"
    full_render="$(mktemp)"
    "$kustomize_bin" build "$economical" > "$economical_render"
    "$kustomize_bin" build "$full" > "$full_render"
    # The golden renders exist to prove COMPOSITION is unchanged. The image
    # digest is the one field designed to change on every release, so pin its
    # shape rather than its value: a promotion must not have to rewrite the
    # goldens, but dropping to a mutable tag still fails, because only
    # @sha256:<64 hex> is normalized.
    golden_normalized="$(mktemp)"
    render_normalized="$(mktemp)"
    sed -E 's/@sha256:[a-f0-9]{64}/@sha256:<DIGEST>/g' "$golden" > "$golden_normalized"
    sed -E 's/@sha256:[a-f0-9]{64}/@sha256:<DIGEST>/g' "$economical_render" > "$render_normalized"
    cmp -s "$golden_normalized" "$render_normalized" || {
      diff -u "$golden_normalized" "$render_normalized" >&2 || true
      printf 'FAIL: %s/%s economical render changed.\n' "$service" "$environment" >&2
      exit 1
    }
    unlink "$golden_normalized"
    unlink "$render_normalized"
    grep -Fq 'microtodosuite.io/topology: full' "$full_render" || {
      printf 'FAIL: %s/%s full render does not select topology-full.\n' "$service" "$environment" >&2
      exit 1
    }
    unlink "$economical_render"
    unlink "$full_render"
  done
done

grep -Fq 'path: "{{ .path.path }}/profiles/{{ .profile }}/overlays/{{ .env }}"' \
  "$repo_root/clusters/base/apps.yaml" || {
  printf 'FAIL: the ApplicationSet path is not profile-aware.\n' >&2
  exit 1
}

for activation in \
  "$repo_root/clusters/eks-dev/activation-apps.yaml" \
  "$repo_root/clusters/eks-dev-capacity-constrained/activation-apps.yaml" \
  "$repo_root/clusters/local-kind/activation-templates/local/activation-apps.yaml"
do
  [[ -f "$activation" ]] || {
    printf 'FAIL: missing explicit profile activation %s\n' "$activation" >&2
    exit 1
  }
  grep -Fq 'profile: economical' "$activation" || {
    printf 'FAIL: %s does not preserve the economical profile.\n' "$activation" >&2
    exit 1
  }
  grep -Eq 'destination: (eks-dev|local-kind)' "$activation" || {
    printf 'FAIL: %s does not declare an economical destination identity.\n' "$activation" >&2
    exit 1
  }
done

grep -Fq 'value: []' "$repo_root/clusters/local-kind/activation-apps.yaml" || {
  printf 'FAIL: local-kind bootstrap activation must remain empty.\n' >&2
  exit 1
}

printf 'PASS: economical and full profiles render concurrently without changing the economical golden output.\n'

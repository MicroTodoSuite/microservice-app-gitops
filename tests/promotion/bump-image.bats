#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
kustomize_bin="${KUSTOMIZE_BIN:-kustomize}"
digest="sha256:1111111111111111111111111111111111111111111111111111111111111111"

command -v "$kustomize_bin" >/dev/null 2>&1 || {
  printf 'FAIL: kustomize is required; set KUSTOMIZE_BIN to the pinned binary.\n' >&2
  exit 1
}

worktree="$(mktemp -d)"
cp -a "$repo_root/apps" "$worktree/apps"
mkdir -p "$worktree/scripts"
cp "$repo_root/scripts/bump-image.sh" "$worktree/scripts/bump-image.sh"
chmod +x "$worktree/scripts/bump-image.sh"

git -C "$worktree" init -q
git -C "$worktree" config user.name "MicroTodoSuite Contract Test"
git -C "$worktree" config user.email "contract-test@microtodosuite.online"
git -C "$worktree" add apps scripts/bump-image.sh
git -C "$worktree" commit -qm "test: capture fixture"

(
  cd "$worktree"
  KUSTOMIZE_BIN="$kustomize_bin" \
    ./scripts/bump-image.sh auth-api dev economical eks-dev "$digest"
)

expected_path="apps/auth-api/profiles/economical/overlays/dev/kustomization.yaml"
changed_paths="$(git -C "$worktree" diff-tree --no-commit-id --name-only -r HEAD)"
[[ "$changed_paths" == "$expected_path" ]] || {
  printf 'FAIL: expected only %s to change, got:\n%s\n' "$expected_path" "$changed_paths" >&2
  exit 1
}
grep -Fq "digest: $digest" "$worktree/$expected_path" || {
  printf 'FAIL: selected overlay does not contain the requested digest.\n' >&2
  exit 1
}

# A promotion is a digest swap and nothing else.
#
# `kustomize edit set image` re-serializes the whole kustomization, so it
# silently reformats every unrelated block and strips the comments that record
# why an overlay is configured the way it is. Asserting only "one file changed"
# lets that through, which is exactly how ten promotion PRs came to rewrite
# their overlays end to end for a one-line change.
# --numstat rather than counting diff lines: a YAML sequence entry renders as
# `-- digest:` / `+- digest:`, which a naive ^-[^-] filter drops along with the
# diff header and reports as zero removals.
read -r added removed _ < <(git -C "$worktree" diff --numstat HEAD~1 HEAD -- "$expected_path")
[[ "$added" -eq 1 && "$removed" -eq 1 ]] || {
  printf 'FAIL: a promotion must change exactly one line, got +%s/-%s:\n' "$added" "$removed" >&2
  git -C "$worktree" diff HEAD~1 HEAD -- "$expected_path" >&2
  exit 1
}

# The changed line must be the digest itself, not a line that merely moved.
changed_line="$(git -C "$worktree" diff HEAD~1 HEAD -- "$expected_path" | grep -E '^\+' | grep -v '^+++')"
[[ "$changed_line" == *"digest: $digest"* ]] || {
  printf 'FAIL: the single changed line is not the digest: %s\n' "$changed_line" >&2
  exit 1
}

# Comments carry the overlay's policy; a promotion must not consume them.
comments_before="$(git -C "$worktree" show "HEAD~1:$expected_path" | grep -c '^\s*#' || true)"
comments_after="$(grep -c '^\s*#' "$worktree/$expected_path" || true)"
[[ "$comments_before" -eq "$comments_after" ]] || {
  printf 'FAIL: promotion dropped overlay comments (%s -> %s).\n' "$comments_before" "$comments_after" >&2
  exit 1
}

before_invalid="$(git -C "$worktree" rev-parse HEAD)"
if (
  cd "$worktree"
  KUSTOMIZE_BIN="$kustomize_bin" \
    ./scripts/bump-image.sh auth-api dev full eks-full-prod "$digest"
) >/dev/null 2>&1; then
  printf 'FAIL: an invalid environment/profile/destination tuple was accepted.\n' >&2
  exit 1
fi
[[ "$(git -C "$worktree" rev-parse HEAD)" == "$before_invalid" ]] || {
  printf 'FAIL: rejected tuple created a commit.\n' >&2
  exit 1
}
[[ -z "$(git -C "$worktree" status --short)" ]] || {
  printf 'FAIL: rejected tuple changed the fixture worktree.\n' >&2
  exit 1
}

printf 'PASS: image promotion updates one validated profile overlay and rejects an invalid tuple.\n'

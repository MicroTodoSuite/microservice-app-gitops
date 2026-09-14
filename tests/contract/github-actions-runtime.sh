#!/usr/bin/env bash
# Holds repository-owned workflows to the reviewed Node.js 24 checkout release.
# The SHA is actions/checkout v7.0.1, verified from the upstream signed commit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPECTED_CHECKOUT_SHA="3d3c42e5aac5ba805825da76410c181273ba90b1"

failures=0
references=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

while IFS= read -r workflow; do
  while IFS=: read -r line_number checkout_reference; do
    [[ -n "$checkout_reference" ]] || continue
    references=$((references + 1))
    checkout_sha="${checkout_reference##*@}"

    [[ "$checkout_sha" =~ ^[0-9a-f]{40}$ ]] \
      || fail "$workflow:$line_number must pin actions/checkout by a full commit SHA"
    [[ "$checkout_sha" == "$EXPECTED_CHECKOUT_SHA" ]] \
      || fail "$workflow:$line_number must use the reviewed Node.js 24 checkout SHA $EXPECTED_CHECKOUT_SHA"
  done < <(grep -nEo 'actions/checkout@[^[:space:]#]+' "$ROOT/$workflow" || true)
done < <(git -C "$ROOT" ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')

[[ "$references" -gt 0 ]] || fail "repository workflows must contain at least one actions/checkout reference"

if [[ "$failures" -gt 0 ]]; then
  printf 'FAIL: %d GitHub Actions runtime pin violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: all %d actions/checkout references use the reviewed Node.js 24 SHA.\n' "$references"

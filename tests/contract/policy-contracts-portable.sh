#!/usr/bin/env bash
# The policy-contracts job runs on a stock ubuntu-24.04 runner, which ships
# GNU grep but no ripgrep (spec 003 T032). The text-asserting contracts it
# runs must therefore need no tool outside the base image and the job's
# checksum-locked installs: a missing search tool once turned their rejections
# and counts into vacuous passes.
#
# Two checks per contract:
#   * static: no non-comment line invokes rg;
#   * runtime: with an rg trap first on PATH, the contract never calls it and
#     never reports a missing command. The contract's own verdict belongs to
#     its own workflow step, so it is not asserted here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

contracts=(
  tests/contract/platform-addons.sh
  tests/contract/service-onboarding.sh
  tests/contract/namespace-isolation.sh
)

trap_dir="$TMP_DIR/bin"
trap_log="$TMP_DIR/rg-calls.log"
mkdir -p "$trap_dir"
cat >"$trap_dir/rg" <<EOF
#!/usr/bin/env bash
printf '%s\n' "rg \$*" >>"$trap_log"
exit 127
EOF
chmod +x "$trap_dir/rg"

for contract in "${contracts[@]}"; do
  [[ -f "$ROOT/$contract" ]] || { fail "$contract is missing"; continue; }

  if grep -nE '(^|[[:space:]|;&(!])rg([[:space:]]|$)' "$ROOT/$contract" \
      | grep -vE '^[0-9]+:[[:space:]]*#'; then
    fail "$contract invokes ripgrep, which the policy-contracts runner does not ship"
  fi

  : >"$trap_log"
  stderr="$TMP_DIR/$(basename "$contract").stderr"
  PATH="$trap_dir:$PATH" bash "$ROOT/$contract" >/dev/null 2>"$stderr" || true
  if [[ -s "$trap_log" ]]; then
    fail "$contract called ripgrep at run time: $(head -1 "$trap_log")"
  fi
  if grep -nE 'command not found|ripgrep|\(rg\)' "$stderr"; then
    fail "$contract reported a missing search tool"
  fi
done

(( failures == 0 )) || exit 1
printf 'PASS: %s\n' "the policy contracts need no ripgrep" >&2

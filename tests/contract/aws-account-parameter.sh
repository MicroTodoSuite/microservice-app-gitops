#!/usr/bin/env bash
# The AWS account this repository targets is declared exactly once, in
# config/aws-account.env. This contract fails when any tracked file disagrees
# with that declaration or still carries a retired account.
#
# Specifications and evidence are records of what happened and are not
# checked; a specification's quickstart is an operating instruction and is.
# Anything else still pinned to another account must be listed, with a reason,
# in config/aws-account-exceptions.txt. That list exists to shrink: an entry
# whose file no longer carries a foreign account fails until it is removed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="config/aws-account.env"
EXCEPTIONS="config/aws-account-exceptions.txt"
PLACEHOLDER='^(123456789012|000000000000|111122223333)$'

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$ROOT/$CONFIG" ]] || die "$CONFIG does not declare the AWS account"

# Parsed, never sourced: the declaration is data and must not execute.
current="$(sed -n 's/^AWS_ACCOUNT_ID=\([0-9]*\)[[:space:]]*$/\1/p' "$ROOT/$CONFIG")"
retired="$(sed -n 's/^RETIRED_AWS_ACCOUNT_IDS="\([0-9 ]*\)"[[:space:]]*$/\1/p' "$ROOT/$CONFIG")"

[[ "$current" =~ ^[0-9]{12}$ ]] || die "$CONFIG must set AWS_ACCOUNT_ID to exactly 12 digits"
[[ ! "$current" =~ $PLACEHOLDER ]] || die "AWS_ACCOUNT_ID $current is a documentation placeholder"
for id in $retired; do
  [[ "$id" =~ ^[0-9]{12}$ ]] || die "retired account '$id' is not 12 digits"
  [[ "$id" != "$current" ]] || die "AWS_ACCOUNT_ID $current is also listed as retired"
done

in_scope() {
  case "$1" in
    "$CONFIG" | "$EXCEPTIONS") return 1 ;;
    evidence/*) return 1 ;;
    specs/*/quickstart.md) return 0 ;;
    specs/*) return 1 ;;
  esac
  return 0
}

declare -A excepted=()
if [[ -f "$ROOT/$EXCEPTIONS" ]]; then
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
    path="${line%%#*}"
    path="${path//[[:space:]]/}"
    reason="${line#*#}"
    if [[ "$line" != *"#"* || -z "${reason//[[:space:]]/}" ]]; then
      fail "exception '$path' gives no reason"
      continue
    fi
    [[ -f "$ROOT/$path" ]] || { fail "exception '$path' names a file that does not exist"; continue; }
    excepted["$path"]=1
  done <"$ROOT/$EXCEPTIONS"
fi

# Every shape an AWS account number takes in this project's files.
accounts_in() {
  grep -hoiE \
    -e 'arn:aws[a-z-]*:[a-z0-9-]*:[a-z0-9-]*:[0-9]{12}:' \
    -e '[0-9]{12}\.dkr\.ecr\.' \
    -e 'account[_a-z]*"?[[:space:]]*[:=][[:space:]]*"?[0-9]{12}' \
    -e 'tfstate-[0-9]{12}-' \
    -e 'amazonaws\.com/[0-9]{12}/' \
    -e '^[[:space:]]*[0-9]{12}[[:space:]]*$' \
    -- "$1" 2>/dev/null | grep -oE '[0-9]{12}' | sort -u || true
}

declare -A foreign=()
while IFS= read -r -d '' file; do
  in_scope "$file" || continue
  [[ -f "$ROOT/$file" ]] || continue
  grep -Iq . "$ROOT/$file" 2>/dev/null || continue
  found=""
  for id in $(accounts_in "$ROOT/$file"); do
    [[ "$id" == "$current" || "$id" =~ $PLACEHOLDER ]] && continue
    found+=" $id"
  done
  for id in $retired; do
    if [[ "$found" != *"$id"* ]] && grep -Fq -- "$id" "$ROOT/$file"; then
      found+=" $id"
    fi
  done
  [[ -z "$found" ]] && continue
  foreign["$file"]=1
  [[ -n "${excepted[$file]:-}" ]] && continue
  fail "$file carries account(s)$found instead of $current"
done < <(git -C "$ROOT" ls-files -z)

for path in "${!excepted[@]}"; do
  [[ -n "${foreign[$path]:-}" ]] \
    || fail "exception '$path' no longer carries a foreign account; remove it from $EXCEPTIONS"
done

if ((failures > 0)); then
  printf 'FAIL: %d account-parameter violation(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: every checked file targets AWS account %s (%d listed exception(s)).\n' \
  "$current" "${#excepted[@]}"

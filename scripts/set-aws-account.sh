#!/usr/bin/env bash
# Moves this repository to a different AWS account in one command:
#
#   scripts/set-aws-account.sh <12-digit-account-id>
#
# It rewrites the account declared in config/aws-account.env and every tracked
# file that carries it, retires the previous account, and then runs
# tests/contract/aws-account-parameter.sh. Specifications and evidence record
# what happened in the old account and are never rewritten; a specification's
# quickstart is an operating instruction and is.
#
# It changes files only. Creating the new account's state backend, applying
# Terraform, and publishing images remain separate, reviewed steps.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="config/aws-account.env"
EXCEPTIONS="config/aws-account-exceptions.txt"
PLACEHOLDER='^(123456789012|000000000000|111122223333)$'

die() {
  printf 'set-aws-account: %s\n' "$*" >&2
  exit 1
}

new="${1:-}"
[[ "$new" =~ ^[0-9]{12}$ ]] || die "usage: scripts/set-aws-account.sh <12-digit-account-id>"
[[ ! "$new" =~ $PLACEHOLDER ]] || die "$new is a documentation placeholder, not an account"

current="$(sed -n 's/^AWS_ACCOUNT_ID=\([0-9]*\)[[:space:]]*$/\1/p' "$ROOT/$CONFIG")"
retired="$(sed -n 's/^RETIRED_AWS_ACCOUNT_IDS="\([0-9 ]*\)"[[:space:]]*$/\1/p' "$ROOT/$CONFIG")"
[[ "$current" =~ ^[0-9]{12}$ ]] || die "$CONFIG does not declare a valid AWS_ACCOUNT_ID"
[[ "$new" != "$current" ]] || die "the repository already targets $new"
for id in $retired; do
  [[ "$new" != "$id" ]] \
    || die "$new is retired; un-retire it in $CONFIG through a reviewed change if that is really intended"
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

changed=()
while IFS= read -r -d '' file; do
  in_scope "$file" || continue
  [[ -f "$ROOT/$file" ]] || continue
  grep -Fq -- "$current" "$ROOT/$file" || continue
  sed -i "s/$current/$new/g" "$ROOT/$file"
  changed+=("$file")
done < <(git -C "$ROOT" ls-files -z)

retired_after="$(printf '%s %s' "$retired" "$current" | xargs)"
sed -i \
  -e "s/^AWS_ACCOUNT_ID=.*/AWS_ACCOUNT_ID=$new/" \
  -e "s/^RETIRED_AWS_ACCOUNT_IDS=.*/RETIRED_AWS_ACCOUNT_IDS=\"$retired_after\"/" \
  "$ROOT/$CONFIG"

printf 'set-aws-account: %s -> %s; %d tracked file(s) rewritten\n' "$current" "$new" "${#changed[@]}"
((${#changed[@]} == 0)) || printf '  %s\n' "${changed[@]}"

# Operator-owned inputs are gitignored and never edited here. Name every one
# that still carries an old account so it is not forgotten.
old_pattern="$current"
for id in $retired; do old_pattern+="|$id"; done
while IFS= read -r -d '' file; do
  grep -Eq -- "$old_pattern" "$ROOT/$file" 2>/dev/null \
    && printf 'set-aws-account: update by hand (gitignored): %s\n' "$file"
done < <(git -C "$ROOT" ls-files -z -o -i --exclude-standard -- '*.tfvars' '*.tfbackend')

"$ROOT/tests/contract/aws-account-parameter.sh"

cat <<NEXT
set-aws-account: this repository now targets $new. Still to do, each reviewed:
  - the same command in the other repository that declares an account
    (microservice-app-ops and microservice-app-gitops each declare their own);
  - the organization variable AWS_ACCOUNT_ID, read by every service workflow;
  - the new account's state backend and foundation, applied from saved plans.
NEXT

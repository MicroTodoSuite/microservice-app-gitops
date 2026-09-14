#!/usr/bin/env bash
# Admission and runtime security hardening render test (spec 009, T088,
# research.md Decision 22). Offline by design: no live cluster is touched, and
# no image signature is verified here; that needs the registry and Rekor.
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

# Print one rendered document by kind and metadata.name.
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

# --- slice 1: the service CI signing identity --------------------------------
# Fulcio uses a GitHub job's job_workflow_ref as the certificate SAN, so an
# image signed by the shared CI carries
# https://github.com/MicroTodoSuite/.github/.github/workflows/ci.yml@<ref>, with
# the ref each service's reviewed main pins. One SHA pin rejects every image
# signed after the next .github release.
SERVICES=(auth-api todos-api users-api frontend log-message-processor)
ISSUER='https://token.actions.githubusercontent.com'
SUBJECT_REGEXP='^https://github\.com/MicroTodoSuite/\.github/\.github/workflows/ci\.yml@[0-9a-f]{40}$'

kyverno_out="$(render infrastructure/kyverno)"
signatures="$(document ClusterPolicy verify-approved-release-signatures <<<"$kyverno_out")"
if [[ -z "$signatures" ]]; then
  fail "ClusterPolicy verify-approved-release-signatures is missing"
fi

# One row per keyless attestor, fields separated by the unit separator (\037):
# repository, workflow ref, trigger, issuer, exact subject, subject regexp.
# Not a tab: read treats tabs as whitespace and collapses empty fields.
US=$'\037'
attestors="$(awk '
  function row() { return repo "\037" ref "\037" trigger "\037" issuer "\037" subject "\037" subject_re }
  function value(line, key) {
    sub("^[[:space:]]*" key ":[[:space:]]*", "", line)
    if (line ~ /^'\''.*'\''$/) { line = substr(line, 2, length(line) - 2); gsub(/'\'''\''/, "'\''", line) }
    else if (line ~ /^".*"$/) { line = substr(line, 2, length(line) - 2) }
    return line
  }
  /^[[:space:]]*- keyless:$/ { if (n) print row(); n++; repo = ref = trigger = issuer = subject = subject_re = ""; next }
  !n { next }
  /^[[:space:]]+githubWorkflowRepository:/ { repo = value($0, "githubWorkflowRepository") }
  /^[[:space:]]+githubWorkflowRef:/ { ref = value($0, "githubWorkflowRef") }
  /^[[:space:]]+githubWorkflowTrigger:/ { trigger = value($0, "githubWorkflowTrigger") }
  /^[[:space:]]+issuer:/ { issuer = value($0, "issuer") }
  /^[[:space:]]+subject:/ { subject = value($0, "subject") }
  /^[[:space:]]+subjectRegExp:/ { subject_re = value($0, "subjectRegExp") }
  END { if (n) print row() }
' <<<"$signatures")"

[[ "$(grep -c . <<<"$attestors" || true)" == "${#SERVICES[@]}" ]] \
  || fail "verify-approved-release-signatures must have exactly one keyless attestor per service (${#SERVICES[@]})"
for service in "${SERVICES[@]}"; do
  matches="$(awk -F "$US" -v repo="MicroTodoSuite/microservice-app-$service" '$1 == repo' <<<"$attestors")"
  if [[ "$(grep -c . <<<"$matches" || true)" != 1 ]]; then
    fail "exactly one attestor must name githubWorkflowRepository MicroTodoSuite/microservice-app-$service"
    continue
  fi
  IFS="$US" read -r _ ref trigger issuer subject subject_re <<<"$matches"
  [[ "$ref" == refs/heads/main ]] || fail "$service attestor must require githubWorkflowRef refs/heads/main"
  [[ "$trigger" == push ]] || fail "$service attestor must require githubWorkflowTrigger push"
  [[ "$issuer" == "$ISSUER" ]] || fail "$service attestor must require issuer $ISSUER"
  [[ -z "$subject" ]] || fail "$service attestor must not pin one .github SHA as its exact subject ($subject)"
  [[ "$subject_re" == "$SUBJECT_REGEXP" ]] \
    || fail "$service attestor must use subjectRegExp $SUBJECT_REGEXP, found: ${subject_re:-none}"
done

# The expression, as rendered, admits the shared CI at any full commit SHA and
# nothing else. Go's RE2 and POSIX ERE agree on this expression's syntax.
policy_re="$(awk -F "$US" 'NR == 1 { print $6 }' <<<"$attestors")"
if [[ -z "$policy_re" ]]; then
  fail "no subjectRegExp to evaluate"
else
  for subject in \
    'https://github.com/MicroTodoSuite/.github/.github/workflows/ci.yml@d0da1aefcc8affcd07087d6e0c2c6391b270001d' \
    'https://github.com/MicroTodoSuite/.github/.github/workflows/ci.yml@5c4e133fc528ef6ff596d146150321ca94760721'; do
    grep -qE -- "$policy_re" <<<"$subject" || fail "subjectRegExp must admit $subject"
  done
  for subject in \
    'https://github.com/MicroTodoSuite/.github/.github/workflows/release.yml@d0da1aefcc8affcd07087d6e0c2c6391b270001d' \
    'https://github.com/MicroTodoSuite/.github/.github/workflows/ci.yml@refs/heads/main' \
    'https://github.com/MicroTodoSuite/.github/.github/workflows/ci.yml@d0da1ae' \
    'https://github.com/Elsewhere/.github/.github/workflows/ci.yml@d0da1aefcc8affcd07087d6e0c2c6391b270001d' \
    'https://github.com/MicroTodoSuite/microservice-app-auth-api/.github/workflows/ci.yml@d0da1aefcc8affcd07087d6e0c2c6391b270001d' \
    'https://github.com/MicroTodoSuite/.github/.github/workflows/ci.yml@d0da1aefcc8affcd07087d6e0c2c6391b270001d/extra' \
    'https://attacker.example/https://github.com/MicroTodoSuite/.github/.github/workflows/ci.yml@d0da1aefcc8affcd07087d6e0c2c6391b270001d'; do
    if grep -qE -- "$policy_re" <<<"$subject"; then
      fail "subjectRegExp must reject $subject"
    fi
  done
fi

# The policy stays fail-closed.
for expected in \
  'validationFailureAction: Enforce' \
  'failureAction: Enforce' \
  'required: true' \
  'failurePolicy: Fail' \
  '- 575172595729.dkr.ecr.us-east-1.amazonaws.com/lex-mts-shd-ecr-authapi*' \
  '- 575172595729.dkr.ecr.us-east-1.amazonaws.com/lex-mts-shd-ecr-frontend*' \
  '- 575172595729.dkr.ecr.us-east-1.amazonaws.com/lex-mts-shd-ecr-logmsgproc*' \
  '- 575172595729.dkr.ecr.us-east-1.amazonaws.com/lex-mts-shd-ecr-todosapi*' \
  '- 575172595729.dkr.ecr.us-east-1.amazonaws.com/lex-mts-shd-ecr-usersapi*'; do
  grep -qF -- "$expected" <<<"$signatures" \
    || fail "verify-approved-release-signatures must keep '$expected'"
done

if (( failures > 0 )); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: Kyverno admits images signed by the shared CI at any full commit SHA from the five services'"'"' reviewed main, and nothing else\n'

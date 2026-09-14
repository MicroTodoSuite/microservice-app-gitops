#!/usr/bin/env bash
# Admission and runtime security hardening render test (spec 009, T088,
# research.md Decision 22): the service CI signing identity (slice 1) and
# read-only evidence with GitOps-owned triggers (slice 2). Offline by design:
# no live cluster is touched, and no image signature is verified here; that
# needs the registry and Rekor.
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
  '- 575172595729.dkr.ecr.us-east-1.amazonaws.com/microtodosuite/*'; do
  grep -qF -- "$expected" <<<"$signatures" \
    || fail "verify-approved-release-signatures must keep '$expected'"
done

# --- slice 2: read-only evidence and GitOps-owned triggers ------------------
validate() {
  local path="$1" out
  out="$(render "$path" | kubeconform -strict -ignore-missing-schemas -summary 2>&1)" || {
    fail "$path does not render or does not pass kubeconform: $out"
    return
  }
  grep -q 'Invalid: 0, Errors: 0' <<<"$out" || fail "$path has invalid or errored resources: $out"
}
KUBE_BENCH_IMAGE='aquasec/kube-bench@sha256:75506f222d1eb6ce2a751a5533bdc0a3b54c898e2e49e7751d0ee22cfb862679'

for component in kube-bench kube-hunter falco; do
  triggers="infrastructure/$component/triggers"
  if [[ ! -f "$triggers/kustomization.yaml" ]]; then
    fail "$triggers is missing"
    continue
  fi
  # Disabled by default: only a reviewed commit adds triggers to the parent.
  if grep -qE '^[[:space:]]*-[[:space:]]*(\./)?triggers/?[[:space:]]*$' "infrastructure/$component/kustomization.yaml"; then
    fail "infrastructure/$component must not include triggers/ until a reviewed commit activates it"
  fi
  validate "$triggers"
  trigger_out="$(render "$triggers")"
  if grep -E '^  namespace:' <<<"$trigger_out" | grep -qvE '^  namespace: security$'; then
    fail "$triggers must render every namespaced resource into security"
  fi
  if grep -qE '^kind: (CronJob|Pod|Deployment|DaemonSet)$' <<<"$trigger_out"; then
    fail "$triggers must hold one-shot Jobs, not workloads that keep running"
  fi
done

# A kube-bench or kube-hunter trigger runs exactly what the schedule runs.
for entry in 'kube-bench|kube-bench-evidence' 'kube-hunter|kube-hunter-evidence'; do
  component="${entry%%|*}" job="${entry#*|}"
  [[ -f "infrastructure/$component/triggers/kustomization.yaml" ]] || continue
  cron_spec="$(render "infrastructure/$component" | document CronJob "$component" \
    | awk '/^  jobTemplate:$/ { t = 1; next } t && /^    spec:$/ { s = 1; next } s && /^      / { sub(/^    /, ""); print; next } s { exit }')"
  job_spec="$(render "infrastructure/$component/triggers" | document Job "$job" \
    | awk '/^spec:$/ { s = 1; next } s && /^  / { print; next } s { exit }')"
  if [[ -z "$job_spec" ]]; then
    fail "infrastructure/$component/triggers must define Job $job"
  elif [[ "$job_spec" != "$cron_spec" ]]; then
    fail "Job $job must repeat CronJob $component's job spec exactly"
  fi
done

# The Falco trigger is its own non-root Job, never a shell in a business pod.
if [[ -f infrastructure/falco/triggers/kustomization.yaml ]]; then
  falco_job="$(render infrastructure/falco/triggers | document Job falco-evidence-trigger)"
  if [[ -z "$falco_job" ]]; then
    fail "infrastructure/falco/triggers must define Job falco-evidence-trigger"
  else
    grep -qF "image: $KUBE_BENCH_IMAGE" <<<"$falco_job" \
      || fail "falco-evidence-trigger must run the pinned kube-bench image, which ships a real find binary"
    command_block="$(awk '/^ +command:$/ { c = 1; next } c && /^ +- / { sub(/^ +- /, ""); printf "%s ", $0; next } c { exit }' <<<"$falco_job")"
    [[ "$command_block" == "find /tmp -name id_rsa " ]] \
      || fail "falco-evidence-trigger must run exactly find /tmp -name id_rsa, found: ${command_block:-none}"
    grep -qE '^ +runAsNonRoot: true$' <<<"$falco_job" || fail "falco-evidence-trigger must run as non-root"
    grep -qE '^ +automountServiceAccountToken: false$' <<<"$falco_job" || fail "falco-evidence-trigger must not mount a service account token"
    if grep -qE '^ +(tty|stdin|hostPID|hostNetwork|privileged): true$' <<<"$falco_job"; then
      fail "falco-evidence-trigger must not use a terminal, host namespaces, or privilege"
    fi
  fi
fi

# The collector only reads, and tells the operator which trigger to activate.
for expected in 'Search Private Keys or Passwords' 'infrastructure/falco/triggers' 'infrastructure/kube-bench/triggers' 'infrastructure/kube-hunter/triggers'; do
  grep -qF -- "$expected" scripts/managed/verify-security.sh \
    || fail "scripts/managed/verify-security.sh must name '$expected'"
done
grep -qE '\bport-forward\b' scripts/managed/verify-observability.sh \
  || fail "scripts/managed/verify-observability.sh must query Prometheus through a local port-forward"

# No operator instruction still mutates the cluster by hand.
for doc in docs/security-runtime.md specs/008-security-runtime-hardening/quickstart.md specs/008-security-runtime-hardening/contracts/security-registration.md; do
  if grep -nE 'create job|kubectl[^|]*\bexec\b' "$doc"; then
    fail "$doc must not instruct creating Jobs or exec into pods by hand"
  fi
done

if (( failures > 0 )); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: Kyverno admits images signed by the shared CI at any full commit SHA from the five services'"'"' reviewed main, and nothing else; evidence triggers are disabled-by-default GitOps Jobs and the collectors only read\n'

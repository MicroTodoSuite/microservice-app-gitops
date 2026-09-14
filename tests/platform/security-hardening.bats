#!/usr/bin/env bash
# Admission and runtime security hardening render test (spec 009, T088,
# research.md Decision 22): the service CI signing identity (slice 1),
# read-only evidence with GitOps-owned triggers (slice 2), immutable digests
# over the full profile's platform namespaces (slice 3, partial), and exact
# RBAC, resource bounds, and audit retention (slice 4). Offline by design: no
# live cluster is touched, the pinned Kyverno CLI runs with no network, and no
# image signature is verified here; that needs the registry and Rekor.
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
    # Kustomize sorts keys, so command, the first key of the container, opens
    # its list item line ("- command:").
    command_block="$(awk '/^ +(- )?command:$/ { c = 1; next } c && /^ +- / { sub(/^ +- /, ""); printf "%s ", $0; next } c { exit }' <<<"$falco_job")"
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

# --- slice 4: exact RBAC, resource bounds, and audit retention --------------
# Exact RBAC is none: no audit pod may call the Kubernetes API (spec 008 FR-007).
for component in falco kube-bench kube-hunter; do
  parent_out="$(render "infrastructure/$component")"
  combined="$parent_out"
  if [[ -f "infrastructure/$component/triggers/kustomization.yaml" ]]; then
    combined="$parent_out"$'\n---\n'"$(render "infrastructure/$component/triggers")"
  fi
  if grep -qE '^kind: (Role|ClusterRole|RoleBinding|ClusterRoleBinding)$' <<<"$combined"; then
    fail "infrastructure/$component and its triggers must grant no Kubernetes API permission"
  fi

  # One line per pod template: "<kind>/<name> <serviceAccountName or none> <automount>".
  pods="$(awk '
    function flush() {
      if (kind ~ /^(DaemonSet|Deployment|CronJob|Job)$/) print kind "/" name, (sa == "" ? "none" : sa), (automount == "" ? "unset" : automount)
      kind = name = sa = automount = ""
    }
    /^---$/ { flush(); next }
    /^kind: / { kind = $2 }
    /^  name: / && name == "" { name = $2 }
    /^ +serviceAccountName: / { sa = $2 }
    /^ +automountServiceAccountToken: / && $0 !~ /^automount/ { automount = $2 }
    END { flush() }
  ' <<<"$combined")"
  while read -r workload sa automount; do
    [[ -n "$workload" ]] || continue
    if [[ "$sa" == none || "$sa" == default ]]; then
      fail "$workload in infrastructure/$component must name its own ServiceAccount, not ${sa/none/the default one}"
      continue
    fi
    [[ "$automount" == false ]] || fail "$workload in infrastructure/$component must set automountServiceAccountToken: false"
    account="$(document ServiceAccount "$sa" <<<"$parent_out")"
    if [[ -z "$account" ]]; then
      fail "ServiceAccount $sa used by $workload must be defined in infrastructure/$component"
    elif ! grep -qE '^automountServiceAccountToken: false$' <<<"$account"; then
      fail "ServiceAccount $sa must set automountServiceAccountToken: false"
    fi
  done <<<"$pods"

  # Every container bounds CPU and memory in both requests and limits.
  # Kustomize renders limits before requests at the same indentation, so an
  # open block is closed before the next line can open another one.
  bounds="$(awk '
    function close_block() { if (open && cpu && memory) complete[block]++; open = 0 }
    /^---$/ { close_block(); next }
    {
      if (open) {
        match($0, /^ */)
        if (RLENGTH > indent) {
          if ($1 == "cpu:") cpu = 1
          if ($1 == "memory:") memory = 1
          next
        }
        close_block()
      }
      if (match($0, /^ +(requests|limits):$/)) {
        block = $1; indent = RLENGTH - length(block); cpu = memory = 0; open = 1; next
      }
      if ($0 ~ /^ +(- )?image: /) containers++
    }
    END { close_block(); print containers + 0, complete["requests:"] + 0, complete["limits:"] + 0 }
  ' <<<"$combined")"
  read -r containers requests limits <<<"$bounds"
  [[ "$requests" == "$containers" && "$limits" == "$containers" ]] \
    || fail "every container in infrastructure/$component and its triggers must set CPU and memory requests and limits ($containers containers, $requests complete requests, $limits complete limits)"
done

# Audit reports stay readable for 7 days.
for component in kube-bench kube-hunter; do
  cron="$(render "infrastructure/$component" | document CronJob "$component")"
  grep -qE '^      ttlSecondsAfterFinished: 604800$' <<<"$cron" \
    || fail "CronJob $component must keep finished Jobs for 7 days (ttlSecondsAfterFinished: 604800)"
done
grep -qE '^  successfulJobsHistoryLimit: 7$' <<<"$(render infrastructure/kube-bench | document CronJob kube-bench)" \
  || fail "CronJob kube-bench runs daily and must keep 7 successful Jobs, or its history limit deletes reports before the TTL"

# --- slice 3, partial: immutable digests over full-profile platform namespaces
# The full profile's own Kyverno root extends the digest rule from microtodo-*
# to every namespace a GitOps infrastructure root renders, and from containers
# to init and ephemeral containers. The platform-mirror identity and the
# unsigned, wrong-identity, and unmirrored fixtures wait for the mirror
# repository (research.md Decision 22).
FULL_KYVERNO=infrastructure/profiles/full/kyverno/aws
KYVERNO_CLI_IMAGE='ghcr.io/kyverno/kyverno-cli@sha256:7224ed05508c24419c3df98114c28ba682ad0a940dcdb7b9fdba0a4b6bf943cf'
ADMISSION_FIXTURES=tests/platform/fixtures/full-profile-admission
# kube-system holds the Terraform-managed EKS add-ons and, like kyverno, is
# excluded by Kyverno's webhook; the bootstrap installs argocd with tagged images.
OUTSIDE_ADMISSION=(kube-system kyverno argocd)

# Print a render without one document (kind and metadata.name), so two renders
# can be compared everywhere else.
without_document() {
  awk -v kind="$1" -v name="$2" '
    function flush() {
      if (!(doc ~ ("\nkind: " kind "\n") && doc ~ ("\n  name: " name "\n"))) printf "---%s", doc
      doc = "\n"
    }
    BEGIN { doc = "\n" }
    /^---$/ { flush(); next }
    { doc = doc $0 "\n" }
    END { flush() }
  '
}

# Print the namespaces of the rule's match, one per line, sorted.
rule_namespaces() {
  awk '
    /^ *namespaces:$/ { match($0, /^ */); indent = RLENGTH; on = 1; next }
    on && match($0, /^ *- /) && RLENGTH - 2 >= indent {
      value = substr($0, RLENGTH + 1); gsub(/["'\'']/, "", value); print value; next
    }
    { on = 0 }
  ' | sort -u
}

# Print every namespace a render places objects in, including Namespace
# objects, ignoring null placeholders in vendored templates.
rendered_namespaces() {
  awk '
    function flush() {
      if (kind == "Namespace" && name != "") print name
      if (namespace != "") print namespace
      kind = name = namespace = ""; in_metadata = 0
    }
    /^---$/ { flush(); next }
    /^kind: / { kind = $2; next }
    /^metadata:$/ { in_metadata = 1; next }
    /^[^ #]/ { in_metadata = 0 }
    in_metadata && /^  name: / { name = $2 }
    in_metadata && /^  namespace: [a-z0-9]([-a-z0-9]*[a-z0-9])?$/ && $2 != "null" { namespace = $2 }
    END { flush() }
  '
}

shared_policy="$(document ClusterPolicy require-immutable-images <<<"$kyverno_out")"
[[ "$(rule_namespaces <<<"$shared_policy")" == 'microtodo-*' ]] \
  || fail "infrastructure/kyverno must keep require-immutable-images on microtodo-* only, so the economical cluster does not change"

if [[ ! -f "$FULL_KYVERNO/kustomization.yaml" ]]; then
  fail "$FULL_KYVERNO must exist as the full profile's Kyverno root"
else
  grep -qxE -- '- \.\./\.\./\.\./\.\./kyverno|  - \.\./\.\./\.\./\.\./kyverno' "$FULL_KYVERNO/kustomization.yaml" \
    || fail "$FULL_KYVERNO must take infrastructure/kyverno as its base"
  full_kyverno_out="$(render "$FULL_KYVERNO")"
  [[ "$(without_document ClusterPolicy require-immutable-images <<<"$full_kyverno_out")" == \
     "$(without_document ClusterPolicy require-immutable-images <<<"$kyverno_out")" ]] \
    || fail "$FULL_KYVERNO must render exactly infrastructure/kyverno apart from ClusterPolicy require-immutable-images"
  full_policy="$(document ClusterPolicy require-immutable-images <<<"$full_kyverno_out")"
  # Only the rules differ: admission, background, and the failure action stay
  # exactly as in the shared policy.
  without_rules() {
    awk '/^  rules:$/ { skip = 1; next } skip && /^(  - |   )/ { next } { skip = 0; print }'
  }
  [[ -n "$full_policy" && "$(without_rules <<<"$full_policy")" == "$(without_rules <<<"$shared_policy")" ]] \
    || fail "full-profile require-immutable-images must match the shared policy everywhere but its rules"

  # Business namespaces plus every namespace any GitOps infrastructure root renders.
  platform=""
  while IFS= read -r root; do
    if ! root_out="$(render "$root")"; then
      fail "$root must render to derive its namespaces"
      continue
    fi
    platform+="$(rendered_namespaces <<<"$root_out")"$'\n'
  done < <(find infrastructure -name kustomization.yaml -not -path '*/components/*' -printf '%h\n' | sort -u)
  outside_re="^($(IFS='|'; printf '%s' "${OUTSIDE_ADMISSION[*]}"))$"
  expected="$( { printf 'microtodo-*\n'; grep -vE "$outside_re" <<<"$platform" | grep . || true; } | sort -u)"
  actual="$(rule_namespaces <<<"$full_policy")"
  missing="$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | paste -sd ' ' -)"
  extra="$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | paste -sd ' ' -)"
  [[ -z "$missing" ]] || fail "full-profile require-immutable-images must match these rendered namespaces: $missing"
  [[ -z "$extra" ]] || fail "full-profile require-immutable-images must not match namespaces no root renders: $extra"
  for namespace in "${OUTSIDE_ADMISSION[@]}"; do
    if grep -qxF -- "$namespace" <<<"$actual"; then
      fail "full-profile require-immutable-images must leave $namespace outside admission"
    fi
  done
  grep -qE '^  validationFailureAction: Enforce$' <<<"$full_policy" \
    || fail "full-profile require-immutable-images must stay in Enforce"

  # The rendered rule decides the fixtures offline through the pinned Kyverno CLI.
  if ! command -v docker >/dev/null; then
    fail "docker is required to run the pinned Kyverno CLI ($KYVERNO_CLI_IMAGE)"
  else
    admission_dir="$(mktemp -d)"
    trap 'rm -rf "$admission_dir"' EXIT
    cp "$ADMISSION_FIXTURES/kyverno-test.yaml" "$ADMISSION_FIXTURES/resources.yaml" "$admission_dir/"
    printf '%s\n' "$full_policy" >"$admission_dir/require-immutable-images.yaml"
    chmod -R a+rX "$admission_dir"
    if ! cli_out="$(docker run --rm --network none --user "$(id -u):$(id -g)" -e HOME=/tmp \
        -v "$admission_dir:/fixtures:ro" -w /fixtures "$KYVERNO_CLI_IMAGE" \
        test . --remove-color 2>&1)"; then
      printf '%s\n' "$cli_out" >&2
      fail "the full-profile admission fixtures must all match their expected Kyverno result ($ADMISSION_FIXTURES)"
    fi
  fi
fi

if (( failures > 0 )); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: Kyverno admits images signed by the shared CI at any full commit SHA from the five services'"'"' reviewed main, and nothing else; evidence triggers are disabled-by-default GitOps Jobs and the collectors only read; full-profile admission requires digests in every container of business and GitOps-installed platform namespaces; audit pods hold no API permission, bound their resources, and keep reports for 7 days\n'

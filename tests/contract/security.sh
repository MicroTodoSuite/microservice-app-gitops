#!/usr/bin/env bash
# Static contract for runtime security hardening (feature 008).
# Covers all three user stories: Falco + Falcosidekick (US1), kube-bench
# (US2), and kube-hunter (US3).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*" >&2
}

render_kustomize() {
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "required file is missing: $1"
}

# GNU grep, not ripgrep: the validate-gitops runner image ships grep but not
# ripgrep. -r lets the same helpers check a single file or a whole directory.
check_checksum() {
  local directory="$1"
  require_file "$directory/SHA256SUMS"
  (
    cd "$ROOT/$directory"
    sha256sum -c SHA256SUMS >/dev/null
  ) || fail "checksum verification failed under $directory"
}

require_text() {
  local path="$1" pattern="$2" description="$3"
  grep -rEq -- "$pattern" "$ROOT/$path" || fail "$description ($path)"
}

reject_text() {
  local path="$1" pattern="$2" description="$3"
  if grep -rEq -- "$pattern" "$ROOT/$path"; then
    fail "$description ($path)"
  fi
}

# An approved economical teardown quiesces eks-dev by replacing every activation
# list with exactly `value: []` (spec 009 T170, clusters/README.md), a state that
# tests/contract/economical-runtime-quiescence.sh owns. Registration entries can
# be asserted only while the infrastructure list is active; a quiesced list is
# reported as skipped, never as a pass.
infrastructure_activation_is_quiesced() {
  local path="$ROOT/clusters/eks-dev/activation-infrastructure.yaml"
  [[ "$(grep -Ec '^  value: \[\]$' "$path" || true)" == 1 ]] \
    && ! grep -Eq '^    - ' "$path"
}

check_rendered_images() {
  local render="$1" image_ref
  while IFS= read -r image_ref; do
    image_ref="${image_ref%\"}"
    image_ref="${image_ref#\"}"
    [[ "$image_ref" == *@sha256:* ]] \
      || fail "rendered executable image is not digest-pinned: $image_ref"
  done < <(sed -nE 's/^[[:space:]-]*image:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$render" | grep -v '^{{')
}

require_resource() {
  local render="$1" kind="$2" name="$3"
  awk -v wanted_kind="$kind" -v wanted_name="$name" '
    /^---$/ { current_kind=""; in_metadata=0 }
    /^kind: / { current_kind=$2; in_metadata=0 }
    current_kind == wanted_kind && /^metadata:$/ { in_metadata=1; next }
    current_kind == wanted_kind && in_metadata && /^  name: / {
      name=$2
      gsub(/"/, "", name)
      if (name == wanted_name) found=1
      in_metadata=0
    }
    END { exit found ? 0 : 1 }
  ' "$render" || fail "$kind/$name is missing from $(basename "$render")"
}

# A container passes only if its own list item (not a sibling container, and not
# initContainers) declares the probe. Rendered YAML sorts keys, so the item is
# read as a whole rather than assuming "- name:" comes first; comment and blank
# lines are skipped, since a source manifest may annotate a container between
# list items. POSIX awk only.
require_container_probes() {
  local file="$1" container="$2" probe
  for probe in livenessProbe readinessProbe startupProbe; do
    awk -v wanted="$container" -v probe="$probe" '
      function indent(s) { match(s, /^ */); return RLENGTH }
      function flush() { if (item_name == wanted && item_has) found = 1; item_name = ""; item_has = 0 }
      /^ *containers: *$/ { flush(); in_list = 1; list_indent = -1; next }
      in_list {
        if ($0 ~ /^ *(#|$)/) next
        i = indent($0)
        if (list_indent < 0) {
          if ($0 ~ /^ *- /) list_indent = i
          else { in_list = 0; next }
        }
        if (i < list_indent || (i == list_indent && $0 !~ /^ *- /)) { flush(); in_list = 0; next }
        if (i == list_indent) { flush(); line = $0; sub(/^ *- /, "", line) }
        else if (i == list_indent + 2) { line = $0; sub(/^ */, "", line) }
        else next
        if (line ~ /^name: /) { name = line; sub(/^name: */, "", name); gsub(/"/, "", name); item_name = name }
        if (index(line, probe ":") == 1) item_has = 1
      }
      END { flush(); exit found ? 0 : 1 }
    ' "$file" || fail "container $container in ${file#"$ROOT"/} is missing $probe"
  done
}

# --- Vendor provenance: none of the three tools has a genuine upstream
# bundle to checksum (all normally installed via Helm chart or example Job) ---
require_file "infrastructure/falco/vendor/v0.44.1/README.md"
require_file "infrastructure/kube-bench/vendor/v0.16.0/README.md"
require_file "infrastructure/kube-hunter/vendor/v0.6.8/README.md"

# Trivy Operator is the exception: it ships a genuine upstream static bundle,
# retained with its checksum (spec 008 US4, T030).
require_file "infrastructure/trivy-operator/vendor/v0.34.0/README.md"
check_checksum "infrastructure/trivy-operator/vendor/v0.34.0"

# --- Render check ---
for component in falco kube-bench kube-hunter trivy-operator; do
  render="$TMP_DIR/$component.yaml"
  render_kustomize "$ROOT/infrastructure/$component" >"$render" \
    || fail "Kustomize render failed for $component"
  [[ -s "$render" ]] || fail "$component rendered no resources"
  check_rendered_images "$render"
done

# --- Falco resources ---
require_resource "$TMP_DIR/falco.yaml" DaemonSet falco
require_resource "$TMP_DIR/falco.yaml" Deployment falcosidekick
require_resource "$TMP_DIR/falco.yaml" Service falcosidekick
require_resource "$TMP_DIR/falco.yaml" ExternalSecret falcosidekick-slack-webhook
require_resource "$TMP_DIR/falco.yaml" SecretStore aws-secrets-manager

# --- Liveness, readiness, and startup probes on Falcosidekick (evolution plan
# section 10; spec 008 T028) ---
require_container_probes "$TMP_DIR/falco.yaml" falcosidekick

# --- Falco driver: modern eBPF least-privileged, never full privileged ---
# engine.kind lives in falco.yaml, not a --modern-bpf CLI flag: that flag is a
# docker-entrypoint.sh wrapper convenience, not a real falco binary option,
# and fails at runtime with "Option 'modern-bpf' does not exist".
require_text infrastructure/falco/falco-config.yaml 'kind: modern_ebpf' \
  "Falco must use the modern eBPF driver (Clarifications session decision)"
require_text infrastructure/falco/falco-daemonset.yaml 'add: \["BPF", "SYS_RESOURCE", "PERFMON", "SYS_PTRACE"\]' \
  "Falco must use the least-privileged modern eBPF capability set, not privileged: true"
reject_text infrastructure/falco/falco-daemonset.yaml '^\s*privileged: true\s*$' \
  "Falco must never run as a fully privileged container"
reject_text infrastructure/falco/falco-daemonset.yaml 'hostPID' \
  "Falco does not need hostPID (verified against the real Helm chart)"

# --- No ClusterRole for Falco (only needed for driver.kind: auto, unused here) ---
reject_text infrastructure/falco/falco-daemonset.yaml 'kind: ClusterRole' \
  "Falco with an explicit modern_ebpf driver needs no ClusterRole"

# --- Falcosidekick wired to Slack via ESO, never a literal webhook ---
require_text infrastructure/falco/falcosidekick-slack-secret.yaml 'SLACK_WEBHOOKURL' \
  "Falcosidekick's Slack env var must be sourced from the ExternalSecret"
reject_text infrastructure/falco/falcosidekick-slack-secret.yaml 'hooks\.slack\.com/services' \
  "Slack webhook URL must never be a literal value in Git"
require_text infrastructure/falco/falco-config.yaml 'http_output:' \
  "Falco must forward findings to Falcosidekick over HTTP"
require_text infrastructure/falco/falco-config.yaml 'json_output: true' \
  "Falco must enable json_output for Falcosidekick per the real chart's own note"

# --- No enforcement: detection/audit only (FR-004) ---
for f in infrastructure/falco/falco-daemonset.yaml infrastructure/falco/falcosidekick.yaml; do
  reject_text "$f" 'kind: Ingress' \
    "$f must not add a public Ingress"
done

# --- kube-bench resources ---
require_resource "$TMP_DIR/kube-bench.yaml" CronJob kube-bench
require_text infrastructure/kube-bench/cronjob.yaml 'eks-1.5.0' \
  "kube-bench must use the eks target profile (Clarifications session decision)"
require_text infrastructure/kube-bench/cronjob.yaml 'ttlSecondsAfterFinished' \
  "kube-bench Job must not leave a standing workload after it completes"
reject_text infrastructure/kube-bench/cronjob.yaml 'kind: ClusterRole' \
  "kube-bench needs no ClusterRole (verified against the real upstream job)"
reject_text infrastructure/kube-bench/cronjob.yaml '--outputfile' \
  "kube-bench must not write a persisted report file (findings stay in Job logs only)"

# --- kube-hunter resources ---
require_resource "$TMP_DIR/kube-hunter.yaml" CronJob kube-hunter
require_text infrastructure/kube-hunter/cronjob.yaml '"--pod"' \
  "kube-hunter must run in internal/passive --pod mode"
reject_text infrastructure/kube-hunter/cronjob.yaml '"--active"' \
  "kube-hunter must never run in active/exploiting mode (FR-006)"
require_text infrastructure/kube-hunter/cronjob.yaml 'ttlSecondsAfterFinished' \
  "kube-hunter Job must not leave a standing workload after it completes"
reject_text infrastructure/kube-hunter/cronjob.yaml 'kind: ClusterRole' \
  "kube-hunter needs no ClusterRole (verified against the real upstream job)"
reject_text infrastructure/kube-hunter/cronjob.yaml '^\s*hostPID: true\s*$' \
  "kube-hunter needs no hostPID (verified against the real upstream job)"

# --- Trivy Operator: continuous vulnerability scanning (FR-013 to FR-018; T030) ---
trivy="$TMP_DIR/trivy-operator.yaml"
require_resource "$trivy" Deployment trivy-operator
require_resource "$trivy" ServiceAccount trivy-operator
require_resource "$trivy" Service trivy-operator
require_resource "$trivy" CustomResourceDefinition vulnerabilityreports.aquasecurity.github.io
for policy in trivy-operator-default-deny trivy-operator-allow trivy-scan-jobs-default-deny trivy-scan-jobs-allow-egress; do
  require_resource "$trivy" NetworkPolicy "$policy"
done
if grep -Eq '^kind: Namespace$' "$trivy"; then
  fail "trivy-operator must not render the upstream trivy-system Namespace"
fi
if grep -q 'trivy-system' "$trivy"; then
  fail "the trivy-operator render still references trivy-system"
fi
if grep -E '^  namespace: ' "$trivy" | grep -vq '^  namespace: security$'; then
  fail "every namespaced trivy-operator resource must be in the security namespace"
fi

# Rendered ConfigMap data and container env, one key per line.
require_trivy_setting() {
  local key="$1" value="$2"
  grep -Eq "^  ${key}: \"?${value}\"?$" "$trivy" \
    || fail "trivy-operator must set ${key} to ${value}"
}
require_trivy_env() {
  local name="$1" value="$2"
  grep -A1 -E "^ +- name: ${name}$" "$trivy" | grep -Eq "^ +value: \"?${value}\"?$" \
    || fail "the trivy-operator container must set ${name} to ${value}"
}
# Vulnerability scanning only (FR-014), one scan Job at a time on two nodes.
require_trivy_setting OPERATOR_VULNERABILITY_SCANNER_ENABLED true
for flag in OPERATOR_CONFIG_AUDIT_SCANNER_ENABLED OPERATOR_RBAC_ASSESSMENT_SCANNER_ENABLED \
  OPERATOR_INFRA_ASSESSMENT_SCANNER_ENABLED OPERATOR_EXPOSED_SECRET_SCANNER_ENABLED \
  OPERATOR_CLUSTER_COMPLIANCE_ENABLED OPERATOR_SBOM_GENERATION_ENABLED \
  OPERATOR_METRICS_VULN_ID_ENABLED; do
  require_trivy_setting "$flag" false
done
require_trivy_setting OPERATOR_CONCURRENT_SCAN_JOBS_LIMIT 1
# Kustomize's namespace transformer does not rewrite env values.
require_trivy_env OPERATOR_NAMESPACE security
require_trivy_env OPERATOR_TARGET_NAMESPACES 'microtodo-dev,microtodo-staging,microtodo-prod,observability,security'
# The Trivy scanner image is set through ConfigMap data, not a Pod spec, so the
# images transformer cannot pin it.
require_trivy_setting trivy.tag '[0-9.]+@sha256:[a-f0-9]{64}'
# Private ECR access through IRSA, never static credentials (FR-017).
grep -Eq '^    eks\.amazonaws\.com/role-arn: arn:aws:iam::[0-9]{12}:role/microtodosuite-security-trivy-ecr-reader$' "$trivy" \
  || fail "the trivy-operator ServiceAccount must carry the Trivy ECR reader role ARN"
require_container_probes "$trivy" trivy-operator

# --- Registration contract ---
registration="asserted"
if infrastructure_activation_is_quiesced; then
  registration="skipped, eks-dev infrastructure activation is quiesced"
  printf 'SKIP: registration contract: %s\n' "$registration" >&2
else
  for name in falco kube-bench kube-hunter trivy-operator; do
    require_text clusters/eks-dev/activation-infrastructure.yaml "name: $name$" \
      "eks-dev infrastructure activation omits $name"
    if [[ "$(grep -A2 "name: $name$" "$ROOT/clusters/eks-dev/activation-infrastructure.yaml" | grep -c 'namespace: security')" -lt 1 ]]; then
      fail "eks-dev activation entry $name is not destined to the security namespace"
    fi
  done
fi
require_text clusters/base/project.yaml 'namespace: security' \
  "AppProject destinations omit the security namespace"

pass "runtime security hardening static contract (falco, kube-bench, kube-hunter, trivy-operator); registration $registration"

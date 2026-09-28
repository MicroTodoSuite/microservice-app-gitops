#!/usr/bin/env bash
# Failing-first GitOps-owned failure-mode contract (spec 009 T071/T094).
# Fixtures are disabled by construction and are activated only by a reviewed
# commit, observed read-only, and removed by Git revert.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KUSTOMIZE_BIN="${KUSTOMIZE_BIN:-kustomize}"

command -v "$KUSTOMIZE_BIN" >/dev/null || { printf 'FAIL: kustomize is required\n' >&2; exit 1; }

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
require_file() { [[ -f "$ROOT/$1" ]] || fail "required file is missing: $1"; }
render() { "$KUSTOMIZE_BIN" build "$ROOT/$1"; }

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

assert_disabled_child() {
  local parent="$1" child="$2"
  # A parent that does not exist yet cannot enable anything; the fixture's own
  # require_file assertion already reports the missing root.
  [[ -f "$ROOT/$parent/kustomization.yaml" ]] || return 0
  if grep -qE "^[[:space:]]*-[[:space:]]*(\./)?${child}/?[[:space:]]*$" "$ROOT/$parent/kustomization.yaml"; then
    fail "$parent/$child must stay disabled until a reviewed activation commit"
  fi
}

# Alert delivery is tested by a GitOps-owned rule/fixture, never by editing
# Alertmanager or firing a command inside a running pod.
ALERT_FIXTURE=infrastructure/profiles/full/prometheus/failure-fixtures/alert-delivery
require_file "$ALERT_FIXTURE/kustomization.yaml"
if [[ -f "$ROOT/$ALERT_FIXTURE/kustomization.yaml" ]]; then
  alert_render="$(render "$ALERT_FIXTURE")"
  grep -q '^kind: PrometheusRule$' <<<"$alert_render" \
    || fail "$ALERT_FIXTURE must render a PrometheusRule"
  grep -q 'alert: FullProfileEvidenceAlert' <<<"$alert_render" \
    || fail "$ALERT_FIXTURE must expose the fixed FullProfileEvidenceAlert signal"
  grep -q 'microtodosuite.io/evidence-fixture: "true"' <<<"$alert_render" \
    || fail "$ALERT_FIXTURE must be visibly marked as evidence-only"
fi
assert_disabled_child infrastructure/profiles/full/prometheus failure-fixtures

# Falco evidence is an isolated non-root Job; the parent stays disabled.
require_file infrastructure/falco/triggers/kustomization.yaml
if [[ -f "$ROOT/infrastructure/falco/triggers/kustomization.yaml" ]]; then
  falco="$(render infrastructure/falco/triggers)"
  trigger="$(document Job falco-evidence-trigger <<<"$falco")"
  [[ -n "$trigger" ]] || fail "Falco must have the GitOps-owned falco-evidence-trigger Job"
  grep -qE '^ +runAsNonRoot: true$' <<<"$trigger" \
    || fail "the Falco trigger must run as non-root"
  grep -qE '^ +automountServiceAccountToken: false$' <<<"$trigger" \
    || fail "the Falco trigger must not mount a service-account token"
  grep -qF -- '- id_rsa' <<<"$trigger" \
    || fail "the Falco trigger must exercise the private-key discovery rule"
fi
assert_disabled_child infrastructure/falco triggers

# Recovery experiments target only the full-dev stateful workloads and never
# remove a PVC. The assertion after recovery is a checked-in read-only Job.
CHAOS_FIXTURES=infrastructure/chaos-mesh/experiments/full-dev
for fixture in eck-retained-volume-recovery sonarqube-postgresql-retained-volume-recovery; do
  require_file "$CHAOS_FIXTURES/$fixture.yaml"
done
require_file "$CHAOS_FIXTURES/kustomization.yaml"
if [[ -f "$ROOT/$CHAOS_FIXTURES/kustomization.yaml" ]]; then
  recovery="$(render "$CHAOS_FIXTURES")"
  for experiment in eck-retained-volume-recovery sonarqube-postgresql-retained-volume-recovery; do
    grep -q "name: $experiment" <<<"$recovery" \
      || fail "$CHAOS_FIXTURES must render $experiment"
  done
  if grep -qE 'kind: (IOChaos|HTTPChaos)|action: (loss|corrupt)|persistentvolumeclaims|delete.*pvc' <<<"$recovery"; then
    fail "retained-volume recovery fixtures may restart pods/nodes but must not corrupt or delete PVCs"
  fi
  if grep -qE 'CHANGEME|microtodo-(staging|prod)' <<<"$recovery"; then
    fail "full-dev recovery fixtures must use exact selectors and expose no cross-environment target"
  fi
fi
assert_disabled_child infrastructure/chaos-mesh/experiments full-dev

# SonarQube and PostgreSQL expose readiness/startup health and retained claims
# (server data, extensions, database, backup) before a recovery experiment can
# be meaningful. The names are the ones infrastructure/sonarqube renders.
sonar="$(render infrastructure/sonarqube)"
for workload in sonarqube sonarqube-postgres; do
  block="$(document Deployment "$workload" <<<"$sonar")"
  [[ -n "$block" ]] || fail "Sonar root must render Deployment $workload"
  grep -qE '^ +readinessProbe:$' <<<"$block" \
    || fail "Deployment $workload must define readinessProbe"
done
grep -qE '^ +startupProbe:$' <<<"$(document Deployment sonarqube <<<"$sonar")" \
  || fail "SonarQube must define startupProbe"
for claim in sonarqube-data sonarqube-extensions sonarqube-postgres sonarqube-db-backup; do
  [[ -n "$(document PersistentVolumeClaim "$claim" <<<"$sonar")" ]] \
    || fail "Sonar recovery requires retained PersistentVolumeClaim $claim"
done

# ECK recovery requires a persistent Elasticsearch claim and readiness-aware
# custom resources rather than an ephemeral emptyDir deployment.
eck="$(render infrastructure/elasticsearch)"
grep -q '^kind: Elasticsearch$' <<<"$eck" \
  || fail "the ECK recovery target must render an Elasticsearch resource"
grep -q 'volumeClaimTemplates:' <<<"$eck" \
  || fail "the ECK recovery target must use a retained volumeClaimTemplate"
if grep -qE 'emptyDir:[[:space:]]*\{?\}?' <<<"$eck"; then
  fail "the ECK data path must not use emptyDir"
fi

# Scheduled audits and their on-demand equivalents are Jobs with seven-day
# retention, bounded resources, and no Kubernetes API token.
for component in kube-bench kube-hunter; do
  require_file "infrastructure/$component/triggers/kustomization.yaml"
  [[ -f "$ROOT/infrastructure/$component/triggers/kustomization.yaml" ]] || continue
  audit="$(render "infrastructure/$component/triggers")"
  grep -q '^kind: Job$' <<<"$audit" || fail "$component trigger must render a Job"
  grep -qE '^ +ttlSecondsAfterFinished: 604800$' <<<"$audit" \
    || fail "$component trigger Job must remain reviewable for seven days"
  grep -qE '^ +automountServiceAccountToken: false$' <<<"$audit" \
    || fail "$component trigger Job must not mount Kubernetes API credentials"
  for resource in cpu memory; do
    [[ "$(grep -cE "^ +$resource: " <<<"$audit" || true)" -ge 2 ]] \
      || fail "$component trigger Job must request and limit $resource"
  done
  assert_disabled_child "infrastructure/$component" triggers
done

# Bounded scaling needs both the controller/object limits and a disabled
# GitOps-owned load generator. No script may patch replicas directly.
SCALING_FIXTURE=infrastructure/profiles/full/keda/failure-fixtures/bounded-scaling
require_file "$SCALING_FIXTURE/kustomization.yaml"
if [[ -f "$ROOT/$SCALING_FIXTURE/kustomization.yaml" ]]; then
  scaling="$(render "$SCALING_FIXTURE")"
  grep -q '^kind: Job$' <<<"$scaling" \
    || fail "$SCALING_FIXTURE must render a bounded load-generator Job"
  grep -q 'activeDeadlineSeconds:' <<<"$scaling" \
    || fail "$SCALING_FIXTURE must stop itself through activeDeadlineSeconds"
  grep -q 'microtodosuite.io/evidence-fixture: "true"' <<<"$scaling" \
    || fail "$SCALING_FIXTURE must be visibly marked as evidence-only"
fi
for service in auth-api todos-api users-api frontend; do
  for environment in dev staging prod; do
    scaled="$(render "apps/$service/profiles/full/overlays/$environment" | document ScaledObject "$service")"
    [[ -n "$scaled" ]] || { fail "$service/$environment must render a ScaledObject"; continue; }
    grep -qE '^  minReplicaCount: [1-3]$' <<<"$scaled" \
      || fail "$service/$environment must keep minReplicaCount in the reviewed 1-3 range"
    grep -qE '^  maxReplicaCount: 5$' <<<"$scaled" \
      || fail "$service/$environment must cap maxReplicaCount at 5"
  done
done

# Chaos is inert in the shared parent and only an exact, reviewed destination
# overlay may select an experiment. Placeholder selectors are never activatable.
if grep -qE '^[[:space:]]*-[[:space:]]*(\./)?experiments/?[[:space:]]*$' "$ROOT/infrastructure/chaos-mesh/kustomization.yaml"; then
  fail "Chaos experiments must remain disabled in the shared capability root"
fi
if grep -R -n 'CHANGEME' "$ROOT/infrastructure/chaos-mesh/experiments/full-dev" 2>/dev/null; then
  fail "the reviewed full-dev chaos activation must not contain placeholder selectors"
fi

# Verification code remains read-only; activation belongs to Git commits. The
# audited bootstrap helper (docs/bootstrap-boundary.md) is not a verifier, and
# tests/policy/no-imperative-managed-mutations.bats owns its boundary.
if grep -R -nE 'kubectl[[:space:]]+(apply|create|patch|delete|scale|run)|kubectl[^|]*[[:space:]]exec[[:space:]]' \
    "$ROOT/scripts/managed" --include='verify-*.sh'; then
  fail "managed verification scripts must not imperatively activate failure fixtures"
fi

if (( failures > 0 )); then
  printf 'FAIL: %d failure-fixture contract violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: alert, Falco, recovery, audit, scaling, and chaos evidence actions are bounded, disabled-by-default GitOps manifests with retained-volume and readiness guards.\n'

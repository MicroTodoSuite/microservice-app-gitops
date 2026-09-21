#!/usr/bin/env bash
# Structural test for scripts/managed/verify-full-profile-cost.sh (spec 009,
# T147, research.md Decision 24). Runs the real collector -- no mocked kubectl
# -- like tests/platform/verify-full-platform.bats does for T148: the DESIRED
# half needs no cluster, and this environment genuinely has no
# eks-full-{dev,staging,prod} context, so the LIVE half's BLOCKED outcome is
# exercised for real rather than simulated.
#
# This is not a second copy of tests/platform/opencost-allocation.bats. That
# test is the contract on what the manifests must declare; this one is the
# contract on the collector: that it reads the declaration honestly, reports an
# explicit verdict, and never calls a cost it could not observe a pass.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$repo_root/scripts/managed/verify-full-profile-cost.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -x "$script" ]] || fail "verify-full-profile-cost.sh is missing or not executable"

# The collector must only read. A write verb against a managed cluster in its
# source is a defect no runtime check would catch here, because the live half
# never executes in this environment.
#
# Comments and string literals are removed before the search: several of this
# collector's own failure messages talk about labels and creation, and matching
# those words inside a message would report a mutation that no line performs.
mutations="$(python3 - "$script" <<'PY'
import re
import sys

VERBS = ("apply", "create", "delete", "patch", "scale", "edit", "replace",
         "annotate", "label", "cordon", "drain", "uncordon", "taint", "exec",
         "run", "set", "rollout")
INVOCATION = re.compile(
    r"\b(?:kubectl|kube)\b(?:\s+-{1,2}[^\s]+(?:\s+[^\s-][^\s]*)?)*\s+(" +
    "|".join(VERBS) + r")\b")

for number, line in enumerate(open(sys.argv[1]), start=1):
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    code = re.sub(r"'[^']*'", "''", code)
    code = re.sub(r"#.*$", "", code)
    found = INVOCATION.search(code)
    if found:
        print(f"{number}: {found.group(0).strip()}")
PY
)" || fail "could not scan the collector for mutating verbs"
[[ -z "$mutations" ]] || fail "the collector must stay read-only, but these lines invoke a mutating verb:
$mutations"

before_runs="$(find "$repo_root/evidence/runs" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

code=0
output="$(bash "$script" 2>&1)" || code=$?

# No eks-full-* context here: the honest result is DESIRED-only PASS plus a
# BLOCKED verdict, never a silent success and never a fabricated cost.
[[ "$code" -eq 2 ]] || fail "expected exit 2 (BLOCKED, no live full-profile cluster access here); got $code. Output:
$output"
grep -Fq 'VERDICT: BLOCKED' <<<"$output" || fail "missing explicit BLOCKED verdict in output:
$output"

# Cluster is the dimension a shared root cannot know, so the collector has to
# prove each destination names its own before any cost it reports means
# anything.
declare -A PHYSICAL=(
  [eks-full-dev]=lex-mts-fdev-eks-main
  [eks-full-staging]=lex-mts-fstg-eks-main
  [eks-full-prod]=lex-mts-fprd-eks-main
)
for destination in eks-full-dev eks-full-staging eks-full-prod; do
  grep -Fq "PASS: $destination: cost is attributed to ${PHYSICAL[$destination]}" <<<"$output" \
    || fail "$destination: expected the CLUSTER_ID attribution PASS naming ${PHYSICAL[$destination]}:
$output"
  grep -Fq "BLOCKED: $destination: live cost allocation" <<<"$output" \
    || fail "$destination: expected a BLOCKED live-allocation check, not found:
$output"
done

# The inputs OpenCost prices, the dimensions it groups by, and the dashboard
# that reads them: each recorded as its own check, because losing any one of
# them turns a cost report into an empty panel.
for anchor in \
  'PASS: allocation sources: the full Prometheus root runs node-exporter and kube-state-metrics' \
  'PASS: allocation sources: Prometheus scrapes the OpenCost exporter with honorLabels' \
  'PASS: allocation dimensions: kube-state-metrics publishes the service and profile pod labels' \
  'PASS: cost dashboard: the full Grafana root renders grafana-dashboards-full-profile-cost'; do
  grep -Fq "$anchor" <<<"$output" || fail "missing collector check: $anchor
$output"
done

# Profile and service are pod labels, so every full business overlay has to
# carry them for a per-service cost to exist at all.
for service in auth-api todos-api users-api frontend log-message-processor; do
  for destination in eks-full-dev eks-full-staging eks-full-prod; do
    grep -Fq "PASS: $destination/$service: pods carry microtodosuite.io/profile: full" <<<"$output" \
      || fail "$destination/$service: expected the profile-label PASS, not found:
$output"
  done
done

# Nothing about the declared cost model is broken today, so a FAIL here would
# be the collector inventing one.
if grep -Fq 'FAIL:' <<<"$output"; then
  fail "unexpected FAIL in a run where every declared cost input is present:
$output"
fi

# The collector writes only its own timestamped evidence directory.
after_dirs=("$repo_root"/evidence/runs/*-full-profile-cost)
[[ -d "${after_dirs[0]}" ]] || fail "expected a new -full-profile-cost evidence directory"
[[ -s "${after_dirs[0]}/raw/eks-full-dev-cluster-id.txt" ]] \
  || fail "expected the observed CLUSTER_ID of eks-full-dev to be retained as evidence"
for dir in "${after_dirs[@]}"; do
  rm -rf "$dir"
done
after_runs="$(find "$repo_root/evidence/runs" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
[[ "$after_runs" -eq "$before_runs" ]] || fail "left stray evidence directories behind after cleanup"

printf 'PASS: verify-full-profile-cost.sh reports the declared cost model per destination (cluster attribution, priced inputs, grouping labels, dashboard) and blocks explicitly on the live allocation it cannot observe here.\n'

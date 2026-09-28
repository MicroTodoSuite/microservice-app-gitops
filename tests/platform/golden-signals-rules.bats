#!/usr/bin/env bash
# Golden-signal rule behavior test (spec 006 T054). Extracts the groups of the
# business-workload-golden-signals PrometheusRule into a plain Prometheus rule
# file and runs promtool's rule unit tests against it, proving that
# WorkloadHighLatency can fire for stable traffic. Offline by design.
set -euo pipefail

command -v promtool >/dev/null || { printf 'FAIL: promtool is required\n' >&2; exit 1; }

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
rules="$repo_root/infrastructure/prometheus/rules/golden-signals.yaml"
fixture="$repo_root/tests/platform/fixtures/golden-signals/latency-alert.test.yaml"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# A PrometheusRule's spec is a Prometheus rule file indented under `spec:`.
awk '
  /^spec:$/ { in_spec = 1; next }
  in_spec && /^[^[:space:]#]/ { in_spec = 0 }
  in_spec { sub(/^  /, ""); print }
' "$rules" >"$tmp_dir/golden-signals.rules.yaml"
grep -q '^groups:$' "$tmp_dir/golden-signals.rules.yaml" \
  || fail "could not extract rule groups from $rules"
cp "$fixture" "$tmp_dir/latency-alert.test.yaml"

promtool check rules "$tmp_dir/golden-signals.rules.yaml" >/dev/null \
  || fail "golden-signal rules do not pass promtool check rules"
(cd "$tmp_dir" && promtool test rules latency-alert.test.yaml) \
  || fail "WorkloadHighLatency does not fire for slow stable traffic (promtool test rules)"

printf 'PASS: golden-signal rules pass promtool; WorkloadHighLatency fires for slow stable traffic and ignores the canary revision\n'

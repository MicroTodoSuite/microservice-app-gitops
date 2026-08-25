#!/usr/bin/env bash
# Economical platform baseline (spec 009, T033).
#
# SC-001 requires that every capability healthy before a full-profile stage is
# still healthy after it. That is only checkable against a recorded baseline,
# so this captures one: Git revision, AWS and cluster identity, ArgoCD
# Applications, workloads, endpoints, namespace isolation, and the dev drift
# verdict.
#
# STRICTLY READ-ONLY. It reads cluster and cloud state and writes only its own
# report. It contains no mutating kubectl verb and no mutating terraform verb,
# which tests/evidence/economical-baseline.bats asserts against this file.
#
# Fails closed. A degraded platform, an unreachable cluster, or an Application
# synced to a revision other than the one under test are all recorded as such
# and exit non-zero, because a baseline that reports success while the cluster
# disagrees is worse than no baseline.
set -euo pipefail

OUTPUT=""
GIT_REVISION=""
DEV_PLAN_RESULT=""
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
WORKLOAD_NAMESPACES="${WORKLOAD_NAMESPACES:-microtodo-dev,microtodo-staging,microtodo-prod}"
KUBE_CONTEXT=""

usage() {
  cat >&2 <<'EOF'
Usage: capture-economical-baseline.sh --output FILE [options]

  --output           Baseline JSON path (required).
  --git-revision     Revision every Application must be synced to.
  --dev-plan-result  `no-changes` when the refreshed dev plan was clean.
  --kube-context     Context to read.
EOF
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output)          [[ "$#" -ge 2 ]] || fail "--output requires a value";          OUTPUT="$2";          shift 2 ;;
    --git-revision)    [[ "$#" -ge 2 ]] || fail "--git-revision requires a value";    GIT_REVISION="$2";    shift 2 ;;
    --dev-plan-result) [[ "$#" -ge 2 ]] || fail "--dev-plan-result requires a value"; DEV_PLAN_RESULT="$2"; shift 2 ;;
    --kube-context)    [[ "$#" -ge 2 ]] || fail "--kube-context requires a value";    KUBE_CONTEXT="$2";    shift 2 ;;
    --help|-h)         usage; exit 0 ;;
    *)                 usage; fail "unknown argument: $1" ;;
  esac
done

[[ -n "$OUTPUT" ]] || { usage; fail "--output is required"; }
for dependency in jq python3 kubectl; do
  command -v "$dependency" >/dev/null 2>&1 || fail "required command is missing: $dependency"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

kube() {
  local args=(--request-timeout=60s -o json)
  [[ -n "$KUBE_CONTEXT" ]] && args+=(--context "$KUBE_CONTEXT")
  kubectl get "$@" "${args[@]}"
}

# An unreachable cluster is recorded and reported, never treated as empty.
record_unreachable() {
  python3 - "$OUTPUT" "$GIT_REVISION" "$1" <<'PY'
import json, pathlib, sys, datetime
output, revision, reason = sys.argv[1], sys.argv[2], sys.argv[3]
pathlib.Path(output).write_text(json.dumps({
    "result": "unreachable",
    "capturedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "git": {"revision": revision},
    "reason": reason,
}, indent=2) + "\n", encoding="utf-8")
PY
  printf 'FAIL: the economical platform is unreachable: %s\n' "$1" >&2
  exit 1
}

kube applications -n "$ARGOCD_NAMESPACE" > "$WORK/applications.json" 2>"$WORK/err.txt" \
  || record_unreachable "$(head -1 "$WORK/err.txt")"

IFS=',' read -r -a namespaces <<< "$WORKLOAD_NAMESPACES"
printf '{"items":[]}' > "$WORK/pods.json"
printf '{"items":[]}' > "$WORK/endpoints.json"
printf '{"items":[]}' > "$WORK/networkpolicies.json"
for resource in pods endpoints networkpolicies; do
  kube "$resource" --all-namespaces > "$WORK/$resource.json" 2>"$WORK/err.txt" \
    || record_unreachable "$(head -1 "$WORK/err.txt")"
done

AWS_IDENTITY='{}'
if command -v aws >/dev/null 2>&1; then
  AWS_IDENTITY="$(aws sts get-caller-identity 2>/dev/null || echo '{}')"
fi
printf '%s' "$AWS_IDENTITY" > "$WORK/aws-identity.json"

python3 - \
  "$OUTPUT" "$GIT_REVISION" "$DEV_PLAN_RESULT" "$WORKLOAD_NAMESPACES" \
  "$WORK/applications.json" "$WORK/pods.json" "$WORK/endpoints.json" \
  "$WORK/networkpolicies.json" "$WORK/aws-identity.json" <<'PY'
import datetime
import json
import pathlib
import sys

(output, revision, dev_plan_result, namespaces_raw,
 applications_path, pods_path, endpoints_path, policies_path, identity_path) = sys.argv[1:10]

namespaces = [n for n in namespaces_raw.split(",") if n]


def load(path):
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))


applications = load(applications_path).get("items", [])
pods = load(pods_path).get("items", [])
endpoints = load(endpoints_path).get("items", [])
policies = load(policies_path).get("items", [])
identity = load(identity_path)

app_exceptions, revision_mismatches = [], []
synced = healthy = 0
for app in applications:
    status = app.get("status", {})
    sync = status.get("sync", {})
    name = app["metadata"]["name"]
    sync_status = sync.get("status")
    health_status = status.get("health", {}).get("status")

    if sync_status == "Synced":
        synced += 1
    if health_status == "Healthy":
        healthy += 1
    if sync_status != "Synced" or health_status != "Healthy":
        app_exceptions.append({"name": name, "sync": sync_status, "health": health_status})

    # An Application synced to another revision describes a platform that is
    # not the one the revision under test declares.
    observed = sync.get("revision")
    if revision and observed and observed != revision:
        revision_mismatches.append({"name": name, "expected": revision, "observed": observed})

not_ready = []
ready = 0
for pod in pods:
    namespace = pod["metadata"].get("namespace")
    if namespaces and namespace not in namespaces:
        continue
    statuses = pod.get("status", {}).get("containerStatuses") or []
    if pod.get("status", {}).get("phase") == "Running" and statuses and all(c.get("ready") for c in statuses):
        ready += 1
    else:
        not_ready.append({"name": pod["metadata"]["name"], "namespace": namespace,
                          "phase": pod.get("status", {}).get("phase")})

without_addresses = []
for endpoint in endpoints:
    namespace = endpoint["metadata"].get("namespace")
    if namespaces and namespace not in namespaces:
        continue
    addresses = [a for subset in (endpoint.get("subsets") or []) for a in (subset.get("addresses") or [])]
    if not addresses:
        without_addresses.append({"name": endpoint["metadata"]["name"], "namespace": namespace})

with_policy = {p["metadata"].get("namespace") for p in policies}
without_policy = sorted(n for n in namespaces if n not in with_policy)

dev_plan_clean = dev_plan_result == "no-changes"

if revision_mismatches:
    result = "revision-mismatch"
elif app_exceptions or not_ready or without_addresses or without_policy or not dev_plan_clean:
    result = "degraded"
else:
    result = "pass"

baseline = {
    "result": result,
    "capturedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "git": {"revision": revision},
    # Account and cluster only: a baseline is comparison evidence and must not
    # become somewhere credentials live.
    "identities": {
        "awsAccountId": identity.get("Account"),
        "argocdNamespace": "argocd",
        "workloadNamespaces": namespaces,
    },
    "applications": {
        "total": len(applications),
        "synced": synced,
        "healthy": healthy,
        "exceptions": sorted(app_exceptions, key=lambda item: item["name"]),
        "revisionMismatches": sorted(revision_mismatches, key=lambda item: item["name"]),
    },
    "workloads": {"total": ready + len(not_ready), "ready": ready,
                  "notReady": sorted(not_ready, key=lambda item: item["name"])},
    "endpoints": {"total": len([e for e in endpoints
                                if e["metadata"].get("namespace") in namespaces or not namespaces]),
                  "withoutAddresses": sorted(without_addresses, key=lambda item: item["name"])},
    "namespaceIsolation": {"namespacesWithoutPolicy": without_policy},
    "devPlan": {"clean": dev_plan_clean, "result": dev_plan_result},
}

pathlib.Path(output).write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")

if result != "pass":
    print(f"FAIL: the economical baseline is '{result}'", file=sys.stderr)
    for exception in app_exceptions:
        print(f"  application {exception['name']}: sync={exception['sync']} health={exception['health']}", file=sys.stderr)
    for mismatch in revision_mismatches:
        print(f"  application {mismatch['name']}: expected {mismatch['expected']}, observed {mismatch['observed']}", file=sys.stderr)
    for workload in not_ready:
        print(f"  workload {workload['namespace']}/{workload['name']}: {workload['phase']}", file=sys.stderr)
    for endpoint in without_addresses:
        print(f"  endpoint {endpoint['namespace']}/{endpoint['name']}: no ready addresses", file=sys.stderr)
    for namespace in without_policy:
        print(f"  namespace {namespace}: no NetworkPolicy", file=sys.stderr)
    if not dev_plan_clean:
        print(f"  dev plan: {dev_plan_result}", file=sys.stderr)
    raise SystemExit(1)

print(f"PASS: economical baseline captured at {baseline['capturedAt']} ({len(applications)} applications, {ready} workloads ready).")
PY

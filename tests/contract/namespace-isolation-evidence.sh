#!/usr/bin/env bash
# Contract coverage for feature-005 evidence schema, redaction, and phase helpers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
SCHEMA="$ROOT/specs/005-namespace-isolation/contracts/namespace-isolation-evidence.schema.json"
VALID_FIXTURE="$ROOT/tests/fixtures/namespace-isolation/evidence/valid-v2.0.0-baseline.json"
INVALID_FIXTURE="$ROOT/tests/fixtures/namespace-isolation/evidence/invalid-v2.0.0-secret-output.json"
KUBE_CONTEXT=test-context
EXPECTED_CLUSTER_ID=arn:aws:eks:us-east-1:916491575487:cluster/microtodosuite-dev
EXPECTED_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
CLEANUP_REVISION=
PREVIOUS_EVIDENCE=
RELEASE_EVIDENCE=
PHASE=baseline
PHASE_EVIDENCE_JSON='{}'
BLOCKED_REASONS_JSON='["business release prerequisites are not yet reconciled","AWS principal-to-group mappings remain deferred"]'

# shellcheck source=scripts/managed/lib/namespace-isolation.sh
source "$ROOT/scripts/managed/lib/namespace-isolation.sh"

validate_fixture() {
  python3 - "$SCHEMA" "$1" <<'PY'
import json
import sys
from jsonschema import Draft202012Validator, FormatChecker

with open(sys.argv[1], encoding="utf-8") as schema_file:
    schema = json.load(schema_file)
with open(sys.argv[2], encoding="utf-8") as evidence_file:
    evidence = json.load(evidence_file)
Draft202012Validator(schema, format_checker=FormatChecker()).validate(evidence)
PY
}

validate_fixture "$VALID_FIXTURE"
if validate_fixture "$INVALID_FIXTURE" >/dev/null 2>&1; then
  printf 'FAIL: secret-output fixture unexpectedly satisfied schema v2.0.0\n' >&2
  exit 1
fi
previous_phase_is_acceptable "$VALID_FIXTURE" baseline microtodosuite-dev
jq '.blockedReasons = ["different blocker"]' "$VALID_FIXTURE" \
  >"$TMP_DIR/invalid-baseline-predecessor.json"
if previous_phase_is_acceptable "$TMP_DIR/invalid-baseline-predecessor.json" baseline microtodosuite-dev; then
  printf 'FAIL: an unrelated blocked baseline was accepted as a prerequisite predecessor\n' >&2
  exit 1
fi

help_output="$("$ROOT/scripts/managed/verify-namespace-isolation.sh" --help 2>&1)"
for phase in baseline prerequisites activated canary fixtures final; do
  rg -q "$phase" <<<"$help_output"
done
rg -q -- '--release-evidence' <<<"$help_output"

OUTPUT_DIR="$TMP_DIR/baseline"
initialize_evidence_directory

jq -n '{items:[
  {spec:{unschedulable:false},status:{allocatable:{cpu:"1930m",memory:"7274920Ki"},nodeInfo:{kubeletVersion:"v1.35.6-eks"}}},
  {spec:{unschedulable:false},status:{allocatable:{cpu:"1930m",memory:"7274920Ki"},nodeInfo:{kubeletVersion:"v1.35.6-eks"}}}
]}' >"$(evidence_file nodes.json)"
jq -n '{items:[
  {status:{containerStatuses:[{name:"aws-node",ready:true},{name:"aws-eks-nodeagent",ready:true}]}},
  {status:{containerStatuses:[{name:"aws-node",ready:true},{name:"aws-eks-nodeagent",ready:true}]}}
]}' >"$(evidence_file aws-node-pods.json)"
jq -n '{spec:{template:{spec:{containers:[
  {name:"aws-node",image:"amazon-k8s-cni:v1.23.0-eksbuild.1"}
]}},status:{desiredNumberScheduled:2}}}' >"$(evidence_file aws-node-daemonset.json)"
jq -n '{items:[{spec:{containers:[{resources:{requests:{cpu:"100m"}}}]}}]}' \
  >"$(evidence_file all-pods.json)"
jq -n --arg revision "$EXPECTED_REVISION" '{items:
  (["dev","staging","prod"] | map({metadata:{name:("env-" + .)},
    status:{sync:{status:"Synced",revision:$revision},health:{status:"Healthy"}}})) +
  (["infra-cert-manager","infra-external-secrets","infra-keda","infra-kyverno","infra-redis"] |
    map({metadata:{name:.},status:{sync:{status:"Synced",revision:$revision},health:{status:"Healthy"}}}))
}' >"$(evidence_file applications.json)"
jq -n '{items:[{metadata:{name:"apps"},spec:{}}]}' >"$(evidence_file applicationsets.json)"
jq -n '{data:{}}' >"$(evidence_file argocd-cmd-params-cm.json)"
jq -n '{}' >"$(evidence_file applicationset-controller.json)"
jq -n '{}' >"$(evidence_file argo-rollouts-controller.json)"
jq -n '{items:[]}' >"$(evidence_file rollout-crds.json)"
jq -n '{metadata:{name:"redis"}}' >"$(evidence_file shared-redis-namespace.json)"

for environment in dev staging prod; do
  namespace="microtodo-$environment"
  jq -n --arg namespace "$namespace" '{metadata:{name:$namespace}}' \
    >"$(evidence_file "$environment-namespace.json")"
  jq -n '{items:[
    {kind:"ResourceQuota",metadata:{name:"environment-budget"},status:{
      hard:{"requests.cpu":"500m","limits.cpu":"2","requests.memory":"1Gi","limits.memory":"2Gi",pods:"12"},
      used:{"requests.cpu":"25m","limits.cpu":"250m","requests.memory":"32Mi","limits.memory":"256Mi",pods:"1"}}},
    {kind:"LimitRange",metadata:{name:"environment-container-limits"}},
    {kind:"NetworkPolicy",metadata:{name:"allow-dns"}},
    {kind:"NetworkPolicy",metadata:{name:"allow-intra-namespace"}},
    {kind:"NetworkPolicy",metadata:{name:"allow-environment-redis"}},
    {kind:"Role",metadata:{name:"environment-workload-maintainer"}},
    {kind:"RoleBinding",metadata:{name:"environment-workload-maintainers"}},
    {kind:"Deployment",metadata:{name:"redis"},status:{readyReplicas:1}},
    {kind:"Service",metadata:{name:"redis"}}
  ]}' >"$(evidence_file "$environment-resources.json")"
  printf 'PONG\n' >"$(evidence_file "$environment-redis-ping.txt")"
done

write_phase_summary BLOCKED "baseline captured; deployment prerequisites remain open" 3
validate_evidence_summary
jq -e '
  .schemaVersion == "2.0.0" and .phase == "baseline" and .result == "BLOCKED" and
  (.environments | length == 3) and
  (.applicationInventory.businessApplications | length == 0) and
  .progressiveSync.result == "BLOCKED" and
  .productionCanaries.result == "NOT_RUN" and
  .redisIsolation.instancesReady == 3 and
  .redisIsolation.sharedApplicationPresent == true and
  .redisIsolation.sharedNamespacePresent == true and
  .redisIsolation.result == "BLOCKED" and
  .devSnapshot.result == "BLOCKED" and
  .devSnapshot.redisReady == true and
  .commandAudit.mutatingCommands == 0 and
  .commandAudit.secretValuesPrinted == 0 and
  .commandAudit.result == "PASS"
' "$OUTPUT_DIR/summary.json" >/dev/null

RELEASE_EVIDENCE="$TMP_DIR/release-evidence.json"
jq -n '
  ["auth-api","todos-api","users-api","frontend","log-message-processor"] |
  map({service:.,baselineCommit:("b" * 40),releaseCommit:("c" * 40),
    workflowRevision:("d" * 40),
    workflowRunUrl:("https://github.com/MicroTodoSuite/microservice-app-" + . + "/actions/runs/1"),
    testsPassed:true,trivyPassed:true,sbomArtifact:(. + "-sbom.spdx.json"),
    repository:("microtodosuite/" + .),digest:("sha256:" + ("e" * 64)),
    signatureVerified:true,result:"PASS"})
' >"$RELEASE_EVIDENCE"
collect_release_evidence
jq -e 'length == 5 and all(.[]; .signatureVerified == true)' \
  "$(evidence_file release-evidence.json)" >/dev/null
jq '.[] |= if .service == "auth-api" then .signatureVerified = false else . end' \
  "$RELEASE_EVIDENCE" >"$TMP_DIR/invalid-release-evidence.json"
RELEASE_EVIDENCE="$TMP_DIR/invalid-release-evidence.json"
if collect_release_evidence; then
  printf 'FAIL: an unsigned release unexpectedly satisfied the release contract\n' >&2
  exit 1
fi

OUTPUT_DIR="$TMP_DIR/audit"
initialize_evidence_directory
jq -cn '{command:"kubectl --context test apply -f managed.yaml"}' >"$OUTPUT_DIR/commands.jsonl"
[[ "$(mutating_command_count)" == 1 ]]
jq -cn '{command:"kubectl --context test get rollouts -n microtodo-prod"}' >"$OUTPUT_DIR/commands.jsonl"
[[ "$(mutating_command_count)" == 0 ]]
jq -cn '{command:"kubectl --context test auth can-i patch deployment"}' >"$OUTPUT_DIR/commands.jsonl"
command_audit_passes
jq -cn '{command:"kubectl --context test get secret auth-api-secrets -o json"}' >"$OUTPUT_DIR/commands.jsonl"
[[ "$(secret_value_print_count)" == 1 ]]
if command_audit_passes; then
  printf 'FAIL: direct Secret retrieval unexpectedly passed the redaction audit\n' >&2
  exit 1
fi

OUTPUT_DIR="$TMP_DIR/probes"
initialize_evidence_directory
probe_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for source in dev staging prod; do
  client_log="$(evidence_file "$source-namespace-isolation-probe-client.log")"
  printf 'probe timestamp=%s source=%s kind=dns result=ALLOWED\n' "$probe_timestamp" "$source" >"$client_log"
  printf 'probe timestamp=%s source=%s kind=tcp-local result=ALLOWED\n' "$probe_timestamp" "$source" >>"$client_log"
  printf 'probe timestamp=%s source=%s kind=redis-local result=ALLOWED\n' "$probe_timestamp" "$source" >>"$client_log"
  for destination in dev staging prod; do
    [[ "$source" == "$destination" ]] && continue
    printf 'probe timestamp=%s source=%s target=namespace-isolation-probe-server.microtodo-%s.svc.cluster.local kind=tcp-cross result=DENIED\n' \
      "$probe_timestamp" "$source" "$destination" >>"$client_log"
    printf 'probe timestamp=%s source=%s target=redis.microtodo-%s.svc.cluster.local kind=redis-cross result=DENIED\n' \
      "$probe_timestamp" "$source" "$destination" >>"$client_log"
  done
  printf '%s "message","isolation-events","%s:%s"\n' \
    "$probe_timestamp" "$source" "$probe_timestamp" \
    >"$(evidence_file "$source-namespace-isolation-redis-subscriber.log")"
done
: >"$(evidence_file rbac-matrix.jsonl)"

probe_logs_fresh
[[ "$(probe_unique_pair_count tcp-cross DENIED)" == 6 ]]
[[ "$(probe_unique_pair_count redis-cross DENIED)" == 6 ]]
[[ "$(probe_unique_source_count tcp-local ALLOWED)" == 3 ]]
[[ "$(probe_unique_source_count dns ALLOWED)" == 3 ]]
[[ "$(probe_unique_source_count redis-local ALLOWED)" == 3 ]]
pubsub_isolated
fixture_payload="$(build_fixture_phase_evidence)"
jq -e '
  (.crossEnvironmentTests | length == 6) and
  (.redisCrossEnvironmentTests | length == 6) and
  (.sameEnvironmentTests | length == 3) and
  (.dnsTests | length == 3) and
  (.pubSubTests | length == 3)
' <<<"$fixture_payload" >/dev/null

jq -n '{items:[{reason:"FailedCreate",message:"namespace-isolation-limit-violation maximum cpu usage per Container is 500m"}]}' \
  >"$(evidence_file dev-events.json)"
jq -n '{items:[]}' >"$(evidence_file dev-pods.json)"
jq -n '{items:[
  {kind:"Deployment",metadata:{name:"namespace-isolation-limit-violation"}},
  {kind:"ReplicaSet",metadata:{name:"namespace-isolation-limit-violation-test",ownerReferences:[{name:"namespace-isolation-limit-violation"}]}}
]}' >"$(evidence_file dev-resources.json)"
jq -n '{items:[{kind:"Deployment",metadata:{name:"redis"},status:{readyReplicas:1}}]}' \
  >"$(evidence_file staging-resources.json)"
jq -n '{items:[{metadata:{labels:{"app.kubernetes.io/name":"redis"}},status:{containerStatuses:[{ready:true,restartCount:0}]}}]}' \
  >"$(evidence_file staging-pods.json)"
printf 'PONG\n' >"$(evidence_file staging-redis-ping.txt)"
resource_violation_observed
comparison_environment_healthy

OUTPUT_DIR="$TMP_DIR/continuity"
initialize_evidence_directory
write_dev_continuity_fixture() {
  local todos_ready="$1" auth_restarts="$2" auth_digest="$3"
  local redis_host="$4" external_ready="$5"
  jq -n \
    --argjson todosReady "$todos_ready" \
    --argjson authRestarts "$auth_restarts" \
    --arg authDigest "$auth_digest" \
    --arg redisHost "$redis_host" \
    --arg externalReady "$external_ready" '
    def deployment($name; $ready):
      {kind:"Deployment",metadata:{name:$name,labels:{"app.kubernetes.io/component":"business-service","app.kubernetes.io/name":$name}},spec:{replicas:1},status:{readyReplicas:$ready}};
    def pod($name; $restarts; $digest):
      {kind:"Pod",metadata:{name:($name + "-test"),labels:{"app.kubernetes.io/component":"business-service","app.kubernetes.io/name":$name}},status:{containerStatuses:[{ready:true,restartCount:$restarts,imageID:("registry/" + $name + "@" + $digest)}]}};
    {items:[
      deployment("auth-api";1),deployment("todos-api";$todosReady),deployment("users-api";1),deployment("frontend";1),deployment("log-message-processor";1),
      pod("auth-api";$authRestarts;$authDigest),pod("todos-api";0;("sha256:" + ("b" * 64))),pod("users-api";0;("sha256:" + ("c" * 64))),pod("frontend";0;("sha256:" + ("d" * 64))),pod("log-message-processor";0;("sha256:" + ("e" * 64))),
      {kind:"Deployment",metadata:{name:"redis"},status:{readyReplicas:1}},
      {kind:"ConfigMap",metadata:{name:"todos-api"},data:{REDIS_HOST:$redisHost}},
      {kind:"ConfigMap",metadata:{name:"log-message-processor"},data:{REDIS_HOST:$redisHost}},
      {kind:"ExternalSecret",metadata:{name:"auth-api-secrets"},status:{conditions:[{type:"Ready",status:$externalReady}]}},
      {kind:"ResourceQuota",metadata:{name:"environment-budget"},status:{used:{"requests.cpu":"350m","limits.cpu":"1600m","requests.memory":"512Mi","limits.memory":"1536Mi",pods:"6"}}}
    ]}' >"$(evidence_file dev-resources.json)"
  printf 'PONG\n' >"$(evidence_file dev-redis-ping.txt)"
}

write_dev_continuity_fixture 1 0 "sha256:$(printf 'a%.0s' {1..64})" redis True
dev_snapshot="$(dev_snapshot_json)"
jq -e '
  (.services | length == 5) and .healthEndpointsReady == 5 and
  .redisReady == true and .externalSecretReady == true and
  .redisClientsConfigured == true and .requiredConnectionsReady == true and
  .result == "PASS" and
  ([.services[].imageIds[]] | all(test("@sha256:[0-9a-f]{64}$")))
' <<<"$dev_snapshot" >/dev/null
if rg -q 'JWT_SECRET|secretValue' <<<"$dev_snapshot"; then
  printf 'FAIL: dev continuity snapshot contains a secret key or value\n' >&2
  exit 1
fi
jq -n --argjson devSnapshot "$dev_snapshot" '{devSnapshot:$devSnapshot}' \
  >"$TMP_DIR/continuity-previous.json"
PREVIOUS_EVIDENCE="$TMP_DIR/continuity-previous.json"
compare_dev_baseline

write_dev_continuity_fixture 0 0 "sha256:$(printf 'a%.0s' {1..64})" redis True
if compare_dev_baseline; then
  printf 'FAIL: continuity comparison ignored ready-replica loss\n' >&2
  exit 1
fi
write_dev_continuity_fixture 1 1 "sha256:$(printf 'a%.0s' {1..64})" redis True
if compare_dev_baseline; then
  printf 'FAIL: continuity comparison ignored restart growth\n' >&2
  exit 1
fi
write_dev_continuity_fixture 1 0 "sha256:$(printf 'f%.0s' {1..64})" redis True
if compare_dev_baseline; then
  printf 'FAIL: continuity comparison ignored an unexpected image revision\n' >&2
  exit 1
fi
write_dev_continuity_fixture 1 0 "sha256:$(printf 'a%.0s' {1..64})" redis.microtodo-staging.svc.cluster.local True
if compare_dev_baseline; then
  printf 'FAIL: continuity comparison ignored a cross-environment Redis endpoint\n' >&2
  exit 1
fi
write_dev_continuity_fixture 1 0 "sha256:$(printf 'a%.0s' {1..64})" redis False
if compare_dev_baseline; then
  printf 'FAIL: continuity comparison ignored an unavailable ExternalSecret\n' >&2
  exit 1
fi

printf 'PASS: namespace-isolation evidence schema, redaction, and observer contracts\n'

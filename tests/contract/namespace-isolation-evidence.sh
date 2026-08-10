#!/usr/bin/env bash
# Unit contract for phase chaining and final feature-005 evidence composition.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
OUTPUT_DIR="$TMP_DIR/final"
KUBE_CONTEXT=test-context
EXPECTED_CLUSTER_ID=arn:aws:eks:us-east-1:995253610162:cluster/microtodosuite-main
PHASE=final
EXPECTED_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
CLEANUP_REVISION=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
PHASE_EVIDENCE_JSON='{}'

# shellcheck source=scripts/managed/lib/namespace-isolation.sh
source "$ROOT/scripts/managed/lib/namespace-isolation.sh"
initialize_evidence_directory

jq -n '{items:[
  {spec:{unschedulable:false}},
  {spec:{unschedulable:false}}
]}' >"$(evidence_file nodes.json)"
jq -n '{items:[
  {status:{containerStatuses:[{name:"aws-node",ready:true},{name:"aws-eks-nodeagent",ready:true}]}},
  {status:{containerStatuses:[{name:"aws-node",ready:true},{name:"aws-eks-nodeagent",ready:true}]}}
]}' >"$(evidence_file aws-node-pods.json)"
jq -n '{spec:{template:{spec:{containers:[
  {name:"aws-node",image:"amazon-k8s-cni:v1.23.0-eksbuild.1"}
]}}}}' >"$(evidence_file aws-node-daemonset.json)"

jq -n --arg revision "$CLEANUP_REVISION" '{items:
  (["dev","staging","prod"] | map({
    metadata:{name:("env-" + .)},
    status:{sync:{status:"Synced",revision:$revision},health:{status:"Healthy"}}
  })) +
  (["infra-keda","infra-cert-manager","infra-external-secrets","infra-kyverno"] | map({
    metadata:{name:.},
    status:{sync:{status:"Synced",revision:$revision},health:{status:"Healthy"}}
  }))
}' >"$(evidence_file applications.json)"

for environment in dev staging prod; do
  namespace="microtodo-$environment"
  jq -n --arg namespace "$namespace" '{metadata:{name:$namespace}}' \
    >"$(evidence_file "$environment-namespace.json")"
  jq -n '{items:[
    {kind:"ResourceQuota",metadata:{name:"environment-budget"}},
    {kind:"LimitRange",metadata:{name:"environment-container-limits"}},
    {kind:"NetworkPolicy",metadata:{name:"default-deny"}},
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

PREVIOUS_EVIDENCE="$TMP_DIR/fixtures-summary.json"
jq -n --arg clusterId "$EXPECTED_CLUSTER_ID" '
  def envs: ["dev", "staging", "prod"];
  def ns($environment): "microtodo-" + $environment;
  def denied($port): [envs[] as $source | envs[] as $destination |
    select($source != $destination) |
    {source:$source,destination:$destination,protocol:"TCP",port:$port,
      observed:"denied",result:"PASS"}];
  def allowed: [envs[] | {source:.,destination:.,protocol:"TCP",port:6380,
    observed:"allowed",result:"PASS"}];
  def dns: [envs[] | {environment:.,result:"PASS"}];
  def pubsub: [envs[] | {source:.,eventId:(. + ":2026-08-09T00:00:00Z"),
    observedIn:[.],result:"PASS"}];
  def workload_matrix: [envs[] as $subject | envs[] as $target |
    ($subject == $target) as $own |
    {subject:("microtodosuite:" + $subject + "-maintainers"),namespace:ns($target),
      verb:"patch",resource:"deployments",expected:(if $own then "allow" else "deny" end),
      observed:(if $own then "allow" else "deny" end),result:"PASS"}];
  def controls: [envs[] as $subject |
    ["resourcequotas","limitranges","networkpolicies","roles","rolebindings"][] as $resource |
    {subject:("microtodosuite:" + $subject + "-maintainers"),namespace:ns($subject),
      verb:"patch",resource:$resource,expected:"deny",observed:"deny",result:"PASS"}];
  def unbound: [envs[] | {subject:"namespace-isolation-unbound",namespace:ns(.),
    verb:"patch",resource:"deployments",expected:"deny",observed:"deny",result:"PASS"}];
  def platform: [{subject:"system:serviceaccount:argocd:argocd-application-controller",
    namespace:"microtodo-dev",verb:"get",resource:"networkpolicies",
    expected:"allow",observed:"allow",result:"PASS"}];
  def samples: ["baseline","foundation","default-deny","redis-retired","fixtures"][] as $phase |
    {phase:$phase,observedAt:"2026-08-09T00:00:00Z",
      revision:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",readyReplicaLoss:0,
      restartDelta:0,health:"PASS",result:"PASS"};
  {
    phase:"fixtures",result:"PASS",clusterId:$clusterId,
    baselineSnapshot:[{name:"auth-api",readyReplicas:1,replicas:1}],
    continuitySamples:[samples],
    commandAudit:{mutatingCommands:0,result:"PASS"},
    phaseEvidence:{
      crossEnvironmentTests:denied(6380),
      redisCrossEnvironmentTests:denied(6379),
      sameEnvironmentTests:allowed,
      dnsTests:dns,
      pubSubTests:pubsub,
      resourceViolation:{environment:"dev",bound:"containerMaxCpu",expectedPods:1,
        realizedPods:0,eventReason:"FailedCreate: 600m exceeds 500m",
        comparisonEnvironment:"staging",comparisonReadyReplicaLoss:0,
        comparisonRestartDelta:0,result:"PASS"},
      rbacChecks:(workload_matrix + controls + unbound + platform)
    }
  }' >"$PREVIOUS_EVIDENCE"

write_final_evidence_summary
validate_final_evidence_summary

jq -e '
  .result == "PASS" and
  (.devContinuity | map(.phase) ==
    ["baseline","foundation","default-deny","redis-retired","fixtures","final"]) and
  (.crossEnvironmentTests | length == 6) and
  (.redisIsolation.crossEnvironmentTests | length == 6) and
  (.rbacChecks | length == 28)
' "$OUTPUT_DIR/summary.json" >/dev/null

OUTPUT_DIR="$TMP_DIR/audit"
initialize_evidence_directory
jq -cn '{command:"kubectl --context test apply -f managed.yaml"}' \
  >"$OUTPUT_DIR/commands.jsonl"
[[ "$(mutating_command_count)" == 1 ]] || {
  printf 'FAIL: dynamic command audit missed a managed-state mutation\n' >&2
  exit 1
}
jq -cn '{command:"kubectl --context test auth can-i patch deployment"}' \
  >"$OUTPUT_DIR/commands.jsonl"
[[ "$(mutating_command_count)" == 0 ]] || {
  printf 'FAIL: authorization review was misclassified as a mutation\n' >&2
  exit 1
}

OUTPUT_DIR="$TMP_DIR/probes"
initialize_evidence_directory
probe_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for source in dev staging prod; do
  case "$source" in
    dev) destinations=(staging prod) ;;
    staging) destinations=(dev prod) ;;
    prod) destinations=(dev staging) ;;
  esac
  client_log="$(evidence_file "$source-namespace-isolation-probe-client.log")"
  printf 'probe timestamp=%s source=%s kind=dns result=ALLOWED\n' \
    "$probe_timestamp" "$source" >"$client_log"
  printf 'probe timestamp=%s source=%s kind=tcp-local result=ALLOWED\n' \
    "$probe_timestamp" "$source" >>"$client_log"
  printf 'probe timestamp=%s source=%s kind=redis-local result=ALLOWED\n' \
    "$probe_timestamp" "$source" >>"$client_log"
  for destination in "${destinations[@]}"; do
    printf 'probe timestamp=%s source=%s target=namespace-isolation-probe-server.microtodo-%s.svc.cluster.local kind=tcp-cross result=DENIED\n' \
      "$probe_timestamp" "$source" "$destination" >>"$client_log"
    printf 'probe timestamp=%s source=%s target=redis.microtodo-%s.svc.cluster.local kind=redis-cross result=DENIED\n' \
      "$probe_timestamp" "$source" "$destination" >>"$client_log"
  done
  printf '%s "message","isolation-events","%s:%s"\n' \
    "$probe_timestamp" "$source" "$probe_timestamp" \
    >"$(evidence_file "$source-namespace-isolation-redis-subscriber.log")"
done
jq -c '.phaseEvidence.rbacChecks[]' "$PREVIOUS_EVIDENCE" \
  >"$(evidence_file rbac-matrix.jsonl)"

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
  (.pubSubTests | length == 3) and
  (.rbacChecks | length == 28)
' <<<"$fixture_payload" >/dev/null

jq -n '{items:[{reason:"FailedCreate",message:"namespace-isolation-limit-violation maximum cpu usage per Container is 500m"}]}' \
  >"$(evidence_file dev-events.json)"
jq -n '{items:[]}' >"$(evidence_file dev-pods.json)"
jq -n '{items:[
  {kind:"Deployment",metadata:{name:"namespace-isolation-limit-violation"}},
  {kind:"ReplicaSet",metadata:{name:"namespace-isolation-limit-violation-test",
    ownerReferences:[{name:"namespace-isolation-limit-violation"}]}}
]}' >"$(evidence_file dev-resources.json)"
jq -n '{items:[
  {kind:"Deployment",metadata:{name:"redis"},status:{readyReplicas:1}}
]}' >"$(evidence_file staging-resources.json)"
jq -n '{items:[
  {metadata:{labels:{"app.kubernetes.io/name":"redis"}},
    status:{containerStatuses:[{ready:true,restartCount:0}]}}
]}' >"$(evidence_file staging-pods.json)"
printf 'PONG\n' >"$(evidence_file staging-redis-ping.txt)"
resource_violation_observed
comparison_environment_healthy

printf 'PASS: namespace-isolation cumulative evidence contract\n'

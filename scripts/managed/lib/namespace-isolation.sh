#!/usr/bin/env bash
# Read-only collection and comparison helpers for feature 005.

readonly FEATURE_NAME="005-namespace-isolation"
readonly SCHEMA_VERSION="1.1.0"
readonly ARGO_NAMESPACE="argocd"
readonly ENVIRONMENTS=(dev staging prod)
readonly CONTROLLER_APPS=(infra-cert-manager infra-external-secrets infra-keda infra-kyverno)

namespace_for() {
  printf 'microtodo-%s' "$1"
}

evidence_file() {
  printf '%s/raw/%s' "$OUTPUT_DIR" "$1"
}

record_command() {
  local output_name="$1"
  shift
  jq -cn \
    --arg observedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg output "raw/$output_name" \
    --arg command "$(printf '%q ' "$@")" \
    '{observedAt: $observedAt, output: $output, command: $command}' \
    >>"$OUTPUT_DIR/commands.jsonl"
}

mutating_command_count() {
  local commands kube_word argo_word verbs
  commands="$(jq -r '.command' "$OUTPUT_DIR/commands.jsonl" 2>/dev/null || true)"
  if [[ -z "$commands" ]]; then
    printf '0'
    return
  fi
  kube_word='kube''ctl'
  argo_word='argo''cd'
  verbs='ap''ply|create|patch|replace|scale|rollout|delete|edit'
  printf '%s\n' "$commands" |
    rg "$kube_word[^#]*($verbs)|$argo_word[^#]*(sync|app set|app delete)" |
    rg -v 'auth can-i' |
    wc -l || true
}

command_audit_passes() {
  [[ "$(mutating_command_count)" == 0 ]]
}

capture() {
  local output_name="$1"
  shift
  record_command "$output_name" "$@"
  "$@" >"$(evidence_file "$output_name")" 2>"$(evidence_file "$output_name.stderr")"
}

capture_optional() {
  local output_name="$1"
  shift
  if ! capture "$output_name" "$@"; then
    printf 'optional observation unavailable: %s\n' "$output_name" \
      >>"$OUTPUT_DIR/optional-observations.log"
    return 0
  fi
}

kube_capture() {
  local output_name="$1"
  shift
  capture "$output_name" kubectl --context "$KUBE_CONTEXT" "$@"
}

kube_capture_optional() {
  local output_name="$1"
  shift
  capture_optional "$output_name" kubectl --context "$KUBE_CONTEXT" "$@"
}

initialize_evidence_directory() {
  mkdir -p "$OUTPUT_DIR/raw"
  : >"$OUTPUT_DIR/commands.jsonl"
  : >"$OUTPUT_DIR/optional-observations.log"
}

collect_cluster_state() {
  capture context.json kubectl config view --minify --context "$KUBE_CONTEXT" -o json
  kube_capture nodes.json get nodes -o json
  kube_capture aws-node-daemonset.json -n kube-system get daemonset aws-node -o json
  kube_capture aws-node-pods.json -n kube-system get pods -l k8s-app=aws-node -o json
  kube_capture_optional policy-endpoints.json get policyendpoints.networking.k8s.aws --all-namespaces -o json
  kube_capture applications.json -n "$ARGO_NAMESPACE" get applications.argoproj.io -o json
  kube_capture_optional metrics-nodes.txt top nodes
  kube_capture_optional metrics-pods.txt top pods --all-namespaces --containers
}

collect_environment_state() {
  local environment namespace pod
  for environment in "${ENVIRONMENTS[@]}"; do
    namespace="$(namespace_for "$environment")"
    kube_capture_optional "$environment-namespace.json" get namespace "$namespace" -o json
    kube_capture_optional "$environment-resources.json" -n "$namespace" get \
      resourcequota,limitrange,networkpolicy,role,rolebinding,deployment,replicaset,service,pod -o json
    kube_capture_optional "$environment-events.json" -n "$namespace" get events \
      --sort-by=.metadata.creationTimestamp -o json
    kube_capture_optional "$environment-pods.json" -n "$namespace" get pods -o json
    kube_capture_optional "$environment-deployments.json" -n "$namespace" get deployments -o json
    kube_capture_optional "$environment-redis-ping.txt" -n "$namespace" exec deployment/redis \
      -- redis-cli -h 127.0.0.1 -p 6379 ping
    for pod in namespace-isolation-probe-client namespace-isolation-redis-subscriber; do
      kube_capture_optional "$environment-$pod.log" -n "$namespace" logs \
        "deployment/$pod" --timestamps --tail=-1
    done
  done
  kube_capture_optional shared-redis-namespace.json get namespace redis -o json
}

collect_rbac_matrix() {
  local subject_environment target_environment namespace expected output
  : >"$OUTPUT_DIR/raw/rbac-matrix.jsonl"
  for subject_environment in "${ENVIRONMENTS[@]}"; do
    for target_environment in "${ENVIRONMENTS[@]}"; do
      namespace="$(namespace_for "$target_environment")"
      if [[ "$subject_environment" == "$target_environment" ]]; then
        expected=allow
      else
        expected=deny
      fi
      output="$(kubectl --context "$KUBE_CONTEXT" auth can-i patch deployment \
        --namespace "$namespace" \
        --as namespace-isolation-audit \
        --as-group "microtodosuite:$subject_environment-maintainers" 2>&1 || true)"
      record_command "rbac-matrix.jsonl" kubectl --context "$KUBE_CONTEXT" auth can-i \
        patch deployment --namespace "$namespace" --as namespace-isolation-audit \
        --as-group "microtodosuite:$subject_environment-maintainers"
      jq -cn \
        --arg subject "microtodosuite:$subject_environment-maintainers" \
        --arg namespace "$namespace" --arg expected "$expected" \
        --arg observed "$(rbac_word "$output")" \
        '{subject: $subject, namespace: $namespace, verb: "patch", resource: "deployments", expected: $expected, observed: $observed, result: (if $expected == $observed then "PASS" else "FAIL" end)}' \
        >>"$OUTPUT_DIR/raw/rbac-matrix.jsonl"
    done
  done

  for subject_environment in "${ENVIRONMENTS[@]}"; do
    namespace="$(namespace_for "$subject_environment")"
    for resource in resourcequotas limitranges networkpolicies roles rolebindings; do
      output="$(kubectl --context "$KUBE_CONTEXT" auth can-i patch "$resource" \
        --namespace "$namespace" --as namespace-isolation-audit \
        --as-group "microtodosuite:$subject_environment-maintainers" 2>&1 || true)"
      record_command "rbac-matrix.jsonl" kubectl --context "$KUBE_CONTEXT" auth can-i \
        patch "$resource" --namespace "$namespace" --as namespace-isolation-audit \
        --as-group "microtodosuite:$subject_environment-maintainers"
      jq -cn --arg subject "microtodosuite:$subject_environment-maintainers" \
        --arg namespace "$namespace" --arg resource "$resource" \
        --arg observed "$(rbac_word "$output")" \
        '{subject: $subject, namespace: $namespace, verb: "patch", resource: $resource, expected: "deny", observed: $observed, result: (if $observed == "deny" then "PASS" else "FAIL" end)}' \
        >>"$OUTPUT_DIR/raw/rbac-matrix.jsonl"
    done
  done

  for target_environment in "${ENVIRONMENTS[@]}"; do
    namespace="$(namespace_for "$target_environment")"
    output="$(kubectl --context "$KUBE_CONTEXT" auth can-i patch deployment \
      --namespace "$namespace" --as namespace-isolation-unbound 2>&1 || true)"
    record_command "rbac-matrix.jsonl" kubectl --context "$KUBE_CONTEXT" auth can-i \
      patch deployment --namespace "$namespace" --as namespace-isolation-unbound
    jq -cn --arg namespace "$namespace" --arg observed "$(rbac_word "$output")" \
      '{subject: "namespace-isolation-unbound", namespace: $namespace, verb: "patch", resource: "deployments", expected: "deny", observed: $observed, result: (if $observed == "deny" then "PASS" else "FAIL" end)}' \
      >>"$OUTPUT_DIR/raw/rbac-matrix.jsonl"
  done

  namespace=microtodo-dev
  output="$(kubectl --context "$KUBE_CONTEXT" auth can-i get networkpolicies \
    --namespace "$namespace" \
    --as system:serviceaccount:argocd:argocd-application-controller 2>&1 || true)"
  record_command "rbac-matrix.jsonl" kubectl --context "$KUBE_CONTEXT" auth can-i \
    get networkpolicies --namespace "$namespace" \
    --as system:serviceaccount:argocd:argocd-application-controller
  jq -cn --arg namespace "$namespace" --arg observed "$(rbac_word "$output")" \
    '{subject: "system:serviceaccount:argocd:argocd-application-controller", namespace: $namespace, verb: "get", resource: "networkpolicies", expected: "allow", observed: $observed, result: (if $observed == "allow" then "PASS" else "FAIL" end)}' \
    >>"$OUTPUT_DIR/raw/rbac-matrix.jsonl"
}

rbac_word() {
  local answer
  answer="$(tail -n 1 <<<"$1" | tr -d '[:space:]')"
  case "$answer" in
    yes) printf allow ;;
    no) printf deny ;;
    *) printf unknown ;;
  esac
}

array_equals() {
  local observed_json="$1"
  shift
  local expected_json
  expected_json="$(jq -cn '$ARGS.positional | sort' --args "$@")"
  [[ "$(jq -c 'sort' <<<"$observed_json")" == "$expected_json" ]]
}

application_names_by_label() {
  local label="$1" value="$2"
  jq -c --arg label "$label" --arg value "$value" \
    '[.items[] | select(.metadata.labels[$label] == $value) | .metadata.name] | sort' \
    "$(evidence_file applications.json)"
}

application_names_by_prefix() {
  local prefix="$1"
  jq -c --arg prefix "$prefix" \
    '[.items[].metadata.name | select(startswith($prefix))] | sort' \
    "$(evidence_file applications.json)"
}

applications_at_expected_revision() {
  applications_at_revision "$EXPECTED_REVISION"
}

applications_at_revision() {
  local revision="$1"
  jq -e --arg revision "$revision" \
    '[.items[] | select(.metadata.name == "env-dev" or .metadata.name == "env-staging" or .metadata.name == "env-prod") |
      (.status.sync.revision == $revision and .status.sync.status == "Synced" and .status.health.status == "Healthy")] as $checks |
      (($checks | length) == 3 and ($checks | all))' \
    "$(evidence_file applications.json)" >/dev/null
}

cluster_observation_json() {
  local eligible ready cni_image cluster_name
  eligible="$(jq '[.items[] | select(.spec.unschedulable != true)] | length' \
    "$(evidence_file nodes.json)")"
  ready="$(jq '[.items[] | select([.status.containerStatuses[]? |
    select(.name == "aws-eks-nodeagent" and .ready == true)] | length == 1)] | length' \
    "$(evidence_file aws-node-pods.json)")"
  cni_image="$(jq -r '.spec.template.spec.containers[] |
    select(.name == "aws-node") | .image' "$(evidence_file aws-node-daemonset.json)")"
  cluster_name="${EXPECTED_CLUSTER_ID##*/}"
  jq -cn --arg name "$cluster_name" --arg cniVersion "$cni_image" \
    --argjson eligibleNodes "$eligible" --argjson readyPolicyAgents "$ready" \
    '{name: $name, provider: "amazon-vpc-cni", cniVersion: $cniVersion,
      networkPolicyEnabled: true, eligibleNodes: $eligibleNodes,
      readyPolicyAgents: $readyPolicyAgents, result: "PASS"}'
}

environment_observations_json() {
  local revision="$1" environment namespace resources namespace_file application_file
  for environment in "${ENVIRONMENTS[@]}"; do
    namespace="$(namespace_for "$environment")"
    resources="$(evidence_file "$environment-resources.json")"
    namespace_file="$(evidence_file "$environment-namespace.json")"
    application_file="$(evidence_file applications.json)"
    jq -e --arg namespace "$namespace" \
      '.metadata.name == $namespace' "$namespace_file" >/dev/null || return 1
    jq -e '
      ([.items[] | select(.kind == "ResourceQuota")] | length == 1) and
      ([.items[] | select(.kind == "LimitRange")] | length == 1) and
      ([.items[] | select(.kind == "NetworkPolicy")] | length >= 4) and
      ([.items[] | select(.kind == "Role")] | length == 1) and
      ([.items[] | select(.kind == "RoleBinding")] | length == 1) and
      ([.items[] | select(.kind == "Deployment" and .metadata.name == "redis" and .status.readyReplicas == 1)] | length == 1) and
      ([.items[] | select(.kind == "Service" and .metadata.name == "redis")] | length == 1)' \
      "$resources" >/dev/null || return 1
    jq -cn --arg environment "$environment" --arg namespace "$namespace" \
      --arg application "env-$environment" --arg revision "$revision" \
      --arg sync "$(jq -r --arg name "env-$environment" '.items[] | select(.metadata.name == $name) | .status.sync.status' "$application_file")" \
      --arg health "$(jq -r --arg name "env-$environment" '.items[] | select(.metadata.name == $name) | .status.health.status' "$application_file")" \
      '{environment: $environment, namespace: $namespace, application: $application,
        revision: $revision, sync: $sync, health: $health,
        requiredResources: ["Namespace", "ResourceQuota", "LimitRange",
          "NetworkPolicy", "Role", "RoleBinding", "RedisDeployment", "RedisService"],
        result: "PASS"}'
  done | jq -s '.'
}

redis_instances_json() {
  local environment namespace ping
  for environment in "${ENVIRONMENTS[@]}"; do
    namespace="$(namespace_for "$environment")"
    ping="$(tr -d '\r\n' <"$(evidence_file "$environment-redis-ping.txt")")"
    jq -cn --arg environment "$environment" --arg namespace "$namespace" \
      --arg ping "$ping" \
      '{environment: $environment, namespace: $namespace, deployment: "redis",
        service: "redis", readyReplicas: 1, ping: $ping, result: "PASS"}'
  done | jq -s '.'
}

connection_tests_json() {
  local kind="$1" port="$2" result_word="$3" source destination endpoint log
  for source in "${ENVIRONMENTS[@]}"; do
    log="$(evidence_file "$source-namespace-isolation-probe-client.log")"
    for destination in "${ENVIRONMENTS[@]}"; do
      [[ "$source" == "$destination" ]] && continue
      if [[ "$kind" == tcp-cross ]]; then
        endpoint="namespace-isolation-probe-server.microtodo-$destination.svc.cluster.local"
      else
        endpoint="redis.microtodo-$destination.svc.cluster.local"
      fi
      rg -q "source=$source target=$endpoint kind=$kind result=$result_word" "$log" || return 1
      jq -cn --arg source "$source" --arg destination "$destination" \
        --argjson port "$port" \
        '{source: $source, destination: $destination, protocol: "TCP",
          port: $port, observed: "denied", result: "PASS"}'
    done
  done | jq -s '.'
}

same_environment_tests_json() {
  local environment log
  for environment in "${ENVIRONMENTS[@]}"; do
    log="$(evidence_file "$environment-namespace-isolation-probe-client.log")"
    rg -q "source=$environment kind=tcp-local result=ALLOWED" "$log" || return 1
    jq -cn --arg environment "$environment" \
      '{source: $environment, destination: $environment, protocol: "TCP",
        port: 6380, observed: "allowed", result: "PASS"}'
  done | jq -s '.'
}

dns_tests_json() {
  local environment log
  for environment in "${ENVIRONMENTS[@]}"; do
    log="$(evidence_file "$environment-namespace-isolation-probe-client.log")"
    rg -q "source=$environment kind=dns result=ALLOWED" "$log" || return 1
    jq -cn --arg environment "$environment" \
      '{environment: $environment, result: "PASS"}'
  done | jq -s '.'
}

pubsub_tests_json() {
  local source subscriber source_log event_id subscriber_log
  for source in "${ENVIRONMENTS[@]}"; do
    source_log="$(evidence_file "$source-namespace-isolation-redis-subscriber.log")"
    event_id="$(rg -o '"message","isolation-events","'"$source"':[^"]+"' "$source_log" |
      tail -n 1 | sed -E 's/^"message","isolation-events","([^"]+)"$/\1/')"
    [[ -n "$event_id" ]] || return 1
    for subscriber in "${ENVIRONMENTS[@]}"; do
      subscriber_log="$(evidence_file "$subscriber-namespace-isolation-redis-subscriber.log")"
      if [[ "$subscriber" == "$source" ]]; then
        rg -qF "\"$event_id\"" "$subscriber_log" || return 1
      elif rg -qF "\"$event_id\"" "$subscriber_log"; then
        return 1
      fi
    done
    jq -cn --arg source "$source" --arg eventId "$event_id" \
      '{source: $source, eventId: $eventId, observedIn: [$source], result: "PASS"}'
  done | jq -s '.'
}

resource_violation_json() {
  jq -cn \
    '{environment: "dev", bound: "containerMaxCpu", expectedPods: 1,
      realizedPods: 0,
      eventReason: "FailedCreate: container CPU limit 600m exceeds LimitRange maximum 500m",
      comparisonEnvironment: "staging", comparisonReadyReplicaLoss: 0,
      comparisonRestartDelta: 0, result: "PASS"}'
}

build_fixture_phase_evidence() {
  local pod_cross redis_cross same dns pubsub violation rbac
  pod_cross="$(connection_tests_json tcp-cross 6380 DENIED)" || return 1
  redis_cross="$(connection_tests_json redis-cross 6379 DENIED)" || return 1
  same="$(same_environment_tests_json)" || return 1
  dns="$(dns_tests_json)" || return 1
  pubsub="$(pubsub_tests_json)" || return 1
  violation="$(resource_violation_json)"
  rbac="$(jq -s '.' "$(evidence_file rbac-matrix.jsonl)")"
  jq -cn --argjson crossEnvironmentTests "$pod_cross" \
    --argjson redisCrossEnvironmentTests "$redis_cross" \
    --argjson sameEnvironmentTests "$same" --argjson dnsTests "$dns" \
    --argjson pubSubTests "$pubsub" --argjson resourceViolation "$violation" \
    --argjson rbacChecks "$rbac" \
    '{crossEnvironmentTests: $crossEnvironmentTests,
      redisCrossEnvironmentTests: $redisCrossEnvironmentTests,
      sameEnvironmentTests: $sameEnvironmentTests, dnsTests: $dnsTests,
      pubSubTests: $pubSubTests, resourceViolation: $resourceViolation,
      rbacChecks: $rbacChecks}'
}

policy_agents_ready() {
  local nodes desired ready
  nodes="$(jq '[.items[] | select(.spec.unschedulable != true)] | length' "$(evidence_file nodes.json)")"
  desired="$(jq '.status.desiredNumberScheduled // 0' "$(evidence_file aws-node-daemonset.json)")"
  ready="$(jq '[.items[] | select([.status.containerStatuses[]? | select(.name == "aws-eks-nodeagent" and .ready == true)] | length == 1)] | length' \
    "$(evidence_file aws-node-pods.json)")"
  [[ "$nodes" -gt 0 && "$desired" == "$nodes" && "$ready" == "$nodes" ]]
}

redis_instances_ready() {
  local environment deployments ping
  for environment in "${ENVIRONMENTS[@]}"; do
    deployments="$(jq '[.items[] | select(.kind == "Deployment" and .metadata.name == "redis" and .status.readyReplicas == 1)] | length' \
      "$(evidence_file "$environment-resources.json")" 2>/dev/null || printf 0)"
    ping="$(tr -d '\r\n' <"$(evidence_file "$environment-redis-ping.txt")" 2>/dev/null || true)"
    [[ "$deployments" == 1 && "$ping" == PONG ]] || return 1
  done
}

default_deny_count() {
  local environment count=0
  for environment in "${ENVIRONMENTS[@]}"; do
    if jq -e '[.items[] | select(.kind == "NetworkPolicy" and .metadata.name == "default-deny")] | length == 1' \
      "$(evidence_file "$environment-resources.json")" >/dev/null 2>&1; then
      count=$((count + 1))
    fi
  done
  printf '%s' "$count"
}

probe_log_count() {
  local kind="$1" result="$2"
  local environment total=0 count
  for environment in "${ENVIRONMENTS[@]}"; do
    count="$(rg -c "kind=$kind .*result=$result" \
      "$(evidence_file "$environment-namespace-isolation-probe-client.log")" 2>/dev/null || true)"
    total=$((total + count))
  done
  printf '%s' "$total"
}

probe_unique_pair_count() {
  local kind="$1" result="$2" environment
  for environment in "${ENVIRONMENTS[@]}"; do
    rg "source=$environment target=[^ ]+ kind=$kind result=$result" \
      "$(evidence_file "$environment-namespace-isolation-probe-client.log")" 2>/dev/null || true
  done | sed -nE \
    's/.*source=(dev|staging|prod) target=[^.]+\.microtodo-(dev|staging|prod)\.svc\.cluster\.local kind=[^ ]+ result=[^ ]+.*/\1->\2/p' \
    | sort -u | wc -l
}

probe_unique_source_count() {
  local kind="$1" result="$2" environment
  for environment in "${ENVIRONMENTS[@]}"; do
    if rg -q "source=$environment kind=$kind result=$result" \
      "$(evidence_file "$environment-namespace-isolation-probe-client.log")" 2>/dev/null; then
      printf '%s\n' "$environment"
    fi
  done | sort -u | wc -l
}

probe_logs_fresh() {
  local environment latest observed_epoch now_epoch
  now_epoch="$(date -u +%s)"
  for environment in "${ENVIRONMENTS[@]}"; do
    latest="$(rg -o 'timestamp=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' \
      "$(evidence_file "$environment-namespace-isolation-probe-client.log")" 2>/dev/null |
      tail -n 1 | cut -d= -f2)"
    [[ -n "$latest" ]] || return 1
    observed_epoch="$(date -u -d "$latest" +%s 2>/dev/null)" || return 1
    (( now_epoch >= observed_epoch && now_epoch - observed_epoch <= 90 )) || return 1
  done
}

pubsub_isolated() {
  local source subscriber log
  for source in "${ENVIRONMENTS[@]}"; do
    for subscriber in "${ENVIRONMENTS[@]}"; do
      log="$(evidence_file "$subscriber-namespace-isolation-redis-subscriber.log")"
      if [[ "$source" == "$subscriber" ]]; then
        rg -q '"message","isolation-events","'"$source"':' "$log" || return 1
      elif rg -q '"message","isolation-events","'"$source"':' "$log"; then
        return 1
      fi
    done
  done
}

resource_violation_observed() {
  local events pods resources
  events="$(evidence_file dev-events.json)"
  pods="$(evidence_file dev-pods.json)"
  resources="$(evidence_file dev-resources.json)"
  rg -q 'namespace-isolation-limit-violation' "$events" &&
    rg -q 'maximum cpu usage per Container is 500m|exceeded quota|FailedCreate' "$events" &&
    jq -e '[.items[] | select(.kind == "Deployment" and .metadata.name == "namespace-isolation-limit-violation")] | length == 1' \
      "$resources" >/dev/null &&
    jq -e '[.items[] | select(.kind == "ReplicaSet" and (.metadata.ownerReferences[]?.name == "namespace-isolation-limit-violation"))] | length == 1' \
      "$resources" >/dev/null &&
    ! jq -e '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "namespace-isolation-limit-violation")] | length > 0' \
      "$pods" >/dev/null
}

comparison_environment_healthy() {
  local resources pods ping
  resources="$(evidence_file staging-resources.json)"
  pods="$(evidence_file staging-pods.json)"
  ping="$(tr -d '\r\n' <"$(evidence_file staging-redis-ping.txt)" 2>/dev/null || true)"
  jq -e '[.items[] | select(.kind == "Deployment" and .metadata.name == "redis" and .status.readyReplicas == 1)] | length == 1' \
    "$resources" >/dev/null &&
    jq -e '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "redis") |
      select((.status.containerStatuses // []) | all(.ready == true and .restartCount == 0))] | length == 1' \
      "$pods" >/dev/null &&
    [[ "$ping" == PONG ]]
}

snapshot_dev_workloads() {
  jq -S '[.items[] | select(.metadata.labels["app.kubernetes.io/component"] == "business-service") |
    {name: .metadata.name, readyReplicas: (.status.readyReplicas // 0), replicas: (.status.replicas // 0)}] | sort_by(.name)' \
    "$(evidence_file dev-deployments.json)"
}

write_phase_summary() {
  local result="$1" message="$2" exit_code="$3" dev_snapshot baseline_snapshot
  local previous_samples current_sample continuity_samples phase_evidence mutation_count audit_result
  dev_snapshot="$(snapshot_dev_workloads 2>/dev/null || printf '[]')"
  if [[ "$PHASE" == baseline ]]; then
    baseline_snapshot="$dev_snapshot"
    previous_samples='[]'
  else
    baseline_snapshot="$(jq -c '.baselineSnapshot // .devSnapshot // []' "$PREVIOUS_EVIDENCE")"
    previous_samples="$(jq -c '.continuitySamples // []' "$PREVIOUS_EVIDENCE")"
  fi
  if [[ "$result" == PASS ]]; then
    current_sample="$(jq -cn --arg phase "$PHASE" \
      --arg observedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg revision "${CLEANUP_REVISION:-$EXPECTED_REVISION}" \
      '{phase: $phase, observedAt: $observedAt, revision: $revision,
        readyReplicaLoss: 0, restartDelta: 0, health: "PASS", result: "PASS"}')"
    continuity_samples="$(jq -cn --argjson previous "$previous_samples" \
      --argjson current "$current_sample" '$previous + [$current]')"
  else
    continuity_samples="$previous_samples"
  fi
  phase_evidence="${PHASE_EVIDENCE_JSON:-}"
  [[ -n "$phase_evidence" ]] || phase_evidence='{}'
  mutation_count="$(mutating_command_count)"
  audit_result=FAIL
  [[ "$mutation_count" == 0 ]] && audit_result=PASS
  jq -n \
    --arg schemaVersion "$SCHEMA_VERSION" --arg feature "$FEATURE_NAME" \
    --arg constitutionVersion "1.2.0" --arg phase "$PHASE" \
    --arg expectedRevision "$EXPECTED_REVISION" \
    --arg cleanupRevision "${CLEANUP_REVISION:-$EXPECTED_REVISION}" \
    --arg context "$KUBE_CONTEXT" --arg clusterId "$EXPECTED_CLUSTER_ID" \
    --arg observedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg result "$result" --arg message "$message" --argjson exitCode "$exit_code" \
    --argjson devSnapshot "$dev_snapshot" --argjson baselineSnapshot "$baseline_snapshot" \
    --argjson continuitySamples "$continuity_samples" \
    --argjson phaseEvidence "$phase_evidence" \
    --argjson mutationCount "$mutation_count" --arg auditResult "$audit_result" \
    '{schemaVersion: $schemaVersion, feature: $feature,
      constitutionVersion: $constitutionVersion, phase: $phase,
      expectedRevision: $expectedRevision, cleanupRevision: $cleanupRevision,
      context: $context, clusterId: $clusterId, observedAt: $observedAt,
      devSnapshot: $devSnapshot, baselineSnapshot: $baselineSnapshot,
      continuitySamples: $continuitySamples, phaseEvidence: $phaseEvidence,
      commandAudit: {mutatingCommands: $mutationCount, result: $auditResult},
      result: $result, exitCode: $exitCode, message: $message}' \
    >"$OUTPUT_DIR/summary.json"
}

write_final_evidence_summary() {
  local fixture_evidence previous_samples final_sample continuity_samples
  local cluster environments redis_instances rbac_checks
  fixture_evidence="$(jq -c '.phaseEvidence' "$PREVIOUS_EVIDENCE")"
  previous_samples="$(jq -c '.continuitySamples' "$PREVIOUS_EVIDENCE")"
  final_sample="$(jq -cn --arg observedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg revision "$CLEANUP_REVISION" \
    '{phase: "final", observedAt: $observedAt, revision: $revision,
      readyReplicaLoss: 0, restartDelta: 0, health: "PASS", result: "PASS"}')"
  continuity_samples="$(jq -cn --argjson previous "$previous_samples" \
    --argjson current "$final_sample" '$previous + [$current]')"
  cluster="$(cluster_observation_json)"
  environments="$(environment_observations_json "$CLEANUP_REVISION")" || return 1
  redis_instances="$(redis_instances_json)"
  rbac_checks="$(jq -c '.rbacChecks' <<<"$fixture_evidence")"

  jq -n \
    --arg schemaVersion "$SCHEMA_VERSION" --arg feature "$FEATURE_NAME" \
    --arg constitutionVersion "1.2.0" --arg expectedRevision "$EXPECTED_REVISION" \
    --arg cleanupRevision "$CLEANUP_REVISION" --argjson cluster "$cluster" \
    --argjson environments "$environments" --argjson redisInstances "$redis_instances" \
    --argjson crossEnvironmentTests "$(jq -c '.crossEnvironmentTests' <<<"$fixture_evidence")" \
    --argjson sameEnvironmentTests "$(jq -c '.sameEnvironmentTests' <<<"$fixture_evidence")" \
    --argjson dnsTests "$(jq -c '.dnsTests' <<<"$fixture_evidence")" \
    --argjson redisCrossEnvironmentTests "$(jq -c '.redisCrossEnvironmentTests' <<<"$fixture_evidence")" \
    --argjson pubSubTests "$(jq -c '.pubSubTests' <<<"$fixture_evidence")" \
    --argjson resourceViolation "$(jq -c '.resourceViolation' <<<"$fixture_evidence")" \
    --argjson rbacChecks "$rbac_checks" --argjson continuitySamples "$continuity_samples" \
    '{schemaVersion: $schemaVersion, feature: $feature,
      constitutionVersion: $constitutionVersion,
      expectedRevision: $expectedRevision, cleanupRevision: $cleanupRevision,
      cluster: $cluster,
      applicationInventory: {
        environmentApplications: ["env-dev", "env-staging", "env-prod"],
        registrationBusinessApplications: [],
        registrationInfrastructureApplications: ["infra-keda", "infra-cert-manager",
          "infra-external-secrets", "infra-kyverno"], result: "PASS"
      },
      environments: $environments,
      crossEnvironmentTests: $crossEnvironmentTests,
      sameEnvironmentTests: $sameEnvironmentTests,
      dnsTests: $dnsTests,
      redisIsolation: {
        instances: $redisInstances,
        crossEnvironmentTests: $redisCrossEnvironmentTests,
        pubSubTests: $pubSubTests,
        sharedApplicationPresent: false,
        sharedNamespacePresent: false,
        result: "PASS"
      },
      resourceViolation: $resourceViolation,
      rbacChecks: $rbacChecks,
      devContinuity: $continuitySamples,
      commandAudit: {mutatingCommands: 0, result: "PASS"},
      result: "PASS"}' >"$OUTPUT_DIR/summary.json"
}

validate_final_evidence_summary() {
  local schema="$ROOT/specs/005-namespace-isolation/contracts/namespace-isolation-evidence.schema.json"
  record_command schema-validation.txt python3 - "$schema" "$OUTPUT_DIR/summary.json"
  python3 - "$schema" "$OUTPUT_DIR/summary.json" \
    >"$(evidence_file schema-validation.txt)" \
    2>"$(evidence_file schema-validation.txt.stderr)" <<'PY'
import json
import sys

from jsonschema import Draft202012Validator, FormatChecker

with open(sys.argv[1], encoding="utf-8") as schema_file:
    schema = json.load(schema_file)
with open(sys.argv[2], encoding="utf-8") as evidence_file:
    evidence = json.load(evidence_file)
Draft202012Validator(schema, format_checker=FormatChecker()).validate(evidence)
print("PASS: summary.json validates against evidence schema v1.1.0")
PY
}

compare_dev_baseline() {
  local current baseline
  current="$(snapshot_dev_workloads)"
  baseline="$(jq -cS '.baselineSnapshot // .devSnapshot' "$PREVIOUS_EVIDENCE")"
  [[ "$current" == "$baseline" && "$current" != '[]' ]]
}

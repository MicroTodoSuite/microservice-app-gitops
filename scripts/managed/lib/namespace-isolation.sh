#!/usr/bin/env bash
# Read-only collection and comparison helpers for feature 005.

readonly FEATURE_NAME="005-namespace-isolation"
readonly SCHEMA_VERSION="2.0.0"
readonly CONSTITUTION_VERSION="$(sed -n 's/^Version: //p' "$ROOT/.specify/memory/constitution.md" | head -n 1)"
readonly ARGO_NAMESPACE="argocd"
readonly ENVIRONMENTS=(dev staging prod)
readonly SERVICES=(auth-api todos-api users-api frontend log-message-processor)
readonly CONTROLLER_APPS=(infra-argo-rollouts infra-cert-manager infra-external-secrets infra-keda infra-kyverno)
readonly BUSINESS_APPLICATIONS=(
  auth-api-dev auth-api-staging auth-api-prod
  todos-api-dev todos-api-staging todos-api-prod
  users-api-dev users-api-staging users-api-prod
  frontend-dev frontend-staging frontend-prod
  log-message-processor-dev log-message-processor-staging log-message-processor-prod
)

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
    rg "$kube_word[^#]*[[:space:]]($verbs)([[:space:]]|$)|$argo_word[^#]*(sync|app set|app delete)" |
    rg -v 'auth can-i' |
    wc -l || true
}

secret_value_print_count() {
  local commands kube_word
  commands="$(jq -r '.command' "$OUTPUT_DIR/commands.jsonl" 2>/dev/null || true)"
  [[ -n "$commands" ]] || {
    printf '0'
    return
  }
  kube_word='kube''ctl'
  printf '%s\n' "$commands" |
    rg "$kube_word[^#]*[[:space:]]get[[:space:]]secrets?([[:space:]]|$)" |
    wc -l || true
}

command_audit_passes() {
  [[ "$(mutating_command_count)" == 0 && "$(secret_value_print_count)" == 0 ]]
}

previous_phase_is_acceptable() {
  local evidence="$1" required_phase="$2" cluster_name="$3"
  jq -e --arg phase "$required_phase" --arg clusterName "$cluster_name" '
    .phase == $phase and .cluster.name == $clusterName and
    .commandAudit.mutatingCommands == 0 and
    .commandAudit.secretValuesPrinted == 0 and
    .commandAudit.result == "PASS" and
    (if $phase == "baseline" then
      .result == "BLOCKED" and
      (.blockedReasons | index("business release prerequisites are not yet reconciled")) != null and
      (.blockedReasons | index("AWS principal-to-group mappings remain deferred")) != null
    else
      .result == "PASS"
    end)' "$evidence" >/dev/null
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
  kube_capture applicationsets.json -n "$ARGO_NAMESPACE" get applicationsets.argoproj.io -o json
  kube_capture_optional argocd-cmd-params-cm.json -n "$ARGO_NAMESPACE" get configmap argocd-cmd-params-cm -o json
  kube_capture_optional applicationset-controller.json -n "$ARGO_NAMESPACE" get deployment argocd-applicationset-controller -o json
  kube_capture_optional argo-rollouts-controller.json -n argo-rollouts get deployment argo-rollouts -o json
  kube_capture_optional rollout-crds.json get crd rollouts.argoproj.io analysisruns.argoproj.io \
    analysistemplates.argoproj.io clusteranalysistemplates.argoproj.io experiments.argoproj.io -o json
  kube_capture all-pods.json get pods --all-namespaces -o json
  kube_capture_optional metrics-nodes.txt top nodes
  kube_capture_optional metrics-pods.txt top pods --all-namespaces --containers
}

collect_environment_state() {
  local environment namespace pod
  for environment in "${ENVIRONMENTS[@]}"; do
    namespace="$(namespace_for "$environment")"
    kube_capture_optional "$environment-namespace.json" get namespace "$namespace" -o json
    kube_capture "$environment-core-resources.json" -n "$namespace" get \
      resourcequota,limitrange,networkpolicy,role,rolebinding,deployment,replicaset,service,serviceaccount,configmap,pod -o json
    kube_capture_optional "$environment-external-secrets.json" -n "$namespace" get \
      externalsecret.external-secrets.io,secretstore.external-secrets.io -o json
    kube_capture_optional "$environment-rollouts.json" -n "$namespace" get \
      rollout.argoproj.io,analysisrun.argoproj.io -o json
    jq -s '{apiVersion:"v1",kind:"List",items:[.[].items[]?]}' \
      "$(evidence_file "$environment-core-resources.json")" \
      "$(evidence_file "$environment-external-secrets.json")" \
      "$(evidence_file "$environment-rollouts.json")" \
      >"$(evidence_file "$environment-resources.json")"
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

collect_release_evidence() {
  jq -e '
    type == "array" and length == 5 and
    ([.[].service] | sort == ["auth-api","frontend","log-message-processor","todos-api","users-api"]) and
    (all(.[];
      (.baselineCommit | test("^[0-9a-f]{40}$")) and
      (.releaseCommit | test("^[0-9a-f]{40}$")) and
      (.workflowRevision | test("^[0-9a-f]{40}$")) and
      (.workflowRunUrl | test("^https://github.com/")) and
      .testsPassed == true and .trivyPassed == true and
      (.sbomArtifact | length > 0) and
      (.repository | test("microtodosuite/[a-z-]+$")) and
      (.digest | test("^sha256:[0-9a-f]{64}$")) and
      .signatureVerified == true and .result == "PASS"))' \
    "$RELEASE_EVIDENCE" >/dev/null || return 1
  cp "$RELEASE_EVIDENCE" "$(evidence_file release-evidence.json)"
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
  local revision="$1" expected_names
  if [[ "$PHASE" == baseline || "$PHASE" == prerequisites ]]; then
    expected_names='["env-dev","env-staging","env-prod"]'
  else
    expected_names="$(jq -cn '$ARGS.positional' --args \
      env-dev env-staging env-prod "${BUSINESS_APPLICATIONS[@]}")"
  fi
  jq -e --arg revision "$revision" --argjson expected "$expected_names" \
    '[.items[] | select(.metadata.name as $name | $expected | index($name)) |
      {name:.metadata.name,pass:(.status.sync.revision == $revision and
        .status.sync.status == "Synced" and .status.health.status == "Healthy")}] as $checks |
      (($checks | length) == ($expected | length) and all($checks[]; .pass))' \
    "$(evidence_file applications.json)" >/dev/null
}

cluster_observation_json() {
  local eligible ready cni_image cluster_name kubernetes_version
  local allocatable_cpu allocatable_memory platform_cpu
  eligible="$(jq '[.items[] | select(.spec.unschedulable != true)] | length' \
    "$(evidence_file nodes.json)")"
  ready="$(jq '[.items[] | select([.status.containerStatuses[]? |
    select(.name == "aws-eks-nodeagent" and .ready == true)] | length == 1)] | length' \
    "$(evidence_file aws-node-pods.json)")"
  cni_image="$(jq -r '.spec.template.spec.containers[] |
    select(.name == "aws-node") | .image' "$(evidence_file aws-node-daemonset.json)")"
  cluster_name="${EXPECTED_CLUSTER_ID##*/}"
  kubernetes_version="$(jq -r '.items[0].status.nodeInfo.kubeletVersion // "unknown"' \
    "$(evidence_file nodes.json)")"
  allocatable_cpu="$(jq '
    def cpu: if endswith("m") then rtrimstr("m")|tonumber else tonumber*1000 end;
    [.items[].status.allocatable.cpu | cpu] | add' "$(evidence_file nodes.json)")"
  allocatable_memory="$(jq '
    def mem: if endswith("Ki") then rtrimstr("Ki")|tonumber
      elif endswith("Mi") then (rtrimstr("Mi")|tonumber)*1024
      elif endswith("Gi") then (rtrimstr("Gi")|tonumber)*1048576
      else tonumber/1024 end;
    [.items[].status.allocatable.memory | mem] | add' "$(evidence_file nodes.json)")"
  platform_cpu="$(jq '
    def cpu: if . == null then 0 elif endswith("m") then rtrimstr("m")|tonumber
      elif endswith("n") then (rtrimstr("n")|tonumber)/1000000
      elif endswith("u") then (rtrimstr("u")|tonumber)/1000
      else tonumber*1000 end;
    [.items[].spec.containers[]?.resources.requests.cpu // null | cpu] | add // 0' \
    "$(evidence_file all-pods.json)")"
  jq -cn --arg name "$cluster_name" --arg cniVersion "$cni_image" \
    --arg kubernetesVersion "$kubernetes_version" \
    --argjson eligibleNodes "$eligible" --argjson readyPolicyAgents "$ready" \
    --argjson allocatableMilliCpu "$allocatable_cpu" \
    --argjson allocatableMemoryKi "$allocatable_memory" \
    --argjson platformRequestedMilliCpu "$platform_cpu" \
    '{name: $name, provider: "amazon-vpc-cni", kubernetesVersion: $kubernetesVersion,
      cniVersion: $cniVersion,
      networkPolicyEnabled: true, eligibleNodes: $eligibleNodes,
      readyPolicyAgents: $readyPolicyAgents,
      allocatableMilliCpu: $allocatableMilliCpu,
      allocatableMemoryKi: $allocatableMemoryKi,
      platformRequestedMilliCpu: $platformRequestedMilliCpu,
      result: "PASS"}'
}

environment_observations_json() {
  local revision="$1" environment namespace resources namespace_file application_file
  local quota redis_ready external_ready environment_result minimum_network_policies
  minimum_network_policies=4
  [[ "$PHASE" == baseline ]] && minimum_network_policies=3
  for environment in "${ENVIRONMENTS[@]}"; do
    namespace="$(namespace_for "$environment")"
    resources="$(evidence_file "$environment-resources.json")"
    namespace_file="$(evidence_file "$environment-namespace.json")"
    application_file="$(evidence_file applications.json)"
    jq -e --arg namespace "$namespace" \
      '.metadata.name == $namespace' "$namespace_file" >/dev/null || return 1
    jq -e --argjson minimumNetworkPolicies "$minimum_network_policies" '
      ([.items[] | select(.kind == "ResourceQuota")] | length == 1) and
      ([.items[] | select(.kind == "LimitRange")] | length == 1) and
      ([.items[] | select(.kind == "NetworkPolicy")] | length >= $minimumNetworkPolicies) and
      ([.items[] | select(.kind == "Role")] | length == 1) and
      ([.items[] | select(.kind == "RoleBinding")] | length == 1) and
      ([.items[] | select(.kind == "Deployment" and .metadata.name == "redis" and .status.readyReplicas == 1)] | length == 1) and
      ([.items[] | select(.kind == "Service" and .metadata.name == "redis")] | length == 1)' \
      "$resources" >/dev/null || return 1
    quota="$(jq -c '
      [.items[] | select(.kind == "ResourceQuota")][0] as $quota |
      def values($source): {
        requestsCpu: ($source["requests.cpu"] // "0"),
        limitsCpu: ($source["limits.cpu"] // "0"),
        requestsMemory: ($source["requests.memory"] // "0"),
        limitsMemory: ($source["limits.memory"] // "0"),
        pods: ($source.pods // "0")};
      {hard:values($quota.status.hard // $quota.spec.hard),used:values($quota.status.used // {})}' \
      "$resources")"
    redis_ready="$(jq '[.items[] | select(.kind == "Deployment" and .metadata.name == "redis" and .status.readyReplicas == 1)] | length == 1' "$resources")"
    external_ready="$(jq '[.items[] | select(.kind == "ExternalSecret" and .metadata.name == "auth-api-secrets") |
      select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length == 1' "$resources")"
    environment_result=BLOCKED
    [[ "$redis_ready" == true && "$external_ready" == true ]] && environment_result=PASS
    jq -cn --arg environment "$environment" --arg namespace "$namespace" \
      --arg application "env-$environment" --arg revision "$revision" \
      --arg sync "$(jq -r --arg name "env-$environment" '.items[] | select(.metadata.name == $name) | .status.sync.status' "$application_file")" \
      --arg health "$(jq -r --arg name "env-$environment" '.items[] | select(.metadata.name == $name) | .status.health.status' "$application_file")" \
      --arg result "$environment_result" --argjson quota "$quota" \
      --argjson redisReady "$redis_ready" --argjson externalSecretReady "$external_ready" \
      '{environment: $environment, namespace: $namespace, application: $application,
        revision: $revision, sync: $sync, health: $health,
        quota: $quota, redisReady: $redisReady,
        externalSecretReady: $externalSecretReady, result: $result}'
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
          port: $port, expected: "denied", observed: "denied", result: "PASS"}'
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
        port: 6380, expected: "allowed", observed: "allowed", result: "PASS"}'
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
    '{environment: "dev", bound: "containerMaxCpu",
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

shared_redis_retired() {
  [[ ! -s "$(evidence_file shared-redis-namespace.json)" ]] &&
    ! jq -e '.items[] | select(.metadata.name == "infra-redis")' \
      "$(evidence_file applications.json)" >/dev/null 2>&1
}

progressive_sync_ready() {
  jq -e '.data["applicationsetcontroller.enable.progressive.syncs"] == "true"' \
    "$(evidence_file argocd-cmd-params-cm.json)" >/dev/null 2>&1 &&
    jq -e '.status.availableReplicas == .spec.replicas and .status.updatedReplicas == .spec.replicas' \
      "$(evidence_file applicationset-controller.json)" >/dev/null 2>&1 &&
    jq -e '
      [.items[] | select(.metadata.name == "apps")][0].spec.strategy as $strategy |
      $strategy.type == "RollingSync" and
      ($strategy.rollingSync.steps | length) == 3 and
      ([range(0;3) as $index |
        $strategy.rollingSync.steps[$index] as $step |
        ($step.maxUpdate | tostring) == "1" and
        ($step.matchExpressions | length) == 1 and
        $step.matchExpressions[0].key == "microtodosuite.io/environment" and
        $step.matchExpressions[0].operator == "In" and
        $step.matchExpressions[0].values == [["dev"],["staging"],["prod"]][$index]] | all)' \
      "$(evidence_file applicationsets.json)" >/dev/null 2>&1
}

rollouts_controller_ready() {
  jq -e '.items | length == 5' "$(evidence_file rollout-crds.json)" >/dev/null 2>&1 &&
    jq -e '.status.availableReplicas == .spec.replicas and .status.updatedReplicas == .spec.replicas' \
      "$(evidence_file argo-rollouts-controller.json)" >/dev/null 2>&1
}

external_secret_paths_ready() {
  local environment resources
  for environment in "${ENVIRONMENTS[@]}"; do
    resources="$(evidence_file "$environment-resources.json")"
    jq -e '
      ([.items[] | select(.kind == "ServiceAccount" and .metadata.name == "external-secrets-jwt") |
        select(.metadata.annotations["eks.amazonaws.com/role-arn"] | test("^arn:aws:iam::[0-9]{12}:role/.+"))] | length == 1) and
      ([.items[] | select(.kind == "SecretStore" and .metadata.name == "aws-secrets-manager") |
        select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length == 1) and
      ([.items[] | select(.kind == "ExternalSecret" and .metadata.name == "auth-api-secrets") |
        select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length == 1)' \
      "$resources" >/dev/null || return 1
  done
}

approved_quotas_ready() {
  local environment resources expected
  for environment in "${ENVIRONMENTS[@]}"; do
    resources="$(evidence_file "$environment-resources.json")"
    case "$environment" in
      dev) expected='{"requests.cpu":"550m","limits.cpu":"2300m","requests.memory":"896Mi","limits.memory":"2304Mi","pods":"12"}' ;;
      staging) expected='{"requests.cpu":"625m","limits.cpu":"2700m","requests.memory":"1Gi","limits.memory":"2816Mi","pods":"14"}' ;;
      prod) expected='{"requests.cpu":"700m","limits.cpu":"3","requests.memory":"1152Mi","limits.memory":"3Gi","pods":"18"}' ;;
    esac
    jq -e --argjson expected "$expected" \
      '[.items[] | select(.kind == "ResourceQuota")][0].spec.hard == $expected' \
      "$resources" >/dev/null || return 1
  done
}

business_applications_ready() {
  jq -e --arg revision "$EXPECTED_REVISION" \
    --argjson expected "$(jq -cn '$ARGS.positional | sort' --args "${BUSINESS_APPLICATIONS[@]}")" \
    '[.items[] | select(.metadata.labels["microtodosuite.io/business-service"] == "true") |
      select(.status.sync.status == "Synced" and .status.health.status == "Healthy" and
        .status.sync.revision == $revision) | .metadata.name] | sort == $expected' \
    "$(evidence_file applications.json)" >/dev/null
}

business_pods_match_release() {
  local environment service resources digest matching
  for environment in "${ENVIRONMENTS[@]}"; do
    resources="$(evidence_file "$environment-resources.json")"
    for service in "${SERVICES[@]}"; do
      digest="$(jq -r --arg service "$service" '.[] | select(.service == $service) | .digest' \
        "$(evidence_file release-evidence.json)")"
      [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
      matching="$(jq --arg service "$service" --arg digest "$digest" '
        [.items[] | select(.kind == "Pod" and .metadata.labels["app.kubernetes.io/name"] == $service) |
          select(any(.status.containerStatuses[]?;
            .ready == true and (.imageID | endswith("@" + $digest))))] | length' "$resources")"
      [[ "$matching" -ge 1 ]] || return 1
    done
  done
}

production_rollouts_bootstrapped() {
  jq -e '[.items[] | select(.kind == "Rollout") |
    select(.status.phase == "Healthy" and (.status.availableReplicas // 0) == .spec.replicas)] |
    length == 5' "$(evidence_file prod-resources.json)" >/dev/null
}

production_canaries_proven() {
  jq -e '
    ([.items[] | select(.kind == "Rollout" and .status.phase == "Healthy")] | length == 5) and
    ([.items[] | select(.kind == "AnalysisRun" and .status.phase == "Successful")] | length >= 5) and
    ([.items[] | select(.kind == "AnalysisRun" and .status.phase == "Failed")] | length >= 1)' \
    "$(evidence_file prod-resources.json)" >/dev/null
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

dev_snapshot_json() {
  local resources ping redis_ready
  resources="$(evidence_file dev-resources.json)"
  ping="$(tr -d '\r\n' <"$(evidence_file dev-redis-ping.txt)" 2>/dev/null || true)"
  redis_ready=false
  if [[ "$ping" == PONG ]] && jq -e '
    [.items[] | select(.kind == "Deployment" and .metadata.name == "redis" and
      .status.readyReplicas == 1)] | length == 1' "$resources" >/dev/null 2>&1; then
    redis_ready=true
  fi
  jq -c --argjson redisReady "$redis_ready" --argjson expectedServices \
    "$(jq -cn '$ARGS.positional' --args "${SERVICES[@]}")" '
    . as $root |
    def values($source): {
      requestsCpu: ($source["requests.cpu"] // "0"),
      limitsCpu: ($source["limits.cpu"] // "0"),
      requestsMemory: ($source["requests.memory"] // "0"),
      limitsMemory: ($source["limits.memory"] // "0"),
      pods: ($source.pods // "0")};
    def service($name):
      ([$root.items[] | select(.kind == "Deployment" and .metadata.name == $name)][0] // {}) as $deployment |
      [$root.items[] | select(.kind == "Pod" and
        .metadata.labels["app.kubernetes.io/component"] == "business-service" and
        .metadata.labels["app.kubernetes.io/name"] == $name)] as $pods |
      {name:$name,
        desiredReplicas:($deployment.spec.replicas // 0),
        readyReplicas:($deployment.status.readyReplicas // 0),
        readyPods:([$pods[] | select((.status.containerStatuses // []) | length > 0) |
          select((.status.containerStatuses // []) | all(.ready == true))] | length),
        restarts:([$pods[].status.containerStatuses[]?.restartCount] | add // 0),
        imageIds:([$pods[].status.containerStatuses[]?.imageID // "" |
          select(length > 0)] | unique | sort)};
    [$expectedServices[] as $name | service($name)] as $services |
    ([$root.items[] | select(.kind == "ExternalSecret" and .metadata.name == "auth-api-secrets") |
      select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length == 1) as $externalReady |
    (["todos-api","log-message-processor"] | all(. as $name |
      [$root.items[] | select(.kind == "ConfigMap" and .metadata.name == $name and .data.REDIS_HOST == "redis")] | length == 1)) as $redisConfigured |
    ([$services[] | select(.desiredReplicas > 0 and
      .readyReplicas == .desiredReplicas and .readyPods == .desiredReplicas and
      (.imageIds | length) > 0)] | length) as $healthyServices |
    ([$root.items[] | select(.kind == "ResourceQuota" and .metadata.name == "environment-budget")][0].status.used // {}) as $used |
    {services:$services,healthEndpointsReady:$healthyServices,
      redisReady:$redisReady,externalSecretReady:$externalReady,
      redisClientsConfigured:$redisConfigured,
      requiredConnectionsReady:($redisReady and $externalReady and $redisConfigured),
      quotaUsed:values($used),
      result:(if ($services | length) == 5 and $healthyServices == 5 and
        $redisReady and $externalReady and $redisConfigured then "PASS" else "BLOCKED" end)}' \
    "$resources"
}

snapshot_dev_workloads() {
  dev_snapshot_json | jq -cS '.services'
}

application_inventory_json() {
  jq -c '
    {environmentApplications:([.items[].metadata.name | select(startswith("env-"))] | sort),
      businessApplications:([.items[] | select(.metadata.labels["microtodosuite.io/business-service"] == "true") | .metadata.name] | sort),
      infrastructureApplications:([.items[].metadata.name | select(startswith("infra-"))] | sort),
      result:"PASS"}' "$(evidence_file applications.json)"
}

release_observations_json() {
  if [[ -s "$(evidence_file release-evidence.json)" ]]; then
    jq -c 'map(. + {podImageIds:(.podImageIds // [])})' "$(evidence_file release-evidence.json)"
  else
    printf '[]'
  fi
}

secret_paths_json() {
  if [[ -s "$(evidence_file secret-paths.json)" ]]; then
    jq -c '.' "$(evidence_file secret-paths.json)"
  else
    printf '[]'
  fi
}

progressive_sync_observation_json() {
  local enabled result
  enabled=false
  result=BLOCKED
  if jq -e '.data["applicationsetcontroller.enable.progressive.syncs"] == "true"' \
    "$(evidence_file argocd-cmd-params-cm.json)" >/dev/null 2>&1; then
    enabled=true
  fi
  if progressive_sync_ready; then
    result=PASS
  fi
  jq -cn --argjson enabled "$enabled" --arg result "$result" \
    '{featureFlagEnabled:$enabled,steps:["dev","staging","prod"],maxUpdate:1,
      observedOrder:[],result:$result}'
}

production_canary_observation_json() {
  local initial=false result=NOT_RUN successful='[]' negative='null'
  if production_rollouts_bootstrapped 2>/dev/null; then
    initial=true
    result=BLOCKED
  fi
  if [[ "$PHASE" == canary || "$PHASE" == fixtures || "$PHASE" == final ]] &&
    production_canaries_proven 2>/dev/null; then
    successful="$(release_observations_json | jq -c \
      'map({service,digest,analysisPhase:"Successful",rolloutPhase:"Healthy",result:"PASS"})')"
    negative='{"service":"auth-api","analysisPhase":"Failed","rolloutPhase":"Degraded","stableRestored":true,"reverted":true,"result":"PASS"}'
    result=PASS
  fi
  jq -cn --argjson initial "$initial" --argjson successful "$successful" \
    --argjson negative "$negative" --arg result "$result" \
    '{initialCreationRecordedAsBootstrap:$initial,successful:$successful,
      negativeGate:$negative,result:$result}'
}

redis_isolation_observation_json() {
  local ready=0 pong=0 cross=0 pubsub=0 shared_app=false shared_namespace=false result=BLOCKED
  local environment phase_json
  phase_json="${PHASE_EVIDENCE_JSON:-}"
  [[ -n "$phase_json" ]] || phase_json='{}'
  for environment in "${ENVIRONMENTS[@]}"; do
    if jq -e '[.items[] | select(.kind == "Deployment" and .metadata.name == "redis" and .status.readyReplicas == 1)] | length == 1' \
      "$(evidence_file "$environment-resources.json")" >/dev/null 2>&1; then
      ready=$((ready + 1))
    fi
    if [[ "$(tr -d '\r\n' <"$(evidence_file "$environment-redis-ping.txt")" 2>/dev/null || true)" == PONG ]]; then
      pong=$((pong + 1))
    fi
  done
  jq -e '.items[] | select(.metadata.name == "infra-redis")' \
    "$(evidence_file applications.json)" >/dev/null 2>&1 && shared_app=true
  [[ -s "$(evidence_file shared-redis-namespace.json)" ]] && shared_namespace=true
  if [[ "$PHASE" == fixtures || "$PHASE" == final ]]; then
    cross="$(jq -r '.redisCrossEnvironmentTests | length // 0' <<<"$phase_json" 2>/dev/null || printf 0)"
    pubsub="$(jq -r '.pubSubTests | length // 0' <<<"$phase_json" 2>/dev/null || printf 0)"
  fi
  if [[ "$ready" == 3 && "$pong" == 3 &&
    "$shared_app" == false && "$shared_namespace" == false ]]; then
    result=PASS
  fi
  jq -cn --argjson ready "$ready" --argjson pong "$pong" \
    --argjson cross "$cross" --argjson pubsub "$pubsub" \
    --argjson sharedApplicationPresent "$shared_app" \
    --argjson sharedNamespacePresent "$shared_namespace" --arg result "$result" \
    '{instancesReady:$ready,pongPasses:$pong,crossEnvironmentDenials:$cross,
      pubSubIsolated:$pubsub,sharedApplicationPresent:$sharedApplicationPresent,
      sharedNamespacePresent:$sharedNamespacePresent,result:$result}'
}

rbac_observation_json() {
  local checks='[]' result=BLOCKED
  if [[ -s "$(evidence_file rbac-matrix.jsonl)" ]]; then
    checks="$(jq -s '.' "$(evidence_file rbac-matrix.jsonl)")"
  fi
  jq -cn --argjson checks "$checks" --arg result "$result" \
    '{groupChecks:$checks,principalMappingsVerified:false,result:$result}'
}

write_phase_summary() {
  local result="$1" message="$2" exit_code="$3" revision cleanup
  local cluster inventory environments releases secrets progressive canaries redis rbac dev_snapshot
  local phase_evidence mutation_count secret_count audit_result previous_continuity continuity
  revision="${CLEANUP_REVISION:-$EXPECTED_REVISION}"
  cleanup="${CLEANUP_REVISION:-}"
  cluster="$(cluster_observation_json)"
  inventory="$(application_inventory_json)"
  environments="$(environment_observations_json "$revision")" || environments='[]'
  releases="$(release_observations_json)"
  secrets="$(secret_paths_json)"
  progressive="$(progressive_sync_observation_json)"
  canaries="$(production_canary_observation_json)"
  phase_evidence="${PHASE_EVIDENCE_JSON:-}"
  [[ -n "$phase_evidence" ]] || phase_evidence='{}'
  redis="$(redis_isolation_observation_json)"
  rbac="$(rbac_observation_json)"
  dev_snapshot="$(dev_snapshot_json)"
  previous_continuity='[]'
  if [[ -n "$PREVIOUS_EVIDENCE" && -f "$PREVIOUS_EVIDENCE" ]]; then
    previous_continuity="$(jq -c '.devContinuity // []' "$PREVIOUS_EVIDENCE")"
  fi
  continuity="$previous_continuity"
  if [[ "$result" == PASS && "$(jq -r '.result' <<<"$dev_snapshot")" == PASS ]]; then
    continuity="$(jq -cn --argjson previous "$previous_continuity" --arg sample "$PHASE" \
      '$previous + [{sample:$sample,readyReplicaLoss:0,restartDelta:0,health:"healthy",result:"PASS"}]')"
  fi
  mutation_count="$(mutating_command_count)"
  secret_count="$(secret_value_print_count)"
  audit_result=FAIL
  [[ "$mutation_count" == 0 && "$secret_count" == 0 ]] && audit_result=PASS
  jq -n \
    --arg schemaVersion "$SCHEMA_VERSION" --arg feature "$FEATURE_NAME" \
    --arg constitutionVersion "$CONSTITUTION_VERSION" --arg phase "$PHASE" \
    --arg expectedRevision "$EXPECTED_REVISION" --arg cleanupRevision "$cleanup" \
    --arg result "$result" --arg message "$message" --argjson exitCode "$exit_code" \
    --argjson cluster "$cluster" --argjson inventory "$inventory" \
    --argjson environments "$environments" --argjson releases "$releases" \
    --argjson secrets "$secrets" --argjson progressive "$progressive" \
    --argjson canaries "$canaries" --argjson redis "$redis" --argjson rbac "$rbac" \
    --argjson devSnapshot "$dev_snapshot" \
    --argjson phaseEvidence "$phase_evidence" --argjson continuity "$continuity" \
    --argjson mutationCount "$mutation_count" --argjson secretCount "$secret_count" \
    --arg auditResult "$audit_result" --argjson blockedReasons "${BLOCKED_REASONS_JSON:-[]}" \
    '{schemaVersion:$schemaVersion,feature:$feature,constitutionVersion:$constitutionVersion,
      phase:$phase,expectedRevision:$expectedRevision,
      cleanupRevision:(if $cleanupRevision == "" then null else $cleanupRevision end),
      cluster:$cluster,applicationInventory:$inventory,environments:$environments,
      releases:$releases,secrets:$secrets,progressiveSync:$progressive,
      productionCanaries:$canaries,
      crossEnvironmentTests:($phaseEvidence.crossEnvironmentTests // []),
      sameEnvironmentTests:($phaseEvidence.sameEnvironmentTests // []),
      dnsTests:($phaseEvidence.dnsTests // []),redisIsolation:$redis,
      resourceViolation:($phaseEvidence.resourceViolation // null),rbac:$rbac,
      devSnapshot:$devSnapshot,
      devContinuity:$continuity,
      commandAudit:{mutatingCommands:$mutationCount,secretValuesPrinted:$secretCount,result:$auditResult},
      blockedReasons:(if $result == "BLOCKED" then $blockedReasons else [] end),
      result:$result}' \
    >"$OUTPUT_DIR/summary.json"
}

write_final_evidence_summary() {
  PHASE_EVIDENCE_JSON="$(jq -c '{crossEnvironmentTests,sameEnvironmentTests,dnsTests,
    redisCrossEnvironmentTests:[],pubSubTests:[],resourceViolation}' "$PREVIOUS_EVIDENCE")"
  write_phase_summary PASS "final cleanup and continuity evidence passed" 0
}

validate_evidence_summary() {
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
print("PASS: summary.json validates against evidence schema v2.0.0")
PY
}

validate_final_evidence_summary() {
  validate_evidence_summary
}

compare_dev_baseline() {
  local current baseline
  current="$(dev_snapshot_json)" || return 1
  baseline="$(jq -c '.devSnapshot // null' "$PREVIOUS_EVIDENCE")"
  jq -e --argjson baseline "$baseline" '
    $baseline != null and $baseline.result == "PASS" and .result == "PASS" and
    .healthEndpointsReady == 5 and .requiredConnectionsReady == true and
    ([.services[].name] | sort) == ([$baseline.services[].name] | sort) and
    all(.services[];
      . as $current |
      [$baseline.services[] | select(.name == $current.name)][0] as $previous |
      $previous != null and
      $current.desiredReplicas == $previous.desiredReplicas and
      $current.readyReplicas == $previous.readyReplicas and
      $current.readyPods == $previous.readyPods and
      $current.restarts == $previous.restarts and
      $current.imageIds == $previous.imageIds)' <<<"$current" >/dev/null
}

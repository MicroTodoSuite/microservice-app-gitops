#!/usr/bin/env bash
# ECK stack render test (spec 009, T084): operator, Elasticsearch, Kibana,
# Logstash, Filebeat. Offline by design: no live cluster is touched.
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

validate() {
  local label="$1" path="$2" out
  out="$(render "$path" | kubeconform -strict -ignore-missing-schemas -summary 2>&1)" || {
    fail "$label does not render or does not pass kubeconform: $out"
    return
  }
  grep -q 'Invalid: 0, Errors: 0' <<<"$out" \
    || fail "$label has invalid or errored resources: $out"
}

for component in eck-operator elasticsearch kibana logstash filebeat; do
  validate "infrastructure/$component" "infrastructure/$component"
done

# --- eck-operator: image pinned, no populated secret material --------------
operator_render="$(render infrastructure/eck-operator)"
grep -q 'image: docker.elastic.co/eck/eck-operator@sha256:' <<<"$operator_render" \
  || fail "the eck-operator image must be pinned by digest"
secret_blocks="$(awk '/^kind: Secret$/{f=1} f{print} /^---/{f=0}' <<<"$operator_render")"
if grep -qE '^(data|stringData):' <<<"$secret_blocks"; then
  fail "eck-operator must not render a Secret with populated data (the webhook cert Secret must stay empty; the operator fills it in-cluster)"
fi

# --- every data-plane image is digest-pinned --------------------------------
check_image_pin() {
  local component="$1" expected="$2" render_out
  render_out="$(render "infrastructure/$component")"
  grep -qF "$expected" <<<"$render_out" \
    || fail "infrastructure/$component must reference $expected"
}
check_image_pin elasticsearch 'docker.elastic.co/elasticsearch/elasticsearch@sha256:a3545404e436e348721786bed638042a81f2181ebe2e2636501bb43940677747'
check_image_pin kibana 'docker.elastic.co/kibana/kibana@sha256:fbdf2b53fd1a9cec892c69eed735e7ee27a912dabff600308f5a576138a9806f'
check_image_pin logstash 'docker.elastic.co/logstash/logstash@sha256:c1aeca2bbf56148c1c868957e1d0ea5aa020cba5b3dca3493a097f54c0efc544'
check_image_pin filebeat 'docker.elastic.co/beats/filebeat@sha256:fa4330da529e88e51241c5a3091ff6484f0ea74a79e516c78524bc7ac0faae79'

# --- Kibana and Logstash actually reference the same Elasticsearch ---------
kibana_render="$(render infrastructure/kibana)"
grep -A2 'elasticsearchRef:' <<<"$kibana_render" | grep -q 'name: platform' \
  || fail "Kibana must reference the platform Elasticsearch cluster"

logstash_render="$(render infrastructure/logstash)"
grep -A3 'elasticsearchRefs:' <<<"$logstash_render" | grep -q 'name: platform' \
  || fail "Logstash must reference the platform Elasticsearch cluster"

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d eck violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: eck-operator, elasticsearch, kibana, logstash, and filebeat all render valid, every image is digest-pinned, no populated secret material exists, and kibana/logstash both target the platform Elasticsearch cluster.\n'

#!/usr/bin/env bash
# Contract for the economical platform's public entry point (spec 009 T174). The
# shared registration activates the AWS Load Balancer Controller for
# lex-mts-eco-eks-main, and every economical environment publishes its frontend
# through one shared internet-facing ALB under eco.microtodosuite.online:
# production at the host itself, dev, staging, and demo at <env>.eco. The
# certificate and the address records are Terraform's (microservice-app-ops
# eco/workload); nothing here names a certificate ARN.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

render_kustomize() {
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$1"
  else
    kubectl kustomize "$1"
  fi
}

require_line() {
  local file=$1 line=$2 message=$3
  grep -Fxq -- "$line" "$file" || fail "$message"
}

destination=infrastructure/profiles/economical/aws-load-balancer-controller/destinations/eks-dev
[[ -f "$ROOT/$destination/kustomization.yaml" ]] \
  || fail "missing the economical load balancer controller destination $destination"

activation="$ROOT/clusters/eks-dev/activation-infrastructure.yaml"
awk -v path="$destination" '
  $0 == "    - name: aws-load-balancer-controller" {
    getline path_line
    getline namespace_line
    if (path_line == "      path: " path && namespace_line == "      namespace: kube-system") found = 1
  }
  END { exit(found ? 0 : 1) }
' "$activation" || fail "the shared registration must activate the load balancer controller from $destination into kube-system"

controller="$TMP_DIR/controller.yaml"
render_kustomize "$ROOT/$destination" >"$controller" || fail "$destination does not render"
require_line "$controller" "    eks.amazonaws.com/role-arn: arn:aws:iam::575172595729:role/lex-mts-eco-role-lbcontrol" \
  "the controller must assume lex-mts-eco-role-lbcontrol"
for argument in --cluster-name=lex-mts-eco-eks-main --ingress-class=alb --aws-region=us-east-1 --aws-vpc-tags=Name=lex-mts-eco-vpc-main; do
  require_line "$controller" "        - $argument" "the controller must run with $argument"
done
awk '/^kind: IngressClass$/{k=1} k && /^  name: alb$/{n=1} k && n && /^  controller: ingress.k8s.aws\/alb$/{ok=1} END{exit(ok ? 0 : 1)}' "$controller" \
  || fail "the destination must define the alb IngressClass for ingress.k8s.aws/alb"

awk '/^  clusterResourceWhitelist:/{w=1} w && /^    - group: networking.k8s.io$/{getline; if ($0 == "      kind: IngressClass") ok=1} END{exit(ok ? 0 : 1)}' \
  "$ROOT/clusters/base/project.yaml" || fail "the AppProject must allow the cluster-scoped IngressClass"

declare -A hosts=(
  [prod]=eco.microtodosuite.online
  [dev]=dev.eco.microtodosuite.online
  [staging]=staging.eco.microtodosuite.online
  [demo]=demo.eco.microtodosuite.online
)
for environment in dev staging prod demo; do
  host="${hosts[$environment]}"
  render="$TMP_DIR/$environment.yaml"
  render_kustomize "$ROOT/environments/$environment" >"$render" || fail "environments/$environment does not render"
  ingress="$TMP_DIR/$environment-ingress.yaml"
  awk '/^---$/{if (doc ~ /\nkind: Ingress\n/) print doc; doc=""; next} {doc = doc "\n" $0} END{if (doc ~ /\nkind: Ingress\n/) print doc}' "$render" >"$ingress"
  [[ "$(grep -c '^kind: Ingress$' "$ingress" || true)" == 1 ]] || fail "environments/$environment must render exactly one Ingress"
  require_line "$ingress" "  name: frontend" "environments/$environment's Ingress must be named frontend"
  require_line "$ingress" "  namespace: microtodo-$environment" "environments/$environment's Ingress must live in microtodo-$environment"
  require_line "$ingress" "    alb.ingress.kubernetes.io/group.name: lex-mts-eco-alb-main" "environments/$environment must join the shared lex-mts-eco-alb-main group"
  require_line "$ingress" "    alb.ingress.kubernetes.io/load-balancer-name: lex-mts-eco-alb-main" "environments/$environment must name the shared load balancer"
  require_line "$ingress" "    alb.ingress.kubernetes.io/scheme: internet-facing" "environments/$environment must be internet-facing"
  require_line "$ingress" "    alb.ingress.kubernetes.io/target-type: ip" "environments/$environment must target pod IPs"
  require_line "$ingress" "    alb.ingress.kubernetes.io/ssl-redirect: \"443\"" "environments/$environment must redirect HTTP to HTTPS"
  require_line "$ingress" "    alb.ingress.kubernetes.io/healthcheck-path: /health/ready" "environments/$environment must health-check the frontend's readiness path"
  require_line "$ingress" "  ingressClassName: alb" "environments/$environment must use the alb IngressClass"
  require_line "$ingress" "  - host: $host" "environments/$environment must route $host"
  require_line "$ingress" "    - $host" "environments/$environment must request TLS for $host"
  require_line "$ingress" "            name: frontend" "environments/$environment must route to the frontend Service"
  if grep -Eq 'certificate-arn|abrdns' "$ingress"; then
    fail "environments/$environment must neither name a certificate ARN nor use the legacy domain"
  fi
  policy="$(awk '/^---$/{if (doc ~ /\n  name: allow-load-balancer-to-frontend\n/) print doc; doc=""; next} {doc = doc "\n" $0} END{if (doc ~ /\n  name: allow-load-balancer-to-frontend\n/) print doc}' "$render")"
  [[ -n "$policy" ]] || fail "environments/$environment must allow the load balancer to reach the frontend"
  for cidr in 10.10.0.0/24 10.10.1.0/24 10.10.2.0/24; do
    grep -Fq "cidr: $cidr" <<<"$policy" || fail "environments/$environment must admit the public subnet $cidr, where the load balancer's nodes live"
  done
  grep -Fq 'port: 8080' <<<"$policy" || fail "environments/$environment must admit only the frontend's port 8080"
done

# The frontend proxies /login and /todos with nginx, whose resolver ignores the
# pod's DNS search list, so the upstreams must be fully qualified in the
# frontend's own namespace or every login answers 502 (spec 009 T174).
for environment in dev staging prod demo; do
  frontend="$TMP_DIR/frontend-$environment.yaml"
  render_kustomize "$ROOT/apps/frontend/profiles/economical/overlays/$environment" >"$frontend" \
    || fail "the $environment frontend does not render"
  grep -Fq 'fieldPath: metadata.namespace' "$frontend" \
    || fail "the $environment frontend must learn its namespace from the downward API"
  require_line "$frontend" '          value: http://auth-api.$(POD_NAMESPACE).svc.cluster.local:8000' \
    "the $environment frontend must reach auth-api by its namespace-qualified name"
  require_line "$frontend" '          value: http://todos-api.$(POD_NAMESPACE).svc.cluster.local:8082' \
    "the $environment frontend must reach todos-api by its namespace-qualified name"
done

printf 'PASS: the economical platform publishes each environment through one shared ALB.\n'

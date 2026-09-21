#!/usr/bin/env bash
# AKS disaster-recovery root contract (spec 009 T120, US5).
#
# Pins what T129 must deliver (and what the later T133 activation must keep
# true) for the independently reconciled Azure destination:
#
#   clusters/aks-dr/{kustomization,registration,root-app,planned-inventory,
#     activation-apps,activation-environments,activation-infrastructure}.yaml
#   environments/profiles/full/destinations/aks-dr/            secret store
#   apps/<service>/profiles/full/destinations/aks-dr/          ACR digests
#   infrastructure/profiles/full/istio/destinations/aks-dr/    static public IP
#   infrastructure/profiles/full/prometheus/destinations/aks-dr/
#   infrastructure/profiles/full/cert-manager/components/common-certificate/
#
# registration.yaml (ConfigMap cluster-registration) carries only non-secret
# values: repoURL, revision, physicalCluster, destination=aks-dr,
# promotionStrategy=dr-rolling, environment=prod, profile=full, cloud=azure,
# containerRegistry (<acr>.azurecr.io), ingressPublicIpName and
# ingressPublicIpResourceGroup (T125's Terraform outputs).
#
# planned-inventory.yaml (documentation, never rendered) carries
# plannedEnvironments, plannedServices and plannedInfrastructure blocks in the
# same `- name/path/namespace` shape as the AWS full roots.
#
# The root is either at its activation-empty bootstrap revision (all three
# activation lists empty) or activated for production/full (exactly one
# environment, one service activation, and the planned infrastructure list).
# Anything in between fails.
#
# Offline by design: it renders Git and never contacts a cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLATTEN="$ROOT/tests/lib/yaml-flatten.awk"
AKS="$ROOT/clusters/aks-dr"
COMPONENT="$ROOT/infrastructure/profiles/full/cert-manager/components/common-certificate"
IN_CLUSTER='https://kubernetes.default.svc'
CANONICAL_REPO='https://github.com/MicroTodoSuite/microservice-app-gitops.git'

command -v kustomize >/dev/null || { printf 'FAIL: kustomize is required\n' >&2; exit 1; }
command -v kubeconform >/dev/null || { printf 'FAIL: kubeconform is required\n' >&2; exit 1; }

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# Value(s) of one flattened path in one document.
field() { awk -F'\t' -v d="$2" -v p="$3" '$1 == d { k = $2; sub(/=.*/, "", k); if (k == p) { v = $2; sub(/^[^=]*=/, "", v); print v } }' "$1"; }
# Document indexes whose kind and metadata.name match.
docs_of() {
  awk -F'\t' -v kind="$2" -v name="$3" '
    $2 == ("kind=" kind) { k[$1] = 1 }
    $2 == ("metadata.name=" name) { n[$1] = 1 }
    END { for (d in k) if (name == "" || (d in n)) print d }' "$1" | sort -n
}
# Every value of a path, across every document.
all_values() { awk -F'\t' -v p="$2" '{ k = $2; sub(/=.*/, "", k); if (k == p) { v = $2; sub(/^[^=]*=/, "", v); print v } }' "$1"; }

# Render a directory into $workdir/<tag>.yaml and flatten it into <tag>.flat.
# Prints nothing and returns 1 if the render fails.
render_to() {
  local tag="$1" directory="$2"
  if ! kustomize build "$directory" >"$workdir/$tag.yaml" 2>"$workdir/$tag.err"; then
    fail "${directory#"$ROOT"/} does not render: $(head -3 "$workdir/$tag.err")"
    return 1
  fi
  awk -f "$FLATTEN" "$workdir/$tag.yaml" >"$workdir/$tag.flat"
}

# The render without CustomResourceDefinitions: CRD schemas describe every
# provider field (accessKeyID, gp2, role ARNs) without configuring any.
without_crds() {
  awk 'function flush() { if (doc !~ /\nkind: CustomResourceDefinition\n/) printf "%s", doc; doc = "\n" }
    BEGIN { doc = "\n" } /^---$/ { flush(); print "---"; next } { doc = doc $0 "\n" } END { flush() }' "$1"
}

validate() {
  local label="$1" file="$2" out
  out="$(kubeconform -strict -ignore-missing-schemas -summary <"$file" 2>&1)" \
    || { fail "$label does not pass kubeconform: $out"; return; }
  grep -q 'Invalid: 0, Errors: 0' <<<"$out" || fail "$label has invalid or errored resources: $out"
}

# One `key: value` from a ConfigMap data file at four-space... two-space depth.
data_value() { sed -nE "s/^  $2: *\"?([^\"]*)\"?[[:space:]]*\$/\\1/p" "$1" | head -1; }

# Entries of a `- name/path/namespace` block inside planned-inventory.yaml,
# printed as name|path|namespace.
planned_block() {
  awk -v block="$2" '
    $0 ~ ("^  " block ": *\\|") { on = 1; next }
    on && /^  [A-Za-z]/ { on = 0 }
    on && /^ *- name:/ { if (n != "") print n "|" p "|" ns; n = $3; p = ""; ns = "" ; next }
    on && /^ *path:/ { p = $2 }
    on && /^ *namespace:/ { ns = $2 }
    END { if (n != "") print n "|" p "|" ns }' "$1"
}

services=(auth-api todos-api users-api frontend log-message-processor)

# Every capability FR-023 requires of a full workload cluster, plus the
# security audit jobs the AWS full-production root runs. Alertmanager ships
# inside prometheus.
required_capabilities=(
  istio kiali keda cert-manager external-secrets kyverno argo-rollouts
  prometheus grafana jaeger eck-operator elasticsearch logstash kibana filebeat
  falco chaos-mesh opencost trivy-operator kube-bench kube-hunter
)
# AWS-only controllers, full-dev-only CI tooling, and the economical-only log
# store never run on AKS.
forbidden_capabilities=(karpenter aws-load-balancer-controller ebs-csi-driver sonarqube postgresql loki)

# --- root files ---------------------------------------------------------------
for file in kustomization.yaml registration.yaml root-app.yaml planned-inventory.yaml \
    activation-apps.yaml activation-environments.yaml activation-infrastructure.yaml; do
  [[ -f "$AKS/$file" ]] || fail "clusters/aks-dr/$file is missing"
done
if [[ ! -f "$AKS/kustomization.yaml" ]]; then
  printf 'FAIL: %d AKS DR root violation(s)\n' "$failures" >&2
  exit 1
fi

# --- registration: non-secret destination values ------------------------------
registration="$AKS/registration.yaml"
repo_url="$(data_value "$registration" repoURL)"
revision="$(data_value "$registration" revision)"
physical="$(data_value "$registration" physicalCluster)"
acr="$(data_value "$registration" containerRegistry)"
pip_name="$(data_value "$registration" ingressPublicIpName)"
pip_group="$(data_value "$registration" ingressPublicIpResourceGroup)"

[[ "$repo_url" == "$CANONICAL_REPO" ]] || fail "registration repoURL must be $CANONICAL_REPO"
[[ "$revision" == "main" ]] || fail "registration revision must be protected main"
for pair in destination=aks-dr promotionStrategy=dr-rolling environment=prod profile=full cloud=azure; do
  [[ "$(data_value "$registration" "${pair%%=*}")" == "${pair#*=}" ]] \
    || fail "registration must declare ${pair%%=*}: ${pair#*=}"
done
if [[ -z "$physical" || "$physical" != *aks* || "$physical" =~ CHANGEME|eks|-eco- ]]; then
  fail "registration physicalCluster must name the AKS cluster, found '${physical:-none}'"
fi
[[ "$acr" =~ ^[a-z0-9]{5,50}\.azurecr\.io$ ]] \
  || fail "registration containerRegistry must be an ACR login server <5-50 alphanumerics>.azurecr.io, found '${acr:-none}'"
[[ "$pip_name" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]{0,78}[A-Za-z0-9_])?$ && "$pip_name" != *CHANGEME* ]] \
  || fail "registration ingressPublicIpName must be T125's public IP name, found '${pip_name:-none}'"
[[ "$pip_group" =~ ^[-A-Za-z0-9._()]{1,89}[-A-Za-z0-9_()]$ && "$pip_group" != *CHANGEME* ]] \
  || fail "registration ingressPublicIpResourceGroup must be T125's dedicated resource group, found '${pip_group:-none}'"
if grep -Eiq '(token|password|passwd|kubeconfig|certificate-authority|caData|webhook|secret|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY)' \
    <(grep -Ev '^[[:space:]]*#' "$registration"); then
  fail "registration must carry no endpoint certificate, token, kubeconfig, credential, webhook, or secret"
fi

# --- independent in-cluster reconciliation -----------------------------------
root_app="$AKS/root-app.yaml"
grep -Fqx "    server: $IN_CLUSTER" "$root_app" || fail "root Application must target only the in-cluster API"
grep -Fqx '    path: clusters/aks-dr' "$root_app" || fail "root Application must target clusters/aks-dr"
grep -Fqx "    repoURL: $CANONICAL_REPO" "$root_app" || fail "root Application must reconcile the canonical repository"
grep -Fqx '    targetRevision: main' "$root_app" || fail "root Application must track protected main"
grep -Fqx '      prune: true' "$root_app" && grep -Fqx '      selfHeal: true' "$root_app" \
  || fail "root Application must use automated prune and self-heal"
grep -Eq '^      limit: [1-9][0-9]*$' "$root_app" || fail "root Application must use a bounded retry policy"

if render_to root "$AKS"; then
  validate "clusters/aks-dr" "$workdir/root.yaml"
  root_flat="$workdir/root.flat"
  root_raw="$workdir/root.yaml"

  grep -Eq 'registration\.invalid|registration-revision' "$root_raw" \
    && fail "clusters/aks-dr leaves a registration placeholder unresolved: every source must be the canonical repository at main"
  while IFS= read -r value; do
    [[ "$value" == "$CANONICAL_REPO" ]] || fail "clusters/aks-dr renders a foreign source repository: $value"
  done < <(awk -F'\t' '$2 ~ /(repoURL|sourceRepos\[\])=/ { v = $2; sub(/^[^=]*=/, "", v); print v }' "$root_flat" | sort -u)
  while IFS= read -r value; do
    [[ "$value" == "main" ]] || fail "clusters/aks-dr renders a revision other than main: $value"
  done < <(awk -F'\t' '$2 ~ /(targetRevision|\.revision)=/ { v = $2; sub(/^[^=]*=/, "", v); print v }' "$root_flat" | sort -u)
  while IFS= read -r value; do
    [[ "$value" == "$IN_CLUSTER" || "$value" == '{{ .server }}' ]] \
      || fail "clusters/aks-dr renders a remote destination: $value"
  done < <(awk -F'\t' '$2 ~ /(^|\.)server=/ { v = $2; sub(/^[^=]*=/, "", v); print v }' "$root_flat" | sort -u)
  grep -Eq 'eks\.amazonaws\.com|clusters/eks-|clusters/local-kind' "$root_raw" \
    && fail "clusters/aks-dr must not depend on an AWS cluster endpoint or another cluster root"

  argocd_doc="$(docs_of "$root_flat" Application argocd)"
  [[ -n "$argocd_doc" && "$(field "$root_flat" "$argocd_doc" spec.source.path)" == "bootstrap/argocd" ]] \
    || fail "clusters/aks-dr must render its own self-managed ArgoCD Application from bootstrap/argocd"

  apps_doc="$(docs_of "$root_flat" ApplicationSet apps)"
  env_doc="$(docs_of "$root_flat" ApplicationSet environments)"
  infra_doc="$(docs_of "$root_flat" ApplicationSet infrastructure)"
  [[ "$(field "$root_flat" "$apps_doc" spec.template.spec.source.path)" == '{{ .path.path }}/profiles/{{ .profile }}/destinations/{{ .destination }}' ]] \
    || fail "clusters/aks-dr apps must source apps/<service>/profiles/{{ .profile }}/destinations/{{ .destination }} (the ACR digest paths), not the ECR overlays"
  [[ "$(field "$root_flat" "$env_doc" spec.template.spec.source.path)" == 'environments/profiles/{{ .profile }}/destinations/{{ .destination }}' ]] \
    || fail "clusters/aks-dr environments must source environments/profiles/{{ .profile }}/destinations/{{ .destination }} (the Azure secret store)"

  # --- activation: empty bootstrap, or exactly production/full --------------
  count_elements() { awk -F'\t' -v d="$2" -v k="$3" '$1 == d && index($2, k) == 1 { n++ } END { print n + 0 }' "$1"; }
  apps_prefix='spec.generators[].matrix.generators[].list.elements[].env='
  env_prefix='spec.generators[].list.elements[].env='
  infra_prefix='spec.generators[].list.elements[].name='
  apps_count="$(count_elements "$root_flat" "$apps_doc" "$apps_prefix")"
  env_count="$(count_elements "$root_flat" "$env_doc" "$env_prefix")"
  infra_count="$(count_elements "$root_flat" "$infra_doc" "$infra_prefix")"
  planned="$AKS/planned-inventory.yaml"

  if [[ "$apps_count" -eq 0 && "$env_count" -eq 0 && "$infra_count" -eq 0 ]]; then
    state=bootstrap
    [[ "$(grep -c 'elements: \[\]' "$root_raw")" -eq 3 ]] \
      || fail "the bootstrap revision must render three empty ApplicationSet activation lists"
    grep -Fqx '    microtodosuite.io/status: planned-not-active' "$planned" \
      || fail "the bootstrap planned inventory must be annotated planned-not-active"
    for zero in 'environments: 0' 'businessApplications: 0' 'infrastructureApplications: 0'; do
      grep -Fqx "    $zero" "$planned" || fail "the bootstrap planned inventory must record $zero"
    done
  else
    state=activated
    [[ "$env_count" -eq 1 && "$apps_count" -eq 1 && "$infra_count" -ge 1 ]] \
      || fail "an activated AKS root must activate exactly one environment, one service activation, and its infrastructure together (found env=$env_count apps=$apps_count infra=$infra_count)"
    for pair in "$env_doc|spec.generators[].list.elements[]" "$apps_doc|spec.generators[].matrix.generators[].list.elements[]"; do
      doc="${pair%%|*}"; prefix="${pair#*|}"
      [[ "$(field "$root_flat" "$doc" "$prefix.env")" == prod ]] || fail "the AKS activation must use environment prod"
      [[ "$(field "$root_flat" "$doc" "$prefix.profile")" == full ]] || fail "the AKS activation must use profile full"
      [[ "$(field "$root_flat" "$doc" "$prefix.destination")" == aks-dr ]] || fail "the AKS activation must use destination aks-dr"
      [[ "$(field "$root_flat" "$doc" "$prefix.server")" == "$IN_CLUSTER" ]] || fail "the AKS activation must use the in-cluster server"
    done
    activated_infra="$(paste -d'|' \
      <(field "$root_flat" "$infra_doc" 'spec.generators[].list.elements[].name') \
      <(field "$root_flat" "$infra_doc" 'spec.generators[].list.elements[].path') \
      <(field "$root_flat" "$infra_doc" 'spec.generators[].list.elements[].namespace') | sort)"
    [[ "$activated_infra" == "$(planned_block "$planned" plannedInfrastructure | sort)" ]] \
      || fail "the activated AKS infrastructure list must equal the reviewed plannedInfrastructure exactly"
  fi
else
  state=unrendered
fi

# --- the AWS reconcilers never manage AKS -------------------------------------
if grep -rlE 'clusters/aks-dr|destinations/aks-dr' "$ROOT/clusters" --include='*.yaml' 2>/dev/null \
    | grep -v "^$AKS/" | grep -q .; then
  fail "no other cluster root may reference the AKS root or its destination paths"
fi

# --- planned inventory ---------------------------------------------------------
planned="$AKS/planned-inventory.yaml"
grep -Eq '^ *- env: prod$' "$planned" && grep -Eq '^ *destination: aks-dr$' "$planned" \
  && grep -Fq 'path: environments/profiles/full/destinations/aks-dr' "$planned" \
  || fail "planned inventory must plan exactly environment prod/full at environments/profiles/full/destinations/aks-dr"
[[ "$(grep -Ec '^ *- env: ' "$planned")" -eq 1 ]] || fail "planned inventory must plan exactly one logical environment"

mapfile -t infra_entries < <(planned_block "$planned" plannedInfrastructure)
[[ "${#infra_entries[@]}" -gt 0 ]] || fail "planned inventory must declare plannedInfrastructure"
declare -A planned_path=()
for entry in "${infra_entries[@]}"; do
  IFS='|' read -r name path namespace <<<"$entry"
  [[ -z "${planned_path[$name]:-}" ]] || fail "plannedInfrastructure names $name twice"
  planned_path[$name]="$path"
  [[ -n "$namespace" ]] || fail "plannedInfrastructure $name must name its namespace"
  [[ -f "$ROOT/$path/kustomization.yaml" ]] || fail "plannedInfrastructure $name path $path does not exist"
  [[ "$path" =~ (/aws(/|$)|destinations/eks-) ]] && fail "plannedInfrastructure $name must not use an AWS path: $path"
done
for capability in "${required_capabilities[@]}"; do
  [[ -n "${planned_path[$capability]:-}" ]] || fail "plannedInfrastructure must include $capability"
done
for capability in "${forbidden_capabilities[@]}"; do
  [[ -z "${planned_path[$capability]:-}" ]] || fail "plannedInfrastructure must exclude $capability"
  for entry in "${infra_entries[@]}"; do
    [[ "$(cut -d'|' -f2 <<<"$entry")" == *"/$capability"* ]] && fail "plannedInfrastructure must not deploy $capability through $(cut -d'|' -f1 <<<"$entry")"
  done
done
[[ "${planned_path[istio]:-}" == infrastructure/profiles/full/istio/destinations/aks-dr ]] \
  || fail "plannedInfrastructure istio must be infrastructure/profiles/full/istio/destinations/aks-dr"
[[ "${planned_path[prometheus]:-}" == infrastructure/profiles/full/prometheus/destinations/aks-dr ]] \
  || fail "plannedInfrastructure prometheus must be infrastructure/profiles/full/prometheus/destinations/aks-dr"
for service in "${services[@]}"; do
  grep -Fq "path: apps/$service/profiles/full/destinations/aks-dr" "$planned" \
    || fail "planned inventory plannedServices must name apps/$service/profiles/full/destinations/aks-dr"
done

# --- helpers over every AKS render -------------------------------------------
upstream_registries='(^|[^a-z0-9.-])([a-z0-9-]+\.)*(docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io|k8s\.gcr\.io|registry\.istio\.io|reg\.kyverno\.io|docker\.elastic\.co|public\.ecr\.aws|mcr\.microsoft\.com|[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com)/'
# Workload images: every container, init and ephemeral container, and the
# operator-managed spec.image fields (Prometheus, Alertmanager, Elastic).
check_images() {
  local label="$1" raw="$2" flat="${2%.yaml}.flat" image
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    [[ "$image" =~ ^${acr//./\\.}/[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9._-]+)?@sha256:[a-f0-9]{64}$ ]] \
      || fail "$label renders an image that is not an ACR digest reference in $acr: $image"
  done < <(awk -F'\t' '{ k = $2; sub(/=.*/, "", k) }
      k ~ /(containers|initContainers|ephemeralContainers)\[\]\.image$/ || k == "spec.image" { v = $2; sub(/^[^=]*=/, "", v); print v }' "$flat" | sort -u)
  if without_crds "$raw" | grep -Eq "$upstream_registries"; then
    fail "$label still references an upstream or ECR registry: $(without_crds "$raw" | grep -Eo "$upstream_registries[^ \"]*" | head -1)"
  fi
  return 0
}
check_persistence() {
  local label="$1" flat="$2" raw="$3" class doc
  while IFS= read -r class; do
    [[ "$class" == managed-csi || "$class" == managed-csi-premium ]] \
      || fail "$label persists on '$class'; AKS volumes must use the encrypted Azure Disk class managed-csi"
  done < <(awk -F'\t' '$2 ~ /(^|\.)storageClassName=/ { v = $2; sub(/^[^=]*=/, "", v); print v }' "$flat" | sort -u)
  while IFS= read -r doc; do
    [[ "$(field "$flat" "$doc" provisioner)" =~ ebs\.csi\.aws\.com|kubernetes\.io/aws-ebs ]] \
      && fail "$label renders an EBS StorageClass $(field "$flat" "$doc" metadata.name)"
  done < <(docs_of "$flat" StorageClass "")
  return 0
}
check_no_dns01_identity() {
  local label="$1" raw="$2" match
  match="$(without_crds "$raw" | grep -Eo 'sts\.amazonaws\.com|AWS_ROLE_ARN|AWS_WEB_IDENTITY_TOKEN_FILE|eks\.amazonaws\.com/role-arn' | sort -u | tr '\n' ' ' || true)"
  [[ -z "$match" ]] || fail "$label carries an AWS web identity ($match); only the common-certificate cert-manager path may"
  match="$(without_crds "$raw" | grep -Eo 'AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|accessKeyID|secretAccessKeySecretRef|AKIA[0-9A-Z]{16}' | sort -u | tr '\n' ' ' || true)"
  [[ -z "$match" ]] || fail "$label carries a static AWS credential ($match)"
  return 0
}
check_load_balancers() {
  local label="$1" flat="$2" doc
  while IFS= read -r doc; do
    [[ "$(field "$flat" "$doc" spec.type)" == LoadBalancer ]] || continue
    [[ "$(field "$flat" "$doc" metadata.annotations.service.beta.kubernetes.io/azure-pip-name)" == "$pip_name" ]] \
      || fail "$label LoadBalancer $(field "$flat" "$doc" metadata.name) must bind the Terraform-owned public IP $pip_name (service.beta.kubernetes.io/azure-pip-name)"
    [[ "$(field "$flat" "$doc" metadata.annotations.service.beta.kubernetes.io/azure-load-balancer-resource-group)" == "$pip_group" ]] \
      || fail "$label LoadBalancer $(field "$flat" "$doc" metadata.name) must name the public IP resource group $pip_group (service.beta.kubernetes.io/azure-load-balancer-resource-group)"
    [[ -z "$(field "$flat" "$doc" spec.loadBalancerIP)" ]] \
      || fail "$label LoadBalancer must not use the deprecated spec.loadBalancerIP"
    awk -F'\t' -v d="$doc" '$1 == d && $2 ~ /service\.beta\.kubernetes\.io\/(azure-dns-label-name|azure-load-balancer-ipv[46]|aws-load-balancer)/' "$flat" | grep -q . \
      && fail "$label LoadBalancer must not request its own address, DNS label, or AWS load balancer; Terraform owns the IP and its label"
  done < <(docs_of "$flat" Service "")
  return 0
}

# --- ACR digests, rolling strategy: every service -----------------------------
for service in "${services[@]}"; do
  path="$ROOT/apps/$service/profiles/full/destinations/aks-dr"
  label="apps/$service/profiles/full/destinations/aks-dr"
  [[ -f "$path/kustomization.yaml" ]] || { fail "$label is missing"; continue; }
  render_to "svc-$service" "$path" || continue
  raw="$workdir/svc-$service.yaml"; flat="$workdir/svc-$service.flat"
  validate "$label" "$raw"
  check_images "$label" "$raw"
  check_no_dns01_identity "$label" "$raw"
  check_persistence "$label" "$flat" "$raw"
  check_load_balancers "$label" "$flat"
  grep -q '^kind: Rollout$' "$raw" && fail "$label must roll out with a Deployment (dr-rolling), not an Argo Rollouts canary"
  grep -Eq '^kind: Analysis(Template|Run)$|canary' "$raw" && fail "$label must not repeat the production canary"
  grep -Eq '^  namespace: microtodo-prod$' "$raw" || fail "$label must deploy into microtodo-prod"

  # The production digest is the one the prod overlay pins for this service.
  prod_digest="$(awk -v s="$service" '
    /^images:/ { on = 1; next } on && /^[^ ]/ { on = 0 }
    on && /^  - name:/ { mine = ($3 == s) }
    on && mine && /^    digest:/ { print $2; exit }' "$ROOT/apps/$service/profiles/full/overlays/prod/kustomization.yaml")"
  aks_digest=""
  [[ -n "$prod_digest" ]] && grep -Eq "^[[:space:]]+(- )?image: ${acr//./\\.}/[^ ]*@${prod_digest}\$" "$raw" && aks_digest="$prod_digest"
  if [[ -z "$prod_digest" || "$aks_digest" != "$prod_digest" ]]; then
    fail "$label must run the exact production digest ${prod_digest:-unknown} from $acr"
  fi
done

# --- Azure secret store --------------------------------------------------------
env_path="$ROOT/environments/profiles/full/destinations/aks-dr"
env_label="environments/profiles/full/destinations/aks-dr"
if [[ ! -f "$env_path/kustomization.yaml" ]]; then
  fail "$env_label is missing"
elif render_to env "$env_path"; then
  raw="$workdir/env.yaml"; flat="$workdir/env.flat"
  validate "$env_label" "$raw"
  check_images "$env_label" "$raw"
  check_persistence "$env_label" "$flat" "$raw"
  check_no_dns01_identity "$env_label" "$raw"
  check_load_balancers "$env_label" "$flat"
  awk -F'\t' '$2 ~ /^spec\.provider\.aws\./' "$flat" | grep -q . && fail "$env_label must not render an AWS Secrets Manager store"
  mapfile -t stores < <(docs_of "$flat" SecretStore ""; docs_of "$flat" ClusterSecretStore "")
  [[ "${#stores[@]}" -eq 1 ]] || fail "$env_label must render exactly one secret store, found ${#stores[@]}"
  store="${stores[0]:-}"
  if [[ -n "$store" ]]; then
    store_name="$(field "$flat" "$store" metadata.name)"
    [[ "$(field "$flat" "$store" spec.provider.azurekv.authType)" == WorkloadIdentity ]] \
      || fail "$env_label secret store must use the Azure Key Vault provider with authType WorkloadIdentity"
    [[ "$(field "$flat" "$store" spec.provider.azurekv.vaultUrl)" =~ ^https://[A-Za-z][A-Za-z0-9-]{1,22}[A-Za-z0-9]\.vault\.azure\.net/?$ ]] \
      || fail "$env_label secret store must name T125's Key Vault URL https://<vault>.vault.azure.net"
    awk -F'\t' -v d="$store" '$1 == d && $2 ~ /authSecretRef|clientSecret|identityId/' "$flat" | grep -q . \
      && fail "$env_label secret store must not use a service principal secret or managed identity id"
    reader="$(field "$flat" "$store" spec.provider.azurekv.serviceAccountRef.name)"
    reader_doc="$(docs_of "$flat" ServiceAccount "$reader")"
    if [[ -z "$reader" || -z "$reader_doc" ]]; then
      fail "$env_label secret store must reference a rendered ServiceAccount"
    else
      [[ "$(field "$flat" "$reader_doc" metadata.annotations.azure.workload.identity/client-id)" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
        || fail "$env_label ServiceAccount $reader must carry azure.workload.identity/client-id for T125's workload-reader identity"
    fi
    external="$(docs_of "$flat" ExternalSecret auth-api-secrets)"
    if [[ -z "$external" ]]; then
      fail "$env_label must render ExternalSecret auth-api-secrets"
    else
      [[ "$(field "$flat" "$external" spec.secretStoreRef.name)" == "$store_name" ]] \
        || fail "$env_label auth-api-secrets must read from the Azure secret store $store_name"
      key="$(field "$flat" "$external" 'spec.data[].remoteRef.key' | head -1)"
      [[ "$key" =~ ^[0-9A-Za-z-]{1,127}$ && "$key" != lex-mts-*-sm-* ]] \
        || fail "$env_label auth-api-secrets must name a Key Vault secret, found '${key:-none}'"
    fi
  fi
fi

# --- planned platform renders: ACR, persistence, identity, static IP ----------
for name in "${!planned_path[@]}"; do
  path="$ROOT/${planned_path[$name]}"
  label="${planned_path[$name]}"
  [[ -f "$path/kustomization.yaml" ]] || continue
  render_to "infra-$name" "$path" || continue
  raw="$workdir/infra-$name.yaml"; flat="$workdir/infra-$name.flat"
  validate "$label" "$raw"
  check_images "$label" "$raw"
  check_persistence "$label" "$flat" "$raw"
  check_no_dns01_identity "$label" "$raw"
  check_load_balancers "$label" "$flat"
done
for stateful in prometheus grafana; do
  if [[ -f "$workdir/infra-$stateful.flat" ]]; then
    awk -F'\t' '$2 ~ /storageClassName=managed-csi/' "$workdir/infra-$stateful.flat" | grep -q . \
      || fail "$stateful on AKS must keep its data on an encrypted managed-csi Azure Disk"
  fi
done
if [[ -f "$workdir/infra-istio.flat" ]]; then
  gateway="$(docs_of "$workdir/infra-istio.flat" Service istio-ingressgateway)"
  [[ -n "$gateway" && "$(field "$workdir/infra-istio.flat" "$gateway" spec.type)" == LoadBalancer ]] \
    || fail "the AKS istio-ingressgateway must be a LoadBalancer Service bound to the static public IP"
fi

# --- default-disabled common-certificate component -----------------------------
component_label="infrastructure/profiles/full/cert-manager/components/common-certificate"
if [[ ! -f "$COMPONENT/kustomization.yaml" ]]; then
  fail "$component_label is missing"
else
  grep -q '^kind: Component$' "$COMPONENT/kustomization.yaml" || fail "$component_label must be a Kustomize Component"
  if grep -rlE 'components/common-certificate' "$ROOT/clusters" "$ROOT/infrastructure" "$ROOT/environments" "$ROOT/apps" \
      --include='*.yaml' 2>/dev/null | grep -v "^$COMPONENT/" | grep -q .; then
    fail "$component_label must be disabled by default: nothing may include it yet"
  fi

  cert_manager_path="${planned_path[cert-manager]:-infrastructure/cert-manager}"
  compose="$workdir/compose"
  mkdir -p "$compose"
  cat >"$compose/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - $(realpath --relative-to="$compose" "$ROOT/$cert_manager_path")
components:
  - $(realpath --relative-to="$compose" "$COMPONENT")
EOF
  if render_to certificate "$compose"; then
    raw="$workdir/certificate.yaml"; flat="$workdir/certificate.flat"
    validate "cert-manager with $component_label" "$raw"
    without_crds "$raw" | grep -Eq 'AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|accessKeyID|secretAccessKeySecretRef|AKIA[0-9A-Z]{16}' \
      && fail "$component_label must not carry a static AWS credential"
    account="$(sed -nE 's/^AWS_ACCOUNT_ID=([0-9]{12})$/\1/p' "$ROOT/config/aws-account.env")"

    controller="$(docs_of "$flat" Deployment cert-manager)"
    if [[ -z "$controller" ]]; then
      fail "$component_label render has no cert-manager controller Deployment"
    else
      sa_prefix='spec.template.spec.volumes[].projected.sources[].serviceAccountToken'
      [[ "$(field "$flat" "$controller" "$sa_prefix.audience")" == sts.amazonaws.com ]] \
        || fail "$component_label must project a service account token with audience sts.amazonaws.com into cert-manager"
      token_path="$(field "$flat" "$controller" "$sa_prefix.path")"
      # Join list-item fields through the flattener's item chain (column 3).
      chain_of() { awk -F'\t' -v d="$controller" -v line="$1" '$1 == d && $2 == line { print $3; exit }' "$flat"; }
      value_at() { awk -F'\t' -v d="$controller" -v p="$1" -v c="$2" '$1 == d && $3 == c { k = $2; sub(/=.*/, "", k); if (k == p) { v = $2; sub(/^[^=]*=/, "", v); print v; exit } }' "$flat"; }
      audience_chain="$(chain_of "$sa_prefix.audience=sts.amazonaws.com")"
      volume="$(value_at spec.template.spec.volumes[].name "${audience_chain%%/*}")"
      mount_chain="$(chain_of "spec.template.spec.containers[].volumeMounts[].name=$volume")"
      mount="$(value_at 'spec.template.spec.containers[].volumeMounts[].mountPath' "$mount_chain")"
      env_value() {
        value_at 'spec.template.spec.containers[].env[].value' "$(chain_of "spec.template.spec.containers[].env[].name=$1")"
      }
      [[ -n "$volume" && -n "$mount" && -n "$token_path" ]] \
        || fail "$component_label must mount the projected sts.amazonaws.com token into the cert-manager container"
      [[ "$(env_value AWS_WEB_IDENTITY_TOKEN_FILE)" == "${mount%/}/$token_path" ]] \
        || fail "$component_label AWS_WEB_IDENTITY_TOKEN_FILE must point at the mounted projected token (${mount%/}/$token_path)"
      [[ "$(env_value AWS_ROLE_ARN)" =~ ^arn:aws:iam::${account}:role/[A-Za-z0-9+=,.@_-]{1,64}$ ]] \
        || fail "$component_label AWS_ROLE_ARN must be a role in the declared account $account"
      [[ "$(env_value AWS_REGION)" == us-east-1 ]] || fail "$component_label must set AWS_REGION=us-east-1"
      [[ "$(env_value AWS_STS_REGIONAL_ENDPOINTS)" == regional ]] \
        || fail "$component_label must set AWS_STS_REGIONAL_ENDPOINTS=regional"
      awk -F'\t' -v d="$controller" '$1 == d && $2 ~ /eks\.amazonaws\.com\/role-arn/' "$flat" | grep -q . \
        && fail "$component_label must not rely on the EKS pod identity webhook annotation on AKS"
    fi
    for other in cert-manager-cainjector cert-manager-webhook; do
      doc="$(docs_of "$flat" Deployment "$other")"
      [[ -n "$doc" ]] || continue
      awk -F'\t' -v d="$doc" '$1 == d && $2 ~ /sts\.amazonaws\.com|AWS_ROLE_ARN|AWS_WEB_IDENTITY_TOKEN_FILE/' "$flat" | grep -q . \
        && fail "$component_label must give the AWS web identity to the cert-manager controller only, not $other"
    done
    while IFS= read -r doc; do
      kind="$(field "$flat" "$doc" kind)"
      [[ "$kind" == Deployment && "$(field "$flat" "$doc" metadata.name)" == cert-manager ]] && continue
      awk -F'\t' -v d="$doc" '$1 == d && $2 ~ /sts\.amazonaws\.com|AWS_ROLE_ARN|AWS_WEB_IDENTITY_TOKEN_FILE/' "$flat" | grep -q . \
        && fail "$component_label gives an AWS web identity to $kind $(field "$flat" "$doc" metadata.name)"
    done < <(awk -F'\t' '{print $1}' "$flat" | sort -un)

    issuer="$(awk -F'\t' '$2 ~ /^spec\.acme\.solvers\[\]\.dns01\.route53\.region=/ {print $1}' "$flat" | sort -u)"
    if [[ "$(wc -w <<<"$issuer")" -ne 1 ]]; then
      fail "$component_label must render exactly one ACME issuer with a Route 53 DNS-01 solver"
    else
      [[ "$(field "$flat" "$issuer" kind)" == ClusterIssuer ]] || fail "$component_label DNS-01 issuer must be a ClusterIssuer"
      [[ "$(field "$flat" "$issuer" 'spec.acme.solvers[].dns01.route53.region')" == us-east-1 ]] \
        || fail "$component_label Route 53 solver must use us-east-1"
      [[ "$(field "$flat" "$issuer" 'spec.acme.solvers[].selector.dnsNames[]')" == app.microtodosuite.online ]] \
        || fail "$component_label DNS-01 solver must be restricted to app.microtodosuite.online"
      issuer_name="$(field "$flat" "$issuer" metadata.name)"
      certificate="$(awk -F'\t' '$2 == "spec.dnsNames[]=app.microtodosuite.online" {print $1}' "$flat" | sort -u)"
      if [[ "$(wc -w <<<"$certificate")" -ne 1 ]]; then
        fail "$component_label must render exactly one Certificate for app.microtodosuite.online"
      else
        [[ "$(field "$flat" "$certificate" 'spec.dnsNames[]')" == app.microtodosuite.online ]] \
          || fail "$component_label Certificate must cover only app.microtodosuite.online"
        [[ "$(field "$flat" "$certificate" spec.issuerRef.name)" == "$issuer_name" \
          && "$(field "$flat" "$certificate" spec.issuerRef.kind)" == ClusterIssuer ]] \
          || fail "$component_label Certificate must be issued by the DNS-01 ClusterIssuer $issuer_name"
      fi
    fi
  fi
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d AKS DR root violation(s) (root state: %s)\n' "$failures" "$state" >&2
  exit 1
fi

printf 'PASS: the AKS DR root reconciles independently in-cluster (%s), plans the complete full inventory from ACR digests with an Azure secret store, managed-csi persistence, and the Terraform-owned static IP, and keeps the DNS-01 web identity in a disabled cert-manager-only component.\n' "$state"

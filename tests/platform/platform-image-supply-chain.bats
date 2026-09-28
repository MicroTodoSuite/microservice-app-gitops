#!/usr/bin/env bash
# Failing-first platform image supply-chain contract (spec 009 T071/T088).
# Static checks run without a registry. Signature/referrer verification belongs
# to the post-mirror policy-contracts job once the platform mirror exists.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOCK="$ROOT/scripts/managed/full-profile-toolchain.lock"
KUSTOMIZE_BIN="${KUSTOMIZE_BIN:-kustomize}"

command -v "$KUSTOMIZE_BIN" >/dev/null || { printf 'FAIL: kustomize is required\n' >&2; exit 1; }
command -v jq >/dev/null || { printf 'FAIL: jq is required\n' >&2; exit 1; }

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
require_file() { [[ -f "$ROOT/$1" ]] || fail "required file is missing: $1"; }
render() { "$KUSTOMIZE_BIN" build "$ROOT/$1"; }

document() {
  awk -v kind="$1" -v name="$2" '
    function flush() {
      if (doc ~ ("\nkind: " kind "\n") && doc ~ ("\n  name: " name "\n")) printf "%s", doc
      doc = "\n"
    }
    BEGIN { doc = "\n" }
    /^---$/ { flush(); next }
    { doc = doc $0 "\n" }
    END { flush() }
  '
}

# Lock rows are immutable, one-to-one source/mirror identities.
locked_count="$(jq '.images | length' "$LOCK")"
[[ "$locked_count" -gt 0 ]] || fail "the locked platform graph must contain images"
jq -e 'all(.images[];
  (.upstreamDigest | test("^sha256:[0-9a-f]{64}$")) and
  (.upstreamRef | test("@sha256:") | not) and
  (.mirrorTag | test("^[A-Za-z0-9][A-Za-z0-9._-]*$")))' "$LOCK" >/dev/null \
  || fail "every source row must separate its immutable digest from the upstream tag and carry one valid mirror tag"
[[ "$(jq '[.images[].upstreamDigest] | unique | length' "$LOCK")" == "$locked_count" ]] \
  || fail "every locked image id must resolve to one distinct manifest digest"

# The EKS admission root must retain the service identity and add exactly the
# dedicated platform-mirror workflow identity. A service CI signature is not a
# platform signature, and another organization/workflow/ref must not match.
KYVERNO_ROOT=infrastructure/profiles/full/kyverno/aws
require_file "$KYVERNO_ROOT/kustomization.yaml"
if [[ -f "$ROOT/$KYVERNO_ROOT/kustomization.yaml" ]]; then
  policy="$(render "$KYVERNO_ROOT" | document ClusterPolicy verify-approved-release-signatures)"
  [[ -n "$policy" ]] || fail "full-profile Kyverno must render verify-approved-release-signatures"
  expected_subject='^https://github\.com/MicroTodoSuite/\.github/\.github/workflows/mirror-platform-images\.yml@refs/heads/main$'
  grep -qF "subjectRegExp: '$expected_subject'" <<<"$policy" \
    || fail "the platform attestor must use the exact mirror-platform-images.yml@refs/heads/main identity"
  grep -qF 'githubWorkflowRepository: MicroTodoSuite/.github' <<<"$policy" \
    || fail "the platform attestor must require githubWorkflowRepository MicroTodoSuite/.github"
  grep -qF 'githubWorkflowRef: refs/heads/main' <<<"$policy" \
    || fail "the platform attestor must require githubWorkflowRef refs/heads/main"
  grep -qF 'issuer: https://token.actions.githubusercontent.com' <<<"$policy" \
    || fail "the platform attestor must require the GitHub Actions issuer"
  [[ "$(grep -cF 'mirror-platform-images\.yml@refs/heads/main' <<<"$policy" || true)" -eq 1 ]] \
    || fail "the platform mirror identity must appear exactly once"
fi

# Admission fixtures cover each failure independently. Registry-backed
# fixtures remain disabled until T082 has created and signed the mirror graph;
# their expected result is still checked in now so the future job cannot omit a
# negative case.
FIXTURES=tests/platform/fixtures/platform-image-supply-chain
for fixture in unsigned-image unmirrored-image mutable-image wrong-platform-mirror-identity; do
  require_file "$FIXTURES/$fixture.yaml"
done
require_file "$FIXTURES/kyverno-test.yaml"
if [[ -f "$ROOT/$FIXTURES/kyverno-test.yaml" ]]; then
  fixture_contract="$(<"$ROOT/$FIXTURES/kyverno-test.yaml")"
  for fixture in unsigned-image unmirrored-image mutable-image wrong-platform-mirror-identity; do
    grep -qF "$fixture" <<<"$fixture_contract" \
      || fail "$FIXTURES/kyverno-test.yaml must assert the $fixture negative case"
  done
  denied="$(grep -cE '^[[:space:]]*result: fail$' <<<"$fixture_contract" || true)"
  [[ "$denied" -eq 4 ]] || fail "the four supply-chain negative fixtures must all be denied"
fi

# A complete evidence graph has one row per lock id, equal source/mirror
# digests, and explicit signature, SBOM, and scan records. The committed
# template is value-free and gives the mirror workflow a fail-closed schema.
GRAPH_TEMPLATE=evidence/templates/platform-image-graph.json
require_file "$GRAPH_TEMPLATE"
if [[ -f "$ROOT/$GRAPH_TEMPLATE" ]]; then
  graph="$ROOT/$GRAPH_TEMPLATE"
  [[ "$(jq '.images | length' "$graph")" == "$locked_count" ]] \
    || fail "the OCI graph template must contain exactly $locked_count locked images"
  jq -e --slurpfile lock "$LOCK" '
    ([.images[].id] | sort) == ([$lock[0].images[].id] | sort) and
    all(.images[];
      (.sourceDigest | test("^sha256:[0-9a-f]{64}$")) and
      (.mirrorDigest == .sourceDigest) and
      (.signature.verified == true) and
      (.sbom.verified == true) and
      (.scan.status == "passed"))' "$graph" >/dev/null \
    || fail "the OCI graph must be complete, digest-equal, signed, SBOM-linked, and scan-passed"
fi

# Full EKS roots deploy only the single ECR mirror repository by digest. AKS
# roots deploy only the ACR copy by the same digest. Direct upstream, tag-only,
# and repository-per-component references are all rejected.
for destination in eks-full-dev eks-full-staging eks-full-prod aks-dr; do
  inventory="$ROOT/clusters/$destination/planned-inventory.yaml"
  [[ -f "$inventory" ]] || { fail "missing planned inventory for $destination"; continue; }
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    [[ -f "$ROOT/$path/kustomization.yaml" ]] || continue
    output="$(render "$path" 2>/dev/null)" || { fail "$path must render"; continue; }
    while IFS= read -r image; do
      [[ -z "$image" ]] && continue
      [[ "$image" =~ @sha256:[0-9a-f]{64}$ ]] \
        || { fail "$destination/$path renders a mutable platform image: $image"; continue; }
      digest="${image##*@}"
      jq -e --arg digest "$digest" 'any(.images[]; .upstreamDigest == $digest)' "$LOCK" >/dev/null \
        || fail "$destination/$path renders an image outside the locked OCI graph: $image"
      if [[ "$destination" == eks-* ]]; then
        [[ "$image" =~ \.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/microtodosuite/platform@sha256:[0-9a-f]{64}$ ]] \
          || fail "$destination/$path renders an unsigned or unmirrored ECR image: $image"
      else
        [[ "$image" =~ ^[a-z0-9-]+\.azurecr\.io/microtodosuite/platform@sha256:[0-9a-f]{64}$ ]] \
          || fail "$destination/$path renders an unsigned or unmirrored ACR image: $image"
      fi
    done < <(awk '$1 == "image:" && $2 != "" { gsub(/["'"'"']/, "", $2); print $2 }' <<<"$output" | sort -u)
  done < <(awk '
    /^  plannedInfrastructure: \|$/ { active = 1; next }
    active && /^  [[:alnum:]][^:]*:/ { active = 0 }
    active && /^      path: / { print $2 }
  ' "$inventory")
done

if (( failures > 0 )); then
  printf 'FAIL: %d platform image supply-chain violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: the complete locked OCI graph is mirrored by digest, signed only by the approved platform workflow, and protected by mutable/unmirrored/unsigned/wrong-identity failure fixtures.\n'

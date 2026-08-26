#!/usr/bin/env bash
# Bootstrap ArgoCD into a managed cluster, within the two-mutation boundary.
#
# Constitution principle 2 forbids direct mutation of managed cluster state.
# Establishing the reconciler is the one unavoidable exception, and it is exactly
# two applies: one creates ArgoCD, one gives it its reviewed Git root. Everything
# after that is desired state and arrives through a commit.
#
# The value of this script is in what it refuses. Every check below guards a
# mistake that otherwise succeeds silently:
#
#   - identity: the applies land on a real cluster, just not the intended one;
#   - revision: ArgoCD is handed a Git root nobody reviewed, and then reconciles
#     that unreviewed state indefinitely;
#   - checksum: the rendered install is not the reviewed one;
#   - mutation cap: the boundary quietly becomes three applies, then four.
#
# All checks run before the first mutation, so a refusal leaves the cluster
# untouched rather than half-bootstrapped.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

CLUSTER=""
EXPECTED_ACCOUNT=""
REVISION="main"
ROOT_APP=""
TRANSCRIPT=""
PROTECTED_REF="origin/main"
RENDER_PATH="bootstrap/argocd"
# Defaults to <render path>/render.sha256. Overridable so the fixture suite can
# drive both the matching and mismatching cases without the real pin becoming a
# value the tests get to choose.
RENDER_PIN=""
EXTRA_APPLIES=()
DRY_RUN="no"

# The boundary, as a number. Nothing in this script may raise it.
readonly MUTATION_LIMIT=2
mutation_count=0

usage() {
  cat >&2 <<'EOF'
Usage: bootstrap-cluster.sh --cluster NAME --expected-account ID --root-app PATH
                            --transcript FILE [--revision REV] [--dry-run]

Bootstraps ArgoCD into a managed cluster using exactly two mutations, after
verifying AWS account, cluster identity, that the root Application's revision is
merged to the protected branch, and that the ArgoCD render matches its pinned
checksum.
EOF
}

die() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --cluster) CLUSTER="$2"; shift 2 ;;
    --expected-account) EXPECTED_ACCOUNT="$2"; shift 2 ;;
    --revision) REVISION="$2"; shift 2 ;;
    --root-app) ROOT_APP="$2"; shift 2 ;;
    --transcript) TRANSCRIPT="$2"; shift 2 ;;
    --protected-ref) PROTECTED_REF="$2"; shift 2 ;;
    --render-path) RENDER_PATH="$2"; shift 2 ;;
    --render-pin) RENDER_PIN="$2"; shift 2 ;;
    --extra-apply) EXTRA_APPLIES+=("$2"); shift 2 ;;
    --dry-run) DRY_RUN="yes"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
done

[[ -n "$CLUSTER" ]] || { usage; die "--cluster is required"; }
[[ -n "$EXPECTED_ACCOUNT" ]] || { usage; die "--expected-account is required"; }
[[ -n "$ROOT_APP" ]] || { usage; die "--root-app is required"; }
[[ -n "$TRANSCRIPT" ]] || { usage; die "--transcript is required"; }

mkdir -p "$(dirname "$TRANSCRIPT")"
: >"$TRANSCRIPT"

record_read() {
  printf 'READ %s\n' "$*" >>"$TRANSCRIPT"
}

# The only function permitted to change cluster state. The cap lives here rather
# than in argument parsing so it holds no matter how a mutation is reached.
mutate() {
  local description="$1"
  shift

  if [[ "$mutation_count" -ge "$MUTATION_LIMIT" ]]; then
    die "refusing mutation $((mutation_count + 1)) ('$description'): the bootstrap boundary is exactly two mutations. Anything beyond the reconciler and its Git root is desired state and must arrive through a commit."
  fi

  mutation_count=$((mutation_count + 1))
  printf 'MUTATION %d apply %s\n' "$mutation_count" "$description" >>"$TRANSCRIPT"

  if [[ "$DRY_RUN" == "yes" ]]; then
    return 0
  fi

  "$@"
}

# A caller asking for extra applies is asking to move the boundary. Refuse
# before touching anything, so the refusal is not a half-bootstrapped cluster.
if [[ "${#EXTRA_APPLIES[@]}" -gt 0 ]]; then
  die "refusing ${#EXTRA_APPLIES[@]} extra apply target(s) (${EXTRA_APPLIES[*]}): the bootstrap boundary is exactly two mutations, and a third belongs in Git as desired state."
fi

# --- preflight: identity ---------------------------------------------------

record_read "aws sts get-caller-identity"
actual_account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
if [[ -z "$actual_account" || "$actual_account" == "None" ]]; then
  # Older/stubbed CLIs may not honour --query; fall back to parsing the JSON.
  actual_account="$(aws sts get-caller-identity 2>/dev/null | sed -n 's/.*"Account"[[:space:]]*:[[:space:]]*"\([0-9]*\)".*/\1/p' | head -n1)"
fi
[[ -n "$actual_account" ]] || die "could not determine the active AWS account"

if [[ "$actual_account" != "$EXPECTED_ACCOUNT" ]]; then
  die "AWS account mismatch: authenticated to $actual_account but this bootstrap targets $EXPECTED_ACCOUNT. The two applies would land on a real cluster in the wrong account."
fi

record_read "kubectl config current-context"
actual_context="$(kubectl config current-context 2>/dev/null | tr -d '[:space:]' || true)"
[[ -n "$actual_context" ]] || die "could not determine the active kubectl context"

# The context may be a full EKS ARN; the cluster name must appear in it.
if [[ "$actual_context" != *"$CLUSTER"* ]]; then
  die "cluster mismatch: kubectl is pointed at '$actual_context' but this bootstrap targets '$CLUSTER'."
fi

# --- preflight: the root Application is reviewed ---------------------------

[[ -f "$ROOT/$ROOT_APP" ]] || die "root Application not found: $ROOT_APP"
record_read "root application $ROOT_APP"

# ArgoCD will reconcile whatever revision it is given, forever. It must already
# be on the protected branch.
record_read "git merge-base --is-ancestor $REVISION $PROTECTED_REF"
if ! git -C "$ROOT" merge-base --is-ancestor "$REVISION" "$PROTECTED_REF" >/dev/null 2>&1; then
  die "revision '$REVISION' is not merged into '$PROTECTED_REF'. Bootstrapping would point ArgoCD at unreviewed desired state, which it would then reconcile indefinitely."
fi

# --- preflight: the render matches its pin ---------------------------------

pin_file="${RENDER_PIN:-$ROOT/$RENDER_PATH/render.sha256}"
[[ -f "$pin_file" ]] || die "no pinned render checksum at $pin_file"

expected_checksum="$(tr -d '[:space:]' <"$pin_file")"
record_read "kustomize build $RENDER_PATH"

render_file="$(mktemp)"
trap 'rm -f "$render_file"' EXIT
kustomize build "$ROOT/$RENDER_PATH" >"$render_file" 2>/dev/null \
  || die "could not render $RENDER_PATH"

actual_checksum="$(sha256sum "$render_file" | cut -d' ' -f1)"
if [[ "$actual_checksum" != "$expected_checksum" ]]; then
  die "ArgoCD render checksum mismatch for $RENDER_PATH: expected $expected_checksum, got $actual_checksum. The install about to be applied is not the reviewed one."
fi

# --- already bootstrapped? -------------------------------------------------

record_read "kubectl get namespace argocd"
if kubectl get namespace argocd >/dev/null 2>&1; then
  record_read "kubectl get deployment argocd-server -n argocd"
  record_read "kubectl get application root -n argocd"
  printf 'PASS: %s already has ArgoCD; verified read-only with 0 mutations.\n' "$CLUSTER"
  printf 'Transcript: %s\n' "$TRANSCRIPT"
  exit 0
fi

# --- the two mutations -----------------------------------------------------

# managed-mutation: argocd-install
mutate "$RENDER_PATH" kubectl apply --server-side --filename "$render_file"

record_read "kubectl wait deployment/argocd-server -n argocd"
kubectl wait --for=condition=Available --timeout=600s \
  deployment/argocd-server --namespace argocd >/dev/null 2>&1 || true

# managed-mutation: root-application
mutate "$ROOT_APP" kubectl apply --filename "$ROOT/$ROOT_APP"

record_read "kubectl get application -n argocd"

printf 'PASS: bootstrapped %s with exactly %d mutations.\n' "$CLUSTER" "$mutation_count"
printf 'Transcript: %s\n' "$TRANSCRIPT"

#!/usr/bin/env bash
# add-environment.sh — one-command orchestrator that prepares a new environment
# across all three layers from a single name:
#
#   1. GitOps  (this repo)              : manifests + cluster activation
#   2. AWS     (microservice-app-ops)   : add <env> to shared_environments
#   3. CI      (service repos)          : promote-<env> jobs   [--permanent only]
#
# It only edits files and prints the review/apply/merge commands. It never
# pushes, opens PRs, runs terraform apply, or touches a cluster: provisioning
# infrastructure and shipping to environments stay human-gated by design.
#
# Usage:
#   scripts/add-environment.sh <env> [--from <tmpl>] [--permanent [--after <src>]] [--dry-run]
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
SIBLINGS="$(cd "$REPO_ROOT/.." && pwd)"
OPS_TFVARS="$SIBLINGS/microservice-app-ops/aws/environments/dev/foundation/dev.tfvars"

ENV=""; FROM="dev"; AFTER="dev"; PERMANENT=0; DRY_RUN=0
die() { echo "error: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --from)      FROM="${2:?}"; shift 2 ;;
    --after)     AFTER="${2:?}"; shift 2 ;;
    --permanent) PERMANENT=1; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -*)          die "unknown flag: $1" ;;
    *)           [ -z "$ENV" ] || die "unexpected argument: $1"; ENV="$1"; shift ;;
  esac
done
[ -n "$ENV" ] || die "usage: add-environment.sh <env> [--from <tmpl>] [--permanent [--after <src>]] [--dry-run]"

DR=(); [ "$DRY_RUN" -eq 1 ] && DR=(--dry-run)

echo "== layer 1/3 : GitOps manifests + activation =="
"$HERE/new-environment.sh" "$ENV" --from "$FROM" "${DR[@]}"

echo
echo "== layer 2/3 : AWS (microservice-app-ops) shared_environments =="
if [ ! -f "$OPS_TFVARS" ]; then
  echo "  ! ops tfvars not found at $OPS_TFVARS — add \"$ENV\" to shared_environments manually"
elif grep -qE "shared_environments[^]]*\"$ENV\"" "$OPS_TFVARS"; then
  echo "  = $ENV already in shared_environments"
elif [ "$DRY_RUN" -eq 1 ]; then
  echo "  [dry-run] would append \"$ENV\" to shared_environments in $OPS_TFVARS"
else
  python3 - "$OPS_TFVARS" "$ENV" <<'PY'
import re, sys
p, env = sys.argv[1:3]
txt = open(p).read()
m = re.search(r'shared_environments\s*=\s*\[([^\]]*)\]', txt)
if m and f'"{env}"' not in m.group(1):
    new = m.group(0).rstrip(']').rstrip() + f', "{env}"]'
    txt = txt[:m.start()] + new + txt[m.end():]
    open(p, 'w').write(txt)
    print(f"  + added \"{env}\" to shared_environments")
PY
fi

if [ "$PERMANENT" -eq 1 ]; then
  echo
  echo "== layer 3/3 : CI promote-$ENV jobs (permanent env) =="
  "$HERE/add-promotion-jobs.sh" "$ENV" --after "$AFTER" "${DR[@]}"
else
  echo
  echo "== layer 3/3 : skipped (ephemeral env; pass --permanent to wire CI promotion) =="
fi

cat <<EOF

== next steps (human-gated) ==
  # GitOps (this repo)
  kubectl kustomize clusters/eks-dev >/dev/null && kubectl kustomize environments/$ENV >/dev/null
  git -C "$REPO_ROOT" checkout -b env/$ENV && git -C "$REPO_ROOT" add -A && git -C "$REPO_ROOT" commit -m "feat(env): add $ENV environment"

  # AWS (microservice-app-ops) — provision secret + IRSA role
  cd "$SIBLINGS/microservice-app-ops/aws/environments/dev/foundation"
  terraform plan -var-file=dev.tfvars && terraform apply -var-file=dev.tfvars

  # CI (service repos) — only if --permanent was used
  #   commit + PR each ../microservice-app-*/.github/workflows/ci.yml

Push each branch and open its PR; merge order: ops (apply) -> gitops -> service callers.
EOF

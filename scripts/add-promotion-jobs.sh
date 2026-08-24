#!/usr/bin/env bash
# add-promotion-jobs.sh — inject a promote-<env> job into every service caller so
# a PERMANENT environment joins the CI promotion flow. Ephemeral environments
# (demo, preview) do not need this: they are created ad-hoc from dev's digest.
#
# It edits the sibling repos ../microservice-app-<service>/.github/workflows/ci.yml,
# reusing each caller's own pinned promote.yml SHA, service-name and
# publisher-role-arn, and inserts the new job right before `gate-prod:` so it
# runs after --after (default: dev) without rewiring the dev->staging->prod
# chain. Review the diff and open a PR per repo; nothing is pushed here.
#
# Usage:
#   scripts/add-promotion-jobs.sh <env> [--after <src-env>] [--dry-run]
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIBLINGS="$(cd "$REPO_ROOT/.." && pwd)"

ENV=""
AFTER="dev"
DRY_RUN=0
SERVICES="auth-api todos-api users-api frontend log-message-processor"

die() { echo "error: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --after)   AFTER="${2:?}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*)        die "unknown flag: $1" ;;
    *)         [ -z "$ENV" ] || die "unexpected argument: $1"; ENV="$1"; shift ;;
  esac
done
[ -n "$ENV" ] || die "usage: add-promotion-jobs.sh <env> [--after <src-env>] [--dry-run]"
echo "$ENV" | grep -qE '^[a-z][a-z0-9-]*$' || die "invalid environment name '$ENV'"

for svc in $SERVICES; do
  f="$SIBLINGS/microservice-app-$svc/.github/workflows/ci.yml"
  [ -f "$f" ] || { echo "  skip $svc (no caller at $f)"; continue; }
  DRY_RUN="$DRY_RUN" python3 - "$f" "$svc" "$ENV" "$AFTER" <<'PY'
import os, re, sys
f, svc, env, after = sys.argv[1:5]
dry = os.environ.get("DRY_RUN") == "1"
txt = open(f).read()

if re.search(rf'^\s{{2}}promote-{re.escape(env)}:', txt, re.M):
    print(f"  = {svc}: promote-{env} already present, skipping"); raise SystemExit(0)

sha  = (re.search(r'promote\.yml@(\w+)', txt) or [None, None])[1]
arn  = (re.search(r'publisher-role-arn:\s*(\S+)', txt) or [None, None])[1]
name = (re.search(r'service-name:\s*(\S+)', txt) or [None, None])[1]
if not (sha and arn and name):
    print(f"  ! {svc}: could not read sha/arn/service-name, skipping"); raise SystemExit(0)

job = f"""  promote-{env}:
    # Auto-generated promotion for the '{env}' environment (build-once, same digest).
    if: ${{{{ github.event_name == 'push' && vars.ENABLE_LEGACY_DEV_PROMOTION == 'true' && needs.release.outputs.released == 'true' }}}}
    needs: [ci, release, promote-{after}]
    uses: MicroTodoSuite/.github/.github/workflows/promote.yml@{sha}
    with:
      service-name: {name}
      environment: {env}
      image-digest: ${{{{ needs.ci.outputs.image-digest }}}}
      image-ref: ${{{{ needs.ci.outputs.image-ref }}}}
      publisher-role-arn: {arn}
    secrets:
      gitops-app-id: ${{{{ secrets.GITOPS_PROMOTE_APP_ID }}}}
      gitops-app-key: ${{{{ secrets.GITOPS_PROMOTE_APP_KEY }}}}

"""

anchor = re.search(r'^\s{2}gate-prod:', txt, re.M)
if not anchor:
    print(f"  ! {svc}: no gate-prod anchor, skipping"); raise SystemExit(0)

new = txt[:anchor.start()] + job + txt[anchor.start():]
if dry:
    print(f"  [dry-run] {svc}: would insert promote-{env} (needs promote-{after}) before gate-prod")
else:
    open(f, 'w').write(new)
    print(f"  + {svc}: inserted promote-{env}")
PY
done

echo ">> done. review each ../microservice-app-*/.github/workflows/ci.yml and open a PR per repo."

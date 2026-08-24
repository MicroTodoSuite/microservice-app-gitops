#!/usr/bin/env bash
# new-environment.sh — scaffold (or remove) a managed namespace environment for
# the shared economical cluster, generated entirely from an existing environment
# used as the template (dev by default).
#
# It is generic: the environment name is the only required argument, so the same
# script produces dev, staging, prod, qa, demo, preview-42, ... The immutable
# image digest is copied unchanged from the template, so the new environment is a
# bit-for-bit replica that runs the identical signed images (build-once).
#
# This tool only writes GitOps desired state (manifests + the cluster activation
# lists) and never applies anything to a cluster: review the diff, open a PR, and
# ArgoCD reconciles it. The one non-GitOps dependency, the per-environment JWT
# secret and its IRSA reader role, is provisioned by Terraform in
# microservice-app-ops (add the name to shared_environments); see
# docs/new-environment.md.
#
# Usage:
#   scripts/new-environment.sh <env> [--from <template-env>] [--dry-run]
#   scripts/new-environment.sh <env> --delete
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SOURCE_ENV="dev"
DELETE=0
DRY_RUN=0
ENV=""

RS="clusters/eks-dev/rolling-sync-apps.yaml"
ACT_APPS="clusters/eks-dev/activation-apps.yaml"
ACT_ENVS="clusters/eks-dev/activation-environments.yaml"

usage() {
  sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() { echo "error: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --from)    SOURCE_ENV="${2:?}"; shift 2 ;;
    --delete)  DELETE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        die "unknown flag: $1" ;;
    *)         [ -z "$ENV" ] || die "unexpected argument: $1"; ENV="$1"; shift ;;
  esac
done

[ -n "$ENV" ] || { usage; exit 2; }
echo "$ENV" | grep -qE '^[a-z][a-z0-9-]*$' \
  || die "invalid environment name '$ENV' (use lowercase letters, digits, hyphens)"
case "$ENV" in base|local) die "'$ENV' is a reserved directory name" ;; esac

# --- python helper: edit the cluster activation + rolling-sync lists ----------
edit_registration() {
  local action="$1" # add | remove
  python3 - "$action" "$ENV" "$ACT_APPS" "$ACT_ENVS" "$RS" <<'PY'
import re, sys
action, env, act_apps, act_envs, rs = sys.argv[1:6]
SERVER = "https://kubernetes.default.svc"

def add_activation(path):
    lines = open(path).read().splitlines()
    if any(re.match(rf'\s*-\s*env:\s*{re.escape(env)}\s*$', l) for l in lines):
        return
    last = max(i for i, l in enumerate(lines) if l.strip() == f'server: {SERVER}')
    ind = re.match(r'\s*', lines[last]).group(0)          # server indent (e.g. 6)
    dash = ind[:-2] if len(ind) >= 2 else ind             # '- env' dash indent
    lines[last+1:last+1] = [f'{dash}- env: {env}', f'{ind}server: {SERVER}']
    open(path, 'w').write('\n'.join(lines) + '\n')

def remove_activation(path):
    lines = open(path).read().splitlines()
    out, i = [], 0
    while i < len(lines):
        if re.match(rf'\s*-\s*env:\s*{re.escape(env)}\s*$', lines[i]):
            i += 2  # skip the '- env:' line and its 'server:' line
            continue
        out.append(lines[i]); i += 1
    open(path, 'w').write('\n'.join(out) + '\n')

def add_wave(path):
    txt = open(path).read()
    if f'["{env}"]' in txt:
        return
    lines = txt.splitlines()
    last = max(i for i, l in enumerate(lines) if l.strip() == 'maxUpdate: 1')
    s = '        '  # step indent used by this file
    block = [
        f'{s}- matchExpressions:',
        f'{s}    - key: microtodosuite.io/environment',
        f'{s}      operator: In',
        f'{s}      values: ["{env}"]',
        f'{s}  maxUpdate: 1',
    ]
    lines[last+1:last+1] = block
    open(path, 'w').write('\n'.join(lines) + '\n')

def remove_wave(path):
    lines = open(path).read().splitlines()
    out, i = [], 0
    while i < len(lines):
        if lines[i].strip() == '- matchExpressions:' and i+3 < len(lines) \
           and f'["{env}"]' in lines[i+3]:
            i += 5  # drop this 5-line step block
            continue
        out.append(lines[i]); i += 1
    open(path, 'w').write('\n'.join(out) + '\n')

if action == 'add':
    add_activation(act_apps); add_activation(act_envs); add_wave(rs)
else:
    remove_activation(act_apps); remove_activation(act_envs); remove_wave(rs)
PY
}

# ---------------------------------------------------------------------------- #
if [ "$DELETE" -eq 1 ]; then
  echo ">> removing environment '$ENV'"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] rm -rf environments/$ENV apps/*/overlays/$ENV; drop $ENV from activation + rolling-sync"
    exit 0
  fi
  rm -rf "environments/$ENV"
  for svc in apps/*/; do rm -rf "${svc}overlays/$ENV"; done
  edit_registration remove
  echo ">> done. review 'git status' and open a PR; ArgoCD prunes the environment on merge."
  exit 0
fi

[ -d "environments/$SOURCE_ENV" ] || die "template environment not found: environments/$SOURCE_ENV"
[ ! -e "environments/$ENV" ] || die "environment already exists: environments/$ENV"

echo ">> creating environment '$ENV' from template '$SOURCE_ENV'"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] would copy environments/$SOURCE_ENV -> environments/$ENV"
  for svc in apps/*/; do
    s="${svc%/}"; s="${s#apps/}"
    [ -d "apps/$s/overlays/$SOURCE_ENV" ] && echo "[dry-run] would copy apps/$s/overlays/$SOURCE_ENV -> apps/$s/overlays/$ENV"
  done
  echo "[dry-run] would activate '$ENV' in $ACT_APPS, $ACT_ENVS and add a RollingSync wave in $RS"
  exit 0
fi

# 1) environment policy (namespace quota/limits/netpol/RBAC + ESO secret wiring)
cp -R "environments/$SOURCE_ENV" "environments/$ENV"
while IFS= read -r f; do
  sed -i.bak \
    -e "s|microtodo-$SOURCE_ENV|microtodo-$ENV|g" \
    -e "s|environment: $SOURCE_ENV|environment: $ENV|g" \
    -e "s|microtodosuite/$SOURCE_ENV/|microtodosuite/$ENV/|g" \
    -e "s|microtodosuite-$SOURCE_ENV-jwt-reader|microtodosuite-$ENV-jwt-reader|g" \
    -e "s|microtodosuite:$SOURCE_ENV-maintainers|microtodosuite:$ENV-maintainers|g" \
    "$f" && rm -f "$f.bak"
done < <(find "environments/$ENV" -type f -name '*.yaml')

# 2) per-service overlays — only the namespace changes; the immutable digest is
#    copied verbatim so the new environment is a bit-for-bit replica.
for svc in apps/*/; do
  s="${svc%/}"; s="${s#apps/}"
  if [ -d "apps/$s/overlays/$SOURCE_ENV" ]; then
    cp -R "apps/$s/overlays/$SOURCE_ENV" "apps/$s/overlays/$ENV"
    while IFS= read -r f; do
      sed -i.bak -e "s|microtodo-$SOURCE_ENV|microtodo-$ENV|g" "$f" && rm -f "$f.bak"
    done < <(find "apps/$s/overlays/$ENV" -type f -name '*.yaml')
  fi
done

# 3) activate the environment in the shared-cluster registration
edit_registration add

echo ">> done. review 'git status', then:"
echo "     kubectl kustomize clusters/eks-dev >/dev/null   # validate the render"
echo "     git checkout -b env/$ENV && git add -A && git commit && open a PR"
echo "   remember: provision the $ENV JWT secret + IRSA role in microservice-app-ops"
echo "   (add '$ENV' to shared_environments) before ArgoCD syncs, or /login will fail."

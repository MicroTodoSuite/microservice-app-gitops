#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
managed_root="$repo_root/scripts/managed"
bootstrap="$managed_root/bootstrap-cluster.sh"

python3 - "$managed_root" "$bootstrap" <<'PY'
import pathlib
import re
import sys

managed_root = pathlib.Path(sys.argv[1])
bootstrap = pathlib.Path(sys.argv[2])
VERBS = r'(apply|create|patch|delete|scale|run|exec)'
mutation = re.compile(r'(?:\bkubectl\b|KUBECTL_BIN).*\b' + VERBS + r'\b')
bootstrap_exists = bootstrap.is_file()


def kubectl_wrappers(text):
    # Shell functions whose body calls kubectl, such as kube() { kubectl --context "$C" "$@"; }.
    # A mutation behind one (kube create job ...) is still a mutation (spec 009 T088).
    names, current, body = set(), None, []
    definition = re.compile(r'^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{(.*)$')
    for line in text.splitlines():
        if current is None:
            match = definition.match(line)
            if not match:
                continue
            current, rest = match.group(1), match.group(2)
            body = [rest]
            if '}' in rest:
                if re.search(r'\bkubectl\b|KUBECTL_BIN', rest):
                    names.add(current)
                current = None
            continue
        body.append(line)
        if re.match(r'^\s*\}', line):
            if re.search(r'\bkubectl\b|KUBECTL_BIN', '\n'.join(body)):
                names.add(current)
            current = None
    return names


def wrapper_mutation(line, wrappers):
    for name in wrappers:
        # The wrapper name as a command, optionally followed by flags and their
        # values, then a mutating verb.
        pattern = r'(?:^|[\s;(|&!{]|\$\()' + re.escape(name) + r'\s+(?:-{1,2}[^\s=]+(?:[=\s]+(?!-)[^\s]+)?\s+)*' + VERBS + r'\b'
        if re.search(pattern, line):
            return True
    return False

violations = []
for path in sorted(managed_root.rglob('*.sh')):
    if bootstrap_exists and path == bootstrap:
        continue
    text = path.read_text(encoding='utf-8')
    wrappers = kubectl_wrappers(text)
    for number, line in enumerate(text.splitlines(), 1):
        if 'auth can-i' in line or line.strip().startswith('#'):
            continue
        if mutation.search(line) or wrapper_mutation(line, wrappers):
            violations.append(f'{path}:{number}:{line.strip()}')

if violations:
    print('FAIL: post-bootstrap imperative managed mutations found:', file=sys.stderr)
    print('\n'.join(violations), file=sys.stderr)
    sys.exit(1)

if bootstrap_exists:
    bootstrap_text = bootstrap.read_text(encoding='utf-8')
    markers = re.findall(
        r'^# managed-mutation: (argocd-install|root-application)$',
        bootstrap_text,
        re.MULTILINE,
    )
    commands = [
        line.strip()
        for line in bootstrap_text.splitlines()
        if mutation.search(line) and 'auth can-i' not in line
    ]
    if not bootstrap.stat().st_mode & 0o111:
        print('FAIL: the managed bootstrap helper is not executable.', file=sys.stderr)
        sys.exit(1)
    if markers != ['argocd-install', 'root-application']:
        print(f'FAIL: bootstrap mutation markers are not the exact ordered pair: {markers}', file=sys.stderr)
        sys.exit(1)
    if len(commands) != 2 or any('apply' not in command for command in commands):
        print(f'FAIL: bootstrap must contain exactly two apply commands, got: {commands}', file=sys.stderr)
        sys.exit(1)

print('PASS: managed scripts contain no post-bootstrap imperative mutations or exec, directly or behind kubectl wrappers; any bootstrap helper is limited to two audited apply commands.')
PY

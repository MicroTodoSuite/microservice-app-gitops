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
mutation = re.compile(r'(?:\bkubectl\b|KUBECTL_BIN).*\b(apply|create|patch|delete|scale|run)\b')
bootstrap_exists = bootstrap.is_file()

violations = []
for path in sorted(managed_root.rglob('*.sh')):
    if bootstrap_exists and path == bootstrap:
        continue
    for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        if 'auth can-i' in line:
            continue
        if mutation.search(line):
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

print('PASS: managed scripts contain no post-bootstrap imperative mutations; any bootstrap helper is limited to two audited apply commands.')
PY

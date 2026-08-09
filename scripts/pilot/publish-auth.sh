#!/usr/bin/env bash
# Compatibility entry point retained for the original pilot quickstart. Once the
# repository contains more than auth-api, environment activation must publish
# every discovered service with a real digest, so delegate to the suite publisher.
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: scripts/pilot/publish-auth.sh [auth-api-source]" >&2
  exit 2
fi
if [[ $# == 1 ]]; then
  export AUTH_API_SRC="$1"
fi

echo "publish-auth.sh now publishes the complete discovered service set." >&2
exec "$(dirname "$0")/publish-services.sh"

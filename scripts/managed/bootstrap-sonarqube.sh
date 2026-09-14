#!/usr/bin/env bash
# One-time, value-blind SonarQube bootstrap for the shared full-dev server
# (spec 009 T103/T111, research.md decision D-sonar). Rotates the factory
# default administrator credential, forces authentication on every project,
# creates the five fixed service project keys, provisions an analysis-only
# service identity, and streams its token straight into the selected-repository
# organization secret SONAR_TOKEN -- never through a PAT, never through a value
# this script prints, logs, or leaves on disk.
#
# Usage:
#   SONAR_HOST_URL=https://sonar-full-dev.microtodosuite.online \
#   SONAR_ADMIN_PASSWORD_FILE=/run/secrets/sonarqube-admin \
#     scripts/managed/bootstrap-sonarqube.sh
#
# SONAR_ADMIN_PASSWORD_FILE is the mounted/fetched value this run rotates the
# factory default into (the caller reads it from AWS Secrets Manager
# microtodosuite/tooling/sonarqube-admin, e.g. via a mounted Secret volume or
# `aws secretsmanager get-secret-value`; fetching it is out of this script's
# scope). This script only ever reads that file into an in-process variable --
# it is never echoed, logged, or re-written to disk, and mode must already be
# 0600 or the run refuses to start.
#
# Idempotent by design: it first checks whether the factory default
# admin/admin credential still authenticates. If it does not, a prior run
# already rotated it, so this run does nothing and exits 0 -- safe to wire
# into CI and re-run without re-touching a live server.
#
# No PAT: GitHub calls run through the caller's own already-authenticated `gh`
# session (`gh auth status`), never a token this script mints or stores.
set -euo pipefail

CURL_BIN="${CURL_BIN:-curl}"
GH_BIN="${GH_BIN:-gh}"
SONAR_HOST_URL="${SONAR_HOST_URL:?SONAR_HOST_URL is required, e.g. https://sonar-full-dev.microtodosuite.online}"
SONAR_ADMIN_PASSWORD_FILE="${SONAR_ADMIN_PASSWORD_FILE:?SONAR_ADMIN_PASSWORD_FILE is required: path to the mounted/fetched administrator credential}"
GITHUB_ORG="${GITHUB_ORG:-MicroTodoSuite}"
ANALYSIS_LOGIN="${SONAR_ANALYSIS_LOGIN:-ci-analysis}"

# The five fixed project keys already wired into every service's ci.yml
# sonar-project-key input (spec 009 T105-T109) -- this bootstrap must not
# invent different keys or the CI gate would target nonexistent projects.
SERVICES=(auth-api todos-api users-api frontend log-message-processor)
REPOS="microservice-app-auth-api,microservice-app-todos-api,microservice-app-users-api,microservice-app-frontend,microservice-app-log-message-processor"

err() { echo "ERROR: $*" >&2; exit 1; }

command -v "$CURL_BIN" >/dev/null 2>&1 || err "curl is required."
command -v "$GH_BIN" >/dev/null 2>&1 || err "gh is required."
"$GH_BIN" auth status >/dev/null 2>&1 || err "gh is not authenticated; this script never substitutes a PAT."

[[ -f "$SONAR_ADMIN_PASSWORD_FILE" ]] || err "SONAR_ADMIN_PASSWORD_FILE does not exist: $SONAR_ADMIN_PASSWORD_FILE"
mode="$(stat -f '%Lp' "$SONAR_ADMIN_PASSWORD_FILE" 2>/dev/null || stat -c '%a' "$SONAR_ADMIN_PASSWORD_FILE" 2>/dev/null || true)"
[[ "$mode" == "600" ]] || err "SONAR_ADMIN_PASSWORD_FILE must be mode 0600, found: ${mode:-unreadable}"

# Read once into a process-local variable; never echoed, logged, or persisted
# anywhere else. The trap clears every secret-bearing variable on any exit.
admin_new_password="$(cat "$SONAR_ADMIN_PASSWORD_FILE")"
[[ -n "$admin_new_password" ]] || err "SONAR_ADMIN_PASSWORD_FILE is empty."
analysis_token=""
throwaway_password=""
body="$(mktemp)"
cleanup() { admin_new_password=""; analysis_token=""; throwaway_password=""; rm -f "$body"; }
trap cleanup EXIT

# api <method> <path> <user> <pass> [--data-urlencode k=v ...]
# Never runs with `-v`/`set -x`: the only thing that ever reaches stdout is
# the HTTP status code, and the only thing written to disk is the response
# body, in a file this function's caller controls and never prints.
api() {
  local method="$1" path="$2" user="$3" pass="$4" body_file="$5"
  shift 5
  "$CURL_BIN" -s -o "$body_file" -w '%{http_code}' \
    -u "${user}:${pass}" -X "$method" "${SONAR_HOST_URL}${path}" "$@"
}

# --- idempotency guard: is the factory default credential still live? ------
code="$(api GET /api/authentication/validate admin admin "$body")"
if [[ "$code" != "200" ]] || ! grep -Fq '"valid":true' "$body"; then
  echo "OK: factory default administrator credential is no longer active; bootstrap already ran."
  exit 0
fi

# --- rotate the default administrator credential immediately ---------------
code="$(api POST /api/users/change_password admin admin "$body" \
  --data-urlencode "login=admin" \
  --data-urlencode "previousPassword=admin" \
  --data-urlencode "password=${admin_new_password}")"
[[ "$code" == "204" ]] || err "administrator password rotation failed (HTTP $code)."

# --- force authentication: no anonymous project access from here on --------
code="$(api POST /api/settings/set admin "$admin_new_password" "$body" \
  --data-urlencode "key=sonar.forceAuthentication" \
  --data-urlencode "value=true")"
[[ "$code" == "204" ]] || err "forcing authentication failed (HTTP $code)."

# --- create the five fixed, private project keys ----------------------------
for svc in "${SERVICES[@]}"; do
  code="$(api POST /api/projects/create admin "$admin_new_password" "$body" \
    --data-urlencode "project=MicroTodoSuite_${svc}" \
    --data-urlencode "name=${svc}" \
    --data-urlencode "visibility=private")"
  [[ "$code" == "200" ]] || err "creating project MicroTodoSuite_${svc} failed (HTTP $code)."
done

# --- analysis-only service identity: scan permission, nothing more ---------
# A local, disposable password: this identity is never used interactively,
# only through the generated token below, so the value only has to exist long
# enough to satisfy SonarQube's user-creation API and is discarded on exit.
# `head -c` closing early SIGPIPEs the upstream `tr` reading /dev/urandom;
# under `set -o pipefail` that reports as a failed pipeline even though the
# substitution captured exactly the 32 bytes wanted, so the trailing
# `|| true` is required, not decorative.
throwaway_password="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)" || true
code="$(api POST /api/users/create admin "$admin_new_password" "$body" \
  --data-urlencode "login=${ANALYSIS_LOGIN}" \
  --data-urlencode "name=CI analysis (no interactive login)" \
  --data-urlencode "password=${throwaway_password}" \
  --data-urlencode "local=true")"
[[ "$code" == "200" ]] || err "creating the analysis-only identity failed (HTTP $code)."

for svc in "${SERVICES[@]}"; do
  code="$(api POST /api/permissions/add_user admin "$admin_new_password" "$body" \
    --data-urlencode "login=${ANALYSIS_LOGIN}" \
    --data-urlencode "permission=scan" \
    --data-urlencode "projectKey=MicroTodoSuite_${svc}")"
  [[ "$code" == "204" ]] || err "granting scan permission on MicroTodoSuite_${svc} failed (HTTP $code)."
done

code="$(api POST /api/user_tokens/generate admin "$admin_new_password" "$body" \
  --data-urlencode "login=${ANALYSIS_LOGIN}" \
  --data-urlencode "name=ci-analysis-$(date +%s)" \
  --data-urlencode "type=GLOBAL_ANALYSIS_TOKEN")"
[[ "$code" == "200" ]] || err "generating the analysis-only token failed (HTTP $code)."
analysis_token="$(grep -oE '"token"\s*:\s*"[^"]+"' "$body" | sed -E 's/.*"([^"]+)"$/\1/')"
[[ -n "$analysis_token" ]] || err "SonarQube did not return a token."

# --- stream the token straight into the selected-repository org secret -----
# Piped over stdin: the value never touches a shell history entry, a file, or
# a process argument list (all of which `ps` or a shell log could expose).
printf '%s' "$analysis_token" | "$GH_BIN" secret set SONAR_TOKEN --org "$GITHUB_ORG" --repos "$REPOS"
"$GH_BIN" variable set SONAR_HOST_URL --org "$GITHUB_ORG" --repos "$REPOS" --body "$SONAR_HOST_URL"

echo "OK: administrator rotated, authentication forced, five projects created, analysis-only token issued and stored as the selected-repository SONAR_TOKEN secret."

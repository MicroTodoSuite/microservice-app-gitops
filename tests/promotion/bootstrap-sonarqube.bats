#!/usr/bin/env bash
# Contract test for the value-blind SonarQube bootstrap (spec 009 T103).
# Runs the real script against mocked `curl`/`gh` binaries (no live server, no
# live GitHub org) and asserts: administrator rotation, forced authentication,
# the five fixed project keys, an analysis-only token scoped to `scan` only,
# the token streamed to the exact selected-repository org secret, idempotency
# on a second run, and -- the property that matters most -- that neither the
# rotated administrator credential nor the generated token ever appears in the
# script's own stdout/stderr.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$repo_root/scripts/managed/bootstrap-sonarqube.sh"
workspace_root="$(cd "$repo_root/.." && pwd)"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -x "$script" ]] || fail "missing or non-executable scripts/managed/bootstrap-sonarqube.sh"

# Derive the expected five projects from what each sibling repo's ci.yml
# actually wires (T105-T109), the same cross-repo-contract style
# service-workflows.bats uses, so a drifted sonar-project-key would fail here
# too, not just silently target the wrong project.
declare -A REPO_DIR=(
  [auth-api]="$workspace_root/microservice-app-auth-api"
  [todos-api]="$workspace_root/microservice-app-todos-api"
  [users-api]="$workspace_root/microservice-app-users-api"
  [frontend]="$workspace_root/microservice-app-frontend"
  [log-message-processor]="$workspace_root/microservice-app-log-message-processor"
)
for svc in "${!REPO_DIR[@]}"; do
  ci="${REPO_DIR[$svc]}/.github/workflows/ci.yml"
  [[ -f "$ci" ]] || fail "missing sibling checkout for $svc: $ci"
  key="$(grep -E '^\s*sonar-project-key:' "$ci" | awk '{print $2}')"
  [[ "$key" == "MicroTodoSuite_${svc}" ]] || fail "$svc/ci.yml sonar-project-key is '$key', expected MicroTodoSuite_${svc}"
done

mock_dir="$(mktemp -d)"
mock_log="$mock_dir/calls.log"
: > "$mock_log"

# --- mock curl: canned SonarQube Web API responses, args recorded verbatim -
cat > "$mock_dir/curl" <<'MOCKCURL'
#!/usr/bin/env bash
set -euo pipefail
body_file="" method="GET" url="" userpass="" data=()
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  case "${args[$i]}" in
    -o) i=$((i+1)); body_file="${args[$i]}" ;;
    -u) i=$((i+1)); userpass="${args[$i]}" ;;
    -X) i=$((i+1)); method="${args[$i]}" ;;
    --data-urlencode) i=$((i+1)); data+=("${args[$i]}") ;;
    http*) url="${args[$i]}" ;;
  esac
  i=$((i+1))
done
path="${url#*MOCKHOST}"
{
  printf 'CALL %s %s %s' "$method" "$path" "$userpass"
  for d in "${data[@]:-}"; do printf ' %s' "$d"; done
  printf '\n'
} >> "$MOCK_LOG"

case "$path" in
  /api/authentication/validate)
    printf '{"valid":%s}' "${MOCK_AUTH_VALID:-true}" > "$body_file"
    printf '200' ;;
  /api/users/change_password) printf '' > "$body_file"; printf '204' ;;
  /api/settings/set) printf '' > "$body_file"; printf '204' ;;
  /api/projects/create) printf '{}' > "$body_file"; printf '200' ;;
  /api/users/create) printf '{}' > "$body_file"; printf '200' ;;
  /api/permissions/add_user) printf '' > "$body_file"; printf '204' ;;
  /api/user_tokens/generate)
    printf '{"token":"%s"}' "$MOCK_ANALYSIS_TOKEN" > "$body_file"
    printf '200' ;;
  *) echo "unmocked path: $path" >&2; exit 1 ;;
esac
MOCKCURL
chmod +x "$mock_dir/curl"

# --- mock gh: records org/repos/value, never a live call --------------------
cat > "$mock_dir/gh" <<'MOCKGH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  [[ -z "${MOCK_GH_AUTH_FAIL:-}" ]] && exit 0 || exit 1
fi
if [[ "$1" == "secret" && "$2" == "set" ]]; then
  name="$3"; shift 3
  org="" repos=""
  while [[ $# -gt 0 ]]; do
    case "$1" in --org) org="$2"; shift 2 ;; --repos) repos="$2"; shift 2 ;; *) shift ;; esac
  done
  value="$(cat)"
  printf 'SECRET %s %s %s %s\n' "$name" "$org" "$repos" "$value" >> "$MOCK_LOG"
  exit 0
fi
if [[ "$1" == "variable" && "$2" == "set" ]]; then
  name="$3"; shift 3
  org="" repos="" value=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --org) org="$2"; shift 2 ;;
      --repos) repos="$2"; shift 2 ;;
      --body) value="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  printf 'VARIABLE %s %s %s %s\n' "$name" "$org" "$repos" "$value" >> "$MOCK_LOG"
  exit 0
fi
echo "unmocked gh invocation: $*" >&2
exit 1
MOCKGH
chmod +x "$mock_dir/gh"

# The real curl needs to know the fake host to strip it back to a path; sed it
# into the mock at run time rather than hardcoding a host in the mock itself.
sed -i.bak "s#MOCKHOST#sonar-fake.example#" "$mock_dir/curl" && rm "$mock_dir/curl.bak"

password_file="$mock_dir/admin-password"
printf 'N3wAdm1nSecr3t!' > "$password_file"
chmod 600 "$password_file"

expected_repos="microservice-app-auth-api,microservice-app-todos-api,microservice-app-users-api,microservice-app-frontend,microservice-app-log-message-processor"
fake_token="FAKE-ANALYSIS-TOKEN-XYZ-0000000000000000"

run_bootstrap() {
  : > "$mock_log"
  PATH="$mock_dir:$PATH" \
  MOCK_LOG="$mock_log" \
  MOCK_AUTH_VALID="${1:-true}" \
  MOCK_ANALYSIS_TOKEN="$fake_token" \
  SONAR_HOST_URL="https://sonar-fake.example" \
  SONAR_ADMIN_PASSWORD_FILE="$password_file" \
  "$script" > "$mock_dir/stdout" 2> "$mock_dir/stderr"
}

# --- first run: full bootstrap -----------------------------------------------
run_bootstrap true

grep -Fq 'N3wAdm1nSecr3t!' "$mock_dir/stdout" "$mock_dir/stderr" && \
  fail "the rotated administrator credential leaked into the script's own output."
grep -Fq "$fake_token" "$mock_dir/stdout" "$mock_dir/stderr" && \
  fail "the generated analysis token leaked into the script's own output."

grep -Fq "CALL POST /api/users/change_password admin:admin login=admin previousPassword=admin password=N3wAdm1nSecr3t!" "$mock_log" || \
  fail "did not rotate the factory default administrator credential with the exact fetched value."

grep -Fq "CALL POST /api/settings/set admin:N3wAdm1nSecr3t! key=sonar.forceAuthentication value=true" "$mock_log" || \
  fail "did not force authentication after rotating the credential."

for svc in auth-api todos-api users-api frontend log-message-processor; do
  grep -Fq "CALL POST /api/projects/create admin:N3wAdm1nSecr3t! project=MicroTodoSuite_${svc} name=${svc} visibility=private" "$mock_log" || \
    fail "did not create the private project MicroTodoSuite_${svc}."
  grep -Fq "CALL POST /api/permissions/add_user admin:N3wAdm1nSecr3t! login=ci-analysis permission=scan projectKey=MicroTodoSuite_${svc}" "$mock_log" || \
    fail "did not grant scan-only permission to ci-analysis on MicroTodoSuite_${svc}."
done

grep -F 'CALL POST /api/users/create' "$mock_log" | grep -Fq 'login=ci-analysis' || \
  fail "did not create the ci-analysis service identity."
grep -F 'CALL POST /api/user_tokens/generate' "$mock_log" | grep -Fq 'type=GLOBAL_ANALYSIS_TOKEN' || \
  fail "did not request a GLOBAL_ANALYSIS_TOKEN (not a user session token)."

grep -Fq "SECRET SONAR_TOKEN MicroTodoSuite $expected_repos $fake_token" "$mock_log" || \
  fail "did not stream the generated token into the exact selected-repository SONAR_TOKEN secret."
grep -Fq "VARIABLE SONAR_HOST_URL MicroTodoSuite $expected_repos https://sonar-fake.example" "$mock_log" || \
  fail "did not set the selected-repository SONAR_HOST_URL variable."

# --- idempotency: the credential is already rotated on a second run ---------
run_bootstrap false
grep -Fq 'already ran' "$mock_dir/stdout" || fail "did not report idempotent no-op when the default credential is already rotated."
other_calls="$(grep -v 'authentication/validate' "$mock_log" || true)"
[[ -z "$other_calls" ]] || fail "an idempotent run made calls beyond the one-time authentication check: $other_calls"

# --- refuses to run without gh authenticated (no PAT substitute) -----------
: > "$mock_log"
if PATH="$mock_dir:$PATH" MOCK_LOG="$mock_log" MOCK_GH_AUTH_FAIL=1 \
   SONAR_HOST_URL="https://sonar-fake.example" SONAR_ADMIN_PASSWORD_FILE="$password_file" \
   "$script" >/dev/null 2>/dev/null; then
  fail "must refuse to run when gh is not authenticated, rather than falling back to a PAT."
fi

# --- refuses a loosely permissioned credential file -------------------------
loose_file="$mock_dir/loose-password"
printf 'whatever' > "$loose_file"
chmod 644 "$loose_file"
if PATH="$mock_dir:$PATH" MOCK_LOG="$mock_log" \
   SONAR_HOST_URL="https://sonar-fake.example" SONAR_ADMIN_PASSWORD_FILE="$loose_file" \
   "$script" >/dev/null 2>/dev/null; then
  fail "must refuse a SONAR_ADMIN_PASSWORD_FILE that is not mode 0600."
fi

rm -rf "$mock_dir"
printf 'PASS: bootstrap-sonarqube rotates the default administrator, forces authentication, creates the five fixed private projects, issues a scan-only analysis token, streams it to the exact selected-repository SONAR_TOKEN secret, is idempotent, refuses an unauthenticated gh session, refuses a loosely permissioned credential file, and never leaks the administrator credential or the token into its own output.\n'

#!/usr/bin/env bash
# Managed cluster bootstrap helper (spec 009, T044).
#
# Bootstrapping is the one place the constitution allows a direct mutation of a
# managed cluster, so the helper's value is entirely in what it refuses. Three
# refusals matter most, because each one is a mistake that otherwise succeeds
# quietly:
#
#   - wrong account or wrong cluster: the two applies land on a real cluster,
#     just not the intended one, and nothing reports an error;
#   - unmerged revision: ArgoCD is handed a Git root nobody reviewed, and it
#     then reconciles that unreviewed state forever;
#   - checksum mismatch: the rendered ArgoCD manifest is not the reviewed one,
#     which is the supply-chain case the render pin exists for.
#
# The third-mutation check guards the boundary itself: two applies create the
# reconciler and give it its root, and anything beyond that is desired state
# that belongs in Git.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BOOTSTRAP="$ROOT/scripts/managed/bootstrap-cluster.sh"
FIXTURES="$ROOT/tests/bootstrap/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

[[ -x "$BOOTSTRAP" ]] || {
  printf 'FAIL: bootstrap helper is missing or not executable: %s\n' "$BOOTSTRAP" >&2
  exit 1
}

# Runs the helper against a fixture. Prints the exit code; the transcript is
# written to $TMP/<name>.transcript.
run_bootstrap() {
  local fixture="$1" name="$2"
  shift 2
  local rc=0
  BOOTSTRAP_FIXTURE_DIR="$FIXTURES/$fixture" \
  PATH="$FIXTURES/$fixture/bin:$PATH" \
    "$BOOTSTRAP" \
      --cluster "microtodosuite-full-dev" \
      --expected-account "916491575487" \
      --revision "main" \
      --root-app "clusters/eks-full-dev/root-app.yaml" \
      --transcript "$TMP/$name.transcript" \
      --render-pin "$FIXTURES/render-canonical.sha256" \
      "$@" >"$TMP/$name.out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# --- the happy path: exactly two mutations ---------------------------------
rc="$(run_bootstrap valid two-mutations)"
[[ "$rc" -eq 0 ]] || fail "a valid bootstrap must succeed (exit $rc): $(cat "$TMP/two-mutations.out")"

if [[ -f "$TMP/two-mutations.transcript" ]]; then
  mutations="$(grep -c '^MUTATION ' "$TMP/two-mutations.transcript" || true)"
  [[ "$mutations" -eq 2 ]] \
    || fail "a valid bootstrap must record exactly two mutations, recorded $mutations"

  grep -q '^MUTATION 1 apply bootstrap/argocd' "$TMP/two-mutations.transcript" \
    || fail "the first mutation must be the checksum-pinned ArgoCD render"
  grep -q '^MUTATION 2 apply clusters/eks-full-dev/root-app.yaml' "$TMP/two-mutations.transcript" \
    || fail "the second mutation must be the tracked root Application"

  # Everything else in the transcript must be a read.
  if grep -E '^(MUTATION|READ) ' "$TMP/two-mutations.transcript" \
    | grep -vE '^(MUTATION [12] |READ )' >/dev/null; then
    fail "the transcript must contain only two mutations and reads"
  fi

  # The transcript is evidence and gets committed; it must carry no secrets.
  grep -qiE '(BEGIN [A-Z ]*PRIVATE KEY|bearer [A-Za-z0-9._-]{20,})' "$TMP/two-mutations.transcript" \
    && fail "the transcript must not record credential material"
else
  fail "a valid bootstrap must write a transcript"
fi

# --- wrong account ---------------------------------------------------------
rc="$(run_bootstrap wrong-account wrong-account)"
[[ "$rc" -ne 0 ]] || fail "a bootstrap against the wrong AWS account must fail"
grep -qi 'account' "$TMP/wrong-account.out" \
  || fail "the wrong-account failure must name the account mismatch"
if [[ -f "$TMP/wrong-account.transcript" ]]; then
  mutations="$(grep -c '^MUTATION ' "$TMP/wrong-account.transcript" || true)"
  [[ "$mutations" -eq 0 ]] \
    || fail "a wrong-account bootstrap must mutate nothing, recorded $mutations"
fi

# --- wrong cluster ---------------------------------------------------------
rc="$(run_bootstrap wrong-cluster wrong-cluster)"
[[ "$rc" -ne 0 ]] || fail "a bootstrap pointed at the wrong cluster must fail"
grep -qi 'cluster' "$TMP/wrong-cluster.out" \
  || fail "the wrong-cluster failure must name the cluster mismatch"
if [[ -f "$TMP/wrong-cluster.transcript" ]]; then
  mutations="$(grep -c '^MUTATION ' "$TMP/wrong-cluster.transcript" || true)"
  [[ "$mutations" -eq 0 ]] \
    || fail "a wrong-cluster bootstrap must mutate nothing, recorded $mutations"
fi

# --- unmerged revision -----------------------------------------------------
# The root Application's revision must already be on protected main. Handing
# ArgoCD an unmerged revision makes it reconcile unreviewed desired state.
rc="$(run_bootstrap unmerged-revision unmerged)"
[[ "$rc" -ne 0 ]] || fail "a bootstrap on an unmerged revision must fail"
grep -qiE 'revision|merged|main' "$TMP/unmerged.out" \
  || fail "the unmerged-revision failure must name the revision problem"
if [[ -f "$TMP/unmerged.transcript" ]]; then
  mutations="$(grep -c '^MUTATION ' "$TMP/unmerged.transcript" || true)"
  [[ "$mutations" -eq 0 ]] \
    || fail "an unmerged-revision bootstrap must mutate nothing, recorded $mutations"
fi

# --- checksum mismatch -----------------------------------------------------
rc="$(run_bootstrap checksum-mismatch checksum)"
[[ "$rc" -ne 0 ]] || fail "a bootstrap with a mismatched ArgoCD render checksum must fail"
grep -qiE 'checksum|sha256' "$TMP/checksum.out" \
  || fail "the checksum failure must name the checksum mismatch"
if [[ -f "$TMP/checksum.transcript" ]]; then
  mutations="$(grep -c '^MUTATION ' "$TMP/checksum.transcript" || true)"
  [[ "$mutations" -eq 0 ]] \
    || fail "a checksum mismatch must be caught before any mutation, recorded $mutations"
fi

# --- a third mutation ------------------------------------------------------
# The boundary is two applies. A fixture that induces a third must be refused,
# because everything past the root Application is desired state that belongs in
# Git and must arrive through ArgoCD.
rc="$(run_bootstrap third-mutation third --extra-apply infrastructure/keda)"
[[ "$rc" -ne 0 ]] || fail "a third mutation must be refused"
grep -qiE 'third|boundary|two' "$TMP/third.out" \
  || fail "the third-mutation failure must name the two-mutation boundary"
if [[ -f "$TMP/third.transcript" ]]; then
  mutations="$(grep -c '^MUTATION ' "$TMP/third.transcript" || true)"
  [[ "$mutations" -le 2 ]] \
    || fail "no more than two mutations may ever be recorded, recorded $mutations"
fi

# --- already bootstrapped --------------------------------------------------
# Re-running against a cluster that already has ArgoCD must verify read-only
# rather than re-apply. A second bootstrap of a live cluster is not a recovery
# path.
rc="$(run_bootstrap already-bootstrapped already)"
[[ "$rc" -eq 0 ]] || fail "a cluster that already has ArgoCD must verify successfully (exit $rc)"
if [[ -f "$TMP/already.transcript" ]]; then
  mutations="$(grep -c '^MUTATION ' "$TMP/already.transcript" || true)"
  [[ "$mutations" -eq 0 ]] \
    || fail "an already-bootstrapped cluster must be verified read-only, recorded $mutations"
fi

if [[ "$failures" -gt 0 ]]; then
  printf '\n%d check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf 'PASS: managed cluster bootstrap honours its identity, revision, checksum, and two-mutation boundary.\n'

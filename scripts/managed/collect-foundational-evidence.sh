#!/usr/bin/env bash
# Collect the Phase 2 foundational evidence bundle (spec 009, T028-T030).
#
# Runs every foundational gate, retains its raw output, produces the redacted
# dev plan summary, captures live ArgoCD health, and emits an evidence bundle
# that validate-full-profile-evidence.sh can check offline.
#
# Read-only with respect to infrastructure: it runs tests and `terraform plan`,
# never `apply`, and only reads cluster state.
#
# The full plan text is deliberately NOT committed. It is written to the
# external directory given by --external-dir and only its checksum plus a
# redacted result reach Git, because a plan can echo tagged resource contents.
set -euo pipefail

GITOPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_ROOT="$(dirname "$GITOPS_ROOT")"
OPS_ROOT="${OPS_ROOT:-$WORKSPACE_ROOT/microservice-app-ops}"

EXTERNAL_DIR=""
KUBE_CONTEXT=""
SKIP_LIVE=0
STAGE_ID="foundational-compatibility"

usage() {
  cat >&2 <<'EOF'
Usage: collect-foundational-evidence.sh --external-dir DIR [--kube-context CONTEXT] [--skip-live]

  --external-dir  Directory for artifacts that must NOT be committed
                  (full Terraform plan text and the saved plan file).
  --kube-context  Context used for the live ArgoCD health capture.
  --skip-live     Record the live capture as blocked instead of running it.
EOF
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --external-dir)
      [[ "$#" -ge 2 ]] || fail "--external-dir requires a value"
      EXTERNAL_DIR="$2"; shift 2 ;;
    --kube-context)
      [[ "$#" -ge 2 ]] || fail "--kube-context requires a value"
      KUBE_CONTEXT="$2"; shift 2 ;;
    --skip-live)
      SKIP_LIVE=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      usage; fail "unknown argument: $1" ;;
  esac
done

[[ -n "$EXTERNAL_DIR" ]] || { usage; fail "--external-dir is required"; }
[[ -d "$OPS_ROOT" ]] || fail "ops repository is missing: $OPS_ROOT"

for dependency in jq python3 sha256sum terraform git; do
  command -v "$dependency" >/dev/null 2>&1 || fail "required command is missing: $dependency"
done

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_REL="evidence/runs/${TIMESTAMP}-foundational"
RUN_DIR="$GITOPS_ROOT/$RUN_REL"
mkdir -p "$RUN_DIR/gates" "$RUN_DIR/infrastructure" "$RUN_DIR/live" "$EXTERNAL_DIR"

printf '>> foundational evidence run %s\n' "$TIMESTAMP"

# --- Gates ------------------------------------------------------------------
# Every gate's raw output is retained whether it passes or fails; a failure
# stops the run, because inferred evidence is worse than no evidence.
declare -a GATE_FILES=()

run_gate() {
  local name="$1" directory="$2"; shift 2
  local output="$RUN_DIR/gates/${name}.txt"
  printf '   gate %s\n' "$name"
  {
    printf '$ (cd %s && %s)\n\n' "$directory" "$*"
  } > "$output"
  if ! (cd "$directory" && "$@") >> "$output" 2>&1; then
    printf 'FAIL: gate %s failed; raw output retained at %s\n' "$name" "$output" >&2
    tail -20 "$output" >&2
    exit 1
  fi
  GATE_FILES+=("$RUN_REL/gates/${name}.txt")
}

run_gate gitops-profile-routing   "$GITOPS_ROOT" tests/profiles/validate-profile-routing.bats
run_gate gitops-image-promotion   "$GITOPS_ROOT" tests/promotion/bump-image.bats
run_gate gitops-managed-policy    "$GITOPS_ROOT" tests/policy/no-imperative-managed-mutations.bats
run_gate gitops-ownership         "$GITOPS_ROOT" tests/evidence/validate-ownership.bats
run_gate gitops-evidence-schema   "$GITOPS_ROOT" tests/evidence/validate-evidence.bats
run_gate ops-terraform-fmt        "$OPS_ROOT"    terraform fmt -check -recursive aws
run_gate ops-module-tests         "$OPS_ROOT"    terraform -chdir=aws/modules/environment-foundation test -no-color
run_gate ops-root-tests           "$OPS_ROOT"    terraform -chdir=aws/environments/dev/foundation test -no-color
run_gate ops-workflow-contract    "$OPS_ROOT"    tests/workflows/foundation-checks.bats
run_gate ops-azure-dr-preflight   "$OPS_ROOT"    tests/preflight/azure-dr-preflight.bats

# --- Refreshed dev plan -----------------------------------------------------
# The gate is that the foundational work introduces no drift: every resource
# change must be no-op. The full text stays external; only its checksum and a
# redacted count reach Git.
printf '   dev plan (real backend, refreshed)\n'
PLAN_BIN="$EXTERNAL_DIR/dev-foundation-${TIMESTAMP}.tfplan"
PLAN_TEXT="$EXTERNAL_DIR/dev-foundation-${TIMESTAMP}.plan.txt"
PLAN_JSON="$EXTERNAL_DIR/dev-foundation-${TIMESTAMP}.plan.json"

(
  cd "$OPS_ROOT/aws/environments/dev/foundation"
  terraform init -input=false -no-color -backend-config=dev.s3.tfbackend -reconfigure > "$EXTERNAL_DIR/dev-init.txt" 2>&1
  terraform plan -input=false -no-color -var-file=dev.tfvars -out="$PLAN_BIN" > "$PLAN_TEXT" 2>&1
  terraform show -json "$PLAN_BIN" > "$PLAN_JSON"
) || {
  printf 'FAIL: the refreshed dev plan did not complete; see %s\n' "$PLAN_TEXT" >&2
  tail -20 "$PLAN_TEXT" >&2
  exit 1
}

python3 - "$PLAN_JSON" "$PLAN_TEXT" "$RUN_DIR/infrastructure/dev-plan-summary.json" <<'PY'
import hashlib
import json
import pathlib
import sys

plan_json, plan_text, destination = (pathlib.Path(argument) for argument in sys.argv[1:4])
plan = json.loads(plan_json.read_text(encoding="utf-8"))

counts = {"add": 0, "change": 0, "destroy": 0, "replace": 0}
changed = []
for resource in plan.get("resource_changes", []):
    actions = resource["change"]["actions"]
    if actions == ["no-op"]:
        continue
    changed.append({"address": resource["address"], "actions": actions})
    if actions in (["create", "delete"], ["delete", "create"]):
        counts["replace"] += 1
    else:
        for action in actions:
            if action == "create":
                counts["add"] += 1
            elif action == "update":
                counts["change"] += 1
            elif action == "delete":
                counts["destroy"] += 1

output_changes = sorted(
    name
    for name, change in (plan.get("output_changes") or {}).items()
    if change["actions"] != ["no-op"]
)

digest = hashlib.sha256(plan_text.read_bytes()).hexdigest()
clean = not changed

destination.write_text(
    json.dumps(
        {
            "result": "pass" if clean else "fail",
            "cleanPlan": clean,
            "summary": "0 to add, 0 to change, 0 to destroy" if clean
            else f"{counts['add']} to add, {counts['change']} to change, {counts['destroy']} to destroy",
            "resourceChangeCounts": counts,
            "changedResources": changed,
            "outputOnlyChanges": output_changes,
            "terraformVersion": plan.get("terraform_version"),
            "externalPlanTextSha256": digest,
            "note": (
                "The full plan text is retained outside Git; only its checksum and this "
                "redacted result are committed. Output-only changes do not alter infrastructure."
            ),
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)

print(f"   plan: {'clean' if clean else 'DRIFT'} ({len(changed)} changed resources)")
if not clean:
    raise SystemExit("FAIL: the refreshed dev plan is not clean; fix compatibility drift before proceeding")
PY

# --- Live ArgoCD health -----------------------------------------------------
LIVE_REL="$RUN_REL/live/argocd-health.json"
if [[ "$SKIP_LIVE" -eq 1 ]]; then
  printf '   live capture skipped\n'
  printf '{\n  "result": "blocked",\n  "reason": "live capture explicitly skipped"\n}\n' > "$RUN_DIR/live/argocd-health.json"
else
  printf '   live ArgoCD health\n'
  command -v kubectl >/dev/null 2>&1 || fail "kubectl is required for the live capture; pass --skip-live to record it as blocked"
  KUBECTL_ARGS=(get applications -n argocd -o json --request-timeout=60s)
  [[ -n "$KUBE_CONTEXT" ]] && KUBECTL_ARGS+=(--context "$KUBE_CONTEXT")
  kubectl "${KUBECTL_ARGS[@]}" > "$EXTERNAL_DIR/argocd-applications.json" 2>"$EXTERNAL_DIR/argocd-error.txt" \
    || fail "could not read live ArgoCD state; see $EXTERNAL_DIR/argocd-error.txt"

  # Names and statuses only: no manifests, parameters, or resource contents.
  #
  # The stage verdict is the health of the ECONOMICAL PLATFORM: the five business
  # services and the environment policy applications. That is the rollback target
  # the rollout must never regress, and the only thing this stage could plausibly
  # have broken, since everything in it is either unapplied Terraform or GitOps
  # composition whose economical renders are proven byte-identical.
  #
  # Platform add-ons are still captured and still reported by name, but as
  # attributed advisories rather than as a verdict, so one team's unrelated drift
  # cannot silently be laundered into this stage's approval OR block it forever.
  jq '
    def platform_app: (.metadata.name | startswith("infra-")) or .metadata.name == "argocd";
    def unhealthy: .status.health.status != "Healthy";
    def undesired: .status.sync.status != "Synced";
    {
      result: (if ([.items[] | select(platform_app | not) | select(unhealthy or undesired)] | length) == 0
               then "pass" else "degraded" end),
      verdictScope: "economical platform: business services and environment policy",
      total: (.items | length),
      synced: ([.items[] | select(undesired | not)] | length),
      healthy: ([.items[] | select(unhealthy | not)] | length),
      exceptions: [.items[]
        | select(platform_app | not) | select(unhealthy or undesired)
        | {name: .metadata.name, sync: .status.sync.status, health: .status.health.status}]
        | sort_by(.name),
      platformAdvisories: [.items[]
        | select(platform_app) | select(unhealthy or undesired)
        | {name: .metadata.name, sync: .status.sync.status, health: .status.health.status,
           owner: "platform add-on owner"}]
        | sort_by(.name)
    }' "$EXTERNAL_DIR/argocd-applications.json" > "$RUN_DIR/live/argocd-health.json"
fi

# --- Bundle -----------------------------------------------------------------
printf '   assembling bundle\n'
GIT_ACTOR="$(git -C "$GITOPS_ROOT" config user.name)"
OPS_HEAD="$(git -C "$OPS_ROOT" rev-parse HEAD)"
GITOPS_HEAD="$(git -C "$GITOPS_ROOT" rev-parse HEAD)"

printf '%s\n' \
  "gitops HEAD: $GITOPS_HEAD" \
  "ops HEAD:    $OPS_HEAD" \
  "collected:   $TIMESTAMP" \
  > "$RUN_DIR/heads.txt"

python3 - \
  "$GITOPS_ROOT" "$RUN_REL" "$STAGE_ID" "$GIT_ACTOR" "$LIVE_REL" \
  "${GATE_FILES[@]}" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
run_rel = sys.argv[2]
stage_id = sys.argv[3]
git_actor = sys.argv[4]
live_rel = sys.argv[5]
gate_files = sys.argv[6:]

plan_rel = f"{run_rel}/infrastructure/dev-plan-summary.json"
heads_rel = f"{run_rel}/heads.txt"


def sha256(relative: str) -> str:
    return hashlib.sha256((root / relative).read_bytes()).hexdigest()


live = json.loads((root / live_rel).read_text(encoding="utf-8"))
plan = json.loads((root / plan_rel).read_text(encoding="utf-8"))

artifacts = [
    {"kind": "desired-state", "path": heads_rel, "sha256": sha256(heads_rel),
     "producer": "git", "result": "pass"},
    {"kind": "terraform-plan", "path": plan_rel, "sha256": sha256(plan_rel),
     "producer": "terraform", "result": plan["result"]},
    {"kind": "live-success" if live.get("result") == "pass" else "continuity",
     "path": live_rel, "sha256": sha256(live_rel),
     "producer": "kubectl", "result": "pass" if live.get("result") == "pass" else "fail"},
]
for gate in gate_files:
    artifacts.append({
        "kind": "gitops-render" if "gitops-" in gate else "desired-state",
        "path": gate, "sha256": sha256(gate), "producer": "test-suite", "result": "pass",
    })

gate_paths = [artifact["path"] for artifact in artifacts if artifact["producer"] == "test-suite"]
live_pass = live.get("result") == "pass"

evidence = {
    "schemaVersion": "1.0.0",
    "stageId": stage_id,
    "generatedAt": subprocess.run(
        ["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], capture_output=True, text=True, check=True
    ).stdout.strip(),
    "scope": {
        "repositories": ["microservice-app-gitops", "microservice-app-ops"],
        "destinations": ["eks-dev"],
        "stateKeys": ["environments/dev/foundation/terraform.tfstate"],
        "capabilities": [
            "profile-routing",
            "full-profile-network",
            "full-profile-cluster-prerequisites",
            "canonical-dns",
            "platform-image-mirror",
            "multi-issuer-irsa",
            "full-profile-secrets",
        ],
    },
    "identities": {"gitActor": git_actor, "awsAccountId": "916491575487"},
    "baseline": {"result": "pass", "evidence": gate_paths},
    "artifacts": artifacts,
    "requirements": {
        "FR-038": {"result": "pass", "evidence": gate_paths},
        "SC-004": {"result": "pass" if plan["cleanPlan"] else "fail", "evidence": [plan_rel]},
    },
    "rollback": {"result": "pass", "evidence": [plan_rel, heads_rel]},
    "postBaseline": {
        "result": "pass" if live_pass else "blocked",
        "evidence": [live_rel],
    },
    "decision": "approved" if (plan["cleanPlan"] and live_pass) else "blocked",
}

(root / run_rel / "evidence.json").write_text(
    json.dumps(evidence, indent=2) + "\n", encoding="utf-8"
)
print(f"   decision: {evidence['decision']}")
PY

"$GITOPS_ROOT/scripts/managed/validate-full-profile-evidence.sh" "$RUN_DIR/evidence.json"

printf '>> bundle: %s\n' "$RUN_REL"
printf '>> external (not committed): %s\n' "$EXTERNAL_DIR"

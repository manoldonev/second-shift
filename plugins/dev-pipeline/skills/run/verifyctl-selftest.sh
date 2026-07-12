#!/usr/bin/env bash
# verifyctl-selftest.sh — fixture-based verification of verifyctl.sh's contract.
#
# Runs against a synthetic git repo + a PATH-shimmed `yarn` whose behavior is
# driven by marker files; never runs a real suite. Independent of any pipeline
# state on disk (fresh mktemp dir + STATECTL_STATE_DIR pin — same posture as
# statectl-selftest.sh).
#
# Usage:
#   .claude/skills/run/verifyctl-selftest.sh
#
# Exit code = number of failed tests (0 = all pass).

set -uo pipefail

# Sibling plugin files resolve against this script's own dir (skills/run/).
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFYCTL="${SKILL_DIR}/verifyctl.sh"
STATECTL="${SKILL_DIR}/statectl.sh"

[[ -x "$VERIFYCTL" ]] || { echo "[self-test] FATAL: $VERIFYCTL not executable"; exit 99; }
[[ -x "$STATECTL" ]] || { echo "[self-test] FATAL: $STATECTL not executable"; exit 99; }

TMPDIR_VT=$(mktemp -d -t verifyctl-selftest.XXXXXX)
trap 'rm -rf "$TMPDIR_VT"' EXIT INT TERM
cd "$TMPDIR_VT" || exit 99
mkdir -p .claude/pipeline-state
# Pin the state dir to the fixture tmp dir (statectl AND verifyctl honor it) —
# without this both resolve the MAIN checkout's pipeline-state via git.
export STATECTL_STATE_DIR="$TMPDIR_VT/.claude/pipeline-state"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

STATE=".claude/pipeline-state/8888.json"
SIDECAR=".claude/pipeline-state/8888-verify.json"

# ---- yarn shim (PATH-prepended) — behavior driven by marker files ------------
MARKERS="$TMPDIR_VT/markers"
SHIM_BIN="$TMPDIR_VT/bin"
mkdir -p "$MARKERS" "$SHIM_BIN"
cat > "$SHIM_BIN/yarn" <<'SHIM'
#!/usr/bin/env bash
# Test shim: `yarn <script> [args...]`, invoked from cwd = the worktree.
# verifyctl runs the CONFIGURED commands (e.g. `yarn lint`) after cd'ing into
# the worktree — a generic `cd <wt> && <cmd>` shape, not `yarn --cwd <wt>` — so
# the worktree is $PWD here, not an argument. Behavior via $VERIFYCTL_TEST_MARKERS.
M="${VERIFYCTL_TEST_MARKERS:?}"
WT="$PWD"; SCRIPT="${1:-}"; shift || true
touch "$M/ran-${SCRIPT//:/_}$( [[ "$*" == *--fix* ]] && echo '-fix' )"
[[ -f "$M/INFRA" ]] && exit 127
case "$SCRIPT" in
  install) exit 0 ;;
  workspaces) exit 0 ;;   # `yarn workspaces foreach ... run build` (packages build)
  type-check) [[ -f "$M/FAIL_TYPE_CHECK" ]] && { echo "src/x.ts(1,1): error TS2322: type mismatch"; exit 2; }; exit 0 ;;
  lint)
    if [[ "$*" == *--fix* ]]; then
      # Simulate a successful autofix: clear the failure + dirty a tracked file.
      if [[ -f "$M/LINT_FIXABLE" ]]; then
        rm -f "$M/FAIL_LINT"
        echo "// autofixed" >> "$WT/src/thing.ts"
      fi
      exit 0
    fi
    [[ -f "$M/FAIL_LINT" ]] && { echo "1:1 error no-unused-vars"; exit 1; }
    exit 0
    ;;
  test) [[ -f "$M/FAIL_TEST" ]] && { echo "FAIL src/thing.spec.ts"; exit 1; }; exit 0 ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$SHIM_BIN/yarn"
export VERIFYCTL_TEST_MARKERS="$MARKERS"
export PATH="$SHIM_BIN:$PATH"

# ---- git fixture --------------------------------------------------------------
WORK="$TMPDIR_VT/work"
mkdir -p "$WORK/src"
git -C "$WORK" init -q -b main 2>/dev/null || { git -C "$WORK" init -q && git -C "$WORK" checkout -qb main; }
git -C "$WORK" config user.email t@t && git -C "$WORK" config user.name t
echo '{"devDependencies": {"prettier": "3.0.0"}}' > "$WORK/package.json"
# node_modules present ⇒ the install-if-missing step skips; prettier resolves
# from the worktree's own .bin.
mkdir -p "$WORK/node_modules/.bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/node_modules/.bin/prettier"
chmod +x "$WORK/node_modules/.bin/prettier"
echo "export const x = 1" > "$WORK/src/thing.ts"
git -C "$WORK" add -A && git -C "$WORK" commit -qm init
# Synthetic origin/main ref — no real remote needed for merge-base.
git -C "$WORK" update-ref refs/remotes/origin/main HEAD
git -C "$WORK" checkout -qb feature

# ---- consumer config fixture ---------------------------------------------------
# verifyctl reads the command truth table + host base branch from the consumer
# config (mandatory — it never guesses commands). Reproduce acme's shape so
# the yarn shim is exercised exactly as before: monorepo host "mono", setup
# lanes (install + packages build) then the lint/type-check/test trio.
CONFIG_FIXTURE="$TMPDIR_VT/second-shift.config.json"
cat > "$CONFIG_FIXTURE" <<'CFG'
{
  "configVersion": 1,
  "tracker": { "type": "github" },
  "topology": { "type": "monorepo", "repos": { "mono": { "path": ".", "baseBranch": "main" } } },
  "commands": {
    "mono": {
      "lint": "yarn lint", "lintAutofixes": true,
      "typecheck": "yarn type-check", "test": "yarn test",
      "lanes": [
        { "name": "install", "commands": ["yarn install --immutable"] },
        { "name": "workspaces", "commands": ["yarn workspaces foreach -A -t --include 'packages/*' run build"] }
      ],
      "extraLanes": [
        { "name": "contract-check", "commands": ["true"], "failureClass": "TEST_FAILURE" }
      ]
    }
  }
}
CFG
export SECOND_SHIFT_CONFIG="$CONFIG_FIXTURE"

# ---- state fixture -------------------------------------------------------------
# worktreePath is written ABSOLUTE via raw jq (fixture-only; production paths are
# repo-relative via worktree-set — verifyctl passes an absolute value through).
reset_all() {
  rm -f .claude/pipeline-state/*.json .claude/pipeline-state/*.log .claude/pipeline-state/*.tmp
  rm -f "$MARKERS"/*
  "$STATECTL" init 8888 --run-id "vrun-$$" >/dev/null
  jq --arg wt "$WORK" '.worktreePath = $wt | .worktreeBase = "main"' \
    "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

vrun() { # runs verifyctl, captures stdout json to $VERDICT and rc to $VRC
  VERDICT=$("$VERIFYCTL" run 8888 "$@" 2>/dev/null)
  VRC=$?
}

attempts() { "$STATECTL" get 8888 ".verifyAttempts.${1} // 0"; }

echo "[self-test] verifyctl — lanes, classification, attempt accounting"

# (v1) INERT lane on md-only diff (via is-inert-diff.sh); verdict parses; sidecar pass
reset_all
echo "# doc" > "$WORK/README.md"
git -C "$WORK" add -A && git -C "$WORK" commit -qm docs
vrun
lane=$(jq -r '.lane' <<< "$VERDICT" 2>/dev/null)
vs=$(jq -r '.verifySummary' <<< "$VERDICT" 2>/dev/null)
sc_status=$(jq -r '.status' "$SIDECAR" 2>/dev/null)
if [[ "$VRC" == "0" && "$lane" == "INERT" && "$vs" == *"inert diff"* && "$sc_status" == "pass" ]]; then
  pass "(v1) INERT lane on md-only diff — verdict parses, skipped-string verifySummary, pass sidecar"
else
  fail "(v1) INERT lane — rc=$VRC lane=$lane vs='$vs' sidecar=$sc_status"
fi

# (v2) default-to-SUITE when the diff has a TS surface; clean run passes;
#      packages build + all three concurrent commands ran
reset_all
echo "export const y = 2" >> "$WORK/src/thing.ts"
git -C "$WORK" add -A && git -C "$WORK" commit -qm feat
vrun
lane=$(jq -r '.lane' <<< "$VERDICT")
tsc=$(jq -r '.verifySummary.typeCheck' <<< "$VERDICT")
build=$(jq -r '.verifySummary.build' <<< "$VERDICT")
ext=$(jq -r '.verifySummary."ext:contract-check"' <<< "$VERDICT")   # EP-2: extra lane, namespaced
if [[ "$VRC" == "0" && "$lane" == "SUITE" && "$tsc" == "clean" && "$build" == "clean" \
      && "$ext" == "clean" \
      && -f "$MARKERS/ran-workspaces" && -f "$MARKERS/ran-type-check" \
      && -f "$MARKERS/ran-lint" && -f "$MARKERS/ran-test" ]]; then
  pass "(v2) SUITE lane clean run — packages build + lint/type-check/test + ext:contract-check ran, verdict pass"
else
  fail "(v2) SUITE clean — rc=$VRC lane=$lane tsc=$tsc build=$build ext=$ext"
fi

# (v3) type-check failure → TYPE_ERROR classified, exit 1, sidecar fail
reset_all
touch "$MARKERS/FAIL_TYPE_CHECK"
vrun
class=$(jq -r '.failures[0].class' <<< "$VERDICT")
sc=$(jq -r '.status + ":" + (.failedClasses | join(","))' "$SIDECAR")
if [[ "$VRC" == "1" && "$class" == "TYPE_ERROR" && "$sc" == "fail:TYPE_ERROR" ]]; then
  pass "(v3) type-check failure → TYPE_ERROR, exit 1, fail sidecar"
else
  fail "(v3) type-check failure — rc=$VRC class=$class sidecar=$sc"
fi

# (v4) re-run after failure → charges TYPE_ERROR once (fix-attempt detection)
vrun
charged=$(jq -r '.attemptsCharged.TYPE_ERROR // 0' <<< "$VERDICT")
count=$(attempts TYPE_ERROR)
if [[ "$charged" == "1" && "$count" == "1" ]]; then
  pass "(v4) re-run after failure → TYPE_ERROR charged once"
else
  fail "(v4) charge-on-rerun — charged=$charged count=$count"
fi

# (v5) another re-run at the SAME HEAD → no double charge (chargedHead idempotence)
vrun
count=$(attempts TYPE_ERROR)
if [[ "$count" == "1" ]]; then
  pass "(v5) same-HEAD re-run → no double charge (still 1)"
else
  fail "(v5) same-HEAD idempotence — count=$count"
fi

# (v6) budget exhaustion → exit 4, suite does NOT run, counter stays 2
"$STATECTL" verify-attempts 8888 --incr TYPE_ERROR >/dev/null   # -> 2
git -C "$WORK" commit -qam "fix attempt" --allow-empty          # advance HEAD past chargedHead
rm -f "$MARKERS"/ran-*
vrun
status=$(jq -r '.status' <<< "$VERDICT")
count=$(attempts TYPE_ERROR)
ran=$(find "$MARKERS" -maxdepth 1 -name 'ran-*' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$VRC" == "4" && "$status" == "budget-exhausted" && "$count" == "2" && "$ran" == "0" ]]; then
  pass "(v6) budget exhausted → exit 4, nothing ran, counter stays 2"
else
  fail "(v6) budget refuse — rc=$VRC status=$status count=$count ran=$ran"
fi

# (v7) --no-attempt → runs despite budget, no charge, sidecar untouched
sc_before=$(cat "$SIDECAR")
rm -f "$MARKERS"/ran-* "$MARKERS/FAIL_TYPE_CHECK"
vrun --no-attempt
count=$(attempts TYPE_ERROR)
sc_after=$(cat "$SIDECAR")
noatt=$(jq -r '.noAttempt' <<< "$VERDICT")
if [[ "$VRC" == "0" && "$count" == "2" && "$sc_before" == "$sc_after" && "$noatt" == "true" && -f "$MARKERS/ran-test" ]]; then
  pass "(v7) --no-attempt → full no-op accounting (ran, no charge, sidecar byte-identical)"
else
  fail "(v7) --no-attempt — rc=$VRC count=$count noatt=$noatt sidecar-same=$([[ "$sc_before" == "$sc_after" ]] && echo y || echo n)"
fi

# (v8) runId-mismatch sidecar discarded (no charge from a stale run's failure)
reset_all
echo "export const z = 3" >> "$WORK/src/thing.ts"
git -C "$WORK" commit -qam more
jq -n '{runId: "SOME-OTHER-RUN", headSha: "dead", chargedHead: "", at: "x", failedClasses: ["TEST_FAILURE"], status: "fail"}' > "$SIDECAR"
vrun
count=$(attempts TEST_FAILURE)
sc_run=$(jq -r '.runId' "$SIDECAR")
if [[ "$VRC" == "0" && "$count" == "0" && "$sc_run" == "vrun-$$" ]]; then
  pass "(v8) runId-mismatch sidecar discarded — no stale charge, sidecar re-owned"
else
  fail "(v8) runId discard — rc=$VRC count=$count sidecar-runId=$sc_run"
fi

# (v9) lint autofix flow → LINT_AUTOFIX charged by verifyctl, verdict pass, files reported
reset_all
touch "$MARKERS/FAIL_LINT" "$MARKERS/LINT_FIXABLE"
vrun
lint=$(jq -r '.verifySummary.lint' <<< "$VERDICT")
count=$(attempts LINT_AUTOFIX)
fixed=$(jq -r '.lintAutofixed | length' <<< "$VERDICT")
if [[ "$VRC" == "0" && "$lint" == "autofixed" && "$count" == "1" && "$fixed" -ge 1 ]]; then
  pass "(v9) lint autofix → cleaned, LINT_AUTOFIX charged by verifyctl, files reported"
else
  fail "(v9) lint autofix — rc=$VRC lint=$lint count=$count fixed=$fixed"
fi

# (v10) INFRA (exit 127) → classified INFRA, exit 1; re-run never charges INFRA
reset_all
touch "$MARKERS/INFRA"
vrun
class=$(jq -r '.failures[0].class' <<< "$VERDICT")
vrun   # re-run with prior fail sidecar — INFRA must not be charged
count=$(attempts INFRA)
if [[ "$class" == "INFRA" && "$count" == "0" ]]; then
  pass "(v10) INFRA classified, never charged on re-run"
else
  fail "(v10) INFRA — class=$class count=$count"
fi

# (v11) verdict JSON is well-formed on every path exercised above (final sanity)
reset_all
vrun
if jq -e '.lane and .status and (.failures | type == "array") and (.attempts | type == "object")' <<< "$VERDICT" >/dev/null; then
  pass "(v11) verdict JSON shape — jq -e validates required fields"
else
  fail "(v11) verdict JSON shape — got: $(head -c 200 <<< "$VERDICT")"
fi

# (v12) commands.<host>.format = a command -> FORMAT_MODE=config: verifyctl runs
#       it VERBATIM (not prettier). The yarn shim touches ran-format. (#12)
reset_all
echo "export const z = 3" >> "$WORK/src/thing.ts"
git -C "$WORK" add -A && git -C "$WORK" commit -qm feat-fmt-config
FMT_CFG="$TMPDIR_VT/cfg-format-config.json"
jq '.commands.mono.format = "yarn format"' "$CONFIG_FIXTURE" > "$FMT_CFG"
VERDICT=$(SECOND_SHIFT_CONFIG="$FMT_CFG" "$VERIFYCTL" run 8888 2>/dev/null); VRC=$?
fmt=$(jq -r '.verifySummary.format' <<< "$VERDICT")
if [[ "$VRC" == "0" && -f "$MARKERS/ran-format" && "$fmt" != "skipped" ]]; then
  pass "(v12) config format command runs verbatim (ran-format marker; prettier not forced)"
else
  fail "(v12) config format — rc=$VRC ran-format=$([[ -f "$MARKERS/ran-format" ]] && echo yes || echo no) fmt=$fmt"
fi

# (v13) commands.<host>.format = null -> FORMAT_MODE=skip: NO formatter runs
#       (no ran-format marker, no prettier/npx), verdict format = "skipped". (#12)
reset_all
echo "export const w = 4" >> "$WORK/src/thing.ts"
git -C "$WORK" add -A && git -C "$WORK" commit -qm feat-fmt-null
FMT_NULL="$TMPDIR_VT/cfg-format-null.json"
jq '.commands.mono.format = null' "$CONFIG_FIXTURE" > "$FMT_NULL"
VERDICT=$(SECOND_SHIFT_CONFIG="$FMT_NULL" "$VERIFYCTL" run 8888 2>/dev/null); VRC=$?
fmt=$(jq -r '.verifySummary.format' <<< "$VERDICT")
if [[ "$VRC" == "0" && ! -f "$MARKERS/ran-format" && "$fmt" == "skipped" ]]; then
  pass "(v13) null format -> lane skipped (no formatter run, verdict format=skipped)"
else
  fail "(v13) null format skip — rc=$VRC ran-format=$([[ -f "$MARKERS/ran-format" ]] && echo yes || echo no) fmt=$fmt"
fi

echo
echo "[self-test] summary: $PASS passed, $FAIL failed"
exit "$FAIL"

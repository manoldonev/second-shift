#!/usr/bin/env bash
# Smoke test for the lean audit infrastructure.
# Run on demand to verify the ledger writer + history aggregator work
# end-to-end without waiting for a real session.
#
# Tests:
#   1. PostToolUse → ledger row written
#   2. PostToolUseFailure → outcome=fail captured
#   3. /audit-history reports clean

set -uo pipefail

# The hook and history scripts ship in this plugin — resolve them
# script-relative. The ledger itself stays in the consumer repo: we cd to the
# git toplevel and write the smoke ledgers under its .claude/audit/.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/audit-tool-calls.sh"
HISTORY="$SCRIPT_DIR/audit-history.sh"

cd "$(git rev-parse --show-toplevel)" || { echo "not in a git repo"; exit 1; }

[ -x "$HOOK" ] || { echo "FAIL: $HOOK not executable"; exit 1; }
[ -x "$HISTORY" ] || { echo "FAIL: $HISTORY not executable"; exit 1; }

PASS=0; FAIL=0
SID="audit-smoke-$$"
CSID="audit-smoke-concurrent-$$"
TSID="audit-smoke-target-$$"

cleanup() {
    rm -f ".claude/audit/${SID}.jsonl" ".claude/audit/${CSID}.jsonl" \
          ".claude/audit/${TSID}.jsonl" 2>/dev/null
}
trap cleanup EXIT

ok()   { PASS=$((PASS+1)); echo "  OK $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Test 1
echo "Test 1 — PostToolUse → ledger row"
echo "{\"session_id\":\"$SID\",\"cwd\":\"$PWD\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},\"tool_response\":{}}" | "$HOOK"
if [ -f ".claude/audit/$SID.jsonl" ]; then
    tool=$(jq -r '.tool' ".claude/audit/$SID.jsonl")
    [ "$tool" = "Read" ] && ok "row written, tool=Read" || fail "tool=$tool"
else
    fail "ledger not created"
fi

# Test 2
echo "Test 2 — PostToolUseFailure → outcome=fail"
echo "{\"session_id\":\"$SID\",\"cwd\":\"$PWD\",\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{},\"error\":{}}" | "$HOOK"
out=$(jq -r 'select(.outcome == "fail") | .outcome' ".claude/audit/$SID.jsonl" | head -1)
[ "$out" = "fail" ] && ok "outcome=fail captured" || fail "outcome=$out (expected fail)"

# Test 3
echo "Test 3 — /audit-history runs clean"
"$HISTORY" 30 >/dev/null 2>&1 && ok "audit-history exits 0" || fail "audit-history exits non-zero"

# Test 4 — concurrent invocations on one session_id must not lose or corrupt rows.
# Guards the atomic-append ledger creation against the check-then-create TOCTOU
# (the original `[ ! -e ] && install -m 600 /dev/null` could truncate under a race).
# Honors SKIP_STRESS: the repo's verification lane runs every discovered selftest
# under `env SKIP_STRESS=1`, and this 20-way fan-out is the suite's only stress case.
if [ -n "${SKIP_STRESS:-}" ]; then
    echo "Test 4 — concurrent invocations → SKIPPED (SKIP_STRESS set)"
else
    echo "Test 4 — concurrent invocations → no lost/clobbered rows"
    N=20
    rm -f ".claude/audit/$CSID.jsonl" 2>/dev/null
    for _ in $(seq 1 "$N"); do
        echo "{\"session_id\":\"$CSID\",\"cwd\":\"$PWD\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},\"tool_response\":{}}" | "$HOOK" &
    done
    wait
    if [ -f ".claude/audit/$CSID.jsonl" ]; then
        rows=$(grep -c '' ".claude/audit/$CSID.jsonl")
        invalid=0
        while IFS= read -r line; do
            printf '%s' "$line" | jq empty 2>/dev/null || invalid=$((invalid+1))
        done < ".claude/audit/$CSID.jsonl"
        if [ "$rows" -eq "$N" ] && [ "$invalid" -eq 0 ]; then
            ok "all $N concurrent rows present and valid JSON"
        else
            fail "rows=$rows (expected $N), invalid JSON rows=$invalid"
        fi
    else
        fail "concurrent ledger not created"
    fi
fi

# --- `target` capture (Tests 5-9) ------------------------------------------
#
# Invariant guarded: the ledger records what each call ran ON, per tool class, so a
# pipeline gate can assert "a Read of stages/9-*.md happened inside this stage's
# window" rather than trusting the executor's self-report. A wrong payload key emits
# "" silently, so the field's PRESENCE proves nothing — only its per-class VALUE does.
#
# Why no scenario covers it: scenario-liveness-selftest.sh composes dev-pipeline
# verdict paths through the pipeline state machine. This hook sits on none of them —
# it is driven by the Claude Code harness on PostToolUse, an event no scenario can
# raise, and it writes to .claude/audit/ rather than to pipeline state. There is no
# composed verdict path to extend, so a per-tool fixture is the only reachable tier.
#
# What these cases CANNOT catch: the payloads below are synthesized from the
# documented tool-input schemas, so they do not fail if the harness renames a
# `tool_input` key. The hook's fallback chains are the mitigation, not this suite.
# The honest scope here is "the mapping we implemented behaves as specified", not
# "the mapping still matches the live harness".

feed() { echo "$1" | "$HOOK"; }
last_target() { jq -r --arg t "$1" 'select(.tool == $t) | .target' ".claude/audit/$TSID.jsonl" | tail -1; }

# Test 5 — path-bearing tools carry file_path (AC-1)
echo "Test 5 — Read/Edit/Write → target=file_path"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$PWD\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/repo/stages/9-open-pr.md\"}}"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$PWD\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/repo/docs/plans/acme-244.md\"}}"
t=$(last_target Read)
[ "$t" = "/repo/stages/9-open-pr.md" ] && ok "Read target=$t" || fail "Read target=$t"
t=$(last_target Write)
[ "$t" = "/repo/docs/plans/acme-244.md" ] && ok "Write target=$t" || fail "Write target=$t"

# Test 6 — Skill/Workflow identity, incl. the Workflow name fallback (AC-3)
echo "Test 6 — Skill → skill; Workflow → scriptPath else name"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$PWD\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"review-toolkit:review-lead\"}}"
t=$(last_target Skill)
[ "$t" = "review-toolkit:review-lead" ] && ok "Skill target=$t" || fail "Skill target=$t"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$PWD\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Workflow\",\"tool_input\":{\"scriptPath\":\"workflows/code-review.mjs\"}}"
t=$(last_target Workflow)
[ "$t" = "workflows/code-review.mjs" ] && ok "Workflow target=$t (scriptPath)" || fail "Workflow target=$t"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$PWD\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Workflow\",\"tool_input\":{\"name\":\"find-flaky-tests\"}}"
t=$(last_target Workflow)
[ "$t" = "find-flaky-tests" ] && ok "Workflow target=$t (name fallback)" || fail "Workflow target=$t"

# Test 7 — Bash: first line only, capped at 200 chars (AC-2)
echo "Test 7 — Bash → first line, truncated to 200 chars"
PAD=$(head -c 400 /dev/zero | tr '\0' 'x')
CMD="statectl.sh set-stage 244 9 --status completed $PAD
rm -rf /should/not/appear"
feed "$(jq -nc --arg s "$TSID" --arg c "$PWD" --arg cmd "$CMD" \
    '{session_id:$s, cwd:$c, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:$cmd}}')"
t=$(last_target Bash)
len=${#t}
[ "$len" -eq 200 ] && ok "Bash target truncated to 200 chars" || fail "Bash target length=$len (expected 200)"
case "$t" in
    "statectl.sh set-stage 244 9 --status completed"*) ok "Bash target keeps the identifying prefix" ;;
    *) fail "Bash target lost its prefix: $t" ;;
esac
case "$t" in
    *should/not/appear*) fail "Bash target leaked a line after the first" ;;
    *) ok "Bash target dropped lines after the first" ;;
esac

# Test 8 — unmapped tool: target present, empty (AC-4)
echo "Test 8 — unmapped tool → target present and empty"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$PWD\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":[]}}"
row=$(jq -c 'select(.tool == "TodoWrite")' ".claude/audit/$TSID.jsonl" | tail -1)
if jq -e 'has("target")' <<<"$row" >/dev/null 2>&1; then
    t=$(jq -r '.target' <<<"$row")
    [ -z "$t" ] && ok "unmapped target present and empty" || fail "unmapped target=$t (expected empty)"
else
    fail "target key absent on unmapped tool (it must always be present)"
fi

# Test 9 — the emitted key set is exactly the documented row schema (AC-4).
# This is the mechanical anchor for the HOOK side of the row-schema contract: the two
# doc copies are held to each other by a lockstep row (scripts/lockstep-manifest.tsv,
# pair `audit-row-fields`), and this assertion holds the hook's actual output to the
# same field list. Adding or renaming a field without updating the docs fails here.
echo "Test 9 — emitted key set matches the documented row schema"
keys=$(jq -r 'select(.tool == "TodoWrite") | keys_unsorted | join(",")' ".claude/audit/$TSID.jsonl" | tail -1)
expected="ts,session_id,event,tool,subagent,command_name,target,outcome"
[ "$keys" = "$expected" ] && ok "key set = $expected" || fail "key set = $keys (expected $expected)"

echo
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

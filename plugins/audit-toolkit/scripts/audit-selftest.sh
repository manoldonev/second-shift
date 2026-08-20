#!/usr/bin/env bash
# Smoke test for the lean audit infrastructure.
# Run on demand to verify the ledger writer + history aggregator work
# end-to-end without waiting for a real session.
#
# Tests:
#   1. PostToolUse → ledger row written
#   2. PostToolUseFailure → outcome=fail captured
#   3. /audit-history reports clean
#   4. concurrent invocations lose no rows (stress; SKIP_STRESS honored)
#   5-9. per-tool `target` capture and the emitted row schema
#   10-14. WHERE the ledger lands: the main-checkout anchor and its fallbacks

set -uo pipefail

# The hook and history scripts ship in this plugin — resolve them script-relative.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/audit-tool-calls.sh"
HISTORY="$SCRIPT_DIR/audit-history.sh"

[ -x "$HOOK" ] || { echo "FAIL: $HOOK not executable"; exit 1; }
[ -x "$HISTORY" ] || { echo "FAIL: $HISTORY not executable"; exit 1; }

# THE FIXTURE IS A THROWAWAY REPO, never the real checkout. Two reasons, and the second
# only became true once the writer moved to the main-checkout anchor:
#   - Smoke ledgers used to be written into the operator's own .claude/audit/ and deleted
#     again by a trap. A run interrupted between the two left rows behind in live evidence.
#   - The mutation sweep runs suites from a sandbox WORKTREE. Post-anchor, a hook driven
#     from there resolves to the REAL main checkout, so the suite would write into live
#     evidence and then look for its rows somewhere else — every assertion failing for a
#     reason that has nothing to do with the mutant under test.
#
# `pwd -P` is load-bearing: on macOS `mktemp -d` hands back /var/folders/… while git records
# and prints the physical /private/var/folders/… . Comparing the two would fail on a path
# spelling rather than on behavior.
WORK="$(cd "$(mktemp -d -t audit.XXXXXX)" && pwd -P)"
# shellcheck disable=SC2317,SC2329  # invoked indirectly by the EXIT trap below.
# BOTH codes: shellcheck >=0.10 reports SC2329 on the function, 0.9 (CI) reports SC2317 on
# each command in the body — suppressing only the newer one is clean locally and reds CI.
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT

TREE="$WORK/tree"
mkdir -p "$TREE"
git -C "$TREE" init -q
git -C "$TREE" config user.email t@example.invalid
git -C "$TREE" config user.name t
printf '.claude/\n' > "$TREE/.gitignore"
git -C "$TREE" add .gitignore >/dev/null 2>&1
git -C "$TREE" commit -q -m "fixture" >/dev/null 2>&1
# A LINKED WORKTREE, which is what a lean run works in. It needs a commit to exist, hence
# the fixture commit above.
WT="$WORK/wt"
git -C "$TREE" worktree add -q -b wt-branch "$WT" >/dev/null 2>&1
NOGIT="$WORK/nogit"
mkdir -p "$NOGIT"

LEDGERS="$TREE/.claude/audit"

PASS=0; FAIL=0
SID="audit-smoke-$$"
CSID="audit-smoke-concurrent-$$"
TSID="audit-smoke-target-$$"

ok()   { PASS=$((PASS+1)); echo "  OK $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Every invocation names CLAUDE_PROJECT_DIR explicitly. The ambient one is exported in any
# real Claude Code session and takes precedence over the payload's `cwd`, so a bare call
# here would silently resolve against the operator's project instead of the fixture — the
# same env-leak class that makes an unqualified local sweep no evidence of CI green.
feed() { # feed <payload> [project-dir]
    if [ $# -ge 2 ]; then
        printf '%s' "$1" | CLAUDE_PROJECT_DIR="$2" "$HOOK"
    else
        printf '%s' "$1" | CLAUDE_PROJECT_DIR="$TREE" "$HOOK"
    fi
}

# Test 1
echo "Test 1 — PostToolUse → ledger row"
feed "{\"session_id\":\"$SID\",\"cwd\":\"$TREE\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},\"tool_response\":{}}"
if [ -f "$LEDGERS/$SID.jsonl" ]; then
    tool=$(jq -r '.tool' "$LEDGERS/$SID.jsonl")
    [ "$tool" = "Read" ] && ok "row written, tool=Read" || fail "tool=$tool"
else
    fail "ledger not created"
fi

# Test 2
echo "Test 2 — PostToolUseFailure → outcome=fail"
feed "{\"session_id\":\"$SID\",\"cwd\":\"$TREE\",\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{},\"error\":{}}"
out=$(jq -r 'select(.outcome == "fail") | .outcome' "$LEDGERS/$SID.jsonl" | head -1)
[ "$out" = "fail" ] && ok "outcome=fail captured" || fail "outcome=$out (expected fail)"

# Test 3
echo "Test 3 — /audit-history runs clean"
( cd "$TREE" && "$HISTORY" 30 >/dev/null 2>&1 ) && ok "audit-history exits 0" || fail "audit-history exits non-zero"

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
    rm -f "$LEDGERS/$CSID.jsonl" 2>/dev/null
    for _ in $(seq 1 "$N"); do
        feed "{\"session_id\":\"$CSID\",\"cwd\":\"$TREE\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},\"tool_response\":{}}" &
    done
    wait
    if [ -f "$LEDGERS/$CSID.jsonl" ]; then
        rows=$(grep -c '' "$LEDGERS/$CSID.jsonl")
        invalid=0
        while IFS= read -r line; do
            printf '%s' "$line" | jq empty 2>/dev/null || invalid=$((invalid+1))
        done < "$LEDGERS/$CSID.jsonl"
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

last_target() { jq -r --arg t "$1" 'select(.tool == $t) | .target' "$LEDGERS/$TSID.jsonl" | tail -1; }

# Test 5 — path-bearing tools carry file_path (AC-1)
echo "Test 5 — Read/Edit/Write → target=file_path"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$TREE\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/repo/stages/9-open-pr.md\"}}"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$TREE\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/repo/docs/plans/acme-244.md\"}}"
t=$(last_target Read)
[ "$t" = "/repo/stages/9-open-pr.md" ] && ok "Read target=$t" || fail "Read target=$t"
t=$(last_target Write)
[ "$t" = "/repo/docs/plans/acme-244.md" ] && ok "Write target=$t" || fail "Write target=$t"

# Test 6 — Skill/Workflow identity, incl. the Workflow name fallback (AC-3)
echo "Test 6 — Skill → skill; Workflow → scriptPath else name"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$TREE\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"review-toolkit:review-lead\"}}"
t=$(last_target Skill)
[ "$t" = "review-toolkit:review-lead" ] && ok "Skill target=$t" || fail "Skill target=$t"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$TREE\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Workflow\",\"tool_input\":{\"scriptPath\":\"workflows/code-review.mjs\"}}"
t=$(last_target Workflow)
[ "$t" = "workflows/code-review.mjs" ] && ok "Workflow target=$t (scriptPath)" || fail "Workflow target=$t"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$TREE\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Workflow\",\"tool_input\":{\"name\":\"find-flaky-tests\"}}"
t=$(last_target Workflow)
[ "$t" = "find-flaky-tests" ] && ok "Workflow target=$t (name fallback)" || fail "Workflow target=$t"

# Test 7 — Bash: first line only, capped at 200 chars (AC-2)
echo "Test 7 — Bash → first line, truncated to 200 chars"
PAD=$(head -c 400 /dev/zero | tr '\0' 'x')
CMD="lean-gate.sh mark 244 --status completed $PAD
rm -rf /should/not/appear"
feed "$(jq -nc --arg s "$TSID" --arg c "$TREE" --arg cmd "$CMD" \
    '{session_id:$s, cwd:$c, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:$cmd}}')"
t=$(last_target Bash)
len=${#t}
[ "$len" -eq 200 ] && ok "Bash target truncated to 200 chars" || fail "Bash target length=$len (expected 200)"
case "$t" in
    "lean-gate.sh mark 244 --status completed"*) ok "Bash target keeps the identifying prefix" ;;
    *) fail "Bash target lost its prefix: $t" ;;
esac
case "$t" in
    *should/not/appear*) fail "Bash target leaked a line after the first" ;;
    *) ok "Bash target dropped lines after the first" ;;
esac

# Test 8 — unmapped tool: target present, empty (AC-4)
echo "Test 8 — unmapped tool → target present and empty"
feed "{\"session_id\":\"$TSID\",\"cwd\":\"$TREE\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":[]}}"
row=$(jq -c 'select(.tool == "TodoWrite")' "$LEDGERS/$TSID.jsonl" | tail -1)
if jq -e 'has("target")' <<<"$row" >/dev/null 2>&1; then
    t=$(jq -r '.target' <<<"$row")
    [ -z "$t" ] && ok "unmapped target present and empty" || fail "unmapped target=$t (expected empty)"
else
    fail "target key absent on unmapped tool (it must always be present)"
fi

# Test 9 — the emitted key set is exactly the documented row schema (AC-4).
# This is the mechanical anchor for the HOOK side of the row-schema contract: the two
# doc copies are held to each other by the `audit-row-fields` LOCKSTEP group
# (scripts/check-lockstep-pairs.sh), and this assertion holds the hook's actual output to the
# same field list. Adding or renaming a field without updating the docs fails here.
echo "Test 9 — emitted key set matches the documented row schema"
keys=$(jq -r 'select(.tool == "TodoWrite") | keys_unsorted | join(",")' "$LEDGERS/$TSID.jsonl" | tail -1)
expected="ts,session_id,event,tool,subagent,command_name,target,outcome"
[ "$keys" = "$expected" ] && ok "key set = $expected" || fail "key set = $keys (expected $expected)"

# --- WHERE the ledger lands (Tests 10-14) ----------------------------------
#
# Invariant guarded: the hook resolves the ledger directory as `--git-common-dir/..` of
# ${CLAUDE_PROJECT_DIR:-$CWD} — the MAIN checkout — because every reader does. It used to
# write beside the worktree, so a lean run's ledger landed where lean-gate.sh's `entry`,
# and lean-reconcile.sh do not look: an honest run refused
# at the door, and a verdict record naming a session reconcile could not resolve, which
# reads as forgery.
#
# These are per-tool fixtures because the WRITER is what moved; the two readers are pinned
# from their own side, each driving this same hook from a linked worktree
# (lean-gate-selftest.sh's (d5), lean-reconcile-selftest.sh's (R)). Between them, a
# writer-side regression reds three suites, and a reader-side one reds its own.
#
# Not a scenario: scenario-liveness-selftest.sh composes verdict paths through pipeline
# state, and this hook is driven by a harness event no scenario can raise.

WSID="audit-smoke-worktree-$$"
echo "Test 10 — project dir = linked worktree → ledger lands in the MAIN checkout"
feed "{\"session_id\":\"$WSID\",\"cwd\":\"$WT\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WT/x\"}}" "$WT"
if [ -s "$LEDGERS/$WSID.jsonl" ]; then
    ok "worktree-run session wrote to $LEDGERS"
else
    fail "no ledger at $LEDGERS/$WSID.jsonl"
fi
if [ -e "$WT/.claude/audit/$WSID.jsonl" ]; then
    fail "the ledger was ALSO written beside the worktree — the old path is still live"
else
    ok "nothing written beside the worktree"
fi

# Test 11 — the payload's cwd takes the same resolution when CLAUDE_PROJECT_DIR is absent.
# This is the branch a legacy/manual-mode wiring actually takes, and it is the one an
# ambient CLAUDE_PROJECT_DIR would hide: `env -u` is what makes the case real.
CSID2="audit-smoke-cwdfallback-$$"
echo "Test 11 — no CLAUDE_PROJECT_DIR → payload cwd, same main-checkout anchor"
printf '%s' "{\"session_id\":\"$CSID2\",\"cwd\":\"$WT\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{}}" \
    | env -u CLAUDE_PROJECT_DIR "$HOOK"
if [ -s "$LEDGERS/$CSID2.jsonl" ]; then
    ok "cwd-only resolution reached the main checkout"
else
    fail "no ledger at $LEDGERS/$CSID2.jsonl (cwd fallback did not resolve)"
fi

# Test 12 — a non-git project dir falls back to exactly today's path. The fallback IS the
# status quo, which is what makes the layouts this repo never exercises no worse off than
# before the anchor moved.
NSID="audit-smoke-nongit-$$"
echo "Test 12 — non-git project dir → falls back to <dir>/.claude/audit"
feed "{\"session_id\":\"$NSID\",\"cwd\":\"$NOGIT\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{}}" "$NOGIT"
if [ -s "$NOGIT/.claude/audit/$NSID.jsonl" ]; then
    ok "non-git fallback wrote to $NOGIT/.claude/audit"
else
    fail "no ledger at $NOGIT/.claude/audit/$NSID.jsonl"
fi

# Test 13 — the hook must never block a session, whatever the layout. Exit status is the
# contract the masthead states; without this, a resolution that hard-failed would be caught
# only by the absence of a file, which several other causes also produce.
echo "Test 13 — the hook exits 0 even when nothing can be resolved"
printf '%s' "{\"session_id\":\"audit-smoke-noblock-$$\",\"cwd\":\"$WORK/does-not-exist\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{}}" \
    | env -u CLAUDE_PROJECT_DIR "$HOOK"
rc=$?
[ "$rc" -eq 0 ] && ok "hook exits 0 on an unresolvable project dir" || fail "hook exited $rc"

# Test 14 — the sweeper is anchored on the same directory the writer targets. Run from the
# WORKTREE: pre-anchor this reported nothing at all, because `.claude/audit` relative to a
# linked worktree is empty by construction.
echo "Test 14 — /audit-history from a linked worktree sees the main checkout's ledgers"
hist=$( cd "$WT" && "$HISTORY" 30 2>/dev/null )
if grep -qE 'Total sessions: +[1-9]' <<<"$hist"; then
    ok "audit-history from the worktree reported the repo family's sessions"
else
    fail "audit-history from the worktree reported no sessions: $(printf '%s' "$hist" | tr '\n' ' ' | cut -c1-160)"
fi

echo
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

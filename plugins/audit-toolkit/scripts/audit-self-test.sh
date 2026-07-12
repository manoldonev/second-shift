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

cleanup() { rm -f ".claude/audit/${SID}.jsonl" ".claude/audit/${CSID}.jsonl" 2>/dev/null; }
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

echo
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

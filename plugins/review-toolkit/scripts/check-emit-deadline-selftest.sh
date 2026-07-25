#!/usr/bin/env bash
# check-emit-deadline-selftest.sh — covers the emit-deadline lint (#183).
#
# Two halves, mirroring check-bounded-exploration-selftest.sh:
#   (A) FIXTURES — synthetic agent docs exercising each rule in both directions.
#   (B) REAL TREE — the lint must pass over the live plugins/*/agents dirs, so CI goes red
#       when someone raises a cap without moving the deadline with it.
#
# Case A3 is the one that matters most: it is the #175 regression in miniature — a cap
# raised in frontmatter while the doc keeps citing the old number. That is precisely the
# silent no-op this lint exists to make inexpressible.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/check-emit-deadline.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}
bad() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}

# write_agent <dir> <name> <maxTurns-line> <body>
write_agent() {
  mkdir -p "$1"
  {
    echo "---"
    echo "name: $2"
    echo "model: opus"
    [ -n "$3" ] && echo "$3"
    echo "---"
    echo
    echo "You are a test agent."
    echo
    printf '%s\n' "$4"
  } > "$1/$2.md"
}

run_check() {
  bash "$CHECK" "$1" >"$TMP/.out" 2>&1
  echo $?
}

echo "[A] fixture cases"

# A1: above-default cap, no deadline -> reject.
d="$TMP/a1/agents"
write_agent "$d" "exhaustive-reviewer" "maxTurns: 30" "Enumerate everything. Never stop early."
rc=$(run_check "$d")
[ "$rc" -eq 1 ] && ok "A1 above-default cap with no deadline is rejected" \
  || bad "A1 expected rc=1, got $rc"

# A2: above-default cap with a well-formed deadline -> accept.
d="$TMP/a2/agents"
write_agent "$d" "exhaustive-reviewer" "maxTurns: 30" \
  "By **turn 20** (of your 30 maximum) you MUST be writing the final result."
rc=$(run_check "$d")
[ "$rc" -eq 0 ] && ok "A2 above-default cap with a matching deadline is accepted" \
  || bad "A2 expected rc=0, got $rc ($(cat "$TMP/.out"))"

# A3: THE #175 REGRESSION — cap bumped in frontmatter, doc still cites the old cap.
d="$TMP/a3/agents"
write_agent "$d" "exhaustive-reviewer" "maxTurns: 45" \
  "By **turn 20** (of your 30 maximum) you MUST be writing the final result."
rc=$(run_check "$d")
if [ "$rc" -eq 1 ] && grep -q "cap moved and the deadline did not" "$TMP/.out"; then
  ok "A3 silent cap bump (frontmatter 45, doc cites 30) is rejected"
else
  bad "A3 expected rc=1 with the cap-moved message, got $rc ($(cat "$TMP/.out"))"
fi

# A4: deadline at the cap is not a deadline.
d="$TMP/a4/agents"
write_agent "$d" "exhaustive-reviewer" "maxTurns: 30" \
  "By **turn 30** (of your 30 maximum) you MUST be writing the final result."
rc=$(run_check "$d")
[ "$rc" -eq 1 ] && ok "A4 deadline equal to the cap is rejected" \
  || bad "A4 expected rc=1, got $rc"

# A5: deadline past the 2/3 ratio leaves too little room to write.
d="$TMP/a5/agents"
write_agent "$d" "exhaustive-reviewer" "maxTurns: 30" \
  "By **turn 27** (of your 30 maximum) you MUST be writing the final result."
rc=$(run_check "$d")
[ "$rc" -eq 1 ] && ok "A5 deadline beyond ceil(2N/3) is rejected" \
  || bad "A5 expected rc=1, got $rc"

# A6: at/below the default cap -> not this lint's jurisdiction (dispatch-time bounding is).
d="$TMP/a6/agents"
write_agent "$d" "ordinary-reviewer" "maxTurns: 15" "No deadline here; bounded at dispatch."
rc=$(run_check "$d")
[ "$rc" -eq 0 ] && ok "A6 default-cap agent without a deadline is accepted" \
  || bad "A6 expected rc=0, got $rc ($(cat "$TMP/.out"))"

# A7: no maxTurns at all -> ignored.
d="$TMP/a7/agents"
write_agent "$d" "uncapped-agent" "" "No cap declared."
rc=$(run_check "$d")
[ "$rc" -eq 0 ] && ok "A7 agent with no maxTurns is ignored" \
  || bad "A7 expected rc=0, got $rc ($(cat "$TMP/.out"))"

# A8: declared exemption with a reason -> accepted.
d="$TMP/a8/agents"
write_agent "$d" "sink-agent" "maxTurns: 30" \
  "<!-- emit-deadline-exempt: transcription sink, tools:[] so it cannot explore -->"
rc=$(run_check "$d")
[ "$rc" -eq 0 ] && ok "A8 declared exemption with a reason is accepted" \
  || bad "A8 expected rc=0, got $rc ($(cat "$TMP/.out"))"

# A9: exemption with an EMPTY reason -> still rejected (the point is the reason is stated).
d="$TMP/a9/agents"
write_agent "$d" "sink-agent" "maxTurns: 30" "<!-- emit-deadline-exempt: -->"
rc=$(run_check "$d")
[ "$rc" -eq 1 ] && ok "A9 exemption with an empty reason is rejected" \
  || bad "A9 expected rc=1, got $rc"

echo
echo "[B] real tree"

# B1: the live agent tree must pass. This is the CI-enforcing case — a future cap raise
# that forgets its deadline fails here, in the sweep, not in a review comment. No arg: the
# check resolves the repo's plugins/*/agents dirs itself from its own path.
if bash "$CHECK" >"$TMP/.live" 2>&1; then
  ok "B1 live plugins/*/agents pass the emit-deadline lint"
else
  bad "B1 live tree fails the lint: $(cat "$TMP/.live")"
fi

# B2: the two agents #175 raised to 30 must each be covered (not silently skipped, which
# is how a lint rots into a no-op).
covered=0
for a in scope-completeness-reviewer unit-test-mutation-reviewer; do
  grep -q "$a" "$TMP/.live" && covered=$((covered + 1))
done
[ "$covered" -eq 2 ] && ok "B2 both above-default exhaustive agents are covered by the lint" \
  || bad "B2 expected both exhaustive agents in the lint output, saw $covered"

echo
echo "[check-emit-deadline-selftest] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

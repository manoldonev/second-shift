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

# run_check_env <enrollment-list> <dir> <outfile>
# Same as run_check but sets the DEADLINE_AT_DEFAULT enrollment seam and captures to a
# caller-named file, so a case asserting on the message text cannot read another case's
# output.
run_check_env() {
  DEADLINE_AT_DEFAULT="$1" bash "$CHECK" "$2" >"$3" 2>&1
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

# --- default-cap enrollment (#232) ---------------------------------------------------
# A6 above proves an unenrolled default-cap agent is still out of jurisdiction. A10-A14
# cover the opt-in that brings ONE named default-cap agent in, without widening the rule
# to the whole panel.

# A10: enrolled, at the default cap, no deadline -> reject, and say WHY it is in scope.
# The message matters: the pre-#232 wording ("is above the default 15") is self-
# contradictory for a cap-15 agent, so an operator could not act on it.
d="$TMP/a10/agents"
write_agent "$d" "enrolled-reviewer" "maxTurns: 15" "No deadline, but enrolled."
rc=$(run_check_env "enrolled-reviewer" "$d" "$TMP/.a10")
if [ "$rc" -eq 1 ] && grep -q "enrolled" "$TMP/.a10"; then
  ok "A10 enrolled default-cap agent with no deadline is rejected, naming the enrollment"
else
  bad "A10 expected rc=1 naming the enrollment, got $rc ($(cat "$TMP/.a10"))"
fi

# A11: enrolled, at the default cap, deadline at the ratio bound -> accept.
# turn 10 is ceil(2*15/3) — the value plan-reviewer.md itself must use.
d="$TMP/a11/agents"
write_agent "$d" "enrolled-reviewer" "maxTurns: 15" \
  "By **turn 10** (of your 15 maximum) you MUST be writing the verdict."
rc=$(run_check_env "enrolled-reviewer" "$d" "$TMP/.a11")
[ "$rc" -eq 0 ] && ok "A11 enrolled default-cap agent with a turn-10 deadline is accepted" \
  || bad "A11 expected rc=0, got $rc ($(cat "$TMP/.a11"))"

# A12: enrolled, at the default cap, deadline one past the ratio bound -> reject.
# Proves the ratio rule applies at the default cap too, rather than the enrollment
# merely requiring SOME deadline.
d="$TMP/a12/agents"
write_agent "$d" "enrolled-reviewer" "maxTurns: 15" \
  "By **turn 11** (of your 15 maximum) you MUST be writing the verdict."
rc=$(run_check_env "enrolled-reviewer" "$d" "$TMP/.a12")
[ "$rc" -eq 1 ] && ok "A12 enrolled default-cap deadline past ceil(2N/3) is rejected" \
  || bad "A12 expected rc=1, got $rc ($(cat "$TMP/.a12"))"

# A13: NOT enrolled, at the default cap, no deadline, while a different name IS enrolled
# -> accept. With A6 this is the pair that keeps the deferred scope (deadlines for every
# default-cap agent) mechanically deferred: enrollment is per-agent, not a cap-15 rule.
d="$TMP/a13/agents"
write_agent "$d" "ordinary-reviewer" "maxTurns: 15" "No deadline; not enrolled."
rc=$(run_check_env "some-other-agent" "$d" "$TMP/.a13")
[ "$rc" -eq 0 ] && ok "A13 unenrolled default-cap agent is untouched while another is enrolled" \
  || bad "A13 expected rc=0, got $rc ($(cat "$TMP/.a13"))"

# A14: enrollment matches the agent name EXACTLY, never as a substring. `plan-reviewer`
# is a substring of both `unit-test-plan-reviewer` (cap 15, no deadline) and
# `figma-faithful-plan-reviewer`, so a substring implementation would sweep in agents
# nobody enrolled and turn the live tree (B1) red.
d="$TMP/a14/agents"
write_agent "$d" "unit-test-plan-reviewer" "maxTurns: 15" "No deadline; not enrolled."
rc=$(run_check_env "plan-reviewer" "$d" "$TMP/.a14")
[ "$rc" -eq 0 ] && ok "A14 enrollment matches whole agent names, not substrings" \
  || bad "A14 expected rc=0 (substring sweep), got $rc ($(cat "$TMP/.a14"))"

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

# B3: an enrolled name that matches no agent file must be LOUD. A typo'd or renamed
# enrollment would otherwise be a silent no-op — the lint would report clean while the
# agent it was meant to cover went unchecked, which is the #232 failure wearing a
# different hat.
if DEADLINE_AT_DEFAULT="no-such-agent" bash "$CHECK" >"$TMP/.b3" 2>&1; then
  bad "B3 expected rc=1 for an unresolvable enrollment, got rc=0 ($(cat "$TMP/.b3"))"
else
  grep -q "no-such-agent" "$TMP/.b3" \
    && ok "B3 an enrolled name matching no agent file fails, naming it" \
    || bad "B3 failed but did not name the unresolved enrollment ($(cat "$TMP/.b3"))"
fi

# B4: plan-reviewer must actually appear in the live lint output under the shipped
# default enrollment. B1 only proves the tree passes — it would keep passing if
# plan-reviewer were quietly dropped from the enrollment list, which is exactly the
# regression this issue closes. Mirrors B2's coverage shape.
grep -q "plan-reviewer" "$TMP/.live" \
  && ok "B4 plan-reviewer is covered by the lint under the shipped enrollment" \
  || bad "B4 expected plan-reviewer in the live lint output ($(cat "$TMP/.live"))"

# B5: spec-reviewer (#283's demonstrated death, run #273) must likewise stay covered
# under the shipped enrollment — same regression shape as B4, second name.
grep -q "spec-reviewer" "$TMP/.live" \
  && ok "B5 spec-reviewer is covered by the lint under the shipped enrollment" \
  || bad "B5 expected spec-reviewer in the live lint output ($(cat "$TMP/.live"))"

# B6/B7: the live scan's two REFUSALS. Both are one contract from opposite sides — a lint that
# cannot see the tree it lints must say so, not report clean. That is what the fixed hop count
# did from an install for a release: `$HERE/../../..` landed on the cache root, the glob matched
# nothing, and the lint printed "clean — 0 linted agent(s)" with rc=0.
#
# Both stage a real directory shape and run the REAL script from inside it, so they exercise
# production resolution rather than a model of it. `.claude-plugin/plugin.json` is what makes a
# candidate a plugin here — the same marker install-topology-selftest.sh stages from — and is
# why the unbounded cache-rung walk cannot wander into whatever else shares a parent.

# B6: no plugin sibling in either topology => rc=1, naming the anchors it tried.
b6="$TMP/b6/lonely/scripts"; mkdir -p "$b6"
cp "$CHECK" "$b6/check-emit-deadline.sh"
if (cd "$TMP" && bash "$b6/check-emit-deadline.sh") >"$TMP/.b6" 2>&1; then
  bad "B6 expected rc=1 when no plugin sibling resolves, got rc=0 ($(cat "$TMP/.b6"))"
else
  grep -q "no sibling plugin agents dir found" "$TMP/.b6" \
    && ok "B6 an unresolvable live scan fails loudly instead of reporting clean" \
    || bad "B6 failed but did not name the resolution miss ($(cat "$TMP/.b6"))"
fi

# B7: roots resolve, but no agent file is read out of them => still rc=1. Resolving a root is
# not the same as linting something, and "clean over zero agents" is the same vacuous green
# wearing the other hat.
b7="$TMP/b7/marketplace/toolkit/1.0.0"
mkdir -p "$b7/scripts" "$b7/agents" "$b7/.claude-plugin"
echo '{"name":"toolkit","version":"1.0.0"}' > "$b7/.claude-plugin/plugin.json"
cp "$CHECK" "$b7/scripts/check-emit-deadline.sh"
if (cd "$TMP" && bash "$b7/scripts/check-emit-deadline.sh") >"$TMP/.b7" 2>&1; then
  bad "B7 expected rc=1 for a resolved-but-empty scan, got rc=0 ($(cat "$TMP/.b7"))"
else
  grep -q "read no agent file" "$TMP/.b7" \
    && ok "B7 a live scan that reads no agent file fails instead of reporting clean" \
    || bad "B7 failed for the wrong reason ($(cat "$TMP/.b7"))"
fi

# B8: the resolved roots ARE reported, and on STDERR. Resolution is the part that went wrong
# silently, so it has to be visible; stdout has to stay byte-identical to the pre-fix run so
# anything reading the verdict lines is unaffected by the diagnostic.
bash "$CHECK" >"$TMP/.b8.out" 2>"$TMP/.b8.err"
if grep -q "scanning roots:" "$TMP/.b8.err" && ! grep -q "scanning roots:" "$TMP/.b8.out"; then
  ok "B8 resolved roots are reported on stderr, leaving stdout unchanged"
else
  bad "B8 expected the roots line on stderr only (out: $(head -1 "$TMP/.b8.out"); err: $(head -1 "$TMP/.b8.err"))"
fi

# B9: from a version-keyed cache shape, the scan must reach SIBLING plugins, not just the one
# it ships in. This is the narrowing a first-hit ladder produces and nothing else here would
# catch: B1-B5 all name agents that live in review-toolkit, so they pass identically whether
# the scan covered every plugin or only its own. Measured on an earlier draft — from an
# install it scanned review-toolkit alone, because one level up a cache's `<plugin>/<version>/`
# dirs are shape-indistinguishable from the monorepo's `plugins/<plugin>/` dirs.
b9="$TMP/b9/marketplace"
for plug in mine other; do
  mkdir -p "$b9/$plug/1.0.0/.claude-plugin" "$b9/$plug/1.0.0/agents"
  echo "{\"name\":\"$plug\",\"version\":\"1.0.0\"}" > "$b9/$plug/1.0.0/.claude-plugin/plugin.json"
  write_agent "$b9/$plug/1.0.0/agents" "$plug-reviewer" "maxTurns: 30" \
    "By **turn 20** (of your 30 maximum) you MUST be writing the final result."
done
mkdir -p "$b9/mine/1.0.0/scripts"
cp "$CHECK" "$b9/mine/1.0.0/scripts/check-emit-deadline.sh"
(cd "$TMP" && bash "$b9/mine/1.0.0/scripts/check-emit-deadline.sh") >"$TMP/.b9" 2>&1
if grep -q "other-reviewer" "$TMP/.b9" && grep -q "mine-reviewer" "$TMP/.b9"; then
  ok "B9 a cache-shaped scan reaches sibling plugins, not only the one it ships in"
else
  bad "B9 expected both plugins' agents in a cache-shaped scan ($(cat "$TMP/.b9"))"
fi

echo
echo "[check-emit-deadline-selftest] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

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
# Staged under its OWN mktemp root rather than under $TMP: shape 2 globs two levels up, so a
# sibling case that happens to stage `<x>/<y>/.claude-plugin` would resolve for this one and
# quietly turn "nothing resolves" into "something did" — an order dependence on where the other
# cases sit in this file.
#
# That root is nested one level BELOW the mktemp dir, which is what makes the isolation hold
# against any OTHER suite running at the same time. `mktemp -d` returns a direct child of
# $TMPDIR, so staging the scripts dir at `<mktemp>/lonely/scripts` leaves shape 2 —
# `$HERE/../../../*/*/agents` — globbing `$TMPDIR/*/*/agents`: every fixture any concurrent
# suite has staged one level below ITS OWN mktemp root. That is an ordinary shape, not an
# exotic one. check-reviewer-references-selftest.sh does `TMP=$(mktemp -d)` and copies a
# plugin fixture to `$TMP/plugin-wrong-prefix`, carrying both `.claude-plugin/plugin.json`
# and `agents/` — a valid shape-2 candidate sitting exactly there. Its fixture then resolves
# for THIS case and the premise "nothing resolves" goes false through no fault of the tool.
# The exposure is therefore a plain `SELFTEST_JOBS=4` sweep, not only install-topology's
# re-run of every shipped suite. Interposing $B6PARENT means shape 2 globs only that private
# dir, whose sole child is the staged root — asserted by B6c below, not assumed.
B6PARENT="$(mktemp -d)"; B6ROOT="$B6PARENT/iso"; mkdir -p "$B6ROOT"
B6DECOYP="$(mktemp -d)"; B6DECOY="$B6DECOYP/plugin-decoy"
trap 'rm -rf "$TMP" "$B6PARENT" "$B6DECOYP"' EXIT
b6="$B6ROOT/lonely/scripts"; mkdir -p "$b6"
cp "$CHECK" "$b6/check-emit-deadline.sh"
if (cd "$B6ROOT" && bash "$b6/check-emit-deadline.sh") >"$TMP/.b6" 2>&1; then
  bad "B6 expected rc=1 when no plugin sibling resolves, got rc=0 ($(cat "$TMP/.b6"))"
else
  grep -q "no sibling plugin agents dir found" "$TMP/.b6" \
    && ok "B6 an unresolvable live scan fails loudly instead of reporting clean" \
    || bad "B6 failed but did not name the resolution miss ($(cat "$TMP/.b6"))"
fi

# B6c: B6's isolation ASSERTED, not rehearsed. The comment above claims $B6PARENT is what keeps
# a concurrent suite's fixture out of shape 2's glob — this stages exactly such a fixture and
# re-runs B6's own command against B6's own root, so dropping the nesting fails HERE, in one
# deterministic process, instead of intermittently in whoever's sweep happens to interleave.
# The decoy sits at `<its own mktemp>/plugin-decoy`: the same depth
# check-reviewer-references-selftest.sh's `$TMP/plugin-wrong-prefix` occupies, which shape 2
# reaches from a root staged directly at `<mktemp>` and cannot reach from `<mktemp>/iso`.
mkdir -p "$B6DECOY/.claude-plugin" "$B6DECOY/agents"
echo '{"name":"decoy","version":"1.0.0"}' > "$B6DECOY/.claude-plugin/plugin.json"
printf -- '---\nname: decoy-reviewer\nmaxTurns: 5\n---\n' > "$B6DECOY/agents/decoy-reviewer.md"
if (cd "$B6ROOT" && bash "$b6/check-emit-deadline.sh") >"$TMP/.b6c" 2>&1; then
  bad "B6c expected rc=1 with a decoy plugin staged at the collide depth, got rc=0 ($(cat "$TMP/.b6c"))"
else
  grep -q "no sibling plugin agents dir found" "$TMP/.b6c" \
    && ok "B6c a concurrent suite's plugin-shaped fixture stays outside B6's resolution glob" \
    || bad "B6c the decoy resolved into B6's scan — the mktemp nesting no longer isolates it ($(cat "$TMP/.b6c"))"
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

# B10: a real cache holds MORE THAN ONE version of the scanning plugin, and one level up those
# version dirs are shape-1 candidates. Without newest-per-name selection every superseded copy
# is linted as if current, so agents nobody ships any more red the lint on a correct install —
# measured at 16 violations across 38 agents against a 12-version cache. B9 cannot see it: it
# stages one version per plugin, as does install-topology-selftest.sh's staged cache.
#
# THE VERSIONS ARE 9.0.0 AND 10.0.0 ON PURPOSE, so this case pins NUMERIC ordering rather than
# merely "some selection happens". Glob order is lexical and sorts 10.0.0 BEFORE 9.0.0, so a
# last-wins selection lands on 9.0.0 — the superseded copy — and `stale-reviewer` reaches the
# scan. A 1.0.0/2.0.0 pair agrees under both orderings and cannot tell them apart.
b10="$TMP/b10/marketplace"
for v in 9.0.0 10.0.0; do
  mkdir -p "$b10/mine/$v/.claude-plugin" "$b10/mine/$v/agents"
  echo "{\"name\":\"mine\",\"version\":\"$v\"}" > "$b10/mine/$v/.claude-plugin/plugin.json"
done
# The superseded version carries a VIOLATION — linting it at all is both visible and fatal.
write_agent "$b10/mine/9.0.0/agents" "stale-reviewer" "maxTurns: 30" "No deadline in this body."
write_agent "$b10/mine/10.0.0/agents" "current-reviewer" "maxTurns: 30" \
  "By **turn 20** (of your 30 maximum) you MUST be writing the final result."
mkdir -p "$b10/mine/10.0.0/scripts"
cp "$CHECK" "$b10/mine/10.0.0/scripts/check-emit-deadline.sh"
# The shipped enrollment names agents this fixture does not have, and an unresolvable
# enrollment is its own (B3) failure — point it at the newest version's agent instead, which
# also asserts that agent is the one the scan reached.
if (cd "$TMP" && DEADLINE_AT_DEFAULT=current-reviewer \
      bash "$b10/mine/10.0.0/scripts/check-emit-deadline.sh") >"$TMP/.b10" 2>&1; then
  grep -q "stale-reviewer" "$TMP/.b10" \
    && bad "B10 clean, but a superseded version's agents were still scanned ($(cat "$TMP/.b10"))" \
    || ok "B10 a multi-version cache lints only the newest version of the scanning plugin"
else
  bad "B10 expected rc=0 from a two-version cache, got rc=1 ($(cat "$TMP/.b10"))"
fi

# B11: B10 again, with jq forced unresolvable. The name lookup has two implementations and the
# jq one wins on every machine that has jq — which is every machine this suite has ever run on,
# so without this the sed fallback is dead code, green by never executing. Manifests are written
# the way real ones are (pretty-printed, two-space indent) because that is what the fallback's
# line anchor keys on.
b11="$TMP/b11/marketplace"
for v in 9.0.0 10.0.0; do
  mkdir -p "$b11/mine/$v/.claude-plugin" "$b11/mine/$v/agents"
  printf '{\n  "name": "mine",\n  "version": "%s",\n  "author": {\n    "name": "not-the-plugin"\n  }\n}\n' \
    "$v" > "$b11/mine/$v/.claude-plugin/plugin.json"
done
write_agent "$b11/mine/9.0.0/agents" "stale-reviewer" "maxTurns: 30" "No deadline in this body."
write_agent "$b11/mine/10.0.0/agents" "current-reviewer" "maxTurns: 30" \
  "By **turn 20** (of your 30 maximum) you MUST be writing the final result."
mkdir -p "$b11/mine/10.0.0/scripts"
cp "$CHECK" "$b11/mine/10.0.0/scripts/check-emit-deadline.sh"
if (cd "$TMP" && DEADLINE_AT_DEFAULT=current-reviewer EMIT_DEADLINE_JQ=jq-does-not-resolve \
      bash "$b11/mine/10.0.0/scripts/check-emit-deadline.sh") >"$TMP/.b11" 2>&1; then
  grep -q "stale-reviewer" "$TMP/.b11" \
    && bad "B11 clean, but the jq-less name lookup did not select the newest version ($(cat "$TMP/.b11"))" \
    || ok "B11 the jq-less name lookup selects the newest version, and ignores a nested author.name"
else
  bad "B11 expected rc=0 with jq forced unresolvable, got rc=1 ($(cat "$TMP/.b11"))"
fi

# B12: the fallback must read the RIGHT name, not merely some name. B10 and B11 assert an
# ABSENCE — `stale-reviewer` must not appear — and an absence cannot separate "read the declared
# name" from "returned a constant": a constant is a perfectly good dedup key, so newest-per-name
# still collapses the two version dirs and the absence holds either way. Measured: swapping the
# whole lookup for `head -1 "$j"` (which returns `{` for every candidate) left B10 and B11 green.
#
# That is also the axis the `cmp-z` mutant moves along, which is why an absence-only case does
# not kill it on the platform CI runs. BSD sed rejects `-z` outright, so the name comes back
# empty, every candidate keys on its own path, nothing is selected, and B11 fails. GNU sed
# accepts it — and `-z` is not `-n`, so quiet mode silently goes away: sed auto-prints, the whole
# manifest is one NUL-record whose `^` sits on `{`, the substitution never fires, and `head -1`
# yields that same `{`. A constant. B11 passes there.
#
# So this fixture discriminates on the VALUE. The two version dirs declare DIFFERENT top-level
# names, so a lookup that reads them keys them apart and keeps BOTH roots — the superseded
# agent IS scanned and its violation reds the lint — while a constant-returning lookup collapses
# them and the run comes back clean. The assertion inverts with B10/B11: here a clean run is the
# failure, which is what makes a broken fallback detectable rather than invisible.
#
# `author` is written BEFORE the top-level `name` so the anchor's WIDENING direction is caught
# too. `sed -n '…p' | head -1` takes the first matching line, so relaxing the bound
# (`\{0,2\}` -> `\{0,\}`, or dropping the anchor) reads the nested author name — which is shared
# across both manifests, and therefore collapses them exactly as a constant does. B11 catches the
# narrowing direction; between them both directions are pinned.
b12="$TMP/b12/marketplace"
for v in 1.0.0 2.0.0; do
  mkdir -p "$b12/mine/$v/.claude-plugin" "$b12/mine/$v/agents"
done
printf '{\n  "author": {\n    "name": "shared-author"\n  },\n  "name": "%s",\n  "version": "1.0.0"\n}\n' \
  "mine-superseded" > "$b12/mine/1.0.0/.claude-plugin/plugin.json"
printf '{\n  "author": {\n    "name": "shared-author"\n  },\n  "name": "%s",\n  "version": "2.0.0"\n}\n' \
  "mine-current" > "$b12/mine/2.0.0/.claude-plugin/plugin.json"
write_agent "$b12/mine/1.0.0/agents" "stale-reviewer" "maxTurns: 30" "No deadline in this body."
write_agent "$b12/mine/2.0.0/agents" "current-reviewer" "maxTurns: 30" \
  "By **turn 20** (of your 30 maximum) you MUST be writing the final result."
mkdir -p "$b12/mine/2.0.0/scripts"
cp "$CHECK" "$b12/mine/2.0.0/scripts/check-emit-deadline.sh"
if (cd "$TMP" && DEADLINE_AT_DEFAULT=current-reviewer EMIT_DEADLINE_JQ=jq-does-not-resolve \
      bash "$b12/mine/2.0.0/scripts/check-emit-deadline.sh") >"$TMP/.b12" 2>&1; then
  bad "B12 two differently-named candidates came back clean — the jq-less lookup collapsed them, so it is not reading the declared name ($(cat "$TMP/.b12"))"
else
  grep -q "stale-reviewer" "$TMP/.b12" \
    && ok "B12 the jq-less lookup reads the declared name — differently-named candidates are both kept" \
    || bad "B12 failed, but not because the second candidate was scanned ($(cat "$TMP/.b12"))"
fi

echo
echo "[check-emit-deadline-selftest] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

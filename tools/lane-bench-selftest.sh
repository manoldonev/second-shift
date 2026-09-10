#!/usr/bin/env bash
# lane-bench-selftest.sh — behavioral cover for tools/lane-bench.sh, and the completeness guard
# for tools/lane-bench-classes.tsv.
#
# Zero network, zero model calls. Every case builds a real git substrate, a real lane branch with
# real committed verdict records, and hands them to the real tool through a `gh` fake; nothing
# here re-implements the tool's counting, which is the point — a hand-maintained copy of the
# detector arithmetic would converge on green while production drifted (docs/testing.md, the
# no-mirror-harnesses rule).
#
# THE SCENARIO EACH CASE GUARDS is stated on the case, and none of them is covered by
# plugins/dev-pipeline/skills/build/scenario-liveness-selftest.sh: that suite composes the
# milestone gate's own verdict paths, and this tool is not on one. It reads a lane's leavings from
# outside, after the lane is over, in a repo the gate never touches.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/lane-bench.sh"
CLASSES="$HERE/lane-bench-classes.tsv"
ORCH="$(cd "$HERE/.." && pwd)/plugins/dev-pipeline/skills/run/orchestrate.sh"
# The explicit-template form, which IS honored by a private TMPDIR (docs/testing.md), unlike the
# `-t` form the two big stamped fixture families use.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lane-bench-selftest.XXXXXX")"
# NORMALIZED. A TMPDIR ending in `/` (the macOS default) yields a `//` in this path, and the tool
# under test resolves every path it reports through `cd`+`pwd`, which collapses it — so a case
# comparing its output against this variable would fail on the separator alone.
WORK="$(cd "$WORK" && pwd)"
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

TAB=$'\t'
PASSES=0; FAILS=0
pass() { PASSES=$((PASSES + 1)); echo "  PASS: $*"; }
fail() { FAILS=$((FAILS + 1));  echo "  FAIL: $*"; }

PREFIX="bench/sub-"
ISSUE=42
SLUG="substrate"
BRANCH="${PREFIX}${ISSUE}"
VERDICT_REL="docs/plans/${SLUG}-${ISSUE}-lean-verdict.md"
HEADER="cell_id${TAB}ticket_role${TAB}arm${TAB}repeat${TAB}harness_sha${TAB}cli_version${TAB}build_model${TAB}review_model${TAB}terminal_slug${TAB}terminal_class${TAB}rounds${TAB}wall_min${TAB}pr_head_sha${TAB}tests_passed${TAB}tests_total${TAB}defects_at_head${TAB}defects_named${TAB}review_catch${TAB}scored_at"

# ---- the substrate ------------------------------------------------------------------------------
# A lane branch carrying TWO committed verdict-record versions, because D-2's claim is that a
# defect named in ANY version counts — a scorer reading only the head version would pass every
# case that put both names in the last one.
SUB="$WORK/substrate"
mkdir -p "$SUB/.claude" "$SUB/docs/plans" "$SUB/pkg"
git -C "$SUB" init -q
git -C "$SUB" config user.email bench@example.invalid
git -C "$SUB" config user.name  "Bench Fixture"
echo "seed" > "$SUB/pkg/mod.txt"
git -C "$SUB" add -A && git -C "$SUB" commit -qm "seed"
git -C "$SUB" checkout -qb "$BRANCH"

cat > "$SUB/.claude/eval.json" <<JSON
{ "configVersion": 2,
  "tracker": { "type": "github", "branchPrefix": "$PREFIX" },
  "topology": { "type": "standalone", "repos": { "$SLUG": { "path": ".", "baseBranch": "main" } } } }
JSON
CONFIG="$SUB/.claude/eval.json"

# Round 1's record names D-a only. Round 2's names D-b only. Neither names D-c.
cat > "$SUB/$VERDICT_REL" <<'MD'
verdict=needs-work
rounds: 1
The overlay's fixture module drops the trailing separator on an empty list.
MD
git -C "$SUB" add -A && git -C "$SUB" commit -qm "review r1"
cat > "$SUB/$VERDICT_REL" <<'MD'
verdict=approve
rounds: 2
The retry path swallows the upstream error code.
MD
git -C "$SUB" add -A && git -C "$SUB" commit -qm "review r2"
HEAD_SHA="$(git -C "$SUB" rev-parse HEAD)"

# A branch with a PR but no verdict record at all — the shape every cell of an arm without
# review-toolkit produces.
BRANCH_NR="${PREFIX}77"
git -C "$SUB" checkout -q -b "$BRANCH_NR" main 2>/dev/null || git -C "$SUB" checkout -q -b "$BRANCH_NR" master
echo "work" > "$SUB/pkg/mod.txt"
git -C "$SUB" add -A && git -C "$SUB" commit -qm "build, never reviewed"
HEAD_NR="$(git -C "$SUB" rev-parse HEAD)"
git -C "$SUB" checkout -q "$BRANCH"

# ---- the overlay ---------------------------------------------------------------------------------
# run.sh reads a case-written outcome file rather than deciding anything, so a case scripts the
# hidden tests' verdicts as data and the tool's counting is what is under test.
OVERLAY="$WORK/overlay"
mkdir -p "$OVERLAY"
cat > "$OVERLAY/run.sh" <<'SH'
#!/usr/bin/env bash
cat "$OUTCOMES"
grep -q ' FAIL$' "$OUTCOMES" && exit 1
exit 0
SH
chmod +x "$OVERLAY/run.sh"

OUTCOMES="$WORK/outcomes"
export OUTCOMES
cat > "$OUTCOMES" <<'TXT'
TEST t-happy PASS
TEST t-sep FAIL
TEST t-retry PASS
TEST t-extra PASS
TXT

DEFECTS="$WORK/defects.tsv"
{
  printf 'id\tfile\tdescription\ttest_id\tverdict_regex\n'
  printf 'D-a\tpkg/mod.txt\tdrops the trailing separator\tt-sep\ttrailing separator\n'
  printf 'D-b\tpkg/mod.txt\tswallows the error code\tt-retry\tupstream error code\n'
  printf 'D-c\tpkg/mod.txt\tmiscounts the empty case\tt-extra\tmiscounts the empty\n'
} > "$DEFECTS"

# ---- the gh fake -----------------------------------------------------------------------------
# It records ARGV, so a case asserting "the tool asked about branch X" is a measurement rather
# than a claim, and answers from a case-written file.
BIN="$WORK/bin"; mkdir -p "$BIN"
# Argv-discriminated since #813: `run` asks it four different questions and one canned answer
# could not tell them apart. `pr list` keeps the original behavior, GH_FAIL included, so every
# scorer case above is driven exactly as it was.
cat > "$BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "repo view")
    [ -n "${GH_HOST_FAIL:-}" ] && { echo "gh: could not resolve to a Repository" >&2; exit 1; }
    printf '{"nameWithOwner":"%s"}\n' "${GH_HOST:-bench-owner/substrate}"
    exit 0 ;;
  "issue create")
    n="$(head -n1 "$ISSUE_SEQ")"
    [ -n "$n" ] || { echo "gh: the case ran out of issue numbers" >&2; exit 1; }
    tail -n +2 "$ISSUE_SEQ" > "$ISSUE_SEQ.next" && mv "$ISSUE_SEQ.next" "$ISSUE_SEQ"
    echo "https://example.invalid/bench-owner/substrate/issues/$n"
    exit 0 ;;
  "issue edit") exit 0 ;;
esac
[ -n "${GH_FAIL:-}" ] && { echo "gh: could not resolve to a Repository" >&2; exit 1; }
cat "$PR_ANSWER"
SH
chmod +x "$BIN/gh"
export GH="$BIN/gh"
GH_LOG="$WORK/gh.log"; export GH_LOG
PR_ANSWER="$WORK/pr.json"; export PR_ANSWER
ISSUE_SEQ="$WORK/issue-seq"; export ISSUE_SEQ
: > "$ISSUE_SEQ"
printf '[{"number":9,"headRefOid":"%s"}]\n' "$HEAD_SHA" > "$PR_ANSWER"

# ---- helpers ---------------------------------------------------------------------------------
mk_results() { # mk_results <file> [row-override...]
  local f="$1"; shift
  { printf '%s\n' "$HEADER"
    printf 't4-control-r2\t4\tcontrol\t2\tdeadbee\t2.1.263\tclaude-opus-5\tclaude-opus-5\tapproved\tapproved\t2\t18\t\t\t\t\t\t\t\n'
    printf 't1-skeleton-r1\t1\tskeleton\t1\tdeadbee\t2.1.263\tclaude-opus-5\tclaude-opus-5\treview-dark\tpr-unapproved\t\t\t\t\t\t\t\t\t\n'
  } > "$f"
  [ $# -gt 0 ] && printf '%s\n' "$@" >> "$f"
  return 0
}
col() { # col <file> <cell> <n>
  awk -F"$TAB" -v c="$2" -v n="$3" '$1 == c { print $n; exit }' "$1"
}
score() { # score <results> <cell> [extra args...]
  local r="$1" c="$2"; shift 2
  bash "$TOOL" score --results "$r" --cell "$c" --issue "$ISSUE" --config "$CONFIG" \
       --overlay "$OVERLAY" --defects "$DEFECTS" "$@" 2>&1
}

# ================================================================= (a) the full row
# The scenario: a cell whose lane produced one PR and two review rounds. Every score column has to
# carry a measured value, and the two detectors have to disagree — `defects_at_head` counts the one
# hidden test still failing, `defects_named` counts the two the reviewer named across BOTH record
# versions. A scorer that conflated them would score 1/3 or 3/3 here and 2/3 nowhere.
R="$WORK/a.tsv"; mk_results "$R"
out="$(score "$R" t4-control-r2)"; rc=$?
if [ "$rc" -eq 0 ] \
   && [ "$(col "$R" t4-control-r2 13)" = "$HEAD_SHA" ] \
   && [ "$(col "$R" t4-control-r2 14)" = "3" ] \
   && [ "$(col "$R" t4-control-r2 15)" = "4" ] \
   && [ "$(col "$R" t4-control-r2 16)" = "1" ] \
   && [ "$(col "$R" t4-control-r2 17)" = "2" ] \
   && [ "$(col "$R" t4-control-r2 18)" = "2/3" ] \
   && [ -n "$(col "$R" t4-control-r2 19)" ]; then
  pass "(a1) every score column is written: head, 3/4 tests, 1 defect at head, 2 named across two record versions, 2/3"
else fail "(a1) rc=$rc, row: $(awk -F"$TAB" '$1=="t4-control-r2"' "$R" | tr '\t' '|')  out: $out"; fi

if grep -qF "t4-control-r2 approved 3/4 1 2 2/3" <<<"$out"; then
  pass "(a2) the summary line carries the same six figures the row does"
else fail "(a2) summary line missing or disagreeing with the row: $out"; fi

if grep -q -- "--head $BRANCH" "$GH_LOG"; then
  pass "(a3) the PR is resolved on the config's branch prefix plus the issue, not on a guess"
else fail "(a3) gh was never asked about $BRANCH: $(cat "$GH_LOG")"; fi

# The pre-score columns are `run`'s and must survive untouched — a scorer that rewrote the whole
# row would silently re-stamp the arm's identity from its own environment.
if [ "$(col "$R" t4-control-r2 5)" = "deadbee" ] && [ "$(col "$R" t4-control-r2 10)" = "approved" ]; then
  pass "(a4) columns 1..12 are left exactly as run wrote them"
else fail "(a4) the scorer rewrote a pre-score column"; fi

# The OTHER row must not move. A rewrite keyed on the wrong thing would score every row alike.
if [ -z "$(col "$R" t1-skeleton-r1 13)" ] && [ -z "$(col "$R" t1-skeleton-r1 19)" ]; then
  pass "(a5) only the --cell row is written"
else fail "(a5) a second row was written"; fi

# The seeded-defect list is hand-authored by the operator, so its last row may carry no trailing
# newline. Dropping it would shrink review_catch's DENOMINATOR silently: the same lane would score
# a flattering 2/2 instead of 2/3, and the dropped defect's D-6 detector-pair refusal would never
# run. The fraction is the assertion — a count of rows read would pass on a scorer that read them
# and then scored something else.
NONL="$WORK/defects-nonl.tsv"
printf '%s' "$(cat "$DEFECTS")" > "$NONL"
[ -n "$(tail -c1 "$NONL")" ] || fail "(a6) fixture is not newline-less — the case cannot fail for the reason it names"
R1B="$WORK/a-nonl.tsv"; mk_results "$R1B"
out="$(bash "$TOOL" score --results "$R1B" --cell t4-control-r2 --issue "$ISSUE" --config "$CONFIG" \
        --overlay "$OVERLAY" --defects "$NONL" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(col "$R1B" t4-control-r2 18)" = "2/3" ] \
   && [ "$(col "$R1B" t4-control-r2 16)" = "1" ]; then
  pass "(a6) a defect list whose last row has no trailing newline is read whole — review_catch keeps all three in its denominator"
else fail "(a6) rc=$rc catch=$(col "$R1B" t4-control-r2 18) at_head=$(col "$R1B" t4-control-r2 16) out: $out"; fi

# ================================================================= (b) idempotence
prev="$(col "$R" t4-control-r2 19)"
sleep 1
out="$(score "$R" t4-control-r2)"; rc=$?
now="$(col "$R" t4-control-r2 19)"
if [ "$rc" -eq 0 ] && [ "$(col "$R" t4-control-r2 18)" = "2/3" ] && [ "$now" != "$prev" ] \
   && [ "$(wc -l < "$R")" -eq 3 ]; then
  pass "(b1) re-scoring a cell overwrites its score columns and refreshes scored_at, adding no row"
else fail "(b1) re-score changed shape: rc=$rc prev=$prev now=$now lines=$(wc -l < "$R")"; fi

# ================================================================= (c) n/a is not zero
# The scenario: an arm with no reviewer at all. `review_catch` must read `n/a` and `defects_named`
# must be EMPTY — a 0 would claim the reviewer named none of three, which is a different fact from
# "no reviewer ever wrote a record".
printf '[{"number":11,"headRefOid":"%s"}]\n' "$HEAD_NR" > "$PR_ANSWER"
R2="$WORK/c.tsv"; mk_results "$R2"
out="$(bash "$TOOL" score --results "$R2" --cell t1-skeleton-r1 --issue 77 --config "$CONFIG" \
        --overlay "$OVERLAY" --defects "$DEFECTS" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(col "$R2" t1-skeleton-r1 18)" = "n/a" ] \
   && [ -z "$(col "$R2" t1-skeleton-r1 17)" ] \
   && [ "$(col "$R2" t1-skeleton-r1 15)" = "4" ]; then
  pass "(c1) a branch with no verdict record scores review_catch=n/a with an EMPTY defects_named, and the hidden tests still run"
else fail "(c1) rc=$rc row: $(awk -F"$TAB" '$1=="t1-skeleton-r1"' "$R2" | tr '\t' '|') out: $out"; fi
printf '[{"number":9,"headRefOid":"%s"}]\n' "$HEAD_SHA" > "$PR_ANSWER"

# ================================================================= (d) no PR — empty, never zero
echo '[]' > "$PR_ANSWER"
R3="$WORK/d.tsv"; mk_results "$R3"
out="$(score "$R3" t4-control-r2)"; rc=$?
empties=0
for n in 13 14 15 16 17 18; do [ -z "$(col "$R3" t4-control-r2 "$n")" ] && empties=$((empties + 1)); done
if [ "$rc" -eq 0 ] && [ "$empties" -eq 6 ] && [ "$(col "$R3" t4-control-r2 10)" = "approved" ]; then
  pass "(d1) no PR leaves all six score columns EMPTY — not 0/0 — and does not touch the terminal class"
else fail "(d1) rc=$rc empties=$empties class=$(col "$R3" t4-control-r2 10) out: $out"; fi

# ================================================================= (e) an errored read is not an empty one
# The fail-open shape this repo refuses repo-wide: `gh` exiting non-zero must REFUSE, because a
# scorer that read it as "no PR" would write empty columns over a cell that has one.
mk_results "$WORK/e.tsv"
out="$(GH_FAIL=1 score "$WORK/e.tsv" t4-control-r2)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'is not a read that found nothing' <<<"$out" \
   && [ -z "$(col "$WORK/e.tsv" t4-control-r2 19)" ]; then
  pass "(e1) a gh read that ERRORS refuses and leaves the file untouched, rather than scoring the cell as PR-less"
else fail "(e1) rc=$rc out: $out"; fi
printf '[{"number":9,"headRefOid":"%s"}]\n' "$HEAD_SHA" > "$PR_ANSWER"

# ================================================================= (f) ambiguous PR
printf '[{"number":9,"headRefOid":"%s"},{"number":10,"headRefOid":"%s"}]\n' "$HEAD_SHA" "$HEAD_NR" > "$PR_ANSWER"
R5="$WORK/f.tsv"; mk_results "$R5"
out="$(score "$R5" t4-control-r2)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(col "$R5" t4-control-r2 10)" = "unscorable" ] \
   && [ -z "$(col "$R5" t4-control-r2 14)" ]; then
  pass "(f1) two PRs on the lane branch set terminal_class=unscorable and score nothing"
else fail "(f1) rc=$rc class=$(col "$R5" t4-control-r2 10) out: $out"; fi
printf '[{"number":9,"headRefOid":"%s"}]\n' "$HEAD_SHA" > "$PR_ANSWER"

# ================================================================= (g) an overlay that cannot apply
# A file in the overlay where the PR head has a DIRECTORY: cp refuses, and the cell is unscorable
# rather than a zero the arm did not earn.
BAD="$WORK/overlay-bad"; mkdir -p "$BAD"
cp "$OVERLAY/run.sh" "$BAD/run.sh"
echo "collides with the head's directory" > "$BAD/pkg"
R6="$WORK/g.tsv"; mk_results "$R6"
out="$(bash "$TOOL" score --results "$R6" --cell t4-control-r2 --issue "$ISSUE" --config "$CONFIG" \
        --overlay "$BAD" --defects "$DEFECTS" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(col "$R6" t4-control-r2 10)" = "unscorable" ] \
   && [ -z "$(col "$R6" t4-control-r2 14)" ] && [ "$(col "$R6" t4-control-r2 13)" = "$HEAD_SHA" ]; then
  pass "(g1) an overlay that cannot be applied is unscorable, never a zero, and the head it failed on is recorded"
else fail "(g1) rc=$rc class=$(col "$R6" t4-control-r2 10) out: $out"; fi

# ================================================================= (h) a run.sh that says nothing
SILENT="$WORK/overlay-silent"; mkdir -p "$SILENT"
printf '#!/usr/bin/env bash\necho "make: nothing to be done"\n' > "$SILENT/run.sh"
chmod +x "$SILENT/run.sh"
R7="$WORK/h.tsv"; mk_results "$R7"
out="$(bash "$TOOL" score --results "$R7" --cell t4-control-r2 --issue "$ISSUE" --config "$CONFIG" \
        --overlay "$SILENT" --defects "$DEFECTS" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(col "$R7" t4-control-r2 10)" = "unscorable" ] \
   && [ -z "$(col "$R7" t4-control-r2 15)" ]; then
  pass "(h1) a run.sh printing no TEST line is unscorable, not 0/0 — nothing was measured"
else fail "(h1) rc=$rc class=$(col "$R7" t4-control-r2 10) out: $out"; fi

# ================================================================= (i) refusals (#812 D-6)
R8="$WORK/i.tsv"; mk_results "$R8"
out="$(score "$R8" t9-nope-r1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "no row for cell 't9-nope-r1'" <<<"$out"; then
  pass "(i1) a cell with no row refuses"
else fail "(i1) rc=$rc out: $out"; fi

mk_results "$R8" "$(printf 't2-control-r1\t2\t\t1\tdeadbee\t2.1.263\tclaude-opus-5\tclaude-opus-5\tbuild-no-pr\tpaused\t\t\t\t\t\t\t\t\t')"
out="$(score "$R8" t2-control-r1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'missing pre-score column(s) 3' <<<"$out"; then
  pass "(i2) a row with a blank pre-score column refuses and names the column"
else fail "(i2) rc=$rc out: $out"; fi

NORUN="$WORK/overlay-norun"; mkdir -p "$NORUN"; echo x > "$NORUN/thing"
out="$(bash "$TOOL" score --results "$R8" --cell t4-control-r2 --issue "$ISSUE" --config "$CONFIG" \
        --overlay "$NORUN" --defects "$DEFECTS" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'carries no run.sh' <<<"$out"; then
  pass "(i3) an overlay with no run.sh refuses"
else fail "(i3) rc=$rc out: $out"; fi

# The one refusal that is about the DETECTOR PAIR rather than about an input's shape: a defect
# whose test id the overlay never reports would otherwise be silently scored "not present at
# head", crediting the arm for a test that never ran.
BADDEF="$WORK/defects-bad.tsv"
{ printf 'id\tfile\tdescription\ttest_id\tverdict_regex\n'
  printf 'D-z\tpkg/mod.txt\tnames a test the overlay does not have\tt-ghost\tsomething\n'; } > "$BADDEF"
R9="$WORK/i4.tsv"; mk_results "$R9"
out="$(bash "$TOOL" score --results "$R9" --cell t4-control-r2 --issue "$ISSUE" --config "$CONFIG" \
        --overlay "$OVERLAY" --defects "$BADDEF" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "names test id 't-ghost'" <<<"$out" \
   && [ -z "$(col "$R9" t4-control-r2 19)" ]; then
  pass "(i4) a seeded defect whose test id the overlay never reports refuses, and writes nothing"
else fail "(i4) rc=$rc out: $out"; fi

BADCFG="$WORK/bad.json"; echo '{ nope' > "$BADCFG"
out="$(bash "$TOOL" score --results "$R9" --cell t4-control-r2 --issue "$ISSUE" --config "$BADCFG" \
        --overlay "$OVERLAY" --defects "$DEFECTS" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'not parseable JSON' <<<"$out"; then
  pass "(i5) an unparseable eval config refuses rather than falling back to defaults"
else fail "(i5) rc=$rc out: $out"; fi

BADHDR="$WORK/badhdr.tsv"; { echo "cell_id${TAB}whatever"; echo "t4-control-r2${TAB}x"; } > "$BADHDR"
out="$(score "$BADHDR" t4-control-r2)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q '19-column header' <<<"$out"; then
  pass "(i6) a results file whose header is not the 19-column contract refuses — the scorer will not rewrite a shape it cannot vouch for"
else fail "(i6) rc=$rc out: $out"; fi

# ================================================================= (j) the class table is DERIVED
# The completeness guard (#812 D-15). docs/lane-bench.md claims the table covers the lane's full
# slug vocabulary; this is what makes that claim falsifiable. It reads the vocabulary out of the
# shipped scheduler and compares both ways.
if [ -f "$ORCH" ]; then
  CODE="$WORK/slugs-code"; TABLE="$WORK/slugs-table"
  # Command position only: start of line, or after ||, &&, ;, a case-arm ), then, else, do. That
  # excludes `terminal "$1" 2 …` inside envfail() (a variable, not a slug) and every prose mention
  # of the word "terminal", both of which a bare word match sweeps in.
  grep -oE '(^|\|\||&&|;|\)|then|else|do)[[:space:]]+(terminal|envfail)[[:space:]]+[a-z][a-z0-9-]*' "$ORCH" \
    | awk '{ print $NF }' > "$CODE"
  # Plus the announced-but-not-terminal member, which carries the scheduler's own marker prefix.
  grep -oE 'terminal-vocabulary:[[:space:]]+[a-z][a-z0-9-]*' "$ORCH" | awk '{ print $NF }' >> "$CODE"
  sort -u -o "$CODE" "$CODE"
  awk -F"$TAB" '!/^#/ && NF >= 2 { print $1 }' "$CLASSES" | sort -u > "$TABLE"

  if [ -s "$CODE" ] && [ "$(wc -l < "$CODE")" -ge 20 ]; then
    pass "(j1) the derivation reads a plausible vocabulary out of the scheduler ($(wc -l < "$CODE" | tr -d ' ') slugs) — a zero here would make (j2) vacuous"
  else fail "(j1) the derivation extracted $(wc -l < "$CODE" | tr -d ' ') slug(s) from $ORCH — it no longer models the scheduler's call sites and must be taught the new shape before it can speak for the table"; fi

  miss="$(comm -23 "$CODE" "$TABLE" | tr '\n' ' ')"
  extra="$(comm -13 "$CODE" "$TABLE" | tr '\n' ' ')"
  if [ -z "$miss" ] && [ -z "$extra" ]; then
    pass "(j2) lane-bench-classes.tsv names exactly the scheduler's slug vocabulary, both directions"
  else fail "(j2) class table drift — in the scheduler but not the table: [${miss}]; in the table but not the scheduler: [${extra}]"; fi

  # Every class the table uses must be one of the six the protocol declares, plus the `-` the one
  # announced non-terminal carries. An unmodelled class would make a row unreadable to `run`.
  badcls="$(awk -F"$TAB" '!/^#/ && NF >= 2 && $2 !~ /^(approved|paused|no-pr|pr-unapproved|lane-error|unscorable|-)$/ { print $1 "=" $2 }' "$CLASSES" | tr '\n' ' ')"
  if [ -z "$badcls" ]; then
    pass "(j3) every row's class is one of the six declared classes, or the '-' of the announced non-terminal"
  else fail "(j3) unmodelled class(es): $badcls"; fi

  arity="$(awk -F"$TAB" '!/^#/ && NF { if (NF != 3) print NR }' "$CLASSES" | tr '\n' ' ')"
  if [ -z "$arity" ]; then
    pass "(j4) every row carries all three columns"
  else fail "(j4) rows at wrong arity: $arity"; fi
else
  fail "(j) cannot find the scheduler at $ORCH — the completeness guard did not run, and a skipped guard is not a passing one"
fi

# ================================================================================================
# `run` — one cell end to end (#813)
# ================================================================================================
# THE SCENARIO THESE GUARD is a cell's bookkeeping: which tracker it is allowed to write to, what
# it hands the lane, what it reads back out of the lane's leavings, and that a matrix resumed
# after an interruption cannot double-count a cell. The lane itself is a STUB at the
# `LANE_BENCH_BIN` seam (#811 D-34): driving the real `orchestrate.sh` behind a `claude`
# fake would be a second copy of `orchestrate-selftest.sh` with this file's name on it, and
# what is under test here is the runner, not the scheduler.

# ---- a second-shift checkout to cut arms from ---------------------------------------------------
SS="$WORK/second-shift"
mkdir -p "$SS"
git -C "$SS" init -q
git -C "$SS" config user.email bench@example.invalid
git -C "$SS" config user.name  "Bench Fixture"
for pl in second-shift dev-pipeline review-toolkit intake-toolkit audit-toolkit design-toolkit; do
  mkdir -p "$SS/plugins/$pl/.claude-plugin"
  printf '{"name":"%s"}\n' "$pl" > "$SS/plugins/$pl/.claude-plugin/plugin.json"
done
# A directory under plugins/ with no manifest: the full-kit manifest is built from what declares
# itself a plugin, not from what happens to be a directory.
mkdir -p "$SS/plugins/not-a-plugin"
echo "scratch" > "$SS/plugins/not-a-plugin/notes.md"
git -C "$SS" add -A && git -C "$SS" commit -qm "kit"
SS_SHA="$(git -C "$SS" rev-parse HEAD)"

# ---- the lane stub ------------------------------------------------------------------------------
# It writes what the runner reads — a launch ledger, optionally a progress record — and records
# what it was handed, so "the runner exported the three variables and launched from the substrate"
# is a measurement rather than a claim. Its state dir is derived from its OWN cwd, which is how
# the `cd $ROOT` is asserted: a runner that launched from somewhere else would write the ledger
# where the runner is not looking.
LANE="$WORK/lane-stub.sh"
cat > "$LANE" <<'SH'
#!/usr/bin/env bash
issue="$1"
{ echo "ARGV: $*"
  echo "LANE_SPAWN_BIN=${LANE_SPAWN_BIN:-}"
  echo "LANE_ARM_MANIFEST=${LANE_ARM_MANIFEST:-}"
  echo "SECOND_SHIFT_CONFIG=${SECOND_SHIFT_CONFIG:-}"
  echo "CWD=$PWD"; } >> "$LANE_LOG"
[ -n "${LANE_ARM_MANIFEST:-}" ] && cp "$LANE_ARM_MANIFEST" "$LANE_MANIFEST_COPY"
sd="$PWD/.claude/pipeline-state"
mkdir -p "$sd"
term="$(head -n1 "$LANE_TERM_SEQ")"
tail -n +2 "$LANE_TERM_SEQ" > "$LANE_TERM_SEQ.next" && mv "$LANE_TERM_SEQ.next" "$LANE_TERM_SEQ"
[ "$term" = "NONE" ] && exit 1
{ printf '2026-09-07T10:00:00Z\tRUN\t%s\tlaunch\tbranch_key=%s\n' "$issue" "$issue"
  [ -n "${LANE_BUILD_SID:-}" ] && printf '2026-09-07T10:00:01Z\tRUN\t%s\tspawn\tn=1 role=BUILD model=opus id=%s\n' "$issue" "$LANE_BUILD_SID"
  [ -n "${LANE_REVIEW_SID:-}" ] && printf '2026-09-07T10:00:02Z\tRUN\t%s\tspawn\tn=2 role=REVIEW model=opus id=%s\n' "$issue" "$LANE_REVIEW_SID"
  printf '2026-09-07T10:18:00Z\tRUN\t%s\tterminal\t%s\n' "$issue" "$term"; } > "$sd/$issue-lean-launches.tsv"
[ -n "${LANE_PROGRESS:-}" ] && printf '%s\n' "$LANE_PROGRESS" > "$sd/$issue-lean-progress.md"
exit 0
SH
chmod +x "$LANE"
LANE_LOG="$WORK/lane.log"; export LANE_LOG
LANE_MANIFEST_COPY="$WORK/manifest-copy"; export LANE_MANIFEST_COPY
LANE_TERM_SEQ="$WORK/term-seq"; export LANE_TERM_SEQ

# ---- a `claude` whose only job here is to name a version ------------------------------------------
cat > "$BIN/claude" <<'SH'
#!/usr/bin/env bash
[ "$1" = "--version" ] && { echo "2.1.263 (Claude Code)"; exit 0; }
exit 0
SH
chmod +x "$BIN/claude"

# ---- payload transcripts ---------------------------------------------------------------------
# Named for the FULL session id while the ledger records the SHORT one, which is the shape the
# harness actually produces and the reason the read globs on a prefix.
FAKEHOME="$WORK/home"
mkdir -p "$FAKEHOME/.claude/projects/some-cwd-slug"
printf '{"type":"assistant","message":{"model":"claude-opus-5-resolved-build"}}\n' \
  > "$FAKEHOME/.claude/projects/some-cwd-slug/bsid0001-d505-4a8b-83f0-66f798415a20.jsonl"
printf '{"type":"assistant","message":{"model":"claude-opus-5-resolved-review"}}\n' \
  > "$FAKEHOME/.claude/projects/some-cwd-slug/rsid0001-d505-4a8b-83f0-66f798415a20.jsonl"

BODY="$WORK/ticket-body.md"
printf '# The corpus role 1 ticket\n\nA happy-path change.\n' > "$BODY"
RECEIPT="$WORK/ticket-receipt.md"
printf '## Decision Ledger\n\n| D-1 | x | y | user-answered |\n' > "$RECEIPT"
STATE="$SUB/.claude/pipeline-state"

runcell() { # runcell <results> <arm> <extra args...>
  local r="$1" arm="$2"; shift 2
  env PATH="$BIN:$PATH" HOME="$FAKEHOME" \
      LANE_BENCH_ROOT="$SS" LANE_BENCH_BIN="$LANE" \
      LANE_BENCH_POLL_SECS=0.2 LANE_BENCH_CELL_CEILING_SECS="${CEIL:-60}" \
      bash "$TOOL" run --results "$r" --arm "$arm" --config "$CONFIG" \
        --substrate bench-owner/substrate --overlay "$OVERLAY" --defects "$DEFECTS" \
        --body "$BODY" --receipt "$RECEIPT" "$@" 2>&1
}
rows() { awk 'NR > 1' "$1" | wc -l | tr -d ' '; }

# ================================================================= (k) the approved cell
# Every column the runner owns has to be measured rather than assumed, and the two model columns
# have to carry RESOLVED ids: `opus` is an alias that moves with releases, so a series that
# recorded it could not tell a model change from a kit change.
printf '42\n' > "$ISSUE_SEQ"
printf 'approved rc=0 — the PR is approved and closed out\n' > "$LANE_TERM_SEQ"
printf '[{"number":9,"headRefOid":"%s"}]\n' "$HEAD_SHA" > "$PR_ANSWER"
LANE_BUILD_SID=bsid0001 LANE_REVIEW_SID=rsid0001; export LANE_BUILD_SID LANE_REVIEW_SID
unset LANE_PROGRESS
RK="$WORK/k.tsv"; mk_results "$RK"
before="$(rows "$RK")"
: > "$LANE_LOG"; : > "$GH_LOG"
out="$(runcell "$RK" ctl --arm-ref "$SS_SHA" --ticket 1 --repeat 1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(rows "$RK")" -eq "$((before + 1))" ] \
   && [ "$(col "$RK" t1-ctl-r1 5)" = "$SS_SHA" ] \
   && [ "$(col "$RK" t1-ctl-r1 6)" = "2.1.263" ] \
   && [ "$(col "$RK" t1-ctl-r1 7)" = "claude-opus-5-resolved-build" ] \
   && [ "$(col "$RK" t1-ctl-r1 8)" = "claude-opus-5-resolved-review" ] \
   && [ "$(col "$RK" t1-ctl-r1 9)" = "approved" ] \
   && [ "$(col "$RK" t1-ctl-r1 10)" = "approved" ] \
   && [ "$(col "$RK" t1-ctl-r1 11)" = "2" ] \
   && [ "$(col "$RK" t1-ctl-r1 12)" = "18" ]; then
  pass "(k1) an approved cell appends exactly one row carrying the arm's harness_sha, the CLI version, both RESOLVED model ids, the terminal slug and class, the verdict record's rounds, and 18 wall minutes"
else fail "(k1) rc=$rc rows=$(rows "$RK") row: $(awk -F"$TAB" '$1=="t1-ctl-r1"' "$RK" | tr '\t' '|')  out: $out"; fi

# `run` ends by handing the row to `score`, so the score columns must be filled by the same call.
if [ "$(col "$RK" t1-ctl-r1 13)" = "$HEAD_SHA" ] && [ "$(col "$RK" t1-ctl-r1 18)" = "2/3" ]; then
  pass "(k2) run calls score on the row it appended — the cell comes out scored, not half-written"
else fail "(k2) score columns: $(col "$RK" t1-ctl-r1 13) / $(col "$RK" t1-ctl-r1 18)"; fi

# What the lane was handed. Each of the three is load-bearing: without SECOND_SHIFT_CONFIG the
# payload silently falls back to the committed config and targets the wrong base branch, and
# without the other two the session loads the machine's own kit instead of the arm's.
if grep -q "LANE_SPAWN_BIN=$HERE/lane-bench-arm.sh" "$LANE_LOG" \
   && grep -q "SECOND_SHIFT_CONFIG=$CONFIG" "$LANE_LOG" \
   && grep -q "CWD=$SUB" "$LANE_LOG"; then
  pass "(k3) the lane is launched from the substrate root with the arm wrapper as LANE_SPAWN_BIN and the eval config forwarded"
else fail "(k3) lane env: $(cat "$LANE_LOG")"; fi

if grep -q -- '--build-model opus --review-model opus' "$LANE_LOG" \
   && grep -q -- '--max-rounds 2' "$LANE_LOG" \
   && grep -q -- '--review-model-basis' "$LANE_LOG"; then
  pass "(k4) both models, the basis and the round cap are passed explicitly, never left to a default"
else fail "(k4) argv: $(grep '^ARGV' "$LANE_LOG")"; fi

if [ "$(wc -l < "$LANE_MANIFEST_COPY" | tr -d ' ')" -eq 6 ] \
   && ! grep -qv '^/' "$LANE_MANIFEST_COPY" \
   && ! grep -q 'not-a-plugin' "$LANE_MANIFEST_COPY"; then
  pass "(k5) the full-kit manifest names the six directories that declare a plugin manifest, absolute, and skips a plugins/ directory that declares none"
else fail "(k5) manifest: $(tr '\n' ' ' < "$LANE_MANIFEST_COPY")"; fi

if [ -f "$STATE/42-ledger.md" ] && grep -q 'Decision Ledger' "$STATE/42-ledger.md"; then
  pass "(k6) the fixture receipt lands at the gate's ledger path, so no cell measures the interview"
else fail "(k6) no receipt at $STATE/42-ledger.md"; fi

if grep -q 'issue edit 42 .*--add-label ready-for-dev' "$GH_LOG"; then
  pass "(k7) the queue label is applied — without it the lane rejects the launch at preflight and the cell measures a refusal"
else fail "(k7) gh log: $(cat "$GH_LOG")"; fi

# ================================================================= (l) the {paused, no-pr} pair
# `build-no-pr` is the one slug whose class turns on the progress record rather than on a PR. The
# distinction is the corpus's role-2 measurement: a seeded ambiguity must cost a pause, not a guess.
printf '91\n' > "$ISSUE_SEQ"
printf 'build-no-pr rc=1 — the build produced no PR\n' > "$LANE_TERM_SEQ"
echo '[]' > "$PR_ANSWER"
LANE_PROGRESS='| milestone-1 | pause-and-ask | OR-3 is unresolved |'; export LANE_PROGRESS
RL="$WORK/l.tsv"; mk_results "$RL"
out="$(runcell "$RL" ctl --arm-ref "$SS_SHA" --ticket 2 --repeat 1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(col "$RL" t2-ctl-r1 9)" = "build-no-pr" ] \
   && [ "$(col "$RL" t2-ctl-r1 10)" = "paused" ]; then
  pass "(l1) build-no-pr WITH a milestone-1 pause-and-ask row classifies as paused"
else fail "(l1) rc=$rc class=$(col "$RL" t2-ctl-r1 10) out: $out"; fi

printf '92\n' > "$ISSUE_SEQ"
printf 'build-no-pr rc=1 — the build produced no PR\n' > "$LANE_TERM_SEQ"
unset LANE_PROGRESS
RL2="$WORK/l2.tsv"; mk_results "$RL2"
out="$(runcell "$RL2" ctl --arm-ref "$SS_SHA" --ticket 2 --repeat 2)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(col "$RL2" t2-ctl-r2 10)" = "no-pr" ] \
   && [ -z "$(col "$RL2" t2-ctl-r2 14)" ]; then
  pass "(l2) the SAME slug without that row classifies as no-pr, and a cell with no PR scores empty rather than zero"
else fail "(l2) rc=$rc class=$(col "$RL2" t2-ctl-r2 10) out: $out"; fi

# ================================================================= (m/n) the {pr-unapproved, no-pr} pair
# `review-dark` is the shape every cell of an arm without review-toolkit produces, so this is also
# where `review_model` has no session to read: `n/a`, never empty, because `score` refuses a row
# with a blank pre-score column and 0 would claim a reviewer was asked.
printf '77\n' > "$ISSUE_SEQ"
printf 'review-dark rc=5 — no verdict record\n' > "$LANE_TERM_SEQ"
printf '[{"number":11,"headRefOid":"%s"}]\n' "$HEAD_NR" > "$PR_ANSWER"
unset LANE_REVIEW_SID
: > "$LANE_MANIFEST_COPY"
RN="$WORK/n.tsv"; mk_results "$RN"
out="$(runcell "$RN" skel --skeleton --control-ref "$SS_SHA" --ticket 1 --repeat 2)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(col "$RN" t1-skel-r2 10)" = "pr-unapproved" ] \
   && [ "$(col "$RN" t1-skel-r2 8)" = "n/a" ] \
   && [ "$(col "$RN" t1-skel-r2 18)" = "n/a" ]; then
  pass "(n1) review-dark WITH a PR is pr-unapproved, and a cell that spawned no REVIEW session carries review_model=n/a — the same word review_catch carries, for the same reason"
else fail "(n1) rc=$rc class=$(col "$RN" t1-skel-r2 10) review_model=$(col "$RN" t1-skel-r2 8) out: $out"; fi

if [ "$(wc -l < "$LANE_MANIFEST_COPY" | tr -d ' ')" -eq 2 ] \
   && grep -q '/plugins/dev-pipeline$' "$LANE_MANIFEST_COPY" \
   && grep -q '/plugins/audit-toolkit$' "$LANE_MANIFEST_COPY"; then
  pass "(n2) --skeleton assembles the two-directory floor out of the control worktree, not the arm's whole kit"
else fail "(n2) manifest: $(tr '\n' ' ' < "$LANE_MANIFEST_COPY")"; fi

printf '94\n' > "$ISSUE_SEQ"
printf 'review-dark rc=5 — no verdict record\n' > "$LANE_TERM_SEQ"
echo '[]' > "$PR_ANSWER"
RM="$WORK/m.tsv"; mk_results "$RM"
out="$(runcell "$RM" skel --skeleton --control-ref "$SS_SHA" --ticket 1 --repeat 3)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(col "$RM" t1-skel-r3 10)" = "no-pr" ]; then
  pass "(m1) the same slug WITHOUT a PR is no-pr — the pair is decided by PR presence, not by the slug"
else fail "(m1) rc=$rc class=$(col "$RM" t1-skel-r3 10) out: $out"; fi
LANE_REVIEW_SID=rsid0001; export LANE_REVIEW_SID

# ================================================================= (o) lane-error and its one re-run
# A class the bench cannot read is re-run on a FRESH issue, never re-scored on the old one: lane
# state is keyed on the issue number and none of it is deleted, so a reused issue would report
# series-to-series elapsed time as run time.
printf '95\n42\n' > "$ISSUE_SEQ"
printf 'spawn-unreadable rc=1 — no readable session id\napproved rc=0 — approved on the retry\n' > "$LANE_TERM_SEQ"
printf '[{"number":9,"headRefOid":"%s"}]\n' "$HEAD_SHA" > "$PR_ANSWER"
: > "$GH_LOG"
RO="$WORK/o.tsv"; mk_results "$RO"
before="$(rows "$RO")"
out="$(runcell "$RO" ctl --arm-ref "$SS_SHA" --ticket 4 --repeat 1)"; rc=$?
creates="$(grep -c '^issue create' "$GH_LOG")"
if [ "$rc" -eq 0 ] && [ "$(rows "$RO")" -eq "$((before + 1))" ] \
   && [ "$creates" -eq 2 ] && [ "$(col "$RO" t4-ctl-r1 10)" = "approved" ] \
   && grep -q 're-running once with a fresh issue' <<<"$out"; then
  pass "(o1) a lane-error cell is re-run once on a FRESH issue and only the retry's terminal reaches the results file — one row, not two"
else fail "(o1) rc=$rc rows=$(rows "$RO") creates=$creates class=$(col "$RO" t4-ctl-r1 10) out: $out"; fi

# Two lane errors is the operator's problem. The row is still recorded — a cell the bench could
# not read is a fact about the arm — and the exit code says so without pretending the file is
# untouched, which is what a refusal's exit 2 would claim.
printf '96\n97\n' > "$ISSUE_SEQ"
printf 'NONE\nNONE\n' > "$LANE_TERM_SEQ"
echo '[]' > "$PR_ANSWER"
: > "$GH_LOG"
RO2="$WORK/o2.tsv"; mk_results "$RO2"
before="$(rows "$RO2")"
out="$(CEIL=1 runcell "$RO2" ctl --arm-ref "$SS_SHA" --ticket 5 --repeat 1)"; rc=$?
creates="$(grep -c '^issue create' "$GH_LOG")"
if [ "$rc" -eq 1 ] && [ "$(rows "$RO2")" -eq "$((before + 1))" ] && [ "$creates" -eq 2 ] \
   && [ "$(col "$RO2" t5-ctl-r1 9)" = "no-terminal-row" ] \
   && [ "$(col "$RO2" t5-ctl-r1 10)" = "lane-error" ] \
   && grep -q 'a SECOND time' <<<"$out"; then
  pass "(o2) a lane that never writes a terminal row hits the cell ceiling, classifies lane-error, takes its one re-run, and is then recorded with exit 1 — a row written, not a refusal"
else fail "(o2) rc=$rc rows=$(rows "$RO2") creates=$creates slug=$(col "$RO2" t5-ctl-r1 9) out: $out"; fi

# ================================================================= (p) unscorable
printf '98\n' > "$ISSUE_SEQ"
printf 'approved rc=0 — approved\n' > "$LANE_TERM_SEQ"
printf '[{"number":9,"headRefOid":"%s"},{"number":10,"headRefOid":"%s"}]\n' "$HEAD_SHA" "$HEAD_NR" > "$PR_ANSWER"
RP="$WORK/p.tsv"; mk_results "$RP"
out="$(runcell "$RP" ctl --arm-ref "$SS_SHA" --ticket 6 --repeat 1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(col "$RP" t6-ctl-r1 10)" = "unscorable" ] \
   && [ "$(col "$RP" t6-ctl-r1 9)" = "approved" ]; then
  pass "(p1) two PRs on the lane branch leave the runner's terminal slug alone and let score rewrite the class to unscorable"
else fail "(p1) rc=$rc class=$(col "$RP" t6-ctl-r1 10) out: $out"; fi
printf '[{"number":9,"headRefOid":"%s"}]\n' "$HEAD_SHA" > "$PR_ANSWER"

# ================================================================= (q..t) the four pre-cell refusals
# EVERY ONE ASSERTS THAT NO ISSUE WAS FILED. That is the property AC-10 turns on: a refusal that
# fired after `gh issue create` has already written to a tracker, and the exit code cannot take
# that back.
refused_before_filing() { # refused_before_filing <label> <rc> <out> <fragment> <results> <rows>
  local label="$1" rc="$2" out="$3" frag="$4" res="$5" want="$6"
  if [ "$rc" -eq 2 ] && grep -q "$frag" <<<"$out" \
     && [ "$(grep -c '^issue create' "$GH_LOG")" -eq 0 ] \
     && [ "$(rows "$res")" -eq "$want" ]; then
    pass "$label"
  else fail "$label — rc=$rc creates=$(grep -c '^issue create' "$GH_LOG") rows=$(rows "$res") out: $out"; fi
}

printf '99\n' > "$ISSUE_SEQ"
printf 'approved rc=0 — approved\n' > "$LANE_TERM_SEQ"
RQ="$WORK/q.tsv"
mk_results "$RQ" "$(printf 't4-ctl-r2\t4\tctl\t2\t%s\t2.1.263\tm\tm\tapproved\tapproved\t1\t5\t\t\t\t\t\t\t' "$SS_SHA")"
: > "$GH_LOG"
out="$(runcell "$RQ" ctl --arm-ref "$SS_SHA" --ticket 4 --repeat 2)"; rc=$?
refused_before_filing "(q1) a cell id already in the results file is refused before anything is filed — the matrix is resumed by re-running the cells that have no row, which only works if this refuses" \
  "$rc" "$out" "already carries a row for cell" "$RQ" 3

RR="$WORK/r.tsv"; mk_results "$RR"
printf 't7-ctl-r9\t7\tctl\t9\tOTHERSHA\t2.1.263\tm\tm\tapproved\tapproved\t1\t5\t\t\t\t\t\t\t\n' >> "$RR"
: > "$GH_LOG"
out="$(runcell "$RR" ctl --arm-ref "$SS_SHA" --ticket 7 --repeat 1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'within one arm the harness is a constant' <<<"$out" \
   && [ "$(grep -c '^issue create' "$GH_LOG")" -eq 0 ] && [ "$(rows "$RR")" -eq 3 ]; then
  pass "(r1) an arm whose existing row carries a different harness_sha is refused — two kits averaged under one label is the confusion the bench exists to remove"
else fail "(r1) rc=$rc creates=$(grep -c '^issue create' "$GH_LOG") out: $out"; fi

RS="$WORK/s.tsv"; mk_results "$RS"
echo "uncommitted" > "$SS/plugins/dev-pipeline/scratch.txt"
: > "$GH_LOG"
out="$(runcell "$RS" ctl --arm-ref "$SS_SHA" --ticket 1 --repeat 9)"; rc=$?
refused_before_filing "(s1) a dirty second-shift checkout is refused — an arm is a commit, and a cell run from a dirty tree records a harness_sha that does not describe what ran" \
  "$rc" "$out" "is not clean" "$RS" 2
rm -f "$SS/plugins/dev-pipeline/scratch.txt"

RT="$WORK/t.tsv"; mk_results "$RT"
: > "$GH_LOG"
out="$(GH_HOST=some-owner/a-real-repo runcell "$RT" ctl --arm-ref "$SS_SHA" --ticket 1 --repeat 8)"; rc=$?
refused_before_filing "(t1) an eval config resolving to a tracker host that is not the substrate is refused BEFORE an issue is filed — this is AC-10's rung" \
  "$rc" "$out" "not the substrate" "$RT" 2

# A host read that ERRORS is the same fail-open shape the scorer refuses on its own gh call: an
# unverified host is exactly the case this must not run in.
: > "$GH_LOG"
out="$(GH_HOST_FAIL=1 runcell "$RT" ctl --arm-ref "$SS_SHA" --ticket 1 --repeat 8)"; rc=$?
refused_before_filing "(t2) a gh read that errored while resolving the tracker host refuses, rather than proceeding on an unverified one" \
  "$rc" "$out" "a read that errored is not a read that agreed" "$RT" 2

echo
echo "lane-bench-selftest: $PASSES passed, $FAILS failed"
[ "$FAILS" -eq 0 ] || exit 1

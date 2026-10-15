#!/usr/bin/env bash
# verdict-check-selftest.sh — behavioral selftest for tools/verdict-check.sh (#991 AC-1).
#
# INVARIANTS GUARDED: PR #983's two verdicts as posted are rejected against the #979 record at each
# head and at its first commit (round 1 names "needs-work with no blocker", round 2 "Findings not in
# the grammar"); each rule passes and fails; a render-unavailable needs-work passes; a row the build
# deleted or added is still owed a score; every failed rule is printed, not only the first; a record
# that cannot be read is exit 2. The run.sh wiring is a scenario case in skills/run/run-verdict-selftest.sh.
#
# Operator-safe: no network. Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/verdict-check.sh"
FX="$HERE/verdict-check-fixtures"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/verdict-check-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT

SHA=0123456789abcdef0123456789abcdef01234567
# two record versions: D-1 and D-2 at the first commit; at the head D-2 is gone and D-3 was added.
# The indented row is a fan-out snapshot, never one of the record's own (#991 D-6).
printf '# record\n\n| ID | Decision | Resolution | Provenance |\n| --- | --- | --- | --- |\n| D-1 | a | b | user-answered |\n| D-2 | c | d | user-answered |\n\n## Fan-out\n\n    | D-77 | snapshot | x | y |\n' > "$T/first.md"
printf '# record\n\n| ID | Decision | Resolution | Provenance |\n| --- | --- | --- | --- |\n| D-1 | a | b | user-answered |\n| D-3 | e | f | user-delegated |\n' > "$T/head.md"
HEAD_ROWS=$'| D-1 a | honored | x |\n| D-2 c | departed (deleted by the build) | y |\n| D-3 e | honored | z |'

# check <name> <body> -> $RC, $OUT; the body is printf %s'd, so pass real newlines
check() { printf '%s\n' "$2" > "$T/$1.md"; OUT="$(bash "$TOOL" "$T/$1.md" "${HEADREC:-$T/head.md}" "${FIRSTREC:-$T/first.md}" 2>"$T/$1.err")"; RC=$?; }
# body <verdict> <rows> <findings> [extra after findings]
body() { printf 'verdict: %s\nreviewed: %s\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n%s\n\n## Findings\n\n%s\n%s' "$1" "$SHA" "$2" "$3" "${4:-}"; }
has() { grep -qF -- "$1" <<<"$OUT"; }
passes() { [ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "$1" || bad "$1: rc=$RC out=$(tr '\n' '|' <<<"$OUT")"; }
fails_with() { [ "$RC" -eq 1 ] && has "$2" && ok "$1" || bad "$1: rc=$RC, wanted '$2', out=$(tr '\n' '|' <<<"$OUT")"; }

echo "== verdict-check.sh =="

# ---- AC-1: PR #983's verdicts as posted, against the #979 record at each head and at its first commit ----
OUT="$(bash "$TOOL" "$FX/pr983-round1.md" "$FX/record-979-at-7100d01b.md" "$FX/record-979-at-7100d01b.md")"; RC=$?   # 1be8b826's record is byte-identical to 7100d01b's
fails_with "(ac1) #983 round 1 (needs-work on one Warning) is rejected" "needs-work with no blocker"
has "Decision record rows not in the grammar" && has "unknown section: ## review-lead" && has "Ready to merge? in the body" \
  && ok "(ac1) round 1 also names its prose in the rows section, its extra sections and 'Ready to merge?'" || bad "(ac1) round 1: $(tr '\n' '|' <<<"$OUT")"
OUT="$(bash "$TOOL" "$FX/pr983-round2.md" "$FX/record-979-at-c9ff84e4.md" "$FX/record-979-at-7100d01b.md")"; RC=$?
fails_with "(ac1) #983 round 2 (approve beside a must-fix Warning) is rejected" "Findings not in the grammar"
! has "record row not scored" && ! has "row not in the record" && ok "(ac1) round 2 scored D-8, the row its build added, and every other row" || bad "(ac1) round 2 rows: $(tr '\n' '|' <<<"$OUT")"

# ---- each rule passing ----
check approve "$(body approve "$HEAD_ROWS" $'- [note] N1 a thing to know\n  continued on an indented line\n\n- [note] N2 suppressed (confidence 40)')"
passes "(v1) a consistent approve passes: every row of both versions scored, notes only, continuation lines indented"
check nw-blocker "$(body needs-work "$HEAD_ROWS" $'- [blocker] B1 fix this before merge\n- [note] N1 and this is optional')"
passes "(v2) a needs-work with a [blocker] passes"
check nw-violated "$(body needs-work $'| D-1 a | violated | x |\n| D-2 c | honored | y |\n| D-3 e | honored | z |' 'None.')"
passes "(v3) a needs-work with a violated row and no finding passes"
check nw-undet "$(body needs-work $'| D-1 a | undeterminable | x |\n| D-2 c | honored | y |\n| D-3 e | honored | z |' 'None.')"
passes "(v3) a needs-work with an undeterminable row passes"
check render "$(printf 'verdict: needs-work\nreviewed: %s\nreason: render-unavailable\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n\n## Findings\n\nNone.' "$SHA")"
passes "(v4) a render-unavailable needs-work passes with no blocker and no row scored"
check panel-notes "$(body approve "$HEAD_ROWS" 'None.' $'\n## Panel\n\n| Reviewer | Verdict |\n| --- | --- |\n| Scope | Pass |\n\n## Notes\n\nrevised after reading the account of the build: nothing changed.\n- [blocker] B9 quoted in prose, not a finding\n### a sub-heading is prose too')"
passes "(v5) ## Panel and ## Notes are optional and unparsed; a [blocker] line in Notes counts for nothing"
check crlf "$(body approve "$HEAD_ROWS" 'None.' | awk '{ printf "%s\r\n", $0 }')"
passes "(v6) a CRLF body passes"
check escaped "$(body approve $'| D-1 a | honored | `a \\|\\| b` |\n| D-2 c | honored | y |\n| D-3 e | honored | z |' 'None.')"
passes "(v7) an escaped pipe in the Evidence cell is not a cell boundary"

# ---- each rule failing ----
check approve-blocker "$(body approve "$HEAD_ROWS" '- [blocker] B1 must change before merge')"
fails_with "(f1) an approve with a [blocker]" "approve with a blocker"
check approve-violated "$(body approve $'| D-1 a | violated | x |\n| D-2 c | honored | y |\n| D-3 e | honored | z |' 'None.')"
fails_with "(f2) an approve with a violated row" "approve with a violated or undeterminable row: D-1 violated"
check approve-undet "$(body approve $'| D-1 a | honored | x |\n| D-2 c | honored | y |\n| D-3 e | undeterminable | z |' 'None.')"
fails_with "(f2) an approve with an undeterminable row" "approve with a violated or undeterminable row: D-3 undeterminable"
check approve-render "$(printf 'verdict: approve\nreviewed: %s\nreason: render-unavailable\n\n%s' "$SHA" "$(body approve "$HEAD_ROWS" 'None.' | sed 1,2d)")"
fails_with "(f3) an approve carrying reason: render-unavailable" "approve with reason: render-unavailable"
check nw-notes "$(body needs-work "$HEAD_ROWS" '- [note] N1 nothing required')"
fails_with "(f4) a needs-work with nothing to fix" "needs-work with no blocker"
check deleted "$(body approve $'| D-1 a | honored | x |\n| D-3 e | honored | z |' 'None.')"
fails_with "(f5) a row the build deleted, left unscored" "record row not scored: D-2"
check added "$(body approve $'| D-1 a | honored | x |\n| D-2 c | departed | y |' 'None.')"
fails_with "(f6) a row the build added, left unscored" "record row not scored: D-3"
check unknown-row "$(body approve "$HEAD_ROWS"$'\n| D-9 z | honored | w |' 'None.')"
fails_with "(f7) a row in neither version of the record" "row not in the record: D-9"
# a record row that ledger-lint accepts with other padding (`|  D-2  |`, `|D-4|`) is still owed a score
printf '# record\n\n| ID | Decision | Resolution | Provenance |\n| --- | --- | --- | --- |\n| D-1 | a | b | user-answered |\n|  D-2  | c | d | user-answered |\n|D-4| g | h | user-answered |\n' > "$T/padded-record.md"
HEADREC="$T/padded-record.md" FIRSTREC="$T/padded-record.md" check padded "$(body approve '| D-1 a | honored | x |' 'None.')"
fails_with "(f7b) a padded record row, left unscored" "record row not scored: D-2"
has "record row not scored: D-4" && ok "(f7b) a record row with no cell padding, left unscored, is named too" || bad "(f7b) D-4 not named: $(tr '\n' '|' <<<"$OUT")"
check rs-row "$(body approve "$HEAD_ROWS"$'\n| RS-1 home | honored | w |' 'None.')"
fails_with "(f8) an RS row in the table" "row is not a D-n row: RS-1 home"
check bad-score "$(body approve $'| D-1 a | fine | x |\n| D-2 c | honored | y |\n| D-3 e | honored | z |' 'None.')"
fails_with "(f9) a score outside honored|violated|departed|undeterminable" "score not in the grammar: D-1: fine"
check rows-prose "$(printf 'verdict: approve\nreviewed: %s\n\n## Decision record rows\n\nThe record is unchanged.\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n%s\n\nEvery AC is met.\n\n## Findings\n\nNone.' "$SHA" "$HEAD_ROWS")"
fails_with "(f10) prose around the table in ## Decision record rows (D-1)" "Decision record rows not in the grammar: line 6: The record is unchanged."
has "line 14: Every AC is met." && ok "(f10) the prose after the table is named too" || bad "(f10) after-table prose: $(tr '\n' '|' <<<"$OUT")"
check no-table "$(printf 'verdict: approve\nreviewed: %s\n\n## Decision record rows\n\n## Findings\n\nNone.' "$SHA")"
fails_with "(f11) a rows section with no table" "Decision record rows not in the grammar: no | Row | Score | Evidence | table"
check findings-prose "$(body approve "$HEAD_ROWS" $'No blockers.\n\n**W1 — Warning:** fix the description.')"
fails_with "(f12) findings outside the grammar" "Findings not in the grammar: line 14: No blockers."
check findings-unindented "$(body needs-work "$HEAD_ROWS" $'- [blocker] B1 a\none space is not a continuation')"
fails_with "(f12) a continuation line indented under two spaces" "Findings not in the grammar: line 15: one space is not a continuation"
check findings-wrong-id "$(body needs-work "$HEAD_ROWS" $'- [blocker] N1 a blocker numbered as a note\n- [blocker] B2 real')"
fails_with "(f12) a [blocker] numbered N<n>" "Findings not in the grammar: line 14: - [blocker] N1"
check none-beside "$(body needs-work "$HEAD_ROWS" $'None.\n- [blocker] B1 a')"
fails_with "(f13) None. beside a finding" "Findings not in the grammar: None. is the only line"
check empty-findings "$(body approve "$HEAD_ROWS" '')"
fails_with "(f13) an empty Findings section" "Findings not in the grammar: an empty section holds the single line None."
check rtm "$(body approve "$HEAD_ROWS" 'None.' $'\n## Notes\n\n**Ready to merge?** Yes.')"
fails_with "(f14) 'Ready to merge?' anywhere, Notes included" "Ready to merge? in the body"
check unknown-sec "$(body approve "$HEAD_ROWS" 'None.' $'\n## Process notes\n\nprose')"
fails_with "(f15) a section outside the grammar" "unknown section: ## Process notes"
check order "$(printf 'verdict: approve\nreviewed: %s\n\n## Findings\n\nNone.\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n%s' "$SHA" "$HEAD_ROWS")"
fails_with "(f16) sections out of order" "section out of order: ## Decision record rows"
check repeated "$(body approve "$HEAD_ROWS" 'None.' $'\n## Findings\n\nNone.')"
fails_with "(f16) a section repeated" "section repeated: ## Findings"
check missing "$(printf 'verdict: approve\nreviewed: %s\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n%s' "$SHA" "$HEAD_ROWS")"
fails_with "(f17) no ## Findings" "missing section: ## Findings"
check outside "$(printf 'verdict: approve\nreviewed: %s\nSummary: fine.\n\n%s' "$SHA" "$(body approve "$HEAD_ROWS" 'None.' | sed 1,2d)")"
fails_with "(f18) text before the first section" "text outside a section: line 3: Summary: fine."
check line1 "$(body 'approve with notes' "$HEAD_ROWS" 'None.')"
fails_with "(f19) line 1 not a verdict line" "line 1 is not a verdict line"
check line2 "$(body approve "$HEAD_ROWS" 'None.' | sed "2s/.*/reviewed: ${SHA:0:12}/")"
fails_with "(f19) line 2 names a short sha" "line 2 is not a reviewed line"

# ---- every failed rule is printed, not only the first ----
check many "$(body approve $'| D-1 a | violated | x |' $'- [blocker] B1 a\nprose')"
[ "$RC" -eq 1 ] && [ "$(grep -c . <<<"$OUT")" -ge 5 ] && has "approve with a blocker" && has "approve with a violated or undeterminable row" \
  && has "record row not scored: D-2" && has "record row not scored: D-3" && has "Findings not in the grammar" \
  && ok "(m1) a body breaking five rules names all five" || bad "(m1) rc=$RC out=$(tr '\n' '|' <<<"$OUT")"

# ---- exit 2: nothing evaluated ----
check gone-head "$(body approve "$HEAD_ROWS" 'None.')"
OUT="$(bash "$TOOL" "$T/gone-head.md" "$T/no-such-record.md" "$T/first.md" 2>"$T/e2")"; RC=$?
[ "$RC" -eq 2 ] && [ -z "$OUT" ] && grep -q 'cannot read' "$T/e2" && ok "(x1) a missing record at the head: exit 2, no rule printed" || bad "(x1) rc=$RC out=$OUT"
OUT="$(bash "$TOOL" "$T/gone-head.md" "$T/head.md" "$T/no-such-record.md" 2>/dev/null)"; RC=$?
[ "$RC" -eq 2 ] && ok "(x1) a missing record at the first commit: exit 2" || bad "(x1) first: rc=$RC"
OUT="$(bash "$TOOL" "$T/no-such-body.md" "$T/head.md" "$T/first.md" 2>/dev/null)"; RC=$?
[ "$RC" -eq 2 ] && ok "(x2) a missing body: exit 2" || bad "(x2) rc=$RC"
OUT="$(bash "$TOOL" "$T/gone-head.md" "$T/head.md" 2>/dev/null)"; RC=$?
[ "$RC" -eq 2 ] && ok "(x3) a missing argument is usage: exit 2" || bad "(x3) rc=$RC"

echo "verdict-check-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"

#!/usr/bin/env bash
# verdict-check-selftest.sh — behavioral selftest for tools/verdict-check.sh.
#
# INVARIANTS GUARDED: a real PR's two verdicts as posted are rejected against its record at each
# head and at its first commit (round 1 names "needs-work with no finding", round 2 "Findings not in
# the grammar"); each rule passes and fails; a [note] gates like a [blocker]; a needs-work with any of the three line-3 reasons passes; a row the build
# deleted or added is still owed a score; a folded rows table passes only under a summary that counts it and
# beside a ## Summary, and a bare table still passes; a user-delegated edit of a row parked under a pause-and-ask
# region passes only scored violated; every failed rule is printed, not only the first; a record
# that cannot be read is exit 2. With the verdict file alone, a review-lead verdict in the lane format passes and a
# rows section, a review-lead section of the old report or an approve with a finding fails. In both modes a Summary
# over 8 lines, Notes of 150 words, a note over 4 lines and the none contributions line fail, and each limit passes; later-round
# note lines are not counted in the Notes words. An empty Findings beside resolved lines says `None open. <n> resolved`;
# both counts must equal the resolved lines, which sit in a fold and are not counted in the Notes words. The run.sh wiring is a scenario case in skills/run/run-verdict-selftest.sh.
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
# The indented row is a fan-out snapshot, never one of the record's own.
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

# ---- (ac1) a real PR's verdicts as posted, against its record at each head and at its first commit ----
OUT="$(bash "$TOOL" "$FX/pr983-round1.md" "$FX/record-979-at-7100d01b.md" "$FX/record-979-at-7100d01b.md")"; RC=$?   # 1be8b826's record is byte-identical to 7100d01b's
fails_with "(ac1) round 1 (needs-work on one Warning) is rejected" "needs-work with no finding"
has "Decision record rows not in the grammar" && has "unknown section: ## review-lead" && has "Ready to merge? in the body" \
  && ok "(ac1) round 1 also names its prose in the rows section, its extra sections and 'Ready to merge?'" || bad "(ac1) round 1: $(tr '\n' '|' <<<"$OUT")"
OUT="$(bash "$TOOL" "$FX/pr983-round2.md" "$FX/record-979-at-c9ff84e4.md" "$FX/record-979-at-7100d01b.md")"; RC=$?
fails_with "(ac1) round 2 (approve beside a must-fix Warning) is rejected" "Findings not in the grammar"
! has "record row not scored" && ! has "row not in the record" && ok "(ac1) round 2 scored D-8, the row its build added, and every other row" || bad "(ac1) round 2 rows: $(tr '\n' '|' <<<"$OUT")"

# ---- each rule passing ----
check approve "$(body approve "$HEAD_ROWS" 'None.')"
passes "(v1) a consistent approve passes: every row of both versions scored, no finding"
check nw-blocker "$(body needs-work "$HEAD_ROWS" $'- [blocker] B1 fix this before merge\n- [note] N1 and fix this too')"
passes "(v2) a needs-work with a [blocker] passes"
check nw-notes-only "$(body needs-work "$HEAD_ROWS" $'- [note] N1 src/a.ts:3 — the helper repeats the repo\x27s unit constant\n  continued on an indented line\n  Fix: use the constant\n\n- [note] N2 src/b.ts:9 — a second convention break')"
passes "(v2) a needs-work whose only findings are notes passes: a note gates, continuation lines indented"
check nw-violated "$(body needs-work $'| D-1 a | violated | x |\n| D-2 c | honored | y |\n| D-3 e | honored | z |' 'None.')"
passes "(v3) a needs-work with a violated row and no finding passes"
check nw-undet "$(body needs-work $'| D-1 a | undeterminable | x |\n| D-2 c | honored | y |\n| D-3 e | honored | z |' 'None.')"
passes "(v3) a needs-work with an undeterminable row passes"
check render "$(printf 'verdict: needs-work\nreviewed: %s\nreason: render-unavailable\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n\n## Findings\n\nNone.' "$SHA")"
passes "(v4) a render-unavailable needs-work passes with no blocker and no row scored"
for r in ticket-unreadable seat-unavailable; do
  check "reason-$r" "$(printf 'verdict: needs-work\nreviewed: %s\nreason: %s\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n\n## Findings\n\nNone.' "$SHA" "$r")"
  passes "(v4) a $r needs-work passes with no blocker and no row scored"
  check "approve-$r" "$(printf 'verdict: approve\nreviewed: %s\nreason: %s\n\n%s' "$SHA" "$r" "$(body approve "$HEAD_ROWS" 'None.' | sed 1,2d)")"
  fails_with "(f3) an approve carrying reason: $r" "approve with reason: $r"
done
check reason-other "$(printf 'verdict: needs-work\nreviewed: %s\nreason: reviewer-busy\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n\n## Findings\n\nNone.' "$SHA")"
fails_with "(f3) a line 3 reason outside the grammar is text outside a section" "text outside a section: line 3: reason: reviewer-busy"
BY='reviewed-by: second-shift run 20261106T182105Z-40385 (v17.13.0)'
check by-line "$(printf 'verdict: approve\nreviewed: %s\n%s\n%s' "$SHA" "$BY" "$(body approve "$HEAD_ROWS" 'None.' | sed 1,2d)")"
passes "(by1) a reviewed-by line right after the reviewed line passes"
check by-reason "$(printf 'verdict: needs-work\nreviewed: %s\nreason: ticket-unreadable\n%s\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n\n## Findings\n\nNone.' "$SHA" "$BY")"
passes "(by2) a reviewed-by line after a reason line passes"
check by-first "$(printf 'verdict: needs-work\nreviewed: %s\n%s\nreason: ticket-unreadable\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n\n## Findings\n\nNone.' "$SHA" "$BY")"
fails_with "(by3) a reason line after the reviewed-by line is text outside a section" "text outside a section: line 4: reason: ticket-unreadable"
check new-form "$(body needs-work "$HEAD_ROWS" $'- [blocker] B1 src/a.ts:3 — the retry loops forever\n  Scenario: a 409 from the store → the worker never exits\n  Fix: stop after three tries\n- [blocker] B2 [design-faithful-reviewer] src/b.tsx:9 — a raw hex color\n  Scenario: the dark theme → the text is unreadable\n  Fix: use the text token')"
passes "(v2) a needs-work in the session's finding form, a dispatched reviewer's finding included, passes"
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
check approve-note "$(body approve "$HEAD_ROWS" $'- [note] N1 src/a.ts:3 — the helper repeats the repo\x27s unit constant\n  Fix: use the constant\n- [note] N2 src/b.ts:9 — a second one')"
fails_with "(f1) an approve with a [note]" "approve with a note: 2 [note] line(s)"
check nw-none "$(body needs-work "$HEAD_ROWS" 'None.')"
fails_with "(f4) a needs-work with nothing to fix" "needs-work with no finding"
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
# ---- the optional ## Summary: first, line 1 matches the verdict, names every row not honored, no table ----
summ() { printf 'verdict: %s\nreviewed: %s\n\n## Summary\n\n%s\n\n%s' "$1" "$SHA" "$2" "$(body "$1" "$3" "$4" | sed 1,2d)"; }
check s-ok "$(summ approve $'Mergeable as it is.\nD-2 departed: the build deleted it.\nNothing to do.' "$HEAD_ROWS" 'None.')"
passes "(s1) an approve whose Summary matches and names the departed row"
check s-miss "$(summ approve $'Mergeable as it is.\nNothing to do.' "$HEAD_ROWS" 'None.')"
fails_with "(s2) a Summary that hides a departed row" "Summary does not name a row that is not honored: D-2"
check s-line1 "$(summ needs-work $'Mergeable as it is.\nD-2 departed.\nFix B1.' "$HEAD_ROWS" '- [blocker] B1 a thing to fix')"
fails_with "(s3) a needs-work whose Summary says mergeable" "Summary line 1 does not match the verdict: want Not mergeable yet."
check s-table "$(summ approve $'Mergeable as it is.\nD-2 departed.\n| a | b |' "$HEAD_ROWS" 'None.')"
fails_with "(s4) a table in the Summary" "Summary not in the grammar"
check s-order "$(body approve "$HEAD_ROWS" 'None.' $'\n## Summary\n\nMergeable as it is.\nD-2 departed.')"
fails_with "(s5) a Summary after the findings" "section out of order: ## Summary"
# ---- the folded rows table: a one-line count summary, a blank line, the table, then </details> ----
folded() { # folded <verdict> <summary-line> <rows> <findings> [summary-section]
  printf 'verdict: %s\nreviewed: %s\n\n%s## Decision record rows\n\n%s\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n%s\n</details>\n\n## Findings\n\n%s\n' \
    "$1" "$SHA" "${5-$'## Summary\n\nMergeable as it is.\nD-2 departed: the build deleted it.\nNothing to do.\n\n'}" "$2" "$3" "$4"
}
FOLD_OK='<details><summary>3 rows: 2 honored, 1 departed</summary>'
check fold-ok "$(folded approve "$FOLD_OK" "$HEAD_ROWS" 'None.')"
passes "(fo1) a folded rows table under a summary that counts it passes"
check fold-blank-end "$(folded approve "$FOLD_OK" "$HEAD_ROWS" 'None.' | awk '{ print } $0 == "| D-3 e | honored | z |" { print "" }')"
passes "(fo1) a blank line between the table and </details> passes"
check fold-nw "$(folded needs-work '<details><summary>3 rows: 1 honored, 1 departed, 1 violated</summary>' $'| D-1 a | violated | x |\n| D-2 c | departed | y |\n| D-3 e | honored | z |' '- [blocker] B1 a thing to fix' $'## Summary\n\nNot mergeable yet.\nD-1 violated. D-2 departed.\nFix B1.\n\n')"
passes "(fo1) a folded needs-work names its violated and departed rows in the Summary and passes"
check fold-reason "$(printf 'verdict: needs-work\nreviewed: %s\nreason: render-unavailable\n\n## Summary\n\nNot mergeable yet.\nRender the screens.\n\n## Decision record rows\n\n<details><summary>0 rows</summary>\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n</details>\n\n## Findings\n\nNone.' "$SHA")"
passes "(fo1) under a reason line, an empty folded table counts 0 rows"
check fold-unscored "$(folded approve '<details><summary>2 rows: 1 honored, 1 departed</summary>' $'| D-1 a | honored | x |\n| D-2 c | departed | y |' 'None.')"
fails_with "(fo2) a row left unscored inside the fold still fails" "record row not scored: D-3"
check fold-badscore "$(folded approve '<details><summary>3 rows: 2 honored, 1 departed</summary>' $'| D-1 a | fine | x |\n| D-2 c | departed | y |\n| D-3 e | honored | z |' 'None.')"
fails_with "(fo2) an unknown score inside the fold still fails" "score not in the grammar: D-1: fine"
check fold-violated "$(folded approve '<details><summary>3 rows: 1 honored, 1 departed, 1 violated</summary>' $'| D-1 a | violated | x |\n| D-2 c | departed | y |\n| D-3 e | honored | z |' 'None.' $'## Summary\n\nMergeable as it is.\nD-1 violated. D-2 departed.\nNothing to do.\n\n')"
fails_with "(fo2) an approve with a violated row inside the fold still fails" "approve with a violated or undeterminable row: D-1 violated"
check fold-hidden "$(folded approve "$FOLD_OK" "$HEAD_ROWS" 'None.' $'## Summary\n\nMergeable as it is.\nNothing to do.\n\n')"
fails_with "(fo2) a Summary that hides a departed row under a fold still fails" "Summary does not name a row that is not honored: D-2"
check fold-count "$(folded approve '<details><summary>3 rows: 3 honored</summary>' "$HEAD_ROWS" 'None.')"
fails_with "(fo3) a summary whose score counts differ from the table" "rows summary counts differ from the table: the summary says 3 honored, the table has 2"
has "the summary says 0 departed, the table has 1" && ok "(fo3) the missing departed count is named too" || bad "(fo3) departed count: $(tr '\n' '|' <<<"$OUT")"
check fold-total "$(folded approve '<details><summary>4 rows: 2 honored, 1 departed</summary>' "$HEAD_ROWS" 'None.')"
fails_with "(fo3) a summary whose row total differs from the table" "rows summary counts differ from the table: the summary says 4 rows, the table has 3"
check fold-nosummary "$(folded approve '<details><summary>3 rows: 2 honored, 1 departed</summary>' "$HEAD_ROWS" 'None.' '')"
fails_with "(fo4) a folded table with no ## Summary" "folded rows table with no ## Summary"
check fold-open "$(folded approve '<details open><summary>3 rows: 2 honored, 1 departed</summary>' "$HEAD_ROWS" 'None.')"
fails_with "(fo5) a fold that renders open" "Decision record rows not in the grammar: line 12: <details open>"
check fold-order "$(folded approve '<details><summary>3 rows: 1 departed, 2 honored</summary>' "$HEAD_ROWS" 'None.')"
fails_with "(fo5) scores out of order in the summary" "the summary lists honored, departed, violated, undeterminable in that order"
check fold-zero "$(folded approve '<details><summary>3 rows: 2 honored, 1 departed, 0 violated</summary>' "$HEAD_ROWS" 'None.')"
fails_with "(fo5) a zero count in the summary" "the summary leaves out a zero count"
check fold-word "$(folded approve '<details><summary>3 decisions: 2 honored, 1 departed</summary>' "$HEAD_ROWS" 'None.')"
fails_with "(fo5) a summary that does not say rows" "the summary is <N> rows: <k> <score>"
check fold-noblank "$(folded approve "$FOLD_OK" "$HEAD_ROWS" 'None.' | awk 'prev ~ /^<details>/ && $0 == "" { prev = $0; next } { print; prev = $0 }')"
fails_with "(fo5) no blank line after the summary" "a blank line follows the rows summary"
check fold-noclose "$(folded approve "$FOLD_OK" "$HEAD_ROWS" 'None.' | grep -vx '</details>')"
fails_with "(fo5) a fold with no </details>" "the rows fold has no </details> line after the table"
check fold-after "$(folded approve "$FOLD_OK" "$HEAD_ROWS" 'None.' | awk '{ print } $0 == "</details>" { print "trailing prose" }')"
fails_with "(fo5) prose after </details>" "Decision record rows not in the grammar: line 20: trailing prose"
check bare-summary "$(summ approve $'Mergeable as it is.\nD-2 departed: the build deleted it.\nNothing to do.' "$HEAD_ROWS" 'None.')"
passes "(fo6) a bare table beside a Summary still passes"
check bare-nosummary "$(body approve "$HEAD_ROWS" 'None.')"
passes "(fo6) a bare table with no Summary still passes"

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
check dup-id "$(body needs-work "$HEAD_ROWS" $'- [blocker] B1 src/a.ts:3 — one\n- [blocker] B1 src/b.ts:9 — two\n- [note] N1 x\n- [note] N2 y')"
fails_with "(id1) two findings sharing an id" "finding id repeated: B1"
! has "finding id repeated: N" && ok "(id1) distinct note ids are not flagged" || bad "(id1) out=$(tr '\n' '|' <<<"$OUT")"
check dev-block "$(body approve "$HEAD_ROWS" 'None.' $'\n## Notes\n\n<details><summary>dev: lane vs plain</summary>\n\n- Lane-only: B7 src/a.ts:3\n- [blocker] B1 a finding-shaped line inside the block\n\n<!-- plain-vs-lane: {"flipped":false} -->\n\n</details>')"
passes "(dv1) a folded dev block under ## Notes is prose: its finding-shaped lines are not graded"
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

# ---- a row under a pause-and-ask region is the requester's alone ----
ask_record() { # ask_record <D-2 provenance> <D-3 provenance>: D-2 cites the pause-and-ask OR-1, D-3 the reversible OR-2
  printf '# record\n\n| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | a | b | user-answered | intent |\n| D-2 | order (A \\| B) | parked under OR-1 | %s | open |\n| D-3 | window | parked under OR-2 | %s | open |\n\n## Open Regions\n\n| ID | Region | Disposition |\n| --- | --- | --- |\n| OR-1 | ordering | pause-and-ask |\n| OR-2 | retention | reversible-default-and-flag |\n' "$1" "$2"
}
ask_record deferred deferred > "$T/ask-first.md"
ask_record user-delegated user-delegated > "$T/ask-delegated.md"
ask_record user-answered user-delegated > "$T/ask-answered.md"
FIRSTREC="$T/ask-first.md" HEADREC="$T/ask-delegated.md" check ask-departed "$(body needs-work $'| D-1 | honored | x |\n| D-2 | departed | Decided by the build (user-delegated). |\n| D-3 | departed | y |' '- [blocker] B1 a thing')"
fails_with "(pa1) a user-delegated edit under a pause-and-ask region scored departed is rejected" "user-delegated row under a pause-and-ask region not scored violated: D-2 departed"
! has "D-3" && ok "(pa1) the same edit under a reversible-default region is not named" || bad "(pa1) out=$(tr '\n' '|' <<<"$OUT")"
FIRSTREC="$T/ask-first.md" HEADREC="$T/ask-delegated.md" check ask-violated "$(body needs-work $'| D-1 | honored | x |\n| D-2 | violated | the build decided it |\n| D-3 | departed | y |' '- [blocker] B1 a thing')"
passes "(pa2) the same edit scored violated passes"
FIRSTREC="$T/ask-first.md" HEADREC="$T/ask-answered.md" check ask-answered "$(body needs-work $'| D-1 | honored | x |\n| D-2 | departed | Decided by the requester (user-answered). |\n| D-3 | departed | y |' '- [blocker] B1 a thing')"
passes "(pa3) the requester's own answer under the region is a departure, not a violation"

# ---- the no-record mode: review-lead's report, the verdict file alone ----
BYL='reviewed-by: second-shift review-lead (v9)'
lead() { printf 'verdict: %s\nreviewed: %s\n%s\n\n## Summary\n\n%s\n\n## Findings\n\n%s\n%s' "$1" "$SHA" "$BYL" "$2" "$3" "${4:-}"; }
check1() { printf '%s\n' "$2" > "$T/$1.md"; OUT="$(bash "$TOOL" "$T/$1.md" 2>"$T/$1.err")"; RC=$?; }
check1 nr-approve "$(lead approve $'Mergeable as it is.\nNot reviewed: a11y + design-fidelity (no changed path matched the web-component globs).\nNothing to do.' 'None.')"
passes "(nr1) a review-lead approve in the lane format, with a Not reviewed line, passes with no record"
check1 nr-nw "$(lead needs-work $'Not mergeable yet.\nFix B1 and N1.' $'- [blocker] B1 [Security] src/a.ts:3 — the token leaks into the log\n  Scenario: a failed login → the token is in the log\n  Fix: redact it\n- [note] N1 [blind] src/b.ts:9 — the helper repeats a constant\n  Fix: use the constant' $'\n## Notes\n\nlane vs blind: 0 agreed, 0 rated differently, 1 lane alone, 1 blind alone; blind flipped the verdict\n<!-- plain-vs-lane: {"v":3} -->')"
passes "(nr1) a review-lead needs-work with a blocker, a [blind] note and the join's lines passes"
check1 nr-seat "$(printf 'verdict: needs-work\nreviewed: %s\nreason: seat-unavailable\n%s\n\n## Summary\n\nNot mergeable yet.\nNot reviewed: security-reviewer (dark after a re-dispatch).\n\n## Findings\n\nNone.' "$SHA" "$BYL")"
passes "(nr1) a review-lead needs-work for a dark gate reviewer passes with reason: seat-unavailable and no finding"
check1 nr-rows "$(lead approve $'Mergeable as it is.\nNothing to do.' 'None.' | ROWS="$HEAD_ROWS" awk '/^## Findings$/ { print "## Decision record rows"; print ""; print "| Row | Score | Evidence |"; print "| --- | --- | --- |"; print ENVIRON["ROWS"]; print "" } { print }')"
fails_with "(nr2) a no-record verdict with ## Decision record rows" "Decision record rows in a verdict with no record"
! has "record row not scored" && ! has "row not in the record" && ok "(nr2) its table rows are not graded against a record" || bad "(nr2) out=$(tr '\n' '|' <<<"$OUT")"
check1 nr-old "$(printf 'verdict: approve\nreviewed: %s\n%s\n\n## Summary\n\nMergeable as it is.\n\n## Strengths\n\n- tidy\n\n## Findings\n\nNone.\n\n## Suggestions (consider)\n\n- [Complexity] src/a.ts:21 — could be simpler\n\n## Verdicts\n\n| Reviewer | Verdict |\n\n## Notes\n\n**Ready to merge?** Yes' "$SHA" "$BYL")"
fails_with "(nr3) a Strengths section" "unknown section: ## Strengths"
has "unknown section: ## Suggestions (consider)" && has "unknown section: ## Verdicts" && has "Ready to merge? in the body" \
  && ok "(nr3) a Suggestions section, a Verdicts section and a Ready to merge? line are each named" || bad "(nr3) out=$(tr '\n' '|' <<<"$OUT")"
check1 nr-approve-note "$(lead approve $'Mergeable as it is.\nNothing to do.' $'- [note] N1 src/b.ts:9 — the helper repeats a constant\n  Fix: use the constant')"
fails_with "(nr4) a no-record approve with a [note]" "approve with a note: 1 [note] line(s)"
check1 nr-approve-blocker "$(lead approve $'Mergeable as it is.\nNothing to do.' $'- [blocker] B1 [Scope completeness] src/a.ts:3 — a plan requirement is missing\n  Fix: add it')"
fails_with "(nr4) a no-record approve with a [blocker]" "approve with a blocker: 1 [blocker] line(s)"
check1 nr-no-by "$(lead approve $'Mergeable as it is.\nNothing to do.' 'None.' | sed 3d)"
fails_with "(nr5) a no-record verdict with no reviewed-by line" "missing reviewed-by line"
check1 nr-no-summary "$(printf 'verdict: approve\nreviewed: %s\n%s\n\n## Findings\n\nNone.' "$SHA" "$BYL")"
fails_with "(nr5) a no-record verdict with no ## Summary" "missing section: ## Summary"
OUT="$(bash "$TOOL" "$T/no-such-report.md" 2>/dev/null)"; RC=$?
[ "$RC" -eq 2 ] && ok "(nr6) a missing verdict file in the no-record mode: exit 2" || bad "(nr6) rc=$RC"

# ---- the length limits and the none contributions line, in both modes ----
lines_of() { seq "$1" | sed 's/^/Line /; s/$/./'; }
words() { printf 'word%.0s ' $(seq "$1"); }
SUM8="$(printf 'Mergeable as it is.\nD-2 departed: the build deleted it.\n%s' "$(lines_of 6)")"
SUM9="$SUM8"$'\nLine 7.'
check s-8 "$(summ approve "$SUM8" "$HEAD_ROWS" 'None.')"
passes "(l1) a Summary of eight non-blank lines passes"
check s-9 "$(summ approve "$SUM9" "$HEAD_ROWS" 'None.')"
fails_with "(l1) a Summary of nine non-blank lines" "Summary longer than eight lines: 9 non-blank lines"
check1 nr-s-8 "$(lead approve "$(printf 'Mergeable as it is.\n%s' "$(lines_of 7)")" 'None.')"
passes "(l1) a no-record Summary of eight lines passes"
check1 nr-s-9 "$(lead approve "$(printf 'Mergeable as it is.\n%s' "$(lines_of 8)")" 'None.')"
fails_with "(l1) a no-record Summary of nine lines" "Summary longer than eight lines: 9 non-blank lines"
JOIN_LINES=$'lane vs blind: 1 agreed, 0 rated differently, 0 lane alone, 0 blind alone\n<!-- plain-vs-lane: {"v":3,"findings":[]} -->'
KB="Knowledge-base contributions:"$'\n'"- kb/auth.md — $(words 40)(change gap)"
N149="$(printf '### Process\n\n%s' "$(words 147)")"
check notes-149 "$(body approve "$HEAD_ROWS" 'None.' "$(printf '\n## Notes\n\n%s\n\nJoined review: the blind review returned no verdict, so this verdict is the lane review alone.\n%s\n\n%s' "$N149" "$KB" "$JOIN_LINES")")"
passes "(l2) a Notes section of 149 words passes; the knowledge-base block and the join lines are not counted"
check notes-150 "$(body approve "$HEAD_ROWS" 'None.' "$(printf '\n## Notes\n\n%s word\n\n%s' "$N149" "$JOIN_LINES")")"
fails_with "(l2) a Notes section of 150 words" "Notes of 150 words or more: 150 words"
check1 nr-notes-149 "$(lead approve $'Mergeable as it is.\nNothing to do.' 'None.' "$(printf '\n## Notes\n\n%s\n\n%s' "$N149" "$KB")")"
passes "(l2) a no-record Notes section of 149 words passes"
check1 nr-notes-150 "$(lead approve $'Mergeable as it is.\nNothing to do.' 'None.' "$(printf '\n## Notes\n\n%s word' "$N149")")"
fails_with "(l2) a no-record Notes section of 150 words" "Notes of 150 words or more: 150 words"
LATER="$(printf -- '- later-round note: src/old.ts:%s — %s\n' 12 "$(words 30)" 40 "$(words 30)")"
LSUM=$'Mergeable as it is.\nD-2 departed: the build deleted it.\nRead the 2 later-round notes in ## Notes.'
check notes-later "$(summ approve "$LSUM" "$HEAD_ROWS" 'None.')"$'\n\n## Notes\n\n'"$N149"$'\n\n'"$LATER"
passes "(l2) an approve whose Notes pass 150 words only through later-round notes passes: those lines are not counted"
check notes-later-prose "$(summ approve "$LSUM" "$HEAD_ROWS" 'None.')"$'\n\n## Notes\n\n'"$N149"$'\n\n'"${LATER//- later-round note: /}"
fails_with "(l2) the same notes written as prose are counted" "Notes of 150 words or more"

# ---- a later review lists the findings it saw resolved, in a fold in ## Notes ----
RL1="- resolved: src/a.ts:3 — the retry loops forever — fixed"
RL2="- resolved: untraced test-expectation change — a snapshot lost a line — rebuttal accepted: the ticket asks for it"
rfold() { printf '<details><summary>%s resolved</summary>\n\n%s\n</details>' "$1" "$2"; }
RES2="$(rfold 2 "$RL1"$'\n'"$RL2")"
OPEN2='None open. 2 resolved, listed in ## Notes.'
check rs-ok "$(body approve "$HEAD_ROWS" "$OPEN2" $'\n## Notes\n\nA process note.\n\n'"$RES2"$'\n\n'"$KB")"
passes "(rs1) an approve whose empty Findings says None open. 2 resolved, with two resolved lines in the fold, passes"
check rs-nw "$(body needs-work "$HEAD_ROWS" '- [blocker] B1 src/b.ts:9 — a new defect' $'\n## Notes\n\n'"$RES2")"
passes "(rs1) a needs-work with a finding and a resolved fold passes"
check rs-open3 "$(body approve "$HEAD_ROWS" 'None open. 3 resolved, listed in ## Notes.' $'\n## Notes\n\n'"$RES2")"
fails_with "(rs2) a None open. line that counts 3 beside two resolved lines" "resolved count differs from the resolved lines: ## Findings says 3, ## Notes has 2"
check rs-fold3 "$(body approve "$HEAD_ROWS" "$OPEN2" $'\n## Notes\n\n'"$(rfold 3 "$RL1"$'\n'"$RL2")")"
fails_with "(rs2) a fold summary that counts 3 beside two resolved lines" "resolved count differs from the resolved lines: the fold summary says 3, ## Notes has 2"
check rs-bare "$(body approve "$HEAD_ROWS" 'None.' $'\n## Notes\n\n'"$RES2")"
fails_with "(rs3) a bare None. beside resolved lines" "None. beside resolved lines"
check rs-nofold "$(body approve "$HEAD_ROWS" "$OPEN2" $'\n## Notes\n\n'"$RL1"$'\n'"$RL2")"
fails_with "(rs4) resolved lines with no fold" "resolved line outside the resolved fold: 2 line(s)"
check rs-empty "$(body approve "$HEAD_ROWS" 'None.' $'\n## Notes\n\n<details><summary>0 resolved</summary>\n\n</details>')"
fails_with "(rs5) a fold with no resolved line" "resolved fold with no resolved line"
check rs-zero "$(body approve "$HEAD_ROWS" 'None open. 0 resolved, listed in ## Notes.')"
fails_with "(rs6) None open. 0 resolved" "None open. line counts no resolved line"
check rs-first "$(body approve "$HEAD_ROWS" 'None.' $'\n## Notes\n\nA process note.')"
passes "(rs7) a first-review approve with None. in an empty Findings and no resolved fold passes"
RLONG="$(for i in 1 2; do printf -- '- resolved: src/r.ts:%s — %s— fixed\n' "$i" "$(words 30)"; done)"
check rs-words "$(body approve "$HEAD_ROWS" "$OPEN2" "$(printf '\n## Notes\n\n%s\n\n%s' "$N149" "$(rfold 2 "$RLONG")")")"
passes "(rs8) an approve whose Notes pass 150 words only through the resolved lines and the two fold lines passes"
check rs-words-prose "$(body approve "$HEAD_ROWS" 'None.' "$(printf '\n## Notes\n\n%s\n\n%s' "$N149" "${RLONG//- resolved: /}")")"
fails_with "(rs8) the same lines written as prose are counted" "Notes of 150 words or more"
NOTE4=$'- [note] N1 src/a.ts:3 — the helper repeats a constant\n  Scenario: the constant changes → the helper keeps the old value\n  The repo keeps it in src/units.ts:1.\n  Fix: use the constant'
NOTE5="$NOTE4"$'\n  One line too many.'
BLOCKER6=$'- [blocker] B1 src/w.ts:40 — the retry loops forever\n  Scenario: a 409 → no exit\n  a\n  b\n  c\n  Fix: stop after three tries'
check note-4 "$(body needs-work "$HEAD_ROWS" "$BLOCKER6"$'\n'"$NOTE4"$'\n\n- [note] N2 src/b.ts:9 — a second one\n  Fix: fix it')"
passes "(l3) a note of four lines passes, and a blocker has no line limit"
check note-5 "$(body needs-work "$HEAD_ROWS" "$NOTE5"$'\n- [note] N2 src/b.ts:9 — a second one')"
fails_with "(l3) a note of five lines" "note longer than four lines: N1 has 5 lines"
! has "N2" && ok "(l3) the short note after it is not named" || bad "(l3) out=$(tr '\n' '|' <<<"$OUT")"
check1 nr-note-4 "$(lead needs-work $'Not mergeable yet.\nFix N1.' "$NOTE4")"
passes "(l3) a no-record note of four lines passes"
check1 nr-note-5 "$(lead needs-work $'Not mergeable yet.\nFix N1.' "$NOTE5")"
fails_with "(l3) a no-record note of five lines, the last in the verdict" "note longer than four lines: N1 has 5 lines"
check kb-none "$(body approve "$HEAD_ROWS" 'None.' $'\n## Notes\n\nKnowledge-base contributions: none')"
fails_with "(kb1) the line Knowledge-base contributions: none" "Knowledge-base contributions: none in the body"
check1 nr-kb-none "$(lead approve $'Mergeable as it is.\nNothing to do.' 'None.' $'\n## Notes\n\nKnowledge-base contributions: none')"
fails_with "(kb1) the none line in a no-record verdict" "Knowledge-base contributions: none in the body"
check kb-some "$(body approve "$HEAD_ROWS" 'None.' $'\n## Notes\n\n'"$KB")"
passes "(kb2) a contributions block with a proposal passes"

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

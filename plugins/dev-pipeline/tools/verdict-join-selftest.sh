#!/usr/bin/env bash
# verdict-join-selftest.sh — behavioral selftest for tools/verdict-join.sh --format report, the join review-lead's
# report goes through. The lane-verdict format is driven through run.sh in skills/run/run-joined-selftest.sh.
#
# INVARIANTS GUARDED: a plain blocker within 3 lines of a Critical bullet tags it [lane+blind]; any other is added
# under Critical as [blind] and flips Ready to merge from With fixes or Yes to No, but never touches an existing No;
# plain's notes stay out of the report; a report with no Critical section gets one; with no plain draft the report
# stands and its Notes say why; every report ends with the folded dev block: a list pairing every finding of both
# reviews one to one by site, disagreements first, grouped under a bold outcome line, one line per pair leading with its site, plain's draft as written, and a machine line whose matrix sums.
#
# Operator-safe: no network. Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/verdict-join.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/verdict-join-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT

printf '%s\n' '## Review Summary' 'Fine.' '' '## Strengths' '- tidy' '' '## Critical (must fix before merge)' \
  '- [Security] src/a.ts:10 (confidence: 90) — injection' '' '## Warnings (should fix)' \
  '- [Performance] src/b.ts:5 (confidence: 85) — slow' '' '## Verdicts' '| Reviewer | Verdict |' '' \
  '**Ready to merge?** With fixes' '' '**Reasoning:** ok' > "$T/lead.md"
printf '%s\n' '## Review Summary' 'ok' '' '## Strengths' '- x' '' '## Warnings (should fix)' 'None' '' \
  '**Ready to merge?** Yes' > "$T/lead-clean.md"
sed 's/^\*\*Ready to merge?\*\* With fixes$/**Ready to merge?** No/' "$T/lead.md" > "$T/lead-no.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/a.ts:12 — the same injection' '  Scenario: x → y' \
  '- [blocker] B2 src/c.ts:3 — off by one' '  Scenario: n = 0 → crash' '- [note] N1 src/d.ts:1 — style' > "$T/plain.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/a.ts:11 — the same injection' > "$T/plain-agrees.md"

OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain.md" --format report --lane-cost 1.2 --plain-cost 0.3 --lane-wall 100 --plain-wall 40)"; RC=$?
CRIT="$(printf '%s\n' "$OUT" | awk '/^## Critical/ { on = 1; next } /^## / { on = 0 } on')"
[ "$RC" -eq 0 ] && printf '%s\n' "$CRIT" | grep -qxF -- '- [lane+blind] [Security] src/a.ts:10 (confidence: 90) — injection' \
  && ok "(r1) a plain blocker 2 lines from a Critical bullet merges into it as [lane+blind]" || bad "(r1) rc=$RC: $CRIT"
printf '%s\n' "$CRIT" | grep -qxF -- '- [blind] src/c.ts:3 — off by one' && printf '%s\n' "$CRIT" | grep -qxF '  Scenario: n = 0 → crash' \
  && [ "$(printf '%s\n' "$CRIT" | grep -c '^- ')" -eq 2 ] \
  && ok "(r2) a plain-only blocker is added under Critical as [blind], with its continuation" || bad "(r2) $CRIT"
printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** No' && ! printf '%s\n' "$OUT" | grep -q 'With fixes$' \
  && ok "(r3) a plain-only blocker flips Ready to merge from With fixes to No" || bad "(r3) $(printf '%s\n' "$OUT" | grep 'Ready')"
pairs() { printf '%s\n' "$1" | grep -E '^(\*\*[a-z][^*]*\*\* \([0-9]+\)|- `|- \(no site\))'; }   # the dev block's list: a bold outcome header per group, then one `- site — findings` line per pair
listed() { local p; p="$(pairs "$1")"; shift; [[ "$p"$'\n' == *"$(printf '%s\n' "$@")"* ]]; }
ABOVE="$(printf '%s\n' "$OUT" | sed '/^<details><summary>dev: lane vs blind/,$d')"; DEV="$(printf '%s\n' "$OUT" | sed -n '/^<details><summary>dev: lane vs blind/,$p')"
! grep -q 'src/d.ts' <<<"$ABOVE" && listed "$DEV" '**blind only: note** (1)' '- `src/d.ts:1` — N1: style' \
  && ok "(r4) plain's note stays out of the report and is compared in the dev block" || bad "(r4) $DEV"
JSON="$(printf '%s\n' "$OUT" | sed -n 's/^<!-- plain-vs-lane: \(.*\) -->$/\1/p')"
INV='.lane_blockers == .m_b_b + .m_b_n + .m_b_0 and .lane_notes == .m_n_b + .m_n_n + .m_n_0 and .lane_dismissed == .m_d_b + .m_d_n + .m_d_0
  and .plain_blockers == .m_b_b + .plain_merged + .m_n_b + .m_d_b + .m_0_b and .plain_notes_dropped == .m_b_n + .m_n_n + .m_d_n + .m_0_n
  and .agreed == .m_b_b and .lane_only == .m_b_n + .m_b_0 and .plain_only == .m_n_b + .m_d_b + .m_0_b'
PAIRS="$(printf '%s\n' '**blind only: blocker** (1)' '- `src/c.ts:3` — B2: off by one _(added as [blind])_' \
  '**agreed: blocker** (1)' '- `src/a.ts:10` (blind :12) — lane Critical [Security]: injection · blind B1: the same injection' \
  '**lane only: note** (1)' '- `src/b.ts:5` — Warning [Performance]: slow' '**blind only: note** (1)' '- `src/d.ts:1` — N1: style')"
[ "$(jq -c '[.lane_blockers,.plain_blockers,.agreed,.lane_only,.plain_only,.plain_notes_dropped,.flipped,.plain_returned,.lane_cost_usd,.plain_wall_s,.v,.format,.lane_verdict,.plain_verdict]' <<<"$JSON" 2>/dev/null)" = '[1,2,1,0,1,1,true,true,1.2,40,2,"report","with-fixes","needs-work"]' ] \
  && jq -e "$INV" <<<"$JSON" >/dev/null \
  && grep -qxF '<details><summary>dev: lane vs blind — 1 agreed, 0 rated differently, 1 lane alone, 2 blind alone; blind flipped the verdict</summary>' <<<"$DEV" \
  && [ "$(pairs "$DEV")" = "$PAIRS" ] \
  && grep -qxF -- '- Ready to merge: lane With fixes · blind needs-work · joined No (blind flipped it).' <<<"$DEV" \
  && grep -qxF -- "- Lane session: \$1.20, 100 s. Blind session: \$0.30, 40 s, returned." <<<"$DEV" \
  && grep -qxF '    - [note] N1 src/d.ts:1 — style' <<<"$DEV" \
  && ok "(r5) the dev block pairs every finding, disagreements first, quotes plain's draft, and its matrix sums" || bad "(r5) json=$JSON"

OUT="$(bash "$TOOL" "$T/lead-no.md" "$T/plain.md" --format report)"
printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** No' && [ "$(jq -r .flipped <<<"$(printf '%s\n' "$OUT" | sed -n 's/^<!-- plain-vs-lane: \(.*\) -->$/\1/p')")" = false ] \
  && ok "(r6) a report already at No is not counted as flipped" || bad "(r6) $OUT"

OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-agrees.md" --format report)"
printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** With fixes' && ! printf '%s\n' "$OUT" | grep -q '^- \[blind\]' \
  && ok "(r7) a plain blocker that agrees adds nothing and leaves Ready to merge as it was" || bad "(r7) $OUT"

OUT="$(bash "$TOOL" "$T/lead-clean.md" "$T/plain.md" --format report)"
printf '%s\n' "$OUT" | awk '/^## Critical/ { c = NR } /^## Warnings/ { w = NR } END { exit !(c && c < w) }' \
  && printf '%s\n' "$OUT" | grep -qxF -- '- [blind] src/a.ts:12 — the same injection' && printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** No' \
  && ok "(r8) a report with no Critical section gets one before Warnings, and Yes becomes No" || bad "(r8) $OUT"

OUT="$(bash "$TOOL" "$T/lead.md" '' --format report --why 'the blind review ran past 3600s')"
printf '%s\n' "$OUT" | grep -qxF 'Joined review: the blind review ran past 3600s, so this report is review-lead alone.' \
  && printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** With fixes' && printf '%s\n' "$OUT" | grep -qF '"plain_returned":false' \
  && ok "(r9) with no plain draft the report stands and its Notes say why" || bad "(r9) $OUT"

bash "$TOOL" "$T/lead.md" "$T/plain.md" --format bogus >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "(r10) an unknown --format is usage: exit 2" || bad "(r10) rc=$RC"

OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain.md" --format report --plain-cost 0.3 --plain-wall '')"
printf '%s\n' "$OUT" | grep -qF "Blind session: \$0.30, ? s, returned." && printf '%s\n' "$OUT" | grep -qF '"plain_wall_s":null' \
  && ok "(r11) an empty --plain-wall is unknown: '? s' and null, never 0 or negative" || bad "(r11) $(printf '%s\n' "$OUT" | grep 'Blind session')"

printf '%s\n' '## Critical (must fix before merge)' '- [Pipeline] Makefile:12 (confidence: 90) — the test target never runs' '' \
  '**Ready to merge?** With fixes' > "$T/lead-make.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B4 Makefile:13 — test target skipped' '- [blocker] B5 build/Dockerfile:2 — wrong base' > "$T/plain-make.md"
OUT="$(bash "$TOOL" "$T/lead-make.md" "$T/plain-make.md" --format report)"
printf '%s\n' "$OUT" | grep -qxF -- '- [lane+blind] [Pipeline] Makefile:12 (confidence: 90) — the test target never runs' \
  && printf '%s\n' "$OUT" | grep -qxF -- '- [blind] build/Dockerfile:2 — wrong base' \
  && listed "$OUT" '- `Makefile:12` (blind :13) — lane Critical [Pipeline]: the test target never runs · blind B4: test target skipped' \
  && listed "$OUT" '- `build/Dockerfile:2` — B5: wrong base _(added as [blind])_' \
  && ok "(r12) an extensionless path (Makefile:12) is a Critical bullet's site: plain's Makefile:13 agrees with it, ids kept" || bad "(r12) $OUT"

devjs() { printf '%s\n' "$1" | sed -n 's/^<!-- plain-vs-lane: \(.*\) -->$/\1/p'; }
printf '%s\n' 'verdict: approve' '## Findings' '- [note] N1 src/b.ts:6 — slow loop' > "$T/plain-note.md"
OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-note.md" --format report)"
listed "$OUT" '**agreed: note** (1)' '- `src/b.ts:5` (blind :6) — lane Warning [Performance]: slow · blind N1: slow loop' && printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** With fixes' \
  && jq -e '.m_n_n == 1 and .agreed == 0 and .flipped == false' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r13) a plain note at a Warning's site is an agreed note, and changes nothing in the report" || bad "(r13) $(devjs "$OUT")"

printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/b.ts:5 — the loop is quadratic' > "$T/plain-on-warning.md"
sed 's/— slow$/— slow, as the plain review also says/' "$T/lead.md" > "$T/lead-cites.md"
OUT="$(bash "$TOOL" "$T/lead-cites.md" "$T/plain-on-warning.md" --format report)"
printf '%s\n' "$OUT" | grep -qxF -- '- [blind] src/b.ts:5 — the loop is quadratic' && printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** No' \
  && listed "$OUT" '**lane note, blind blocker** (1)' '- `src/b.ts:5` — lane Warning [Performance]: slow, as the plain review also says · blind B1: the loop is quadratic _(added as [blind]; lane cites blind)_' \
  && jq -e '.m_n_b == 1 and .plain_only == 1 and .lane_cites_plain == 1 and .flipped == true' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r14) a plain blocker the lane rated a Warning is still added and flips; its pair names the split and the citation" || bad "(r14) $(devjs "$OUT")"

printf '%s\n' '## Critical (must fix before merge)' 'None.' '' '## Suppressed (below confidence threshold)' '- [Security] src/e.ts:4 (confidence: 60) — maybe injectable' \
  '- [Style] src/f.ts:1 (confidence: 40) — naming' '' '**Ready to merge?** Yes' > "$T/lead-supp.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/e.ts:5 — the query is injectable' > "$T/plain-supp.md"
OUT="$(bash "$TOOL" "$T/lead-supp.md" "$T/plain-supp.md" --format report)"
listed "$OUT" '**lane dismissed, blind blocker** (1)' '- `src/e.ts:4` (blind :5) — lane Suppressed [Security]: maybe injectable · blind B1: the query is injectable _(added as [blind])_' \
  && [[ "$(pairs "$OUT")" != *'src/f.ts'* ]] && jq -e '.m_d_b == 1 and .m_d_0 == 1 and .lane_dismissed == 2' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r15) a suppressed bullet at plain's site is a dismissal, not a miss; an unpaired one is not listed" || bad "(r15) $(devjs "$OUT")"

printf '%s\n' 'verdict: approve' '## Findings' '- [note] N0 src/a.ts:1 — ticket-unavailable — getJiraIssue could not fetch GH-42' > "$T/plain-noticket.md"
OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-noticket.md" --format report --ticket true)"
jq -e '.ticket == false and .plain_notes_dropped == 0 and .m_0_n == 0' <<<"$(devjs "$OUT")" >/dev/null && printf '%s\n' "$OUT" | grep -q 'returned, reviewed without a ticket\.$' \
  && ok "(r16) a ticket-unavailable note with a site before it still means plain had no ticket, and is not listed" || bad "(r16) $(devjs "$OUT")"

{ printf '%s\n' 'verdict: approve' '## Extra' '## Findings'; printf -- '- [note] N1 src/a.ts:30 — a | pipe and </details> and Ready to merge? then %s\n' "$(printf 'word %.0s' $(seq 60))"; } > "$T/plain-hostile.md"
OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-hostile.md" --format report)"
DEV="$(printf '%s\n' "$OUT" | sed -n '/^<details><summary>dev: lane vs blind/,$p')"
ENTRY="$(grep '^- `src/a.ts:30` — N1: ' <<<"$DEV")"
[[ "$ENTRY" == *'a | pipe and &lt;/details> and Ready to merge then word'*'…' ]] && ! grep -q '^## \|^- \[\|Ready to merge?' <<<"$DEV" \
  && [ "$(grep -cx '</details>' <<<"$DEV")" -eq 2 ] && [ "$(tail -n 1 <<<"$DEV")" = '</details>' ] && grep -qx '    ## Extra' <<<"$DEV" \
  && ok "(r17) plain text cannot break the block: entries escape and cut, the quoted draft is indented, and the folds close" || bad "(r17) $DEV"

OUT="$(bash "$TOOL" "$T/lead.md" '' --format report)"
printf '%s\n' "$OUT" | grep -qxF '<details><summary>dev: lane vs blind — the blind review did not return</summary>' && [ -z "$(pairs "$OUT")" ] \
  && printf '%s\n' "$OUT" | grep -qF 'Lane session: not measured. Blind session: unpriced, ? s, did not return' \
  && jq -e '.plain_merged == null and .m_b_b == null and .m_0_n == null and .plain_verdict == null' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r18) with no plain draft there is no list, every matrix cell is null, and a lane given no cost or wall is not measured" || bad "(r18) $(devjs "$OUT")"

printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/a.ts:9 — injection' '- [blocker] B2 src/a.ts:11 — injection again' > "$T/plain-two.md"
OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-two.md" --format report)"
listed "$OUT" '**agreed: blocker** (1)' '- `src/a.ts:10` (blind :9) — lane Critical [Security]: injection · blind B1: injection (+ B2)' \
  && printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** With fixes' && jq -e '.plain_merged == 1 and .plain_only == 0 and .m_b_b == 1' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r19) two plain blockers at one lane blocker are one agreed pair, the second counted as merged" || bad "(r19) $(devjs "$OUT")"

printf '%s\n' 'verdict: approve' '## Findings' 'None.' > "$T/plain-none.md"
OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-none.md" --format report)"
! printf '%s\n' "$OUT" | grep -q 'blind review, as written' && printf '%s\n' "$OUT" | grep -qF 'blind approve' && [ "$(printf '%s\n' "$OUT" | tail -n 1)" = '</details>' ] \
  && ok "(r21) a blind draft with no findings is not quoted: the verdict line already says it" || bad "(r21) $(printf '%s\n' "$OUT" | tail -n 12)"

{ printf '%s\n' 'verdict: approve' '## Findings'; for i in $(seq 45); do printf -- '- [note] N%s src/n%s.ts:1 — note %s\n' "$i" "$i" "$i"; done; } > "$T/plain-many.md"
OUT="$(bash "$TOOL" "$T/lead-clean.md" "$T/plain-many.md" --format report)"
[ "$(printf '%s\n' "$OUT" | grep -c '^- `src/n')" -eq 40 ] && printf '%s\n' "$OUT" | grep -qxF '**blind only: note** (45)' && printf '%s\n' "$OUT" | grep -qx '5 more pairs are counted in the machine line.' \
  && jq -e '.m_0_n == 45' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r20) the list stops at 40 pairs and says how many more the machine line counts" || bad "(r20) pairs=$(printf '%s\n' "$OUT" | grep -c '^- `')"

echo "verdict-join-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"

#!/usr/bin/env bash
# shellcheck disable=SC2016  # expected lines hold literal backticks
# verdict-join-selftest.sh — behavioral selftest for tools/verdict-join.sh, under --format report (the join review-lead's
# report goes through) and --format verdict. The lane-verdict format is also driven through run.sh in
# skills/run/run-joined-selftest.sh.
#
# INVARIANTS GUARDED: a review-lead report in the lane grammar is joined by the verdict rules: a plain blocker within 3
# lines of a lane blocker tags it [lane+blind]; any other plain blocker or note is added as [blind] with the next free
# id and flips an approve; one near a lane finding is not listed again; an added note keeps within the checker's
# four-line limit. Both formats end with one visible
# `lane vs blind:` line and the hidden machine line, and write no fold, pair list, session line or blind draft; the
# machine line keeps cost and wall time, a findings list in pairing order, and a matrix that sums. With no plain draft
# the verdict stands, its Notes say why, and the line says the blind review did not return. With a changed-line set
# (a later review), a plain finding sited outside it is left out and counted; one inside it, or with no site, is added;
# an unreadable set is exit 2.
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

SHA=0123456789abcdef0123456789abcdef01234567
BY='reviewed-by: second-shift review-lead (v1)'
# lead <verdict> <summary lines...> -- <findings lines...>: a review-lead report in the lane grammar
lead() {
  local v="$1"; shift; printf '%s\n' "verdict: $v" "reviewed: $SHA" "$BY" '' '## Summary' ''
  while [ "$1" != -- ]; do printf '%s\n' "$1"; shift; done; shift
  printf '%s\n' '' '## Findings' ''; printf '%s\n' "$@"
}
lead needs-work 'Not mergeable yet.' 'Fix B1 and N1.' -- '- [blocker] B1 [Security] src/a.ts:10 — injection' '  Scenario: a quote → the query breaks' \
  '- [note] N1 [Performance] src/b.ts:5 — slow' > "$T/lead.md"
lead approve 'Mergeable as it is.' 'Nothing to do.' -- 'None.' > "$T/lead-clean.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/a.ts:12 — the same injection' '  Scenario: x → y' \
  '- [blocker] B2 src/c.ts:3 — off by one' '  Scenario: n = 0 → crash' '- [note] N1 src/d.ts:1 — style' > "$T/plain.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/a.ts:11 — the same injection' > "$T/plain-agrees.md"
devjs() { printf '%s\n' "$1" | sed -n 's/^<!-- plain-vs-lane: \(.*\) -->$/\1/p'; }
above() { printf '%s\n' "$1" | sed '/^lane vs blind: /,$d'; }
findings() { printf '%s\n' "$1" | awk '/^## Findings/ { on = 1; next } /^## / { on = 0 } on'; }

OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain.md" --format report --lane-cost 1.2 --plain-cost 0.3 --lane-wall 100 --plain-wall 40)"; RC=$?
F="$(findings "$OUT")"
[ "$RC" -eq 0 ] && grep -qxF -- '- [blocker] B1 [lane+blind] [Security] src/a.ts:10 — injection' <<<"$F" \
  && ok "(r1) a plain blocker 2 lines from a report's blocker merges into it as [lane+blind]" || bad "(r1) rc=$RC: $F"
grep -qxF -- '- [blocker] B2 [blind] src/c.ts:3 — off by one' <<<"$F" && grep -qxF '  Scenario: n = 0 → crash' <<<"$F" \
  && [ "$(grep -c '^- \[blocker\]' <<<"$F")" -eq 2 ] \
  && ok "(r2) a plain-only blocker is added to the report as [blind] with the next B id and its continuation" || bad "(r2) $F"
grep -qxF -- '- [note] N2 [blind] src/d.ts:1 — style' <<<"$F" \
  && ok "(r3) a plain-only note is added to the report as [blind] with the next N id" || bad "(r3) $F"
JSON="$(devjs "$OUT")"
INV='.lane_blockers == .m_b_b + .m_b_n + .m_b_0 and .lane_notes == .m_n_b + .m_n_n + .m_n_0 and .lane_dismissed == .m_d_b + .m_d_n + .m_d_0
  and .plain_blockers == .m_b_b + .plain_merged + .m_n_b + .m_d_b + .m_0_b and .agreed == .m_b_b and .lane_only == .m_b_n + .m_b_0'
[ "$(jq -c '[.lane_blockers,.plain_blockers,.agreed,.lane_only,.plain_only,.plain_notes_dropped,.flipped,.plain_returned,.lane_cost_usd,.plain_cost_usd,.lane_wall_s,.plain_wall_s,.v,.format,.lane_verdict,.plain_verdict]' <<<"$JSON" 2>/dev/null)" \
     = '[1,2,1,0,2,0,false,true,1.2,0.3,100,40,4,"report","needs-work","needs-work"]' ] \
  && jq -e "$INV" <<<"$JSON" >/dev/null \
  && ok "(r5) the machine line counts the report's pairs, keeps both sessions' cost and wall time, and its matrix sums" || bad "(r5) json=$JSON"

# both formats: one visible line, then the hidden machine line, last
printf '%s\n' 'verdict: needs-work' "reviewed: $SHA" '' '## Findings' '' '- [blocker] B1 src/a.ts:10 — injection' '- [note] N1 src/b.ts:5 — slow' > "$T/lane-n.md"
for f in report verdict; do
  src="$T/lead.md"; [ "$f" = verdict ] && src="$T/lane-n.md"
  OUT="$(bash "$TOOL" "$src" "$T/plain.md" --format "$f")"
  [ "$(grep -c '^lane vs blind: ' <<<"$OUT")" -eq 1 ] \
    && grep -qxF 'lane vs blind: 1 agreed, 0 rated differently, 1 lane alone, 2 blind alone' <<<"$OUT" \
    && [ "$(tail -n 2 <<<"$OUT" | head -n 1)" = 'lane vs blind: 1 agreed, 0 rated differently, 1 lane alone, 2 blind alone' ] \
    && [[ "$(tail -n 1 <<<"$OUT")" == '<!-- plain-vs-lane: {'*'} -->' ]] && jq -e --arg f "$f" '.format == $f' <<<"$(devjs "$OUT")" >/dev/null \
    && ! grep -qE '<details|</details>|dev: lane vs blind|Lane session:|Blind session:|blind review, as written|^- Verdict:|^- Ready to merge:|^\*\*[a-z].*\*\* \([0-9]+\)$' <<<"$OUT" \
    && [ "$(awk '/^## Notes/ { on = 1 } on && /^lane vs blind: /' <<<"$OUT")" != "" ] \
    && ok "(r4) --format $f writes one 'lane vs blind:' line under ## Notes and the hidden JSON line last, and no fold, pair list, session line or blind draft" \
    || bad "(r4) --format $f: $(tail -n 6 <<<"$OUT" | tr '\n' '|')"
done
OUT="$(bash "$TOOL" "$T/lead.md" '' --format report --why 'the blind review ran past 3600s')"
grep -qxF 'Joined review: the blind review ran past 3600s, so this report is review-lead alone.' <<<"$OUT" \
  && grep -qxF 'lane vs blind: the blind review did not return' <<<"$OUT" && [ "$(head -n 1 <<<"$OUT")" = 'verdict: needs-work' ] \
  && jq -e '.plain_returned == false and .plain_merged == null and .m_b_b == null and .m_0_n == null and .plain_verdict == null and .lane_cost_usd == null and .lane_wall_s == null' <<<"$(devjs "$OUT")" >/dev/null \
  && ! grep -q '<details' <<<"$OUT" \
  && ok "(r9) with no plain draft the report stands, its Notes say why, the line says the blind review did not return, and every matrix cell and an unpassed cost is null" \
  || bad "(r9) $(tail -n 5 <<<"$OUT" | tr '\n' '|')"
OUT="$(bash "$TOOL" "$T/lane-n.md" '')"
grep -qxF 'Joined review: the blind review did not return, so this verdict is the lane review alone.' <<<"$OUT" \
  && [ "$(grep -c '^lane vs blind: the blind review did not return$' <<<"$OUT")" -eq 1 ] && [[ "$(tail -n 1 <<<"$OUT")" == '<!-- plain-vs-lane: '* ]] \
  && ok "(r9) under --format verdict too, a missing blind review gives the one line and the machine line" || bad "(r9) verdict: $(tail -n 5 <<<"$OUT" | tr '\n' '|')"

lead approve 'Mergeable as it is.' 'Nothing to do.' -- 'None.' > "$T/lead-approve.md"
OUT="$(bash "$TOOL" "$T/lead-approve.md" "$T/plain.md" --format report)"; printf '%s\n' "$OUT" > "$T/joined-flip.md"
CHECK="$(bash "$HERE/verdict-check.sh" "$T/joined-flip.md")"; RC=$?
[ "$RC" -eq 0 ] && [ "$(head -n 1 <<<"$OUT")" = 'verdict: needs-work' ] && grep -qx 'Not mergeable yet.' <<<"$OUT" && grep -qx 'Fix the \[blind\] findings in Findings.' <<<"$OUT" \
  && grep -qxF 'lane vs blind: 0 agreed, 0 rated differently, 0 lane alone, 3 blind alone; blind flipped the verdict' <<<"$OUT" \
  && jq -e '.flipped == true and .lane_verdict == "approve" and .plain_only == 3' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r6) a blind finding flips a report's approve; the line says so, and the joined report passes verdict-check.sh with no record" \
  || bad "(r6) rc=$RC check=$CHECK $(above "$OUT" | tr '\n' '|')"

OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-agrees.md" --format report)"
! grep -q '\[blind\]' <<<"$OUT" && grep -qxF -- '- [blocker] B1 [lane+blind] [Security] src/a.ts:10 — injection' <<<"$OUT" \
  && ok "(r7) a plain blocker that agrees adds nothing" || bad "(r7) $OUT"

OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain.md" --format report)"
[ "$(sed -n 1,3p <<<"$OUT")" = "$(sed -n 1,3p "$T/lead.md")" ] \
  && ok "(r9b) the verdict, reviewed and reviewed-by lines pass through the join unchanged" || bad "(r9b) $(sed -n 1,3p <<<"$OUT")"

bash "$TOOL" "$T/lead.md" "$T/plain.md" --format bogus >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "(r10) an unknown --format is usage: exit 2" || bad "(r10) rc=$RC"

OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain.md" --format report --plain-cost 0.3 --plain-wall '')"
jq -e '.plain_cost_usd == 0.3 and .plain_wall_s == null' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r11) an empty --plain-wall is unknown: null, never 0 or negative" || bad "(r11) $(devjs "$OUT")"

lead needs-work 'Not mergeable yet.' 'Fix B1.' -- '- [blocker] B1 [Pipeline] Makefile:12 — the test target never runs' > "$T/lead-make.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B4 Makefile:13 — test target skipped' '- [blocker] B5 build/Dockerfile:2 — wrong base' > "$T/plain-make.md"
OUT="$(bash "$TOOL" "$T/lead-make.md" "$T/plain-make.md" --format report)"
grep -qxF -- '- [blocker] B1 [lane+blind] [Pipeline] Makefile:12 — the test target never runs' <<<"$OUT" \
  && grep -qxF -- '- [blocker] B2 [blind] build/Dockerfile:2 — wrong base' <<<"$OUT" \
  && jq -e '.m_b_b == 1 and .m_0_b == 1' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r12) an extensionless path (Makefile:12) is a finding's site: plain's Makefile:13 agrees with it" || bad "(r12) $OUT"

printf '%s\n' 'verdict: approve' '## Findings' '- [note] N1 src/b.ts:6 — slow loop' > "$T/plain-note.md"
OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-note.md" --format report)"
! grep -q '\[blind\]' <<<"$OUT" && jq -e '.m_n_n == 1 and .agreed == 0 and .flipped == false and .plain_only == 0' <<<"$(devjs "$OUT")" >/dev/null \
  && grep -qxF 'lane vs blind: 1 agreed, 0 rated differently, 1 lane alone, 0 blind alone' <<<"$OUT" \
  && ok "(r13) a plain note at a lane note's site is an agreed note and is not listed again" || bad "(r13) $(devjs "$OUT")"

printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/b.ts:5 — the loop is quadratic' > "$T/plain-on-note.md"
sed 's/— slow$/— slow, as the plain review also says/' "$T/lead.md" > "$T/lead-cites.md"
OUT="$(bash "$TOOL" "$T/lead-cites.md" "$T/plain-on-note.md" --format report)"
grep -qxF -- '- [blocker] B2 [blind] src/b.ts:5 — the loop is quadratic' <<<"$OUT" \
  && jq -e '.m_n_b == 1 and .plain_only == 1 and .lane_cites_plain == 1' <<<"$(devjs "$OUT")" >/dev/null \
  && grep -qxF 'lane vs blind: 0 agreed, 1 rated differently, 1 lane alone, 0 blind alone' <<<"$OUT" \
  && ok "(r14) a plain blocker the lane rated a note is still added; the line counts it as rated differently" || bad "(r14) $(devjs "$OUT")"

printf '%s\n' 'verdict: approve' '## Findings' '- [note] N0 src/a.ts:1 — ticket-unavailable — getJiraIssue could not fetch GH-42' > "$T/plain-noticket.md"
OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-noticket.md" --format report --ticket true)"
jq -e '.ticket == false and .plain_notes_dropped == 0 and .m_0_n == 0 and .plain_only == 0' <<<"$(devjs "$OUT")" >/dev/null && ! grep -q 'ticket-unavailable' <<<"$(above "$OUT")" \
  && ok "(r16) a ticket-unavailable note with a site before it still means plain had no ticket, and is not added or counted" || bad "(r16) $(devjs "$OUT")"

{ printf '%s\n' 'verdict: approve' '## Extra' '## Findings'; printf -- '- [note] N1 src/z.ts:30 — a | pipe and </details> and --> and Ready to merge? then %s\n' "$(printf 'word %.0s' $(seq 60))"; } > "$T/plain-hostile.md"
OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-hostile.md" --format report)"
grep -q '^- \[note\] N2 \[blind\] src/z.ts:30 — a | pipe and </details> and --> and Ready to merge then word' <<<"$OUT" && ! grep -q 'Ready to merge?' <<<"$OUT" \
  && [ "$(grep -c '^<!-- plain-vs-lane: ' <<<"$OUT")" -eq 1 ] && [[ "$(tail -n 1 <<<"$OUT")" == '<!-- plain-vs-lane: '*' -->' ]] \
  && jq -e '.findings | length == 3' <<<"$(devjs "$OUT")" >/dev/null && ! grep -q '^## Extra' <<<"$OUT" \
  && ok "(r17) plain text cannot break the body: Ready to merge? loses its question mark, plain's own sections stay out, and the machine line stays one line" || bad "(r17) $(tail -n 4 <<<"$OUT" | tr '\n' '|')"

printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/a.ts:9 — injection' '- [blocker] B2 src/a.ts:11 — injection again' > "$T/plain-two.md"
OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-two.md" --format report)"
! grep -q '\[blind\]' <<<"$OUT" && jq -e '.plain_merged == 1 and .plain_only == 0 and .m_b_b == 1' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r19) two plain blockers at one lane blocker are one agreed pair, the second counted as merged" || bad "(r19) $(devjs "$OUT")"

V2KEYS='["lane_blockers","plain_blockers","agreed","lane_only","plain_only","plain_notes_dropped","flipped","plain_returned","lane_cost_usd","plain_cost_usd","lane_wall_s","plain_wall_s","ticket","v","format","lane_verdict","plain_verdict","lane_notes","lane_dismissed","lane_cites_plain","plain_merged","m_b_b","m_b_n","m_b_0","m_n_b","m_n_n","m_n_0","m_d_b","m_d_n","m_d_0","m_0_b","m_0_n"]'
v4ok() { jq -e --argjson k "$V2KEYS" '. as $l | .v == 4 and (.findings | type) == "array" and .plain_unchanged_dropped == null and all($k[]; . as $x | $l | has($x))' <<<"$1" >/dev/null 2>&1; }
printf '%s\n' 'verdict: needs-work' 'reviewed: abc' '' '## Findings' '' '- [blocker] B1 src/a.ts:10 — injection' '  Scenario: a quote → the query breaks' \
  '- [note] N1 src/b.ts:5 — slow' '- [note] N2 src/z.ts:40 — Dismissed. not reachable' > "$T/lane-v.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/a.ts:9 — injection' '- [blocker] B2 src/a.ts:11 — injection again' \
  '- [blocker] B3 src/c.ts:3 — off by one' '- [note] the docs are stale' > "$T/plain-v.md"
OUT="$(bash "$TOOL" "$T/lane-v.md" "$T/plain-v.md")"; RJ="$(devjs "$OUT")"
OUTR="$(bash "$TOOL" "$T/lead.md" "$T/plain.md" --format report)"; RR="$(devjs "$OUTR")"
v4ok "$RJ" && v4ok "$RR" && [ "$(jq -r .format <<<"$RJ")" = verdict ] && [ "$(jq -r .format <<<"$RR")" = report ] \
  && ok "(r22) the machine line is v4 and carries a findings array, every v2 field and a null plain_unchanged_dropped, under --format verdict and --format report" || bad "(r22) verdict=$RJ report=$RR"
WANT='[{"src":"blind","id":"B3","class":"blocker","path":"src/c.ts","line":3,"pair":null,"posted_as":"B2"},{"src":"lane","id":"B1","class":"blocker","path":"src/a.ts","line":10,"pair":1},{"src":"blind","id":"B1","class":"blocker","path":"src/a.ts","line":9,"pair":1},{"src":"blind","id":"B2","class":"blocker","path":"src/a.ts","line":11,"pair":1},{"src":"lane","id":"N1","class":"note","path":"src/b.ts","line":5,"pair":null},{"src":"blind","id":null,"class":"note","path":null,"line":null,"pair":null,"posted_as":"N3"},{"src":"lane","id":"N2","class":"dismissed","path":"src/z.ts","line":40,"pair":null}]'
[ "$(jq -c .findings <<<"$RJ")" = "$WANT" ] && [ "$(jq .findings_omitted <<<"$RJ")" = 0 ] && grep -qx -- '- \[blocker\] B2 \[blind\] src/c.ts:3 — off by one' <<<"$OUT" \
  && grep -qx -- '- \[note\] N3 \[blind\] the docs are stale' <<<"$OUT" \
  && ok "(r23) one entry per finding in pairing order: two blind blockers merged onto lane B1 share its pair, the added one is posted_as B2, the siteless blind note is posted_as N3, a lone dismissal comes last, a missing id or site is null" \
  || bad "(r23) findings=$(jq -c .findings <<<"$RJ")"
WANT='[{"src":"blind","id":"B2","class":"blocker","path":"src/c.ts","line":3,"pair":null,"posted_as":"B2"},{"src":"lane","id":"B1","class":"blocker","path":"src/a.ts","line":10,"pair":1},{"src":"blind","id":"B1","class":"blocker","path":"src/a.ts","line":12,"pair":1},{"src":"lane","id":"N1","class":"note","path":"src/b.ts","line":5,"pair":null},{"src":"blind","id":"N1","class":"note","path":"src/d.ts","line":1,"pair":null,"posted_as":"N2"}]'
[ "$(jq -c .findings <<<"$RR")" = "$WANT" ] \
  && ok "(r24) under --format report a lane entry keeps its id, and each added blind finding is posted_as its new id" || bad "(r24) findings=$(jq -c .findings <<<"$RR")"

RJ="$(devjs "$(bash "$TOOL" "$T/lane-v.md" '')")"; RR="$(devjs "$(bash "$TOOL" "$T/lead.md" '' --format report)")"
[ "$(jq -c '[.findings[] | [.src, .id, .class, .line, .pair]]' <<<"$RJ")" = '[["lane","B1","blocker",10,null],["lane","N1","note",5,null],["lane","N2","dismissed",40,null]]' ] \
  && [ "$(jq -c '[.findings[] | [.src, .id, .class, .line]]' <<<"$RR")" = '[["lane","B1","blocker",10],["lane","N1","note",5]]' ] \
  && [ "$(jq -c '[.findings[] | select(.src == "blind")] | length' <<<"$(devjs "$(bash "$TOOL" "$T/lead.md" "$T/plain-noticket.md" --format report)")")" = 0 ] \
  && ok "(r25) with no blind draft every lane finding has an entry in draft order; the ticket-unavailable note has none" || bad "(r25) verdict=$RJ report=$RR"

{ printf '%s\n' 'verdict: needs-work' 'reviewed: abc' '' '## Findings' ''
  for i in $(seq 160); do printf -- '- [blocker] B%s src/module-%s/handler-%s.ts:%s — the handler drops the retry header\n  Scenario: a 503 → the request is lost\n' "$i" "$i" "$i" "$i"; done; } > "$T/lane-320.md"
{ printf '%s\n' 'verdict: approve' '## Findings'; for i in $(seq 160); do printf -- '- [note] N%s lib/other-%s/thing-%s.ts:%s — a naming nit\n' "$i" "$i" "$i" "$i"; done; } > "$T/plain-320.md"
OUT="$(bash "$TOOL" "$T/lane-320.md" "$T/plain-320.md")"; RJ="$(devjs "$OUT")"
[ "$(jq '.findings | length' <<<"$RJ")" = 150 ] && [ "$(jq .findings_omitted <<<"$RJ")" = 170 ] && [ "$(printf '%s\n' "$OUT" | wc -c)" -lt 65536 ] \
  && ok "(r26) a join of 320 findings lists 150 entries, counts 170 omitted, and stays under 65,536 bytes ($(printf '%s\n' "$OUT" | wc -c | tr -d ' '))" \
  || bad "(r26) entries=$(jq '.findings | length' <<<"$RJ") omitted=$(jq .findings_omitted <<<"$RJ") bytes=$(printf '%s\n' "$OUT" | wc -c)"

printf '%s\n' '{"at":"2026-01-02T03:04:05Z","total":2,"by_author":{"greptile-apps[bot]":2}}' > "$T/oc.json"
printf '%s\n' '{"at":"2026-01-02T03:04:05Z","total":"2","by_author":{}}' > "$T/oc-shape.json"
printf '%s\n' '{"at":' > "$T/oc-broken.json"
printf '%s\n' '{"at":"x-->y<","total":0,"by_author":{}}' > "$T/oc-angle.json"
ocv() { devjs "$(bash "$TOOL" "$T/lane-v.md" "$T/plain-v.md" "$@")" | jq -c '.other_comments'; }
[ "$(ocv --other-comments "$T/oc.json")" = '{"at":"2026-01-02T03:04:05Z","total":2,"by_author":{"greptile-apps[bot]":2}}' ] \
  && [ "$(devjs "$(bash "$TOOL" "$T/lead.md" "$T/plain.md" --format report --other-comments "$T/oc.json")" | jq -c '.other_comments.by_author')" = '{"greptile-apps[bot]":2}' ] \
  && [ "$(ocv)" = null ] && [ "$(ocv --other-comments "$T/absent.json")" = null ] && [ "$(ocv --other-comments "$T/oc-broken.json")" = null ] \
  && [ "$(ocv --other-comments "$T/oc-shape.json")" = null ] && [ "$(ocv --other-comments "$T/oc-angle.json")" = '{"at":"x-->y<","total":0,"by_author":{}}' ] \
  && OUT="$(bash "$TOOL" "$T/lane-v.md" "$T/plain-v.md" --other-comments "$T/oc-angle.json")" && [[ -n "$OUT" && "$OUT" != *'-->y'* ]] \
  && ok "(r27) --other-comments emits the count file as other_comments; no flag, an absent file, invalid JSON or a wrong shape give null; '>' cannot close the comment" \
  || bad "(r27) good=$(ocv --other-comments "$T/oc.json") none=$(ocv) broken=$(ocv --other-comments "$T/oc-broken.json") shape=$(ocv --other-comments "$T/oc-shape.json")"

lead needs-work 'Not mergeable yet.' 'Fix B1, B2 and N1.' -- '- [blocker] B1 [Routing] app/users/[id]/page.tsx:12 — the param is read as a number' \
  '- [blocker] B2 [Security] src/a.ts:10 — injection' '- [note] N1 [Style] app/(shop)/[[...slug]]/page.tsx:3 — dead branch' > "$T/lead-routes.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 app/posts/[id]/page.tsx:12 — the param is read as a number' \
  '- [blocker] B2 see [x](src/a.ts:10) — injection' > "$T/plain-routes.md"
OUT="$(bash "$TOOL" "$T/lead-routes.md" "$T/plain-routes.md" --format report)"; RR="$(devjs "$OUT")"
grep -qxF -- '- [blocker] B2 [lane+blind] [Security] src/a.ts:10 — injection' <<<"$OUT" \
  && grep -qxF -- '- [blocker] B1 [Routing] app/users/[id]/page.tsx:12 — the param is read as a number' <<<"$OUT" \
  && grep -qxF -- '- [blocker] B3 [blind] app/posts/[id]/page.tsx:12 — the param is read as a number' <<<"$OUT" \
  && [ "$(jq -c '[.findings[] | [.src, .path, .line, (.pair != null)]]' <<<"$RR")" = '[["blind","app/posts/[id]/page.tsx",12,false],["lane","app/users/[id]/page.tsx",12,false],["lane","src/a.ts",10,true],["blind","src/a.ts",10,true],["lane","app/(shop)/[[...slug]]/page.tsx",3,false]]' ] \
  && ok "(r28) a route path is read whole, [x](src/a.ts:10) yields src/a.ts:10, and two route files at one line do not pair" || bad "(r28) findings=$(jq -c .findings <<<"$RR") $(printf '%s\n' "$OUT" | grep '^- ')"

printf '%s\n' 'verdict: approve' "reviewed: $(printf 'a%.0s' $(seq 40))" '' '## Decision record rows' '' '| Row | Score | Evidence |' '| --- | --- | --- |' \
  '| D-1 | honored | ok |' '' '## Findings' '' 'None.' > "$T/lane-ready.md"
printf '%s\n' '| D-1 | a | b | user-answered |' > "$T/rec-ready.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/x.ts:4 — the banner asks "Ready to merge?" before the save completes' \
  '  Scenario: click save → the banner still says "Ready to merge?"' > "$T/plain-ready.md"
OUT="$(bash "$TOOL" "$T/lane-ready.md" "$T/plain-ready.md")"; printf '%s\n' "$OUT" > "$T/joined-ready.md"
CHECK="$(bash "$HERE/verdict-check.sh" "$T/joined-ready.md" "$T/rec-ready.md" "$T/rec-ready.md")"; RC=$?
[ "$RC" -eq 0 ] && grep -qxF -- '- [blocker] B1 [blind] src/x.ts:4 — the banner asks "Ready to merge" before the save completes' <<<"$OUT" \
  && grep -qxF '  Scenario: click save → the banner still says "Ready to merge"' <<<"$OUT" \
  && ok "(r29) a blind blocker quoting Ready to merge? is added without the question mark, and the joined verdict passes verdict-check" \
  || bad "(r29) rc=$RC: $CHECK"

printf '%s\n' 'verdict: approve' "reviewed: $(printf 'a%.0s' $(seq 40))" '' '## Summary' '' 'Mergeable as it is.' 'Nothing to do.' '' '## Decision record rows' '' \
  '| Row | Score | Evidence |' '| --- | --- | --- |' '| D-1 | honored | ok |' '' '## Findings' '' 'None.' '' '## Notes' '' 'A process note.' > "$T/lane-approve.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [note] N1 src/u.ts:7 — the helper repeats a literal the repo keeps as a constant' \
  '  Scenario: the constant changes → this helper keeps the old value' '  Fix: use the constant' '- [note] N2 src/v.ts:2 — a second convention break' > "$T/plain-notes.md"
OUT="$(bash "$TOOL" "$T/lane-approve.md" "$T/plain-notes.md")"; printf '%s\n' "$OUT" > "$T/joined-notes.md"; RJ="$(devjs "$OUT")"
CHECK="$(bash "$HERE/verdict-check.sh" "$T/joined-notes.md" "$T/rec-ready.md" "$T/rec-ready.md")"; RC=$?
ABOVE="$(above "$OUT")"
[ "$RC" -eq 0 ] && [ "$(head -n 1 <<<"$OUT")" = 'verdict: needs-work' ] && grep -qx 'Not mergeable yet.' <<<"$ABOVE" && grep -qx 'Fix the \[blind\] findings in Findings.' <<<"$ABOVE" \
  && grep -qxF -- '- [note] N1 [blind] src/u.ts:7 — the helper repeats a literal the repo keeps as a constant' <<<"$ABOVE" \
  && grep -qxF '  Fix: use the constant' <<<"$ABOVE" && grep -qxF -- '- [note] N2 [blind] src/v.ts:2 — a second convention break' <<<"$ABOVE" && ! grep -qx 'None.' <<<"$ABOVE" \
  && jq -e '.flipped == true and .plain_only == 2 and .plain_notes_dropped == 0 and ([.findings[] | select(.src == "blind") | .posted_as] == ["N1","N2"])' <<<"$RJ" >/dev/null \
  && ok "(r30) an unmatched blind note is added as a [blind] note with its continuation, flips an approve, is counted in plain_only, and the joined verdict passes verdict-check" \
  || bad "(r30) rc=$RC check=$CHECK json=$RJ"

printf '%s\n' 'verdict: needs-work' "reviewed: $(printf 'a%.0s' $(seq 40))" '' '## Decision record rows' '' '| Row | Score | Evidence |' '| --- | --- | --- |' '| D-1 | honored | ok |' '' \
  '## Findings' '' '- [blocker] B1 src/w.ts:40 — the retry loops forever' '  Scenario: a 409 → no exit' '  Fix: stop after three tries' \
  '- [note] N4 src/u.ts:8 — a literal the repo keeps as a constant' '  Fix: use the constant' > "$T/lane-mixed.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [note] N1 src/u.ts:6 — the same literal' '- [note] N2 src/w.ts:41 — the loop has no bound' '- [note] N3 src/x.ts:1 — a new one' > "$T/plain-near.md"
OUT="$(bash "$TOOL" "$T/lane-mixed.md" "$T/plain-near.md")"; RJ="$(devjs "$OUT")"; printf '%s\n' "$OUT" > "$T/joined-near.md"
ABOVE="$(above "$OUT")"
bash "$HERE/verdict-check.sh" "$T/joined-near.md" "$T/rec-ready.md" "$T/rec-ready.md" >/dev/null && [ "$(grep -c '^- \[note\]' <<<"$ABOVE")" -eq 2 ] \
  && grep -qxF -- '- [note] N5 [blind] src/x.ts:1 — a new one' <<<"$ABOVE" && ! grep -q 'the same literal\|the loop has no bound' <<<"$ABOVE" \
  && jq -e '.plain_only == 1 and .plain_notes_dropped == 0 and .flipped == false' <<<"$RJ" >/dev/null \
  && ok "(r31) a blind note within 3 lines of a lane note or blocker is not listed again; an unmatched one takes the id after the lane's highest N" \
  || bad "(r31) json=$RJ findings=$(grep '^- \[' <<<"$ABOVE" | tr '\n' '|')"

OUT="$(bash "$TOOL" "$T/lead-clean.md" "$T/plain-notes.md" --format report)"
[ "$(head -n 1 <<<"$OUT")" = 'verdict: needs-work' ] && grep -qxF -- '- [note] N1 [blind] src/u.ts:7 — the helper repeats a literal the repo keeps as a constant' <<<"$OUT" \
  && jq -e '.plain_only == 2 and .plain_notes_dropped == 0 and .flipped == true' <<<"$(devjs "$OUT")" >/dev/null \
  && ok "(r32) --format report adds a blind-only note, and it turns the report's approve into a needs-work" || bad "(r32) $(devjs "$OUT")"

printf '%s\n' 'verdict: approve' "reviewed: $(printf 'a%.0s' $(seq 40))" '' '## Summary' '' 'Mergeable as it is.' 'Nothing to do.' '' '## Decision record rows' '' \
  '| Row | Score | Evidence |' '| --- | --- | --- |' '| D-1 | honored | ok |' '' '## Findings' '' 'None.' '' '## Notes' '' \
  '- `src/u.ts:7` — the record prescribes the helper: "keep the literal local to the helper"' 'A process note that names src/v.ts:2 after its first word.' > "$T/lane-prescribed.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [note] N1 src/u.ts:8 — the helper is an abstraction nothing needs' > "$T/plain-prescribed.md"
OUT="$(bash "$TOOL" "$T/lane-prescribed.md" "$T/plain-prescribed.md")"; printf '%s\n' "$OUT" > "$T/joined-prescribed.md"; RJ="$(devjs "$OUT")"
CHECK="$(bash "$HERE/verdict-check.sh" "$T/joined-prescribed.md" "$T/rec-ready.md" "$T/rec-ready.md")"; RC=$?
OUT2="$(bash "$TOOL" "$T/lane-prescribed.md" "$T/plain-notes.md")"; RJ2="$(devjs "$OUT2")"
ABOVE="$(above "$OUT")"; ABOVE2="$(above "$OUT2")"
[ "$RC" -eq 0 ] && [ "$(head -n 1 <<<"$OUT")" = 'verdict: approve' ] && ! grep -q '^- \[note\]' <<<"$ABOVE" \
  && jq -e '.flipped == false and .plain_only == 0 and .plain_notes_dropped == 1' <<<"$RJ" >/dev/null \
  && [ "$(head -n 1 <<<"$OUT2")" = 'verdict: needs-work' ] && grep -qxF -- '- [note] N1 [blind] src/v.ts:2 — a second convention break' <<<"$ABOVE2" \
  && ! grep -q '^- \[note\] .*src/u.ts' <<<"$ABOVE2" && jq -e '.plain_only == 1 and .plain_notes_dropped == 1' <<<"$RJ2" >/dev/null \
  && ok "(r33) a blind note within 3 lines of a lane Notes line that starts with a site is left out and counted in plain_notes_dropped; a site later in a Notes line does not match" \
  || bad "(r33) rc=$RC check=$CHECK json=$RJ json2=$RJ2"

sed 's/^- `src\/u.ts:7` — .*$/- `src\/u.ts:7` — mutant: guard removed, killed/' "$T/lane-prescribed.md" > "$T/lane-inventory.md"
OUT="$(bash "$TOOL" "$T/lane-inventory.md" "$T/plain-prescribed.md")"; RJ="$(devjs "$OUT")"
ABOVE="$(above "$OUT")"
[ "$(head -n 1 <<<"$OUT")" = 'verdict: needs-work' ] && grep -qxF -- '- [note] N1 [blind] src/u.ts:8 — the helper is an abstraction nothing needs' <<<"$ABOVE" \
  && jq -e '.flipped == true and .plain_only == 1 and .plain_notes_dropped == 0' <<<"$RJ" >/dev/null \
  && ok "(r34) a lane Notes line that starts with a site but quotes no decision leaves out no blind note: the note is added and the approve flips" \
  || bad "(r34) json=$RJ findings=$(grep '^- \[' <<<"$ABOVE" | tr '\n' '|')"

printf '%s\n' 'verdict: needs-work' '## Findings' '- [note] N1 src/u.ts:7 — the helper repeats a literal' '  Scenario: the constant changes → stale value' \
  '  Evidence: src/k.ts:3 holds the constant' '  Callers: src/a.ts:1' '  More: src/b.ts:2' '  Fix: use the constant' > "$T/plain-long.md"
OUT="$(bash "$TOOL" "$T/lane-approve.md" "$T/plain-long.md")"; printf '%s\n' "$OUT" > "$T/joined-long.md"
CHECK="$(bash "$HERE/verdict-check.sh" "$T/joined-long.md" "$T/rec-ready.md" "$T/rec-ready.md")"; RC=$?
REP="$(bash "$TOOL" "$T/lead-clean.md" "$T/plain-long.md" --format report)"; printf '%s\n' "$REP" > "$T/joined-long-report.md"
CHECK2="$(bash "$HERE/verdict-check.sh" "$T/joined-long-report.md")"; RC2=$?
N="$(findings "$OUT" | awk '/^- \[note\] N1 \[blind\] / { on = 1; print; next } on && /^  / { print; next } { on = 0 }')"
[ "$RC" -eq 0 ] && [ "$RC2" -eq 0 ] && [ "$(grep -c '' <<<"$N")" -eq 4 ] \
  && grep -qxF '  Callers: src/a.ts:1 More: src/b.ts:2 Fix: use the constant' <<<"$N" \
  && ok "(r35) a blind note longer than four lines keeps three continuation lines, the later ones appended to the third, and the joined body passes verdict-check in both modes" \
  || bad "(r35) rc=$RC rc2=$RC2 check=$CHECK check2=$CHECK2 note=$N"

# ---- a later review: --changed names the lines changed since the last reviewed head ----
printf '%s\n' 'src/new.ts:9-15' 'src/other.ts:1-3' > "$T/changed.txt"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/old.ts:40 — a defect on code the last review read' '  Scenario: x → y' \
  '- [blocker] B2 src/new.ts:12 — a defect on a changed line' '  Scenario: n = 0 → crash' '- [blocker] B3 the docs name the old flag' \
  '- [note] N1 src/old.ts:41 — a style point on unchanged code' '- [note] N2 src/new.ts:5 — a note on an unchanged line of a changed file' \
  '- [note] N3 new.ts:14 — a note on a changed line, named by its file name' > "$T/plain-later.md"
OUT="$(bash "$TOOL" "$T/lane-approve.md" "$T/plain-later.md" --changed "$T/changed.txt")"; RC=$?; RJ="$(devjs "$OUT")"
F="$(findings "$OUT")"; printf '%s\n' "$OUT" > "$T/joined-later.md"
CHECK="$(bash "$HERE/verdict-check.sh" "$T/joined-later.md" "$T/rec-ready.md" "$T/rec-ready.md")"; RC2=$?
[ "$RC" -eq 0 ] && [ "$RC2" -eq 0 ] && [ "$(head -n 1 <<<"$OUT")" = 'verdict: needs-work' ] \
  && grep -qxF -- '- [blocker] B1 [blind] src/new.ts:12 — a defect on a changed line' <<<"$F" \
  && grep -qxF -- '- [blocker] B2 [blind] the docs name the old flag' <<<"$F" \
  && grep -qxF -- '- [note] N1 [blind] new.ts:14 — a note on a changed line, named by its file name' <<<"$F" \
  && ! grep -q 'src/old.ts\|src/new.ts:5' <<<"$(above "$OUT")" && [ "$(grep -c '^- \[' <<<"$F")" -eq 3 ] \
  && jq -e '.plain_unchanged_dropped == 3 and .plain_only == 3 and .flipped == true and .v == 4' <<<"$RJ" >/dev/null \
  && ok "(r36) with a changed-line set, a plain blocker and notes outside it are left out and counted; one inside it, one named by its file name and a siteless one are added, and the body passes verdict-check" \
  || bad "(r36) rc=$RC check=$RC2 $CHECK json=$RJ findings=$(tr '\n' '|' <<<"$F")"

printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/old.ts:40 — a defect on code the last review read' '- [note] N1 src/other.ts:7 — a note four lines from a hunk' > "$T/plain-unchanged.md"
printf '%s\n' 'verdict: approve' '## Findings' 'None.' > "$T/plain-clean.md"
OUT="$(bash "$TOOL" "$T/lane-approve.md" "$T/plain-unchanged.md" --changed "$T/changed.txt")"; RJ="$(devjs "$OUT")"
[ "$(above "$OUT")" = "$(above "$(bash "$TOOL" "$T/lane-approve.md" "$T/plain-clean.md")")" ] \
  && [ "$(head -n 1 <<<"$OUT")" = 'verdict: approve' ] && ! grep -q '\[blind\]' <<<"$OUT" \
  && jq -e '.plain_unchanged_dropped == 2 and .plain_only == 0 and .flipped == false and .plain_blockers == 1' <<<"$RJ" >/dev/null \
  && ok "(r37) when every plain finding is on an unchanged line, the lane's approve stands as written and the machine line counts both" \
  || bad "(r37) json=$RJ body=$(above "$OUT" | tr '\n' '|')"

: > "$T/changed-empty.txt"
OUT="$(bash "$TOOL" "$T/lane-approve.md" "$T/plain-later.md" --changed "$T/changed-empty.txt")"; RJ="$(devjs "$OUT")"
grep -qxF -- '- [blocker] B1 [blind] the docs name the old flag' <<<"$OUT" && [ "$(grep -c '^- \[' <<<"$(findings "$OUT")")" -eq 1 ] \
  && jq -e '.plain_unchanged_dropped == 5' <<<"$RJ" >/dev/null \
  && ok "(r38) an empty set (the same head reviewed again) leaves out every sited plain finding and keeps the siteless one" || bad "(r38) json=$RJ"

OUT="$(bash "$TOOL" "$T/lane-approve.md" "$T/plain-later.md" --changed "$T/no-such-set.txt" 2>"$T/err")"; RC=$?
[ "$RC" -eq 2 ] && [ -z "$OUT" ] && grep -q 'cannot read the changed-line set' "$T/err" \
  && ok "(r39) an unreadable changed-line set is exit 2, as an unreadable lane draft is, and nothing is joined" || bad "(r39) rc=$RC out=$OUT"

OUT="$(bash "$TOOL" "$T/lane-approve.md" "$T/plain-later.md")"; RJ="$(devjs "$OUT")"
[ "$(grep -c '^- \[[a-z]*\] [BN][0-9]* \[blind\]' <<<"$OUT")" -eq 6 ] && grep -qxF -- '- [blocker] B1 [blind] src/old.ts:40 — a defect on code the last review read' <<<"$OUT" \
  && jq -e '.plain_unchanged_dropped == null and .plain_only == 6' <<<"$RJ" >/dev/null \
  && ok "(r40) with no changed-line set, as in a first review or review-lead's join, every unpaired plain finding is added" || bad "(r40) json=$RJ"

printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 b/src/new.ts:12 — crash on n = 0' \
  '- [note] N1 /work/repo/src/new.ts:13 — a note on a changed line, named by an absolute path' \
  '- [blocker] B2 xsrc/new.ts:12 — a defect in another file whose name ends like a changed one' > "$T/plain-longer.md"
OUT="$(bash "$TOOL" "$T/lane-approve.md" "$T/plain-longer.md" --changed "$T/changed.txt")"; RJ="$(devjs "$OUT")"; F="$(findings "$OUT")"
[ "$(head -n 1 <<<"$OUT")" = 'verdict: needs-work' ] \
  && grep -qxF -- '- [blocker] B1 [blind] b/src/new.ts:12 — crash on n = 0' <<<"$F" \
  && grep -qxF -- '- [note] N1 [blind] /work/repo/src/new.ts:13 — a note on a changed line, named by an absolute path' <<<"$F" \
  && [ "$(grep -c '^- \[' <<<"$F")" -eq 2 ] && jq -e '.plain_unchanged_dropped == 1' <<<"$RJ" >/dev/null \
  && ok "(r41) a site whose path is longer than the range's path, after a /, is on the changed line; a path that only ends with the same letters is not" \
  || bad "(r41) json=$RJ findings=$(tr '\n' '|' <<<"$F")"

echo "verdict-join-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"

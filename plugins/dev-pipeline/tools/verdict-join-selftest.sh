#!/usr/bin/env bash
# verdict-join-selftest.sh — behavioral selftest for tools/verdict-join.sh --format report, the join review-lead's
# report goes through. The lane-verdict format is driven through run.sh in skills/run/run-joined-selftest.sh.
#
# INVARIANTS GUARDED: a plain blocker within 3 lines of a Critical bullet tags it [lane+plain]; any other is added
# under Critical as [plain] and flips Ready to merge from With fixes or Yes to No, but never touches an existing No;
# plain's notes are dropped; a report with no Critical section gets one; with no plain draft the report stands and
# its Notes say why; every report ends with the folded dev block and its machine line.
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
[ "$RC" -eq 0 ] && printf '%s\n' "$CRIT" | grep -qxF -- '- [lane+plain] [Security] src/a.ts:10 (confidence: 90) — injection' \
  && ok "(r1) a plain blocker 2 lines from a Critical bullet merges into it as [lane+plain]" || bad "(r1) rc=$RC: $CRIT"
printf '%s\n' "$CRIT" | grep -qxF -- '- [plain] src/c.ts:3 — off by one' && printf '%s\n' "$CRIT" | grep -qxF '  Scenario: n = 0 → crash' \
  && [ "$(printf '%s\n' "$CRIT" | grep -c '^- ')" -eq 2 ] \
  && ok "(r2) a plain-only blocker is added under Critical as [plain], with its continuation" || bad "(r2) $CRIT"
printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** No' && ! printf '%s\n' "$OUT" | grep -q 'With fixes$' \
  && ok "(r3) a plain-only blocker flips Ready to merge from With fixes to No" || bad "(r3) $(printf '%s\n' "$OUT" | grep 'Ready')"
! printf '%s\n' "$OUT" | grep -q 'src/d.ts' && ok "(r4) plain's notes are dropped" || bad "(r4) a plain note leaked"
JSON="$(printf '%s\n' "$OUT" | sed -n 's/^<!-- plain-vs-lane: \(.*\) -->$/\1/p')"
[ "$(jq -c '[.lane_blockers,.plain_blockers,.agreed,.lane_only,.plain_only,.plain_notes_dropped,.flipped,.plain_returned,.lane_cost_usd,.plain_wall_s]' <<<"$JSON" 2>/dev/null)" = '[1,2,1,0,1,1,true,true,1.2,40]' ] \
  && printf '%s\n' "$OUT" | grep -qxF '<details><summary>dev: lane vs plain</summary>' \
  && printf '%s\n' "$OUT" | grep -qF -- '- Plain-only: plain B2 src/c.ts:3' && printf '%s\n' "$OUT" | grep -qF -- '- Agreed: src/a.ts:10 ↔ plain B1' \
  && ok "(r5) the folded dev block counts both sides, names each id, and carries the machine line" || bad "(r5) json=$JSON"

OUT="$(bash "$TOOL" "$T/lead-no.md" "$T/plain.md" --format report)"
printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** No' && [ "$(jq -r .flipped <<<"$(printf '%s\n' "$OUT" | sed -n 's/^<!-- plain-vs-lane: \(.*\) -->$/\1/p')")" = false ] \
  && ok "(r6) a report already at No is not counted as flipped" || bad "(r6) $OUT"

OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain-agrees.md" --format report)"
printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** With fixes' && ! printf '%s\n' "$OUT" | grep -q '^- \[plain\]' \
  && ok "(r7) a plain blocker that agrees adds nothing and leaves Ready to merge as it was" || bad "(r7) $OUT"

OUT="$(bash "$TOOL" "$T/lead-clean.md" "$T/plain.md" --format report)"
printf '%s\n' "$OUT" | awk '/^## Critical/ { c = NR } /^## Warnings/ { w = NR } END { exit !(c && c < w) }' \
  && printf '%s\n' "$OUT" | grep -qxF -- '- [plain] src/a.ts:12 — the same injection' && printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** No' \
  && ok "(r8) a report with no Critical section gets one before Warnings, and Yes becomes No" || bad "(r8) $OUT"

OUT="$(bash "$TOOL" "$T/lead.md" '' --format report --why 'the plain review ran past 3600s')"
printf '%s\n' "$OUT" | grep -qxF 'Joined review: the plain review ran past 3600s, so this report is review-lead alone.' \
  && printf '%s\n' "$OUT" | grep -qxF '**Ready to merge?** With fixes' && printf '%s\n' "$OUT" | grep -qF '"plain_returned":false' \
  && ok "(r9) with no plain draft the report stands and its Notes say why" || bad "(r9) $OUT"

bash "$TOOL" "$T/lead.md" "$T/plain.md" --format bogus >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "(r10) an unknown --format is usage: exit 2" || bad "(r10) rc=$RC"

OUT="$(bash "$TOOL" "$T/lead.md" "$T/plain.md" --format report --plain-cost 0.3 --plain-wall '')"
printf '%s\n' "$OUT" | grep -qF "Plain session: \$0.30, ? s, returned." && printf '%s\n' "$OUT" | grep -qF '"plain_wall_s":null' \
  && ok "(r11) an empty --plain-wall is unknown: '? s' and null, never 0 or negative" || bad "(r11) $(printf '%s\n' "$OUT" | grep 'Plain session')"

echo "verdict-join-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"

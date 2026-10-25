#!/usr/bin/env bash
# corpus-selftest.sh — the shipped corpus passes `planted.py check`, and a copy that lacks any part a case
# must carry, or holds a marker, or falls short of a class or a P4 pattern, or a new case that misses the
# size floor or the distraction rule, or an upstream above 40% of the cases, or a runner case whose runner
# the gate cannot run, fails naming it. No network and no model.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
TD="${TMPDIR:-/tmp}"
T="$(mktemp -d "${TD%/}/corpus-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT

check() { python3 "$HERE/planted.py" --root "$1" check 2>&1; }
copy() { # copy <name> -> a fresh copy of the corpus at $T/<name>
  mkdir -p "$T/$1" && cp -R "$HERE/cases" "$HERE/overlays" "$HERE/NOTICE" "$T/$1/" && printf '%s' "$T/$1"
}
expect_red() { # expect_red <root> <what> <message the check must print>
  local out rc; out="$(check "$1")"; rc=$?
  if [ "$rc" -ne 0 ] && grep -qF -- "$3" <<<"$out"; then ok "$2"; else bad "$2: rc=$rc, wanted [$3], got: $(head -n 3 <<<"$out" | tr '\n' '|')"; fi
}
edit_case() { # edit_case <root> <id> <jq filter>
  jq "$3" "$1/cases/$2/case.json" > "$1/cases/$2/case.json.new" && mv "$1/cases/$2/case.json.new" "$1/cases/$2/case.json"
}

echo "== the shipped corpus =="
out="$(check "$HERE")"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "check: ok (P1 16, P2 4, P3 4, P4 10, P5 4, control 5; P4 patterns: rejects-held-input 2, dead-guard 2, two-hop-caller 1, omitted-option 1)" ] \
  && ok "the shipped corpus passes, with sixteen P1 cases and ten P4 cases that cover all four patterns" || bad "shipped corpus: rc=$rc $out"
hard="$(python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import planted, pathlib
for c in planted.load_cases(pathlib.Path(sys.argv[1])):
    t = c["truth"]
    if c["id"] in planted.FROZEN or t["class"] != "P1" or "expect_stop" in c:
        continue
    touched = planted.patch_files((c["dir"] / "patch.diff").read_text())
    outside = [l for l in t["locations"] if l["file"] not in touched and "start" in l]
    print(c["id"], len(outside))' "$HERE" | sort | tr '\n' ' ')"
[ "$hard" = "g8r2ub 1 k2v7ad 1 s4w9mf 1 x7c3nh 1 " ] \
  && ok "four new P1 cases each range their unmet AC in a file the patch does not touch" || bad "review-hard P1 cases: [$hard]"
runners="$(jq -r 'select(.expect_stop) | "\(.truth.class):\(.overlay)"' "$HERE"/cases/*/case.json | sort | uniq -c | tr -s ' ' | tr '\n' '|')"
[ "$runners" = " 4 P1:anuraghazra__github-readme-stats-jest|" ] \
  && ok "four P1 runner cases name the runner overlay and an expected stop" || bad "runner cases: [$runners]"
[ ! -e "$HERE/cases/d4p7sx" ] && ok "the control whose fix pads a negative year wrongly is gone, and five controls remain" || bad "d4p7sx is still in the corpus"
n_up="$(jq -r .upstream "$HERE"/cases/*/case.json | sort -u | grep -c .)"
[ "$n_up" -ge 2 ] && ok "the cases come from $n_up upstreams" || bad "upstreams: $n_up"

echo "== a missing part fails, naming the case =="
R="$(copy no-ticket)"; rm "$R/cases/f6t2gy/ticket.md"
expect_red "$R" "a case with no ticket" "f6t2gy: no ticket.md"
R="$(copy no-ac)"; printf '# A title\n\nSome text.\n' > "$R/cases/f6t2gy/ticket.md"
expect_red "$R" "a ticket with no AC block" "f6t2gy: ticket.md has no '## Acceptance criteria' block"
R="$(copy no-intent)"; printf '# Record\n\n| D-1 | a | b | user-answered | intent |\n' > "$R/cases/f6t2gy/record.md"
expect_red "$R" "a record with no Test intent line" "f6t2gy: record.md has no '## Test intent' section"
R="$(copy no-rows)"; printf '# Record\n\n## Test intent\n\nACs: AC-1\n' > "$R/cases/f6t2gy/record.md"
expect_red "$R" "a record with no decision row" "f6t2gy: record.md has no '| D-n |' row"
R="$(copy bad-intent)"; sed 's/^ACs: AC-1 AC-2$/ACs: AC-1 AC-9/' "$HERE/cases/f6t2gy/record.md" > "$R/cases/f6t2gy/record.md"
expect_red "$R" "a Test intent that lists an AC the ticket does not define" "the Test intent lists ['AC-9']"
R="$(copy no-patch)"; rm "$R/cases/f6t2gy/patch.diff"
expect_red "$R" "a case with no patch" "f6t2gy: no patch.diff"
R="$(copy no-plan)"; awk '/^diff --git a\/src\/plugin\/customParseFormat\/index.js/{on=1} on' "$HERE/cases/f6t2gy/patch.diff" > "$R/cases/f6t2gy/patch.diff"
expect_red "$R" "a patch that carries no plan" "f6t2gy: the patch does not add the plan at docs/plans/dayjs-1205-plan.md"
R="$(copy untagged-plan)"; sed 's/ \[AC-[0-9]*\]$//' "$HERE/cases/f6t2gy/patch.diff" > "$R/cases/f6t2gy/patch.diff"
expect_red "$R" "a plan with no test task tagged to an AC" "f6t2gy: the plan in the patch has no test task tagged to an AC"
R="$(copy no-overlay)"; rm "$R/overlays/iamkun__dayjs/review-context.md"
expect_red "$R" "an overlay with no review-context.md" "overlay iamkun__dayjs has no review-context.md"
R="$(copy no-config)"; rm "$R/overlays/iamkun__dayjs/config.json"
expect_red "$R" "an overlay with no config" "overlay iamkun__dayjs has no readable config.json"

echo "== case.json and the ground truth =="
R="$(copy no-base)"; edit_case "$R" f6t2gy 'del(.base)'
expect_red "$R" "a case with no base sha" "f6t2gy: base is not a 40-hex sha"
R="$(copy bad-license)"; edit_case "$R" f6t2gy '.license = "GPL-3.0"'
expect_red "$R" "an upstream under a license outside the allowed set" "f6t2gy: license 'GPL-3.0' is not one of"
R="$(copy bad-upstream)"; edit_case "$R" f6t2gy '.upstream = "git@github.com:iamkun/dayjs.git"'
expect_red "$R" "an upstream that is not a GitHub https URL" "f6t2gy: upstream is not an https://github.com/<owner>/<repo>.git URL"
R="$(copy no-class)"; edit_case "$R" a7t4yp '.truth.class = "P9"'
expect_red "$R" "a ground truth with an unknown class" "a7t4yp: truth.class 'P9' is not one of"
R="$(copy two-sentences)"; edit_case "$R" a7t4yp '.truth.description = "One. Two."'
expect_red "$R" "a description of more than one sentence" "a7t4yp: truth.description is not one sentence"
R="$(copy no-locations)"; edit_case "$R" a7t4yp '.truth.locations = []'
expect_red "$R" "a planted case with no location" "a7t4yp: truth has no locations"
R="$(copy outside)"; edit_case "$R" a7t4yp '.truth.locations = [{"file": "lib/core/AxiosHeaders.js", "start": 1, "end": 2, "side": "head"}]'
expect_red "$R" "a planted range outside every hunk of the patch" "a7t4yp: no ranged truth location falls inside a hunk of the patch"
R="$(copy path-level)"; edit_case "$R" a7t4yp '.truth.locations += [{"file": "lib/defaults/index.js", "side": "head"}]'
out="$(check "$R")"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^check: ok' <<<"$out" && ok "a path-level location on a file outside every hunk is accepted" || bad "path-level: rc=$rc $(head -n 3 <<<"$out" | tr '\n' '|')"
R="$(copy path-no-file)"; edit_case "$R" a7t4yp '.truth.locations += [{"side": "head"}]'
expect_red "$R" "a path-level location with no file" "a7t4yp: truth location {'side': 'head'} is not {file, side: head|base}"
R="$(copy path-only)"; edit_case "$R" a7t4yp '.truth.locations = [{"file": "lib/core/AxiosHeaders.js", "side": "head"}]'
expect_red "$R" "a truth with only a path-level location, which no hunk holds" "a7t4yp: no ranged truth location falls inside a hunk of the patch"
R="$(copy no-row)"; edit_case "$R" a7t4yp '.truth.row = "D-9"'
expect_red "$R" "a P2 case whose row is not in the record" "a7t4yp: truth.row 'D-9' is not a D-n row of the record"

echo "== no marker =="
R="$(copy marker)"; printf '\nThis change was planted for the bench.\n' >> "$R/cases/f6t2gy/ticket.md"
expect_red "$R" "a ticket that says it is planted" "f6t2gy: ticket.md carries a marker: planted"
R="$(copy leaked)"; jq -r .truth.description "$HERE/cases/a7t4yp/case.json" >> "$R/cases/a7t4yp/record.md"
expect_red "$R" "a record that carries the ground-truth description" "a7t4yp: record.md carries a marker: the ground-truth description"
R="$(copy class-id)"; mv "$R/cases/f6t2gy" "$R/cases/p1case"
expect_red "$R" "a case id that names a class" "p1case: the case id reads as a class name"
R="$(copy long-id)"; mv "$R/cases/f6t2gy" "$R/cases/dayjs-1209"
expect_red "$R" "a case id that names its upstream" "dayjs-1209: the case id is not six lowercase letters or digits"

echo "== the corpus as a whole =="
R="$(copy short)"; rm -r "$R/cases/a7t4yp"
expect_red "$R" "three P2 cases" "corpus: class P2 has 3 cases, fewer than 4"
R="$(copy few-controls)"; rm -r "$R/cases/f6t2gy"
expect_red "$R" "four clean controls" "corpus: 4 clean controls, fewer than 5"
R="$(copy notice)"; grep -v 'github.com/axios/axios' "$HERE/NOTICE" > "$R/NOTICE"
expect_red "$R" "a NOTICE that omits an upstream" "corpus: NOTICE does not name https://github.com/axios/axios"

echo "== the P4 patterns =="
R="$(copy no-two-hop)"; rm -r "$R/cases/b3v8qn"
expect_red "$R" "a corpus whose only two-hop case is gone" "corpus: no P4 case has pattern two-hop-caller"
R="$(copy no-omitted)"; rm -r "$R/cases/q7d2hv"
expect_red "$R" "a corpus whose only omitted-option case is gone" "corpus: no P4 case has pattern omitted-option"
R="$(copy no-pattern)"; edit_case "$R" e7k3wb 'del(.truth.pattern)'
expect_red "$R" "a new P4 case with no pattern" "e7k3wb: truth.pattern None is not one of"
R="$(copy odd-pattern)"; edit_case "$R" e7k3wb '.truth.pattern = "far-caller"'
expect_red "$R" "a new P4 case with an unknown pattern" "e7k3wb: truth.pattern 'far-caller' is not one of"
R="$(copy pattern-on-p2)"; edit_case "$R" a7t4yp '.truth.pattern = "dead-guard"'
expect_red "$R" "a pattern on a case outside P4" "a7t4yp: only a P4 case names truth.pattern"

echo "== distractions =="
R="$(copy no-distraction)"; edit_case "$R" q7d2hv 'del(.distractions)'
expect_red "$R" "a new case with no distraction" "q7d2hv: case.json has no distractions"
R="$(copy empty-distractions)"; edit_case "$R" q7d2hv '.distractions = []'
expect_red "$R" "a new case with an empty distraction list" "q7d2hv: case.json has no distractions"
R="$(copy near-truth)"; edit_case "$R" q7d2hv '.distractions[0].start = 221 | .distractions[0].end = 224'
expect_red "$R" "a distraction within WINDOW of a truth range" "q7d2hv: distraction packages/compiler-sfc/src/script/resolveType.ts:221-224 sits within 3 lines of a truth location"
R="$(copy edge-truth)"; edit_case "$R" e7k3wb '.distractions[0] = {"file": "packages/runtime-core/src/renderer.ts", "start": 1063, "end": 1069, "side": "head", "why": "A line just outside the reach of the truth."}'
out="$(check "$R")"; rc=$?
[ "$rc" -eq 0 ] && ok "a distraction four lines from a truth range is accepted" || bad "edge-truth: rc=$rc $(head -n 3 <<<"$out" | tr '\n' '|')"
R="$(copy edge-near)"; edit_case "$R" e7k3wb '.distractions[0] = {"file": "packages/runtime-core/src/renderer.ts", "start": 1063, "end": 1070, "side": "head", "why": "A line just inside the reach of the truth."}'
expect_red "$R" "a distraction three lines from a truth range" "e7k3wb: distraction packages/runtime-core/src/renderer.ts:1063-1070 sits within 3 lines of a truth location"
R="$(copy off-hunk)"; edit_case "$R" q7d2hv '.distractions[0].start = 700 | .distractions[0].end = 701'
expect_red "$R" "a distraction outside every hunk" "q7d2hv: distraction packages/compiler-sfc/src/script/resolveType.ts:700-701 falls inside no hunk of the patch"
R="$(copy two-whys)"; edit_case "$R" q7d2hv '.distractions[0].why = "It is fine. It is correct."'
expect_red "$R" "a distraction whose why is two sentences" "q7d2hv: distraction packages/compiler-sfc/src/script/resolveType.ts:292-295 has no one-sentence why"

echo "== the size floor =="
R="$(copy short-patch)"; awk '/^diff --git/{skip = ($0 ~ /__tests__/)} !skip' "$HERE/cases/e7k3wb/patch.diff" > "$R/cases/e7k3wb/patch.diff"; edit_case "$R" e7k3wb 'del(.distractions)'
expect_red "$R" "a new case cut to its source hunks" "e7k3wb: the patch changes 25 lines outside docs/plans/, fewer than 80"
R="$(copy unfrozen)"; cp -R "$R/cases/f6t2gy" "$R/cases/z9w4xa"
expect_red "$R" "a copy of a frozen under-80 case under a new id" "z9w4xa: the patch changes"
out="$(check "$HERE")"
n_small="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import planted, pathlib; print(sum(1 for c in planted.load_cases(pathlib.Path(sys.argv[1])) if c["id"] in planted.FROZEN and planted.changed_lines((c["dir"] / "patch.diff").read_text()) < planted.MIN_CHANGED_LINES))' "$HERE")"
[ "$n_small" -ge 20 ] && grep -q '^check: ok' <<<"$out" && ! grep -q 'fewer than 80' <<<"$out" \
  && ok "the $n_small frozen cases under 80 lines still pass" || bad "frozen: $n_small under 80, $out"

echo "== the new P1 cases meet the size floor and the distraction rule =="
R="$(copy p1-short)"; awk '/^diff --git/{skip = ($0 ~ / b\/readme\.md$/)} !skip' "$HERE/cases/s4w9mf/patch.diff" > "$R/cases/s4w9mf/patch.diff"
expect_red "$R" "a review-hard P1 case cut below 80 changed lines" "s4w9mf: the patch changes 79 lines outside docs/plans/, fewer than 80"
R="$(copy p1-no-distraction)"; edit_case "$R" k2v7ad 'del(.distractions)'
expect_red "$R" "a review-hard P1 case with no distraction" "k2v7ad: case.json has no distractions"
R="$(copy runner-no-distraction)"; edit_case "$R" t3h7we '.distractions = []'
expect_red "$R" "a runner P1 case with no distraction" "t3h7we: case.json has no distractions"

echo "== no upstream above 40% of the corpus =="
R="$(copy cap-41)"; rm -r "$R/cases/k2v7ad" "$R/cases/s4w9mf" "$R/cases/x7c3nh" "$R/cases/g8r2ub"
expect_red "$R" "dayjs at 16 of 39 cases" "corpus: https://github.com/iamkun/dayjs holds 16 of 39 cases (41.0%), more than 40%"
R="$(copy cap-40)"; rm -r "$R/cases/k2v7ad" "$R/cases/s4w9mf" "$R/cases/x7c3nh"
out="$(check "$R")"; rc=$?
[ "$rc" -eq 0 ] && ! grep -q 'more than 40%' <<<"$out" && ok "dayjs at exactly 16 of 40 cases passes" || bad "cap at 40%: rc=$rc $(head -n 3 <<<"$out" | tr '\n' '|')"
R="$(copy cap-readme)"; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do cp -R "$R/cases/g8r2ub" "$R/cases/g8r$(printf '%03d' "$i" | tr 0-9 a-j)"; done
out="$(check "$R")"; rc=$?
[ "$rc" -ne 0 ] && [ "$out" = "check: corpus: https://github.com/anuraghazra/github-readme-stats holds 34 of 63 cases (54.0%), more than 40%" ] \
  && ok "readme-stats at 34 of 63 cases fails on its share alone" || bad "readme-stats cap: rc=$rc $(head -n 3 <<<"$out" | tr '\n' '|')"

echo "== a runner case declares a runner the gate can run =="
RO=overlays/anuraghazra__github-readme-stats-jest/config.json
R="$(copy no-command)"; jq 'del(.commands[].testRunners[0].command)' "$HERE/$RO" > "$R/$RO"
expect_red "$R" "a runner overlay whose entry has no command" "d6m1zo: testRunners[0] of overlay anuraghazra__github-readme-stats-jest has no command"
R="$(copy exit-format)"; jq '.commands[].testRunners[0].format = "exit"' "$HERE/$RO" > "$R/$RO"
expect_red "$R" "a runner overlay whose format is exit" "a9n5jx: testRunners[0] of overlay anuraghazra__github-readme-stats-jest has format 'exit', not jest-json"
R="$(copy no-format)"; jq 'del(.commands[].testRunners[0].format)' "$HERE/$RO" > "$R/$RO"
expect_red "$R" "a runner overlay with no format" "v2q8ci: testRunners[0] of overlay anuraghazra__github-readme-stats-jest has format None, not jest-json"
R="$(copy bare-tag)"
# shellcheck disable=SC2016  # the backticks are the plan's case quotes, matched literally
sed 's/(tests\/fetchRepo\.test\.js::`Test fetchRepo > should fetch the repo through the token rotation`)/(tests\/fetchRepo.test.js)/' "$HERE/cases/t3h7we/patch.diff" > "$R/cases/t3h7we/patch.diff"
expect_red "$R" "a runner case whose plan tags a bare file" "t3h7we: the plan tags tests/fetchRepo.test.js for AC-3 as a bare file, but a jest-json runner judges named tests"
R="$(copy unmatched-tag)"; sed 's/(tests\/fetchRepo\.test\.js::/(spec\/fetchRepo.test.js::/' "$HERE/cases/t3h7we/patch.diff" > "$R/cases/t3h7we/patch.diff"
expect_red "$R" "a runner case whose plan tags a path no when glob matches" "t3h7we: the plan tags spec/fetchRepo.test.js for AC-3, which no when glob of overlay anuraghazra__github-readme-stats-jest's testRunners matches"
R="$(copy no-expect)"; edit_case "$R" d6m1zo 'del(.expect_stop)'
expect_red "$R" "a case on the runner overlay with no expected stop" "d6m1zo: overlay anuraghazra__github-readme-stats-jest declares testRunners, but case.json names no expect_stop"
R="$(copy expect-no-runner)"; edit_case "$R" d6m1zo '.overlay = "anuraghazra__github-readme-stats"'
expect_red "$R" "an expected stop on an overlay with no runner" "d6m1zo: case.json names expect_stop, but overlay anuraghazra__github-readme-stats declares no testRunners"
R="$(copy odd-expect)"; edit_case "$R" d6m1zo '.expect_stop = "plan_coverage"'
expect_red "$R" "an expected stop the gate does not make" "d6m1zo: expect_stop 'plan_coverage' is not one of fails_without_change"

echo "corpus-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"

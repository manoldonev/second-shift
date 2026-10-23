#!/usr/bin/env bash
# score-selftest.sh — the scorer on canned reviews with a canned judge, no model: right, wrong, harm and noise
# per class and arm; the three-line window; the judge asked only about findings inside a planted range; a P2 row
# by its id; a P5 [note]; a gate stop; an unscorable verdict counted apart and never as an approve; and the gate,
# which reads every class but P2.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
TD="${TMPDIR:-/tmp}"
T="$(mktemp -d "${TD%/}/score-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
R="$T/root"
SHA=0123456789abcdef0123456789abcdef01234567

mkcase() { # mkcase <id> <truth json>
  mkdir -p "$R/cases/$1"
  printf '{"upstream": "https://github.com/acme/tool.git", "issue": 1, "pr": 2, "truth": %s}\n' "$2" > "$R/cases/$1/case.json"
  printf '# Decision record\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | Parsing | Split on spaces. | user-answered | intent |\n| D-2 | Errors | Throw a TypeError. | user-answered | intent |\n\n## Test intent\n\nACs: AC-1\n\nAC-1: it splits\n' > "$R/cases/$1/record.md"
}
mkcase p1case '{"class": "P1", "description": "The parser drops the third token.", "locations": [{"file": "src/a.js", "start": 10, "end": 12, "side": "head"}]}'
mkcase p2case '{"class": "P2", "row": "D-2", "description": "The code returns null where the record decides a TypeError.", "locations": [{"file": "src/b.js", "start": 5, "end": 5, "side": "head"}]}'
mkcase p3case '{"class": "P3", "description": "An existing expectation on the empty input is deleted.", "locations": [{"file": "test/c.test.js", "start": 20, "end": 20, "side": "head"}, {"file": "test/c.test.js", "start": 18, "end": 22, "side": "base"}]}'
mkcase p4case '{"class": "P4", "description": "The renamed export breaks the existing caller in src/e.js.", "locations": [{"file": "src/d.js", "start": 30, "end": 31, "side": "head"}]}'
mkcase p5case '{"class": "P5", "description": "The new helper uses a string literal where the repo uses the unit constants.", "locations": [{"file": "src/e.js", "start": 7, "end": 7, "side": "head"}]}'
mkcase ctcase '{"class": "control"}'

V="$T/v"; mkdir -p "$V"
rows() { printf '## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n| D-1 | %s | src/a.js:1 splits. |\n| D-2 | %s | src/b.js:5 throws. |\n\n' "$1" "$2"; }
lane_approve() { printf 'verdict: approve\nreviewed: %s\n\n## Summary\nMergeable as it is.\nNothing to do.\n\n' "$SHA"; rows honored honored; printf '## Findings\n\n%s\n' "${1:-None.}"; }
lane_back() { # lane_back <D-2 score> <findings>
  printf 'verdict: needs-work\nreviewed: %s\n\n## Summary\nNot mergeable yet.\n' "$SHA"
  [ "$1" = honored ] || printf 'D-2 %s.\n' "$1"
  printf 'Fix the blockers.\n\n'; rows honored "$1"; printf '## Findings\n\n%s\n' "$2"
}
B() { printf -- '- [blocker] %s %s — %s\n  Scenario: an input → a wrong outcome\n  Fix: change it.\n' "$1" "$2" "$3"; }
lane_back honored "$(B B1 src/a.js:14 'the third token is dropped.'; B B2 src/z.js:1 'an unrelated worry.')" > "$V/lane-p1.md"
lane_back violated "$(B B1 'D-2' 'violated: the code returns null.')" > "$V/lane-p2.md"
lane_approve > "$V/lane-p4.md"
lane_approve '- [note] N1 src/e.js:7 — a string literal where the repo uses the unit constants.' > "$V/lane-p5.md"
lane_back honored "$(B B1 src/q.js:3 'a worry.')" > "$V/lane-ct.md"
printf 'verdict: approve\n\n## Findings\n\nNone.\n' > "$V/lane-bad.md"
printf 'verdict: needs-work\n## Findings\n- [blocker] B1 src/a.js:16 — the third token is dropped.\n' > "$V/plain-p1.md"
printf 'verdict: approve\n## Findings\nNone.\n' > "$V/plain-p2.md"
printf 'verdict: needs-work\n## Findings\n- [blocker] B1 test/c.test.js:19 — an expectation was deleted.\n' > "$V/plain-p3.md"
printf 'verdict: needs-work\n## Findings\n- [blocker] B1 src/d.js:30 — a style worry.\n' > "$V/plain-p4.md"
printf 'verdict: approve\n## Findings\nNone.\n' > "$V/plain-p5.md"
printf 'verdict: approve\n## Findings\nNone.\n' > "$V/plain-ct.md"
printf 'verdict: approve\n## Findings\n- [blocker] B1 src/a.js:11 — the third token is dropped.\n' > "$V/plain-bad.md"

r() { printf '{"arm": "%s", "case": "%s", "run": %s, "status": "%s", "text": %s}' "$1" "$2" "$3" "$4" "$(if [ -n "${5:-}" ]; then jq -Rs . < "$V/$5"; else echo null; fi)"; }
{ echo "["
  r lane p1case 1 ok lane-p1.md; echo ","; r lane p2case 1 ok lane-p2.md; echo ","; r lane p3case 1 gate-stop; echo ","
  r lane p4case 1 ok lane-p4.md; echo ","; r lane p5case 1 ok lane-p5.md; echo ","; r lane ctcase 1 ok lane-ct.md; echo ","
  r lane p1case 2 ok lane-bad.md; echo ","
  r plain p1case 1 ok plain-p1.md; echo ","; r plain p2case 1 ok plain-p2.md; echo ","; r plain p3case 1 ok plain-p3.md; echo ","
  r plain p4case 1 ok plain-p4.md; echo ","; r plain p5case 1 ok plain-p5.md; echo ","; r plain ctcase 1 ok plain-ct.md; echo ","
  r plain p1case 2 ok plain-bad.md
  echo "]"; } > "$T/reviews.json"
j() { printf '{"golden": "%s", "candidate": "%s", "match": %s}' "$1" "$2" "$3"; }
judge() { # judge <plain's P3 match: true|false>
  { echo "["
    j "The parser drops the third token." "src/a.js:14 — the third token is dropped. Scenario: an input → a wrong outcome Fix: change it." true; echo ","
    j "The new helper uses a string literal where the repo uses the unit constants." "src/e.js:7 — a string literal where the repo uses the unit constants." true; echo ","
    j "An existing expectation on the empty input is deleted." "test/c.test.js:19 — an expectation was deleted." "$1"; echo ","
    j "The renamed export breaks the existing caller in src/e.js." "src/d.js:30 — a style worry." false; echo ","
    j "The parser drops the third token." "src/a.js:16 — the third token is dropped." true
    echo "]"; } > "$T/judge-$1.json"
}
judge true; judge false
score() { python3 "$HERE/planted.py" --root "$R" score --reviews "$T/reviews.json" --judge "$T/judge-$1.json" > "$T/out-$1.json" 2> "$T/err-$1.txt"; }
s() { jq -c --arg a "$1" --arg c "$2" --argjson n "$3" '.records[] | select(.arm == $a and .case == $c and .run == $n) | .score | if . == null then null else [.right, .wrong, .harm, .noise, .how] end' "$T/out-true.json"; }

echo "== one review per class and arm =="
score true; rc=$?
[ "$rc" -eq 0 ] && ok "score exits 0" || bad "score rc=$rc: $(tail -n 5 "$T/err-true.txt")"
[ "$(s lane p1case 1)" = '[1,0,0,1,"blocker"]' ] && ok "lane P1: a [blocker] two lines past the range, which the judge matches, is right; an unmatched [blocker] is noise" || bad "lane P1: $(s lane p1case 1)"
[ "$(s lane p2case 1)" = '[1,0,0,0,"blocker"]' ] && ok "lane P2: a blocker that names the planted row is right and is not noise" || bad "lane P2: $(s lane p2case 1)"
[ "$(s lane p3case 1)" = '[1,0,0,0,"gate"]' ] && ok "lane P3: a gate that stops the case is right" || bad "lane P3: $(s lane p3case 1)"
[ "$(s lane p4case 1)" = '[0,1,0,0,""]' ] && ok "lane P4: an approve of a planted case is wrong" || bad "lane P4: $(s lane p4case 1)"
[ "$(s lane p5case 1)" = '[1,0,0,0,"note"]' ] && ok "lane P5: a matching [note] on an approve is right, and the approve is not wrong" || bad "lane P5: $(s lane p5case 1)"
[ "$(s lane ctcase 1)" = '[0,0,1,0,"blocker"]' ] && ok "lane control: a [blocker] is harm" || bad "lane control: $(s lane ctcase 1)"
[ "$(s plain p1case 1)" = '[0,0,0,1,""]' ] && ok "plain P1: a [blocker] four lines past the range is not judged, misses and is noise; a needs-work is not wrong" || bad "plain P1: $(s plain p1case 1)"
[ "$(s plain p2case 1)" = '[0,1,0,0,""]' ] && ok "plain P2: an approve is wrong" || bad "plain P2: $(s plain p2case 1)"
[ "$(s plain p3case 1)" = '[1,0,0,0,"blocker"]' ] && ok "plain P3: a [blocker] inside the base-side range of a deletion is right" || bad "plain P3: $(s plain p3case 1)"
[ "$(s plain p4case 1)" = '[0,0,0,1,""]' ] && ok "plain P4: a [blocker] in range that the judge rejects is noise" || bad "plain P4: $(s plain p4case 1)"
[ "$(s plain p5case 1)" = '[0,0,0,0,""]' ] && ok "plain P5: an approve with no finding is neither right nor wrong" || bad "plain P5: $(s plain p5case 1)"
[ "$(s plain ctcase 1)" = '[0,0,0,0,""]' ] && ok "plain control: an approve is no harm" || bad "plain control: $(s plain ctcase 1)"
[ "$(s lane p1case 2)" = null ] && [ "$(jq -r '.records[] | select(.arm == "lane" and .run == 2) | .status' "$T/out-true.json")" = unscorable ] \
  && ok "a lane verdict that fails verdict-check.sh is unscorable" || bad "lane bad: $(jq -c '.records[] | select(.arm == "lane" and .run == 2)' "$T/out-true.json")"
[ "$(jq -r '.records[] | select(.arm == "plain" and .run == 2) | .status' "$T/out-true.json")" = unscorable ] \
  && ok "a plain approve that carries a [blocker] is unscorable" || bad "plain bad: $(jq -c '.records[] | select(.arm == "plain" and .run == 2)' "$T/out-true.json")"
[ "$(jq -c '[.arms.lane["2"].classes.P1.unscorable, .arms.lane["2"].classes.P1.wrong, .arms.plain["2"].classes.P1.unscorable, .arms.plain["2"].classes.P1.wrong]' "$T/out-true.json")" = '[1,0,1,0]' ] \
  && ok "an unscorable run is counted apart and never as an approve" || bad "unscorable tally: $(jq -c '.arms.lane["2"].classes.P1' "$T/out-true.json")"
[ "$(jq -c '[.judge_calls[][1]] | sort' "$T/out-true.json")" = '["src/a.js:14 — the third token is dropped. Scenario: an input → a wrong outcome Fix: change it.","src/d.js:30 — a style worry.","src/e.js:7 — a string literal where the repo uses the unit constants.","test/c.test.js:19 — an expectation was deleted."]' ] \
  && ok "the judge is asked only about the four findings inside a planted range, each with its continuation lines"|| bad "judge calls: $(jq -c '.judge_calls' "$T/out-true.json")"

echo "== the tally and the gate =="
[ "$(jq -c '.arms.lane["1"] | [.net, .gate_net, .p1_net]' "$T/out-true.json")" = '[2,1,1]' ] && ok "lane run 1: net 2, without P2 1, on P1 1" || bad "lane nets: $(jq -c '.arms.lane["1"] | [.net, .gate_net, .p1_net]' "$T/out-true.json")"
[ "$(jq -c '.arms.plain["1"] | [.net, .gate_net, .p1_net]' "$T/out-true.json")" = '[0,1,0]' ] && ok "plain run 1: net 0, without P2 1, on P1 0" || bad "plain nets: $(jq -c '.arms.plain["1"] | [.net, .gate_net, .p1_net]' "$T/out-true.json")"
[ "$(jq -c '.arms.lane["1"].classes.control' "$T/out-true.json")" = '{"n":1,"right":0,"wrong":0,"harm":1,"noise":0,"unscorable":0}' ] \
  && ok "harm counts once per control" || bad "control tally: $(jq -c '.arms.lane["1"].classes.control' "$T/out-true.json")"
[ "$(jq -c '.gate | [.pass, .lane_worst, .plain_best]' "$T/out-true.json")" = '[false,0,1]' ] \
  && ok "the gate fails when the lane's worst run does not beat plain's best; P2, where the lane leads, is left out" || bad "gate: $(jq -c '.gate' "$T/out-true.json")"
score false
[ "$(jq -c '.gate | [.pass, .lane_worst, .plain_best, .lane_worst_p1, .plain_best_p1]' "$T/out-false.json")" = '[false,0,0,0,0]' ] \
  && ok "a run whose one review is unscorable nets 0, and a tie with plain's best fails the gate" || bad "gate 2: $(jq -c '.gate' "$T/out-false.json")"
jq 'map(select(.run == 1))' "$T/reviews.json" > "$T/reviews-1.json" && mv "$T/reviews-1.json" "$T/reviews.json"
score false
[ "$(jq -c '.gate | [.pass, .lane_worst, .plain_best, .lane_worst_p1, .plain_best_p1]' "$T/out-false.json")" = '[true,1,0,1,0]' ] \
  && ok "the gate passes when the lane's worst run beats plain's best, overall without P2 and on P1" || bad "gate 3: $(jq -c '.gate' "$T/out-false.json")"
grep -q '^gate: pass' "$T/err-false.txt" && ok "the report prints the gate" || bad "report: $(tail -n 2 "$T/err-false.txt")"

echo "score-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"

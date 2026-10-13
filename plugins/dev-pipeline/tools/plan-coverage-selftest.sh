#!/usr/bin/env bash
# plan-coverage-selftest.sh — behavioral selftest for tools/plan-coverage.sh (#1039).
#
# INVARIANTS GUARDED: a plan tagging every AC the record does not exempt passes (AC-2); an uncovered AC,
# a tag the record does not define and every task line out of the grammar are each red and named, all of
# them in one report (AC-3, D-4); PM-n never enters the set, and a record with no Test intent or no AC
# block is not-applicable, never a pass (AC-4, D-3); an exempt AC is reported exempt, tagged or not,
# never covered and never red (D-8); ids are exact strings over non-contiguous sets (D-13); CR line ends
# are stripped (D-15); a missing plan is red, an unreadable input is exit 2. #1040: a holds or unchecked
# AC is tagged like a behavior and reported in its form (D-4 D-11); a tagged task naming no test file is
# red (D-3); --files maps each tagged AC to its files for run.sh's fails-without-the-change leg (D-7).
#
# Operator-safe: files only, no network, no git. Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/plan-coverage.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/plan-coverage-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# a v4 record whose test intent names AC-1..3 and AC-8 (a slice keeps its parent's ids), AC-3 exempt
record() { # record <file> <the Test intent section body>
  printf '# Intake receipt — #42 fixture\n\nReceipt: v4\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | a | b | user-answered | intent |\n\n## Test intent\n\n%s\n\n## Knowledge source\n\nKnowledge source: none declared\n' "$2" > "$1"
}
record "$T/rec.md" $'ACs: AC-1 AC-2 AC-3 AC-8\n\nAC-1: a duplicate import answers 409\nAC-2: an upload above 50 MB is refused\nAC-3: exempt — docs only\nAC-8: the scheduler runs the check'
plan() { printf '%s\n' "$@" > "$T/plan.md"; }
run() { OUT="$(bash "$TOOL" "$@" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"; }
has() { grep -qF -- "$1" <<< "$OUT"; }

echo "== plan-coverage.sh =="

# (pc1) AC-2: every AC tagged on a test task → 0; one id per bracket, several on one task, [x] ticked, prose between
plan '# Plan' '' '## 1. Tests' '' 'Prose the check never reads.' \
  '- [ ] 1.1 duplicate import answers 409 (src/import.spec.ts) [AC-1]' \
  '- [x] 1.2 size limit and the scheduler case (src/limit.spec.ts, run-selftest.sh) [AC-2] [AC-8]' \
  '' '## 2. Implementation' '' '- [ ] 2.1 the worker (src/import.ts)'
run "$T/rec.md" "$T/plan.md"
[ "$RC" -eq 0 ] && has 'plan-coverage: AC-1 covered (task 1.1)' && has 'plan-coverage: AC-2 covered (task 1.2)' && has 'plan-coverage: AC-8 covered (task 1.2)' \
  && has 'plan-coverage: pass — 3 covered, 1 exempt' \
  && ok "(pc1) AC-2: every non-exempt AC tagged → 0, each named with its task" || bad "(pc1) rc=$RC out=$OUT err=$ERR"
has 'plan-coverage: AC-3 exempt' && ! has 'AC-3 covered' && ok "(pc1) D-8: the untagged exempt AC is reported exempt, not covered" || bad "(pc1) D-8: $OUT"

# (pc2) D-8: an exempt AC the plan tags anyway — allowed, 'exempt (tagged)', never covered; an AC on two tasks lists both
plan '- [ ] 1.1 a (a.spec.ts) [AC-1] [AC-3]' '- [ ] 1.2 b (b.spec.ts) [AC-2] [AC-8]' '- [ ] 1.3 c (c.spec.ts) [AC-1]'
run "$T/rec.md" "$T/plan.md"
[ "$RC" -eq 0 ] && has 'plan-coverage: AC-3 exempt (tagged: task 1.1)' && has 'plan-coverage: AC-1 covered (task 1.1, 1.3)' && has 'pass — 3 covered, 1 exempt' \
  && ok "(pc2) D-8: a tagged exempt AC is 'exempt (tagged)', not covered and not red" || bad "(pc2) rc=$RC out=$OUT"

# (pc3) AC-3: an AC with no test task, and a tag the record does not define — red, each named, both in one report
plan '- [ ] 1.1 a (a.spec.ts) [AC-1]' '- [ ] 1.2 b (b.spec.ts) [AC-2] [AC-9]'
run "$T/rec.md" "$T/plan.md"
[ "$RC" -eq 1 ] && has 'plan-coverage: RED: AC-8 has no test task' && has 'plan-coverage: RED: task 1.2 tags AC-9, which the record' && has 'RED — 2 problem(s)' \
  && ok "(pc3) AC-3: the uncovered AC-8 and the undefined AC-9 are both named → 1" || bad "(pc3) rc=$RC out=$OUT"
# D-13: ids are exact strings — AC-08 is not AC-8, and is undefined
plan '- [ ] 1.1 a (a.spec.ts) [AC-1] [AC-2] [AC-08]'
run "$T/rec.md" "$T/plan.md"
[ "$RC" -eq 1 ] && has 'RED: AC-8 has no test task' && has 'tags AC-08, which the record' \
  && ok "(pc3) D-13: [AC-08] covers nothing and is undefined → 1" || bad "(pc3) D-13: rc=$RC out=$OUT"

# (pc4) D-4: every '- [' line out of the grammar is red by line number, never skipped — and a tag on one is not counted
plan '## 1. Tests' \
  '- [ ] 1.1 comma list (a.spec.ts) [AC-1, AC-2]' \
  '  - [ ] 1.2 indented (b.spec.ts) [AC-8]' \
  '- [ ] 1.3 [AC-1] tag before the description (c.spec.ts)' \
  '- [ ] tests with no number (d.spec.ts) [AC-2]' \
  '- [ ] 1.5 [AC-1]' \
  '- [] 1.6 no space in the box [AC-2]' \
  '- [ ] 1.7 lower case (e.spec.ts) [ac-2]'
run "$T/rec.md" "$T/plan.md"
n_unparse="$(grep -c 'is unparseable' <<< "$OUT")"; named=1
for l in 2 3 4 5 6 7 8; do has "RED: line $l is unparseable" || named=0; done
[ "$RC" -eq 1 ] && [ "$n_unparse" -eq 7 ] && [ "$named" -eq 1 ] \
  && has 'RED: AC-1 has no test task' && has 'RED: AC-8 has no test task' \
  && ok "(pc4) D-4: seven malformed task lines each named by line number, none of their tags counted → 1" || bad "(pc4) rc=$RC n=$n_unparse out=$OUT"

# (pc5) AC-4: PM-n never enters the set — a [PM-1] in a description is neither covered nor undefined
plan '- [ ] 1.1 a, and the post-merge item [PM-1] it relates to (a.spec.ts) [AC-1] [AC-2] [AC-8]'
run "$T/rec.md" "$T/plan.md"
[ "$RC" -eq 0 ] && ! has 'PM-1' && ok "(pc5) AC-4: a PM-1 tag is not counted, covered or undefined → 0" || bad "(pc5) rc=$RC out=$OUT"
record "$T/rec-pm.md" $'ACs: AC-1 PM-1\n\nAC-1: x'
run "$T/rec-pm.md" "$T/plan.md"
[ "$RC" -eq 2 ] && grep -qF "'PM-1', which is not an AC id" <<< "$ERR" && ok "(pc5) AC-4: a record listing PM-1 in 'ACs:' is not read as an AC set → 2" || bad "(pc5) rc=$RC err=$ERR"

# (pc6) AC-4 / D-3: no AC block → not-applicable (3), named, never a pass — whatever the plan holds
record "$T/rec-none.md" 'ACs: none — the ticket has no AC block'
run "$T/rec-none.md" "$T/no-plan.md"
[ "$RC" -eq 3 ] && [ "$OUT" = 'plan-coverage: not-applicable — the ticket has no AC block' ] && ! has 'pass' \
  && ok "(pc6) AC-4: 'ACs: none' → 3, not-applicable, distinct from a pass" || bad "(pc6) rc=$RC out=$OUT"
# D-3: a record written before v4 carries no Test intent → 3, naming its version
printf '# record\n\nReceipt: v3\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | a | b | user-answered | intent |\n' > "$T/rec-v3.md"
run "$T/rec-v3.md" "$T/no-plan.md"
[ "$RC" -eq 3 ] && [ "$OUT" = 'plan-coverage: not-applicable — record v3 carries no Test intent' ] \
  && ok "(pc6) D-3: a v3 record → 3, 'record v3 carries no Test intent'" || bad "(pc6) rc=$RC out=$OUT"
printf '# record\n\n## Decision Ledger\n' > "$T/rec-v1.md"
run "$T/rec-v1.md" "$T/no-plan.md"
[ "$RC" -eq 3 ] && has 'record v1 carries no Test intent' && ok "(pc6) a record with no version line is v1" || bad "(pc6) v1: rc=$RC out=$OUT"
# the section is read with the scheduler's heading rule: a '## Test intent notes' heading is not it
printf '# record\n\nReceipt: v4\n\n## Test intent notes\n\nACs: AC-1\n' > "$T/rec-notes.md"
run "$T/rec-notes.md" "$T/no-plan.md"
[ "$RC" -eq 3 ] && ok "(pc6) '## Test intent notes' is not the section → 3" || bad "(pc6) notes: rc=$RC out=$OUT"

# (pc7) D-7: a missing plan is red, named — the build can fix it with a commit
run "$T/rec.md" "$T/no-plan.md"
[ "$RC" -eq 1 ] && has "plan-coverage: RED: no plan — $T/no-plan.md does not exist" && ok "(pc7) a missing plan → 1, named" || bad "(pc7) rc=$RC out=$OUT"
# an empty plan names every AC it leaves uncovered
: > "$T/empty.md"
run "$T/rec.md" "$T/empty.md"
[ "$RC" -eq 1 ] && has 'RED: AC-1 has no test task' && has 'RED: AC-2 has no test task' && has 'RED: AC-8 has no test task' && ! has 'AC-3 has no' \
  && ok "(pc7) an empty plan names every non-exempt AC → 1" || bad "(pc7) empty: rc=$RC out=$OUT"

# (pc8) D-15: CRLF line ends in the record and the plan are stripped before matching
tr -d '\r' < "$T/rec.md" | sed 's/$/\r/' > "$T/rec-crlf.md"
printf '%s\r\n' '- [ ] 1.1 a (a.spec.ts) [AC-1] [AC-2]' '- [ ] 1.2 b (b.spec.ts) [AC-8]' > "$T/plan-crlf.md"
run "$T/rec-crlf.md" "$T/plan-crlf.md"
[ "$RC" -eq 0 ] && has 'pass — 3 covered, 1 exempt' && ok "(pc8) D-15: CRLF record and plan → 0" || bad "(pc8) rc=$RC out=$OUT err=$ERR"

# (pc9) a process substitution is a readable input, as run.sh hands the record
OUT="$(bash "$TOOL" <(cat "$T/rec.md") "$T/plan-crlf.md" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "(pc9) the record through a pipe (/dev/fd) is read → 0" || bad "(pc9) rc=$RC out=$OUT"

# (pc10) exit 2: an unreadable record, a record whose Test intent has no 'ACs:' line, a plan that is a directory, usage
run "$T/no-such-record.md" "$T/plan.md"; r1=$RC
record "$T/rec-noacs.md" 'AC-1: x'
run "$T/rec-noacs.md" "$T/plan.md"; r2=$RC; e2="$ERR"
run "$T/rec.md" "$T"; r3=$RC
run "$T/rec.md"; r4=$RC
[ "$r1" -eq 2 ] && [ "$r2" -eq 2 ] && grep -qF "carries 0 'ACs:' lines" <<< "$e2" && [ "$r3" -eq 2 ] && [ "$r4" -eq 2 ] \
  && ok "(pc10) unreadable record, no 'ACs:' line, a directory for the plan, a missing argument → 2" || bad "(pc10) rc=$r1/$r2/$r3/$r4 err=$e2"

# (pc11) #1040 D-4 D-11: a holds or unchecked AC must be tagged like a behavior, and is reported as covered in its form
record "$T/rec-forms.md" $'ACs: AC-1 AC-2 AC-3 AC-4\n\nAC-1: a duplicate import answers 409\nAC-2: holds — an import under 50 MB still lands\nAC-3: unchecked — api tier; needs the running app\nAC-4: exempt — docs only'
plan '- [ ] 1.1 import (src/import.spec.ts) [AC-1] [AC-2]' '- [ ] 1.2 the api suite (api/import.api.ts) [AC-3]'
run "$T/rec-forms.md" "$T/plan.md"
[ "$RC" -eq 0 ] && has 'plan-coverage: AC-2 covered (task 1.1) — holds' && has 'plan-coverage: AC-3 covered (task 1.2) — unchecked' \
  && has 'plan-coverage: AC-1 covered (task 1.1)' && ! has 'AC-1 covered (task 1.1) —' \
  && has 'plan-coverage: pass — 3 covered, 1 exempt (of the covered: 1 holds, 1 unchecked)' \
  && ok "(pc11) D-4 D-11: holds and unchecked ACs are covered in their form, counted apart" || bad "(pc11) rc=$RC out=$OUT"
plan '- [ ] 1.1 import (src/import.spec.ts) [AC-1]'
run "$T/rec-forms.md" "$T/plan.md"
[ "$RC" -eq 1 ] && has 'RED: AC-2 has no test task' && has 'RED: AC-3 has no test task' \
  && ok "(pc11) D-4 D-11: an untagged holds or unchecked AC is uncovered → 1" || bad "(pc11) untagged: rc=$RC out=$OUT"

# (pc12) #1040 D-3: a tagged task names its test files in the parenthetical that ends its description; one with none is red, named
plan '- [ ] 1.1 duplicate import answers 409 [AC-1] [AC-2]' '- [ ] 1.2 the scheduler case () [AC-8]' '- [ ] 2.1 the worker, untagged, needs no file'
run "$T/rec.md" "$T/plan.md"
[ "$RC" -eq 1 ] && has 'plan-coverage: RED: task 1.1 tags AC-1 AC-2 but names no test file' && has 'plan-coverage: RED: task 1.2 tags AC-8 but names no test file' \
  && ! has 'task 2.1' && has 'RED: AC-1 has no test task' \
  && ok "(pc12) D-3: tagged tasks naming no file are red by task, their tags uncounted; an untagged task needs none → 1" || bad "(pc12) rc=$RC out=$OUT"
plan '- [ ] 1.1 import, the (old) tests (src/a.spec.ts) [AC-1] [AC-2] [AC-8] [AC-3]'
run --files "$T/rec.md" "$T/plan.md"
[ "$RC" -eq 0 ] && [ "$OUT" = $'run AC-1 src/a.spec.ts\nrun AC-2 src/a.spec.ts\nrun AC-8 src/a.spec.ts' ] \
  && ok "(pc12) D-3: only the parenthetical that ends the description names files → 0" || bad "(pc12) last paren: rc=$RC out=$OUT"

# (pc13) #1040 D-7: --files prints the map on a pass — run / holds / unchecked per AC and file, in plan order, once each;
# an exempt AC's files are left out, and a file shared by a behavior and a holds AC is listed under both
plan '- [ ] 1.1 import (src/import.spec.ts, src/b.spec.ts) [AC-1] [AC-2]' '- [ ] 1.2 the api suite (api/import.api.ts) [AC-3] [AC-4]' \
  '- [ ] 1.3 again (src/import.spec.ts) [AC-1]'
run --files "$T/rec-forms.md" "$T/plan.md"
want=$'run AC-1 src/import.spec.ts\nrun AC-1 src/b.spec.ts\nholds AC-2 src/import.spec.ts\nholds AC-2 src/b.spec.ts\nunchecked AC-3 api/import.api.ts'
[ "$RC" -eq 0 ] && [ "$OUT" = "$want" ] && ok "(pc13) D-7: --files prints the AC-to-file map alone, exempt AC-4 left out" || bad "(pc13) rc=$RC out=$OUT"
plan '- [ ] 1.1 import (src/import.spec.ts) [AC-1]'
run --files "$T/rec-forms.md" "$T/plan.md"
[ "$RC" -eq 1 ] && has 'RED: AC-2 has no test task' && ! has 'run AC-1' && ok "(pc13) --files on a red prints the RED lines, no map → 1" || bad "(pc13) red: rc=$RC out=$OUT"
run --files "$T/rec-none.md" "$T/plan.md"
[ "$RC" -eq 3 ] && ok "(pc13) --files on 'ACs: none' → 3" || bad "(pc13) none: rc=$RC out=$OUT"

echo "plan-coverage-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"

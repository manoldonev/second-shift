#!/usr/bin/env bash
# corpus-selftest.sh — the shipped corpus passes `planted.py check`, and a copy that lacks any part a case
# must carry, or holds a marker, or falls short of a class, fails naming it. No network and no model.
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
[ "$rc" -eq 0 ] && [ "$out" = "check: ok (P1 8, P2 4, P3 4, P4 4, P5 4, control 5)" ] \
  && ok "the shipped corpus passes, with eight P1 cases, four cases in each other class and five clean controls" || bad "shipped corpus: rc=$rc $out"
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

echo "corpus-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"

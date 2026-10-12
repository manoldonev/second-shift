#!/usr/bin/env bash
# verdict-check.sh — a review verdict binds only when its own comment backs it (#991). Both paths that
# set `second-shift/review` call it: run.sh on the body it bound, and the manual /dev-pipeline:review
# on its draft and again, through post-review-status.sh, on the posted body.
#
# Usage:
#   verdict-check.sh <body-file> <record-at-head> <record-at-first>
#
# The body has these parts, in this order and nothing else (the grammar run.sh's review prompt and
# review/SKILL.md state):
#   line 1 `verdict: approve|needs-work`, line 2 `reviewed: <40-hex sha>`, an optional line 3
#   `reason: render-unavailable`;
#   `## Decision record rows`: only the `| Row | Score | Evidence |` table and blank lines. The Row
#   cell's first token is a record `D-n` id, the Score cell's first word one of
#   honored|violated|departed|undeterminable;
#   `## Findings`: each finding starts `- [blocker] B<n> ` or `- [note] N<n> `, continuation lines are
#   indented two or more spaces, and a section with no findings holds the single line `None.`; the
#   grammar asks a review-lead finding to carry `[Reviewer] file:line (confidence: N)` after the id,
#   but nothing here checks it (#1010 D-9): the rest of the line is free text;
#   `## Panel` (optional, not parsed) and `## Notes` (optional, free prose).
# `Ready to merge?` anywhere fails. An approve has no [blocker], no violated or undeterminable score
# and no render-unavailable line; a needs-work has a [blocker], a violated or undeterminable score, or
# the render-unavailable line. Every `D-n` row of either record version — only unindented lines
# `| D-n |` (#991 D-6) — is scored, except under render-unavailable.
#
# Exit: 0 the body passes · 1 it breaks a rule (stdout: one line per failure, every one of them, each
# starting with the rule's stable name) · 2 usage, or a file cannot be read (nothing is evaluated).
set -uo pipefail

[ $# -eq 3 ] || { echo "usage: verdict-check.sh <body-file> <record-at-head> <record-at-first>" >&2; exit 2; }
for f in "$@"; do
  [ -f "$f" ] && [ -r "$f" ] || { echo "verdict-check: cannot read $f — nothing evaluated" >&2; exit 2; }
done
ids="$(cat "$2" "$3" | tr -d '\r' | sed -n -E 's/^\| (D-[0-9]+) \|.*/\1/p' | sort -u -t- -k2,2n | tr '\n' ' ')" \
  || { echo "verdict-check: cannot read the record files — nothing evaluated" >&2; exit 2; }

# shellcheck disable=SC2016  # an awk program, not shell
prog='
function fail(rule, detail) { if (detail != "") rule = rule ": " detail; if (!(rule in said)) { said[rule] = 1; print rule }; bad = 1 }
function cut(s) { return length(s) > 80 ? substr(s, 1, 77) "..." : s }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
BEGIN {
  n = split(ids, idl, " "); for (i = 1; i <= n; i++) if (idl[i] != "") rec[idl[i]] = 1
  order["## Decision record rows"] = 1; order["## Findings"] = 2; order["## Panel"] = 3; order["## Notes"] = 4
  score["honored"] = 1; score["violated"] = 1; score["departed"] = 1; score["undeterminable"] = 1
  sec = 0; last = 0; ts = 0; infind = 0
}
{ sub(/\r$/, "") }
/Ready to merge\?/ { fail("Ready to merge? in the body", "line " NR) }
NR == 1 { if ($0 ~ /^verdict: (approve|needs-work)$/) v = substr($0, 10); else fail("line 1 is not a verdict line", cut($0)); next }
NR == 2 { if (!($0 ~ /^reviewed: [0-9a-f]+$/ && length($0) == 50)) fail("line 2 is not a reviewed line", cut($0)); next }
NR == 3 && $0 == "reason: render-unavailable" { render = 1; next }
/^## / {
  h = $0; sub(/[ \t]+$/, "", h)
  if (!(h in order)) { fail("unknown section", h); sec = -1; next }
  if (h in seen) { fail("section repeated", h); sec = -1; next }
  seen[h] = 1
  if (order[h] < last) fail("section out of order", h)
  last = order[h]; sec = order[h]; next
}
sec == 0 { if ($0 !~ /^[ \t]*$/) fail("text outside a section", "line " NR ": " cut($0)); next }
sec == 1 {
  if ($0 ~ /^[ \t]*$/) { if (ts == 2) ts = 3; next }
  if (ts == 0) { if ($0 ~ /^\| *Row *\| *Score *\| *Evidence *\| *$/) ts = 1; else fail("Decision record rows not in the grammar", "line " NR ": " cut($0)); next }
  if (ts == 1) { if ($0 ~ /^\|( *:?-+:? *\|)( *:?-+:? *\|)( *:?-+:? *\|) *$/) ts = 2; else fail("Decision record rows not in the grammar", "line " NR ": the table has no | --- | line"); next }
  if (ts == 3 || $0 !~ /^\|/) { fail("Decision record rows not in the grammar", "line " NR ": " cut($0)); next }
  s = $0; gsub(/\\\|/, "\001", s); sub(/^\|/, "", s); sub(/\|[ \t]*$/, "", s)
  if (split(s, cell, "|") != 3) { fail("Decision record rows not in the grammar", "line " NR ": a row has three cells"); next }
  split(trim(cell[1]), tok, /[ \t]+/); id = tok[1]
  if (id !~ /^D-[0-9]+$/) { fail("row is not a D-n row", cut(trim(cell[1]))); next }
  if (!(id in rec)) fail("row not in the record", id)
  scored[id] = 1
  split(trim(cell[2]), w, /[ \t]+/)
  if (!(w[1] in score)) { fail("score not in the grammar", id ": " cut(trim(cell[2]))); next }
  if (w[1] == "violated" || w[1] == "undeterminable") badrows = badrows (badrows == "" ? "" : ", ") id " " w[1]
  next
}
sec == 2 {
  if ($0 ~ /^[ \t]*$/) next
  if ($0 == "None.") { nones++; next }
  if ($0 ~ /^- \[blocker\] B[0-9]+ /) { blockers++; finds++; infind = 1; next }
  if ($0 ~ /^- \[note\] N[0-9]+ /) { finds++; infind = 1; next }
  if (infind && $0 ~ /^  /) next
  fail("Findings not in the grammar", "line " NR ": " cut($0)); next
}
END {
  if (NR < 2) fail("line 2 is not a reviewed line", "the body has fewer than two lines")
  if (!("## Decision record rows" in seen)) fail("missing section", "## Decision record rows")
  else if (ts < 2) fail("Decision record rows not in the grammar", "no | Row | Score | Evidence | table")
  if (!("## Findings" in seen)) fail("missing section", "## Findings")
  else if (nones + finds == 0) fail("Findings not in the grammar", "an empty section holds the single line None.")
  else if (nones > 0 && (finds > 0 || nones > 1)) fail("Findings not in the grammar", "None. is the only line of a section with no findings")
  if (v == "approve") {
    if (blockers > 0) fail("approve with a blocker", blockers " [blocker] line(s)")
    if (badrows != "") fail("approve with a violated or undeterminable row", badrows)
    if (render) fail("approve with reason: render-unavailable")
  }
  if (v == "needs-work" && !render && blockers == 0 && badrows == "") fail("needs-work with no blocker")
  if (!render) for (i = 1; i <= n; i++) if (idl[i] != "" && !(idl[i] in scored)) fail("record row not scored", idl[i])
  exit bad
}'
awk -v ids="$ids" "$prog" "$1"

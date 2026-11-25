#!/usr/bin/env bash
# verdict-check.sh — a review verdict binds only when its own comment backs it. Both paths that
# set `second-shift/review` call it: run.sh on the body it bound, and the manual /dev-pipeline:review
# on its draft and again, through post-review-status.sh, on the posted body.
#
# Usage:
#   verdict-check.sh <body-file> <record-at-head> <record-at-first>
#   verdict-check.sh <body-file>       (no-record mode: review-lead's report, which scores no record)
#
# The no-record mode takes the same grammar without `## Decision record rows`, which it fails, and requires the
# `reviewed-by:` line and `## Summary`. Both modes fail a `## Summary` of more than 8 non-blank lines, a `## Notes` of
# 150 words or more, a `[note]` finding of more than 4 lines, and the line `Knowledge-base contributions: none`. The
# Notes count leaves out the knowledge-base block (from its lead line to the end of the section), the later-round
# notes (`- later-round note: <file:line> — <defect>`, a new note on code a later review found unchanged), the resolved
# fold and the lines the join writes: `Joined review:`, `lane vs blind:` and the hidden `<!-- plain-vs-lane: … -->` line.
#
# A later review lists what it saw resolved in `## Notes`: `<details><summary><n> resolved</summary>`, the
# `- resolved: <file:line> — <defect> — <how>` lines, then `</details>`. Every resolved line sits in that fold, a fold
# holds at least one, <n> equals their number, and the fold closes. An empty `## Findings` beside resolved lines holds
# `None open. <n> resolved, listed in ## Notes.` with the same <n>, never `None.`. Where the fold sits is not checked:
# the join writes its own lines after it.
#
# The body has these parts, in this order and nothing else (the grammar run.sh's review prompt and
# review/SKILL.md state):
#   line 1 `verdict: approve|needs-work`, line 2 `reviewed: <40-hex sha>`, an optional line 3
#   `reason: render-unavailable|ticket-unreadable|seat-unavailable`, then an optional
#   `reviewed-by: second-shift ...` line;
#   `## Summary` (optional, first): its first line is `Mergeable as it is.` on an approve or `Not mergeable
#   yet.` on a needs-work, it names every row scored departed, violated or undeterminable, and it
#   holds no table;
#   `## Decision record rows`: only the `| Row | Score | Evidence |` table and blank lines. The Row
#   cell's first token is a record `D-n` id, the Score cell's first word one of
#   honored|violated|departed|undeterminable. The table may be folded: the line
#   `<details><summary><N> rows: <k> honored, <k> departed, <k> violated, <k> undeterminable</summary>`
#   before it (scores in that order, zero counts left out, N and every count equal to the table's),
#   a blank line after that, and `</details>` on its own line after the table. A folded table needs
#   a `## Summary`, which names every row that is not honored;
#   `## Findings`: each finding starts `- [blocker] B<n> ` or `- [note] N<n> `, continuation lines are
#   indented two or more spaces, and a section with no findings holds the single line `None.` or `None open.`; the
#   rest of a finding's line is free text, and no finding id appears twice;
#   `## Panel` (optional, not parsed: earlier verdicts carry one) and `## Notes` (optional, free prose).
# `Ready to merge?` anywhere fails. Every finding gates, a [note] the same as a [blocker]: an approve
# has no finding, no violated or undeterminable score and no reason line; a needs-work has a finding,
# a violated or undeterminable score, or a reason line. Every `D-n` row of either record version — only unindented lines `| D-n |` — is
# scored, except under a reason line. A row that was `deferred` at the first commit, citing an `OR-n`
# its Open Regions table marks `pause-and-ask`, and is `user-delegated` at the head is scored
# `violated` when it is scored: only the requester decides it.
#
# Exit: 0 the body passes · 1 it breaks a rule (stdout: one line per failure, every one of them, each
# starting with the rule's stable name) · 2 usage, or a file cannot be read (nothing is evaluated).
set -uo pipefail

[ $# -eq 3 ] || [ $# -eq 1 ] || { echo "usage: verdict-check.sh <body-file> [<record-at-head> <record-at-first>]" >&2; exit 2; }
for f in "$@"; do
  [ -f "$f" ] && [ -r "$f" ] || { echo "verdict-check: cannot read $f — nothing evaluated" >&2; exit 2; }
done
norec=0 ids="" asked=""
[ $# -eq 1 ] && norec=1
[ "$norec" = 1 ] || ids="$(cat "$2" "$3" | tr -d '\r' | sed -n -E 's/^\|[[:space:]]*(D-[0-9]+)[[:space:]]*\|.*/\1/p' | sort -u -t- -k2,2n | tr '\n' ' ')" \
  || { echo "verdict-check: cannot read the record files — nothing evaluated" >&2; exit 2; }
# shellcheck disable=SC2016  # an awk program, not shell
[ "$norec" = 1 ] || asked="$(awk '
  { sub(/\r$/, ""); s = $0; gsub(/\\\|/, "\001", s) }
  s !~ /^\|[ \t]*(D|OR)-[0-9]+[ \t]*\|/ { next }
  { n = split(s, c, "|"); for (i = 2; i <= n; i++) gsub(/^[ \t]+|[ \t]+$/, "", c[i]) }
  at == "first" && c[2] ~ /^OR-/ { if (c[4] == "pause-and-ask") ask[c[2]] = 1; next }
  at == "first" { if (c[5] == "deferred") cites[c[2]] = c[4]; next }
  c[2] ~ /^D-/ { head[c[2]] = c[5] }
  END {
    for (id in cites) {
      if (head[id] != "user-delegated") continue
      r = cites[id]
      while (match(r, /OR-[0-9]+/)) { if (substr(r, RSTART, RLENGTH) in ask) { print id; break }; r = substr(r, RSTART + RLENGTH) }
    }
  }' at=first "$3" at=head "$2" | tr '\n' ' ')" \
  || { echo "verdict-check: cannot read the record files — nothing evaluated" >&2; exit 2; }

# shellcheck disable=SC2016  # an awk program, not shell
prog='
function fail(rule, detail) { if (detail != "") rule = rule ": " detail; if (!(rule in said)) { said[rule] = 1; print rule }; bad = 1 }
function cut(s) { return length(s) > 80 ? substr(s, 1, 77) "..." : s }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
BEGIN {
  n = split(ids, idl, " "); for (i = 1; i <= n; i++) if (idl[i] != "") rec[idl[i]] = 1
  na = split(asked, al, " "); for (i = 1; i <= na; i++) if (al[i] != "") ask[al[i]] = 1
  order["## Summary"] = 1; order["## Decision record rows"] = 2; order["## Findings"] = 3; order["## Panel"] = 4; order["## Notes"] = 5
  score["honored"] = 1; score["violated"] = 1; score["departed"] = 1; score["undeterminable"] = 1
  sec = 0; last = 0; ts = 0; infind = 0; fd = 0; trows = 0
  sorder[1] = "honored"; sorder[2] = "departed"; sorder[3] = "violated"; sorder[4] = "undeterminable"
}
function fold_summary(s,    body, list, nl, it, kw, i, j, k, p, total) {
  body = s; sub(/^<details><summary>/, "", body); sub(/<\/summary>$/, "", body)
  if (!match(body, /^[0-9]+ rows(: .+)?$/)) { fail("Decision record rows not in the grammar", "line " NR ": the summary is <N> rows: <k> <score>, ..."); return }
  split(body, it, " "); total = it[1] + 0
  list = body; if (!sub(/^[0-9]+ rows: /, "", list)) list = ""
  nl = (list == "") ? 0 : split(list, it, ", "); p = 0
  for (i = 1; i <= nl; i++) {
    if (it[i] !~ /^[0-9]+ [a-z]+$/) { fail("Decision record rows not in the grammar", "line " NR ": the summary is <N> rows: <k> <score>, ..."); return }
    split(it[i], kw, " "); k = 0
    for (j = 1; j <= 4; j++) if (sorder[j] == kw[2]) k = j
    if (k == 0) { fail("score not in the grammar", "rows summary: " kw[2]); return }
    if (k <= p) { fail("Decision record rows not in the grammar", "line " NR ": the summary lists honored, departed, violated, undeterminable in that order, each once"); return }
    if (kw[1] + 0 == 0) { fail("Decision record rows not in the grammar", "line " NR ": the summary leaves out a zero count"); return }
    p = k; fcount[kw[2]] = kw[1] + 0
  }
  fnrows = total
}
function endnote() { if (notelines > 4) fail("note longer than four lines", noteid " has " notelines " lines"); notelines = 0 }
{ sub(/\r$/, "") }
/Ready to merge\?/ { fail("Ready to merge? in the body", "line " NR) }
/^[ \t]*Knowledge-base contributions: none[ \t]*$/ { fail("Knowledge-base contributions: none in the body", "line " NR ": leave the block out when it has no proposal") }
NR == 1 { if ($0 ~ /^verdict: (approve|needs-work)$/) v = substr($0, 10); else fail("line 1 is not a verdict line", cut($0)); next }
NR == 2 { if (!($0 ~ /^reviewed: [0-9a-f]+$/ && length($0) == 50)) fail("line 2 is not a reviewed line", cut($0)); next }
NR == 3 && $0 ~ /^reason: (render-unavailable|ticket-unreadable|seat-unavailable)$/ { reason = substr($0, 9); next }
(NR == 3 || (NR == 4 && reason != "")) && /^reviewed-by: second-shift / { by = 1; next }
/^## / {
  endnote()
  h = $0; sub(/[ \t]+$/, "", h)
  if (norec && h == "## Decision record rows") { fail("Decision record rows in a verdict with no record"); seen[h] = 1; sec = -1; next }
  if (!(h in order)) { fail("unknown section", h); sec = -1; next }
  if (h in seen) { fail("section repeated", h); sec = -1; next }
  seen[h] = 1
  if (order[h] < last) fail("section out of order", h)
  last = order[h]; sec = order[h]; next
}
sec == 0 { if ($0 !~ /^[ \t]*$/) fail("text outside a section", "line " NR ": " cut($0)); next }
sec == 1 {
  if ($0 ~ /^[ \t]*$/) next
  slines++
  if (sfirst == "") sfirst = trim($0)
  if ($0 ~ /^[ \t]*\|/) fail("Summary not in the grammar", "line " NR ": a Summary holds no table")
  stext = stext " " $0; next
}
sec == 2 {
  if ($0 ~ /^[ \t]*$/) { if (ts == 2) ts = 3; next }
  if (NR == fblank) fail("Decision record rows not in the grammar", "line " NR ": a blank line follows the rows summary")
  if ($0 ~ /^<details/ && fd == 0 && ts == 0) {
    fd = 1; fblank = NR + 1
    if ($0 ~ /^<details><summary>.*<\/summary>$/) fold_summary($0); else fail("Decision record rows not in the grammar", "line " NR ": " cut($0))
    next
  }
  if ($0 == "</details>" && fd == 1 && ts >= 2) { fd = 2; next }
  if (fd == 2) { fail("Decision record rows not in the grammar", "line " NR ": " cut($0)); next }
  if (ts == 0) { if ($0 ~ /^\| *Row *\| *Score *\| *Evidence *\| *$/) ts = 1; else fail("Decision record rows not in the grammar", "line " NR ": " cut($0)); next }
  if (ts == 1) { if ($0 ~ /^\|( *:?-+:? *\|)( *:?-+:? *\|)( *:?-+:? *\|) *$/) ts = 2; else fail("Decision record rows not in the grammar", "line " NR ": the table has no | --- | line"); next }
  if (ts == 3 || $0 !~ /^\|/) { fail("Decision record rows not in the grammar", "line " NR ": " cut($0)); next }
  trows++
  s = $0; gsub(/\\\|/, "\001", s); sub(/^\|/, "", s); sub(/\|[ \t]*$/, "", s)
  if (split(s, cell, "|") != 3) { fail("Decision record rows not in the grammar", "line " NR ": a row has three cells"); next }
  split(trim(cell[1]), tok, /[ \t]+/); id = tok[1]
  if (id !~ /^D-[0-9]+$/) { fail("row is not a D-n row", cut(trim(cell[1]))); next }
  if (!(id in rec)) fail("row not in the record", id)
  scored[id] = 1
  split(trim(cell[2]), w, /[ \t]+/)
  if (!(w[1] in score)) { fail("score not in the grammar", id ": " cut(trim(cell[2]))); next }
  tcount[w[1]]++
  if ((id in ask) && w[1] != "violated") fail("user-delegated row under a pause-and-ask region not scored violated", id " " w[1])
  if (w[1] == "violated" || w[1] == "undeterminable") badrows = badrows (badrows == "" ? "" : ", ") id " " w[1]
  if (w[1] != "honored") { nn++; notable[nn] = id }
  next
}
sec == 3 {
  if ($0 ~ /^[ \t]*$/) next
  if ($0 == "None.") { nones++; bare++; next }
  if ($0 ~ /^None open\. [0-9]+ resolved, listed in ## Notes\.$/) { nones++; split($0, ow, " "); nopen = ow[3] + 0; hasopen = 1; next }
  if (match($0, /^- \[(blocker|note)\] [BN][0-9]+ /)) {
    fid = substr($0, 1, RLENGTH - 1); sub(/^.* /, "", fid)
    if (fid in fids) fail("finding id repeated", fid); fids[fid] = 1
  }
  if ($0 ~ /^- \[blocker\] B[0-9]+ /) { endnote(); blockers++; finds++; infind = 1; next }
  if ($0 ~ /^- \[note\] N[0-9]+ /) { endnote(); finds++; infind = 1; notelines = 1; noteid = fid; next }
  if (infind && $0 ~ /^  /) { if (notelines) notelines++; next }
  fail("Findings not in the grammar", "line " NR ": " cut($0)); next
}
sec == 5 {
  if ($0 ~ /^<details><summary>[0-9]+ resolved<\/summary>$/) { rfold++; inres = 1; rsumn = $0; gsub(/[^0-9]/, "", rsumn); rsumn += 0; next }
  if (inres && $0 == "</details>") { inres = 0; next }
  if ($0 ~ /^- resolved: /) { nres++; if (!inres) rout++; next }
  if ($0 ~ /^(### )?Knowledge-base contributions/) kb = 1
  if (kb || $0 ~ /^(<!-- plain-vs-lane: |Joined review: |lane vs blind: |- later-round note: )/) next
  nwords += NF; next
}
END {
  endnote()
  if (slines > 8) fail("Summary longer than eight lines", slines " non-blank lines")
  if (nwords >= 150) fail("Notes of 150 words or more", nwords " words, not counting the knowledge-base block, the later-round notes, the resolved fold and the join lines")
  if (bare && nres) fail("None. beside resolved lines", "an empty ## Findings holds None open. " nres " resolved, listed in ## Notes.")
  if (hasopen && nopen == 0) fail("None open. line counts no resolved line", "an empty ## Findings with no resolved line holds None.")
  else if (hasopen && nopen != nres) fail("resolved count differs from the resolved lines", "## Findings says " nopen ", ## Notes has " nres)
  if (rout) fail("resolved line outside the resolved fold", rout " line(s)")
  if (rfold && nres == 0) fail("resolved fold with no resolved line")
  else if (rfold && rsumn != nres) fail("resolved count differs from the resolved lines", "the fold summary says " rsumn ", ## Notes has " nres)
  if (inres) fail("resolved fold not closed", "no </details> line after the resolved lines")
  if (norec) {
    if (!by) fail("missing reviewed-by line", "line 3, or line 4 after a reason line")
    if (!("## Summary" in seen)) fail("missing section", "## Summary")
  }
  if (NR < 2) fail("line 2 is not a reviewed line", "the body has fewer than two lines")
  if (norec) {}
  else if (!("## Decision record rows" in seen)) fail("missing section", "## Decision record rows")
  else if (ts < 2) fail("Decision record rows not in the grammar", "no | Row | Score | Evidence | table")
  if (fd == 1) fail("Decision record rows not in the grammar", "the rows fold has no </details> line after the table")
  if (fd > 0 && fnrows != "") {
    if (fnrows != trows) fail("rows summary counts differ from the table", "the summary says " fnrows " rows, the table has " trows)
    for (j = 1; j <= 4; j++) if ((fcount[sorder[j]] + 0) != (tcount[sorder[j]] + 0)) fail("rows summary counts differ from the table", "the summary says " (fcount[sorder[j]] + 0) " " sorder[j] ", the table has " (tcount[sorder[j]] + 0))
  }
  if (fd > 0 && !("## Summary" in seen)) fail("folded rows table with no ## Summary", "a verdict that folds the rows table names its rows that are not honored in ## Summary")
  if (!("## Findings" in seen)) fail("missing section", "## Findings")
  else if (nones + finds == 0) fail("Findings not in the grammar", "an empty section holds the single line None.")
  else if (nones > 0 && (finds > 0 || nones > 1)) fail("Findings not in the grammar", "None. is the only line of a section with no findings")
  if (v == "approve") {
    if (blockers > 0) fail("approve with a blocker", blockers " [blocker] line(s)")
    if (finds > blockers) fail("approve with a note", finds - blockers " [note] line(s)")
    if (badrows != "") fail("approve with a violated or undeterminable row", badrows)
    if (reason != "") fail("approve with reason: " reason)
  }
  if (v == "needs-work" && reason == "" && finds == 0 && badrows == "") fail("needs-work with no finding")
  if ("## Summary" in seen) {
    want = (v == "approve") ? "Mergeable as it is." : "Not mergeable yet."
    if (sfirst != want) fail("Summary line 1 does not match the verdict", "want " want)
    for (i = 1; i <= nn; i++) if (!((" " stext " ") ~ ("[^-0-9A-Za-z]" notable[i] "[^0-9]"))) fail("Summary does not name a row that is not honored", notable[i])
  }
  if (reason == "") for (i = 1; i <= n; i++) if (idl[i] != "" && !(idl[i] in scored)) fail("record row not scored", idl[i])
  exit bad
}'
awk -v ids="$ids" -v asked="$asked" -v norec="$norec" "$prog" "$1"

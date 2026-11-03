#!/usr/bin/env bash
# verdict-join.sh — joins a lane review's verdict draft with a plain review's into the one verdict a harness posts.
#
# Usage:
#   verdict-join.sh <lane-draft> <plain-draft or ''> [--why <why plain is missing>] [--format verdict|report]
#                   [--lane-cost <usd>] [--plain-cost <usd>] [--lane-wall <s>] [--plain-wall <s>] [--ticket true|false]
#
# --format report joins a review-lead report instead of a lane verdict, by the same rules: its blockers are the
# bullets under `## Critical`, an agreed one becomes `- [lane+plain] …`, a plain-only one is added there as
# `- [plain] …`, and a plain-only blocker turns `**Ready to merge?** Yes` or `With fixes` into `No`.
#
# Plain contributes blockers only; its notes are dropped. A plain blocker at the file of a lane blocker, within 3
# lines of it, is that blocker, tagged [lane+plain]. Any other is added after the lane's blockers as [plain],
# numbered after the lane's highest B id, and turns an approve into a needs-work: line 1 becomes
# `verdict: needs-work`, the Summary's first line `Not mergeable yet.`, and a `Nothing to do.` line names the
# [plain] blockers. With no plain draft, `## Notes` says why and the lane's verdict stands as written.
# The body ends with a folded `dev: lane vs plain` block under `## Notes`, which verdict-check.sh reads as prose:
# the counts, the ids on each side, the verdict impact, each session's cost and wall time, whether plain had the
# ticket (--ticket false, or a plain `ticket-unavailable` note: it reviewed the diff alone), and one
# `<!-- plain-vs-lane: {json} -->` line for scripts that aggregate across PRs.
#
# Exit: 0 the joined verdict on stdout · 2 usage, or the lane draft cannot be read.
set -uo pipefail
usage() { echo "usage: verdict-join.sh <lane-draft> <plain-draft or ''> [--why <text>] [--format verdict|report] [--lane-cost <usd>] [--plain-cost <usd>] [--lane-wall <s>] [--plain-wall <s>] [--ticket true|false]" >&2; exit 2; }
[ $# -ge 2 ] || usage
lane="$1" plain="$2"; shift 2
why="the plain review did not return" fmt=verdict lc="" pc="" lw="" pw="" ticket=true
while [ $# -gt 0 ]; do
  case "$1" in
    --why) why="${2-}"; shift 2 ;;
    --ticket) ticket="${2-}"; shift 2; case "$ticket" in true|false) : ;; *) usage ;; esac ;;
    --format) fmt="${2-}"; case "$fmt" in verdict|report) : ;; *) usage ;; esac; shift 2 ;;
    --lane-cost) lc="${2-}"; shift 2 ;;
    --plain-cost) pc="${2-}"; shift 2 ;;
    --lane-wall) lw="${2-}"; shift 2 ;;
    --plain-wall) pw="${2-}"; shift 2 ;;
    *) usage ;;
  esac
done
[ -f "$lane" ] && [ -r "$lane" ] || { echo "verdict-join: cannot read the lane draft $lane" >&2; exit 2; }
[ -z "$plain" ] || [ -r "$plain" ] || plain=""
num() { case "$1" in ''|*[!0-9.]*|.*) printf 'null' ;; *) printf '%s' "$1" ;; esac; }

# shellcheck disable=SC2016  # an awk program, not shell
awk -v pf="$plain" -v why="$why" -v ticket="$ticket" -v rep="$([ "$fmt" = report ] && echo 1 || echo 0)" -v lc="$(num "$lc")" -v pc="$(num "$pc")" -v lw="$(num "$lw")" -v pw="$(num "$pw")" '
  # the first path:line in s: an extensionless path (Makefile:12) counts; a URL host:port, a bare id (B1:2) or a time does not
  function loc(s,   m, p, pre) {
    while (match(s, /[A-Za-z0-9_@.\/-]+:[0-9]+/)) {
      m = substr(s, RSTART, RLENGTH); pre = RSTART > 1 ? substr(s, RSTART - 1, 1) : ""; s = substr(s, RSTART + RLENGTH)
      p = m; sub(/:[0-9]+$/, "", p)
      if (pre == ":" || index(m, "//") || p ~ /^[BNH][0-9]+$/ || p ~ /^[0-9.]+$/) continue
      sub(/^\.\//, "", m); return m
    }
    return ""
  }
  function near(a, b,   pa, pb, d) {
    if (a == "" || b == "") return 0
    pa = a; sub(/:[0-9]+$/, "", pa); pb = b; sub(/:[0-9]+$/, "", pb); if (pa != pb) return 0
    d = substr(a, length(pa) + 2) - substr(b, length(pb) + 2); return d <= 3 && d >= -3
  }
  function added(   k, c) {
    if (done) return 0; done = 1
    for (k = 1; k <= np; k++) if (!pmatch[k]) { c++; print (rep ? "- [plain] " : "- [blocker] " newid[k] " [plain] ") ptext[k]; printf "%s", pcont[k] }
    return c
  }
  function usd(x) { return x == "null" ? "unpriced" : sprintf("$%.2f", x) }
  function secs(x) { return x == "null" ? "? s" : x " s" }
  function devblock(   b, k, s, lone, pone, pairs) {
    for (b = 1; b <= nb; b++) if (!bagreed[b]) lone = lone (lone == "" ? "" : ", ") (rep ? (bloc[b] == "" ? "(no location)" : bloc[b]) : bid[b] (bloc[b] == "" ? "" : " " bloc[b]))
    for (k = 1; k <= np; k++) {
      if (pmatch[k]) pairs = pairs (pairs == "" ? "" : ", ") (rep ? bloc[pmatch[k]] : bid[pmatch[k]]) " ↔ plain " pid[k]
      else pone = pone (pone == "" ? "" : ", ") (rep ? "plain " pid[k] : newid[k] " (plain " pid[k] ")") (ploc[k] == "" ? "" : " " ploc[k])
    }
    print ""
    print "<details><summary>dev: lane vs plain</summary>"
    print ""
    print "Lane blockers: " nb + 0 ". Plain blockers: " np + 0 ". Agreed: " na + 0 ". Lane-only: " nb - na ". Plain-only: " nadd + 0 ". Plain notes dropped: " pnotes + 0 "."
    print "- Lane-only: " (lone == "" ? "none" : lone)
    print "- Plain-only: " (pone == "" ? "none" : pone)
    print "- Agreed: " (pairs == "" ? "none" : pairs)
    if (rep) print "Ready to merge: the lane alone said " ready "; the joined report says " (flip ? "No (plain flipped it to No)" : ready) "."
    else { s = substr(line[1], 10); print "Verdict: the lane alone said " s "; the joined verdict is " (flip ? "needs-work (plain flipped approve → needs-work)" : s) "." }
    print "Lane session: " usd(lc) ", " secs(lw) ". Plain session: " usd(pc) ", " secs(pw) ", " (pf == "" ? "did not return (" why ")" : "returned") (ticket == "true" ? "" : ", reviewed without a ticket") "."
    print ""
    printf "<!-- plain-vs-lane: {\"lane_blockers\":%d,\"plain_blockers\":%d,\"agreed\":%d,\"lane_only\":%d,\"plain_only\":%d,\"plain_notes_dropped\":%d,\"flipped\":%s,\"plain_returned\":%s,\"lane_cost_usd\":%s,\"plain_cost_usd\":%s,\"lane_wall_s\":%s,\"plain_wall_s\":%s,\"ticket\":%s} -->\n", nb, np, na, nb - na, nadd, pnotes, (flip ? "true" : "false"), (pf == "" ? "false" : "true"), lc, pc, lw, pw, (ticket == "true" ? "true" : "false")
    print ""
    print "</details>"
  }
  function report(   i, s, crit, later) {
    if (ready == "") ready = "(not stated)"
    flip = nadd > 0 && ready !~ /^No([^A-Za-z]|$)/
    for (i = 1; i <= n; i++) {
      s = line[i]
      if (s ~ /^## /) {
        later = s !~ /^## (Review Summary|Strengths|Critical)/
        if (crit == 1) { added(); if (pend) print ""; pend = 0 }
        if (later && !crit && nadd > 0) { crit = 2; print "## Critical (must fix before merge)"; added(); print "" }
        if (s ~ /^## Critical/) crit = 1; else if (crit == 1) crit = 2
        print s; continue
      }
      if (crit == 1) {
        if (s ~ /^[ \t]*$/) { pend++; continue }
        for (; pend > 0; pend--) print ""
        if (nadd > 0 && s ~ /^(- )?None\.?[ \t]*$/) continue
        if (i in agreed) { print "- [lane+plain] " substr(s, 3); continue }
      }
      if (i == readyline && flip) { print "**Ready to merge?** No"; continue }
      print s
    }
    if (crit == 1) { for (; pend > 0; pend--) print ""; added() }
    else if (!crit && nadd > 0) { print ""; print "## Critical (must fix before merge)"; added() }
    print ""; print "## Notes"
    if (pf == "") { print ""; print "Joined review: " why ", so this report is review-lead alone." }
    devblock()
  }
  BEGIN {
    if (pf != "") while ((getline l < pf) > 0) {
      sub(/\r$/, "", l)
      if (l ~ /^## /) { psec = l; inb = 0; continue }
      if (psec !~ /^## Findings[ \t]*$/) continue
      if (l ~ /^- \[note\] ([BNH][0-9]+ )?ticket-unavailable/) { ticket = "false"; inb = 0; continue }
      if (l ~ /^- \[note\] /) { pnotes++; inb = 0; continue }
      if (l ~ /^- \[blocker\] /) {
        np++; t = l; sub(/^- \[blocker\] /, "", t); pid[np] = "?"
        if (match(t, /^[BNH][0-9]+ /)) { pid[np] = substr(t, 1, RLENGTH - 1); t = substr(t, RLENGTH + 1) }
        ptext[np] = t; ploc[np] = loc(t); inb = 1; continue
      }
      if (inb && l ~ /^[ \t]+[^ \t]/) { c = l; sub(/^[ \t]+/, "", c); pcont[np] = pcont[np] "  " c "\n"; continue }
      inb = 0
    }
  }
  { sub(/\r$/, ""); line[++n] = $0
    if ($0 ~ /^## /) { sec = $0; sub(/[ \t]+$/, "", sec) }
    else if (rep) {
      if (sec ~ /^## Critical/ && $0 ~ /^- / && $0 !~ /^- None\.?[ \t]*$/) { nb++; bline[nb] = n; bloc[nb] = loc($0) }
      else if (match($0, /^\*\*Ready to merge\?\*\*[ \t]*/)) { readyline = n; ready = substr($0, RLENGTH + 1); sub(/[ \t]+$/, "", ready) }
    }
    else if (sec == "## Findings" && match($0, /^- \[blocker\] B[0-9]+ /)) {
      r = RLENGTH; nb++; bline[nb] = n; bid[nb] = substr($0, 13, r - 13)
      id = substr($0, 14, r - 14) + 0; if (id > maxb) maxb = id
      bloc[nb] = loc(substr($0, r + 1))
    }
  }
  END {
    for (k = 1; k <= np; k++) for (b = 1; b <= nb; b++) if (near(ploc[k], bloc[b])) { pmatch[k] = b; agreed[bline[b]] = 1; if (!bagreed[b]) na++; bagreed[b] = 1; break }
    for (k = 1; k <= np; k++) if (!pmatch[k]) { nadd++; newid[k] = "B" (maxb + nadd) }
    if (rep) { report(); exit }
    flip = nadd > 0 && line[1] == "verdict: approve"
    sec = ""; first = 0
    for (i = 1; i <= n; i++) {
      s = line[i]
      if (i == 1 && flip) { print "verdict: needs-work"; continue }
      if (s ~ /^## /) {
        if (sec == "## Findings" && added()) print ""
        sec = s; sub(/[ \t]+$/, "", sec); print s
        if (sec == "## Notes" && pf == "") { print ""; print "Joined review: " why ", so this verdict is the lane review alone." }
        continue
      }
      if (sec == "## Summary" && flip) {
        if (!first && s ~ /[^ \t]/) { first = 1; print "Not mergeable yet."; continue }
        if (s == "Nothing to do.") { print "Fix the [plain] blockers in Findings."; continue }
      }
      if (sec == "## Findings") {
        if (s == "None." && nadd > 0) continue
        if (s ~ /^- \[note\] /) added()
        if (i in agreed) { match(s, /^- \[blocker\] B[0-9]+ /); print substr(s, 1, RLENGTH) "[lane+plain] " substr(s, RLENGTH + 1); continue }
      }
      print s
    }
    if (sec == "## Findings") added()
    if (sec != "## Notes") { print ""; print "## Notes"; if (pf == "") { print ""; print "Joined review: " why ", so this verdict is the lane review alone." } }
    devblock()
  }' "$lane"

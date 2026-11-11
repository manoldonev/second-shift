#!/usr/bin/env bash
# verdict-join.sh — joins a lane review's verdict draft with a plain review's into the one verdict a harness posts.
#
# Usage:
#   verdict-join.sh <lane-draft> <plain-draft or ''> [--why <why plain is missing>] [--format verdict|report]
#                   [--lane-cost <usd>] [--plain-cost <usd>] [--lane-wall <s>] [--plain-wall <s>] [--ticket true|false]
#                   [--other-comments <other-comments.sh output>]
#
# --format report joins a review-lead report instead of a lane verdict, by the same rules: its blockers are the
# bullets under `## Critical`, an agreed one becomes `- [lane+blind] …`, a plain-only one is added there as
# `- [blind] …`, and a plain-only blocker turns `**Ready to merge?** Yes` or `With fixes` into `No`.
#
# The body takes plain's blockers only. A plain blocker at the file of a lane blocker, within 3 lines of it, is that
# blocker, tagged [lane+blind]. Any other is added after the lane's blockers as [blind], numbered after the lane's
# highest B id, and turns an approve into a needs-work: line 1 becomes `verdict: needs-work`, the Summary's first
# line `Not mergeable yet.`, and a `Nothing to do.` line names the [blind] blockers. With no plain draft, `## Notes`
# says why and the lane's verdict stands as written.
#
# The body ends with a folded `dev: lane vs blind` block under `## Notes`, which verdict-check.sh reads as prose. It
# compares every finding of both reviews, notes and dismissals included: the summary counts agreed, rated
# differently, lane alone and blind alone (the comment names the plain review "blind"); a list pairs the findings, one
# to one, by the same site rule (nearest first, then the same severity), disagreements first, grouped under one bold outcome
# line with its count, one line per pair that leads with the site (a GitHub table squeezed the findings into one-word
# columns beside a long path, and a nested entry per pair was too tall to skim); then both verdicts, both sessions (a lane passed no cost and no wall is "not
# measured"), plain's draft as written, and one `<!-- plain-vs-lane: {json} -->` line for scripts that aggregate
# across PRs. Its `lane_only` and `plain_only` count blockers only; `m_<lane>_<plain>` count pairs by class (b
# blocker, n note, d dismissed, 0 absent). Its `findings` lists one entry per finding of each review, in the dev list's
# order, capped at 150 with `findings_omitted` counting the rest; findings the join matched share a `pair` number.
# Its `other_comments` is the --other-comments file when that file has the tool's shape, else null. A plain
# `ticket-unavailable` note, with or without a site before it, means plain reviewed the diff alone; it is in no count
# and no row. Sites are a proxy: two findings at one site
# are paired whatever they say, and a first-sentence excerpt stops at an abbreviation's period.
#
# Exit: 0 the joined verdict on stdout · 2 usage, or the lane draft cannot be read.
set -uo pipefail
usage() { echo "usage: verdict-join.sh <lane-draft> <plain-draft or ''> [--why <text>] [--format verdict|report] [--lane-cost <usd>] [--plain-cost <usd>] [--lane-wall <s>] [--plain-wall <s>] [--ticket true|false] [--other-comments <file>]" >&2; exit 2; }
[ $# -ge 2 ] || usage
lane="$1" plain="$2"; shift 2
why="the blind review did not return" fmt=verdict lc="" pc="" lw="" pw="" ticket=true ocf=""
while [ $# -gt 0 ]; do
  case "$1" in
    --why) why="${2-}"; shift 2 ;;
    --other-comments) ocf="${2-}"; shift 2 ;;
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
OC=""
[ -z "$ocf" ] || [ ! -r "$ocf" ] || OC="$(jq -sc 'if length == 1 and (.[0] | type == "object" and (.at | type) == "string" and (.total | type) == "number" and (.by_author | type) == "object")
    then .[0] | {at, total, by_author} else null end' "$ocf" 2>/dev/null | sed 's/</\\u003c/g; s/>/\\u003e/g')" || OC=""
export OC="${OC:-null}"

# shellcheck disable=SC2016  # an awk program, not shell
awk -v pf="$plain" -v why="$why" -v ticket="$ticket" -v rep="$([ "$fmt" = report ] && echo 1 || echo 0)" -v lc="$(num "$lc")" -v pc="$(num "$pc")" -v lw="$(num "$lw")" -v pw="$(num "$pw")" '
  # the first path:line in s: an extensionless path (Makefile:12) counts; a URL host:port, a bare id (B1:2) or a time does not.
  # A segment may hold a balanced [..], [[..]] or (..) group without a slash (app/[id]/page.tsx), so [x](a.ts:1) yields a.ts:1
  function loc(s,   m, p, pre) {
    while (match(s, /([A-Za-z0-9_@.\/-]|\[\[[A-Za-z0-9_@.-]+\]\]|\[[A-Za-z0-9_@.-]+\]|\([A-Za-z0-9_@.-]+\))+:[0-9]+/)) {
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
  function lineof(a) { sub(/^.*:/, "", a); return a + 0 }
  function dist(a, b,   d) { if (!near(a, b)) return -1; d = lineof(a) - lineof(b); return d < 0 ? -d : d }
  function added(   k, c) {
    if (done) return 0; done = 1
    for (k = 1; k <= np; k++) if (!pmatch[k]) { c++; print (rep ? "- [blind] " : "- [blocker] " newid[k] " [blind] ") ptext[k]; printf "%s", pcont[k] }
    return c
  }
  function usd(x) { return x == "null" ? "unpriced" : sprintf("$%.2f", x) }
  function secs(x) { return x == "null" ? "? s" : x " s" }
  function addl(c, lab, t) { nl++; lcls[nl] = c; llab[nl] = lab; ltxt[nl] = t; lloc[nl] = loc(t); lfull[nl] = t; cur = nl; return nl }
  function dismissed(t,   p) { p = index(t, DASH); return t ~ /^(Dismissed|Suppressed)\./ || (p && substr(t, p + DL) ~ /^(Dismissed|Suppressed)\./) }
  function esc(s) { gsub(/Ready to merge\?/, "Ready to merge", s); gsub(/</, "\\&lt;", s); return s }
  function sent(t) { return match(t, /\.( |$)/) ? substr(t, 1, RSTART) : t }
  function untag(t) { sub(/^\[[A-Za-z0-9 _.\/-]+\] /, "", t); return t }
  function ex(t,   p, l, s, r) {
    t = untag(t); p = index(t, DASH)
    if (p) t = substr(t, p + DL)
    else { l = loc(t); if (l != "" && (p = index(t, l))) t = substr(t, 1, p - 1) substr(t, p + length(l)); gsub(/\(confidence: [0-9]+\)/, "", t); gsub(/^[ \t]+|[ \t]+$/, "", t); gsub(/[ \t][ \t]+/, " ", t) }
    s = sent(t); if (s ~ /^(Dismissed|Suppressed)\.$/) s = s " " sent(substr(t, length(s) + 2))
    if (length(s) > 160) { r = substr(s, 1, 160); for (p = 160; p > 0 && substr(r, p, 1) != " "; p--) ; if (p > 1) s = substr(r, 1, p - 1) "…" }
    return esc(s)
  }
  function anchor(t,   p) { t = untag(t); p = index(t, DASH); if (p < 2 || p > 61) return "(no site)"; t = substr(t, 1, p - 1); gsub(/^[ \t]+|[ \t]+$/, "", t); return esc(t) }
  function word(c) { return c == "b" ? "blocker" : c == "n" ? "note" : "dismissed" }
  function row(j, i, x,   k) {
    k = (j ? lcls[j] : "0") "_" (i ? pcl[i] : "0"); m[k]++
    nr++; rj[nr] = j; ri[nr] = i; rx[nr] = x; rkey[nr] = rk[k] * 1000000 + j * 1000 + i; rcls[nr] = k
  }
  function pair2(   b, k, j, i, x, bj, bi, bd, bs, d, s) {
    split("0_b n_b d_b b_0 b_n b_b n_n d_n n_0 0_n", ord, " "); for (k = 1; k <= 10; k++) rk[ord[k]] = k
    ot["0_b"] = "blind only: blocker"; ot["n_b"] = "lane note, blind blocker"; ot["d_b"] = "lane dismissed, blind blocker"; ot["b_0"] = "lane only: blocker"
    ot["b_n"] = "lane blocker, blind note"; ot["b_b"] = "agreed: blocker"; ot["n_n"] = "agreed: note"; ot["d_n"] = "lane dismissed, blind note"; ot["n_0"] = "lane only: note"; ot["0_n"] = "blind only: note"
    for (i = 1; i <= np; i++) { pcl[i] = "b"; plab[i] = pid[i]; ptx[i] = ptext[i]; plc[i] = ploc[i] }
    for (i = 1; i <= nq; i++) { pcl[np + i] = "n"; plab[np + i] = qid[i]; ptx[np + i] = qtx[i]; plc[np + i] = qloc[i] }
    pt = np + nq
    for (b = 1; b <= nb; b++) if (bagreed[b]) {
      x = ""; i = 0
      for (k = 1; k <= np; k++) if (pmatch[k] == b) { puse[k] = 1; if (!i) i = k; else { x = x (x == "" ? "" : ", ") pid[k]; merged++ } }
      luse[lj[b]] = 1; row(lj[b], i, x)
    }
    for (k = 1; k <= np; k++) if (pmatch[k]) puse[k] = 1
    while (1) {
      bj = 0
      for (j = 1; j <= nl; j++) if (!luse[j]) for (i = 1; i <= pt; i++) if (!puse[i]) {
        d = dist(lloc[j], plc[i]); if (d < 0) continue
        s = lcls[j] == pcl[i] ? 0 : 1
        if (!bj || d < bd || (d == bd && s < bs)) { bj = j; bi = i; bd = d; bs = s }
      }
      if (!bj) break
      luse[bj] = 1; puse[bi] = 1; row(bj, bi, "")
    }
    for (j = 1; j <= nl; j++) if (!luse[j]) { if (lcls[j] == "d") m["d_0"]++; else row(j, 0, "") }
    for (i = 1; i <= pt; i++) if (!puse[i]) row(0, i, "")
    for (j = 1; j <= nr; j++) so[j] = j
    for (j = 2; j <= nr; j++) for (i = j; i > 1 && rkey[so[i - 1]] > rkey[so[i]]; i--) { k = so[i]; so[i] = so[i - 1]; so[i - 1] = k }
  }
  function code(s) { return s == "(no site)" ? s : "`" s "`" }
  function site(j, i,   s) {
    if (j && lloc[j] != "") { s = code(esc(lloc[j])); if (i && plc[i] != "" && lineof(plc[i]) != lineof(lloc[j])) s = s " (blind :" lineof(plc[i]) ")"; return s }
    if (j) return code(anchor(ltxt[j]))
    return code(plc[i] != "" ? esc(plc[i]) : anchor(ptx[i]))
  }
  function lcell(j) { return llab[j] ": " ex(ltxt[j]) }
  function pcell(i, x) { return plab[i] ": " ex(ptx[i]) (x == "" ? "" : " (+ " x ")") }
  function extra(r,   s, i) {
    i = ri[r]
    if (i && i <= np && !pmatch[i]) s = "added as " (rep ? "[blind]" : newid[i])
    if (rj[r] && tolower(lfull[rj[r]]) ~ /(plain|blind) review/) s = s (s == "" ? "" : "; ") "lane cites blind"
    return s == "" ? "" : " _(" s ")_"
  }
  function pairline(r,   j, i) {
    j = rj[r]; i = ri[r]
    if (j && i) return "- " site(j, i) " — lane " lcell(j) " · blind " pcell(i, rx[r]) extra(r)
    return "- " site(j, i) " — " (j ? lcell(j) : pcell(i, rx[r])) extra(r)
  }
  function mv(k) { return pf == "" ? "null" : m[k] + 0 }
  # loc() keeps only JSON-safe characters, and ids are [BNH]<n> or a section label, so no value here needs escaping
  function q(s) { return s == "" || s == "?" ? "null" : "\"" s "\"" }
  function fent(src, id, c, l, pr, pa,   p) {
    p = l; sub(/:[0-9]+$/, "", p)
    nfl++; fl[nfl] = "{\"src\":\"" src "\",\"id\":" q(id) ",\"class\":\"" word(c) "\",\"path\":" q(p) ",\"line\":" (l == "" ? "null" : lineof(l)) ",\"pair\":" (pr ? pr : "null") (pa == "" ? "" : ",\"posted_as\":\"" pa "\"") "}"
  }
  function lent(j, pr) { fent("lane", rep ? "" : llab[j], lcls[j], lloc[j], pr, "") }
  function bent(i, pr) { fent("blind", plab[i], pcl[i], plc[i], pr, i <= np && !pmatch[i] ? (rep ? "[blind]" : newid[i]) : "") }
  function flist(   r, x, j, i, k, pr, s) {
    if (pf == "") for (j = 1; j <= nl; j++) lent(j, 0)
    for (r = 1; r <= nr; r++) {
      x = so[r]; j = rj[x]; i = ri[x]; pr = (j && i) ? ++npair : 0
      if (j) lent(j, pr)
      if (i && i <= np && pmatch[i]) { for (k = 1; k <= np; k++) if (pmatch[k] == pmatch[i]) bent(k, pr) }
      else if (i) bent(i, pr)
    }
    if (pf != "") for (j = 1; j <= nl; j++) if (!luse[j] && lcls[j] == "d") lent(j, 0)
    for (k = 1; k <= nfl && k <= 150; k++) s = s (k > 1 ? "," : "") fl[k]
    return s
  }
  function bare(   i, s) {
    for (i = 1; i <= nraw; i++) { s = praw[i]; gsub(/^[ \t]+|[ \t]+$/, "", s); if (s != "" && s !~ /^verdict: (approve|needs-work)$/ && s != "## Findings" && s != "None.") return 0 }
    return 1
  }
  function fold(   i, s, tot, left) {
    print "<details><summary>blind review, as written</summary>"; print ""; print "```text"
    for (i = 1; i <= nraw; i++) {
      s = praw[i]; if (s !~ /[^ \t]/) continue
      gsub(/Ready to merge\?/, "Ready to merge", s); s = "    " s
      if (tot + length(s) > 8000) { for (left = 0; i <= nraw; i++) if (praw[i] ~ /[^ \t]/) left++; print "    … " left " more lines not shown"; break }
      tot += length(s); print s
    }
    print "```"; print ""; print "</details>"; print ""
  }
  function devblock(   g, j, r, a, dd, la, pa, lv, rv, jv, pvs, cites, fs) {
    if (pf != "") pair2()
    fs = flist()
    for (j = 1; j <= nl; j++) { if (lcls[j] == "n") lnotes++; if (lcls[j] == "d") ldis++; if (tolower(lfull[j]) ~ /(plain|blind) review/) cites++ }
    a = m["b_b"] + m["n_n"]; dd = m["n_b"] + m["d_b"] + m["b_n"] + m["d_n"]; la = m["b_0"] + m["n_0"]; pa = m["0_b"] + m["0_n"]
    print ""
    if (pf == "") print "<details><summary>dev: lane vs blind — the blind review did not return</summary>"
    else print "<details><summary>dev: lane vs blind — " a + 0 " agreed, " dd + 0 " rated differently, " la + 0 " lane alone, " pa + 0 " blind alone" (flip ? "; blind flipped the verdict" : "") "</summary>"
    print ""
    if (pf != "" && !nr) { print "No finding to compare."; print "" }
    if (nr) {
      for (r = 1; r <= nr && r <= 40; r++) {
        j = so[r]
        if (rcls[j] != g) { if (g != "") print ""; g = rcls[j]; print "**" ot[g] "** (" m[g] ")"; print "" }
        print pairline(j)
      }
      print ""; if (nr > 40) { print nr - 40 " more pairs are counted in the machine line."; print "" }
    }
    pvs = pf == "" ? "did not return" : pv == "" ? "no verdict line" : pv
    if (rep) {
      lv = ready ~ /^Yes/ ? "yes" : ready ~ /^No([^A-Za-z]|$)/ ? "no" : ready ~ /^With fixes/ ? "with-fixes" : ""
      print "- Ready to merge: lane " ready " · blind " pvs " · joined " (flip ? "No (blind flipped it)" : ready) "."
    } else {
      rv = substr(line[1], 10); lv = rv ~ /^(approve|needs-work)$/ ? rv : ""; jv = flip ? "needs-work (blind flipped it)" : rv
      print "- Verdict: lane " rv " · blind " pvs " · joined " jv "."
    }
    print "- Lane session: " (lc == "null" && lw == "null" ? "not measured" : usd(lc) ", " secs(lw)) ". Blind session: " usd(pc) ", " secs(pw) ", " (pf == "" ? "did not return (" why ")" : "returned") (ticket == "true" ? "" : ", reviewed without a ticket") "."
    print ""
    if (pf != "" && !bare()) fold()
    printf "<!-- plain-vs-lane: {\"lane_blockers\":%d,\"plain_blockers\":%d,\"agreed\":%d,\"lane_only\":%d,\"plain_only\":%d,\"plain_notes_dropped\":%d,\"flipped\":%s,\"plain_returned\":%s,\"lane_cost_usd\":%s,\"plain_cost_usd\":%s,\"lane_wall_s\":%s,\"plain_wall_s\":%s,\"ticket\":%s", nb, np, na, nb - na, nadd, pnotes, (flip ? "true" : "false"), (pf == "" ? "false" : "true"), lc, pc, lw, pw, (ticket == "true" ? "true" : "false")
    printf ",\"v\":3,\"format\":\"%s\",\"lane_verdict\":%s,\"plain_verdict\":%s,\"lane_notes\":%d,\"lane_dismissed\":%d,\"lane_cites_plain\":%d,\"plain_merged\":%s", (rep ? "report" : "verdict"), (lv == "" ? "null" : "\"" lv "\""), (pv == "" ? "null" : "\"" pv "\""), lnotes, ldis, cites, (pf == "" ? "null" : merged + 0)
    printf ",\"m_b_b\":%s,\"m_b_n\":%s,\"m_b_0\":%s,\"m_n_b\":%s,\"m_n_n\":%s,\"m_n_0\":%s,\"m_d_b\":%s,\"m_d_n\":%s,\"m_d_0\":%s,\"m_0_b\":%s,\"m_0_n\":%s", mv("b_b"), mv("b_n"), mv("b_0"), mv("n_b"), mv("n_n"), mv("n_0"), mv("d_b"), mv("d_n"), mv("d_0"), mv("0_b"), mv("0_n")
    printf ",\"findings\":[%s],\"findings_omitted\":%d,\"other_comments\":%s} -->\n", fs, (nfl > 150 ? nfl - 150 : 0), ENVIRON["OC"]
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
        if (i in agreed) { print "- [lane+blind] " substr(s, 3); continue }
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
    DASH = " — "; DL = length(DASH)
    if (pf != "") while ((getline l < pf) > 0) {
      sub(/\r$/, "", l); praw[++nraw] = l
      if (pv == "" && match(l, /^verdict: (approve|needs-work)[ \t]*$/)) { pv = substr(l, 10); sub(/[ \t]+$/, "", pv) }
      if (l ~ /^## /) { psec = l; inb = 0; continue }
      if (psec !~ /^## Findings[ \t]*$/) continue
      if (l ~ /^- \[note\] ([BNH][0-9]+ )?([^ ]+ — )?ticket-unavailable([^A-Za-z0-9_-]|$)/) { ticket = "false"; inb = 0; continue }
      if (l ~ /^- \[note\] /) {
        pnotes++; nq++; t = l; sub(/^- \[note\] /, "", t); qid[nq] = "?"
        if (match(t, /^[BNH][0-9]+ /)) { qid[nq] = substr(t, 1, RLENGTH - 1); t = substr(t, RLENGTH + 1) }
        qtx[nq] = t; qloc[nq] = loc(t); inb = 0; continue
      }
      if (l ~ /^- \[blocker\] /) {
        np++; t = l; sub(/^- \[blocker\] /, "", t); pid[np] = "?"
        if (match(t, /^[BNH][0-9]+ /)) { pid[np] = substr(t, 1, RLENGTH - 1); t = substr(t, RLENGTH + 1) }
        ptext[np] = t; ploc[np] = loc(t); inb = 1; continue
      }
      if (inb && l ~ /^[ \t]+[^ \t]/) { c = l; sub(/^[ \t]+/, "", c); pcont[np] = pcont[np] "  " c "\n"; continue }
      inb = 0
    }
    rsec["Critical"] = "b"; rsec["Warnings"] = "n"; rsec["Suggestions"] = "n"; rsec["Pre-existing"] = "d"; rsec["Suppressed"] = "d"
    rlab["Critical"] = "Critical"; rlab["Warnings"] = "Warning"; rlab["Suggestions"] = "Suggestion"; rlab["Pre-existing"] = "Pre-existing"; rlab["Suppressed"] = "Suppressed"
  }
  { sub(/\r$/, ""); line[++n] = $0
    if ($0 ~ /^## /) { sec = $0; sub(/[ \t]+$/, "", sec); cur = 0; rs = sec; sub(/^## /, "", rs); sub(/ .*/, "", rs); if (!(rs in rsec)) rs = "" }
    else if (cur && $0 ~ /^[ \t]+[^ \t]/) lfull[cur] = lfull[cur] " " $0
    else if (rep) {
      cur = 0
      if (rs != "" && $0 ~ /^- / && $0 !~ /^- None\.?[ \t]*$/) {
        t = substr($0, 3); lab = rlab[rs]; if (match(t, /^\[[A-Za-z0-9 _.\/-]+\] /)) lab = lab " " substr(t, 1, RLENGTH - 1)
        j = addl(rsec[rs], lab, t)
        if (rs == "Critical") { nb++; bline[nb] = n; bloc[nb] = loc($0); lj[nb] = j }
      }
      else if (match($0, /^\*\*Ready to merge\?\*\*[ \t]*/)) { readyline = n; ready = substr($0, RLENGTH + 1); sub(/[ \t]+$/, "", ready) }
    }
    else if (sec == "## Findings" && match($0, /^- \[blocker\] B[0-9]+ /)) {
      r = RLENGTH; nb++; bline[nb] = n; bid[nb] = substr($0, 13, r - 13)
      id = substr($0, 14, r - 14) + 0; if (id > maxb) maxb = id
      bloc[nb] = loc(substr($0, r + 1)); lj[nb] = addl("b", bid[nb], substr($0, r + 1))
    }
    else if (sec == "## Findings" && $0 ~ /^- \[note\] /) {
      t = substr($0, 10); lab = "?"; if (match(t, /^[BNH][0-9]+ /)) { lab = substr(t, 1, RLENGTH - 1); t = substr(t, RLENGTH + 1) }
      addl(dismissed(t) ? "d" : "n", lab, t)
    }
    else cur = 0
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
        if (s == "Nothing to do.") { print "Fix the [blind] blockers in Findings."; continue }
      }
      if (sec == "## Findings") {
        if (s == "None." && nadd > 0) continue
        if (s ~ /^- \[note\] /) added()
        if (i in agreed) { match(s, /^- \[blocker\] B[0-9]+ /); print substr(s, 1, RLENGTH) "[lane+blind] " substr(s, RLENGTH + 1); continue }
      }
      print s
    }
    if (sec == "## Findings") added()
    if (sec != "## Notes") { print ""; print "## Notes"; if (pf == "") { print ""; print "Joined review: " why ", so this verdict is the lane review alone." } }
    devblock()
  }' "$lane"

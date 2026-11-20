#!/usr/bin/env bash
# verdict-join.sh — joins a lane review's verdict draft with a plain review's into the one verdict a harness posts.
#
# Usage:
#   verdict-join.sh <lane-draft> <plain-draft or ''> [--why <why plain is missing>] [--format verdict|report]
#                   [--lane-cost <usd>] [--plain-cost <usd>] [--lane-wall <s>] [--plain-wall <s>] [--ticket true|false]
#                   [--other-comments <other-comments.sh output>]
#
# --format report joins a review-lead report. The report is in the lane verdict grammar, so it is joined by the same
# rules; the format changes only the machine line's "format" and the wording of the Notes line when plain is missing.
#
# Every finding gates, so the body takes plain's blockers and notes. A plain blocker at the file of a lane blocker,
# within 3 lines of it, is that blocker, tagged [lane+blind]. Any other is added after the lane's blockers as [blind],
# numbered after the lane's highest B id. A plain note within 3 lines of any lane finding is that finding and is not
# listed again. A plain note within 3 lines of the site that starts a line of the lane's `## Notes` that quotes a
# decision is left out: the lane put a decision the operator made there, and plain never sees the record. A Notes line
# that starts with a site and quotes nothing, such as an inventory item, leaves out no note. Any other plain note is added after
# the lane's notes as [blind], numbered after the lane's highest N id. An added
# finding turns an approve into a needs-work: line 1 becomes `verdict: needs-work`, the Summary's first line `Not
# mergeable yet.`, and a `Nothing to do.` line names the [blind] findings. With no plain draft, `## Notes` says why
# and the lane's verdict stands as written.
#
# The body ends under `## Notes` with one visible line, `lane vs blind: <a> agreed, <d> rated differently, <l> lane
# alone, <p> blind alone` (plus `; blind flipped the verdict`), or `lane vs blind: the blind review did not return`,
# then one hidden `<!-- plain-vs-lane: {json} -->` line for scripts that aggregate across PRs. The counts pair every
# finding of both reviews, notes and dismissals included, one to one, by the same site rule (nearest first, then the
# same severity); the comment names the plain review "blind". The JSON's `lane_only` counts blockers only,
# `plain_only` the blind blockers and notes the join added, and `plain_notes_dropped` the blind notes it left out at a
# lane Notes site; `m_<lane>_<plain>` count pairs by class (b blocker, n note, d dismissed, 0 absent). Its `findings`
# lists one entry per finding of each review, disagreements first, capped at 150 with `findings_omitted` counting the
# rest; findings the join matched share a `pair` number. Cost and wall time are in the JSON alone, a lane passed none
# is null. Its `other_comments` is the --other-comments file when that file has the tool's shape, else null. A plain
# `ticket-unavailable` note, with or without a site before it, means plain reviewed the diff alone; it is in no count
# and no entry. Sites are a proxy: two findings at one site are paired whatever they say.
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
awk -v pf="$plain" -v why="$why" -v ticket="$ticket" -v fmt="$fmt" -v lc="$(num "$lc")" -v pc="$(num "$pc")" -v lw="$(num "$lw")" -v pw="$(num "$pw")" '
  # LOCKSTEP-BEGIN verdict-join-loc
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
  # LOCKSTEP-END verdict-join-loc
  function near(a, b,   pa, pb, d) {
    if (a == "" || b == "") return 0
    pa = a; sub(/:[0-9]+$/, "", pa); pb = b; sub(/:[0-9]+$/, "", pb); if (pa != pb) return 0
    d = substr(a, length(pa) + 2) - substr(b, length(pb) + 2); return d <= 3 && d >= -3
  }
  function lineof(a) { sub(/^.*:/, "", a); return a + 0 }
  function dist(a, b,   d) { if (!near(a, b)) return -1; d = lineof(a) - lineof(b); return d < 0 ? -d : d }
  function unready(s) { gsub(/Ready to merge\?/, "Ready to merge", s); return s }
  function added(   k, c) {
    if (done) return 0; done = 1
    for (k = 1; k <= np; k++) if (!pmatch[k]) { c++; print "- [blocker] " newid[k] " [blind] " unready(ptext[k]); printf "%s", unready(pcont[k]) }
    return c
  }
  function addedn(   k, c) {
    if (ndone) return 0; ndone = 1
    for (k = 1; k <= nq; k++) if (qnewid[k] != "") { c++; print "- [note] " qnewid[k] " [blind] " unready(qtx[k]); printf "%s", unready(qcont[k]) }
    return c
  }
  function postedas(i) { if (i <= np) return pmatch[i] ? "" : newid[i]; return qnewid[i - np] }
  function addl(c, lab, t) { nl++; lcls[nl] = c; llab[nl] = lab; lloc[nl] = loc(t); lfull[nl] = t; cur = nl; return nl }
  function dismissed(t,   p) { p = index(t, DASH); return t ~ /^(Dismissed|Suppressed)\./ || (p && substr(t, p + DL) ~ /^(Dismissed|Suppressed)\./) }
  function word(c) { return c == "b" ? "blocker" : c == "n" ? "note" : "dismissed" }
  function row(j, i,   k) {
    k = (j ? lcls[j] : "0") "_" (i ? pcl[i] : "0"); m[k]++
    nr++; rj[nr] = j; ri[nr] = i; rkey[nr] = rk[k] * 1000000 + j * 1000 + i
  }
  function pair2(   b, k, j, i, bj, bi, bd, bs, d, s) {
    split("0_b n_b d_b b_0 b_n b_b n_n d_n n_0 0_n", ord, " "); for (k = 1; k <= 10; k++) rk[ord[k]] = k
    for (i = 1; i <= np; i++) { pcl[i] = "b"; plab[i] = pid[i]; plc[i] = ploc[i] }
    for (i = 1; i <= nq; i++) { pcl[np + i] = "n"; plab[np + i] = qid[i]; plc[np + i] = qloc[i] }
    pt = np + nq
    for (b = 1; b <= nb; b++) if (bagreed[b]) {
      i = 0
      for (k = 1; k <= np; k++) if (pmatch[k] == b) { puse[k] = 1; if (!i) i = k; else merged++ }
      luse[lj[b]] = 1; row(lj[b], i)
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
      luse[bj] = 1; puse[bi] = 1; row(bj, bi)
    }
    for (j = 1; j <= nl; j++) if (!luse[j]) { if (lcls[j] == "d") m["d_0"]++; else row(j, 0) }
    for (i = 1; i <= pt; i++) if (!puse[i]) row(0, i)
    for (j = 1; j <= nr; j++) so[j] = j
    for (j = 2; j <= nr; j++) for (i = j; i > 1 && rkey[so[i - 1]] > rkey[so[i]]; i--) { k = so[i]; so[i] = so[i - 1]; so[i - 1] = k }
  }
  function mv(k) { return pf == "" ? "null" : m[k] + 0 }
  # loc() keeps only JSON-safe characters, and an id is [BNH]<n>, "?" or empty, so no value here needs escaping
  function q(s) { return s == "" || s == "?" ? "null" : "\"" s "\"" }
  function fent(src, id, c, l, pr, pa,   p) {
    p = l; sub(/:[0-9]+$/, "", p)
    nfl++; fl[nfl] = "{\"src\":\"" src "\",\"id\":" q(id) ",\"class\":\"" word(c) "\",\"path\":" q(p) ",\"line\":" (l == "" ? "null" : lineof(l)) ",\"pair\":" (pr ? pr : "null") (pa == "" ? "" : ",\"posted_as\":\"" pa "\"") "}"
  }
  function lent(j, pr) { fent("lane", llab[j], lcls[j], lloc[j], pr, "") }
  function bent(i, pr) { fent("blind", plab[i], pcl[i], plc[i], pr, postedas(i)) }
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
  function machine(   j, a, dd, la, pa, lv, rv, lnotes, ldis, cites, fs) {
    if (pf != "") pair2()
    fs = flist()
    for (j = 1; j <= nl; j++) { if (lcls[j] == "n") lnotes++; if (lcls[j] == "d") ldis++; if (tolower(lfull[j]) ~ /(plain|blind) review/) cites++ }
    a = m["b_b"] + m["n_n"]; dd = m["n_b"] + m["d_b"] + m["b_n"] + m["d_n"]; la = m["b_0"] + m["n_0"]; pa = m["0_b"] + m["0_n"]
    print ""
    if (pf == "") print "lane vs blind: the blind review did not return"
    else print "lane vs blind: " a + 0 " agreed, " dd + 0 " rated differently, " la + 0 " lane alone, " pa + 0 " blind alone" (flip ? "; blind flipped the verdict" : "")
    rv = substr(line[1], 10); lv = rv ~ /^(approve|needs-work)$/ ? rv : ""
    printf "<!-- plain-vs-lane: {\"lane_blockers\":%d,\"plain_blockers\":%d,\"agreed\":%d,\"lane_only\":%d,\"plain_only\":%d,\"plain_notes_dropped\":%d,\"flipped\":%s,\"plain_returned\":%s,\"lane_cost_usd\":%s,\"plain_cost_usd\":%s,\"lane_wall_s\":%s,\"plain_wall_s\":%s,\"ticket\":%s", nb, np, na, nb - na, nadd + naddn, ndrop, (flip ? "true" : "false"), (pf == "" ? "false" : "true"), lc, pc, lw, pw, (ticket == "true" ? "true" : "false")
    printf ",\"v\":3,\"format\":\"%s\",\"lane_verdict\":%s,\"plain_verdict\":%s,\"lane_notes\":%d,\"lane_dismissed\":%d,\"lane_cites_plain\":%d,\"plain_merged\":%s", fmt, (lv == "" ? "null" : "\"" lv "\""), (pv == "" ? "null" : "\"" pv "\""), lnotes, ldis, cites, (pf == "" ? "null" : merged + 0)
    printf ",\"m_b_b\":%s,\"m_b_n\":%s,\"m_b_0\":%s,\"m_n_b\":%s,\"m_n_n\":%s,\"m_n_0\":%s,\"m_d_b\":%s,\"m_d_n\":%s,\"m_d_0\":%s,\"m_0_b\":%s,\"m_0_n\":%s", mv("b_b"), mv("b_n"), mv("b_0"), mv("n_b"), mv("n_n"), mv("n_0"), mv("d_b"), mv("d_n"), mv("d_0"), mv("0_b"), mv("0_n")
    printf ",\"findings\":[%s],\"findings_omitted\":%d,\"other_comments\":%s} -->\n", fs, (nfl > 150 ? nfl - 150 : 0), ENVIRON["OC"]
  }
  function alone() { print ""; print "Joined review: " why ", so this " (fmt == "report" ? "report is review-lead alone." : "verdict is the lane review alone.") }
  BEGIN {
    DASH = " — "; DL = length(DASH)
    if (pf != "") while ((getline l < pf) > 0) {
      sub(/\r$/, "", l)
      if (pv == "" && match(l, /^verdict: (approve|needs-work)[ \t]*$/)) { pv = substr(l, 10); sub(/[ \t]+$/, "", pv) }
      if (l ~ /^## /) { psec = l; inb = 0; continue }
      if (psec !~ /^## Findings[ \t]*$/) continue
      if (l ~ /^- \[note\] ([BNH][0-9]+ )?([^ ]+ — )?ticket-unavailable([^A-Za-z0-9_-]|$)/) { ticket = "false"; inb = 0; continue }
      if (l ~ /^- \[note\] /) {
        nq++; t = l; sub(/^- \[note\] /, "", t); qid[nq] = "?"
        if (match(t, /^[BNH][0-9]+ /)) { qid[nq] = substr(t, 1, RLENGTH - 1); t = substr(t, RLENGTH + 1) }
        qtx[nq] = t; qloc[nq] = loc(t); inb = 2; continue
      }
      if (l ~ /^- \[blocker\] /) {
        np++; t = l; sub(/^- \[blocker\] /, "", t); pid[np] = "?"
        if (match(t, /^[BNH][0-9]+ /)) { pid[np] = substr(t, 1, RLENGTH - 1); t = substr(t, RLENGTH + 1) }
        ptext[np] = t; ploc[np] = loc(t); inb = 1; continue
      }
      if (inb && l ~ /^[ \t]+[^ \t]/) { c = l; sub(/^[ \t]+/, "", c); if (inb == 1) pcont[np] = pcont[np] "  " c "\n"; else qcont[nq] = qcont[nq] "  " c "\n"; continue }
      inb = 0
    }
  }
  { sub(/\r$/, ""); line[++n] = $0
    if ($0 ~ /^## /) { sec = $0; sub(/[ \t]+$/, "", sec); cur = 0 }
    else if (cur && $0 ~ /^[ \t]+[^ \t]/) lfull[cur] = lfull[cur] " " $0
    else if (sec == "## Findings" && match($0, /^- \[blocker\] B[0-9]+ /)) {
      r = RLENGTH; nb++; bline[nb] = n; bid[nb] = substr($0, 13, r - 13)
      id = substr($0, 14, r - 14) + 0; if (id > maxb) maxb = id
      bloc[nb] = loc(substr($0, r + 1)); lj[nb] = addl("b", bid[nb], substr($0, r + 1))
    }
    else if (sec == "## Findings" && $0 ~ /^- \[note\] /) {
      t = substr($0, 10); lab = "?"; if (match(t, /^[BNH][0-9]+ /)) { lab = substr(t, 1, RLENGTH - 1); t = substr(t, RLENGTH + 1) }
      if (lab ~ /^N/ && substr(lab, 2) + 0 > maxn) maxn = substr(lab, 2) + 0
      addl(dismissed(t) ? "d" : "n", lab, t)
    }
    else if (sec == "## Notes" && match($0, /^(- )?[^ \t]+/) && (nsl = loc(substr($0, RSTART, RLENGTH))) != "" && (index(substr($0, RLENGTH + 1), "\"") || index(substr($0, RLENGTH + 1), "“"))) { cur = 0; ns++; nsite[ns] = nsl }
    else cur = 0
  }
  END {
    for (k = 1; k <= np; k++) for (b = 1; b <= nb; b++) if (near(ploc[k], bloc[b])) { pmatch[k] = b; agreed[bline[b]] = 1; if (!bagreed[b]) na++; bagreed[b] = 1; break }
    for (k = 1; k <= np; k++) if (!pmatch[k]) { nadd++; newid[k] = "B" (maxb + nadd) }
    for (k = 1; k <= nq; k++) {
      for (j = 1; j <= nl; j++) if (near(qloc[k], lloc[j])) break
      if (j <= nl) continue
      for (j = 1; j <= ns; j++) if (near(qloc[k], nsite[j])) break
      if (j <= ns) ndrop++
      else { naddn++; qnewid[k] = "N" (maxn + naddn) }
    }
    flip = nadd + naddn > 0 && line[1] == "verdict: approve"
    sec = ""; first = 0
    for (i = 1; i <= n; i++) {
      s = line[i]
      if (i == 1 && flip) { print "verdict: needs-work"; continue }
      if (s ~ /^## /) {
        if (sec == "## Findings" && added() + addedn()) print ""
        sec = s; sub(/[ \t]+$/, "", sec); print s
        if (sec == "## Notes" && pf == "") alone()
        continue
      }
      if (sec == "## Summary" && flip) {
        if (!first && s ~ /[^ \t]/) { first = 1; print "Not mergeable yet."; continue }
        if (s == "Nothing to do.") { print "Fix the [blind] " (naddn ? "findings" : "blockers") " in Findings."; continue }
      }
      if (sec == "## Findings") {
        if (s == "None." && nadd + naddn > 0) continue
        if (s ~ /^- \[note\] /) added()
        if (i in agreed) { match(s, /^- \[blocker\] B[0-9]+ /); print substr(s, 1, RLENGTH) "[lane+blind] " substr(s, RLENGTH + 1); continue }
      }
      print s
    }
    if (sec == "## Findings") { added(); addedn() }
    if (sec != "## Notes") { print ""; print "## Notes"; if (pf == "") alone() }
    machine()
  }' "$lane"

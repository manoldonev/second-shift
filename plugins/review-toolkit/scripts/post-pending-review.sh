#!/usr/bin/env bash
# post-pending-review.sh — posts a review-lead report on its PR as a pending review, under the caller's own gh login.
#
# Usage: post-pending-review.sh [--check] [--repo <owner/name>] [--worktree <dir>] <pr> <report>
#
# The report is in the lane verdict grammar: line 1 `verdict: approve|needs-work`, line 2 `reviewed: <full sha>`, and
# `reviewed-by: second-shift review-lead` on line 3, or on line 4 after a `reason:` line. Before any gh call the report
# must pass dev-pipeline's verdict-check.sh in its no-record mode, found through plain-review-tools.sh; a report that
# fails it, or a checker that cannot run, is refused and nothing is posted. The sha is the review's commit_id. It must
# be the PR's head or one of its commits; when it is not the head, the review is still posted and the output says the
# PR has moved on. A pending review of the caller's already on the PR blocks the post: nothing is created or deleted.
# --check runs only these checks, before the offer, and writes nothing.
#
# Each `## Findings` entry whose first path:line is inside a hunk of `<PR base>...<sha>`, diffed in --worktree, is one
# inline comment on the right side: the defect and its continuation lines, without the id, the site and the
# [blocker]/[note] tag, with its reviewer tag kept and [blind] shown as [Blind review]. The body is the report without
# the inline findings. An inline [blocker] keeps one line `- [blocker] B<n> path:line — <first sentence>`, and when a
# note went inline `## Findings` ends with `<k> notes are inline comments.` A finding not posted inline stays in full.
# The machine line is kept byte for byte. When the base commit cannot be fetched, the review has no inline comments,
# the body is the whole report, and the output says why. An @-mention outside code is wrapped in backticks, so no one
# is notified.
#
# Writes: the one review creation, through plain gh. A failed create is reported and never retried.
# Exit: 0 posted, or --check found it postable · 1 refused or failed, the reason on stderr · 2 usage, or the report
# lacks its head lines.
set -uo pipefail
usage() { echo "usage: post-pending-review.sh [--check] [--repo <owner/name>] [--worktree <dir>] <pr> <report>" >&2; exit 2; }
REPO="" WT="." CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --repo) REPO="${2-}"; shift 2 ;;
    --worktree) WT="${2-}"; shift 2 ;;
    --*) usage ;;
    *) break ;;
  esac
done
[ $# -eq 2 ] || usage
PR="$1" REPORT="$2"
case "$PR" in ''|*[!0-9]*) usage ;; esac
[ -r "$REPORT" ] || { echo "post-pending-review: cannot read the report $REPORT" >&2; exit 2; }
l1="$(sed -n '1{s/\r$//;p;}' "$REPORT")"; l2="$(sed -n '2{s/\r$//;p;}' "$REPORT")"
l3="$(sed -n '3{s/\r$//;p;}' "$REPORT")"; l4="$(sed -n '4{s/\r$//;p;}' "$REPORT")"
case "$l1" in "verdict: approve"|"verdict: needs-work") : ;; *) echo "post-pending-review: line 1 of $REPORT is not its verdict line" >&2; exit 2 ;; esac
SHA="${l2#reviewed: }"
[ "$l2" != "$SHA" ] && [[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "post-pending-review: line 2 of $REPORT is not 'reviewed: <full sha>'" >&2; exit 2; }
case "$l3" in reason:*) by="$l4" ;; *) by="$l3" ;; esac
case "$by" in "reviewed-by: second-shift review-lead"*) : ;; *) echo "post-pending-review: $REPORT has no 'reviewed-by: second-shift review-lead' line on line 3, or on line 4 after a reason line" >&2; exit 2 ;; esac
die() { echo "post-pending-review: $*" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PT="$(bash "$HERE/plain-review-tools.sh" 2>&1)" || die "the report's format could not be checked: $PT; nothing posted"
[ -f "$PT/verdict-check.sh" ] || die "the report's format could not be checked: $PT has no verdict-check.sh; nothing posted"
vc="$(bash "$PT/verdict-check.sh" "$REPORT" 2>&1)"; vrc=$?
case "$vrc" in
  0) : ;;
  1) die "the report fails verdict-check.sh, so nothing is posted: $(tr '\n' ';' <<<"$vc" | sed 's/;$//; s/;/; /g')" ;;
  *) die "the report's format could not be checked (verdict-check.sh exit $vrc: $(tr '\n' ' ' <<<"$vc" | sed 's/ *$//')); nothing posted" ;;
esac

T="$(mktemp -d "${TMPDIR:-/tmp}/post-pending-review.XXXXXX")" || die "no temp dir"
trap 'rm -rf "$T"' EXIT

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner 2>/dev/null | jq -r '.nameWithOwner // empty' 2>/dev/null)"
  [ -n "$REPO" ] || die "the repo slug could not be read; pass --repo"
fi
me="$(gh api user 2>/dev/null | jq -r '.login // empty' 2>/dev/null)"
[ -n "$me" ] || die "your gh login could not be read"
refs="$(gh pr view "$PR" --repo "$REPO" --json headRefOid,baseRefOid 2>/dev/null | jq -r '"\(.headRefOid // "") \(.baseRefOid // "")"' 2>/dev/null)"
read -r HEAD BASE <<<"$refs"
[ -n "${HEAD:-}" ] && [ -n "${BASE:-}" ] || die "PR #$PR could not be read"
# The commit list stops at 250, so the head is accepted without it.
if [ "$SHA" != "$HEAD" ]; then
  commits="$(gh api "repos/$REPO/pulls/$PR/commits" --paginate 2>/dev/null | jq -r '.[].sha' 2>/dev/null)" \
    || die "the commits of PR #$PR could not be read"
  grep -qx "$SHA" <<<"$commits" \
    || die "the reviewed commit $SHA is not one of PR #$PR's commits (its head is $HEAD); nothing posted"
fi
pending="$(gh api "repos/$REPO/pulls/$PR/reviews" --paginate 2>/dev/null \
  | jq -r --arg me "$me" '.[] | select(.state == "PENDING" and (.user.login // "") == $me) | "\(.id) \(.html_url // "")"' 2>/dev/null)" \
  || die "the reviews of PR #$PR could not be read"
[ -z "$pending" ] || die "you already have a pending review on PR #$PR: $(head -1 <<<"$pending"); nothing created or deleted. Submit or delete it in the GitHub UI, then post again"
if [ "$CHECK" = 1 ]; then
  echo "the report can be posted on PR #$PR at $SHA"
  [ "$SHA" = "$HEAD" ] || echo "the PR has moved on: its head is now $HEAD, and the report reviewed $SHA"
  exit 0
fi

inline=1 why=""
git -C "$WT" cat-file -e "$BASE^{commit}" 2>/dev/null \
  || GIT_TERMINAL_PROMPT=0 git -C "$WT" fetch --quiet --no-tags origin "$BASE" >/dev/null 2>&1
if ! git -C "$WT" cat-file -e "$BASE^{commit}" 2>/dev/null; then inline=0 why="the PR's base commit $BASE could not be fetched"
elif ! git -C "$WT" cat-file -e "$SHA^{commit}" 2>/dev/null; then inline=0 why="the reviewed commit $SHA is not in $WT"
elif ! git -C "$WT" -c core.quotePath=false -c diff.interHunkContext=0 diff --no-color --no-ext-diff -M -U3 --src-prefix=a/ --dst-prefix=b/ "$BASE...$SHA" > "$T/diff" 2>/dev/null
then inline=0 why="git diff $BASE...$SHA failed"
fi
: > "$T/hunks"
# shellcheck disable=SC2016  # an awk program, not shell
[ "$inline" = 0 ] || awk '
  /^\+\+\+ / { p = substr($0, 5); sub(/\t$/, "", p); if (p == "/dev/null") p = ""; else sub(/^b\//, "", p); next }
  /^@@ / && p != "" { if (!match($0, /\+[0-9]+(,[0-9]+)?/)) next
    r = substr($0, RSTART + 1, RLENGTH - 1); s = r + 0; c = 1; if (index(r, ",")) c = substr(r, index(r, ",") + 1) + 0
    if (c > 0) print p "\t" s "\t" s + c - 1 }' "$T/diff" > "$T/hunks"

# shellcheck disable=SC2016  # an awk program, not shell
counts="$(awk -v dir="$T" -v inline="$inline" '
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
  function closing(r, n,   off) {
    off = 0
    while (match(r, /`+/)) {
      if (RLENGTH == n) return off + RSTART + RLENGTH - 1
      off += RSTART + RLENGTH - 1; r = substr(r, RSTART + RLENGTH)
    }
    return 0
  }
  # GitHub notifies on an @ that follows no word character and starts a handle, optionally /team, outside code
  function unmention(s,   out, c, run, rest, q, prev) {
    out = ""; prev = ""
    while (s != "") {
      c = substr(s, 1, 1)
      if (c == "`") {
        match(s, /^`+/); run = substr(s, 1, RLENGTH); rest = substr(s, RLENGTH + 1); q = closing(rest, RLENGTH)
        if (q) { out = out run substr(rest, 1, q); s = substr(rest, q + 1) } else { out = out run; s = rest }
        prev = "`"; continue
      }
      if (c == "@" && prev !~ /[A-Za-z0-9_]/ && match(s, /^@[A-Za-z0-9-]+(\/[A-Za-z0-9_-]+)?/)) {
        out = out "`" substr(s, 1, RLENGTH) "`"; s = substr(s, RLENGTH + 1); prev = "`"; continue
      }
      out = out c; prev = c; s = substr(s, 2)
    }
    return out
  }
  function fence(s) { return s ~ /^ ? ? ?(```|~~~)/ }
  # tag(t) is the reviewer tag an inline comment keeps; defect(t) is the text without the tags and the site
  function tag(t) {
    if (t ~ /^\[blind\] /) return "[Blind review]"
    sub(/^\[lane\+blind\] /, "", t)
    return match(t, /^\[[A-Za-z0-9 _.\/-]+\] /) ? substr(t, 1, RLENGTH - 1) : ""
  }
  function defect(t,   l, p, d) {
    sub(/^\[(blind|lane\+blind)\] /, "", t); sub(/^\[[A-Za-z0-9 _.\/-]+\] /, "", t)
    p = index(t, DASH)
    if (p) d = substr(t, p + DL)
    else { d = t; l = loc(d); if (l != "" && (p = index(d, l))) d = substr(d, 1, p - 1) substr(d, p + length(l)) }
    gsub(/^[ \t]+|[ \t]+$/, "", d); gsub(/[ \t][ \t]+/, " ", d)
    return d
  }
  function sentence(t,   r, p) {
    if (match(t, /\.( |$)/)) t = substr(t, 1, RSTART)
    if (length(t) > 160) { r = substr(t, 1, 160); for (p = 160; p > 0 && substr(r, p, 1) != " "; p--) ; if (p > 1) t = substr(r, 1, p - 1) "…" }
    return t
  }
  function inhunk(p, n,   k) { for (k = 1; k <= nh; k++) if (hp[k] == p && hs[k] <= n && n <= he[k]) return 1; return 0 }
  function out(s) { if (s ~ /^<!-- plain-vs-lane: /) b[++nb] = s; else if (fence(s)) { b[++nb] = s; infence = !infence } else b[++nb] = infence ? s : unmention(s) }
  function countline() {
    if (!ninote) return
    while (nb > 0 && b[nb] !~ /[^ \t]/) nb--
    out(""); out(ninote == 1 ? "1 note is an inline comment." : ninote " notes are inline comments."); out("")
  }
  BEGIN {
    DASH = " — "; DL = length(DASH)
    while ((getline l < (dir "/hunks")) > 0) { split(l, h, "\t"); nh++; hp[nh] = h[1]; hs[nh] = h[2] + 0; he[nh] = h[3] + 0 }
  }
  { sub(/\r$/, ""); raw[++n] = $0
    if ($0 ~ /^## /) { sec = $0; sub(/[ \t]+$/, "", sec); cur = 0; if (fstart && !fend) fend = n; if (sec == "## Findings") fstart = n; next }
    if (sec == "## Findings" && match($0, /^- \[(blocker|note)\] [BN][0-9]+ /)) {
      nf++; first[n] = nf; fe[nf] = n; fk[nf] = substr($0, 4, 1); fid[nf] = substr($0, 1, RLENGTH - 1); sub(/^.* /, "", fid[nf])
      ft[nf] = substr($0, RLENGTH + 1); fc[nf] = ""; cur = nf; next
    }
    if (sec == "## Findings" && cur && $0 ~ /^[ \t]+[^ \t]/) { c = $0; sub(/^[ \t]+/, "", c); fc[cur] = fc[cur] "\n" c; fe[cur] = n; next }
    if ($0 ~ /[^ \t]/) cur = 0
  }
  END {
    printf "" > (dir "/index")
    for (k = 1; k <= nf; k++) {
      l = loc(ft[k]); if (l == "" || !inline) continue
      p = l; sub(/:[0-9]+$/, "", p); ln = substr(l, length(p) + 2) + 0
      if (!inhunk(p, ln)) continue
      isin[k] = 1; site[k] = l; ni++; if (fk[k] == "n") ninote++
      f = dir "/c." k; t = tag(ft[k]); d = defect(ft[k])
      m = split((t == "" ? d : t " " d) fc[k], cl, "\n")
      for (j = 1; j <= m; j++) printf "%s%s", unmention(cl[j]), (j < m ? "\n" : "") > f
      close(f); print p "\t" ln "\t" f > (dir "/index")
    }
    close(dir "/index")
    for (i = 1; i <= n; i++) {
      if (i == fend) countline()
      if ((i in first) && isin[k = first[i]]) {
        if (fk[k] == "b") out("- [blocker] " fid[k] " " site[k] DASH sentence(defect(ft[k])))
        i = fe[k]; continue
      }
      out(raw[i])
    }
    if (!fend) countline()
    while (nb > 0 && b[nb] !~ /[^ \t]/) nb--
    for (k = 1; k <= nb; k++) print b[k] > (dir "/body")
    close(dir "/body")
    print ni + 0, nf - ni
  }' "$REPORT")" || die "the report could not be read"
read -r NIN NBODY <<<"$counts"

: > "$T/comments"
while IFS=$'\t' read -r p n f; do
  [ -n "$p" ] || continue
  jq -nc --arg p "$p" --argjson n "$n" --rawfile b "$f" '{path: $p, line: $n, side: "RIGHT", body: $b}' >> "$T/comments" || die "an inline comment could not be built"
done < "$T/index"
jq -n --arg sha "$SHA" --rawfile body "$T/body" --slurpfile c "$T/comments" \
  '{commit_id: $sha, body: ($body | rtrimstr("\n"))} + (if ($c | length) > 0 then {comments: $c} else {} end)' > "$T/payload" \
  || die "the review could not be built"

if ! resp="$(gh api --method POST "repos/$REPO/pulls/$PR/reviews" --input "$T/payload" 2>"$T/err")"; then
  die "the pending review was not created — $(tr '\n' ' ' < "$T/err" | sed 's/ *$//')"
fi
id="$(jq -r '.id // empty' <<<"$resp" 2>/dev/null)"; url="$(jq -r '.html_url // empty' <<<"$resp" 2>/dev/null)"
echo "posted pending review ${id:-?} on PR #$PR at $SHA${url:+: $url}"
[ "$SHA" = "$HEAD" ] || echo "the PR has moved on: its head is now $HEAD, and this review sits on $SHA"
echo "inline comments: $NIN; findings in the body only: $NBODY"
[ "$inline" = 1 ] || echo "no inline comments: $why"
echo "it is visible only to you until you submit it in the GitHub UI"

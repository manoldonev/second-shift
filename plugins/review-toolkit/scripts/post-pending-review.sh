#!/usr/bin/env bash
# post-pending-review.sh — posts a review-lead report on its PR as a pending review, under the caller's own gh login.
#
# Usage: post-pending-review.sh [--check] [--repo <owner/name>] [--worktree <dir>] <pr> <report>
#
# The report's line 1 is its `reviewed-by: second-shift review-lead` line and line 2 its `reviewed: <full sha>` line.
# That sha is the review's commit_id. It must be the PR's head or one of its commits; when it is not the head, the
# review is still posted and the output says the PR has moved on. A pending review of the caller's already on the PR
# blocks the post: nothing is created or deleted. --check runs only these checks, before the offer, and writes nothing.
#
# The body is the report without its folded `dev: lane vs blind` block; the block's hidden machine line is kept, byte
# for byte. Each Critical or Warning finding whose first path:line is inside a hunk of `<PR base>...<sha>`, diffed in
# --worktree, is also one inline comment on the right side. When the base commit cannot be fetched, the review has no
# inline comments and the output says why. An @-mention outside code is wrapped in backticks, so no one is notified.
#
# Writes: the one review creation, through plain gh. A failed create is reported and never retried.
# Exit: 0 posted, or --check found it postable · 1 refused or failed, the reason on stderr · 2 usage, or the report
# lacks its two head lines.
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
case "$l1" in "reviewed-by: second-shift review-lead"*) : ;; *) echo "post-pending-review: line 1 of $REPORT is not its reviewed-by line" >&2; exit 2 ;; esac
SHA="${l2#reviewed: }"
[ "$l2" != "$SHA" ] && [[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "post-pending-review: line 2 of $REPORT is not 'reviewed: <full sha>'" >&2; exit 2; }
die() { echo "post-pending-review: $*" >&2; exit 1; }

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
  function text(t,   tag, l, p, d) {
    sub(/^- /, "", t)
    if (match(t, /^\[blind\] /)) { tag = "[Blind review]"; t = substr(t, RLENGTH + 1) }
    else {
      if (match(t, /^\[lane\+blind\] /)) t = substr(t, RLENGTH + 1)
      if (match(t, /^\[[A-Za-z0-9 _.\/-]+\] /)) { tag = substr(t, 1, RLENGTH - 1); t = substr(t, RLENGTH + 1) }
    }
    p = index(t, DASH)
    if (p) d = substr(t, p + DL)
    else { d = t; l = loc(d); if (l != "" && (p = index(d, l))) d = substr(d, 1, p - 1) substr(d, p + length(l)); gsub(/\(confidence: [0-9]+\)/, "", d) }
    gsub(/^[ \t]+|[ \t]+$/, "", d); gsub(/[ \t][ \t]+/, " ", d)
    return tag == "" ? d : tag " " d
  }
  function inhunk(p, n,   k) { for (k = 1; k <= nh; k++) if (hp[k] == p && hs[k] <= n && n <= he[k]) return 1; return 0 }
  BEGIN {
    DASH = " — "; DL = length(DASH)
    while ((getline l < (dir "/hunks")) > 0) { split(l, h, "\t"); nh++; hp[nh] = h[1]; hs[nh] = h[2] + 0; he[nh] = h[3] + 0 }
  }
  { sub(/\r$/, "") }
  NR <= 2 { b[++nb] = $0; next }
  dev {
    if ($0 ~ /^<details>/) depth++
    else if ($0 ~ /^<\/details>/ && --depth == 0) dev = 0
    else if ($0 ~ /^<!-- plain-vs-lane: /) b[++nb] = $0
    next
  }
  /^<details><summary>dev: lane vs blind/ { dev = 1; depth = 1; next }
  /^<!-- plain-vs-lane: / { b[++nb] = $0; next }
  { if (fence($0)) { b[++nb] = $0; infence = !infence } else b[++nb] = infence ? $0 : unmention($0) }
  /^## / { sec = $0 ~ /^## (Critical|Warnings)/; cur = 0; next }
  sec && /^- / && !/^- None\.?[ \t]*$/ { nf++; ft[nf] = $0; fc[nf] = ""; cur = nf; next }
  sec && cur && /^[ \t]+[^ \t]/ { c = $0; sub(/^[ \t]+/, "", c); fc[cur] = fc[cur] "\n" c; next }
  { cur = 0 }
  END {
    while (nb > 2 && b[nb] !~ /[^ \t]/) nb--
    for (k = 1; k <= nb; k++) print b[k] > (dir "/body")
    close(dir "/body")
    printf "" > (dir "/index")
    for (k = 1; k <= nf; k++) {
      l = loc(ft[k]); if (l == "" || !inline) continue
      p = l; sub(/:[0-9]+$/, "", p); n = substr(l, length(p) + 2) + 0
      if (!inhunk(p, n)) continue
      f = dir "/c." k; ni++
      m = split(text(ft[k]) fc[k], cl, "\n")
      for (j = 1; j <= m; j++) printf "%s%s", unmention(cl[j]), (j < m ? "\n" : "") > f
      close(f); print p "\t" n "\t" f > (dir "/index")
    }
    close(dir "/index")
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

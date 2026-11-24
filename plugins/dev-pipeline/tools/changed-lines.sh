#!/usr/bin/env bash
# changed-lines.sh — the head the last lane review read, and the lines changed since then. Both review paths run it
# before a review: run.sh, and the manual /dev-pipeline:review. A review that gets a set is a later review: pass 2 and
# verdict-join.sh gate a new finding only on a changed line.
#
# Usage:
#   GH=<the gh the verdict is posted through> [GH_READ=<the gh that reads>] \
#     changed-lines.sh [--repo <owner/name>] -C <worktree> <pr> <head-sha> <out-file>
#
# The last reviewed head is line 2 of the latest lane verdict on the PR: a comment by a Bot or by the account $GH
# writes as, never edited, whose line 1 is `verdict: approve` or `verdict: needs-work` and whose line 2 is
# `reviewed: <40-hex sha>`. That is run.sh verdict()'s filter without its review window and without its match on the
# current head: a verdict that a moved head voided still reviewed its own sha in full. A verdict whose line 3 is a
# `reason:` line is skipped, because that review did not finish. The comments are read through $GH_READ (default $GH).
#
# A changed line is a line of the head within 3 lines of a hunk of `git diff -U0 <reviewed> <head>`, new side: the
# join's proximity rule. The two-dot content diff survives a rebase, and it also marks the base's own edits as changed.
# The out file holds one `<path>:<first>-<last>` range per line. An empty file means that nothing changed.
#
# Exit: 0 a later review: the set is in <out-file>, and stdout is `reviewed: <sha>` · 3 a full review: no set, the
# out file is removed, and stdout says why · 2 usage.
set -uo pipefail
GH="${GH:-gh}"; GH_READ="${GH_READ:-$GH}"
usage() { echo "usage: changed-lines.sh [--repo <owner/name>] -C <worktree> <pr> <head-sha> <out-file>" >&2; exit 2; }
REPO="" WT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    -C) WT="${2:-}"; shift 2 ;;
    *) break ;;
  esac
done
[ $# -eq 3 ] && [ -n "$WT" ] || usage
PR="$1" HEAD_SHA="$2" OUT="$3"
case "$PR" in ''|*[!0-9]*) usage ;; esac
rm -f "$OUT"
full() { echo "full review: $1"; exit 3; }

if [ -z "$REPO" ]; then
  REPO="$(cd "$WT" 2>/dev/null && "$GH_READ" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || REPO=""
  [ -n "$REPO" ] || full "the repo slug could not be read"
fi
me="$("$GH" api user --jq .login 2>/dev/null)" || me=""
raw="$("$GH_READ" api "repos/$REPO/issues/$PR/comments" --paginate 2>/dev/null)" || full "the comments of PR #$PR could not be read"
# --paginate prints one array per page
sha="$(printf '%s' "$raw" | jq -rs --arg me "$me" '
  [.[][] | select(.created_at == .updated_at)
    | select((.user.type // "") == "Bot" or (($me != "") and ((.user.login // "") == $me)))
    | ((.body // "") | split("\n") | map(sub("\r$"; ""))) as $l
    | select($l[0] | test("^verdict: (approve|needs-work)$"))
    | select(($l[1] // "") | test("^reviewed: [0-9a-f]{40}$"))
    | select(($l[2] // "") | test("^reason: ") | not)
    | {at: .created_at, id: (.id // 0), sha: ($l[1] | sub("^reviewed: "; ""))}]
  | sort_by(.at, .id) | last | .sha // empty' 2>/dev/null)" || full "the comments of PR #$PR could not be parsed"
[ -n "$sha" ] || full "PR #$PR has no earlier lane verdict"
git -C "$WT" cat-file -e "$sha^{commit}" 2>/dev/null || full "the reviewed sha $sha cannot be read"
git -C "$WT" cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null || full "the head $HEAD_SHA cannot be read"

diff="$(git -C "$WT" -c core.quotePath=false diff --no-ext-diff --no-textconv --no-color -U0 -M --src-prefix=a/ --dst-prefix=b/ "$sha" "$HEAD_SHA" 2>/dev/null)" \
  || full "git diff $sha $HEAD_SHA failed"
# shellcheck disable=SC2016  # an awk program, not shell
printf '%s\n' "$diff" | awk '
  /^diff --git / { p = ""; next }
  /^\+\+\+ / { p = substr($0, 5); if (p == "/dev/null") p = ""; else sub(/^b\//, "", p); next }
  /^@@ / && p != "" {
    match($0, /\+[0-9]+(,[0-9]+)?/); n = split(substr($0, RSTART + 1, RLENGTH - 1), a, ",")
    s = a[1] + 0; c = n > 1 ? a[2] + 0 : 1
    lo = s - 3; hi = (c == 0 ? s : s + c - 1) + 3; if (lo < 1) lo = 1
    print p ":" lo "-" hi
  }' > "$OUT.tmp" && mv "$OUT.tmp" "$OUT" || { rm -f "$OUT.tmp"; full "the changed-line set could not be written to $OUT"; }
echo "reviewed: $sha"

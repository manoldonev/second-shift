#!/usr/bin/env bash
# stage8-perrepo-review-selftest.sh — integration + drift guard for the be-fe-pair
# DUAL-target secondary-repo review loop (#48 Phase 4).
#
#   (A) INTEGRATION — reproduce the exact stages/8-code-review.md secondary-review loop
#       against a synthetic three-repo state (primary be with a diff, secondary fe with a
#       diff, secondary ml with NO diff) and assert: the primary is skipped (reviewed by
#       the main loop), fe records a completed-in-session crossBoundaryReviews entry, ml
#       records a skippedReviews no-diff entry, and Stage 8 then completes. The in-session
#       review itself is LLM work (a comment in the .md); the bash the loop actually runs
#       is the clean-worktree assertion + no-diff skip + the statectl writes — tested here.
#   (B) DRIFT GUARD — assert the .md loop still carries its load-bearing tokens.
set -uo pipefail
export GIT_AUTHOR_NAME=ss-selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=ss-selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="$HERE/statectl.sh"
STAGE8_MD="$HERE/stages/8-code-review.md"
FAILS=0
ok() { echo "  PASS: $1"; }
no() { echo "  FAIL: $1"; FAILS=$((FAILS+1)); }

echo "[stage8-perrepo-review-selftest]"

# ----------------------------------------------------------------- (A) integration ---
ROOT=$(mktemp -d)
(
cd "$ROOT" || exit 99
git init -q -b main . && git commit -q --allow-empty -m "root base"
mkdir -p .claude/pipeline-state
export STATECTL_STATE_DIR="$ROOT/.claude/pipeline-state"

mk_wt() {  # $1 = relpath, $2 = base branch, $3 = "diff" | "nodiff"
  local d="$ROOT/$1" leaf="${1##*/}"
  mkdir -p "$d"; git -C "$d" init -q -b "$2" .
  echo base > "$d/base.txt"; git -C "$d" add .; git -C "$d" commit -q -m base
  git -C "$d" checkout -q -b "claude/x-$leaf"
  if [[ "$3" == "diff" ]]; then
    echo feat > "$d/feat-$leaf.txt"; git -C "$d" add .; git -C "$d" commit -q -m feat
  fi   # nodiff: branch tip == base, no changes to review
}
mk_wt wt/be main  diff     # primary (flat mirror), has a diff
mk_wt wt/fe main  diff     # secondary, has a diff → in-session review
mk_wt wt/ml main  nodiff   # secondary, no diff → skipped

ISSUE_NUMBER=48
"$SC" init "$ISSUE_NUMBER" --run-id itest >/dev/null
"$SC" target-repos-set "$ISSUE_NUMBER" --repos "be fe ml" >/dev/null
"$SC" worktree-set "$ISSUE_NUMBER" --repo be --path wt/be --branch claude/x-be --base main >/dev/null
"$SC" worktree-set "$ISSUE_NUMBER" --repo fe --path wt/fe --branch claude/x-fe --base main >/dev/null
"$SC" worktree-set "$ISSUE_NUMBER" --repo ml --path wt/ml --branch claude/x-ml --base main >/dev/null
# Flat-mirror the primary (be) — this is what .worktreePath points at.
"$SC" worktree-set "$ISSUE_NUMBER" --path wt/be --branch claude/x-be --base main >/dev/null
# Advance to Stage 8 started with the primary review already recorded.
for s in 1 2 3 4 5 6 7; do
  "$SC" set-stage "$ISSUE_NUMBER" "$s" --status started >/dev/null
  case "$s" in
    1) "$SC" checkpoint "$ISSUE_NUMBER" 1 --json '{"verdict":"no-split","preflight":{"baseBranch":"main","workingTreeClean":true,"guardOutcome":"proceed-clean"}}' >/dev/null ;;
    4) "$SC" plan-review-set "$ISSUE_NUMBER" --overall pass >/dev/null ;;
    5) "$SC" checkpoint "$ISSUE_NUMBER" 5 --json '{"changedFiles":[]}' >/dev/null ;;
    6) for rr in be fe ml; do "$SC" verify-summary-set "$ISSUE_NUMBER" --repo "$rr" --json '{"format":"clean","test":"passed"}' >/dev/null; done ;;   # test key: the #98 content gate refuses a summary with no verifying lane run
    7) "$SC" checkpoint "$ISSUE_NUMBER" 7 --json "{\"ticketKey\":\"$ISSUE_NUMBER\",\"branch\":\"claude/x-be\",\"headSha\":\"$(git -C "$ROOT/wt/be" rev-parse HEAD)\",\"worktreePath\":\"wt/be\",\"deviations\":[]}" >/dev/null ;;
  esac
  "$SC" set-stage "$ISSUE_NUMBER" "$s" --status completed >/dev/null
done
"$SC" review-rounds "$ISSUE_NUMBER" --set 1 >/dev/null   # primary review done
"$SC" set-stage "$ISSUE_NUMBER" 8 --status started >/dev/null

statectl.sh() { "$SC" "$@"; }
# >>> BEGIN verbatim mirror of the secondary-review loop in stages/8-code-review.md >>>
PRIMARY_WT_REL="$(statectl.sh get "$ISSUE_NUMBER" '.worktreePath')"
REPO_ROOT="$(git rev-parse --show-toplevel)"
if [[ "$(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // [] | length')" -gt 1 ]]; then
  while IFS= read -r r; do
    R_WT_REL="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".worktreePath")"
    [[ "$R_WT_REL" == "$PRIMARY_WT_REL" ]] && continue
    R_WT="$REPO_ROOT/$R_WT_REL"
    R_BASE="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".base")"
    R_HEAD="$(git -C "$R_WT" rev-parse HEAD)"
    R_MB="$(git -C "$R_WT" merge-base HEAD "origin/$R_BASE" 2>/dev/null || git -C "$R_WT" merge-base HEAD "$R_BASE")"
    if ! { git -C "$R_WT" diff --quiet && git -C "$R_WT" diff --cached --quiet; }; then
      echo "[stage-8] FAIL: '$r' worktree is dirty — commit/stash/discard before resuming." >&2
      exit 1
    fi
    if [[ -z "$(git -C "$R_WT" diff --name-only "$R_MB..$R_HEAD")" ]]; then
      statectl.sh skipped-review-add "$ISSUE_NUMBER" --repo "$r" --reason "no changes on this repo's branch" >/dev/null
      continue
    fi
    statectl.sh cross-boundary-review-add "$ISSUE_NUMBER" --repo "$r" --status completed-in-session >/dev/null
  done < <(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // [] | .[]' 2>/dev/null | tr -d '"')
fi
# <<< END verbatim mirror <<<

cbr=$(statectl.sh get "$ISSUE_NUMBER" '.crossBoundaryReviews // [] | map(.repo) | sort | join(",")')
skr=$(statectl.sh get "$ISSUE_NUMBER" '.skippedReviews // [] | map(.repo) | join(",")')
[[ "$cbr" == "fe" ]] && ok "(a1) fe (secondary w/ diff) → completed-in-session review" || no "(a1) crossBoundaryReviews repos = '$cbr' (want fe)"
[[ "$skr" == "ml" ]] && ok "(a2) ml (secondary, no diff) → skippedReviews" || no "(a2) skippedReviews repos = '$skr' (want ml)"
[[ "$(statectl.sh get "$ISSUE_NUMBER" '.crossBoundaryReviews | map(select(.repo=="be")) | length')" == "0" ]] \
  && ok "(a3) primary (be) NOT double-reviewed by the secondary loop" || no "(a3) be leaked into crossBoundaryReviews"
if "$SC" set-stage "$ISSUE_NUMBER" 8 --status completed >/dev/null 2>&1; then
  ok "(a4) Stage 8 completes with primary review + fe cross-boundary + ml skip"
else
  no "(a4) Stage 8 completion rejected"
fi
exit $FAILS
)
FAILS=$((FAILS + $?))
rm -rf "$ROOT"

# --------------------------------------------------------------- (B) drift guard ---
drift() { grep -qF "$1" "$STAGE8_MD" && ok "(b) stage8 carries \`$1\` ($2)" || no "(b) stage8 MISSING \`$1\` ($2)"; }
drift 'cross-boundary-review-add' 'the secondary in-session/handoff writer call'
drift 'skipped-review-add' 'the no-diff skip writer call'
drift '.targetRepos // [] | length' 'the dual-target gate (single-target/non-pair skip the loop)'
drift 'worktree is dirty' 'the clean-worktree assertion'
drift 'the primary was reviewed by the main loop above' 'the primary-skip guard'

echo "[stage8-perrepo-review-selftest] $([[ $FAILS -eq 0 ]] && echo 'all green' || echo "$FAILS FAILURE(S)")"
[[ $FAILS -eq 0 ]]

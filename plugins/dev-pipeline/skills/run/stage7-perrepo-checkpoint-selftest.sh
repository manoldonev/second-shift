#!/usr/bin/env bash
# stage7-perrepo-checkpoint-selftest.sh — integration + drift guard for the be-fe-pair
# DUAL-target Stage-7 checkpoint block (#48 Phase 2).
#
# Stage bash blocks live in the executed .md files, not in a testable function, so this
# selftest reproduces the exact stages/7-doc-update.md dual-target block against a
# synthetic two-worktree state and asserts it composes a per-repo payload that
# validate_stage7_payload (per-repo branch) accepts on the checkpoint write.
#
# It carries no token-presence guard over the .md. That class — grep a literal out of a
# markdown file — asserts only that prose contains words, and cannot fail for a reason a
# reader of the diff would not already see. The mirror block below is instead pinned
# byte-for-byte against the stage doc by scripts/check-lockstep-pairs.sh.
set -uo pipefail
# Hermetic git identity — CI runners often have no global user.name/user.email, and this
# selftest makes real commits in throwaway repos. These env vars override config, so the
# commits succeed regardless of the host's git setup.
export GIT_AUTHOR_NAME=ss-selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=ss-selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="$HERE/statectl.sh"
FAILS=0
ok() { echo "  PASS: $1"; }
no() { echo "  FAIL: $1"; FAILS=$((FAILS+1)); }

echo "[stage7-perrepo-checkpoint-selftest]"

# ----------------------------------------------------------------- (A) integration ---
ROOT=$(mktemp -d)
(
cd "$ROOT" || exit 99
git init -q -b main . && git commit -q --allow-empty -m "root base"
mkdir -p .claude/pipeline-state
export STATECTL_STATE_DIR="$ROOT/.claude/pipeline-state"

mk_wt() {  # $1 = relpath, $2 = base branch
  local base="$2" d="$ROOT/$1" leaf="${1##*/}"
  mkdir -p "$d"; git -C "$d" init -q -b "$base" .
  echo base > "$d/base.txt"; git -C "$d" add .; git -C "$d" commit -q -m base
  git -C "$d" checkout -q -b "claude/x-$leaf"
  echo feat > "$d/feat-$leaf.txt"; git -C "$d" add .; git -C "$d" commit -q -m feat
}
mk_wt wt/be main
mk_wt wt/fe alpha   # FE on a different base branch — exercises per-repo base resolution

ISSUE_NUMBER=48
"$SC" init "$ISSUE_NUMBER" --run-id itest >/dev/null
"$SC" target-repos-set "$ISSUE_NUMBER" --repos "be fe" >/dev/null
"$SC" worktree-set "$ISSUE_NUMBER" --repo be --path wt/be --branch claude/x-be --base main >/dev/null
"$SC" worktree-set "$ISSUE_NUMBER" --repo fe --path wt/fe --branch claude/x-fe --base alpha >/dev/null
"$SC" verify-summary-set "$ISSUE_NUMBER" --repo be --json '{"format":"clean","test":"clean"}' >/dev/null
"$SC" verify-summary-set "$ISSUE_NUMBER" --repo fe --json '"skipped (inert diff — no JS/TS surface)"' >/dev/null

PLAN_PATH="docs/plans/x-48.md"; DEVIATIONS_JSON='[]'; FREE_NOTE=""
PLAN_RISKS_JSON='[]'; DOC_UPDATER_FINDINGS=""
QUALITY_PASS_JSON="$("$SC" get "$ISSUE_NUMBER" '.stages."6".qualityPass // {}')"
statectl.sh() { "$SC" "$@"; }   # the stage block calls `statectl.sh` (on PATH at runtime)

# >>> BEGIN verbatim mirror of the dual-target branch in stages/7-doc-update.md >>>
# LOCKSTEP-BEGIN stage7-dual-target
TARGET_REPOS_JSON="$(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // []')"
if [[ "$(echo "$TARGET_REPOS_JSON" | jq 'length')" -gt 1 ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  TICKET_LC="$(echo "$ISSUE_NUMBER" | tr '[:upper:]' '[:lower:]')"
  CHECKPOINT_JSON=$(
    echo "$TARGET_REPOS_JSON" | jq -r '.[]' | while IFS= read -r r; do
      R_WT_REL="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".worktreePath")"
      R_BRANCH="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".branch")"
      R_BASE="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".base")"
      R_WT="$REPO_ROOT/$R_WT_REL"
      R_HEAD="$(git -C "$R_WT" rev-parse HEAD)"
      R_MB="$(git -C "$R_WT" merge-base HEAD "origin/$R_BASE" 2>/dev/null || git -C "$R_WT" merge-base HEAD "$R_BASE")"
      R_CHANGED="$(git -C "$R_WT" diff --name-only "$R_MB..HEAD" | jq -R . | jq -s .)"
      R_VERIFY="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".verifySummary")"
      # build-checkpoint-7-perrepo wants a JSON object; an INERT-lane verifySummary is the
      # skipped-string — wrap it (same convention as the flat --verify-summary note above).
      echo "$R_VERIFY" | jq -e 'type == "object"' >/dev/null 2>&1 \
        || R_VERIFY="$(jq -n --arg s "$R_VERIFY" '{lane:"INERT",note:$s}')"
      statectl.sh build-checkpoint-7-perrepo \
        --repo "$r" --branch "$R_BRANCH" --head "$R_HEAD" \
        --worktree "$R_WT_REL" --changed-files "$R_CHANGED" --verify-summary "$R_VERIFY"
    done \
    | jq -s 'reduce .[] as $x ({}; .perRepo += $x.perRepo)' \
    | jq --arg k "$TICKET_LC" \
         --argjson tr "$TARGET_REPOS_JSON" \
         --arg pp "$PLAN_PATH" \
         --argjson dv "$DEVIATIONS_JSON" \
         --arg fn "$FREE_NOTE" \
         --argjson prisk "$PLAN_RISKS_JSON" \
         --arg du "$DOC_UPDATER_FINDINGS" \
         --argjson qps "$QUALITY_PASS_JSON" \
         '. + {ticketKey:$k, targetRepos:$tr, planPath:$pp, deviations:$dv, freeNote:$fn, planRisks:$prisk, docUpdaterFindings:$du, qualityPassSummary:$qps}'
  )
# LOCKSTEP-END stage7-dual-target
fi
# <<< END verbatim mirror <<<

[[ "$(echo "$CHECKPOINT_JSON" | jq -r '.perRepo|keys|join(",")')" == "be,fe" ]] \
  && ok "(a1) both target repos composed into perRepo" || no "(a1) perRepo keys: $(echo "$CHECKPOINT_JSON" | jq -c '.perRepo|keys')"
[[ "$(echo "$CHECKPOINT_JSON" | jq -r '.perRepo.be.changedFiles[0]')" == "feat-be.txt" ]] \
  && ok "(a2) be changedFiles recomputed from its worktree" || no "(a2) be changedFiles wrong"
[[ "$(echo "$CHECKPOINT_JSON" | jq -r '.perRepo.fe.verifySummary.lane')" == "INERT" ]] \
  && ok "(a3) fe INERT-string verifySummary wrapped to object" || no "(a3) fe verify wrap failed"
if "$SC" checkpoint "$ISSUE_NUMBER" 7 --json "$CHECKPOINT_JSON" >/dev/null 2>&1; then
  ok "(a4) checkpoint 7 accepted the composed per-repo payload (validate_stage7_payload per-repo branch)"
else
  no "(a4) checkpoint 7 REJECTED: $("$SC" checkpoint "$ISSUE_NUMBER" 7 --json "$CHECKPOINT_JSON" 2>&1 | head -1)"
fi
exit $FAILS
)
FAILS=$((FAILS + $?))
rm -rf "$ROOT"

echo "[stage7-perrepo-checkpoint-selftest] $([[ $FAILS -eq 0 ]] && echo 'all green' || echo "$FAILS FAILURE(S)")"
[[ $FAILS -eq 0 ]]

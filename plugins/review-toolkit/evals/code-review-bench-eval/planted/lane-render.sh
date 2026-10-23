#!/usr/bin/env bash
# lane-render.sh — the lane's model-free half on one case checkout, in run.sh's order: plan coverage, then fails
# without the change when the coverage passed, then the scheduler input and the review prompt. The functions are
# run.sh's own, extracted from it by planted.py, so what renders here is what the lane runs.
#
# Usage: lane-render.sh <functions.sh> <checkout> <state-dir> <scratch> <issue> <pr> <base-branch> <repo-slug> <branch>
# Writes into <state-dir>: gates.txt (plan_coverage=<rc> fails_without_change=<rc>), review-input-1.md, review.prompt,
# review.allow, and the gates' logs. Writes <scratch>/record-at-first.md, as run.sh does before a review.
# Exit: 0 rendered · 1 a gate stopped the case (gates.txt says which; nothing else is rendered) · 2 usage or an
# environment failure.
# shellcheck disable=SC2034  # the globals below are read by the functions extracted from run.sh
set -uo pipefail
[ $# -eq 9 ] || { echo "usage: lane-render.sh <functions.sh> <checkout> <state-dir> <scratch> <issue> <pr> <base-branch> <repo-slug> <branch>" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090  # the extracted functions are generated per run
. "$1" || exit 2
WT="$2"; STATE="$3"; SCRATCH="$4"; ISSUE="$5"; PR="$6"; BASE_NAME="$7"; REPO_SLUG="$8"; BRANCH="$9"
say() { echo "[lane] $*" >&2; }
terminal() { echo "[lane] terminal: $1 — $2" >&2; exit 2; }
TOOLS="$(cd "$HERE/../../../../dev-pipeline/tools" && pwd)" || exit 2
TRACKER=github; GH=gh; GH_READ=gh; BOT_OK=0; MCP_ALLOW=""; RENDER_CMD=""; DESIGN_PROVIDER=""
PLANS_DIR=docs/plans
RECORD_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-decisions.md"; PLAN_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-plan.md"
RECORD="$WT/$RECORD_REL"
CONFIG="$WT/.claude/second-shift.config.json"; CONFIG_JSON="$(cat "$CONFIG" 2>/dev/null)" || CONFIG_JSON="{}"
LOG_DIR="$STATE"; RED_TREE_MARK="$STATE/red-tree"; A=1
FIRST="$(git -C "$WT" log --format=%H --diff-filter=A -n 1 -- "$RECORD_REL")" && [ -n "$FIRST" ] || { echo "lane-render: no commit adds $RECORD_REL in $WT" >&2; exit 2; }
HEAD_SHA="$(git -C "$WT" rev-parse HEAD)" || exit 2
CHANGED="$(git -C "$WT" -c core.quotePath=false diff --name-only "$FIRST" HEAD)" || exit 2
mkdir -p "$STATE" "$SCRATCH" || exit 2

plan_coverage 1; pc=$?
fw=3
if [ "$pc" -eq 0 ]; then fails_without_change 1; fw=$?; fi
echo "plan_coverage=$pc fails_without_change=$fw" > "$STATE/gates.txt"
[ "$pc" -ne 1 ] && [ "$fw" -ne 1 ] || exit 1

review_input 1 || { echo "lane-render: cannot diff $FIRST..HEAD in $WT" >&2; exit 2; }
record_at_first > "$SCRATCH/record-at-first.md" || exit 2
review_prompt "$PR" "$STATE/review-input-1.md" > "$STATE/review.prompt" || exit 2
review_allowlist > "$STATE/review.allow" || exit 2

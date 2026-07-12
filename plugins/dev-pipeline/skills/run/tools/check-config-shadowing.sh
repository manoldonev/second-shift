#!/usr/bin/env bash
# check-config-shadowing.sh — EP-1 companion lockstep validator.
#
# The rule (report defect #1): a config key that the schema publishes but no stage reads is the
# worst kind of surface rot — a consumer sets it, nothing happens, trust erodes. This validator
# fails closed if any `stageParams` key promoted to config is NOT read by its owning stage/tool
# file (i.e. a hardcoded literal still shadows the config key).
#
# Usage: check-config-shadowing.sh [dev-pipeline-skill-dir]   (exit 1 on any shadow)
set -euo pipefail
DP="${1:-$(cd "$(dirname "$0")/.." && pwd)}"   # .../skills/run
fails=0

# Each config key promoted from a hardcoded literal must be READ (referenced) by the
# file(s) that own its resolution — stageParams, plansDir, and the base/prefix keys
# (tracker.branchPrefix, topology.repos.<host>.baseBranch) threaded through stages 1/2/5/9.
# form: "<relative-file>|<config-key-reference>|<label>"
CHECKS=(
  "stages/6-verify.md|stageParams.visualCapture|Stage-6 visual capture"
  "SKILL.md|stageParams.requiredLabels|required labels"
  "verifyctl.sh|stageParams.formatGlob|format glob"
  "stages/3-write-plan.md|stageParams.planFilePattern|plan-file pattern"
  "stages/3-write-plan.md|paths.plansDir|plans dir"
  "stages/1-intake.md|tracker.branchPrefix|Stage-1 branch prefix"
  "stages/1-intake.md|baseBranch|Stage-1 base branch"
  "stages/2-worktree.md|tracker.branchPrefix|Stage-2 branch prefix"
  "stages/2-worktree.md|baseBranch|Stage-2 base branch"
  "stages/5-implement.md|baseBranch|Stage-5 base branch"
  "stages/9-open-pr.md|baseBranch|Stage-9 base branch"
)

for c in "${CHECKS[@]}"; do
  IFS='|' read -r rel key label <<< "$c"
  f="$DP/$rel"
  if [[ ! -f "$f" ]]; then
    echo "SHADOW-CHECK: missing file $rel (cannot verify $label)"; fails=$((fails+1)); continue
  fi
  if ! grep -qF "$key" "$f"; then
    echo "SHADOW: '$key' is published in the schema but $rel does not read it ($label) — a hardcoded literal still shadows the config key"
    fails=$((fails+1))
  fi
done

if [[ "$fails" -gt 0 ]]; then
  echo "check-config-shadowing: $fails shadow(s)" >&2
  exit 1
fi
echo "check-config-shadowing: clean"

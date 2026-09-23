#!/usr/bin/env bash
# check-config-shadowing.sh — every published config key keeps a reader.
#
# A config key that the schema publishes but nothing reads is the
# worst kind of surface rot — a consumer sets it, nothing happens, trust erodes. This validator
# fails closed if any key promoted to config is NOT read by its owning tool/skill file
# (i.e. a hardcoded literal still shadows the config key).
#
# Usage: check-config-shadowing.sh [dev-pipeline-plugin-dir]   (exit 1 on any shadow)
set -euo pipefail
DP="${1:-$(cd "$(dirname "$0")/.." && pwd)}"   # .../plugins/dev-pipeline
fails=0

# Each published config key must be READ (referenced) by the file that owns its resolution.
#
# Keys whose reader is in a SIBLING plugin are deliberately absent: this validator is anchored
# at $DP and cannot see review-toolkit or second-shift. `reviewers.webComponentGlobs` (read by
# review-lead/SKILL.md) is one.
#
# form: "<relative-file>|<config-key-reference>|<label>"
CHECKS=(
  "skills/run/run.sh|paths.plansDir|plans dir"
  "skills/run/run.sh|extraLanes|commands.<id>.extraLanes"
  "skills/run/run.sh|allowUnverified|commands.<id>.allowUnverified zero-check opt-out"
  "skills/run/run.sh|design.liveRender|design live-render command"
  "skills/run/run.sh|design.liveRender.smokeCommand|route smoke"
  "skills/run/run.sh|run.maxRounds|round cap"
  "skills/run/run.sh|run.checksRedMax|checks-red cap"
  "skills/run/run.sh|run.buildTimeoutSeconds|build session timeout"
  "skills/run/run.sh|run.reviewTimeoutSeconds|review session timeout"
  "skills/run/run.sh|run.costCeilingUsd|cost ceiling"
  "tools/branch-prefix.sh|tracker.branchPrefix|work-branch namespace"
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

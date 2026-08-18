#!/usr/bin/env bash
# check-config-shadowing.sh — EP-1 companion lockstep validator.
#
# The rule (report defect #1): a config key that the schema publishes but nothing reads is the
# worst kind of surface rot — a consumer sets it, nothing happens, trust erodes. This validator
# fails closed if any key promoted to config is NOT read by its owning tool/skill file
# (i.e. a hardcoded literal still shadows the config key).
#
# Usage: check-config-shadowing.sh [dev-pipeline-plugin-dir]   (exit 1 on any shadow)
set -euo pipefail
DP="${1:-$(cd "$(dirname "$0")/.." && pwd)}"   # .../plugins/dev-pipeline
fails=0

# Each config key promoted from a hardcoded literal must be READ (referenced) by the
# file(s) that own its resolution.
#
# #348 RE-ANCHORED. Every row used to name a `stages/*.md` file; the staged lane is gone, so
# each surviving key is now anchored to its surviving reader. Three rows did not survive the
# move, for two different reasons (spec ledger D-17):
#
#   - `stageParams.visualCapture` is RETIRED outright — the advisory smoke-capture was
#     its only consumer, so no reader remains. config-lint.sh's removed-key arm rejects it,
#     the established dead-key pattern (docs/migrations/v1-to-v2.md).
#   - `stageParams.formatGlob` and `gates.mutation` are KEPT keys and still schema-legal:
#     each lost its EXECUTOR but retains a reader in onboard's
#     config-grill.sh (the `T2.formatGlob` waiver; the mutation-seam findings). They are
#     absent from CHECKS for the sibling-plugin reason below, NOT because they are dead.
#
# Keys whose reader is in a SIBLING plugin are deliberately absent: this validator is anchored
# at $DP and cannot see review-toolkit or second-shift. `stageParams.webComponentGlobs` (read
# by review-lead/SKILL.md) is one, as are the two above; scripts/lockstep-manifest.tsv and
# config-grill.sh's own key list carry those pairings instead.
#
# form: "<relative-file>|<config-key-reference>|<label>"
CHECKS=(
  "tools/pipeline-doctor.sh|stageParams.requiredLabels|required labels"
  "tools/is-inert-diff.sh|inertPattern|INERT-lane classifier override"
  "tools/preflight.sh|stageParams.planFilePattern|plan-file pattern"
  "skills/build-lean/lean-gate.sh|paths.plansDir|plans dir"
  "skills/build-lean/lean-gate.sh|baseBranch|lean base branch"
  "skills/build-lean/lean-gate.sh|extraLanes|commands.<host>.extraLanes (#379)"
  "skills/build-lean/lean-gate.sh|design.liveRender|design live-render verification"
  "skills/build-lean/branch-prefix.sh|tracker.branchPrefix|work-branch namespace"
  "skills/run-lean/SKILL.md|ticketTag|topology.repos.<id>.ticketTag pair routing (#4)"
  # #15: extended BEYOND stageParams — every published key that gained a reader
  # must keep it, or the dead-key class (a config key nothing reads) ships again.
  "workflows/mutation-gate.mjs|unitTestScope|commands.<host>.unitTestScope"
  "workflows/mutation-gate.mjs|testFile|commands.<host>.testFile"
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

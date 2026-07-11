#!/usr/bin/env bash
# stage-times.sh — per-stage EFFECTIVE-time report for a dev-pipeline run.
#
# Reads stages.N.startedAt/completedAt from the run's state file and prints a
# duration table plus inter-stage gap times (comment posting / transition
# overhead lives in the gaps). Feed for /pipeline-retro and for runtime
# optimization decisions — optimize from this data, not from impressions.
#
# Pause-aware: a paused/resumed run (session-quota exhaustion → resume hours
# later) records closed `pauseSpans[]` (see state-schema.md). This tool subtracts
# that idle time so the total and per-stage numbers reflect actual compute time,
# not wall-clock. `effective_total = max(0, wall − Σ pause) `; per-stage subtracts
# the pause/stage-window overlap. The inter-stage gap rows stay wall-based (they
# measure transition overhead, not stage compute). On a never-paused run
# (pauseSpans absent ⇒ []) effective == wall.
#
# Usage:
#   bash .claude/skills/run/tools/stage-times.sh <issue-number>
#
# State location: mirrors statectl.sh state_dir()'s precedence exactly so a fixture
# pointed at by $STATECTL_STATE_DIR is assertable through this tool:
#   1. $STATECTL_STATE_DIR (used to point at a committed fixture), else
#   2. the consumer repo's main checkout (SECOND_SHIFT_REPO_ROOT, else the main
#      checkout derived from `git rev-parse --git-common-dir` — worktree-safe) with
#      subdir .claude/pipeline-state (config paths.pipelineStateDir overrides), else
#   3. cwd-relative .claude/pipeline-state (legacy fallback).

set -uo pipefail

ISSUE="${1:-}"
[[ -n "$ISSUE" ]] || { echo "usage: stage-times.sh <issue-number>" >&2; exit 2; }

state_dir() {
  if [[ -n "${STATECTL_STATE_DIR:-}" ]]; then
    printf '%s\n' "$STATECTL_STATE_DIR"; return 0
  fi
  local root="" common_dir cfg rel=".claude/pipeline-state"
  if [[ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]]; then
    root="$SECOND_SHIFT_REPO_ROOT"
  elif common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"; then
    common_dir="$(cd "$common_dir" && pwd)"
    root="$(dirname "$common_dir")"
  fi
  if [[ -n "$root" ]]; then
    cfg="${SECOND_SHIFT_CONFIG:-$root/.claude/second-shift.config.json}"
    if [[ -f "$cfg" ]]; then
      rel="$(jq -r '.paths.pipelineStateDir // ".claude/pipeline-state"' "$cfg" 2>/dev/null)" \
        || rel=".claude/pipeline-state"
    fi
    printf '%s\n' "$root/$rel"; return 0
  fi
  printf '%s\n' ".claude/pipeline-state"
}

STATE="$(state_dir)/${ISSUE}.json"
[[ -f "$STATE" ]] || { echo "no state file at $STATE" >&2; exit 2; }

# jq strptime is portable (BSD `date -j -f` is not).
jq -r '
  def ts: strptime("%Y-%m-%dT%H:%M:%SZ") | mktime;
  def minutes($s): ($s / 60 * 10 | round) / 10;
  (.pauseSpans // []) as $spans
  | ([ $spans[] | (.to | ts) - (.from | ts) ] | add // 0) as $pausedSecs
  | (.stages | to_entries | sort_by(.key | tonumber)) as $st
  # Tolerates a lifecycle-less final stage (e.g. a Stage 9 that never wrote
  # startedAt — see #174): the select() drops any stage missing startedAt or
  # completedAt from the per-stage table and gap computation rather than crashing.
  | ($st | map(select(.value.startedAt and .value.completedAt))) as $done
  | ((.lastUpdatedAt | ts) - (.startedAt | ts)) as $wall
  | ([0, $wall - $pausedSecs] | max) as $effTotal
  | "run: #\(.ticketKey)  runId: \(.runId)  status: \(.status)",
    "total: \(minutes($effTotal)) min effective  (wall \(minutes($wall)) min, paused \(minutes($pausedSecs)) min)  (\(.startedAt) -> \(.lastUpdatedAt))",
    "",
    "stage  effective   window",
    ($done[]
      | (.value.startedAt | ts) as $ss | (.value.completedAt | ts) as $ee
      # overlap(stage, span) = max(0, min(ends) - max(starts)); sum over spans.
      | ([ $spans[] | ([0, ([$ee, (.to | ts)] | min) - ([$ss, (.from | ts)] | max)] | max) ] | add // 0) as $ov
      | "  \(.key)    \(minutes(($ee - $ss) - $ov)) min   \(.value.startedAt | sub(".*T";"")) -> \(.value.completedAt | sub(".*T";""))"),
    "",
    "inter-stage gaps (transition overhead — comments, label edits):",
    ($done as $d | [range(1; $d | length)] | map(
      ($d[. - 1]) as $prev | ($d[.]) as $cur
      | "  \($prev.key) -> \($cur.key): \((((($cur.value.startedAt | ts) - ($prev.value.completedAt | ts))) / 60 * 10 | round) / 10) min"
    ) | .[])
' "$STATE"

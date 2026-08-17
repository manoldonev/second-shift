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
#   bash "${CLAUDE_PLUGIN_ROOT}/tools/stage-times.sh" [--json] <issue-number>
#
# --json emits the same numbers as a single JSON object instead of the text table,
# for programmatic consumers (tools/stage-envelopes.sh). It is ADDITIVE: the default
# text output is unchanged, and both renderers read from ONE model computed once in
# the jq program below — there is no second copy of the pause arithmetic, so the two
# cannot drift. stage-envelopes-selftest.sh's (env16) pins the arithmetic and (env16b)
# asserts the two renderers agree on the same committed fixture. (Those were
# statectl-selftest's (pause3)/(pause4) until #348 deleted that suite with the staged
# lane; they were re-homed rather than dropped.)
#
# The argument is a state-file BASENAME STEM, not strictly an issue number: snapshot
# files whose basename differs from their ticketKey (e.g. `42-aborted-<ts>`) are
# addressed by passing that stem. stage-envelopes.sh depends on this to reach every
# run in its corpus.
#
# State location: mirrors statectl.sh state_dir()'s precedence exactly so a fixture
# pointed at by $STATECTL_STATE_DIR is assertable through this tool:
#   1. $STATECTL_STATE_DIR (used to point at a committed fixture), else
#   2. the consumer repo's main checkout (SECOND_SHIFT_REPO_ROOT, else the main
#      checkout derived from `git rev-parse --git-common-dir` — worktree-safe) with
#      subdir .claude/pipeline-state (config paths.pipelineStateDir overrides), else
#   3. cwd-relative .claude/pipeline-state (legacy fallback).

set -uo pipefail

EMIT_JSON=false
if [[ "${1:-}" == "--json" ]]; then
  EMIT_JSON=true; shift
fi

ISSUE="${1:-}"
[[ -n "$ISSUE" ]] || { echo "usage: stage-times.sh [--json] <issue-number>" >&2; exit 2; }

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
#
# ONE model, TWO renderers. Everything numeric is computed once into $m below; the
# text and --json branches only FORMAT it. Adding a renderer must never mean adding
# arithmetic — that is the property (pause4) asserts.
jq -r --argjson emit_json "$EMIT_JSON" '
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
  | {
      ticketKey: .ticketKey,
      runId: .runId,
      status: .status,
      mode: .mode,
      startedAt: .startedAt,
      lastUpdatedAt: .lastUpdatedAt,
      sessionIds: [ (.pipelineSessions // [])[] | .sessionId // empty ],
      sessionCount: ((.pipelineSessions // []) | length),
      pauseSpanCount: ($spans | length),
      wallMin: minutes($wall),
      pausedMin: minutes($pausedSecs),
      effectiveTotalMin: minutes($effTotal),
      stages: [ $done[]
        | (.value.startedAt | ts) as $ss | (.value.completedAt | ts) as $ee
        # overlap(stage, span) = max(0, min(ends) - max(starts)); sum over spans.
        | ([ $spans[] | ([0, ([$ee, (.to | ts)] | min) - ([$ss, (.from | ts)] | max)] | max) ] | add // 0) as $ov
        | { stage: .key,
            effectiveMin: minutes(($ee - $ss) - $ov),
            startedAt: .value.startedAt,
            completedAt: .value.completedAt } ],
      # Stages recorded in state but dropped from the table for a missing lifecycle
      # field. Consumers need these BY NAME — an omitted stage is invisible, which is
      # exactly how a dropped stage comes to read as a fast one (perf-retro signal 5).
      droppedStages: [ $st[] | select((.value.startedAt and .value.completedAt) | not) | .key ],
      gaps: [ $done as $d | range(1; $d | length)
        | ($d[. - 1]) as $prev | ($d[.]) as $cur
        | { from: $prev.key, to: $cur.key,
            minutes: minutes((($cur.value.startedAt | ts) - ($prev.value.completedAt | ts))) } ]
    } as $m
  | if $emit_json then ($m | tojson)
    else
      "run: #\($m.ticketKey)  runId: \($m.runId)  status: \($m.status)",
      "total: \($m.effectiveTotalMin) min effective  (wall \($m.wallMin) min, paused \($m.pausedMin) min)  (\($m.startedAt) -> \($m.lastUpdatedAt))",
      "",
      "stage  effective   window",
      ($m.stages[]
        | "  \(.stage)    \(.effectiveMin) min   \(.startedAt | sub(".*T";"")) -> \(.completedAt | sub(".*T";""))"),
      "",
      "inter-stage gaps (transition overhead — comments, label edits):",
      ($m.gaps[] | "  \(.from) -> \(.to): \(.minutes) min")
    end
' "$STATE"

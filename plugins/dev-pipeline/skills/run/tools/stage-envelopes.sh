#!/usr/bin/env bash
# stage-envelopes.sh — per-stage TIME and per-bucket COST envelopes over the run corpus,
# plus over-envelope flags for one run.
#
# The over-half of manifesto P4: derive a reference distribution from the recorded corpus
# so "this run was expensive" becomes a measurement instead of an impression. ADVISORY —
# nothing here gates. Its two consumers (perf-retro's report, pipeline-doctor's WARN-only
# section) are pure callers; NOTHING is stored, so the envelopes are recomputed from the
# corpus on every invocation and cannot go stale.
#
# Usage:
#   bash stage-envelopes.sh [--window N] [--run <stem>] [--min-n N] [--json]
#                           [--mtime-prefilter] [--state-dir <dir>]
#
#   --window N        runs in the TIME window, newest first by startedAt (default 15,
#                     matching perf-retro's default profile window)
#   --run <stem>      the run under test (default: the newest run in the window)
#   --min-n N         minimum trusted windows required to emit an envelope (default 8)
#   --json            emit the model as JSON instead of the text report
#   --mtime-prefilter cap enumeration at the newest ~3N files by mtime before the real
#                     startedAt ordering (a speed knob for pipeline-doctor's pre-flight;
#                     see the honesty note at the flag's implementation below)
#
# THE PREDICATE (D-5). A stage/bucket flags when its value exceeds the corpus p90,
# nearest-rank, computed LEAVE-ONE-OUT (the run under test never inflates the envelope it
# is measured against), over trusted windows only. The min-n floor is evaluated on the
# POST-exclusion corpus (D-7), so no envelope is ever backed by fewer than --min-n windows;
# below the floor a known-unknown row is emitted and never a flag. At small n, "exceeds
# p90" frequently just means "set a new record" — the report says so rather than implying
# a stable distribution it does not have.
#
# PAUSE ARITHMETIC IS NOT REIMPLEMENTED HERE. Per-stage effective durations come from
# `stage-times.sh --json`, which stays the single owner of the pause/window overlap math.
#
# State location: mirrors statectl.sh state_dir()'s precedence exactly, so a fixture
# pointed at by $STATECTL_STATE_DIR is assertable through this tool (the technique
# stage-envelopes-selftest.sh uses).

set -uo pipefail

WINDOW=15
MIN_N=8
RUN_UNDER_TEST=""
EMIT_JSON=false
MTIME_PREFILTER=false
STATE_DIR_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --window) WINDOW="${2:-}"; shift 2 ;;
    --min-n) MIN_N="${2:-}"; shift 2 ;;
    --run) RUN_UNDER_TEST="${2:-}"; shift 2 ;;
    --state-dir) STATE_DIR_ARG="${2:-}"; shift 2 ;;
    --json) EMIT_JSON=true; shift ;;
    --mtime-prefilter) MTIME_PREFILTER=true; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "stage-envelopes.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

case "$WINDOW" in ''|*[!0-9]*) echo "stage-envelopes.sh: --window must be a positive integer" >&2; exit 2 ;; esac
case "$MIN_N" in ''|*[!0-9]*) echo "stage-envelopes.sh: --min-n must be a positive integer" >&2; exit 2 ;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_TIMES="$SCRIPT_DIR/stage-times.sh"

state_dir() {
  if [[ -n "$STATE_DIR_ARG" ]]; then
    printf '%s\n' "$STATE_DIR_ARG"; return 0
  fi
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

STATE_DIR="$(state_dir)"
[[ -d "$STATE_DIR" ]] || { echo "stage-envelopes.sh: no state dir at $STATE_DIR" >&2; exit 2; }

# ── Corpus enumeration ────────────────────────────────────────────────────────────
# Run-state files only: a top-level `stages` key, minus BOTH quarantine families. The
# key gate alone is not enough — `*-released-*` is a complete state file with `stages`
# intact and would otherwise aggregate as a live run. Identical case pattern to
# perf-retro Step 1 and pipeline-doctor section 8, deliberately.
CANDIDATES=()
if [[ "$MTIME_PREFILTER" == "true" ]]; then
  # HONESTY NOTE (D-9): mtime order is a BEST-EFFORT superset of the top-N-by-startedAt
  # set, not a proven one — a run can be touched recently but have started long ago, so
  # a long-untouched live file can in principle fall outside the newest 3N. This flag is
  # a speed knob for a WARN-only pre-flight caller, where a miss costs a missed hint and
  # can never produce a wrong flag. Final selection and ordering below are ALWAYS by
  # startedAt, never by mtime. Do not reach for this flag on the reporting path.
  # shellcheck disable=SC2012  # `ls -t` over statectl-generated names only: every file
  # here is `<ticketKey>[-<suffix>].json` written by statectl, so there are no newlines
  # or exotic characters to mishandle. The portable alternative (stat-based sorting)
  # needs a BSD/GNU fork this speed knob does not earn.
  while IFS= read -r f; do CANDIDATES+=("$f"); done < <(
    ls -t "$STATE_DIR"/*.json 2>/dev/null | head -n $((WINDOW * 3))
  )
else
  while IFS= read -r f; do CANDIDATES+=("$f"); done < <(ls "$STATE_DIR"/*.json 2>/dev/null)
fi

CORPUS_FILE_COUNT=0
ROWS=""
for f in "${CANDIDATES[@]}"; do
  [[ -f "$f" ]] || continue
  case "$(basename "$f")" in *-stale-*|*-released-*) continue ;; esac
  [[ "$(jq -r 'has("stages")' "$f" 2>/dev/null)" == "true" ]] || continue
  CORPUS_FILE_COUNT=$((CORPUS_FILE_COUNT + 1))
  stem="$(basename "$f" .json)"
  tk="$(jq -r '.ticketKey // ""' "$f" 2>/dev/null)"
  sa="$(jq -r '.startedAt // ""' "$f" 2>/dev/null)"
  ROWS+="${sa}"$'\t'"${stem}"$'\t'"${tk}"$'\n'
done

[[ -n "$ROWS" ]] || { echo "stage-envelopes.sh: no run-state files under $STATE_DIR" >&2; exit 2; }

# ── Structural per-ticket dedup (D-4) ─────────────────────────────────────────────
# The file whose basename equals its ticketKey is the LIVE file and supersedes every
# snapshot of that ticket. With no live file, every snapshot is kept as a distinct run
# — a ticket re-run three times without a surviving live file genuinely IS three runs.
# Deliberately structural: there is no `-failed-` (or `-aborted-`, or `-escalated-`)
# filename literal here, because the rename conventions are undocumented and a literal
# would silently miss the ones it did not enumerate.
SELECTED="$(printf '%s' "$ROWS" | awk -F'\t' '
  { sa[NR]=$1; stem[NR]=$2; tk[NR]=$3; n=NR
    if ($2 == $3) live[$3]=1 }
  END {
    for (i = 1; i <= n; i++) {
      if (tk[i] in live && stem[i] != tk[i]) continue   # superseded snapshot
      printf "%s\t%s\t%s\n", sa[i], stem[i], tk[i]
    }
  }' | sort -r | head -n "$WINDOW")"

# ── Per-run timing models (pause math owned by stage-times.sh) ─────────────────────
MODELS="[]"
while IFS=$'\t' read -r sa stem tk; do
  [[ -n "$stem" ]] || continue
  m="$(STATECTL_STATE_DIR="$STATE_DIR" bash "$STAGE_TIMES" --json "$stem" 2>/dev/null)" || continue
  [[ -n "$m" ]] || continue
  MODELS="$(jq -c --argjson m "$m" --arg stem "$stem" '. + [$m + {stem: $stem}]' <<<"$MODELS")"
done <<<"$SELECTED"

[[ "$(jq 'length' <<<"$MODELS")" != "0" ]] || { echo "stage-envelopes.sh: no readable runs in the window" >&2; exit 2; }

# Default run under test: the newest run in the window.
[[ -n "$RUN_UNDER_TEST" ]] || RUN_UNDER_TEST="$(jq -r '.[0].stem' <<<"$MODELS")"

# ── Cost rows (the cost log's OWN append-only window — D-6) ────────────────────────
# Deliberately NOT clamped to the state window: on a real corpus only a minority of runs
# carry cost rows, so tying cost to the 15-run state window would darken the whole axis
# behind the min-n floor.
COST_LOG="$STATE_DIR/cost-log.jsonl"
COST_ROWS="[]"
if [[ -f "$COST_LOG" ]]; then
  COST_ROWS="$(jq -s -c '[ .[] | select(type == "object") ]' "$COST_LOG" 2>/dev/null || echo '[]')"
fi

# ── Statistics ────────────────────────────────────────────────────────────────────
MODEL="$(jq -n -c \
  --argjson runs "$MODELS" \
  --argjson costRows "$COST_ROWS" \
  --arg rut "$RUN_UNDER_TEST" \
  --argjson minN "$MIN_N" \
  --argjson window "$WINDOW" \
  --argjson corpusFiles "$CORPUS_FILE_COUNT" '

  # nearest-rank percentile: 1-based index ceil(p/100 * n) over the ASCENDING sort.
  # Chosen over interpolation because at these corpus sizes an interpolated value is a
  # number no run ever produced; nearest-rank always returns an observed value.
  def pct($sorted; $p):
    ($sorted | length) as $n
    | if $n == 0 then null
      else $sorted[ ([ (($p / 100) * $n | ceil), 1 ] | max) - 1 ] end;

  def round1: (. * 10 | round) / 10;
  def round2: (. * 100 | round) / 100;
  def day: .[0:10];

  # ── Fidelity triage (perf-retro Step 2) ────────────────────────────────────────
  # All FIVE signals are mechanized. Signals 1, 2 and 4 are run-level properties and
  # therefore degrade every window of that run; signal 3 is per-window; signal 5 does
  # not degrade a window at all — a lifecycle-dropped stage HAS no window, so it is
  # reported as a known-unknown row instead (never letting a dropped stage read as a
  # fast one).
  #
  # Signal 4 keys on `.mode`, NOT on pipelineSessions[].source (D-8). Every run recorded
  # by this pipeline carries source "interactive" as its TRANSPORT; reading that field
  # as "human-paced" would mark the entire corpus degraded and darken the instrument
  # permanently. `.mode` is the field that actually distinguishes an operator-paced run.
  ($runs | map(
    . as $r
    | ([]
       + (if ($r.sessionCount > 1 and $r.pausedMin == 0)
          then ["multi-session-no-pause"] else [] end)
       + (if ($r.effectiveTotalMin == $r.wallMin
              and (($r.startedAt | day) != ($r.lastUpdatedAt | day)))
          then ["effective-equals-wall-across-days"] else [] end)
       + (if $r.mode == "interactive" then ["human-paced-mode"] else [] end)
      ) as $runSignals
    | $r + {
        runSignals: $runSignals,
        windows: [ $r.stages[]
          | . as $s
          # Signal 3: a window that barely elapsed, preceded by a large transition gap —
          # the real work happened before the start was recorded, so it landed in the gap.
          | ([ $r.gaps[] | select(.to == $s.stage) | .minutes ] | first // 0) as $gapIn
          | (if ($s.effectiveMin <= 0.1 and $gapIn >= 5)
             then ["near-zero-after-gap"] else [] end) as $winSignals
          | ($runSignals + $winSignals) as $sig
          | { stage: $s.stage, effectiveMin: $s.effectiveMin,
              signals: $sig, trusted: (($sig | length) == 0) } ]
      }
  )) as $triaged

  # ── Cost join (D-6) ────────────────────────────────────────────────────────────
  # A cost row carries no runId, so it joins its run by sessionIds intersection. A row
  # that matches no run in the state window still belongs to the cost axis (its own
  # window) and falls back to its ticketKey as identity. Multiplicity — the live case
  # being a mid-run block plus the whole-run rollup sharing a session id — resolves
  # newest-by-.at, flagged. Exactly ONE row represents a run, so a run never
  # double-counts; the flag fires on multiplicity, not on a missing id.
  | ($costRows | map(
      . as $row
      | ([ $triaged[] | select((.sessionIds // []) | any(. as $s | ($row.sessionIds // []) | index($s))) ] | first) as $match
      | $row + { joinKey: (if $match then $match.stem else ("ticket:" + ($row.ticketKey // "?")) end) }
    )) as $joined
  | ($joined | group_by(.joinKey) | map(
      (. | sort_by(.at) | last) as $winner
      | $winner + { joinMultiRow: ((. | length) > 1), rowsSeen: (. | length) }
    )) as $costRuns

  # Retired label vocabularies normalize forward; anything else collapses into ONE
  # explicit legacy row rather than silently becoming its own bucket.
  | (["Intake","Plan","Implementation","Verify","Doc Update","Code Review","PR Creation","Cleanup","Other"]) as $known
  | ($costRuns | map(
      . as $cr
      | { joinKey: $cr.joinKey, ticketKey: $cr.ticketKey, at: $cr.at,
          joinMultiRow: $cr.joinMultiRow, rowsSeen: $cr.rowsSeen,
          buckets: ([ ($cr.byLabel // [])[]
              # $lbl is captured BEFORE the pipe into index(): inside `$known | index(X)`
              # the `.` in X would be $known (the array), not this row.
              | .label as $lbl
              | { label: (if $lbl == "Intake + Planning" then "Intake"
                          elif ($known | index($lbl)) then $lbl
                          else "legacy vocabulary" end),
                  usd: .cost_usd } ]
            | group_by(.label)
            | map({ label: .[0].label, usd: ([.[].usd] | add) })) }
    )) as $costModel

  # ── Envelopes ──────────────────────────────────────────────────────────────────
  # Leave-one-out is applied by EXCLUDING the run under test from the sample before the
  # percentile, and the min-n floor is checked on what remains (D-7) — so an emitted
  # envelope is always backed by >= minN windows that do not include the run being judged.
  | ([ $triaged[] | .windows[] | .stage ] | unique | sort_by(tonumber)) as $stageKeys
  | ([ $triaged[] | select(.stem == $rut) ] | first) as $rutRun
  | ($stageKeys | map(
      . as $stage
      | [ $triaged[] | select(.stem != $rut) | .windows[]
          | select(.stage == $stage and .trusted) | .effectiveMin ] as $sample
      | ($sample | sort) as $sorted
      | ($sorted | length) as $n
      | ([ ($rutRun.windows // [])[] | select(.stage == $stage) ] | first) as $mine
      | (if $n >= $minN then pct($sorted; 50) else null end) as $p50
      | (if $n >= $minN then pct($sorted; 90) else null end) as $p90
      | { stage: $stage, n: $n,
          p50: $p50, p90: $p90,
          floorMet: ($n >= $minN),
          thisRun: ($mine.effectiveMin // null),
          thisRunTrusted: ($mine.trusted // null),
          over: (if ($p90 != null and $mine != null and $mine.effectiveMin > $p90)
                 then true else false end),
          # At small n the p90 IS the observed maximum, so exceeding it is not evidence
          # of a heavy tail — it is a new record. Say which one it is.
          record: (if ($p90 != null and $mine != null and $mine.effectiveMin > $p90
                       and $p90 == ($sorted | last)) then true else false end) }
    )) as $timeEnvelopes

  | ([ $costModel[] | .buckets[] | .label ] | unique | sort) as $bucketKeys
  | ([ $costModel[] | select(.joinKey == $rut) ] | first) as $rutCost
  | ($bucketKeys | map(
      . as $bucket
      | [ $costModel[] | select(.joinKey != $rut) | .buckets[]
          | select(.label == $bucket) | .usd ] as $sample
      | ($sample | sort) as $sorted
      | ($sorted | length) as $n
      | ([ ($rutCost.buckets // [])[] | select(.label == $bucket) ] | first) as $mine
      | (if $n >= $minN then pct($sorted; 50) else null end) as $p50
      | (if $n >= $minN then pct($sorted; 90) else null end) as $p90
      | { bucket: $bucket, n: $n,
          p50: (if $p50 == null then null else ($p50 | round2) end),
          p90: (if $p90 == null then null else ($p90 | round2) end),
          floorMet: ($n >= $minN),
          thisRun: (if $mine == null then null else ($mine.usd | round2) end),
          over: (if ($p90 != null and $mine != null and $mine.usd > $p90) then true else false end),
          record: (if ($p90 != null and $mine != null and $mine.usd > $p90
                       and $p90 == ($sorted | last)) then true else false end) }
    )) as $costEnvelopes

  | {
      corpus: {
        stateFiles: $corpusFiles,
        runsInWindow: ($triaged | length),
        window: $window,
        minN: $minN,
        dedupRule: "basename==ticketKey supersedes snapshots of that ticket; with no live file every snapshot is a distinct run",
        quarantineExcluded: "*-stale-*, *-released-*",
        costRows: ($costRows | length),
        costRunsJoined: ($costModel | length)
      },
      runUnderTest: {
        stem: $rut,
        ticketKey: ($rutRun.ticketKey // null),
        startedAt: ($rutRun.startedAt // null),
        signals: ($rutRun.runSignals // []),
        costJoined: ($rutCost != null),
        joinMultiRow: ($rutCost.joinMultiRow // false)
      },
      trustedWindows: ([ $triaged[] | .windows[] | select(.trusted) ] | length),
      degradedWindows: ([ $triaged[] | .windows[] | select(.trusted | not) ] | length),
      degraded: [ $triaged[] | . as $r | $r.windows[] | select(.trusted | not)
                  | { stem: $r.stem, stage: .stage, signals: .signals } ],
      lifecycleDropped: [ $triaged[] | . as $r | (.droppedStages // [])[]
                          | { stem: $r.stem, stage: . } ],
      timeEnvelopes: $timeEnvelopes,
      costEnvelopes: $costEnvelopes,
      flags: (
        [ $timeEnvelopes[] | select(.over)
          | { axis: "time", key: ("stage " + .stage), measured: .thisRun,
              unit: "min", p90: .p90, n: .n, record: .record } ]
        + [ $costEnvelopes[] | select(.over)
            | { axis: "cost", key: .bucket, measured: .thisRun,
                unit: "usd", p90: .p90, n: .n, record: .record } ]
      ),
      knownUnknowns: (
        [ $timeEnvelopes[] | select(.floorMet | not)
          | { axis: "time", key: ("stage " + .stage), n: .n,
              reason: ("below min-n floor (" + (.n | tostring) + " < " + ($minN | tostring) + " trusted windows after leave-one-out)") } ]
        + [ $costEnvelopes[] | select(.floorMet | not)
            | { axis: "cost", key: .bucket, n: .n,
                reason: ("below min-n floor (" + (.n | tostring) + " < " + ($minN | tostring) + " joined runs after leave-one-out)") } ]
        + [ $triaged[] | . as $r | (.droppedStages // [])[]
            | { axis: "time", key: ("stage " + .), n: 0,
                reason: ("lifecycle-dropped in run " + $r.stem + " — a missing startedAt/completedAt, not a fast stage") } ]
      )
    }
')" || { echo "stage-envelopes.sh: statistics computation failed" >&2; exit 2; }

if [[ "$EMIT_JSON" == "true" ]]; then
  printf '%s\n' "$MODEL" | jq .
  exit 0
fi

# ── Text report ───────────────────────────────────────────────────────────────────
# The corpus is DECLARED (file count + dedup rule) so this report can never silently
# disagree with a consumer enumerating the same directory by a different rule.
jq -r '
  def f($v): if $v == null then "-" else ($v | tostring) end;
  # A missing value renders as a bare "-", never "- min"/"- usd": an absent measurement
  # is not a measurement with a unit.
  def fmin($v): if $v == null then "-" else "\($v) min" end;
  def fusd($v): if $v == null then "-" else "$\($v)" end;
  def pad($s; $w): $s + (" " * ([0, $w - ($s | length)] | max));
  "corpus: \(.corpus.runsInWindow) run(s) in window from \(.corpus.stateFiles) state file(s); \(.corpus.costRows) cost row(s) -> \(.corpus.costRunsJoined) run(s)",
  "dedup: \(.corpus.dedupRule)",
  "excluded: \(.corpus.quarantineExcluded)   window=\(.corpus.window)  min-n floor=\(.corpus.minN)",
  "run under test: \(.runUnderTest.stem)\(if (.runUnderTest.signals | length) > 0 then "  [degraded: \(.runUnderTest.signals | join(", "))]" else "" end)",
  "windows: \(.trustedWindows) trusted, \(.degradedWindows) degraded",
  "",
  "time envelopes (per stage; leave-one-out nearest-rank over trusted windows)",
  "  stage  n    p50         p90         this run    flag",
  (.timeEnvelopes[]
    | "  " + pad(.stage; 7) + pad((.n | tostring); 5)
      + pad(fmin(.p50); 12) + pad(fmin(.p90); 12) + pad(fmin(.thisRun); 12)
      + (if .over then (if .record then "OVER (new record)" else "OVER" end)
         elif (.floorMet | not) then "known-unknown"
         else "-" end)),
  "",
  "cost envelopes (per bucket; the cost log'"'"'s own window, independent of the state window)",
  "  bucket             n    p50         p90         this run    flag",
  (.costEnvelopes[]
    | "  " + pad(.bucket; 19) + pad((.n | tostring); 5)
      + pad(fusd(.p50); 12) + pad(fusd(.p90); 12) + pad(fusd(.thisRun); 12)
      + (if .over then (if .record then "OVER (new record)" else "OVER" end)
         elif (.floorMet | not) then "known-unknown"
         else "-" end)),
  "",
  (if (.flags | length) == 0 then "over-envelope flags: none"
   else "over-envelope flags:" end),
  (.flags[]
    | "  \(.axis) \(.key): \(.measured) \(.unit) exceeds p90 \(.p90) (n=\(.n))" +
      (if .record then " — set a new record; at this n the p90 IS the observed maximum" else "" end)),
  (if (.runUnderTest.joinMultiRow) then "  join:multi-row — several cost rows shared this run'"'"'s session; the newest by .at represents it" else empty end),
  "",
  (if (.knownUnknowns | length) == 0 then "known-unknowns: none"
   else "known-unknowns (reported, never flagged):" end),
  (.knownUnknowns[] | "  \(.axis) \(.key): \(.reason)")
' <<<"$MODEL"

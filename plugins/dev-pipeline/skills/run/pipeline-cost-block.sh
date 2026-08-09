#!/bin/bash
# pipeline-cost-block.sh — append a per-stage OTel cost block to a dev-pipeline
# run's PR(s). Invoked explicitly by Stage 9 (this is NOT a Stop hook).
#
# Usage:  pipeline-cost-block.sh <issue-number>
#         pipeline-cost-block.sh --stateless --sessions <id[,id…]> \
#                                --start <iso> --end <iso> [--out <file>]
# Exit:   0 = ran, or recorded a documented skip (no metrics, no bot wrapper, no
#         collector, no PRs, …) into the state file's costBlockApplied field.
#         non-zero = the state file could not be resolved (nothing to record
#         into) — a loud, state-unresolvable failure. Either way the sub-step is
#         non-fatal to Stage 9: the caller invokes it without checking rc, so a
#         non-zero exit surfaces in the run summary but never blocks completion.
#
# STATE-LESS MODE (additive; run-lean, D-28). One instrument across both harnesses —
# the same collector query and the same cache-tier pricing math — with an honest
# layout difference. run-lean has no state file and no stage windows, so the mode
# takes its two required inputs as ARGUMENTS (the session-id set and a [start, end]
# time fence, both carried by the lean progress file), emits session-window totals
# only to stdout or --out, amends no PR body, and writes NO cost-log.jsonl row (lean
# is out of the perf corpus by declaration).
#
# The flags are parsed AHEAD of the required `$1` positional, which is load-bearing:
# `${1:?usage}` is evaluated before any flag handling, so a state-less invocation with
# no issue number would otherwise abort on a usage error before reaching its own mode.
# Every state-file path below is guarded on $STATELESS, so existing invocations keep
# their exact behavior.
#
# TIER BUCKETING. Cost is bucketed by (stage label, TIER), not by stage label alone. The
# tier comes from each datapoint's `model` telemetry attribute through $TIER_FAMILY_MAP
# below — a SCRIPT CONSTANT, deliberately not a config key. A consumer-overridable surface
# is a follow-on for when a second vendor actually runs; a key here would cost a schema
# edit, a lint allowlist entry and a configVersion call for a consumer nobody has yet.
#
# The alphabet is `reasoning` / `code` / `emit`, plus `unknown` — NOT the opus/sonnet/haiku
# dispatch alphabet, which would make the bucket key a vendor token and move the debt
# rather than pay it. The map is keyed on FAMILY SUBSTRINGS of the RESOLVED telemetry id
# (`claude-opus-4-7`, not `opus`), because the resolved id is what the collector emits and
# the dispatch string never reaches this file.
#
# The classification is TOTAL. An id matching no family, and a datapoint carrying no
# `model` attribute at all, both resolve to `unknown`. Totality is the point: a model-less
# cost datapoint already counts toward the run total, so a partial key would let its money
# vanish from the per-tier table while still appearing in the sum.
#
# Coverage is today's Anthropic families only. An unrecognized backend reads honestly as
# `unknown` rather than being mis-tiered, and the fix is one entry in the map.
#
# RENDER FILTER. The rollup and the cost-log row stay total: every (label, tier) pair
# present in the fenced datapoint set has a row. The RENDERED table drops rows carrying
# zero cost with an empty model set, because live telemetry emits whole metric families
# with no `model` attribute (active_time.total, code_edit_tool.decision,
# pull_request.count). Without the filter every stage label would gain a companion
# zero-dollar `unknown` row in the artifact a human actually reads. Filtering here rather
# than in the rollup keeps the durable record complete and the PR block legible.
#
# ROTATED BACKUPS (#432). The shipped exporter config rotates at `max_megabytes: 50`, keeping
# up to `max_backups: 30` files named `metrics-<ts>-size.jsonl` beside the live one. Reading
# only the live file made ANY run whose window predates the newest rotation silently
# unattributable even with telemetry on. select_metrics_files() below picks the live file plus
# every backup whose MTIME is at or after the fence's lower bound — mtime, not the filename
# timestamp, because `localtime: true` puts a LOCAL timestamp in that name while the fence is
# ISO-8601 `Z`, and comparing them directly is an off-by-the-tz-offset bug that reads correct
# only in UTC.
#
# MEMORY CEILING (#432 OR-2). compute_bucket_rollup uses `jq -s`, which slurps every input
# file. The selection above bounds the realistic worst case to TWO 50 MB files (a fence
# spanning one rotation), not thirty. If a longer fence ever selects more, the contained fix is
# inside compute_bucket_rollup alone — per-file rollup then merge, or `--stream` — with no
# change to any caller or to the emitted shape.

set -uo pipefail
log() { echo "[pipeline-cost-block] $*" >&2; }

# Telemetry-id → tier map (see TIER BUCKETING above). Keys are family substrings matched
# against the resolved model id; values are the tier alphabet. Unmatched ids and
# attribute-less datapoints tier to `unknown`, which is never a key here.
TIER_FAMILY_MAP='{"opus":"reasoning","sonnet":"code","haiku":"emit"}'
# Tier order within one stage label, so rows sharing a label never permute between runs.
# Also orders the session-total row's tier list. Anything absent sorts last.
TIER_ORDER='{"reasoning":1,"code":2,"emit":3,"unknown":4}'

STATELESS=0
ARG_SESSIONS=""
ARG_START=""
ARG_END=""
ARG_OUT=""
POSITIONAL_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --stateless) STATELESS=1; shift ;;
    --sessions)  ARG_SESSIONS="${2:-}"; shift 2 ;;
    --start)     ARG_START="${2:-}"; shift 2 ;;
    --end)       ARG_END="${2:-}"; shift 2 ;;
    --out)       ARG_OUT="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '2,70p' "$0"; exit 0 ;;
    -*)          log "unknown option: $1"; exit 2 ;;
    *)           POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- ${POSITIONAL_ARGS+"${POSITIONAL_ARGS[@]}"}

if [ "$STATELESS" -eq 1 ]; then
  [ -n "$ARG_SESSIONS" ] || { log "--stateless requires --sessions <id[,id…]>"; exit 2; }
  [ -n "$ARG_START" ] && [ -n "$ARG_END" ] \
    || { log "--stateless requires both --start <iso> and --end <iso> (the time fence)"; exit 2; }
  ISSUE="stateless"
else
  ISSUE_RAW="${1:?usage: pipeline-cost-block.sh <issue-number>}"
  ISSUE=$(echo "$ISSUE_RAW" | tr '[:upper:]' '[:lower:]')
fi

# ────────────────────────────────────────────────────────────────────────────
# Resolve state-file path in the CONSUMER repo, git-common-dir anchored from
# $PWD (mirrors statectl.sh state_dir: STATECTL_STATE_DIR > SECOND_SHIFT_REPO_ROOT
# > cwd-derived main checkout; config paths.pipelineStateDir overrides the
# default subdir).
# ────────────────────────────────────────────────────────────────────────────
# Repo root: SECOND_SHIFT_REPO_ROOT > git-common-dir parent > empty.
_repo_root() {
  local cd
  if [ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]; then
    echo "$SECOND_SHIFT_REPO_ROOT"
  elif cd=$(git rev-parse --git-common-dir 2>/dev/null) \
     && cd=$(cd "$cd" 2>/dev/null && pwd); then
    dirname "$cd"
  else
    echo ""
  fi
}

# Consumer config path: SECOND_SHIFT_CONFIG > <root>/.claude/second-shift.config.json
# > empty (no resolvable root). Empty means "no config" — callers treat that as
# absent, not as an error. Deliberately does NOT honor STATECTL_STATE_DIR: that is
# a state-file override, and inheriting it here would make the tracker.bot read
# skip the config entirely (silently downgrading write identity) whenever a state
# dir is set.
_config_path() {
  local root
  if [ -n "${SECOND_SHIFT_CONFIG:-}" ]; then
    echo "$SECOND_SHIFT_CONFIG"
    return 0
  fi
  root=$(_repo_root)
  if [ -n "$root" ]; then
    echo "$root/.claude/second-shift.config.json"
  else
    echo ""
  fi
}

resolve_state() {
  if [ -n "${STATECTL_STATE_DIR:-}" ]; then
    echo "${STATECTL_STATE_DIR}/${ISSUE}.json"
    return 0
  fi
  local root="" cfg rel=".claude/pipeline-state"
  root=$(_repo_root)
  if [ -n "$root" ]; then
    cfg=$(_config_path)
    if [ -n "$cfg" ] && [ -f "$cfg" ]; then
      rel=$(jq -r '.paths.pipelineStateDir // ".claude/pipeline-state"' "$cfg" 2>/dev/null) \
        || rel=".claude/pipeline-state"
    fi
    echo "$root/$rel/${ISSUE}.json"
  else
    echo ".claude/pipeline-state/${ISSUE}.json"
  fi
}
if [ "$STATELESS" -eq 1 ]; then
  # No state file exists, by definition. Everything downstream that reads it is guarded
  # on $STATELESS; the empty value here makes an unguarded read fail loudly rather than
  # silently resolving to some other run's state.
  STATE_FILE=""
else
STATE_FILE=$(resolve_state)
# No state file at the resolved path is UNRECORDABLE: record() writes into
# $STATE_FILE, which by definition does not exist here, so we cannot leave a
# costBlockApplied breadcrumb. Fail LOUD (non-zero) instead of the old silent
# `exit 0` — a bare null was the #188 silent-skip. A cross-repo run must point
# this script at the CONTROL repo's state (Stage 9 exports SECOND_SHIFT_REPO_ROOT
# on the invocation; operators of a bespoke cwd set STATECTL_STATE_DIR). Stage 9
# invokes this without checking rc, so the non-zero never blocks completion.
[ -f "$STATE_FILE" ] || { log "no state file at $STATE_FILE — state unresolvable, cannot record costBlockApplied (see #188: export SECOND_SHIFT_REPO_ROOT/STATECTL_STATE_DIR to the control repo)"; exit 2; }
fi

# ────────────────────────────────────────────────────────────────────────────
# Record outcome into costBlockApplied (raw jq — statectl does not own this).
# ────────────────────────────────────────────────────────────────────────────
record() {
  local val="$1"  # JSON scalar: `true` or a quoted string
  local tmp
  # State-less mode has nothing to record into. A no-op here (rather than a guard at
  # each of the ~8 call sites) keeps every documented skip path working unchanged.
  [ "$STATELESS" -eq 1 ] && return 0
  tmp=$(mktemp) || return
  if jq --argjson v "$val" '.costBlockApplied = $v' "$STATE_FILE" > "$tmp"; then
    mv "$tmp" "$STATE_FILE"
  else
    rm -f "$tmp"
  fi
}

# Append a machine-readable row to cost-log.jsonl for cross-run analytics.
# DURATION_MIN defaults to "?" and prs_json is computed locally, so the row is
# self-contained regardless of which globals are set when it runs.
write_cost_log_row() {
  local dur="${DURATION_MIN:-?}"
  # Output path: cost-log.jsonl beside the state file. Overridable via COST_LOG_FILE
  # so cost-block-selftest.sh (whose state fixtures live in the REAL pipeline-state
  # dir) can capture the row in a temp file instead of polluting the real log.
  local out="${COST_LOG_FILE:-$(dirname "$STATE_FILE")/cost-log.jsonl}"
  local prs_json
  prs_json=$(jq -c '[.prs | values[]? | select(. != null) | .url // empty | select(length > 0)]' "$STATE_FILE")
  jq -n -c --arg issue "$ISSUE" --arg dur "$dur" \
    --argjson sids "$SIDS_JSON" --argjson rollup "$ROLLUP" --argjson prs "$prs_json" '
    { at: (now | todate),
      ticketKey: $issue,
      sessionIds: $sids,
      totalUsd: $rollup.totals.cost_usd,
      durationMin: ($dur | tonumber? // null),
      models: ([$rollup.byLabel[].models[]] | unique | sort),
      tiers: ([$rollup.byLabel[].tier] | unique | sort),
      byLabel: $rollup.byLabel,
      cacheHitRate: $rollup.totals.cache_hit_rate,
      prs: $prs }
  ' >> "$out"
}

# ────────────────────────────────────────────────────────────────────────────
# Write identity. Config `tracker.bot.enabled` decides bot-vs-operator identity;
# the runtime value of $GH_BOT is never sniffed to infer it. A bot-ENABLED repo
# writes through the wrapper (missing wrapper => skipped-no-bot-wrapper). A
# bot-DISABLED repo — including one whose config is absent, unreadable, or
# malformed, which resolves to disabled per `// false` — writes with plain `gh`
# under operator identity. Same enabled/disabled default as tools/bot-commit.sh,
# but NOT the same config lookup: that helper searches $SECOND_SHIFT_CONFIG, its
# -C dir, then the main checkout, so a gitignored config absent from a worktree
# still resolves there. This script's _repo_root() is already common-dir anchored.
# ────────────────────────────────────────────────────────────────────────────
# Bot wrapper: single resolver (tools/gh-bot.sh, #92). Config tracker.bot.enabled
# decides bot-vs-operator; when disabled we never call the resolver (so a stray
# env var cannot take the write — cost-block-selftest AC-4).
CFG_FILE=$(_config_path)
BOT_ENABLED=false
if [ -n "$CFG_FILE" ] && [ -f "$CFG_FILE" ]; then
  BOT_ENABLED=$(jq -r '.tracker.bot.enabled // false' "$CFG_FILE" 2>/dev/null) || BOT_ENABLED=false
  [ "$BOT_ENABLED" = "true" ] || BOT_ENABLED=false
fi

if [ "$BOT_ENABLED" = "true" ]; then
  _RESOLVER="$(cd "$(dirname "$0")" && pwd)/tools/gh-bot.sh"
  if [ ! -f "$_RESOLVER" ]; then
    log "gh-bot.sh missing at $_RESOLVER — skipping PR amend"
    record '"skipped-no-bot-wrapper"'
    exit 0
  fi
  if ! GH_BOT="$(bash "$_RESOLVER" --path 2>/dev/null)"; then
    log "bot wrapper unresolved (gh-bot --status=$(bash "$_RESOLVER" --status 2>/dev/null || echo '?')) — skipping PR amend (see cost-tracking-setup.md prerequisites)"
    record '"skipped-no-bot-wrapper"'
    exit 0
  fi
  GH_CMD="$GH_BOT"
else
  GH_CMD="gh"
  log "config tracker.bot.enabled is not true — amending PR under operator identity via plain gh"
fi

# ────────────────────────────────────────────────────────────────────────────
# Session set: read pipelineSessions[], registered by statectl's shared write seam
# (apply_session_seam) on each contributing session's first state write. Each id is
# the native Claude Code session UUID ($CLAUDE_CODE_SESSION_ID), the same value the
# collector tags datapoints with as session.id; every session that wrote state
# appears, including a crash-recovery resume at any stage. Runs with no recorded
# sessions skip cleanly.
# ────────────────────────────────────────────────────────────────────────────
if [ "$STATELESS" -eq 1 ]; then
  # The caller supplies the set (comma- or whitespace-separated); the lean progress file
  # is its carrier, which is why AC-14's reconciliation keys are load-bearing here rather
  # than forward-looking.
  SESSIONS=$(printf '%s' "$ARG_SESSIONS" | tr ',' '\n' | tr ' ' '\n' | awk 'NF' | sort -u)
else
SESSIONS=$(jq -r '
  (.pipelineSessions // [])
  | map(.sessionId // empty)
  | map(select(. != null and . != ""))
  | unique
  | .[]
' "$STATE_FILE")
fi

if [ -z "$SESSIONS" ]; then
  log "no pipelineSessions recorded — skipping (no state write carried a UUID-shaped CLAUDE_CODE_SESSION_ID)"
  record '"skipped-no-sessions"'
  exit 0
fi

METRICS_FILE="${OTEL_METRICS_FILE:-$HOME/.claude/otel-metrics/metrics.jsonl}"
METRICS_DIR=$(dirname "$METRICS_FILE")
METRICS_STEM=$(basename "$METRICS_FILE"); METRICS_STEM="${METRICS_STEM%.jsonl}"

# Every non-empty file the exporter may have written for this stem: the live file first, then
# its rotated backups. Derived from the RESOLVED $METRICS_FILE so an $OTEL_METRICS_FILE override
# keeps working. An unmatched glob expands to the literal pattern, which `-s` rejects.
metrics_candidates() {
  local f
  [ -s "$METRICS_FILE" ] && printf '%s\n' "$METRICS_FILE"
  for f in "$METRICS_DIR/$METRICS_STEM"-*.jsonl; do
    [ -s "$f" ] && printf '%s\n' "$f"
  done
  return 0
}

# "Nothing was ever written" is now the absence of the live file AND of every backup — a machine
# that rotated moments ago has an empty live file and a full backup, and used to read here as
# telemetry-off.
if [ -z "$(metrics_candidates)" ]; then
  log "no OTel metrics file at $METRICS_FILE, and no rotated backup beside it — was otelcol-contrib running?"
  record '"skipped-telemetry-off"'
  exit 0
fi

# Let any in-flight metrics flush from the collector. Skipped under either test
# hook (COST_BLOCK_DUMP_ROLLUP / COST_BLOCK_DUMP_LOGROW) — fixtures are static,
# nothing to flush.
[ -z "${COST_BLOCK_DUMP_ROLLUP:-}${COST_BLOCK_DUMP_LOGROW:-}" ] && sleep 5

# ────────────────────────────────────────────────────────────────────────────
# Per-stage bucketing.
#
# For each row in metrics.jsonl, filter by session.id in $SESSIONS, then
# assign each row to its stage label based on the row's timestamp falling
# inside the stage's [startedAt, completedAt] window.
#
# Stage → bucket label (10 stages). MUST track the stage numbering in SKILL.md's
# Pipeline Checklist: 1 Intake, 2 Worktree, 3 Write Plan, 4 Plan Review,
# 5 Implement, 6 Verify, 7 Doc Update, 8 Code Review, 9 Open PR, 10 Cleanup.
#   1,2 → Intake                 3,4 → Plan          5   → Implementation
#   6   → Verify                 7   → Doc Update    8   → Code Review
#   9   → PR Creation            10  → Cleanup
# ────────────────────────────────────────────────────────────────────────────
SIDS_JSON=$(jq -R -s 'split("\n") | map(select(length > 0))' <<<"$SESSIONS")

# ────────────────────────────────────────────────────────────────────────────
# Per-run time fence. A long-lived interactive Claude Code session can host
# several sequential runs (and /pipeline-retro) under ONE session.id; without a
# fence, a later run's rollup inhales every co-resident datapoint. Clamp each
# run to its own wall-clock span in ADDITION to session.id:
#   FENCE_LO = run start (.startedAt)
#   FENCE_HI = terminal stage completedAt — max(.stages[].completedAt) — falling
#              back to .lastUpdatedAt when no stage has completed (aborted run).
# Timestamps are ISO-8601 Z strings (nanos_to_iso renders the same form), so
# lexicographic compare is chronological. If .startedAt is somehow absent, the
# fence disables itself (empty bounds) and we degrade to session-only behavior.
# ────────────────────────────────────────────────────────────────────────────
if [ "$STATELESS" -eq 1 ]; then
  # The fence is an ARGUMENT here, not derived from stage timestamps — lean has none.
  # It is required (not optional) precisely because session-only attribution would
  # inhale every co-resident datapoint from a long-lived interactive session.
  FENCE_LO="$ARG_START"
  FENCE_HI="$ARG_END"
else
FENCE_LO=$(jq -r '.startedAt // empty' "$STATE_FILE")
FENCE_HI=$(jq -r '
  ([.stages[]?.completedAt // empty] | map(select(. != null and . != "")) | max) //
  (.lastUpdatedAt // empty) // empty
' "$STATE_FILE")
fi
if [ -z "$FENCE_LO" ] || [ -z "$FENCE_HI" ]; then
  log "no usable time fence (startedAt/completedAt/lastUpdatedAt missing) — degrading to session-only attribution"
  FENCE_LO=""
  FENCE_HI=""
fi

# ────────────────────────────────────────────────────────────────────────────
# Rotation-aware input set (#432). See ROTATED BACKUPS in the header.
#
# A backup's mtime is the moment it STOPPED being written, so one with mtime < FENCE_LO cannot
# hold an in-fence row and is skipped. With the fence disabled (the degraded session-only path
# above) there is no window to cover, so the live file is read alone.
#
# The selection is never allowed to come out empty: `jq -s` with no file operands reads STDIN
# and would hang the sub-step forever. The newest candidate is the backstop — it is also the
# right one for the rotated-out branch below, whose evidence is "the oldest row we can still see
# starts after the run did".
# ────────────────────────────────────────────────────────────────────────────
# `-u` is load-bearing on BSD: without it `date -j -f` interprets the fence — which is an
# ISO-8601 `Z` string — as LOCAL time, and the resulting epoch is off by the operator's offset.
# That would compare a skewed fence against real file mtimes and select the wrong backups
# everywhere except UTC, which is the same class of bug as trusting the rotated filename.
# Validated the same way as file_mtime below, and for the same reason: a `date` form that is
# wrong for the platform is not reliably a non-zero exit, so the digits are the test.
iso_to_epoch() {
  local e
  e=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null)
  case "$e" in ''|*[!0-9]*) e=$(date -u -d "$1" +%s 2>/dev/null) ;; esac
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$e"
}
# BSD `stat -f %m` and GNU `stat -c %Y`, and neither one fails cleanly under the other. On GNU,
# `-f` is --file-system and `%m` is read as another OPERAND, so the call prints filesystem info
# for the real file and the `||` fallback never gets a chance to produce a number — the caller
# then compares that text against an epoch, the test errors, and NO rotated backup is ever
# selected. Validating the digits rather than trusting the exit status is what makes the pair
# portable; a non-numeric result from either form is treated as no answer.
file_mtime() {
  local m
  m=$(stat -c %Y "$1" 2>/dev/null)
  case "$m" in ''|*[!0-9]*) m=$(stat -f %m "$1" 2>/dev/null) ;; esac
  case "$m" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$m"
}

select_metrics_files() {
  local lo_epoch="" f mt newest="" newest_mt=-1
  METRICS_FILES=()
  [ -s "$METRICS_FILE" ] && METRICS_FILES+=("$METRICS_FILE")
  if [ -n "$FENCE_LO" ]; then
    lo_epoch=$(iso_to_epoch "$FENCE_LO")
    if [ -z "$lo_epoch" ]; then
      log "fence lower bound '$FENCE_LO' is not a parseable timestamp — reading the live metrics file only, rotated backups are not selectable"
    else
      while IFS= read -r f; do
        [ "$f" = "$METRICS_FILE" ] && continue
        mt=$(file_mtime "$f") || continue
        [ -n "$mt" ] && [ "$mt" -ge "$lo_epoch" ] && METRICS_FILES+=("$f")
      done < <(metrics_candidates)
    fi
  fi
  if [ ${#METRICS_FILES[@]} -eq 0 ]; then
    while IFS= read -r f; do
      mt=$(file_mtime "$f") || continue
      [ -n "$mt" ] && [ "$mt" -gt "$newest_mt" ] && { newest_mt="$mt"; newest="$f"; }
    done < <(metrics_candidates)
    [ -n "$newest" ] && METRICS_FILES+=("$newest")
  fi
}
select_metrics_files
# Belt-and-braces against the stdin hang: metrics_candidates() already found something, so this
# is only reachable if every candidate's mtime became unreadable between the two calls.
if [ ${#METRICS_FILES[@]} -eq 0 ]; then
  log "no readable metrics file could be selected under $METRICS_DIR — treating as telemetry off"
  record '"skipped-telemetry-off"'
  exit 0
fi
[ ${#METRICS_FILES[@]} -gt 1 ] && log "fence spans a rotation — reading ${#METRICS_FILES[@]} metrics files"

compute_bucket_rollup() {
  jq -s --argjson sids "$SIDS_JSON" \
        --arg fenceLo "$FENCE_LO" \
        --arg fenceHi "$FENCE_HI" \
        --argjson tierMap "$TIER_FAMILY_MAP" \
        --argjson tierOrder "$TIER_ORDER" \
        --argjson stages "$([ "$STATELESS" -eq 1 ] && echo '{}' || jq -c '.stages' "$STATE_FILE")" '
    def nanos_to_iso: tonumber / 1e9 | todate;
    # Total by construction: a non-string (absent) id, and a string matching no family
    # substring, both land in "unknown".
    def tier_of($m):
      if ($m | type) != "string" then "unknown"
      else ( [ $tierMap | to_entries[] as $e | select($m | contains($e.key)) | $e.value ] | first ) // "unknown"
      end;
    def stage_label(n):
      {"1":"Intake","2":"Intake",
       "3":"Plan","4":"Plan",
       "5":"Implementation","6":"Verify","7":"Doc Update",
       "8":"Code Review","9":"PR Creation","10":"Cleanup"}
      [n|tostring] // "Other";

    # Flatten EVERY cost + token datapoint in the scanned files, unfiltered. The two
    # discriminating counts (#432, D-5) come off this same pass — filtering here would throw
    # away the evidence that tells "the collector saw nothing" apart from "the collector saw
    # everyone but us".
    [ .[] | select(.resourceMetrics)
          | .resourceMetrics[].scopeMetrics[].metrics[]
          | {name, dps: (.sum.dataPoints // [])}
          | .dps[] as $dp
          | ($dp.attributes | map({(.key): (.value.stringValue // .value.intValue)}) | add) as $attrs
          | ($dp.timeUnixNano | nanos_to_iso) as $t
          | { name, t: $t,
              value: ($dp.asDouble // ($dp.asInt // 0 | tonumber)),
              model: $attrs.model,
              tier: tier_of($attrs.model),
              token_type: $attrs.type,
              sid: $attrs["session.id"] }
    ] as $all
    |
    # Per-run time fence: keep only datapoints inside the run wall-clock span. Disabled (kept)
    # when $fenceLo is empty. This is what stops a co-resident sequential run/retro (same
    # session.id) from leaking in.
    [ $all[] | select( $fenceLo == "" or (.t >= $fenceLo and .t <= $fenceHi) ) ] as $inFence
    |
    # `$r` is bound rather than piped: inside `index(...)` the input is $sids, so a bare `.sid`
    # there indexes the id ARRAY, not the row.
    [ $inFence[] as $r | select( ($sids | index($r.sid)) != null ) | $r ] as $rows
    |
    # Assign each (already-fenced) row to the first stage window containing it.
    # A row that falls in no stage window is in-fence inter-stage-gap cost (or
    # pre-Stage-1 setup) → explicit "Other" bucket. Out-of-fence rows were
    # already dropped above, so there is no whole-session "Other" anymore.
    ($stages | to_entries
      | map({n: .key,
             started: .value.startedAt,
             completed: (.value.completedAt // (now|todate))})
      | sort_by(.started)) as $ordered
    |
    [ $rows[] as $row |
        ($row + { stage: (
          ([ $ordered[] | select(.started <= $row.t and $row.t <= .completed) | .n ] | first) //
          "Other"
        ) }) |
        (. + { label: stage_label(.stage) })
    ] as $tagged
    |
    {
      byLabel: (
        $tagged
        | group_by([.label, .tier])
        | map({
            label: .[0].label,
            tier: .[0].tier,
            cost_usd: ( [.[] | select(.name=="claude_code.cost.usage") | .value] | add // 0 ),
            models: ( [.[] | .model // empty] | unique | sort )
          })
        | sort_by(
            [ {"Intake":1,"Plan":2,"Implementation":3,"Verify":4,"Doc Update":5,
               "Code Review":6,"PR Creation":7,"Cleanup":8,"Other":9}
               [.label] // 10,
              $tierOrder[.tier] // 9 ]
          )
      ),
      totals: {
        cost_usd: ( [$tagged[] | select(.name=="claude_code.cost.usage") | .value] | add // 0 ),
        input_tokens: ( [$tagged[] | select(.name=="claude_code.token.usage" and .token_type=="input") | .value] | add // 0 ),
        output_tokens: ( [$tagged[] | select(.name=="claude_code.token.usage" and .token_type=="output") | .value] | add // 0 ),
        cache_read_tokens: ( [$tagged[] | select(.name=="claude_code.token.usage" and .token_type=="cacheRead") | .value] | add // 0 ),
        cache_creation_tokens: ( [$tagged[] | select(.name=="claude_code.token.usage" and .token_type=="cacheCreation") | .value] | add // 0 ),
        session_count: ( $sids | length )
      }
    }
    | .totals.cache_hit_rate =
        ( (.totals.input_tokens + .totals.cache_read_tokens + .totals.cache_creation_tokens) as $denom
          | if $denom > 0 then (.totals.cache_read_tokens / $denom) else 0 end )
    | .rowCount = ($tagged | length)
    # #432 discrimination evidence. `fenceRowCount` counts in-fence rows for ANY session, so a
    # zero `rowCount` beside a non-zero one says THIS session exported nothing. `oldestScannedAt`
    # is the oldest row anywhere in the scanned files; when it starts AFTER the fence does, the
    # coverage of the window itself is missing and no other verdict can be trusted.
    | .fenceRowCount = ($inFence | length)
    | .oldestScannedAt = ( [ $all[].t ] | min // "" )
    | .rotatedOut = ( $fenceLo != "" and (($all | length) > 0) and (([ $all[].t ] | min) > $fenceLo) )
    | .rowSpanSeconds = (
        if ($tagged | length) > 1 then
          ( ( [$tagged[].t] | max | fromdateiso8601 )
            - ( [$tagged[].t] | min | fromdateiso8601 ) )
        else 0 end )
  ' "${METRICS_FILES[@]}"
}

# Stage-window quality check: if startedAt is missing everywhere, or all
# timestamps collapse to a single distinct value, bucketing is meaningless
# and we degrade to a single-row "Session total" table.
# This also tolerates a lifecycle-less final stage (e.g. a Stage 9 that never
# wrote startedAt — see #174): the gate keys off >=2 starts / >=3 distinct
# timestamps across ALL stages, so a single missing final-stage window still
# passes (prior stages satisfy it) and never crashes the cost block.
stage_windows_ok() {
  # Lean has no stage windows by construction, so the state-less mode always renders the
  # single-row session total. That is the honest layout difference D-28 asks for — not a
  # degraded per-stage table with empty rows.
  [ "$STATELESS" -eq 1 ] && { echo "no"; return 0; }
  jq -r '
    (.stages // {}) as $s
    | ( [$s | to_entries[] | .value.startedAt] | map(select(. != null)) | length ) as $starts
    | ( [$s | to_entries[] | .value.completedAt, .value.startedAt] | map(select(. != null)) | unique | length ) as $distinct
    | if ($starts >= 2 and $distinct >= 3) then "yes" else "no" end
  ' "$STATE_FILE"
}
STAGE_WINDOWS_OK=$(stage_windows_ok)

ROLLUP=$(compute_bucket_rollup 2>/dev/null)
if [ -z "$ROLLUP" ] || ! jq -e . >/dev/null 2>&1 <<<"$ROLLUP"; then
  log "OTel metrics query failed"
  record '"skipped-otel-error"'
  exit 0
fi

# Test hook: when COST_BLOCK_DUMP_ROLLUP is set, print the time-fenced rollup JSON
# and exit before any PR I/O. Lets cost-block-selftest.sh assert the fenced totals
# / Other bucket without a real PR. Never set in production.
if [ -n "${COST_BLOCK_DUMP_ROLLUP:-}" ]; then
  printf '%s\n' "$ROLLUP"
  exit 0
fi

# ────────────────────────────────────────────────────────────────────────────
# Four-way discrimination (#432, D-4). The old single message named the collector and the
# session-id format — the two things that are almost never the cause — and it keyed on
# TOTAL_COST being zero, which conflates "no rows at all" with "rows, but no money in them".
# The branch below keys on ROW COUNTS, and each state records its own value because the field
# is the durable record an operator reads back: one value carrying four different remedies is
# unqueryable.
#
# `rotated-out` is tested FIRST. It means the evidence itself is incomplete, so neither of the
# other two zero-row verdicts can be trusted over it.
# ────────────────────────────────────────────────────────────────────────────
TOTAL_COST=$(jq -r '.totals.cost_usd' <<<"$ROLLUP")
ROW_COUNT=$(jq -r '.rowCount // 0' <<<"$ROLLUP")
FENCE_ROW_COUNT=$(jq -r '.fenceRowCount // 0' <<<"$ROLLUP")
OLDEST_SCANNED=$(jq -r '.oldestScannedAt // ""' <<<"$ROLLUP")
ROTATED_OUT=$(jq -r '.rotatedOut // false' <<<"$ROLLUP")

if [ "$ROW_COUNT" -eq 0 ]; then
  if [ "$ROTATED_OUT" = "true" ]; then
    log "the retained metrics start at $OLDEST_SCANNED, after this run's fence opened at $FENCE_LO — the file covering the run has rotated out of retention (max_backups/max_days), or the collector was not running yet. Cost for this run is unrecoverable."
    record '"skipped-rotated-out"'
  elif [ "$FENCE_ROW_COUNT" -gt 0 ]; then
    log "$FENCE_ROW_COUNT in-fence rows from other sessions, none from this run's session ids — this session was launched without CLAUDE_CODE_ENABLE_TELEMETRY and exported nothing. Set it in ~/.claude/settings.json's env block (cost-tracking-setup.md §3); the datapoints cannot be recovered for this run."
    record '"skipped-session-not-exporting"'
  else
    log "no rows at all inside the fence [$FENCE_LO, $FENCE_HI] — the collector was down for the run's whole window, or nothing on this machine was exporting."
    record '"skipped-telemetry-off"'
  fi
  exit 0
fi

if [ -z "$TOTAL_COST" ] || [ "$TOTAL_COST" = "0" ] || [ "$TOTAL_COST" = "null" ]; then
  log "$ROW_COUNT in-fence rows for this run's sessions, but no claude_code.cost.usage among them — telemetry is flowing; there is genuinely no cost to report."
  record '"skipped-zero-datapoints"'
  exit 0
fi

# ────────────────────────────────────────────────────────────────────────────
# PR cost split: divide total cost evenly across all PRs in this run.
# A single-PR run uses factor 1; a be-fe-pair run splits across its per-repo PRs.
# ────────────────────────────────────────────────────────────────────────────
if [ "$STATELESS" -eq 1 ]; then
  # No PR set to split across — the lean session posts one block in one comment. The
  # duration comes from the supplied fence, which is the only span this mode knows.
  PR_COUNT=1
  STARTED_AT="$ARG_START"
  COMPLETED_AT="$ARG_END"
else
PR_COUNT=$(jq -r '[.prs | values[]? | select(. != null)] | length' "$STATE_FILE")
# State exists but carries no PRs → record the skip reason (never a bare null /
# silent exit — #188). Sibling of the skipped-* paths above.
[ "$PR_COUNT" -eq 0 ] && { log "no PRs in state — skipping"; record '"skipped-no-prs"'; exit 0; }
fi

SPLIT_FACTOR="1"
if [ "$PR_COUNT" -gt 1 ]; then
  SPLIT_FACTOR=$(awk "BEGIN { printf \"%.6f\", 1/$PR_COUNT }")
fi

if [ "$STATELESS" -eq 0 ]; then
STARTED_AT=$(jq -r '.startedAt // empty' "$STATE_FILE")
COMPLETED_AT=$(jq -r '.lastUpdatedAt // empty' "$STATE_FILE")
fi
DURATION_MIN="?"
if [ -n "$STARTED_AT" ] && [ -n "$COMPLETED_AT" ]; then
  S=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED_AT" +%s 2>/dev/null || date -d "$STARTED_AT" +%s 2>/dev/null)
  E=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$COMPLETED_AT" +%s 2>/dev/null || date -d "$COMPLETED_AT" +%s 2>/dev/null)
  [ -n "$S" ] && [ -n "$E" ] && DURATION_MIN=$(( (E - S) / 60 ))
fi

# Fallback duration from OTel row span when state timestamps are bogus.
if [ "$DURATION_MIN" = "?" ] || [ "$DURATION_MIN" = "0" ]; then
  ROW_SPAN=$(jq -r '.rowSpanSeconds // 0' <<<"$ROLLUP")
  if [ -n "$ROW_SPAN" ] && [ "$ROW_SPAN" != "0" ] && [ "$ROW_SPAN" != "null" ]; then
    DURATION_MIN=$(awk "BEGIN { d = int($ROW_SPAN / 60); if (d < 1) d = 1; print d }")
  fi
fi

# Test hook: when COST_BLOCK_DUMP_LOGROW is set, append the cross-run cost-log row
# via the real write_cost_log_row and print it, then exit before any PR I/O. Lets
# cost-block-selftest.sh assert the persisted row's shape (e.g. byLabel) without a
# real PR. Placed here so write_cost_log_row's globals ($ROLLUP, $SIDS_JSON,
# $DURATION_MIN) are all in scope. The row is redirected to $COST_LOG_FILE (which
# cost-block-selftest.sh sets to a temp path) so nothing in the real cost-log.jsonl
# is touched — the selftest keeps the real fixture state dir, only the log path is
# overridden. Never set in production. (Sibling of COST_BLOCK_DUMP_ROLLUP above.)
if [ -n "${COST_BLOCK_DUMP_LOGROW:-}" ]; then
  write_cost_log_row
  tail -n 1 "${COST_LOG_FILE:-$(dirname "$STATE_FILE")/cost-log.jsonl}"
  exit 0
fi

# ────────────────────────────────────────────────────────────────────────────
# Render cost block (Markdown). Marker is first line for idempotent detection.
# ────────────────────────────────────────────────────────────────────────────
render_block() {
  local factor="$1"
  local windows_ok="$2"
  # HH:MM bounds of the active time fence (empty when the fence is disabled).
  local fence_lo_hm="" fence_hi_hm=""
  if [ -n "$FENCE_LO" ] && [ -n "$FENCE_HI" ]; then
    fence_lo_hm="${FENCE_LO:11:5}"
    fence_hi_hm="${FENCE_HI:11:5}"
  fi
  # The session-total row's parenthetical. In state-less mode the absence of a per-stage
  # breakdown is not a defect to apologize for — lean has no stages by construction — so
  # the honest label says that instead of implying the run failed to record timestamps.
  local total_note="per-stage breakdown unavailable — pipeline did not record stage timestamps"
  [ "$STATELESS" -eq 1 ] && total_note="lean run — no stage windows by design"
  jq -r --arg factor "$factor" --arg dur "$DURATION_MIN" --arg windows_ok "$windows_ok" \
        --arg totalNote "$total_note" \
        --argjson tierOrder "$TIER_ORDER" \
        --arg fenceLoHm "$fence_lo_hm" --arg fenceHiHm "$fence_hi_hm" '
    def usd(x): x * ($factor|tonumber);
    def fmt(x):
      (x * 100 | round) as $c
      | "$" + ( ($c / 100 | floor) | tostring ) + "." +
        ( $c % 100 | tostring | if length == 1 then "0" + . else . end );
    # The render filter (see RENDER FILTER in the header). A row with no money and no model
    # identity reports nothing; the rollup and the cost-log row keep it regardless.
    def reportable: select((.cost_usd > 0) or ((.models | length) > 0));
    ([.byLabel[].models[]] | unique | sort) as $all_models |
    ([.byLabel[] | reportable | .tier] | unique | sort_by($tierOrder[.] // 9)) as $all_tiers |
    (
      [
        "<!-- pipeline-cost-block -->",
        "---",
        "",
        "## Pipeline Cost",
        ""
      ]
      +
      ( if $windows_ok == "yes" then
          [ "| Stage | Tier | Models | Cost (USD) |",
            "|-------|------|--------|-----------:|" ] +
          [ .byLabel[] | reportable |
              "| " + .label +
              " | " + .tier +
              " | " + (.models | join(", ")) +
              " | " + fmt(usd(.cost_usd)) + " |"
          ] +
          [ "| **Total** | | | **" + fmt(usd(.totals.cost_usd)) + "** |" ]
        else
          [ "| Scope | Tiers | Models | Cost (USD) |",
            "|-------|-------|--------|-----------:|",
            "| Session total (" + $totalNote + ") | " + ($all_tiers | join(", ")) + " | " + ($all_models | join(", ")) + " | " + fmt(usd(.totals.cost_usd)) + " |"
          ]
        end
      )
      +
      [
        "",
        "Cache-hit rate: " + ((.totals.cache_hit_rate * 100 | round) | tostring) + "%"
          + " · Pipeline run: " + $dur + " min"
          + " · Sessions: " + (.totals.session_count | tostring)
          + ( if $fenceLoHm != "" then " (time-fenced " + $fenceLoHm + "–" + $fenceHiHm + ")" else "" end )
          + ( if ($factor|tonumber) < 1 then " · Split " + (1/($factor|tonumber) | tostring) + "-way across the PRs in this run" else "" end )
          + " · Source: OTel `claude_code.cost.usage`"
      ]
    ) | .[]
  ' <<<"$ROLLUP"
}

COST_BLOCK=$(render_block "$SPLIT_FACTOR" "$STAGE_WINDOWS_OK")
if [ "$STAGE_WINDOWS_OK" != "yes" ] && [ "$STATELESS" -eq 0 ]; then
  log "state file lacks valid per-stage timestamps — emitting single-row session total"
fi

# ────────────────────────────────────────────────────────────────────────────
# State-less mode ends here: emit and stop. No PR body is amended (the lean session
# posts the block itself, in its one closing comment) and NO cost-log.jsonl row is
# written — lean runs are out of the perf corpus by declaration (D-36), so a row here
# would quietly contaminate cross-run analytics with a harness that has no stages.
# ────────────────────────────────────────────────────────────────────────────
if [ "$STATELESS" -eq 1 ]; then
  if [ -n "$ARG_OUT" ]; then
    printf '%s\n' "$COST_BLOCK" > "$ARG_OUT" || { log "could not write --out '$ARG_OUT'"; exit 2; }
    log "state-less cost block written to $ARG_OUT"
  else
    printf '%s\n' "$COST_BLOCK"
  fi
  exit 0
fi

# ────────────────────────────────────────────────────────────────────────────
# Amend each PR body, idempotent via the <!-- pipeline-cost-block --> marker.
# Reads always use plain `gh`; writes use `$GH_CMD` — the wrapper on a bot-enabled
# repo, plain `gh` (operator identity) otherwise. See the write-identity block above.
# ────────────────────────────────────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  log "gh CLI not found — skipping PR amend"
  record '"skipped-no-gh-cli"'
  exit 0
fi

amend_pr() {
  local url="$1"
  local owner_repo number
  owner_repo=$(sed -E 's#https://github.com/([^/]+/[^/]+)/pull/.*#\1#' <<<"$url")
  number=$(sed -E 's#.*/pull/([0-9]+).*#\1#' <<<"$url")
  [ -z "$owner_repo" ] || [ -z "$number" ] && { log "could not parse $url"; return 1; }

  local existing
  existing=$(gh pr view --repo "$owner_repo" "$number" --json body --jq .body 2>/dev/null) || return 1
  if grep -qF '<!-- pipeline-cost-block -->' <<<"$existing"; then
    log "$owner_repo#$number already has cost block — skipping"
    return 0
  fi

  local new_body_file
  new_body_file=$(mktemp)
  { printf '%s\n\n' "$existing"; printf '%s\n' "$COST_BLOCK"; } > "$new_body_file"
  if "$GH_CMD" pr edit --repo "$owner_repo" "$number" --body-file "$new_body_file" >/dev/null 2>&1; then
    log "appended cost block to $owner_repo#$number"
  else
    log "gh pr edit failed for $owner_repo#$number"
    rm -f "$new_body_file"
    return 1
  fi
  rm -f "$new_body_file"
}

AMEND_OK=1
while IFS= read -r url; do
  [ -z "$url" ] || [ "$url" = "null" ] && continue
  amend_pr "$url" || AMEND_OK=0
done < <(jq -r '.prs | values[]? | select(. != null) | .url // empty' "$STATE_FILE")

if [ "$AMEND_OK" -eq 1 ]; then
  record true
  log "cost block applied to all PRs"
else
  record '"skipped-amend-failed"'
fi

# ────────────────────────────────────────────────────────────────────────────
# Append a machine-readable row to cost-log.jsonl for cross-run analytics.
# ────────────────────────────────────────────────────────────────────────────
write_cost_log_row

exit 0

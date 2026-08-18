#!/bin/bash
# pipeline-cost-block.sh — compute a session-window OTel cost block for a lean run.
# Invoked explicitly by the caller (this is NOT a Stop hook).
#
# Usage:  pipeline-cost-block.sh --stateless --sessions <id[,id…]> \
#                                --start <iso> --end <iso> [--out <file>]
# Exit:   0 = ran, or logged a documented skip (no metrics, no collector, rotated-out,
#         …). 2 = usage error. The caller (build-lean checklist step 7) invokes this
#         without checking rc, so a non-zero exit surfaces in the run summary but never
#         blocks completion.
#
# STATE-LESS ONLY (#574). The per-stage STATEFUL branch — bucketing cost rows into
# stage windows read from a staged state file, the cost-log.jsonl writer and the
# costBlockApplied record — was unreachable from the moment #348 deleted the staged
# lane (no lane wrote the state files it read), and was retired with #574. The
# `--stateless` flag is kept REQUIRED so the surviving caller's invocation shape is
# unchanged; a positional-issue invocation now errors with this pointer instead of
# resolving a state file nothing writes. The two required inputs arrive as ARGUMENTS
# (the session-id set and a [start, end] time fence, both carried by the lean progress
# file); the block is emitted to stdout or --out, no PR body is amended, and no
# cost-log.jsonl row is written (lean is out of the perf corpus by declaration, D-36).
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
    -h|--help)   sed -n '2,64p' "$0"; exit 0 ;;
    -*)          log "unknown option: $1"; exit 2 ;;
    *)           POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- ${POSITIONAL_ARGS+"${POSITIONAL_ARGS[@]}"}

if [ "$STATELESS" -ne 1 ]; then
  log "stateful mode was retired in #574 — the staged state files it read have had no writer since #348. Invoke with --stateless --sessions <id[,id…]> --start <iso> --end <iso>."
  exit 2
fi
[ -n "$ARG_SESSIONS" ] || { log "--stateless requires --sessions <id[,id…]>"; exit 2; }
[ -n "$ARG_START" ] && [ -n "$ARG_END" ] \
  || { log "--stateless requires both --start <iso> and --end <iso> (the time fence)"; exit 2; }

# Session set: HANDED to this mode by its caller (comma- or whitespace-separated);
# the lean progress file is its carrier, which is why AC-14's reconciliation keys are
# load-bearing here rather than forward-looking.
SESSIONS=$(printf '%s' "$ARG_SESSIONS" | tr ',' '\n' | tr ' ' '\n' | awk 'NF' | sort -u)

if [ -z "$SESSIONS" ]; then
  log "skip(no-sessions): the supplied --sessions set is empty"
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
  log "skip(telemetry-off): no OTel metrics file at $METRICS_FILE, and no rotated backup beside it — was otelcol-contrib running?"
  exit 0
fi

# Let any in-flight metrics flush from the collector. Skipped under the rollup dump
# hook and under COST_BLOCK_SKIP_FLUSH (set by cost-block-selftest.sh for the paths
# that exit before rendering) — fixtures are static, nothing to flush.
[ -z "${COST_BLOCK_DUMP_ROLLUP:-}${COST_BLOCK_SKIP_FLUSH:-}" ] && sleep 5

# ────────────────────────────────────────────────────────────────────────────
# Rollup: filter each metrics row by session.id in $SESSIONS and the time fence,
# then bucket by TIER (see TIER BUCKETING in the header). Lean has no stage
# windows by construction, so there is no per-stage axis — one label, tier rows.
# ────────────────────────────────────────────────────────────────────────────
SIDS_JSON=$(jq -R -s 'split("\n") | map(select(length > 0))' <<<"$SESSIONS")

# ────────────────────────────────────────────────────────────────────────────
# Per-run time fence. A long-lived interactive Claude Code session can host
# several sequential runs under ONE session.id; without a fence, a later run's
# rollup inhales every co-resident datapoint. Clamp each run to its own
# wall-clock span in ADDITION to session.id. Timestamps are ISO-8601 Z strings
# (nanos_to_iso renders the same form), so lexicographic compare is
# chronological.
# ────────────────────────────────────────────────────────────────────────────
# The fence is an ARGUMENT — lean has no stage timestamps to derive one from. It is
# required (not optional, enforced at parse) precisely because session-only
# attribution would inhale every co-resident datapoint from a long-lived
# interactive session. The rollup still carries the empty-fence disabled branch:
# it costs one comparison and keeps compute_bucket_rollup honest about what an
# empty bound would mean, rather than encoding an assumption a future caller
# cannot see.
FENCE_LO="$ARG_START"
FENCE_HI="$ARG_END"

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
        --argjson tierOrder "$TIER_ORDER" '
    def nanos_to_iso: tonumber / 1e9 | todate;
    # Total by construction: a non-string (absent) id, and a string matching no family
    # substring, both land in "unknown".
    def tier_of($m):
      if ($m | type) != "string" then "unknown"
      else ( [ $tierMap | to_entries[] as $e | select($m | contains($e.key)) | $e.value ] | first ) // "unknown"
      end;
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
    # No stage axis (lean has no stage windows): every in-fence row for this run
    # is $tagged, and the rollup groups by TIER alone. The field is named byTier so
    # a reader cannot mistake it for the retired per-stage byLabel.
    $rows as $tagged
    |
    {
      byTier: (
        $tagged
        | group_by(.tier)
        | map({
            tier: .[0].tier,
            cost_usd: ( [.[] | select(.name=="claude_code.cost.usage") | .value] | add // 0 ),
            models: ( [.[] | .model // empty] | unique | sort )
          })
        | sort_by($tierOrder[.tier] // 9)
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

ROLLUP=$(compute_bucket_rollup 2>/dev/null)
if [ -z "$ROLLUP" ] || ! jq -e . >/dev/null 2>&1 <<<"$ROLLUP"; then
  log "skip(otel-error): OTel metrics query failed"
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
    log "skip(rotated-out): the retained metrics start at $OLDEST_SCANNED, after this run's fence opened at $FENCE_LO — the file covering the run has rotated out of retention (max_backups/max_days), or the collector was not running yet. Cost for this run is unrecoverable."
  elif [ "$FENCE_ROW_COUNT" -gt 0 ]; then
    log "skip(session-not-exporting): $FENCE_ROW_COUNT in-fence rows from other sessions, none from this run's session ids — this session was launched without CLAUDE_CODE_ENABLE_TELEMETRY and exported nothing. Set it in ~/.claude/settings.json's env block (cost-tracking-setup.md §3); the datapoints cannot be recovered for this run."
  else
    log "skip(telemetry-off): no rows at all inside the fence [$FENCE_LO, $FENCE_HI] — the collector was down for the run's whole window, or nothing on this machine was exporting."
  fi
  exit 0
fi

if [ -z "$TOTAL_COST" ] || [ "$TOTAL_COST" = "0" ] || [ "$TOTAL_COST" = "null" ]; then
  log "skip(zero-datapoints): $ROW_COUNT in-fence rows for this run's sessions, but no claude_code.cost.usage among them — telemetry is flowing; there is genuinely no cost to report."
  exit 0
fi

# ────────────────────────────────────────────────────────────────────────────
# Duration: the supplied fence is the only span this mode knows. There is no PR
# split — the lean session posts one block in one closing comment.
# ────────────────────────────────────────────────────────────────────────────
STARTED_AT="$ARG_START"
COMPLETED_AT="$ARG_END"
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

# ────────────────────────────────────────────────────────────────────────────
# Render cost block (Markdown). Marker is first line for idempotent detection.
# ────────────────────────────────────────────────────────────────────────────
render_block() {
  # HH:MM bounds of the active time fence (empty when the fence is disabled).
  local fence_lo_hm="" fence_hi_hm=""
  if [ -n "$FENCE_LO" ] && [ -n "$FENCE_HI" ]; then
    fence_lo_hm="${FENCE_LO:11:5}"
    fence_hi_hm="${FENCE_HI:11:5}"
  fi
  # The session-total row's parenthetical. The absence of a per-stage breakdown is not
  # a defect to apologize for — lean has no stages by construction — so the honest
  # label says that instead of implying the run failed to record timestamps.
  local total_note="lean run — no stage windows by design"
  jq -r --arg dur "$DURATION_MIN" \
        --arg totalNote "$total_note" \
        --argjson tierOrder "$TIER_ORDER" \
        --arg fenceLoHm "$fence_lo_hm" --arg fenceHiHm "$fence_hi_hm" '
    def fmt(x):
      (x * 100 | round) as $c
      | "$" + ( ($c / 100 | floor) | tostring ) + "." +
        ( $c % 100 | tostring | if length == 1 then "0" + . else . end );
    # The render filter (see RENDER FILTER in the header). A row with no money and no model
    # identity reports nothing; the rollup and the cost-log row keep it regardless.
    def reportable: select((.cost_usd > 0) or ((.models | length) > 0));
    ([.byTier[].models[]] | unique | sort) as $all_models |
    ([.byTier[] | reportable | .tier] | unique | sort_by($tierOrder[.] // 9)) as $all_tiers |
    (
      [
        "<!-- pipeline-cost-block -->",
        "---",
        "",
        "## Pipeline Cost",
        "",
        "| Scope | Tiers | Models | Cost (USD) |",
        "|-------|-------|--------|-----------:|",
        "| Session total (" + $totalNote + ") | " + ($all_tiers | join(", ")) + " | " + ($all_models | join(", ")) + " | " + fmt(.totals.cost_usd) + " |"
      ]
      +
      [
        "",
        "Cache-hit rate: " + ((.totals.cache_hit_rate * 100 | round) | tostring) + "%"
          + " · Pipeline run: " + $dur + " min"
          + " · Sessions: " + (.totals.session_count | tostring)
          + ( if $fenceLoHm != "" then " (time-fenced " + $fenceLoHm + "–" + $fenceHiHm + ")" else "" end )
          + " · Source: OTel `claude_code.cost.usage`"
      ]
    ) | .[]
  ' <<<"$ROLLUP"
}

COST_BLOCK=$(render_block)

# ────────────────────────────────────────────────────────────────────────────
# Emit. No PR body is amended (the lean session posts the block itself, in its one
# closing comment) and NO cost-log.jsonl row is written — lean runs are out of the
# perf corpus by declaration (D-36), so a row here would quietly contaminate
# cross-run analytics with a harness that has no stages.
# ────────────────────────────────────────────────────────────────────────────
if [ -n "$ARG_OUT" ]; then
  printf '%s\n' "$COST_BLOCK" > "$ARG_OUT" || { log "could not write --out '$ARG_OUT'"; exit 2; }
  log "state-less cost block written to $ARG_OUT"
else
  printf '%s\n' "$COST_BLOCK"
fi
exit 0

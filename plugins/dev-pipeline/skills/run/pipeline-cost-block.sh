#!/bin/bash
# pipeline-cost-block.sh — append a per-stage OTel cost block to a dev-pipeline
# run's PR(s). Invoked explicitly by Stage 9 (this is NOT a Stop hook).
#
# Usage:  pipeline-cost-block.sh <issue-number>
# Exit:   0 = ran, or recorded a documented skip (no metrics, no bot wrapper, no
#         collector, no PRs, …) into the state file's costBlockApplied field.
#         non-zero = the state file could not be resolved (nothing to record
#         into) — a loud, state-unresolvable failure. Either way the sub-step is
#         non-fatal to Stage 9: the caller invokes it without checking rc, so a
#         non-zero exit surfaces in the run summary but never blocks completion.

set -uo pipefail
log() { echo "[pipeline-cost-block] $*" >&2; }

ISSUE_RAW="${1:?usage: pipeline-cost-block.sh <issue-number>}"
ISSUE=$(echo "$ISSUE_RAW" | tr '[:upper:]' '[:lower:]')

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
STATE_FILE=$(resolve_state)
# No state file at the resolved path is UNRECORDABLE: record() writes into
# $STATE_FILE, which by definition does not exist here, so we cannot leave a
# costBlockApplied breadcrumb. Fail LOUD (non-zero) instead of the old silent
# `exit 0` — a bare null was the #188 silent-skip. A cross-repo run must point
# this script at the CONTROL repo's state (Stage 9 exports SECOND_SHIFT_REPO_ROOT
# on the invocation; operators of a bespoke cwd set STATECTL_STATE_DIR). Stage 9
# invokes this without checking rc, so the non-zero never blocks completion.
[ -f "$STATE_FILE" ] || { log "no state file at $STATE_FILE — state unresolvable, cannot record costBlockApplied (see #188: export SECOND_SHIFT_REPO_ROOT/STATECTL_STATE_DIR to the control repo)"; exit 2; }

# ────────────────────────────────────────────────────────────────────────────
# Record outcome into costBlockApplied (raw jq — statectl does not own this).
# ────────────────────────────────────────────────────────────────────────────
record() {
  local val="$1"  # JSON scalar: `true` or a quoted string
  local tmp
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
# Bot wrapper: env contract first; then config tracker.bot.wrapperPath (parity
# with claim-issue.sh / pipeline-doctor.sh); then a default derived from the
# consumer repo's directory name (install-gh-bot.sh creates it at this path).
_default_bot() {
  local cd root
  if cd=$(git rev-parse --git-common-dir 2>/dev/null) && cd=$(cd "$cd" 2>/dev/null && pwd); then
    root=$(dirname "$cd")
    echo "$HOME/.config/$(basename "$root")/gh-as-bot.sh"
  else
    echo "$HOME/.config/gh-as-bot/gh-as-bot.sh"
  fi
}

CFG_FILE=$(_config_path)
BOT_ENABLED=false
if [ -n "$CFG_FILE" ] && [ -f "$CFG_FILE" ]; then
  BOT_ENABLED=$(jq -r '.tracker.bot.enabled // false' "$CFG_FILE" 2>/dev/null) || BOT_ENABLED=false
  [ "$BOT_ENABLED" = "true" ] || BOT_ENABLED=false
fi

if [ "$BOT_ENABLED" = "true" ]; then
  if [ -z "${GH_BOT:-}" ]; then
    WRAPPER=$(jq -r '.tracker.bot.wrapperPath // empty' "$CFG_FILE" 2>/dev/null) || WRAPPER=""
    if [ -n "$WRAPPER" ]; then
      GH_BOT="${WRAPPER/#\~/$HOME}"
    else
      GH_BOT=$(_default_bot)
    fi
  fi
  if [ ! -x "$GH_BOT" ]; then
    log "GH_BOT wrapper not found at $GH_BOT — skipping PR amend (see cost-tracking-setup.md prerequisites)"
    record '"skipped-no-bot-wrapper"'
    exit 0
  fi
  GH_CMD="$GH_BOT"
else
  GH_CMD="gh"
  log "config tracker.bot.enabled is not true — amending PR under operator identity via plain gh"
fi

# ────────────────────────────────────────────────────────────────────────────
# Session set: read explicit pipelineSessions[] recorded by Stage 2 / Stage 8.
# Each id is the native Claude Code session UUID ($CLAUDE_CODE_SESSION_ID), the
# same value the collector tags datapoints with as session.id; a crash-recovery
# Stage 8 resume records its own (distinct) UUID. Runs with no recorded sessions
# skip cleanly.
# ────────────────────────────────────────────────────────────────────────────
SESSIONS=$(jq -r '
  (.pipelineSessions // [])
  | map(.sessionId // empty)
  | map(select(. != null and . != ""))
  | unique
  | .[]
' "$STATE_FILE")

if [ -z "$SESSIONS" ]; then
  log "no pipelineSessions recorded — skipping (Stage 2 session derivation did not run?)"
  record '"skipped-no-sessions"'
  exit 0
fi

METRICS_FILE="${OTEL_METRICS_FILE:-$HOME/.claude/otel-metrics/metrics.jsonl}"
if [ ! -s "$METRICS_FILE" ]; then
  log "no OTel metrics file at $METRICS_FILE — was otelcol-contrib running?"
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
FENCE_LO=$(jq -r '.startedAt // empty' "$STATE_FILE")
FENCE_HI=$(jq -r '
  ([.stages[]?.completedAt // empty] | map(select(. != null and . != "")) | max) //
  (.lastUpdatedAt // empty) // empty
' "$STATE_FILE")
if [ -z "$FENCE_LO" ] || [ -z "$FENCE_HI" ]; then
  log "no usable time fence (startedAt/completedAt/lastUpdatedAt missing) — degrading to session-only attribution"
  FENCE_LO=""
  FENCE_HI=""
fi

compute_bucket_rollup() {
  jq -s --argjson sids "$SIDS_JSON" \
        --arg fenceLo "$FENCE_LO" \
        --arg fenceHi "$FENCE_HI" \
        --argjson stages "$(jq -c '.stages' "$STATE_FILE")" '
    def nanos_to_iso: tonumber / 1e9 | todate;
    def stage_label(n):
      {"1":"Intake","2":"Intake",
       "3":"Plan","4":"Plan",
       "5":"Implementation","6":"Verify","7":"Doc Update",
       "8":"Code Review","9":"PR Creation","10":"Cleanup"}
      [n|tostring] // "Other";

    # Flatten all cost + token datapoints whose session.id is in $sids.
    [ .[] | select(.resourceMetrics)
          | .resourceMetrics[].scopeMetrics[].metrics[]
          | {name, dps: (.sum.dataPoints // [])}
          | .dps[] as $dp
          | ($dp.attributes | map({(.key): (.value.stringValue // .value.intValue)}) | add) as $attrs
          | ($dp.timeUnixNano | nanos_to_iso) as $t
          | select( ($sids | index($attrs["session.id"])) != null )
          # Per-run time fence: keep only datapoints inside the run wall-clock
          # span. Disabled (kept) when $fenceLo is empty. This is what stops a
          # co-resident sequential run/retro (same session.id) from leaking in.
          | select( $fenceLo == "" or ($t >= $fenceLo and $t <= $fenceHi) )
          | { name, t: $t,
              value: ($dp.asDouble // ($dp.asInt // 0 | tonumber)),
              model: $attrs.model,
              token_type: $attrs.type,
              sid: $attrs["session.id"] }
    ] as $rows
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
        | group_by(.label)
        | map({
            label: .[0].label,
            cost_usd: ( [.[] | select(.name=="claude_code.cost.usage") | .value] | add // 0 ),
            models: ( [.[] | .model // empty] | unique | sort )
          })
        | sort_by(
            {"Intake":1,"Plan":2,"Implementation":3,"Verify":4,"Doc Update":5,
             "Code Review":6,"PR Creation":7,"Cleanup":8,"Other":9}
             [.label] // 10
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
    | .rowSpanSeconds = (
        if ($tagged | length) > 1 then
          ( ( [$tagged[].t] | max | fromdateiso8601 )
            - ( [$tagged[].t] | min | fromdateiso8601 ) )
        else 0 end )
  ' "$METRICS_FILE"
}

# Stage-window quality check: if startedAt is missing everywhere, or all
# timestamps collapse to a single distinct value, bucketing is meaningless
# and we degrade to a single-row "Session total" table.
# This also tolerates a lifecycle-less final stage (e.g. a Stage 9 that never
# wrote startedAt — see #174): the gate keys off >=2 starts / >=3 distinct
# timestamps across ALL stages, so a single missing final-stage window still
# passes (prior stages satisfy it) and never crashes the cost block.
stage_windows_ok() {
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

TOTAL_COST=$(jq -r '.totals.cost_usd' <<<"$ROLLUP")
if [ -z "$TOTAL_COST" ] || [ "$TOTAL_COST" = "0" ] || [ "$TOTAL_COST" = "null" ]; then
  log "no metrics rows for recorded sessions (collector may have missed the run, or session ids drifted from what the collector sees)"
  record '"skipped-zero-datapoints"'
  exit 0
fi

# ────────────────────────────────────────────────────────────────────────────
# PR cost split: divide total cost evenly across all PRs in this run.
# Stacked-PR runs split evenly across slices; single-PR runs use factor 1.
# ────────────────────────────────────────────────────────────────────────────
PR_COUNT=$(jq -r '[.prs | values[]? | select(. != null)] | length' "$STATE_FILE")
# State exists but carries no PRs → record the skip reason (never a bare null /
# silent exit — #188). Sibling of the skipped-* paths above.
[ "$PR_COUNT" -eq 0 ] && { log "no PRs in state — skipping"; record '"skipped-no-prs"'; exit 0; }

SPLIT_FACTOR="1"
if [ "$PR_COUNT" -gt 1 ]; then
  SPLIT_FACTOR=$(awk "BEGIN { printf \"%.6f\", 1/$PR_COUNT }")
fi

STARTED_AT=$(jq -r '.startedAt // empty' "$STATE_FILE")
COMPLETED_AT=$(jq -r '.lastUpdatedAt // empty' "$STATE_FILE")
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
  jq -r --arg factor "$factor" --arg dur "$DURATION_MIN" --arg windows_ok "$windows_ok" \
        --arg fenceLoHm "$fence_lo_hm" --arg fenceHiHm "$fence_hi_hm" '
    def usd(x): x * ($factor|tonumber);
    def fmt(x):
      (x * 100 | round) as $c
      | "$" + ( ($c / 100 | floor) | tostring ) + "." +
        ( $c % 100 | tostring | if length == 1 then "0" + . else . end );
    ([.byLabel[].models[]] | unique | sort) as $all_models |
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
          [ "| Stage | Models | Cost (USD) |",
            "|-------|--------|-----------:|" ] +
          [ .byLabel[] |
              "| " + .label +
              " | " + (.models | join(", ")) +
              " | " + fmt(usd(.cost_usd)) + " |"
          ] +
          [ "| **Total** | | **" + fmt(usd(.totals.cost_usd)) + "** |" ]
        else
          [ "| Scope | Models | Cost (USD) |",
            "|-------|--------|-----------:|",
            "| Session total (per-stage breakdown unavailable — pipeline did not record stage timestamps) | " + ($all_models | join(", ")) + " | " + fmt(usd(.totals.cost_usd)) + " |"
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
          + ( if ($factor|tonumber) < 1 then " · Split " + (1/($factor|tonumber) | tostring) + "-way across stacked-PR slices" else "" end )
          + " · Source: OTel `claude_code.cost.usage`"
      ]
    ) | .[]
  ' <<<"$ROLLUP"
}

COST_BLOCK=$(render_block "$SPLIT_FACTOR" "$STAGE_WINDOWS_OK")
if [ "$STAGE_WINDOWS_OK" != "yes" ]; then
  log "state file lacks valid per-stage timestamps — emitting single-row session total"
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

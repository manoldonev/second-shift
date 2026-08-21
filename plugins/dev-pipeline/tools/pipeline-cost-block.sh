#!/bin/bash
# pipeline-cost-block.sh — compute a session-window OTel cost block for a lean run.
# Invoked explicitly by the caller (this is NOT a Stop hook).
#
# Usage:  pipeline-cost-block.sh --stateless --issue <n> [--close-out]
#                                [--prs <ref[,ref…]>] [--out <file>]
#         pipeline-cost-block.sh --stateless --sessions <id[,id…]> \
#                                --start <iso> --end <iso> [--out <file>]
# Exit:   0 = ran, or logged a documented skip (no metrics, no collector, rotated-out,
#         …). 2 = usage error. The caller (build-lean checklist steps 7 and 9) invokes
#         this without checking rc, so a non-zero exit surfaces in the run summary but
#         never blocks completion.
#
# STATE-LESS ONLY (#574). The per-stage STATEFUL branch — bucketing cost rows into
# stage windows read from a staged state file, the cost-log.jsonl writer and the
# costBlockApplied record — was unreachable from the moment #348 deleted the staged
# lane (no lane wrote the state files it read), and was retired with #574. The
# `--stateless` flag is kept REQUIRED so the surviving caller's invocation shape is
# unchanged; a positional-issue invocation now errors with this pointer instead of
# resolving a state file nothing writes. The block is emitted to stdout or --out and no
# PR body is amended — the lean session pastes it into the PR description and the closing
# comment itself, so re-adding the retired bot-identity amend ladder would buy access to a
# body the caller already owns.
#
# DERIVED INPUTS (#546). The two inputs — the session-id set and a [start, end] time fence
# — used to arrive ONLY as arguments, which made every published figure as good as the
# reconstruction of the one session least able to make it: the close-out one, which by
# construction did not watch the run begin and does not know how many sessions preceded it.
# One shipped run published "43 min · Sessions: 1" for a 98-minute, three-session run, and
# nothing caught it — a wrong fence renders a block as well-formed as a right one.
#
# `--issue <n>` reads both off the run's own append-only progress record instead:
#   fence     its FIRST timestamped row → its LAST, at invocation time.
#   sessions  build_session_set() below — header `session_id:` ∪ every `| session |` row —
#             UNIONED with the verdict record's `session_id:` when that record exists, so a
#             close-out counts the review session it really paid for. A pre-review or
#             aborted invocation finds no verdict record and degrades to the build set.
# `--sessions`, `--start` and `--end` each still override their derived counterpart, and
# without `--issue` the contract is exactly what it was: both required, rc=2 by name.
# A record that is absent, unreadable, or carries no timestamped row is a rc=2 USAGE ERROR
# — rendering a plausible default is the whole defect this mode exists to close.
#
# THE COST-LOG ROW (#546). `--close-out` appends or updates one row per run in
# ${COST_LOG_FILE:-<stateDir>/cost-log.jsonl}, restoring the cross-run cost corpus that
# ended on 2026-07-31 when the lean era began — cost-effectiveness is one of the two
# ratified goal axes and had nothing left to be measured against. This supersedes the live
# half of D-36 (its perf-corpus half was already retired by #565).
#
# The row is written ONLY under --close-out, so the step-7 snapshot — taken before review
# has happened, over a fence that has not finished — leaves the corpus untouched. Verdict
# record presence cannot serve as the trigger: it is true from the moment milestone 4
# passes, which is not the close-out.
#
# Its identity is (`ticketKey`, `runId`): a write REPLACES a row carrying the same pair and
# APPENDS otherwise, so a re-entered close-out updates its own row while an abort→retry
# under a new run id appends — aborted runs are real cost and stay in the corpus.
#
# Schema: every key a staged-era row carried (`at`, `ticketKey`, `sessionIds`, `totalUsd`,
# `durationMin`, `models`, `cacheHitRate`, `prs`) plus `runId`, and `byTier` where staged
# rows had `byLabel`. There is no `byLabel` and no era-marker field: which of the two keys
# is PRESENT is the discriminator, and a reader that wants the flat tier list has
# `[byTier[].tier] | unique`. No rollup means no row — every skip(…) exit below records its
# stderr verdict and writes nothing, which is what the retired writer did.
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

# The two literals that BOUND a rendered block inside a PR description, and the reason they are
# held to a copy rather than left inline in the jq program below. lean-gate.sh's close-out
# REPLACES a stale block in a body it does not otherwise own: it strips from the marker line
# through the first following line carrying the terminator prefix, and leaves everything after it
# untouched. If the renderer's last line moved and the stripper's did not, that strip would run to
# end-of-file and silently delete whatever a human had appended below the block.
# LOCKSTEP-BEGIN lean-cost-block-bounds
COST_BLOCK_MARKER='<!-- pipeline-cost-block -->'
COST_BLOCK_TERMINATOR='Cache-hit rate: '
# LOCKSTEP-END lean-cost-block-bounds

STATELESS=0
ARG_SESSIONS=""
ARG_START=""
ARG_END=""
ARG_OUT=""
ARG_ISSUE=""
ARG_PRS=""
CLOSE_OUT=0
POSITIONAL_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --stateless) STATELESS=1; shift ;;
    --sessions)  ARG_SESSIONS="${2:-}"; shift 2 ;;
    --start)     ARG_START="${2:-}"; shift 2 ;;
    --end)       ARG_END="${2:-}"; shift 2 ;;
    --out)       ARG_OUT="${2:-}"; shift 2 ;;
    --issue)     ARG_ISSUE="${2:-}"; shift 2 ;;
    --prs)       ARG_PRS="${2:-}"; shift 2 ;;
    --close-out) CLOSE_OUT=1; shift ;;
    -h|--help)   sed -n '2,106p' "$0"; exit 0 ;;
    -*)          log "unknown option: $1"; exit 2 ;;
    *)           POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- ${POSITIONAL_ARGS+"${POSITIONAL_ARGS[@]}"}

if [ "$STATELESS" -ne 1 ]; then
  log "stateful mode was retired in #574 — the staged state files it read have had no writer since #348. Invoke with --stateless --sessions <id[,id…]> --start <iso> --end <iso>."
  exit 2
fi

# ────────────────────────────────────────────────────────────────────────────
# Derivation from the run's own record (#546). See DERIVED INPUTS in the header.
# ────────────────────────────────────────────────────────────────────────────
# The MAIN checkout, not the worktree: the progress record lives there so it survives
# worktree teardown. Same --git-common-dir anchor lean-gate.sh and retro-corpus.sh use.
# The VERDICT record is the other way round — it is a committed artifact of the branch, so
# it is resolved against the cwd's toplevel, which during close-out is the lane worktree.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
_common="$(git rev-parse --git-common-dir 2>/dev/null)"
case "$_common" in /*) : ;; '') _common="" ;; *) _common="$REPO_ROOT/$_common" ;; esac
MAIN_ROOT=""
[ -n "$_common" ] && MAIN_ROOT="$(cd "$_common/.." 2>/dev/null && pwd)"

CONFIG="${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}"
cfg() { # cfg <jq-filter> <default>
  local v
  if [ -f "$CONFIG" ]; then
    v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
    if [ -n "$v" ] && [ "$v" != "null" ]; then echo "$v"; return 0; fi
  fi
  echo "$2"
}

state_dir() {
  if [ -n "${STATECTL_STATE_DIR:-}" ]; then printf '%s\n' "$STATECTL_STATE_DIR"; return 0; fi
  printf '%s\n' "$MAIN_ROOT/$(cfg '.paths.pipelineStateDir' '.claude/pipeline-state')"
}

# The record's key:value header reader. This is retro-corpus.sh's variant, not lean-gate.sh's:
# the character class allows `/` because `verdict_record:` carries a repo-relative PATH, and
# lean-gate.sh's narrower class truncates one at the first slash (never triggered there, since
# it re-derives that path from config instead of reading it back — both readers here do read
# it back). Held to that copy by the markers, so the two path-reading readers cannot drift.
# LOCKSTEP-BEGIN lean-record-key
record_key() { # record_key <key> <file>
  [ -f "$2" ] || return 0
  grep -oE "$1:[[:space:]]*[A-Za-z0-9._/-]+" "$2" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"
}
# LOCKSTEP-END lean-record-key

# What counts as a timestamped row, and therefore what the fence is measured between. Held
# byte-identical to retro-corpus.sh, which derives the lean TIMING profile from the same rows
# (#565): a record whose stamp shape moved would silently give one reader a fence and the other
# a span, and both would keep reporting confident numbers about different windows.
# LOCKSTEP-BEGIN lean-progress-ts-re
TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
# LOCKSTEP-END lean-progress-ts-re

# ---------------------------------------------------------------- the build-session SET (#446)
# A verbatim copy of lean-gate.sh's, held by the markers rather than extracted — it is the
# definition the `mark` refusal already uses, and #546's whole point is that this reader must
# not invent a second one. `record_key` above is the wider variant; for `session_id`, whose
# values are UUIDs, the two classes cannot disagree.
# LOCKSTEP-BEGIN lean-session-set
build_session_set() { # one build session id per line, deduped; never empty, never 'unset'
  local hdr
  [ -f "$PROGRESS_FILE" ] || return 0
  # The header via record_key, NOT a second extraction: two readers of one schema that disagreed
  # about what a key looks like would be a silent divergence, not a loud one.
  hdr="$(record_key session_id "$PROGRESS_FILE")"
  {
    [ -n "$hdr" ] && printf '%s\n' "$hdr"
    sed -n 's/^.*| session | \([A-Za-z0-9._-][A-Za-z0-9._-]*\)[[:space:]]*$/\1/p' "$PROGRESS_FILE"
  } | awk '$0 != "" && $0 != "unset" && !seen[$0]++'
  return 0
}
# LOCKSTEP-END lean-session-set

PROGRESS_FILE=""
RUN_ID_VALUE=""
REVIEW_SESSION_INCLUDED=0

if [ -n "$ARG_ISSUE" ]; then
  case "$ARG_ISSUE" in
    # THE KEY SHAPE IS THE TRACKER'S, NOT GITHUB'S — the same class #634 widened in
    # operator-override.sh, missed here. This was `[!0-9]` — numbers only — so under a
    # non-numeric tracker the lean lane's close-out could never publish a figure: the gate
    # passes the run's own ticket key straight through, and every one of those keys was
    # rejected as malformed. The value is a record-path component and a JSON string here
    # (the cost-log row already calls it `ticketKey`), never a number, so nothing downstream
    # wanted digits in the first place.
    # STILL CLOSED, and deliberately: `/` stays out, because ARG_ISSUE is interpolated into
    # the progress record's path, and the empty case stays a usage error.
    ''|*[!0-9A-Za-z._-]*) log "--issue takes an issue key, got '$ARG_ISSUE'"; exit 2 ;;
  esac
  [ -n "$MAIN_ROOT" ] \
    || { log "--issue $ARG_ISSUE: not in a git repo, so the lean progress record is unresolvable — pass --sessions/--start/--end instead"; exit 2; }
  PROGRESS_FILE="${LEAN_PROGRESS_FILE:-$(state_dir)/$ARG_ISSUE-lean-progress.md}"
  [ -r "$PROGRESS_FILE" ] \
    || { log "--issue $ARG_ISSUE: no readable lean progress record at $PROGRESS_FILE — nothing to derive a fence or a session set from"; exit 2; }

  # The fence. First timestamped row to last; the record is append-only, so those are also
  # the earliest and the latest. An empty answer is a refusal, never a rendered default.
  DERIVED_START="$(grep -oE "$TS_RE" "$PROGRESS_FILE" 2>/dev/null | head -n1)"
  DERIVED_END="$(grep -oE "$TS_RE" "$PROGRESS_FILE" 2>/dev/null | tail -n1)"
  { [ -n "$DERIVED_START" ] && [ -n "$DERIVED_END" ]; } \
    || { log "--issue $ARG_ISSUE: $PROGRESS_FILE carries no timestamped row, so its fence is underivable"; exit 2; }

  RUN_ID_VALUE="$(record_key run_id "$PROGRESS_FILE")"
  [ "$RUN_ID_VALUE" = "unset" ] && RUN_ID_VALUE=""

  # The session set, plus the review session when its record exists. `verdict_record:` is a
  # repo-relative path into the BRANCH's worktree, which is why REPO_ROOT and not MAIN_ROOT.
  DERIVED_SESSIONS="$(build_session_set)"
  _vrec="$(record_key verdict_record "$PROGRESS_FILE")"
  if [ -n "$_vrec" ] && [ -n "$REPO_ROOT" ] && [ -r "$REPO_ROOT/$_vrec" ]; then
    _vsid="$(record_key session_id "$REPO_ROOT/$_vrec")"
    if [ -n "$_vsid" ] && [ "$_vsid" != "unset" ] \
       && ! printf '%s\n' "$DERIVED_SESSIONS" | grep -qx -- "$_vsid"; then
      DERIVED_SESSIONS="$DERIVED_SESSIONS
$_vsid"
      REVIEW_SESSION_INCLUDED=1
    fi
  fi

  # Explicit arguments win, INDIVIDUALLY. A caller re-running one bound by hand keeps the
  # other two derived rather than being pushed back to supplying all three.
  [ -n "$ARG_START" ]    || ARG_START="$DERIVED_START"
  [ -n "$ARG_END" ]      || ARG_END="$DERIVED_END"
  if [ -n "$ARG_SESSIONS" ]; then
    # A hand-supplied set is the whole set; the review union described a DERIVED one.
    REVIEW_SESSION_INCLUDED=0
  else
    ARG_SESSIONS="$DERIVED_SESSIONS"
  fi
  log "derived from $PROGRESS_FILE: fence [$ARG_START, $ARG_END], $(printf '%s\n' "$ARG_SESSIONS" | awk 'NF' | wc -l | tr -d ' ') session(s)$([ "$REVIEW_SESSION_INCLUDED" -eq 1 ] && printf ' (review included)')"
elif [ "$CLOSE_OUT" -eq 1 ]; then
  log "--close-out writes a cost-log row keyed on (ticketKey, runId) and so requires --issue <n>"
  exit 2
fi

[ -n "$ARG_SESSIONS" ] || { log "--stateless requires --sessions <id[,id…]> (or --issue <n> to derive it)"; exit 2; }
[ -n "$ARG_START" ] && [ -n "$ARG_END" ] \
  || { log "--stateless requires both --start <iso> and --end <iso> (the time fence), or --issue <n> to derive them"; exit 2; }

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
# LOCKSTEP-BEGIN iso-to-epoch
iso_to_epoch() {
  local e
  e=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null)
  case "$e" in ''|*[!0-9]*) e=$(date -u -d "$1" +%s 2>/dev/null) ;; esac
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$e"
}
# LOCKSTEP-END iso-to-epoch
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
  # The total row's scope and parenthetical. The absence of a per-stage breakdown is not
  # a defect to apologize for — lean has no stages by construction — so the honest
  # label says that instead of implying the run failed to record timestamps.
  #
  # The SCOPE moves with the set (#546). Once the review session is unioned in, the row is no
  # longer one session's spend and must not keep saying so: "Session total (lean run)" over a
  # build+review set is precisely the class of confidently-wrong figure this mode exists to
  # stop, just one field over from the fence.
  local total_note="lean run — no stage windows by design"
  local total_scope="Session total"
  if [ "$REVIEW_SESSION_INCLUDED" -eq 1 ]; then
    total_scope="Run total"
    total_note="build + review — no stage windows by design"
  fi
  jq -r --arg dur "$DURATION_MIN" \
        --arg marker "$COST_BLOCK_MARKER" --arg term "$COST_BLOCK_TERMINATOR" \
        --arg totalNote "$total_note" \
        --arg totalScope "$total_scope" \
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
        $marker,
        "---",
        "",
        "## Pipeline Cost",
        "",
        "| Scope | Tiers | Models | Cost (USD) |",
        "|-------|-------|--------|-----------:|",
        "| " + $totalScope + " (" + $totalNote + ") | " + ($all_tiers | join(", ")) + " | " + ($all_models | join(", ")) + " | " + fmt(.totals.cost_usd) + " |"
      ]
      +
      [
        "",
        $term + ((.totals.cache_hit_rate * 100 | round) | tostring) + "%"
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
# The cost-log row (#546). See THE COST-LOG ROW in the header for why it is back and why
# --close-out is its only trigger. Reached only from here, past every skip(…) exit above,
# which is what makes "no rollup, no row" structural rather than a rule to remember.
# ────────────────────────────────────────────────────────────────────────────
write_cost_log_row() {
  local out="${COST_LOG_FILE:-$(state_dir)/cost-log.jsonl}"
  local dur="${DURATION_MIN:-?}" tmp row prs_json
  prs_json=$(printf '%s' "$ARG_PRS" | tr ',' '\n' | tr ' ' '\n' | awk 'NF' \
    | jq -R -s 'split("\n") | map(select(length > 0))')
  mkdir -p "$(dirname "$out")" 2>/dev/null
  [ -f "$out" ] || : > "$out"

  row=$(jq -n -c --arg issue "$ARG_ISSUE" --arg runId "$RUN_ID_VALUE" --arg dur "$dur" \
    --argjson sids "$SIDS_JSON" --argjson rollup "$ROLLUP" --argjson prs "$prs_json" '
    { at: (now | todate),
      ticketKey: $issue,
      runId: $runId,
      sessionIds: $sids,
      totalUsd: $rollup.totals.cost_usd,
      durationMin: ($dur | tonumber? // null),
      models: ([$rollup.byTier[].models[]] | unique | sort),
      byTier: $rollup.byTier,
      cacheHitRate: $rollup.totals.cache_hit_rate,
      prs: $prs }
  ') || { log "could not render a cost-log row for #$ARG_ISSUE — the log is unchanged"; return 1; }

  # REPLACE on (ticketKey, runId), APPEND otherwise. A log that does not parse as JSONL is
  # carried through unchanged rather than rewritten: losing a corpus to a salvage attempt is
  # strictly worse than carrying one duplicate pair.
  tmp="$out.$$.tmp"
  if ! jq -c --arg k "$ARG_ISSUE" --arg r "$RUN_ID_VALUE" \
        'select((.ticketKey != $k) or ((.runId // "") != $r))' "$out" > "$tmp" 2>/dev/null; then
    log "cost-log at $out does not parse as JSONL — appending without replacing this run's row"
    cp "$out" "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  printf '%s\n' "$row" >> "$tmp"
  mv "$tmp" "$out" || { rm -f "$tmp"; log "could not replace $out"; return 1; }
  log "cost-log row written to $out (ticketKey=$ARG_ISSUE, runId=${RUN_ID_VALUE:-<none>})"
}

if [ "$CLOSE_OUT" -eq 1 ]; then
  write_cost_log_row || true
fi

# ────────────────────────────────────────────────────────────────────────────
# Emit. No PR body is amended — the lean session pastes the block into the PR description
# at step 7 and into its one closing comment at step 9, where it also replaces the earlier
# snapshot in the body (keyed on the marker line below).
# ────────────────────────────────────────────────────────────────────────────
if [ -n "$ARG_OUT" ]; then
  printf '%s\n' "$COST_BLOCK" > "$ARG_OUT" || { log "could not write --out '$ARG_OUT'"; exit 2; }
  log "state-less cost block written to $ARG_OUT"
else
  printf '%s\n' "$COST_BLOCK"
fi
exit 0

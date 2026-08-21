#!/usr/bin/env bash
#
# Self-test for pipeline-cost-block.sh — state-less mode, which since #574 is the
# script's ONLY mode. Pure-local: no Claude CLI, no network, no real `gh`.
#
# WHAT DIED WITH #574 (and where its coverage went):
#   The stateful branch — per-stage bucketing from a staged state file, the
#   cost-log.jsonl writer, the costBlockApplied record, the PR amend and its
#   bot-identity ladder, and resolve_state()'s derivation ladder — was unreachable
#   from the moment #348 deleted the staged lane (no lane wrote the state files it
#   read). The cases that drove those paths died with them. What SURVIVES in the
#   script survives here, re-hosted onto the state-less invocation: the per-run time
#   fence (#224 — now an argument instead of state timestamps), the vendor-neutral
#   tier bucketing (#357), the rotation-aware input set and the four-way skip
#   discrimination (#432 — log-line verdicts now; there is no state file to record
#   costBlockApplied into).
#
# FENCE FIXTURE GEOMETRY (two-runs-shared-session.jsonl, one session.id):
#   window A [10:00,10:30]: $1.00 @ 10:15 (claude-opus-4-7)
#   window B [11:00,11:20]: $0.30 @ 11:08, $0.10 @ 11:11, and $0.05 @ EXACTLY 11:20
#                           (all claude-sonnet-4-6; the boundary point exercises the
#                           inclusive <= bound)
# So: fence A total == $1.00 (B excluded); fence B total == $0.45 (A excluded,
# boundary point KEPT). This is the #224 regression guard: one session.id, two
# windows, neither inhales the other.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/pipeline-cost-block.sh"
FIX="$HERE/../cost-tracking-fixtures"
METRICS="$FIX/two-runs-shared-session.jsonl"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

[[ -f "$METRICS" ]] || { echo "FAIL: metrics fixture missing at $METRICS" >&2; exit 1; }
[[ -f "$SCRIPT" ]]  || { echo "FAIL: script missing at $SCRIPT" >&2; exit 1; }

# jq helpers over a rollup JSON on stdin.
total_of() { jq -r '.totals.cost_usd'; }
# Cost in whole cents for one tier, so assertions never compare IEEE-754 artifacts:
# the cross-vendor fixture's unknown bucket sums to 0.15000000000000002, and its
# total to 0.8000000000000002.
tier_cents() { jq -r --arg t "$1" '(([.byTier[] | select(.tier==$t) | .cost_usd] | add) // 0) * 100 | round'; }

# rollup <metrics-file> <sid> <fence-lo> <fence-hi> — the fenced rollup JSON, via the
# DUMP_ROLLUP hook (prints the rollup and exits before rendering).
rollup() {
  OTEL_METRICS_FILE="$1" COST_BLOCK_DUMP_ROLLUP=1 \
    bash "$SCRIPT" --stateless --sessions "$2" --start "$3" --end "$4" 2>/dev/null
}
# skipline <metrics-file> <sid> <fence-lo> <fence-hi> — stderr of a full run, for the
# skip(<verdict>) discrimination lines. COST_BLOCK_SKIP_FLUSH skips the 5s collector
# flush; every branch under test exits before rendering.
skipline() {
  # shellcheck disable=SC2069 # deliberate: keep STDERR (the skip verdict), discard stdout
  OTEL_METRICS_FILE="$1" COST_BLOCK_SKIP_FLUSH=1 \
    bash "$SCRIPT" --stateless --sessions "$2" --start "$3" --end "$4" 2>&1 >/dev/null
}

SHARED_SID="11111111-2222-4333-8444-555555555555"

echo "=== #574: the stateful invocation is a NAMED usage error, not a silent resolve ==="
# shellcheck disable=SC2069 # deliberate: keep STDERR (the refusal), discard stdout
OUT="$(bash "$SCRIPT" 42 2>&1 >/dev/null)"; RC=$?
[[ "$RC" -eq 2 ]] \
  && ok "(#574) a positional-issue invocation exits 2" \
  || bad "(#574) positional invocation exited $RC, expected 2"
grep -q "retired in #574" <<<"$OUT" \
  && ok "(#574) the refusal names the retirement and the surviving invocation shape" \
  || bad "(#574) expected the retirement pointer in: $OUT"

echo
echo "=== #224: the time fence — one session.id, two windows, neither inhales the other ==="
A_ROLLUP="$(rollup "$METRICS" "$SHARED_SID" 2026-05-25T10:00:00Z 2026-05-25T10:30:00Z)"
if [[ -z "$A_ROLLUP" ]] || ! jq -e . >/dev/null 2>&1 <<<"$A_ROLLUP"; then
  bad "fence A produced no valid rollup JSON"
else
  A_TOTAL="$(total_of <<<"$A_ROLLUP")"
  [[ "$A_TOTAL" == "1.00" || "$A_TOTAL" == "1" ]] \
    && ok "fence A total == \$1.00 (B's \$0.45 excluded by the fence)" \
    || bad "fence A total expected 1.00, got $A_TOTAL"

  # (#357) This fixture's ids are the shipped map's ORACLE, not decoration: window A's
  # whole \$1.00 carries model claude-opus-4-7, so it must land in `reasoning`. Drop opus
  # from the map — or key the map on the dispatch alphabet, which cannot classify a
  # resolved id — and this reads 0 with the cost sitting in `unknown` instead.
  A_REASONING="$(tier_cents reasoning <<<"$A_ROLLUP")"
  [[ "$A_REASONING" == "100" ]] \
    && ok "(#357) fence A's \$1.00 (claude-opus-4-7) tiers to 'reasoning'" \
    || bad "(#357) fence A 'reasoning' expected 100 cents, got $A_REASONING"
fi

B_ROLLUP="$(rollup "$METRICS" "$SHARED_SID" 2026-05-25T11:00:00Z 2026-05-25T11:20:00Z)"
if [[ -z "$B_ROLLUP" ]] || ! jq -e . >/dev/null 2>&1 <<<"$B_ROLLUP"; then
  bad "fence B produced no valid rollup JSON"
else
  B_TOTAL="$(total_of <<<"$B_ROLLUP")"
  [[ "$B_TOTAL" == "0.45" ]] \
    && ok "fence B total == \$0.45 (A's \$1.00 NOT inhaled, and the \$0.05 @ EXACTLY fenceHi is KEPT — inclusive bound)" \
    || bad "fence B total expected 0.45, got $B_TOTAL"

  # (#357) The map's second oracle: every one of window B's three datapoints carries
  # model claude-sonnet-4-6, so the whole \$0.45 must land in `code`.
  B_CODE="$(tier_cents code <<<"$B_ROLLUP")"
  [[ "$B_CODE" == "45" ]] \
    && ok "(#357) fence B's \$0.45 (claude-sonnet-4-6) tiers to 'code'" \
    || bad "(#357) fence B 'code' expected 45 cents, got $B_CODE"
fi

echo
echo "=== AC-8: the state-less contract (build-lean checklist step 7's invocation) ==="
MINI_METRICS="$FIX/single-session-mini.jsonl"
MINI_SESSION="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
SL_OUT="$TMP/stateless-block.md"

OTEL_METRICS_FILE="$MINI_METRICS" COST_BLOCK_SKIP_FLUSH=1 \
  bash "$SCRIPT" --stateless --sessions "$MINI_SESSION" \
    --start "2026-05-01T00:00:00Z" --end "2026-06-01T00:00:00Z" --out "$SL_OUT" >/dev/null 2>&1
SL_RC=$?
[[ "$SL_RC" -eq 0 ]] \
  && ok "(AC-8) state-less mode exits 0 with no state file present" \
  || bad "(AC-8) state-less mode exited $SL_RC, expected 0"

{ [[ -s "$SL_OUT" ]] && grep -q 'Pipeline Cost' "$SL_OUT"; } \
  && ok "(AC-8) --out receives the rendered cost block" \
  || bad "(AC-8) --out did not receive a rendered block"

# The session total must carry the real fixture cost — the same collector query and
# pricing math the stateful path used before its retirement. One instrument.
grep -q '0\.50' "$SL_OUT" 2>/dev/null \
  && ok "(AC-8) state-less totals use the same collector query and pricing math" \
  || bad "(AC-8) expected the fixture's 0.50 session total in the emitted block"

# Session-window totals ONLY: lean has no stage windows, so a per-stage table would be
# a fabrication rather than a degraded view.
{ grep -q 'Session total' "$SL_OUT" 2>/dev/null \
  && ! grep -qE '^\| (Intake|Plan|Implementation|Verify) ' "$SL_OUT" 2>/dev/null; } \
  && ok "(AC-8) emits session-window totals only (no per-stage table)" \
  || bad "(AC-8) state-less block should carry no per-stage rows"

# (#357) The session-total layout carries a TIER LIST, and it runs through the render
# filter. This fixture's four token rows carry no `model`, so an unfiltered list would
# read "reasoning, unknown" — advertising a bucket that cost nothing and names nothing.
# The single \$0.50 cost row is claude-opus-4-7, so the cell is exactly "reasoning",
# which also makes this fixture an oracle for the map's opus entry.
# shellcheck disable=SC2016 # $0.50 is a rendered dollar amount, not a shell expansion
grep -qE '^\| Session total \(.*\) \| reasoning \| claude-opus-4-7 \| \$0\.50 \|$' "$SL_OUT" 2>/dev/null \
  && ok "(#357) the session-total row's tier list is filtered and reads 'reasoning'" \
  || bad "(#357) session-total tier cell should be exactly 'reasoning'"

# Both inputs are REQUIRED, not optional: without a fence, session-only attribution
# inhales every co-resident datapoint from a long-lived interactive session.
OTEL_METRICS_FILE="$MINI_METRICS" \
  bash "$SCRIPT" --stateless --sessions "$MINI_SESSION" >/dev/null 2>&1
[[ $? -eq 2 ]] \
  && ok "(AC-8) --stateless without a time fence is a usage error" \
  || bad "(AC-8) --stateless without --start/--end should exit 2"

OTEL_METRICS_FILE="$MINI_METRICS" \
  bash "$SCRIPT" --stateless --start "2026-05-01T00:00:00Z" --end "2026-06-01T00:00:00Z" >/dev/null 2>&1
[[ $? -eq 2 ]] \
  && ok "(AC-8) --stateless without --sessions is a usage error" \
  || bad "(AC-8) --stateless without --sessions should exit 2"

echo
echo "=== #357: tier bucketing is vendor-neutral ==="
#
# The cross-vendor fixture is the kill criterion the suite lacked entirely: before it,
# `grep -c model` over this file returned 0, so no assertion could fail on vendor
# coupling. Its five cost datapoints sit in one window — three Anthropic families the
# default map covers, one non-Anthropic id it does not, and one datapoint carrying no
# `model` attribute at all. A further zero-cost sonnet datapoint gives the render
# filter its keep case, and the zero-cost model-less token rows its drop case.
XV_METRICS="$FIX/cross-vendor.jsonl"
XV_SID="33333333-4444-4555-8666-777777777777"
XV_LO="2026-06-10T09:00:00Z"
XV_HI="2026-06-10T09:40:00Z"

XV_ROLLUP="$(rollup "$XV_METRICS" "$XV_SID" "$XV_LO" "$XV_HI")"
if [[ -z "$XV_ROLLUP" ]] || ! jq -e . >/dev/null 2>&1 <<<"$XV_ROLLUP"; then
  bad "(#357) cross-vendor fixture produced no valid rollup JSON"
else
  # The split, and its ORDER: four tier rows in the order the script declares — so a
  # row set that permutes between runs fails here rather than churning a PR body.
  XV_TIERS="$(jq -r '[.byTier[].tier] | join(",")' <<<"$XV_ROLLUP")"
  [[ "$XV_TIERS" == "reasoning,code,emit,unknown" ]] \
    && ok "(#357) the rollup splits into 4 deterministically ordered tier rows" \
    || bad "(#357) tiers expected 'reasoning,code,emit,unknown', got '$XV_TIERS'"

  # Each Anthropic family the default map covers, classified. Together with fence A's
  # opus and fence B's sonnet above, every entry of the shipped map has an oracle.
  XV_R="$(tier_cents reasoning <<<"$XV_ROLLUP")"
  XV_C="$(tier_cents code <<<"$XV_ROLLUP")"
  XV_E="$(tier_cents emit <<<"$XV_ROLLUP")"
  [[ "$XV_R" == "40" && "$XV_C" == "20" && "$XV_E" == "5" ]] \
    && ok "(#357) opus/sonnet/haiku ids map to reasoning/code/emit (40/20/5 cents)" \
    || bad "(#357) expected 40/20/5 cents for reasoning/code/emit, got $XV_R/$XV_C/$XV_E"

  # The `unknown` fallback carries BOTH kinds of unclassifiable datapoint, and the two
  # amounts are deliberately distinct so one assertion separates all three failures:
  # 15 = both present, 10 = the attribute-less \$0.05 was dropped, 5 = the unmatched
  # vendor id was mis-tiered into a real tier.
  XV_U="$(tier_cents unknown <<<"$XV_ROLLUP")"
  [[ "$XV_U" == "15" ]] \
    && ok "(#357) unmatched vendor id AND attribute-less datapoint both bucket to 'unknown'" \
    || bad "(#357) 'unknown' expected 15 cents (10 unmatched + 5 attribute-less), got $XV_U"

  # Totality, stated directly: the per-tier rows must account for every dollar the
  # run's total claims. A partial tier key leaves cost in the total and out of the table.
  XV_SUM="$(jq -r '(([.byTier[].cost_usd] | add) // 0) * 100 | round' <<<"$XV_ROLLUP")"
  XV_TOT="$(jq -r '.totals.cost_usd * 100 | round' <<<"$XV_ROLLUP")"
  [[ "$XV_SUM" == "80" && "$XV_TOT" == "80" ]] \
    && ok "(#357) per-tier rows sum to the run total (80 cents) — no cost escapes the key" \
    || bad "(#357) byTier sums to $XV_SUM cents, totals says $XV_TOT, expected 80/80"

  # `models` survives as the SECONDARY field — the tier is the bucket key, not a
  # replacement for the id. The attribute-less datapoint contributes nothing here,
  # which is exactly why `unknown` shows only the unmatched vendor id.
  XV_UNKNOWN_MODELS="$(jq -r '[.byTier[] | select(.tier=="unknown") | .models[]] | join(",")' <<<"$XV_ROLLUP")"
  [[ "$XV_UNKNOWN_MODELS" == "mistral-large-2" ]] \
    && ok "(#357) the unknown tier row keeps its own 'models' set (the unmatched id only)" \
    || bad "(#357) unknown-tier models expected 'mistral-large-2', got '$XV_UNKNOWN_MODELS'"
fi

# Full path, no dump hook: renders the block to --out. The render filter and the
# single-row layout are asserted on the artifact a reader actually sees.
XV_OUT="$TMP/cross-vendor-block.md"
OTEL_METRICS_FILE="$XV_METRICS" COST_BLOCK_SKIP_FLUSH=1 \
  bash "$SCRIPT" --stateless --sessions "$XV_SID" --start "$XV_LO" --end "$XV_HI" \
    --out "$XV_OUT" >/dev/null 2>&1

if [[ ! -s "$XV_OUT" ]]; then
  bad "(#357) no rendered block was written to --out"
else
  # shellcheck disable=SC2016 # $0.80 is a rendered dollar amount, not a shell expansion
  grep -qE '^\| Session total \(.*\) \| reasoning, code, emit, unknown \| claude-haiku-4-5-20251001, claude-opus-4-7, claude-sonnet-4-6, mistral-large-2 \| \$0\.80 \|$' "$XV_OUT" \
    && ok "(#357) the session-total row carries the ordered tier list, the model set, and the full \$0.80" \
    || bad "(#357) expected the 4-tier, 4-model session-total row; got: $(grep 'Session total' "$XV_OUT")"
fi

echo
echo "=== #357/D-8: --help prints the whole header and none of the code ==="
# The range in the -h branch is hand-maintained and was already off by one once. The
# oracle is DERIVED from the file — where the comment block actually ends — so this
# assertion cannot rot the next time the header grows.
HELP_OUT="$(bash "$SCRIPT" --help 2>/dev/null)"
HDR_END="$(awk 'NR==1{next} /^#/{last=NR; next} {print last; exit}' "$SCRIPT")"
HELP_FIRST="$(printf '%s\n' "$HELP_OUT" | head -n 1)"
HELP_LAST="$(printf '%s\n' "$HELP_OUT" | tail -n 1)"
FIRST_CODE="$(awk 'NR==1{next} /^#/{next} NF{print; exit}' "$SCRIPT")"

[[ -n "$HDR_END" && "$HELP_FIRST" == "$(sed -n '2p' "$SCRIPT")" ]] \
  && ok "(D-8) --help starts at the header's first line (line 2, past the shebang)" \
  || bad "(D-8) --help first line '$HELP_FIRST' is not the script's line 2"

[[ -n "$HDR_END" && "$HELP_LAST" == "$(sed -n "${HDR_END}p" "$SCRIPT")" ]] \
  && ok "(D-8) --help prints through the header's last line (line $HDR_END)" \
  || bad "(D-8) --help ends at '$HELP_LAST', expected the header's last line ($HDR_END)"

if [[ -n "$FIRST_CODE" ]] && grep -qF -- "$FIRST_CODE" <<<"$HELP_OUT"; then
  bad "(D-8) --help leaked the first line of code ('$FIRST_CODE')"
else
  ok "(D-8) --help stops before the first line of code"
fi

echo
echo "=== #432: rotated backups, and the four-way skip discrimination ==="
# Two bugs shared one symptom — an empty cost block — and one message that named neither.
#
#   1. METRICS_FILE resolved to the live file ONLY, while the shipped exporter rotates
#      at 50 MB to `metrics-<ts>-size.jsonl`. Any run whose window predated the newest
#      rotation was silently unattributable EVEN WITH TELEMETRY ON.
#   2. The skip branch keyed on TOTAL_COST being zero and blamed "the collector … or
#      session ids drifted" — the two things that are almost never the cause.
#
# The verdicts are LOG LINES now (`skip(<verdict>): …`): the costBlockApplied record
# they used to land in died with the state file (#574). The discrimination itself is
# unchanged, and each case asserts its token on stderr.
#
# WHY THE MTIME/FILENAME DISAGREEMENT BELOW IS DELIBERATE: the exporter writes those
# filenames with `localtime: true`, so the timestamp in the name is LOCAL while the
# fence is ISO-8601 `Z`. An implementation that selects on the filename reads correct
# in UTC and wrong everywhere else. Each rotation fixture is therefore named to suggest
# the OPPOSITE of what its mtime says, so a filename-parsing implementation fails these
# cases in every timezone, including UTC.
# `-u` matters in iso2ep for the same reason it does in the script: without it BSD
# `date -j -f` reads a `Z` timestamp as local time. BSD and GNU disagree on both forms,
# and NEITHER wrong form reliably fails — validate the shape of the answer instead of
# trusting the exit status.
digits_or_empty() { case "$1" in ''|*[!0-9]*) echo "" ;; *) echo "$1" ;; esac; }
iso2ep() {
  local e
  e="$(digits_or_empty "$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null)")"
  [ -n "$e" ] || e="$(digits_or_empty "$(date -u -d "$1" +%s 2>/dev/null)")"
  echo "$e"
}
set_mtime() { # set_mtime <file> <iso>
  local ep stamp
  ep="$(iso2ep "$2")"
  [ -n "$ep" ] || { bad "set_mtime: could not convert '$2' to an epoch on this platform"; return 1; }
  stamp="$(date -r "$ep" +%Y%m%d%H%M.%S 2>/dev/null)"
  case "$stamp" in ''|*[!0-9.]*) stamp="$(date -d "@$ep" +%Y%m%d%H%M.%S 2>/dev/null)" ;; esac
  [ -n "$stamp" ] || { bad "set_mtime: could not render a touch stamp for '$2'"; return 1; }
  touch -t "$stamp" "$1"
}
# mk_metrics <file> <metric-name> <sid:iso:value>…
mk_metrics() {
  local out="$1" metric="$2"; shift 2
  local dps="" spec sid rest iso val
  for spec in "$@"; do
    sid="${spec%%:*}"; rest="${spec#*:}"
    iso="${rest%:*}"; val="${rest##*:}"
    dps="$dps$(jq -nc --arg sid "$sid" --arg t "$(iso2ep "$iso")000000000" --argjson v "$val" \
      '{attributes:[{key:"session.id",value:{stringValue:$sid}},
                    {key:"model",value:{stringValue:"claude-sonnet-4-6"}},
                    {key:"type",value:{stringValue:"input"}}],
        timeUnixNano:$t, asDouble:$v}'),"
  done
  printf '{"resourceMetrics":[{"resource":{"attributes":[]},"scopeMetrics":[{"metrics":[{"name":"%s","sum":{"dataPoints":[%s]}}]}]}]}\n' \
    "$metric" "${dps%,}" > "$out"
}

SID_A="aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"   # this run
SID_B="bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"   # a concurrent session in another repo
F_LO="2026-05-01T10:00:00Z"
F_HI="2026-05-01T11:00:00Z"

# --- rotation: a backup whose MTIME covers the fence is read ------------------
ROT="$TMP/rot-covered"; mkdir -p "$ROT/metrics"
mk_metrics "$ROT/metrics/metrics.jsonl" claude_code.cost.usage "$SID_A:2026-05-01T10:50:00Z:0.20"
# Filename says 09:00 (before the fence); mtime says 10:20 (inside it). mtime must win.
mk_metrics "$ROT/metrics/metrics-2026-05-01T09-00-00.000-size.jsonl" claude_code.cost.usage \
  "$SID_A:2026-05-01T10:10:00Z:1.00"
set_mtime "$ROT/metrics/metrics-2026-05-01T09-00-00.000-size.jsonl" "2026-05-01T10:20:00Z"
T="$(rollup "$ROT/metrics/metrics.jsonl" "$SID_A" "$F_LO" "$F_HI" | jq -r '.totals.cost_usd')"
[[ "$T" == "1.2" || "$T" == "1.20" ]] \
  && ok "(#432) a rotated backup whose mtime covers the fence is read (total $T = live 0.20 + backup 1.00)" \
  || bad "(#432) expected 1.2 with the covering backup read, got '$T'"

# --- rotation: a backup whose MTIME predates the fence is NOT read ------------
# (The third rotation case — "fence disabled reads the live file alone" — died with the
# stateful branch: the fence is a REQUIRED argument now, so there is no disabled-fence
# invocation to drive. The empty-fence guard inside compute_bucket_rollup keeps its
# meaning documented in the script.)
ROT2="$TMP/rot-stale"; mkdir -p "$ROT2/metrics"
mk_metrics "$ROT2/metrics/metrics.jsonl" claude_code.cost.usage "$SID_A:2026-05-01T10:50:00Z:0.20"
# The mirror image: filename says 10:10 (inside the fence), mtime says 09:00 (before
# it). A backup stops being written at its mtime, so it cannot hold an in-fence row —
# skip it, and skip paying to slurp 50 MB for nothing.
mk_metrics "$ROT2/metrics/metrics-2026-05-01T10-10-00.000-size.jsonl" claude_code.cost.usage \
  "$SID_A:2026-05-01T10:10:00Z:1.00"
set_mtime "$ROT2/metrics/metrics-2026-05-01T10-10-00.000-size.jsonl" "2026-05-01T09:00:00Z"
T="$(rollup "$ROT2/metrics/metrics.jsonl" "$SID_A" "$F_LO" "$F_HI" | jq -r '.totals.cost_usd')"
[[ "$T" == "0.2" || "$T" == "0.20" ]] \
  && ok "(#432) a backup whose mtime predates the fence is skipped (total $T, the live file alone)" \
  || bad "(#432) expected 0.2 with the stale backup skipped, got '$T'"

# --- discrimination: nothing in the fence, from anyone -----------------------
DSC="$TMP/disc"; mkdir -p "$DSC/m1" "$DSC/m2" "$DSC/m3" "$DSC/m4"
mk_metrics "$DSC/m1/metrics.jsonl" claude_code.cost.usage "$SID_B:2026-05-01T09:00:00Z:1.00"
R="$(skipline "$DSC/m1/metrics.jsonl" "$SID_A" "$F_LO" "$F_HI")"
grep -q 'skip(telemetry-off)' <<<"$R" \
  && ok "(#432) no in-fence rows from ANY session logs skip(telemetry-off)" \
  || bad "(#432) expected skip(telemetry-off), got: $R"

# --- discrimination: the fence is populated, but not by us -------------------
# One row apart from the case above: the 09:00 row keeps the oldest scanned datapoint
# BEFORE the fence, so coverage is not in doubt and the honest verdict is "this session
# exported nothing".
mk_metrics "$DSC/m2/metrics.jsonl" claude_code.cost.usage \
  "$SID_B:2026-05-01T09:00:00Z:1.00" "$SID_B:2026-05-01T10:30:00Z:2.00"
R="$(skipline "$DSC/m2/metrics.jsonl" "$SID_A" "$F_LO" "$F_HI")"
grep -q 'skip(session-not-exporting)' <<<"$R" \
  && ok "(#432) in-fence rows from other sessions only logs skip(session-not-exporting)" \
  || bad "(#432) expected skip(session-not-exporting), got: $R"

# --- discrimination: the coverage of the window itself is gone --------------
# Same in-fence foreign row as above, minus the 09:00 one — now the oldest datapoint on
# disk is NEWER than the run start, so the file that covered the run is gone and no
# other verdict can be trusted. This also pins the PRECEDENCE: in-fence foreign rows
# exist here too, and rotated-out must still win over the not-exporting verdict.
mk_metrics "$DSC/m3/metrics.jsonl" claude_code.cost.usage "$SID_B:2026-05-01T10:30:00Z:2.00"
R="$(skipline "$DSC/m3/metrics.jsonl" "$SID_A" "$F_LO" "$F_HI")"
grep -q 'skip(rotated-out)' <<<"$R" \
  && ok "(#432) retained metrics starting after the fence logs skip(rotated-out), ahead of the not-exporting verdict" \
  || bad "(#432) expected skip(rotated-out), got: $R"

# --- discrimination: our rows are there, they just carry no cost ------------
# The narrowed meaning of the value that used to absorb all four states: token rows for
# THIS session, inside the fence, and not one claude_code.cost.usage among them.
mk_metrics "$DSC/m4/metrics.jsonl" claude_code.token.usage \
  "$SID_B:2026-05-01T09:00:00Z:10" "$SID_A:2026-05-01T10:30:00Z:500"
R="$(skipline "$DSC/m4/metrics.jsonl" "$SID_A" "$F_LO" "$F_HI")"
grep -q 'skip(zero-datapoints)' <<<"$R" \
  && ok "(#432) in-fence rows for this session with no cost datapoint logs skip(zero-datapoints)" \
  || bad "(#432) expected skip(zero-datapoints), got: $R"

echo
echo "=== #546: the fence and the session set are DERIVED, not improvised ==="
#
# The defect this section guards is not "the block was empty" — it is "the block was
# well-formed and wrong". A run whose close-out session guessed the fence published 43 min
# and one session for a 98-minute, three-session run, and every assertion anyone could have
# written about the RENDER would have passed. So each case below pins the derived answer
# against a DIFFERENT, plausible hand-supplied one over the same fixture: a mode that quietly
# ignored the record and kept taking the caller's word would render the wrong number here and
# fail, which greping the block for "Pipeline Cost" never could.
#
# FIXTURE GEOMETRY ($RT, a throwaway git repo so the REAL resolution ladder runs — main-checkout
# anchor, config defaults, state dir, and the branch-relative verdict-record path — instead of a
# stub that would agree with anything):
#   progress record 900   fence rows 10:00 → 11:30, header session S1, `| session |` row S2
#   verdict record        header session S3 (the review's)
#   metrics               S1 @ 09:00 $9.00  ← BEFORE the fence: the decoy an unfenced or
#                                             wrongly-opened window inhales
#                         S1 @ 10:10 $1.00 (opus)
#                         S2 @ 11:10 $2.00 (sonnet)
#                         S3 @ 11:20 $0.50 (haiku)
# So: derived build-only = $3.00. Derived with review = $3.50. The published-figure bug's own
# shape (fence [10:00,10:30], sessions S1) = $1.00. Three distinguishable totals, one fixture.

S1="c0510001-1111-4111-8111-aaaaaaaaaaaa"
S2="c0510002-2222-4222-8222-bbbbbbbbbbbb"
S3="c0510003-3333-4333-8333-cccccccccccc"

# mk_cost_metrics <file> <sid:iso:value:model>… — like mk_metrics above, but the model id is
# per-datapoint (the tier split is not what these cases are about; the attribution is).
mk_cost_metrics() {
  local out="$1"; shift
  local dps="" spec sid rest iso val model
  for spec in "$@"; do
    sid="${spec%%:*}"; rest="${spec#*:}"
    model="${rest##*:}"; rest="${rest%:*}"
    val="${rest##*:}"; iso="${rest%:*}"
    dps="$dps$(jq -nc --arg sid "$sid" --arg t "$(iso2ep "$iso")000000000" \
      --argjson v "$val" --arg m "$model" \
      '{attributes:[{key:"session.id",value:{stringValue:$sid}},
                    {key:"model",value:{stringValue:$m}}],
        timeUnixNano:$t, asDouble:$v}'),"
  done
  printf '{"resourceMetrics":[{"resource":{"attributes":[]},"scopeMetrics":[{"metrics":[{"name":"claude_code.cost.usage","sum":{"dataPoints":[%s]}}]}]}]}\n' \
    "${dps%,}" > "$out"
}

RT="$TMP/lean-repo"
mkdir -p "$RT/.claude/pipeline-state" "$RT/docs/plans" "$RT/metrics"
git -C "$RT" init -q 2>/dev/null
PROG="$RT/.claude/pipeline-state/900-lean-progress.md"
VREC="$RT/docs/plans/acme-900-lean-verdict.md"
cat > "$PROG" <<PROGEOF
# lean run — issue 900

run_id: run-900-alpha
session_id: $S1
issue: 900
branch: claude/acme-900
spec: docs/plans/acme-900-lean.md
verdict_record: docs/plans/acme-900-lean-verdict.md
model: opus

2026-07-02T10:00:00Z | entry | ledger=/dev/null | lines=3 | telemetry=on | session=$S1
2026-07-02T10:20:00Z | milestone-1 | satisfied
2026-07-02T11:00:00Z | session | $S2
2026-07-02T11:30:00Z | milestone-3 | concluded | rc=0
PROGEOF

MET="$RT/metrics/metrics.jsonl"
mk_cost_metrics "$MET" \
  "$S1:2026-07-02T09:00:00Z:9.00:claude-opus-4-7" \
  "$S1:2026-07-02T10:10:00Z:1.00:claude-opus-4-7" \
  "$S2:2026-07-02T11:10:00Z:2.00:claude-sonnet-4-6" \
  "$S3:2026-07-02T11:20:00Z:0.50:claude-haiku-4-5-20251001"

# issue_block <out-file> <extra args…> — the full render path, run from inside $RT so the
# script resolves the record the way a lane session does.
issue_block() {
  local out="$1"; shift
  ( cd "$RT" && OTEL_METRICS_FILE="$MET" COST_BLOCK_SKIP_FLUSH=1 \
      bash "$SCRIPT" --stateless --issue 900 --out "$out" "$@" ) >/dev/null 2>&1
}
block_total() { grep -oE '\$[0-9]+\.[0-9]{2} \|$' "$1" | tr -d '$ |'; }
# The same invocation, keeping STDERR instead of the render: the derivation summary is the
# only place the resolution ladder and the review union are observable from outside.
issue_stderr() { # issue_stderr <issue> [extra args…]
  local n="$1"; shift
  # shellcheck disable=SC2069 # deliberate: keep STDERR (the summary), discard stdout
  ( cd "$RT" && OTEL_METRICS_FILE="$MET" COST_BLOCK_SKIP_FLUSH=1 \
      bash "$SCRIPT" --stateless --issue "$n" --out /dev/null "$@" 2>&1 >/dev/null )
}

# --- AC-1/AC-2: the derived fence and session set ----------------------------
D_OUT="$TMP/derived.md"
issue_block "$D_OUT"
[[ "$(block_total "$D_OUT")" == "3.00" ]] \
  && ok "(AC-1/AC-2) --issue derives fence [10:00,11:30] and sessions {S1,S2}: \$3.00" \
  || bad "(AC-1/AC-2) derived total expected 3.00, got '$(block_total "$D_OUT")' — the 09:00 decoy or a session was mis-attributed"

# The published-figure bug, reproduced by hand over the same fixture. It is the CONTRAST that
# makes the case above an assertion about derivation rather than about arithmetic.
W_OUT="$TMP/improvised.md"
OTEL_METRICS_FILE="$MET" COST_BLOCK_SKIP_FLUSH=1 \
  bash "$SCRIPT" --stateless --sessions "$S1" \
    --start 2026-07-02T10:00:00Z --end 2026-07-02T10:30:00Z --out "$W_OUT" >/dev/null 2>&1
[[ "$(block_total "$W_OUT")" == "1.00" ]] \
  && ok "(AC-1) a hand-supplied fence+set over the same fixture renders a DIFFERENT, well-formed \$1.00" \
  || bad "(AC-1) the improvised-fence contrast expected 1.00, got '$(block_total "$W_OUT")'"

grep -q 'Sessions: 2' "$D_OUT" \
  && ok "(AC-2) the derived block reports 2 sessions, not the header's one" \
  || bad "(AC-2) expected 'Sessions: 2' in the derived block"

# --- AC-3/AC-4: the review session, and the title that must move with it -----
grep -qE '^\| Session total \(lean run' "$D_OUT" \
  && ok "(AC-4) with no verdict record the row keeps the build-only title" \
  || bad "(AC-4) pre-review block should read 'Session total (lean run …)'"

# The derivation summary's `(review included)` suffix is the ONLY operator-visible signal that
# the union fired, and AC-3 makes the degrade deliberately silent: a close-out accidentally run
# from the main checkout — where the branch-committed verdict record does not exist — renders a
# build-only figure that is well-formed and wrong, which is this ticket's own defect class. The
# suffix is what tells the two apart, so it is asserted in BOTH directions rather than read.
PRE_ERR="$(issue_stderr 900)"
{ grep -q '2 session(s)' <<<"$PRE_ERR" && ! grep -q 'review included' <<<"$PRE_ERR"; } \
  && ok "(AC-3) with no verdict record the summary reports 2 sessions and claims no review" \
  || bad "(AC-3) pre-review summary should be '2 session(s)' with no suffix, got: $PRE_ERR"

cat > "$VREC" <<VRECEOF
# lean verdict — issue 900

run_id: run-900-alpha
session_id: $S3
verdict=approve
pr: 901
VRECEOF
R_OUT="$TMP/with-review.md"
issue_block "$R_OUT"
[[ "$(block_total "$R_OUT")" == "3.50" ]] \
  && ok "(AC-3) the verdict record's session is unioned in: \$3.50" \
  || bad "(AC-3) with-review total expected 3.50, got '$(block_total "$R_OUT")'"

grep -qE '^\| Run total \(build \+ review' "$R_OUT" \
  && ok "(AC-4) a set that counts review is titled 'Run total (build + review …)'" \
  || bad "(AC-4) expected the retitled row; got: $(grep 'total (' "$R_OUT")"

grep -q 'Sessions: 3' "$R_OUT" \
  && ok "(AC-3) the review session is counted, not merely priced" \
  || bad "(AC-3) expected 'Sessions: 3' once the verdict record exists"

POST_ERR="$(issue_stderr 900)"
grep -q '3 session(s) (review included)' <<<"$POST_ERR" \
  && ok "(AC-3) the summary SAYS the union fired — the silent degrade is distinguishable" \
  || bad "(AC-3) expected '3 session(s) (review included)', got: $POST_ERR"

# --- AC-5: explicit arguments override, INDIVIDUALLY -------------------------
O_OUT="$TMP/override-start.md"
issue_block "$O_OUT" --start 2026-07-02T11:00:00Z
[[ "$(block_total "$O_OUT")" == "2.50" ]] \
  && ok "(AC-5) --start overrides its derived half while --end and the set stay derived: \$2.50" \
  || bad "(AC-5) --start override expected 2.50, got '$(block_total "$O_OUT")'"

OS_OUT="$TMP/override-sessions.md"
issue_block "$OS_OUT" --sessions "$S1"
[[ "$(block_total "$OS_OUT")" == "1.00" ]] \
  && ok "(AC-5) --sessions overrides the derived set while the fence stays derived: \$1.00" \
  || bad "(AC-5) --sessions override expected 1.00, got '$(block_total "$OS_OUT")'"

grep -qE '^\| Session total \(lean run' "$OS_OUT" \
  && ok "(AC-4/AC-5) a hand-supplied set drops the review title with it" \
  || bad "(AC-4/AC-5) an overridden set must not keep claiming build + review"

# --- AC-6: an underivable fence is a refusal, not a plausible default --------
# shellcheck disable=SC2069 # deliberate: keep STDERR (the refusal), discard stdout
MISS_OUT="$( cd "$RT" && OTEL_METRICS_FILE="$MET" COST_BLOCK_SKIP_FLUSH=1 \
  bash "$SCRIPT" --stateless --issue 902 2>&1 >/dev/null )"; MISS_RC=$?
{ [[ "$MISS_RC" -eq 2 ]] && grep -q '902-lean-progress.md' <<<"$MISS_OUT"; } \
  && ok "(AC-6) an absent progress record exits 2 naming the resolved path" \
  || bad "(AC-6) absent record: rc=$MISS_RC, stderr: $MISS_OUT"

printf '# lean run — issue 903\n\nrun_id: run-903\nsession_id: %s\n' "$S1" \
  > "$RT/.claude/pipeline-state/903-lean-progress.md"
# shellcheck disable=SC2069 # deliberate: keep STDERR (the refusal), discard stdout
NOTS_OUT="$( cd "$RT" && OTEL_METRICS_FILE="$MET" COST_BLOCK_SKIP_FLUSH=1 \
  bash "$SCRIPT" --stateless --issue 903 2>&1 >/dev/null )"; NOTS_RC=$?
{ [[ "$NOTS_RC" -eq 2 ]] && grep -q 'underivable' <<<"$NOTS_OUT"; } \
  && ok "(AC-6) a record with no timestamped row exits 2 rather than rendering a default" \
  || bad "(AC-6) stampless record: rc=$NOTS_RC, stderr: $NOTS_OUT"

# --- AC-6: WHICH record --issue reads — the config ladder, driven -------------
# Every fixture above lands on the built-in `.claude/pipeline-state` default, so the whole
# CONFIG → cfg() → state_dir() ladder — the code that decides which record a run derives from —
# would answer identically if it were deleted. These two repos are the only inputs that
# separate it from its default. `SECOND_SHIFT_CONFIG` is unset deliberately: the ladder under
# test is the one an unconfigured lane session actually takes.
mk_lean_repo() { # mk_lean_repo <root> <state-subdir> <issue> — a throwaway repo + record
  mkdir -p "$1/$2" "$1/.claude"
  git -C "$1" init -q 2>/dev/null
  printf '# lean run — issue %s\n\nrun_id: run-%s\nsession_id: %s\n\n%s | entry | telemetry=on\n%s | milestone-3 | concluded | rc=0\n' \
    "$3" "$3" "$S1" "2026-07-02T10:00:00Z" "2026-07-02T11:30:00Z" > "$1/$2/$3-lean-progress.md"
}
issue_stderr_at() { # issue_stderr_at <root> <issue> — the summary, from inside <root>
  # shellcheck disable=SC2069 # deliberate: keep STDERR (the summary), discard stdout
  ( cd "$1" && env -u SECOND_SHIFT_CONFIG OTEL_METRICS_FILE="$MET" COST_BLOCK_SKIP_FLUSH=1 \
      bash "$SCRIPT" --stateless --issue "$2" --out /dev/null 2>&1 >/dev/null )
}

# A config that MOVES the state dir. Ignore it — read the default dir instead — and the record
# is not there at all, so the run refuses rather than deriving a fence from the wrong run.
RT2="$TMP/lean-repo-cfgdir"
mk_lean_repo "$RT2" "custom-state" 910
printf '{"configVersion":2,"paths":{"pipelineStateDir":"custom-state"}}\n' \
  > "$RT2/.claude/second-shift.config.json"
CFG_ERR="$(issue_stderr_at "$RT2" 910)"; CFG_RC=$?
{ [[ "$CFG_RC" -eq 0 ]] && grep -q "custom-state/910-lean-progress.md" <<<"$CFG_ERR"; } \
  && ok "(AC-6) a configured pipelineStateDir is where --issue looks for the record" \
  || bad "(AC-6) configured state dir: rc=$CFG_RC, stderr: $CFG_ERR"

# A config that EXISTS but omits the key. `jq -r` yields the literal string "null" there, which
# is the only input on which cfg()'s two guards disagree: keep the "null" and the run resolves a
# state dir literally named `null`. So this repo, not the config-less ones above, is what makes
# the `!= "null"` half load-bearing.
RT3="$TMP/lean-repo-cfgnull"
mk_lean_repo "$RT3" ".claude/pipeline-state" 920
printf '{"configVersion":2,"tracker":{"type":"github"}}\n' > "$RT3/.claude/second-shift.config.json"
NUL_ERR="$(issue_stderr_at "$RT3" 920)"; NUL_RC=$?
{ [[ "$NUL_RC" -eq 0 ]] && grep -q ".claude/pipeline-state/920-lean-progress.md" <<<"$NUL_ERR"; } \
  && ok "(AC-6) a config missing the key falls back to the default dir, not to a dir named 'null'" \
  || bad "(AC-6) absent config key: rc=$NUL_RC, stderr: $NUL_ERR"

# --- the key shape is the tracker's, not github's ----------------------------
# THE REGRESSION GUARD. Every case above passes a github issue NUMBER — the one shape a
# non-numeric tracker never has — which is how a guard those consumers could not get past
# stayed green for this tool's whole life. #634 widened the same class in operator-override.sh
# and did not reach here, so the lean lane's close-out still died on a jira-shaped key: the gate
# hands it the run's own ticket key and the tool called it malformed. On the old guard this
# answers rc=2 with "takes an issue number"; the record is never even looked for.
RT4="$TMP/lean-repo-jira-key"
mk_lean_repo "$RT4" ".claude/pipeline-state" PROJ-123
KEY_ERR="$(issue_stderr_at "$RT4" PROJ-123)"; KEY_RC=$?
{ [[ "$KEY_RC" -eq 0 ]] && grep -q ".claude/pipeline-state/PROJ-123-lean-progress.md" <<<"$KEY_ERR"; } \
  && ok "(#634-class) a non-numeric tracker key reaches its record instead of being refused as malformed" \
  || bad "(#634-class) jira-shaped key: rc=$KEY_RC, stderr: $KEY_ERR"

# The two constraints the widened class still holds. A traversal-shaped value stays out
# because the key is interpolated into the record's path, and empty stays a usage error.
TRAV_ERR="$(issue_stderr_at "$RT4" ../etc/passwd)"; TRAV_RC=$?
{ [[ "$TRAV_RC" -eq 2 ]] && grep -q "takes an issue key" <<<"$TRAV_ERR"; } \
  && ok "(#634-class) a traversal-shaped key is still refused by the widened guard" \
  || bad "(#634-class) traversal key: rc=$TRAV_RC, stderr: $TRAV_ERR"

echo
echo "=== #546: the cost-log row is back, and only the close-out writes it ==="
CL="$TMP/cost-log.jsonl"

# --- AC-7: no flag, no row --------------------------------------------------
COST_LOG_FILE="$CL" issue_block "$TMP/norow.md"
[[ ! -s "$CL" ]] \
  && ok "(AC-7) the step-7 snapshot writes no cost-log row" \
  || bad "(AC-7) a row was written without --close-out: $(cat "$CL")"

# --- AC-8: the row's key set is cross-era readable --------------------------
COST_LOG_FILE="$CL" issue_block "$TMP/row1.md" --close-out --prs "https://x/pull/901"
ROW_KEYS="$(jq -r 'keys | join(",")' < "$CL" 2>/dev/null | tail -n1)"
[[ "$ROW_KEYS" == "at,byTier,cacheHitRate,durationMin,models,prs,runId,sessionIds,ticketKey,totalUsd" ]] \
  && ok "(AC-8) the row carries every cross-era key plus runId and byTier" \
  || bad "(AC-8) unexpected row keys: '$ROW_KEYS'"

# byLabel's ABSENCE is the era discriminator — no marker field was added, so a reader that
# cannot tell the eras apart is a reader this assertion is protecting.
{ jq -e 'has("byLabel") | not' < "$CL" >/dev/null 2>&1 \
  && [[ "$(jq -r '.byTier | length' < "$CL")" -ge 1 ]]; } \
  && ok "(AC-8) byTier is present and byLabel is absent — the era split needs no marker field" \
  || bad "(AC-8) the row must carry byTier and no byLabel"

[[ "$(jq -r '.totalUsd' < "$CL")" == "3.5" && "$(jq -r '.sessionIds | length' < "$CL")" == "3" ]] \
  && ok "(AC-8) the row records the same derived total and session set the block renders" \
  || bad "(AC-8) row totalUsd/sessionIds disagree with the rendered block"

# --- AC-11: --prs, present and absent ---------------------------------------
[[ "$(jq -r '.prs | join(",")' < "$CL")" == "https://x/pull/901" ]] \
  && ok "(AC-11) --prs lands on the row" \
  || bad "(AC-11) prs expected the supplied url, got '$(jq -r '.prs|join(",")' < "$CL")'"

# --- AC-9: REPLACE on (ticketKey, runId), APPEND on a new run id ------------
COST_LOG_FILE="$CL" issue_block "$TMP/row2.md" --close-out
[[ "$(wc -l < "$CL" | tr -d ' ')" == "1" ]] \
  && ok "(AC-9) a re-entered close-out REPLACES its own row (still 1 row)" \
  || bad "(AC-9) re-entry should replace, log has $(wc -l < "$CL" | tr -d ' ') rows"

[[ "$(jq -r '.prs | length' < "$CL")" == "0" ]] \
  && ok "(AC-9/AC-11) the replacement is the new row, not a merge of the old one" \
  || bad "(AC-9) the replaced row kept the first invocation's prs"

sed -i.bak 's/^run_id: run-900-alpha$/run_id: run-900-beta/' "$PROG" && rm -f "$PROG.bak"
COST_LOG_FILE="$CL" issue_block "$TMP/row3.md" --close-out
{ [[ "$(wc -l < "$CL" | tr -d ' ')" == "2" ]] \
  && [[ "$(jq -rs '[.[].runId] | join(",")' < "$CL")" == "run-900-alpha,run-900-beta" ]]; } \
  && ok "(AC-9) a retry under a NEW run id APPENDS — aborted runs stay in the corpus" \
  || bad "(AC-9) expected 2 rows keyed alpha,beta; got $(jq -rs '[.[].runId]|join(",")' < "$CL")"

# --- AC-7: --close-out without --issue has no identity to key on ------------
# shellcheck disable=SC2069 # deliberate: keep STDERR (the refusal), discard stdout
CO_OUT="$( OTEL_METRICS_FILE="$MET" COST_BLOCK_SKIP_FLUSH=1 \
  bash "$SCRIPT" --stateless --close-out --sessions "$S1" \
    --start 2026-07-02T10:00:00Z --end 2026-07-02T11:30:00Z 2>&1 >/dev/null )"; CO_RC=$?
{ [[ "$CO_RC" -eq 2 ]] && grep -q 'requires --issue' <<<"$CO_OUT"; } \
  && ok "(AC-7) --close-out without --issue is a usage error, not a row with an empty key" \
  || bad "(AC-7) --close-out alone: rc=$CO_RC, stderr: $CO_OUT"

# --- AC-10: no rollup, no row ------------------------------------------------
# The fence is derivable and the sessions are real; there is simply no cost inside it. The
# writer sits past every skip(…) exit, so this is structural — but a future edit that moved it
# above them would publish a $0.00 row for every collector outage, and only this case would say so.
EMPTY_MET="$RT/metrics/empty-window.jsonl"
mk_cost_metrics "$EMPTY_MET" "$S1:2026-07-03T20:10:00Z:1.00:claude-opus-4-7"
CL2="$TMP/cost-log-skip.jsonl"
SKIP_STDERR="$( cd "$RT" && OTEL_METRICS_FILE="$EMPTY_MET" COST_LOG_FILE="$CL2" COST_BLOCK_SKIP_FLUSH=1 \
  bash "$SCRIPT" --stateless --issue 900 --close-out 2>&1 >/dev/null )"
{ grep -q 'skip(' <<<"$SKIP_STDERR" && [[ ! -s "$CL2" ]]; } \
  && ok "(AC-10) a skip(…) verdict writes no row, even under --close-out" \
  || bad "(AC-10) a skip path wrote a row or produced no verdict: $SKIP_STDERR"

# --- AC-13: the no-readable-metrics branch, driven ---------------------------
# The deleted `record` call sat on ONE branch — the belt-and-braces exit taken when every
# metrics candidate's mtime became unreadable — and `set -uo pipefail` renders a call to a
# retired function as one stderr line and a continue. A guard that never enters that branch
# cannot fail on a revert of it, so the branch is entered here rather than reasoned about:
# an empty live file beside a non-empty rotated backup gets past the telemetry-off check,
# and a `stat` that refuses makes both mtime passes come up empty. Its own diagnostic is
# asserted first, so this can never pass by not reaching the code it exists to cover.
STUB="$TMP/stub-bin"; mkdir -p "$STUB"
printf '#!/bin/sh\nexit 1\n' > "$STUB/stat"; chmod +x "$STUB/stat"
UNREAD="$RT/unreadable"; mkdir -p "$UNREAD"
: > "$UNREAD/metrics.jsonl"
mk_cost_metrics "$UNREAD/metrics-2026-07-02T09-00-00.000-size.jsonl" \
  "$S1:2026-07-02T10:10:00Z:1.00:claude-opus-4-7"
# shellcheck disable=SC2069 # deliberate: keep STDERR (the diagnostic), discard stdout
UNREAD_STDERR="$( cd "$RT" && PATH="$STUB:$PATH" OTEL_METRICS_FILE="$UNREAD/metrics.jsonl" \
  COST_BLOCK_SKIP_FLUSH=1 bash "$SCRIPT" --stateless --issue 900 --close-out --out /dev/null 2>&1 >/dev/null )"
grep -q 'no readable metrics file could be selected' <<<"$UNREAD_STDERR" \
  && ok "(AC-13) the no-readable-metrics branch is entered, not merely present" \
  || bad "(AC-13) the branch was not reached, so the guard below proves nothing: $UNREAD_STDERR"

# With that branch driven alongside the skip and close-out paths, this asserts the CLASS: any
# surviving call to something that no longer exists shows up as an interpreter complaint.
ALL_STDERR="$SKIP_STDERR
$UNREAD_STDERR
$( cd "$RT" && COST_LOG_FILE="$CL2" OTEL_METRICS_FILE="$MET" COST_BLOCK_SKIP_FLUSH=1 \
     bash "$SCRIPT" --stateless --issue 900 --close-out --out /dev/null 2>&1 >/dev/null )"
grep -qE 'command not found|not found$' <<<"$ALL_STDERR" \
  && bad "(AC-13) a driven path calls something that does not exist: $ALL_STDERR" \
  || ok "(AC-13) no driven path emits a shell diagnostic for a retired helper"

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1

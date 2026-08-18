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
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1

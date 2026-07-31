#!/usr/bin/env bash
# stage-envelopes-selftest.sh — behavioral suite for tools/stage-envelopes.sh.
#
# Every case executes the REAL script against a generated corpus and asserts on what it
# emits. Nothing here re-declares the production percentile/triage/join logic — a copy
# cannot fail on a production edit (docs/testing.md, "Never test a copy").
#
# Corpora are GENERATED rather than committed because each case's point is the
# arithmetic, and hand-writing 10 state files hides the expected value from the reader.
# The generator writes real statectl-shaped state files that stage-times.sh reads
# unmodified, so the tool under test still walks a real corpus through its real seam.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$SCRIPT_DIR/stage-envelopes.sh"
[[ -f "$TOOL" ]] || { echo "stage-envelopes-selftest: missing $TOOL" >&2; exit 1; }
command -v jq >/dev/null || { echo "stage-envelopes-selftest: jq is required" >&2; exit 1; }

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1" >&2; }

WORK="$(mktemp -d -t stage-envelopes-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

BASE_EPOCH=1767225600   # 2026-01-01T00:00:00Z — fixed, so no case depends on the clock.

# mkrun <dir> <stem> <ticketKey> <base-offset-min> <stage-spec>...
#   stage-spec = <stage>:<offset-min-from-run-start>:<duration-min>
# Emits a minimal but REAL state file: single session, no pause spans, one calendar day,
# no `.mode` — i.e. every window trusted unless a case deliberately breaks one signal.
mkrun() {
  local dir="$1" stem="$2" tk="$3" runoff="$4"; shift 4
  local start=$((BASE_EPOCH + runoff * 60))
  local stages="{}" last="$start" spec n off dur s e
  for spec in "$@"; do
    n="${spec%%:*}"; spec="${spec#*:}"
    off="${spec%%:*}"; dur="${spec#*:}"
    s=$((start + off * 60)); e=$((s + dur * 60))
    [[ "$e" -gt "$last" ]] && last="$e"
    stages="$(jq -c --arg n "$n" --argjson s "$s" --argjson e "$e" \
      '.[$n] = {startedAt: ($s | todate), completedAt: ($e | todate), status: "completed"}' <<<"$stages")"
  done
  jq -n --arg tk "$tk" --arg stem "$stem" --argjson start "$start" --argjson last "$last" \
        --argjson stages "$stages" '{
    ticketKey: $tk, runId: ("selftest-" + $stem), status: "completed",
    startedAt: ($start | todate), lastUpdatedAt: ($last | todate),
    pipelineSessions: [{sessionId: ("sess-" + $stem), source: "interactive"}],
    pauseSpans: [], stages: $stages
  }' > "$dir/$stem.json"
}

run_tool() { bash "$TOOL" --state-dir "$1" --json "${@:2}"; }

# ─────────────────────────────────────────────────────────────────────────────────
# (env1) Nearest-rank percentile math, and the record/non-record distinction.
# Ten peer runs with stage-1 durations 1..10 min; the run under test sits at 100.
# nearest-rank over the ASCENDING sample of n=10: p50 = ceil(0.50*10)=5th  = 5
#                                                 p90 = ceil(0.90*10)=9th  = 9
# 100 > 9 so it flags OVER; p90 (9) is NOT the sample maximum (10), so `record` is
# false — the run is in the tail, it did not set a record.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env1"; mkdir -p "$D"
for i in $(seq 1 10); do mkrun "$D" "peer$i" "peer$i" $((i * 1000)) "1:0:$i"; done
mkrun "$D" "target" "target" 90000 "1:0:100"
OUT="$(run_tool "$D" --run target --window 50)"
E="$(jq -c '.timeEnvelopes[] | select(.stage == "1")' <<<"$OUT")"
if [[ "$(jq -r '.n, .p50, .p90, .thisRun, .over, .record' <<<"$E" | paste -sd, -)" == "10,5,9,100,true,false" ]]; then
  pass "(env1) nearest-rank p50/p90 over n=10 -> 5/9; 100 flags OVER but is not a record"
else
  fail "(env1) percentile math — got $(jq -c '{n,p50,p90,thisRun,over,record}' <<<"$E")"
fi

# `record` must fire when the p90 IS the observed maximum — the small-n case the report
# is required to name, because "exceeds p90" there means only "nothing went higher yet".
D="$WORK/env1b"; mkdir -p "$D"
for i in $(seq 1 8); do mkrun "$D" "peer$i" "peer$i" $((i * 1000)) "1:0:5"; done
mkrun "$D" "target" "target" 90000 "1:0:99"
E="$(run_tool "$D" --run target --window 50 | jq -c '.timeEnvelopes[] | select(.stage == "1")')"
if [[ "$(jq -r '.p90, .over, .record' <<<"$E" | paste -sd, -)" == "5,true,true" ]]; then
  pass "(env1b) p90 == sample max -> OVER is reported as a new record, not a tail event"
else
  fail "(env1b) record detection — got $(jq -c '{p90,over,record}' <<<"$E")"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env2) Leave-one-out. Eight peers at 1 min, target at 1000 min.
# WITH leave-one-out : sample = [1 x8],        n=8, p90 = 1    -> 1000 > 1  -> OVER.
# WITHOUT it         : sample = [1 x8, 1000],  n=9, p90 = 9th = 1000 -> NOT over.
# So the flag itself discriminates: a broken leave-one-out cannot produce this result.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env2"; mkdir -p "$D"
for i in $(seq 1 8); do mkrun "$D" "peer$i" "peer$i" $((i * 1000)) "1:0:1"; done
mkrun "$D" "target" "target" 90000 "1:0:1000"
E="$(run_tool "$D" --run target --window 50 | jq -c '.timeEnvelopes[] | select(.stage == "1")')"
if [[ "$(jq -r '.n, .p90, .over' <<<"$E" | paste -sd, -)" == "8,1,true" ]]; then
  pass "(env2) run under test is excluded from its own envelope (n=8, p90=1, OVER)"
else
  fail "(env2) leave-one-out — got $(jq -c '{n,p90,over}' <<<"$E")"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env3) Min-n floor, AT THE BOUNDARY, pinning D-7: the floor is evaluated on the
# POST-exclusion sample. Eight peers + target -> n=8 -> envelope. Seven peers +
# target -> n=7 -> known-unknown and NO flag, even though the target is extreme.
# Under a pre-exclusion reading the second case would count 8 and emit an envelope,
# so these two cases together are what fix the ordering.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env3a"; mkdir -p "$D"
for i in $(seq 1 8); do mkrun "$D" "peer$i" "peer$i" $((i * 1000)) "1:0:2"; done
mkrun "$D" "target" "target" 90000 "1:0:500"
E="$(run_tool "$D" --run target --window 50 | jq -c '.timeEnvelopes[] | select(.stage == "1")')"
if [[ "$(jq -r '.n, .floorMet, .over' <<<"$E" | paste -sd, -)" == "8,true,true" ]]; then
  pass "(env3a) exactly 8 trusted windows AFTER exclusion -> envelope emitted, flag allowed"
else
  fail "(env3a) floor at n=8 — got $(jq -c '{n,floorMet,over}' <<<"$E")"
fi

D="$WORK/env3b"; mkdir -p "$D"
for i in $(seq 1 7); do mkrun "$D" "peer$i" "peer$i" $((i * 1000)) "1:0:2"; done
mkrun "$D" "target" "target" 90000 "1:0:500"
OUT="$(run_tool "$D" --run target --window 50)"
E="$(jq -c '.timeEnvelopes[] | select(.stage == "1")' <<<"$OUT")"
KU="$(jq -r '[.knownUnknowns[] | select(.key == "stage 1")] | length' <<<"$OUT")"
FL="$(jq -r '.flags | length' <<<"$OUT")"
if [[ "$(jq -r '.n, .floorMet, .p90, .over' <<<"$E" | paste -sd, -)" == "7,false,null,false" \
      && "$KU" == "1" && "$FL" == "0" ]]; then
  pass "(env3b) 7 after exclusion -> known-unknown row, no envelope, no flag (D-7 ordering)"
else
  fail "(env3b) floor at n=7 — env=$(jq -c '{n,floorMet,p90,over}' <<<"$E") knownUnknowns=$KU flags=$FL"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env4) Degradation is excluded at WINDOW granularity, not run granularity.
# One peer's stage-1 window is degraded (near-zero elapsed, preceded by a >=5 min
# transition gap — perf-retro signal 3), while its stage-2 window is clean. The
# degraded window must drop out of stage 1's sample while stage 2's sample keeps all
# nine peers. A run-granularity exclusion would show n=8 for BOTH stages.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env4"; mkdir -p "$D"
for i in $(seq 1 8); do mkrun "$D" "peer$i" "peer$i" $((i * 1000)) "1:0:4" "2:10:4"; done
# stage 1 ends at +0 (zero elapsed) and stage 2 starts at +30 -> a 30 min gap into
# stage 2... the degraded window is the one that barely elapsed AFTER a big gap, so
# put the near-zero window second: stage 1 runs 0..4, stage 2 starts at 40 for 0 min.
mkrun "$D" "degraded" "degraded" 50000 "1:0:4" "2:40:0"
mkrun "$D" "target" "target" 90000 "1:0:4" "2:10:4"
OUT="$(run_tool "$D" --run target --window 50)"
N1="$(jq -r '.timeEnvelopes[] | select(.stage == "1") | .n' <<<"$OUT")"
N2="$(jq -r '.timeEnvelopes[] | select(.stage == "2") | .n' <<<"$OUT")"
SIG="$(jq -r '[.degraded[] | select(.stem == "degraded") | .signals[]] | join(",")' <<<"$OUT")"
if [[ "$N1" == "9" && "$N2" == "8" && "$SIG" == "near-zero-after-gap" ]]; then
  pass "(env4) one degraded window is dropped; the same run's clean window still counts"
else
  fail "(env4) window-granularity exclusion — stage1 n=$N1 (want 9), stage2 n=$N2 (want 8), signals='$SIG'"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env5) Structural per-ticket dedup (D-4). Ticket 500 has a live file plus two
# snapshots -> the live file supersedes both. Ticket 501 has TWO snapshots and no
# live file -> both survive as distinct runs. The snapshot suffixes deliberately
# differ (`-failed-`, `-aborted-`, `-escalated-`) because the rename conventions are
# undocumented and a literal-suffix rule would miss whichever it did not enumerate.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env5"; mkdir -p "$D"
mkrun "$D" "500" "500" 5000 "1:0:7"
mkrun "$D" "500-failed-20260101T000000Z" "500" 1000 "1:0:99"
mkrun "$D" "500-escalated-20260101T000000Z" "500" 2000 "1:0:98"
mkrun "$D" "501-aborted-20260101T000000Z" "501" 3000 "1:0:11"
mkrun "$D" "501-aborted-20260102T000000Z" "501" 4000 "1:0:12"
OUT="$(run_tool "$D" --run 500 --window 50 --min-n 1)"
STEMS="$(jq -r '[.degraded[].stem] + [.timeEnvelopes[].stage] | length' <<<"$OUT")"
RUNS="$(jq -r '.corpus.runsInWindow' <<<"$OUT")"
SAMPLE_N="$(jq -r '.timeEnvelopes[] | select(.stage == "1") | .n' <<<"$OUT")"
MINE="$(jq -r '.timeEnvelopes[] | select(.stage == "1") | .thisRun' <<<"$OUT")"
if [[ "$RUNS" == "3" && "$SAMPLE_N" == "2" && "$MINE" == "7" ]]; then
  pass "(env5) live file supersedes its snapshots; a snapshot-only ticket keeps both runs"
else
  fail "(env5) dedup — runsInWindow=$RUNS (want 3), sample n=$SAMPLE_N (want 2), thisRun=$MINE (want 7) [$STEMS]"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env6) Cost axis: bucket separation, legacy-vocabulary normalization, and join
# disambiguation — all three read off ONE fixture log.
#   * `Intake + Planning` normalizes forward into `Intake`.
#   * An unrecognized label collapses into the single `legacy vocabulary` row rather
#     than quietly becoming its own bucket.
#   * Two rows share run c1's session id (the live mid-run-block + rollup case): the
#     NEWEST by `.at` represents the run, it is marked join:multi-row, and the older
#     row must NOT also contribute (that would double-count the run).
#   * Cost buckets never appear as numbered stages — the two axes stay separate.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env6"; mkdir -p "$D"
for i in $(seq 1 9); do mkrun "$D" "c$i" "c$i" $((i * 1000)) "1:0:3"; done
mkrun "$D" "target" "target" 90000 "1:0:3"
{
  # c1: an early partial row, then the authoritative rollup — same session id.
  echo '{"at":"2026-01-01T01:00:00Z","ticketKey":"c1","sessionIds":["sess-c1"],"byLabel":[{"label":"Intake","cost_usd":999}]}'
  echo '{"at":"2026-01-01T09:00:00Z","ticketKey":"c1","sessionIds":["sess-c1"],"byLabel":[{"label":"Intake + Planning","cost_usd":2},{"label":"Warp Core","cost_usd":5}]}'
  for i in $(seq 2 9); do
    printf '{"at":"2026-01-01T0%d:00:00Z","ticketKey":"c%d","sessionIds":["sess-c%d"],"byLabel":[{"label":"Intake","cost_usd":%d}]}\n' "$i" "$i" "$i" "$i"
  done
  echo '{"at":"2026-01-02T00:00:00Z","ticketKey":"target","sessionIds":["sess-target"],"byLabel":[{"label":"Intake","cost_usd":500}]}'
} > "$D/cost-log.jsonl"
OUT="$(run_tool "$D" --run target --window 50)"
INTAKE="$(jq -c '.costEnvelopes[] | select(.bucket == "Intake")' <<<"$OUT")"
LEGACY="$(jq -r '[.costEnvelopes[] | select(.bucket == "legacy vocabulary")] | length' <<<"$OUT")"
MULTI="$(jq -r '.corpus.costRunsJoined' <<<"$OUT")"
STAGEBUCKET="$(jq -r '[.timeEnvelopes[] | select(.stage == "Intake")] | length' <<<"$OUT")"
# c1 contributes 2 (the rollup's normalized Intake), c2..c9 contribute 2..9.
# Sample ascending = [2,2,3,4,5,6,7,8,9] -> n=9, p90 = ceil(8.1)=9th = 9. 500 > 9.
if [[ "$(jq -r '.n, .p90, .thisRun, .over' <<<"$INTAKE" | paste -sd, -)" == "9,9,500,true" \
      && "$LEGACY" == "1" && "$MULTI" == "10" && "$STAGEBUCKET" == "0" ]]; then
  pass "(env6) legacy label normalizes; unknown label isolated; multi-row joins once; axes stay separate"
else
  fail "(env6) cost axis — Intake=$INTAKE legacyRows=$LEGACY joinedRuns=$MULTI stageNamedIntake=$STAGEBUCKET"
fi

# The older c1 row must be the one discarded — if the OLDEST had won, c1 would
# contribute 999 and the p90 would be 999, not 9. Assert the direction explicitly.
if [[ "$(jq -r '.costEnvelopes[] | select(.bucket == "Intake") | .p90' <<<"$OUT")" == "9" ]]; then
  pass "(env6b) on multiplicity the NEWEST row by .at represents the run (999 discarded)"
else
  fail "(env6b) join direction — p90=$(jq -r '.costEnvelopes[] | select(.bucket == "Intake") | .p90' <<<"$OUT")"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env7) A lifecycle-dropped stage is reported as a known-unknown, never as a fast
# stage. The run under test records stage 2 in `stages` with no completedAt, so it has
# no window at all — the failure mode this guards is it silently reading as 0 min.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env7"; mkdir -p "$D"
for i in $(seq 1 9); do mkrun "$D" "peer$i" "peer$i" $((i * 1000)) "1:0:3" "2:10:3"; done
mkrun "$D" "target" "target" 90000 "1:0:3" "2:10:3"
jq '.stages["2"] |= {startedAt: .startedAt}' "$D/target.json" > "$D/target.tmp" && mv "$D/target.tmp" "$D/target.json"
OUT="$(run_tool "$D" --run target --window 50)"
DROP="$(jq -r '[.knownUnknowns[] | select(.key == "stage 2" and (.reason | test("lifecycle-dropped")))] | length' <<<"$OUT")"
MINE2="$(jq -r '.timeEnvelopes[] | select(.stage == "2") | .thisRun' <<<"$OUT")"
if [[ "$DROP" == "1" && "$MINE2" == "null" ]]; then
  pass "(env7) a lifecycle-dropped stage reports as known-unknown, not as 0 min"
else
  fail "(env7) lifecycle-dropped — knownUnknown rows=$DROP (want 1), thisRun=$MINE2 (want null)"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env8) Quarantined artifacts never enter the corpus. A `-released-` file is a
# COMPLETE state file with `stages` intact, so the `has("stages")` gate alone would
# let it aggregate as a live run and double-count its ticket.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env8"; mkdir -p "$D"
for i in $(seq 1 3); do mkrun "$D" "q$i" "q$i" $((i * 1000)) "1:0:3"; done
mkrun "$D" "q9-released-20260101T000000Z" "q9" 4000 "1:0:3"
mkrun "$D" "q8-stale-20260101T000000Z" "q8" 5000 "1:0:3"
RUNS="$(run_tool "$D" --run q1 --window 50 --min-n 1 | jq -r '.corpus.runsInWindow')"
if [[ "$RUNS" == "3" ]]; then
  pass "(env8) *-released-* and *-stale-* stay out of the corpus"
else
  fail "(env8) quarantine exclusion — runsInWindow=$RUNS (want 3)"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env9) The five fidelity signals that degrade a window all fire, and a clean run
# stays trusted. Signal 4 keys on `.mode` (D-8) — NOT on pipelineSessions[].source,
# which every run in this pipeline sets to "interactive" as its TRANSPORT. Reading
# that field as human-paced would degrade the entire corpus and darken the tool.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env9"; mkdir -p "$D"
mkrun "$D" "clean" "clean" 1000 "1:0:5"
mkrun "$D" "multisession" "multisession" 2000 "1:0:5"
jq '.pipelineSessions += [{sessionId: "sess-b", source: "interactive"}]' "$D/multisession.json" > "$D/t" && mv "$D/t" "$D/multisession.json"
mkrun "$D" "humanpaced" "humanpaced" 3000 "1:0:5"
jq '.mode = "interactive"' "$D/humanpaced.json" > "$D/t" && mv "$D/t" "$D/humanpaced.json"
mkrun "$D" "acrossdays" "acrossdays" 4000 "1:0:5"
jq '.lastUpdatedAt = "2026-01-05T00:00:00Z"' "$D/acrossdays.json" > "$D/t" && mv "$D/t" "$D/acrossdays.json"
OUT="$(run_tool "$D" --run clean --window 50 --min-n 1)"
sig_of() { jq -r --arg s "$1" '[.degraded[] | select(.stem == $s) | .signals[]] | join(",")' <<<"$OUT"; }
CLEAN_DEG="$(jq -r '[.degraded[] | select(.stem == "clean")] | length' <<<"$OUT")"
if [[ "$CLEAN_DEG" == "0" \
      && "$(sig_of multisession)" == "multi-session-no-pause" \
      && "$(sig_of humanpaced)" == "human-paced-mode" \
      && "$(sig_of acrossdays)" == "effective-equals-wall-across-days" ]]; then
  pass "(env9) run-level signals 1/2/4 each degrade their run; a transport-interactive clean run does not"
else
  fail "(env9) triage signals — clean=$CLEAN_DEG multi='$(sig_of multisession)' human='$(sig_of humanpaced)' days='$(sig_of acrossdays)'"
fi

# A source-keyed signal 4 would have degraded EVERY run here, since mkrun writes
# source "interactive" for all of them. Assert the corpus is not wholesale degraded.
TRUSTED="$(jq -r '.trustedWindows' <<<"$OUT")"
if [[ "$TRUSTED" -ge 1 ]]; then
  pass "(env9b) transport source=interactive alone never degrades a window (D-8)"
else
  fail "(env9b) D-8 — the whole corpus degraded (trustedWindows=$TRUSTED)"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env10) The text report DECLARES its corpus, so a consumer enumerating the same
# directory by a different rule cannot silently disagree with it.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env10"; mkdir -p "$D"
for i in $(seq 1 3); do mkrun "$D" "d$i" "d$i" $((i * 1000)) "1:0:3"; done
TXT="$(bash "$TOOL" --state-dir "$D" --run d1 --window 50)"
if grep -q '^corpus: 3 run(s) in window' <<<"$TXT" \
   && grep -q '^dedup: basename==ticketKey supersedes' <<<"$TXT" \
   && grep -q 'excluded: \*-stale-\*, \*-released-\*' <<<"$TXT"; then
  pass "(env10) the text report declares run count, dedup rule and quarantine exclusion"
else
  fail "(env10) corpus declaration missing from the report"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env11) The mtime pre-filter is a SPEED knob, not a corpus change: on a corpus that
# fits inside the 3N cap it must select exactly what the unfiltered walk selects.
# (D-9 is explicit that on a large dir it is only a best-effort superset.)
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env11"; mkdir -p "$D"
for i in $(seq 1 6); do mkrun "$D" "m$i" "m$i" $((i * 1000)) "1:0:$i"; done
A="$(run_tool "$D" --run m1 --window 3 --min-n 1 | jq -c '[.timeEnvelopes[] | {stage, n, p50, p90}]')"
B="$(run_tool "$D" --run m1 --window 3 --min-n 1 --mtime-prefilter | jq -c '[.timeEnvelopes[] | {stage, n, p50, p90}]')"
if [[ "$A" == "$B" ]]; then
  pass "(env11) --mtime-prefilter derives the same envelopes as the unfiltered walk"
else
  fail "(env11) pre-filter changed the corpus — unfiltered=$A prefiltered=$B"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env12) The state-dir precedence ladder. Every case above addresses its corpus with
# --state-dir, which short-circuits the resolver on its first branch — so the tool's
# advertised precedence (STATECTL_STATE_DIR, then the repo root, then cwd) went
# entirely unexercised. The mutation sweep found this: mutants in the ladder's
# `${VAR:-}` defaults and its `-n` guards all survived, because no case could reach
# them. STATECTL_STATE_DIR is also the documented way a fixture is addressed through
# this family of tools ((pause3) uses it), so it is contract, not an internal.
# ─────────────────────────────────────────────────────────────────────────────────
D="$WORK/env12"; mkdir -p "$D"
for i in $(seq 1 3); do mkrun "$D" "e$i" "e$i" $((i * 1000)) "1:0:3"; done
# No --state-dir here: the corpus is reachable ONLY if the env-var branch resolves.
ENV_OUT="$(STATECTL_STATE_DIR="$D" bash "$TOOL" --run e1 --window 50 --min-n 1 --json 2>&1)"
if jq -e '.corpus.runsInWindow == 3' >/dev/null 2>&1 <<<"$ENV_OUT"; then
  pass "(env12) STATECTL_STATE_DIR resolves the corpus when --state-dir is absent"
else
  fail "(env12) STATECTL_STATE_DIR ladder — got ${ENV_OUT:0:160}"
fi

# --state-dir must WIN over the env var, not merely work alongside it: the flag is the
# explicit operator override, and a resolver that silently preferred the environment
# would derive over a different corpus than the caller named.
D2="$WORK/env12b"; mkdir -p "$D2"
for i in $(seq 1 5); do mkrun "$D2" "f$i" "f$i" $((i * 1000)) "1:0:3"; done
PREC="$(STATECTL_STATE_DIR="$D" bash "$TOOL" --state-dir "$D2" --run f1 --window 50 --min-n 1 --json 2>&1)"
if jq -e '.corpus.runsInWindow == 5' >/dev/null 2>&1 <<<"$PREC"; then
  pass "(env12b) --state-dir takes precedence over STATECTL_STATE_DIR"
else
  fail "(env12b) precedence — got ${PREC:0:160}"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env13) Argument validation rejects a non-numeric window / floor rather than
# silently deriving over a garbage corpus. A tool whose whole output is a statistic
# must not accept a non-number for the two knobs that size its sample.
# ─────────────────────────────────────────────────────────────────────────────────
if ! bash "$TOOL" --state-dir "$D" --window abc >/dev/null 2>&1 \
   && ! bash "$TOOL" --state-dir "$D" --min-n abc >/dev/null 2>&1 \
   && ! bash "$TOOL" --state-dir "$D" --bogus-flag >/dev/null 2>&1; then
  pass "(env13) non-numeric --window / --min-n and an unknown flag are all rejected"
else
  fail "(env13) argument validation accepted a bad value"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env14) A state dir that does not exist, and one holding no run-state files, both
# exit nonzero with a diagnostic rather than emitting an empty-but-plausible report.
# An envelope tool that prints a clean table over nothing is the worst failure mode
# it has: the reader cannot tell "measured nothing" from "measured and found nothing".
# ─────────────────────────────────────────────────────────────────────────────────
EMPTY="$WORK/env14-empty"; mkdir -p "$EMPTY"
if ! bash "$TOOL" --state-dir "$WORK/env14-missing" >/dev/null 2>&1 \
   && ! bash "$TOOL" --state-dir "$EMPTY" >/dev/null 2>&1; then
  pass "(env14) a missing state dir and an empty one both fail loudly, never a blank report"
else
  fail "(env14) an absent/empty corpus produced a report instead of an error"
fi

# ─────────────────────────────────────────────────────────────────────────────────
# (env15) The repo-root fall-through: no --state-dir, no STATECTL_STATE_DIR, no
# SECOND_SHIFT_REPO_ROOT — the resolver must anchor on `git rev-parse --git-common-dir`
# and find the corpus under the MAIN checkout. This is the branch production actually
# takes (the tool is invoked from pipeline worktrees, where a cwd-relative path is
# empty and would read as "no runs recorded" rather than as the wrong directory).
#
# Every earlier case short-circuits the ladder on an earlier branch, so this is the
# only case that reaches the tail of state_dir(). The mutation sweep is what proved
# that mattered: `cd "$common_dir" && pwd` -> `|| pwd` survived, and that flip is not
# cosmetic — with `||`, cd succeeds so pwd never runs, common_dir collapses to empty,
# and the root resolves to "." — i.e. exactly the cwd-relative failure the anchoring
# exists to prevent.
# ─────────────────────────────────────────────────────────────────────────────────
REPO="$WORK/env15-repo"
mkdir -p "$REPO/.claude/pipeline-state"
# The git env is cleared for `init` as well as for the tool run below: with GIT_DIR set,
# `git init` initializes THAT repo rather than $REPO, and the fixture never exists.
if env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$REPO" init --quiet 2>/dev/null; then
  D="$REPO/.claude/pipeline-state"
  for i in $(seq 1 4); do mkrun "$D" "g$i" "g$i" $((i * 1000)) "1:0:6"; done
  # Run from a SUBDIRECTORY, so a resolver that quietly used cwd instead of the
  # common-dir anchor would look in the wrong place and find nothing.
  mkdir -p "$REPO/sub/dir"
  # GIT_DIR / GIT_WORK_TREE are cleared too, not just the second-shift vars: an inherited
  # git env re-points `git rev-parse --git-common-dir` at the CALLER's repo, so this case
  # would resolve someone else's state dir and fail for a reason that has nothing to do
  # with the resolver. Verified: with GIT_DIR set and no unset, this case fails.
  ROOT_OUT="$(cd "$REPO/sub/dir" && env -u STATECTL_STATE_DIR -u SECOND_SHIFT_REPO_ROOT \
    -u SECOND_SHIFT_CONFIG -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
    bash "$TOOL" --run g1 --window 50 --min-n 1 --json 2>&1)"
  if jq -e '.corpus.runsInWindow == 4' >/dev/null 2>&1 <<<"$ROOT_OUT"; then
    pass "(env15) with no overrides the corpus resolves via the git-common-dir repo root, from a subdir"
  else
    fail "(env15) repo-root fall-through — got ${ROOT_OUT:0:200}"
  fi
else
  echo "  skip (env15) — git init unavailable in this environment"
fi

echo
echo "stage-envelopes-selftest: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

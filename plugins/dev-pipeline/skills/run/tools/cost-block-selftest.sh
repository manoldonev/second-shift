#!/usr/bin/env bash
#
# Self-test for the per-run time fence in pipeline-cost-block.sh (#224).
#
# A self-test in the style of claim-selftest.sh, located under tools/ and
# wired into pipeline-doctor.sh. Pure-local: no Claude CLI, no network, no real
# `gh`. It drives TWO sequential runs that share ONE session.id against ONE
# metrics fixture, via the script's COST_BLOCK_DUMP_ROLLUP test hook (which
# prints the time-fenced rollup JSON and exits before any PR I/O), and asserts
# each run's rollup excludes the other run's co-resident cost.
#
# WHY this exists (#224): the cost block attributed OTel spend by session.id
# ONLY. Running several pipelines (+ retros) sequentially in one long-lived
# interactive session — the recommended pattern — means every run records the
# same session.id, so a later/shorter run's "Other" inhaled all co-resident
# work. The fix clamps each run to its own wall-clock fence. This is the
# regression #183/#218/#211 would have caught.
#
# FIXTURE GEOMETRY (cost.usage datapoints, all under one session.id):
#   run A fence [10:00,10:30]: $1.00 @ 10:15 (inside a stage window)
#   run B fence [11:00,11:20]: $0.30 @ 11:08 (in a stage window -> "Plan")
#                              $0.10 @ 11:11 (in the 11:09->11:12 gap -> "Other")
#                              $0.05 @ 11:20 (EXACTLY fenceHi == stage-9 completedAt;
#                                             exercises the inclusive <= bound -> "PR Creation")
# So: run A total == $1.00 (B excluded); run B total == $0.45 (A excluded),
# of which "Other" == $0.10 (the in-fence gap only, never A's $1.00) and the
# $0.05 boundary point is KEPT (inclusive fenceHi) and buckets to a real stage.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../pipeline-cost-block.sh"
FIX="$HERE/../cost-tracking-fixtures"
METRICS="$FIX/two-runs-shared-session.jsonl"

# The script resolves STATE_FILE via `git rev-parse --git-common-dir` (the MAIN
# checkout's .claude/pipeline-state/, NOT the worktree's — they differ when this
# tree is a git worktree). Mirror that exact resolution so the state fixtures we
# install are the ones the script reads.
COMMON_RAW="$(cd "$HERE" && git rev-parse --git-common-dir)"     # may be relative (e.g. .git)
COMMON="$(cd "$HERE" && cd "$COMMON_RAW" && pwd)"                # resolved absolute
STATE_DIR="$(dirname "$COMMON")/.claude/pipeline-state"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

TMP="$(mktemp -d)"
# Executable stub bot wrapper: the script's early GH_BOT guard requires an
# executable, but the dump hook exits before the wrapper is ever invoked.
STUB_BOT="$TMP/gh-as-bot.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BOT"
chmod +x "$STUB_BOT"

# Track state files we install so cleanup never touches a real run's state.
A_STATE="$STATE_DIR/cost-fence-selftest-a.json"
B_STATE="$STATE_DIR/cost-fence-selftest-b.json"
cleanup() { rm -rf "$TMP"; rm -f "$A_STATE" "$B_STATE"; }
trap cleanup EXIT

mkdir -p "$STATE_DIR"

# Run the cost block in dump mode for one fixture state file; echo the rollup JSON.
#   $1 state id (basename without .json) — must already be installed in STATE_DIR
dump_rollup() {
  local id="$1"
  OTEL_METRICS_FILE="$METRICS" \
  COST_BLOCK_DUMP_ROLLUP=1 \
  GH_BOT="$STUB_BOT" \
    bash "$SCRIPT" "$id" 2>/dev/null
}

# Run the cost block in cost-log-row dump mode for one fixture state file; echo the
# persisted row JSON (the line write_cost_log_row appends to cost-log.jsonl). The
# row lands in $(dirname "$STATE_FILE")/cost-log.jsonl — i.e. STATE_DIR — so clean
# it up after. Used to assert the persisted row carries byLabel (#242).
dump_logrow() {
  local id="$1"
  OTEL_METRICS_FILE="$METRICS" \
  COST_BLOCK_DUMP_LOGROW=1 \
  COST_LOG_FILE="$TMP/cost-log.jsonl" \
  GH_BOT="$STUB_BOT" \
    bash "$SCRIPT" "$id" 2>/dev/null
}

# jq helpers over a rollup JSON on stdin.
total_of()  { jq -r '.totals.cost_usd'; }
label_cost() { jq -r --arg l "$1" '([.byLabel[] | select(.label==$l) | .cost_usd] | add) // 0'; }

[[ -f "$METRICS" ]] || { echo "FAIL: metrics fixture missing at $METRICS" >&2; exit 1; }
[[ -f "$SCRIPT" ]]  || { echo "FAIL: script missing at $SCRIPT" >&2; exit 1; }

cp "$FIX/state-two-runs-A.json" "$A_STATE"
cp "$FIX/state-two-runs-B.json" "$B_STATE"

echo "=== run A: [10:00–10:30] fence excludes run B's later cost ==="
A_ROLLUP="$(dump_rollup cost-fence-selftest-a)"
if [[ -z "$A_ROLLUP" ]] || ! jq -e . >/dev/null 2>&1 <<<"$A_ROLLUP"; then
  bad "run A produced no valid rollup JSON"
else
  A_TOTAL="$(total_of <<<"$A_ROLLUP")"
  [[ "$A_TOTAL" == "1.00" || "$A_TOTAL" == "1" ]] \
    && ok "run A total == \$1.00 (B's \$0.45 excluded by the fence)" \
    || bad "run A total expected 1.00, got $A_TOTAL"
fi

echo "=== run B: [11:00–11:20] fence excludes run A's earlier cost (the regression) ==="
B_ROLLUP="$(dump_rollup cost-fence-selftest-b)"
if [[ -z "$B_ROLLUP" ]] || ! jq -e . >/dev/null 2>&1 <<<"$B_ROLLUP"; then
  bad "run B produced no valid rollup JSON"
else
  B_TOTAL="$(total_of <<<"$B_ROLLUP")"
  [[ "$B_TOTAL" == "0.45" ]] \
    && ok "run B total == \$0.45 (A's \$1.00 NOT inhaled — the regression guard)" \
    || bad "run B total expected 0.45, got $B_TOTAL"

  B_OTHER="$(label_cost Other <<<"$B_ROLLUP")"
  [[ "$B_OTHER" == "0.10" || "$B_OTHER" == "0.1" ]] \
    && ok "run B 'Other' == \$0.10 (in-fence gap cost only, never run A's)" \
    || bad "run B 'Other' expected 0.10, got $B_OTHER"

  # The in-window datapoint must land in a real stage bucket, not Other.
  B_PLAN="$(label_cost Plan <<<"$B_ROLLUP")"
  [[ "$B_PLAN" == "0.30" || "$B_PLAN" == "0.3" ]] \
    && ok "run B in-window \$0.30 buckets to a real stage (Plan), not Other" \
    || bad "run B 'Plan' expected 0.30, got $B_PLAN"

  # The datapoint at EXACTLY fenceHi must be kept (inclusive <=) and bucket to
  # the terminal stage window (stage 9 / PR Creation), not be dropped.
  B_PR="$(label_cost "PR Creation" <<<"$B_ROLLUP")"
  [[ "$B_PR" == "0.05" ]] \
    && ok "run B boundary \$0.05 @ fenceHi kept (inclusive bound) -> PR Creation" \
    || bad "run B 'PR Creation' expected 0.05, got $B_PR"
fi

echo "=== persisted cost-log row carries byLabel (#242) ==="
# The cross-run cost-log row (write_cost_log_row) must persist byLabel so per-stage
# cost is queryable across runs — not just the totals. Drive the real function via
# the COST_BLOCK_DUMP_LOGROW hook against run B (which has a PR, so it passes the
# PR-count guard) and assert the row's byLabel shape.
B_LOGROW="$(dump_logrow cost-fence-selftest-b)"
if [[ -z "$B_LOGROW" ]] || ! jq -e . >/dev/null 2>&1 <<<"$B_LOGROW"; then
  bad "run B produced no valid cost-log row JSON"
else
  # byLabel present and a non-empty array.
  B_BYLABEL_LEN="$(jq -r '(.byLabel // []) | length' <<<"$B_LOGROW")"
  [[ "$B_BYLABEL_LEN" -gt 0 ]] \
    && ok "cost-log row .byLabel is a non-empty array ($B_BYLABEL_LEN entries)" \
    || bad "cost-log row .byLabel missing or empty (got len=$B_BYLABEL_LEN)"

  # Each entry carries label + cost_usd (the rollup projection shape).
  B_SHAPE_OK="$(jq -r '[.byLabel[]? | select((.label|type=="string") and (.cost_usd|type=="number"))] | length' <<<"$B_LOGROW")"
  [[ "$B_SHAPE_OK" == "$B_BYLABEL_LEN" && "$B_BYLABEL_LEN" -gt 0 ]] \
    && ok "every .byLabel entry carries string label + numeric cost_usd" \
    || bad "byLabel entry shape wrong: $B_SHAPE_OK/$B_BYLABEL_LEN entries valid"

  # The persisted byLabel must match the rollup's byLabel (verbatim projection),
  # so the row is the queryable per-stage record the rollup already computes.
  B_ROLLUP_BYLABEL="$(jq -c '.byLabel' <<<"$B_ROLLUP")"
  B_ROW_BYLABEL="$(jq -c '.byLabel' <<<"$B_LOGROW")"
  [[ "$B_ROW_BYLABEL" == "$B_ROLLUP_BYLABEL" ]] \
    && ok "cost-log row .byLabel matches the rollup's byLabel verbatim" \
    || bad "cost-log row .byLabel diverged from rollup byLabel"
fi

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1

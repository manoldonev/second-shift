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
#   run B fence [11:00,11:20]: $0.30 @ 11:08 (inside stage 5's window -> "Implementation")
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

  # The in-window datapoint must land in a real stage bucket, not Other. 11:08 sits
  # inside stage 5's window, and stage 5 is Implement -> "Implementation". Asserting the
  # label (not just the amount) is what pins the stage->label map to SKILL.md's stage
  # numbering; the map was previously shifted one stage late, so stage 5 (Implement)
  # rendered as "Plan" and no Implementation row ever appeared.
  B_IMPL="$(label_cost Implementation <<<"$B_ROLLUP")"
  [[ "$B_IMPL" == "0.30" || "$B_IMPL" == "0.3" ]] \
    && ok "run B in-window \$0.30 buckets to stage 5 => Implementation, not Plan/Other" \
    || bad "run B 'Implementation' expected 0.30, got $B_IMPL"

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
echo "=== write identity: tracker.bot.enabled decides bot-vs-operator (#74) ==="
#
# These cases drive the REAL script end-to-end through the amend path (no dump
# hook short-circuits them), with both `gh` and the bot wrapper stubbed as
# argv-logging scripts. Each asserts BOTH the recorded costBlockApplied AND which
# binary actually received `pr edit` — so a case cannot pass by recording the
# right value while writing through the wrong identity.
#
# Fake-`gh` contract (load-bearing):
#   1. named exactly `gh` in a dir prepended to PATH, so `command -v gh` finds it;
#   2. answers `pr view --json body --jq .body` with exit 0 and a body WITHOUT the
#      <!-- pipeline-cost-block --> marker (a nonzero exit would make amend_pr
#      return 1 and record skipped-amend-failed, never reaching the write);
#   3. logs argv and exits 0 for everything else, including `pr edit`.
#
# Each case runs in its own temp dir with its own SECOND_SHIFT_CONFIG,
# STATECTL_STATE_DIR (holding a copy of the state fixture) and COST_LOG_FILE, so
# nothing touches the operator's real pipeline-state dir or cost-log.jsonl.

# Build an argv-logging stub satisfying the contract above.
#   $1 destination path   $2 log file path
make_gh_stub() {
  cat > "$1" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$2"
if [ "\${1:-}" = "pr" ] && [ "\${2:-}" = "view" ]; then
  echo "existing body without the marker"
fi
exit 0
STUB
  chmod +x "$1"
}

# Run the script for one write-identity case.
#   $1 case dir   $2 config JSON (or the literal ABSENT)   $3 value for GH_BOT
# Echoes the recorded costBlockApplied. Leaves gh.log / bot.log in the case dir.
run_identity_case() {
  local dir="$1" cfg_json="$2" bot_val="$3"
  local id="cost-identity-selftest"
  mkdir -p "$dir/bin" "$dir/state" "$dir/home"
  cp "$FIX/state-two-runs-B.json" "$dir/state/$id.json"

  local cfg_path="$dir/second-shift.config.json"
  if [[ "$cfg_json" == "ABSENT" ]]; then
    cfg_path="$dir/does-not-exist.json"
  else
    printf '%s\n' "$cfg_json" > "$cfg_path"
  fi

  make_gh_stub "$dir/bin/gh" "$dir/gh.log"
  [[ -f "$dir/wrapper.sh" ]] || make_gh_stub "$dir/wrapper.sh" "$dir/bot.log"

  # HOME is sandboxed per case so _default_bot()'s derived fallback
  # ($HOME/.config/<repo>/gh-as-bot.sh) can never resolve to a wrapper that
  # happens to exist on the operator's machine. Without this the AC-1 assertion
  # is machine-dependent: a real wrapper would take the write and then delegate
  # to the PATH-stubbed `gh` internally, so gh.log records `pr edit` and the case
  # passes for the wrong reason (verified — it survives the unconditional-guard
  # mutant on a machine with a wrapper installed).
  PATH="$dir/bin:$PATH" \
  HOME="$dir/home" \
  OTEL_METRICS_FILE="$METRICS" \
  SECOND_SHIFT_CONFIG="$cfg_path" \
  STATECTL_STATE_DIR="$dir/state" \
  COST_LOG_FILE="$dir/cost-log.jsonl" \
  GH_BOT="$bot_val" \
    bash "$SCRIPT" "$id" >/dev/null 2>&1

  jq -r '.costBlockApplied' "$dir/state/$id.json"
}

# --- AC-1: bot disabled + gh present -> amended via plain gh, NOT skipped -----
D1="$TMP/case-bot-disabled"
R1="$(run_identity_case "$D1" '{"tracker":{"bot":{"enabled":false}}}' '')"
[[ "$R1" == "true" ]] \
  && ok "(AC-1) bot-disabled repo amends the cost block (costBlockApplied=true)" \
  || bad "(AC-1) bot-disabled repo recorded '$R1', expected true"
grep -q 'pr edit' "$D1/gh.log" 2>/dev/null \
  && ok "(AC-1) the amend went through plain gh" \
  || bad "(AC-1) plain gh never received 'pr edit'"

# --- AC-2: bot ENABLED + wrapper missing -> skipped-no-bot-wrapper ------------
D2="$TMP/case-wrapper-missing"
R2="$(run_identity_case "$D2" '{"tracker":{"bot":{"enabled":true}}}' "$TMP/nonexistent-wrapper.sh")"
[[ "$R2" == "skipped-no-bot-wrapper" ]] \
  && ok "(AC-2) bot-enabled + missing wrapper records skipped-no-bot-wrapper" \
  || bad "(AC-2) recorded '$R2', expected skipped-no-bot-wrapper"
if grep -q 'pr edit' "$D2/gh.log" 2>/dev/null || grep -q 'pr edit' "$D2/bot.log" 2>/dev/null; then
  bad "(AC-2) a 'pr edit' was issued despite the missing wrapper"
else
  ok "(AC-2) no 'pr edit' reached either binary"
fi

# --- AC-3: bot ENABLED + wrapper present -> amends THROUGH THE WRAPPER --------
# The regression guard: a naive "always fall through to gh" breaks exactly here.
D3="$TMP/case-wrapper-present"
mkdir -p "$D3"
make_gh_stub "$D3/wrapper.sh" "$D3/bot.log"
R3="$(run_identity_case "$D3" '{"tracker":{"bot":{"enabled":true}}}' "$D3/wrapper.sh")"
[[ "$R3" == "true" ]] \
  && ok "(AC-3) bot-enabled + present wrapper amends (costBlockApplied=true)" \
  || bad "(AC-3) recorded '$R3', expected true"
grep -q 'pr edit' "$D3/bot.log" 2>/dev/null \
  && ok "(AC-3) the amend went through the bot wrapper" \
  || bad "(AC-3) the bot wrapper never received 'pr edit'"
grep -q 'pr edit' "$D3/gh.log" 2>/dev/null \
  && bad "(AC-3) plain gh received 'pr edit' — identity was downgraded" \
  || ok "(AC-3) plain gh did NOT receive the write"

# --- AC-4: config absent -> treated as bot-disabled -> plain gh ---------------
# $GH_BOT deliberately points at a WORKING wrapper, so this can only pass if the
# absent config (not a missing wrapper) drove the identity choice. Also covers
# D-3: a stray $GH_BOT never overrides a disabled/defaulted bot.
D4="$TMP/case-config-absent"
mkdir -p "$D4"
make_gh_stub "$D4/wrapper.sh" "$D4/bot.log"
R4="$(run_identity_case "$D4" ABSENT "$D4/wrapper.sh")"
[[ "$R4" == "true" ]] \
  && ok "(AC-4) absent config defaults to bot-disabled and amends" \
  || bad "(AC-4) recorded '$R4', expected true"
grep -q 'pr edit' "$D4/gh.log" 2>/dev/null \
  && ok "(AC-4) the amend went through plain gh" \
  || bad "(AC-4) plain gh never received 'pr edit'"
grep -q 'pr edit' "$D4/bot.log" 2>/dev/null \
  && bad "(AC-4) a stray \$GH_BOT wrapper took the write despite no config" \
  || ok "(AC-4) the stray \$GH_BOT wrapper was correctly ignored"

# --- wrapper resolution: config tracker.bot.wrapperPath, with ~ expansion -----
# The middle rung of the $GH_BOT > wrapperPath > _default_bot precedence. The
# four AC cases above all set $GH_BOT explicitly, so none of them reach this
# branch; without these two cases a broken jq path or a lost ~ expansion would
# ship silently (both would fall through to _default_bot and, under a sandboxed
# HOME, degrade to skipped-no-bot-wrapper).
D5="$TMP/case-wrapperpath"
mkdir -p "$D5"
make_gh_stub "$D5/wrapper.sh" "$D5/bot.log"
R5="$(run_identity_case "$D5" "{\"tracker\":{\"bot\":{\"enabled\":true,\"wrapperPath\":\"$D5/wrapper.sh\"}}}" '')"
[[ "$R5" == "true" ]] \
  && ok "(wrapperPath) config-resolved wrapper amends with \$GH_BOT unset" \
  || bad "(wrapperPath) recorded '$R5', expected true"
grep -q 'pr edit' "$D5/bot.log" 2>/dev/null \
  && ok "(wrapperPath) the config-resolved wrapper received 'pr edit'" \
  || bad "(wrapperPath) the config-resolved wrapper never received 'pr edit'"

# A leading ~ in wrapperPath must expand against $HOME (sandboxed per case), so
# the wrapper is planted inside the case's home dir and referenced as ~/wrapper.sh.
D6="$TMP/case-wrapperpath-tilde"
mkdir -p "$D6/home"
make_gh_stub "$D6/home/wrapper.sh" "$D6/bot.log"
R6="$(run_identity_case "$D6" '{"tracker":{"bot":{"enabled":true,"wrapperPath":"~/wrapper.sh"}}}' '')"
[[ "$R6" == "true" ]] \
  && ok "(wrapperPath) a leading ~ in wrapperPath expands against \$HOME" \
  || bad "(wrapperPath) ~ expansion failed — recorded '$R6', expected true"
grep -q 'pr edit' "$D6/bot.log" 2>/dev/null \
  && ok "(wrapperPath) the ~-expanded wrapper received 'pr edit'" \
  || bad "(wrapperPath) the ~-expanded wrapper never received 'pr edit'"

# --- skipped-no-gh-cli: gh absent from PATH entirely -------------------------
# Guards the retag from the misleading skipped-otel-error. Runs bot-DISABLED so
# the write-identity gate passes and execution actually reaches `command -v gh`.
#
# The PATH must still carry the tools the script genuinely needs to get that far
# (jq above all — `record` itself is a jq call, so a jq-less PATH records nothing
# and the case reads a vacuous `null`). A bare/empty PATH is therefore wrong. We
# use the system dirs, which on a normal install hold jq/git/coreutils but NOT
# `gh` (Homebrew installs that under its own prefix) — and we ASSERT that rather
# than assume it, skipping the case on a host where the assumption fails.
NOGH_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
if PATH="$NOGH_PATH" command -v gh >/dev/null 2>&1; then
  echo "  SKIP (no-gh) system PATH still resolves gh on this host — cannot stage the absent-gh case"
elif ! PATH="$NOGH_PATH" command -v jq >/dev/null 2>&1; then
  echo "  SKIP (no-gh) system PATH lacks jq — the script could not reach the gh check"
else
  D7="$TMP/case-no-gh"
  mkdir -p "$D7/state" "$D7/home"
  cp "$FIX/state-two-runs-B.json" "$D7/state/cost-identity-selftest.json"
  printf '%s\n' '{"tracker":{"bot":{"enabled":false}}}' > "$D7/second-shift.config.json"
  PATH="$NOGH_PATH" \
  HOME="$D7/home" \
  OTEL_METRICS_FILE="$METRICS" \
  SECOND_SHIFT_CONFIG="$D7/second-shift.config.json" \
  STATECTL_STATE_DIR="$D7/state" \
  COST_LOG_FILE="$D7/cost-log.jsonl" \
    bash "$SCRIPT" cost-identity-selftest >/dev/null 2>&1
  R7="$(jq -r '.costBlockApplied' "$D7/state/cost-identity-selftest.json")"
  [[ "$R7" == "skipped-no-gh-cli" ]] \
    && ok "(no-gh) absent gh CLI records skipped-no-gh-cli, not skipped-otel-error" \
    || bad "(no-gh) recorded '$R7', expected skipped-no-gh-cli"
fi

echo
echo "=== #188: fail-loud skips (no bare null) ==="
# (AC-1) no-PRs: state resolves and has sessions+cost, but prs is empty. The script
# must RECORD skipped-no-prs (not exit silently), leaving a breadcrumb instead of
# a bare null. Drive the real script with a stubbed GH_BOT; the record happens
# before any PR I/O so no gh stubbing is needed.
D8="$TMP/case-no-prs"
mkdir -p "$D8"
jq '.prs = {}' "$FIX/state-two-runs-B.json" > "$D8/noprs.json"
OTEL_METRICS_FILE="$METRICS" \
STATECTL_STATE_DIR="$D8" \
GH_BOT="$STUB_BOT" \
  bash "$SCRIPT" noprs >/dev/null 2>&1
R8_RC=$?
R8="$(jq -r '.costBlockApplied' "$D8/noprs.json")"
[[ "$R8" == "skipped-no-prs" ]] \
  && ok "(AC-1) no-PRs run records skipped-no-prs (never bare null)" \
  || bad "(AC-1) recorded '$R8', expected skipped-no-prs"
[[ "$R8_RC" -eq 0 ]] \
  && ok "(AC-1) no-PRs run exits 0 (recorded skip is not a failure)" \
  || bad "(AC-1) no-PRs run exited $R8_RC, expected 0"

# (AC-1) no-state: the resolved state file does not exist, so nothing can be
# recorded. The script must fail LOUD — non-zero (rc 2) — not the old silent exit 0
# that left the control repo's real state file at costBlockApplied:null (#188).
D9_EMPTY="$TMP/case-no-state"   # dir exists, but no <issue>.json inside it
mkdir -p "$D9_EMPTY"
OTEL_METRICS_FILE="$METRICS" \
STATECTL_STATE_DIR="$D9_EMPTY" \
GH_BOT="$STUB_BOT" \
  bash "$SCRIPT" 424242 >/dev/null 2>&1
R9_RC=$?
[[ "$R9_RC" -eq 2 ]] \
  && ok "(AC-1) unresolvable state exits non-zero (rc 2), fails loud" \
  || bad "(AC-1) no-state run exited $R9_RC, expected 2"

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1

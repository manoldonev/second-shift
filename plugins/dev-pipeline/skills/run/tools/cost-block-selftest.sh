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
# Cost in whole cents for one tier (summed across labels), so assertions never compare
# IEEE-754 artifacts: the cross-vendor fixture's unknown bucket sums to
# 0.15000000000000002, and its total to 0.8000000000000002.
tier_cents() { jq -r --arg t "$1" '(([.byLabel[] | select(.tier==$t) | .cost_usd] | add) // 0) * 100 | round'; }

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

  # (#357) This fixture's ids are the shipped map's ORACLE, not decoration: run A's whole
  # \$1.00 carries model claude-opus-4-7, so it must land in `reasoning`. Drop opus from the
  # map — or key the map on the dispatch alphabet, which cannot classify a resolved id — and
  # this reads 0 with the cost sitting in `unknown` instead.
  A_REASONING="$(tier_cents reasoning <<<"$A_ROLLUP")"
  [[ "$A_REASONING" == "100" ]] \
    && ok "(#357) run A's \$1.00 (claude-opus-4-7) tiers to 'reasoning'" \
    || bad "(#357) run A 'reasoning' expected 100 cents, got $A_REASONING"
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

  # (#357) The map's second oracle: every one of run B's three datapoints carries model
  # claude-sonnet-4-6, so the whole \$0.45 must land in `code` — across three DIFFERENT stage
  # labels, which is also what proves the tier is a bucket key independent of the label axis.
  B_CODE="$(tier_cents code <<<"$B_ROLLUP")"
  [[ "$B_CODE" == "45" ]] \
    && ok "(#357) run B's \$0.45 (claude-sonnet-4-6, 3 labels) tiers to 'code'" \
    || bad "(#357) run B 'code' expected 45 cents, got $B_CODE"
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

# Same contract as make_gh_stub, plus: on any invocation it copies the value passed to
# --body-file to $3. The rendered cost block exists nowhere else — render_block's output
# goes straight into the amend payload — so this is how a case asserts on the TABLE (#357's
# Tier column and its render filter) rather than on the rollup behind it.
#   $1 destination path   $2 argv log path   $3 captured body path
make_gh_capture_stub() {
  cat > "$1" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$2"
if [ "\${1:-}" = "pr" ] && [ "\${2:-}" = "view" ]; then
  echo "existing body without the marker"
fi
_prev=""
for _a in "\$@"; do
  if [ "\$_prev" = "--body-file" ]; then cp "\$_a" "$3"; fi
  _prev="\$_a"
done
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
echo "=== AC-8: state-less mode (run-lean) is ADDITIVE ==="
# The mode's whole safety claim is that it changes nothing for state-file callers — every
# case above already exercised those paths. These assert the new one, and critically that
# it writes NO cost-log row and needs no state.
MINI_METRICS="$FIX/single-session-mini.jsonl"
MINI_SESSION="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
SL_OUT="$TMP/stateless-block.md"
SL_LOG="$TMP/stateless-cost-log.jsonl"

OTEL_METRICS_FILE="$MINI_METRICS" COST_LOG_FILE="$SL_LOG" \
  bash "$SCRIPT" --stateless --sessions "$MINI_SESSION" \
    --start "2026-05-01T00:00:00Z" --end "2026-06-01T00:00:00Z" --out "$SL_OUT" >/dev/null 2>&1
SL_RC=$?
[[ "$SL_RC" -eq 0 ]] \
  && ok "(AC-8) state-less mode exits 0 with no state file present" \
  || bad "(AC-8) state-less mode exited $SL_RC, expected 0"

{ [[ -s "$SL_OUT" ]] && grep -q 'Pipeline Cost' "$SL_OUT"; } \
  && ok "(AC-8) --out receives the rendered cost block" \
  || bad "(AC-8) --out did not receive a rendered block"

# The session total must carry the real fixture cost — the same collector query and pricing
# math as the state-file path. One instrument, not a second implementation.
grep -q '0\.50' "$SL_OUT" 2>/dev/null \
  && ok "(AC-8) state-less totals use the same collector query and pricing math" \
  || bad "(AC-8) expected the fixture's 0.50 session total in the emitted block"

# Session-window totals ONLY: lean has no stage windows, so a per-stage table would be a
# fabrication rather than a degraded view.
{ grep -q 'Session total' "$SL_OUT" 2>/dev/null \
  && ! grep -qE '^\| (Intake|Plan|Implementation|Verify) ' "$SL_OUT" 2>/dev/null; } \
  && ok "(AC-8) emits session-window totals only (no per-stage table)" \
  || bad "(AC-8) state-less block should carry no per-stage rows"

# (#357) The session-total layout carries a TIER LIST, and it runs through the same render
# filter as the per-stage table. This fixture's four token rows carry no `model`, so an
# unfiltered list would read "reasoning, unknown" — advertising a bucket that cost nothing
# and names nothing. The single \$0.50 cost row is claude-opus-4-7, so the cell is exactly
# "reasoning", which also makes this fixture an oracle for the map's opus entry.
# shellcheck disable=SC2016 # $0.50 is a rendered dollar amount, not a shell expansion
grep -qE '^\| Session total \(.*\) \| reasoning \| claude-opus-4-7 \| \$0\.50 \|$' "$SL_OUT" 2>/dev/null \
  && ok "(#357) the session-total row's tier list is filtered and reads 'reasoning'" \
  || bad "(#357) session-total tier cell should be exactly 'reasoning'"

# D-36: lean runs are out of the perf corpus, so a row here would silently contaminate
# cross-run analytics with a harness that has no stages.
[[ ! -s "$SL_LOG" ]] \
  && ok "(AC-8) state-less mode writes NO cost-log.jsonl row (D-36 corpus hygiene)" \
  || bad "(AC-8) state-less mode wrote a cost-log row: $(cat "$SL_LOG")"

# Both inputs are REQUIRED, not optional: without a fence, session-only attribution inhales
# every co-resident datapoint from a long-lived interactive session.
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

# The flag must be parsed AHEAD of the required positional: `${1:?usage}` is evaluated
# before any flag handling, so a state-less call with no issue number would otherwise die
# on a usage error before ever reaching its own mode.
OTEL_METRICS_FILE="$MINI_METRICS" \
  bash "$SCRIPT" --stateless --sessions "$MINI_SESSION" \
    --start "2026-05-01T00:00:00Z" --end "2026-06-01T00:00:00Z" >/dev/null 2>&1
[[ $? -eq 0 ]] \
  && ok "(AC-8) --stateless needs no issue positional (flags parsed before the required \$1)" \
  || bad "(AC-8) state-less mode still requires the issue positional"

echo
echo "=== #357: tier bucketing is vendor-neutral ==="
#
# The cross-vendor fixture is the kill criterion the suite lacked entirely: before this,
# `grep -c model` over this file returned 0, so no assertion could fail on vendor coupling.
# Its five cost datapoints sit in ONE stage window, so tier is the only axis that can split
# them — three Anthropic families the default map covers, one non-Anthropic id it does not,
# and one datapoint carrying no `model` attribute at all. Two further datapoints in two
# other windows give the render filter both of its cases.
XV_METRICS="$FIX/cross-vendor.jsonl"
XV_ID="cost-cross-vendor-selftest"
XV_DIR="$TMP/case-cross-vendor"
XV_BODY="$XV_DIR/pr-body.md"
mkdir -p "$XV_DIR/bin" "$XV_DIR/state" "$XV_DIR/home"
cp "$FIX/state-cross-vendor.json" "$XV_DIR/state/$XV_ID.json"
printf '%s\n' '{"tracker":{"bot":{"enabled":false}}}' > "$XV_DIR/second-shift.config.json"
make_gh_capture_stub "$XV_DIR/bin/gh" "$XV_DIR/gh.log" "$XV_BODY"

XV_ROLLUP="$(OTEL_METRICS_FILE="$XV_METRICS" \
  SECOND_SHIFT_CONFIG="$XV_DIR/second-shift.config.json" \
  STATECTL_STATE_DIR="$XV_DIR/state" \
  COST_BLOCK_DUMP_ROLLUP=1 \
    bash "$SCRIPT" "$XV_ID" 2>/dev/null)"

if [[ -z "$XV_ROLLUP" ]] || ! jq -e . >/dev/null 2>&1 <<<"$XV_ROLLUP"; then
  bad "(#357) cross-vendor fixture produced no valid rollup JSON"
else
  # The split, and its ORDER. One stage label, four tiers, in the tier order the script
  # declares — so a row set that permutes between runs (or collapses back onto the label
  # axis) fails here rather than churning a PR body nobody diffs.
  XV_TIERS="$(jq -r '[.byLabel[] | select(.label=="Implementation") | .tier] | join(",")' <<<"$XV_ROLLUP")"
  [[ "$XV_TIERS" == "reasoning,code,emit,unknown" ]] \
    && ok "(#357) one label splits into 4 deterministically ordered tier rows" \
    || bad "(#357) Implementation tiers expected 'reasoning,code,emit,unknown', got '$XV_TIERS'"

  # Each Anthropic family the default map covers, classified. Together with run A's opus and
  # run B's sonnet above, every entry of the shipped map now has an oracle.
  XV_R="$(tier_cents reasoning <<<"$XV_ROLLUP")"
  XV_C="$(tier_cents code <<<"$XV_ROLLUP")"
  XV_E="$(tier_cents emit <<<"$XV_ROLLUP")"
  [[ "$XV_R" == "40" && "$XV_C" == "20" && "$XV_E" == "5" ]] \
    && ok "(#357) opus/sonnet/haiku ids map to reasoning/code/emit (40/20/5 cents)" \
    || bad "(#357) expected 40/20/5 cents for reasoning/code/emit, got $XV_R/$XV_C/$XV_E"

  # The `unknown` fallback carries BOTH kinds of unclassifiable datapoint, and the two
  # amounts are deliberately distinct so one assertion separates all three failures:
  # 15 = both present, 10 = the attribute-less \$0.05 was dropped, 5 = the unmatched vendor
  # id was mis-tiered into a real tier.
  XV_U="$(tier_cents unknown <<<"$XV_ROLLUP")"
  [[ "$XV_U" == "15" ]] \
    && ok "(#357) unmatched vendor id AND attribute-less datapoint both bucket to 'unknown'" \
    || bad "(#357) 'unknown' expected 15 cents (10 unmatched + 5 attribute-less), got $XV_U"

  # Totality, stated directly: the per-tier rows must account for every dollar the run's
  # total claims. A partial tier key leaves cost in the total and out of the table.
  XV_SUM="$(jq -r '(([.byLabel[].cost_usd] | add) // 0) * 100 | round' <<<"$XV_ROLLUP")"
  XV_TOT="$(jq -r '.totals.cost_usd * 100 | round' <<<"$XV_ROLLUP")"
  [[ "$XV_SUM" == "80" && "$XV_TOT" == "80" ]] \
    && ok "(#357) per-tier rows sum to the run total (80 cents) — no cost escapes the key" \
    || bad "(#357) byLabel sums to $XV_SUM cents, totals says $XV_TOT, expected 80/80"

  # `models` survives as the SECONDARY field the issue asks for — the tier is the bucket
  # key, not a replacement for the id. The attribute-less datapoint contributes nothing
  # here, which is exactly why `unknown` shows only the unmatched vendor id.
  XV_MODELS="$(jq -r '[.byLabel[] | select(.label=="Implementation") | (.models | join("+"))] | join(",")' <<<"$XV_ROLLUP")"
  [[ "$XV_MODELS" == "claude-opus-4-7,claude-sonnet-4-6,claude-haiku-4-5-20251001,mistral-large-2" ]] \
    && ok "(#357) each tier row keeps its own 'models' set as the secondary field" \
    || bad "(#357) per-tier models expected the 4 fixture ids in tier order, got '$XV_MODELS'"

  # The rollup stays TOTAL: the zero-cost, model-less group the renderer drops is still a
  # row here (and in the cost-log). Deleting it at the rollup instead would be the easy fix
  # and the wrong one — the durable record would then disagree with the datapoint set.
  XV_CR="$(jq -r '[.byLabel[] | select(.label=="Code Review")] | length' <<<"$XV_ROLLUP")"
  [[ "$XV_CR" == "1" ]] \
    && ok "(#357) the zero-cost model-less group IS present in the rollup (stays total)" \
    || bad "(#357) expected 1 'Code Review' rollup row, got $XV_CR"
fi

# Full path, no dump hook: renders the block into the amend payload and writes the cost-log
# row. Both artifacts are asserted below.
PATH="$XV_DIR/bin:$PATH" \
HOME="$XV_DIR/home" \
OTEL_METRICS_FILE="$XV_METRICS" \
SECOND_SHIFT_CONFIG="$XV_DIR/second-shift.config.json" \
STATECTL_STATE_DIR="$XV_DIR/state" \
COST_LOG_FILE="$XV_DIR/cost-log.jsonl" \
  bash "$SCRIPT" "$XV_ID" >/dev/null 2>&1

if [[ ! -s "$XV_BODY" ]]; then
  bad "(#357) no PR body was captured — the amend never reached the stubbed gh"
else
  grep -qF '| Stage | Tier | Models | Cost (USD) |' "$XV_BODY" \
    && ok "(#357) the rendered per-stage table carries a Tier column" \
    || bad "(#357) rendered table header is missing the Tier column"

  # shellcheck disable=SC2016 # $0.40 is a rendered dollar amount, not a shell expansion
  grep -qE '^\| Implementation \| reasoning \| claude-opus-4-7 \| \$0\.40 \|$' "$XV_BODY" \
    && ok "(#357) a rendered row reads (label, tier, models, cost)" \
    || bad "(#357) expected '| Implementation | reasoning | claude-opus-4-7 | \$0.40 |'"

  # shellcheck disable=SC2016 # $0.15 is a rendered dollar amount, not a shell expansion
  grep -qE '^\| Implementation \| unknown \| mistral-large-2 \| \$0\.15 \|$' "$XV_BODY" \
    && ok "(#357) the unknown bucket renders its unmatched id and its full \$0.15" \
    || bad "(#357) expected '| Implementation | unknown | mistral-large-2 | \$0.15 |'"

  # The render filter, both directions. A zero-cost row that NAMES a model still reports
  # something (which model was active in that stage) and is kept; a zero-cost row with no
  # model at all reports nothing and is dropped. Live telemetry emits whole metric families
  # with no `model`, so without the drop every label gains a \$0.00 companion row.
  # shellcheck disable=SC2016 # $0.00 is a rendered dollar amount, not a shell expansion
  grep -qE '^\| Doc Update \| code \| claude-sonnet-4-6 \| \$0\.00 \|$' "$XV_BODY" \
    && ok "(#357) a zero-cost row that names a model is KEPT" \
    || bad "(#357) the zero-cost Doc Update/code row was dropped"

  grep -qE '^\| Code Review \|' "$XV_BODY" \
    && bad "(#357) the zero-cost model-less row leaked into the rendered table" \
    || ok "(#357) the zero-cost model-less row is omitted from the rendered table"

  # The total row must keep the table rectangular now that a column was added.
  # shellcheck disable=SC2016 # $0.80 is a rendered dollar amount, not a shell expansion
  grep -qF '| **Total** | | | **$0.80** |' "$XV_BODY" \
    && ok "(#357) the Total row carries the added column and the full \$0.80" \
    || bad "(#357) expected '| **Total** | | | **\$0.80** |'"
fi

XV_LOGROW="$(tail -n 1 "$XV_DIR/cost-log.jsonl" 2>/dev/null)"
if [[ -z "$XV_LOGROW" ]] || ! jq -e . >/dev/null 2>&1 <<<"$XV_LOGROW"; then
  bad "(#357) no valid cost-log row was written"
else
  XV_ROW_TIERS="$(jq -r '(.tiers // ["MISSING"]) | join(",")' <<<"$XV_LOGROW")"
  [[ "$XV_ROW_TIERS" == "code,emit,reasoning,unknown" ]] \
    && ok "(#357) the cost-log row carries a top-level 'tiers' array" \
    || bad "(#357) cost-log .tiers expected 'code,emit,reasoning,unknown', got '$XV_ROW_TIERS'"

  # Additive: `models` keeps its exact prior shape beside the new key.
  XV_ROW_MODELS="$(jq -r '(.models // ["MISSING"]) | join(",")' <<<"$XV_LOGROW")"
  [[ "$XV_ROW_MODELS" == "claude-haiku-4-5-20251001,claude-opus-4-7,claude-sonnet-4-6,mistral-large-2" ]] \
    && ok "(#357) the cost-log row's 'models' array is unchanged beside 'tiers'" \
    || bad "(#357) cost-log .models changed shape: '$XV_ROW_MODELS'"
fi

echo
echo "=== #357/D-8: --help prints the whole header and none of the code ==="
# The range in the -h branch is hand-maintained and was already off by one (it stopped at
# 26 while the header ran to 27, truncating mid-sentence). The oracle is DERIVED from the
# file — where the comment block actually ends — so this assertion cannot rot the next time
# the header grows, which is the failure mode that produced the off-by-one.
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

if [[ -n "$FIRST_CODE" ]] && printf '%s\n' "$HELP_OUT" | grep -qF -- "$FIRST_CODE"; then
  bad "(D-8) --help leaked the first line of code ('$FIRST_CODE')"
else
  ok "(D-8) --help stops before the first line of code"
fi

echo
echo "=== #432: rotated backups, and the four-way skip discrimination ==="
# Two bugs shared one symptom — an empty cost block — and one message that named neither.
#
#   1. METRICS_FILE resolved to the live file ONLY, while the shipped exporter rotates at 50 MB
#      to `metrics-<ts>-size.jsonl`. Any run whose window predated the newest rotation was
#      silently unattributable EVEN WITH TELEMETRY ON.
#   2. The skip branch keyed on TOTAL_COST being zero and blamed "the collector … or session ids
#      drifted" — the two things that are almost never the cause. The real one (the session was
#      launched without CLAUDE_CODE_ENABLE_TELEMETRY and exported nothing) had no value of its own.
#
# WHY THE MTIME/FILENAME DISAGREEMENT BELOW IS DELIBERATE: the exporter writes those filenames
# with `localtime: true`, so the timestamp in the name is LOCAL while the fence is ISO-8601 `Z`.
# An implementation that selects on the filename reads correct in UTC and wrong everywhere else.
# Each rotation fixture is therefore named to suggest the OPPOSITE of what its mtime says, so a
# filename-parsing implementation fails these cases in every timezone, including UTC.
# `-u` matters here for the same reason it does in the script: without it BSD `date -j -f` reads
# a `Z` timestamp as local time, and every fixture datapoint lands one tz offset away from where
# the case says it is — green in UTC, red on the machines this actually runs on.
iso2ep() { date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null; }
set_mtime() { # set_mtime <file> <iso> — `date -r` means "reference file" on GNU, so it falls through
  local ep stamp
  ep="$(iso2ep "$2")"
  stamp="$(date -r "$ep" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$ep" +%Y%m%d%H%M.%S 2>/dev/null)"
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
# mk_state <dir> <id> <sid> <startedAt|""> <lastUpdatedAt> — no stages, so the rollup renders the
# single-row session total and every row buckets to "Other". An empty startedAt disables the fence.
mk_state() {
  local d="$1" id="$2" sid="$3" started="$4" last="$5"
  mkdir -p "$d"
  jq -n --arg sid "$sid" --arg s "$started" --arg l "$last" '
    { pipelineSessions: [{sessionId: $sid}],
      stages: {},
      prs: {},
      lastUpdatedAt: $l }
    | if $s == "" then . else .startedAt = $s end' > "$d/$id.json"
}

SID_A="aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"   # this run
SID_B="bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"   # a concurrent session in another repo
F_LO="2026-05-01T10:00:00Z"
F_HI="2026-05-01T11:00:00Z"

# dump_total <state-dir> <id> <metrics-file> — the fenced rollup total, via the DUMP_ROLLUP hook.
dump_total() {
  OTEL_METRICS_FILE="$3" STATECTL_STATE_DIR="$1" COST_BLOCK_DUMP_ROLLUP=1 GH_BOT="$STUB_BOT" \
    bash "$SCRIPT" "$2" 2>/dev/null | jq -r '.totals.cost_usd'
}
# disc <state-dir> <id> <metrics-file> — the recorded costBlockApplied.
# COST_BLOCK_DUMP_LOGROW is set purely to skip the script's 5s collector-flush sleep: every branch
# under test exits BEFORE the log-row hook is reached, so it changes no outcome here.
disc() {
  OTEL_METRICS_FILE="$3" STATECTL_STATE_DIR="$1" COST_BLOCK_DUMP_LOGROW=1 \
  COST_LOG_FILE="$TMP/disc-cost-log.jsonl" GH_BOT="$STUB_BOT" \
    bash "$SCRIPT" "$2" >/dev/null 2>&1
  jq -r '.costBlockApplied' "$1/$2.json"
}

# --- rotation: a backup whose MTIME covers the fence is read ------------------
ROT="$TMP/rot-covered"; mkdir -p "$ROT/metrics"
mk_metrics "$ROT/metrics/metrics.jsonl" claude_code.cost.usage "$SID_A:2026-05-01T10:50:00Z:0.20"
# Filename says 09:00 (before the fence); mtime says 10:20 (inside it). mtime must win.
mk_metrics "$ROT/metrics/metrics-2026-05-01T09-00-00.000-size.jsonl" claude_code.cost.usage \
  "$SID_A:2026-05-01T10:10:00Z:1.00"
set_mtime "$ROT/metrics/metrics-2026-05-01T09-00-00.000-size.jsonl" "2026-05-01T10:20:00Z"
mk_state "$ROT/state" rot-covered "$SID_A" "$F_LO" "$F_HI"
T="$(dump_total "$ROT/state" rot-covered "$ROT/metrics/metrics.jsonl")"
[[ "$T" == "1.2" || "$T" == "1.20" ]] \
  && ok "(#432) a rotated backup whose mtime covers the fence is read (total $T = live 0.20 + backup 1.00)" \
  || bad "(#432) expected 1.2 with the covering backup read, got '$T'"

# --- rotation: a backup whose MTIME predates the fence is NOT read ------------
ROT2="$TMP/rot-stale"; mkdir -p "$ROT2/metrics"
mk_metrics "$ROT2/metrics/metrics.jsonl" claude_code.cost.usage "$SID_A:2026-05-01T10:50:00Z:0.20"
# The mirror image: filename says 10:10 (inside the fence), mtime says 09:00 (before it). A backup
# stops being written at its mtime, so it cannot hold an in-fence row — skip it, and skip paying
# to slurp 50 MB for nothing.
mk_metrics "$ROT2/metrics/metrics-2026-05-01T10-10-00.000-size.jsonl" claude_code.cost.usage \
  "$SID_A:2026-05-01T10:10:00Z:1.00"
set_mtime "$ROT2/metrics/metrics-2026-05-01T10-10-00.000-size.jsonl" "2026-05-01T09:00:00Z"
mk_state "$ROT2/state" rot-stale "$SID_A" "$F_LO" "$F_HI"
T="$(dump_total "$ROT2/state" rot-stale "$ROT2/metrics/metrics.jsonl")"
[[ "$T" == "0.2" || "$T" == "0.20" ]] \
  && ok "(#432) a backup whose mtime predates the fence is skipped (total $T, the live file alone)" \
  || bad "(#432) expected 0.2 with the stale backup skipped, got '$T'"

# --- rotation: fence disabled → the live file alone, no window to cover -------
ROT3="$TMP/rot-nofence"; mkdir -p "$ROT3/metrics"
cp "$ROT/metrics/metrics.jsonl" "$ROT3/metrics/metrics.jsonl"
cp "$ROT/metrics/metrics-2026-05-01T09-00-00.000-size.jsonl" \
   "$ROT3/metrics/metrics-2026-05-01T09-00-00.000-size.jsonl"
set_mtime "$ROT3/metrics/metrics-2026-05-01T09-00-00.000-size.jsonl" "2026-05-01T10:20:00Z"
mk_state "$ROT3/state" rot-nofence "$SID_A" "" "$F_HI"   # no startedAt → the fence disables itself
T="$(dump_total "$ROT3/state" rot-nofence "$ROT3/metrics/metrics.jsonl")"
[[ "$T" == "0.2" || "$T" == "0.20" ]] \
  && ok "(#432) a disabled fence reads the live file alone (total $T) — no window means no backups to select" \
  || bad "(#432) expected 0.2 on the fence-disabled path, got '$T'"

# --- discrimination: nothing in the fence, from anyone -----------------------
DSC="$TMP/disc"; mkdir -p "$DSC/m1" "$DSC/m2" "$DSC/m3" "$DSC/m4"
mk_metrics "$DSC/m1/metrics.jsonl" claude_code.cost.usage "$SID_B:2026-05-01T09:00:00Z:1.00"
mk_state "$DSC/s1" d1 "$SID_A" "$F_LO" "$F_HI"
R="$(disc "$DSC/s1" d1 "$DSC/m1/metrics.jsonl")"
[[ "$R" == "skipped-telemetry-off" ]] \
  && ok "(#432) no in-fence rows from ANY session records skipped-telemetry-off" \
  || bad "(#432) expected skipped-telemetry-off, got '$R'"

# --- discrimination: the fence is populated, but not by us -------------------
# One row apart from the case above: the 09:00 row keeps the oldest scanned datapoint BEFORE the
# fence, so coverage is not in doubt and the honest verdict is "this session exported nothing".
mk_metrics "$DSC/m2/metrics.jsonl" claude_code.cost.usage \
  "$SID_B:2026-05-01T09:00:00Z:1.00" "$SID_B:2026-05-01T10:30:00Z:2.00"
mk_state "$DSC/s2" d2 "$SID_A" "$F_LO" "$F_HI"
R="$(disc "$DSC/s2" d2 "$DSC/m2/metrics.jsonl")"
[[ "$R" == "skipped-session-not-exporting" ]] \
  && ok "(#432) in-fence rows from other sessions only records skipped-session-not-exporting" \
  || bad "(#432) expected skipped-session-not-exporting, got '$R'"

# --- discrimination: the coverage of the window itself is gone --------------
# Same in-fence foreign row as above, minus the 09:00 one — now the oldest datapoint on disk is
# NEWER than the run start, so the file that covered the run is gone and no other verdict can be
# trusted. This also pins the PRECEDENCE: in-fence foreign rows exist here too, and rotated-out
# must still win over the not-exporting verdict.
mk_metrics "$DSC/m3/metrics.jsonl" claude_code.cost.usage "$SID_B:2026-05-01T10:30:00Z:2.00"
mk_state "$DSC/s3" d3 "$SID_A" "$F_LO" "$F_HI"
R="$(disc "$DSC/s3" d3 "$DSC/m3/metrics.jsonl")"
[[ "$R" == "skipped-rotated-out" ]] \
  && ok "(#432) retained metrics starting after the fence records skipped-rotated-out, ahead of the not-exporting verdict" \
  || bad "(#432) expected skipped-rotated-out, got '$R'"

# --- discrimination: our rows are there, they just carry no cost ------------
# The narrowed meaning of the value that used to absorb all four states: token rows for THIS
# session, inside the fence, and not one claude_code.cost.usage among them.
mk_metrics "$DSC/m4/metrics.jsonl" claude_code.token.usage \
  "$SID_B:2026-05-01T09:00:00Z:10" "$SID_A:2026-05-01T10:30:00Z:500"
mk_state "$DSC/s4" d4 "$SID_A" "$F_LO" "$F_HI"
R="$(disc "$DSC/s4" d4 "$DSC/m4/metrics.jsonl")"
[[ "$R" == "skipped-zero-datapoints" ]] \
  && ok "(#432) in-fence rows for this session with no cost datapoint records skipped-zero-datapoints" \
  || bad "(#432) expected skipped-zero-datapoints, got '$R'"

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1

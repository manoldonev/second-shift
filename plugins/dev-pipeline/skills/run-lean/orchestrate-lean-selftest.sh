#!/usr/bin/env bash
# orchestrate-lean-selftest.sh — proves orchestrate-lean.sh, the lean lane's scheduler.
#
# Tier justification (CLAUDE.md's map): one script's behavior against fixtures ⇒ a per-tool
# behavioral selftest. What it guards is the loop's CONTROL FLOW — preflight's reject-and-stop,
# the round budget's two hard-stop routes, spawn hygiene, and the zero-write posture. No
# scenario in scenario-liveness-selftest.sh covers it: the scenarios compose a single run's
# progress-line chain against the real gate, where every case here is about what the scheduler
# does BETWEEN two sessions, which no single-session composition can reach.
#
# ZERO NETWORK, ZERO MODEL. Every seam is an env override with a shipped default pointing at the
# real thing — `LEAN_SPAWN_BIN` (the session binary), `LEAN_GATE` (the milestone gate) and
# `${GH:-gh}` — so the whole suite drives fakes that RECORD what they were given. That is also
# this suite's honest ceiling, stated rather than papered over: it proves the scheduler's loop,
# and cannot prove that a real `claude -p` build session completes build-lean unattended. CI is
# model-free by design; that fidelity is provable only by an operator-run end-to-end.
#
# Anti-vacuity: the tool's existence is asserted up front with a distinct exit 2, and the fakes
# are asserted to have RECORDED something in the happy path before any absence-based case is
# scored — an absence assertion over a spawn log that was never written is not a pass.
#
# bash-3.2-safe; runs in CI via the '*-selftest.sh' discovery loop.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/orchestrate-lean.sh"

PASSES=0
FAILS=0
pass() { PASSES=$((PASSES + 1)); echo "  PASS: $1"; }
fail() { FAILS=$((FAILS + 1)); echo "  FAIL: $1" >&2; }

if [ ! -f "$TOOL" ]; then
  echo "FATAL: $TOOL does not exist — the suite has nothing to prove. This is the anti-vacuity guard." >&2
  exit 2
fi
if [ ! -f "$HERE/../build-lean/branch-prefix.sh" ]; then
  echo "FATAL: the sibling build-lean/branch-prefix.sh is absent — the tool sources it, so every case below would fail for the same uninformative reason." >&2
  exit 2
fi

# `pwd -P` because macOS resolves /var through a symlink to /private/var: the tool reports the
# worktree path git gives it, and an unresolved fixture path would make the cwd assertions below
# fail for a reason that has nothing to do with the tool.
WORK="$(mktemp -d -t orchestrate-lean-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
WORK="$(cd "$WORK" && pwd -P)"

ISSUE=7
BRANCH="claude/acme-$ISSUE"

# ---- the fixture repo, with a real lane worktree on the work branch -------------------------
# A real `git worktree` rather than a stub directory: the tool resolves the gate's cwd from
# `git worktree list --porcelain`, so a fixture that faked that answer would leave the one piece
# of git parsing in this script unexercised.
TREE="$WORK/tree"
mkdir -p "$TREE"
( cd "$TREE" \
  && git init -q . \
  && git config user.name selftest \
  && git config user.email selftest@example.invalid \
  && git config commit.gpgsign false \
  && git commit -q --allow-empty -m fixture \
  && git worktree add -q -b "$BRANCH" "$WORK/wt" HEAD ) >/dev/null 2>&1 \
  || { echo "FATAL: could not build the fixture repo." >&2; exit 2; }

CFG="$WORK/config.json"
cat > "$CFG" <<'JSON'
{ "configVersion": 2,
  "tracker": { "type": "github", "branchPrefix": "claude/acme-" } }
JSON

CFG_JIRA="$WORK/config-jira.json"
cat > "$CFG_JIRA" <<'JSON'
{ "configVersion": 2,
  "tracker": { "type": "jira", "branchPrefix": "claude/", "keyPattern": "ACME-[0-9]+" } }
JSON

CFG_BAD="$WORK/config-bad.json"
cat > "$CFG_BAD" <<'JSON'
{ "configVersion": 2, "tracker": { "type": "gitlab", "branchPrefix": "claude/acme-" } }
JSON

# ---- the fakes -------------------------------------------------------------------------------
# The session fake records ARGV and the two env vars the contract is about, one file per spawn,
# so ordering is assertable. Its exit code comes from a file the case writes, popped line by
# line, which is how a multi-round case scripts a failing session.
BIN="$WORK/bin"
mkdir -p "$BIN"
cat > "$BIN/claude" <<'SH'
#!/usr/bin/env bash
n=$(( $(cat "$SPAWN_LOG_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$SPAWN_LOG_DIR/count"
{
  echo "ARGV: $*"
  echo "RUN_ID_SET: ${RUN_ID+yes}"
  echo "LEAN_RUN_MODEL: ${LEAN_RUN_MODEL:-<unset>}"
  echo "SESSION_ID_SET: ${CLAUDE_CODE_SESSION_ID+yes}"
} > "$SPAWN_LOG_DIR/spawn-$n"
rc="$(sed -n "${n}p" "$SPAWN_RC_FILE" 2>/dev/null)"
exit "${rc:-0}"
SH
chmod +x "$BIN/claude"

# The tracker fake records EVERY invocation — that recording is what makes the zero-write
# assertion a measurement rather than a claim — and answers only the two reads the tool makes.
cat > "$BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "issue view") cat "$LABELS_FILE" 2>/dev/null; exit 0 ;;
  "pr list")    cat "$PR_FILE" 2>/dev/null ;;
  *) exit 1 ;;
esac
SH
chmod +x "$BIN/gh"

# The gate fake pops one exit code per call, so a case scripts `needs-work, needs-work, approve`
# as a three-line file. It also records its own cwd: the tool must run the gate from the lane
# WORKTREE, and a gate evaluated in the main checkout would read a different HEAD.
cat > "$BIN/fake-gate.sh" <<'SH'
#!/usr/bin/env bash
n=$(( $(cat "$GATE_LOG_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$GATE_LOG_DIR/count"
{ echo "ARGV: $*"; echo "CWD: $PWD"; echo "RUN_ID_SET: ${RUN_ID+yes}"; } > "$GATE_LOG_DIR/call-$n"
rc="$(sed -n "${n}p" "$GATE_RC_FILE" 2>/dev/null)"
exit "${rc:-0}"
SH
chmod +x "$BIN/fake-gate.sh"

# ---- the driver ------------------------------------------------------------------------------
# Every case starts from a clean set of logs so a stale spawn from the previous case cannot be
# scored as this case's.
SPAWN_LOG_DIR=""; GATE_LOG_DIR=""; GH_LOG=""; LABELS_FILE=""; PR_FILE=""
SPAWN_RC_FILE=""; GATE_RC_FILE=""
CASE_N=0

setup_case() { # setup_case <spawn-rcs> <gate-rcs> <labels> <pr>
  CASE_N=$((CASE_N + 1))
  local d="$WORK/case-$CASE_N"
  mkdir -p "$d/spawns" "$d/gates"
  SPAWN_LOG_DIR="$d/spawns"; GATE_LOG_DIR="$d/gates"; GH_LOG="$d/gh.log"
  LABELS_FILE="$d/labels"; PR_FILE="$d/pr"
  SPAWN_RC_FILE="$d/spawn-rcs"; GATE_RC_FILE="$d/gate-rcs"
  printf '%s' "$1" > "$SPAWN_RC_FILE"
  printf '%s' "$2" > "$GATE_RC_FILE"
  printf '%s' "$3" > "$LABELS_FILE"
  printf '%s' "$4" > "$PR_FILE"
  : > "$GH_LOG"
}

# RUN_ID and LEAN_RUN_MODEL are POISONED in the parent on purpose: they are ordinary env vars
# that DO inherit, and the whole scrub contract is invisible against a parent that never set them.
run_tool() { # run_tool [config] [args...]
  local cfg="$1"; shift
  local envs
  # An ARRAY, not a fixed assignment list, because one case below must run with GH genuinely
  # UNSET so the tool falls through to its own shipped default. `-u GH` precedes the
  # assignments, so the ordinary case still gets the fake.
  envs=( PATH="$BIN:$PATH"
         SECOND_SHIFT_CONFIG="$cfg"
         LEAN_SPAWN_BIN="${SPAWN_BIN_OVERRIDE:-$BIN/claude}"
         LEAN_GATE="$BIN/fake-gate.sh"
         SPAWN_LOG_DIR="$SPAWN_LOG_DIR" SPAWN_RC_FILE="$SPAWN_RC_FILE"
         GATE_LOG_DIR="$GATE_LOG_DIR" GATE_RC_FILE="$GATE_RC_FILE"
         GH_LOG="$GH_LOG" LABELS_FILE="$LABELS_FILE" PR_FILE="$PR_FILE"
         RUN_ID=poisoned-parent-run LEAN_RUN_MODEL=poisoned-parent-model )
  [ "${USE_DEFAULT_GH:-0}" -eq 1 ] || envs+=( GH="$BIN/gh" )
  ( cd "$TREE" \
    && env -u CLAUDE_CODE_SESSION_ID -u GH "${envs[@]}" bash "$TOOL" "$@" 2>&1 )
}

spawn_count() { cat "$SPAWN_LOG_DIR/count" 2>/dev/null || echo 0; }
gate_count()  { cat "$GATE_LOG_DIR/count" 2>/dev/null || echo 0; }
spawn_argv()  { sed -n 's/^ARGV: //p' "$SPAWN_LOG_DIR/spawn-$1" 2>/dev/null; }
all_argv()    { cat "$SPAWN_LOG_DIR"/spawn-* 2>/dev/null; }

echo "[orchestrate-lean-selftest]"

# ---- (a) usage: the scheduler refuses to size a ticket ---------------------------------------
setup_case "" "" "ready-for-dev" "5"
out="$(run_tool "$CFG" "$ISSUE")"; rc=$?
if [ "$rc" -eq 2 ] && grep -q -- '--build-model is required' <<<"$out" \
   && [ "$(spawn_count)" -eq 0 ]; then
  pass "(a) a missing --build-model is a usage refusal naming the label, and spawns nothing"
else fail "(a) expected rc=2 with no spawn, got rc=$rc / $(spawn_count) spawn(s): $out"; fi

# ---- (b) the happy path, and the POSITIVE CONTROL for every absence case below ---------------
# Scored first on purpose: cases (e)-(g) assert that something is NOT in a spawn log, and an
# empty log would satisfy them vacuously. This case proves the fakes record.
setup_case "" "0" "ready-for-dev
opus" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 3 ] && [ "$(gate_count)" -eq 1 ] \
   && grep -q 'build-lean 7' <<<"$(spawn_argv 1)" \
   && grep -q 'review-lean 11' <<<"$(spawn_argv 2)" \
   && grep -q 'build-lean 7' <<<"$(spawn_argv 3)"; then
  pass "(b) approve ⇒ BUILD → REVIEW(pr from the tracker) → close-out BUILD, exit 0"
else fail "(b) expected rc=0 with 3 spawns / 1 gate call, got rc=$rc / $(spawn_count) / $(gate_count): $out"; fi

if grep -q 'PR #11 is open' <<<"$out"; then
  pass "(b2) the PR number comes from the tracker, not from a convention"
else fail "(b2) the resolved PR was not reported: $out"; fi

# ---- (c) the gate runs in the lane WORKTREE, with no ambient run id --------------------------
if grep -q "^CWD: $WORK/wt$" "$GATE_LOG_DIR/call-1" 2>/dev/null \
   && grep -q '^ARGV: 4 7$' "$GATE_LOG_DIR/call-1" 2>/dev/null; then
  pass "(c1) the verdict gate is invoked as '4 <issue>' from the lane worktree, not the main checkout"
else fail "(c1) gate call 1 was wrong: $(cat "$GATE_LOG_DIR/call-1" 2>/dev/null)"; fi

if ! grep -q '^RUN_ID_SET: yes$' "$GATE_LOG_DIR/call-1" 2>/dev/null; then
  pass "(c2) the gate is called with RUN_ID unset, so it resolves the build run's cached id"
else fail "(c2) an ambient RUN_ID leaked into the verdict gate"; fi

# ---- (d) env hygiene on every spawn ----------------------------------------------------------
bad=0
for f in "$SPAWN_LOG_DIR"/spawn-*; do
  grep -q '^RUN_ID_SET: yes$' "$f" && bad=1
done
if [ "$bad" -eq 0 ]; then
  pass "(d1) RUN_ID is scrubbed from every spawned session, against a poisoned parent"
else fail "(d1) the parent's RUN_ID leaked into a spawned session"; fi

if grep -q '^LEAN_RUN_MODEL: sonnet$' "$SPAWN_LOG_DIR/spawn-1" \
   && grep -q '^LEAN_RUN_MODEL: opus$' "$SPAWN_LOG_DIR/spawn-2" \
   && grep -q '^LEAN_RUN_MODEL: sonnet$' "$SPAWN_LOG_DIR/spawn-3"; then
  pass "(d2) LEAN_RUN_MODEL is set per PHASE — build's model on build, review's on review"
else fail "(d2) LEAN_RUN_MODEL was not re-set per phase: $(grep -h LEAN_RUN_MODEL "$SPAWN_LOG_DIR"/spawn-*)"; fi

# ---- (e) fresh contexts, never a resumed one --------------------------------------------------
if grep -qE -- '(^| )-p ' <<<"$(all_argv)" \
   && grep -qE -- '(^| )--model ' <<<"$(all_argv)" \
   && ! grep -qE -- '--resume|--continue|(^| )-c( |$)' <<<"$(all_argv)"; then
  pass "(e1) every spawn is a fresh top-level session: -p + --model, no --resume/--continue/-c"
else fail "(e1) spawn argv carried a resume flag or lost -p/--model: $(all_argv)"; fi

# Driven with CLAUDE_CODE_SESSION_ID UNSET in the parent, so a `yes` here can only have come
# from the scheduler. Running it with the operator's own session id ambient would make this case
# pass or fail on the environment rather than on the code.
if ! grep -q '^SESSION_ID_SET: yes$' "$SPAWN_LOG_DIR"/spawn-* 2>/dev/null \
   && ! grep -q -- '--session-id' <<<"$(all_argv)"; then
  pass "(e2) no session id is set or passed down — the identity separation rests on the harness's own stamp"
else fail "(e2) the scheduler set or passed a session id on a spawned session"; fi

# ---- (f) the zero-write posture, measured ------------------------------------------------------
if [ -s "$GH_LOG" ] \
   && ! grep -qE 'issue (edit|comment|create|close)|pr (comment|edit|merge|create|review)|--method (POST|PATCH|PUT|DELETE)|-X (POST|PATCH|PUT|DELETE)' "$GH_LOG"; then
  pass "(f) across a full approved run the tracker CLI is READ-ONLY (issue view / pr list only)"
else fail "(f) the scheduler made a tracker write, or made no call at all: $(cat "$GH_LOG")"; fi

# ---- (g) preflight is a reject-and-stop, and reports EVERY failure at once ---------------------
setup_case "" "0" "" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'FAIL intake' <<<"$out" \
   && grep -q 'does not spawn an intake session' <<<"$out"; then
  pass "(g1) a ticket without the queue label is rejected before any spawn, naming the hand-back"
else fail "(g1) expected rc=2 with 0 spawns, got rc=$rc / $(spawn_count): $out"; fi

setup_case "" "0" "" "11"
SPAWN_BIN_OVERRIDE="$WORK/no-such-binary" \
  out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
unset SPAWN_BIN_OVERRIDE
if [ "$rc" -eq 2 ] \
   && grep -q 'FAIL intake' <<<"$out" \
   && grep -q 'FAIL spawn' <<<"$out"; then
  pass "(g2) two failing probes are BOTH reported from one invocation — no first-failure abort"
else fail "(g2) expected both probe failures in one run, got rc=$rc: $out"; fi

# The probes run concurrently. That is not directly observable from outside, so what is asserted
# is the property concurrency has to preserve and a serial short-circuit would not: the ok/FAIL
# verdict of every probe is present regardless of which ones failed.
setup_case "" "0" "ready-for-dev" "11"
SPAWN_BIN_OVERRIDE="$WORK/no-such-binary" \
  out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
unset SPAWN_BIN_OVERRIDE
if [ "$rc" -eq 2 ] \
   && grep -q 'ok intake' <<<"$out" \
   && grep -q 'FAIL spawn' <<<"$out" \
   && grep -q 'ok gate' <<<"$out"; then
  pass "(g3) all three probe verdicts are reported even when a middle one fails"
else fail "(g3) a probe verdict went missing: $out"; fi

# ---- (h) needs-work: a fix round and a NEW review context ---------------------------------------
setup_case "" "1
0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 5 ] && [ "$(gate_count)" -eq 2 ] \
   && grep -q 'build-lean 7' <<<"$(spawn_argv 3)" \
   && grep -q 'review-lean 11' <<<"$(spawn_argv 4)"; then
  pass "(h1) needs-work ⇒ a fresh fix BUILD then a fresh REVIEW, then close-out on the approve"
else fail "(h1) expected 5 spawns / 2 gate calls, got rc=$rc / $(spawn_count) / $(gate_count): $out"; fi

if ! grep -qE -- '--resume|--continue' <<<"$(spawn_argv 4)"; then
  pass "(h2) round 2's review is a NEW context, not round 1's resumed"
else fail "(h2) round 2's review resumed a context: $(spawn_argv 4)"; fi

# ---- (i) the two hard-stop routes ----------------------------------------------------------------
setup_case "" "4" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 4 ] && [ "$(spawn_count)" -eq 2 ] \
   && grep -q 'HARD STOP' <<<"$out" \
   && grep -q 'No rescue attempt' <<<"$out"; then
  pass "(i1) the gate's own rc=4 is a hard stop: no close-out, no fix round, no rescue"
else fail "(i1) expected rc=4 after 2 spawns, got rc=$rc / $(spawn_count): $out"; fi

# The second route exists because the gate's counter lives in a file a fix round can reset: a
# scheduler with no bound of its own would loop forever against a gate that only ever says 1.
setup_case "" "1
1
1
1
1" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --max-rounds 2)"; rc=$?
if [ "$rc" -eq 4 ] && [ "$(spawn_count)" -eq 4 ] && [ "$(gate_count)" -eq 2 ] \
   && grep -q '2 rounds spent' <<<"$out"; then
  pass "(i2) --max-rounds bounds the loop independently of the gate's own counter"
else fail "(i2) expected rc=4 after 2 rounds, got rc=$rc / $(spawn_count) spawn(s) / $(gate_count) gate call(s): $out"; fi

# ---- (j) a failing session is a phase failure, not a silent next round ----------------------------
setup_case "9" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 1 ] && [ "$(gate_count)" -eq 0 ] \
   && grep -q 'BUILD session failed' <<<"$out"; then
  pass "(j1) a nonzero BUILD session stops the run at exit 1 — the gate is never consulted"
else fail "(j1) expected rc=1 after 1 spawn, got rc=$rc / $(spawn_count): $out"; fi

setup_case "" "0" "ready-for-dev" ""
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 1 ] \
   && grep -q 'no open PR' <<<"$out"; then
  pass "(j2) a BUILD that left no open PR stops at exit 1 rather than reviewing nothing"
else fail "(j2) expected rc=1 on an absent PR, got rc=$rc: $out"; fi

# ---- (k) model resolution stays the caller's ------------------------------------------------------
# #490: a departure from the shipped review tier now requires a stated reason, so this case
# carries --review-model-basis alongside its --review-model override, where before it needed
# none — the case still proves the override itself reaches the spawn.
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model opus --review-model sonnet --model-basis 'sized-here: two gates' --review-model-basis 'sized-here: reviewer rate limited')"; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -q '^LEAN_RUN_MODEL: sonnet$' "$SPAWN_LOG_DIR/spawn-2" \
   && grep -q 'basis: sized-here: two gates' <<<"$out" \
   && grep -q 'basis: sized-here: reviewer rate limited' <<<"$out"; then
  pass "(k1) --review-model overrides the shipped default, and BOTH --model-basis and --review-model-basis are echoed into the run log"
else fail "(k1) review model or basis did not take: rc=$rc: $out"; fi

# A non-default --review-model with no --review-model-basis is a usage refusal, nothing spawned,
# and the message names the flag that resolves it — the AC-2 defect this ticket closes.
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --review-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q -- '--review-model-basis' <<<"$out" \
   && grep -q 'departs from the shipped default' <<<"$out"; then
  pass "(k2) a non-default --review-model with no --review-model-basis is a usage refusal naming the flag, nothing spawned"
else fail "(k2) expected rc=2 with 0 spawns, got rc=$rc / $(spawn_count): $out"; fi

# A stated departure is accepted: the override reaches the spawn and the reason is echoed.
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --review-model sonnet --review-model-basis 'sized-here: rate-limited on opus')"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 3 ] \
   && grep -q '^LEAN_RUN_MODEL: sonnet$' "$SPAWN_LOG_DIR/spawn-2" \
   && grep -q 'basis: sized-here: rate-limited on opus' <<<"$out"; then
  pass "(k3) a stated --review-model-basis is accepted: the departure reaches the spawn and the reason is echoed"
else fail "(k3) expected rc=0 with the departure taking and the basis echoed, got rc=$rc / $(spawn_count): $out"; fi

# The untouched happy path: omitting --review-model needs no basis, and the review spawn still
# gets the shipped default tier with no basis note in the log.
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^LEAN_RUN_MODEL: opus$' "$SPAWN_LOG_DIR/spawn-2" \
   && ! grep -q 'review model: opus (basis' <<<"$out"; then
  pass "(k4) omitting --review-model needs no basis, and the review spawn still gets the shipped default tier"
else fail "(k4) expected rc=0 with the review spawn on the default tier and no basis note, got rc=$rc: $out"; fi

# AC-3/AC-4: the default passed EXPLICITLY is the default, not a departure — no basis required.
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --review-model opus)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^LEAN_RUN_MODEL: opus$' "$SPAWN_LOG_DIR/spawn-2" \
   && ! grep -q 'review model: opus (basis' <<<"$out"; then
  pass "(k5) --review-model opus passed explicitly is the shipped default, not a departure — no basis required"
else fail "(k5) expected rc=0 with no basis required, got rc=$rc: $out"; fi

# AC-4: volunteering a basis for a default-tier review is accepted and echoed, never refused.
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --review-model opus --review-model-basis 'confirming default explicitly')"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'review model: opus (basis: confirming default explicitly)' <<<"$out"; then
  pass "(k6) a basis volunteered alongside the default-tier review is accepted and echoed, never refused"
else fail "(k6) expected rc=0 with the volunteered basis echoed, got rc=$rc: $out"; fi

# ---- (l) --dry-run prints the schedule and spawns nothing -------------------------------------------
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --dry-run)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 0 ] && [ "$(gate_count)" -eq 0 ] \
   && grep -q "branch=$BRANCH" <<<"$out"; then
  pass "(l) --dry-run reports the resolved branch and schedule without spawning"
else fail "(l) expected a spawn-free dry run, got rc=$rc / $(spawn_count): $out"; fi

# ---- (m) the tracker adapters -----------------------------------------------------------------------
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG_JIRA" ACME-7 --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'has no queue label' <<<"$out"; then
  pass "(m1) under a tracker with no queue label, intake cannot be read and the run is rejected"
else fail "(m1) expected a jira reject, got rc=$rc: $out"; fi

setup_case "" "0" "" "11"
out="$(run_tool "$CFG_JIRA" ACME-7 --build-model sonnet --intake-attested)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'build-lean ACME-7' <<<"$(spawn_argv 1)" \
   && grep -q "^CWD: $WORK/wt$" "$GATE_LOG_DIR/call-1" 2>/dev/null; then
  pass "(m2) --intake-attested carries the jira run: the key reaches the payload unlowercased while the BRANCH is lowercased"
else fail "(m2) expected an attested jira run, got rc=$rc: $out"; fi

setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG_BAD" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q "unrecognized tracker.type" <<<"$out"; then
  pass "(m3) an unrecognized tracker.type is a loud refusal, never a fall-through to an arm"
else fail "(m3) expected rc=2 on a bad tracker.type, got rc=$rc: $out"; fi

# ---- (m4) the SHIPPED default of the tracker seam ------------------------------------------------
# Every other case sets GH to the fake, which means every other case leaves `${GH:-gh}`'s own
# fallback unexercised — a seam whose default was mistyped would pass the entire suite. Here GH is
# unset and the fake is named `gh` on PATH, so the run only completes if the shipped default is
# the real CLI's name.
setup_case "" "0" "ready-for-dev" "11"
USE_DEFAULT_GH=1 out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
unset USE_DEFAULT_GH
if [ "$rc" -eq 0 ] && [ -s "$GH_LOG" ] && grep -q 'PR #11 is open' <<<"$out"; then
  pass "(m4) with GH unset the tool falls through to its shipped 'gh' default and still resolves the PR"
else fail "(m4) the shipped tracker-CLI default did not resolve, rc=$rc: $out"; fi

# ---- (n0) the front door's own line cap ---------------------------------------------------------------
# The same cap the payload skill carries, asserted the same way. A front door is read on every
# invocation of the lane, so anti-accretion is load-bearing here rather than tidy: the scheduler's
# rules are short because a long one would be skimmed.
SKILL="$HERE/SKILL.md"
if [ -f "$SKILL" ]; then
  lines="$(wc -l < "$SKILL" | tr -d ' ')"
  if [ "$lines" -le 60 ]; then pass "(n0) SKILL.md is $lines lines (<= 60, frontmatter included)"
  else fail "(n0) SKILL.md is $lines lines — the cap is 60 including frontmatter"; fi
else fail "(n0) SKILL.md not found at $SKILL"; fi

# ---- (n) --help prints the header and stops before the code ------------------------------------------
out="$(bash "$TOOL" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'Exit: 0 = approved' <<<"$out" \
   && ! grep -qF 'set -uo pipefail' <<<"$out"; then
  pass "(n) --help prints through the last header line and stops before the code"
else fail "(n) --help did not print exactly the header, rc=$rc: $out"; fi

echo "[orchestrate-lean-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

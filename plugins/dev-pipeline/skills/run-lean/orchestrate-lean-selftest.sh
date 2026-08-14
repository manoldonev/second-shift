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

# Ownership stamp for tools/reap-lean-fixtures.sh (#528). The expression is NOT repeated here —
# it lives in tools/fixture-stamp.sh, sourced by this producer and by the reaper that reads the
# stamp back, so the two cannot drift into an agreement that holds only on one `ps`. Optional:
# a shipped plugin install carries no tools/, and an unstamped name is the safe fallback.
STAMP_LIB="$HERE/../../../../tools/fixture-stamp.sh"
OWN_SEG=""
if [ -r "$STAMP_LIB" ]; then
  # shellcheck source=../../../../tools/fixture-stamp.sh
  . "$STAMP_LIB"
  OWN_SEG="$(fixture_stamp_own 2>/dev/null)" || OWN_SEG=""
fi

# TRAP INSTALLED BEFORE WORK EXISTS (#528), mirroring lean-gate-selftest.sh: the old order
# (mktemp, then trap) left a window where a signal orphaned WORK with nothing registered to
# remove it. cleanup() guards on WORK being set, so registering it first is safe.
# shellcheck disable=SC2317,SC2329  # invoked indirectly by the EXIT trap below.
# BOTH codes: shellcheck >=0.10 reports SC2329 on the function, 0.9 (CI) reports SC2317 on
# each command in the body — suppressing only the newer one is clean locally and reds CI.
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT
# `pwd -P` because macOS resolves /var through a symlink to /private/var: the tool reports the
# worktree path git gives it, and an unresolved fixture path would make the cwd assertions below
# fail for a reason that has nothing to do with the tool.
if [ -n "$OWN_SEG" ]; then
  WORK="$(mktemp -d -t "orchestrate-lean-selftest.$OWN_SEG.XXXXXX")"
else
  WORK="$(mktemp -d -t "orchestrate-lean-selftest.XXXXXX")"
fi
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
  # #515: the REAL gate's ticket arm asks this same subcommand for `--json state`, and the (v9)
  # composition drives it. Discriminated on the flag rather than served from a second arm, because
  # `issue view` is genuinely the call both make.
  "issue view")
    case "$*" in
      *--json\ state*) printf '%s\n' "${STATE_ANSWER:-OPEN}"; exit 0 ;;
    esac
    cat "$LABELS_FILE" 2>/dev/null; exit 0 ;;
  # #500: the comment trail, served as the REAL API's shape — a JSON array of objects carrying
  # `.user.type`. The tool reads it through `gh api` rather than `gh issue view --json comments`
  # precisely because only this response carries that field, so a fake that answered the trail on
  # the `issue view` arm would leave the tool's actual call unexercised.
  # COMMENTS_FAIL is the D-8 fixture: a read that errors, which must not read as "no marker".
  "api "*)
    [ -n "${COMMENTS_FAIL:-}" ] && exit 1
    cat "$COMMENTS_FILE" 2>/dev/null; exit 0 ;;
  "pr list")
    # #492: a PR that only APPEARS on a later spawn. Without this the tracker fake answers the
    # same thing for every spawn in a case, and the continuation path — whose whole subject is
    # "no PR yet, then a PR" — could not be scripted at all.
    if [ -n "${PR_FROM_SPAWN:-}" ]; then
      sc="$(cat "$SPAWN_LOG_DIR/count" 2>/dev/null || echo 0)"
      [ "$sc" -ge "$PR_FROM_SPAWN" ] || exit 0
    fi
    cat "$PR_FILE" 2>/dev/null ;;
  *) exit 1 ;;
esac
SH
chmod +x "$BIN/gh"

# The gate fake pops one exit code per call, so a case scripts `needs-work, needs-work, approve`
# as a three-line file. It also records its own cwd: the tool must run the gate from the lane
# WORKTREE, and a gate evaluated in the main checkout would read a different HEAD.
#
# #492's `progress` reads are served on a SEPARATE arm with their own counters and log. Folding
# them into `count` would silently re-number the gate-call assertion in every case above, turning
# a contract change into a suite-wide edit and hiding which numbers actually mean "verdict call".
cat > "$BIN/fake-gate.sh" <<'SH'
#!/usr/bin/env bash
# #515's `staleness` reads get a THIRD arm, with their own counters, log and rc streams — the same
# separation `progress` already has, and for the identical reason: folding them into `count` would
# re-number the gate-call assertion in every case above and hide which numbers mean "verdict call".
# The two call sites are split on `--arm`, so a case can script preflight's answer and the loop's
# independently; both default to 0, which is what keeps every pre-existing case meaning what it did.
if [ "${1:-}" = "staleness" ]; then
  case "$*" in
    *--arm*) k=ticket; f="$STALENESS_TICKET_RC_FILE" ;;
    *)       k=loop;   f="$STALENESS_RC_FILE" ;;
  esac
  n=$(( $(cat "$GATE_LOG_DIR/scount-$k" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$GATE_LOG_DIR/scount-$k"
  echo "ARGV: $* | CWD: $PWD | RUN_ID_SET: ${RUN_ID+yes}" >> "$GATE_LOG_DIR/staleness.log"
  echo "fake-gate: staleness/$k call $n"
  rc="$(sed -n "${n}p" "$f" 2>/dev/null)"
  exit "${rc:-0}"
fi
if [ "${1:-}" = "progress" ]; then
  [ -n "${PROGRESS_FAIL:-}" ] && exit 3
  # #527's `--infra` is a THIRD token space on the same subcommand, with its own counter and its
  # own scripted stream — never folded into `adv`. The tool compares each space against itself,
  # and a fake that served one stream to both could not express the case the feature is for: a
  # spawn where the continuation predicate is unmoved and the infra residue is not.
  # INFRA_FAIL is its own seam, so the fail-closed posture can be driven per-space: a broken
  # infra read must stop the run even while the ordinary progress read is answering fine.
  case "$*" in
    *--infra*)     k=infra; f="$PROGRESS_INFRA_FILE"
                   [ -n "${INFRA_FAIL:-}" ] && exit 3 ;;
    *--satisfied*) k=m5;  f="$PROGRESS_M5_FILE" ;;
    *)             k=adv; f="$PROGRESS_ADV_FILE" ;;
  esac
  n=$(( $(cat "$GATE_LOG_DIR/pcount-$k" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$GATE_LOG_DIR/pcount-$k"
  echo "ARGV: $* | CWD: $PWD | RUN_ID_SET: ${RUN_ID+yes}" >> "$GATE_LOG_DIR/progress.log"
  # Past the end of a scripted stream the LAST line repeats. A case that scripts two reads must
  # not have a third one invent a change the case never asked for — that would make the
  # continuation loop advance on the fake's exhaustion rather than on the tool's logic.
  line="$(sed -n "${n}p" "$f" 2>/dev/null)"
  [ -n "$line" ] && echo "$line" || tail -n 1 "$f" 2>/dev/null
  exit 0
fi
n=$(( $(cat "$GATE_LOG_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$GATE_LOG_DIR/count"
{ echo "ARGV: $*"; echo "CWD: $PWD"; echo "RUN_ID_SET: ${RUN_ID+yes}"
  echo "OBSERVE: ${LEAN_GATE_OBSERVE:-<unset>}"; } > "$GATE_LOG_DIR/call-$n"
# #496 AC-6, modelled at the seam the scheduler actually controls: the REAL gate appends a
# milestone-4 attempt line on every recording red, so a fake that is called WITHOUT the observe
# seam stands in for exactly that write. The gate suite owns the other half — that observe mode
# really does record nothing — so nothing here re-implements the gate's logic, it only records
# which mode it was asked for.
[ "${LEAN_GATE_OBSERVE:-0}" = "1" ] || echo "attempt $*" >> "$GATE_LOG_DIR/attempts"
rc="$(sed -n "${n}p" "$GATE_RC_FILE" 2>/dev/null)"
exit "${rc:-0}"
SH
chmod +x "$BIN/fake-gate.sh"

# ---- the driver ------------------------------------------------------------------------------
# Every case starts from a clean set of logs so a stale spawn from the previous case cannot be
# scored as this case's.
SPAWN_LOG_DIR=""; GATE_LOG_DIR=""; GH_LOG=""; LABELS_FILE=""; PR_FILE=""
SPAWN_RC_FILE=""; GATE_RC_FILE=""
PROGRESS_ADV_FILE=""; PROGRESS_M5_FILE=""; PROGRESS_INFRA_FILE=""; COMMENTS_FILE=""
STALENESS_RC_FILE=""; STALENESS_TICKET_RC_FILE=""
CASE_N=0

setup_case() { # setup_case <spawn-rcs> <gate-rcs> <labels> <pr>
  CASE_N=$((CASE_N + 1))
  local d="$WORK/case-$CASE_N"
  mkdir -p "$d/spawns" "$d/gates"
  SPAWN_LOG_DIR="$d/spawns"; GATE_LOG_DIR="$d/gates"; GH_LOG="$d/gh.log"
  LABELS_FILE="$d/labels"; PR_FILE="$d/pr"; COMMENTS_FILE="$d/comments"
  SPAWN_RC_FILE="$d/spawn-rcs"; GATE_RC_FILE="$d/gate-rcs"
  PROGRESS_ADV_FILE="$d/progress-adv"; PROGRESS_M5_FILE="$d/progress-m5"
  PROGRESS_INFRA_FILE="$d/progress-infra"
  # #515 DEFAULT: EMPTY streams, so every staleness read answers 0 and every pre-existing case
  # keeps meaning what it meant — a clean premise, checked and passed.
  STALENESS_RC_FILE="$d/staleness-rcs"; STALENESS_TICKET_RC_FILE="$d/staleness-ticket-rcs"
  : > "$STALENESS_RC_FILE"; : > "$STALENESS_TICKET_RC_FILE"
  printf '%s' "$1" > "$SPAWN_RC_FILE"
  printf '%s' "$2" > "$GATE_RC_FILE"
  printf '%s' "$3" > "$LABELS_FILE"
  printf '%s' "$4" > "$PR_FILE"
  # #500 DEFAULT: an EMPTY trail, so every pre-existing case means what it meant — a ticket with
  # no queue label and no claim marker is still the plain reject, not a re-entry.
  printf '[]\n' > "$COMMENTS_FILE"
  : > "$GH_LOG"
  # #492 DEFAULTS, chosen so every pre-existing case keeps meaning what it meant.
  #   adv: one line, so every read returns the same token — the run never "advances", which is
  #        what keeps (j2)'s single-spawn no-PR stop unchanged.
  #   m5:  two lines, so the close-out's before/after differ — an honest close-out, which is what
  #        keeps every approve case exiting 0 with `done`.
  # A case that wants the other polarity calls set_progress_tokens.
  printf 'adv-0\n' > "$PROGRESS_ADV_FILE"
  printf 'm5-0\nm5-1\n' > "$PROGRESS_M5_FILE"
  # #527 DEFAULT, chosen on the same principle as `adv` above: ONE line, so the infra residue
  # never moves and every pre-existing case keeps meaning what it meant. (j2)'s no-progress stop
  # in particular is now conditioned on BOTH predicates being unmoved, and this is what keeps it
  # the plain idle-session case rather than an infrastructure death.
  printf 'infra-0\n' > "$PROGRESS_INFRA_FILE"
}

set_progress_tokens() { # set_progress_tokens <adv-stream> <m5-stream>
  printf '%s\n' "$1" > "$PROGRESS_ADV_FILE"
  printf '%s\n' "$2" > "$PROGRESS_M5_FILE"
}

set_infra_tokens() { # set_infra_tokens <infra-stream>
  printf '%s\n' "$1" > "$PROGRESS_INFRA_FILE"
}

# #500: a comment trail in the REAL API's shape, with TWO DECOYS ahead of the claim marker. Both
# are discriminators, not scenery — each carries its own `run_id:` and sits EARLIER in the trail
# than the real marker, so a tool that dropped either filter would take `first` from a decoy and
# the run-id assertion in (s1) would name the wrong run:
#   1. bot-authored, carries a run id, but no `stage: lean-claimed` tag  → kills a missing TAG filter
#   2. tagged and carries a run id, but authored by a USER               → kills a missing TYPE filter
# The third entry is the marker itself, whose author type the case picks — which is how (s4) drives
# "tagged, but nothing bot-authored" without changing anything else.
set_claim_trail() { # set_claim_trail <author-type> <run-id>
  jq -n --arg t "$1" --arg r "$2" '
    [ { user: { type: "Bot",  login: "some-other-bot" },
        body: "<!-- run_id: decoy-untagged-bot -->\nnot a claim marker" },
      { user: { type: "User", login: "an-operator" },
        body: "<!-- stage: lean-claimed -->\n<!-- run_id: decoy-operator-forged -->" },
      { user: { type: $t,     login: "pipeline-bot" },
        body: ("<!-- dev-pipeline -->\n<!-- run_id: " + $r
               + " -->\n<!-- stage: lean-claimed -->\n\nClaimed by build-lean.") } ]' \
    > "$COMMENTS_FILE"
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
         COMMENTS_FILE="$COMMENTS_FILE" COMMENTS_FAIL="${COMMENTS_FAIL:-}"
         PROGRESS_ADV_FILE="$PROGRESS_ADV_FILE" PROGRESS_M5_FILE="$PROGRESS_M5_FILE"
         PROGRESS_INFRA_FILE="$PROGRESS_INFRA_FILE" INFRA_FAIL="${INFRA_FAIL:-}"
         PR_FROM_SPAWN="${PR_FROM_SPAWN:-}" PROGRESS_FAIL="${PROGRESS_FAIL:-}"
         STALENESS_RC_FILE="$STALENESS_RC_FILE"
         STALENESS_TICKET_RC_FILE="$STALENESS_TICKET_RC_FILE"
         STATE_ANSWER="${STATE_ANSWER:-OPEN}"
         RUN_ID=poisoned-parent-run LEAN_RUN_MODEL=poisoned-parent-model )
  [ "${USE_DEFAULT_GH:-0}" -eq 1 ] || envs+=( GH="$BIN/gh" )
  ( cd "$TREE" \
    && env -u CLAUDE_CODE_SESSION_ID -u GH "${envs[@]}" bash "$TOOL" "$@" 2>&1 )
}

spawn_count() { cat "$SPAWN_LOG_DIR/count" 2>/dev/null || echo 0; }
gate_count()  { cat "$GATE_LOG_DIR/count" 2>/dev/null || echo 0; }
# #496: how many gate calls ran on the RECORDING path. Capture-then-default, never
# `grep -c … || echo 0` — on zero matches grep prints "0" AND exits 1, so the `||` fires too and
# the helper emits "0\n0", which every `-eq 0` comparison through it then rejects as a
# non-integer. That shape survives only in suites where the counter never has to be zero, and
# this one exists precisely to assert a zero.
attempt_count() { local n; n="$(grep -c . "$GATE_LOG_DIR/attempts" 2>/dev/null)" || n=0; [ -n "$n" ] || n=0; echo "$n"; }
# #492: progress reads, counted per token space. `adv` is the continuation predicate, `m5` the
# close-out's milestone-5 check.
progress_reads() { cat "$GATE_LOG_DIR/pcount-${1:-adv}" 2>/dev/null || echo 0; }
progress_log()   { cat "$GATE_LOG_DIR/progress.log" 2>/dev/null; }
# #515: staleness reads, counted per call site. `loop` is the pre-spawn check, `ticket` preflight's.
staleness_reads() { cat "$GATE_LOG_DIR/scount-${1:-loop}" 2>/dev/null || echo 0; }
staleness_log()   { cat "$GATE_LOG_DIR/staleness.log" 2>/dev/null; }
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

# ---- (s) #500: re-entering a run the lane stopped itself ---------------------------------------
# `claim` swaps the queue label for the claimed one, so the ticket of a run this lane stopped
# presents the CLAIMED label plus this lane's own bot-authored marker — never the queue label
# preflight used to demand. That PAIR is the second accepting state; (g1) above stays the case for
# a ticket that presents neither, which must keep rejecting.

# AC-1/AC-7: accepted, the run proceeds end to end, and the accept is NAMED as re-entry with the
# run id the marker carries — not folded into the queue-label wording.
setup_case "" "0" "in-progress" "11"
set_claim_trail Bot lean-500-abc123
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 3 ] \
   && grep -q 'ok intake: re-entry' <<<"$out" \
   && grep -q 'lean-500-abc123' <<<"$out"; then
  pass "(s1) a claimed ticket carrying this lane's bot-authored marker is accepted as re-entry, and the accept names the marker's run id"
else fail "(s1) expected rc=0 with 3 spawns and a named re-entry, got rc=$rc / $(spawn_count) spawn(s): $out"; fi

# The claimed label defaults to `in-progress` here — the fixture config sets no
# `.tracker.labels.claimed` — which is the same shipped default lean-gate.sh's `claim` writes. A
# tool that resolved a different one could not have matched the label above at all.
#
# ANTI-VACUITY for (s1): the accept must have come from the comment READ, on the call that carries
# `.user.type`. Without this, a tool that accepted every claimed ticket unconditionally would pass
# (s1) — and (s3)/(s4) below are what stop it passing the rest.
if grep -q "api repos/{owner}/{repo}/issues/$ISSUE/comments" "$GH_LOG"; then
  pass "(s2) the re-entry evidence is read through 'gh api …/comments' — the response that carries .user.type"
else fail "(s2) the comment trail was never read: $(cat "$GH_LOG")"; fi

# AC-2, measured on the same run: re-entry restores nothing. The scheduler never wrote anyway —
# what this pins is that the new arm did not reach for a label swap to "repair" the state it read.
if [ -s "$GH_LOG" ] \
   && ! grep -qE 'issue (edit|comment|create|close)|pr (comment|edit|merge|create|review)|--method (POST|PATCH|PUT|DELETE)|-X (POST|PATCH|PUT|DELETE)' "$GH_LOG"; then
  pass "(s3) a re-entered run makes ZERO tracker writes — no label is re-swapped and none is restored"
else fail "(s3) re-entry made a tracker write: $(cat "$GH_LOG")"; fi

# AC-5: the label ALONE is a human moving a card, not evidence this lane ever claimed the ticket.
setup_case "" "0" "in-progress" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q "no bot-authored 'lean-claimed' marker" <<<"$out"; then
  pass "(s4) the claimed label with no marker is rejected — the conjunction is the guard, not either half"
else fail "(s4) expected rc=2 with 0 spawns on a markerless claimed ticket, got rc=$rc / $(spawn_count): $out"; fi

# AC-5's other half. Issue comments are writable by any account on a public repo, so an
# operator-posted marker must not be re-entry evidence: with the marker authored by a USER the
# whole trail — decoys included — has nothing bot-authored, and the run rejects.
setup_case "" "0" "in-progress" "11"
set_claim_trail User lean-500-forged
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q "no bot-authored 'lean-claimed' marker" <<<"$out" \
   && ! grep -q 'lean-500-forged' <<<"$out"; then
  pass "(s5) a lean-claimed marker that is not bot-authored is not re-entry evidence — an operator cannot post their way past preflight"
else fail "(s5) expected rc=2 with 0 spawns on a user-authored marker, got rc=$rc / $(spawn_count): $out"; fi

# AC-6 / D-8: a FAILED read is not "no marker". One is an environment error the operator must fix
# before any verdict means anything; collapsing it into the reject would report a tracker outage as
# an intake problem, and preflight never falls back to local state to paper over it.
setup_case "" "0" "in-progress" "11"
set_claim_trail Bot lean-500-abc123
COMMENTS_FAIL=1 out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
unset COMMENTS_FAIL
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'comment trail could not be read' <<<"$out" \
   && ! grep -q "no bot-authored 'lean-claimed' marker" <<<"$out"; then
  pass "(s6) an unreadable comment trail rejects as its own failure, never as 'no marker'"
else fail "(s6) expected rc=2 naming the failed read, got rc=$rc / $(spawn_count): $out"; fi

# The retired flag has no parse arm left, so it reaches the generic `-*)` reject. Driven on a
# queue-labelled ticket that would otherwise have run clean, so a pass here could only mean the
# argument was silently swallowed. Without this case, deleting the parse arm is unobservable — the
# two cases that used to exercise the flag went with it.
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --intake-attested)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q -- 'unknown option: --intake-attested' <<<"$out"; then
  pass "(s7) the retired --intake-attested is an unknown option, not a silently accepted no-op"
else fail "(s7) expected an unknown-option reject, got rc=$rc / $(spawn_count): $out"; fi

# AC-4/AC-1, the conjunction's OTHER half. A marker with no claimed label is a stale claim on a
# ticket whose label was hand-reset — the lane's own bookkeeping says this ticket is not in flight,
# and a marker from some earlier run must not override that. Without this case a tool that dropped
# the label check entirely would pass every other case in this section.
setup_case "" "0" "" "11"
set_claim_trail Bot lean-500-abc123
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q "does not carry 'ready-for-dev'" <<<"$out" \
   && ! grep -q 're-entry' <<<"$out"; then
  pass "(s10) a bot marker with NO claimed label is not re-entry — both halves of the conjunction are load-bearing"
else fail "(s10) a markered ticket with no claimed label was accepted, got rc=$rc / $(spawn_count): $out"; fi

# AC-4's ordering half: the queue label still wins outright, and the ordinary fresh run costs no
# comment read at all. A tool that read the trail unconditionally would pass every case above while
# adding a tracker round-trip to every launch in the lane.
setup_case "" "0" "ready-for-dev
in-progress" "11"
set_claim_trail Bot lean-500-abc123
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q "carries the 'ready-for-dev' queue label" <<<"$out" \
   && ! grep -q 're-entry' <<<"$out" \
   && ! grep -q "api repos/{owner}/{repo}/issues/$ISSUE/comments" "$GH_LOG"; then
  pass "(s9) the queue label wins outright: a fresh queued ticket is accepted as such and never pays for the comment read"
else fail "(s9) the queue-label arm did not short-circuit, rc=$rc: $out / $(cat "$GH_LOG")"; fi

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

# ---- (o) #492: exit 0 + no PR is THREE states, not two ------------------------------------------
# `claude -p` exits 0 when the model ends its turn, not when the block finishes, so "exited 0 and
# left no PR" splits into "did nothing" (j2, above) and "advanced and stopped early" (here). The
# whole section turns on the tool being able to tell them apart from an artifact.

# ANTI-VACUITY FOR (j2), scored while its logs are still the live ones. (j2) passed before #492
# and would pass again if the predicate were never wired at all — the assertion below is what
# makes it evidence that the tool CONSULTED the record and found it unmoved, rather than evidence
# that it never looked.
#
# #527 RE-DERIVES IT over BOTH predicates. The stop (j2) asserts is now a conjunction — progress
# unmoved AND infra residue unmoved — so the old single-predicate form would keep passing against
# a tool that never learned to read the second one and stopped on the first alone. Both spaces,
# both sides of the spawn.
if [ "$(progress_reads adv)" -ge 2 ] && [ "$(progress_reads infra)" -ge 2 ]; then
  pass "(j3) the no-progress stop was reached by READING both predicates — each twice, once per side of the spawn"
else fail "(j3) (j2) stopped without consulting both predicates (adv=$(progress_reads adv), infra=$(progress_reads infra)) — it would pass with the feature absent"; fi

# AC-1/AC-6: advanced ⇒ a second BUILD spawn, and the run goes on to REVIEW.
setup_case "" "0" "ready-for-dev" "11"
set_progress_tokens "a1
a2" "m5-0
m5-1"
PR_FROM_SPAWN=2 out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
unset PR_FROM_SPAWN
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 4 ] \
   && grep -q 'build-lean 7' <<<"$(spawn_argv 1)" \
   && grep -q 'build-lean 7' <<<"$(spawn_argv 2)" \
   && grep -q 'review-lean 11' <<<"$(spawn_argv 3)" \
   && grep -q 'BUILD advanced but left no open PR' <<<"$out"; then
  pass "(o1) exit-0 + no PR + progress advanced ⇒ a second BUILD spawn, and the run reaches REVIEW"
else fail "(o1) expected rc=0 with 4 spawns (build, build, review, close-out), got rc=$rc / $(spawn_count): $out"; fi

# AC-1's other half: a continuation is a FRESH session. The separation rule this lane rests on
# does not get an exception for the recovery path.
if grep -qE -- '(^| )-p ' <<<"$(spawn_argv 2)" \
   && ! grep -qE -- '--resume|--continue|(^| )-c( |$)' <<<"$(spawn_argv 2)"; then
  pass "(o2) the continuation is a fresh -p session, never a resumed one"
else fail "(o2) the continuation carried a resume flag or lost -p: $(spawn_argv 2)"; fi

# The counter is per BUILD PHASE, and the phase ends when a PR appears. Asserted through the
# reported ordinal rather than an internal: a cap that never reset would print "2 of 2" here.
if grep -q 'no open PR — continuing in a fresh session (1 of 2)' <<<"$out"; then
  pass "(o3) the continuation is reported with its ordinal against the shipped default of 2"
else fail "(o3) the continuation ordinal was not reported: $out"; fi

# AC-5's boundary, measured. The predicate must be read from the MAIN checkout — the progress
# record lives there so it survives teardown, and the close-out compares across a spawn whose
# last act deletes the worktree. It is also read with no ambient RUN_ID, like every other gate call.
if grep -q "CWD: $TREE " <<<"$(progress_log)" \
   && ! grep -q 'RUN_ID_SET: yes' <<<"$(progress_log)"; then
  pass "(o4) the predicate is read from the main checkout, with RUN_ID scrubbed"
else fail "(o4) the progress read was made from the wrong cwd or with an ambient RUN_ID: $(progress_log)"; fi

# AC-2: the cap is honored and NAMED. Driven at 1 rather than the default so the exhaustion is
# two spawns away instead of three — the property is the bound, not its shipped value.
setup_case "" "0" "ready-for-dev" ""
set_progress_tokens "a1
a2
a3
a4" "m5-0
m5-1"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --max-continuations 1)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 2 ] && [ "$(gate_count)" -eq 0 ] \
   && grep -q 'HARD STOP' <<<"$out" \
   && grep -q -- '--max-continuations budget (1)' <<<"$out"; then
  pass "(o5) a build phase that keeps advancing without a PR is bounded, and the exhaustion names the cap"
else fail "(o5) expected rc=1 after 2 spawns, got rc=$rc / $(spawn_count) spawn(s) / $(gate_count) gate call(s): $out"; fi

# The bound is the SCHEDULER's, and it is what keeps a payload that hit the gate's own rc=4 hard
# stop from re-spawning forever: fail_milestone appends an attempt row on every red including the
# over-budget one, so such a spawn reads as "advanced" here. Zero restores the pre-#492 behavior,
# which is the honest way to ask for it rather than deleting the feature.
setup_case "" "0" "ready-for-dev" ""
set_progress_tokens "a1
a2" "m5-0
m5-1"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --max-continuations 0)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 1 ] && grep -q 'HARD STOP' <<<"$out"; then
  pass "(o6) --max-continuations 0 restores the pre-#492 single-spawn behavior on an advanced run"
else fail "(o6) expected rc=1 after exactly 1 spawn, got rc=$rc / $(spawn_count): $out"; fi

setup_case "" "0" "ready-for-dev" "abc"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --max-continuations x)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q -- '--max-continuations must be a non-negative integer' <<<"$out"; then
  pass "(o7) a non-numeric --max-continuations is a usage refusal, not a silently-zero budget"
else fail "(o7) expected rc=2 with no spawn, got rc=$rc / $(spawn_count): $out"; fi

# An unreadable predicate must not degrade into "the run did not advance": that verdict is
# indistinguishable from an idle session, and a scheduler that cannot tell them apart is the
# defect this ticket is about. It refuses BEFORE spawning — spawning blind would burn a session
# on a question the tool has already lost the ability to answer.
setup_case "" "0" "ready-for-dev" "11"
PROGRESS_FAIL=1 out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
unset PROGRESS_FAIL
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'continuation predicate is unavailable' <<<"$out"; then
  pass "(o8) a gate that cannot answer the predicate is a loud refusal, not a blind spawn"
else fail "(o8) expected rc=1 with 0 spawns on an unreadable predicate, got rc=$rc / $(spawn_count): $out"; fi

# ---- (oi) #527: a KILLED milestone-3 evaluation is not an idle session ---------------------------
# `claude -p` ends the turn and the harness kills what it detached, so a BUILD session whose
# milestone-3 sweep was five minutes in satisfies no milestone and fails none. The record it leaves
# is byte-identical to an idle spawn's — measured on the motivating run as four launches, zero PRs,
# both continuations unspent every time, against an implementation that was complete throughout.
# The infra residue is the second predicate that tells the two apart.

# The whole feature in one case: the continuation predicate is UNMOVED and the run continues anyway,
# because the infra residue moved. Nothing else about the recovery path changes.
setup_case "" "0" "ready-for-dev" "11"
set_infra_tokens "i1
i2"
PR_FROM_SPAWN=2 out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
unset PR_FROM_SPAWN
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 4 ] \
   && grep -q 'build-lean 7' <<<"$(spawn_argv 2)" \
   && grep -q 'review-lean 11' <<<"$(spawn_argv 3)" \
   && grep -q 'killed by infrastructure' <<<"$out"; then
  pass "(oi1) progress unmoved but infra residue MOVED ⇒ a second BUILD spawn, and the run reaches REVIEW"
else fail "(oi1) expected rc=0 with 4 spawns on an infra-only advance, got rc=$rc / $(spawn_count): $out"; fi

# The same boundary (o4) pins for the continuation predicate: read from the MAIN checkout, with no
# ambient RUN_ID. The residue lives in the main checkout's state dir, which is exactly why the read
# locates it by issue-keyed glob rather than by a key hashed off the caller's cwd.
if grep -q -- '--infra' <<<"$(progress_log)" \
   && grep -q "CWD: $TREE " <<<"$(progress_log)" \
   && ! grep -q 'RUN_ID_SET: yes' <<<"$(progress_log)"; then
  pass "(oi2) the infra read is made from the main checkout, with RUN_ID scrubbed"
else fail "(oi2) the infra read was made from the wrong cwd, with an ambient RUN_ID, or not at all: $(progress_log)"; fi

# THE DELTA, NEVER THE LEVEL — and this case is the whole reason for that choice. The progress
# record is append-only, so residue from one death stays readable for the rest of the run: a tool
# routing on "is there residue" would read every later idle session as recoverable and spend the
# continuation budget on nothing, which is a fresh instance of the bug being removed. Here the
# residue moves ONCE and then holds, and the second spawn must stop exactly like (j2).
setup_case "" "0" "ready-for-dev" ""
set_infra_tokens "i1
i2"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 2 ] \
   && grep -q 'no open PR' <<<"$out" \
   && ! grep -q 'HARD STOP' <<<"$out"; then
  pass "(oi3) residue that moved once and then holds stops the next spawn — the routing is on the delta"
else fail "(oi3) expected rc=1 after exactly 2 spawns, got rc=$rc / $(spawn_count): $out"; fi

# No new bound and no new flag: an infra-driven continuation is spent from, and stopped by, the
# same --max-continuations budget an ordinary advance is.
setup_case "" "0" "ready-for-dev" ""
set_infra_tokens "i1
i2
i3
i4
i5"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --max-continuations 1)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 2 ] \
   && grep -q -- '--max-continuations budget (1)' <<<"$out"; then
  pass "(oi4) repeated infrastructure deaths are bounded by the existing --max-continuations"
else fail "(oi4) expected rc=1 after 2 spawns on the existing bound, got rc=$rc / $(spawn_count): $out"; fi

# Fail-closed, exactly like (o8) for its sibling. The gate answers `m3infra-v1:0` when there is no
# death, so an erroring read is never a legitimate negative — treating it as one puts the scheduler
# straight back to reading a killed session as an idle one.
setup_case "" "0" "ready-for-dev" "11"
INFRA_FAIL=1 out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
unset INFRA_FAIL
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'infrastructure residue' <<<"$out"; then
  pass "(oi5) a gate that cannot answer the infra read is a loud refusal, not a blind spawn"
else fail "(oi5) expected rc=1 with 0 spawns on an unreadable infra read, got rc=$rc / $(spawn_count): $out"; fi

# ---- (p) #492 AC-7: the close-out is VERIFIED, never credited on its exit status -----------------
# `verdict_rc` runs before the close-out spawn and nothing evaluated after it, so this site
# reported `done` on a session that had done nothing — worse than the no-PR case, which at least
# exits loudly. What is checked is a NEW milestone-5 satisfaction, so a re-entered lane cannot be
# credited with a prior run's.
setup_case "" "0" "ready-for-dev" "11"
set_progress_tokens "adv-0" "m5-0"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 3 ] \
   && grep -q 'recorded no NEW milestone-5 satisfaction' <<<"$out" \
   && ! grep -q 'done — #' <<<"$out"; then
  pass "(p1) a close-out that exits 0 without satisfying milestone 5 is a non-zero exit naming what is unmet, not 'done'"
else fail "(p1) expected rc=1 after the close-out spawn, got rc=$rc / $(spawn_count): $out"; fi

# D-9: verify-only. The continuation machinery is NOT extended to this site — three spawns above,
# not four — because past an approve another silent session answers a question the operator has
# not been told about yet.
if [ "$(spawn_count)" -eq 3 ] && grep -q -- '--satisfied 5' <<<"$(progress_log)"; then
  pass "(p2) the uncredited close-out is not re-spawned, and the check it failed is milestone-5-scoped"
else fail "(p2) the close-out was re-spawned, or the check was not milestone-scoped: $(spawn_count) spawn(s) / $(progress_log)"; fi

# The positive control for (p1): the SAME path with a new milestone-5 row reaches `done`. Without
# it, (p1) would also pass against a tool that failed every close-out unconditionally.
setup_case "" "0" "ready-for-dev" "11"
set_progress_tokens "adv-0" "m5-0
m5-1"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(progress_reads m5)" -eq 2 ] && grep -q 'done — #7 approved on PR #11' <<<"$out"; then
  pass "(p3) a close-out that DOES satisfy milestone 5 reaches 'done' — the check is a comparison, not a blanket refusal"
else fail "(p3) expected rc=0 with 2 milestone-5 reads, got rc=$rc / $(progress_reads m5) read(s): $out"; fi

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
# The ticket carries NO label, which is what makes this case non-vacuous: delete the non-github arm
# entirely and the run falls through to the github label read, finds nothing, and rejects — so all
# three assertions below fail. Driven on a labelled ticket it would instead pass against a scheduler
# with no arm at all. Not redundant with (m2) despite the identical invocation: this one asserts the
# arm is REACHED and what it says, (m2) asserts what the key and branch become once it has passed.
setup_case "" "0" "" "11"
out="$(run_tool "$CFG_JIRA" ACME-7 --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -gt 0 ] \
   && grep -q "tracker 'jira'" <<<"$out" \
   && grep -q 'intake is not gated here' <<<"$out" \
   && grep -q 'Run /intake-toolkit:intake before the lane' <<<"$out"; then
  pass "(m1) a tracker with no queue label is ungated: preflight names the tracker, says so, and the run proceeds"
else fail "(m1) expected an ungated jira run naming the tracker, got rc=$rc / $(spawn_count): $out"; fi

setup_case "" "0" "" "11"
out="$(run_tool "$CFG_JIRA" ACME-7 --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'build-lean ACME-7' <<<"$(spawn_argv 1)" \
   && grep -q "^CWD: $WORK/wt$" "$GATE_LOG_DIR/call-1" 2>/dev/null; then
  pass "(m2) the jira key reaches the payload unlowercased while the BRANCH is lowercased"
else fail "(m2) expected a clean jira run, got rc=$rc: $out"; fi

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

# ---- (r) #496: the verdict gate's rc is a taxonomy, and each class gets its own action -----------
# The gate here is a FAKE whose rc is popped from a fixture file, which is the point: these cases
# are about what the SCHEDULER does with a class, never about which condition produces it. The
# real gate's classification is the gate suite's to prove — a mutation of lean-gate.sh cannot red
# anything below, and a case here that claimed otherwise would be asserting nothing.

# Class 5 — no verdict usable against this head. No BUILD spawn, no round spent: exactly one
# REVIEW re-spawn, then the approve that follows it closes the run out normally.
setup_case "" "5
0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 4 ] && [ "$(gate_count)" -eq 2 ] \
   && grep -q 'review-lean 11' <<<"$(spawn_argv 2)" \
   && grep -q 'review-lean 11' <<<"$(spawn_argv 3)" \
   && grep -q 'build-lean 7' <<<"$(spawn_argv 4)" \
   && grep -q 'No round spent, no BUILD spawn' <<<"$out"; then
  pass "(r1) a class-5 read re-spawns REVIEW — not BUILD — and spends no round"
else fail "(r1) expected rc=0 with build,review,review,close-out, got rc=$rc / $(spawn_count) spawn(s) / $(gate_count) gate call(s): $out"; fi

# ...and the retry is BOUNDED at one. A second dark review is a broken review lane, so the run
# exits 5 naming it rather than spending the round budget on sessions that produce no record.
setup_case "" "5
5
5" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 5 ] && [ "$(spawn_count)" -eq 3 ] && [ "$(gate_count)" -eq 2 ] \
   && grep -q 'HARD STOP' <<<"$out" \
   && grep -q 'no verdict record usable against the current head, twice' <<<"$out"; then
  pass "(r2) two class-5 reads in one round is a bounded stop at exit 5, not a third review and not a fix round"
else fail "(r2) expected rc=5 after 3 spawns / 2 gate calls, got rc=$rc / $(spawn_count) / $(gate_count): $out"; fi

# The BUILD spawn count is the load-bearing half of (r1)/(r2): a class-5 that fell through to the
# needs-work arm would look similar in exit code from some angles but would have re-spawned BUILD.
if [ "$(grep -l 'build-lean' "$SPAWN_LOG_DIR"/spawn-* 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]; then
  pass "(r3) across both dark reviews exactly ONE build-lean session ran — BUILD is never asked to fix a review-half failure"
else fail "(r3) a class-5 round spawned BUILD again: $(all_argv)"; fi

# Class 6 — an integrity refusal is TERMINAL. Scripted with a second gate rc that would approve,
# so a fall-through to the needs-work arm would be visible as a green run rather than as a
# different failure.
setup_case "" "6
0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 6 ] && [ "$(spawn_count)" -eq 2 ] && [ "$(gate_count)" -eq 1 ] \
   && grep -q 'HARD STOP' <<<"$out" \
   && grep -q 'P10' <<<"$out"; then
  pass "(r4) a class-6 integrity refusal exits 6 immediately — nothing re-spawned, no round spent, and the message names P10"
else fail "(r4) expected rc=6 after 2 spawns / 1 gate call, got rc=$rc / $(spawn_count) / $(gate_count): $out"; fi

# AC-6: across a whole approved round the scheduler's verdict read records NOTHING. It used to run
# the gate's recording path, so every non-approve verdict it merely READ spent the BUILD role's
# milestone-4 fix budget — the "this script writes nothing" premise was false at exactly one site.
setup_case "" "1
0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(gate_count)" -eq 2 ] && [ "$(attempt_count)" -eq 0 ]; then
  pass "(r5) a full needs-work-then-approve run makes both verdict reads through the observe seam — zero recording-path calls"
else fail "(r5) expected 2 gate calls and 0 recording-path calls, got rc=$rc / $(gate_count) / $(attempt_count): $out"; fi

# ...and the seam is asserted on the CALL, not only through the fake's bookkeeping, so a rename of
# the variable cannot pass this by accident.
if grep -q '^OBSERVE: 1$' "$GATE_LOG_DIR/call-1" 2>/dev/null \
   && grep -q '^ARGV: 4 7$' "$GATE_LOG_DIR/call-1" 2>/dev/null; then
  pass "(r6) the verdict gate is invoked as '4 <issue>' with the observe seam set"
else fail "(r6) the verdict call carried no observe seam: $(cat "$GATE_LOG_DIR/call-1" 2>/dev/null)"; fi

# The positive control for (r5): the fake DOES record when the seam is absent. Without it, a fake
# that never wrote the file would satisfy the zero-count assertion vacuously.
: > "$GATE_LOG_DIR/attempts"
( cd "$TREE" && GATE_LOG_DIR="$GATE_LOG_DIR" GATE_RC_FILE="$GATE_RC_FILE" bash "$BIN/fake-gate.sh" 4 7 >/dev/null 2>&1 )
if [ "$(attempt_count)" -eq 1 ]; then
  pass "(r7) the fake records a recording-path call when the seam is absent — (r5)'s zero is a measurement"
else fail "(r7) the fake recorded nothing even without the seam, so (r5) asserts nothing"; fi

# AC-8: more than one open PR on the head is refused by NAME, never resolved by picking the first.
setup_case "" "0" "ready-for-dev" "11
12"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 1 ] && [ "$(gate_count)" -eq 0 ] \
   && grep -q 'more than one open PR' <<<"$out" \
   && grep -q '11' <<<"$out" && grep -q '12' <<<"$out"; then
  pass "(r8) two open PRs on the head is a named refusal after the build spawn, not a silent pick of the first"
else fail "(r8) expected rc=1 naming both PRs, got rc=$rc / $(spawn_count) spawn(s): $out"; fi

# AC-9: a config that exists but does not parse is a refusal. The defaults are not neutral —
# `.tracker.type` falls back to `github`, whose intake arm attests more than jira's — so the
# fall-through would silently pick a policy. Nothing is spawned.
CFG_CORRUPT="$WORK/config-corrupt.json"
printf '{ "tracker": { "type": "jira", }\n' > "$CFG_CORRUPT"
if jq empty "$CFG_CORRUPT" >/dev/null 2>&1; then
  fail "(r9-fixture) the corrupt config parses, so (r9) would assert nothing"
fi
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG_CORRUPT" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'not parseable JSON' <<<"$out"; then
  pass "(r9) an unparseable config is a refusal with nothing spawned, not a silent fall-through to tracker.type=github"
else fail "(r9) expected rc=2 with 0 spawns, got rc=$rc / $(spawn_count): $out"; fi

# ...and the other half: an ABSENT config is the ordinary un-onboarded consumer and resolves the
# documented defaults. Without this the guard could have been "refuse unless a config parses",
# which would break every consumer that never wrote one.
# The remote ref is the fixture absence needs and presence did not: with no config there is no
# `tracker.branchPrefix`, so the namespace is inferred from remote branches, and a fixture repo
# with none refuses for that unrelated reason. One work-shaped remote branch supplies the vote.
git -C "$TREE" update-ref refs/remotes/origin/"$BRANCH" HEAD
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$WORK/no-such-config.json" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 3 ]; then
  pass "(r10) an ABSENT config still resolves the shipped defaults — the guard fails closed on corruption only"
else fail "(r10) an absent config was refused, got rc=$rc / $(spawn_count) spawn(s): $out"; fi

# ---- (v) #515: the run's premise is re-checked before every BUILD spawn, and only those --------
# What this block owns is the scheduler's WIRING — which call sites exist, with which arm, in which
# order, and how each rc routes. What it deliberately does NOT own is whether the predicate is
# right: that is lean-gate-selftest.sh's (st*) block, which drives the real subcommand against a
# real remote and a real fetch. (v13)/(v14) are the matched pair here that joins the two, because
# the seam between them — the scheduler invoking a subcommand and an arm the real gate actually
# accepts — is precisely what a fake gate cannot fail on.
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 3 ] \
   && [ "$(staleness_reads loop)" -eq 1 ] && [ "$(staleness_reads ticket)" -eq 1 ]; then
  pass "(v1) an approved run reads staleness ONCE for its one build spawn — never before REVIEW, never before the close-out"
else fail "(v1) expected 3 spawns with 1 loop + 1 ticket read, got $(spawn_count) / $(staleness_reads loop) / $(staleness_reads ticket), rc=$rc: $out"; fi

if grep -q "CWD: $TREE" <<<"$(staleness_log)" \
   && ! grep -q 'RUN_ID_SET: yes' <<<"$(staleness_log)"; then
  pass "(v2) every staleness read runs from the MAIN checkout with RUN_ID scrubbed, against a poisoned parent"
else fail "(v2) the staleness reads had the wrong cwd or an ambient run id: $(staleness_log)"; fi

if grep -q 'ARGV: staleness 7 --arm ticket ' <<<"$(staleness_log)" \
   && grep -qE 'ARGV: staleness 7 \|' <<<"$(staleness_log)"; then
  pass "(v3) preflight asks for the TICKET arm alone; the loop asks for both — the base arm belongs to the spawn loop"
else fail "(v3) the two call sites did not use the arms the contract assigns them: $(staleness_log)"; fi

# The continuation arm. Two BUILD spawns in ONE build phase, four spawns overall — so a read count
# of 2 can only mean "per BUILD spawn", never "per spawn" and never "once per run".
setup_case "" "0" "ready-for-dev" "11"
set_progress_tokens 'adv-0
adv-1' 'm5-0
m5-1'
PR_FROM_SPAWN=2 \
  out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
unset PR_FROM_SPAWN
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 4 ] && [ "$(staleness_reads loop)" -eq 2 ]; then
  pass "(v4) a continuation re-checks the premise — 4 spawns, 2 build spawns, 2 reads"
else fail "(v4) expected 4 spawns with 2 loop reads, got $(spawn_count) / $(staleness_reads loop), rc=$rc: $out"; fi

# Round 2's read is a FRESH evaluation, not round 1's answer remembered: the same run passes the
# check, spends a needs-work round, and is stopped by the check on the way into round 2.
setup_case "" "1" "ready-for-dev" "11"
printf '0\n7\n' > "$STALENESS_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 7 ] && [ "$(spawn_count)" -eq 2 ] && [ "$(staleness_reads loop)" -eq 2 ]; then
  pass "(v5) the premise is re-evaluated on every round — a run that was clean in round 1 is stopped entering round 2"
else fail "(v5) expected rc=7 after 2 spawns and 2 reads, got rc=$rc / $(spawn_count) / $(staleness_reads loop): $out"; fi

setup_case "" "0" "ready-for-dev" "11"
printf '7\n' > "$STALENESS_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 7 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'premise expired' <<<"$out" && grep -q 'Rebase this branch' <<<"$out" \
   && grep -q 'worktree and the claim are left in place' <<<"$out"; then
  pass "(v6) a stale premise is exit 7 with nothing spawned, naming the rebase-or-abandon choice and the state left behind"
else fail "(v6) expected rc=7 with 0 spawns, got rc=$rc / $(spawn_count): $out"; fi

if grep -q 're-fires this stop at the same point' <<<"$out"; then
  pass "(v7) the stop says a re-launch without a rebase re-fires it, rather than leaving that to be discovered (D-10)"
else fail "(v7) the exit-7 message did not state the re-fire: $out"; fi

# Ordering, and it is not cosmetic: the progress read is a second gate invocation, and a run whose
# premise has already expired should not pay for it.
if [ "$(progress_reads adv)" -eq 0 ]; then
  pass "(v8) the check runs FIRST in the loop body — a stale run costs not even the continuation predicate's read"
else fail "(v8) the progress predicate was read $(progress_reads adv) time(s) on a stale run: $(progress_log)"; fi

# D-5, at the loop. A read that could not be completed is a phase failure's exit 1, NOT 7 and
# emphatically not 0 — the distinction the whole ticket turns on.
setup_case "" "0" "ready-for-dev" "11"
printf '1\n' > "$STALENESS_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'could not be completed' <<<"$out" && grep -q 'premise nothing verified' <<<"$out"; then
  pass "(v9) an unevaluable staleness read exits 1 with nothing spawned — never a blind spawn, and distinguishable from the stale stop"
else fail "(v9) expected rc=1 with 0 spawns, got rc=$rc / $(spawn_count): $out"; fi

# Preflight's arm. A launch onto an already-closed ticket costs no run at all, and reports as a
# preflight reject (exit 2) rather than the loop's 7, because nothing was spawned.
setup_case "" "0" "ready-for-dev" "11"
printf '7\n' > "$STALENESS_TICKET_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] && [ "$(staleness_reads loop)" -eq 0 ] \
   && grep -q 'FAIL ticket' <<<"$out" && grep -q 'premise is already false' <<<"$out"; then
  pass "(v10) preflight rejects a launch onto an expired premise at exit 2, before the loop is ever entered"
else fail "(v10) expected a preflight rc=2 with 0 spawns, got rc=$rc / $(spawn_count): $out"; fi

if grep -q 'ok intake' <<<"$out" && grep -q 'ok spawn' <<<"$out" && grep -q 'ok gate' <<<"$out"; then
  pass "(v11) the ticket probe joins the concurrent set — every other probe's verdict is still reported alongside its failure"
else fail "(v11) a failing ticket probe suppressed the other probe verdicts: $out"; fi

setup_case "" "0" "ready-for-dev" "11"
printf '1\n' > "$STALENESS_TICKET_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] && grep -q 'could not be completed' <<<"$out"; then
  pass "(v12) preflight fails closed too — an unreadable tracker is not an open ticket"
else fail "(v12) expected a preflight rc=2 on an unevaluable read, got rc=$rc / $(spawn_count): $out"; fi

# ---- (v13) the REAL gate, end to end: the one case a fake cannot make green ---------------------
# Its own fixture repo with a real bare origin, because it is the only case in this file that runs
# actual git ranges. Everything above would stay green if the scheduler asked the gate for a
# subcommand or an arm the real gate rejects; this fails on exactly that, and on the rc integer.
#
# LEAN_GATE is UNSET here on purpose — the tool falls through to its shipped default, so the
# default is asserted to point at the real sibling gate rather than merely documented to.
v_git() { git -C "$1" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false "${@:2}"; }

# ONE fixture builder, TWO independent trees. The overlapping and non-overlapping runs get their
# own repo each rather than sharing one that the first run mutates — a second case reading state
# the first left behind is how a pair like this stops discriminating without either half changing.
# The branch always edits `shared.txt`; `$2` is the file the base's new commit lands in, which is
# the ONLY difference between the two.
make_real_fixture() { # make_real_fixture <dir> <file-the-base-moves-into>
  local d="$1" moved="$2"
  mkdir -p "$d"
  { git init -q --bare "$d/origin.git" \
    && git -C "$d/origin.git" symbolic-ref HEAD refs/heads/main \
    && git init -q "$d/tree" \
    && git -C "$d/tree" symbolic-ref HEAD refs/heads/main; } >/dev/null 2>&1
  printf 'base\n' > "$d/tree/shared.txt"
  printf 'base\n' > "$d/tree/elsewhere.txt"
  { v_git "$d/tree" add -A && v_git "$d/tree" commit -q -m base \
    && git -C "$d/tree" remote add origin "$d/origin.git" \
    && git -C "$d/tree" push -q origin main \
    && v_git "$d/tree" checkout -q -b "$BRANCH"; } >/dev/null 2>&1
  printf 'the branch is editing this file\n' >> "$d/tree/shared.txt"
  { v_git "$d/tree" add -A && v_git "$d/tree" commit -q -m "branch work" \
    && v_git "$d/tree" checkout -q main \
    && git clone -q "$d/origin.git" "$d/push"; } >/dev/null 2>&1
  # Landed through a SECOND clone and never fetched by hand, so the gate's own `git fetch` is the
  # only way `$d/tree` can learn about it. A build that dropped that fetch reads a ref frozen at
  # the branch point and answers "nothing moved" — which would make the overlapping case green.
  printf 'and so is someone else\n' >> "$d/push/$moved"
  { v_git "$d/push" add -A && v_git "$d/push" commit -q -m "another PR lands" \
    && v_git "$d/push" push -q origin main; } >/dev/null 2>&1
}

run_real_gate() { # run_real_gate <tree>
  ( cd "$1" && env -u CLAUDE_CODE_SESSION_ID -u LEAN_GATE \
      PATH="$BIN:$PATH" GH="$BIN/gh" SECOND_SHIFT_CONFIG="$CFG" \
      LEAN_SPAWN_BIN="$BIN/claude" \
      SPAWN_LOG_DIR="$SPAWN_LOG_DIR" SPAWN_RC_FILE="$SPAWN_RC_FILE" \
      GH_LOG="$GH_LOG" LABELS_FILE="$LABELS_FILE" PR_FILE="$PR_FILE" \
      COMMENTS_FILE="$COMMENTS_FILE" STATE_ANSWER="${STATE_ANSWER:-OPEN}" \
      RUN_ID=poisoned-parent-run LEAN_RUN_MODEL=poisoned-parent-model \
      bash "$TOOL" "$ISSUE" --build-model sonnet 2>&1 )
}

make_real_fixture "$WORK/real-overlap" shared.txt
setup_case "" "0" "ready-for-dev" "11"
out="$(run_real_gate "$WORK/real-overlap/tree")"; rc=$?
if [ "$rc" -eq 7 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'BASE ARM FIRED' <<<"$out" && grep -q 'shared.txt' <<<"$out"; then
  pass "(v13) against the REAL gate, an open ticket whose base moved into its own files exits 7 with nothing spawned"
else fail "(v13) the real-gate composition did not stop the run, rc=$rc / $(spawn_count) spawn(s): $out"; fi

# The other half. Same real gate, same real fetch, same branch diff — the base's new commit simply
# lands somewhere the branch is not. Without it, (v13) would pass just as well against a gate that
# fires unconditionally, which is a shape a lane discovers by having every run stopped.
make_real_fixture "$WORK/real-clean" elsewhere.txt
setup_case "" "0" "ready-for-dev" "11"
out="$(run_real_gate "$WORK/real-clean/tree")"; rc=$?
if [ "$rc" -ne 7 ] && [ "$(spawn_count)" -ge 1 ] \
   && grep -q 'into no file this branch touches' <<<"$out"; then
  pass "(v14) the real gate lets a non-overlapping advance through to the BUILD spawn — (v13) is a measurement, not a constant"
else fail "(v14) the real gate stopped a run whose base moved elsewhere, rc=$rc / $(spawn_count) spawn(s): $out"; fi

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
# BOTH bounds, and the lower one is not decoration: the `Exit: 0 = approved` anchor sits four lines
# above the header's end, so a range that over-shrinks (2,134p -> 2,130p) drops the whole exit-code
# tail from --help while still satisfying an upper-bound-only check. Pin the LAST header line by its
# own text so truncation reds in the direction a doc-line deletion actually moves the boundary.
out="$(bash "$TOOL" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'Exit: 0 = approved' <<<"$out" \
   && grep -qF 'integrity refusal (P10)' <<<"$out" \
   && ! grep -qF 'set -uo pipefail' <<<"$out"; then
  pass "(n) --help prints through the last header line and stops before the code"
else fail "(n) --help did not print exactly the header, rc=$rc: $out"; fi

echo "[orchestrate-lean-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

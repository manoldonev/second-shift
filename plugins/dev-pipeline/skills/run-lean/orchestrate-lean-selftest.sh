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

# TRAP INSTALLED BEFORE WORK EXISTS (#528), mirroring lean-gate-selftest.sh: the old order
# (mktemp, then trap) left a window where a signal orphaned WORK with nothing registered to
# remove it. cleanup() guards on WORK being set, so registering it first is safe.
# shellcheck disable=SC2317,SC2329  # invoked indirectly by the EXIT trap below.
# BOTH codes: shellcheck >=0.10 reports SC2329 on the function, 0.9 (CI) reports SC2317 on
# each command in the body — suppressing only the newer one is clean locally and reds CI.
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT
# Explicit-template form (#780): a private TMPDIR is honored, unlike `mktemp -d -t` on macOS —
# so a lane run under its own TMPDIR isolates this fixture instead of sharing one directory
# with every other worktree and lane on the machine.
#
# `pwd -P` because macOS resolves /var through a symlink to /private/var: the tool reports the
# worktree path git gives it, and an unresolved fixture path would make the cwd assertions below
# fail for a reason that has nothing to do with the tool. That mismatch matters MORE under the
# explicit-template form, not less — TMPDIR's unresolved and resolved spellings now differ right
# where WORK is allocated, the same class of divergence -t independently reached via confstr.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orchestrate-lean-selftest.XXXXXX")"
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
# The session fake is DISCRIMINATED ON ARGV, the `gh` fake's precedent below: one binary answers
# the dispatch, the listing and the stop, because production calls one binary for all three and a
# fake split across three files could not catch a call routed to the wrong subcommand.
#
# THE DISPATCH records ARGV and the env vars the contract is about, one file per spawn, so
# ordering is assertable, and prints the harness's own `backgrounded · <id>` line. The id comes
# from a case-written stream so a case can pin it, or force the no-id shape with `NOID`.
#
# THE LISTING is served from a second stream, one line PER POLL rather than per spawn, which is
# what lets a case script `working, working, done` or drive an unreadable read. Four sentinels
# stand for the shapes that are not a state: `UNREADABLE` (the call fails), `GARBAGE` (it answers
# non-JSON), `ABSENT` (a well-formed listing the id is not in) and `NOSTATE` (rows without the
# field the poll reads). Past the end of a stream the LAST line repeats, so a case that scripts
# two polls is not handed a third answer it never asked for — `progress`'s convention exactly.
#
# IT NEVER SLEEPS. The poll interval is a seam the driver pins to 0, so a case that scripts three
# polls costs three `sed` reads rather than ninety seconds.
BIN="$WORK/bin"
mkdir -p "$BIN"
cat > "$BIN/claude" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "agents" ]; then
  # PREFLIGHT'S OWN READ IS NOT A POLL. `probe_spawn` parses this listing before anything is
  # dispatched, so counting it would shift every case's scripted stream by one and silently make
  # a case that scripts `blocked` on tick 1 assert about tick 0. Discriminated on there being no
  # dispatched session yet, which is exactly what distinguishes the two callers.
  if [ ! -f "$SPAWN_LOG_DIR/last-id" ]; then echo '[]'; exit 0; fi
  n=$(( $(cat "$SPAWN_LOG_DIR/acount" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$SPAWN_LOG_DIR/acount"
  echo "ARGV: $*" >> "$SPAWN_LOG_DIR/agents.log"
  line="$(sed -n "${n}p" "$AGENTS_STATE_FILE" 2>/dev/null)"
  [ -n "$line" ] || line="$(tail -n 1 "$AGENTS_STATE_FILE" 2>/dev/null)"
  [ -n "$line" ] || line=done
  case "$line" in
    UNREADABLE) exit 1 ;;
    GARBAGE)    echo 'this is not json'; exit 0 ;;
    ABSENT)     echo '[]'; exit 0 ;;
    NOSTATE)    echo '[{"id":"other","sessionId":"other-full"}]'; exit 0 ;;
  esac
  # Anything else is served AS a state, which is what lets a case drive a word outside the
  # documented enum — the shape an agent-view schema change would produce.
  jq -n --arg id "$(cat "$SPAWN_LOG_DIR/last-id" 2>/dev/null)" --arg st "$line" \
    '[{id:$id, sessionId:($id + "-full"), kind:"background", state:$st}]'
  exit 0
fi
if [ "${1:-}" = "stop" ]; then
  echo "stop ${2:-}" >> "$SPAWN_LOG_DIR/stops"
  exit 0
fi
n=$(( $(cat "$SPAWN_LOG_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$SPAWN_LOG_DIR/count"
# #805 review round 4. `--settings` carries a PATH now, not the JSON itself, so a fake that only
# logged argv would have stopped seeing the child's environment entirely — and (d1)/(d2) would
# have gone vacuous rather than red. Resolved here, once, so the cases keep asserting on content.
settings_file=""; prev=""
for a in "$@"; do [ "$prev" = "--settings" ] && settings_file="$a"; prev="$a"; done
{
  echo "ARGV: $*"
  echo "SETTINGS: $(cat "$settings_file" 2>/dev/null)"
  echo "SETTINGS_PERMS: $(ls -l "$settings_file" 2>/dev/null | cut -c1-10)"
  echo "RUN_ID_SET: ${RUN_ID+yes}"
  echo "LEAN_RUN_MODEL: ${LEAN_RUN_MODEL:-<unset>}"
  echo "LEAN_ATTEND_MODE: ${LEAN_ATTEND_MODE:-<unset>}"
  echo "SESSION_ID_SET: ${CLAUDE_CODE_SESSION_ID+yes}"
  echo "BG_CEILING: ${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-<unset>}"
} > "$SPAWN_LOG_DIR/spawn-$n"
id="$(sed -n "${n}p" "$SPAWN_ID_FILE" 2>/dev/null)"
[ -n "$id" ] || id="sess$n"
if [ "$id" = "NOID" ]; then echo "the session could not be started"; exit 0; fi
echo "$id" > "$SPAWN_LOG_DIR/last-id"
echo "backgrounded · $id"
exit 0
SH
chmod +x "$BIN/claude"

# THE CLOCK, as a fake. The session ceiling is the one behavior here whose input is elapsed wall
# time, and without this a case can only drive it by setting the ceiling to zero — which proves
# the arm fires and says nothing about whether the SHIPPED bound tolerates a long healthy session.
# That is the discrimination the 30-minute default turned out to need and did not have.
cat > "$BIN/fakeclock" <<'SH'
#!/usr/bin/env bash
n=$(( $(cat "$CLOCK_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$CLOCK_FILE"
echo $(( 1000000000 + (n - 1) * ${CLOCK_STEP:-60} ))
SH
chmod +x "$BIN/fakeclock"

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
# #531's `inflight` gets its own arm, its own counter and its own scripted rc stream, for the same
# reason `staleness` and `progress` do: folding it into `count` would re-number the gate-call
# assertion in every case above and hide which numbers mean "verdict call". DEFAULTS TO 0 through
# an EMPTY stream, so every pre-existing case keeps meaning what it meant — a BUILD session that
# collected its work, which is what all of them assume.
if [ "${1:-}" = "inflight" ]; then
  n=$(( $(cat "$GATE_LOG_DIR/fcount" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$GATE_LOG_DIR/fcount"
  echo "ARGV: $* | CWD: $PWD | RUN_ID_SET: ${RUN_ID+yes}" >> "$GATE_LOG_DIR/inflight.log"
  echo "fake-gate: inflight call $n"
  rc="$(sed -n "${n}p" "$INFLIGHT_RC_FILE" 2>/dev/null)"
  exit "${rc:-0}"
fi
# #590's `close-out` gets its own arm, its own counter and its own scripted rc stream, on
# `inflight`'s precedent exactly: folding it into `count` would re-number the gate-call assertion
# in every case above and — because the fallthrough arm records an `attempts` line whenever the
# observe seam is absent — would make the WRITING close-out call read as the recording verdict
# read (r5) exists to forbid. DEFAULTS TO 0 through an EMPTY stream, so every approve case keeps
# meaning what it meant: a close-out that completed.
if [ "${1:-}" = "close-out" ]; then
  n=$(( $(cat "$GATE_LOG_DIR/ccount" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$GATE_LOG_DIR/ccount"
  echo "ARGV: $* | CWD: $PWD | RUN_ID_SET: ${RUN_ID+yes} | SESSION_SET: ${CLAUDE_CODE_SESSION_ID+yes}" >> "$GATE_LOG_DIR/closeout.log"
  echo "fake-gate: close-out call $n"
  rc="$(sed -n "${n}p" "$CLOSEOUT_RC_FILE" 2>/dev/null)"
  exit "${rc:-0}"
fi
if [ "${1:-}" = "progress" ]; then
  # #531's `--obligations` is a REPORT, not a token space: the tool echoes its lines and compares
  # nothing, so the fake serves a fixture file rather than a scripted stream and records the call.
  case "$*" in
    *--obligations*)
      echo "$(( $(cat "$GATE_LOG_DIR/pcount-obl" 2>/dev/null || echo 0) + 1 ))" > "$GATE_LOG_DIR/pcount-obl"
      echo "ARGV: $* | CWD: $PWD | RUN_ID_SET: ${RUN_ID+yes}" >> "$GATE_LOG_DIR/progress.log"
      cat "$PROGRESS_OBL_FILE" 2>/dev/null
      exit 0 ;;
  esac
  # #718: the bare form is a usage refusal in production, so the fake refuses it too — a fake that
  # answered where production exits 2 would let a re-added bare read pass unnoticed here.
  case "$*" in
    *--satisfied*) k=m5; f="$PROGRESS_M5_FILE" ;;
    *)             echo "fake-gate: unknown progress form" >&2; exit 2 ;;
  esac
  n=$(( $(cat "$GATE_LOG_DIR/pcount-$k" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$GATE_LOG_DIR/pcount-$k"
  echo "ARGV: $* | CWD: $PWD | RUN_ID_SET: ${RUN_ID+yes}" >> "$GATE_LOG_DIR/progress.log"
  # Past the end of a scripted stream the LAST line repeats, so a case that scripts two reads is
  # not handed a third answer it never asked for.
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
AGENTS_STATE_FILE=""; SPAWN_ID_FILE=""; CASE_HOME=""; GATE_RC_FILE=""
PROGRESS_M5_FILE=""; COMMENTS_FILE=""
STALENESS_RC_FILE=""; STALENESS_TICKET_RC_FILE=""
PROGRESS_OBL_FILE=""; INFLIGHT_RC_FILE=""; CLOSEOUT_RC_FILE=""
CASE_N=0

# #531 D-7. THE VERDICT READ NOW RUNS BEFORE THE REVIEW SPAWN AS WELL AS AFTER IT, so a round
# consumes TWO gate rcs rather than one and every stream below leads with the pre-spawn read.
# `5` is that read's HONEST answer on a head no review has covered — the real gate returns "no
# verdict usable against the current head" there — so these constants are the fixture shape of a
# real round rather than a padding convention. Named, because a bare `5\n0` at fifty call sites
# would read as noise and drift.
V_APPROVE=$'5\n0'                  # one round: nothing usable yet, then approve
V_NEEDSWORK_APPROVE=$'5\n1\n5\n0'  # round 1 needs-work, round 2 approves

# #805: the first parameter is the LISTING stream, not a spawn exit code — a `--bg` dispatch
# always returns immediately and its status says nothing about the payload. Empty keeps the shape
# every pre-existing case was written against: the first poll answers `done`.
setup_case() { # setup_case <agent-states> <gate-rcs> <labels> <pr>
  CASE_N=$((CASE_N + 1))
  local d="$WORK/case-$CASE_N"
  mkdir -p "$d/spawns" "$d/gates"
  SPAWN_LOG_DIR="$d/spawns"; GATE_LOG_DIR="$d/gates"; GH_LOG="$d/gh.log"
  LABELS_FILE="$d/labels"; PR_FILE="$d/pr"; COMMENTS_FILE="$d/comments"
  AGENTS_STATE_FILE="$d/agent-states"; SPAWN_ID_FILE="$d/spawn-ids"
  GATE_RC_FILE="$d/gate-rcs"
  # #805. A PRIVATE HOME per case, because the tool reads a harness-owned path under it —
  # `~/.claude/projects/*/<sid>.jsonl`, for the transcript's closing message. Without this the
  # suite would consult the machine's real session state, so a case would pass or fail on what the
  # developer's own harness happened to be holding. Empty by default: no final message, which is
  # the shape every pre-existing case assumes.
  CASE_HOME="$d/home"; mkdir -p "$CASE_HOME"
  : > "$SPAWN_ID_FILE"
  PROGRESS_M5_FILE="$d/progress-m5"
  # #515 DEFAULT: EMPTY streams, so every staleness read answers 0 and every pre-existing case
  # keeps meaning what it meant — a clean premise, checked and passed.
  STALENESS_RC_FILE="$d/staleness-rcs"; STALENESS_TICKET_RC_FILE="$d/staleness-ticket-rcs"
  : > "$STALENESS_RC_FILE"; : > "$STALENESS_TICKET_RC_FILE"
  printf '%s' "$1" > "$AGENTS_STATE_FILE"
  printf '%s' "$2" > "$GATE_RC_FILE"
  printf '%s' "$3" > "$LABELS_FILE"
  printf '%s' "$4" > "$PR_FILE"
  # #500 DEFAULT: an EMPTY trail, so every pre-existing case means what it meant — a ticket with
  # no queue label and no claim marker is still the plain reject, not a re-entry.
  printf '[]\n' > "$COMMENTS_FILE"
  : > "$GH_LOG"
  # #718 DEFAULT: the close-out's milestone-5 stream, two lines so its before/after differ — an
  # honest close-out, which is what keeps every approve case exiting 0 with `done`. A case that
  # wants the other polarity calls set_m5_tokens.
  printf 'm5-0\nm5-1\n' > "$PROGRESS_M5_FILE"
  # #531 DEFAULTS. An EMPTY inflight stream answers 0 on every call — a BUILD session that
  # collected its work — so every pre-existing case keeps meaning what it meant. The obligations
  # fixture is what the tool ECHOES when a close-out fails; its content is only ever asserted as
  # having been passed through, never parsed.
  INFLIGHT_RC_FILE="$d/inflight-rcs"; : > "$INFLIGHT_RC_FILE"
  # #590 DEFAULT, on the same principle: an EMPTY stream answers 0 on every call, so every
  # pre-existing approve case keeps meaning what it meant — a close-out that completed first try.
  CLOSEOUT_RC_FILE="$d/closeout-rcs"; : > "$CLOSEOUT_RC_FILE"
  PROGRESS_OBL_FILE="$d/progress-obligations"
  { echo "milestone-5 obligation exit-artifacts: met"
    echo "milestone-5 obligation verdict-reference: unmet"
    echo "milestone-5 aggregate: not satisfied"
    echo "teardown: not recorded"; } > "$PROGRESS_OBL_FILE"
}

set_m5_tokens() { # set_m5_tokens <m5-stream>
  printf '%s\n' "$1" > "$PROGRESS_M5_FILE"
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
         LEAN_SPAWN_BIN="${SPAWN_BIN_OVERRIDE:-$BIN/claude}"
         LEAN_GATE="$BIN/fake-gate.sh"
         SPAWN_LOG_DIR="$SPAWN_LOG_DIR" AGENTS_STATE_FILE="$AGENTS_STATE_FILE"
         SPAWN_ID_FILE="$SPAWN_ID_FILE" HOME="$CASE_HOME"
         # The poll interval and D-8's ceiling, pinned so the suite never sleeps and the
         # ceiling arm is reachable in one tick rather than in two hours.
         LEAN_SPAWN_POLL_SECS=0
         LEAN_SPAWN_SESSION_CEILING_MS="${SESSION_CEILING_OVERRIDE:-7200000}"
         # ZERO BY DEFAULT, which re-asks the premise on every tick — the behavior every case
         # written before the cadence existed assumes. Only the case that asserts the THROTTLE
         # sets it, so the throttle is proved by one case rather than assumed by all of them.
         LEAN_SPAWN_STALENESS_SECS="${STALENESS_SECS_OVERRIDE:-0}"
         # Real `date` unless a case drives elapsed time; CLOCK_FILE/CLOCK_STEP arm the fake.
         LEAN_SPAWN_CLOCK="${CLOCK_OVERRIDE:-date +%s}"
         CLOCK_FILE="${CLOCK_FILE:-$CASE_HOME/.clock}" CLOCK_STEP="${CLOCK_STEP:-60}"
         GATE_LOG_DIR="$GATE_LOG_DIR" GATE_RC_FILE="$GATE_RC_FILE"
         GH_LOG="$GH_LOG" LABELS_FILE="$LABELS_FILE" PR_FILE="$PR_FILE"
         COMMENTS_FILE="$COMMENTS_FILE" COMMENTS_FAIL="${COMMENTS_FAIL:-}"
         PROGRESS_M5_FILE="$PROGRESS_M5_FILE"
         PROGRESS_OBL_FILE="$PROGRESS_OBL_FILE" INFLIGHT_RC_FILE="$INFLIGHT_RC_FILE"
         CLOSEOUT_RC_FILE="$CLOSEOUT_RC_FILE"
         PR_FROM_SPAWN="${PR_FROM_SPAWN:-}"
         STALENESS_RC_FILE="$STALENESS_RC_FILE"
         STALENESS_TICKET_RC_FILE="$STALENESS_TICKET_RC_FILE"
         STATE_ANSWER="${STATE_ANSWER:-OPEN}"
         # #650 AC-1. EMPTY by default, and `${LEAN_LAUNCH_ID:-...}` in the tool treats empty as
         # unset — so every pre-existing case still exercises the PRODUCTION token expression and
         # only the cases that assert a transcript path pin one.
         LEAN_LAUNCH_ID="${LAUNCH_ID_OVERRIDE:-}"
         RUN_ID=poisoned-parent-run LEAN_RUN_MODEL=poisoned-parent-model )
  [ "${USE_DEFAULT_GH:-0}" -eq 1 ] || envs+=( GH="$BIN/gh" )
  # #811 OR-5. Same opt-out shape as GH above, and for the same reason: one case must run with
  # SECOND_SHIFT_CONFIG genuinely UNSET in the launcher, so the tool falls through to the
  # payload's own resolution ladder. `-u SECOND_SHIFT_CONFIG` precedes the assignments below, so
  # an ambient one in the developer's shell cannot make that case pass by accident.
  [ "${USE_DEFAULT_CONFIG:-0}" -eq 1 ] || envs+=( SECOND_SHIFT_CONFIG="$cfg" )
  # #613. Attendance is OPT-IN per case. Every pre-existing case keeps running with the session
  # id unset — which resolves headless, which is what makes their unchanged wording a real
  # assertion about the headless arm rather than an accident of this harness.
  [ -z "${ATTEND_SESSION:-}" ] || envs+=( CLAUDE_CODE_SESSION_ID="$ATTEND_SESSION" )
  # #531 D-5: the two streams now carry different KINDS of line, so one case has to see them
  # apart. Every other case keeps the merged view it was written against.
  if [ "${RUN_TOOL_SPLIT:-0}" -eq 1 ]; then
    ( cd "$TREE" \
      && env -u CLAUDE_CODE_SESSION_ID -u GH -u SECOND_SHIFT_CONFIG "${envs[@]}" bash "$TOOL" "$@" )
  else
    ( cd "$TREE" \
      && env -u CLAUDE_CODE_SESSION_ID -u GH -u SECOND_SHIFT_CONFIG "${envs[@]}" bash "$TOOL" "$@" 2>&1 )
  fi
}

# #531 D-1: the slug off a terminal control line. Anchored on the `] terminal: ` stem so the
# `terminal-vocabulary:` line the approved-head skip prints — which names a state the run passes
# THROUGH rather than ends at — cannot be mistaken for one.
slug_of() { sed -n 's/.*\] terminal: \([a-z][a-z-]*\) —.*/\1/p' <<<"$1"; }

spawn_count() { cat "$SPAWN_LOG_DIR/count" 2>/dev/null || echo 0; }
closeout_count() { cat "$GATE_LOG_DIR/ccount" 2>/dev/null || echo 0; }
set_closeout_rcs() { printf '%s\n' "$1" > "$CLOSEOUT_RC_FILE"; }
gate_count()  { cat "$GATE_LOG_DIR/count" 2>/dev/null || echo 0; }
# #496: how many gate calls ran on the RECORDING path. Capture-then-default, never
# `grep -c … || echo 0` — on zero matches grep prints "0" AND exits 1, so the `||` fires too and
# the helper emits "0\n0", which every `-eq 0` comparison through it then rejects as a
# non-integer. That shape survives only in suites where the counter never has to be zero, and
# this one exists precisely to assert a zero.
attempt_count() { local n; n="$(grep -c . "$GATE_LOG_DIR/attempts" 2>/dev/null)" || n=0; [ -n "$n" ] || n=0; echo "$n"; }
# Progress reads, counted per form: `m5` is the close-out's milestone-5 check, `obl` the
# obligations report. The `adv` continuation predicate went with the loop that read it (#718).
progress_reads() { cat "$GATE_LOG_DIR/pcount-${1:-m5}" 2>/dev/null || echo 0; }
# #531: in-flight reads, counted on their own arm.
inflight_reads() { cat "$GATE_LOG_DIR/fcount" 2>/dev/null || echo 0; }
inflight_log()   { cat "$GATE_LOG_DIR/inflight.log" 2>/dev/null; }
progress_log()   { cat "$GATE_LOG_DIR/progress.log" 2>/dev/null; }
# #515: staleness reads, counted per call site. `loop` is the pre-spawn check, `ticket` preflight's.
staleness_reads() { cat "$GATE_LOG_DIR/scount-${1:-loop}" 2>/dev/null || echo 0; }
staleness_log()   { cat "$GATE_LOG_DIR/staleness.log" 2>/dev/null; }
spawn_argv()  { sed -n 's/^ARGV: //p' "$SPAWN_LOG_DIR/spawn-$1" 2>/dev/null; }
spawn_settings_of() { sed -n 's/^SETTINGS: //p' "$SPAWN_LOG_DIR/spawn-$1" 2>/dev/null; }
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
setup_case "" "$V_APPROVE" "ready-for-dev
opus" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 2 ] && [ "$(gate_count)" -eq 2 ] \
   && [ "$(closeout_count)" -eq 1 ] \
   && grep -q 'build-lean 7' <<<"$(spawn_argv 1)" \
   && grep -q 'review-lean 11' <<<"$(spawn_argv 2)"; then
  pass "(b) approve ⇒ BUILD → REVIEW(pr from the tracker) → a close-out GATE CALL, exit 0 — #590 deleted the third spawn"
else fail "(b) expected rc=0 with 2 spawns / 2 gate calls / 1 close-out, got rc=$rc / $(spawn_count) / $(gate_count) / $(closeout_count): $out"; fi

# ...and that call lends NEITHER identity. Both scrubs are what keeps this script's
# authors-nothing rule true while it gains a call that WRITES: RUN_ID so the run's own cached id
# keys the records, CLAUDE_CODE_SESSION_ID so the scheduler's session can never reach a PR marker
# through the gate's `mark`.
if grep -q 'ARGV: close-out 7 ' "$GATE_LOG_DIR/closeout.log" 2>/dev/null \
   && ! grep -q 'RUN_ID_SET: yes' "$GATE_LOG_DIR/closeout.log" 2>/dev/null \
   && ! grep -q 'SESSION_SET: yes' "$GATE_LOG_DIR/closeout.log" 2>/dev/null; then
  pass "(b1a) the close-out gate call carries neither an ambient RUN_ID nor the scheduler's session id"
else fail "(b1a) the close-out call leaked an identity: $(cat "$GATE_LOG_DIR/closeout.log" 2>/dev/null)"; fi

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

# ---- (d) the child's environment, which is now carried IN ARGV -------------------------------
# #805 MOVED THIS ASSERTION, and the move is the contract change. Under `-p` the child inherited
# the launcher's environment, so the guard was a scrub — "RUN_ID must not be visible in there" —
# and the fake could measure it by reading its own env. Nothing inherits into a `--bg` session, so
# the scrub has nothing left to defend and the question became the opposite one: does the payload
# RECEIVE what it needs? That is answerable only from the `--settings` argument, which is why
# these read argv rather than the fake's environment. A fake cannot model non-inheritance for
# itself — it is an ordinary child of this shell and sees everything this shell exports — so an
# env-reading assertion here would now be measuring the harness, not the tool.
if grep -q '"LEAN_ATTEND_MODE":"headless"' <<<"$(spawn_settings_of 1)" \
   && grep -q '"LEAN_ATTEND_MODE":"headless"' <<<"$(spawn_settings_of 2)"; then
  pass "(d1) every spawn is POSITIVELY marked headless through --settings, not merely left unattended"
else fail "(d1) a spawn carried no headless mark in its --settings: $(all_argv)"; fi

if grep -q '"LEAN_RUN_MODEL":"sonnet"' <<<"$(spawn_settings_of 1)" \
   && grep -q '"LEAN_RUN_MODEL":"opus"' <<<"$(spawn_settings_of 2)"; then
  pass "(d2) LEAN_RUN_MODEL is set per PHASE in --settings — build's model on build, review's on review"
else fail "(d2) LEAN_RUN_MODEL was not re-set per phase: $(all_argv)"; fi

# THE PRINT-MODE CEILING IS GONE, and stays asserted gone. It existed because a print-mode turn
# ended over its own pending work; a supervised session stays `working` through it, so re-adding
# the variable would be re-adding a bound that cuts a healthy session short.
if ! grep -q 'CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS' "$TOOL" \
   && ! grep -q 'SPAWN_BG_WAIT_CEILING_MS' "$TOOL"; then
  pass "(d3) the print-mode background-wait ceiling is gone with the turn semantics that needed it"
else fail "(d3) the tool still carries the print-mode wait ceiling"; fi

# THE SCRUB IS NOT GONE — one half of it came back, and this is the case that holds it there.
# Round 4 of review: D-9 measured that a bg session inherits nothing, and the whole `env -u
# RUN_ID -u LEAN_RUN_MODEL` scrub was deleted on that measurement. But LEAN_RUN_MODEL is
# re-asserted in the settings block ((d2) above) and RUN_ID is asserted NOWHERE, so RUN_ID was the
# one variable whose defense was removed rather than moved — and an inherited RUN_ID keys a
# child's records to the parent's run, which is a wrong answer no other guard in this repo reads.
#
# MEASURABLE PRECISELY BECAUSE THE FAKE CANNOT MODEL NON-INHERITANCE. The fake is an ordinary
# child of this shell and sees everything it exports, and `run_tool` exports
# RUN_ID=poisoned-parent-run — so with the scrub removed this case reads `yes` and fails. That is
# the opposite of (d1)/(d2)'s situation and is what makes it a guard rather than a restatement.
if ! grep -q '^RUN_ID_SET: yes$' "$SPAWN_LOG_DIR"/spawn-* 2>/dev/null; then
  pass "(d3a) RUN_ID does not reach a spawned payload — the half of the scrub the settings block does not re-assert is still defended"
else fail "(d3a) the parent's RUN_ID reached a spawned session: $(cat "$SPAWN_LOG_DIR"/spawn-* 2>/dev/null)"; fi

# ...and the settings block is a FILE, not an argument. `OTEL_EXPORTER_OTLP_HEADERS` is the
# standard carrier for a collector's auth material, and a command line is world-readable on every
# platform this runs on while an environment is not — so passing the block as argv would have been
# strictly more exposed than the `-p` inheritance the forwarding exists to keep at parity.
if grep -qE -- '--settings /' <<<"$(spawn_argv 1)" \
   && ! grep -q 'LEAN_ATTEND_MODE' <<<"$(spawn_argv 1)" \
   && [ -n "$(spawn_settings_of 1)" ]; then
  pass "(d3b) the child's environment travels by FILE PATH, never in argv — the block is readable to the payload and not to every process on the box"
else fail "(d3b) the settings block was passed in argv, or no file reached the fake: $(spawn_argv 1)"; fi

# #811 OR-5. SECOND_SHIFT_CONFIG REACHES THE PAYLOAD, and this is the arm the transport swap broke
# in silence. The gate resolves it INSIDE the session — lean-gate.sh and seven siblings share one
# `${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}` ladder — so under `-p` it
# inherited and under `--bg` it did not, and a launch carrying an alternate config (the pinned-base
# eval recipe, the lane bench) fell back to the COMMITTED one and targeted the wrong base branch
# with no error anywhere. A silent wrong answer, which is why it is asserted on content.
if grep -q "\"SECOND_SHIFT_CONFIG\":\"$CFG\"" <<<"$(spawn_settings_of 1)" \
   && grep -q "\"SECOND_SHIFT_CONFIG\":\"$CFG\"" <<<"$(spawn_settings_of 2)"; then
  pass "(d4) an alternate SECOND_SHIFT_CONFIG is forwarded VERBATIM to every spawn — the payload resolves the config the launcher chose, not the committed one"
else fail "(d4) SECOND_SHIFT_CONFIG did not reach a spawn: $(spawn_settings_of 1) / $(spawn_settings_of 2)"; fi

# ...and the KEY IS ABSENT when the launcher set none. Without this the forwarding could be
# unconditional — writing an empty or a scheduler-invented value into the child's environment,
# which would override the payload's own ladder with a worse answer than inheriting nothing. The
# committed config is placed at the default path so the run still resolves and the case is
# measuring the key's absence rather than a refusal.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
mkdir -p "$TREE/.claude"
cp "$CFG" "$TREE/.claude/second-shift.config.json"
out="$(USE_DEFAULT_CONFIG=1 run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ -n "$(spawn_settings_of 1)" ] \
   && ! grep -q 'SECOND_SHIFT_CONFIG' <<<"$(spawn_settings_of 1)"; then
  pass "(d4a) a launcher that set no SECOND_SHIFT_CONFIG forwards no key — the payload keeps its own resolution ladder rather than being handed a value the scheduler invented"
else fail "(d4a) the scheduler forwarded a config key it was never given, rc=$rc: $(spawn_settings_of 1)"; fi

# ---- (e) fresh contexts, never a resumed one --------------------------------------------------
if grep -qE -- '(^| )--bg( |$)' <<<"$(all_argv)" \
   && grep -qE -- '(^| )--model ' <<<"$(all_argv)" \
   && ! grep -qE -- '--resume|--continue|(^| )-c( |$)|(^| )-p ' <<<"$(all_argv)"; then
  pass "(e1) every spawn is a fresh supervised session: --bg + --model, no -p and no --resume/--continue/-c"
else fail "(e1) spawn argv carried a resume flag, or lost --bg/--model: $(all_argv)"; fi

# D-6. The one prompt source a real payload reaches is removed at dispatch, which is the parity
# `-p` had for free by not offering the tool. Without it a payload that asks a question reads
# `blocked` and ends the run — a stop where print mode simply carried on.
if ! grep -q 'AskUserQuestion' <<<"$(all_argv | sed 's/--disallowedTools AskUserQuestion//g')" \
   && [ "$(all_argv | grep -c -- '--disallowedTools AskUserQuestion')" -eq 2 ]; then
  pass "(e1a) every spawn removes AskUserQuestion, the one prompt source a headless payload can reach"
else fail "(e1a) a spawn did not disallow AskUserQuestion: $(all_argv)"; fi

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
# #613 AC-3 changed the CODE this exits with, and nothing else about it: the unintaken reject is
# now RESUMABLE and says so, where every other preflight refusal stays 2. The probe's own wording
# is asserted unchanged in the same breath, because that half is what AC-3 binds for a headless
# run — which this is, the harness leaving the session id unset.
setup_case "" "$V_APPROVE" "" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 3 ] && [ "$(spawn_count)" -eq 0 ] \
   && [ "$(slug_of "$out")" = "preflight-rejected-resumable" ] \
   && grep -q 'FAIL intake' <<<"$out" \
   && grep -q 'does not spawn an intake session' <<<"$out" \
   && grep -q 'attendance: headless' <<<"$out"; then
  pass "(g1) a ticket without the queue label is rejected before any spawn, with the RESUMABLE code and the hand-back wording unchanged"
else fail "(g1) expected rc=3 / slug preflight-rejected-resumable / 0 spawns, got rc=$rc / '$(slug_of "$out")' / $(spawn_count): $out"; fi

# The affordance is NOT printed to a headless run: this is the reject a scheduler payload sees,
# and a command it cannot legally run would be noise at best.
if ! grep -q 'record --gate intake-unqueued' <<<"$out"; then
  pass "(g1b) AC-3: headless, the reject offers no record-writing command"
else fail "(g1b) the affordance leaked into a headless reject: $out"; fi

setup_case "" "$V_APPROVE" "" "11"
SPAWN_BIN_OVERRIDE="$WORK/no-such-binary" \
  out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
unset SPAWN_BIN_OVERRIDE
if [ "$rc" -eq 2 ] \
   && grep -q 'FAIL intake' <<<"$out" \
   && grep -q 'FAIL spawn' <<<"$out"; then
  pass "(g2) two failing probes are BOTH reported from one invocation — no first-failure abort"
else fail "(g2) expected both probe failures in one run, got rc=$rc: $out"; fi

# #613 AC-3, the other half of (g1): the resumable code is claimed ONLY when the unintaken probe
# is the SOLE failure. This run is not resumable by paying off intake — the session binary is
# missing — so it must read as the ordinary terminal reject. (g2) already pins rc=2; what is new
# is that the SLUG did not become the resumable one.
if [ "$(slug_of "$out")" = "preflight-rejected" ]; then
  pass "(g2b) AC-3: an unintaken ticket alongside another failing probe is NOT resumable"
else fail "(g2b) expected slug preflight-rejected, got '$(slug_of "$out")': $out"; fi

# The probes run concurrently. That is not directly observable from outside, so what is asserted
# is the property concurrency has to preserve and a serial short-circuit would not: the ok/FAIL
# verdict of every probe is present regardless of which ones failed.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
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
setup_case "" "$V_APPROVE" "in-progress" "11"
set_claim_trail Bot lean-500-abc123
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 2 ] \
   && grep -q 'ok intake: re-entry' <<<"$out" \
   && grep -q 'lean-500-abc123' <<<"$out"; then
  pass "(s1) a claimed ticket carrying this lane's bot-authored marker is accepted as re-entry, and the accept names the marker's run id"
else fail "(s1) expected rc=0 with 2 spawns and a named re-entry, got rc=$rc / $(spawn_count) spawn(s): $out"; fi

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
setup_case "" "$V_APPROVE" "in-progress" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q "no bot-authored 'lean-claimed' marker" <<<"$out"; then
  pass "(s4) the claimed label with no marker is rejected — the conjunction is the guard, not either half"
else fail "(s4) expected rc=2 with 0 spawns on a markerless claimed ticket, got rc=$rc / $(spawn_count): $out"; fi

# AC-5's other half. Issue comments are writable by any account on a public repo, so an
# operator-posted marker must not be re-entry evidence: with the marker authored by a USER the
# whole trail — decoys included — has nothing bot-authored, and the run rejects.
setup_case "" "$V_APPROVE" "in-progress" "11"
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
setup_case "" "$V_APPROVE" "in-progress" "11"
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
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --intake-attested)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q -- 'unknown option: --intake-attested' <<<"$out"; then
  pass "(s7) the retired --intake-attested is an unknown option, not a silently accepted no-op"
else fail "(s7) expected an unknown-option reject, got rc=$rc / $(spawn_count): $out"; fi

# ---- (ov) #613: the THIRD accepting state, and the affordance the reject offers ---------------
# The unintaken ticket keeps rejecting for a headless run — (g1) above — and these cases are what
# an ATTENDED operator gets instead. The two halves are kept apart on purpose: a token alone
# reaches only the printed command, and only a RECORD accepts.
#
# The identity is opted into per case through ATTEND_SESSION; RUN_ID is whatever run_tool already
# poisons the environment with, which is exactly the ambient id probe_intake resolves against.
OV_TOOL="$HERE/../../tools/operator-override.sh"
OV_RECORD="$TREE/docs/plans/acme-$ISSUE-lean-override.md"
mint_attendance() { # mint_attendance <session-id>
  mkdir -p "$TREE/.claude/pipeline-state"
  printf 'session_id: %s\nrun_id: poisoned-parent-run\n' "$1" > "$TREE/.claude/pipeline-state/attend-$1.token"
}
drop_attendance() { rm -rf "$TREE/.claude/pipeline-state" "$OV_RECORD"; }

if [ ! -f "$OV_TOOL" ]; then
  fail "(ov0) the override mechanism at $OV_TOOL is absent — the three cases below would all pass vacuously"
else
  pass "(ov0) the override mechanism resolves at the path the scheduler defaults to"

  # (ov1) ATTENDED, NO RECORD: still a reject, still resumable — and now carrying the exact
  # command. This is the epic's central claim at a consumer: the signal alone unlocks nothing.
  drop_attendance
  mint_attendance ov-session-1
  setup_case "" "$V_APPROVE" "" "11"
  ATTEND_SESSION=ov-session-1 out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
  unset ATTEND_SESSION
  if [ "$rc" -eq 3 ] && [ "$(spawn_count)" -eq 0 ] \
     && grep -q 'attendance: attended' <<<"$out" \
     && grep -q 'record --gate intake-unqueued --scope intake-attestation' <<<"$out" \
     && grep -q 'does not spawn an intake session' <<<"$out"; then
    pass "(ov1) AC-3: attended with no record still REJECTS, and prints the exact record-writing command"
  else fail "(ov1) expected rc=3 with the affordance printed, got rc=$rc / $(spawn_count): $out"; fi

  # (ov2) ATTENDED WITH A RECORD: accepted, the run proceeds, and NOTHING is re-labelled. The
  # tracker-write assertion is the half that makes "no re-labelling" checkable rather than a claim
  # about intent — a lane that quietly added the queue label would satisfy the accept and fail
  # here.
  drop_attendance
  mint_attendance ov-session-2
  setup_case "" "$V_APPROVE" "" "11"
  ( cd "$TREE" && env RUN_ID=poisoned-parent-run CLAUDE_CODE_SESSION_ID=ov-session-2 \
      SECOND_SHIFT_CONFIG="$CFG" bash "$OV_TOOL" record \
      --gate intake-unqueued --scope intake-attestation --issue "$ISSUE" \
      --decision 'intake was run in this session; proceed without re-labelling' \
      --answer 'I ran intake here — go.' --repo-root "$TREE" ) >/dev/null 2>&1
  ATTEND_SESSION=ov-session-2 out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
  unset ATTEND_SESSION
  if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 2 ] \
     && grep -q 'recorded operator override' <<<"$out" \
     && grep -q 'nothing is re-labelled' <<<"$out" \
     && ! grep -qE 'issue (edit|comment)|-X (POST|PATCH|PUT|DELETE)' "$GH_LOG"; then
    pass "(ov2) AC-3: a recorded override accepts an unintaken ticket and the run proceeds — with no tracker write at all"
  else fail "(ov2) expected rc=0 / 2 spawns / a named override accept and zero writes, got rc=$rc / $(spawn_count): $out"; fi

  # (ov3) A MALFORMED record is UNKNOWN, never a clean reject: fail-closed, and NOT resumable,
  # because the remedy is fixing the record rather than paying off intake. Without this case a
  # tool that folded rc 2 into rc 1 would look identical to (ov1).
  drop_attendance
  mint_attendance ov-session-3
  mkdir -p "$TREE/docs/plans"
  printf '## Override 1\ngate: intake-unqueued\nscope: not-a-scope\nissue: %s\nregion: none\nrun_id: r\nsession_id: s\nexpiry: run\ndecision: d\n\n### Operator answer\n\n> a\n' "$ISSUE" > "$OV_RECORD"
  setup_case "" "$V_APPROVE" "" "11"
  ATTEND_SESSION=ov-session-3 out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
  unset ATTEND_SESSION
  if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
     && [ "$(slug_of "$out")" = "preflight-rejected" ] \
     && grep -q 'could not be read as a clean answer' <<<"$out"; then
    pass "(ov3) a malformed override record fails CLOSED and is not the resumable reject"
  else fail "(ov3) expected rc=2 / slug preflight-rejected, got rc=$rc / '$(slug_of "$out")' / $(spawn_count): $out"; fi
  drop_attendance
fi

# AC-4/AC-1, the conjunction's OTHER half. A marker with no claimed label is a stale claim on a
# ticket whose label was hand-reset — the lane's own bookkeeping says this ticket is not in flight,
# and a marker from some earlier run must not override that. Without this case a tool that dropped
# the label check entirely would pass every other case in this section.
setup_case "" "$V_APPROVE" "" "11"
set_claim_trail Bot lean-500-abc123
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
# rc 3, not 2, since #613: this ticket presents as unintaken and that IS the resumable class. The
# assertion that matters here is unchanged — it fell through to the plain reject rather than being
# read as re-entry.
if [ "$rc" -eq 3 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q "does not carry 'ready-for-dev'" <<<"$out" \
   && ! grep -q 're-entry' <<<"$out"; then
  pass "(s10) a bot marker with NO claimed label is not re-entry — both halves of the conjunction are load-bearing"
else fail "(s10) a markered ticket with no claimed label was accepted, got rc=$rc / $(spawn_count): $out"; fi

# AC-4's ordering half: the queue label still wins outright, and the ordinary fresh run costs no
# comment read at all. A tool that read the trail unconditionally would pass every case above while
# adding a tracker round-trip to every launch in the lane.
setup_case "" "$V_APPROVE" "ready-for-dev
in-progress" "11"
set_claim_trail Bot lean-500-abc123
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q "carries the 'ready-for-dev' queue label" <<<"$out" \
   && ! grep -q 're-entry' <<<"$out" \
   && ! grep -q "api repos/{owner}/{repo}/issues/$ISSUE/comments" "$GH_LOG"; then
  pass "(s9) the queue label wins outright: a fresh queued ticket is accepted as such and never pays for the comment read"
else fail "(s9) the queue-label arm did not short-circuit, rc=$rc: $out / $(cat "$GH_LOG")"; fi

# ---- (h) needs-work: a fix round and a NEW review context ---------------------------------------
setup_case "" "$V_NEEDSWORK_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 4 ] && [ "$(gate_count)" -eq 4 ] \
   && [ "$(closeout_count)" -eq 1 ] \
   && grep -q 'build-lean 7' <<<"$(spawn_argv 3)" \
   && grep -q 'review-lean 11' <<<"$(spawn_argv 4)"; then
  pass "(h1) needs-work ⇒ a fresh fix BUILD then a fresh REVIEW, then the close-out call on the approve"
else fail "(h1) expected 4 spawns / 4 gate calls / 1 close-out, got rc=$rc / $(spawn_count) / $(gate_count) / $(closeout_count): $out"; fi

if ! grep -qE -- '--resume|--continue' <<<"$(spawn_argv 4)"; then
  pass "(h2) round 2's review is a NEW context, not round 1's resumed"
else fail "(h2) round 2's review resumed a context: $(spawn_argv 4)"; fi

# ---- (h4) #718: ONE build spawn per round, and both of its dead ends ----------------------------
# The whole ticket in one case. A BUILD session that exits 0 is read for exactly one thing — did it
# leave an open PR the review can run against — and each answer that is not "yes" ends the run for
# a human. Three mechanisms stood behind those exits (a continuation budget, two opaque token
# spaces, an in-flight recovery counter), none of which could read the lane log.
#
# EXACTLY ONE SPAWN IS THE ASSERTION, not "at least one": the deleted loop's residue shows up here
# as a second one, and every re-add mutant this ticket lists reaches that number.

# Arm 1 — exit 0, no PR, a clean worktree. The stop is `build-no-pr`, and the in-flight check is
# never reached, because there is no PR to make its question meaningful.
setup_case "" "$V_APPROVE" "ready-for-dev" ""
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 1 ] && [ "$(inflight_reads)" -eq 0 ] \
   && [ "$(slug_of "$out")" = "build-no-pr" ] \
   && grep -q 'a human decides' <<<"$out" \
   && grep -qE "claude attach [A-Za-z0-9-]+' reaches" <<<"$out" \
   && grep -q 'worktree and the claim are left in place' <<<"$out"; then
  pass "(h4) exit 0 with no PR is ONE spawn and a terminal build-no-pr that hands the run to a human"
else fail "(h4) expected rc=1 / 1 spawn / 0 in-flight reads / slug build-no-pr, got rc=$rc / $(spawn_count) / $(inflight_reads) / '$(slug_of "$out")': $out"; fi

# Arm 2 — exit 0, a PR IS open, and the gate answers 8: the worktree holds work nothing else has a
# copy of. Still one spawn. The read's SHAPE is asserted here too, which is what (t3) used to own:
# from MAIN_ROOT, never the lane worktree whose last act in a close-out is deleting itself, and
# with RUN_ID scrubbed like every other gate call this script makes.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
printf '8\n' > "$INFLIGHT_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 1 ] && [ "$(inflight_reads)" -eq 1 ] \
   && [ "$(slug_of "$out")" = "build-inflight" ] \
   && grep -q 'HARD STOP' <<<"$out" \
   && ! grep -q 're-spawning BUILD' <<<"$out" \
   && grep -q "CWD: $TREE " <<<"$(inflight_log)" \
   && ! grep -q 'RUN_ID_SET: yes' <<<"$(inflight_log)"; then
  pass "(h4) an in-flight 8 is ONE spawn and a terminal build-inflight, read from the main checkout with RUN_ID scrubbed"
else fail "(h4) expected rc=1 / 1 spawn / 1 in-flight read / slug build-inflight, got rc=$rc / $(spawn_count) / $(inflight_reads) / '$(slug_of "$out")': $(inflight_log)
$out"; fi

# Arm 3 — the flag that drove the deleted budget is a usage REFUSAL naming the removal, not a
# silently-ignored argument. A wrapper or a runbook still passing it must learn that from the
# scheduler rather than from a run that quietly behaves differently than it asked for.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --max-continuations 2)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q -- '--max-continuations was removed' <<<"$out"; then
  pass "(h4) --max-continuations is a usage refusal naming the removal, not an accepted no-op"
else fail "(h4) expected rc=2 with no spawn on the removed flag, got rc=$rc / $(spawn_count): $out"; fi

# ---- (i) the two hard-stop routes ----------------------------------------------------------------
setup_case "" $'5\n4' "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 4 ] && [ "$(spawn_count)" -eq 2 ] \
   && grep -q 'HARD STOP' <<<"$out" \
   && grep -q 'No rescue attempt' <<<"$out"; then
  pass "(i1) the gate's own rc=4 is a hard stop: no close-out, no fix round, no rescue"
else fail "(i1) expected rc=4 after 2 spawns, got rc=$rc / $(spawn_count): $out"; fi

# The second route exists because the gate's counter lives in a file a fix round can reset: a
# scheduler with no bound of its own would loop forever against a gate that only ever says 1.
setup_case "" $'5\n1\n5\n1' "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --max-rounds 2)"; rc=$?
if [ "$rc" -eq 4 ] && [ "$(spawn_count)" -eq 4 ] && [ "$(gate_count)" -eq 4 ] \
   && grep -q '2 rounds spent' <<<"$out"; then
  pass "(i2) --max-rounds bounds the loop independently of the gate's own counter"
else fail "(i2) expected rc=4 after 2 rounds / 4 gate calls, got rc=$rc / $(spawn_count) spawn(s) / $(gate_count) gate call(s): $out"; fi

# ---- (j) a failing session is a phase failure, not a silent next round ----------------------------
# #805: the fixture is a STATE the supervisor reports, not a non-zero exit — a `--bg` dispatch
# always returns 0 and the payload's fate arrives from the listing. `failed` and `stopped` are
# separate documented states and both end the phase, so both are driven rather than one standing
# in for the pair.
setup_case "failed" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 1 ] && [ "$(gate_count)" -eq 0 ] \
   && grep -q 'BUILD session sess1 ended failed' <<<"$out" \
   && [ "$(slug_of "$out")" = "build-session-failed" ]; then
  pass "(j1) a BUILD session the supervisor reports as failed stops the run at exit 1 — the gate is never consulted"
else fail "(j1) expected rc=1 after 1 spawn, got rc=$rc / $(spawn_count) / slug=$(slug_of "$out"): $out"; fi

setup_case "stopped" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
# The stop hygiene rides on the same case rather than a twin, because it is a property of THIS
# terminal rather than a scenario of its own: `stopped` is the state where "still in flight" is
# most obviously false, and the handle `spawn` leaves behind is the only thing that decides it.
# A tool that keeps the handle here announces a stop of a session the listing just reported as
# ended, and issues it.
if [ "$rc" -eq 1 ] && [ "$(gate_count)" -eq 0 ] \
   && [ "$(slug_of "$out")" = "build-session-failed" ] \
   && grep -q 'ended stopped' <<<"$out" \
   && ! grep -q 'still in flight' <<<"$out" \
   && [ ! -s "$SPAWN_LOG_DIR/stops" ]; then
  pass "(j1a) 'stopped' is the same phase failure as 'failed' — a session somebody ended is not one that finished, and is not announced as in flight nor stopped a second time"
else fail "(j1a) expected rc=1 with build-session-failed and no re-stop, got rc=$rc / slug=$(slug_of "$out") / stops=[$(cat "$SPAWN_LOG_DIR/stops" 2>/dev/null)]: $out"; fi

setup_case "" "$V_APPROVE" "ready-for-dev" ""
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 1 ] \
   && grep -q 'no open PR' <<<"$out"; then
  pass "(j2) a BUILD that left no open PR stops at exit 1 rather than reviewing nothing"
else fail "(j2) expected rc=1 on an absent PR, got rc=$rc: $out"; fi

# ---- (o) #492: exit 0 + no PR is THREE states, not two ------------------------------------------
# `claude -p` exits 0 when the model ends its turn, not when the block finishes, so "exited 0 and
# left no PR" splits into "did nothing" (j2, above) and "advanced and stopped early" (here). The
# whole section turns on the tool being able to tell them apart from an artifact.

# #718 DELETED THE (o) AND (oi) SECTIONS, and (j3) with them. Thirteen cases stood here over two
# opaque token spaces — #492's continuation predicate and #527's infra-death read — pinning a loop
# that re-spawned BUILD when a session exited 0 and opened no PR. There is no such loop and no such
# token: one spawn, then (j2) above and (h4) below, then a human. (j3) asserted the two reads
# happened at all, which is what went away.

# ---- (p) #590: the close-out is READ FROM ITS EXIT CODE ------------------------------------------
# #492 AC-7 put a token comparison here because the close-out was a `claude -p` session, which
# exits 0 whenever the model ends its turn — so `done` was printed over a session that had done
# nothing. A gate command cannot end its turn early, and D-5 retired the comparison for the rule
# every other call site already follows. These three cases are that rule, driven at the seam.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
set_closeout_rcs $'1\n1'
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(closeout_count)" -eq 2 ] \
   && grep -q 'close-out did not complete' <<<"$out" \
   && ! grep -q 'done — #' <<<"$out"; then
  pass "(p1) a close-out whose gate call reds twice is a non-zero exit, not 'done'"
else fail "(p1) expected rc=1 after 2 close-out calls, got rc=$rc / $(closeout_count) call(s): $out"; fi

# ONE retry, hard-coded — never two, and never a spawn. The bound is MAX_REVIEW_RETRIES' reasoning
# at a cheaper site, and the whole point of deleting the session is that nothing here is worth
# paying a model to re-attempt a third time.
if [ "$(closeout_count)" -eq 2 ] && [ "$(spawn_count)" -eq 2 ] \
   && [ "$(slug_of "$out")" = "closeout-incomplete" ]; then
  pass "(p2) the retry budget is exactly one, and the failure is its own slug — no third call, no re-spawn"
else fail "(p2) expected 2 close-out calls / 2 spawns / slug closeout-incomplete, got $(closeout_count) / $(spawn_count) / '$(slug_of "$out")'"; fi

# The failure carries the gate's per-obligation report — the states come from the GATE, and this
# script echoes them. Asserted on the passed-through lines rather than on wording it could invent,
# which is what keeps the scheduler from growing a reader of the record's schema.
if grep -q 'obligation exit-artifacts: met' <<<"$out" \
   && grep -q 'obligation verdict-reference: unmet' <<<"$out" \
   && grep -q 'teardown: not recorded' <<<"$out" \
   && [ "$(progress_reads obl)" -ge 1 ]; then
  pass "(p2a) the close-out failure carries the gate's per-obligation report, teardown included as its own line"
else fail "(p2a) the obligation report was not echoed ($(progress_reads obl) read(s)): $out"; fi

# NON-VACUITY. (p1) would also pass against a tool that failed every close-out unconditionally,
# and (p2) against one that never retried. A FIRST call that succeeds is one call and a `done`;
# a first that reds and a second that succeeds is two calls and a `done`.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(closeout_count)" -eq 1 ] \
   && grep -q 'done — #7 approved on PR #11' <<<"$out"; then
  pass "(p3) a close-out that completes first try is ONE call and 'done' — the read is an exit code, not a blanket refusal"
else fail "(p3) expected rc=0 with 1 close-out call, got rc=$rc / $(closeout_count): $out"; fi

setup_case "" "$V_APPROVE" "ready-for-dev" "11"
set_closeout_rcs $'1\n0'
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(closeout_count)" -eq 2 ] \
   && grep -q 'retrying once' <<<"$out" \
   && grep -q 'done — #7 approved on PR #11' <<<"$out"; then
  pass "(p4) the one retry is real: a first red followed by a green reaches 'done' on the second call"
else fail "(p4) expected rc=0 after a retried close-out, got rc=$rc / $(closeout_count): $out"; fi

# ---- (k) model resolution stays the caller's ------------------------------------------------------
# #490: a departure from the shipped review tier now requires a stated reason, so this case
# carries --review-model-basis alongside its --review-model override, where before it needed
# none — the case still proves the override itself reaches the spawn.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model opus --review-model sonnet --model-basis 'sized-here: two gates' --review-model-basis 'sized-here: reviewer rate limited')"; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -q '"LEAN_RUN_MODEL":"sonnet"' <<<"$(spawn_settings_of 2)" \
   && grep -q 'basis: sized-here: two gates' <<<"$out" \
   && grep -q 'basis: sized-here: reviewer rate limited' <<<"$out"; then
  pass "(k1) --review-model overrides the shipped default, and BOTH --model-basis and --review-model-basis are echoed into the run log"
else fail "(k1) review model or basis did not take: rc=$rc: $out"; fi

# A non-default --review-model with no --review-model-basis is a usage refusal, nothing spawned,
# and the message names the flag that resolves it — the AC-2 defect this ticket closes.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --review-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q -- '--review-model-basis' <<<"$out" \
   && grep -q 'departs from the shipped default' <<<"$out"; then
  pass "(k2) a non-default --review-model with no --review-model-basis is a usage refusal naming the flag, nothing spawned"
else fail "(k2) expected rc=2 with 0 spawns, got rc=$rc / $(spawn_count): $out"; fi

# A stated departure is accepted: the override reaches the spawn and the reason is echoed.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --review-model sonnet --review-model-basis 'sized-here: rate-limited on opus')"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 2 ] \
   && grep -q '"LEAN_RUN_MODEL":"sonnet"' <<<"$(spawn_settings_of 2)" \
   && grep -q 'basis: sized-here: rate-limited on opus' <<<"$out"; then
  pass "(k3) a stated --review-model-basis is accepted: the departure reaches the spawn and the reason is echoed"
else fail "(k3) expected rc=0 with the departure taking and the basis echoed, got rc=$rc / $(spawn_count): $out"; fi

# The untouched happy path: omitting --review-model needs no basis, and the review spawn still
# gets the shipped default tier with no basis note in the log.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '"LEAN_RUN_MODEL":"opus"' <<<"$(spawn_settings_of 2)" \
   && ! grep -q 'review model: opus (basis' <<<"$out"; then
  pass "(k4) omitting --review-model needs no basis, and the review spawn still gets the shipped default tier"
else fail "(k4) expected rc=0 with the review spawn on the default tier and no basis note, got rc=$rc: $out"; fi

# AC-3/AC-4: the default passed EXPLICITLY is the default, not a departure — no basis required.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --review-model opus)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '"LEAN_RUN_MODEL":"opus"' <<<"$(spawn_settings_of 2)" \
   && ! grep -q 'review model: opus (basis' <<<"$out"; then
  pass "(k5) --review-model opus passed explicitly is the shipped default, not a departure — no basis required"
else fail "(k5) expected rc=0 with no basis required, got rc=$rc: $out"; fi

# AC-4: volunteering a basis for a default-tier review is accepted and echoed, never refused.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet --review-model opus --review-model-basis 'confirming default explicitly')"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'review model: opus (basis: confirming default explicitly)' <<<"$out"; then
  pass "(k6) a basis volunteered alongside the default-tier review is accepted and echoed, never refused"
else fail "(k6) expected rc=0 with the volunteered basis echoed, got rc=$rc: $out"; fi

# ---- (l) --dry-run prints the schedule and spawns nothing -------------------------------------------
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
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
setup_case "" "$V_APPROVE" "" "11"
out="$(run_tool "$CFG_JIRA" ACME-7 --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -gt 0 ] \
   && grep -q "tracker 'jira'" <<<"$out" \
   && grep -q 'intake is not gated here' <<<"$out" \
   && grep -q 'Run /intake-toolkit:intake before the lane' <<<"$out"; then
  pass "(m1) a tracker with no queue label is ungated: preflight names the tracker, says so, and the run proceeds"
else fail "(m1) expected an ungated jira run naming the tracker, got rc=$rc / $(spawn_count): $out"; fi

setup_case "" "$V_APPROVE" "" "11"
out="$(run_tool "$CFG_JIRA" ACME-7 --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'build-lean ACME-7' <<<"$(spawn_argv 1)" \
   && grep -q "^CWD: $WORK/wt$" "$GATE_LOG_DIR/call-1" 2>/dev/null; then
  pass "(m2) the jira key reaches the payload unlowercased while the BRANCH is lowercased"
else fail "(m2) expected a clean jira run, got rc=$rc: $out"; fi

setup_case "" "$V_APPROVE" "ready-for-dev" "11"
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
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
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
setup_case "" $'5\n5\n0' "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 3 ] && [ "$(gate_count)" -eq 3 ] \
   && [ "$(closeout_count)" -eq 1 ] \
   && grep -q 'review-lean 11' <<<"$(spawn_argv 2)" \
   && grep -q 'review-lean 11' <<<"$(spawn_argv 3)" \
   && grep -q 'No round spent, no BUILD spawn' <<<"$out"; then
  pass "(r1) a class-5 read re-spawns REVIEW — not BUILD — and spends no round"
else fail "(r1) expected rc=0 with build,review,review and 3 gate calls, got rc=$rc / $(spawn_count) spawn(s) / $(gate_count) gate call(s): $out"; fi

# ...and the retry is BOUNDED at one. A second dark review is a broken review lane, so the run
# exits 5 naming it rather than spending the round budget on sessions that produce no record.
setup_case "" "5
5
5" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 5 ] && [ "$(spawn_count)" -eq 3 ] && [ "$(gate_count)" -eq 3 ] \
   && grep -q 'HARD STOP' <<<"$out" \
   && grep -q 'no verdict record usable against the current head, twice' <<<"$out"; then
  pass "(r2) two class-5 reads in one round is a bounded stop at exit 5, not a third review and not a fix round"
else fail "(r2) expected rc=5 after 3 spawns / 3 gate calls, got rc=$rc / $(spawn_count) / $(gate_count): $out"; fi

# The BUILD spawn count is the load-bearing half of (r1)/(r2): a class-5 that fell through to the
# needs-work arm would look similar in exit code from some angles but would have re-spawned BUILD.
if [ "$(grep -l 'build-lean' "$SPAWN_LOG_DIR"/spawn-* 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]; then
  pass "(r3) across both dark reviews exactly ONE build-lean session ran — BUILD is never asked to fix a review-half failure"
else fail "(r3) a class-5 round spawned BUILD again: $(all_argv)"; fi

# Class 6 — an integrity refusal is TERMINAL. Scripted with a second gate rc that would approve,
# so a fall-through to the needs-work arm would be visible as a green run rather than as a
# different failure.
setup_case "" $'5\n6' "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 6 ] && [ "$(spawn_count)" -eq 2 ] && [ "$(gate_count)" -eq 2 ] \
   && grep -q 'HARD STOP' <<<"$out" \
   && grep -q 'P10' <<<"$out"; then
  pass "(r4) a class-6 integrity refusal exits 6 immediately — nothing re-spawned, no round spent, and the message names P10"
else fail "(r4) expected rc=6 after 2 spawns / 2 gate calls, got rc=$rc / $(spawn_count) / $(gate_count): $out"; fi

# AC-6: across a whole approved round the scheduler's verdict read records NOTHING. It used to run
# the gate's recording path, so every non-approve verdict it merely READ spent the BUILD role's
# milestone-4 fix budget — the "this script writes nothing" premise was false at exactly one site.
setup_case "" "$V_NEEDSWORK_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(gate_count)" -eq 4 ] && [ "$(attempt_count)" -eq 0 ]; then
  pass "(r5) a full needs-work-then-approve run makes both verdict reads through the observe seam — zero recording-path calls"
else fail "(r5) expected 4 gate calls and 0 recording-path calls, got rc=$rc / $(gate_count) / $(attempt_count): $out"; fi

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
setup_case "" "$V_APPROVE" "ready-for-dev" "11
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
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
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
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$WORK/no-such-config.json" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 2 ]; then
  pass "(r10) an ABSENT config still resolves the shipped defaults — the guard fails closed on corruption only"
else fail "(r10) an absent config was refused, got rc=$rc / $(spawn_count) spawn(s): $out"; fi

# ---- (v) #515: the run's premise is re-checked before every BUILD spawn, and only those --------
# What this block owns is the scheduler's WIRING — which call sites exist, with which arm, in which
# order, and how each rc routes. What it deliberately does NOT own is whether the predicate is
# right: that is lean-gate-selftest.sh's (st*) block, which drives the real subcommand against a
# real remote and a real fetch. (v13)/(v14) are the matched pair here that joins the two, because
# the seam between them — the scheduler invoking a subcommand and an arm the real gate actually
# accepts — is precisely what a fake gate cannot fail on.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
# #805 CHANGED THE DENOMINATOR, not the wiring. The pre-spawn read is still exactly one per BUILD
# spawn; D-2 added a read per POLL TICK on top of it, because the premise can now expire while the
# session is live and there is finally a channel to act on that. Two spawns settling on their
# first tick is therefore three loop reads — one pre-BUILD, one inside BUILD's tick, one inside
# REVIEW's — and preflight's ticket-arm read stays at one. Pinned as an exact count rather than a
# floor, so a read that migrated into the close-out or into a second preflight still reds.
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 2 ] \
   && [ "$(staleness_reads loop)" -eq 3 ] && [ "$(staleness_reads ticket)" -eq 1 ]; then
  pass "(v1) an approved run reads staleness once before its one build spawn and once per poll tick — never before the close-out"
else fail "(v1) expected 2 spawns with 3 loop + 1 ticket read, got $(spawn_count) / $(staleness_reads loop) / $(staleness_reads ticket), rc=$rc: $out"; fi

if grep -q "CWD: $TREE" <<<"$(staleness_log)" \
   && ! grep -q 'RUN_ID_SET: yes' <<<"$(staleness_log)"; then
  pass "(v2) every staleness read runs from the MAIN checkout with RUN_ID scrubbed, against a poisoned parent"
else fail "(v2) the staleness reads had the wrong cwd or an ambient run id: $(staleness_log)"; fi

if grep -q 'ARGV: staleness 7 --arm ticket ' <<<"$(staleness_log)" \
   && grep -qE 'ARGV: staleness 7 \|' <<<"$(staleness_log)"; then
  pass "(v3) preflight asks for the TICKET arm alone; the loop asks for both — the base arm belongs to the spawn loop"
else fail "(v3) the two call sites did not use the arms the contract assigns them: $(staleness_log)"; fi

# (v4) went with the continuation it drove (#718). It put two BUILD spawns in ONE build phase so a
# read count of 2 could only mean "per BUILD spawn"; (v5) below makes the same distinction over two
# ROUNDS, which is the only way one run reaches two build spawns now.

# Round 2's read is a FRESH evaluation, not round 1's answer remembered: the same run passes the
# check, spends a needs-work round, and is stopped by the check on the way into round 2.
# #805: the second read is now BUILD's first poll tick rather than round 2's pre-spawn check, so
# the same scripted stream stops the run one spawn EARLIER — mid-session instead of between
# rounds. That is the ticket's gain stated as a count: the round-2 spawn this used to pay for is
# no longer spent, and neither are the minutes round 1's session would have run out.
setup_case "" $'5\n1' "ready-for-dev" "11"
printf '0\n7\n' > "$STALENESS_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 7 ] && [ "$(spawn_count)" -eq 1 ] && [ "$(staleness_reads loop)" -eq 2 ] \
   && grep -q 'stop sess1' "$SPAWN_LOG_DIR/stops" 2>/dev/null; then
  pass "(v5) the premise is re-evaluated inside the wait — a run clean at the spawn boundary is stopped mid-session, a round earlier than the boundary check could"
else fail "(v5) expected rc=7 after 1 spawn and 2 reads, got rc=$rc / $(spawn_count) / $(staleness_reads loop): $out"; fi

setup_case "" "$V_APPROVE" "ready-for-dev" "11"
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

# Ordering, and it is not cosmetic: the spawn is the expensive thing in the phase, and a run whose
# premise has already expired should not pay for it. Scored over the SAME run (v6) just made — the
# loop's premise read happened, and nothing downstream of it did.
if [ "$(staleness_reads loop)" -eq 1 ] && [ "$(inflight_reads)" -eq 0 ] \
   && [ "$(progress_reads m5)" -eq 0 ]; then
  pass "(v8) the check runs FIRST in the phase — a stale run pays for the premise read and nothing after it"
else fail "(v8) the stale run made $(staleness_reads loop) premise read(s), $(inflight_reads) in-flight read(s) and $(progress_reads m5) milestone-5 read(s): $(progress_log)"; fi

# D-5, at the loop. A read that could not be completed is a phase failure's exit 1, NOT 7 and
# emphatically not 0 — the distinction the whole ticket turns on.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
printf '1\n' > "$STALENESS_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'could not be completed' <<<"$out" && grep -q 'premise nothing verified' <<<"$out"; then
  pass "(v9) an unevaluable staleness read exits 1 with nothing spawned — never a blind spawn, and distinguishable from the stale stop"
else fail "(v9) expected rc=1 with 0 spawns, got rc=$rc / $(spawn_count): $out"; fi

# Preflight's arm. A launch onto an already-closed ticket costs no run at all, and reports as a
# preflight reject (exit 2) rather than the loop's 7, because nothing was spawned.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
printf '7\n' > "$STALENESS_TICKET_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] && [ "$(staleness_reads loop)" -eq 0 ] \
   && grep -q 'FAIL ticket' <<<"$out" && grep -q 'premise is already false' <<<"$out"; then
  pass "(v10) preflight rejects a launch onto an expired premise at exit 2, before the loop is ever entered"
else fail "(v10) expected a preflight rc=2 with 0 spawns, got rc=$rc / $(spawn_count): $out"; fi

if grep -q 'ok intake' <<<"$out" && grep -q 'ok spawn' <<<"$out" && grep -q 'ok gate' <<<"$out"; then
  pass "(v11) the ticket probe joins the concurrent set — every other probe's verdict is still reported alongside its failure"
else fail "(v11) a failing ticket probe suppressed the other probe verdicts: $out"; fi

setup_case "" "$V_APPROVE" "ready-for-dev" "11"
printf '1\n' > "$STALENESS_TICKET_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 0 ] && grep -q 'could not be completed' <<<"$out"; then
  pass "(v12) preflight fails closed too — an unreadable tracker is not an open ticket"
else fail "(v12) expected a preflight rc=2 on an unevaluable read, got rc=$rc / $(spawn_count): $out"; fi

# ---- (v14) telemetry preflight: the half-configured shape is named, and never blocks -----------
# SCENARIO, not a presence grep. #704 spent a full two-hour run whose four payload sessions
# exported zero OTel rows, and published totalUsd:null at close-out — the first such row in 27.
# The launching environment had the enable flag and no exporter. Nothing in the lane said so
# until the cost block ran, by which point the spend had happened. These three cases pin the
# three-way split: off is fine, configured is fine, half-configured is called out — and none of
# them changes the exit code, because telemetry is optional and a warn that rejects would break
# every consumer that runs without it.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER='' run_tool "$CFG" "$ISSUE" --build-model sonnet --dry-run)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'WARN telemetry' <<<"$out" && grep -q 'OTEL_METRICS_EXPORTER' <<<"$out"; then
  pass "(v14a) telemetry on with no exporter WARNS, names the variable, and still exits 0"
else fail "(v14a) expected rc=0 with a WARN naming OTEL_METRICS_EXPORTER, got rc=$rc: $out"; fi

out="$(CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=otlp run_tool "$CFG" "$ISSUE" --build-model sonnet --dry-run)"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'WARN telemetry' <<<"$out" && grep -q 'ok telemetry' <<<"$out"; then
  pass "(v14b) a configured exporter reports ok and raises no warning"
else fail "(v14b) expected an ok telemetry line and no WARN, got rc=$rc: $out"; fi

out="$(CLAUDE_CODE_ENABLE_TELEMETRY='' OTEL_METRICS_EXPORTER='' run_tool "$CFG" "$ISSUE" --build-model sonnet --dry-run)"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'WARN telemetry' <<<"$out" && grep -q 'skip(telemetry-off)' <<<"$out"; then
  pass "(v14c) telemetry deliberately off is a supported state, not a warning"
else fail "(v14c) expected the telemetry-off ok line and no WARN, got rc=$rc: $out"; fi

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
      SPAWN_LOG_DIR="$SPAWN_LOG_DIR" AGENTS_STATE_FILE="$AGENTS_STATE_FILE" \
      SPAWN_ID_FILE="$SPAWN_ID_FILE" HOME="$CASE_HOME" LEAN_SPAWN_POLL_SECS=0 \
      GH_LOG="$GH_LOG" LABELS_FILE="$LABELS_FILE" PR_FILE="$PR_FILE" \
      COMMENTS_FILE="$COMMENTS_FILE" STATE_ANSWER="${STATE_ANSWER:-OPEN}" \
      RUN_ID=poisoned-parent-run LEAN_RUN_MODEL=poisoned-parent-model \
      bash "$TOOL" "$ISSUE" --build-model sonnet 2>&1 )
}

make_real_fixture "$WORK/real-overlap" shared.txt
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_real_gate "$WORK/real-overlap/tree")"; rc=$?
if [ "$rc" -eq 7 ] && [ "$(spawn_count)" -eq 0 ] \
   && grep -q 'BASE ARM FIRED' <<<"$out" && grep -q 'shared.txt' <<<"$out"; then
  pass "(v13) against the REAL gate, an open ticket whose base moved into its own files exits 7 with nothing spawned"
else fail "(v13) the real-gate composition did not stop the run, rc=$rc / $(spawn_count) spawn(s): $out"; fi

# The other half. Same real gate, same real fetch, same branch diff — the base's new commit simply
# lands somewhere the branch is not. Without it, (v13) would pass just as well against a gate that
# fires unconditionally, which is a shape a lane discovers by having every run stopped.
make_real_fixture "$WORK/real-clean" elsewhere.txt
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
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

# #531 — the terminal-state taxonomy and the three boundaries it gave a vocabulary to.

# ---- (t) the BUILD exit contract: exited 0 with work in flight ---------------------------------
# THE DEFECT, at the boundary it is observable from. `claude -p` exits 0 whenever the model ends
# its turn, so a BUILD session that committed without pushing is byte-identical to one that
# finished — and every read after it is about a REMOTE head missing the work. Three occurrences in
# a single run of one ticket, each costing a full review round, with nothing in the log to tell it
# from a legitimate one.
#
# THE GATE ANSWERS, THIS SCRIPT ROUTES. The predicate itself is lean-gate-selftest.sh's to prove
# (it owns the real git conditions); what is asserted here is what an 8 ROUTES TO, which no
# gate-side case can reach.
#
# #652 REVERSED THE ROUTE and #718 REVERSED IT BACK. Between them an 8 was RECOVERED by one extra
# BUILD spawn — still a spawn bought on the guess that a session which stopped mid-collection will
# not stop again. #531's reading survives: the remedy is a single push from a tree that still
# exists. (t1) and (t1b) stood here for the recovery and its bound; (h4)'s rc-8 arm replaced both.

# FAIL CLOSED, and distinguishably so: "I could not look" is not "there is nothing there", and the
# slug is what makes the two tellable apart in a log.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
printf '1\n' > "$INFLIGHT_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 1 ] \
   && [ "$(slug_of "$out")" = "build-inflight-unreadable" ]; then
  pass "(t2) an in-flight read that could not be completed stops the run too, under a DIFFERENT slug from the work-in-flight stop"
else fail "(t2) expected rc=1 / 1 spawn / slug build-inflight-unreadable, got rc=$rc / $(spawn_count) / '$(slug_of "$out")': $out"; fi

# (t3) and (t4) went with the paths they described (#718). (t3) pinned the read's SHAPE — from
# MAIN_ROOT, RUN_ID scrubbed — over the two calls a recovery made; (h4)'s rc-8 arm asserts both
# over the one call left. (t4) pinned that the check is not consulted on the no-PR path by watching
# the run continue instead; there is no continuation, and (h4)'s no-PR arm asserts zero reads.

# ---- (u) #531 D-7: a head that already carries an approve is not re-reviewed --------------------
# The round loop entered the build phase unconditionally and the REVIEW spawn PRECEDED the only
# verdict read, so a re-entry reviewed an already-approved head — and could author a COMPETING
# record for it. rc=0 on the PRE-spawn read now skips the review and falls into the close-out;
# stopping instead would strand finished, reviewed work.
setup_case "" "0" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 1 ] && [ "$(closeout_count)" -eq 1 ] \
   && grep -q 'build-lean 7' <<<"$(spawn_argv 1)" \
   && ! grep -q 'review-lean' <<<"$(all_argv)" \
   && grep -q 'review-skipped-approved' <<<"$out"; then
  pass "(u1) an already-approved head spawns NO review and falls into the close-out, naming the state it passed through"
else fail "(u1) expected rc=0 with 1 build spawn, 1 close-out and no review, got rc=$rc / $(spawn_count) / $(closeout_count): $(all_argv)"; fi

# NON-VACUITY. The case above would also pass against a scheduler that never reviewed anything.
# The identical composition whose pre-spawn read is 5 — the real gate's answer on a head no review
# has covered — must spawn the review.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 2 ] && grep -q 'review-lean 11' <<<"$(spawn_argv 2)"; then
  pass "(u2) non-vacuity: a head with no usable verdict still gets its REVIEW spawn — the skip is a comparison, not a blanket refusal"
else fail "(u2) expected rc=0 with 2 spawns and a review, got rc=$rc / $(spawn_count): $(all_argv)"; fi

# ---- (vr) #597 D-1/AC-2: the CANNOT-ANSWER verdict codes route ahead of the REVIEW spawn --------
# #531's header claims classes 4 and 6 "now hard-stop one spawn EARLIER" and lists 3 with them.
# 3 was not: the `else` arm spawns on EVERY non-zero rc and the `case` that routes 3 reads only
# afterwards. On #583 that cost a whole review session — `verdict_rc` is anchored in the LANE
# WORKTREE, the close-out had already run teardown, so it answered 3 without ever reaching the
# gate, and a REVIEW was spawned against a head that had not moved in five and a half hours.
#
# rc=3 IS NOT AN ERROR BY ITSELF. An absent worktree is what a FINISHED lane looks like. The
# milestone-5 token separates the two, and it is compared against the milestone-ZERO token rather
# than parsed — milestone 0 cannot have a satisfied row, so its count is the zero token by
# construction, and the scheduler keeps its "never parses a token" posture.
setup_case "" "3" "ready-for-dev" "11"
set_m5_tokens 'm5-1
m5-0'
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 1 ] \
   && ! grep -q 'review-lean' <<<"$(all_argv)" \
   && grep -q 'lane-closed-out' <<<"$out"; then
  pass "(vr1) AC-2: rc=3 with a satisfied milestone 5 ends the run COMPLETE and spawns NO review against an unmoved head"
else fail "(vr1) expected rc=0, 1 spawn and no review, got rc=$rc / $(spawn_count): $(all_argv)
$out"; fi

# The other half of the same read, and the pre-existing stop it must not swallow. Identical
# composition, milestone-5 token EQUAL to the zero baseline: the lane never finished, so this is
# the old `worktree-missing` failure — still a failure, still no review spawned.
setup_case "" "3" "ready-for-dev" "11"
set_m5_tokens 'm5-0
m5-0'
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(spawn_count)" -eq 1 ] \
   && ! grep -q 'review-lean' <<<"$(all_argv)" \
   && grep -q 'worktree-missing' <<<"$out"; then
  pass "(vr2) rc=3 with an unsatisfied milestone 5 is still the worktree-missing stop, and still spawns no review"
else fail "(vr2) expected rc=1 with worktree-missing and no review, got rc=$rc / $(spawn_count): $(all_argv)
$out"; fi

# rc=2 is the gate refusing to run at all — an environment answer, not a verdict. A review round
# cannot clear it, so spawning one is pure cost, which is #531's own stated reason for 4 and 6.
setup_case "" "2" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 2 ] && [ "$(spawn_count)" -eq 1 ] \
   && ! grep -q 'review-lean' <<<"$(all_argv)" \
   && grep -q 'verdict-gate-unreadable' <<<"$out"; then
  pass "(vr3) rc=2 hard-stops before the REVIEW spawn — a review cannot clear a gate that never evaluated one"
else fail "(vr3) expected rc=2 with no review spawn, got rc=$rc / $(spawn_count): $(all_argv)
$out"; fi

# NON-VACUITY for the whole block. (u2) already proves rc=5 spawns a review; this proves the two
# new routes are keyed on the CODE and not on some incidental property of the fixture — the same
# composition with the ordinary needs-work code still spends a round and spawns.
setup_case "" "$V_NEEDSWORK_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'review-lean 11' <<<"$(all_argv)"; then
  pass "(vr4) non-vacuity: the ordinary verdict codes still spawn their REVIEW — the new routes are keyed on 2/3, not a blanket refusal"
else fail "(vr4) expected the ordinary path to still review, got rc=$rc: $(all_argv)"; fi

# ---- (w) #590: the close-out's own failure modes, past the retry ---------------------------------
# #531 D-8/D-9's continuation arm lived here — one re-SPAWN routed on the general progress token,
# with `closeout-idle` and `closeout-continuations-spent` telling "it never reached a gate call"
# from "it reached one and redded". Both distinctions were properties of a MODEL SESSION and died
# with it: a gate call always reaches the gate, and its rc says whether it landed. What survives
# is the pair below — the in-flight boundary on the far side of a completed close-out, which is
# the one state that must never be reported as a finished run.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
# Line 1 is the BUILD phase's own read — clean, or the run stops before the close-out and this
# case would be measuring `build-inflight` while claiming to measure the close-out's boundary.
printf '0\n8\n' > "$INFLIGHT_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(closeout_count)" -eq 1 ] \
   && [ "$(slug_of "$out")" = "closeout-inflight" ] \
   && ! grep -q 'done — #' <<<"$out"; then
  pass "(w1) a close-out that completed over a worktree still holding work is a hard stop, never 'done'"
else fail "(w1) expected rc=1 with slug closeout-inflight, got rc=$rc / $(closeout_count) / '$(slug_of "$out")': $out"; fi

# Fail-closed, on (o8)/(oi5)'s principle: an in-flight read that could not be COMPLETED is not a
# clean one, and reporting a finished run on that guess is what the check exists to prevent.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
printf '0\n1\n' > "$INFLIGHT_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(slug_of "$out")" = "closeout-inflight-unreadable" ]; then
  pass "(w2) an in-flight read that cannot be completed after the close-out is its own slug, not a pass"
else fail "(w2) expected slug closeout-inflight-unreadable, got rc=$rc / '$(slug_of "$out")': $out"; fi

# ---- (x) #531 D-1: the taxonomy is a taxonomy ---------------------------------------------------
# EXACTLY ONE terminal line per run, and pairwise-DISTINCT slugs across distinct conditions. A
# vocabulary that reused a word would be the thirteen-`exit 1` state with extra ceremony, and one
# that printed two lines would leave a log router picking between them. Six conditions spanning
# five exit codes — usage, preflight, the build phase, the review phase, the close-out, success.
x_slugs=""
x_lines=0
x_one() { # x_one <expected-slug> <output>
  local got n
  got="$(slug_of "$2")"
  n="$(grep -c '\] terminal: ' <<<"$2")" || n=0
  [ "$n" -eq 1 ] || x_lines=$((x_lines + 1))
  [ "$got" = "$1" ] || x_slugs="$x_slugs MISMATCH(want=$1,got=$got)"
  printf '%s\n' "$got"
}
x_seen=""
setup_case "" "" "ready-for-dev" "5"
x_seen="$x_seen$(x_one usage-missing-build-model "$(run_tool "$CFG" "$ISSUE")")
"
setup_case "" "$V_APPROVE" "" "11"
x_seen="$x_seen$(x_one preflight-rejected "$(run_tool "$CFG" "$ISSUE" --build-model sonnet)")
"
setup_case "failed" "$V_APPROVE" "ready-for-dev" "11"
x_seen="$x_seen$(x_one build-session-failed "$(run_tool "$CFG" "$ISSUE" --build-model sonnet)")
"
setup_case "" "5
5
5" "ready-for-dev" "11"
x_seen="$x_seen$(x_one review-dark "$(run_tool "$CFG" "$ISSUE" --build-model sonnet)")
"
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
set_closeout_rcs $'1\n1'
x_seen="$x_seen$(x_one closeout-incomplete "$(run_tool "$CFG" "$ISSUE" --build-model sonnet)")
"
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
x_seen="$x_seen$(x_one approved "$(run_tool "$CFG" "$ISSUE" --build-model sonnet)")
"
x_n="$(printf '%s' "$x_seen" | grep -c .)" || x_n=0
x_u="$(printf '%s' "$x_seen" | sort -u | grep -c .)" || x_u=0
if [ -z "$x_slugs" ] && [ "$x_lines" -eq 0 ] && [ "$x_n" -eq 6 ] && [ "$x_u" -eq 6 ]; then
  pass "(x1) six distinct terminal conditions print six distinct slugs, one line each"
else fail "(x1) slug vocabulary broke: mismatches='$x_slugs' multi-line=$x_lines seen=$x_n unique=$x_u"; fi

# ---- (y) #531 D-5/D-6: the log is timestamped and three-way separable ---------------------------
# `say` wrote stdout and `envfail` wrote stderr, so even this script's own lines were split across
# two streams, and `spawn` ran the child with no redirection at all — a watcher filtering the
# merged log for "error" caught build-session prose. The payload is what moves: control is stdout,
# payload is stderr AND a per-role transcript.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
RUN_TOOL_SPLIT=1 LAUNCH_ID_OVERRIDE=y-launch run_tool "$CFG" "$ISSUE" --build-model sonnet \
  > "$WORK/case-$CASE_N/stdout" 2> "$WORK/case-$CASE_N/stderr"
y_rc=$?
y_out="$(cat "$WORK/case-$CASE_N/stdout")"
y_err="$(cat "$WORK/case-$CASE_N/stderr")"
# #805 STRENGTHENED THIS, and the strengthening is the transport's doing: the payload does not
# reach this process on ANY stream now, so the claim is no longer "control on stdout, payload on
# stderr" but "control on stdout, and the run's stderr is empty of payload". A spawn's own words
# live in its transcript, asserted in (y2a).
if [ "$y_rc" -eq 0 ] \
   && grep -q 'orchestrate-lean' <<<"$y_out" \
   && grep -q 'session sess1' <<<"$y_out" \
   && ! grep -q 'backgrounded' <<<"$y_out" \
   && ! grep -q '\[orchestrate-lean\]' <<<"$y_err"; then
  pass "(y1) a plain stdout redirect captures PURE control lines, and no payload reaches either stream under --bg"
else fail "(y1) the streams were not separated, rc=$y_rc: stdout=[$y_out] stderr=[$y_err]"; fi

# The per-role transcript, which is the durable half: the terminal and the redirects are both
# ephemeral, and reconstructing one run's phase timings previously meant rebuilding the timeline
# from git and PR metadata.
# #650 AC-1: the LAUNCH token now sits between the `spawn` stem and the ordinal, so this path
# pins the whole naming contract — stem, launch, ordinal, role — rather than three quarters of it.
y_log="$TREE/.claude/pipeline-state/$ISSUE-lean-spawn-y-launch-1-build.log"
if [ -f "$y_log" ] \
   && [ -f "$TREE/.claude/pipeline-state/$ISSUE-lean-spawn-y-launch-2-review.log" ]; then
  pass "(y2) each spawn leaves a per-ROLE transcript under the pipeline-state dir — the file retro-corpus.sh classifies a run 'orchestrated' on"
else fail "(y2) no per-role transcript at $y_log: $(ls "$TREE/.claude/pipeline-state" 2>/dev/null)"; fi

# D-3. THE TRANSCRIPT'S CLOSING CONTENT, and the one case that proves the READ rather than the
# file. `-p` printed the session's last message into this file; a bg payload never reaches the
# process at all, so the same text is recovered from the harness's own projects jsonl. The
# fixture writes that jsonl under the case's private HOME, keyed on the sessionId the LISTING
# reported — not the short dispatch id — which is what makes a tool that closed over the wrong
# one fail here.
mkdir -p "$CASE_HOME/.claude/projects/some-cwd-slug"
jq -n -c '{type:"assistant", message:{content:[{type:"text", text:"FINAL-MESSAGE-FROM-BUILD"}]}}' \
  > "$CASE_HOME/.claude/projects/some-cwd-slug/sess1-full.jsonl"
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
mkdir -p "$CASE_HOME/.claude/projects/some-cwd-slug"
{ jq -n -c '{type:"assistant", message:{content:[{type:"text", text:"AN-EARLIER-MESSAGE"}]}}'
  jq -n -c '{type:"user", message:{content:"not an assistant row"}}'
  jq -n -c '{type:"assistant", message:{content:[{type:"text", text:"FINAL-MESSAGE-FROM-BUILD"}]}}'
} > "$CASE_HOME/.claude/projects/some-cwd-slug/sess1-full.jsonl"
LAUNCH_ID_OVERRIDE=y2a-launch run_tool "$CFG" "$ISSUE" --build-model sonnet >/dev/null 2>&1
y2a_log="$TREE/.claude/pipeline-state/$ISSUE-lean-spawn-y2a-launch-1-build.log"
y2a_rev="$TREE/.claude/pipeline-state/$ISSUE-lean-spawn-y2a-launch-2-review.log"
if grep -q 'FINAL-MESSAGE-FROM-BUILD' "$y2a_log" 2>/dev/null \
   && ! grep -q 'AN-EARLIER-MESSAGE' "$y2a_log" 2>/dev/null \
   && grep -q 'left no readable final message' "$y2a_rev" 2>/dev/null; then
  pass "(y2a) a spawn-end appends the session's LAST assistant message to its transcript, and says so plainly when there is none"
else fail "(y2a) transcript close-out wrong: build=[$(cat "$y2a_log" 2>/dev/null)] review=[$(cat "$y2a_rev" 2>/dev/null)]"; fi

# ISO-8601 UTC, matching the gate's now_iso, so scheduler lines and progress-file rows sort against
# each other without conversion. Asserted over EVERY control line rather than one: a clock on some
# of them is a timeline with holes in it.
y_bad="$(grep '\[orchestrate-lean\]' <<<"$y_out" | grep -cvE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[orchestrate-lean\]')" || y_bad=0
y_all="$(grep -c '\[orchestrate-lean\]' <<<"$y_out")" || y_all=0
if [ "$y_all" -ge 5 ] && [ "$y_bad" -eq 0 ]; then
  pass "(y3) every one of the $y_all control lines carries an ISO-8601 UTC instant in the gate's own format"
else fail "(y3) $y_bad of $y_all control lines were unstamped: $y_out"; fi

# ---- (z) #650 AC-1: a re-launch no longer destroys its predecessor's evidence ------------------
# THE REGRESSION, stated as the mechanism rather than as a symptom. `SPAWN_N` resets per scheduler
# PROCESS, and the transcript path was keyed on it alone — so launch 2's first spawn reopened
# launch 1's `<issue>-lean-spawn-1-build.log` and the tool's own readability probe (`: > "$log"`)
# truncated it to zero before a byte was appended. #643's audit hit this directly: it could report
# a launch FLOOR of 18 and no launch COUNT, which is what makes `M1ᵗ`'s denominator unrecoverable.
#
# SCORED ON BYTES, NOT ON EXISTENCE. The file survives either way — truncation leaves it there,
# empty — so an `-f` test passes on the broken tool. The assertion below captures launch 1's
# transcript, runs launch 2, and compares: unchanged and non-empty is the only passing state.
LEDGER="$TREE/.claude/pipeline-state/$ISSUE-lean-launches.tsv"
STATE="$TREE/.claude/pipeline-state"

setup_case "" "$V_APPROVE" "ready-for-dev" "11"
LAUNCH_ID_OVERRIDE=z-first run_tool "$CFG" "$ISSUE" --build-model sonnet >/dev/null 2>&1
z_first="$STATE/$ISSUE-lean-spawn-z-first-1-build.log"
z_before="$(cat "$z_first" 2>/dev/null)"

setup_case "" "$V_APPROVE" "ready-for-dev" "11"
LAUNCH_ID_OVERRIDE=z-second run_tool "$CFG" "$ISSUE" --build-model sonnet >/dev/null 2>&1
z_second="$STATE/$ISSUE-lean-spawn-z-second-1-build.log"
z_after="$(cat "$z_first" 2>/dev/null)"

if [ -n "$z_before" ] && [ "$z_after" = "$z_before" ] && [ -s "$z_second" ]; then
  pass "(z1) a second launch of the same issue leaves the first launch's transcript byte-identical, and writes its own"
else fail "(z1) launch 2 destroyed launch 1's evidence: before=[$z_before] after=[$z_after] second=$(wc -c <"$z_second" 2>/dev/null) — $(ls "$STATE" 2>/dev/null)"; fi

# Anti-vacuity for (z1): the two transcripts must be DIFFERENT FILES. Two launches whose token did
# not reach the path would both satisfy "non-empty" by appending into one, and the equality above
# would then be comparing a file with itself.
if [ "$z_first" != "$z_second" ] && [ -f "$z_first" ] && [ -f "$z_second" ]; then
  pass "(z2) the launch token reaches the transcript path, so two launches address two files"
else fail "(z2) the two launches did not address two files: $z_first / $z_second"; fi

# THE LEDGER'S REASON FOR EXISTING: a launch that spawns NOTHING. A preflight reject is a launch —
# it consumed an operator's attention and it is a row in the campaign's denominator — and no
# transcript records it, because the tool exits before `spawn` is ever called. Stamping the
# filename alone would leave AC-2's denominator under-counting, in the direction that favours the
# delete arm.
setup_case "" "" "" ""
z_out="$(LAUNCH_ID_OVERRIDE=z-reject run_tool "$CFG" "$ISSUE" --build-model sonnet)"; z_rc=$?
z_rows="$(grep -c "	z-reject	" "$LEDGER" 2>/dev/null)" || z_rows=0
z_launch="$(grep -c "	z-reject	$ISSUE	launch	" "$LEDGER" 2>/dev/null)" || z_launch=0
z_term="$(grep -c "	z-reject	$ISSUE	terminal	" "$LEDGER" 2>/dev/null)" || z_term=0
z_spawns="$(grep -c "	z-reject	$ISSUE	spawn	" "$LEDGER" 2>/dev/null)" || z_spawns=0
if [ "$(spawn_count)" -eq 0 ] && [ "$z_launch" -eq 1 ] && [ "$z_term" -eq 1 ] && [ "$z_spawns" -eq 0 ] \
   && [ "$z_rows" -eq 2 ]; then
  pass "(z3) a launch that spawns nothing is still enumerable — one launch row, one terminal row, no spawn rows"
else fail "(z3) the preflight-rejected launch was not enumerable (rc=$z_rc): rows=$z_rows launch=$z_launch term=$z_term spawns=$z_spawns out=$z_out"; fi

# The terminal row carries the VOCABULARY, the exit code AND THE REASON, not merely the fact of an
# ending. The first two are the field the attribution rubric is applied to: `staleness-expired` and
# `build-idle` are different classes. The third is what #652 proved the first two cannot replace —
# a campaign launch recorded `preflight-rejected rc=2` and the sentence naming the failing probe
# lived only on a control stream nobody kept, so the launch was unclassifiable a day later and the
# band it widened is why nine runs selected no arm.
z_detail="$(sed -n "s/.*	z-reject	$ISSUE	terminal	//p" "$LEDGER" 2>/dev/null)"
if grep -qE '^[a-z][a-z-]+ rc=[0-9]+ — .' <<<"$z_detail"; then
  pass "(z4) the terminal row carries the slug, the exit code and the reason: '$z_detail'"
else fail "(z4) the terminal row carries no classifiable outcome: '$z_detail'"; fi

# ONE ROW, whatever the message did. The reason is the LAST field of a TSV row, so a tab in it
# would forge a column and a newline would forge a row — turning one bad launch into a ledger that
# no longer parses. Asserted on the real writer rather than trusted: this is the only field in the
# file whose content is arbitrary prose.
z_term_rows="$(grep -c "	z-reject	$ISSUE	terminal	" "$LEDGER" 2>/dev/null || echo 0)"
z_cols="$(grep "	z-reject	$ISSUE	terminal	" "$LEDGER" 2>/dev/null | head -1 | awk -F'\t' '{print NF}')"
if [ "$z_term_rows" -eq 1 ] && [ "$z_cols" -eq 5 ]; then
  pass "(z4b) a prose reason stays inside one five-column row — no forged column, no forged row"
else fail "(z4b) the reason broke the row shape: rows=$z_term_rows cols=$z_cols"; fi

# A completed run records its spawns in order, so the ledger alone answers "which spawns belonged
# to this launch" without globbing a directory that may have been reaped.
z_sp="$(sed -n "s/.*	z-second	$ISSUE	spawn	//p" "$LEDGER" 2>/dev/null)"
if [ "$(printf '%s\n' "$z_sp" | grep -c .)" -eq 2 ] \
   && grep -q '^n=1 role=BUILD ' <<<"$z_sp" && grep -q '^n=2 role=REVIEW ' <<<"$z_sp"; then
  pass "(z5) a launch's spawns are enumerable from the ledger alone, in order and by role"
else fail "(z5) the ledger did not enumerate z-second's spawns: [$z_sp]"; fi

# EVERY SPAWN IS CLOSED, which is what makes a payload's duration derivable. Start rows alone give
# the interval "this session PLUS whatever the loop did next", so a scheduler that spent ten minutes
# between spawns and one that spent two seconds wrote identical ledgers — and that difference is
# exactly what `tools/lane-latency.sh` gates on. Paired and state-carrying, or the metric silently
# becomes total wall-clock again.
#
# #805 D-12: the closing field is a STATE, not `rc=`. `rc=0` was true of a session that finished
# and of one that was abandoned, which is the defect the transport swap is about — so the field
# that an analyst reads has to be the one that separates them. The `spawn` row gains the id,
# which is what makes a ledger row joinable to `claude agents` and to `claude attach`.
z_end="$(sed -n "s/.*	z-second	$ISSUE	spawn-end	//p" "$LEDGER" 2>/dev/null)"
z_start="$(sed -n "s/.*	z-second	$ISSUE	spawn	//p" "$LEDGER" 2>/dev/null)"
if [ "$(printf '%s\n' "$z_end" | grep -c .)" -eq 2 ] \
   && grep -q '^n=1 role=BUILD state=done$' <<<"$z_end" \
   && grep -q '^n=2 role=REVIEW state=done$' <<<"$z_end" \
   && ! grep -q 'rc=' <<<"$z_end" \
   && [ "$(printf '%s\n' "$z_start" | grep -c ' id=')" -eq 2 ]; then
  pass "(z6) every spawn is closed by a spawn-end row carrying its ordinal, role and SETTLED STATE, and opened by one carrying the session id"
else fail "(z6) the ledger did not close z-second's spawns: start=[$z_start] end=[$z_end]"; fi

# ORDER, not merely presence: a start must precede its own end. Asserted on the file as written,
# because a pair emitted in the wrong order subtracts to a negative payload and would read as the
# scheduler having spent the session's whole duration.
z_seq="$(grep "	z-second	$ISSUE	spawn" "$LEDGER" 2>/dev/null | awk -F'\t' '{printf "%s ", $4}')"
if [ "$z_seq" = "spawn spawn-end spawn spawn-end " ]; then
  pass "(z7) starts and ends alternate — a spawn is closed before the next one opens"
else fail "(z7) the spawn edges are out of order: [$z_seq]"; fi


# ---- (bg) #805: the supervised-session contracts --------------------------------------------
# Everything below drives a state the LISTING reports, which is the signal `-p` did not have.
# Each case scripts the poll stream directly, so what is under test is the loop's routing rather
# than any timing: the interval seam is zero and the fake never sleeps.

# THE POLL ITSELF. Three ticks, two of them `working` — the shape a real payload spends most of
# its life in, and the one `-p`'s wait ceiling used to cut short. Nothing is stopped and no
# fallback fires: a session that is working is a session the scheduler waits for.
setup_case "$(printf 'working\nworking\ndone\n')" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 2 ] \
   && grep -q 'session sess1: working' <<<"$out" \
   && grep -q 'session sess1: done' <<<"$out" \
   && [ "$(grep -c 'session sess1: working' <<<"$out")" -eq 1 ] \
   && [ ! -f "$SPAWN_LOG_DIR/stops" ]; then
  pass "(bg1) a session that stays working is WAITED for, its transitions are reported once each, and nothing is stopped"
else fail "(bg1) the poll did not ride out a working session, rc=$rc: $out"; fi

# `--all`, asserted on the call the poll actually makes. Without it the listing carries only
# sessions still working or blocked, so the tick after a payload finishes would find it absent —
# and the poll would score its own success as three unreadable reads.
if [ "$(grep -c -- '--json --all' "$SPAWN_LOG_DIR/agents.log" 2>/dev/null)" -ge 3 ]; then
  pass "(bg1a) every poll asks for the FULL listing, so a session that finished is still in it"
else fail "(bg1a) a poll did not pass --all: $(cat "$SPAWN_LOG_DIR/agents.log" 2>/dev/null)"; fi

# D-6/D-23. `blocked` is "waiting on you", and nobody is here. Under `-p` this shape was an exit 0
# with no PR — indistinguishable from a session that finished — so the whole gain is that the state
# is named. It ends the phase through the terminal `failed` and `stopped` already used, and the
# session is STOPPED rather than left waiting on a keyboard that does not exist. Both are asserted:
# a routing that named the state without stopping the session leaves a supervised payload running
# under a run nobody is supervising.
setup_case "$(printf 'working\nblocked\n')" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(slug_of "$out")" = "build-session-failed" ] \
   && [ "$(gate_count)" -eq 0 ] \
   && grep -q 'ended blocked' <<<"$out" \
   && grep -q 'waiting on an answer' <<<"$out" \
   && grep -q 'stop sess1' "$SPAWN_LOG_DIR/stops" 2>/dev/null; then
  pass "(bg2) a BUILD session that reads blocked is stopped and ends the phase naming the state — the exit-0-with-no-PR shape -p could not distinguish"
else fail "(bg2) expected rc=1/build-session-failed with a stop, got rc=$rc / slug=$(slug_of "$out") / stops=[$(cat "$SPAWN_LOG_DIR/stops" 2>/dev/null)]: $out"; fi

# THE SLUG IS COMPOSED FROM THE ROLE, so the two halves of the lane stay separable in a log — the
# claim AC-9 collapses two register rows onto. Driven through the REVIEW spawn, which is the only
# way to prove the composition rather than a literal: every other case reaching this line runs
# BUILD, where `$lower` and the hardcoded word are indistinguishable.
setup_case "$(printf 'done\nblocked\n')" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(slug_of "$out")" = "review-session-failed" ]; then
  pass "(bg2a) the phase-failure slug names the ROLE — build-session-failed and review-session-failed route differently in a log"
else fail "(bg2a) expected review-session-failed, got slug=$(slug_of "$out"): $out"; fi

# THE CLOSE IS IDEMPOTENT, and `blocked` is the one path that can prove it. Two closes are reached
# here and only here: `blocked` RETURNS from the poll, so `spawn`'s own close runs, and then the
# terminal it routes to runs `spawn_cleanup`'s. `SPAWN_CLOSED` is what makes the second a no-op, so
# EXACTLY ONE is the assertion — presence alone passes just as happily over a transcript carrying
# the session's final message twice, which is what dropping the flag would produce. Same
# projects-jsonl fixture (y2a) uses.
setup_case "$(printf 'working\nblocked\n')" "$V_APPROVE" "ready-for-dev" "11"
mkdir -p "$CASE_HOME/.claude/projects/some-cwd-slug"
jq -n -c '{type:"assistant", message:{content:[{type:"text", text:"FINAL-MESSAGE-FROM-BUILD"}]}}' \
  > "$CASE_HOME/.claude/projects/some-cwd-slug/sess1-full.jsonl"
LAUNCH_ID_OVERRIDE=bg2b-launch run_tool "$CFG" "$ISSUE" --build-model sonnet >/dev/null 2>&1
bg2b_log="$TREE/.claude/pipeline-state/$ISSUE-lean-spawn-bg2b-launch-1-build.log"
bg2b_n="$(grep -c 'final message of session' "$bg2b_log" 2>/dev/null || echo 0)"
if [ -s "$bg2b_log" ] && grep -q 'FINAL-MESSAGE-FROM-BUILD' "$bg2b_log" 2>/dev/null \
   && [ "$bg2b_n" -eq 1 ]; then
  pass "(bg2b) the path that reaches BOTH closes appends the final message exactly once — the close is idempotent, not merely present"
else fail "(bg2b) expected exactly one close block, got $bg2b_n: [$(cat "$bg2b_log" 2>/dev/null)]"; fi

# THE SILENCE CEILING, which is the whole of the stuck fallback the narrowed scope keeps. A payload
# whose turn ended over a bare backgrounded command sits at `working` with nothing left to do,
# released only by a stop. The ceiling bounds it, the session is stopped, the launch ledger says
# `stuck`, and the run PROCEEDS exactly as for `done` — which is the half a "detect it and stop"
# fallback would get wrong, because the GATE is the completion oracle, not this loop.
setup_case "$(printf 'working\n')" "$V_APPROVE" "ready-for-dev" "11"
out="$(SESSION_CEILING_OVERRIDE=0 run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 2 ] && grep -q 'session ceiling spent' <<<"$out" \
   && grep -q 'stop sess1' "$SPAWN_LOG_DIR/stops" 2>/dev/null \
   && grep -q 'state=stuck' "$TREE/.claude/pipeline-state/$ISSUE-lean-launches.tsv" 2>/dev/null; then
  pass "(bg4) a session past the session ceiling is stopped, ledgered as stuck, and proceeds as done"
else fail "(bg4) the ceiling arm did not fire, rc=$rc: $out"; fi

# ...and its NON-VACUITY, which is the case that matters: the identical listing stream UNDER THE
# SHIPPED CEILING must ride out untouched. Without this, (bg4) would pass just as well for a tool
# that stopped every working session it saw — the print-mode wait ceiling rebuilt by accident, and
# the exact regression this transport swap exists to remove.
setup_case "$(printf 'working\nworking\nworking\nworking\ndone\n')" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] \
   && ! grep -q 'session ceiling spent' <<<"$out" \
   && ! grep -q 'stop sess1' "$SPAWN_LOG_DIR/stops" 2>/dev/null; then
  pass "(bg4a) NON-VACUITY: a session working inside the ceiling rides out four ticks untouched — the bound is the clock, not the state"
else fail "(bg4a) a legitimately working session was stopped, rc=$rc: $out"; fi

# THE CEILING IS ELAPSED TIME, AND THE SHIPPED DEFAULT TOLERATES A LONG HEALTHY SESSION. (bg4) and
# (bg4a) between them prove the arm fires and does not fire spuriously — but both run with elapsed
# time pinned at ~0, so neither can say anything about the BOUND, and a default set below the
# duration of ordinary work would pass both. It was: measured over this lane's own launch ledgers,
# 11 of 55 BUILD spawns ran past thirty minutes, one of them for 100 minutes, so a 30-minute
# default would have stopped one healthy BUILD in five mid-work and ledgered it `stuck`. These two
# cases are the pair that can see that, because the clock is a seam now.
#
# (bg4b) drives fifty minutes of `working` past a THIRTY-minute ceiling: it fires.
setup_case "$(printf 'working\n')" "$V_APPROVE" "ready-for-dev" "11"
out="$(SESSION_CEILING_OVERRIDE=1800000 CLOCK_OVERRIDE="$BIN/fakeclock" \
       CLOCK_FILE="$CASE_HOME/.clock-b" CLOCK_STEP=600 \
       run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'session ceiling spent' <<<"$out" \
   && grep -q 'stop sess1' "$SPAWN_LOG_DIR/stops" 2>/dev/null; then
  pass "(bg4b) the ceiling is measured in ELAPSED WALL TIME, not in ticks — a session past it is stopped even though every read said working"
else fail "(bg4b) a session past the ceiling was not stopped, rc=$rc: $out"; fi

# ...and (bg4c) is the one that would have caught the shipped default. IDENTICAL listing stream and
# an identical fifty minutes of elapsed time, under the ceiling this file actually ships: the
# session must ride it out and settle on its own. Fail this by lowering SESSION_CEILING_MS back
# toward the observed BUILD distribution and the regression is named rather than measured later.
setup_case "$(printf 'working\nworking\nworking\nworking\ndone\n')" "$V_APPROVE" "ready-for-dev" "11"
out="$(CLOCK_OVERRIDE="$BIN/fakeclock" CLOCK_FILE="$CASE_HOME/.clock-c" CLOCK_STEP=600 \
       run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] \
   && ! grep -q 'session ceiling spent' <<<"$out" \
   && ! grep -q 'stop sess1' "$SPAWN_LOG_DIR/stops" 2>/dev/null; then
  pass "(bg4c) FIFTY minutes of healthy work rides out the SHIPPED ceiling untouched — the bound sits above ordinary BUILD durations, not inside them"
else fail "(bg4c) the shipped ceiling stopped a healthy fifty-minute session, rc=$rc: $out"; fi

# THE STALENESS RE-ASK HAS ITS OWN CADENCE. (bg7) proves the premise is re-asked inside the wait;
# nothing proved it is re-asked on a SEPARATE clock, and at the poll's own cadence each re-ask is a
# tracker round trip plus a base fetch — roughly 25 of each for a median BUILD where the pre-#805
# loop made one per round. Driven by pinning the interval ABOVE the fake clock's total travel, so
# the scripted exit 7 is never reached and the run settles instead.
setup_case "$(printf 'working\nworking\ndone\n')" "$V_APPROVE" "ready-for-dev" "11"
printf '0\n7\n7\n' > "$STALENESS_RC_FILE"
out="$(STALENESS_SECS_OVERRIDE=99999 CLOCK_OVERRIDE="$BIN/fakeclock" \
       CLOCK_FILE="$CASE_HOME/.clock-d" CLOCK_STEP=60 \
       run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(slug_of "$out")" != "staleness-expired" ]; then
  pass "(bg7c) the in-poll premise re-ask runs on its OWN interval — an expiry scripted inside the wait is not reached when the cadence has not come round"
else fail "(bg7c) the poll re-asked staleness on the tick clock, rc=$rc / slug=$(slug_of "$out"): $out"; fi

# AN UNREADABLE PREMISE FAILS CLOSED *DURING* A SESSION TOO, which is the arm that did not exist:
# the pre-spawn call refuses outright on a gate rc that is neither 0 nor 7, and the in-poll copy
# handled only 7 — so the SAME predicate failed closed before a session and fell silently through
# during one, and a run whose tracker went unreachable a minute in kept going on a premise nothing
# had verified. Bounded on POLL_TOLERANCE rather than immediate, because one unreachable read is
# evidence about the network and killing a healthy forty-minute BUILD over a blipped fetch is the
# worse of the two failures.
setup_case "$(printf 'working\n')" "$V_APPROVE" "ready-for-dev" "11"
printf '0\n1\n1\n1\n' > "$STALENESS_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(slug_of "$out")" = "staleness-unreadable" ] \
   && grep -q 'stop sess1' "$SPAWN_LOG_DIR/stops" 2>/dev/null \
   && [ "$(gate_count)" -eq 0 ]; then
  pass "(bg7d) an unreadable premise DURING a live session fails closed after POLL_TOLERANCE re-asks, stops the session, and never reaches the verdict gate"
else fail "(bg7d) expected rc=1/staleness-unreadable, got rc=$rc / slug=$(slug_of "$out"): $out"; fi

# ...and its NON-VACUITY, which is the half that makes the tolerance mean something. One bad read
# followed by a good one must ride through: without this, (bg7d) would pass equally for a tool that
# refused on the FIRST unreadable premise — the failure mode that would kill a healthy session over
# one blipped fetch, and the reason the bound is three rather than one.
setup_case "$(printf 'working\nworking\ndone\n')" "$V_APPROVE" "ready-for-dev" "11"
printf '0\n1\n0\n0\n' > "$STALENESS_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(slug_of "$out")" != "staleness-unreadable" ] \
   && ! grep -q 'stop sess1' "$SPAWN_LOG_DIR/stops" 2>/dev/null; then
  pass "(bg7e) NON-VACUITY: a single unreadable premise re-ask is ridden out, not fatal — the counter is consecutive, and one blip is evidence about the network"
else fail "(bg7e) a single unreadable premise killed the run, rc=$rc / slug=$(slug_of "$out"): $out"; fi

# EVERY OPENED SPAWN ROW IS CLOSED, whichever way the phase ended. The `spawn` row is written
# before the poll and the close used to be written after it, so the three arms that terminate from
# INSIDE the poll exited without one — and `tools/lane-latency.sh` reads an unclosed spawn as
# "not-measurable", a signature it was given for a KILLED scheduler. A mid-poll refusal wearing
# that signature does not fail; it quietly shrinks the measurable set the lane is gated on.
setup_case "$(printf 'working\nworking\ndone\n')" "$V_APPROVE" "ready-for-dev" "11"
printf '0\n0\n7\n' > "$STALENESS_RC_FILE"
out="$(LAUNCH_ID_OVERRIDE=bg7f-launch run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
# SCOPED TO THIS LAUNCH. The ledger is one file per ticket and every case in this suite appends to
# it, so an unscoped count would be measuring the whole run and would pass on somebody else's row.
bg7f_rows="$(grep 'bg7f-launch' "$TREE/.claude/pipeline-state/$ISSUE-lean-launches.tsv" 2>/dev/null)"
if [ "$rc" -eq 7 ] && [ "$(slug_of "$out")" = "staleness-expired" ] \
   && [ "$(grep -c "\tspawn\t" <<<"$bg7f_rows")" -eq 1 ] \
   && [ "$(grep -c "\tspawn-end\t" <<<"$bg7f_rows")" -eq 1 ] \
   && grep -q 'state=staleness-expired' <<<"$bg7f_rows"; then
  pass "(bg7f) a terminal reached from INSIDE the poll still closes its LEDGER row, naming the refusal that ended the phase — no spawn is left open"
else fail "(bg7f) the mid-poll terminal left the spawn row open: [$bg7f_rows]"; fi

# THE `stuck` PATH MUST NOT OFFER A SESSION IT JUST KILLED. `stuck` proceeds exactly as `done`, so
# it lands on the terminals written for a session the supervisor is still holding — and the ceiling
# arm STOPS the session before returning. `build-no-pr` therefore told an operator to attach to
# something this loop had killed three lines earlier, which is the identical false sentence `spawn`
# already refuses to print for `failed` and `stopped`, missed on the one arm that exits elsewhere.
setup_case "$(printf 'working\n')" "$V_APPROVE" "ready-for-dev" ""
out="$(SESSION_CEILING_OVERRIDE=0 run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(slug_of "$out")" = "build-no-pr" ] \
   && grep -q 'settled stuck' <<<"$out" \
   && grep -q 'nothing left to attach to' <<<"$out" \
   && ! grep -q 'claude attach sess1-full' <<<"$out"; then
  pass "(bg7g) build-no-pr after a STUCK settlement names the stuck state and does not offer 'claude attach' for a session this scheduler stopped"
else fail "(bg7g) the stuck path still advertised a dead session, rc=$rc / slug=$(slug_of "$out"): $out"; fi

# D-18, all four not-a-state shapes. Each is fail-closed and none is scored as done: a listing the
# scheduler cannot read is not evidence about the payload, and #527's posture decides which way an
# unevaluable predicate falls. Driven as four separate cases because they fail through four
# different code paths in the fake's answer and one of them (NOSTATE) is a listing that PARSES.
for shape in UNREADABLE GARBAGE ABSENT NOSTATE; do
  setup_case "$shape" "$V_APPROVE" "ready-for-dev" "11"
  out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
  if [ "$rc" -eq 1 ] && [ "$(slug_of "$out")" = "spawn-unreadable" ] \
     && [ "$(gate_count)" -eq 0 ] \
     && grep -q 'sess1' <<<"$out"; then
    pass "(bg5/$shape) an unreadable listing fails CLOSED after three polls, names the id, and never reaches the gate"
  else fail "(bg5/$shape) expected rc=1/spawn-unreadable, got rc=$rc / slug=$(slug_of "$out"): $out"; fi
done

# AN UNMODELLED STATE IS THE SAME FAIL-CLOSED FACT, and it gets its own case because it reaches
# the counter down a different path: the listing PARSES and the row IS the dispatched session, so
# every earlier guard passes and only the enum check is left. This is also the case that catches
# the counter being reset on every readable row — with that reset in place the tolerance is never
# reached and the loop spins forever on a state it cannot act on, which no other case here can
# distinguish from a session that is simply taking a while.
setup_case "reticulating" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(slug_of "$out")" = "spawn-unreadable" ] \
   && grep -q "unmodelled state 'reticulating' (3 of 3)" <<<"$out" \
   && [ "$(gate_count)" -eq 0 ]; then
  pass "(bg5b) a state outside the documented enum accumulates to the same fail-closed refusal — the agent view is a research preview and its enum can move"
else fail "(bg5b) expected rc=1/spawn-unreadable after three unmodelled reads, got rc=$rc / slug=$(slug_of "$out"): $out"; fi

# ...and the tolerance is THREE, not one. A supervisor killed under a live session leaves the
# session running and the listing recoverable, so a single bad read is evidence about the listing
# and not about the payload. Without this case a tool that gave up on the first one would pass
# every case above.
setup_case "$(printf 'UNREADABLE\nUNREADABLE\ndone\n')" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(spawn_count)" -eq 2 ]; then
  pass "(bg5a) two unreadable polls followed by a state are ridden out — the counter resets on a good read"
else fail "(bg5a) a recoverable listing ended the run, rc=$rc: $out"; fi

# THE DISPATCH ITSELF can fail to yield an id, and without one there is no state to poll, no
# session to stop and nothing to attach to — so it is not a spawn that happened. Fail-closed at
# the same slug, before any poll.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
printf 'NOID\n' > "$SPAWN_ID_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(slug_of "$out")" = "spawn-unreadable" ] \
   && [ "$(cat "$SPAWN_LOG_DIR/acount" 2>/dev/null || echo 0)" -eq 0 ]; then
  pass "(bg6) a dispatch that yields no session id is refused before the first poll — nothing was started this run can supervise"
else fail "(bg6) expected rc=1/spawn-unreadable with no polls, got rc=$rc / slug=$(slug_of "$out"): $out"; fi

# D-2. THE PREMISE IS RE-ASKED INSIDE THE WAIT, which is what makes exit 7 an abort rather than a
# damage bound. The pre-loop read passes and the poll's second read returns 7, so the only way to
# reach this terminal is from inside the poll — a tool that checked staleness only at the spawn
# boundary spawns, waits out the session, and exits 0. The session is stopped, and the message
# says the tree may hold a partial operation, which a stop can genuinely cause.
setup_case "$(printf 'working\nworking\ndone\n')" "$V_APPROVE" "ready-for-dev" "11"
printf '0\n0\n7\n' > "$STALENESS_RC_FILE"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if [ "$rc" -eq 7 ] && [ "$(slug_of "$out")" = "staleness-expired" ] \
   && [ "$(spawn_count)" -eq 1 ] \
   && grep -q 'stop sess1' "$SPAWN_LOG_DIR/stops" 2>/dev/null \
   && grep -q 'index.lock' <<<"$out"; then
  pass "(bg7) a premise that expires WHILE the session is live stops it mid-flight at exit 7, and the message owns the partial-operation risk"
else fail "(bg7) mid-flight staleness did not abort, rc=$rc / slug=$(slug_of "$out") / stops=[$(cat "$SPAWN_LOG_DIR/stops" 2>/dev/null)]: $out"; fi

# AC-10's "the transcript surviving a terminal reached from INSIDE the poll", and this is the case
# that holds it. A blocked session returns to `spawn` and is closed there; the two arms that still
# exit from within the loop — this one, and `spawn-unreadable` — never come back, so their ONLY
# close is the one in `spawn_cleanup`, the funnel `terminal` goes through. That matters because
# both of those terminals tell the operator to go read the payload transcript, and before the
# funnel close existed the file they named was 0 bytes on exactly those paths.
#
# Driven through mid-flight staleness rather than through `spawn-unreadable`: this is the arm that
# has a session id by the time it fires (tick 1 read the listing), so the transcript has real
# content to carry rather than the no-id notice. Same scenario as (bg7), a separate case because
# the invariant is the transcript's, not the abort's — and the launch override is what makes the
# file addressable by name.
setup_case "$(printf 'working\nworking\ndone\n')" "$V_APPROVE" "ready-for-dev" "11"
printf '0\n0\n7\n' > "$STALENESS_RC_FILE"
mkdir -p "$CASE_HOME/.claude/projects/some-cwd-slug"
jq -n -c '{type:"assistant", message:{content:[{type:"text", text:"FINAL-MESSAGE-FROM-BUILD"}]}}' \
  > "$CASE_HOME/.claude/projects/some-cwd-slug/sess1-full.jsonl"
out="$(LAUNCH_ID_OVERRIDE=bg7a-launch run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
bg7a_log="$TREE/.claude/pipeline-state/$ISSUE-lean-spawn-bg7a-launch-1-build.log"
# NON-VACUITY FIRST. The transcript assertion means nothing unless this run really left through the
# terminal inside the loop: a case that settled normally would be closed by `spawn` and pass while
# proving the opposite. So the slug and exit code are asserted alongside the file.
if [ "$rc" -eq 7 ] && [ "$(slug_of "$out")" = "staleness-expired" ] \
   && [ -s "$bg7a_log" ] && grep -q 'FINAL-MESSAGE-FROM-BUILD' "$bg7a_log" 2>/dev/null; then
  pass "(bg7a) a terminal reached from INSIDE the poll still closes its transcript — the file that terminal's own remedy names is not empty"
else fail "(bg7a) expected rc=7/staleness-expired with a closed transcript, got rc=$rc / slug=$(slug_of "$out") / log=[$(cat "$bg7a_log" 2>/dev/null)]"; fi

# D-4. The id reaches the operator at DISPATCH, with the command that uses it — the property `-p`
# could not have, because there was no id until the process ended and no channel into it if there
# had been.
setup_case "" "$V_APPROVE" "ready-for-dev" "11"
out="$(run_tool "$CFG" "$ISSUE" --build-model sonnet)"; rc=$?
if grep -q 'session sess1 — watch it with: claude attach sess1' <<<"$out" \
   && grep -q 'lean-7-build-r1' <<<"$(spawn_argv 1)" \
   && grep -q 'lean-7-review-r1' <<<"$(spawn_argv 2)"; then
  pass "(bg8) the session id and its attach command reach the control stream at dispatch, and each spawn is NAMED by issue, role and round"
else fail "(bg8) the dispatch line or the --name is wrong: $out / $(all_argv)"; fi

# ---- (n) --help prints the header and stops before the code ------------------------------------------
# BOTH bounds, and the lower one is not decoration: the `Exit: 0 = approved` anchor sits four lines
# above the header's end, so a range that over-shrinks (2,134p -> 2,130p) drops the whole exit-code
# tail from --help while still satisfying an upper-bound-only check. Pin the LAST header line by its
# own text so truncation reds in the direction a doc-line deletion actually moves the boundary.
out="$(bash "$TOOL" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'Exit: 0 = approved' <<<"$out" \
   && grep -qF 'integrity refusal (P10)' <<<"$out" \
   && grep -qF 're-launch the same command.' <<<"$out" \
   && ! grep -qF 'set -uo pipefail' <<<"$out"; then
  pass "(n) --help prints through the last header line and stops before the code"
else fail "(n) --help did not print exactly the header, rc=$rc: $out"; fi

echo "[orchestrate-lean-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

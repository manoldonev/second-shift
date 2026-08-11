#!/usr/bin/env bash
# orchestrate-lean.sh — the lean lane's scheduler. It spawns the payload blocks and reads
# their outcomes. It authors nothing.
#
# WHY THIS IS A SCRIPT AND NOT A PROSE CHECKLIST (#397 D-1). The rest of this lane is
# script-gated — lean-gate.sh, lean-evidence.sh, lean-reconcile.sh, check-lean-chain.sh — and
# every checked-in script in this repo is exercised by some selftest. A loop that lived only in
# SKILL.md would leave the three rules that matter here (the round budget's hard stop, "never
# resume a review context", and preflight's reject-and-stop) as honor-system: nothing could fail
# when they drifted. As a script they are assertable, and the spawn seam below is what lets the
# suite assert them without spending a token on a model.
#
# WHAT IT IS ALLOWED TO KNOW. Gate exit codes and tracker state. Nothing else. It does not read
# a spec, does not parse a verdict record, does not weigh a finding, and does not size a ticket
# — the moment it owns content judgment it has re-grown the stage choreography this lane exists
# to delete. `--build-model` is supplied BY the caller for exactly that reason: reading the
# ticket's `opus`/`sonnet` label is the driving skill's job, and sizing an unlabeled one is a
# judgment call that must be stated in the log rather than buried in a heuristic here.
#
# WHAT IT WRITES. Nothing. Not a tracker comment, not a label, not an artifact — every write in
# a lean run is made by a payload block under its own identity. That is not politeness: the
# merge boundary compares the verdict record's identity against the build run's, and a
# scheduler that wrote records would be a third identity in a two-identity contract.
#
# IDENTITY UNDER ORCHESTRATION. Each spawn is a fresh top-level session, so the harness stamps
# it a new session id and the audit hook opens a live ledger for it — which is what makes
# `lean-gate.sh entry` satisfiable inside a spawned session and the build-vs-review verdict
# refusal structural rather than cooperative. This script therefore never passes a session id
# and never resumes a context. `RUN_ID` and `LEAN_RUN_MODEL` are ordinary env vars and DO
# inherit, so both are scrubbed on every spawn: an inherited RUN_ID would key a child's records
# to the parent's run, and an inherited LEAN_RUN_MODEL has already false-red a nested sweep once.
#
# THE ROUND BUDGET. Three rounds; the fourth is a hard stop with no rescue attempt, mirroring
# the gate's own `rc=4` posture. Two independent routes reach it — the verdict gate returning 4
# (its milestone-4 fix budget exhausted) and this loop reaching --max-rounds — because the gate's
# counter lives in a file a fix round can reset, and a scheduler with no bound of its own would
# loop forever on a reset counter.
#
# WHY A SPAWN'S EXIT STATUS IS NOT A COMPLETION SIGNAL (#492). `claude -p` exits 0 whenever the
# model ends its turn cleanly — which is "the model stopped talking", not "the block finished".
# A headless payload that backgrounds a gate, exhausts its context, or decides to wait on
# anything produces the identical signature: exit 0, work committed, nothing left to review. So
# this loop reads a THIRD post-spawn state beside finished and failed — exited 0, no PR, but the
# run advanced — and re-spawns on it, because build-lean is outcome-gated and resumable by
# construction and its own Resume contract makes a fresh session the recovery.
#
# What it may NOT do is judge that from the session's output. "Advanced" is one opaque token from
# `lean-gate.sh progress`, compared before and after the spawn and interpreted no further; the
# gate owns the predicate, this script owns only the comparison. That is what keeps the boundary
# above ("gate exit codes and tracker state") true while this script gains a third thing to read.
#
# THE CONTINUATION BUDGET, and why it is load-bearing rather than belt-and-braces. `fail_milestone`
# appends an attempt row on every red including the over-budget one, so a spawn that hit the
# gate's own `rc=4` hard stop reads as "advanced" and would re-spawn forever. --max-continuations
# bounds that. It is NOT a new fix budget — the gate's counter still decides when a milestone is
# spent — it is a bound on CONSECUTIVE spawns that leave no PR, and it resets whenever a spawn
# yields one, so each build phase gets its own and a run that keeps advancing is not starved.
#
# THE CLOSE-OUT IS VERIFIED, NOT CREDITED. `verdict_rc` runs BEFORE the close-out spawn and
# nothing evaluated after it, so a close-out that ended its turn early exited 0 and printed
# `done` while step 9's obligations were all unmet — no closing comment, milestone 5 unsatisfied,
# the worktree still on disk, and the claimed label still set on a ticket the lane had just
# declared finished. That is worse than the no-PR case, which at least fails loudly. The check is
# the same token narrowed to milestone 5's `satisfied` row, and the row must be NEW — a re-entered
# lane must not be credited with a prior run's milestone 5. Verify-only, never a re-spawn: the
# scheduler cannot invoke `bash G 5` itself either, because a failing one routes through
# fail_milestone and would consume milestone 5's fix budget on the scheduler's behalf.
#
# Usage:
#   orchestrate-lean.sh <issue> --build-model <model> [options]
#     --build-model <m>    REQUIRED. The model for every BUILD-role session.
#     --review-model <m>   Default `opus`. REVIEW is the higher-stakes read.
#     --model-basis <text> Free text recorded in the log beside the build model, e.g. `label`
#                          or `sized-here: touches two gates`. Default `label`.
#     --max-rounds <n>     Default 3. The n+1th is the hard stop.
#     --max-continuations <n>
#                          Default 2. Consecutive BUILD spawns that exit 0, leave no PR, and
#                          advanced the run are re-spawned up to this many times per build
#                          phase; the counter resets whenever a spawn yields a PR. 0 restores
#                          the pre-#492 behavior of never continuing.
#     --intake-attested    The operator asserts intake is paid off. Required under a tracker
#                          with no queue label; never a way to skip a github label that is
#                          simply absent.
#     --dry-run            Print the schedule and exit 0 without spawning anything.
#
# Seams (every one has a shipped default pointing at the real thing):
#   LEAN_SPAWN_BIN               the session binary (default `claude`)
#   LEAN_SPAWN_PERMISSION_MODE   passed as --permission-mode (default `auto`)
#   LEAN_GATE                    the milestone gate (default: the sibling build-lean skill)
#   ${GH:-gh}                    the tracker/code-host CLI, read-only here
#   SECOND_SHIFT_CONFIG          override the resolved config path
#
# Exit: 0 = approved and closed out; 1 = a phase failed, a build phase spent its continuation
#       budget, or a close-out left step 9's exit artifacts unmet; 2 = usage or preflight reject;
#       4 = round budget exhausted (hard stop, no rescue).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH_CLI="${GH:-gh}"
SPAWN_BIN="${LEAN_SPAWN_BIN:-claude}"
PERM_MODE="${LEAN_SPAWN_PERMISSION_MODE:-auto}"
GATE="${LEAN_GATE:-$SCRIPT_DIR/../build-lean/lean-gate.sh}"

ISSUE=""
BUILD_MODEL=""
REVIEW_MODEL="opus"
MODEL_BASIS="label"
MAX_ROUNDS=3
MAX_CONTINUATIONS=2
INTAKE_ATTESTED=0
DRY_RUN=0

say()     { echo "[orchestrate-lean] $*"; }
envfail() { echo "[orchestrate-lean] $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --build-model)     BUILD_MODEL="${2:-}"; shift 2 ;;
    --review-model)    REVIEW_MODEL="${2:-}"; shift 2 ;;
    --model-basis)     MODEL_BASIS="${2:-}"; shift 2 ;;
    --max-rounds)      MAX_ROUNDS="${2:-}"; shift 2 ;;
    --max-continuations) MAX_CONTINUATIONS="${2:-}"; shift 2 ;;
    --intake-attested) INTAKE_ATTESTED=1; shift ;;
    --dry-run)         DRY_RUN=1; shift ;;
    -h|--help)         sed -n '2,95p' "$0"; exit 0 ;;
    -*)                envfail "unknown option: $1" ;;
    *)                 [ -z "$ISSUE" ] && ISSUE="$1" || envfail "unexpected argument: $1"; shift ;;
  esac
done

[ -n "$ISSUE" ] || envfail "usage: orchestrate-lean.sh <issue> --build-model <model> [options]"
[ -n "$BUILD_MODEL" ] || envfail "--build-model is required: this scheduler does not size tickets. Read the ticket's opus/sonnet label, or size it yourself and say so via --model-basis."
[ -n "$REVIEW_MODEL" ] || envfail "--review-model was given an empty value."
case "$MAX_ROUNDS" in ''|*[!0-9]*) envfail "--max-rounds must be a positive integer, got '$MAX_ROUNDS'" ;; esac
[ "$MAX_ROUNDS" -ge 1 ] || envfail "--max-rounds must be at least 1."
# Zero is legal here where it is not for --max-rounds: a run with no rounds could do nothing at
# all, whereas a run with no continuations is exactly the pre-#492 behavior and is the honest way
# to ask for it back.
case "$MAX_CONTINUATIONS" in ''|*[!0-9]*) envfail "--max-continuations must be a non-negative integer, got '$MAX_CONTINUATIONS'" ;; esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || envfail "not in a git repo."
_common="$(git rev-parse --git-common-dir 2>/dev/null)" || envfail "cannot resolve --git-common-dir."
case "$_common" in /*) : ;; *) _common="$REPO_ROOT/$_common" ;; esac
MAIN_ROOT="$(cd "$_common/.." 2>/dev/null && pwd)" || envfail "cannot resolve the main checkout."

CONFIG="${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}"
cfg() {
  local v
  if [ -f "$CONFIG" ]; then
    v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
    if [ -n "$v" ] && [ "$v" != "null" ]; then echo "$v"; return 0; fi
  fi
  echo "$2"
}
# Absent ⇒ github, and an unrecognized value is a loud error rather than a fall-through — the
# same enum lean-gate.sh and lean-reconcile.sh hold, for the same reason: a typo must not
# silently pick the arm that attests less.
TRACKER_TYPE="$(cfg '.tracker.type' 'github')"
case "$TRACKER_TYPE" in
  github|jira) : ;;
  *) envfail "unrecognized tracker.type '$TRACKER_TYPE' — expected github or jira." ;;
esac
QUEUE_LABEL="$(cfg '.tracker.labels.queue' 'ready-for-dev')"

# ---- preflight ------------------------------------------------------------------------------
# THE PROBES RUN CONCURRENTLY, and one invocation reports EVERY failure. Both halves are
# deliberate. Concurrency because the probes are independent — a network label read, a PATH
# lookup and a stat — and serial execution of independent steps is a defect in this lane, not a
# style choice. Report-everything because the operator's next action is "fix the preflight", and
# a first-failure abort makes that two round trips where the evidence for both was already in
# hand on the first.
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orchestrate-lean.XXXXXX")" || envfail "cannot create a temp dir."
trap 'rm -rf "$PROBE_DIR"' EXIT

probe_intake() {
  # A missing queue label is a REJECT-AND-STOP, never a spawned intake session (#397 D-2). Every
  # intake surface elicits through a question the operator answers; a headless intake session
  # either hangs on that question or fabricates a receipt, and the Decision Ledger has no legal
  # provenance for a fabricated one.
  if [ "$INTAKE_ATTESTED" -eq 1 ]; then
    echo "ok intake: attested by the operator (--intake-attested)"; return 0
  fi
  if [ "$TRACKER_TYPE" != "github" ]; then
    echo "FAIL intake: tracker '$TRACKER_TYPE' has no queue label, so intake cannot be read from it — pass --intake-attested once you have run intake yourself."
    return 1
  fi
  local labels
  labels="$("$GH_CLI" issue view "$ISSUE" --json labels --jq '.labels[].name' 2>/dev/null)" || {
    echo "FAIL intake: could not read #$ISSUE's labels via '$GH_CLI'"; return 1; }
  if printf '%s\n' "$labels" | grep -qxF "$QUEUE_LABEL"; then
    echo "ok intake: #$ISSUE carries the '$QUEUE_LABEL' queue label"; return 0
  fi
  echo "FAIL intake: #$ISSUE does not carry '$QUEUE_LABEL' — run intake yourself (/intake-toolkit:intake) and re-launch. This lane does not spawn an intake session."
  return 1
}

probe_spawn() {
  if command -v "$SPAWN_BIN" >/dev/null 2>&1 || [ -x "$SPAWN_BIN" ]; then
    echo "ok spawn: session binary '$SPAWN_BIN' resolves"; return 0
  fi
  echo "FAIL spawn: session binary '$SPAWN_BIN' does not resolve (set LEAN_SPAWN_BIN)"; return 1
}

probe_gate() {
  if [ -r "$GATE" ]; then
    echo "ok gate: milestone gate at $GATE"; return 0
  fi
  echo "FAIL gate: no readable milestone gate at $GATE (set LEAN_GATE)"; return 1
}

probe_intake > "$PROBE_DIR/1" 2>&1 & p1=$!
probe_spawn  > "$PROBE_DIR/2" 2>&1 & p2=$!
probe_gate   > "$PROBE_DIR/3" 2>&1 & p3=$!
wait "$p1"; r1=$?
wait "$p2"; r2=$?
wait "$p3"; r3=$?

for f in 1 2 3; do
  while IFS= read -r line; do say "  $line"; done < "$PROBE_DIR/$f"
done
if [ "$r1" -ne 0 ] || [ "$r2" -ne 0 ] || [ "$r3" -ne 0 ]; then
  say "preflight rejected — nothing was spawned."
  exit 2
fi
say "preflight: clean."
say "build model: $BUILD_MODEL (basis: $MODEL_BASIS) · review model: $REVIEW_MODEL · rounds: $MAX_ROUNDS · continuations: $MAX_CONTINUATIONS"

# ---- the work branch and its worktree ---------------------------------------------------------
# One prefix resolver for the whole marketplace; this script asks it the same question the gate
# and the evidence payload ask, rather than re-deriving `<prefix><key>` a fourth time.
# shellcheck source=../build-lean/branch-prefix.sh
. "$SCRIPT_DIR/../build-lean/branch-prefix.sh" || envfail "cannot load the sibling branch-prefix.sh."

BRANCH_KEY="$ISSUE"
[ "$TRACKER_TYPE" = "jira" ] && BRANCH_KEY="$(printf '%s' "$ISSUE" | tr '[:upper:]' '[:lower:]')"
PREFIX="$(resolve_branch_prefix "$(cfg '.tracker.branchPrefix' '')" "$TRACKER_TYPE" \
            "$(cfg '.tracker.keyPattern' '')" "$MAIN_ROOT")" || exit 2
BRANCH="$PREFIX$BRANCH_KEY"

# The gate is milestone-scoped and HEAD-bound, so it must run where the branch is checked out.
# Resolving the worktree from git rather than from a naming convention is what keeps this
# working under an operator who cut the worktree by hand.
lane_worktree() {
  local wt="" line
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) wt="${line#worktree }" ;;
      branch\ refs/heads/*) [ "${line#branch refs/heads/}" = "$BRANCH" ] && { printf '%s\n' "$wt"; return 0; } ;;
    esac
  done < <(git -C "$MAIN_ROOT" worktree list --porcelain 2>/dev/null)
  return 1
}

# ---- spawning ---------------------------------------------------------------------------------
# `-p` and a fresh prompt, never --resume/--continue. A resumed review context carries the
# previous round's conclusions into the next one, which is the single failure this lane's
# separation exists to prevent: round 2 would be round 1 agreeing with itself.
spawn() { # spawn <role> <model> <prompt>
  local role="$1" model="$2" prompt="$3" rc
  say "spawn $role — model=$model — $prompt"
  if [ "$DRY_RUN" -eq 1 ]; then return 0; fi
  env -u RUN_ID -u LEAN_RUN_MODEL LEAN_RUN_MODEL="$model" \
    "$SPAWN_BIN" --permission-mode "$PERM_MODE" --model "$model" -p "$prompt"
  rc=$?
  say "spawn $role exited $rc"
  return $rc
}

resolve_pr() {
  "$GH_CLI" pr list --head "$BRANCH" --state open --json number \
    --jq '.[0].number // empty' 2>/dev/null
}

# Called with RUN_ID unset on purpose: the gate resolves the run id from the build run's cached
# record, and an ambient value here would let the scheduler's environment decide which run a
# milestone was evaluated against.
verdict_rc() {
  local wt
  wt="$(lane_worktree)" || return 3
  ( cd "$wt" && env -u RUN_ID bash "$GATE" 4 "$ISSUE" )
}

# The continuation predicate (#492). One opaque token; this script never parses it, only compares
# two of them for equality. Same RUN_ID scrub as verdict_rc, for the same reason.
#
# Run from MAIN_ROOT, NOT the lane worktree: the progress record lives in the main checkout so it
# survives teardown, and the close-out comparison happens on both sides of a spawn whose last act
# is `bash G teardown` — a reader anchored in the worktree would be reading from a directory the
# thing it is measuring has just deleted.
#
# It RETURNS NON-ZERO rather than printing an empty token when the gate cannot answer. An empty
# token compared against an empty token agrees, and that agreement would read as "the run did not
# advance" — a broken gate would be indistinguishable from an idle session, which is the exact
# shape of error-reads-as-success this ticket exists to remove.
progress_token() { # progress_token [--satisfied <n>]
  local tok rc
  tok="$( cd "$MAIN_ROOT" && env -u RUN_ID bash "$GATE" progress "$ISSUE" "$@" 2>/dev/null )"
  rc=$?
  [ "$rc" -eq 0 ] && [ -n "$tok" ] || return 1
  printf '%s\n' "$tok"
}

if [ "$DRY_RUN" -eq 1 ]; then
  say "dry run: branch=$BRANCH · gate=$GATE · $MAX_ROUNDS round(s) of BUILD → REVIEW → verdict"
  spawn BUILD "$BUILD_MODEL" "/dev-pipeline:build-lean $ISSUE"
  spawn REVIEW "$REVIEW_MODEL" "/dev-pipeline:review-lean <pr>"
  say "dry run: nothing was spawned."
  exit 0
fi

round=1
while :; do
  say "── round $round of $MAX_ROUNDS"

  # The build phase. One spawn on the happy path; a continuation only when the spawn left no PR
  # AND the progress record moved. `continuations` is scoped to this phase, which IS the reset
  # D-3 asks for: the only way out of this loop is a PR.
  continuations=0
  PR=""
  while :; do
    tok_before="$(progress_token)" \
      || { say "cannot read the run's progress record through '$GATE' — the continuation predicate is unavailable, so a stopped BUILD session could not be told from a finished one. Not spawning blind."; exit 1; }

    spawn BUILD "$BUILD_MODEL" "/dev-pipeline:build-lean $ISSUE" \
      || { say "BUILD session failed in round $round."; exit 1; }

    PR="$(resolve_pr)"
    [ -n "$PR" ] && break

    tok_after="$(progress_token)" \
      || { say "cannot read the run's progress record through '$GATE' after the BUILD session."; exit 1; }

    # AC-3: exited 0, no PR, and nothing was recorded. Unchanged from before #492 — not
    # reviewing nothing is still correct, and a session that did nothing will do nothing twice.
    if [ "$tok_after" = "$tok_before" ]; then
      say "no open PR on '$BRANCH' after the BUILD session — nothing to review."
      exit 1
    fi

    continuations=$((continuations + 1))
    if [ "$continuations" -gt "$MAX_CONTINUATIONS" ]; then
      say "HARD STOP: the BUILD session advanced but left no PR, and this build phase has spent its --max-continuations budget ($MAX_CONTINUATIONS). The worktree and the claim are left in place for a manual rescue."
      exit 1
    fi
    say "BUILD advanced but left no open PR — continuing in a fresh session ($continuations of $MAX_CONTINUATIONS)."
  done
  say "PR #$PR is open on $BRANCH."

  spawn REVIEW "$REVIEW_MODEL" "/dev-pipeline:review-lean $PR" \
    || { say "REVIEW session failed in round $round."; exit 1; }

  verdict_rc; rc=$?
  case "$rc" in
    0)
      say "verdict: approve. Closing out."
      m5_before="$(progress_token --satisfied 5)" \
        || { say "cannot read the run's progress record through '$GATE' — the close-out cannot be verified, so it is not spawned."; exit 1; }

      spawn BUILD "$BUILD_MODEL" "/dev-pipeline:build-lean $ISSUE" \
        || { say "close-out session failed."; exit 1; }

      m5_after="$(progress_token --satisfied 5)" \
        || { say "cannot read the run's progress record through '$GATE' after the close-out session."; exit 1; }

      # AC-7. The close-out is verified against the record, never credited on its exit status.
      if [ "$m5_after" = "$m5_before" ]; then
        say "close-out session exited 0 but recorded no NEW milestone-5 satisfaction, so build-lean step 9 did not finish: the closing comment, the exit artifacts and the worktree teardown are all unaccounted for. Reporting a failure rather than 'done' — the ticket is still claimed and PR #$PR is still open. Finish step 9 by hand from the lane worktree."
        exit 1
      fi
      say "done — #$ISSUE approved on PR #$PR."
      exit 0
      ;;
    1) say "verdict: needs-work." ;;
    4) say "HARD STOP: the verdict gate exhausted its fix budget. No rescue attempt — re-entry is from the top."; exit 4 ;;
    3) say "cannot locate a worktree for '$BRANCH' — the BUILD session did not leave one."; exit 1 ;;
    *) say "the verdict gate could not run (exit $rc)."; exit 1 ;;
  esac

  round=$((round + 1))
  if [ "$round" -gt "$MAX_ROUNDS" ]; then
    say "HARD STOP: $MAX_ROUNDS rounds spent without an approve. No rescue attempt — re-entry is from the top."
    exit 4
  fi
done

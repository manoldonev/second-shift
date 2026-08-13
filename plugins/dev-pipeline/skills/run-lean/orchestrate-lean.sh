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
# THE VERDICT GATE'S RC IS A TAXONOMY, NOT A BOOLEAN (#496). Every milestone-4 failure used to
# return 1, so twenty distinct conditions arrived here as one word — and the loop had exactly one
# response to it: spend a round, re-spawn BUILD. Two of those conditions make that response wrong
# rather than merely wasteful.
#
#   5 — NO VERDICT USABLE AGAINST THE CURRENT HEAD. The review produced no record, or none that
#       covers this tree. BUILD has nothing to fix: the review half is what failed. So this spends
#       no round and spawns no BUILD; it re-spawns REVIEW once, on a counter of its own, and exits
#       5 if the second one is dark too. A dark review used to loop the lane three times and then
#       report a spent fix budget for fixes nobody ever attempted.
#   6 — INTEGRITY REFUSAL. The verdict carries the build run's identity (P10). That is the trust
#       boundary this two-session lane exists to enforce, and it reached the operator as
#       "verdict: needs-work" and was RETRIED. It is terminal here, named, and never re-spawned.
#
# EVALUATION ORDER IS PART OF THE CONTRACT. The class routes FIRST. #492's advancement test
# applies only within a phase spawn, never across verdict classes — a class-5 round that "advanced"
# is still a round with no review in it.
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
# RE-ENTERING A RUN THE LANE STOPPED ITSELF (#500). Every non-zero exit above leaves the worktree
# and the claim in place, and the operator is told to re-run once the reject is fixed. That was
# unreachable: `claim` (build-lean step 2) swaps the queue label for the claimed one, and preflight
# demanded the queue label — so the lane consumed, at step 2, the one token its own front door
# required, and every run it stopped landed in a state it could not re-enter.
#
# So the github intake probe now recognizes a SECOND accepting state: the claimed label AND a
# bot-authored `lean-claimed` marker comment on the issue. The conjunction is the guard — the label
# alone is a human moving a card, the marker alone is a stale claim on a hand-reset ticket, and only
# both together are evidence that THIS lane wrote the state being read back. A ticket that was never
# intaken presents neither, so an unintaken run still rejects.
#
# Tracker-only, deliberately: the `<issue>-run-id` cache is local state, and consulting it would
# make preflight's answer depend on which machine is asking. The marker is the same artifact
# check-lean-chain.sh evidence 3 already treats as authoritative, under the same
# `.user.type == "Bot"` trust filter — issue comments are writable by any account on a public repo,
# so an operator-posted marker is not evidence the harness ran. Re-entry costs no tracker write: it
# restores nothing, and build-lean skips its claim when the run is already claimed.
#
# Usage:
#   orchestrate-lean.sh <issue> --build-model <model> [options]
#     --build-model <m>    REQUIRED. The model for every BUILD-role session.
#     --review-model <m>   Defaults to the shipped review tier. REVIEW is the higher-stakes read.
#     --review-model-basis <text>
#                          Free text, no default. Required when --review-model departs from
#                          the shipped default; also accepted (and echoed) alongside it.
#     --model-basis <text> Free text recorded in the log beside the build model, e.g. `label`
#                          or `sized-here: touches two gates`. Default `label`.
#     --max-rounds <n>     Default 3. The n+1th is the hard stop.
#     --max-continuations <n>
#                          Default 2. Consecutive BUILD spawns that exit 0, leave no PR, and
#                          advanced the run are re-spawned up to this many times per build
#                          phase; the counter resets whenever a spawn yields a PR. 0 restores
#                          the pre-#492 behavior of never continuing.
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
#       budget, the lane's PR could not be resolved unambiguously, or a close-out left step 9's
#       exit artifacts unmet; 2 = usage or preflight reject; 4 = round budget exhausted (hard stop,
#       no rescue); 5 = no verdict record usable against the current head, after the bounded REVIEW
#       retry; 6 = an integrity refusal (P10) — terminal, never retried.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH_CLI="${GH:-gh}"
SPAWN_BIN="${LEAN_SPAWN_BIN:-claude}"
PERM_MODE="${LEAN_SPAWN_PERMISSION_MODE:-auto}"
GATE="${LEAN_GATE:-$SCRIPT_DIR/../build-lean/lean-gate.sh}"

ISSUE=""
BUILD_MODEL=""
REVIEW_MODEL_DEFAULT="opus"
REVIEW_MODEL="$REVIEW_MODEL_DEFAULT"
REVIEW_MODEL_BASIS=""
MODEL_BASIS="label"
MAX_ROUNDS=3
MAX_CONTINUATIONS=2
# #496 D-10: exactly one. Not a flag — a knob here would let an operator turn a broken review lane
# into an expensive one, and the bound is the point.
MAX_REVIEW_RETRIES=1
DRY_RUN=0

say()     { echo "[orchestrate-lean] $*"; }
envfail() { echo "[orchestrate-lean] $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --build-model)        BUILD_MODEL="${2:-}"; shift 2 ;;
    --review-model)       REVIEW_MODEL="${2:-}"; shift 2 ;;
    --review-model-basis) REVIEW_MODEL_BASIS="${2:-}"; shift 2 ;;
    --model-basis)        MODEL_BASIS="${2:-}"; shift 2 ;;
    --max-rounds)         MAX_ROUNDS="${2:-}"; shift 2 ;;
    --max-continuations)  MAX_CONTINUATIONS="${2:-}"; shift 2 ;;
    --dry-run)            DRY_RUN=1; shift ;;
    -h|--help)            sed -n '2,134p' "$0"; exit 0 ;;
    -*)                   envfail "unknown option: $1" ;;
    *)                    [ -z "$ISSUE" ] && ISSUE="$1" || envfail "unexpected argument: $1"; shift ;;
  esac
done

[ -n "$ISSUE" ] || envfail "usage: orchestrate-lean.sh <issue> --build-model <model> [options]"
[ -n "$BUILD_MODEL" ] || envfail "--build-model is required: this scheduler does not size tickets. Read the ticket's opus/sonnet label, or size it yourself and say so via --model-basis."
[ -n "$REVIEW_MODEL" ] || envfail "--review-model was given an empty value."
# A departure from the shipped review tier costs nothing today, and that is the whole defect
# (#490): the knob whose misuse weakens the gate itself is the one knob free to turn. Comparing
# against the captured default rather than a literal keeps the tier name spelled in one place.
if [ "$REVIEW_MODEL" != "$REVIEW_MODEL_DEFAULT" ] && [ -z "$REVIEW_MODEL_BASIS" ]; then
  envfail "--review-model '$REVIEW_MODEL' departs from the shipped default ('$REVIEW_MODEL_DEFAULT'): say why via --review-model-basis, e.g. 'sized-here: rate-limited on $REVIEW_MODEL_DEFAULT'."
fi
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
# #496 S4, and the same guard the gate carries — the two copies differ by a comment and shared this
# defect. ABSENT means "this consumer configured nothing" and every default below is the documented
# answer; PRESENT-BUT-UNPARSEABLE means the operator's intent is unknown, and the defaults are not
# neutral — `.tracker.type` falls back to `github`, whose intake arm attests MORE than jira's, so a
# corrupt file silently picks a policy. Fail closed.
#
# UP FRONT AND OUTSIDE `cfg`, because `cfg` is called as `$(cfg …)`: an `exit` in there kills the
# command substitution's subshell, the caller reads an empty string, and the refusal is invisible.
# Exactly the shape resolve_pr avoids below by counting in the caller.
if [ -f "$CONFIG" ] && ! jq empty "$CONFIG" >/dev/null 2>&1; then
  envfail "config $CONFIG exists but is not parseable JSON — refusing to fall back to defaults, which would silently select tracker.type=github. Fix the file (jq empty '$CONFIG' names the parse error) or point SECOND_SHIFT_CONFIG elsewhere."
fi
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
# The same default lean-gate.sh carries, because the re-entry arm below reads back the label the
# gate's own `claim` wrote. A consumer that renamed one and not the other would have re-entry
# silently stop matching, which is why both resolve from the same config key.
CLAIMED_LABEL="$(cfg '.tracker.labels.claimed' 'in-progress')"
# The claim marker's stage tag. A FOURTH copy of lean-gate.sh's LEAN_CLAIM_MARKER_TAG, and
# deliberately NOT a lockstep row — see scripts/lockstep-manifest.tsv's lean-producer-capabilities
# comment, which records this and lean-reconcile.sh as the two non-rows. Drift here fails CLOSED
# (re-entry stops being recognized, loudly, on the next stopped run) rather than silently
# weakening a merge boundary, which is what earns a row.
CLAIM_MARKER_TAG='lean-claimed'

# ---- preflight ------------------------------------------------------------------------------
# THE PROBES RUN CONCURRENTLY, and one invocation reports EVERY failure. Both halves are
# deliberate. Concurrency because the probes are independent — a network label read, a PATH
# lookup and a stat — and serial execution of independent steps is a defect in this lane, not a
# style choice. Report-everything because the operator's next action is "fix the preflight", and
# a first-failure abort makes that two round trips where the evidence for both was already in
# hand on the first.
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orchestrate-lean.XXXXXX")" || envfail "cannot create a temp dir."
trap 'rm -rf "$PROBE_DIR"' EXIT

# #500 D-1/D-7. The run id off this lane's own claim marker, or empty when there is none.
# NON-ZERO means the READ failed, which is not the same answer as "no marker" and must not
# collapse into it (D-8) — one is an environment error the operator has to fix before any verdict
# means anything, the other is a legitimate reject with its own message.
#
# `gh api …/comments`, not `gh issue view --json comments`: measured on this repo, the latter
# exposes only `.author.login` (unsuffixed), while the trust filter the merge boundary applies —
# and that this arm must apply too, on a repo where anyone can post a comment — is
# `.user.type == "Bot"`, which only the API response carries.
#
# UNWINDOWED and `first`, where check-lean-chain.sh windows at PR-open: preflight has no PR to
# window at, and `first` names what that boundary will hold this run's verdict against (D-6).
claim_marker_run_id() {
  local comments
  comments="$("$GH_CLI" api "repos/{owner}/{repo}/issues/$ISSUE/comments" --paginate 2>/dev/null)" || return 1
  printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$comments" | jq -r --arg tag "$CLAIM_MARKER_TAG" '
    [ .[]
      | select((.user.type // "") == "Bot")
      | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*" + $tag + "[[:space:]]*-->"))
      | (.body // "")
    ]
    | map(capture("run_id:[[:space:]]*(?<r>[A-Za-z0-9._-]+)").r? // "")
    | map(select(. != ""))
    | first // ""' 2>/dev/null || return 1
}

probe_intake() {
  # A missing queue label is a REJECT-AND-STOP, never a spawned intake session (#397 D-2). Every
  # intake surface elicits through a question the operator answers; a headless intake session
  # either hangs on that question or fabricates a receipt, and the Decision Ledger has no legal
  # provenance for a fabricated one. That rule governs GITHUB, where the label is readable.
  #
  # Under any other tracker there is nothing to read: this script has no jira query path, and the
  # operator attestation that used to stand in for one was persisted nowhere, so it enforced no
  # checkable property. Say that intake is ungated here and pass — the same answer lean-gate.sh
  # already gives for this condition rather than inventing a second, stricter one.
  if [ "$TRACKER_TYPE" != "github" ]; then
    echo "ok intake: tracker '$TRACKER_TYPE' exposes no queue label — intake is not gated here."
    echo "   Run /intake-toolkit:intake before the lane."
    return 0
  fi
  local labels
  labels="$("$GH_CLI" issue view "$ISSUE" --json labels --jq '.labels[].name' 2>/dev/null)" || {
    echo "FAIL intake: could not read #$ISSUE's labels via '$GH_CLI'"; return 1; }
  if grep -qxF "$QUEUE_LABEL" <<<"$labels"; then
    echo "ok intake: #$ISSUE carries the '$QUEUE_LABEL' queue label"; return 0
  fi
  # #500 AC-1: the second accepting state. Gated on the claimed label FIRST so an ordinary
  # unintaken ticket costs no extra tracker read at all — the reject path is unchanged in shape as
  # well as in wording.
  if grep -qxF "$CLAIMED_LABEL" <<<"$labels"; then
    local marker_run_id
    marker_run_id="$(claim_marker_run_id)" || {
      echo "FAIL intake: #$ISSUE carries '$CLAIMED_LABEL', but its comment trail could not be read via '$GH_CLI' — so whether this is a re-entry of a run this lane stopped is unknown. Refusing rather than guessing; re-launch once the tracker read works."
      return 1; }
    if [ -n "$marker_run_id" ]; then
      # D-9: named as re-entry, and carrying the run id, because the log is the operator's only
      # evidence for why preflight did not reject — and (OR-1) the printed id is what makes a
      # second lane on the same ticket visible rather than silent.
      echo "ok intake: re-entry — #$ISSUE carries '$CLAIMED_LABEL' and this lane's bot-authored '$CLAIM_MARKER_TAG' marker from run '$marker_run_id'. Intake was paid off before that claim; nothing is re-labelled."
      return 0
    fi
    echo "FAIL intake: #$ISSUE carries '$CLAIMED_LABEL' but no bot-authored '$CLAIM_MARKER_TAG' marker, so nothing shows this lane ever claimed it — the label alone is not evidence intake was paid off. Run intake yourself (/intake-toolkit:intake) and re-launch."
    return 1
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
# The basis parenthetical is appended only when non-empty — never synthesized as "(basis: )" or
# a fabricated "shipped default" note, either of which would make an unstated basis
# indistinguishable from a stated one in the very log this ticket exists to make legible.
REVIEW_BASIS_NOTE=""
[ -n "$REVIEW_MODEL_BASIS" ] && REVIEW_BASIS_NOTE=" (basis: $REVIEW_MODEL_BASIS)"
say "build model: $BUILD_MODEL (basis: $MODEL_BASIS) · review model: $REVIEW_MODEL$REVIEW_BASIS_NOTE · rounds: $MAX_ROUNDS · continuations: $MAX_CONTINUATIONS"

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

# #496 S4. EVERY match, one per line — the caller decides. `.[0].number` silently picked the first
# of however many open PRs share this head, so a lane with two of them reviewed one and closed out
# against the other with nothing printed. The refusal lives in the CALLER rather than here for a
# mechanical reason: this runs inside `$(resolve_pr)`, where a `return 1` is invisible to the
# assignment and an `exit` kills only the subshell.
resolve_pr() {
  "$GH_CLI" pr list --head "$BRANCH" --state open --json number \
    --jq '.[].number' 2>/dev/null
}

# Called with RUN_ID unset on purpose: the gate resolves the run id from the build run's cached
# record, and an ambient value here would let the scheduler's environment decide which run a
# milestone was evaluated against.
#
# THROUGH THE OBSERVE SEAM (#496 S3). This was the last RECORDING gate call the scheduler made:
# every non-approve verdict it merely READ appended a milestone-4 attempt line and spent the build
# role's fix budget — so the premise that this script writes nothing was false at exactly one site.
# `LEAN_GATE_OBSERVE=1` returns the same taxonomy and records nothing, budget exhaustion included.
verdict_rc() {
  local wt
  wt="$(lane_worktree)" || return 3
  ( cd "$wt" && env -u RUN_ID LEAN_GATE_OBSERVE=1 bash "$GATE" 4 "$ISSUE" )
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
    # More than one open PR on this head is not a state to guess through: the review would run on
    # one and the close-out could verify the other. Named, not counted silently.
    if [ "$(printf '%s' "$PR" | grep -c '[0-9]')" -gt 1 ]; then
      say "more than one open PR on '$BRANCH' ($(printf '%s' "$PR" | tr '\n' ' ')) — the lane cannot choose which one this run is about. Close or retarget the extras and re-launch."
      exit 1
    fi
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

  # The review phase, and its own bounded retry. A class-5 read means the review produced nothing
  # usable against this head — dark, uncommitted, or stale — which is a failure of the REVIEW half,
  # so the recovery is another review, not another round of fixes. One re-spawn, on a counter
  # separate from --max-rounds and --max-continuations, because a second dark review is a broken
  # review lane rather than bad luck and a third would only cost more to learn the same thing.
  review_retries=0
  while :; do
    spawn REVIEW "$REVIEW_MODEL" "/dev-pipeline:review-lean $PR" \
      || { say "REVIEW session failed in round $round."; exit 1; }

    verdict_rc; rc=$?
    [ "$rc" -eq 5 ] || break

    review_retries=$((review_retries + 1))
    if [ "$review_retries" -gt "$MAX_REVIEW_RETRIES" ]; then
      say "HARD STOP: the REVIEW session left no verdict record usable against the current head, twice. No round was spent and no BUILD session was spawned — BUILD has nothing to fix when the review half is what failed. Run '/dev-pipeline:review-lean $PR' by hand and read its output; the worktree and the claim are left in place."
      exit 5
    fi
    say "no verdict record usable against the current head — re-spawning REVIEW ($review_retries of $MAX_REVIEW_RETRIES). No round spent, no BUILD spawn."
  done

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
      # The NEW-row requirement costs the legitimate re-entry too: `append_satisfied` is idempotent
      # and the progress file is keyed by issue rather than by run, so a second full lane run over
      # an issue whose record already carries `| milestone-5 | satisfied` cannot move this token,
      # and its correct close-out is reported as the failure below. Deliberate: that failure is
      # loud and hand-recoverable, where a false `done` is neither.
      if [ "$m5_after" = "$m5_before" ]; then
        say "close-out session exited 0 but recorded no NEW milestone-5 satisfaction, so build-lean step 9 did not finish: the closing comment, the exit artifacts and the worktree teardown are all unaccounted for. Reporting a failure rather than 'done' — the ticket is still claimed and PR #$PR is still open. Finish step 9 by hand from the lane worktree."
        exit 1
      fi
      say "done — #$ISSUE approved on PR #$PR."
      exit 0
      ;;
    1) say "verdict: needs-work." ;;
    6) say "HARD STOP: the verdict record is authored by the build run or the build session (P10) — generation may not author its own evaluation, and that is not something a retry can clear. No round spent, nothing re-spawned. The merge boundary refuses this record too; produce one from a separate review session."; exit 6 ;;
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

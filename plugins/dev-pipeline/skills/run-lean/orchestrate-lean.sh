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
# THE CLOSE-OUT IS A GATE CALL, NOT A SPAWN (#590). It used to be a third full model session on
# the run's BUILD model, and everything it did after the approve was a fixed sequence of commands:
# re-compute the cost block, replace it in the PR description, post one closing comment, assert
# milestone 5, tear the lane down. `bash G close-out` performs all of it under the bot identity
# the lane already commits and comments with, so the two-identity contract is untouched — the
# rule this script holds is that it authors nothing UNDER ITS OWN IDENTITY, and a bot-authored
# artifact is the build side's, exactly as the claim marker and the PR marker already are.
#
# THREE MECHANISMS DIED WITH THE SPAWN (D-3/D-5): the continuation budget, the advancement-token
# comparison, and the verified-not-credited rule. All three existed to work around ONE property
# of a model session — `claude -p` exits 0 whenever the model ends its turn, so a close-out that
# stopped early exited 0 and printed `done` over a run with no closing comment on it. A gate
# command cannot end its turn early. Its exit code IS the verdict, which is already the lane's
# evidence rule at every other call site, and reading it also removes the acknowledged wart where
# a legitimate second lane run over an already-closed issue was reported as a failure because the
# NEW-row requirement could never be met by an idempotent append.
#
# WHAT SURVIVES: the ONE RETRY (MAX_REVIEW_RETRIES' reasoning at a cheaper site), the in-flight
# read on the far side, and the per-obligation report. That last is #531 D-10/D-12 and is worth
# restating: the failure used to name three obligations as one — "the closing comment, the exit
# artifacts and the worktree teardown are all unaccounted for" — which was wrong twice, since
# milestone 5 never asserted the teardown at all and could not say which of the other two was
# outstanding. The gate records a row per obligation and reports them through
# `progress --obligations`; this script ECHOES those lines and reads nothing, which is the same
# division `progress` and `staleness` already hold.
#
# A HEAD THAT ALREADY CARRIES AN APPROVE IS NOT RE-REVIEWED (#531 D-7). The round loop entered the
# build phase unconditionally and the REVIEW spawn PRECEDED the only verdict read, so a re-entry
# ran BUILD and then fell into a review against an already-approved head — and a fresh round could
# author a COMPETING verdict record for it. On the run that surfaced this it was killed by hand.
# `verdict_rc` now runs first; rc=0 skips the review and falls into the close-out rather than
# stopping, because stopping would strand finished, reviewed work.
#
# THE BUILD EXIT CONTRACT IS A GATE CALL, NOT PROSE (#531 D-3/D-4). A BUILD session that exits 0
# with commits unpushed or a dirty tree is `claude -p` ending a turn, and everything this loop
# reads afterwards is about a REMOTE head missing whatever it did — three occurrences in a single
# run of one ticket, each costing a full review round, with nothing in the log to tell them from a
# legitimate one. #535 added a PROSE rule against exactly this, it shipped installed, and the very
# next run ignored it. So the check is `bash G inflight`, called on every BUILD spawn that produced
# a PR and after the close-out — never on the no-PR path, where an unpushed commit is the ORDINARY
# state of a lane that has not reached checklist step 7 yet, and where a stop would hard-fail the
# very spawn #527 taught this loop to continue from. It is a SCHEDULER-BOUNDARY check only: folding
# it into `bash G all` would
# spend milestone-5 fix budget on a condition whose remedy is one push, and the directly-invoked
# two-terminal flow has a human watching by construction. No trap-based push, which the ticket
# also asked for: SIGKILL is untrappable and under `claude -p` no build-session process survives to
# carry a trap, so its only host would be spawn() — making this script a source-control writer
# against its own header two paragraphs up.
#
# THE TERMINAL TAXONOMY (#531 D-1). Every run-ending exit prints `terminal: <slug>` before it goes,
# so a log can be routed on the CONDITION rather than on a prose match that moves with the wording.
# The slugs are in the LOG and not in the exit contract: the codes below are unchanged, nothing in
# this lane branches on an exit-1 subclass, and run-lean/SKILL.md — which enumerates the codes —
# sits at exactly the 60-line cap its own selftest asserts.
#
# THE LOG IS THREE-WAY SEPARABLE (#531 D-5/D-6). `spawn` ran the child with no redirection, so its
# stdout and stderr interleaved with control lines on both streams, and `say` wrote stdout while
# `envfail` wrote stderr — even this script's own output was split. Now: control lines are stdout
# and timestamped (ISO-8601 UTC, the gate's `now_iso` format, so they sort against progress-file
# rows without conversion), payload goes to stderr AND to a per-role transcript under the
# pipeline-state dir. The terminal still shows everything; a plain stdout redirect captures pure
# control; the transcript is pure payload and is the durable per-phase timeline whose absence forced
# one run's timings to be rebuilt from git and PR metadata.
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
# THE RUN'S PREMISE CAN EXPIRE WHILE THE RUN IS IN FLIGHT (#515). Everything above reads tracker
# and base state exactly once, at preflight, and never again: a continuation inherits the original
# branch point, and nothing asks whether the ticket is still open. Measured here — a branch kept
# working for 30 minutes after another PR landed the same fix, and its ticket was not closed until
# 63 minutes after that. The session was not stuck and was not looping; it was diligently verifying
# work that no longer needed doing.
#
# So the build phase re-asks before EVERY build spawn, through the gate's read-only `staleness`
# subcommand: the loop owns the comparison, the gate owns the predicate — the same division
# `progress` established, and for the same reason. A file-overlap heuristic inlined here would
# break the boundary two paragraphs up.
#
# WHICH SPAWNS, and which deliberately not (D-4). Round-1 entry, every continuation, and every
# later round's build spawn. NOT the REVIEW spawn and, since #590 deleted it, no close-out spawn
# exists to exempt — the close-out is a gate call. An approved PR must still land, and a stop
# there would strand finished, reviewed work rather than save any.
#
# WHAT IT CANNOT DO, said out loud so exit 7 is not misread as a promptness guarantee (OR-3): this
# is a SPAWN-BOUNDARY check and there is no channel into a live `claude -p`, so the incident's 30
# redundant in-session minutes would still be spent. It bounds the damage at one session, not at
# zero.
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
#       budget, the lane's PR could not be resolved unambiguously, the close-out did not complete
#       twice running, or a staleness / progress / infra-residue read could not be
#       completed (#527: every one of the three is fail-closed — a predicate that could not be
#       evaluated is not a predicate that passed); 2 = usage or preflight
#       reject, including a launch onto an already-closed ticket; 4 = round budget exhausted (hard
#       stop, no rescue); 5 = no verdict record usable against the current head, after the bounded
#       REVIEW retry; 6 = an integrity refusal (P10) — terminal, never retried; 7 = the run's
#       premise expired mid-flight (#515) — the ticket closed, or the base moved into this
#       branch's files.
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

# #531 D-6. THE CLOCK, in the gate's own `now_iso` format, so scheduler control lines and
# progress-file rows sort against each other without conversion. Reconstructing one run's phase
# timings previously meant rebuilding the whole timeline from git and PR metadata, because the
# only chronology in a run lived in the gate's record and nothing here could be joined to it.
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# #531 D-5. ONE STREAM FOR CONTROL. `say` wrote stdout and `envfail` wrote stderr, so even this
# script's own lines were split across two — and a watcher filtering the merged log for "error"
# caught build-session prose. Control is stdout, all of it; the PAYLOAD is what goes to stderr now
# (see spawn), which is what makes the two mechanically separable rather than a matter of reading
# carefully.
say()     { echo "$(now_iso) [orchestrate-lean] $*"; }

# #531 D-1. THE TERMINAL TAXONOMY. Counting this file's bare status-1 exits used to return
# thirteen sites, and one of them — "BUILD advanced but left no open PR" — covered *paused on a
# question nothing could answer*, *crashed*, and *orphaned its sweep and died*: three different
# remedies behind one scalar. Every run-ending exit now prints a stable machine-readable slug, so
# a log can be routed on the CONDITION rather than on a prose match that moves with the wording.
#
# #585. That count is spelled in words on purpose, and so is the text-search idiom that produced
# it. The mutation enumerator reads prose as code, so naming either literal here manufactures a
# phantom site — this one line was ordinal 1 for TWO operators at once while the guard's real
# sites had all moved into terminal(), which is how it reached the nightly as a survivor no case
# could ever kill. Keep it in words.
#
# THE SLUG IS IN THE LOG, NOT IN THE EXIT CONTRACT, and that is deliberate rather than a
# compromise. The eight documented exit codes below are unchanged: run-lean/SKILL.md enumerates
# them and sits at exactly the 60-line cap its selftest asserts, so thirteen codes cannot be
# documented there — and nothing in this lane branches on an exit-1 subclass. The harm the ticket
# names is an unclassifiable LOG, not a caller that cannot branch, so that is where the fix lands.
#
# EVERY run-ending path goes through here, usage refusals included. `--help` deliberately does not:
# it prints documentation and starts no run, so a terminal line there would name a state that never
# existed.
terminal() { # terminal <slug> <exit-code> <message...>
  local slug="$1" code="$2"
  shift 2
  say "terminal: $slug — $*"
  exit "$code"
}
envfail() { terminal "$1" 2 "$2"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --build-model)        BUILD_MODEL="${2:-}"; shift 2 ;;
    --review-model)       REVIEW_MODEL="${2:-}"; shift 2 ;;
    --review-model-basis) REVIEW_MODEL_BASIS="${2:-}"; shift 2 ;;
    --model-basis)        MODEL_BASIS="${2:-}"; shift 2 ;;
    --max-rounds)         MAX_ROUNDS="${2:-}"; shift 2 ;;
    --max-continuations)  MAX_CONTINUATIONS="${2:-}"; shift 2 ;;
    --dry-run)            DRY_RUN=1; shift ;;
    -h|--help)            sed -n '2,215p' "$0"; exit 0 ;;
    -*)                   envfail usage-unknown-option "unknown option: $1" ;;
    *)                    [ -z "$ISSUE" ] && ISSUE="$1" || envfail usage-unexpected-argument "unexpected argument: $1"; shift ;;
  esac
done

[ -n "$ISSUE" ] || envfail usage-missing-issue "usage: orchestrate-lean.sh <issue> --build-model <model> [options]"
[ -n "$BUILD_MODEL" ] || envfail usage-missing-build-model "--build-model is required: this scheduler does not size tickets. Read the ticket's opus/sonnet label, or size it yourself and say so via --model-basis."
[ -n "$REVIEW_MODEL" ] || envfail usage-empty-review-model "--review-model was given an empty value."
# A departure from the shipped review tier costs nothing today, and that is the whole defect
# (#490): the knob whose misuse weakens the gate itself is the one knob free to turn. Comparing
# against the captured default rather than a literal keeps the tier name spelled in one place.
if [ "$REVIEW_MODEL" != "$REVIEW_MODEL_DEFAULT" ] && [ -z "$REVIEW_MODEL_BASIS" ]; then
  envfail usage-review-model-basis "--review-model '$REVIEW_MODEL' departs from the shipped default ('$REVIEW_MODEL_DEFAULT'): say why via --review-model-basis, e.g. 'sized-here: rate-limited on $REVIEW_MODEL_DEFAULT'."
fi
case "$MAX_ROUNDS" in ''|*[!0-9]*) envfail usage-max-rounds "--max-rounds must be a positive integer, got '$MAX_ROUNDS'" ;; esac
[ "$MAX_ROUNDS" -ge 1 ] || envfail usage-max-rounds "--max-rounds must be at least 1."
# Zero is legal here where it is not for --max-rounds: a run with no rounds could do nothing at
# all, whereas a run with no continuations is exactly the pre-#492 behavior and is the honest way
# to ask for it back.
case "$MAX_CONTINUATIONS" in ''|*[!0-9]*) envfail usage-max-continuations "--max-continuations must be a non-negative integer, got '$MAX_CONTINUATIONS'" ;; esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || envfail env-no-git-repo "not in a git repo."
_common="$(git rev-parse --git-common-dir 2>/dev/null)" || envfail env-git-common-dir "cannot resolve --git-common-dir."
case "$_common" in /*) : ;; *) _common="$REPO_ROOT/$_common" ;; esac
MAIN_ROOT="$(cd "$_common/.." 2>/dev/null && pwd)" || envfail env-main-root "cannot resolve the main checkout."

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
  envfail env-config-unparseable "config $CONFIG exists but is not parseable JSON — refusing to fall back to defaults, which would silently select tracker.type=github. Fix the file (jq empty '$CONFIG' names the parse error) or point SECOND_SHIFT_CONFIG elsewhere."
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
  *) envfail env-tracker-type "unrecognized tracker.type '$TRACKER_TYPE' — expected github or jira." ;;
esac
QUEUE_LABEL="$(cfg '.tracker.labels.queue' 'ready-for-dev')"
# The same default lean-gate.sh carries, because the re-entry arm below reads back the label the
# gate's own `claim` wrote. A consumer that renamed one and not the other would have re-entry
# silently stop matching, which is why both resolve from the same config key.
CLAIMED_LABEL="$(cfg '.tracker.labels.claimed' 'in-progress')"
# The claim marker's stage tag. A FOURTH copy of lean-gate.sh's LEAN_CLAIM_MARKER_TAG, and
# deliberately NOT a LOCKSTEP site — see docs/testing.md, which records this and lean-reconcile.sh
# as the two unbound copies under *Couplings considered and declined*. Drift here fails CLOSED
# (re-entry stops being recognized, loudly, on the next stopped run) rather than silently
# weakening a merge boundary, which is what earns a row.
CLAIM_MARKER_TAG='lean-claimed'

# #531 D-5. WHERE THE PAYLOAD TRANSCRIPT LANDS. The same default and the same config key the gate
# resolves, so a consumer that re-rooted its state dir gets its scheduler logs beside its progress
# record rather than in a second place nothing points at.
#
# AND NO, THIS DOES NOT BREAK "WHAT IT WRITES: NOTHING". That premise is about ARTIFACTS — records
# carrying a run's identity, which the merge boundary compares — and a transcript carries none: it
# is a local cache of bytes the spawned session already emitted, read by an operator and by no gate.
# It is the same distinction #515 drew for the staleness fetch's remote-tracking ref. What it buys
# is the durable per-phase timeline whose absence forced one run's timings to be rebuilt from git
# and PR metadata.
STATE_DIR="$(cfg '.paths.pipelineStateDir' '.claude/pipeline-state')"
LOG_DIR="$MAIN_ROOT/$STATE_DIR"

# ---- preflight ------------------------------------------------------------------------------
# THE PROBES RUN CONCURRENTLY, and one invocation reports EVERY failure. Both halves are
# deliberate. Concurrency because the probes are independent — a network label read, a PATH
# lookup and a stat — and serial execution of independent steps is a defect in this lane, not a
# style choice. Report-everything because the operator's next action is "fix the preflight", and
# a first-failure abort makes that two round trips where the evidence for both was already in
# hand on the first.
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orchestrate-lean.XXXXXX")" || envfail env-temp-dir "cannot create a temp dir."
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

# #515 D-4/D-6. The TICKET arm only, and the asymmetry is deliberate: the base arm belongs to the
# spawn loop, so a re-launch that was never rebased fires exit 7 at the same point it fired last
# time (D-10) rather than becoming a preflight reject the operator has to read differently. Here
# nothing has been spawned yet, so a closed ticket is exit 2 like every other preflight refusal.
#
# Through the gate rather than a `gh issue view --json state` inlined here, even though this
# script is allowed to read tracker state: one implementation of "is the ticket still open" is
# what stops the two call sites from drifting into two answers.
probe_ticket() {
  local out rc
  out="$( cd "$MAIN_ROOT" && env -u RUN_ID bash "$GATE" staleness "$ISSUE" --arm ticket 2>&1 )"
  rc=$?
  # #528: this capture merges stderr so a failure carries the gate's diagnostic, and the gate now
  # announces its resolved config path there. That belongs in a run's record, not inlined into the
  # one-line preflight verdict a human reads. Filtered AFTER `rc` is taken, never by piping the
  # capture itself — a trailing `grep` would report its own status as the gate's.
  out="$(printf '%s\n' "$out" | grep -v '^\[lean-gate\] config: ')"
  case "$rc" in
    0) echo "ok ticket: $out"; return 0 ;;
    7) echo "FAIL ticket: $out"
       echo "FAIL ticket: this run's premise is already false — nothing was spawned. Re-open #$ISSUE if the work is still wanted, or drop the launch."
       return 1 ;;
    # Fail closed (D-5). An unreadable tracker is not an open ticket, and preflight is exactly
    # where that distinction is cheapest to act on.
    *) echo "FAIL ticket: the staleness check could not be completed (gate exit $rc): $out"; return 1 ;;
  esac
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
probe_ticket > "$PROBE_DIR/4" 2>&1 & p4=$!
wait "$p1"; r1=$?
wait "$p2"; r2=$?
wait "$p3"; r3=$?
wait "$p4"; r4=$?

for f in 1 2 3 4; do
  while IFS= read -r line; do say "  $line"; done < "$PROBE_DIR/$f"
done
if [ "$r1" -ne 0 ] || [ "$r2" -ne 0 ] || [ "$r3" -ne 0 ] || [ "$r4" -ne 0 ]; then
  terminal preflight-rejected 2 "preflight rejected — nothing was spawned."
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
. "$SCRIPT_DIR/../build-lean/branch-prefix.sh" || envfail env-branch-prefix-lib "cannot load the sibling branch-prefix.sh."

BRANCH_KEY="$ISSUE"
[ "$TRACKER_TYPE" = "jira" ] && BRANCH_KEY="$(printf '%s' "$ISSUE" | tr '[:upper:]' '[:lower:]')"
# The resolver prints its own diagnosis, so this adds the slug and nothing else — a second wording
# of a refusal the shared library already worded is how two answers to one question start.
PREFIX="$(resolve_branch_prefix "$(cfg '.tracker.branchPrefix' '')" "$TRACKER_TYPE" \
            "$(cfg '.tracker.keyPattern' '')" "$MAIN_ROOT")" \
  || terminal env-branch-prefix 2 "the lane's branch prefix could not be resolved — see the line above."
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
#
# #531 D-5. THE STREAM SPLIT. `spawn` ran the child with NO redirection, so the spawned session's
# stdout and stderr interleaved with this script's control lines on both streams at once, and the
# run was one undifferentiated log. Three-way separable now:
#
#   * the terminal still shows everything, which is what an operator watching a live run needs;
#   * a plain `> control.log` captures ONLY control lines, because the payload is on stderr;
#   * the per-role file is ONLY payload, and is the durable per-phase timeline.
#
# `2>&1 | tee` rather than a process substitution, and the choice is mechanical: `> >(tee …)` leaves
# the tee racing past the child's exit, so the last lines of a phase can land after the control line
# announcing its end. A pipeline is ordered, and `${PIPESTATUS[0]}` is the child's own status —
# read explicitly rather than relying on `$?`, which under this pipeline is tee's.
SPAWN_N=0
spawn() { # spawn <role> <model> <prompt>
  local role="$1" model="$2" prompt="$3" rc lower log
  SPAWN_N=$((SPAWN_N + 1))
  lower="$(printf '%s' "$role" | tr '[:upper:]' '[:lower:]')"
  log="$LOG_DIR/$ISSUE-lean-spawn-$SPAWN_N-$lower.log"
  say "spawn $role — model=$model — $prompt"
  if [ "$DRY_RUN" -eq 1 ]; then return 0; fi
  # ADVISORY, never fatal (AC-3). A transcript that cannot be opened is a lost convenience; a run
  # stopped over one would be this script deciding that its own logging outranks the work. The
  # mkdir is part of that: round 1's first spawn precedes the BUILD session's own `entry`, so on a
  # checkout that has never run the lane the state dir does not exist yet and every transcript
  # would degrade for the life of the run.
  mkdir -p "$LOG_DIR" 2>/dev/null
  if ! ( : > "$log" ) 2>/dev/null; then
    say "  the payload transcript could not be opened at $log — the run continues and the payload still reaches stderr."
    log=/dev/null
  else
    say "  payload transcript: $log"
  fi
  env -u RUN_ID -u LEAN_RUN_MODEL LEAN_RUN_MODEL="$model" \
    "$SPAWN_BIN" --permission-mode "$PERM_MODE" --model "$model" -p "$prompt" 2>&1 \
    | tee -a "$log" >&2
  rc=${PIPESTATUS[0]}
  say "spawn $role exited $rc"
  return "$rc"
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
# #515. Both arms, from MAIN_ROOT and with RUN_ID scrubbed, for the same two reasons progress_token
# carries: the branch ref and the remote-tracking ref live in the main checkout's common dir, and
# an ambient run id must not let the scheduler's environment key anything the gate resolves.
#
# Output is NOT suppressed — the gate's line naming which arm fired and what it saw IS the
# operator's evidence for the stop, and this script must not paraphrase a predicate it does not own.
staleness_rc() {
  ( cd "$MAIN_ROOT" && env -u RUN_ID bash "$GATE" staleness "$ISSUE" )
}

# #531 D-3. THE BUILD EXIT CONTRACT, mechanized as a gate call rather than as build-lean prose.
# #535 added a prose rule against ending a turn with work in flight, it shipped installed, and the
# very next run ignored it — which is the class #166 exists for. The predicate itself is the one
# `teardown` already refuses on, extracted so that the boundary and the cleanup cannot drift into
# two answers about whether a tree is collected.
#
# Same MAIN_ROOT anchor and same RUN_ID scrub as its two siblings, for their reasons exactly: the
# branch and remote-tracking refs live in the main checkout's common dir, the close-out's last act
# deletes the worktree a reader anchored there would be standing in, and an ambient run id must not
# let the scheduler's environment key anything the gate resolves.
#
# Output is NOT suppressed. The gate's line naming which arm fired and what it saw IS the operator's
# evidence, and this script must not paraphrase a predicate it does not own.
inflight_rc() {
  ( cd "$MAIN_ROOT" && env -u RUN_ID bash "$GATE" inflight "$ISSUE" )
}

# #531 D-12. The close-out report, read by the gate and ECHOED here. The scheduler must be able to
# name WHICH obligation is outstanding, and the alternative — parsing the progress record — would
# make it a reader of the record's schema, which its header forbids. Best-effort by construction:
# this decorates a failure that has already been decided, so a read that cannot be completed
# degrades to a note rather than changing an exit code.
closeout_report() {
  ( cd "$MAIN_ROOT" && env -u RUN_ID bash "$GATE" progress "$ISSUE" --obligations 2>/dev/null ) \
    || echo "the gate could not report milestone 5's obligations — read $MAIN_ROOT/$STATE_DIR/$ISSUE-lean-progress.md by hand."
}

# #590. THE CLOSE-OUT ITSELF, and it is a gate call rather than a third spawn. Everything the
# spawned session did after the approve was a fixed sequence of commands, so the session was pure
# overhead — one reasoning-tier model session per run to type them.
#
# ANCHORED IN THE LANE WORKTREE, unlike its three read-only siblings above. They are anchored at
# MAIN_ROOT precisely because the close-out deletes the tree; this IS the close-out, and the gate
# refuses a milestone call from anywhere but the lane branch (rc=9). The teardown that removes the
# tree is the last thing it does, from inside it, exactly as the spawned session's last act was.
#
# BOTH IDENTITIES SCRUBBED, and that is what keeps this script's authors-nothing rule true while
# it gains a call that writes. `RUN_ID` so the run's own cached id keys the records rather than
# the scheduler's environment — the same reason its siblings scrub it. `CLAUDE_CODE_SESSION_ID`
# because the scheduler's session is not a recorded BUILD session and must not become one: the
# gate's `mark` no-ops when checklist step 7 already stamped the PR and REFUSES when a marker
# would have to be written, so a close-out can never put this session's identity on an artifact.
closeout_rc() {
  local wt
  wt="$(lane_worktree)" || return 3
  ( cd "$wt" && env -u RUN_ID -u CLAUDE_CODE_SESSION_ID bash "$GATE" close-out "$ISSUE" )
}

progress_token() { # progress_token [--satisfied <n>]
  local tok rc
  tok="$( cd "$MAIN_ROOT" && env -u RUN_ID bash "$GATE" progress "$ISSUE" "$@" 2>/dev/null )"
  rc=$?
  [ "$rc" -eq 0 ] && [ -n "$tok" ] || return 1
  printf '%s\n' "$tok"
}

# #527. THE INFRA-DEATH READ, and it is a SEPARATE token space from the one above rather than a
# widening of it. The continuation predicate counts milestones the build role SATISFIED or FAILED;
# an evaluation that was killed did neither, which is exactly why a session that spent five minutes
# sweeping is byte-identical to one that did nothing. Folding the two into one token would make
# every killed spawn read as advancement — the thing lean-gate.sh's row set was closed to prevent.
#
# Same MAIN_ROOT anchor and same RUN_ID scrub as its sibling, for the same two reasons; and the
# same FAIL-CLOSED posture, for a third. The gate answers `m3infra-v3:0` when there is no death, so
# an empty or erroring read is never a legitimate negative — treating it as one would put this
# script back to reading a killed session as an idle one, which is the bug being removed.
infra_token() {
  local tok rc
  tok="$( cd "$MAIN_ROOT" && env -u RUN_ID bash "$GATE" progress "$ISSUE" --infra 2>/dev/null )"
  rc=$?
  [ "$rc" -eq 0 ] && [ -n "$tok" ] || return 1
  printf '%s\n' "$tok"
}

if [ "$DRY_RUN" -eq 1 ]; then
  say "dry run: branch=$BRANCH · gate=$GATE · $MAX_ROUNDS round(s) of BUILD → REVIEW → verdict"
  spawn BUILD "$BUILD_MODEL" "/dev-pipeline:build-lean $ISSUE"
  spawn REVIEW "$REVIEW_MODEL" "/dev-pipeline:review-lean <pr>"
  terminal dry-run 0 "dry run: nothing was spawned."
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
    # #515, and FIRST in the loop body: a run whose premise has expired should cost nothing more,
    # not even the progress read below. This covers round-1 entry and every continuation, because
    # a continuation re-enters here — which is the spawn the motivating incident kept taking.
    staleness_rc; st_rc=$?
    case "$st_rc" in
      0) : ;;
      7) terminal staleness-expired 7 "HARD STOP: this run's premise expired while it was in flight — see the gate's line above for which arm fired and what it saw. Rebase this branch onto the updated base and re-launch, or abandon the ticket; a re-launch without rebasing re-fires this stop at the same point. Detection is all this does: nothing was rebased and nothing was reverted. The worktree and the claim are left in place." ;;
      # Fail closed (D-5). Same posture as the progress read below: a predicate that could not be
      # evaluated is not a predicate that passed, and spawning on one would be spawning blind.
      *) terminal staleness-unreadable 1 "the staleness check could not be completed (gate exit $st_rc) — refusing to spawn BUILD against a premise nothing verified." ;;
    esac

    tok_before="$(progress_token)" \
      || terminal progress-unreadable 1 "cannot read the run's progress record through '$GATE' — the continuation predicate is unavailable, so a stopped BUILD session could not be told from a finished one. Not spawning blind."

    # #527: read on BOTH sides, in the same shape as the token above, because the routing below is
    # on the DELTA and never on the level. The record is append-only, so one infrastructure death
    # leaves a level test true for the rest of the run — every later idle session would then read
    # as recoverable and spend the whole continuation budget on nothing, which is a fresh instance
    # of the bug this reads for.
    infra_before="$(infra_token)" \
      || terminal infra-unreadable 1 "cannot read the run's milestone-3 infrastructure residue through '$GATE' — a killed evaluation could not be told from an idle session, which is the one distinction this loop needs. Not spawning blind."

    spawn BUILD "$BUILD_MODEL" "/dev-pipeline:build-lean $ISSUE" \
      || terminal build-session-failed 1 "BUILD session failed in round $round."

    PR="$(resolve_pr)"
    # More than one open PR on this head is not a state to guess through: the review would run on
    # one and the close-out could verify the other. Named, not counted silently.
    if [ "$(printf '%s' "$PR" | grep -c '[0-9]')" -gt 1 ]; then
      terminal pr-ambiguous 1 "more than one open PR on '$BRANCH' ($(printf '%s' "$PR" | tr '\n' ' ')) — the lane cannot choose which one this run is about. Close or retarget the extras and re-launch."
    fi
    # #531 AC-5. THE BUILD EXIT CONTRACT, and it is gated on there BEING a PR, which is where the
    # harm lives: the round that follows hands `review-lean` a PR whose REMOTE head is missing
    # everything the build session just did. Measured three times in a single run of one ticket,
    # each costing a full review round with nothing in the log to distinguish it from a legitimate
    # one; the worst shape had BUILD correctly rebase onto a moved base AND find a real defect the
    # new base introduced, then exit 0 leaving both unpushed — one teardown from losing them.
    #
    # DELIBERATELY NOT ON THE NO-PR PATH, and that ordering is load-bearing rather than incidental.
    # A build session is expected to hold unpushed commits for most of its life — milestone 3 runs
    # long before checklist step 7 pushes — so asserting this before a PR exists would hard-stop
    # exactly the spawn #527 taught this loop to CONTINUE from: an infrastructure kill mid-sweep,
    # whose worktree legitimately carries an unpushed spec commit. The continuation predicate below
    # owns "did anything happen at all"; this owns "is what happened visible to a reviewer".
    #
    # An open PR also means the branch was pushed at least once, which is what makes the unreadable
    # arm below a genuine environment error rather than the ordinary state of a young lane.
    #
    # A TERMINAL, not a continuation. The remedy is one push from a tree that still exists, and a
    # fresh session re-deriving the work would be the expensive way to reach the same place.
    if [ -n "$PR" ]; then
      inflight_rc; if_rc=$?
      case "$if_rc" in
        0) break ;;
        8) terminal build-inflight 1 "HARD STOP: the BUILD session exited 0 and PR #$PR is open, but the lane worktree still holds work nothing else has a copy of — see the gate's line above for which arm fired. A review would read a remote head missing it. Push from the lane worktree and re-launch; the worktree and the claim are left in place." ;;
        # Fail closed, the same posture the two reads above take: a predicate that could not be
        # evaluated is not a predicate that passed, and the failure direction of guessing here is a
        # review round spent on code nobody will merge.
        *) terminal build-inflight-unreadable 1 "the in-flight check could not be completed (gate exit $if_rc) — whether the BUILD session left work behind is unknown, and reviewing on that guess is the defect this check exists to remove." ;;
      esac
    fi

    tok_after="$(progress_token)" \
      || terminal progress-unreadable 1 "cannot read the run's progress record through '$GATE' after the BUILD session."
    infra_after="$(infra_token)" \
      || terminal infra-unreadable 1 "cannot read the run's milestone-3 infrastructure residue through '$GATE' after the BUILD session."

    # AC-3: exited 0, no PR, and nothing was recorded. Unchanged from before #492 — not
    # reviewing nothing is still correct, and a session that did nothing will do nothing twice.
    #
    # #527 NARROWS "a session that did nothing", which was the false half of that sentence. It is
    # true of an IDLE session and false of a KILLED one, and until this read the code could not
    # tell them apart: a milestone-3 evaluation killed at the turn boundary satisfies no milestone
    # and fails none, so the token it leaves is byte-identical to an idle spawn's — measured at
    # four launches, zero PRs, both continuations unspent every time, against an implementation
    # that was complete and correct the whole time. The stop below is now conditioned on BOTH
    # predicates being unmoved; an infrastructure death falls through to the ordinary continuation
    # path, on the ordinary --max-continuations bound.
    if [ "$tok_after" = "$tok_before" ]; then
      if [ "$infra_after" = "$infra_before" ]; then
        terminal build-idle 1 "no open PR on '$BRANCH' after the BUILD session — nothing to review."
      fi
      say "the BUILD session's milestone-3 evaluation was killed by infrastructure — it recorded no milestone because none of them concluded, not because the session was idle. Re-spawning rather than stopping."
    fi

    continuations=$((continuations + 1))
    if [ "$continuations" -gt "$MAX_CONTINUATIONS" ]; then
      terminal build-continuations-spent 1 "HARD STOP: the BUILD session advanced but left no PR, and this build phase has spent its --max-continuations budget ($MAX_CONTINUATIONS). The worktree and the claim are left in place for a manual rescue."
    fi
    say "BUILD advanced but left no open PR — continuing in a fresh session ($continuations of $MAX_CONTINUATIONS)."
  done
  say "PR #$PR is open on $BRANCH."

  # The review phase, and its own bounded retry. A class-5 read means the review produced nothing
  # usable against this head — dark, uncommitted, or stale — which is a failure of the REVIEW half,
  # so the recovery is another review, not another round of fixes. One re-spawn, on a counter
  # separate from --max-rounds and --max-continuations, because a second dark review is a broken
  # review lane rather than bad luck and a third would only cost more to learn the same thing.
  # #531 D-7. THE VERDICT READ MOVES AHEAD OF THE SPAWN. The loop entered the build phase
  # unconditionally and the review spawn PRECEDED the only verdict read, so a re-entry ran BUILD and
  # then fell into a review against a head that already carried an approve — and a fresh round could
  # author a COMPETING verdict record for the same head. On the run that surfaced this it was killed
  # by hand; nothing in the lane would have.
  #
  # rc=0 HERE IS NOT A STOP. Stopping would strand approved, reviewed work, which the two paragraphs
  # above already decline to do for the REVIEW spawn. It skips the review it does not
  # need and falls into the close-out, so the competing-record path closes without costing the run
  # anything. A prior run's approve is still caught loudly downstream by the close-out's NEW-row
  # requirement.
  #
  # EVERY OTHER CLASS ROUTES EXACTLY AS BEFORE — including 5, whose bounded retry is below, and
  # 4 and 6, which now hard-stop one spawn EARLIER. That is strictly better: neither is something a
  # review could clear, so spawning one to produce a record the gate will refuse is pure cost.
  #
  # #597 D-1/F1. THE CANNOT-ANSWER CODES MOVE AHEAD OF THE SPAWN TOO. #531's header above claims 4
  # and 6 "now hard-stop one spawn EARLIER"; 3 was listed with them and was NOT, because the `else`
  # arm below spawns on EVERY non-zero rc and the `case` that routes 3 reads only afterwards. On
  # #583 that cost a whole review session: `verdict_rc` is anchored in the LANE WORKTREE, the
  # close-out had already run teardown, so it returned 3 without ever reaching the gate — and a
  # REVIEW was spawned against a head that had not moved in five and a half hours. Its two siblings
  # `staleness_rc` and `inflight_rc` are anchored at MAIN_ROOT for exactly this reason; this one was
  # never converted, and D-1 declines to ref-parameterize the gate (that surface belongs to #141),
  # so the fix is to stop spawning a review that cannot possibly clear the condition.
  #
  # rc=3 IS NOT AN ERROR BY ITSELF. The worktree is ABSENT because teardown removed it, which is
  # what a finished lane looks like. `progress --satisfied 5` separates the two: a satisfied
  # milestone 5 means the lane finished, and the run ends COMPLETE. Unsatisfied keeps the
  # pre-existing `worktree-missing` stop. Since #590 this is the token's ONLY remaining reader on
  # the close-out side — the before/after comparison that used to bracket the spawn went with it.
  verdict_rc; rc=$?
  if [ "$rc" -eq 0 ]; then
    say "terminal-vocabulary: review-skipped-approved — the current head already carries an approve verdict, so no REVIEW is spawned against it and no competing record can be authored for it. Falling into the close-out."
  elif [ "$rc" -eq 3 ]; then
    # STILL TWO TOKENS COMPARED FOR EQUALITY, never parsed — the invariant progress_token's header
    # states, and the reason this does not read `progress-v1:0`. Milestone 0 does not exist, so its
    # satisfied-count is the ZERO token by construction; milestone 5 equal to it means no
    # `| milestone-5 | satisfied` row was ever written. A format read here would couple this
    # scheduler to the gate's token grammar with nothing enforcing the pair.
    m5_tok="$(progress_token --satisfied 5)" \
      || terminal verdict-progress-unreadable 1 "no lane worktree for '$BRANCH', and the run's progress record could not be read through '$GATE' either — whether the lane finished is unknown, and neither guess is worth a REVIEW spawn."
    m5_zero="$(progress_token --satisfied 0)" \
      || terminal verdict-progress-unreadable 1 "no lane worktree for '$BRANCH', and the zero-baseline progress read failed through '$GATE' — the comparison that decides whether the lane finished cannot be made, so no REVIEW is spawned on a guess."
    if [ "$m5_tok" = "$m5_zero" ]; then
      terminal worktree-missing 1 "cannot locate a worktree for '$BRANCH', and the run's record carries no satisfied milestone 5 — the BUILD session did not leave one. No REVIEW spawned: a review cannot produce a worktree."
    fi
    terminal lane-closed-out 0 "done — #$ISSUE closed out on PR #$PR. The lane worktree is gone because teardown removed it and milestone 5 is satisfied, which is a FINISHED run, not a missing one. No REVIEW spawned against an unmoved head (#597 AC-2)."
  elif [ "$rc" -eq 2 ]; then
    terminal verdict-gate-unreadable 2 "the verdict gate could not run against '$BRANCH' (exit 2) — an environment refusal, not a verdict. No REVIEW spawned: a review round cannot clear a gate that never evaluated one."
  else
    review_retries=0
    while :; do
      spawn REVIEW "$REVIEW_MODEL" "/dev-pipeline:review-lean $PR" \
        || terminal review-session-failed 1 "REVIEW session failed in round $round."

      verdict_rc; rc=$?
      [ "$rc" -eq 5 ] || break

      review_retries=$((review_retries + 1))
      if [ "$review_retries" -gt "$MAX_REVIEW_RETRIES" ]; then
        terminal review-dark 5 "HARD STOP: the REVIEW session left no verdict record usable against the current head, twice. No round was spent and no BUILD session was spawned — BUILD has nothing to fix when the review half is what failed. Run '/dev-pipeline:review-lean $PR' by hand and read its output; the worktree and the claim are left in place."
      fi
      say "no verdict record usable against the current head — re-spawning REVIEW ($review_retries of $MAX_REVIEW_RETRIES). No round spent, no BUILD spawn."
    done
  fi

  case "$rc" in
    0)
      say "verdict: approve. Closing out."
      # #590 D-3/D-5. NO SPAWN, NO CONTINUATION BUDGET, NO TOKEN COMPARISON. All three existed to
      # work around one property of a model session: `claude -p` exits 0 whenever the model ends
      # its turn, so the close-out's exit status could not be trusted and its work had to be read
      # back out of the record. A gate command cannot end its turn early — its exit code IS the
      # verdict, which is already the lane's evidence rule at every other call site.
      #
      # ONE RETRY, then a stop. The bound is MAX_REVIEW_RETRIES' reasoning at a cheaper site: the
      # close-out is a fixed sequence of writes, and a call that cannot complete them twice will
      # not complete them on a third. Not a flag — a knob here turns a broken lane into an
      # expensive one.
      #
      # THE RETIRED WART. The old check required a NEW `| milestone-5 | satisfied` row, which a
      # legitimate second lane run over an already-closed issue could never produce (the append is
      # idempotent and the record is keyed by issue), so its correct close-out was reported as a
      # failure. Reading the exit code removes that case without adding one.
      closeout_rc; rc=$?
      if [ "$rc" -ne 0 ]; then
        say "close-out did not complete (gate exit $rc) — retrying once."
        closeout_rc; rc=$?
      fi
      if [ "$rc" -ne 0 ]; then
        say "milestone 5's own obligations, as recorded:"
        closeout_report | while IFS= read -r line; do say "  $line"; done
        terminal closeout-incomplete 1 "HARD STOP: the close-out did not complete (gate exit $rc), twice. The obligations above name what is outstanding. The ticket is still claimed and PR #$PR is still open; finish it by hand with 'bash $GATE close-out $ISSUE' from the lane worktree."
      fi

      # AC-5 again, at the second boundary #531 D-3 names. The ordinary shape here is that there
      # is nothing left to read — the close-out's last act is teardown — so this fires only when
      # teardown KEPT the worktree over uncollected work, which is exactly the state that must not
      # be reported as a finished run.
      inflight_rc; co_if_rc=$?
      case "$co_if_rc" in
        0) : ;;
        8) terminal closeout-inflight 1 "HARD STOP: the close-out completed but the lane worktree still holds work nothing else has a copy of — see the gate's line above. The ticket is still claimed and PR #$PR is still open." ;;
        *) terminal closeout-inflight-unreadable 1 "the in-flight check could not be completed after the close-out (gate exit $co_if_rc) — whether the lane worktree still holds work is unknown, and reporting a finished run on that guess is what this check exists to prevent." ;;
      esac
      terminal approved 0 "done — #$ISSUE approved on PR #$PR."
      ;;
    1) say "verdict: needs-work." ;;
    6) terminal verdict-self-authored 6 "HARD STOP: the verdict record is authored by the build run or the build session (P10) — generation may not author its own evaluation, and that is not something a retry can clear. No round spent, nothing re-spawned. The merge boundary refuses this record too; produce one from a separate review session." ;;
    4) terminal verdict-budget-spent 4 "HARD STOP: the verdict gate exhausted its fix budget. No rescue attempt — re-entry is from the top." ;;
    # 2 and 3 are deliberately absent here: #597 D-1 routes both AHEAD of the REVIEW spawn above,
    # where they hard-stop, so an arm for either could only be dead code claiming to be a route.
    *) terminal verdict-gate-failed 1 "the verdict gate could not run (exit $rc)." ;;
  esac

  round=$((round + 1))
  if [ "$round" -gt "$MAX_ROUNDS" ]; then
    terminal rounds-spent 4 "HARD STOP: $MAX_ROUNDS rounds spent without an approve. No rescue attempt — re-entry is from the top."
  fi
done

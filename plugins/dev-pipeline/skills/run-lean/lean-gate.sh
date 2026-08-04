#!/usr/bin/env bash
# lean-gate.sh — the five milestone gates of /dev-pipeline:run-lean, plus the entry
# precondition and the claim helper.
#
# WHY THIS EXISTS: run-lean is OUTCOME-gated, not process-prescribed. The harness asserts
# ARTIFACTS at five ordered milestones and is deliberately silent about the path between
# them — the session may draw on any skill surface it likes, or none. Everything this
# script checks is a file, an exit code, or a tracker record; nothing is a claim about how
# the work was done.
#
# TRUST POSTURE (D-47) — read this before adding a check here. Lean-in-run is NOT
# lean-in-enforcement. Every record this script writes is written by the agent being
# checked, so it is at best tamper-EVIDENT. The binding evidence contract lives at the
# model-free merge boundary (scripts/check-lean-chain.sh) and in the operator-side
# lean-reconcile.sh, where it costs zero run tokens. The fix-budget counter here is
# cost-control, NOT integrity: gaming it means spending more, which the cost block makes
# visible. Do not add an integrity check here and call it enforcement.
#
# AUTHORSHIP (P10) — the one property here that is a check rather than a record. Generation
# must not author evaluation's record. The BUILD role (`entry`, `claim`, `1..5`, `all`) can
# only READ the verdict record; the REVIEW role (`verdict`) can only WRITE it, and refuses to
# run inside the build session at all. Identity is role-keyed on both sides, so a review
# session that provisioned no identity is refused rather than silently inheriting the build's
# — see the RUN_ID persistence section.
#
# HONEST ALTITUDE, same as the siblings: this is tamper-EVIDENCE, not proof. RUN_ID is
# agent-CHOSEN, whereas the session id is merely agent-OVERRIDABLE — $CLAUDE_CODE_SESSION_ID
# is an ordinary environment variable, so a determined agent can spoof it here. That is worth
# something (the honest value is assigned by the harness, and a spoof must then be sustained
# across the audit ledger lean-reconcile.sh reads) but it is not a guarantee. Do not describe
# this check as stronger than lean-reconcile.sh and check-lean-chain.sh describe theirs.
#
# FRESHNESS (milestone 4). Four of the five milestones re-derive their answer from the current
# tree on every sweep, which is what makes `satisfied` a record rather than a cache. Milestone
# 4 cannot: its evaluation is reading a file. So it additionally binds that file to a tree —
# the record must be COMMITTED, and nothing but the record itself may have changed since. A
# verdict for an earlier head is not a verdict for this one.
#
# TWO ARMS, and neither subsumes the other. The check just described is INFERRED freshness: git
# says which commit carries the record, and the record's prose cannot argue with it. The
# DECLARED arm reads what the reviewer stated. Inference binds the record to where it was
# COMMITTED; the declaration binds it to what was REVIEWED, and the two come apart in the
# ordinary case where code lands between the review and the record's commit — the reviewer then
# commits an honest record on top of a head it never read, and inference alone calls that fresh.
# Running both is what makes the pair non-vacuous in either direction.
#
# The declaration is keyed on `reviewed_patch_id` — the patch identity of the branch's own diff
# — and NOT on the `reviewed_head` SHA beside it. A rebase rewrites commit SHAs and changes no
# reviewed content, so SHA keying refused a mechanical operation, and refused it unavoidably: in
# a fresh checkout the pre-rebase object does not exist at all. Patch identity is invariant
# there, and still moves on any real change — including a conflict resolution, which SHA keying
# could not distinguish from a clean replay. It does NOT cover a base change that reds the suite
# with no textual conflict; the verdict correctly still stands there, and the merged result is
# CI's business. `reviewed_head` remains a diagnostic pointer, and the path records written
# before the patch-id key still gate on.
#
# Usage:
#   lean-gate.sh entry  <issue>          entry precondition: the session's audit ledger is live.
#                                        The queue-label reject is the SESSION's step (SKILL.md
#                                        step 1) — it needs a tracker read, so it is not gated
#                                        here. Under tracker.type: jira there is no queue at all.
#   lean-gate.sh claim  <issue>          the two bot-wrapper claim writes (AC-15/D-49).
#                                        Under tracker.type: jira it makes NO tracker write and
#                                        needs no GH_BOT — it records the run id and returns.
#   lean-gate.sh <1..5> <issue>          evaluate one milestone
#   lean-gate.sh all    <issue>          evaluate 1..5 in order, stop at the first failure
#   lean-gate.sh verdict <issue> --pr <n> --verdict <approve|needs-work> [--rounds <n>]
#                                        [--summary-file <path>]
#                                        REVIEW role: write the committed verdict record.
#
# Exit: 0 = satisfied / ok
#       1 = milestone failed, or a `verdict` authorship refusal (fix and retry — budget remains)
#       2 = usage or environment error
#       4 = fix budget exhausted for that milestone (hard stop; D-19)
#
# Seams (zero-network selftest; the check-pipeline-chain.sh precedent):
#   ${GH:-gh}                the CLI used for reads
#   LEAN_PROGRESS_FILE       override the resolved progress-file path
#   SECOND_SHIFT_CONFIG      override the resolved config path
#   --pr-file <path>         milestone 5: read the PR record from a JSON fixture
#   --comments-file <path>   milestone 5: read the issue comments from a JSON fixture
#   LEAN_RUN_MODEL           #347: the `model:` key stamped into the progress/verdict record
#                            at creation time (retro-corpus.sh's corpus-aggregation key).
#                            Read once, not cached; absent reads "unknown", never an error.
#
# bash 3.2 compatible (macOS ships it, and CI has a bash-3.2 lane).
set -uo pipefail

GH_CLI="${GH:-gh}"
PR_FILE=""
COMMENTS_FILE=""
VERDICT_VALUE=""
VERDICT_PR=""
VERDICT_ROUNDS=""
SUMMARY_FILE=""

# The fix budget: 3 attempts per milestone, the 4th red hard-stops (D-19). Counted from
# the progress file's `attempt` lines per D-41 — only FAILED evaluations append one.
FIX_BUDGET=3

say()  { echo "[lean-gate] $*"; }
warn() { echo "[lean-gate] $*" >&2; }
envfail() { echo "[lean-gate] $*" >&2; exit 2; }

# ---------------------------------------------------------------- argument parsing
SUB=""
ISSUE=""
POSITIONAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pr-file)       PR_FILE="${2:-}"; shift 2 ;;
    --comments-file) COMMENTS_FILE="${2:-}"; shift 2 ;;
    --pr)            VERDICT_PR="${2:-}"; shift 2 ;;
    --verdict)       VERDICT_VALUE="${2:-}"; shift 2 ;;
    --rounds)        VERDICT_ROUNDS="${2:-}"; shift 2 ;;
    --summary-file)  SUMMARY_FILE="${2:-}"; shift 2 ;;
    -h|--help)       sed -n '2,86p' "$0"; exit 0 ;;
    -*)              envfail "unknown option: $1" ;;
    *)
      if [ "$POSITIONAL" -eq 0 ]; then SUB="$1"; POSITIONAL=1
      elif [ "$POSITIONAL" -eq 1 ]; then ISSUE="$1"; POSITIONAL=2
      else envfail "unexpected argument: $1"
      fi
      shift ;;
  esac
done

[ -n "$SUB" ]   || envfail "usage: lean-gate.sh <entry|claim|1..5|all|verdict> <issue>"
[ -n "$ISSUE" ] || envfail "usage: lean-gate.sh <entry|claim|1..5|all|verdict> <issue>"

case "$SUB" in
  entry|claim|1|2|3|4|5|all|verdict) : ;;
  *) envfail "unknown subcommand '$SUB' (expected entry|claim|1..5|all|verdict)" ;;
esac

# ---------------------------------------------------------------- roots + config
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || envfail "not in a git repo — cannot resolve the worktree root."

# The MAIN checkout, not the worktree: the progress file must survive worktree teardown,
# which is what makes resume work. Same --git-common-dir anchor bot-commit.sh uses.
_common="$(git rev-parse --git-common-dir 2>/dev/null)" \
  || envfail "cannot resolve --git-common-dir."
case "$_common" in
  /*) : ;;
  *)  _common="$REPO_ROOT/$_common" ;;
esac
MAIN_ROOT="$(cd "$_common/.." 2>/dev/null && pwd)" \
  || envfail "cannot resolve the main checkout from '$_common'."

CONFIG="${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}"

cfg() { # cfg <jq-filter> <default>
  local v
  if [ -f "$CONFIG" ]; then
    v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
    if [ -n "$v" ] && [ "$v" != "null" ]; then echo "$v"; return 0; fi
  fi
  echo "$2"
}

PLANS_DIR="$(cfg '.paths.plansDir' 'docs/plans')"
STATE_DIR="$(cfg '.paths.pipelineStateDir' '.claude/pipeline-state')"
BRANCH_PREFIX="$(cfg '.tracker.branchPrefix' 'claude/acme-')"
QUEUE_LABEL="$(cfg '.tracker.labels.queue' 'ready-for-dev')"
CLAIMED_LABEL="$(cfg '.tracker.labels.claimed' 'in-progress')"
HOST_Q='(.topology.repos | to_entries[] | select(.value.path==".") | .key)'
REPO_SLUG="$(cfg "$HOST_Q" 'acme')"
BASE_BRANCH="$(cfg "$HOST_Q as \$h | .topology.repos[\$h].baseBranch" 'main')"

# ---------------------------------------------------------------- the tracker adapter
# ONE resolution, THREE branch sites: the entry note, cmd_claim, and cmd_5. Milestones 1-4
# are adapter-INSENSITIVE (a committed file, two repo scripts, a config command table, a
# committed verdict record) and must stay that way — an adapter branch inside them would be
# a second tracker authority.
#
# Absent ⇒ github is a FAIL-SAFE, not a back-compat allowance: config-lint.sh already requires
# `tracker.type` to be github|jira (an absent key reads as "" and errors), so no lint-clean
# config omits it. The default is for the config that never reached the lint — hand-edited, or
# read before it runs — and github is the safe side of that: the arm whose exit gate demands a
# closing comment fails loudly, where the jira arm would quietly accept a PR body.
#
# An UNRECOGNIZED value is a loud environment error rather than a fall-through — a typo'd
# `tracker.type` silently running the write-happy arm on a read-only tracker is exactly the
# failure this whole change removes. The enum matches config-lint.sh's.
TRACKER_TYPE="$(cfg '.tracker.type' 'github')"
case "$TRACKER_TYPE" in
  github|jira) : ;;
  *) envfail "unknown tracker.type '$TRACKER_TYPE' — expected 'github' or 'jira'." ;;
esac

# ---------------------------------------------------------------- the pinned name table
# ONE derivation, three consumers: this script, scripts/check-lean-chain.sh (running in CI
# with no access to any local convention), and lean-reconcile.sh. A name invented at any
# one of those sites instead of derived here is a drift the CI gate surfaces as a red merge
# boundary on every lean PR — see the plan's pinned-name-table section.

# Branch prefix: replace the FIRST path segment with `lean`. The REQUIRED property is
# MUTUAL non-prefix-matching against the pipeline prefix (AC-9): check-pipeline-chain.sh
# classifies with `head_ref == PREFIX*`, so `lean/` derived from `claude/second-shift-`
# would satisfy a one-directional reading while making EVERY pipeline PR applicable to the
# lean gate. Both directions are asserted below and in the selftest.
lean_branch_prefix() {
  local pipeline_prefix="$1" tail derived
  case "$pipeline_prefix" in
    */*) tail="${pipeline_prefix#*/}" ;;
    *)   tail="$pipeline_prefix" ;;
  esac
  derived="lean/$tail"
  # Pathological input (a configured prefix already under lean/) collapses the two onto
  # each other. Fail loudly rather than return a colliding prefix — a silent collision
  # double-classifies every PR in both gates.
  case "$pipeline_prefix" in
    "$derived"*) echo "[lean-gate] configured tracker.branchPrefix '$pipeline_prefix' collides with the derived lean prefix '$derived' — they must be mutually non-prefix-matching." >&2; return 1 ;;
  esac
  case "$derived" in
    "$pipeline_prefix"*) echo "[lean-gate] derived lean prefix '$derived' prefix-matches the pipeline prefix '$pipeline_prefix' — refusing." >&2; return 1 ;;
  esac
  echo "$derived"
}

LEAN_BRANCH_PREFIX="$(lean_branch_prefix "$BRANCH_PREFIX")" || exit 2
SPEC_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean.md"
VERDICT_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean-verdict.md"
PROGRESS_FILE="${LEAN_PROGRESS_FILE:-$MAIN_ROOT/$STATE_DIR/$ISSUE-lean-progress.md}"

# ---------------------------------------------------------------- RUN_ID persistence
# SKILL.md step 2 says "export RUN_ID first ... it keys every record" — true only if the
# operator's shell survives from `claim` through every later `bash G <n> <issue>` call.
# It does not: this tool is routinely invoked as ONE-SHOT subprocesses (a fresh shell per
# call, only cwd inherited), so an export in the claim call is gone by the next one, and
# every record after it silently stamps `run_id: unset` — exactly the mismatch
# lean-reconcile.sh exists to catch (observed live on #306: claim/verdict carried the real
# id, the progress-file header did not). Fix at the ROOT rather than leaning harder on the
# operator to keep re-exporting it: cache the id to a file the FIRST time it is seen (any
# call made with $RUN_ID set — claim is typically first), and every call without $RUN_ID
# in its own environment reads the cache instead of falling back to "unset".
#
# ROLE-KEYED (P10). There are two caches, not one, and neither role may read the other's.
# Before this split, ANY invocation without an exported RUN_ID resolved the issue's single
# cached id — so a review session working the same issue would stamp the BUILD run's identity
# into the verdict record and the authorship check would compare a value against itself. The
# review role therefore resolves `<issue>-review-run-id` and, finding nothing, resolves
# NOTHING: `verdict` refuses rather than falling through to the build cache. Silent inheritance
# is the exact failure this separation exists to make impossible.
RUN_ID_CACHE="$MAIN_ROOT/$STATE_DIR/$ISSUE-run-id"
REVIEW_RUN_ID_CACHE="$MAIN_ROOT/$STATE_DIR/$ISSUE-review-run-id"
resolve_cached_id() { # resolve_cached_id <cache-path> <persist:0|1>
  if [ -n "${RUN_ID:-}" ]; then
    # SEED-ONCE, as the comment above has always said ("the FIRST time it is seen"). The
    # pre-existing form re-wrote on every call, which is a different thing and a harmful one
    # now that a second role exists: review-lean SKILL.md step 1 REQUIRES the review session to
    # export its own RUN_ID, and nothing forbids it from running `bash G 4 <issue>` to check
    # the record it just wrote. Under overwrite semantics that call replaced the BUILD identity
    # with the review one, and milestone 4 — which compares the verdict against this very file
    # — then refused a valid, review-authored record permanently. Seeding once cannot clobber
    # an established build identity.
    if [ "$2" = "1" ] && [ ! -s "$1" ]; then
      mkdir -p "$(dirname "$1")" 2>/dev/null && printf '%s' "$RUN_ID" > "$1"
    fi
    printf '%s' "$RUN_ID"
  elif [ -s "$1" ]; then
    cat "$1"
  else
    printf 'unset'
  fi
}
case "$SUB" in
  verdict)
    # Resolve WITHOUT persisting. The review identity is cached only once the record is actually
    # written (see cmd_verdict), so a REFUSED call cannot seed the cache — otherwise one rejected
    # attempt would make the next call's "no review identity provisioned" refusal vanish, which is
    # the same silent-inheritance failure in a slower form.
    RESOLVED_RUN_ID="$(resolve_cached_id "$REVIEW_RUN_ID_CACHE" 0)" ;;
  entry|claim)
    # ONLY the two build-role subcommands may ESTABLISH the build identity. Seed-once above is
    # necessary but not sufficient: with no cache on disk yet — a run that never exported
    # RUN_ID, a state dir cleaned after a retro — a REVIEW session running `bash G 4 <issue>`
    # to check the record it just wrote would CREATE the cache holding its own id, and
    # milestone 4 (which compares the record against that very file) would then refuse a valid,
    # review-authored record permanently, burning a fix attempt on every retry. An EVALUATION
    # must be able to read an identity, never to establish one.
    RESOLVED_RUN_ID="$(resolve_cached_id "$RUN_ID_CACHE" 1)" ;;
  *)
    RESOLVED_RUN_ID="$(resolve_cached_id "$RUN_ID_CACHE" 0)" ;;
esac

# First `<key>: <token>` in a file, HTML-comment or bare form. Deliberately the SAME extraction
# shape lean-reconcile.sh uses on the same records — two readers of one schema that disagreed
# about what a key looks like would be a silent divergence, not a loud one.
record_key() { # record_key <key> <file>
  [ -f "$2" ] || return 0
  grep -oE "$1:[[:space:]]*[A-Za-z0-9._-]+" "$2" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"
}

# The verdict VALUE, read FIRST-MATCH like every other key in the record. Never a substring
# count over the whole file: `--summary-file` puts the reviewer's own prose below these keys,
# and review prose discusses verdicts. That is not hypothetical — the committed record for
# #237 reads `verdict=approve` on line 3 and again on line 9 inside a sentence about round 1.
# Had line 3 said `needs-work`, a count-anywhere reader would have certified it. Line-anchoring
# (`^verdict=approve$`) was the other candidate and was rejected: the earliest records write
# the key as a bullet or a table cell (`- verdict=approve`, `milestone-4 | verdict=approve |`),
# so an anchor would silently reclassify already-merged evidence as unreadable.
record_verdict() { # record_verdict <file>
  [ -f "$1" ] || return 0
  grep -oE 'verdict=[A-Za-z-]+' "$1" 2>/dev/null | head -n1 | sed -E 's/^verdict=//'
}

# The PATCH IDENTITY of the branch's own diff — what `reviewed_patch_id` records and what the
# freshness readers recompute. `git patch-id --stable` hashes patch CONTENT, so it is invariant
# under a rebase (which rewrites commit SHAs and changes not one reviewed line) and under the
# blob-hash and hunk-offset churn a rebase brings with it, while still moving the moment a
# commit — or a conflict resolution — alters a line. That is why it replaced a SHA here: SHA
# identity cannot tell a clean replay from a resolution, so it fired on both and charged a
# review round for a mechanical operation.
#
# The verdict record is EXCLUDED, and the exclusion is load-bearing on BOTH sides rather than
# tidy: at write time HEAD does not yet carry the record, at read time it does. Without it the
# write-side and read-side ids never agree, and the arm reds on every correct record.
#
# The base is the CONFIGURED baseBranch. The merge-boundary reader has only the PR's declared
# base (the runtime config is gitignored and never reaches a CI checkout), so the two agree
# exactly when the PR targets the configured base — which is this lane's contract, since a lean
# worktree is cut from that base. A PR retargeted elsewhere reds at the boundary: fail-closed,
# and named there.
#
# Prints NOTHING when the id is unresolvable, and every caller must treat that as a refusal
# rather than a value. `git patch-id` prints nothing for an empty diff, so two failed
# computations compare EQUAL — an unguarded reader would print its ✓ having hashed nothing.
branch_patch_id() { # branch_patch_id <head-ish>
  local base id
  base="$(git -C "$REPO_ROOT" merge-base "origin/$BASE_BRANCH" "$1" 2>/dev/null)" || return 0
  [ -n "$base" ] || return 0
  id="$(git -C "$REPO_ROOT" diff "$base" "$1" -- . ":(exclude)$VERDICT_REL" 2>/dev/null \
    | git -C "$REPO_ROOT" patch-id --stable 2>/dev/null | cut -d' ' -f1)"
  printf '%s' "$id"
}

# ---------------------------------------------------------------- progress-file primitives
# Append-only markdown. Line shapes are PINNED — check-lean-chain.sh does not read this
# file (it is gitignored and never reaches CI), but lean-reconcile.sh does, and the
# fix-budget counter is derived from it.
#
#   <iso> | milestone-<n> | attempt | <reason>
#   <iso> | milestone-<n> | satisfied
#   milestone-4 | verdict=<approve|needs-work> | round=<n>
#
# Reconciliation keys (AC-14) ride in the header so a run predating #292's general
# verifier stays reconcilable after it lands.
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

ensure_progress_file() {
  local dir
  dir="$(dirname "$PROGRESS_FILE")"
  [ -d "$dir" ] || mkdir -p "$dir" || envfail "cannot create progress dir '$dir'."
  if [ ! -f "$PROGRESS_FILE" ]; then
    {
      echo "# lean run — issue $ISSUE"
      echo ""
      echo "run_id: $RESOLVED_RUN_ID"
      echo "session_id: ${CLAUDE_CODE_SESSION_ID:-unset}"
      echo "issue: $ISSUE"
      echo "branch_prefix: $LEAN_BRANCH_PREFIX"
      echo "spec: $SPEC_REL"
      echo "verdict_record: $VERDICT_REL"
      # #347: a corpus-aggregation key, not a new artifact — read once, here, at record
      # creation. No env var carries the session's own model identity today, so this is
      # opt-in: absent, retro-corpus.sh reads it as "unknown", a label, not an error.
      echo "model: ${LEAN_RUN_MODEL:-unknown}"
      echo ""
    } > "$PROGRESS_FILE"
  fi
}

append_line() { ensure_progress_file; echo "$1" >> "$PROGRESS_FILE"; }

# grep -c, never grep -q: -q exits at the first match, the producer takes SIGPIPE, and
# `set -o pipefail` turns that into a pipeline failure — the documented class that made a
# sibling gate report "absent" precisely when the token was found EARLY in a LONG file.
#
# And never `grep -c … || echo 0`: on zero matches grep PRINTS "0" *and* exits 1, so the
# fallback appends a second "0" and every caller then trips "integer expression expected".
# Capture first, default on the assignment.
count_matches() { # count_matches <pattern> <file> [extra grep args...]
  local pat="$1" file="$2" n
  shift 2
  [ -f "$file" ] || { echo 0; return 0; }
  n="$(grep -c "$@" -- "$pat" "$file" 2>/dev/null)" || n=0
  [ -n "$n" ] || n=0
  echo "$n"
}

# D-41: ONLY a failed evaluation appends an `attempt` line.
append_attempt() { append_line "$(now_iso) | milestone-$1 | attempt | $2"; }

# D-41: a passing evaluation appends AT MOST ONE `satisfied` line per milestone, so
# diagnostic re-runs and `all` sweeps never inflate anything. Idempotent by construction.
append_satisfied() {
  ensure_progress_file
  if [ "$(count_matches "| milestone-$1 | satisfied" "$PROGRESS_FILE" -F)" -eq 0 ]; then
    append_line "$(now_iso) | milestone-$1 | satisfied"
  fi
}

attempt_count() { count_matches "| milestone-$1 | attempt |" "$PROGRESS_FILE" -F; }

# A failed milestone: record the attempt, then decide retry-vs-hard-stop.
fail_milestone() {
  local n="$1" reason="$2" count
  append_attempt "$n" "$reason"
  count="$(attempt_count "$n")"
  warn "✗ milestone-$n: $reason (attempt $count/$FIX_BUDGET)"
  if [ "$count" -gt "$FIX_BUDGET" ]; then
    append_line "$(now_iso) | milestone-$n | budget-exhausted | $count attempts"
    warn "milestone-$n has exhausted its $FIX_BUDGET-attempt fix budget — hard stop."
    return 4
  fi
  return 1
}

pass_milestone() { append_satisfied "$1"; say "✓ milestone-$1${2:+: $2}"; return 0; }

# ---------------------------------------------------------------- entry precondition
# AC-14. The predicate is a NON-EMPTY ledger file for THIS session, anchored at the main
# checkout. Directory existence is explicitly NOT the test — an empty or absent per-session
# file means the hook never fired, and a run whose tool calls left no ledger cannot be
# reconciled by lean-reconcile.sh (or by #292 later). Fail closed.
cmd_entry() {
  local sid ledger
  sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -z "$sid" ]; then
    warn "✗ entry: CLAUDE_CODE_SESSION_ID is unset — the session's audit ledger cannot be located. Refusing to start."
    return 1
  fi
  ledger="$MAIN_ROOT/.claude/audit/$sid.jsonl"
  if [ ! -s "$ledger" ]; then
    warn "✗ entry: audit ledger '$ledger' is missing or empty — the hook ledger is not live. Refusing to start."
    warn "  Every lean record carries reconciliation keys; without a ledger the run is unverifiable at the merge boundary."
    return 1
  fi
  say "✓ entry: audit ledger live ($(wc -l < "$ledger" | tr -d ' ') lines)."
  # SKILL.md step 1 pairs this gate with a SESSION-side queue-label confirm. That confirm
  # has no jira meaning — jira pickup is "the operator supplies the key; no queue, no claim,
  # no label" — so the documented reject-and-stop has no defined outcome there. Say so here
  # rather than leaving the session to infer it: the note is the only place the two halves
  # of step 1 meet.
  if [ "$TRACKER_TYPE" = "jira" ]; then
    say "  tracker delta (jira): no queue label to confirm — the operator supplies the ticket key (tracker.writes: false). Step 1's label reject does not apply."
  fi
  return 0
}

# ---------------------------------------------------------------- claim (AC-15 / D-49)
# TWO bot-wrapper writes. Both must be the bot: check-lean-chain.sh filters the comment
# trail on `.user.type == "Bot"`, so an operator-posted claim comment is INVISIBLE to it
# and the merge-boundary gate would fail a legitimately-claimed PR.
#
# Under jira (`tracker.writes: false`) there is NO claim: no queue to race for, no label to
# swap, and no comment to post. What survives is the RECORD — the progress-file header
# carries the run id and session id, which is lean-reconcile.sh's anchor and the only thing
# a later call can resolve `RUN_ID` from. So this path still runs, still writes that header,
# and never touches `$GH_BOT` (documented github-only, and a hard `:?` failure below).
cmd_claim() {
  local helper body url

  if [ "$TRACKER_TYPE" = "jira" ]; then
    ensure_progress_file
    append_line "$(now_iso) | claim | tracker=jira | no tracker write (read-only tracker)"
    say "✓ claim: jira adapter — no tracker write; run_id '$RESOLVED_RUN_ID' recorded in $PROGRESS_FILE"
    return 0
  fi

  helper="$(dirname "$(cd "$(dirname "$0")" && pwd)")/run/tools/claim-issue.sh"
  [ -f "$helper" ] || envfail "claim-issue.sh not found at '$helper'."

  # (i) the label swap — reuses the pipeline's add-before-remove + confirm-before-DELETE
  # discipline rather than reimplementing it.
  bash "$helper" "$ISSUE" --queue "$QUEUE_LABEL" --claimed "$CLAIMED_LABEL" \
    || { warn "✗ claim: label swap failed — '$QUEUE_LABEL' left intact."; return 1; }

  # (ii) the marker comment. `lean-claimed`, NEVER `stage: claimed` — a lean-distinct
  # marker so this comment can never pollute check-pipeline-chain.sh's run-family
  # selection if the same issue is later run through full `run`.
  # The claim comment is the ONLY build-side record CI can see (the progress file is
  # gitignored and never reaches a checkout), so it carries BOTH build identities, not just
  # the run id. run_id is agent-CHOSEN — a build session that wanted to review itself needs
  # only pick a second string — whereas the session id is harness-assigned. Carrying it here
  # is what lets check-lean-chain.sh compare the stronger of the two at the merge boundary.
  body="$(mktemp -t lean-claim.XXXXXX)" || envfail "mktemp failed."
  {
    echo "<!-- dev-pipeline -->"
    echo "<!-- run_id: $RESOLVED_RUN_ID -->"
    echo "<!-- session_id: ${CLAUDE_CODE_SESSION_ID:-unset} -->"
    echo "<!-- stage: lean-claimed -->"
    echo ""
    echo "🤖 Claimed by \`/dev-pipeline:run-lean\`."
  } > "$body"
  url="$("${GH_BOT:?GH_BOT must point at the bot wrapper}" api -X POST \
        "repos/{owner}/{repo}/issues/$ISSUE/comments" -F body=@"$body" --jq .html_url 2>&1)"
  local rc=$?
  rm -f "$body"
  [ "$rc" -eq 0 ] || { warn "✗ claim: marker comment failed: $url"; return 1; }
  say "✓ claim: labels swapped and lean-claimed comment posted ($url)"
  return 0
}

# ---------------------------------------------------------------- milestone 1: spec/AC
# AC-3, as resolved at intake (G-1): existence AT THE PINNED PATH plus >= 1 numbered AC-n,
# and NO further content assertion. The path predicate is not an extra check — it is which
# file "exists" means, and check-lean-chain.sh keys its artifact scan off the same shape.
cmd_1() {
  local spec="$REPO_ROOT/$SPEC_REL" n
  [ -f "$spec" ] || { fail_milestone 1 "no committed spec at $SPEC_REL"; return $?; }
  n="$(count_matches '(^|[^A-Za-z])AC-[0-9]+' "$spec" -E)"
  [ "$n" -ge 1 ] || { fail_milestone 1 "spec $SPEC_REL carries no numbered AC-n criterion"; return $?; }
  pass_milestone 1 "$SPEC_REL ($n AC-n reference(s))"
}

# ---------------------------------------------------------------- milestone 2: policy
# D-13: EXACTLY the feature-PR half of CI's pr-gates, run pre-PR so violations die in the
# worktree. Excluded on purpose: the chain gate (not-applicable by prefix), the
# release-PR-only gates (on a feature branch they INVERT check-frozen-files.sh), and the
# lockstep/namespace checks (already covered by milestone 3's selftest sweep).
#
# D-44: these are second-shift REPO artifacts, not plugin payload. Outside this repo the
# gate detects their absence and prints a skip notice — never a silent pass.
cmd_2() {
  local base="origin/$BASE_BRANCH" frozen="$REPO_ROOT/scripts/check-frozen-files.sh"
  local trailer="$REPO_ROOT/scripts/check-changelog-trailer.sh" out rc

  if [ ! -f "$frozen" ] && [ ! -f "$trailer" ]; then
    say "milestone-2: policy gate scripts not present in this repo — SKIPPED (consumer repo; these are second-shift artifacts, not plugin payload)."
    append_line "$(now_iso) | milestone-2 | skipped | policy gate scripts absent (consumer repo)"
    pass_milestone 2 "skipped (consumer repo)"
    return 0
  fi

  if [ -f "$frozen" ]; then
    out="$(cd "$REPO_ROOT" && bash "$frozen" "$base" 2>&1)"; rc=$?
    # The ADVISORY tier (.github/workflows/** rows) prints and continues, so exit code
    # alone loses it. Surface it into the progress file rather than dropping it.
    case "$out" in
      *advisory*|*ADVISORY*)
        append_line "$(now_iso) | milestone-2 | advisory | $(printf '%s' "$out" | tr '\n' ' ')" ;;
    esac
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "$out" >&2
      fail_milestone 2 "check-frozen-files.sh failed (rc=$rc)"; return $?
    fi
  else
    say "milestone-2: check-frozen-files.sh absent — skip notice."
  fi

  if [ -f "$trailer" ]; then
    out="$(cd "$REPO_ROOT" && bash "$trailer" "$base" 2>&1)"; rc=$?
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "$out" >&2
      fail_milestone 2 "check-changelog-trailer.sh failed (rc=$rc)"; return $?
    fi
  else
    say "milestone-2: check-changelog-trailer.sh absent — skip notice."
  fi

  pass_milestone 2 "policy invariants hold against $base"
}

# ---------------------------------------------------------------- milestone 3: green
# D-17: the config commands table DIRECTLY — no verifyctl, and deliberately NO inert-diff
# lane. In a repo whose diffs are mostly shell and markdown, the inert lane would skip the
# suite on exactly the changes that need it most.
cmd_3() {
  local cmd rc sweep
  # lanes[] setup steps first, when present.
  if [ -f "$CONFIG" ]; then
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      say "milestone-3: lane » $cmd"
      ( cd "$REPO_ROOT" && eval "$cmd" ); rc=$?
      [ "$rc" -eq 0 ] || { fail_milestone 3 "lane failed (rc=$rc): $cmd"; return $?; }
    done < <(jq -r --arg s "$REPO_SLUG" '(.commands[$s].lanes // []) | .[] | (.command // .)' "$CONFIG" 2>/dev/null)
  fi

  local key
  for key in lint typecheck test build; do
    cmd="$(cfg ".commands[\"$REPO_SLUG\"].$key" '')"
    [ -n "$cmd" ] || { say "milestone-3: $key is null — skipped."; continue; }
    say "milestone-3: $key » $cmd"
    ( cd "$REPO_ROOT" && eval "$cmd" ); rc=$?
    [ "$rc" -eq 0 ] || { fail_milestone 3 "$key failed (rc=$rc)"; return $?; }
  done

  # D-18: the diff-scoped mutation sweep when the target repo carries one. Absent is a
  # PRINTED skip, never silent — a missing test-the-tests lane must be visible.
  sweep="$REPO_ROOT/tools/mutation-sweep.sh"
  if [ -f "$sweep" ]; then
    say "milestone-3: mutation sweep (diff-scoped) » origin/$BASE_BRANCH"
    ( cd "$REPO_ROOT" && bash "$sweep" --mode pr --base "origin/$BASE_BRANCH" ); rc=$?
    [ "$rc" -eq 0 ] || { fail_milestone 3 "mutation sweep failed (rc=$rc)"; return $?; }
  else
    say "milestone-3: tools/mutation-sweep.sh absent — mutation sweep SKIPPED (notice, not a silent pass)."
    append_line "$(now_iso) | milestone-3 | skipped | mutation-sweep.sh absent"
  fi

  pass_milestone 3 "green gate"
}

# ---------------------------------------------------------------- milestone 4: review
# D-22/D-46: the COMMITTED verdict record is the record of record. The progress-file line
# is a local counter only — the lean chain gate re-asserts the committed record at the
# merge boundary, so a hand-typed local line cannot reach a merge.
#
# READ-ONLY BY CONSTRUCTION. This milestone never writes to the verdict record — not to
# create it, not to stamp it, not to "normalize" it. The build session's only relationship
# to that file is reading one somebody else wrote; the moment this function can write it,
# the P10 separation below is decorative. The suite asserts the file is byte- and
# mtime-identical across a full `all` sweep.
cmd_4() {
  local rec="$REPO_ROOT/$VERDICT_REL" v_val v_run v_sess b_prog_run b_prog_sess b_cached cand
  local v_commit v_short stale n_stale v_head v_head_short declared n_declared v_pid cur_pid
  # The handoff moment, and so the one place the P9 reminder is contextual rather than noise.
  # It lives here rather than as another SKILL.md line for the reason the cap exists: stderr is
  # read exactly when it applies, prose is read on every run. NO DETECTION happens here — the
  # refusal is the merge boundary's alone (check-lean-chain.sh evidence 6), and a second in-run
  # copy would be the duplicate machinery D-47 rules out, not defense in depth.
  [ -f "$rec" ] || { fail_milestone 4 "no committed verdict record at $VERDICT_REL — hand off to '/dev-pipeline:review-lean <pr>'. If this run wrote an intent-gap record, ratify it before that handoff: the merge boundary refuses one still reading 'ratified: no'."; return $?; }
  v_val="$(record_verdict "$rec")"
  if [ "$v_val" != "approve" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL reads verdict=${v_val:-<none>}, not verdict=approve"; return $?
  fi
  # The reconciliation keys are what make the record checkable against the audit ledger.
  v_run="$(record_key run_id "$rec")"
  v_sess="$(record_key session_id "$rec")"
  if [ -z "$v_run" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL carries no run_id reconciliation key"; return $?
  fi
  if [ -z "$v_sess" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL carries no session_id reconciliation key — the review session's audit ledger cannot be located, so the verdict is unreconcilable"; return $?
  fi
  # The DECLARED reviewed head. Absent is refused for the same reason a missing verdict is:
  # nothing is checkable, and an uncheckable claim must not read as a satisfied one. Records
  # written before this key existed are refused too — the remedy is a review round on a
  # refreshed plugin, which is always available, so no transitional pass is warranted.
  v_head="$(record_key reviewed_head "$rec")"
  if [ -z "$v_head" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL carries no reviewed_head key, so nothing states which commit the review actually read. Re-run the review round on a dev-pipeline that writes it: '/dev-pipeline:review-lean <pr>'."; return $?
  fi

  # AUTHORSHIP (P10). TWO build identities are compared, and both are FILE-BACKED:
  #   - the id sitting in the build run-id cache file,
  #   - the id the build run stamped into the progress-file header.
  # The cache arm is the load-bearing one. A review session that never provisioned its own
  # RUN_ID used to resolve the BUILD cache, and the record it wrote then looked "distinct"
  # only in the sense that nobody had checked. Comparing against the cache file directly
  # catches that whether or not this invocation happens to have RUN_ID in its environment.
  #
  # $RESOLVED_RUN_ID is deliberately NOT a candidate. It is "whoever is running this command",
  # which is a build identity only when a build session is the caller. A REVIEW session running
  # `bash G 4 <issue>` to check the record it just wrote resolves its own review id there, and
  # comparing the record against it matched by construction — refusing a correct record for the
  # crime of being checked by its author's counterpart. It was also redundant: a build session
  # invoking with RUN_ID set seeds that same value into the cache file on this very call, so
  # the b_cached arm already covers the case the third arm was added for.
  b_cached=""; [ -s "$RUN_ID_CACHE" ] && b_cached="$(cat "$RUN_ID_CACHE")"
  b_prog_run="$(record_key run_id "$PROGRESS_FILE")"
  b_prog_sess="$(record_key session_id "$PROGRESS_FILE")"
  for cand in "$b_cached" "$b_prog_run"; do
    [ -n "$cand" ] || continue
    if [ "$v_run" = "$cand" ]; then
      fail_milestone 4 "verdict record $VERDICT_REL carries the BUILD run's identity ('$v_run') — the session that wrote the code may not author its own review verdict (P10). Produce the record from a separate review session: 'lean-gate.sh verdict $ISSUE --pr <n> --verdict approve'."
      return $?
    fi
  done
  if [ -n "$b_prog_sess" ] && [ "$v_sess" = "$b_prog_sess" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL names the BUILD session ('$v_sess') as its author — the review must run in a separate context (P10)."
    return $?
  fi

  # FRESHNESS — the verdict must cover the tree it is being read against.
  #
  # cmd_all states the invariant the other four milestones live by: `satisfied` is a RECORD,
  # not a CACHE, so every milestone is re-evaluated against the CURRENT tree on every sweep.
  # Milestone 4 is the one that cannot honor it by re-evaluating, because its evaluation is
  # reading a file somebody else wrote. Something else has to bind that file to a tree.
  #
  # That gap was harmless while the build session wrote the record at review time — the record
  # and the tree were coupled by the ordering. Once review moved to a separate session it stops
  # being harmless: "verdict, then more commits" is the ORDINARY shape of the needs-work loop,
  # and the PR that introduced this separation demonstrated it on itself (verdict committed,
  # then a follow-up commit rewrote the authorship arms above, and this gate stayed green).
  #
  # Derived from git, never from a key in the record: git decides which commit carries the
  # record, and the record's own prose cannot argue with it. The tolerance is exactly one path
  # — the record itself — because the review session commits nothing else (review-lean step 6).
  v_commit="$(git -C "$REPO_ROOT" log -1 --format=%H -- "$VERDICT_REL" 2>/dev/null)"
  if [ -z "$v_commit" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL exists but was never committed — a local file is not evidence, and nothing downstream can see it. Commit and push it to the PR's head branch."
    return $?
  fi
  # Tracked-but-dirty is its own case, and the one a bare `git log` lookup misses: the path has
  # a commit, so the lookup above is satisfied, while the bytes being READ are not the bytes
  # anyone committed. Both readings of "not committed" have to fail.
  if ! git -C "$REPO_ROOT" diff --quiet HEAD -- "$VERDICT_REL" 2>/dev/null; then
    fail_milestone 4 "verdict record $VERDICT_REL has uncommitted changes — the record being read is not the record on the branch, so the one downstream sees is a different file. Commit and push it."
    return $?
  fi
  stale="$(git -C "$REPO_ROOT" diff --name-only "$v_commit" HEAD 2>/dev/null | grep -vxF "$VERDICT_REL")"
  if [ -n "$stale" ]; then
    v_short="$(git -C "$REPO_ROOT" rev-parse --short "$v_commit" 2>/dev/null)"
    n_stale="$(printf '%s\n' "$stale" | wc -l | tr -d ' ')"
    fail_milestone 4 "verdict record $VERDICT_REL approves $v_short, but $n_stale file(s) changed after it (e.g. $(printf '%s' "$stale" | head -n1)) — a verdict does not cover code it never saw. Get a new review round on the current head: '/dev-pipeline:review-lean <pr>'."
    return $?
  fi

  # The DECLARED arm. Same question as the arm above — does the review cover this tree — asked
  # against what the record DECLARES rather than the commit it SITS ON, which is the one case
  # inference cannot see: a reviewer who reads head A, waits while a fix lands at B, and then
  # commits an honest record on top of B leaves inference with nothing to complain about.
  #
  # TWO KEYINGS, in precedence order. Patch identity is the gate whenever the record carries
  # one; the SHA path below is what pre-key records still gate on. The old keying is not WRONG,
  # only over-strict — it refused a rebase, which changes no reviewed content — so records
  # written before the key existed are read on it rather than refused by the upgrade itself.
  #
  # What patch identity deliberately does NOT cover: a base change that reds the suite with no
  # textual conflict. The branch's patch is unchanged there, so the verdict correctly still
  # stands, and the merged result failing is CI's business. Conflating "the reviewed content
  # moved" with "the merge result broke" is what made the SHA keying over-strict to begin with.
  v_pid="$(record_key reviewed_patch_id "$rec")"
  if [ -n "$v_pid" ]; then
    cur_pid="$(branch_patch_id HEAD)"
    if [ -z "$cur_pid" ]; then
      fail_milestone 4 "cannot compute this branch's patch identity against origin/$BASE_BRANCH, so there is nothing to compare $VERDICT_REL's reviewed_patch_id against — and a freshness check that cannot run must not report a pass. Fetch origin/$BASE_BRANCH and re-run."
      return $?
    fi
    if [ "$v_pid" != "$cur_pid" ]; then
      fail_milestone 4 "verdict record $VERDICT_REL reviewed patch $(printf '%.12s' "$v_pid"), but this branch's diff against origin/$BASE_BRANCH now hashes to $(printf '%.12s' "$cur_pid") — content changed after the review, so the verdict does not cover it. Get a new review round: '/dev-pipeline:review-lean <pr>'."
      return $?
    fi
    pass_milestone 4 "$VERDICT_REL reads verdict=approve, authored by review run $v_run, covering the current head (patch-id $(printf '%.12s' "$v_pid"))"
    return $?
  fi

  if ! git -C "$REPO_ROOT" cat-file -e "$v_head^{commit}" 2>/dev/null; then
    fail_milestone 4 "verdict record $VERDICT_REL names reviewed_head $v_head, which is not a commit in this branch's history — the branch was rebased or force-pushed after the review, so the reviewed code no longer exists here. Get a new review round: '/dev-pipeline:review-lean <pr>'."
    return $?
  fi
  declared="$(git -C "$REPO_ROOT" diff --name-only "$v_head" HEAD 2>/dev/null | grep -vxF "$VERDICT_REL")"
  if [ -n "$declared" ]; then
    v_head_short="$(git -C "$REPO_ROOT" rev-parse --short "$v_head" 2>/dev/null)"
    n_declared="$(printf '%s\n' "$declared" | wc -l | tr -d ' ')"
    fail_milestone 4 "verdict record $VERDICT_REL states it reviewed $v_head_short, but $n_declared file(s) differ between that commit and the current head (e.g. $(printf '%s' "$declared" | head -n1)) — the review read a different tree than the one being gated. Get a new review round: '/dev-pipeline:review-lean <pr>'."
    return $?
  fi

  pass_milestone 4 "$VERDICT_REL reads verdict=approve, authored by review run $v_run, declaring reviewed_head $(git -C "$REPO_ROOT" rev-parse --short "$v_head" 2>/dev/null) and covering the current head"
}

# ---------------------------------------------------------------- verdict (REVIEW role)
# The ONLY write path to the verdict record, and it lives in this script rather than a second
# one for a single reason: the pinned name table above is the sole derivation of VERDICT_REL,
# and a name invented at a second site is exactly the drift the merge-boundary gate turns red.
#
# It never evaluates a milestone, never appends to the progress file (that file belongs to the
# build run), and never touches the build run-id cache. Those omissions are what let milestone
# 4 stay a pure read while the record still comes from here.
#
# The refusals are ordered cheapest-first and every one of them fails CLOSED. In particular a
# build run whose progress header records no session id is refused outright: without it there
# is nothing to separate the review from, and "unverifiable" must never resolve to "fine".
cmd_verdict() {
  local sess b_prog_sess b_prog_run b_cached rec body c reviewed_head reviewed_patch_id
  sess="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$sess" ] \
    || envfail "verdict: CLAUDE_CODE_SESSION_ID is unset — the review session cannot be identified, so its authorship cannot be separated from the build's."
  [ -f "$PROGRESS_FILE" ] \
    || envfail "verdict: no build progress file at $PROGRESS_FILE — there is no build run on #$ISSUE to review."

  b_prog_sess="$(record_key session_id "$PROGRESS_FILE")"
  b_prog_run="$(record_key run_id "$PROGRESS_FILE")"
  b_cached=""; [ -s "$RUN_ID_CACHE" ] && b_cached="$(cat "$RUN_ID_CACHE")"

  if [ -z "$b_prog_sess" ] || [ "$b_prog_sess" = "unset" ]; then
    warn "✗ verdict: the build progress file records no session id, so authorship separation is unverifiable. Refusing."
    return 1
  fi
  if [ "$sess" = "$b_prog_sess" ]; then
    warn "✗ verdict: this IS the build session ($sess) — the build session may not author its own review verdict (P10)."
    warn "  Run the review from a fresh top-level session: /dev-pipeline:review-lean <pr>."
    return 1
  fi

  if [ "$RESOLVED_RUN_ID" = "unset" ]; then
    warn "✗ verdict: no review identity provisioned. Export RUN_ID (e.g. review-$ISSUE-1) before the first verdict call; it is cached at $REVIEW_RUN_ID_CACHE for later ones."
    warn "  The build cache at $RUN_ID_CACHE is deliberately NOT consulted — inheriting the build's id would defeat the separation this refusal exists for."
    return 1
  fi
  for c in "$b_prog_run" "$b_cached"; do
    [ -n "$c" ] || continue
    if [ "$RESOLVED_RUN_ID" = "$c" ]; then
      warn "✗ verdict: the review identity '$RESOLVED_RUN_ID' IS the build run's. Provision a distinct RUN_ID for the review session."
      return 1
    fi
  done

  case "$VERDICT_VALUE" in
    approve|needs-work) : ;;
    *) envfail "verdict: --verdict must be 'approve' or 'needs-work' (got '$VERDICT_VALUE')." ;;
  esac
  # --pr is validated like the other two value-args, not merely checked for emptiness. It is
  # echoed into the committed record, so an unvalidated value puts arbitrary text — newlines
  # included — into an evidence artifact. Nothing escalates today (all three readers take the
  # FIRST match of each key, so an injected `run_id:` loses to the authentic one written
  # above it), but "harmless because of where it lands in the file" is a property of the
  # current readers, not of this argument.
  [ -n "$VERDICT_PR" ] || envfail "verdict: --pr <number> is required — the record names the PR it reviewed."
  VERDICT_PR="${VERDICT_PR#\#}"   # tolerate `--pr #361`
  case "$VERDICT_PR" in
    ''|*[!0-9]*|0) envfail "verdict: --pr must be a positive integer (got '$VERDICT_PR')." ;;
  esac
  [ -n "$VERDICT_ROUNDS" ] || VERDICT_ROUNDS=1
  # `0` matches neither '' nor *[!0-9]*, so the pre-#345 form accepted --rounds 0 while its own
  # message said "positive integer". Round 0 is not a round.
  case "$VERDICT_ROUNDS" in
    ''|*[!0-9]*|0) envfail "verdict: --rounds must be a positive integer (got '$VERDICT_ROUNDS')." ;;
  esac

  # The reviewed head, DERIVED from the checkout this call runs in — never an argument. The
  # review session works from a checkout of the PR head (review-lean step 3), so HEAD here IS
  # the commit under review; a flag would let the caller name a head it did not read, which is
  # the exact failure the key exists to catch. Running `verdict` from the wrong checkout writes
  # a head that does not match, and every reader refuses it. That is fail-closed, and visible.
  reviewed_head="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" \
    || envfail "verdict: cannot resolve HEAD in '$REPO_ROOT' — there is no commit to name as the reviewed head. Run this from a checkout of the PR's head branch."
  [ -n "$reviewed_head" ] \
    || envfail "verdict: HEAD resolved to nothing in '$REPO_ROOT'. Run this from a checkout of the PR's head branch."

  # The reviewed PATCH, alongside the reviewed head and derived the same way — from this
  # checkout, never from an argument. It is what the freshness readers gate on; `reviewed_head`
  # stays as the human-readable pointer and as the pre-key records' path.
  #
  # Unresolvable is an ENVIRONMENT error, not a record written without the key. A record whose
  # key is silently omitted reads to every downstream reader as "written before the key existed"
  # and falls through to the SHA path — so a missing base ref here would quietly re-introduce
  # the rebase refusal this key exists to remove, at review time, invisibly.
  reviewed_patch_id="$(branch_patch_id "$reviewed_head")"
  [ -n "$reviewed_patch_id" ] \
    || envfail "verdict: cannot compute the branch's patch identity against origin/$BASE_BRANCH (merge-base unresolvable, or the branch's diff excluding $VERDICT_REL is empty). Fetch origin/$BASE_BRANCH in this checkout and re-run — a record written without it would silently degrade to the pre-patch-id path."

  body=""
  if [ -n "$SUMMARY_FILE" ]; then
    [ -f "$SUMMARY_FILE" ] || envfail "verdict: --summary-file '$SUMMARY_FILE' does not exist."
    body="$(cat "$SUMMARY_FILE")"
  fi

  rec="$REPO_ROOT/$VERDICT_REL"
  mkdir -p "$(dirname "$rec")" || envfail "verdict: cannot create '$(dirname "$rec")'."
  # Cache the review identity only now — every refusal above has passed, so this is a real
  # review round and later calls in the same round may resolve it from a fresh shell.
  mkdir -p "$(dirname "$REVIEW_RUN_ID_CACHE")" 2>/dev/null \
    && printf '%s' "$RESOLVED_RUN_ID" > "$REVIEW_RUN_ID_CACHE"
  {
    echo "# lean review verdict — #$ISSUE"
    echo ""
    echo "verdict=$VERDICT_VALUE"
    echo "run_id: $RESOLVED_RUN_ID"
    echo "session_id: $sess"
    echo "rounds: $VERDICT_ROUNDS"
    echo "pr: #$VERDICT_PR"
    echo "reviewed_head: $reviewed_head"
    echo "reviewed_patch_id: $reviewed_patch_id"
    echo "model: ${LEAN_RUN_MODEL:-unknown}"
    echo ""
    if [ -n "$body" ]; then printf '%s\n' "$body"; fi
  } > "$rec"

  say "✓ verdict: $VERDICT_REL written (verdict=$VERDICT_VALUE, run_id=$RESOLVED_RUN_ID, round $VERDICT_ROUNDS, reviewed_head=$reviewed_head, reviewed_patch_id=$reviewed_patch_id)"
  say "  It is evidence only once COMMITTED to the PR's head branch — commit and push it."
  return 0
}

# ---------------------------------------------------------------- milestone 5: exit
# D-42: the most externally-visible artifacts are GATED, not prose-mandated.

# jira's ticket reference is `Closes [<KEY>]` inside the PR template's `### Jira Items`
# section — the SECTION is the contract, so an unsectioned `Closes [KEY]` elsewhere in the
# body does not count. Heading DEPTH is not: `###` is one repo template's choice, so any
# level is accepted. `#+[[:space:]]` (not `#{1,6}`) because interval expressions are not
# portable across the awks this ships on.
#
# BOTH patterns require the space after the hashes, and that symmetry is the point: they are
# two halves of ONE definition of "heading", so they must agree. CommonMark (and GitHub's
# renderer) needs the space — `###Notes` is literal text, not a heading. An asymmetric pair
# is a false-ACCEPT: an optional-space OPEN starts a pseudo-section on a body that merely
# mentions `###Jira Items`, and a required-space CLOSE then never ends it, so a `Closes [KEY]`
# far outside any real section passes the gate.
#
# The heading match is case-FOLDED, matching the `-i` on the ticket-reference grep below. The
# repo's own jira prose writes the acronym in caps throughout, so `### JIRA Items` is a
# likelier consumer template than the canonical spelling — and a case-sensitive match would
# turn it into a false-REJECT that burns milestone 5's whole fix budget to rc=4 AFTER the
# implementation and review are paid for, which is the failure mode this adapter exists to
# remove. Widening acceptance here costs nothing: the section still has to exist.
#
# A NESTED heading (`#### Tickets` inside `### Jira Items`) also closes the section, even
# though markdown renders it within. Deliberate, and stated so the code and the "depth is not
# the contract" decision do not read as contradictory: depth is ignored when OPENING because
# the template's level is the repo's choice, and any heading CLOSES because a flat "runs to
# the next heading" rule is the one a reader can predict. The repo's own template has no
# sub-headings under Jira Items.
jira_items_section() { # stdin: the PR body — prints the section's lines, nothing else
  awk '
    tolower($0) ~ /^#+[[:space:]]+jira items[[:space:]]*$/ { insec = 1; next }
    insec && /^#+[[:space:]]/                              { insec = 0 }
    insec                                                   { print }
  '
}

cmd_5() {
  local pr comments url draft body

  # "Progress file current" is asserted as: milestones 1-4 each left a `satisfied` record.
  #
  # NOT as "the file exists". That check cannot hold: failing any milestone appends an
  # attempt line, appending creates the file, so a bare existence check heals itself between
  # the first run and the second — it reports absent once and passes forever after, which is
  # worse than not checking at all. Asserting the 1-4 records is stable (an M5 attempt line
  # never satisfies M1-4) and is what the contract actually means.
  local m missing=""
  for m in 1 2 3 4; do
    [ "$(count_matches "| milestone-$m | satisfied" "$PROGRESS_FILE" -F)" -ge 1 ] || missing="$missing $m"
  done
  if [ -n "$missing" ]; then
    fail_milestone 5 "progress file is not current — milestone(s)$missing left no satisfied record, so there is nothing to certify"
    return $?
  fi

  if [ -n "$PR_FILE" ]; then
    [ -f "$PR_FILE" ] || envfail "--pr-file '$PR_FILE' does not exist."
    pr="$(cat "$PR_FILE")"
  else
    pr="$("$GH_CLI" pr list --head "$LEAN_BRANCH_PREFIX$ISSUE" --state open \
          --json number,url,body,isDraft --limit 1 2>&1)" \
      || { warn "$pr"; fail_milestone 5 "could not list PRs for $LEAN_BRANCH_PREFIX$ISSUE"; return $?; }
  fi
  printf '%s' "$pr" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { fail_milestone 5 "no open PR found for branch $LEAN_BRANCH_PREFIX$ISSUE"; return $?; }

  draft="$(printf '%s' "$pr" | jq -r '.[0].isDraft')"
  body="$(printf '%s' "$pr" | jq -r '.[0].body // ""')"
  url="$(printf '%s' "$pr" | jq -r '.[0].url')"

  [ "$draft" = "false" ] || { fail_milestone 5 "PR $url is still a draft (D-27 requires a ready PR)"; return $?; }
  # Same capture-first discipline as count_matches — these read a string, not a file.
  local n_closes n_spec
  if [ "$TRACKER_TYPE" = "jira" ]; then
    n_closes="$(printf '%s' "$body" | jira_items_section | grep -c -i -E "closes[[:space:]]+\[$ISSUE\]")" || n_closes=0
    [ "$n_closes" -ge 1 ] \
      || { fail_milestone 5 "PR body carries no 'Closes [$ISSUE]' under a 'Jira Items' heading"; return $?; }
  else
    n_closes="$(printf '%s' "$body" | grep -c -i -E "closes[[:space:]]+#$ISSUE")" || n_closes=0
    [ "$n_closes" -ge 1 ] \
      || { fail_milestone 5 "PR body carries no 'Closes #$ISSUE'"; return $?; }
  fi
  # Adapter-INSENSITIVE: the spec is a committed repo path at the same pinned location under
  # both trackers, so the link assertion is shared rather than duplicated per arm.
  n_spec="$(printf '%s' "$body" | grep -c -F -- "$SPEC_REL")" || n_spec=0
  [ "$n_spec" -ge 1 ] \
    || { fail_milestone 5 "PR body does not link the committed spec ($SPEC_REL)"; return $?; }

  # Under jira the verdict reference has nowhere else to live: `tracker.writes: false` means
  # there is no closing comment, so the PR body carries it and the comment trail is never
  # read. Reviewers read the PR either way — this only changes WHICH surface is gated.
  if [ "$TRACKER_TYPE" = "jira" ]; then
    local n_verdict
    n_verdict="$(printf '%s' "$body" | grep -c -F -- "$VERDICT_REL")" || n_verdict=0
    [ "$n_verdict" -ge 1 ] \
      || { fail_milestone 5 "PR body does not reference the verdict record ($VERDICT_REL) — under a read-only tracker the body is the only surface that can carry it"; return $?; }
    pass_milestone 5 "exit artifacts present, jira adapter, no tracker write ($url)"
    return 0
  fi

  if [ -n "$COMMENTS_FILE" ]; then
    [ -f "$COMMENTS_FILE" ] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
    comments="$(cat "$COMMENTS_FILE")"
  else
    comments="$("$GH_CLI" api "repos/{owner}/{repo}/issues/$ISSUE/comments" --paginate 2>&1)" \
      || { warn "$comments"; fail_milestone 5 "could not fetch the comment trail for #$ISSUE"; return $?; }
  fi
  printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || envfail "comment trail is not a JSON array."

  # The closing comment must REFERENCE the verdict record — that reference is what ties
  # the tracker record to the committed artifact the chain gate checks.
  local closing
  closing="$(printf '%s' "$comments" | jq -r --arg v "$VERDICT_REL" \
    '[ .[] | select((.body // "") | contains($v)) ] | length')"
  [ "$closing" -ge 1 ] \
    || { fail_milestone 5 "no closing comment on #$ISSUE references the verdict record ($VERDICT_REL)"; return $?; }

  pass_milestone 5 "exit artifacts present ($url)"
}

# ---------------------------------------------------------------- all
# G-2, load-bearing: `satisfied` is a RECORD, not a CACHE. Every milestone is re-evaluated
# against the CURRENT tree on every sweep. Short-circuiting on a stored `satisfied` line is
# exactly how a green gate from before a milestone-4 fix round would certify code that
# never passed it.
run_milestone() { # explicit dispatch, not "cmd_$1": an indirect call hides every callee
  case "$1" in                        # from static analysis (shellcheck SC2329) and from
    1) cmd_1 ;;                       # a reader grepping for call sites.
    2) cmd_2 ;;
    3) cmd_3 ;;
    4) cmd_4 ;;
    5) cmd_5 ;;
    *) envfail "run_milestone: unknown milestone '$1'" ;;
  esac
}

cmd_all() {
  local n rc
  for n in 1 2 3 4 5; do
    run_milestone "$n"; rc=$?
    if [ "$rc" -ne 0 ]; then
      say "all: stopped at milestone-$n (rc=$rc)"
      return "$rc"
    fi
  done
  say "all: milestones 1-5 satisfied."
  return 0
}

# ---------------------------------------------------------------- dispatch
case "$SUB" in
  entry)   cmd_entry ;;
  claim)   cmd_claim ;;
  verdict) cmd_verdict ;;
  all)     cmd_all ;;
  *)       run_milestone "$SUB" ;;
esac
exit $?

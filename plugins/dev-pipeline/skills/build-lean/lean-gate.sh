#!/usr/bin/env bash
# lean-gate.sh — the five milestone gates of /dev-pipeline:build-lean, plus the entry
# precondition and the claim helper.
#
# WHY THIS EXISTS: build-lean is OUTCOME-gated, not process-prescribed. The harness asserts
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
# INHERITANCE (#375). Every round declares `inherited_patch_id`: the reviewed patch of the round
# whose coverage it inherits, so a fix round reads the delta since that tree instead of the whole
# diff again — or the literal `none` on a chain root. The merge boundary's guarantee then reads
# "a CHAIN of independent reviews collectively covered this tree", and it holds only while every
# LINK is verified — an unverified link would let a round read forty lines and be credited with a
# thousand. So every reader walks the chain, and a link matching no committed record is refused.
#
# EVERY round, including the roots that inherit nothing, because the alternative was reachable
# and reached: a key the writer sometimes omits leaves the reviewer's own findings as the first
# occurrence in the file, and every reader takes the first match. See `inherited_key`, which
# anchors the read to the header and is the half of that fix which also covers records this
# writer did not produce.
#
# The keys are DERIVED here, never passed in, for the reason `reviewed_head`/`reviewed_patch_id`
# refuse an argument: a flag lets a round name coverage it did not inherit, and a round could
# silently OMIT the key, which every reader would then read as a full-coverage claim it never
# performed. The chain is walked by matching patch identities, never commit SHAs — the same
# reasoning one level up: a SHA link dies on a rebase, and the refusal would charge a review
# round for a mechanical operation. `inherited_from_verdict` is a human pointer only, exactly
# the role `reviewed_head` now holds; no reader gates on it.
#
# Usage:
#   lean-gate.sh entry  <issue>          entry precondition: the session's audit ledger is live.
#                                        On success it RECORDS that fact in the progress file;
#                                        every build-role subcommand below refuses with exit 2
#                                        until that row exists, so skipping this step is a
#                                        refusal rather than a silent omission (#416).
#                                        The queue-label reject is the SESSION's step (SKILL.md
#                                        step 1) — it needs a tracker read, so it is not gated
#                                        here. Under tracker.type: jira there is no queue at all.
#   lean-gate.sh claim  <issue>          the two bot-wrapper claim writes (AC-15/D-49).
#                                        Under tracker.type: jira it makes NO tracker write and
#                                        needs no GH_BOT — it records the run id and returns.
#   lean-gate.sh <1..5> <issue>          evaluate one milestone. Milestone 1 also refuses when
#                                        the issue declares an Open Region dispositioned
#                                        `pause-and-ask` with no resolution artifact (AC-8).
#   lean-gate.sh all    <issue>          a cheap, read-only pre-pass evaluates milestones 1 and
#                                        4 first (no network, no fix-budget attempt) and reports
#                                        every already-unsatisfiable one before running the real
#                                        1..5 progression, so a stale verdict record is reported
#                                        without paying milestone 3's green gate first.
#   lean-gate.sh teardown <issue>        destroy this run's worktree (#442). Checklist step 9's
#                                        final act, deliberately OUTSIDE the 1..5 progression:
#                                        `all` runs milestones 1-5 and is mandated BEFORE that
#                                        step, so a self-removing milestone 5 would delete the
#                                        worktree mid-run. Refuses on unpushed or unclean work
#                                        and exits 0 either way — hygiene is not evidence. Never
#                                        deletes the branch: the PR points at it.
#   lean-gate.sh delta  <issue>          REVIEW role: print the range this round must READ —
#                                        the delta since the tree the last round covered, or the
#                                        full branch diff when there is nothing verifiable to
#                                        inherit. Reads only; writes nothing.
#   lean-gate.sh verdict <issue> --pr <n> --verdict <approve|needs-work> [--rounds <n>]
#                                        [--fidelity <pass|fail|not-applicable>]
#                                        [--summary-file <path>]
#                                        REVIEW role: write the committed verdict record.
#                                        --fidelity defaults to not-applicable, which is the
#                                        fail-closed side on an armed run (milestone 4 wants
#                                        `pass`); `fail` with `approve` is refused.
#   lean-gate.sh progress <issue> [--satisfied <n>]
#                                        SCHEDULER role (#492): print an OPAQUE TOKEN over the
#                                        progress rows that mean the build role advanced. Reads
#                                        only — it writes nothing and, unlike every other
#                                        subcommand, does not create the file it reads. The
#                                        caller compares the token across a spawn and interprets
#                                        nothing; `--satisfied <n>` narrows it to milestone n's
#                                        `satisfied` row alone.
#   lean-gate.sh staleness <issue> [--arm ticket|base|both]
#                                        SCHEDULER role (#515): is this run's premise still true?
#                                        The TICKET arm asks whether the issue is still open; the
#                                        BASE arm asks whether the base has moved into files this
#                                        branch also touches. Reads only, records nothing, spends
#                                        no fix budget, and creates no file. `--arm` defaults to
#                                        `both`; preflight passes `ticket`, because the base arm
#                                        belongs to the spawn loop.
#
# Exit: 0 = satisfied / ok
#       1 = milestone failed, or a `verdict` authorship refusal (fix and retry — budget remains)
#       2 = usage or environment error, or a build-role call made before `entry` was recorded
#       4 = fix budget exhausted for that milestone (hard stop; D-19)
#       5 = milestone 4 only: NO VERDICT USABLE AGAINST THE CURRENT HEAD — the record is absent,
#           uncommitted, dirty, missing a reconciliation key, stale, or its inheritance chain is
#           broken. Distinct from 1 because the remedy is a REVIEW round, never a BUILD fix, and a
#           scheduler that cannot tell them apart re-spawns BUILD to fix nothing (#496).
#       6 = milestone 4 only: INTEGRITY REFUSAL — the record is authored by the build run or the
#           build session (P10). Terminal: the trust boundary this lane exists to enforce is not
#           something a retry can clear.
#       7 = NOTHING WAS EVALUATED — raised by two subcommands, unambiguous at each call site, and
#           under neither one a milestone failure nor a fix attempt:
#           * `staleness`: STALE — the ticket is closed, or the base has moved into this branch's
#             files. Its own integer for the same reason 5 and 6 are: the scheduler's response
#             differs from a phase failure's, and one that cannot tell them apart spends the rest
#             of the run proving the premise it was just told is false.
#           * milestone 3: THE EVALUATION DID NOT COMPLETE — its detached runner died without
#             stamping a code, or the wall-clock ceiling was reached with it still running (#511
#             D-5). Nothing was evaluated, so 1 would send the operator to fix code that was never
#             judged, and 4 would fire an abort comment at a sweep that is very likely still
#             running. The remedy is to RE-INVOKE, which joins a live runner or relaunches a dead
#             one.
#
# Seams (zero-network selftest; the check-pipeline-chain.sh precedent):
#   ${GH:-gh}                the CLI used for reads, including the sweep's PR-state lookup
#   ${CURL:-curl}            the client used for design.liveRender.readyProbe (#394). The only
#                            outbound call milestone 3 can make, and only when a consumer
#                            configures the probe — the suite points it at a stub.
#   LEAN_PROGRESS_FILE       override the resolved progress-file path
#   SECOND_SHIFT_CONFIG      override the resolved config path
#   --pr-file <path>         milestone 5: read the PR record from a JSON fixture
#   --comments-file <path>   milestone 5 and milestone 1's pause-and-ask check: read the issue
#                            comments from a JSON fixture (same trail either way — a live run
#                            fetches it once from the same endpoint)
#   --issue-file <path>      milestone 1's pause-and-ask check: read the issue body ({"body":
#                            "..."}) from a JSON fixture instead of `gh issue view`
#   LEAN_RUN_MODEL           #347: the `model:` key stamped into the progress/verdict record
#                            at creation time (retro-corpus.sh's corpus-aggregation key).
#                            Read once, not cached; absent reads "unknown", never an error.
#   LEAN_GATE_OBSERVE=1      #496: EVALUATE WITHOUT RECORDING. Milestones 1 and 4 return their
#                            ordinary exit code — including the taxonomy above and a spent budget's
#                            4 — while appending no `attempt`/`absent` line, consuming no budget
#                            and writing no `satisfied` line. `cmd_all`'s cheap pre-pass uses it,
#                            and so does the scheduler's verdict read: reading a verdict must not
#                            charge the build role for a milestone the reader did not fail.
#   LEAN_GATE_WAIT_CEILING_SECS
#                            #511 D-4: how long a milestone-3 call blocks on its detached runner
#                            before returning 7. Defaults to 3600. The suite sets it to seconds to
#                            exercise a breach; a real run should not lower it — a breach
#                            reclassifies an honest slow sweep as infrastructure.
#
# There is NO seam and no flag for milestone 3's detached runner, by two rounds of deliberate
# subtraction. It began as an inherited `LEAN_GATE_M3_RUNNER=1` on a re-exec of this script, which
# cost a milestone attempt on this ticket's own PR: milestone 3's lane children here are
# lean-gate.sh itself (dogfooding), so the variable reached the nested selftest and every
# milestone-3 call inside it ran INLINE as a "runner". An argv flag fixed that and was still
# paying a whole second gate startup per call — measured at 1.4s against a 1.9s total overhead,
# which pushed the paired suite past mutation-sweep.sh's 300s killer bound. The runner is now a
# forked SUBSHELL of the process that launches it, so there is no handshake to inherit and
# nothing to re-parse. See m3_launch_or_join.
#
# bash 3.2 compatible (macOS ships it, and CI has a bash-3.2 lane).
set -uo pipefail

GH_CLI="${GH:-gh}"
CURL_CLI="${CURL:-curl}"
PR_FILE=""
COMMENTS_FILE=""
ISSUE_FILE=""
VERDICT_VALUE=""
VERDICT_PR=""
VERDICT_ROUNDS=""
VERDICT_FIDELITY=""
SUMMARY_FILE=""
PROGRESS_SATISFIED=""
# #515. Empty means "not given"; the default is applied after validation, so `--arm` on a
# subcommand that ignores it is still loud rather than silently absorbed into the default.
STALENESS_ARM=""

# The fix budget: 3 attempts per milestone, the 4th red hard-stops (D-19). Counted from
# the progress file's `attempt` lines per D-41 — only FAILED evaluations append one.
FIX_BUDGET=3

# #494 D-2. The absent-artifact budget, a SEPARATE and much larger bound. It is not a fix budget:
# nothing has gone wrong when it is spent, so the number is sized to never bite an honest run
# while still bounding a session that loops forever on "where does the spec go?". Observed honest
# ceiling is ~4 (the #490 run made 2 such calls; a resume in a fresh worktree adds 1-2; cmd_all's
# observe pre-pass records nothing), so 10 is ~2.5x headroom.
ABSENT_BUDGET=10

# #497 D-7. The INTERRUPTED budget: how many evaluations of one milestone may BEGIN and never
# conclude before the next call refuses to start another. A third bound, and deliberately the
# tightest of the three — absence is the contract's own recommended move (build-lean step 3 orders
# a milestone-1 call before the spec can exist), interruption never is. A full lane can spawn ~9
# build sessions (MAX_ROUNDS=3 × 1 + MAX_CONTINUATIONS=2, continuations resetting per build phase),
# each able to interrupt once — so 5 fires on a systematic background-and-exit pattern while
# staying out of reach of the bad luck an honest run meets (0, occasionally 1-2).
INTERRUPTED_BUDGET=5

say()  { echo "[lean-gate] $*"; }
warn() { echo "[lean-gate] $*" >&2; }
envfail() { echo "[lean-gate] $*" >&2; exit 2; }

# ---------------------------------------------------------------- argument parsing
SUB=""
ISSUE=""
POSITIONAL=0

# LIBRARY MODE (#439). `LEAN_GATE_LIB=1 . lean-gate.sh` leaves this file's helpers defined and
# dispatches nothing — the args below are inert placeholders, and the bottom of the file returns
# before the subcommand case. It exists for one function: md_table_prettier has width cases the
# render path cannot reach, because every column of the render manifest is wider than the
# 3-dash minimum, and the only other way to fixture them is a hand-copied padder in the suite —
# a mirror harness, which cannot fail on a production edit and so converges on green while the
# real code drifts. No run sets this; every documented seam still applies in library mode.
#
# CAVEAT for anyone sourcing it: the parser below consumes the placeholders, so the sourcing
# scope's own positional parameters are gone afterwards. Copy anything you need out of `$1`
# BEFORE the `.` — a caller that reads them after it gets an unbound-variable error under
# `set -u`, which is how this caveat was found rather than reasoned about.
[ -n "${LEAN_GATE_LIB:-}" ] && set -- entry 0
while [ $# -gt 0 ]; do
  case "$1" in
    --pr-file)       PR_FILE="${2:-}"; shift 2 ;;
    --comments-file) COMMENTS_FILE="${2:-}"; shift 2 ;;
    --issue-file)    ISSUE_FILE="${2:-}"; shift 2 ;;
    --pr)            VERDICT_PR="${2:-}"; shift 2 ;;
    --verdict)       VERDICT_VALUE="${2:-}"; shift 2 ;;
    --rounds)        VERDICT_ROUNDS="${2:-}"; shift 2 ;;
    --fidelity)      VERDICT_FIDELITY="${2:-}"; shift 2 ;;
    --summary-file)  SUMMARY_FILE="${2:-}"; shift 2 ;;
    --satisfied)     PROGRESS_SATISFIED="${2:-}"; shift 2 ;;
    --arm)           STALENESS_ARM="${2:-}"; shift 2 ;;
    -h|--help)       sed -n '2,195p' "$0"; exit 0 ;;
    -*)              envfail "unknown option: $1" ;;
    *)
      if [ "$POSITIONAL" -eq 0 ]; then SUB="$1"; POSITIONAL=1
      elif [ "$POSITIONAL" -eq 1 ]; then ISSUE="$1"; POSITIONAL=2
      else envfail "unexpected argument: $1"
      fi
      shift ;;
  esac
done

[ -n "$SUB" ]   || envfail "usage: lean-gate.sh <entry|claim|mark|1..5|all|teardown|delta|verdict|progress|staleness> <issue>"
[ -n "$ISSUE" ] || envfail "usage: lean-gate.sh <entry|claim|mark|1..5|all|teardown|delta|verdict|progress|staleness> <issue>"

case "$SUB" in
  entry|claim|mark|1|2|3|4|5|all|teardown|delta|verdict|progress|staleness) : ;;
  *) envfail "unknown subcommand '$SUB' (expected entry|claim|mark|1..5|all|teardown|delta|verdict|progress|staleness)" ;;
esac

# Validated at parse time rather than inside cmd_progress, so a typo is a usage error before any
# root or config resolution — and so `--satisfied` on a subcommand that ignores it is still loud.
if [ -n "$PROGRESS_SATISFIED" ]; then
  [ "$SUB" = "progress" ] || envfail "--satisfied is only meaningful on 'progress', not '$SUB'."
  case "$PROGRESS_SATISFIED" in
    ''|*[!0-9]*) envfail "--satisfied takes a milestone number, got '$PROGRESS_SATISFIED'." ;;
  esac
fi

# #515, same shape and for the same reason: an unknown arm must be a usage error before any read
# happens, not a value that quietly selects neither arm and reports a clean run.
if [ -n "$STALENESS_ARM" ]; then
  [ "$SUB" = "staleness" ] || envfail "--arm is only meaningful on 'staleness', not '$SUB'."
  case "$STALENESS_ARM" in
    ticket|base|both) : ;;
    *) envfail "--arm takes ticket|base|both, got '$STALENESS_ARM'." ;;
  esac
fi
STALENESS_ARM="${STALENESS_ARM:-both}"

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

# #496 S4. ABSENT and UNPARSEABLE are two different facts and only one of them is legal. A config
# that is not there means "this consumer configured nothing", and every `cfg` default below is the
# documented answer. A config that IS there and does not parse means the operator's intent is
# unknown — and the defaults are not a neutral fallback: `.tracker.type` defaults to `github`, the
# arm that attests MORE than jira's, and a run that silently picks an arm from a typo is deciding
# policy by accident. Fail closed.
#
# UP FRONT AND OUTSIDE `cfg`, deliberately. `cfg` is invoked as `$(cfg …)`, where an `exit` kills
# the command substitution's subshell only: the caller reads an empty string and carries on. That
# is the same invisibility the sibling scheduler's resolve_pr avoids by counting in the caller —
# a refusal nobody can observe is not a refusal.
#
# `jq empty` rather than `jq -e .`: it reads the WHOLE input and asserts only that it parses,
# where `-e .` also gates on the last document's truthiness.
if [ -f "$CONFIG" ] && ! jq empty "$CONFIG" >/dev/null 2>&1; then
  envfail "config $CONFIG exists but is not parseable JSON — refusing to fall back to defaults, which would silently select tracker.type=github and every other shipped default. Fix the file (jq empty '$CONFIG' names the parse error) or point SECOND_SHIFT_CONFIG elsewhere."
fi

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
QUEUE_LABEL="$(cfg '.tracker.labels.queue' 'ready-for-dev')"
CLAIMED_LABEL="$(cfg '.tracker.labels.claimed' 'in-progress')"
HOST_Q='(.topology.repos | to_entries[] | select(.value.path==".") | .key)'
REPO_SLUG="$(cfg "$HOST_Q" 'acme')"
BASE_BRANCH="$(cfg "$HOST_Q as \$h | .topology.repos[\$h].baseBranch" 'main')"

# ---------------------------------------------------------------- the design axis (#394)
# HALF of the arming signal (D-8). The other half is the committed spec's `## Design` section,
# and the two are ANDed: a provider with no section is a milestone-1 red (arming is a per-ticket
# decision, never a default), while a section with no provider arms NOTHING — a consumer with no
# design axis may still document one, and a gate that armed on prose alone would demand a render
# harness from a repo that never configured one.
#
# Config is read here and NOWHERE at the merge boundary: CI never sees this file (it is
# gitignored on every consumer), which is why check-lean-chain.sh derives armed-ness from the
# committed spec alone. The two answers agree on every spec that can reach a merge, because a
# spec whose section is malformed never gets past milestone 1.
DESIGN_PROVIDER="$(cfg '.design.provider' '')"
LR_COMMAND="$(cfg '.design.liveRender.command' '')"
LR_CWD="$(cfg '.design.liveRender.cwd' '')"
LR_READY_PROBE="$(cfg '.design.liveRender.readyProbe' '')"

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

# A SECOND axis, deliberately (#440): whether an authenticated GitHub writer exists. The tracker
# answers "is there an issue to write to"; the bot answers "is there an identity to write as".
# Source control is GitHub under both adapters, so `cmd_mark` — which writes to the PR — keys on
# this and not on TRACKER_TYPE. Same tracker-derived default lean-evidence.sh applies, and for
# the same reason: a config declaring no bot at all meant "no writer" under jira, where the lint
# used to forbid the block, and meant nothing in particular under github, where the strict
# reading has always stood.
case "$TRACKER_TYPE" in
  jira) BOT_ENABLED="$(cfg '.tracker.bot.enabled' 'false')" ;;
  *)    BOT_ENABLED="$(cfg '.tracker.bot.enabled' 'true')" ;;
esac
case "$BOT_ENABLED" in
  true|false) : ;;
  *) envfail "unknown tracker.bot.enabled value '$BOT_ENABLED' — expected 'true' or 'false'." ;;
esac

# ---------------------------------------------------------------- the pinned name table
# ONE derivation, three consumers: this script, scripts/check-lean-chain.sh (running in CI
# with no access to any local convention), and lean-reconcile.sh. A name invented at any
# one of those sites instead of derived here is a drift the CI gate surfaces as a red merge
# boundary on every lean PR — see the plan's pinned-name-table section.

# The BRANCH. `<branchPrefix><key>`, the staged lane's formula verbatim (#413) — this lane no
# longer re-roots the configured prefix onto a `lean/` namespace of its own. The two lanes
# therefore SHARE one namespace, and nothing downstream may classify lean-vs-staged by branch
# name any more: that discriminator is the committed lean spec, resolved in lean-evidence.sh.
#
# The prefix itself comes from branch-prefix.sh, which is the one implementation of the
# resolution order (config, else the dominant prefix among remote branches, else refuse). The
# old `cfg '.tracker.branchPrefix' 'claude/acme-'` default is deliberately gone: it wrote the
# placeholder org slug into real branch names whenever a consumer had not set the key.
# shellcheck source=branch-prefix.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/branch-prefix.sh"
# Hoisted into a variable rather than inlined into the call below: the #442 worktree sweep asks
# branch-prefix.sh the inverse question with the same pattern, and two `cfg` reads of one key is
# how the two answers drift. NOT named `KEY_PATTERN` — that spelling is one of milestone 3's
# scrubbed seam variables (SEAM_SCRUB), and a local of the same name reads like the seam.
TRACKER_KEY_PATTERN="$(cfg '.tracker.keyPattern' '')"
BRANCH_PREFIX="$(resolve_branch_prefix \
  "$(cfg '.tracker.branchPrefix' '')" "$TRACKER_TYPE" "$TRACKER_KEY_PATTERN" "$MAIN_ROOT")" \
  || exit 2

# Under jira the key is lowercased in the branch name (tools/tracker/jira/README.md's `branch
# name` row); under github the key is digits and the transform is an identity. Applied to the
# KEY only, never to the prefix, which is used as configured.
case "$TRACKER_TYPE" in
  jira) BRANCH_KEY="$(printf '%s' "$ISSUE" | tr '[:upper:]' '[:lower:]')" ;;
  *)    BRANCH_KEY="$ISSUE" ;;
esac
LEAN_BRANCH="$BRANCH_PREFIX$BRANCH_KEY"

SPEC_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean.md"
VERDICT_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean-verdict.md"
# Same suffix check-lean-chain.sh's LEAN_INTENT_GAP_SUFFIX pins independently (it has no
# access to this derivation from CI) — milestone 1's pause-and-ask check (AC-8) is the first
# BUILD-side reader of this record.
INTENT_GAP_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean-intent-gap.md"
# The render manifest (#394). The suffix is `-lean-renders.md` and NOT `-lean.md` for a
# mechanical reason: check-lean-chain.sh scans the diff for the FIRST path ending in
# `-lean.md` and calls it the spec, so a name that also ended there would shadow the real
# spec on the boundary's artifact arm. Same reasoning that gave the verdict record its own
# suffix. check-lean-chain.sh pins this suffix independently — it cannot see this derivation.
RENDER_MANIFEST_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean-renders.md"
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
  entry|claim|mark)
    # ONLY the build-role subcommands may ESTABLISH the build identity. Seed-once above is
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
#
# Correct for every key the writer emits UNCONDITIONALLY, and only for those: the authentic
# value is written above the body, so it wins the first-match race against any prose below it.
# A key that can be absent has nothing entered in that race and must be read header-anchored
# instead — see `inherited_key`, which is the one key in this schema that needs it.
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

# The RENDER binding (#394): the same identity with the render manifest ALSO excluded, for the
# same self-reference reason the verdict record is excluded above — the manifest records this
# value, so a manifest inside the measurement could never agree with itself.
#
# The asymmetry with branch_patch_id is the design, not an oversight. The manifest stays INSIDE
# `reviewed_patch_id`, so committing render evidence moves the reviewed patch and the verdict
# binds to the evidence it was scored against; it stays OUTSIDE `rendered_from`, so committing
# that evidence — and, later, the reviewer committing the verdict on top of it — does not
# invalidate the render it just recorded. Without the second exclusion the first commit of the
# manifest would immediately make the manifest stale, and milestone 3 would re-render forever.
render_patch_id() { # render_patch_id <head-ish>
  local base id
  base="$(git -C "$REPO_ROOT" merge-base "origin/$BASE_BRANCH" "$1" 2>/dev/null)" || return 0
  [ -n "$base" ] || return 0
  id="$(git -C "$REPO_ROOT" diff "$base" "$1" -- . ":(exclude)$VERDICT_REL" ":(exclude)$RENDER_MANIFEST_REL" 2>/dev/null \
    | git -C "$REPO_ROOT" patch-id --stable 2>/dev/null | cut -d' ' -f1)"
  printf '%s' "$id"
}

# ---------------------------------------------------------------- the inheritance chain (#375)
# The same extraction record_key does, against a COMMITTED version of the record instead of the
# working-tree file. It is the only way to read a PRIOR round: the path holds one round at a
# time, so every round but the newest exists solely in `git log` on that path.
record_key_at() { # record_key_at <key> <commit>
  git -C "$REPO_ROOT" show "$2:$VERDICT_REL" 2>/dev/null \
    | grep -oE "$1:[[:space:]]*[A-Za-z0-9._-]+" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"
}

# LOCKSTEP-BEGIN lean-inherited-key
# Any key of the verdict record, read from its HEADER BLOCK only. Record on stdin; prints
# nothing when the key is absent from that block.
#
# HEADER-ANCHORED, unlike the first-match reads elsewhere in this schema, and the asymmetry is
# the whole point. First-match-anywhere is safe for a key the writer ALWAYS emits with a
# meaningful value, because the authentic value wins the race against any prose below it. It is
# NOT safe for a key that can be ABSENT — a chain root wrote no inheritance, records predating a
# key carry none — because a race has no winner when one side never entered it: the first match
# in the file is then whatever the reviewer's own findings contain. Review prose about these
# features quotes these keys, so the triggering round is every review of a PR that touches them,
# not a crafted one. The value lands where a CLAIM OF COVERAGE (or of design fidelity) is read,
# which is the inverse of the property those keys exist to prove.
#
# The writer's half of the same fix emits both optional keys unconditionally and makes absence a
# written fact; this half covers the records that writer did not produce — a pre-#375 root
# record still sitting on an in-flight branch, which every chain walk on that branch reads
# through, and every record written before `fidelity:` existed.
#
# PARAMETERIZED rather than duplicated (#394). `fidelity:` needs exactly this anchoring for
# exactly this reason, and a second awk program spelled the same way would be a second thing to
# keep in lockstep across all three readers — the drift these markers exist to prevent, forked
# in the act of preventing it.
#
# The header block is the first run of `key: value` / `verdict=` lines, ending at the blank line
# the writer emits before the body. A record whose keys are NOT in that shape (the earliest
# records wrote `verdict=` as a bullet or a table cell) never opens the block, so nothing is
# extracted and the round reads as a root — fail-closed, and correct: those records predate
# inheritance entirely.
header_key() { # header_key <key>   (record on stdin)
  awk -v k="$1" '
    /^[A-Za-z_][A-Za-z0-9_]*[:=]/ { hdr = 1 }
    hdr && /^[[:space:]]*$/ { exit }
    hdr && $0 ~ "^" k ":[[:space:]]*[A-Za-z0-9._-]+" {
      sub("^" k ":[[:space:]]*", "")
      sub(/[^A-Za-z0-9._-].*$/, "")
      printf "%s", $0
      exit
    }
  '
}

# `inherited_patch_id` with the `none` sentinel normalized to empty — the shape every chain
# reader wants. The sentinel lives HERE and not in header_key because it is inheritance's, not
# the schema's: `fidelity: none` is not a value, so a generic reader that swallowed `none` would
# be silently lenient about a key whose enum never contains it.
inherited_key() { # inherited_key   (record on stdin)
  local v
  v="$(header_key inherited_patch_id)"
  [ "$v" = "none" ] || printf '%s' "$v"
}
# LOCKSTEP-END lean-inherited-key

# The header-anchored read against a COMMITTED version of the record — what a chain walk needs,
# since every round but the newest exists solely in that path's git history.
inherited_key_at() { # inherited_key_at <commit>
  git -C "$REPO_ROOT" show "$1:$VERDICT_REL" 2>/dev/null | inherited_key
}

# The round this one inherits coverage FROM: the most recent COMMITTED version of the record
# whose reviewed patch DIFFERS from the tree being reviewed now.
#
# "Differs" is not a tidy-up — it is what makes a same-round re-run idempotent. review-lean
# re-runs a round on its cached identity, and at that point the newest committed record IS this
# round's own; without the clause it would inherit from itself, which every reader then refuses
# as a loop. A prior record predating `reviewed_patch_id` cannot be inherited from either: the
# round becomes a chain ROOT, which is the pre-#375 shape and stays readable everywhere.
#
# A candidate THIS ROUND ITSELF authored is skipped, and the search continues PAST it to the
# newest genuinely earlier round. The "differs" clause alone does not reach this: re-running a
# round after the branch moved leaves this round's own earlier record committed with a patch id
# that differs from the current tree, so it qualifies as a candidate on content while being the
# same review. The resulting link resolves for two of the three readers — milestone 4 and the
# merge boundary both count it and credit one more round than happened — while lean-reconcile.sh
# refuses it as a chain that is one review wearing two hats. Skipping it here is a fix at the
# writer, so no reader ever sees the shape the three of them disagree about.
#
# Continuing rather than degrading to a root is deliberate, and the safe direction either way:
# the round then inherits the last INDEPENDENT round, whose tree is older, so the delta it must
# read grows. Degrading would grow it further, to the whole diff — correct but needlessly
# expensive when a verifiable independent link is sitting one step further back.
#
# Both ids are compared because either alone is defeatable by the ordinary operation of the
# lane: review-lean provisions a fresh RUN_ID per round but a re-run of the SAME round reuses
# the cached one, while a session that outlives a round carries its id into the next.
#
# Prints "<patch-id> <commit>", or NOTHING when there is nothing to inherit.
inherit_candidate() { # inherit_candidate <this-round-patch-id> [this-run-id] [this-session-id]
  local cur="$1" run="${2:-}" sess="${3:-}" c p
  for c in $(git -C "$REPO_ROOT" log --format=%H -- "$VERDICT_REL" 2>/dev/null); do
    p="$(record_key_at reviewed_patch_id "$c")"
    [ -n "$p" ] || continue
    [ "$p" != "$cur" ] || continue
    if [ -n "$run" ] && [ "$(record_key_at run_id "$c")" = "$run" ]; then continue; fi
    if [ -n "$sess" ] && [ "$(record_key_at session_id "$c")" = "$sess" ]; then continue; fi
    printf '%s %s' "$p" "$c"
    return 0
  done
}

# The tail of a newest-first commit list, strictly after <marker>. An absent marker yields the
# EMPTY list, never the whole one: the callers use this to bound a search, and a marker they
# could not find must narrow the search to nothing rather than silently widen it to everything.
versions_after() { # versions_after <newline-separated-commits> <marker>
  local out="" c past=0
  for c in $1; do
    if [ "$past" -eq 1 ]; then out="$out $c"; continue; fi
    [ "$c" = "$2" ] && past=1
  done
  printf '%s' "$out"
}

# Walks the declared chain, matching each `inherited_patch_id` against an earlier record's
# `reviewed_patch_id`. Prints exactly one line: `ok <links>` when the chain verifies — INCLUDING
# the ordinary case of no inheritance at all, which is `ok 0` — or `break <diagnostic>` naming
# the round that broke it. Never exits: each caller phrases its own refusal, and the writer
# degrades rather than refusing.
#
# The COUNT is reported rather than merely tallied, and milestone 4 puts it in its pass line, for
# the same reason that line already names the freshness arm it gated on: with inheritance, "this
# head was reviewed" means "a chain of N verified rounds covered it", and an operator reading a
# checkmark should be able to see which claim was checked. It is also what makes the window below
# MEASURABLE from outside — see the next paragraph.
#
# The search window starts strictly BELOW <declaring-commit> and shrinks past each hit, so the
# chain must run STRICTLY BACKWARDS through the record's history. That keeps a branch reverted to
# a previously-reviewed tree readable: the current round's record then carries an identity an
# ancestor also carries, and an unbounded search resolves that round to ITSELF, counting the
# record under test as a link in its own chain. Shrinking also makes termination structural, so
# there is no cycle counter to get wrong (and none sitting in the code that no fixture can red).
#
# <declaring-commit> is EMPTY at write time, because the record being written is not committed
# yet and so cannot appear in the history being searched. Read-side callers pass it.
chain_walk() { # chain_walk <inherited-patch-id> <declaring-round> [declaring-commit]
  local want="$1" round="${2:-?}" from="${3:-}" versions c hit rest links=0
  versions="$(git -C "$REPO_ROOT" log --format=%H -- "$VERDICT_REL" 2>/dev/null)"
  [ -z "$from" ] || versions="$(versions_after "$versions" "$from")"
  while [ -n "$want" ]; do
    hit=""; rest=""
    for c in $versions; do
      if [ -n "$hit" ]; then rest="$rest $c"; continue; fi
      if [ "$(record_key_at reviewed_patch_id "$c")" = "$want" ]; then hit="$c"; fi
    done
    if [ -z "$hit" ]; then
      echo "break round $round declares inherited_patch_id $(printf '%.12s' "$want"), which matches no earlier verdict record committed on this branch — that round's inherited coverage is unverifiable, so nothing attests the part of the diff it did not read."
      return 0
    fi
    versions="$rest"
    links=$((links + 1))
    round="$(record_key_at rounds "$hit")"; [ -n "$round" ] || round='?'
    want="$(inherited_key_at "$hit")"
  done
  echo "ok $links"
  return 0
}

# ---------------------------------------------------------------- progress-file primitives
# Append-only markdown. Line shapes are PINNED — check-lean-chain.sh does not read this
# file (it is gitignored and never reaches CI), but lean-reconcile.sh does, and the
# fix-budget counter is derived from it.
#
#   <iso> | entry | ledger=<path> | lines=<n> | telemetry=<off|nocoll|on> | session=<id>
#   <iso> | session | <id>
#   <iso> | milestone-<n> | attempt | <reason>
#   <iso> | milestone-<n> | absent | <reason>            # #494 — NOT a fix attempt
#   <iso> | milestone-<n> | absent-exhausted | <n> calls
#   <iso> | milestone-<n> | started |                    # #497 — an evaluation BEGAN
#   <iso> | milestone-<n> | concluded | rc=<n>           # #497 — and returned. NOT idempotent
#   <iso> | milestone-<n> | interrupted-exhausted | <n> unconcluded
#   <iso> | milestone-<n> | satisfied
#   milestone-4 | verdict=<approve|needs-work> | round=<n>
#
# The `session` row is the BUILD-SESSION SET (#446) — see below. It deliberately spells the id
# WITHOUT a `session_id:` key: `record_key` here and `extract_key` in lean-reconcile.sh both
# take the FIRST match of that key in the file, and the header must keep winning that race.
#
# Reconciliation keys (AC-14) ride in the header so a run predating #292's general
# verifier stays reconcilable after it lands.
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# The header is written ONCE, at creation, and was never revisited — which is how #322's
# `run_id: unset` freeze happened, and why its remedy was to stop `entry` from being the
# creator. #416 cannot keep that remedy: the attestation row has to exist before `claim`, the
# first subcommand the precondition guards, so `entry` creates the file again — and SKILL.md
# orders it BEFORE the RUN_ID export, so on an ordinary run the header IS stamped `unset`.
# Heal the field rather than arguing about which subcommand may create the record.
#
# Left unhealed this is not cosmetic. lean-reconcile.sh's arm (1) compares the bot claim
# comment's run_id against this header's, so an honest github run reds at the merge boundary
# with the real id on one side and `unset` on the other.
#
# The ONE behavioral guard is the cache compare, and the BUILD CACHE is the authority — not
# $RESOLVED_RUN_ID alone. Only `entry` and `claim` persist there, and arm (1) compares this
# header against what `claim` wrote, so the header must carry the ESTABLISHED identity and no
# other: a milestone call made with an ad-hoc RUN_ID resolves one for its own records and leaves
# the header alone. It is also what keeps the review role out — a review identity is never in
# the build cache (P10), so `verdict` could not stamp itself here even if it grew a write into
# this file, which today it has not.
#
# Matching the literal `unset` is a narrowing, not a second guard: the cache compare already
# makes a rewrite of an established id a no-op (it can only ever write the value that is
# already there), so no fixture can red on that half alone. Do not read a surviving mutant on
# the two lines below as a coverage hole — the placeholder check is there to keep an already
# healed run from spawning awk on every append, which is cost, not correctness.
heal_progress_run_id() {
  [ -f "$PROGRESS_FILE" ] || return 0
  [ "$RESOLVED_RUN_ID" != "unset" ] || return 0
  [ "$(cat "$RUN_ID_CACHE" 2>/dev/null)" = "$RESOLVED_RUN_ID" ] || return 0
  [ "$(count_matches '^run_id: unset$' "$PROGRESS_FILE")" -gt 0 ] || return 0
  local tmp="$PROGRESS_FILE.heal"
  # awk with an EXACT string compare, not sed: the id is operator-supplied, and a
  # replacement-side metacharacter in a sed program would be interpreted. The compare also
  # bounds the rewrite to the header — every appended line carries the pinned
  # `<iso> | <kind> | …` shape, so no body line can equal this literal.
  awk -v id="$RESOLVED_RUN_ID" '
    $0 == "run_id: unset" { print "run_id: " id; next }
    { print }
  ' "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE" || rm -f "$tmp"
}

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
      echo "branch_prefix: $BRANCH_PREFIX"
      # The COMPOSED name, not only its prefix (#413). A reader that rebuilt it as
      # `<branch_prefix><issue>` would be right under github and wrong under jira, where the
      # key is lowercased — pipeline-retro's PR lookup is exactly such a reader.
      echo "branch: $LEAN_BRANCH"
      echo "spec: $SPEC_REL"
      echo "verdict_record: $VERDICT_REL"
      # #347: a corpus-aggregation key, not a new artifact — read once, here, at record
      # creation. No env var carries the session's own model identity today, so this is
      # opt-in: absent, retro-corpus.sh reads it as "unknown", a label, not an error.
      echo "model: ${LEAN_RUN_MODEL:-unknown}"
      echo ""
    } > "$PROGRESS_FILE"
  fi
  heal_progress_run_id
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

# #494: the absent-artifact counterpart. A distinct verb, not a distinct suffix on `attempt` —
# attempt_count() greps the fixed string `| milestone-N | attempt |`, so anything carrying that
# substring is still fix budget however it is spelled.
append_absent() { append_line "$(now_iso) | milestone-$1 | absent | $2"; }

# D-41: a passing evaluation appends AT MOST ONE `satisfied` line per milestone, so
# diagnostic re-runs and `all` sweeps never inflate anything. Idempotent by construction.
append_satisfied() {
  ensure_progress_file
  if [ "$(count_matches "| milestone-$1 | satisfied" "$PROGRESS_FILE" -F)" -eq 0 ]; then
    append_line "$(now_iso) | milestone-$1 | satisfied"
  fi
}

attempt_count() { count_matches "| milestone-$1 | attempt |" "$PROGRESS_FILE" -F; }

# #494. The absent-artifact counterpart. Its line shape deliberately does NOT contain the
# `| milestone-N | attempt |` substring attempt_count() greps — the same technique the
# `| milestone-3 | armed |` record already uses — so an evaluation that reds only because the
# artifact is not written yet cannot consume fix budget.
#
# The `absent-exhausted` line below is likewise invisible HERE: the pattern requires " absent |",
# and the exhaustion line reads " absent-exhausted |", so exhaustion never re-counts itself.
# Its name is also load-bearing in the other direction — `absent-budget-exhausted` would contain
# the `budget-exhausted` substring the fix budget's own exhaustion assertion counts, and would
# silently inflate it.
absent_count() { count_matches "| milestone-$1 | absent |" "$PROGRESS_FILE" -F; }

# #497. THE IN-FLIGHT PAIR. Every other row above is written after an evaluation RETURNS, so a
# gate process killed mid-run leaves a record byte-identical to one where the milestone was never
# invoked — and `bash G all`, the resuming session and the retro corpus all read the second.
#
# WHY TWO VERBS AND NOT ONE. The issue's own sketch closes a `started` row with the concluding
# `attempt`/`satisfied` line. That is unsound HERE: append_satisfied is idempotent by construction
# (D-41 above), so re-evaluating an already-satisfied milestone appends no closing line at all —
# and CLAUDE.md mandates exactly such a re-run (`bash G all`) before build-lean's close-out step.
# Every honest run would end its record looking interrupted. So the conclusion is its own,
# deliberately NON-idempotent verb.
#
# WHY THE PAYLOAD IS `rc=<n>`. `| milestone-3 | concluded | satisfied` would be safe against
# today's readers — each anchors `| milestone-N | ` immediately before its verb — but it puts the
# literal `satisfied` on a bookkeeping line, which is the trap absent_count's note above records.
# `rc=<n>` cannot collide, and it carries #496's class taxonomy into the record for free.
#
# NEITHER VERB IS IN progress_token's ROW SET, on purpose — see the D-3 note there.
append_started()   { append_line "$(now_iso) | milestone-$1 | started |"; }
append_concluded() { append_line "$(now_iso) | milestone-$1 | concluded | rc=$2"; }

# D-11. The predicate is a DIFFERENCE, not a flag. Both rows are append-only and nothing rewrites
# them, so `started` minus `concluded` for one milestone is exactly the cumulative number of
# evaluations that began and never returned — progress_token's soundness argument below ("the
# selected count cannot go up and back down within a spawn") extends to them unchanged.
#
# Both patterns carry the TRAILING separator, for absent_count's reason in the other direction:
# `| milestone-N | started` alone would also count a future `started-…` verb, and
# `interrupted-exhausted` must never be countable as either half of this pair.
unclosed_count() { # unclosed_count <milestone>
  local started concluded
  started="$(count_matches "| milestone-$1 | started |" "$PROGRESS_FILE" -F)"
  concluded="$(count_matches "| milestone-$1 | concluded |" "$PROGRESS_FILE" -F)"
  echo $((started - concluded))
}

# ---------------------------------------------------------------- the build-session SET (#446)
# `mark` stamps a session id onto the PR marker, and that field is the STRONGER of the two
# comparisons lean-evidence.sh's arm_identity makes: run_id is agent-CHOSEN, the session id is
# harness-assigned. It was nonetheless read straight from the ambient environment while
# $RESOLVED_RUN_ID beside it came from the role-keyed cache — so the documented manual recovery,
# run from the REVIEW session (the only place a missing marker becomes visible, since the arm is
# unmasked by the verdict-record push), stamped the review session as the build session and the
# boundary reported an honest, independent review as a P10 self-review.
#
# WHY A SET RATHER THAN A LOOKUP. Resolving the id from the progress HEADER — the issue's first
# suggested direction — would re-open a deliberately closed hole: the header is seed-once and
# single-valued, so a second build session on the same PR (the case cmd_mark's D-4 idempotence
# exists for) would carry session 1's id on its own marker, and nothing checks that at session
# level. So `mark` keeps writing the AMBIENT id, which is correct on every honest path including
# that second session, and instead REFUSES when the ambient session is not a recorded build
# session. A refusal is recoverable; a mis-stamped marker is not — it survives a re-run (the
# idempotence guard keys on run_id alone) and survives a corrective second marker (the boundary
# compares against EVERY marker), leaving only "delete bot-authored evidence and hand-supply an
# identity string", which is the posture the P10 arms exist to remove.
#
# THE SET IS header ∪ rows. The header is already the build identity by cmd_verdict's compare,
# so including it is the definition rather than a compatibility shim — and it is what keeps a run
# already in flight when this lands, whose file has no session rows yet, from stranding at `mark`.
#
# 'unset' and the empty string are NOT members. cmd_mark's compare would otherwise pass an unset
# ambient session against an unset recorded one — two unverifiable values agreeing — and write
# `session_id: unset` onto the marker. "Unverifiable" must never resolve to "fine".
build_session_set() { # one build session id per line, deduped; never empty, never 'unset'
  local hdr
  [ -f "$PROGRESS_FILE" ] || return 0
  # The header via record_key, NOT a second extraction: two readers of one schema that disagreed
  # about what a key looks like would be a silent divergence, not a loud one.
  hdr="$(record_key session_id "$PROGRESS_FILE")"
  {
    [ -n "$hdr" ] && printf '%s\n' "$hdr"
    sed -n 's/^.*| session | \([A-Za-z0-9._-][A-Za-z0-9._-]*\)[[:space:]]*$/\1/p' "$PROGRESS_FILE"
  } | awk '$0 != "" && $0 != "unset" && !seen[$0]++'
  return 0
}

session_in_build_set() { # session_in_build_set <session-id>
  local want="$1" have
  [ -n "$want" ] || return 1
  [ "$want" != "unset" ] || return 1
  for have in $(build_session_set); do
    [ "$have" = "$want" ] && return 0
  done
  return 1
}

# ONLY `entry` and `claim` call this — the same arm that may ESTABLISH the build run id, for the
# reason stated there: "an EVALUATION must be able to read an identity, never to establish one".
# `mark` is a pure reader, or the guard would whitelist itself and be vacuous; `1..5`, `all`,
# `delta` and `verdict` record nothing, which is what keeps a review session running
# `bash G 4 <issue>` from whitelisting itself through a milestone call.
#
# Its presence test is the SESSION's own, deliberately not cmd_entry's per-RUN attestation row:
# that row short-circuits on `entry_row_present`, so a second build session running the
# idempotent `entry` would record no session at all and then be refused at `mark`.
record_build_session() {
  local sid
  sid="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$sid" ] || return 0
  ensure_progress_file
  if ! session_in_build_set "$sid"; then
    append_line "$(now_iso) | session | $sid"
  fi
  return 0
}

# A failed milestone: record the attempt, then decide retry-vs-hard-stop.
#
# THE OBSERVE SEAM (#374 AC-1..3, promoted by #496). `LEAN_GATE_OBSERVE=1` calls a milestone body
# to learn whether it would fail WITHOUT recording anything — no attempt line, no budget consumed,
# no `satisfied` line. Recording stays the real 1..5 loop's job; a pre-pass that recorded would
# double-count every attempt it shares with the real call further down the same `all` sweep.
#
# It was `PRECHECK`, an ambient internal, and it returned a flat 1 before the budget compare — so
# it SWALLOWED rc=4. That was harmless while cmd_all was its only caller (the real loop below
# re-derives the 4). It is not harmless now the scheduler reads a verdict through it: "this
# milestone is spent" and "this milestone failed once" are the two states a scheduler must not
# confuse. So observe mode reports exhaustion as its own value, predicted from the count already
# on file — `count >= FIX_BUDGET` is exactly the condition under which the recording path's
# post-append `count > FIX_BUDGET` would fire.
#
# THE CLASS (#496 S1). $3 is the exit code a red returns, defaulting to 1 — the historical value,
# so every milestone that does not classify is unchanged. Milestone 4 passes one at all twenty of
# its sites; see cmd_4. Budget exhaustion OUTRANKS the class in both paths: 4 keeps its exact prior
# meaning, and the alternative (a class-6 red suppressing a spent budget) would trade one
# misreport for another. Nothing loops on it — the scheduler never retries a 6 at all.
fail_milestone() {
  local n="$1" reason="$2" class="${3:-1}" count
  if [ "${LEAN_GATE_OBSERVE:-0}" = "1" ]; then
    count="$(attempt_count "$n")"
    warn "✗ milestone-$n (observe): $reason"
    [ "$count" -ge "$FIX_BUDGET" ] && return 4
    return "$class"
  fi
  append_attempt "$n" "$reason"
  count="$(attempt_count "$n")"
  warn "✗ milestone-$n: $reason (attempt $count/$FIX_BUDGET)"
  if [ "$count" -gt "$FIX_BUDGET" ]; then
    append_line "$(now_iso) | milestone-$n | budget-exhausted | $count attempts"
    warn "milestone-$n has exhausted its $FIX_BUDGET-attempt fix budget — hard stop."
    return 4
  fi
  return "$class"
}

# #494 D-1. A milestone that reds because its artifact IS NOT WRITTEN YET — not because a fix
# did not work. `build-lean` step 3 orders `bash G 1 <issue>` to learn the path step 4 must write
# to, so the first such red is the contract's own recommended move; charging it to a 3-attempt
# fix budget made the bound tightest on exactly the runs that later need it most, and made
# `attempt` lines unreadable as a difficulty signal for the retro corpus.
#
# WHY A SECOND COUNTER RATHER THAN FREE. Making absence cost nothing removes the only thing
# bounding a session that loops on step 3 forever. So absence is bounded, just on its own much
# larger budget (D-2) — and it reuses `rc=4` rather than inventing a code, so build-lean's
# existing hard-stop handling (append the reason, one abort comment, keep the worktree and the
# claim) covers it with no new operator path.
#
# WRITTEN GENERICALLY, APPLIED AT ONE SITE (D-7). Milestone 4's `[ -f "$rec" ]` carries the same
# shape, but this ticket scopes milestones 2-5 out: widening it would flip selftest case (c1),
# which drives milestone 4's absence and whose staying green is the evidence the scoping held.
block_milestone() {
  local n="$1" reason="$2" count
  if [ "${LEAN_GATE_OBSERVE:-0}" = "1" ]; then
    count="$(absent_count "$n")"
    warn "✗ milestone-$n (observe): $reason"
    [ "$count" -ge "$ABSENT_BUDGET" ] && return 4
    return 1
  fi
  append_absent "$n" "$reason"
  count="$(absent_count "$n")"
  warn "✗ milestone-$n: $reason (absent $count/$ABSENT_BUDGET — not a fix attempt)"
  if [ "$count" -gt "$ABSENT_BUDGET" ]; then
    append_line "$(now_iso) | milestone-$n | absent-exhausted | $count calls"
    warn "milestone-$n has been evaluated $count times against an artifact that was never written — hard stop."
    return 4
  fi
  return 1
}

pass_milestone() {
  if [ "${LEAN_GATE_OBSERVE:-0}" = "1" ]; then
    say "✓ milestone-$1 (observe)${2:+: $2}"
    return 0
  fi
  append_satisfied "$1"; say "✓ milestone-$1${2:+: $2}"; return 0
}

# ---------------------------------------------------------------- entry precondition
# AC-14. The predicate is a NON-EMPTY ledger file for THIS session, anchored at the main
# checkout. Directory existence is explicitly NOT the test — an empty or absent per-session
# file means the hook never fired, and a run whose tool calls left no ledger cannot be
# reconciled by lean-reconcile.sh (or by #292 later). Fail closed.
#
# #416: fail-closed was never the gap. NOTHING ENFORCED THAT THIS RAN. `entry` appeared here
# and at its dispatch arm and nowhere else, and it wrote nothing durable — so a run that simply
# skipped step 1 reached five green milestones, a verdict record and a merged PR, with no
# artifact recording the omission. Two such runs are what surfaced this. The row below is that
# artifact, and require_entry_attested() is what makes skipping step 1 a refusal.
ENTRY_ROW_MARKER="| entry | ledger="

entry_row_present() { [ "$(count_matches "$ENTRY_ROW_MARKER" "$PROGRESS_FILE" -F)" -gt 0 ]; }

# D-9, ENRICHMENT ONLY. `audit-toolkit` off and "the ledger is missing" are one operator action
# apart and read identically today, so the refusal below picks its wording from the settings
# files — best-effort, and never a second authority over the verdict: the ledger predicate stays
# the sole decider, and an absent, unreadable or jq-less settings read just yields the generic
# message. Matched on the plugin NAME, not `name@marketplace`, so a consumer whose marketplace is
# vendored under another name still gets the specific wording.
audit_toolkit_opted_out() {
  local root f
  for root in "$REPO_ROOT" "$MAIN_ROOT"; do
    for f in "$root/.claude/settings.json" "$root/.claude/settings.local.json"; do
      [ -f "$f" ] || continue
      jq -e '(.enabledPlugins // {}) | to_entries
             | map(select((.key | startswith("audit-toolkit@")) and .value == false)) | length > 0' \
        "$f" >/dev/null 2>&1 && return 0
    done
  done
  return 1
}

# AC-1/AC-3 (#432). Cost attribution is decided at minute zero and discovered at the end: a
# session launched without CLAUDE_CODE_ENABLE_TELEMETRY exports nothing, and step 7's cost block
# is empty with no way to recover it afterwards. This gate is a bash child of the `claude`
# process, so its OWN inherited environment IS the export decision the run never had — the exact
# discriminator the failing run lacked.
#
# WARN, never refuse (D-1/D-3). The audit-ledger precedent above does not transfer: the ledger is
# CONSUMED downstream (lean-reconcile.sh reads it; check-lean-chain.sh gates the merge on the
# chain it anchors), whereas nothing consumes cost — no milestone, no verdict arm, no
# merge-boundary check. cost-tracking-setup.md declares the feature "Opt-in, local, experimental.
# The dev-pipeline works fine without this", so refusing here would promote an optional feature to
# a hard precondition for every consumer, including those with no collector installed.
#
# Three states: `off` (the variable is not enabling telemetry), `nocoll` (it is, but nothing
# accepts on a loopback OTLP endpoint), `on` (it is, and either the probe connected or the probe
# was skipped).
telemetry_env_on() {
  case "${CLAUDE_CODE_ENABLE_TELEMETRY:-}" in
    ""|0|false|FALSE|False) return 1 ;;
    *) return 0 ;;
  esac
}

# OR-1. Echo `<host> <port>` for an endpoint worth probing, or nothing when the reachability half
# must be SKIPPED. Skipping is not a fallback here, it is the correct answer: a warning that fires
# on a working remote collector trains the operator to ignore it, which costs more than the
# missing signal. Restricting to loopback is also what keeps the /dev/tcp connect below unable to
# hang — a refused loopback connect returns immediately, a filtered remote one would not.
#
# Unset falls back to the documented default; `http://<loopback>[:port]` with no path is probed;
# https, a path-bearing URL, a non-loopback host and anything unparseable all yield nothing.
telemetry_probe_target() {
  local ep="${OTEL_EXPORTER_OTLP_ENDPOINT:-}" host port rest
  [ -n "$ep" ] || { echo "127.0.0.1 4317"; return 0; }
  case "$ep" in
    http://*) rest="${ep#http://}" ;;
    *) return 0 ;;
  esac
  # A trailing slash is the only path we accept; anything else names a gateway, not the
  # documented local collector.
  rest="${rest%/}"
  case "$rest" in */*) return 0 ;; esac
  host="${rest%%:*}"
  port="${rest#*:}"
  [ "$port" = "$rest" ] && port="4317"
  case "$host" in
    localhost|127.0.0.1|'[::1]'|::1) : ;;
    *) return 0 ;;
  esac
  case "$port" in ''|*[!0-9]*) return 0 ;; esac
  echo "${host} ${port}"
}

telemetry_state() {
  local target host port
  telemetry_env_on || { echo "off"; return 0; }
  target="$(telemetry_probe_target)"
  [ -n "$target" ] || { echo "on"; return 0; }
  host="${target%% *}"; port="${target##* }"
  host="${host#[}"; host="${host%]}"
  if (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; then echo "on"; else echo "nocoll"; fi
}

# ---------------------------------------------------------------- worktree teardown (#442)
# The lane created a worktree per run and never removed one, so a checkout accumulated a stale
# directory per finished ticket. The cost is not disk: `git checkout <branch>` in the main
# checkout then fails with "already used by worktree at ..." for branches whose work landed
# weeks earlier, and the only fix was a human noticing.
#
# TWO ENTRY POINTS, ONE REMOVAL. `teardown` fires at approval (checklist step 9); the sweep below
# covers the exits approval never reaches — the session died, a human merged the PR with no lean
# round, the run was abandoned. Neither suffices alone: of five stale worktrees found on a live
# consumer checkout, most were the second kind. Both funnel through worktree_destroy(), so a
# worktree can only be destroyed on terms the other path would also accept.
#
# WHAT IS NEVER DONE HERE: `git branch -d/-D`. The PR points at the branch and the verdict record
# is committed on it, so removing the CHECKOUT is correct and deleting the REF is not. `git
# worktree remove` already leaves the branch alone; said out loud so a later edit does not
# "helpfully" add the delete.

# `<path>\t<branch>` for every registered worktree that has a branch checked out. --porcelain is
# the only parseable form — the human listing pads columns with spaces and brackets the branch,
# so it breaks on any path containing one. Detached and bare entries emit no `branch` line and
# are therefore skipped, which is right: neither is a lane worktree.
lean_worktrees() {
  git -C "$MAIN_ROOT" worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { p = substr($0, 10); next }
    /^branch /   { b = substr($0, 8); sub(/^refs\/heads\//, "", b);
                   if (p != "") { print p "\t" b }; p = "" }
  '
}

lean_worktree_for_branch() { # lean_worktree_for_branch <branch> -> its path, or nothing
  local p b
  while IFS="$(printf '\t')" read -r p b; do
    [ -n "$b" ] || continue
    [ "$b" = "$1" ] || continue
    printf '%s\n' "$p"
    return 0
  done <<EOF
$(lean_worktrees)
EOF
  return 1
}

# The DECLINE path, and the only one either mechanism has. It prints rather than fails (D-6):
# the run is complete and a leftover directory is hygiene, not evidence, so a refusal must not
# red a gate or an `entry` that is otherwise ready to start the next run. The manual command is
# printed in full because it IS the whole remedy.
worktree_keep() { # worktree_keep <path> <reason> [<detail>]
  warn "  keeping $1 — $2."
  if [ -n "${3:-}" ]; then printf '%s\n' "$3" | sed 's/^/[lean-gate]     /' >&2; fi
  warn "  remove it by hand once that is resolved: git -C '$MAIN_ROOT' worktree remove '$1'"
}

# The preconditions and the removal. 0 = the worktree is gone, 1 = it was deliberately kept.
#
# PUSHED-NESS IS "origin/<branch>..HEAD is empty", NOT the issue's proposed `HEAD =
# origin/<branch>`. Once the review session pushes its verdict record the build worktree is
# legitimately BEHIND origin, and strict equality would refuse exactly the removal this exists
# for. Behind is safe; ahead is not.
#
# Gitignored files do not block `git worktree remove`, so the run's render PNGs under
# `.claude/lean-renders/<issue>/` go with it — safe, because milestone 4 depends on the render id
# alone once the verdict lands, never on the PNG bytes.
worktree_destroy() { # worktree_destroy <path> <branch>
  local wt="$1" br="$2" dirty unpushed out
  if [ "$wt" = "$MAIN_ROOT" ]; then
    worktree_keep "$wt" "it is the main checkout, not a lane worktree"
    return 1
  fi
  dirty="$(git -C "$wt" status --porcelain 2>&1)" \
    || { worktree_keep "$wt" "its status could not be read ($dirty)"; return 1; }
  if [ -n "$dirty" ]; then
    worktree_keep "$wt" "its tree is not clean" "$dirty"
    return 1
  fi
  # Best effort, and wrong only ever in the SAFE direction: a fetch that fails leaves a stale
  # remote-tracking ref, which can make pushed work look unpushed and KEEP the worktree, never
  # the reverse.
  git -C "$wt" fetch --quiet origin "$br" >/dev/null 2>&1
  unpushed="$(git -C "$wt" log --oneline "refs/remotes/origin/$br..HEAD" 2>&1)" \
    || { worktree_keep "$wt" "origin/$br is unresolvable, so nothing proves its work is pushed"; return 1; }
  if [ -n "$unpushed" ]; then
    worktree_keep "$wt" "it carries commits that are not on origin/$br" "$unpushed"
    return 1
  fi
  out="$(git -C "$MAIN_ROOT" worktree remove "$wt" 2>&1)" \
    || { worktree_keep "$wt" "git refused to remove it ($out)"; return 1; }
  say "  removed $wt (branch $br kept — the PR points at it)"
  return 0
}

# Checklist step 9's final act. OUTSIDE the 1..5 progression on purpose (D-2): `cmd_all` runs
# milestones 1-5 and the checklist mandates it BEFORE step 9, so a self-removing milestone 5
# would delete the worktree mid-run, before the closing comment is even posted.
#
# NOT in require_entry_attested's set, unlike every other build-role subcommand: this asserts
# nothing and records nothing, so refusing it for a missing attestation would block cleanup for
# no evidentiary gain. What guards the removal is worktree_destroy()'s preconditions, which are
# stronger and independent of any record the run wrote about itself.
cmd_teardown() {
  local wt
  wt="$(lean_worktree_for_branch "$LEAN_BRANCH")" || wt=""
  if [ -z "$wt" ]; then
    say "teardown: no registered worktree is on $LEAN_BRANCH — nothing to remove."
    return 0
  fi
  say "teardown: $LEAN_BRANCH"
  worktree_destroy "$wt" "$LEAN_BRANCH"
  # ALWAYS 0, whichever way that went. A kept worktree has already reported itself, and a
  # non-zero exit on the last command of a finished run reads as "the run failed" over a
  # directory nobody needs.
  return 0
}

# ---------------------------------------------------------------- the CONTINUATION PREDICATE
# #492. `claude -p` exits 0 whenever the model ends its turn cleanly, which is "the model stopped
# talking", not "the block finished" — so a scheduler reading the spawn's exit status cannot tell
# a finished build from one that stopped two milestones early with every artifact on disk. This
# subcommand is the artifact it reads instead (AC-5): one opaque token over the progress rows that
# mean THE BUILD ROLE ADVANCED. The caller compares the token across a spawn and interprets
# nothing, which is what keeps orchestrate-lean.sh's "gate exit codes and tracker state, nothing
# else" boundary intact while it gains a third thing to know.
#
# WHY THESE TWO ROW KINDS AND NO OTHERS (D-1). `satisfied` and `attempt` are the only rows a
# milestone EVALUATION writes, so they are exactly "the build role did something that counts".
# The bookkeeping rows must stay out, and one of them is load-bearing: record_build_session
# appends `| session | <id>` on every fresh session's `entry` call — deliberately, even when
# `entry` short-circuits — so a naive "did the file change" predicate would be TRUE for any spawn
# that reached checklist step 1, and the no-progress case AC-3 protects would be unreachable.
#
# #497 D-3 KEEPS THE SET AT EXACTLY THOSE TWO. `started`/`concluded` are written on EVERY
# continuation, so counting them would make each dead spawn of a background-and-exit session read
# as advancement and burn the whole `--max-continuations` budget re-proving the same thing. Today
# that pattern costs exactly one continuation: spawn 2 re-runs the milestones, hits
# append_satisfied's idempotence, moves nothing, and the scheduler correctly stops. The in-flight
# pair is a record for the resuming SESSION, never a signal to the orchestrator.
#
# WHY A COUNT IS A SOUND TOKEN. These rows are append-only: append_attempt and append_satisfied
# only ever add, and the single rewriter in this file (heal_progress_run_id) has an exact-string
# compare bounded to the header. So the selected count cannot go up and back down within a spawn
# and read as unchanged. It is printed behind a generation prefix rather than bare precisely
# because it is a number a caller must NOT order: `progress-v1:` marks the token space, so a
# future change of predicate is visibly a different token rather than a silently comparable
# integer, and a caller reaching for `-gt` has to notice it is not one.
#
# NOT in require_entry_attested's set (D-2), for a sharper reason than teardown's: this reads the
# very file an attestation would live in, so gating it on that attestation would make the
# predicate unavailable in exactly the state — a spawn that died before `entry` — the scheduler
# most needs an answer about.
progress_token() { # progress_token [<milestone>] — prints the token, never touches the file
  local pat n
  if [ -n "${1:-}" ]; then
    # D-8: milestone n's `satisfied` row ALONE. `attempt` is excluded here on purpose — a
    # close-out that redded milestone 5 advanced the record but did not finish the checklist,
    # and crediting it would be the exact false `done` this ticket exists to remove.
    pat="| milestone-$1 | satisfied"
  else
    pat="| milestone-"
  fi
  # ensure_progress_file is deliberately NOT called: this subcommand must not bring into
  # existence the artifact whose absence is itself the answer. count_matches already answers 0
  # for a missing file.
  if [ -n "${1:-}" ]; then
    n="$(count_matches "$pat" "$PROGRESS_FILE" -F)"
  else
    # One pass, both kinds. -E over two -F greps so the row set is defined in one expression:
    # the `| milestone-<n> | ` stem followed by either verb, end-anchored for `satisfied` and
    # carrying the trailing separator for `attempt`, so neither a `budget-exhausted` row nor a
    # reason string mentioning either word can inflate the count.
    #
    # `[|]` and not `\|`: an escaped pipe inside an ERE is a GNU extension that POSIX leaves
    # undefined, and this file has a macOS/BSD lane. A bracket expression means the same literal
    # to both, where `\|` is exactly the class of dual form that fails dirty rather than loudly.
    n="$(count_matches '[|] milestone-[0-9][0-9]* [|] (satisfied$|attempt [|])' "$PROGRESS_FILE" -E)"
  fi
  printf 'progress-v1:%s\n' "$n"
}

cmd_progress() {
  progress_token "$PROGRESS_SATISFIED"
  return 0
}

# ---------------------------------------------------------------- the STALENESS PREDICATE (#515)
# The lane reads tracker and base state once, at preflight, and never again — so a run whose
# premise expired mid-flight keeps spending continuations against a base that already carries its
# fix. Measured on this repo: the branch for one ticket kept working for 30 minutes after another
# PR landed the same fix, and the ticket itself was not closed until 63 minutes after that.
#
# TWO ARMS, and the weaker one is the one everybody reaches for first. A ticket closing records a
# HUMAN NOTICING, not the event — in the motivating incident it lagged the merge by an hour, so an
# arm that reads only tracker state catches nothing in real time. It is still worth reading,
# because a launch onto an already-closed ticket should not spend a run at all, but the leading
# signal is the base: main had moved into the very files the branch was editing.
#
# WHY FILE OVERLAP AND NOT "THE BASE ADVANCED" (D-1). Measured here: 178 first-parent merges in 21
# days, ~9.4/day, one every ~1.5 working hours. Bare advancement is therefore true on essentially
# every multi-hour run, and each stop costs a hand rebase. The predicate is
#
#     files(merge-base..origin/<base>) ∩ files(merge-base..<branch>) ≠ ∅
#
# which the incident satisfies (7 files landed, 4 of them shared with the branch). Patch-level
# redundancy was rejected as false-negative-prone: a second agent re-implementing the same fix
# produces a different patch-id.
#
# ITS KNOWN FALSE-POSITIVE CLASS, named rather than engineered around (OR-1). Any file that
# essentially every base merge touches — a version-pinned install doc, a generated lockfile — will
# overlap a branch that also edits it, on every release. Measured here at 32 of 32 release merges
# for one such doc, ~7% of runs. There is deliberately NO exclusion list: a config key of paths
# that "do not count" re-introduces exactly the judgment the mechanical predicate exists to avoid,
# and it is cheap to add later if the rate turns out to bite. The exit message names the class so
# an operator recognizes one of these in a single read.
#
# READ-ONLY, in the strict sense the scheduler's contract needs (D-3). It records nothing: no
# `attempt` row, no `satisfied` row, no fix-budget consumption, and — like `progress` — it does not
# call ensure_progress_file, so it cannot bring the run's record into existence. The scheduler reads
# only its rc, which is what keeps "gate exit codes and tracker state, nothing else" true while the
# lane gains a predicate that has to look at git.
#
# NOT in require_entry_attested's set, for a reason sharper than `progress`'s: this runs BEFORE the
# first BUILD spawn of round 1, and `entry` is that spawn's own first act. Gating it on an
# attestation would refuse it on every honest run's first call.
#
# FAIL CLOSED (D-5). A failed fetch, an unresolvable merge-base or an unreadable tracker answer
# returns 1 naming which read failed, and never 0. A stale `origin/<base>` would make the base arm
# answer "nothing moved", which is indistinguishable from a clean check — the same error-reads-as-
# success shape `progress_token`'s non-zero return exists to remove.
#
# THE ARMS SHORT-CIRCUIT, ticket first. It is the cheaper read (no fetch), and a run stopped by it
# is stopping regardless of what the base says — so "which arm fired" stays unambiguous and a dead
# ticket costs no network round trip against the base.
#
# Exit: 0 = clean, or an arm stated a skip · 7 = STALE · 1 = a read could not be completed.
staleness_ticket_arm() {
  # github-only (D-8). The gate's tracker adapter has no issue-state read under jira, and inventing
  # one here would be a second tracker authority; the base arm still runs, which is the arm that
  # would have caught the incident anyway.
  if [ "$TRACKER_TYPE" != "github" ]; then
    say "staleness: ticket arm skipped — tracker '$TRACKER_TYPE' has no issue-state read here. The base arm still runs."
    return 0
  fi
  local state
  state="$("$GH_CLI" issue view "$ISSUE" --json state --jq '.state' 2>/dev/null)" || {
    warn "[lean-gate] ✗ staleness: could not read #$ISSUE's state via '$GH_CLI' — refusing to treat an unreadable tracker as an open ticket."
    return 1; }
  case "$state" in
    # D-7: ANY closed state. The motivating ticket closed NOT_PLANNED, so narrowing to `completed`
    # would miss the case this arm exists for — which is why `.state` is read and `.stateReason`
    # deliberately is not.
    OPEN)   say "staleness: ticket arm clean — #$ISSUE is still OPEN."; return 0 ;;
    CLOSED) say "staleness: TICKET ARM FIRED — #$ISSUE is CLOSED, so this run's premise is already false."; return 7 ;;
    *)      warn "[lean-gate] ✗ staleness: '$GH_CLI' answered an unrecognized state '$state' for #$ISSUE — refusing to guess whether the ticket is open."
            return 1 ;;
  esac
}

staleness_base_arm() {
  local ref="refs/heads/$LEAN_BRANCH" mb base_files branch_files overlap n
  # D-9. On round 1's first pass the branch does not exist yet, so there is no range to compare.
  # A skip is NOT the fail-closed case above: nothing failed to be read, there was nothing to read.
  if ! git -C "$MAIN_ROOT" show-ref --verify --quiet "$ref"; then
    say "staleness: base arm skipped — $ref does not exist yet, so there is no range to compare. Nothing failed."
    return 0
  fi
  # D-12: the fetch belongs here and not to the scheduler, whose zero-write premise is about
  # tracker writes and lane artifacts under a run's identity. A remote-tracking ref is local cache.
  git -C "$MAIN_ROOT" fetch --quiet origin "$BASE_BRANCH" 2>/dev/null || {
    warn "[lean-gate] ✗ staleness: could not fetch origin/$BASE_BRANCH — a stale remote-tracking ref would answer 'nothing moved', which is indistinguishable from a clean check."
    return 1; }
  mb="$(git -C "$MAIN_ROOT" merge-base "origin/$BASE_BRANCH" "$ref" 2>/dev/null)"
  [ -n "$mb" ] || {
    warn "[lean-gate] ✗ staleness: cannot resolve merge-base(origin/$BASE_BRANCH, $ref), so this branch's start point is unknown and no range can be compared."
    return 1; }
  base_files="$(git -C "$MAIN_ROOT" diff --name-only "$mb" "origin/$BASE_BRANCH" 2>/dev/null)"
  branch_files="$(git -C "$MAIN_ROOT" diff --name-only "$mb" "$ref" 2>/dev/null)"
  # Both emptiness guards are load-bearing rather than defensive: `printf '%s\n' ""` emits one
  # EMPTY LINE, and two empty line-sets intersect on it — so an unguarded set intersection would
  # report overlap for a branch and a base that have both changed nothing.
  if [ -z "$base_files" ]; then
    say "staleness: base arm clean — origin/$BASE_BRANCH has not moved since the branch point."
    return 0
  fi
  if [ -z "$branch_files" ]; then
    say "staleness: base arm clean — the branch has committed no changes yet, so it can overlap nothing."
    return 0
  fi
  # `grep -Fxf` IS the set intersection: fixed strings, whole-line, so a path containing a regex
  # metacharacter is compared literally and a path that merely CONTAINS another is not a match.
  overlap="$(printf '%s\n' "$branch_files" | grep -Fxf <(printf '%s\n' "$base_files") 2>/dev/null)"
  if [ -z "$overlap" ]; then
    say "staleness: base arm clean — origin/$BASE_BRANCH moved, but into no file this branch touches. Bare advancement is not the trigger."
    return 0
  fi
  n="$(printf '%s\n' "$overlap" | grep -c .)"
  say "staleness: BASE ARM FIRED — origin/$BASE_BRANCH has moved into $n file(s) this branch also touches since $mb:"
  printf '%s\n' "$overlap" | while IFS= read -r f; do [ -n "$f" ] && say "    $f"; done
  say "  If that list is only a file every base merge rewrites (a version-pinned doc, a generated lockfile), this is the known false-positive class — there is deliberately no exclusion list."
  return 7
}

cmd_staleness() {
  local rc
  if [ "$STALENESS_ARM" != "base" ]; then
    staleness_ticket_arm; rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
  fi
  if [ "$STALENESS_ARM" != "ticket" ]; then
    staleness_base_arm; rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
  fi
  return 0
}

# The sweep (D-3). Invoked by `entry` and by nothing else — `entry` runs before checklist step 3
# cuts this run's worktree, so it is always executing outside it.
#
# PR STATE IS THE SIGNAL, never `git branch --merged`: this repo squash-merges, so a landed lean
# branch is never an ancestor of the base and `--merged` would fire for nothing. `gh` is
# available under a read-only tracker too — the bot is a VCS-axis capability, not a tracker-axis
# one — so this arm needs no adapter branch.
#
# It can never fail its caller. The audit-ledger predicate is the sole decider of whether a run
# may start, and a `gh` outage must not become a second reason it cannot.
cmd_entry_sweep() {
  local wt br prs n_all n_open considered=0 removed=0 kept=0
  while IFS="$(printf '\t')" read -r wt br; do
    [ -n "$wt" ] || continue
    [ "$wt" = "$MAIN_ROOT" ] && continue
    # Never the caller's own worktree. The sweep is for runs that are OVER; a resumed run
    # re-running `entry` from inside its own worktree is by definition not one of them.
    [ "$wt" = "$REPO_ROOT" ] && continue
    # D-10, the blast radius: only branches that parse as `<prefix><key>` for THIS repo's
    # tracker. Anything else is skipped with no PR lookup at all.
    bp_is_work_branch "$br" "$BRANCH_PREFIX" "$TRACKER_TYPE" "$TRACKER_KEY_PATTERN" || continue
    considered=$((considered + 1))
    # D-12: branch on EXIT STATUS before reading output. A failed lookup is not a "no PR"
    # answer, and treating it as one would remove a worktree on the strength of an outage.
    prs="$("$GH_CLI" pr list --head "$br" --state all --json number,state --limit 100 2>&1)" \
      || { warn "  sweep: could not list PRs for $br — leaving $wt in place ($prs)"; kept=$((kept + 1)); continue; }
    printf '%s' "$prs" | jq -e 'type == "array"' >/dev/null 2>&1 \
      || { warn "  sweep: unreadable PR list for $br — leaving $wt in place"; kept=$((kept + 1)); continue; }
    n_all="$(printf '%s' "$prs" | jq 'length')";                               [ -n "$n_all" ]  || n_all=0
    n_open="$(printf '%s' "$prs" | jq '[ .[] | select(.state == "OPEN") ] | length')"
    [ -n "$n_open" ] || n_open=0
    # OR-1's reversible default. The only rule that would catch a PR-less worktree is an age
    # cutoff — the one criterion that can delete work nobody has pushed anywhere — so these are
    # LEFT, and said out loud rather than passed over in silence.
    if [ "$n_all" -eq 0 ]; then
      say "  sweep: $br has no PR at all — leaving $wt in place (nothing proves its work exists elsewhere)"
      kept=$((kept + 1)); continue
    fi
    if [ "$n_open" -gt 0 ]; then
      say "  sweep: $br still has an open PR — leaving $wt in place"
      kept=$((kept + 1)); continue
    fi
    say "  sweep: $br has no open PR ($n_all closed or merged) — removing its worktree"
    if worktree_destroy "$wt" "$br"; then removed=$((removed + 1)); else kept=$((kept + 1)); fi
  done <<EOF
$(lean_worktrees)
EOF
  [ "$considered" -gt 0 ] || return 0
  say "  sweep: $considered lane worktree(s) considered, $removed removed, $kept kept."
  return 0
}

cmd_entry() {
  local sid ledger lines telemetry
  sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -z "$sid" ]; then
    warn "✗ entry: CLAUDE_CODE_SESSION_ID is unset — the session's audit ledger cannot be located. Refusing to start."
    return 1
  fi
  ledger="$MAIN_ROOT/.claude/audit/$sid.jsonl"
  if [ ! -s "$ledger" ]; then
    if audit_toolkit_opted_out; then
      warn "✗ entry: audit-toolkit is disabled in this repo's settings, so no hook writes the ledger at '$ledger'. Refusing to start."
      warn "  The lean lane requires it: re-enable \"audit-toolkit@<marketplace>\" in .claude/settings.json (or settings.local.json) and restart the session."
    else
      warn "✗ entry: audit ledger '$ledger' is missing or empty — the hook ledger is not live. Refusing to start."
      warn "  Every lean record carries reconciliation keys; without a ledger the run is unverifiable at the merge boundary."
    fi
    return 1
  fi
  lines="$(wc -l < "$ledger" | tr -d ' ')"
  say "✓ entry: audit ledger live ($lines lines)."
  # AC-1. Advisory by construction — the return code below is never reached from here.
  telemetry="$(telemetry_state)"
  case "$telemetry" in
    off)
      say "  ⚠ telemetry: CLAUDE_CODE_ENABLE_TELEMETRY is not set in this session, so it exports nothing."
      say "    Step 7's cost block will be empty, and it cannot be recovered after the run — the datapoints are never emitted."
      say "    Fix it now if you want cost on this run: set it in ~/.claude/settings.json's \`env\` block and relaunch (cost-tracking-setup.md §3)."
      ;;
    nocoll)
      say "  ⚠ telemetry: exporting is enabled, but nothing is accepting on ${OTEL_EXPORTER_OTLP_ENDPOINT:-http://127.0.0.1:4317}."
      say "    Step 7's cost block will be empty unless the collector is running before the work starts (cost-tracking-setup.md §2)."
      ;;
    *)
      say "  telemetry: on."
      ;;
  esac
  # The durable half (D-3/D-10). The progress file already survives worktree teardown, is
  # already what lean-reconcile.sh reads, and is the only build-side record outliving the
  # session. Later readers check PRESENCE ONLY — nothing re-resolves a ledger path from inside
  # a worktree, which is what lets this land independently of #417.
  #
  # Idempotent, and retroactive by design (D-11): a run that skipped step 1 in a properly
  # configured repo self-heals with one command, while in the configuration that motivated this
  # (`audit-toolkit` off) the predicate above still refuses — so the enforcement binds exactly
  # where it was missing. OR-1: the row is per-RUN, not per-session. It attests that the run
  # STARTED attested; a session resuming it inherits the row without re-proving its own ledger.
  # Tightening to per-session is one comparison against the id recorded here, but cannot be done
  # honestly until #417 lands.
  ensure_progress_file
  if entry_row_present; then
    say "  entry attestation already recorded in $PROGRESS_FILE — not duplicated."
  else
    append_line "$(now_iso) | entry | ledger=$ledger | lines=$lines | telemetry=$telemetry | session=$sid"
    say "  entry attestation recorded in $PROGRESS_FILE."
  fi
  # #446, and OUTSIDE the branch above on purpose: the attestation row is per-RUN and short-
  # circuits, whereas the build-session set is per-SESSION. A second build session resuming this
  # run reaches the `already recorded` arm and must still be admitted to the set, or its own
  # `mark` is refused.
  record_build_session
  # SKILL.md step 1 pairs this gate with a SESSION-side queue-label confirm. That confirm
  # has no jira meaning — jira pickup is "the operator supplies the key; no queue, no claim,
  # no label" — so the documented reject-and-stop has no defined outcome there. Say so here
  # rather than leaving the session to infer it: the note is the only place the two halves
  # of step 1 meet.
  if [ "$TRACKER_TYPE" = "jira" ]; then
    say "  tracker delta (jira): no queue label to confirm — the operator supplies the ticket key (tracker.writes: false). Step 1's label reject does not apply."
  fi
  # LAST, and its result is discarded: the attestation above is what `entry` exists to
  # establish, so nothing the sweep does may reach this function's exit status.
  cmd_entry_sweep
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
# and never touches `$GH_BOT` (a hard `:?` failure below).
#
# THIS branch stays keyed on the tracker, unlike cmd_mark's (#440). Not for symmetry: a
# read-only tracker has no comment surface at all, so there is nothing to authenticate even
# when a bot exists. cmd_mark writes to the PR, which every adapter has.
cmd_claim() {
  local helper body url

  # #446. Under EVERY adapter, and before the jira early return: `claim` is the second half of
  # the arm that may establish the build identity, and the set is a build-side record with no
  # tracker write of its own.
  record_build_session

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
  #
  # It also carries this producer's CAPABILITY STAMP (#445). The claim comment is the one
  # build-side artifact EVERY github generation writes, which is what lets a merge-boundary arm
  # tell "this run's producer could not write that artifact" from "this run withheld it".
  resolve_capability_stamp
  body="$(mktemp -t lean-claim.XXXXXX)" || envfail "mktemp failed."
  {
    echo "<!-- dev-pipeline -->"
    echo "<!-- run_id: $RESOLVED_RUN_ID -->"
    echo "<!-- session_id: ${CLAUDE_CODE_SESSION_ID:-unset} -->"
    echo "<!-- $LEAN_CAPABILITY_KEY: $LEAN_CAPABILITY_STAMP -->"
    echo "<!-- stage: $LEAN_CLAIM_MARKER_TAG -->"
    echo ""
    echo "🤖 Claimed by \`/dev-pipeline:build-lean\`."
  } > "$body"
  url="$("${GH_BOT:?GH_BOT must point at the bot wrapper}" api -X POST \
        "repos/{owner}/{repo}/issues/$ISSUE/comments" -F body=@"$body" --jq .html_url 2>&1)"
  local rc=$?
  rm -f "$body"
  [ "$rc" -eq 0 ] || { warn "✗ claim: marker comment failed: $url"; return 1; }
  say "✓ claim: labels swapped and lean-claimed comment posted ($url)"
  return 0
}

# ---------------------------------------------------------------- producer capabilities (#445)
# WHY A PRODUCER STAMPS ITS GENERATION. A merge-boundary arm travels by GIT REF — a consumer's CI
# fetches it at its pinned marketplace ref — while this file travels by VERSIONED PLUGIN INSTALL
# into an operator's local cache. The two transports skew, and both trees report the same version,
# so no version-keyed check can observe it. An arm that landed before its producer shipped was
# therefore enforced against runs whose build session had no way to satisfy it.
#
# So the producer stamps what it CAN DO into an artifact it already writes, and an arm bound to a
# capability enforces only when the stamp declares it. Absent a stamp the arm goes INERT rather
# than accusing an honest run — the same degrade-toward-declining posture #444's `since:` takes.
#
# THE CLAIM COMMENT IS THE CARRIER, and that is what makes this non-circular: every github
# generation posts one, the pre-token generation included. Stamping the PR marker instead would be
# circular — the marker IS the artifact the bound arm demands, so its absence could not be told
# apart from a producer that cannot write it. Stamping only the verdict record would let the
# reviewed party soften a build-side arm.
#
# THE SHARED BLOCK holds three literals, not one:
#   LEAN_CLAIM_MARKER_TAG  the claim comment's stage token — written here, read by
#                          lean-evidence.sh (which reads the stamp off it) and by
#                          scripts/check-lean-chain.sh (whose claim arm counts it).
#                          lean-reconcile.sh keeps an unbound copy of the literal: it is an
#                          operator-run reconciler rather than a merge-boundary gate, and it
#                          carried that copy before this contract existed.
#   LEAN_CAPABILITY_KEY    the stamp's key, in the claim comment and in the verdict record.
#   LEAN_CAPABILITIES      the CLOSED vocabulary of capability tokens, comma-separated. Each side
#                          validates its OWN token against it — the producer the subset it ships,
#                          the reader the token its arm requires — so a one-sided rename reds
#                          loudly on the side that renamed, instead of silently producing a stamp
#                          no reader can ever match. Same posture as LEAN_OUTPUT_DISPOSITIONS.
# LOCKSTEP-BEGIN lean-producer-capabilities
LEAN_CLAIM_MARKER_TAG='lean-claimed'
# shellcheck disable=SC2034  # each reader binds a SUBSET of these; the block is one contract.
LEAN_CAPABILITY_KEY='capabilities'
# shellcheck disable=SC2034  # ditto — unused here is the point, not an oversight.
LEAN_CAPABILITIES='pr-marker'
# LOCKSTEP-END lean-producer-capabilities

# WHAT THIS GENERATION SHIPS — deliberately OUTSIDE the shared block, because it is the one thing
# here that is not a shared contract: it is this build of this file's own answer, and a later
# generation widens it without touching a reader.
#
# COMMA-SEPARATED, and that is the wire format too. The stamp rides inside an HTML comment closed
# by ` -->`, so a space-separated list would need a capture charset containing a space and would
# swallow the closing dashes; a comma-separated one stops cleanly at the space.
LEAN_PRODUCER_CAPABILITIES='pr-marker'

# Validated at the point of use, into a global, NEVER through a `$(…)` helper: envfail exits, and
# an exit inside a command substitution kills only the subshell — the caller would then stamp an
# empty capability list and every bound arm downstream would go inert on an honest run.
LEAN_CAPABILITY_STAMP=""
resolve_capability_stamp() {
  local c
  [ -n "$LEAN_CAPABILITY_STAMP" ] && return 0
  for c in $(printf '%s' "$LEAN_PRODUCER_CAPABILITIES" | tr ',' ' '); do
    case ",$LEAN_CAPABILITIES," in
      *",$c,"*) : ;;
      *) envfail "internal: '$c' is not in the closed capability vocabulary ('$LEAN_CAPABILITIES'). Stamping a token no reader can match would arm nothing and disarm everything bound to it." ;;
    esac
  done
  LEAN_CAPABILITY_STAMP="$LEAN_PRODUCER_CAPABILITIES"
  return 0
}

# ---------------------------------------------------------------- the PR marker (#359 / D-2)
# LOCKSTEP-BEGIN lean-pr-marker
# The PR marker's stage token. WRITTEN by lean-gate.sh's `mark` subcommand, READ by the
# identity arm here. A one-sided rename silently empties the marker set, and an empty set is
# indistinguishable from "the harness never ran" — so the reader would refuse every honest PR
# while a reader that failed open would accept every dishonest one. Neither file can see the
# other's spelling, hence the marker block.
#
# `lean-pr-marker`, NEVER `lean-claimed`: the claim marker lives on the ISSUE and is windowed
# at PR-open by check-lean-chain.sh, and a token that matched both would let an issue-side
# comment satisfy a PR-side arm.
LEAN_PR_MARKER_TAG='lean-pr-marker'
# LOCKSTEP-END lean-pr-marker

# WHY THE PR AND NOT THE ISSUE (D-2). The build run's identity has to be readable by a check
# that knows nothing about the tracker: source control is GitHub for every adapter, so a PR
# comment is the one authenticated write surface that needs no `tracker.writes` branching.
# lean-evidence.sh compares the verdict record's identity against EVERY marker here.
#
# WHY STEP 7 AND NOT MILESTONE 5 ALONE. A PR comment does not fire a `pull_request` event, so
# it never re-runs the merge-boundary job. The last CI run on a lean PR is the review session's
# verdict-record push, and nothing pushes after it — a marker first written at milestone 5
# would be invisible to that run and would red every lean PR until someone re-ran the job by
# hand. So the checklist calls this at PR-open, and cmd_5 calls it again; the second call is a
# no-op. (The receipt placed the write at milestone 5 on the reasoning that the PR exists by
# then, which is equally true at step 7 — see this issue's intent-gap record.)
#
# IDEMPOTENT BY IDENTITY, not by presence: a marker carrying THIS run's id suppresses the
# write, while a marker from a DIFFERENT build session on the same PR does not. That is the
# case D-4 exists for — a second session must leave its own marker, or its identity is
# invisible at the boundary and it could author its own review.
cmd_mark() {
  local pr prnum comments existing body url rc msid recorded

  if [ "$BOT_ENABLED" != "true" ]; then
    say "· mark: no bot is enabled for this consumer (tracker.bot.enabled is false, or absent under tracker.type 'jira'), so there is no authenticated writer for a PR marker. The boundary's identity arm runs at reduced strength (printed there); every other arm is unaffected. Configuring a bot restores the marker under either tracker."
    return 0
  fi

  # #446: the ambient session must be a RECORDED build session. FIRST, before the PR lookup and
  # the comment fetch — a review session doing the documented recovery gets its refusal at zero
  # network cost, and the refusal needs no committed verdict record to exist yet.
  #
  # This never records; see record_build_session's note on why a self-whitelisting guard would be
  # vacuous. It prints the recorded id rather than silently substituting it, which is the whole
  # difference: a genuine second build session keeps its OWN ambient id on its OWN marker, while
  # the operator's correction becomes "copy the harness's recorded value" instead of "hand-supply
  # an identity string".
  msid="${CLAUDE_CODE_SESSION_ID:-}"
  if ! session_in_build_set "$msid"; then
    recorded="$(build_session_set | tr '\n' ' ' | sed -e 's/[[:space:]]*$//')"
    warn "✗ mark: this session ('${msid:-unset}') is not a recorded BUILD session for #$ISSUE — refusing to stamp it onto the PR marker."
    warn "  session_id is the strongest identity the merge boundary compares; a marker carrying a REVIEW session's id makes lean-evidence.sh report an independent review as a P10 self-review, and no re-run or second marker clears it."
    if [ -z "$recorded" ]; then
      warn "  The harness recorded no build session in $PROGRESS_FILE. Run 'bash G entry $ISSUE' from the session that built this branch."
    else
      warn "  Build session(s) recorded by the harness: $recorded"
      warn "  Re-invoke from one of them, or: CLAUDE_CODE_SESSION_ID=<id> bash G mark $ISSUE"
    fi
    return 1
  fi

  if [ -n "$PR_FILE" ]; then
    [ -f "$PR_FILE" ] || envfail "--pr-file '$PR_FILE' does not exist."
    pr="$(cat "$PR_FILE")"
  else
    pr="$("$GH_CLI" pr list --head "$LEAN_BRANCH" --state open \
          --json number,url --limit 1 2>&1)" \
      || { warn "✗ mark: could not list PRs for $LEAN_BRANCH: $pr"; return 1; }
  fi
  printf '%s' "$pr" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { warn "✗ mark: no open PR found for branch $LEAN_BRANCH — open it first (checklist step 7)."; return 1; }
  prnum="$(printf '%s' "$pr" | jq -r '.[0].number')"

  if [ -n "$COMMENTS_FILE" ]; then
    [ -f "$COMMENTS_FILE" ] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
    comments="$(cat "$COMMENTS_FILE")"
  else
    comments="$("$GH_CLI" api "repos/{owner}/{repo}/issues/$prnum/comments" --paginate 2>&1)" \
      || { warn "✗ mark: could not fetch the comment trail for PR #$prnum: $comments"; return 1; }
  fi
  printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || envfail "PR comment trail is not a JSON array."

  # The run-id test is DELIMITED on its right (`[^A-Za-z0-9._-]`) rather than left open: the
  # marker body always closes the id with ` -->`, and an open-ended match would let a marker
  # for `lean-359-ab` suppress the write for `lean-359-a` — a silently unmarked second session,
  # which is the exact hole D-4 closes.
  existing="$(printf '%s' "$comments" | jq -r --arg tag "$LEAN_PR_MARKER_TAG" --arg run "$RESOLVED_RUN_ID" \
    '[ .[]
       | select((.user.type // "") == "Bot")
       | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*" + $tag + "[[:space:]]*-->"))
       | select((.body // "") | test("run_id:[[:space:]]*" + $run + "[^A-Za-z0-9._-]"))
     ] | length')"
  if [ "${existing:-0}" -ge 1 ]; then
    say "· mark: PR #$prnum already carries this run's marker (run_id=$RESOLVED_RUN_ID) — nothing posted."
    return 0
  fi

  body="$(mktemp -t lean-mark.XXXXXX)" || envfail "mktemp failed."
  {
    echo "<!-- dev-pipeline -->"
    echo "<!-- run_id: $RESOLVED_RUN_ID -->"
    echo "<!-- session_id: ${CLAUDE_CODE_SESSION_ID:-unset} -->"
    echo "<!-- stage: $LEAN_PR_MARKER_TAG -->"
    echo ""
    echo "🤖 Built by \`/dev-pipeline:build-lean\`. This comment carries the build run's identity at"
    echo "the merge boundary — the review verdict must carry a different one."
  } > "$body"
  url="$("${GH_BOT:?GH_BOT must point at the bot wrapper}" api -X POST \
        "repos/{owner}/{repo}/issues/$prnum/comments" -F body=@"$body" --jq .html_url 2>&1)"
  rc=$?
  rm -f "$body"
  [ "$rc" -eq 0 ] || { warn "✗ mark: marker comment failed: $url"; return 1; }
  say "✓ mark: build identity posted on PR #$prnum (run_id=$RESOLVED_RUN_ID) ($url)"
  return 0
}

# ---------------------------------------------------------------- milestone 1: open regions
# #374 AC-8/9/10. A declared `pause-and-ask` Open Region (interviewing-baseline's Decision
# Ledger contract) is not the build session's to close — refuse here, before any code is
# written, rather than let it surface as a review blocker hours later (observed on #372's
# OR-2: resolved in-session, caught only at round-1 review, cost an operator comment AND a
# round-2 review to clear). `reversible-default-and-flag` regions carry their own default and
# are never refused (AC-9); an issue with no `## Open Regions` section is unaffected (AC-10).
#
# NETWORK, and deliberately NOT part of cmd_all's cheap pre-pass (AC-7 bounds the pre-pass,
# not milestone 1's real body) — the issue and its comment trail are read live unless the
# fixture seams below are set. cmd_1 skips this entirely under LEAN_GATE_OBSERVE=1.
open_regions_section() { # stdin: the issue body — prints the section's lines, nothing else
  awk '
    tolower($0) ~ /^#+[[:space:]]+open regions[[:space:]]*$/ { insec = 1; next }
    insec && /^#+[[:space:]]/                                 { insec = 0 }
    insec                                                     { print }
  '
}

# Table rows `| <id> | ... | pause-and-ask |` inside the section — the closed 2-value
# disposition enum interviewing-baseline defines. The header/separator rows never match:
# neither carries the literal disposition token in its last cell.
#
# The disposition is the LAST NON-EMPTY cell, not $(NF-1). GFM does not require the trailing
# pipe interviewing-baseline's canonical form happens to write, and `| OR-1 | R | pause-and-ask`
# puts the disposition at $NF — under $(NF-1) that row scans the Region text, matches nothing,
# and the gate fails OPEN on a table a renderer accepts. Scanning back from NF over trimmed
# cells reads both shapes, since the trailing pipe's own field is empty.
pause_and_ask_ids() { # stdin: the issue body
  open_regions_section | awk -F'|' '
    /pause-and-ask/ {
      id = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      disp = ""
      for (i = NF; i >= 1; i--) {
        cell = $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell)
        if (cell != "") { disp = cell; break }
      }
      if (disp == "pause-and-ask" && id != "" && id != "ID") print id
    }
  '
}

# A pause-and-ask region's resolution artifact: a non-bot issue comment naming the region id
# (word-bounded, so "OR-1" cannot match inside "OR-10"), or a committed intent-gap record whose
# OWN `region:` key names THIS id and whose `ratified:` key reads `yes` — a record ratified for
# a different region cannot clear this one.
region_resolved() { # region_resolved <id> <comments-json>
  local id="$1" comments="$2" n gap
  gap="$REPO_ROOT/$INTENT_GAP_REL"
  if [ -f "$gap" ] && [ "$(record_key region "$gap")" = "$id" ] && [ "$(record_key ratified "$gap")" = "yes" ]; then
    return 0
  fi
  n="$(printf '%s' "$comments" | jq -r --arg pat "(^|[^A-Za-z0-9-])${id}([^A-Za-z0-9-]|\$)" \
    '[ .[] | select((.user.type // "") != "Bot") | select((.body // "") | test($pat)) ] | length' 2>/dev/null)"
  [ "${n:-0}" -ge 1 ]
}

check_pause_and_ask() { # prints a fail_milestone reason on stdout, nothing when clear
  [ "$TRACKER_TYPE" = "jira" ] && return 0   # no gh issue to read under a read-only tracker
  local body ids comments id

  if [ -n "$ISSUE_FILE" ]; then
    [ -f "$ISSUE_FILE" ] || envfail "--issue-file '$ISSUE_FILE' does not exist."
    body="$(jq -r '.body // ""' "$ISSUE_FILE" 2>/dev/null)"
  else
    body="$("$GH_CLI" issue view "$ISSUE" --json body --jq .body 2>&1)" \
      || { echo "could not read issue #$ISSUE to check for an unresolved pause-and-ask region: $body"; return 0; }
  fi

  ids="$(printf '%s' "$body" | pause_and_ask_ids)"
  [ -n "$ids" ] || return 0

  if [ -n "$COMMENTS_FILE" ]; then
    [ -f "$COMMENTS_FILE" ] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
    comments="$(cat "$COMMENTS_FILE")"
  else
    comments="$("$GH_CLI" api "repos/{owner}/{repo}/issues/$ISSUE/comments" --paginate 2>&1)" \
      || { echo "could not read #$ISSUE's comment trail to check for an unresolved pause-and-ask region: $comments"; return 0; }
  fi

  # Every unresolved region, not just the first — the same ergonomic the `all` pre-pass owes
  # (AC-3): an operator clearing two regions must not pay two round-trips to discover the
  # second. The label stays singular for one so the refusal reads as prose either way.
  local unresolved="" label="region"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    region_resolved "$id" "$comments" || unresolved="${unresolved:+$unresolved, }$id"
  done <<< "$ids"
  [ -n "$unresolved" ] || return 0
  case "$unresolved" in *,*) label="regions" ;; esac
  echo "issue #$ISSUE declares $label $unresolved dispositioned pause-and-ask with no resolution artifact — neither a non-bot comment naming each nor a ratified intent-gap record ($INTENT_GAP_REL) exists. Get an operator comment on #$ISSUE resolving them, or ratify an intent-gap record, before continuing."
}

# ---------------------------------------------------------------- the design axis: arming
# LOCKSTEP-BEGIN lean-design-armed
# Armed-ness exactly as the COMMITTED SPEC declares it. Spec on stdin; prints `armed`, or
# nothing at all.
#
# TWO READERS, which is why this is a marker block and not a private helper: check-lean-chain.sh
# must reach the same answer from a CI checkout that cannot see the runtime config at all (it is
# gitignored on every consumer, this repo included). A boundary that decided armed-ness
# differently from the gate would either wave an armed PR through with no evidence or red an
# honest unarmed one, and neither divergence is visible from either side alone.
#
# The shared predicate is deliberately the NARROW one — at least one `| RS-n |` render-state row
# and no explicit `Design: none` disarm. Everything else the gate checks about the section (a
# provider handoff link, the neither-form refusal, the reason on a disarm) is an AUTHORING error
# it refuses at milestone 1, so a spec that fails those never reaches a merge and the boundary
# never needs an opinion about it. Keeping the shared decision to what both sides can compute
# identically is what stops the two from drifting.
#
# The heading matches at any depth and case-folded (`## Design`, `### DESIGN`), and ANY heading
# closes the section — the flat rule a reader can predict, the same one jira_items_section uses.
# `#+[[:space:]]`, never `#{1,6}`: interval expressions are not portable across the awks this
# ships on, and the space is required because `##Design` is literal text to CommonMark.
design_armed() { # design_armed   (spec on stdin)
  awk '
    tolower($0) ~ /^#+[[:space:]]+design[[:space:]]*$/ { insec = 1; next }
    insec && /^#+[[:space:]]/ { insec = 0 }
    insec && tolower($0) ~ /^[[:space:]]*design:[[:space:]]*none([[:space:]]|$)/ { disarmed = 1; exit }
    insec && /^[[:space:]]*\|[[:space:]]*RS-[0-9]+[[:space:]]*\|/ { rows = 1 }
    END { if (rows && !disarmed) print "armed" }
  '
}
# LOCKSTEP-END lean-design-armed

# The section's body lines, for the gate-side form checks the boundary does not make.
design_section() { # design_section   (spec on stdin)
  awk '
    tolower($0) ~ /^#+[[:space:]]+design[[:space:]]*$/ { insec = 1; next }
    insec && /^#+[[:space:]]/                          { insec = 0 }
    insec                                              { print }
  '
}

# The declared render states, one `RS-n<TAB>route<TAB>state` line per table row, in spec order.
# `-F'|'` over a leading-pipe markdown row puts the id in $2, so the leading empty field is not
# an accident to work around — it is what makes the column indices match the declared shape.
design_rs_rows() { # design_rs_rows   (spec on stdin)
  awk -F'|' '
    tolower($0) ~ /^#+[[:space:]]+design[[:space:]]*$/ { insec = 1; next }
    insec && /^#+[[:space:]]/ { insec = 0 }
    insec && /^[[:space:]]*\|[[:space:]]*RS-[0-9]+[[:space:]]*\|/ {
      id = $2; route = $3; state = $4
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", route)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", state)
      if (id != "" && route != "" && state != "") printf "%s\t%s\t%s\n", id, route, state
    }
  '
}

# The GATE's arming resolution (D-8): the shared predicate plus the form validation only a
# writer can act on. Prints exactly one of `unarmed`, `disarmed`, `armed`, or `error:<message>`
# — an error being an authoring defect the session can fix, never an environment problem.
#
# `unarmed` short-circuits on the config: a repo with no `design.provider` has no design axis, so
# a `## Design` section in its spec is documentation and arms nothing. That is the AND half of
# D-8, and the case that kills an AND→OR mutant — under OR, every consumer that ever wrote the
# heading would be required to own a render harness.
design_state() { # design_state <spec-path>
  local spec="$1" sec n_disarm n_reason n_link
  [ -n "$DESIGN_PROVIDER" ] || { printf 'unarmed'; return 0; }
  [ -f "$spec" ] || { printf 'unarmed'; return 0; }
  sec="$(design_section < "$spec" 2>/dev/null)"
  if [ -z "$sec" ]; then
    printf 'error:config declares design.provider "%s", so the committed spec %s must carry a "## Design" section — either ARMED (a provider handoff link plus a render-state table with at least one "| RS-n | route | state | AC refs |" row) or the explicit disarm "Design: none — <reason>". Arming is a per-ticket decision; a design lane nobody declared is the shape that ships visual defects behind a passing gate.' \
      "$DESIGN_PROVIDER" "$SPEC_REL"
    return 0
  fi

  n_disarm="$(printf '%s\n' "$sec" | grep -ciE '^[[:space:]]*Design:[[:space:]]*none([[:space:]]|$)')" || n_disarm=0
  if [ "${n_disarm:-0}" -ge 1 ]; then
    n_reason="$(printf '%s\n' "$sec" | grep -ciE '^[[:space:]]*Design:[[:space:]]*none[[:space:]]+[^[:space:]]')" || n_reason=0
    [ "${n_reason:-0}" -ge 1 ] \
      || { printf 'error:the "## Design" section of %s disarms this ticket but states no reason. The form is "Design: none — <reason>": a disarm is a decision, and an undocumented one is indistinguishable from an omission at review time.' "$SPEC_REL"; return 0; }
    printf 'disarmed'; return 0
  fi

  if [ "$(design_armed < "$spec" 2>/dev/null)" != "armed" ]; then
    printf 'error:the "## Design" section of %s declares no render state. Add at least one "| RS-n | route | state (what must be visible) | AC refs |" row, or disarm the ticket with "Design: none — <reason>". A section that names neither is the third failure class this gate exists for: a render that captured the default state and verified nothing.' "$SPEC_REL"
    return 0
  fi

  # Shape only — this gate resolves nothing over the network, so the link is checked for being a
  # link and never for pointing anywhere. Its job is to make the handoff FINDABLE by the review
  # session, which is the reader that does resolve it.
  n_link="$(printf '%s\n' "$sec" | grep -ciE 'https?://[^[:space:]]+')" || n_link=0
  [ "${n_link:-0}" -ge 1 ] \
    || { printf 'error:the "## Design" section of %s declares render states but no provider handoff link. The review session scores fidelity against the design frame; without the link there is nothing to score against.' "$SPEC_REL"; return 0; }

  printf 'armed'
}

# The STATE LOCK behind D-8's mid-run-disarm refusal. Its line shape deliberately does NOT
# contain the `| milestone-3 | attempt |` substring attempt_count() greps, so arming — which
# happens on every armed evaluation, passing or failing — can never consume fix budget. It is a
# record of a decision, not a counter.
#
# Read the STRENGTH of this lock correctly. PROGRESS_FILE is uncommitted and machine-local, so
# the row binds inside the worktree that armed the lane; a resume in a fresh worktree, or on a
# second machine, reads no record and accepts the disarm. That matches this script's declared
# trust posture — a local record is tamper-evidence, never integrity — and the residual sits at
# review, where an unjustified "Design: none" on a provider repo is a blocker. Do not inherit
# this as "cannot be escaped".
design_was_armed() {
  [ "$(count_matches "| milestone-3 | armed |" "$PROGRESS_FILE" -F)" -ge 1 ]
}

# The refusal both milestone 1 and milestone 3 raise on a mid-run disarm. One phrasing, two
# sites: the milestone that notices first should not read differently from the other.
design_disarm_locked_msg() {
  printf 'spec %s now disarms the design lane ("Design: none"), but this run already armed it — the progress file carries a "| milestone-3 | armed |" record. Disarming mid-run retires the render evidence a review round would be scored against, so it is refused: restore the "## Design" render-state table, or abandon the run and re-file the ticket with the disarm in its spec from the start.' "$SPEC_REL"
}

# ---------------------------------------------------------------- milestone 1: spec/AC
# AC-3, as resolved at intake (G-1): existence AT THE PINNED PATH plus >= 1 numbered AC-n,
# and NO further content assertion. The path predicate is not an extra check — it is which
# file "exists" means, and check-lean-chain.sh keys its artifact scan off the same shape.
cmd_1() {
  local spec="$REPO_ROOT/$SPEC_REL" n reason dstate note=""
  # #494: ABSENCE, not a failed fix — block_milestone, whose line kind attempt_count() cannot
  # see. This is the call SKILL.md step 3 orders before the spec can exist.
  [ -f "$spec" ] || { block_milestone 1 "no committed spec at $SPEC_REL"; return $?; }
  n="$(count_matches '(^|[^A-Za-z])AC-[0-9]+' "$spec" -E)"
  [ "$n" -ge 1 ] || { fail_milestone 1 "spec $SPEC_REL carries no numbered AC-n criterion"; return $?; }

  # #394 D-8. Grep-shaped like the AC-n assertion above and evaluated in the observe pass with
  # it: both read the committed spec and the config, nothing else — no network, no subprocess
  # beyond grep/awk — so an armed run learns about a malformed `## Design` section before it
  # pays for milestone 3, exactly as it already learns about a missing AC-n.
  dstate="$(design_state "$spec")"
  case "$dstate" in
    error:*)  fail_milestone 1 "${dstate#error:}"; return $? ;;
    disarmed)
      design_was_armed && { fail_milestone 1 "$(design_disarm_locked_msg)"; return $?; }
      note=", design lane disarmed for this ticket" ;;
    armed)    note=", design lane ARMED" ;;
  esac

  if [ "${LEAN_GATE_OBSERVE:-0}" != "1" ]; then
    reason="$(check_pause_and_ask)"
    [ -z "$reason" ] || { fail_milestone 1 "$reason"; return $?; }
  fi

  pass_milestone 1 "$SPEC_REL ($n AC-n reference(s))$note"
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
#
# SEAM-SCRUBBED (#379/AC-9). Every lane child spawned below — lanes[] setup, the fixed
# lint/typecheck/test keys, and extraLanes — is itself second-shift tooling reach on this
# repo (dogfooding), so it must not inherit the gate's own pipeline-seam env: an ambient
# SECOND_SHIFT_CONFIG/STATECTL_STATE_DIR silently re-roots or re-states it, the same class
# #34 found in verifyctl.sh. Verbatim copy of that denylist (scripts/lockstep-manifest.tsv
# pins it) — lean-gate needs nothing narrower or wider. `eval "$cmd"` becomes
# `env <scrub> bash -c "$cmd"`: functionally identical for a shell command string (verifyctl.sh
# already runs this repo's own configured lane commands that way), and the only shape `env`
# can scrub ahead of.
# LOCKSTEP-BEGIN seam-scrub
SEAM_SCRUB='SECOND_SHIFT_CONFIG|SECOND_SHIFT_REPO_ROOT|SECOND_SHIFT_EXTENSION_MANIFEST|SECOND_SHIFT_PLUGIN_ROOT|SECOND_SHIFT_REVIEW_TOOLKIT_ROOT|SECOND_SHIFT_DEV_PIPELINE_ROOT|SECOND_SHIFT_DESIGN_TOOLKIT_ROOT|SECOND_SHIFT_SECTION_CATALOG|STATECTL_STATE_DIR|STATECTL_WRITER|DEV_PIPELINE_MODE|BRANCH_PREFIX|KEY_PATTERN'
# LOCKSTEP-END seam-scrub
declare -a SEAM_SCRUB_ENV=()
IFS='|' read -r -a _seam_scrub_toks <<< "$SEAM_SCRUB"
for _seam_tok in "${_seam_scrub_toks[@]}"; do
  SEAM_SCRUB_ENV+=(-u "$_seam_tok")
done
unset _seam_tok _seam_scrub_toks

# ---------------------------------------------------------------- milestone 3: detach + join
# #511 D-1. THE EVALUATION RUNS DETACHED AND THE CALLING PROCESS BLOCKS ON ITS MARKER.
#
# WHY IT IS THE GATE'S JOB. `orchestrate-lean.sh` spawns every BUILD session under `claude -p`,
# where TURN END IS PROCESS EXIT. A block facing a long wait has one move that looks polite —
# background the work, end the turn, collect it on the next one — and here that move is fatal:
# there is no next turn. On the #497 run both BUILD sessions signed off with verification in
# flight, neither ever reported, milestone 3 never ran and the lane exited with a continuation
# unspent. A prose rule has a poor record against a block trying to be considerate about a long
# wait, so the CHOICE IS REMOVED rather than legislated: the gate detaches, and the call blocks.
# A session that "backgrounds" this call now backgrounds a waiter, not the evaluation.
#
# AND IT KILLS THE DUPLICATE-SWEEP LIVELOCK. On the #500 run a re-spawn launched a SECOND sweep
# into the worktree the first orphan was still sweeping, so the progress token could never reach
# milestone 3. "Never yield" does not stop that; launch-or-JOIN does — a second invocation that
# finds a live runner attaches to it and starts nothing.
#
# WHAT THE TOOL-TIMEOUT REAP NOW KILLS is the waiter alone. The evaluation is a different process
# and keeps going; re-issuing the call rejoins it. That is the property the whole shape is for.
#
# MILESTONE 3 ONLY (D-2), keyed (issue, milestone-3, worktree) so `bash G 3 <issue>` and `all`'s
# 3-leg join the same runner. Measured on #497's own progress record: milestone 1 concluded in 1s,
# milestone 2 in 2s, milestone 3 in 20m44s. Every observed death is the sweep, and a fork + marker
# + poll round-trip on four evaluations that return in a second is cost bought for nothing.
#
# D-4. ~3x the longest milestone-3 evaluation on record (20m44s). Deliberately generous: CLAUDE.md
# warns that `install-topology-selftest.sh` alone swings 319s/438s/584s and to "treat the range,
# not a point value", and a breach RECLASSIFIES an honest slow run as infrastructure. Headroom is
# worth more here than a fast wedge verdict. The seam exists so the suite can breach it in seconds.
M3_WAIT_CEILING_DEFAULT=3600

# The wait this exists for is measured in minutes, so this could be far coarser — but the SUITE
# drives milestone 3 dozens of times against a fixture that returns in milliseconds, and at a
# one-second poll the gate's own selftest paid ~30s in sleeps alone. The loop body below is all
# builtins (`[ -f ]`, `read <`, `kill -0`, `$SECONDS`), so a 20-minute evaluation costs 6000
# wakeups of nothing rather than 6000 forks.
M3_POLL_SECS=0.1

# D-10: STATE_DIR, never TMPDIR. macOS `mktemp -d` ignores TMPDIR and this repo already carries
# orphan-fixture scars from that directory; the state dir is also gitignored, survives worktree
# teardown, and is readable by a joining session that resolved a different checkout.
#
# KEYED ON THE WORKTREE, not the issue alone: two checkouts of one branch are two evaluations of
# two different trees, and joining across them would hand back a verdict about a tree the caller
# never had. `cksum` over the resolved root — POSIX, deterministic, and it cannot emit a path
# separator the way the path itself would.
m3_paths() {
  [ -n "${M3_BASE:-}" ] && return 0
  local key
  key="$(printf '%s' "$REPO_ROOT" | cksum | awk '{print $1}')"
  M3_BASE="$MAIN_ROOT/$STATE_DIR/$ISSUE-lean-m3-$key"
  M3_PID="$M3_BASE.pid"
  M3_RC="$M3_BASE.rc"
  M3_LOG="$M3_BASE.log"
}

# LIVENESS IS THE RECORDED PID PLUS `kill -0`, never `pgrep -f`. This repo carries a mutual-
# deadlock scar where a waiter's own command line matched its own pattern and it waited on itself
# forever. PID reuse could in principle read a recycled pid as live; the window is a whole pid
# wraparound against a marker that is removed at every launch, and the failure mode is one extra
# ceiling wait rather than a wrong verdict.
#
# `read <` rather than `$(cat …)`: this runs on every poll, and a command substitution is a fork.
m3_runner_live() {
  local pid=""
  [ -f "$M3_PID" ] || return 1
  read -r pid < "$M3_PID" 2>/dev/null
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null
}

# The recorded pid, for a diagnostic — empty when there is nothing to name.
m3_runner_pid() {
  local pid=""
  [ -f "${M3_PID:-}" ] && read -r pid < "$M3_PID" 2>/dev/null
  printf '%s' "$pid"
}

# The runner's output is a FILE, not this process's stdout — it has to be, since the runner
# outlives every waiter attached to it. Replayed whole at every terminal outcome, including the
# two that report nothing was evaluated: an `envfail` inside the runner exits it before it can
# stamp a code, and the reason it printed is then the only diagnosis there is.
m3_replay_log() {
  [ -s "${M3_LOG:-}" ] || return 0
  cat "$M3_LOG"
}

# D-3. THREE TERMINAL STATES, and a waiter that polls only for success is not one of them: silence
# through a crash reads identically to "still running", which is the shape that cost the #496
# review round. (i) the marker appears -> exit with its value. (ii) the recorded pid fails `kill -0`
# with no marker -> the runner died. (iii) the ceiling is reached. (ii) and (iii) both return D-5's
# `rc=7` and spend no fix attempt, because nothing was evaluated.
m3_wait() { # m3_wait <ceiling-secs>
  local ceiling="$1" rc="" pid
  # bash's own elapsed-seconds counter, reset here. No `date` fork per poll, and no BSD/GNU split
  # to get wrong — the two `date` arithmetic dialects are a documented scar in this repo.
  SECONDS=0
  while :; do
    if [ -f "$M3_RC" ]; then
      read -r rc < "$M3_RC" 2>/dev/null
      # A marker that is not a number is a marker mid-write or truncated — which the tmp+mv write
      # should make impossible, so reading it as "did not complete" is the fail-closed answer
      # rather than passing a milestone on an unparseable code.
      case "$rc" in ''|*[!0-9]*) rc=7 ;; esac
      m3_replay_log
      return "$rc"
    fi
    if ! m3_runner_live; then
      # ONE GRACE RE-CHECK, and it is not belt-and-braces. The runner stamps the marker with its
      # last statement and exits immediately after, so a runner observed gone between the two
      # probes above may have stamped it in that gap — without this, a completed evaluation
      # reports as a death on every fast lane.
      sleep "$M3_POLL_SECS"
      if [ ! -f "$M3_RC" ]; then
        pid="$(m3_runner_pid)"
        m3_replay_log
        warn "✗ milestone-3: the detached evaluation (pid ${pid:-unknown}) is gone and stamped no exit code — it did not complete, so NOTHING was evaluated and no fix attempt was charged."
        warn "  Re-invoke \`bash G 3 $ISSUE\`: that relaunches a dead runner, or joins a live one. Whatever it printed is above, and in $M3_LOG."
        return 7
      fi
      continue
    fi
    if [ "$SECONDS" -ge "$ceiling" ]; then
      pid="$(m3_runner_pid)"
      m3_replay_log
      warn "✗ milestone-3: still running after ${SECONDS}s, past the ${ceiling}s ceiling (LEAN_GATE_WAIT_CEILING_SECS) — giving up on the WAIT, not on the evaluation."
      warn "  Runner pid ${pid:-unknown} is still alive and is NOT killed here. Re-invoking rejoins it; \`kill\` that pid to stop it. Nothing was evaluated and no fix attempt was charged."
      return 7
    fi
    sleep "$M3_POLL_SECS"
  done
}

# THE DETACHED EVALUATION ITSELF — the only place cmd_3 is called on a recording path. It writes
# exactly ONE started/concluded pair per real evaluation (D-9), then stamps its code into the
# marker every attached waiter is blocked on.
#
# The unclosed check is deliberately NOT repeated here: the waiter made it before launching, and a
# runner that re-announced would print the notice into a log nobody reads first.
#
# THE STAMP IS THE LAST STATEMENT, and its absence is load-bearing. A runner killed mid-sweep, or
# one that `envfail`s out from under itself, leaves no marker — which is exactly D-3's "did not
# complete", reported as rc=7 with this log replayed rather than as a milestone failure. Written
# via a tmp + `mv` so a waiter can never read a half-written code.
m3_run_detached() {
  local r_rc
  append_started 3
  cmd_3; r_rc=$?
  append_concluded 3 "$r_rc"
  printf '%s\n' "$r_rc" > "$M3_RC.tmp" && mv "$M3_RC.tmp" "$M3_RC"
  return "$r_rc"
}

# D-1's decision, in one predicate: a LIVE runner is joined, anything else is relaunched. There is
# no lock — the pid's own liveness is the authority, and it is self-healing in a way a lock file
# is not (a launcher killed while holding one wedges every later call). The window it accepts is
# the sub-millisecond gap between the spawn below and the pidfile write on the next line; the
# arrivals this exists to serialize are a re-spawned session and a rejoining waiter, seconds to
# minutes apart. That is the same posture run_milestone's OR-1 note already takes on concurrency.
m3_launch_or_join() {
  m3_paths
  local dir pid ceiling
  dir="$(dirname "$M3_BASE")"
  [ -d "$dir" ] || mkdir -p "$dir" || envfail "cannot create the milestone-3 runner dir '$dir'."

  # RESOLVED BEFORE ANYTHING IS SPAWNED. A typo in the seam is a usage error, and validating it
  # inside the wait would announce it only after leaving a detached evaluation with no waiter.
  ceiling="${LEAN_GATE_WAIT_CEILING_SECS:-$M3_WAIT_CEILING_DEFAULT}"
  case "$ceiling" in
    ''|*[!0-9]*) envfail "LEAN_GATE_WAIT_CEILING_SECS must be a whole number of seconds, got '$ceiling'." ;;
  esac
  [ "$ceiling" -gt 0 ] \
    || envfail "LEAN_GATE_WAIT_CEILING_SECS must be greater than 0, got '$ceiling'."

  if m3_runner_live; then
    pid="$(m3_runner_pid)"
    # D-9: A JOIN WRITES NOTHING. #497 defines the unclosed diff as "evaluations that began and
    # never returned"; a join is not an evaluation beginning, and counting it would walk an
    # honestly-waiting run into INTERRUPTED_BUDGET.
    say "milestone-3: an evaluation is already running in this worktree (pid $pid) — JOINING it rather than launching a second. Nothing is recorded for a join."
    say "  runner state: $M3_BASE.{pid,rc,log}"
    m3_wait "$ceiling"
    return $?
  fi

  # THE STALE MARKER IS REMOVED BEFORE THE SPAWN, never after. A wait that could see a PREVIOUS
  # evaluation's code would report the last run's verdict about this tree — and in the suite, where
  # consecutive cases share one fixture and therefore one key, it would pass them vacuously.
  rm -f "$M3_RC" "$M3_RC.tmp" "$M3_LOG"
  # A FORKED SUBSHELL, not a re-exec of this script. Two properties, both paid for:
  #   — Nothing to inherit. A re-exec needs a handshake saying "you are the runner", and the first
  #     shape of that was an env var, which milestone 3's own lane children inherited (this repo's
  #     lane children ARE lean-gate.sh) and every nested milestone-3 call ran inline. A subshell
  #     already knows; there is no flag for a grandchild to pick up.
  #   — Nothing to re-parse. A re-exec re-read the config through a dozen `jq` forks and re-resolved
  #     the git roots to reach a function this process already has loaded: 1.4s of the 1.9s per-call
  #     overhead, measured, and enough to push the paired suite past the mutation sweep's 300s
  #     killer bound. Production pays it once per run; the suite pays it ~35 times.
  # `trap '' HUP` in place of `nohup`, which needs an external command to exec. NO `setsid`: it does
  # not exist on macOS, and adding it makes the launch report a pid while the runner never starts —
  # the marker then never appears and the wait reads "still running" until the ceiling. `disown` is
  # best-effort; the HUP half is the trap's.
  ( trap '' HUP; m3_run_detached ) </dev/null >"$M3_LOG" 2>&1 &
  pid=$!
  disown "$pid" 2>/dev/null
  printf '%s\n' "$pid" > "$M3_PID.tmp" && mv "$M3_PID.tmp" "$M3_PID"
  say "milestone-3: evaluation spawned detached (pid $pid) — this call BLOCKS on it and cannot be backgrounded away (#511). Its output is replayed here when it lands."
  # NAMED, not left to be re-derived. An operator whose waiter was reaped needs the log to see how
  # far the evaluation got and the pid to stop it; and the selftest needs the same three paths,
  # where re-deriving the key would be a hand-maintained copy of m3_paths that cannot fail when
  # m3_paths changes. Production says where it put them.
  say "  runner state: $M3_BASE.{pid,rc,log}"
  m3_wait "$ceiling"
  return $?
}

# extraLanes `when` glob match — bash pattern matching (NOT globstar, NOT git pathspec),
# verifyctl.sh's pinned dialect (AC-4, verifyctl.sh:742-748): `*` crosses `/`, so `**` buys
# nothing extra and a bare directory literal never matches a file beneath it. Its own
# function so the selftest can pin the dialect directly instead of through cmd_3's plumbing.
lean_when_matches() { # lean_when_matches <glob> <changed-files, newline-separated>
  local glob="$1" changed="$2" f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # shellcheck disable=SC2053
    if [[ "$f" == $glob ]]; then return 0; fi
  done <<<"$changed"
  return 1
}

# The `when` diff base — FAIL-CLOSED (AC-8), the opposite of branch_patch_id's fail-open
# above it in this file: an unresolvable origin/$BASE_BRANCH must not silently read as an
# empty diff, which would skip every when-scoped lane and report milestone 3 green having
# verified nothing. Prints the changed-file list on success (possibly empty — a real inert
# diff); prints nothing and returns 1 when the base cannot be resolved. Callers must gate on
# the return code, never on empty output alone.
lean_extra_lanes_diff() {
  local base
  base="$(git -C "$REPO_ROOT" merge-base "origin/$BASE_BRANCH" HEAD 2>/dev/null)" || return 1
  [ -n "$base" ] || return 1
  git -C "$REPO_ROOT" diff --name-only "$base..HEAD" 2>/dev/null
}

# ---------------------------------------------------------------- milestone 3: design render
# #394. The lean lane's answer to three failure classes observed on a design-driven consumer
# run: a NON-BLOCKING render degrade shipped a PR with five real visual defects; a PASSING
# render captured the screen's default collapsed state and verified nothing; and the
# design-blind panel reviewer passed while saying it could not verify against the design frame.
#
# BLOCKING (D-2), on the shared 3-attempt budget, with no degrade state. That is the whole point
# of the first class: a fidelity check that can be skipped is skipped exactly when fidelity is
# the deliverable. `readyProbe` and the documented env prerequisites are what keep an
# environmental red cheap; the per-ticket escape is the spec's explicit disarm, not a runtime
# fallback.
#
# The COST, stated rather than discovered: a manifest write reds the milestone until it is
# committed, and `render_patch_id` moves on ANY commit, so a run with several fix rounds spends
# several of its three milestone-3 attempts on re-render/commit cycles. D-2 accepted that. What
# it buys is that no approved lean PR can carry render evidence for code it does not contain.
#
# What this gate does NOT do: compare anything. Comparison against the design frame is review
# judgment (D-5) and lives in the review-lean session. Here the command is opaque — the gate
# owns the state matrix, the output paths, the hashes and the manifest, and nothing else.
RENDER_OUT_REL=".claude/lean-renders/$ISSUE"

# Placeholder substitution is into a SHELL COMMAND STRING, so every value is single-quoted on the
# way in. `{state}` is the reason this is not optional: a render state is human prose ("filters
# expanded"), so the raw form splices two words where the harness expects one argument — observed
# the first time a two-word state was declared, where the harness received `--state filters` and
# a stray `expanded`, rendered the wrong view, and passed every other assertion here. `{out}` and
# `{route}` get the same treatment because a worktree path may contain a space too.
#
# The CONTRACT this creates, and the docs state it: the placeholders appear UNQUOTED in the
# template. `--state {state}` is correct; `--state "{state}"` nests this quoting inside the
# consumer's and delivers a literally-quoted argument.
shquote() { # shquote <value>
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Substitution walks the template rather than using `${t//p/r}`, and that is not a style choice.
# Since bash 5.2 `patsub_replacement` is ON by default, so a bare ampersand in the REPLACEMENT
# expands to whatever the pattern just matched: a route `prospects?tab=new&sort=asc` arrives at
# the harness as `prospects?tab=new{route}sort=asc`, and a state `filters & sort expanded` as
# `filters {state} sort expanded`. shquote() cannot reach this — it quotes for the shell, one
# layer below where the corruption happens. The failure is silent by construction: the harness
# still exits 0, the screenshot is still non-empty, two rows still hash differently because they
# were shot at two different WRONG views, and the manifest records the DECLARED route and state,
# so the receipt is honest about intent while the pixels are of something else. That is failure
# class (2) reinstated, and it also disarms the reviewer's hash check, which would agree.
# Escaping is no fix: `\&` is the literal on 5.2+ and a literal backslash-ampersand on 3.2.
# Splitting on the placeholder has no replacement layer at all, so it is identical on both.
# macOS system bash (3.2) never showed this; every ubuntu runner and every homebrew bash does.
subst() { # subst <template> <placeholder> <replacement>
  local t="$1" p="$2" r="$3" out=""
  while :; do
    case "$t" in
      *"$p"*) out="$out${t%%"$p"*}$r"; t="${t#*"$p"}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$out$t"
}

# The shasum/sha256sum picker tools/mutation-sweep.sh already uses: shasum ships with macOS and
# with the ubuntu runner's perl, sha256sum is coreutils, and this script has a bash-3.2/macOS
# lane. Prints nothing when neither exists, which every caller must treat as a refusal — an
# empty hash compared against an empty hash would agree while hashing nothing.
lean_sha256() { # lean_sha256 <file>
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  fi
}

# A markdown table in the exact bytes Prettier writes it (#439). Rows arrive on stdin as
# `| c1 | c2 | … |`, the FIRST being the header; the delimiter row is NOT supplied, because its
# dash count is a function of the widths computed here.
#
# Padded AT THE WRITE SITE rather than by running a formatter over the finished file, and that
# is forced rather than preferred: cmd_3_render re-derives the manifest on every milestone-3
# run and byte-compares it to HEAD, so a post-hoc `prettier --write` would red the milestone
# forever — gate writes unpadded, operator formats, commits, gate re-derives unpadded, diff,
# repeat. A generated table with a 64-char sha256 column differs from the formatted form on
# every single run, which is why single-space padding was never a cosmetic choice here.
#
# Width = max(3, longest cell in the column, header included); one space each side of every
# cell; the delimiter carries exactly `width` dashes. Measured against prettier 3.7.4 — the
# version verifyctl.sh pins as its own fallback.
#
# CHARACTER count, not display width. Prettier pads by display width, so a wide-glyph route or
# state cell would mis-pad; the cost is one red format check on the branch that introduced it,
# never a mis-read artifact, and every cell this gate writes today (RS-n, a route, a state, a
# path, a hex digest) is ASCII.
#
# NO ESCAPE HANDLING for a literal `|` inside a cell, and this flank is worse than the one above
# rather than the same size. `RS-n`, the png path and the digest are gate-derived, but `route`
# and `state` come from author-written RS rows in the spec, so a pipe in either splits the column
# here AND shifts render_manifest_rows' positional read — a mis-parsed receipt, not just a red
# format check. Untreated deliberately: markdown's own answer (`\|`) would have to round-trip
# through both the padder and the reader, and no consumer has produced such a cell. An author who
# does gets a receipt whose png/sha columns have moved, which the milestone-3 re-derive surfaces
# immediately rather than silently.
md_table_prettier() {
  awk -F'|' '
    /\|/ {
      nr++
      for (i = 2; i < NF; i++) {
        c = $i
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
        cell[nr, i - 1] = c
        if (length(c) > w[i - 1]) w[i - 1] = length(c)
        if (i - 1 > cols) cols = i - 1
      }
    }
    END {
      for (j = 1; j <= cols; j++) if (w[j] < 3) w[j] = 3
      for (r = 1; r <= nr; r++) {
        line = "|"
        for (j = 1; j <= cols; j++) line = line sprintf(" %-" w[j] "s |", cell[r, j])
        print line
        if (r == 1) {
          line = "|"
          for (j = 1; j <= cols; j++) {
            d = ""
            while (length(d) < w[j]) d = d "-"
            line = line " " d " |"
          }
          print line
        }
      }
    }
  '
}

# The prettier binary this gate may run on an artifact IT AUTHORED (#439, D-5). Prints the
# invocation path, or nothing when none resolves — which every caller must treat as "skip the
# format step", never as a failure: an absent formatter is a consumer fact, not a run defect.
#
# Two rungs, and the omission of a third is the design. verifyctl.sh's ladder ends in
# `npx --yes prettier@x`; that rung is deliberately NOT carried here, because a gate call must
# not reach the network. The two rungs it does carry are held in lockstep with that ladder.
#
# `commands.<repo>.format` cannot supply this: in at least one consumer it is bound to the
# CHECK variant (`yarn format:check`), and the shipped config-lint fixture carries exactly
# that. No new config key either — this resolver needs no consumer onboarding to work.
lean_resolve_prettier() {
  local wt="$REPO_ROOT" mr="$MAIN_ROOT"
  # LOCKSTEP-BEGIN prettier-local-rungs
  if [[ -x "$wt/node_modules/.bin/prettier" ]]; then
    printf '%s\n' "$wt/node_modules/.bin/prettier"
    return 0
  fi
  if [[ -x "$mr/node_modules/.bin/prettier" ]]; then
    printf '%s\n' "$mr/node_modules/.bin/prettier"
    return 0
  fi
  # LOCKSTEP-END prettier-local-rungs
  return 1
}

# Every header key cmd_verdict emits in `key: value` form. The list exists so the format step
# below can prove it damaged none of them; it is the writer's own emission set, so a key added
# to the record must be added here too or the guard silently stops covering it.
LEAN_VERDICT_HEADER_KEYS="run_id session_id rounds pr reviewed_head reviewed_patch_id inherited_patch_id inherited_from_verdict fidelity model"

# Format the verdict record, best-effort, and never at the cost of its header contract (#439,
# D-4/D-6). Padding cannot help here the way it does for the manifest: the body is arbitrary
# reviewer-authored markdown, table-heavy by convention, so an external formatter is the only
# thing that can produce the form a consumer's `--check` wants.
#
# VERIFY-AND-REVERT, because the header is a contract and not prose. `header_key` is
# `^key:`-anchored across three lockstep readers, and prettier under `proseWrap: "always"`
# joins the whole header block into one line — measured — which silently degrades the round to
# a chain root and drops `fidelity:`. So the pre-format bytes are kept, every emitted key is
# re-read afterwards, and any mismatch restores them. A red `format:check` costs one CI run; a
# header this step flattened would cost the round's evidence.
#
# Never fails the call. A formatter that is absent, or that exits non-zero, or that damages the
# header, all land on the same posture: keep the record readable, warn once, continue.
lean_format_verdict_record() { # lean_format_verdict_record <path>
  local f="$1" pf tmp k b a
  pf="$(lean_resolve_prettier)" || pf=""
  if [ -z "$pf" ]; then
    warn "verdict: no prettier under $REPO_ROOT/node_modules/.bin or $MAIN_ROOT/node_modules/.bin — $VERDICT_REL is written unformatted, and this gate does not reach the network to fetch one. If this repo's format gate covers $PLANS_DIR, format the record before committing it."
    return 0
  fi
  tmp="$(mktemp 2>/dev/null)" || { warn "verdict: cannot stage a pre-format copy of $VERDICT_REL — leaving it unformatted."; return 0; }
  cp "$f" "$tmp" 2>/dev/null || { rm -f "$tmp"; warn "verdict: cannot stage a pre-format copy of $VERDICT_REL — leaving it unformatted."; return 0; }
  if ! "$pf" --write "$f" >/dev/null 2>&1; then
    cp "$tmp" "$f" 2>/dev/null; rm -f "$tmp"
    warn "verdict: '$pf --write' failed on $VERDICT_REL — the unformatted record is kept."
    return 0
  fi
  for k in $LEAN_VERDICT_HEADER_KEYS; do
    b="$(header_key "$k" < "$tmp")"
    a="$(header_key "$k" < "$f")"
    if [ "$b" != "$a" ]; then
      cp "$tmp" "$f" 2>/dev/null; rm -f "$tmp"
      warn "verdict: formatting $VERDICT_REL changed header key '$k' ('${b:-<none>}' » '${a:-<none>}') — the unformatted record is kept. A prettier config that reflows the header block (proseWrap: \"always\" does) cannot be applied to this artifact; the record's schema wins over the repo's format gate."
      return 0
    fi
  done
  if [ "$(record_verdict "$tmp")" != "$(record_verdict "$f")" ]; then
    cp "$tmp" "$f" 2>/dev/null; rm -f "$tmp"
    warn "verdict: formatting $VERDICT_REL changed the 'verdict=' line — the unformatted record is kept."
    return 0
  fi
  rm -f "$tmp"
  say "  formatted with $pf"
  return 0
}

# The manifest's rows as `RS-n<TAB>pngPath<TAB>sha256`. The `RS-[0-9]+` anchor is what keeps the
# markdown header and separator rows out of the result without a line counter.
render_manifest_rows() {
  [ -f "$REPO_ROOT/$RENDER_MANIFEST_REL" ] || return 0
  awk -F'|' '
    /^[[:space:]]*\|[[:space:]]*RS-[0-9]+[[:space:]]*\|/ {
      id = $2; png = $5; sha = $6
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", png)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", sha)
      printf "%s\t%s\t%s\n", id, png, sha
    }
  ' "$REPO_ROOT/$RENDER_MANIFEST_REL"
}

# Every manifested PNG exists, is non-empty, and still hashes to its recorded value. This is the
# PRE-VERDICT half of D-9's idempotence: before a verdict exists the bytes are the evidence a
# reviewer is about to read, so they must actually be there. After an approve they are not
# consulted at all — see cmd_3_render.
render_bytes_ok() {
  local rows id png sha cur n=0
  rows="$(render_manifest_rows)"
  [ -n "$rows" ] || return 1
  while IFS="$(printf '\t')" read -r id png sha; do
    [ -n "$id" ] || continue
    n=$((n + 1))
    [ -s "$REPO_ROOT/$png" ] || return 1
    cur="$(lean_sha256 "$REPO_ROOT/$png")"
    [ -n "$cur" ] && [ "$cur" = "$sha" ] || return 1
  done <<<"$rows"
  [ "$n" -gt 0 ]
}

# The armed render pass. Returns 0 when the milestone may continue, or fail_milestone's own code
# (1 or 4) when it may not — cmd_3 propagates it verbatim rather than re-deciding.
cmd_3_render() {
  local dstate rows n_rows nondefault=0 cur prev out_dir rc
  local r_id r_route r_state png sha ecmd dup manifest_rows="" seen="" seen_ids=""

  dstate="$(design_state "$REPO_ROOT/$SPEC_REL")"
  case "$dstate" in
    error:*) fail_milestone 3 "${dstate#error:}"; return $? ;;
    unarmed) return 0 ;;
    disarmed)
      # The second half of the state lock. Milestone 1 refuses this too, and the duplication is
      # deliberate: milestone 3 is the milestone that WROTE the armed record, and a run resumed
      # straight into the green gate must not walk past a disarm because nobody re-ran 1.
      design_was_armed && { fail_milestone 3 "$(design_disarm_locked_msg)"; return $?; }
      say "milestone-3: design lane disarmed for this ticket ($SPEC_REL declares 'Design: none') — no render pass."
      return 0 ;;
  esac

  # ARMED from here down. The record is written FIRST, before any assertion can red, because it
  # is the state lock and not a result: a run that armed and then failed its render must still
  # be unable to disarm its way out on the next attempt.
  ensure_progress_file
  if ! design_was_armed; then
    append_line "$(now_iso) | milestone-3 | armed | design render lane armed by $SPEC_REL"
  fi

  [ -n "$LR_COMMAND" ] \
    || { fail_milestone 3 "spec $SPEC_REL arms the design render lane, but the config declares no design.liveRender.command — the harness that owns boot, auth and screenshot is the consumer's, and there is nothing to run. Configure it (docs/live-render.md) or disarm the ticket."; return $?; }

  # cwd names a topology repo; this gate runs in ONE repo's worktree and cannot cd into a
  # sibling's checkout the way the staged lane's orchestrator could. Name the limitation rather
  # than silently rendering the wrong tree.
  if [ -n "$LR_CWD" ] && [ "$LR_CWD" != "$REPO_SLUG" ]; then
    fail_milestone 3 "design.liveRender.cwd names topology repo '$LR_CWD', but this lean run hosts '$REPO_SLUG' — run the lean lane from the repo that owns the render harness. The lean lane works one repo's worktree; it does not drive a sibling checkout."
    return $?
  fi

  case "$LR_COMMAND" in
    *'{out}'*) : ;;
    *) fail_milestone 3 "design.liveRender.command declares no {out} placeholder, so there is nowhere for the screenshot to land and nothing to hash: '$LR_COMMAND'"; return $? ;;
  esac

  rows="$(design_rs_rows < "$REPO_ROOT/$SPEC_REL")"
  n_rows="$(printf '%s\n' "$rows" | grep -c .)" || n_rows=0
  [ "${n_rows:-0}" -ge 1 ] \
    || { fail_milestone 3 "the '## Design' section of $SPEC_REL declares no well-formed '| RS-n | route | state | AC refs |' row — every cell of a row must be non-empty."; return $?; }

  while IFS="$(printf '\t')" read -r r_id r_route r_state; do
    [ -n "$r_id" ] || continue
    # The RS id is also the PNG filename, so a repeated id is destructive rather than merely
    # untidy: the second render overwrites the first, the manifest then carries two rows
    # pointing at one file, and the reviewer's hash check fails on whichever row lost. Refused
    # here, where the fix is one character in the spec.
    case " $seen_ids " in
      *" $r_id "*) fail_milestone 3 "$SPEC_REL declares the render state id '$r_id' twice. Ids are unique per ticket — each names its own screenshot file, so a repeat silently overwrites the earlier row's evidence."; return $? ;;
    esac
    seen_ids="$seen_ids $r_id"
    case "$(printf '%s' "$r_state" | tr '[:upper:]' '[:lower:]')" in
      default) : ;;
      *) nondefault=1 ;;
    esac
  done <<<"$rows"
  if [ "$nondefault" -eq 1 ]; then
    case "$LR_COMMAND" in
      *'{state}'*) : ;;
      *) fail_milestone 3 "$SPEC_REL declares a non-default render state, but design.liveRender.command carries no {state} placeholder, so the harness would screenshot the default view for every row: '$LR_COMMAND'. Add {state} and have the harness drive the named state, or re-scope the table to the default state alone."; return $? ;;
    esac
  fi

  # PNG bytes never enter history (D-4). The assertion is on the OUTPUT PATH, not on what
  # happens to be in the tree, so it holds before the first render as well as after.
  if ! git -C "$REPO_ROOT" check-ignore -q "$RENDER_OUT_REL" 2>/dev/null; then
    fail_milestone 3 "render output path '$RENDER_OUT_REL' is not git-ignored, and screenshot bytes must never enter history. Add this line to .gitignore: .claude/lean-renders/"
    return $?
  fi

  cur="$(render_patch_id HEAD)"
  [ -n "$cur" ] \
    || { fail_milestone 3 "cannot compute this branch's render patch identity against origin/$BASE_BRANCH — the merge-base is unresolvable, or the branch's diff excluding $VERDICT_REL and $RENDER_MANIFEST_REL is empty. Fetch origin/$BASE_BRANCH and re-run; a binding that cannot be computed must not be recorded."; return $?; }
  prev="$(record_key rendered_from "$REPO_ROOT/$RENDER_MANIFEST_REL")"

  # (a) POST-APPROVE (D-9). The id match ALONE, with no PNG-byte dependency, and this asymmetry
  # is load-bearing in two directions. The mandated pre-close `bash G all` sweep runs after the
  # verdict lands: re-rendering there would rewrite the manifest, the manifest is inside
  # `reviewed_patch_id`, and the run would void the approve it just earned — a livelock no fix
  # can clear. And a resume in a fresh worktree has no PNGs at all, while the evidence they back
  # is committed, reviewed and unchanged.
  if [ "$(record_verdict "$REPO_ROOT/$VERDICT_REL")" = "approve" ] && [ -n "$prev" ] && [ "$prev" = "$cur" ]; then
    say "milestone-3: render evidence current (rendered_from $(printf '%.12s' "$cur")) and this round is approved — not re-rendering."
    return 0
  fi

  # (b) PRE-VERDICT: the same binding PLUS the bytes, because the bytes are what a review round
  # is about to hash and read.
  if [ -n "$prev" ] && [ "$prev" = "$cur" ] && render_bytes_ok; then
    say "milestone-3: render evidence current for $n_rows state(s) (rendered_from $(printf '%.12s' "$cur")) — not re-rendering."
    return 0
  fi

  # (c) RENDER.
  if [ -n "$LR_READY_PROBE" ]; then
    say "milestone-3: readyProbe » $LR_READY_PROBE"
    if ! "$CURL_CLI" -fsS --max-time 10 -o /dev/null "$LR_READY_PROBE" >/dev/null 2>&1; then
      fail_milestone 3 "design.liveRender.readyProbe '$LR_READY_PROBE' is not reachable — the render harness's declared external prerequisite is down. Start it and re-run. (This fails fast on purpose: waiting out a render timeout costs the same attempt and tells you less.)"
      return $?
    fi
  fi

  out_dir="$REPO_ROOT/$RENDER_OUT_REL"
  mkdir -p "$out_dir" || { fail_milestone 3 "cannot create the render output dir '$out_dir'"; return $?; }

  while IFS="$(printf '\t')" read -r r_id r_route r_state; do
    [ -n "$r_id" ] || continue
    png="$out_dir/$r_id.png"
    rm -f "$png"
    ecmd="$LR_COMMAND"
    ecmd="$(subst "$ecmd" '{route}' "$(shquote "$r_route")")"
    ecmd="$(subst "$ecmd" '{state}' "$(shquote "$r_state")")"
    ecmd="$(subst "$ecmd" '{out}' "$(shquote "$png")")"
    say "milestone-3: render $r_id ($r_route » $r_state) » $ecmd"
    # SEAM-SCRUBBED like every other lane child cmd_3 spawns: a consumer's render script is
    # ordinary repo tooling and must not inherit this gate's pipeline-seam env.
    ( cd "$REPO_ROOT" && env ${SEAM_SCRUB_ENV[@]+"${SEAM_SCRUB_ENV[@]}"} bash -c "$ecmd" ); rc=$?
    [ "$rc" -eq 0 ] \
      || { fail_milestone 3 "render $r_id ($r_route » $r_state) failed (rc=$rc): $ecmd"; return $?; }
    [ -s "$png" ] \
      || { fail_milestone 3 "render $r_id ($r_route » $r_state) exited 0 but wrote no PNG bytes at $png — the harness must emit exactly one non-empty screenshot at {out}."; return $?; }
    sha="$(lean_sha256 "$png")"
    [ -n "$sha" ] \
      || { fail_milestone 3 "cannot hash $png — neither shasum nor sha256sum is on PATH, so no render receipt can be written. Install one and re-run."; return $?; }
    # The {state}-BLIND-HARNESS detector. Two rows that name different states and produce
    # byte-identical screenshots mean the harness ignored {state} and shot the same view twice —
    # which is failure class (2) verbatim, and passes every other assertion here. This assumes
    # byte-deterministic rendering; when a collision is legitimate the remedy is merging or
    # re-scoping the rows, never suppressing the check.
    dup="$(printf '%s\n' "$seen" | awk -v s="$sha" '$1 == s { print $2; exit }')"
    [ -z "$dup" ] \
      || { fail_milestone 3 "render states $dup and $r_id hash identically ($(printf '%.12s' "$sha")) — the harness rendered the same view for two different declared states, so one of them verifies nothing. Drive {state} in the harness, or merge the rows if the states are genuinely one view."; return $?; }
    seen="$seen$sha $r_id
"
    manifest_rows="$manifest_rows| $r_id | $r_route | $r_state | $RENDER_OUT_REL/$r_id.png | $sha |
"
  done <<<"$rows"

  {
    echo "# lean render manifest — #$ISSUE"
    echo ""
    echo "rendered_from: $cur"
    echo "issue: $ISSUE"
    echo "spec: $SPEC_REL"
    echo ""
    { echo "| RS | route | state | png | sha256 |"; printf '%s' "$manifest_rows"; } | md_table_prettier
  } > "$REPO_ROOT/$RENDER_MANIFEST_REL" \
    || { fail_milestone 3 "cannot write the render manifest at $RENDER_MANIFEST_REL"; return $?; }

  # RED UNTIL COMMITTED, and both readings of "not committed" have to fail — the same pair
  # milestone 4 makes about the verdict record. An untracked file has no commit; a tracked one
  # can differ from the bytes anyone committed. Downstream (the reviewer, and the merge boundary)
  # sees only what is on the branch.
  if [ -z "$(git -C "$REPO_ROOT" log -1 --format=%H -- "$RENDER_MANIFEST_REL" 2>/dev/null)" ] \
     || ! git -C "$REPO_ROOT" diff --quiet HEAD -- "$RENDER_MANIFEST_REL" 2>/dev/null; then
    fail_milestone 3 "render receipt written to $RENDER_MANIFEST_REL ($n_rows state(s), rendered_from $(printf '%.12s' "$cur")) — commit it and re-run milestone 3. It sits inside reviewed_patch_id by design, so the verdict binds to the evidence it was scored against; if a verdict already approves this branch, this rewrite moves that id and voids it, costing one review round. The receipt is written pre-formatted, but the spec and any intent-gap record are NOT — format those yourself before committing if this repo's format gate covers $PLANS_DIR."
    return $?
  fi

  say "milestone-3: rendered $n_rows state(s) into $RENDER_OUT_REL and recorded them in $RENDER_MANIFEST_REL."
  return 0
}

cmd_3() {
  local cmd rc sweep any_verifying=0
  # lanes[] setup steps first, when present. Shape is {name, cwd?, commands[]} — the SAME
  # reader verifyctl.sh uses (its step 1), including the non-object backstop (#100): a lane
  # that is not an object must fail loudly, never be silently skipped on the way to green.
  # Reading `.command // .` instead emits the whole lane object as the command, which is a
  # bash syntax error on every schema-valid config that declares a lane.
  if [ -f "$CONFIG" ]; then
    local lane_count li lane_type lane_name lane_cwd lane_dir lane_cmds lc_i
    lane_count="$(jq --arg s "$REPO_SLUG" '(.commands[$s].lanes // []) | length' "$CONFIG" 2>/dev/null)"
    [ -n "$lane_count" ] || lane_count=0
    for (( li=0; li<lane_count; li++ )); do
      lane_type="$(jq -r --arg s "$REPO_SLUG" --argjson i "$li" '(.commands[$s].lanes)[$i] | type' "$CONFIG" 2>/dev/null)"
      [ "$lane_type" = "object" ] \
        || { fail_milestone 3 "setup lane [$li]: must be an object {name, cwd?, commands[]}, got $lane_type"; return $?; }
      lane_name="$(jq -r --arg s "$REPO_SLUG" --argjson i "$li" '(.commands[$s].lanes)[$i].name // empty' "$CONFIG" 2>/dev/null)"
      [ -n "$lane_name" ] || { fail_milestone 3 "setup lane [$li]: missing 'name'"; return $?; }
      lane_cwd="$(jq -r --arg s "$REPO_SLUG" --argjson i "$li" '(.commands[$s].lanes)[$i].cwd // ""' "$CONFIG" 2>/dev/null)"
      lane_dir="$REPO_ROOT${lane_cwd:+/$lane_cwd}"
      lane_cmds="$(jq -r --arg s "$REPO_SLUG" --argjson i "$li" '((.commands[$s].lanes)[$i].commands // []) | length' "$CONFIG" 2>/dev/null)"
      # The same non-empty guard extraLanes carries. config-lint only requires `commands` to be
      # non-empty WHEN PRESENT, so `{name: "x"}` is lint-clean — and a zero-iteration inner loop
      # would skip it in silence, which is the shape of "green having verified nothing" this
      # whole block was rewritten to stop.
      [ "$lane_cmds" -gt 0 ] \
        || { fail_milestone 3 "setup lane [$li] ('$lane_name'): 'commands' must be a non-empty array"; return $?; }
      for (( lc_i=0; lc_i<lane_cmds; lc_i++ )); do
        cmd="$(jq -r --arg s "$REPO_SLUG" --argjson i "$li" --argjson j "$lc_i" '(.commands[$s].lanes)[$i].commands[$j]' "$CONFIG" 2>/dev/null)"
        [ -n "$cmd" ] || continue
        say "milestone-3: lane:$lane_name » $cmd"
        ( cd "$lane_dir" && env ${SEAM_SCRUB_ENV[@]+"${SEAM_SCRUB_ENV[@]}"} bash -c "$cmd" ); rc=$?
        [ "$rc" -eq 0 ] || { fail_milestone 3 "lane '$lane_name' failed (rc=$rc): $cmd"; return $?; }
      done
    done
  fi

  local key
  for key in lint typecheck test; do
    cmd="$(cfg ".commands[\"$REPO_SLUG\"].$key" '')"
    [ -n "$cmd" ] || { say "milestone-3: $key is null — skipped."; continue; }
    any_verifying=1
    say "milestone-3: $key » $cmd"
    ( cd "$REPO_ROOT" && env ${SEAM_SCRUB_ENV[@]+"${SEAM_SCRUB_ENV[@]}"} bash -c "$cmd" ); rc=$?
    [ "$rc" -eq 0 ] || { fail_milestone 3 "$key failed (rc=$rc)"; return $?; }
  done

  # ---- extraLanes (EP-2) ---------------------------------------------------------
  # Additive verify lanes: the schema's slot for everything config-lint forces out of the
  # fixed keys (build lanes, path-scoped suites, a design-driven live-render lane). Run
  # sequentially AFTER the fixed keys and BEFORE the mutation sweep (AC-6), in declaration
  # order, fail-fast — the same placement verifyctl.sh gives them.
  local el_lanes="[]" el_count=0
  if [ -f "$CONFIG" ]; then
    el_lanes="$(jq -c --arg s "$REPO_SLUG" '(.commands[$s].extraLanes // [])' "$CONFIG" 2>/dev/null)"
    [ -n "$el_lanes" ] && [ "$el_lanes" != "null" ] || el_lanes="[]"
  fi
  el_count="$(jq 'length' <<<"$el_lanes" 2>/dev/null)"
  [ -n "$el_count" ] || el_count=0

  # #392: milestone 3 must not report green having verified nothing. "Configured" is a
  # config-TIME predicate — the fixed keys above and extraLanes' array LENGTH, not whether a
  # when-scoped lane happened to run on this diff (AC-3: configured-but-skipped is not
  # unverified, so this check runs before extraLanes execution and reads $el_count, never the
  # diff). Setup `lanes[]` are INFRA-classed and the mutation sweep is repo-carried, not
  # config — neither counts, matching the staged lane's `allowUnverified` valve, which is
  # inert as soon as any verifying lane is configured (#98). Checked here, before the
  # mutation sweep, so a red never pays for a sweep run it was always going to discard.
  if [ "$any_verifying" -eq 0 ] && [ "$el_count" -eq 0 ]; then
    local allow_unverified
    allow_unverified="$(cfg ".commands[\"$REPO_SLUG\"].allowUnverified" 'false')"
    if [ "$allow_unverified" = "true" ]; then
      say "milestone-3: no verifying lane configured for '$REPO_SLUG' (lint/typecheck/test all null, extraLanes empty) — allowUnverified opt-out is set (config: $CONFIG)."
      append_line "$(now_iso) | milestone-3 | skipped | no verifying lane configured — allowUnverified opt-out"
    else
      fail_milestone 3 "no verifying lane configured for '$REPO_SLUG' (lint/typecheck/test all null, extraLanes empty) — config read from $CONFIG. Configure a verify lane, or set commands.$REPO_SLUG.allowUnverified=true to declare the opt-out."
      return $?
    fi
  fi

  if [ "$el_count" -gt 0 ]; then
    local el_i el_diff="" el_diff_rc="" el_diff_done=0
    for (( el_i=0; el_i<el_count; el_i++ )); do
      local el_type el_name el_cmd_count el_when_count el_run
      # Shape backstop (AC-7): nothing in this lane ever runs config-lint, so this is the
      # only shape guard extraLanes gets here. A non-object entry, or one missing `name` or
      # a non-empty `commands`, reds milestone 3 naming the entry INDEX — mirroring the hole
      # verifyctl.sh grew this same guard for (#100).
      el_type="$(jq -r --argjson i "$el_i" '.[$i] | type' <<<"$el_lanes")"
      if [ "$el_type" != "object" ]; then
        fail_milestone 3 "extraLanes[$el_i]: must be an object {name, when?, commands[], failureClass}, got $el_type"; return $?
      fi
      el_name="$(jq -r --argjson i "$el_i" '.[$i].name // empty' <<<"$el_lanes")"
      [ -n "$el_name" ] || { fail_milestone 3 "extraLanes[$el_i]: missing 'name'"; return $?; }
      el_cmd_count="$(jq -r --argjson i "$el_i" '(.[$i].commands // []) | length' <<<"$el_lanes")"
      [ "$el_cmd_count" -gt 0 ] || { fail_milestone 3 "extraLanes[$el_i] ('$el_name'): 'commands' must be a non-empty array"; return $?; }

      el_when_count="$(jq -r --argjson i "$el_i" '(.[$i].when // []) | length' <<<"$el_lanes")"
      el_run=1
      if [ "$el_when_count" -gt 0 ]; then
        if [ "$el_diff_done" -eq 0 ]; then
          el_diff="$(lean_extra_lanes_diff)"; el_diff_rc=$?; el_diff_done=1
        fi
        if [ "$el_diff_rc" -ne 0 ]; then
          fail_milestone 3 "extraLanes[$el_i] ('$el_name'): cannot resolve origin/$BASE_BRANCH to evaluate 'when' — fetch it and re-run"; return $?
        fi
        el_run=0
        local wi wglob
        for (( wi=0; wi<el_when_count; wi++ )); do
          wglob="$(jq -r --argjson i "$el_i" --argjson j "$wi" '.[$i].when[$j]' <<<"$el_lanes")"
          if lean_when_matches "$wglob" "$el_diff"; then el_run=1; break; fi
        done
      fi

      if [ "$el_run" -ne 1 ]; then
        say "milestone-3: extra lane '$el_name' — skipped (no changed path matches when[])"
        append_line "$(now_iso) | milestone-3 | skipped | extra lane '$el_name' — no changed path matches when[]"
        continue
      fi

      local el_ci el_cmd
      for (( el_ci=0; el_ci<el_cmd_count; el_ci++ )); do
        el_cmd="$(jq -r --argjson i "$el_i" --argjson j "$el_ci" '.[$i].commands[$j]' <<<"$el_lanes")"
        say "milestone-3: extra lane '$el_name' » $el_cmd"
        ( cd "$REPO_ROOT" && env ${SEAM_SCRUB_ENV[@]+"${SEAM_SCRUB_ENV[@]}"} bash -c "$el_cmd" ); rc=$?
        [ "$rc" -eq 0 ] || { fail_milestone 3 "extra lane '$el_name' failed (rc=$rc): $el_cmd"; return $?; }
      done
    done
  fi

  # ---- design live-render (#394) -------------------------------------------------
  # After extraLanes, before the mutation sweep — the same slot, and for the same reason, that
  # extraLanes took after the fixed keys: cheap deterministic lanes first, then the expensive
  # ones. A no-op on every unarmed run, which is every run in a repo with no design.provider.
  cmd_3_render; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"

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
  local v_inh v_chain v_coverage
  # The handoff moment, and so the one place the P9 reminder is contextual rather than noise.
  # It lives here rather than as another SKILL.md line for the reason the cap exists: stderr is
  # read exactly when it applies, prose is read on every run. NO DETECTION happens here — the
  # refusal is the merge boundary's alone (check-lean-chain.sh evidence 6), and a second in-run
  # copy would be the duplicate machinery D-47 rules out, not defense in depth.
  [ -f "$rec" ] || { fail_milestone 4 "no committed verdict record at $VERDICT_REL — hand off to '/dev-pipeline:review-lean <pr>'. If this run wrote an intent-gap record, ratify it before that handoff: the merge boundary refuses one still reading 'ratified: no'." 5; return $?; }
  v_val="$(record_verdict "$rec")"
  if [ "$v_val" != "approve" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL reads verdict=${v_val:-<none>}, not verdict=approve" 1; return $?
  fi
  # The reconciliation keys are what make the record checkable against the audit ledger.
  v_run="$(record_key run_id "$rec")"
  v_sess="$(record_key session_id "$rec")"
  if [ -z "$v_run" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL carries no run_id reconciliation key" 5; return $?
  fi
  if [ -z "$v_sess" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL carries no session_id reconciliation key — the review session's audit ledger cannot be located, so the verdict is unreconcilable" 5; return $?
  fi
  # The DECLARED reviewed head. Absent is refused for the same reason a missing verdict is:
  # nothing is checkable, and an uncheckable claim must not read as a satisfied one. Records
  # written before this key existed are refused too — the remedy is a review round on a
  # refreshed plugin, which is always available, so no transitional pass is warranted.
  v_head="$(record_key reviewed_head "$rec")"
  if [ -z "$v_head" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL carries no reviewed_head key, so nothing states which commit the review actually read. Re-run the review round on a dev-pipeline that writes it: '/dev-pipeline:review-lean <pr>'." 5; return $?
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
      fail_milestone 4 "verdict record $VERDICT_REL carries the BUILD run's identity ('$v_run') — the session that wrote the code may not author its own review verdict (P10). Produce the record from a separate review session: 'lean-gate.sh verdict $ISSUE --pr <n> --verdict approve'." 6
      return $?
    fi
  done
  if [ -n "$b_prog_sess" ] && [ "$v_sess" = "$b_prog_sess" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL names the BUILD session ('$v_sess') as its author — the review must run in a separate context (P10)." 6
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
    fail_milestone 4 "verdict record $VERDICT_REL exists but was never committed — a local file is not evidence, and nothing downstream can see it. Commit and push it to the PR's head branch. The gate formats this record itself when a local prettier resolves; the spec and any intent-gap record it does not, so format those before committing if this repo's format gate covers $PLANS_DIR." 5
    return $?
  fi
  # Tracked-but-dirty is its own case, and the one a bare `git log` lookup misses: the path has
  # a commit, so the lookup above is satisfied, while the bytes being READ are not the bytes
  # anyone committed. Both readings of "not committed" have to fail.
  if ! git -C "$REPO_ROOT" diff --quiet HEAD -- "$VERDICT_REL" 2>/dev/null; then
    fail_milestone 4 "verdict record $VERDICT_REL has uncommitted changes — the record being read is not the record on the branch, so the one downstream sees is a different file. Commit and push it, along with any spec or intent-gap record this repo's format gate expects formatted (the gate formats only what it authors)." 5
    return $?
  fi

  # THE INHERITANCE CHAIN (#375). A record that claims inherited coverage is worth exactly what
  # its link is worth: an unverifiable one credits a round with a tree it never read. Absence is
  # the ordinary case and passes silently — chain roots, and every record predating the key,
  # carry no claim to check. That is what makes this additive.
  #
  # Placed AFTER the two existence arms above and BEFORE the freshness arms below, which is the
  # order the questions actually stack: is this record on the branch at all, then what does it
  # claim to cover, then does that cover the tree in front of us. Asking the middle question
  # first was wrong in a way only a fixture shows: the walk's search window is anchored at the
  # commit carrying the record, so an UNCOMMITTED round-2 record anchors on the PRIOR round's
  # commit, the window trims that round away, and the legitimate link it declares matches
  # nothing left. The refusal was fail-closed but sent the reviewer to redo a round over a
  # record whose only defect was that nobody had run `git commit`.
  #
  # $v_commit is reused rather than re-derived for the same reason: the arm above has already
  # established that a commit carries this record, so a second lookup could only disagree.
  v_inh="$(inherited_key < "$rec")"
  v_coverage="covering the whole branch diff on its own"
  if [ -n "$v_inh" ]; then
    v_chain="$(chain_walk "$v_inh" "$(record_key rounds "$rec")" "$v_commit")"
    case "$v_chain" in
      "ok "*) v_coverage="inheriting ${v_chain#ok } verified earlier round(s)" ;;
      *)      fail_milestone 4 "verdict record $VERDICT_REL: ${v_chain#break } Get a review round that reads the full diff: '/dev-pipeline:review-lean <pr>'." 5
              return $? ;;
    esac
  fi

  stale="$(git -C "$REPO_ROOT" diff --name-only "$v_commit" HEAD 2>/dev/null | grep -vxF "$VERDICT_REL")"
  if [ -n "$stale" ]; then
    v_short="$(git -C "$REPO_ROOT" rev-parse --short "$v_commit" 2>/dev/null)"
    n_stale="$(printf '%s\n' "$stale" | wc -l | tr -d ' ')"
    fail_milestone 4 "verdict record $VERDICT_REL approves $v_short, but $n_stale file(s) changed after it (e.g. $(printf '%s' "$stale" | head -n1)) — a verdict does not cover code it never saw. Get a new review round on the current head: '/dev-pipeline:review-lean <pr>'." 5
    return $?
  fi

  # DESIGN FIDELITY (#394, D-7/D-10). Placed AFTER the inferred freshness arm and before the
  # declared ones, which is one site covering both declared exits — and the order is the point,
  # not tidiness. A commit landing after the verdict moves BOTH the reviewed patch and the render
  # binding, so an earlier placement would report a stale manifest for a tree whose real defect
  # is a stale verdict: the same "one fact printed as three violations" the merge boundary had to
  # unpick. What survives this ordering is exactly D-10's case — a reviewer who scored round-1
  # screenshots against round-2 code and committed an honest record on the round-2 head. Nothing
  # else is stale there, and the manifest is the only thing that can say so.
  #
  # The armed requirement is `pass` and nothing else, INCLUDING absence: a record with no
  # fidelity key on an armed run was written by a review round that never scored the design,
  # which is failure class (3) with a different reader. The unarmed allowance is the transition
  # — records predating the key carry none — but a value that IS present must be
  # `not-applicable`, so a `pass` cannot be parked on an unarmed run and inherited later.
  #
  # The manifest arm is D-10's SECOND detector, not its first: review-lean checks staleness
  # before it scores, so this is the backstop for a round that skipped that step or a fix that
  # landed between the scoring and the record.
  local d_state v_fid m_from cur_render
  d_state="$(design_state "$REPO_ROOT/$SPEC_REL")"
  v_fid="$(header_key fidelity < "$rec")"
  if [ "$d_state" = "armed" ]; then
    if [ "$v_fid" != "pass" ]; then
      fail_milestone 4 "spec $SPEC_REL arms the design render lane, but $VERDICT_REL reads fidelity=${v_fid:-<none>}, not fidelity=pass — an armed ticket is not approved until a design-sighted round scores its declared render states. Get one: '/dev-pipeline:review-lean <pr>'." 5
      return $?
    fi
    m_from="$(record_key rendered_from "$REPO_ROOT/$RENDER_MANIFEST_REL")"
    if [ -z "$m_from" ]; then
      fail_milestone 4 "spec $SPEC_REL arms the design render lane and $VERDICT_REL scores fidelity=pass, but there is no render receipt at $RENDER_MANIFEST_REL to have scored — re-run milestone 3 and commit the receipt." 1
      return $?
    fi
    cur_render="$(render_patch_id HEAD)"
    if [ -z "$cur_render" ]; then
      fail_milestone 4 "cannot compute this branch's render patch identity against origin/$BASE_BRANCH, so $RENDER_MANIFEST_REL's rendered_from has nothing to be compared against — and a freshness check that cannot run must not report a pass. Fetch origin/$BASE_BRANCH and re-run." 2
      return $?
    fi
    if [ "$m_from" != "$cur_render" ]; then
      fail_milestone 4 "$RENDER_MANIFEST_REL records rendered_from $(printf '%.12s' "$m_from"), but this branch now renders from $(printf '%.12s' "$cur_render") — the approved fidelity was scored against screenshots of different code. Re-run milestone 3, commit the fresh receipt, and get a new review round." 1
      return $?
    fi
  elif [ -n "$v_fid" ] && [ "$v_fid" != "not-applicable" ]; then
    fail_milestone 4 "$VERDICT_REL reads fidelity=$v_fid, but $SPEC_REL arms no design render lane — the only value an unarmed run may declare is 'not-applicable'." 5
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
      fail_milestone 4 "cannot compute this branch's patch identity against origin/$BASE_BRANCH, so there is nothing to compare $VERDICT_REL's reviewed_patch_id against — and a freshness check that cannot run must not report a pass. Fetch origin/$BASE_BRANCH and re-run." 2
      return $?
    fi
    if [ "$v_pid" != "$cur_pid" ]; then
      fail_milestone 4 "verdict record $VERDICT_REL reviewed patch $(printf '%.12s' "$v_pid"), but this branch's diff against origin/$BASE_BRANCH now hashes to $(printf '%.12s' "$cur_pid") — content changed after the review, so the verdict does not cover it. Get a new review round: '/dev-pipeline:review-lean <pr>'." 5
      return $?
    fi
    pass_milestone 4 "$VERDICT_REL reads verdict=approve, authored by review run $v_run, covering the current head (patch-id $(printf '%.12s' "$v_pid")), $v_coverage"
    return $?
  fi

  if ! git -C "$REPO_ROOT" cat-file -e "$v_head^{commit}" 2>/dev/null; then
    fail_milestone 4 "verdict record $VERDICT_REL names reviewed_head $v_head, which is not a commit in this branch's history — the branch was rebased or force-pushed after the review, so the reviewed code no longer exists here. Get a new review round: '/dev-pipeline:review-lean <pr>'." 5
    return $?
  fi
  declared="$(git -C "$REPO_ROOT" diff --name-only "$v_head" HEAD 2>/dev/null | grep -vxF "$VERDICT_REL")"
  if [ -n "$declared" ]; then
    v_head_short="$(git -C "$REPO_ROOT" rev-parse --short "$v_head" 2>/dev/null)"
    n_declared="$(printf '%s\n' "$declared" | wc -l | tr -d ' ')"
    fail_milestone 4 "verdict record $VERDICT_REL states it reviewed $v_head_short, but $n_declared file(s) differ between that commit and the current head (e.g. $(printf '%s' "$declared" | head -n1)) — the review read a different tree than the one being gated. Get a new review round: '/dev-pipeline:review-lean <pr>'." 5
    return $?
  fi

  pass_milestone 4 "$VERDICT_REL reads verdict=approve, authored by review run $v_run, declaring reviewed_head $(git -C "$REPO_ROOT" rev-parse --short "$v_head" 2>/dev/null) and covering the current head, $v_coverage"
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
  local cand inherited_patch_id inherited_from chain
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
  # included — into an evidence artifact.
  #
  # The old note here read "nothing escalates today, because all three readers take the FIRST
  # match of each key, so an injected `run_id:` loses to the authentic one written above it".
  # That reasoning was sound about `run_id:` and false as a statement about the SCHEMA, and the
  # difference cost a round: it holds only for keys the writer ALWAYS emits, and
  # `inherited_patch_id:` was introduced as one it emitted conditionally. A key that is absent
  # has no authentic occurrence to win the race, so the reviewer's own body supplied the value —
  # from `--summary-file`, not from this argument, but through the same door. Both halves of the
  # fix are above: the writer emits the key unconditionally, and `inherited_key` anchors the
  # read to the header. The general rule the episode leaves behind: "harmless because of where
  # it lands in the file" is a property of a key's emission being UNCONDITIONAL, and any new
  # optional key re-opens the question for itself.
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

  # DESIGN FIDELITY (#394, D-7). Defaults to `not-applicable` rather than being required, and
  # the default is the FAIL-CLOSED side: on an armed run milestone 4 demands `pass`, so a review
  # round that forgot the flag is refused instead of certifying a design it never looked at. On
  # an unarmed run — every run in a repo with no design axis — the default is simply the truth.
  #
  # `fail` exists so a finding round can record what it found. Omitting the key on a failure
  # would leave the record silent about the one dimension it was scored on, and the next round
  # would inherit that silence.
  [ -n "$VERDICT_FIDELITY" ] || VERDICT_FIDELITY="not-applicable"
  case "$VERDICT_FIDELITY" in
    pass|fail|not-applicable) : ;;
    *) envfail "verdict: --fidelity must be 'pass', 'fail' or 'not-applicable' (got '$VERDICT_FIDELITY')." ;;
  esac
  # Refused at the WRITER, where the contradiction is one flag away from being fixed, rather
  # than only at milestone 4 where it costs the round. A design failure is a blocker by
  # definition, and a blocker is `needs-work` — review-lean's own rule, enforced here.
  if [ "$VERDICT_FIDELITY" = "fail" ] && [ "$VERDICT_VALUE" = "approve" ]; then
    warn "✗ verdict: --fidelity fail cannot accompany --verdict approve — a design-fidelity failure is a blocker, and any blocker is needs-work."
    return 1
  fi

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

  # INHERITANCE (#375), DERIVED from the branch exactly as the two keys above are derived from
  # the checkout. See the header for why this is not a flag.
  cand="$(inherit_candidate "$reviewed_patch_id" "$RESOLVED_RUN_ID" "$sess")"
  inherited_patch_id="${cand%% *}"
  inherited_from=""
  [ -n "$cand" ] && inherited_from="${cand##* }"
  # A chain is worth declaring only while every link verifies. A break DEEPER in the chain means
  # this round has nothing verifiable to inherit, so it writes a ROOT record and says so loudly.
  # Degrading toward MORE reading is the safe direction; declaring an inheritance no reader can
  # verify is not — all three readers refuse that, which would strand the round instead.
  if [ -n "$inherited_patch_id" ]; then
    chain="$(chain_walk "$inherited_patch_id" "$(record_key_at rounds "$inherited_from")")"
    case "$chain" in "ok "*) chain="" ;; *) chain="${chain#break }" ;; esac
    if [ -n "$chain" ]; then
      warn "verdict: $chain"
      warn "  This round therefore inherits nothing and is recorded as covering the FULL diff. Read it in full before trusting the record."
      inherited_patch_id=""; inherited_from=""
    fi
  fi

  body=""
  if [ -n "$SUMMARY_FILE" ]; then
    [ -f "$SUMMARY_FILE" ] || envfail "verdict: --summary-file '$SUMMARY_FILE' does not exist."
    body="$(cat "$SUMMARY_FILE")"
  fi

  resolve_capability_stamp
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
    # UNCONDITIONAL, with an explicit `none` on a chain root. A key the writer sometimes omits
    # is a key whose first occurrence in the file can be the reviewer's own prose — see
    # inherited_key. Always emitting it puts the authentic value above the body, which is the
    # property every other key in this schema already relies on, and makes "this round inherited
    # nothing" a written fact rather than something a reader infers from an absence it cannot
    # distinguish from a writer that never knew the key.
    echo "inherited_patch_id: ${inherited_patch_id:-none}"
    echo "inherited_from_verdict: ${inherited_from:-none}"
    # UNCONDITIONAL, for the reason `inherited_patch_id` is: a key the writer sometimes omits has
    # no authentic occurrence to win the first-match race, so the reviewer's own prose supplies
    # the value. Both readers additionally anchor it to the header (`header_key`), which is the
    # half of that fix covering records this writer did not produce.
    echo "fidelity: $VERDICT_FIDELITY"
    echo "model: ${LEAN_RUN_MODEL:-unknown}"
    # THE PRODUCER'S CAPABILITY STAMP (#445), with NO READER TODAY — and shipped anyway, on
    # purpose. A review-side arm bound to a capability will need to place the generation that
    # wrote the record it is reading, and a stamp introduced only when that arm lands would find
    # every older record silent and go permanently inert over them. Written now, it is simply
    # present by the time it is first read. The build-side stamp on the claim comment is what
    # arms today's one bound arm; relaying THIS one to it would let the reviewed party soften a
    # build-side arm, so no reader may key on it for that purpose.
    #
    # Comma-separated, so a future reader must widen `record_key`'s default charset (which stops
    # at `,`) rather than silently read the first token as the whole list.
    echo "$LEAN_CAPABILITY_KEY: $LEAN_CAPABILITY_STAMP"
    echo ""
    if [ -n "$body" ]; then printf '%s\n' "$body"; fi
  } > "$rec"

  # The record lands in $PLANS_DIR, which sits inside the format gate of at least one consumer,
  # and the body is reviewer-authored markdown this writer cannot pre-shape. Best-effort, and
  # header-safe — see lean_format_verdict_record.
  lean_format_verdict_record "$rec"

  say "✓ verdict: $VERDICT_REL written (verdict=$VERDICT_VALUE, run_id=$RESOLVED_RUN_ID, round $VERDICT_ROUNDS, reviewed_head=$reviewed_head, reviewed_patch_id=$reviewed_patch_id, fidelity=$VERDICT_FIDELITY)"
  if [ -n "$inherited_patch_id" ]; then
    say "  inheriting the coverage of patch $(printf '%.12s' "$inherited_patch_id") — this round's own reading is the delta since that tree."
  else
    say "  chain ROOT — this round claims coverage of the whole branch diff."
  fi
  say "  It is evidence only once COMMITTED to the PR's head branch — commit and push it."
  return 0
}

# ---------------------------------------------------------------- delta (REVIEW role)
# The range this round must READ. A round that inherits coverage reads the delta since the tree
# the inherited round covered; a round with nothing to inherit reads the whole branch diff.
#
# The anchor is resolved by PATCH IDENTITY, never by the SHA `inherited_from_verdict` names: a
# rebase replays every commit under a new SHA while leaving each replayed commit's BRANCH patch
# identity unchanged, so identity resolution survives exactly what SHA resolution does not. The
# NEWEST matching commit is taken, which is the commit carrying the prior round's record — its
# branch patch id equals the reviewed tree's because the record path is excluded from the
# measurement — so the printed delta never re-presents the prior record itself.
#
# READ-ONLY. It writes no record, appends no progress line and touches no identity cache: a
# reviewer must be able to ask what to read without that question becoming evidence of anything.
cmd_delta() {
  local base cur cand prior_pid anchor c broken this_run this_sess
  base="$(git -C "$REPO_ROOT" merge-base "origin/$BASE_BRANCH" HEAD 2>/dev/null)"
  [ -n "$base" ] \
    || envfail "delta: cannot resolve merge-base(origin/$BASE_BRANCH, HEAD) — there is no range to measure. Fetch origin/$BASE_BRANCH in this checkout and re-run."

  # This round's own identity, so the range printed here is the range the record will claim: a
  # round that anchored its READING on its own earlier version would read a narrower delta than
  # its record declares.
  #
  # Taken from the ENVIRONMENT, and emphatically not from $REVIEW_RUN_ID_CACHE. `delta` runs at
  # the START of a round and the cache is written at the END of one, so at this moment the cache
  # holds the PREVIOUS round's id — passing it would skip exactly the record this round means to
  # inherit and degrade every fix round to a full re-read, which is the cost the feature exists
  # to remove. review-lean step 1 has the round's own RUN_ID exported by the time this runs.
  # Absent (an operator poking at the range by hand) both are empty and nothing is skipped,
  # which is the pre-existing behavior.
  this_run="${RUN_ID:-}"
  this_sess="${CLAUDE_CODE_SESSION_ID:-}"

  cur="$(branch_patch_id HEAD)"
  cand="$(inherit_candidate "$cur" "$this_run" "$this_sess")"
  prior_pid="${cand%% *}"
  anchor=""

  if [ -n "$prior_pid" ]; then
    broken="$(chain_walk "$prior_pid" "$(record_key_at rounds "${cand##* }")")"
    case "$broken" in "ok "*) broken="" ;; *) broken="${broken#break }" ;; esac
    if [ -n "$broken" ]; then
      warn "delta: $broken"
      prior_pid=""
    fi
  fi

  if [ -n "$prior_pid" ]; then
    for c in $(git -C "$REPO_ROOT" rev-list "$base..HEAD" 2>/dev/null); do
      if [ "$(branch_patch_id "$c")" = "$prior_pid" ]; then anchor="$c"; break; fi
    done
  fi

  if [ -z "$anchor" ]; then
    say "delta: FULL range — nothing verifiable to inherit, so this round covers the whole branch diff."
    say "  range: $(git -C "$REPO_ROOT" rev-parse --short "$base")..HEAD"
    git -C "$REPO_ROOT" diff --name-only "$base" HEAD
    return 0
  fi

  say "delta: inheriting the coverage of patch $(printf '%.12s' "$prior_pid"). Read the range below AND the prior round's findings in $VERDICT_REL — a round that inherits coverage without seeing what was found cannot tell a fixed blocker from a re-introduced one."
  say "  range: $(git -C "$REPO_ROOT" rev-parse --short "$anchor")..HEAD"
  git -C "$REPO_ROOT" diff --name-only "$anchor" HEAD
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
    pr="$("$GH_CLI" pr list --head "$LEAN_BRANCH" --state open \
          --json number,url,body,isDraft --limit 1 2>&1)" \
      || { warn "$pr"; fail_milestone 5 "could not list PRs for $LEAN_BRANCH"; return $?; }
  fi
  printf '%s' "$pr" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { fail_milestone 5 "no open PR found for branch $LEAN_BRANCH"; return $?; }

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
    cmd_mark || { fail_milestone 5 "could not stamp the build identity on the PR"; return $?; }
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

  # The build identity, stamped on the PR (D-3). LAST, after every assertion above: a run that
  # is not going to pass milestone 5 has no business leaving a marker, and the idempotent
  # no-op means the ordinary path — where checklist step 7 already posted it — writes nothing.
  cmd_mark || { fail_milestone 5 "could not stamp the build identity on the PR"; return $?; }

  pass_milestone 5 "exit artifacts present ($url)"
}

# ---------------------------------------------------------------- all
# G-2, load-bearing: `satisfied` is a RECORD, not a CACHE. Every milestone is re-evaluated
# against the CURRENT tree on every sweep. Short-circuiting on a stored `satisfied` line is
# exactly how a green gate from before a milestone-4 fix round would certify code that
# never passed it.
#
# #497: this is also where the IN-FLIGHT PAIR is written, because it is the ONE explicit cmd_N
# dispatch — every milestone is wrapped by construction (D-5), and nothing has to be remembered at
# five separate call sites.
#
# THE OBSERVE ARM IS NOT OPTIONAL HERE, and #497's own receipt (D-10) got this wrong: it reasoned
# that cmd_all's pre-pass calls `LEAN_GATE_OBSERVE=1 cmd_1`/`cmd_4` directly and therefore bypasses
# this wrapper — true, but not the only observe path. #496 promoted the seam to a SCHEDULER read,
# and orchestrate-lean.sh's verdict_rc runs `LEAN_GATE_OBSERVE=1 bash "$GATE" 4 "$ISSUE"` as a
# TOP-LEVEL invocation, which the dispatch case at the bottom of this file routes straight through
# here. Without the arm below, every round of every lean run would have the scheduler's read
# writing build-role rows into the record — the exact "records nothing" contract #496 exists for.
# So observe PREDICTS exhaustion from the count already on file, exactly as fail_milestone and
# block_milestone do, and writes neither half of the pair.
run_milestone() {
  local n="$1" rc unclosed
  # VALIDATION FIRST, before any bookkeeping. The dispatch case at the bottom of this file routes
  # every unrecognized subcommand here, and a usage error must not bring a progress file into
  # existence or stamp `| milestone-9 | started |` on its way to exit 2.
  #
  # Explicit arms, not "cmd_$1": an indirect call hides every callee from static analysis
  # (shellcheck SC2329) and from a reader grepping for call sites.
  case "$n" in
    1|2|3|4|5) : ;;
    *) envfail "run_milestone: unknown milestone '$n'" ;;
  esac

  # Read BEFORE this call appends its own `started`, so the number is EARLIER evaluations that
  # never returned. OR-1: a concurrent in-flight call contributes 1 here and is indistinguishable
  # from an interrupted one — accepted, because the posture below is announce-not-refuse and
  # reaching the budget would need five simultaneous calls on one milestone.
  unclosed="$(unclosed_count "$n")"
  if [ "$unclosed" -gt 0 ]; then
    # ANNOUNCE, NEVER REFUSE (D-4). An interrupted milestone is precisely the one a resuming
    # session must be able to re-run, and this is the call it makes: SKILL.md's Resume step says
    # `all` stops early while milestone 4 is outstanding and to run the milestones directly, so
    # `bash G <n> <issue>` is where the notice has to land to be seen.
    warn "note: milestone-$n: $unclosed earlier evaluation(s) began and never concluded (interrupted $unclosed/$INTERRUPTED_BUDGET) — re-running it now."
  fi
  # OBSERVE: predict, never record (see the header note above). The announce is deliberately ABOVE
  # this arm — it is a stderr diagnostic and touches nothing the seam promises not to touch.
  #
  # MILESTONE 3 RUNS INLINE HERE, undetached. Observe promises to record nothing, and a detach
  # writes a pidfile, a marker and a log; more to the point, the only caller that observes is
  # cmd_all's pre-pass, which evaluates 1 and 4 alone precisely to avoid paying for milestone 3.
  # A caller that sets the seam by hand on `3` is asking to watch it, not to survive it.
  if [ "${LEAN_GATE_OBSERVE:-0}" = "1" ]; then
    [ "$unclosed" -ge "$INTERRUPTED_BUDGET" ] && return 4
    case "$n" in
      1) cmd_1 ;;
      2) cmd_2 ;;
      3) cmd_3 ;;
      4) cmd_4 ;;
      5) cmd_5 ;;
    esac
    return $?
  fi

  # THE ONE REFUSAL (D-2). Free interruption would remove the only per-milestone bound on a session
  # that backgrounds this gate and ends its turn on every continuation; charging attempt_count()
  # would bill an operator Ctrl-C against a budget that means "a fix did not work", re-conflating
  # the difficulty signal #494 spent a ticket separating. So: its own counter, its own budget, and
  # `rc=4` reused rather than a new code invented — build-lean's existing hard-stop handling
  # (append the reason, one abort comment, keep the worktree and the claim) covers it unchanged.
  if [ "$unclosed" -ge "$INTERRUPTED_BUDGET" ]; then
    append_line "$(now_iso) | milestone-$n | interrupted-exhausted | $unclosed unconcluded"
    warn "milestone-$n has been begun and cut off $unclosed times without ever concluding — hard stop."
    return 4
  fi

  # #511 D-1/D-2: milestone 3 is the one evaluation long enough to outlive a turn, so it does not
  # run in THIS process. The wrapper spawns it detached and blocks on its marker; the runner arm at
  # the top of this function writes the started/concluded pair, because a JOIN must record nothing.
  # Returning here rather than falling through is what keeps that pair single per evaluation.
  if [ "$n" = "3" ]; then
    m3_launch_or_join
    return $?
  fi

  # The append IS the flush: append_line is a single unbuffered `echo >>`, so ordering it before
  # the long work is the whole requirement (D-10). No trap closes this row on a signal (D-9) — the
  # design rests on the ABSENCE of a conclusion, a partial trap would make that absence mean two
  # different things, and SIGKILL cannot be trapped at all. An `exit` from inside a milestone body
  # (envfail) likewise leaves the row open, which is the honest record of what happened (D-12).
  append_started "$n"
  # Milestone 3 is absent by construction — it returned above. A `*)` that fell through silently
  # would turn a regression in that arm into a green milestone that never ran, so it envfails.
  case "$n" in
    1) cmd_1 ;;
    2) cmd_2 ;;
    4) cmd_4 ;;
    5) cmd_5 ;;
    *) envfail "run_milestone: milestone $n must not reach the inline dispatch" ;;
  esac
  rc=$?
  append_concluded "$n" "$rc"
  return "$rc"
}

# #374 AC-1..3: a cheap, READ-ONLY pre-pass. Milestones 1 and 4 read only committed artifacts
# and git state (AC-7 — no network, no subprocess beyond git/grep/jq via cmd_1's spec check and
# cmd_4 in full — milestone 1's pause-and-ask check is excluded, see the observe guard there), so
# evaluating them ahead of milestone 3's ~15-minute green gate costs nothing and can only report
# sooner what a later milestone would report anyway. `all` on a tree whose committed verdict
# record already reads `needs-work` used to pay the whole green gate before learning that,
# knowable, fact — the pre-pass reports it first instead.
#
# LEAN_GATE_OBSERVE=1 makes cmd_1/cmd_4 report-only (see fail_milestone/pass_milestone): neither
# consumes a fix-budget attempt nor writes a `satisfied` record here, so nothing is double-counted
# against the real calls in the loop below. Both are evaluated even when the first already failed
# (AC-3) — an operator fixing two cheap assertions should not need two runs to learn about both.
#
# #496 AC-2: THE PRE-PASS PROPAGATES THE CLASS. A pre-pass that collapsed everything to 1 would
# reintroduce, one layer up, the exact defect this taxonomy removes — `all` laundering an
# integrity refusal into "needs-work". Milestone 4's class wins when it carries one, because
# 4/5/6/2 each name a condition no milestone-1 edit can clear and each sends the operator
# somewhere different; a bare 1 from either milestone keeps the historical value.
cmd_all() {
  local n rc rc1 rc4

  LEAN_GATE_OBSERVE=1 cmd_1; rc1=$?
  LEAN_GATE_OBSERVE=1 cmd_4; rc4=$?
  if [ "$rc1" -ne 0 ] || [ "$rc4" -ne 0 ]; then
    say "all: pre-pass found an already-unsatisfiable cheap assertion — stopping before milestone-3."
    case "$rc4" in 0|1) : ;; *) return "$rc4" ;; esac
    case "$rc1" in 0|1) : ;; *) return "$rc1" ;; esac
    return 1
  fi

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
# D-4. A PRECONDITION on every build-role subcommand, evaluated before any milestone body runs.
# Exit 2, not 1: "you skipped step 1" is a usage error, not a code fix, and routing it through
# fail_milestone would charge the attempt to a milestone that did not fail — silently shortening
# the real fix budget. Placing it here rather than inside each cmd_* closes every start-at-
# milestone-N path at once, including `all`'s cheap pre-pass.
#
# `delta` is in the set even though the REVIEW session invokes it (review-lean step 4), so a
# review of an unattested build is refused with a remedy only the build side can apply. That is
# intended: a reviewer must not certify a run whose ledger never existed. `verdict` is NOT in the
# set — a symmetric review-side ledger precondition is D-5's follow-up, gated on #417, because
# review-lean step 3 works in the build run's leftover worktree and would false-red every honest
# review until that path split is fixed.
#
# The refusal names its SECOND cause too. The progress file is host-local and gitignored, so it
# never travels with the branch: from a clone that is not a worktree of the build host, an
# attested run looks identical to an unattested one, and the remedy the message gives cannot be
# applied from there. That mostly bites `delta`, which the review session runs — review-lean
# step 3 says "any checkout of that branch works", which for this one call it does not.
#
# AND IT DECLARES WHEN IT TOOK EFFECT (#444). This precondition is itself an arm that landed
# after branches were already in flight, and enforcing it against them refuses a run for not
# satisfying a contract that did not exist when it started. So it carries a `since:` and
# de-blocks anything older.
#
# Anchored to `9c0a689` — "enforce the lean entry gate's ledger precondition (#422)", the merge
# that made a missing entry row a refusal. Authored `2026-08-07T13:22:51Z`; the comparison below
# is at-or-after, so a branch started in that second is enforced.
ENTRY_SINCE='2026-08-07T13:22:51Z'

# The branch's own start instant: the AUTHOR date of its first commit past merge-base with the
# configured base, rendered UTC.
#
# AUTHOR, NEVER COMMITTER. A rebase rewrites committer dates, so a year-old branch rebased this
# morning would postdate the cutoff and start refusing — recreating the exact stranding this
# de-block removes. Author dates survive a rebase, which is the whole reason they are the key.
#
# GIT DOES THE ARITHMETIC, not `date` (D-8). `--date=format-local` under `TZ=UTC` renders the
# author's offset into UTC inside git, so the two mutually-incompatible `date -d` / `date -r`
# forms are never on this path and the result is a fixed-width Z instant that plain string `<`
# compares chronologically. That is what makes this correct on bash 3.2 with BSD userland.
#
# `sed -n 1p` rather than `head -n1`: head closes the pipe early, and under `pipefail` git's
# SIGPIPE death would read as a failure to resolve the date.
branch_start_utc() { # branch_start_utc <merge-base>
  TZ=UTC git -C "$REPO_ROOT" log --reverse --date=format-local:%Y-%m-%dT%H:%M:%SZ \
    --format=%ad "$1..HEAD" 2>/dev/null | sed -n '1p'
}

require_entry_attested() {
  entry_row_present && return 0

  # The de-block, evaluated only once the row is known to be missing — so nothing about an
  # attested run changes, and this comparator cannot cost an honest run anything.
  local start mb
  mb="$(git -C "$REPO_ROOT" merge-base "origin/$BASE_BRANCH" HEAD 2>/dev/null)"
  if [ -z "$mb" ]; then
    # D-5. Its OWN environment error, not a fifth cause on the refusal below. This gate runs on
    # the build host where origin/$BASE_BRANCH is present by construction, so an unresolvable
    # merge-base means a broken checkout — a different problem with a different remedy, and
    # conflating "you skipped `entry`" with "your checkout is broken" sends the operator to the
    # wrong one. AC-3's leniency has no analogue here: that exists for a consumer's committed
    # workflow no operator action can retroactively fix, whereas a fetch fixes this.
    echo "[lean-gate] ✗ $SUB: cannot resolve merge-base(origin/$BASE_BRANCH, HEAD), so this branch's start date is unknown and the entry precondition's cutoff cannot be evaluated." >&2
    echo "[lean-gate]   Fetch origin/$BASE_BRANCH in this checkout and re-run. A precondition that cannot be placed in time must not be waived." >&2
    exit 2
  fi
  start="$(branch_start_utc "$mb")"
  # OR-2. An EMPTY range is not the unresolvable case above and must not fall into it: the
  # branch was cut just now with nothing committed yet, which is definitively at or after any
  # cutoff, so it enforces. `claim` reaches here on every run — it is invoked from the main
  # checkout before the first commit exists — and fail-closed is correct there because `entry`
  # is always available to run, so nothing is stranded by refusing.
  if [ -n "$start" ] && [[ "$start" < "$ENTRY_SINCE" ]]; then
    # D-6. One plain notice, in this file's own `note:` idiom rather than a third copy of the
    # class-(b) disposition vocabulary. Silence was rejected: a de-block is not a satisfied
    # precondition but one that never applied, and the operator must be able to tell which.
    echo "[lean-gate] note: $SUB: this branch started at $start, before the entry precondition took effect ($ENTRY_SINCE), so it is not refused for lacking an attestation it could not have recorded." >&2
    echo "[lean-gate]   Nothing was attested and no entry row was written — the run is de-blocked, not credited. Later readers still see no entry row." >&2
    return 0
  fi

  echo "[lean-gate] ✗ $SUB: this run has no entry attestation in $PROGRESS_FILE." >&2
  echo "[lean-gate]   \`bash G entry $ISSUE\` was never recorded, so nothing establishes that the session's audit ledger was live when the run started — and a run with no ledger is unreconcilable at the merge boundary (#416)." >&2
  echo "[lean-gate]   Run \`bash G entry $ISSUE\` (idempotent) and retry. No fix-budget attempt was charged." >&2
  echo "[lean-gate]   Or the record is simply out of reach: that file is host-local and gitignored, so a checkout not sharing the build host's state dir cannot see an attestation that exists. Re-run from the build worktree before handing this back." >&2
  exit 2
}

# LIBRARY MODE stops here (#439): helpers are defined, nothing is attested, nothing dispatches.
[ -n "${LEAN_GATE_LIB:-}" ] && return 0

case "$SUB" in
  claim|delta|all|1|2|3|4|5) require_entry_attested ;;
esac

case "$SUB" in
  entry)   cmd_entry ;;
  claim)   cmd_claim ;;
  mark)    cmd_mark ;;
  teardown) cmd_teardown ;;
  delta)   cmd_delta ;;
  progress) cmd_progress ;;
  staleness) cmd_staleness ;;
  verdict) cmd_verdict ;;
  all)     cmd_all ;;
  *)       run_milestone "$SUB" ;;
esac
exit $?

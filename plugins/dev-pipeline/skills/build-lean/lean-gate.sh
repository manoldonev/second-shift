#!/usr/bin/env bash
# lean-gate.sh — the five milestone gates of /dev-pipeline:build-lean, plus the entry
# precondition and the claim helper.
#
# WHY THIS EXISTS: build-lean is OUTCOME-gated, not process-prescribed. The harness asserts
# ARTIFACTS at five ordered milestones and is deliberately silent about the path between them.
# Everything this script checks is a file, an exit code, or a tracker record.
#
# TRUST POSTURE (D-47) — read this before adding a check here. Every record this script writes is
# written by the agent being checked, so it is at best tamper-EVIDENT. The binding evidence
# contract lives at the model-free merge boundary (scripts/check-lean-chain.sh) and in
# lean-reconcile.sh. The fix-budget counter here is cost-control, NOT integrity. Do not add an
# integrity check here and call it enforcement. RUN_ID is agent-CHOSEN and the session id is
# agent-OVERRIDABLE, so do not describe this as stronger than those two describe themselves.
#
# AUTHORSHIP (P10) — the one property here that is a check rather than a record. The BUILD role
# (`entry`, `claim`, `1..5`, `all`) can only READ the verdict record; the REVIEW role (`verdict`)
# can only WRITE it, and refuses to run inside the build session. Identity is role-keyed on both
# sides, so a review session that provisioned no identity is refused rather than inheriting the
# build's.
#
# FRESHNESS (milestone 4). Four of the five milestones re-derive their answer from the current
# tree on every sweep, which is what makes `satisfied` a record rather than a cache. Milestone 4
# cannot — its evaluation is reading a file — so it binds that file to a tree: the record must be
# COMMITTED, and nothing but the record itself may have changed since.
#
# TWO ARMS, and neither subsumes the other. INFERRED freshness asks where git says the record was
# committed; the DECLARED arm asks what the reviewer stated. They come apart when code lands
# between the review and the record's commit — the reviewer commits an honest record on top of a
# head it never read, and inference alone calls that fresh.
#
# The declaration is keyed on `reviewed_patch_id`, not on the `reviewed_head` SHA beside it: a
# rebase rewrites SHAs and changes no reviewed content, and in a fresh checkout the pre-rebase
# object does not exist at all. Patch identity is invariant there and still moves on any real
# change. It does NOT cover a base change that reds the suite with no textual conflict — the
# verdict correctly still stands there, and the merged result is CI's business. `reviewed_head`
# is a diagnostic pointer and the input to #597's escape hatch; it gates nothing on its own.
#
# INHERITANCE (#375). Every round declares `inherited_patch_id` — the reviewed patch of the round
# whose coverage it inherits, or the literal `none` on a chain root — so a fix round reads the
# delta since that tree. The merge boundary's guarantee then reads "a CHAIN of independent reviews
# collectively covered this tree", and it holds only while every LINK is verified, so every reader
# walks the chain and a link matching no committed record is refused.
#
# EVERY round emits the key, roots included: a key the writer sometimes omits leaves the
# reviewer's own findings as the first occurrence in the file, and every reader takes the first
# match. `inherited_key` anchors the read to the header, which also covers records this writer did
# not produce. The keys are DERIVED here, never passed in, because a flag lets a round name
# coverage it did not inherit. The chain is walked by patch identity, never by SHA — a SHA link
# dies on a rebase. `inherited_from_verdict` is a human pointer; no reader gates on it.
#
# Usage:
#   lean-gate.sh entry  <issue> [--ticket-source argument|lane-branch|lane-registry]
#                                        entry precondition: the session's audit ledger is live.
#                                        On success it RECORDS that fact in the progress file;
#                                        every build-role subcommand below refuses with exit 2
#                                        until that row exists, so skipping this step is a
#                                        refusal rather than a silent omission (#416).
#                                        The queue-label reject is the SESSION's step (SKILL.md
#                                        step 1) — it needs a tracker read, so it is not gated
#                                        here. Under tracker.type: jira there is no queue at all.
#                                        #647: it also SEEDS this run's lane worktree with the
#                                        checkout's own `.claude/settings{,.local}.json`, copied
#                                        never symlinked and never over an existing file, so a
#                                        session launched in the worktree inherits the operator's
#                                        allowlist instead of gambling on the classifier.
#                                        Advisory — it cannot change entry's verdict.
#   lean-gate.sh claim  <issue> [--ticket-source ...]
#                                        the two bot-wrapper claim writes (AC-15/D-49).
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
#                                        deletes the branch: the PR points at it. #531: it also
#                                        appends a `| teardown | <outcome> |` DIAGNOSTIC row —
#                                        removed, kept-with-reason or nothing-to-remove — in its
#                                        own namespace, so nothing reading `| milestone-<n> |`
#                                        can mistake a hygiene outcome for a certified one.
#   lean-gate.sh inflight <issue>        SCHEDULER role (#531): does this lane's worktree hold work
#                                        that exists nowhere else? The same dirty-tree /
#                                        unpushed-head predicate teardown refuses on, exposed
#                                        read-only at the boundary where a BUILD session that
#                                        exited 0 without pushing is still recoverable. Records
#                                        nothing, spends no fix budget, creates no file. 0 =
#                                        collected (a missing worktree included — nothing that does
#                                        not exist holds work); 8 = it still holds work, naming
#                                        which arm fired; 1 = the read could not be completed.
#   lean-gate.sh close-out <issue>       BUILD role (#590): perform the close-out's writes, then
#                                        assert milestone 5, then tear the lane down. It
#                                        re-computes the run's published cost block (which is
#                                        also what writes the cross-run corpus row), replaces the
#                                        stale block in the PR description, and — under a tracker
#                                        that writes — posts the one closing comment carrying the
#                                        PR link, the verdict-record path and that block. Every
#                                        write goes through the bot wrapper where the consumer
#                                        configured one, so no third identity appears on a
#                                        close-out artifact. It then calls milestone 5 unchanged
#                                        and, ONLY on its rc=0, `teardown`. `5` on its own is
#                                        untouched and stays a pure verifier.
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
#                                        `pass`); `fail` with `approve` is refused. On an ARMED
#                                        ticket `pass` additionally requires a conforming
#                                        `## Design fidelity evidence` table in --summary-file
#                                        (grammar: review-lean/SKILL.md step 5b) — refused here,
#                                        at the writer, rather than at milestone 4 where it
#                                        would cost the round.
#   lean-gate.sh progress <issue> [--satisfied <n> | --infra | --obligations]
#                                        SCHEDULER role (#492): print an OPAQUE TOKEN over the
#                                        progress rows that mean the build role advanced. Reads
#                                        only — it writes nothing and, unlike every other
#                                        subcommand, does not create the file it reads. The
#                                        caller compares the token across a spawn and interprets
#                                        nothing; `--satisfied <n>` narrows it to milestone n's
#                                        `satisfied` row alone.
#                                        `--obligations` (#531) prints neither token but a REPORT:
#                                        one line per milestone-5 obligation with its recorded
#                                        state, the aggregate's own state, and the teardown
#                                        outcome read separately. Lines to ECHO, never to parse —
#                                        the scheduler's close-out failure message is assembled
#                                        from them so that it can name WHICH obligation is
#                                        outstanding without the scheduler reading the record.
#                                        All three flags are mutually exclusive.
#                                        `--infra` (#527) prints a DIFFERENT token space,
#                                        `m3infra-v3:<n>`, over milestone-3 evaluations that began
#                                        and never concluded — an infrastructure death, derived
#                                        from residue because a session killed at the turn boundary
#                                        writes no class. v3 (#566): the predicate is the unclosed
#                                        count ALONE. The runner-record half retired with the
#                                        detached runner itself — milestone 3 is inline now, so
#                                        there are no pid records to scan. `m3infra-v3:0` is the
#                                        no-death answer; it is never empty. Compare it ACROSS a
#                                        spawn, never as a level: the record is append-only.
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
#           build session (P10). Terminal: a retry cannot clear it.
#       7 = NOTHING WAS EVALUATED. Never a milestone failure and never a fix attempt. Three
#           subcommands raise it, unambiguously at each call site:
#           * `staleness`: the ticket is closed, or the base has moved into this branch's files.
#           * milestone 3 (#527): a BLOCKING verify lane raised the reserved infrastructure code —
#             see below. Since #642 that is `typecheck` alone; `lint`, `test` and extraLanes are
#             advisory and classify nothing. The remedy is to RE-INVOKE.
#           * `mark` (#650): the ticket closed under this run. Same remedy as the staleness arm's,
#             hence the same integer. `cmd_5`/`cmd_close_out` call `cmd_mark` as a function and
#             never reach it, so the landing path stays open by design.
#       8 = `inflight` only (#531): THE LANE WORKTREE STILL HOLDS WORK — dirty tree, or commits not
#           on origin/<branch>. Its own integer because 1 there means the predicate could not be
#           EVALUATED, and conflating the two either stops every run whose fetch flaked or reviews
#           a head missing everything the build session just did.
#       9 = WRONG TREE (#141): `1`..`5`, `all`, `delta` or `verdict` invoked from a checkout that is
#           not on this run's lane branch. Refuses before the first read — nothing written, nothing
#           spent. Its own integer because the remedy is POSITIONAL, and because this is the one
#           failure mode that otherwise does not fail at all: every answer here is derived from the
#           tree the process is in, so from the wrong one the gate is confidently wrong.
#      10 = UNRESOLVABLE TICKET ARGUMENT (#611): `entry`/`claim` were given no ticket, or one that
#           does not validate, does not exist, is closed with no evidence this run claimed it, or
#           disagrees with the lane branch — that last arm binds `mark` and `teardown` too. Nothing
#           was resolved. ONE integer for all five (each named in its own message) because they
#           share one remedy: re-invoke naming the ticket you meant. Not the usage 2, because a
#           reader that could not tell "you passed no argument" from "the argument is a lie" would
#           treat a false-premise run as a typo.
#
# THE RESERVED VERIFY-LANE INPUT CODE (#527). Exit 3 from a configured verify lane — the fixed
# `lint`/`typecheck`/`test` keys, or any `extraLanes` entry — means "I failed for reasons that are
# not this branch": the sweep's workers were killed, the runner could not start, the environment
# went away. Milestone 3 reds with the 7 above rather than 1 and charges NO fix attempt, because
# nothing was evaluated. `tools/run-selftests.sh` raises it when EVERY failing suite is its
# no-verdict class; a mixed run stays 1, because a red branch is still a red branch.
#
# It is reserved CROSS-REPO, and that is its one exposure: a consumer whose lane already exits 3
# for a genuine failure is reclassified as infrastructure and charged no fix attempt. The failure
# direction is a run that RETRIES when it should have stopped — bounded by the scheduler's
# --max-continuations and by INTERRUPTED_BUDGET — never a red branch reported green. There is
# deliberately no per-lane config opt-out; see docs/config-schema.md.
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
#   --ledger-file <path>     milestone 1's pause-and-ask check AND its #517 receipt
#                            reconciliation: read the pre-flight ledger from this path instead
#                            of the default $STATE_DIR/<issue>-ledger.md (#533). Its Open
#                            Regions table is read ALONGSIDE the issue body, not instead of it
#                            — a region declared in either source is seen — while its `D-n`
#                            rows are the only source for the carry-forward check.
#   LEAN_COST_BLOCK_TOOL     #590: the pipeline-cost-block.sh the close-out invokes. Default: the
#                            sibling under tools/. A selftest points it at a stub so the close-out
#                            can be driven with no OTel collector and no metrics on disk.
#   COST_LOG_FILE            #546/#590: the cross-run cost log the close-out reads its own row
#                            back from. Default: cost-log.jsonl beneath the state dir. Shared
#                            with pipeline-cost-block.sh, which writes it.
#   LEAN_RUN_MODEL           #347: the `model:` key stamped into the progress/verdict record
#                            at creation time (retro-corpus.sh's corpus-aggregation key).
#                            Read once, not cached; absent reads "unknown", never an error.
#   LEAN_GATE_OBSERVE=1      #496: EVALUATE WITHOUT RECORDING. Milestones 1 and 4 return their
#                            ordinary exit code — including the taxonomy above and a spent budget's
#                            4 — while appending no `attempt`/`absent` line, consuming no budget
#                            and writing no `satisfied` line. `cmd_all`'s cheap pre-pass uses it,
#                            and so does the scheduler's verdict read: reading a verdict must not
#                            charge the build role for a milestone the reader did not fail.
#                            NOT IN `SEAM_SCRUB`, so a verify lane the gate runs inherits it. The
#                            register is a `subset-of` lockstep row against preflight.sh (which
#                            carries the superset) and is not widenable from this side alone.
#   LEAN_GATE_TEST_STALL_DIR #528: TEST-ONLY, never set in CI or by an operator — the loop it
#                            gates is otherwise unreachable. Pauses append_satisfied/
#                            heal_progress_run_id between their absence check and their write,
#                            so a selftest can force two same-issue writers to both observe
#                            "absent" before either commits — the one race shape a real
#                            concurrent run cannot be driven through deterministically.
#                            Bounded (10s) so a broken harness cannot hang a real run.
#   LEAN_GATE_ANY_TREE=1     #141: DISARM THE LANE-TREE ASSERTION — let `1`..`5`, `all`, `delta`
#                            and `verdict` grade whatever checkout they are invoked from. It
#                            ANNOUNCES on stderr every time it disarms a call, naming the branch
#                            found and the lane branch expected: a guard nobody can see disarmed
#                            is a guard nobody can audit, and the precedent is this file's own
#                            unconditional config-path announcement.
#                            Its consumer is a SUITE, not an operator — lean-gate-selftest.sh and
#                            scenario-liveness-selftest.sh drive the guarded subcommands against
#                            bare-`git init` fixture trees, over many issue keys and three branch
#                            prefixes, and one tree cannot be on nine lane branches at once. A run
#                            that wants a different tree graded should move, not disarm.
#                            NOT IN `SEAM_SCRUB`, exactly like `LEAN_GATE_OBSERVE` above.
#
# bash 3.2 compatible (macOS ships it, and CI has a bash-3.2 lane).
set -uo pipefail

GH_CLI="${GH:-gh}"
CURL_CLI="${CURL:-curl}"
# #613. The attendance/override mechanism, a same-plugin sibling two hops up — a plain relative
# path, not the resolve-sibling ladder, which exists for CROSS-plugin hops. The seam exists so a
# selftest can drive the third resolution artifact without minting a token on the machine.
OVERRIDE_TOOL="${LEAN_OVERRIDE_TOOL:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/operator-override.sh}"
PR_FILE=""
COMMENTS_FILE=""
ISSUE_FILE=""
LEDGER_FILE=""
VERDICT_VALUE=""
VERDICT_PR=""
VERDICT_ROUNDS=""
VERDICT_FIDELITY=""
SUMMARY_FILE=""
PROGRESS_SATISFIED=""
PROGRESS_INFRA=0
# #531 D-12. A third `progress` mode, and a REPORT rather than a token: the scheduler's close-out
# failure message must name each obligation's own state, and a scheduler that parsed the record to
# get them would own a reader it has no business owning. This prints the lines; the loop echoes
# them and interprets nothing.
PROGRESS_OBLIGATIONS=0
# #515. Empty means "not given"; the default is applied after validation, so `--arm` on a
# subcommand that ignores it is still loud rather than silently absorbed into the default.
STALENESS_ARM=""
# #611. The DECLARED provenance of the ticket argument beside it. Empty means "not given" and the
# default is applied after validation, exactly as `--arm` above does — a source token on a
# subcommand that records nothing has to be loud rather than absorbed.
TICKET_SOURCE=""

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

# #566 RETIRED MILESTONE 3'S SEPARATE, LARGER BOUND. #527 D-7 gave it one (8 against this 5)
# because milestone 3 was the only evaluation that ran DETACHED and the only one long enough to be
# killed by a turn boundary, so re-spawns accumulated unclosed rows faster than any other
# milestone could. Both halves of that premise are gone: the evaluation is inline and bounded to
# fit inside the turn, so milestone 3 is now exactly as exposed to an interrupted run as 1, 2, 4
# and 5 — and one bound describes all five honestly.

# #527 D-2/D-3. THE TWO HALVES OF THE INFRASTRUCTURE CONTRACT, named so they cannot drift apart.
# LANE_INFRA_RC is an INPUT: the code a BLOCKING verify lane uses to say "I failed for reasons that
# are not this branch" — since #642 that is `typecheck` alone. Reserved cross-repo; see
# docs/config-schema.md for a consumer whose lane already exits 3.
# INFRA_CLASS is an OUTPUT: what milestone 3 returns for it, deliberately the EXISTING 7 ("nothing
# was evaluated", remedy: re-invoke) rather than a new integer, so no reader gains an operator path.
LANE_INFRA_RC=3
INFRA_CLASS=7

say()  { echo "[lean-gate] $*"; }
warn() { echo "[lean-gate] $*" >&2; }
envfail() { echo "[lean-gate] $*" >&2; exit 2; }

# ---------------------------------------------------------------- argument parsing
SUB=""
ISSUE=""
POSITIONAL=0

# LIBRARY MODE (#439). `LEAN_GATE_LIB=1 . lean-gate.sh` leaves the helpers defined and dispatches
# nothing. It exists so a selftest can drive production functions directly rather than keeping a
# hand-copied twin — a mirror harness cannot fail on a production edit. No run sets it; every
# documented seam still applies.
#
# CAVEAT for anyone sourcing it: the parser below consumes the placeholders, so the sourcing
# scope's own positional parameters are gone afterwards. Copy what you need out of `$1` BEFORE
# the `.`, or `set -u` bites.
[ -n "${LEAN_GATE_LIB:-}" ] && set -- entry 0
while [ $# -gt 0 ]; do
  case "$1" in
    --pr-file)       PR_FILE="${2:-}"; shift 2 ;;
    --comments-file) COMMENTS_FILE="${2:-}"; shift 2 ;;
    --issue-file)    ISSUE_FILE="${2:-}"; shift 2 ;;
    --ledger-file)   LEDGER_FILE="${2:-}"; shift 2 ;;
    --pr)            VERDICT_PR="${2:-}"; shift 2 ;;
    --verdict)       VERDICT_VALUE="${2:-}"; shift 2 ;;
    --rounds)        VERDICT_ROUNDS="${2:-}"; shift 2 ;;
    --fidelity)      VERDICT_FIDELITY="${2:-}"; shift 2 ;;
    --summary-file)  SUMMARY_FILE="${2:-}"; shift 2 ;;
    --satisfied)     PROGRESS_SATISFIED="${2:-}"; shift 2 ;;
    --infra)         PROGRESS_INFRA=1; shift ;;
    --obligations)   PROGRESS_OBLIGATIONS=1; shift ;;
    --arm)           STALENESS_ARM="${2:-}"; shift 2 ;;
    --ticket-source) TICKET_SOURCE="${2:-}"; shift 2 ;;
    -h|--help)       sed -n '2,269p' "$0"; exit 0 ;;
    -*)              envfail "unknown option: $1" ;;
    *)
      if [ "$POSITIONAL" -eq 0 ]; then SUB="$1"; POSITIONAL=1
      elif [ "$POSITIONAL" -eq 1 ]; then ISSUE="$1"; POSITIONAL=2
      else envfail "unexpected argument: $1"
      fi
      shift ;;
  esac
done

[ -n "$SUB" ]   || envfail "usage: lean-gate.sh <entry|claim|mark|1..5|all|close-out|teardown|inflight|delta|verdict|progress|staleness> <issue>"
# #611. DEFERRED for `entry`/`claim` alone, and into a REFUSAL rather than a usage error — the
# absent-ticket case is what that guard is about, and answering it with the same exit 2 a typo'd
# flag gets is what let a session read "no argument" as "choose one". The assertion is not
# dropped: it moves to the ticket-resolution block below, which runs once the branch namespace is
# resolved and can therefore name what a lane cwd would have inferred. Every other subcommand
# keeps this refusal verbatim, the milestone calls included (the AC preamble binds only two).
case "$SUB" in
  entry|claim) : ;;
  *) [ -n "$ISSUE" ] || envfail "usage: lean-gate.sh <entry|claim|mark|1..5|all|close-out|teardown|inflight|delta|verdict|progress|staleness> <issue>" ;;
esac

case "$SUB" in
  entry|claim|mark|1|2|3|4|5|all|close-out|teardown|inflight|delta|verdict|progress|staleness) : ;;
  *) envfail "unknown subcommand '$SUB' (expected entry|claim|mark|1..5|all|close-out|teardown|inflight|delta|verdict|progress|staleness)" ;;
esac

# Validated at parse time rather than inside cmd_progress, so a typo is a usage error before any
# root or config resolution — and so `--satisfied` on a subcommand that ignores it is still loud.
if [ -n "$PROGRESS_SATISFIED" ]; then
  [ "$SUB" = "progress" ] || envfail "--satisfied is only meaningful on 'progress', not '$SUB'."
  case "$PROGRESS_SATISFIED" in
    ''|*[!0-9]*) envfail "--satisfied takes a milestone number, got '$PROGRESS_SATISFIED'." ;;
  esac
fi

# #527 D-6, the same shape and the same reason: a flag that silently selects nothing is a read that
# answers a question nobody asked. The two flags are MUTUALLY EXCLUSIVE rather than composable —
# they print different token spaces, and one invocation can only print one of them, so accepting
# both would have to pick a winner silently.
if [ "$PROGRESS_INFRA" -eq 1 ]; then
  [ "$SUB" = "progress" ] || envfail "--infra is only meaningful on 'progress', not '$SUB'."
  [ -z "$PROGRESS_SATISFIED" ] \
    || envfail "--infra and --satisfied are different token spaces and cannot be combined — ask for one per call."
fi

# #531, the same shape again, and mutually exclusive with BOTH of the above for a sharper reason
# than theirs: this one prints a human-readable report rather than a token at all, so a caller that
# combined it with either would get two different KINDS of answer on one stream.
if [ "$PROGRESS_OBLIGATIONS" -eq 1 ]; then
  [ "$SUB" = "progress" ] || envfail "--obligations is only meaningful on 'progress', not '$SUB'."
  [ "$PROGRESS_INFRA" -eq 0 ] && [ -z "$PROGRESS_SATISFIED" ] \
    || envfail "--obligations prints a report, not a token — it cannot be combined with --infra or --satisfied."
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

# #611, the same parse-time shape and the same reason: a source token outside the enum, or one
# handed to a subcommand that records nothing, declares a provenance no reader can interpret —
# and the point of the flag is that provenance is CHECKED rather than asserted.
if [ -n "$TICKET_SOURCE" ]; then
  case "$SUB" in
    entry|claim) : ;;
    *) envfail "--ticket-source is only meaningful on 'entry' or 'claim', not '$SUB'." ;;
  esac
  case "$TICKET_SOURCE" in
    argument|lane-branch|lane-registry) : ;;
    *) envfail "--ticket-source takes argument|lane-branch|lane-registry, got '$TICKET_SOURCE'." ;;
  esac
fi
TICKET_SOURCE="${TICKET_SOURCE:-argument}"

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

# #496 S4. ABSENT and UNPARSEABLE are two different facts and only one is legal. Absent means "this
# consumer configured nothing" and every `cfg` default applies. Present-but-unparseable means the
# intent is unknown — and the defaults are not neutral (`.tracker.type` falls back to `github`, the
# arm that attests MORE), so a typo would pick a policy in silence. Fail closed.
#
# UP FRONT AND OUTSIDE `cfg`, deliberately: `cfg` runs as `$(cfg …)`, where an `exit` kills only the
# substitution's subshell and the caller reads an empty string and carries on.
#
# `jq empty`, not `jq -e .`: it reads the WHOLE input and asserts only that it parses.
if [ -f "$CONFIG" ] && ! jq empty "$CONFIG" >/dev/null 2>&1; then
  envfail "config $CONFIG exists but is not parseable JSON — refusing to fall back to defaults, which would silently select tracker.type=github and every other shipped default. Fix the file (jq empty '$CONFIG' names the parse error) or point SECOND_SHIFT_CONFIG elsewhere."
fi

# #528. The config is a SHARED, mutable file, so a sibling session's edit re-points every live
# lane's gate mid-run. Announced once per invocation so a re-point is visible rather than inferred.
#
# STDERR, via `warn`: orchestrate-lean.sh's progress_token() compares this script's STDOUT
# byte-for-byte across two reads, so a stdout announcement would flip that comparison on exactly
# the re-point this exists to surface — corrupting the continuation predicate instead of exposing
# the event. SKIPPED on `progress` even on stderr: that subcommand's contract is a bare
# machine-read answer. Every other subcommand gets it.
[ "$SUB" = "progress" ] || warn "config: $CONFIG"

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
# HALF of the arming signal (D-8); the other half is the spec's `## Design` section, ANDed. A
# provider with no section is a milestone-1 red (arming is per-ticket, never a default); a section
# with no provider arms NOTHING, or a repo that merely documents a design axis would be asked for a
# render harness it never configured.
#
# Config is read here and NOWHERE at the merge boundary — CI never sees this gitignored file — so
# check-lean-chain.sh derives armed-ness from the committed spec alone. The two agree on every spec
# that can reach a merge, because a malformed section never gets past milestone 1.
DESIGN_PROVIDER="$(cfg '.design.provider' '')"
LR_COMMAND="$(cfg '.design.liveRender.command' '')"
LR_CWD="$(cfg '.design.liveRender.cwd' '')"
LR_READY_PROBE="$(cfg '.design.liveRender.readyProbe' '')"

# ---------------------------------------------------------------- the tracker adapter
# ONE resolution, THREE branch sites: the entry note, cmd_claim, and cmd_5. Milestones 1-4 are
# adapter-INSENSITIVE and must stay that way — an adapter branch inside them is a second tracker
# authority.
#
# Absent ⇒ github is a FAIL-SAFE: config-lint requires the key, so the default is only for a config
# that never reached the lint, and github is the safe side — its exit gate demands a closing comment
# and fails loudly where jira would quietly accept a PR body. An UNRECOGNIZED value is a loud
# environment error, never a fall-through. The enum matches config-lint.sh's.
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

# The BRANCH. `<branchPrefix><key>` (#413). Lean and staged SHARE one namespace, so nothing
# downstream may classify lean-vs-staged by branch name; that discriminator is the committed lean
# spec, resolved in lean-evidence.sh. The prefix comes from branch-prefix.sh, the one implementation
# of the resolution order (config, else the dominant remote-branch prefix, else refuse). There is
# deliberately no `claude/acme-` default: it wrote a placeholder org slug into real branch names.
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

# ---------------------------------------------------------------- ticket resolution (#611)
# WHAT THIS DEFENDS. Nothing used to ask whether `<issue>` named anything, so a session whose
# argument was lost to shell quoting could list the queue, SELF-SELECT an assignment, claim it and
# open a PR for it while the operator believed another ticket was in flight. Claiming a ticket the
# caller never named is a write under a false premise, the same class as authoring your own verdict.
#
# THE GATE NEVER RESOLVES A TICKET. It validates one it was handed. An inference the gate performed
# itself would be indistinguishable, in the record, from a caller that named the ticket — which is
# the failure. Inference stays with the CALLER, is legal only from a lane-branch cwd, and comes back
# as an explicit argument plus `--ticket-source`. Both are recorded; the branch name checks them.
#
# THE BRANCH NAME, NOT A REGISTRY (D-5). The gate is standing IN a tree whose identity its own
# branch asserts. #566 retired `lean-lanes.tsv`; `lane-registry` survives as a caller-asserted
# provenance LABEL, still checked against the branch, with no file behind it.
#
# ORDER. The cheap arms run BEFORE the pinned name table below, because every path there is
# `$ISSUE`-derived: with an empty key the run-id cache resolves to `<state-dir>/-run-id`, which
# `entry`/`claim` would then WRITE. A refusal that first creates a file named after the ticket it is
# refusing is not a refusal.
TICKET_UNRESOLVABLE=10

ticket_refuse() { # ticket_refuse <reason> [detail...]
  local d
  warn "✗ $SUB: UNRESOLVABLE TICKET ARGUMENT — $1"
  shift
  for d in "$@"; do warn "  $d"; done
  warn "  Nothing was resolved: no tracker write, no attestation, no progress row and no fix attempt. Name the ticket you mean."
  exit "$TICKET_UNRESOLVABLE"
}

# Under jira the branch name lowercases the key, so a comparison against a branch-derived key has
# to apply the same transform to the argument. Identity under github. Deliberately the transform
# BRANCH_KEY below already performs — one rule, so the two answers cannot drift.
ticket_norm() { # ticket_norm <key>
  case "$TRACKER_TYPE" in
    jira) printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' ;;
    *)    printf '%s\n' "$1" ;;
  esac
}

# ADAPTER-AWARE, and the github arm is deliberately narrower than `bp_key_re`'s `[0-9]+`: an
# issue number is a POSITIVE integer, so `0` is not one, and a zero-padded `0007` — which the API
# happily accepts — would derive a branch name no other reader of this run reconstructs. Both are
# refused at the shape arm rather than surviving to become a lane nobody can find again.
# A here-string, never a pipeline: under `pipefail` a producer that gets SIGPIPE when the reader
# exits early turns a MATCH into a non-zero status, which would read here as "invalid key".
ticket_key_valid() { # ticket_key_valid <key>
  case "$TRACKER_TYPE" in
    jira) grep -qiE "^($(bp_key_re jira "$TRACKER_KEY_PATTERN"))$" <<<"$1" ;;
    *)    grep -qE '^[1-9][0-9]*$' <<<"$1" ;;
  esac
}

# The cwd's OWN ticket, or empty. `bp_branch_key` answers only for a ref that parses as a work
# branch of this repo's namespace, so a shared checkout on the base branch, an unrelated
# `fix/...` branch and a detached HEAD all yield nothing and constrain nothing — the arms below
# fire on DISAGREEMENT, never on the mere absence of a lane.
TICKET_TREE_HEAD="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)" || TICKET_TREE_HEAD=""
[ -n "$TICKET_TREE_HEAD" ] || TICKET_TREE_HEAD="<unresolvable>"
TICKET_TREE_KEY=""
if [ "$TICKET_TREE_HEAD" != "HEAD" ] && [ "$TICKET_TREE_HEAD" != "<unresolvable>" ]; then
  TICKET_TREE_KEY="$(bp_branch_key "$TICKET_TREE_HEAD" "$BRANCH_PREFIX" \
                       "$TRACKER_TYPE" "$TRACKER_KEY_PATTERN")" || TICKET_TREE_KEY=""
fi

# LIBRARY MODE dispatches nothing, so it resolves nothing either: its placeholder args exist only
# to satisfy the parser, and refusing them would break the one consumer that sources this file.
if [ -z "${LEAN_GATE_LIB:-}" ]; then

  # (i) ABSENT. Two messages, one code. From a lane cwd the gate can say what the caller PROBABLY
  # meant — and still refuses, because saying it and acting on it are different things.
  case "$SUB" in
    entry|claim)
      if [ -z "$ISSUE" ]; then
        if [ -n "$TICKET_TREE_KEY" ]; then
          ticket_refuse "\`$SUB\` was given no ticket, and this gate does not self-select one." \
            "This checkout is on '$TICKET_TREE_HEAD', whose key is '$TICKET_TREE_KEY'. If that is the run you mean, say so:" \
            "    bash G $SUB $TICKET_TREE_KEY --ticket-source lane-branch" \
            "Inference is legal from here, but it is the CALLER's to perform and the gate's to check — so it arrives as an argument with its provenance declared, and both are recorded."
        fi
        ticket_refuse "\`$SUB\` was given no ticket, and this checkout ('$TICKET_TREE_HEAD') is not a work branch of '$BRANCH_PREFIX' — there is no lane to infer one from." \
          "A build session that picks its own assignment claims a ticket its caller never named. Re-invoke as \`bash G $SUB <issue>\`."
      fi

      # (ii) KEY SHAPE. Before any tracker read — a key the adapter cannot spell is answered
      # locally rather than by a round trip that would report it as "not found".
      ticket_key_valid "$ISSUE" || case "$TRACKER_TYPE" in
        jira) ticket_refuse "'$ISSUE' is not a valid jira key for this repo — it does not match tracker.keyPattern '$(bp_key_re jira "$TRACKER_KEY_PATTERN")'." \
                "No tracker read was attempted: a key the adapter cannot spell has no ticket to be." ;;
        *)    ticket_refuse "'$ISSUE' is not a github issue number — expected a positive integer with no leading zeros." \
                "No tracker read was attempted. A padded or zero key would also derive a lane branch no other reader of this run reconstructs." ;;
      esac
      ;;
  esac

  # (iii) CWD DISAGREEMENT (AC-4). The four calls the #141 wrong-tree refusal does not bind —
  # it covers `1`..`5`, `all`, `delta` and `verdict`, which are EVALUATIONS derived from the tree
  # they run in. These four are not evaluations, and each writes somewhere the ticket names: a
  # label and a marker comment, a PR marker, a worktree. An error, never a fallback: the argument
  # and the tree are two independent statements of the same fact, and picking a winner silently is
  # how one of them stops being checked. A second exit code is deliberately NOT minted here —
  # `rc=9` stays the milestone calls' alone, as the AC requires.
  case "$SUB" in
    entry|claim|mark|teardown)
      if [ -n "$TICKET_TREE_KEY" ] && [ -n "$ISSUE" ] \
         && [ "$TICKET_TREE_KEY" != "$(ticket_norm "$ISSUE")" ]; then
        ticket_refuse "the argument names '$ISSUE', but this checkout is on '$TICKET_TREE_HEAD', whose key is '$TICKET_TREE_KEY'." \
          "These are two independent statements of which run this is, and they disagree — so one of them is wrong and this gate cannot tell which." \
          "Re-run from a checkout on '$BRANCH_PREFIX$(ticket_norm "$ISSUE")', or name '$TICKET_TREE_KEY' if this tree is the run you meant."
      fi
      ;;
  esac

  # (iv) INFERENCE LEGALITY (AC-3). A declared inference source is a claim about WHERE the ticket
  # came from, and from a checkout that is not a lane there is nowhere it could have come from —
  # so the declaration is false and the run stops. Arm (iii) has already established that a lane
  # cwd AGREES with the argument, which is what makes the pair a check rather than a label.
  case "$SUB" in
    entry|claim)
      if [ "$TICKET_SOURCE" != "argument" ] && [ -z "$TICKET_TREE_KEY" ]; then
        ticket_refuse "--ticket-source '$TICKET_SOURCE' declares an INFERRED ticket, but this checkout ('$TICKET_TREE_HEAD') is not a work branch of '$BRANCH_PREFIX'." \
          "Inference is legal only from a lane worktree — the re-entry shape. A fresh run from the shared checkout names its ticket, or does not start."
      fi
      ;;
  esac

fi

# The tracker arm, DEFINED here beside its siblings and CALLED at dispatch: it needs the run
# identity resolved below, and it opens a socket, so it must not run for a call the cheap arms
# above already refused. One read per run boundary, never per milestone — the milestone calls'
# recorded no-network property is unchanged.
#
# github only, on staleness_ticket_arm's precedent: the jira adapter has no issue-state read here
# and inventing one would be a second tracker authority. The shape arm still ran, so a jira run is
# not unguarded — only its liveness is un-asked, and it says so.
require_ticket_live() {
  local err rc state labels comments marker
  if [ "$TRACKER_TYPE" != "github" ]; then
    say "$SUB: ticket liveness arm skipped — tracker '$TRACKER_TYPE' has no issue-state read here. The key-shape and cwd arms already ran."
    return 0
  fi

  # THE SAME READ EXPRESSION staleness_ticket_arm makes, `--json state --jq '.state'`, and not a
  # combined `--json state,labels`. Two readers of one tracker fact that spell their query
  # differently agree only by accident of what every stub in reach happens to answer — and the
  # scheduler's own composed fixtures serve exactly this shape. Labels are read separately and
  # ONLY on the closed path below, where they are the only place they matter, so the ordinary
  # run still pays one call.
  err="$(mktemp -t lean-ticket.XXXXXX)" || envfail "mktemp failed."
  state="$("$GH_CLI" issue view "$ISSUE" --json state --jq '.state' 2>"$err")"; rc=$?
  err="$(cat "$err" 2>/dev/null; rm -f "$err")"
  if [ "$rc" -ne 0 ]; then
    # TWO NAMED REASONS off one failed read, classified by what the CLI said. The classification
    # is a convenience and never a decision: both arms refuse, so a future `gh` rewording degrades
    # this to the generic reason and never to admission. Fail closed is the staleness arm's own
    # precedent — an unreadable tracker is not an open ticket.
    #
    # CASE-FOLDED before matching, which is not a nicety: the live wording is "Could not resolve
    # to an issue or pull request", lowercase, and the capitalized guess sent a plainly absent
    # number down the outage arm — a refusal either way, but one that named the wrong cause.
    case "$(printf '%s' "$err" | tr '[:upper:]' '[:lower:]')" in
      *"could not resolve to"*)
        ticket_refuse "'$ISSUE' names no issue in this repository." \
          "$GH_CLI said: $(printf '%s' "$err" | tr '\n' ' ')" \
          "Nothing was claimed. Check the number against the queue before re-invoking." ;;
      *)
        ticket_refuse "#$ISSUE's state could not be read via '$GH_CLI' — refusing to treat an unreadable tracker as a live ticket." \
          "$GH_CLI said: $(printf '%s' "$err" | tr '\n' ' ')" \
          "This arm fails CLOSED: an outage that answered 'looks fine' would let exactly the run this refusal exists to stop proceed on a premise nobody checked." ;;
    esac
  fi

  case "$state" in
    OPEN) return 0 ;;
    # ANY terminal state, `.stateReason` deliberately unread — the staleness arm's D-7 reasoning
    # verbatim: a NOT_PLANNED close is exactly as dead as a completed one. MERGED is here because
    # issues and PRs share one number space and `gh issue view` resolves either, so a PR number
    # passed as a ticket reaches this arm; it is terminal, and reporting it as an unrecognized
    # state named the wrong cause for a refusal that was already correct.
    CLOSED|MERGED) : ;;
    *) ticket_refuse "'$GH_CLI' answered an unrecognized state '$state' for #$ISSUE — refusing to guess whether the ticket is open." \
         "Fail closed, for the same reason the unreadable arm above does." ;;
  esac

  # CLOSED, so the one waiver: THIS RUN's own re-entry. A run whose ticket closed under it must
  # still be able to run `entry` — that is the call the close-out and `teardown` paths come
  # through, and stranding it would leave a worktree nobody can reach. The evidence is the pair
  # the skill's own re-entry test names, and both halves are needed: the label alone is set by
  # anyone, and a marker alone survives an unclaimed re-open.
  labels="$("$GH_CLI" issue view "$ISSUE" --json labels --jq '.labels[].name' 2>/dev/null)" || labels=""
  if [ -n "$COMMENTS_FILE" ]; then
    [ -f "$COMMENTS_FILE" ] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
    comments="$(cat "$COMMENTS_FILE")"
  else
    comments="$("$GH_CLI" api "repos/{owner}/{repo}/issues/$ISSUE/comments" --paginate 2>&1)" \
      || ticket_refuse "#$ISSUE is $state and its comment trail could not be read, so this run's own claim evidence cannot be checked." \
           "$GH_CLI said: $(printf '%s' "$comments" | tr '\n' ' ')"
  fi
  # BOT-authored and carrying THIS run's id — the same two filters check-lean-chain.sh applies at
  # the merge boundary. An operator-posted marker is not evidence the harness ran, and a marker
  # from some other run is not evidence THIS one claimed anything.
  marker="$(printf '%s' "$comments" | jq -r --arg tag "$LEAN_CLAIM_MARKER_TAG" --arg id "$RESOLVED_RUN_ID" '
      [ (. // [])[] | select((.user.type // "") == "Bot")
        | select((.body // "") | contains("<!-- stage: " + $tag + " -->"))
        | select((.body // "") | contains("<!-- run_id: " + $id + " -->")) ] | length' 2>/dev/null)" || marker=0
  [ -n "$marker" ] || marker=0

  if [ "$marker" -gt 0 ] && grep -qxF "$CLAIMED_LABEL" <<<"$labels"; then
    case "$SUB" in
      # A fresh claim on a closed ticket is precisely the false-premise write, and the checklist
      # already says to skip step 2 on a re-entry — so this is a refusal, not a no-op that would
      # re-swap labels on an item the repository's unclaim workflow has already released.
      claim) ticket_refuse "#$ISSUE is $state. This run's claim evidence is on it, so the run is real — but a claim WRITE against a closed ticket is not." \
               "Skip step 2 on a re-entry (the marker is posted and the labels are swapped already) and continue at the first unsatisfied milestone." ;;
    esac
    say "entry: #$ISSUE is $state, but carries the '$CLAIMED_LABEL' label and this run's own bot-authored '$LEAN_CLAIM_MARKER_TAG' marker (run_id '$RESOLVED_RUN_ID')."
    say "  Admitted as a RE-ENTRY so close-out and \`teardown\` can still run. This waives the open check and nothing else — it is not a fresh claim."
    return 0
  fi

  ticket_refuse "#$ISSUE is $state, and nothing on it evidences that this run ever claimed it." \
    "Looked for the '$CLAIMED_LABEL' label AND a bot-authored '$LEAN_CLAIM_MARKER_TAG' marker carrying run_id '$RESOLVED_RUN_ID'; found label=$(grep -qxF "$CLAIMED_LABEL" <<<"$labels" && echo yes || echo no), marker=$marker." \
    "Starting a run on a closed ticket is a run whose premise is already false."
}

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
# This tool is routinely invoked as ONE-SHOT subprocesses, so an export in the `claim` call is gone
# by the next one and every later record stamps `run_id: unset` — the mismatch lean-reconcile.sh
# exists to catch. So: cache the id the FIRST time it is seen, and resolve from the cache whenever
# $RUN_ID is absent from a call's own environment.
#
# ROLE-KEYED (P10). TWO caches, and neither role may read the other's. With one, a review session
# working the same issue resolved the BUILD run's id into the verdict record and the authorship
# check compared a value against itself. The review role resolves `<issue>-review-run-id` and,
# finding nothing, resolves NOTHING: `verdict` refuses rather than falling through.
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
    # ONLY the build-role subcommands may ESTABLISH the build identity. With no cache on disk yet,
    # a REVIEW session running `bash G 4 <issue>` would CREATE it holding its own id, and milestone
    # 4 — which compares the record against that very file — would then refuse a valid record
    # permanently. An EVALUATION must be able to read an identity, never to establish one.
    #
    # #611 SPLIT THE SEED OFF THE RESOLVE for the two run-boundary calls: seeding is a WRITE named
    # after the ticket, and `entry`/`claim` can still be refused below by the liveness arm, so a
    # typo'd number used to leave `<typo>-run-id` behind for whatever real run later took it.
    # `mark` keeps the immediate seed — nothing refuses it on ticket grounds past this point.
    case "$SUB" in
      mark) RESOLVED_RUN_ID="$(resolve_cached_id "$RUN_ID_CACHE" 1)" ;;
      *)    RESOLVED_RUN_ID="$(resolve_cached_id "$RUN_ID_CACHE" 0)" ;;
    esac ;;
  *)
    RESOLVED_RUN_ID="$(resolve_cached_id "$RUN_ID_CACHE" 0)" ;;
esac

# The deferred half of the seed above, called once the ticket is known to be real. Discarding the
# value is the point: RESOLVED_RUN_ID is already what this writes, and re-reading it here would
# make a second resolution path out of a function whose whole contract is that there is one.
seed_run_id_cache() { resolve_cached_id "$RUN_ID_CACHE" 1 >/dev/null; }

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
# freshness readers recompute. `git patch-id --stable` hashes patch CONTENT, so it survives a
# rebase and the blob-hash/hunk-offset churn one brings, while still moving the moment a commit or
# a conflict resolution alters a line. SHA identity could not tell a clean replay from a
# resolution and charged a review round for a mechanical operation.
#
# The verdict record is EXCLUDED, load-bearing on BOTH sides: at write time HEAD does not carry the
# record, at read time it does. Without it the two ids never agree and the arm reds on every
# correct record.
#
# The base is the CONFIGURED baseBranch; the merge-boundary reader has only the PR's declared base,
# so the two agree exactly when the PR targets it — this lane's contract. A retargeted PR reds
# there, fail-closed and named.
#
# Prints NOTHING when unresolvable, and every caller must treat that as a refusal: `git patch-id`
# prints nothing for an empty diff, so two failed computations compare EQUAL and an unguarded
# reader prints its ✓ having hashed nothing.
branch_patch_id() { # branch_patch_id <head-ish>
  local base id
  base="$(git -C "$REPO_ROOT" merge-base "origin/$BASE_BRANCH" "$1" 2>/dev/null)" || return 0
  [ -n "$base" ] || return 0
  id="$(git -C "$REPO_ROOT" diff "$base" "$1" -- . ":(exclude)$VERDICT_REL" 2>/dev/null \
    | git -C "$REPO_ROOT" patch-id --stable 2>/dev/null | cut -d' ' -f1)"
  printf '%s' "$id"
}

# The RENDER binding (#394): the same identity with the render manifest ALSO excluded, for the
# self-reference reason the verdict record is excluded above.
#
# The asymmetry with branch_patch_id is the design. The manifest stays INSIDE `reviewed_patch_id`,
# so committing render evidence moves the reviewed patch and the verdict binds to the evidence it
# was scored against; it stays OUTSIDE `rendered_from`, or the first commit of the manifest would
# make the manifest stale and milestone 3 would re-render forever.
render_patch_id() { # render_patch_id <head-ish>
  local base id
  base="$(git -C "$REPO_ROOT" merge-base "origin/$BASE_BRANCH" "$1" 2>/dev/null)" || return 0
  [ -n "$base" ] || return 0
  id="$(git -C "$REPO_ROOT" diff "$base" "$1" -- . ":(exclude)$VERDICT_REL" ":(exclude)$RENDER_MANIFEST_REL" 2>/dev/null \
    | git -C "$REPO_ROOT" patch-id --stable 2>/dev/null | cut -d' ' -f1)"
  printf '%s' "$id"
}

# LOCKSTEP-BEGIN contribution-compare
# THE BRANCH'S OWN CONTRIBUTION, AS LINES (#597, D-2/D-3/D-4). The escape hatch both freshness
# readers — this milestone's arms and the merge boundary's — consult when their naive check reds.
#
# WHY A HASH CANNOT ANSWER THIS. A patch identity is computed over `diff(merge-base(base, head),
# head)`, so MERGING THE BASE IN advances the merge-base and moves the id even when the branch
# alters not one line. On #583 the resolution was a pure union — no new branch line — and the id
# still moved from 1decd12550cd to 86daf57fb18e, because the CONTEXT lines around the branch's own
# additions in CLAUDE.md and docs/testing.md had changed underneath them. That cost a review round
# against an unmoved head and a hand re-stamp.
#
# THE COMPARISON THAT CAN. Take the `+`/`-` lines only, per file, each side measured against ITS
# OWN merge-base, and compare them. Context is excluded on purpose: a base merge moves context, and
# context is not something a review approves. This is AC-4's "nine-file hash comparison,
# mechanized" — the one the ticket ran by hand to prove the branch's contribution was identical.
#
# THE STATE MACHINE IS ANCHORED ON COLUMN 0, and that is what makes it unambiguous rather than
# heuristic: inside a hunk EVERY line carries a ' ', '+', '-' or '\' prefix, so a body line reading
# `diff --git …` or `@@ …` at column 0 cannot exist. A naive `/^[+-]/` over the whole diff would
# have eaten the `---`/`+++` file headers and — the failure that actually bites in a repo full of
# markdown and shell — read a removed line beginning `-- ` as one of them.
contribution_lines() { # contribution_lines <repo-root> <base-ref> <head-ish> <exclude-path>
  local base
  git -C "$1" cat-file -e "$3^{commit}" 2>/dev/null || return 1
  base="$(git -C "$1" merge-base "$2" "$3" 2>/dev/null)" || return 1
  [ -n "$base" ] || return 1
  git -C "$1" diff "$base" "$3" -- . ":(exclude)$4" 2>/dev/null | awk '
    /^diff --git /        { inbody = 0; f = ""; next }
    !inbody && /^--- /    { p = substr($0, 5); if (p != "/dev/null") { sub(/^a\//, "", p); f = p } next }
    !inbody && /^\+\+\+ / { p = substr($0, 5); if (p != "/dev/null") { sub(/^b\//, "", p); f = p } next }
    !inbody && /^@@/      { inbody = 1; next }
    inbody && /^[+-]/     { print f "\t" $0 }
  '
}

# DID THE CONTRIBUTION MOVE — rc 0 identical, 1 moved, 2 not computable.
#
# rc=1 prints the ENUMERATION D-6 requires, one `path<TAB>count<TAB>first-offending-line` row per
# affected file, `LC_ALL=C sort`ed so two runs over one tree cannot disagree about order. The
# enumeration is the invalidation's PRECONDITION, not its decoration: a caller that cannot name an
# affected line has the doubt case, and AC-3 says the verdict stands there.
#
# rc=2 ON AN EMPTY CONTRIBUTION, either side, and that guard is load-bearing rather than defensive
# — it is the same one `branch_patch_id`'s header states for `git patch-id`: two failed
# computations compare EQUAL, so an unguarded reader prints its ✓ having compared nothing. An
# unresolvable merge-base, a head absent from this checkout's history and an empty measured range
# all surface here as the same refusal to answer, which is correct: they are all "no comparison
# was made", and splitting them produces an arm no case can kill.
#
# THE CALLER OWNS THE rc=2 POLICY, not this function. D-5 points the two live callers at
# fail-OPEN — the verdict stands, and the line says so — against every other unreadable-input path
# in these two tools, which fail closed. That reversal is OR-1, and keeping it in the callers is
# what makes it a one-line flip rather than a rewrite.
contribution_delta() { # contribution_delta <repo-root> <base-ref> <old-head> <new-head> <exclude-path>
  local d rc=0
  d="$(mktemp -d 2>/dev/null)" || return 2
  contribution_lines "$1" "$2" "$3" "$5" > "$d/old" 2>/dev/null || rc=2
  contribution_lines "$1" "$2" "$4" "$5" > "$d/new" 2>/dev/null || rc=2
  if [ "$rc" -eq 0 ] && { [ ! -s "$d/old" ] || [ ! -s "$d/new" ]; }; then rc=2; fi
  if [ "$rc" -eq 0 ] && ! cmp -s "$d/old" "$d/new"; then
    rc=1
    awk -F'\t' '
      NR == FNR { n1[$1]++; L1[$1 SUBSEP n1[$1]] = $2; next }
                { n2[$1]++; L2[$1 SUBSEP n2[$1]] = $2 }
      END {
        for (f in n1) seen[f] = 1
        for (f in n2) seen[f] = 1
        for (f in seen) {
          a = (f in n1) ? n1[f] : 0
          b = (f in n2) ? n2[f] : 0
          m = (a > b) ? a : b
          c = 0; first = ""
          for (i = 1; i <= m; i++) {
            x = L1[f SUBSEP i]; y = L2[f SUBSEP i]
            if (x != y) { c++; if (first == "") first = (y != "") ? y : x }
          }
          if (c > 0) print f "\t" c "\t" first
        }
      }
    ' "$d/old" "$d/new" | LC_ALL=C sort
  fi
  rm -rf "$d"
  return "$rc"
}

# The enumeration, as ONE line an operator reads in a single pass. Stdin is contribution_delta's
# rc=1 output; the shape mirrors the existing arms' `(e.g. X)` style rather than inventing a
# second one. NO SILENT CAP: past the third file it says how many more there are.
contribution_summary() { # contribution_summary  (delta rows on stdin)
  awk -F'\t' '
    NF == 0 { next }
    { n++; total += $2; if (n <= 3) { parts = parts (parts == "" ? "" : "; ") $1 ": " $2 " line(s) (e.g. " $3 ")" } }
    END {
      if (n == 0) { print "no affected line could be named"; exit }
      if (n > 3) parts = parts "; and " (n - 3) " more file(s)"
      print total " reviewed line(s) across " n " file(s) — " parts
    }
  '
}
# LOCKSTEP-END contribution-compare

# THE GATE-SIDE BINDING (#597 D-3), memoized. Both freshness arms in milestone 4 ask the SAME
# question — "did the branch's own contribution move between the head the record names and this
# one" — so they ask it through ONE call site. Two implementations of that question is precisely
# the drift the lockstep markers exist to prevent, and a second computation could only disagree
# with the first.
#
# The old head is the record's own `reviewed_head` (D-2): no new record key, no schema change, and
# every in-flight and already-merged record stays readable with no re-stamp obligation.
CONTRIB_RC=""
CONTRIB_DETAIL=""
contribution_state() { # contribution_state <old-head> <new-head> — sets CONTRIB_RC/CONTRIB_DETAIL
  [ -n "$CONTRIB_RC" ] && return 0
  CONTRIB_DETAIL="$(contribution_delta "$REPO_ROOT" "origin/$BASE_BRANCH" "$1" "$2" "$VERDICT_REL")"
  CONTRIB_RC=$?
  return 0
}

# ---------------------------------------------------------------- the inheritance chain (#375)
# The same extraction record_key does, against a COMMITTED version of the record instead of the
# working-tree file. It is the only way to read a PRIOR round: the path holds one round at a
# time, so every round but the newest exists solely in `git log` on that path.
record_key_at() { # record_key_at <key> <commit>
  git -C "$REPO_ROOT" show "$2:$VERDICT_REL" 2>/dev/null \
    | grep -oE "$1:[[:space:]]*[A-Za-z0-9._-]+" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"
}

# LOCKSTEP, canonical side (#375). This awk program is held byte-identical by the record's two
# other readers — scripts/check-lean-chain.sh and lean-reconcile.sh — because all three parse
# the SAME literal in a file-format-neutral form that needs no adaptation to the host dialect.
# There was nothing to invent, so declining to check it would only have been declining to check.
# The coupling is one-directional in the dangerous way: a reader that kept the OLD first-match
# extraction still parses every correct record identically and diverges only on the adversarial
# one, so drift here is invisible to every green run — and it is not hypothetical, since the
# three-reader agreement is what made the pre-fix blind spot uniform rather than caught.
# Behavioral guards sit under it at each reader and compose writer-to-reader: lean-gate-selftest.sh
# (z1)/(z2)/(z3), check-lean-chain-selftest.sh (V6)/(V6b), lean-reconcile-selftest.sh (N7)/(N7b).
# The markers catch what those cannot — a fourth reader added later with a hand-copied extraction.
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
# The COUNT is reported, and milestone 4 puts it in its pass line: with inheritance, "this head
# was reviewed" means "a chain of N verified rounds covered it", and a checkmark should say which
# claim was checked. It is also what makes the window below measurable from outside.
#
# The search window starts strictly BELOW <declaring-commit> and shrinks past each hit, so the walk
# runs STRICTLY BACKWARDS. That keeps a branch reverted to a previously-reviewed tree readable — an
# unbounded search resolves such a round to ITSELF, counting the record under test as a link in its
# own chain — and makes termination structural, so there is no cycle counter to get wrong.
#
# <declaring-commit> is EMPTY at write time: the record is not committed yet and cannot appear in
# the history being searched. Read-side callers pass it.
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
#   <iso> | milestone-3 | advisory | <reason>          # #642 — a demoted lane reported a red
#
# The `session` row is the BUILD-SESSION SET (#446). It spells the id WITHOUT a `session_id:` key:
# `record_key` here and `extract_key` in lean-reconcile.sh take the FIRST match in the file, and the
# header must keep winning that race. Reconciliation keys (AC-14) ride in the header so a run stays
# reconcilable by whatever reads it later.
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# The header is written ONCE at creation, and `entry` creates the file BEFORE SKILL.md orders the
# RUN_ID export — so on an ordinary run it is stamped `unset`. Left unhealed that is not cosmetic:
# lean-reconcile.sh's arm (1) compares the bot claim comment's run_id against this header's, so an
# honest github run reds at the merge boundary with the real id on one side and `unset` on the
# other. Heal the field.
#
# The BUILD CACHE is the authority, not $RESOLVED_RUN_ID: only `entry` and `claim` persist there,
# and arm (1) compares this header against what `claim` wrote, so the header must carry the
# ESTABLISHED identity — a milestone call made with an ad-hoc RUN_ID leaves it alone. It is also
# what keeps the review role out: a review identity is never in the build cache (P10).
#
# Matching the literal `unset` is a narrowing, not a second guard — the cache compare already makes
# a rewrite of an established id a no-op — so a surviving mutant on the two lines below is not a
# coverage hole. It is there to keep a healed run from spawning awk on every append.
# TEST-ONLY, like LEAN_GATE_OBSERVE above — never set in CI or by an operator. Pauses the caller
# between its absence check and its write so a selftest can force two same-issue writers to both
# observe "absent", the one shape a real race cannot be driven through deterministically. Bounded
# (10s) so a broken harness cannot hang a real run.
_lean_gate_test_stall() { # _lean_gate_test_stall <label>
  [ -n "${LEAN_GATE_TEST_STALL_DIR:-}" ] || return 0
  : > "$LEAN_GATE_TEST_STALL_DIR/ready.$1.$$"
  local waited=0
  while [ ! -e "$LEAN_GATE_TEST_STALL_DIR/go" ] && [ "$waited" -lt 100 ]; do
    sleep 0.1; waited=$((waited + 1))
  done
}

heal_progress_run_id() {
  [ -f "$PROGRESS_FILE" ] || return 0
  [ "$RESOLVED_RUN_ID" != "unset" ] || return 0
  [ "$(cat "$RUN_ID_CACHE" 2>/dev/null)" = "$RESOLVED_RUN_ID" ] || return 0
  [ "$(count_matches '^run_id: unset$' "$PROGRESS_FILE")" -gt 0 ] || return 0
  _lean_gate_test_stall heal
  # #528: a UNIQUE temp, not the fixed "$PROGRESS_FILE.heal" sibling this used to write — two
  # concurrent heals (same-issue re-entry, never a cross-lane race: STATE_DIR is issue-keyed)
  # no longer stomp each other's in-flight write. `mktemp` creates it atomically; same
  # directory as PROGRESS_FILE keeps the final `mv` a same-filesystem rename, so no reader ever
  # observes a partial file.
  local tmp
  tmp="$(mktemp "$PROGRESS_FILE.heal.XXXXXX")" || return 0
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
#
# #528: the check-then-append above is not atomic — two gate processes on the SAME issue can both
# read zero rows and both append, duplicating the line this function exists to keep singular.
#
# AN ATOMIC CLAIM, THEN A PLAIN APPEND — deliberately NOT heal_progress_run_id's temp-plus-rename.
# That rebuilds the whole file, making this a SECOND rewriter, and progress_token()'s soundness
# argument rests on there being exactly one: a rebuild can drop a row a concurrent
# append_attempt/append_absent wrote in the gap, which silently un-charges #494's fix budget (that
# append fires only on a fresh failure and is never replayed). Append-only keeps the invariant true.
#
# THE CHECK ABOVE IS A FAST PATH, not the guard: two writers can both pass it before either writes,
# and the gap can be arbitrarily wide. The guard is the `mkdir` — atomic, refuses an existing
# target, so exactly ONE writer enters and the rest return immediately. THE RE-CHECK INSIDE is what
# makes it exactly one: a loser arriving after the winner released would otherwise append a second
# row.
#
# HELD ACROSS ONE APPEND, THEN RELEASED. A persistent claim cannot tell "held by a concurrent
# writer" from "orphaned by a record that was replaced since", and this repo replaces records
# routinely — such a claim permanently blocks the milestone from ever being recorded satisfied,
# which is far worse than the duplicate row it prevents (measured: it reded a full `all` sweep in
# this file's own fixture). The one window left is a process killed between mkdir and rmdir;
# `clear_satisfied_claims` sweeps the orphan at `entry`.
append_satisfied() {
  ensure_progress_file
  [ "$(count_matches "| milestone-$1 | satisfied" "$PROGRESS_FILE" -F)" -eq 0 ] || return 0
  _lean_gate_test_stall "satisfied-$1"
  local claim="$PROGRESS_FILE.satisfied-$1.claim"
  mkdir "$claim" 2>/dev/null || return 0
  if [ "$(count_matches "| milestone-$1 | satisfied" "$PROGRESS_FILE" -F)" -eq 0 ]; then
    append_line "$(now_iso) | milestone-$1 | satisfied"
  fi
  rmdir "$claim" 2>/dev/null
  return 0
}

# Orphans only — see append_satisfied. Called where a leftover claim can no longer be held by a
# live writer: at `entry`, which every session runs before anything else.
clear_satisfied_claims() { rm -rf "$PROGRESS_FILE".satisfied-*.claim; }

# #531 D-10. THE PER-OBLIGATION ROW, and its verb is load-bearing rather than descriptive.
#
# progress_token narrows to milestone n by the FIXED SUBSTRING `| milestone-n | satisfied`, so an
# obligation row spelled with that verb would move the scheduler's close-out token the instant the
# FIRST of the two obligations held — reporting `done` over a run with no closing comment on it.
# `obligation` collides with nothing: not progress_token's row kinds, not attempt_count's, not
# absent_count's, not unclosed_count's pair.
#
# BOTH DIRECTIONS ARE RECORDED: the scheduler's failure message (D-12) has to name which obligation
# is outstanding, and a record of successes alone cannot answer that.
#
# IDEMPOTENT ON THE FULL TRIPLE, not the name — `unmet` then `met` is the history a fix round
# leaves — so one row per (obligation, state) pair.
#
# THE DETAIL IS FREE TEXT AFTER THE TRIPLE (#590); both readers match the triple as a FIXED
# SUBSTRING, so a row carrying a detail dedupes exactly as a bare one. It exists for the close-out's
# cost obligations, which can be met by a real published figure or by a documented skip on a host
# with no telemetry — without it those are one `met` row.
append_obligation() { # append_obligation <milestone> <name> <met|unmet> [detail]
  ensure_progress_file
  [ "$(count_matches "| milestone-$1 | obligation | $2 | $3" "$PROGRESS_FILE" -F)" -eq 0 ] || return 0
  append_line "$(now_iso) | milestone-$1 | obligation | $2 | $3${4:+ | $4}"
}

# Record the outstanding obligation, then fail EXACTLY as before. Every milestone-5 red that names
# one of the two obligations routes through here rather than calling fail_milestone directly, so
# the record and the failure cannot fall out of step — the shape that would let a red leave no row
# and send the scheduler back to reporting all of them as one.
fail_obligation() { # fail_obligation <name> <reason>
  append_obligation 5 "$1" unmet
  fail_milestone 5 "$2"
}

# #642. The ABSENT-verb twin, for the milestone-5 obligations whose red is an announcement: the
# next checklist step has not happened yet. Same obligation row, same refusal, no fix attempt.
block_obligation() { # block_obligation <name> <reason>
  append_obligation 5 "$1" unmet
  block_milestone 5 "$2"
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
# TWO VERBS, NOT ONE. Closing a `started` row with the concluding `attempt`/`satisfied` line is
# unsound here: append_satisfied is idempotent (D-41), so re-evaluating an already-satisfied
# milestone appends no closing line — and CLAUDE.md mandates exactly such a re-run before
# close-out, so every honest run would end its record looking interrupted. The conclusion gets its
# own deliberately NON-idempotent verb.
#
# THE PAYLOAD IS `rc=<n>` because `concluded | satisfied` would put the literal `satisfied` on a
# bookkeeping line — the collision trap absent_count's note records. NEITHER VERB IS IN
# progress_token's ROW SET, on purpose.
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
# harness-assigned. Read straight from the ambient environment, the documented manual recovery —
# run from the REVIEW session, the only place a missing marker becomes visible — stamped the review
# session as the build session, and the boundary reported an independent review as a P10 self-review.
#
# A SET RATHER THAN A LOOKUP. The progress HEADER is seed-once and single-valued, so a second build
# session on the same PR would carry session 1's id on its own marker with nothing checking it at
# session level. `mark` keeps writing the AMBIENT id — correct on every honest path — and REFUSES
# when that session is not a recorded build session. A refusal is recoverable; a mis-stamped marker
# is not: it survives a re-run (the idempotence guard keys on run_id) and a corrective second
# marker (the boundary compares against EVERY marker).
#
# THE SET IS header ∪ rows. The header is already the build identity by cmd_verdict's compare, and
# including it keeps a run already in flight, whose file has no session rows yet, from stranding.
#
# 'unset' and the empty string are NOT members, or cmd_mark's compare would pass two unverifiable
# values against each other and write `session_id: unset` onto the marker.
# Held verbatim by plugins/dev-pipeline/tools/pipeline-cost-block.sh, whose --issue mode derives
# the published cost figure's session set from this same record (#546). The two must not diverge:
# a cost block counting a wider or narrower set than `mark` refuses on is a figure that reads
# correct while attributing a run's money to the wrong number of sessions — the exact defect that
# mode exists to close, and one no green run can surface.
# LOCKSTEP-BEGIN lean-session-set
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
# LOCKSTEP-END lean-session-set

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
# to learn whether it would fail WITHOUT recording anything. Recording stays the real 1..5 loop's
# job; a pre-pass that recorded would double-count every attempt it shares with the real call
# further down the same `all` sweep. It reports EXHAUSTION as its own value, predicted from the
# count on file — `count >= FIX_BUDGET` is exactly when the recording path's post-append
# `count > FIX_BUDGET` fires — because "spent" and "failed once" are the two states a scheduler
# must not confuse.
#
# THE CLASS (#496 S1). $3 is the exit code a red returns, defaulting to 1, so every milestone that
# does not classify is unchanged. Budget exhaustion OUTRANKS the class in both paths: 4 keeps its
# prior meaning, and a class-6 red suppressing a spent budget would trade one misreport for another.
#
# THE INFRA CLASS (#527 D-8) is the one exception, and it inverts that rule rather than
# contradicting it: class 7 says the evaluation did not happen, so it spends nothing and never can,
# and reporting 4 would tell the caller "out of attempts" about a call that took none. So the class
# is honored BEFORE the append, and observe predicts the identical answer. On the recording path
# exhaustion then needs no carve-out: `count > FIX_BUDGET` is only reached on a count this call
# did increment.
fail_milestone() {
  local n="$1" reason="$2" class="${3:-1}" count
  if [ "${LEAN_GATE_OBSERVE:-0}" = "1" ]; then
    warn "✗ milestone-$n (observe): $reason"
    [ "$class" = "$INFRA_CLASS" ] && return "$INFRA_CLASS"
    count="$(attempt_count "$n")"
    [ "$count" -ge "$FIX_BUDGET" ] && return 4
    return "$class"
  fi
  if [ "$class" = "$INFRA_CLASS" ]; then
    warn "✗ milestone-$n: $reason"
    warn "  INFRASTRUCTURE, not a verdict about this branch — NOTHING was evaluated, so no fix attempt was charged. Re-invoke the milestone."
    return "$INFRA_CLASS"
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

# #494 D-1. A milestone that reds because its artifact IS NOT WRITTEN YET — not because a fix did
# not work. Step 3 orders `bash G 1 <issue>` to learn the path step 4 must write to, so the first
# such red is the contract's own recommended move; charging it made the fix bound tightest on
# exactly the runs that later need it most, and made `attempt` lines unreadable as a difficulty
# signal for the retro corpus.
#
# A SECOND COUNTER RATHER THAN FREE: free absence removes the only thing bounding a session that
# loops on step 3 forever. Bounded on its own much larger budget (D-2), reusing `rc=4` so
# build-lean's existing hard-stop handling covers it with no new operator path.
#
# #642 WIDENED IT past #494's single site. The set is exactly the reasons docs/gate-ablation.md
# adjudicates `unchanged` — every one an ANNOUNCEMENT that the checklist's next step has not
# happened yet: m1/spec-absent, m4/verdict-absent, m5/progress-current, m5/no-open-pr,
# m5/closing-comment, m5/identity-stamp. A red that names something the run was going to do anyway
# is not a failed fix, whichever milestone it sits on.
#
# THE CLASS IS CARRIED (#642). Milestone 4's absence returns 5, not 1: the remedy is a REVIEW
# round, and a scheduler that read a bare 1 there would re-spawn BUILD to fix nothing.
block_milestone() { # block_milestone <milestone> <reason> [class]
  local n="$1" reason="$2" class="${3:-1}" count
  if [ "${LEAN_GATE_OBSERVE:-0}" = "1" ]; then
    count="$(absent_count "$n")"
    warn "✗ milestone-$n (observe): $reason"
    [ "$count" -ge "$ABSENT_BUDGET" ] && return 4
    return "$class"
  fi
  append_absent "$n" "$reason"
  count="$(absent_count "$n")"
  warn "✗ milestone-$n: $reason (absent $count/$ABSENT_BUDGET — not a fix attempt)"
  if [ "$count" -gt "$ABSENT_BUDGET" ]; then
    append_line "$(now_iso) | milestone-$n | absent-exhausted | $count calls"
    warn "milestone-$n has been evaluated $count times against an artifact that was never written — hard stop."
    return 4
  fi
  return "$class"
}

pass_milestone() {
  if [ "${LEAN_GATE_OBSERVE:-0}" = "1" ]; then
    say "✓ milestone-$1 (observe)${2:+: $2}"
    return 0
  fi
  append_satisfied "$1"; say "✓ milestone-$1${2:+: $2}"; return 0
}

# ---------------------------------------------------------------- entry precondition
# AC-14. The predicate is a NON-EMPTY ledger file for THIS session, anchored at the main checkout.
# Directory existence is explicitly NOT the test — an empty or absent per-session file means the
# hook never fired, and a run whose tool calls left no ledger cannot be reconciled. Fail closed.
#
# #416: fail-closed was never the gap — NOTHING ENFORCED THAT THIS RAN. `entry` wrote nothing
# durable, so a run that skipped step 1 reached five green milestones, a verdict record and a
# merged PR with no artifact recording the omission (twice, observed). The row below is that
# artifact; require_entry_attested() is what makes skipping step 1 a refusal.
ENTRY_ROW_MARKER="| entry | ledger="

entry_row_present() { [ "$(count_matches "$ENTRY_ROW_MARKER" "$PROGRESS_FILE" -F)" -gt 0 ]; }

# #611. The other half of "a checked control, not a prose reminder": the argument the run boundary
# accepted, and the provenance its caller declared for it. Its OWN `| ticket |` namespace on the
# teardown row's precedent — nothing reading `| milestone-<n> |` (progress_token, the obligations
# report) can mistake it for a certified milestone, and the scheduler's continuation predicate is
# unmoved by it. DEDUPED on the whole row so a resumed run's second `entry` does not stack
# identical lines, while a re-entry that declares a DIFFERENT source records that as a new fact.
record_ticket_resolution() {
  local row
  row="| ticket | resolved=$ISSUE | source=$TICKET_SOURCE | tree=$TICKET_TREE_HEAD"
  [ "$(count_matches "$row" "$PROGRESS_FILE" -F)" -eq 0 ] || return 0
  append_line "$(now_iso) $row"
}

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
# WARN, never refuse (D-1/D-3). The audit-ledger precedent does not transfer: that ledger is
# CONSUMED downstream, whereas nothing consumes cost — no milestone, no verdict arm, no
# merge-boundary check. Refusing would promote an opt-in, experimental feature to a hard
# precondition for every consumer, including those with no collector installed.
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
# A stale worktree per finished ticket is not a disk cost: `git checkout <branch>` in the main
# checkout then fails with "already used by worktree at ..." for work that landed weeks earlier.
#
# TWO ENTRY POINTS, ONE REMOVAL. `teardown` fires at approval; the sweep below covers the exits
# approval never reaches — the session died, a human merged with no lean round, the run was
# abandoned — and of five stale worktrees found on a live checkout, most were the second kind. Both
# funnel through worktree_destroy(), so a worktree can only be destroyed on terms the other path
# would also accept.
#
# NEVER `git branch -d/-D`. The PR points at the branch and the verdict record is committed on it,
# so removing the CHECKOUT is correct and deleting the REF is not. Said out loud so a later edit
# does not "helpfully" add the delete.

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

# #530: PLURAL by construction. A second worktree on the same branch is a SANCTIONED state, not
# a violated expectation — review-lean cuts its own checkout of the PR head, and the build
# worktree is not guaranteed to still be there when it does. A singular `lean_worktree_for_branch`
# that returned on the first match left every caller blind to the second tree, which is what
# accumulated the stray worktrees this fixes. One path per line; both current callers iterate, so
# there is no remaining consumer of a first-match form.
lean_worktrees_for_branch() { # lean_worktrees_for_branch <branch> -> one path per line, or nothing
  local p b found=1
  while IFS="$(printf '\t')" read -r p b; do
    [ -n "$b" ] || continue
    [ "$b" = "$1" ] || continue
    printf '%s\n' "$p"
    found=0
  done <<EOF
$(lean_worktrees)
EOF
  return "$found"
}

# ---------------------------------------------------------------- settings inheritance (#647)
# A git worktree receives TRACKED files only. The operator's permission allowlist lives in
# `.claude/settings.local.json`, which is gitignored — so it STRUCTURALLY cannot exist in a lane
# worktree, and a session launched with that worktree as its cwd starts with no allowlist at all.
# Every tool call then falls through to the harness's classifier, which is probabilistic: two
# identical launches of the #641 lane two hours apart produced one completed build and one session
# denied `git fetch`, `gh api` and its own first gate call. `Bash(git *)` WAS in the operator's
# allowlist and was denied anyway — the rule existed and simply was not visible from where the
# session ran. A session denied every tool call still exits 0, so the failure is near-silent.
#
# So the lane worktree inherits the posture of the checkout it was cut from, which is the only
# posture the operator ever consented to. Four properties, each load-bearing:
#
#   COPY, NEVER SYMLINK. A symlink into the main checkout would let a lane session's write reach
#   the operator's real settings file. `cp` also dereferences a symlinked SOURCE, so what lands in
#   the worktree is a regular file with an independent inode either way.
#
#   NEVER CLOBBER. A destination that already exists is left alone, and that one rule does two
#   jobs: a re-entry reusing a worktree cannot overwrite edits made inside it, and a `settings.json`
#   that is TRACKED is already there and is skipped for free — so nothing here has to ask git what
#   is tracked, which is the reversible default the ticket's Open Region names.
#
#   IGNORED, OR NOT WRITTEN AT ALL. The copy is skipped, loudly, unless the destination path is
#   already covered by an ignore rule — because `entry`'s own sweep and the scheduler both decide
#   whether a lane worktree still holds work by asking whether its tree is clean.
#
#   ADVISORY. Nothing here may reach `entry`'s exit status. The attestation is what `entry` exists
#   to establish; a settings file that could not be copied is a lost convenience, not evidence.
#   Same rule `cmd_entry_sweep` runs under, for the same reason.
#
# NOT INERT, and that was checked rather than assumed: a lane worktree is not a separate trust
# root — the harness resolves project identity through the git common dir, so a worktree of a
# trusted checkout honours a project-scope allowlist on arrival. Were it otherwise, this copy would
# land a file the harness ignores, which reads exactly as green as a working remedy.
seed_lane_worktree_settings() {
  local paths wt rel src dst
  paths="$(lean_worktrees_for_branch "$LEAN_BRANCH")" || return 0
  [ -n "$paths" ] || return 0
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    # The main checkout is the SOURCE. An operator who checked the lane branch out there would
    # otherwise have the file copied onto itself.
    [ "$wt" = "$MAIN_ROOT" ] && continue
    for rel in settings.local.json settings.json; do
      src="$MAIN_ROOT/.claude/$rel"
      dst="$wt/.claude/$rel"
      # Absent at the origin is the documented no-op, not a diagnosis: a consumer who keeps no
      # local settings has nothing to inherit and must not be told they are missing something.
      [ -f "$src" ] || continue
      # -e OR -L: a dangling symlink is `-e`-false and must still count as present, or the copy
      # would write THROUGH it into whatever the operator pointed it at.
      if [ -e "$dst" ] || [ -L "$dst" ]; then
        say "  settings: $wt/.claude/$rel is already present — left as it is."
        continue
      fi
      # IGNORED, OR NOT WRITTEN AT ALL (#647 round 1, B1). Asked of the DESTINATION PATH, before
      # any bytes exist there, so it holds on the first seed as much as on the hundredth — the
      # same shape as the render-output assertion this file already makes before milestone 3
      # writes a PNG, and for a stricter reason. `git check-ignore` answers the very question
      # `git status --porcelain` answers, and that predicate is load-bearing here: an unignored
      # untracked file makes `worktree_inflight` report 8, "its tree is not clean" — to the sweep
      # three lines up in `cmd_entry`, which then declines to reap the worktree FOREVER, and to
      # the scheduler's #531 D-3 boundary, which reads a finished build session as still carrying
      # work. A convenience that quietly disables the reaper is not a convenience.
      #
      # It does not re-open the tracked-ness question the never-clobber rule closed: a tracked
      # `settings.json` is already in the worktree and returned above, so this line is only ever
      # reached for a destination that does not exist.
      if ! git -C "$wt" check-ignore -q ".claude/$rel" 2>/dev/null; then
        warn "  settings: .claude/$rel is not git-ignored in $wt, so copying it would leave the lane worktree permanently unclean — not inherited."
        warn "    Add this line to .gitignore to receive it: .claude/$rel"
        continue
      fi
      mkdir -p "$wt/.claude" 2>/dev/null \
        || { warn "  settings: cannot create $wt/.claude — .claude/$rel not inherited."; continue; }
      if cp "$src" "$dst" 2>/dev/null; then
        say "  settings: copied .claude/$rel into $wt — the lane worktree inherits this checkout's posture."
      else
        warn "  settings: could not copy .claude/$rel into $wt — a session run there will have no allowlist."
      fi
    done
  done <<EOF
$paths
EOF
  return 0
}

# The DECLINE path, and the only one either mechanism has. It prints rather than fails (D-6):
# the run is complete and a leftover directory is hygiene, not evidence, so a refusal must not
# red a gate or an `entry` that is otherwise ready to start the next run. The manual command is
# printed in full because it IS the whole remedy.
#
# #531: it also PUBLISHES the reason it printed, so cmd_teardown's diagnostic row records the
# same words the operator just read rather than re-deriving them from a second source that could
# disagree. Set before anything is printed, so a caller reading it back is never reading a stale
# value from an earlier decline.
WORKTREE_KEEP_REASON=""
worktree_keep() { # worktree_keep <path> <reason> [<detail>]
  WORKTREE_KEEP_REASON="$2"
  warn "  keeping $1 — $2."
  if [ -n "${3:-}" ]; then printf '%s\n' "$3" | sed 's/^/[lean-gate]     /' >&2; fi
  warn "  remove it by hand once that is resolved: git -C '$MAIN_ROOT' worktree remove '$1'"
}

# ---------------------------------------------------------------- the IN-FLIGHT PREDICATE (#531)
# THE ONE QUESTION BOTH SIDES ASK: does this lane worktree hold work that exists nowhere else?
# Teardown has always asked it — a worktree carrying uncommitted or unpushed work must not be
# destroyed — and #531 D-3 gives the SCHEDULER the same question at a different boundary: a BUILD
# session that exits 0 with commits unpushed is `claude -p` ending a turn, not a block finishing,
# and the round that follows reviews a remote head missing everything BUILD just did.
#
# EXTRACTED RATHER THAN RE-DERIVED. Two copies of "is this tree collected" are two answers the
# moment one grows a case, and a scheduler-side copy drifting LENIENT is a review round spent on
# code nobody will merge — the defect being fixed. One predicate, two callers.
#
# PUSHED-NESS IS "origin/<branch>..HEAD is empty", not `HEAD == origin/<branch>`: once the review
# session pushes its verdict record the build worktree is legitimately BEHIND origin, and strict
# equality would refuse exactly the removal this exists for. Behind is safe; ahead is not.
#
# THREE ANSWERS, NOT TWO. "The status could not be read" and "origin/<branch> is unresolvable" are
# reads that did not complete, and both callers fail CLOSED on them — the error-reads-as-success
# posture `staleness` and `progress` already take.
#
# The reason and its detail are PUBLISHED rather than printed, so each caller frames them in its own
# vocabulary without a second copy of the conditions.
INFLIGHT_REASON=""
INFLIGHT_DETAIL=""
worktree_inflight() { # worktree_inflight <path> <branch> — 0 collected · 8 in flight · 1 unreadable
  local wt="$1" br="$2" dirty unpushed
  INFLIGHT_REASON=""
  INFLIGHT_DETAIL=""
  dirty="$(git -C "$wt" status --porcelain 2>&1)" \
    || { INFLIGHT_REASON="its status could not be read ($dirty)"; return 1; }
  if [ -n "$dirty" ]; then
    INFLIGHT_REASON="its tree is not clean"
    INFLIGHT_DETAIL="$dirty"
    return 8
  fi
  # Best effort, and wrong only ever in the SAFE direction: a fetch that fails leaves a stale
  # remote-tracking ref, which can make pushed work look unpushed and KEEP the worktree (or, at the
  # scheduler boundary, stop a run for a push that already happened), never the reverse.
  git -C "$wt" fetch --quiet origin "$br" >/dev/null 2>&1
  unpushed="$(git -C "$wt" log --oneline "refs/remotes/origin/$br..HEAD" 2>&1)" \
    || { INFLIGHT_REASON="origin/$br is unresolvable, so nothing proves its work is pushed"; return 1; }
  if [ -n "$unpushed" ]; then
    INFLIGHT_REASON="it carries commits that are not on origin/$br"
    INFLIGHT_DETAIL="$unpushed"
    return 8
  fi
  return 0
}

# The preconditions and the removal. 0 = the worktree is gone, 1 = it was deliberately kept.
#
# Gitignored files do not block `git worktree remove`, so the run's render PNGs under
# `.claude/lean-renders/<issue>/` go with it — safe, because milestone 4 depends on the render id
# alone once the verdict lands, never on the PNG bytes.
worktree_destroy() { # worktree_destroy <path> <branch>
  local wt="$1" br="$2" out rc
  if [ "$wt" = "$MAIN_ROOT" ]; then
    worktree_keep "$wt" "it is the main checkout, not a lane worktree"
    return 1
  fi
  # Both non-zero answers keep the worktree, exactly as the four inline conditions this replaced
  # did: an unreadable status is no more evidence that the work is safe than a dirty tree is.
  worktree_inflight "$wt" "$br"; rc=$?
  if [ "$rc" -ne 0 ]; then
    worktree_keep "$wt" "$INFLIGHT_REASON" "$INFLIGHT_DETAIL"
    return 1
  fi
  out="$(git -C "$MAIN_ROOT" worktree remove "$wt" 2>&1)" \
    || { worktree_keep "$wt" "git refused to remove it ($out)"; return 1; }
  say "  removed $wt (branch $br kept — the PR points at it)"
  return 0
}

# #563. The SECOND value handed down that same channel, and the same shape for the same reason:
# the `test` command a consumer configured is a string this gate runs and cannot rewrite, so a
# flag is not reachable and an environment name is.
#
# WHAT IT BUYS: run-selftests.sh carries a content-addressed pass cache (#448), and a milestone-3
# sweep re-derives the same verdicts every time a run comes back to it (#549: ~9:47 of an 82-minute
# run). The cache decides per SUITE on content, never on HEAD, so it is no new trust shortcut: a
# suite serves iff every input it DECLARED is byte-identical to a recorded pass, and one that
# declared nothing always runs.
#
# ADVERTISED, NOT ENFORCED: a `test` command that is vitest or pytest never reads it. The store
# lives OUTSIDE every checkout — a teardown must not cost the operator their cache — and carries the
# same 0-valued off switch as the mutation sweep's: a cache you cannot turn off is a green you
# cannot re-check.
lane_apply_selftest_cache() {
  local store
  # THE OFF SWITCH HAS TO SCRUB, not merely decline to export. An operator who already carries
  # LEAN_SELFTEST_CACHE_DIR in their environment hands it to every lane child by ordinary
  # inheritance, so a bare `return` here would announce a cold sweep and run a cached one — the
  # fail-open shape the switch exists to remove, wearing the fix's own output.
  #
  # An EMPTY ASSIGNMENT is the scrub. Until #566 it was also the only option available: an
  # earlier entry in SEAM_SCRUB_ENV was an assignment by this point, and `env` stops reading
  # options at the first NAME=VALUE, so a `-u` appended after one is read as the command to run
  # rather than as a scrub. That constraint died with the lane job ceiling — this is now the LAST
  # entry and `-u` would reach — but the empty assignment is kept because the reader treats empty
  # as absent, so the two are the same no-op and swapping them would be an unrelated edit.
  if [ "${LEAN_SELFTEST_CACHE:-1}" = "0" ]; then
    say "milestone-3: selftest pass cache DISABLED (LEAN_SELFTEST_CACHE=0) — this sweep runs cold."
    SEAM_SCRUB_ENV+=("LEAN_SELFTEST_CACHE_DIR=")
    return 0
  fi
  store="${LEAN_SELFTEST_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/second-shift/lean-selftest}"
  [ -n "$store" ] || return 0
  say "milestone-3: selftest pass cache store $store."
  say "  exported as LEAN_SELFTEST_CACHE_DIR to every lane command below: ADVERTISED, not enforced. A command that does not read it runs exactly as before."
  SEAM_SCRUB_ENV+=("LEAN_SELFTEST_CACHE_DIR=$store")
  return 0
}

# Checklist step 9's final act. OUTSIDE the 1..5 progression on purpose (D-2): `cmd_all` runs
# milestones 1-5 and the checklist mandates it BEFORE step 9, so a self-removing milestone 5
# would delete the worktree mid-run, before the closing comment is even posted.
#
# NOT in require_entry_attested's set: this asserts nothing and records nothing, so refusing it for
# a missing attestation would block cleanup for no evidentiary gain. worktree_destroy()'s
# preconditions guard the removal, and they are stronger and independent of any self-report.
# #531 D-11. TEARDOWN IS REPORTED, NEVER CERTIFIED. Step 9 runs `bash G 5` and THEN `bash G
# teardown`, so the outcome does not exist when milestone 5 is decided. It gets its own
# `| teardown |` namespace, invisible to anything reading `| milestone-<n> |`, which keeps it a
# diagnostic rather than a silent input to the scheduler's satisfied token.
#
# ONE ROW PER OUTCOME KIND, not one per call; a later call reaching a DIFFERENT outcome still
# appends, which is the transition an operator wants to see (kept, fixed, then removed).
#
# IT NEVER MINTS A RECORD — a write that brought the progress file into existence would undo the
# no-run-state property above. Guarded on the file, because the condition IS "there is a record to
# annotate".
append_teardown() { # append_teardown <outcome> <detail>
  [ -f "$PROGRESS_FILE" ] || return 0
  [ "$(count_matches "| teardown | $1 |" "$PROGRESS_FILE" -F)" -eq 0 ] || return 0
  append_line "$(now_iso) | teardown | $1 | $2"
}

cmd_teardown() {
  local wt paths rest="" own="" order removed_paths="" removed=0 kept_lines=""
  paths="$(lean_worktrees_for_branch "$LEAN_BRANCH")" || paths=""
  if [ -z "$paths" ]; then
    say "teardown: no registered worktree is on $LEAN_BRANCH — nothing to remove."
    append_teardown absent "no registered worktree on $LEAN_BRANCH"
    return 0
  fi
  say "teardown: $LEAN_BRANCH"
  # #530: every registered worktree on the branch is accounted for, not just the first match — a
  # second one is the sanctioned shape a review session's own checkout leaves. The caller's own
  # tree ($REPO_ROOT) is ordered LAST and never skipped: `git worktree remove` can remove the
  # current worktree from inside it, but removing it first would leave the remaining trees'
  # removal running from a deleted cwd.
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    if [ "$wt" = "$REPO_ROOT" ]; then own="${own}${wt}"$'\n'; else rest="${rest}${wt}"$'\n'; fi
  done <<EOF
$paths
EOF
  order="${rest}${own}"
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    WORKTREE_KEEP_REASON=""
    if worktree_destroy "$wt" "$LEAN_BRANCH"; then
      removed=$((removed + 1))
      removed_paths="${removed_paths:+$removed_paths, }$wt"
    else
      kept_lines="${kept_lines:+$kept_lines; }$wt — ${WORKTREE_KEEP_REASON:-reason not recorded}"
    fi
  done <<EOF
$order
EOF
  # One row per outcome KIND (append_teardown's own idempotence), not one per tree — and `kept`
  # last when a single call reaches both: the one row `progress --obligations` surfaces is then
  # the state that still needs a human, per the "LAST row wins" contract at obligations_report.
  [ "$removed" -gt 0 ] && append_teardown removed "$removed_paths"
  [ -n "$kept_lines" ] && append_teardown kept "$kept_lines"
  # ALWAYS 0, whichever way that went. A kept worktree has already reported itself, and a
  # non-zero exit on the last command of a finished run reads as "the run failed" over a
  # directory nobody needs.
  return 0
}

# ---------------------------------------------------------------- the IN-FLIGHT READ (#531)
# SCHEDULER ROLE, on the "gate owns the predicate, loop owns the comparison" division `progress`
# and `staleness` established. The scheduler must not learn this by running git itself — an
# inlined heuristic breaks the boundary its header states.
#
# READ-ONLY in the strict sense: no `attempt` row, no `satisfied` row, no fix budget, and no
# ensure_progress_file, so it cannot bring the run's record into existence. NOT in
# require_entry_attested's set, for `progress`'s reason: it is most needed where a spawn died early.
#
# NO WORKTREE IS 0, DELIBERATELY. The scheduler also calls this after the close-out, whose last act
# is teardown, and it is the honest answer besides: a tree that does not exist holds no uncollected
# work, and `git worktree remove` refuses a dirty one. A BUILD spawn that never cut a worktree is
# caught by the continuation predicate beside this.
cmd_inflight() {
  local wt rc paths win_rc=0 win_wt="" win_reason="" win_detail=""
  paths="$(lean_worktrees_for_branch "$LEAN_BRANCH")" || paths=""
  if [ -z "$paths" ]; then
    say "inflight: no registered worktree is on $LEAN_BRANCH — there is no tree that could be holding work."
    return 0
  fi
  # #530 D-1/D-3: every registered worktree on the branch is read, not just the first match, and
  # the strongest answer wins — 8 outranks 1, 1 outranks 0. A tree demonstrably holding work is
  # stronger and more actionable than one nothing could read, and clean outranks nothing. Ranked
  # explicitly (first-found wins a tie) rather than by a numeric rc comparison, so a future
  # renumbering of these codes cannot silently invert it. A tree that is passed over still prints
  # its own reason here — it just does not go on to own the terminal answer below.
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    worktree_inflight "$wt" "$LEAN_BRANCH"; rc=$?
    case "$rc" in
      8) warn "  inflight: $wt STILL HOLDS WORK — $INFLIGHT_REASON."
         if [ "$win_rc" != 8 ]; then
           win_rc=8; win_wt="$wt"; win_reason="$INFLIGHT_REASON"; win_detail="$INFLIGHT_DETAIL"
         fi ;;
      0) say "  inflight: $wt is clean." ;;
      *) warn "  inflight: $wt could not be evaluated — $INFLIGHT_REASON."
         if [ "$win_rc" = 0 ]; then
           win_rc=1; win_wt="$wt"; win_reason="$INFLIGHT_REASON"; win_detail="$INFLIGHT_DETAIL"
         fi ;;
    esac
  done <<EOF
$paths
EOF
  case "$win_rc" in
    0) say "inflight: clean — every registered tree on $LEAN_BRANCH has a clean status and every commit on origin/$LEAN_BRANCH."
       return 0 ;;
    8) warn "[lean-gate] ✗ inflight: $win_wt STILL HOLDS WORK — $win_reason."
       if [ -n "$win_detail" ]; then printf '%s\n' "$win_detail" | sed 's/^/[lean-gate]     /' >&2; fi
       warn "  Nothing outside this worktree has a copy, so a review would read a head missing it. Commit and push from $win_wt, then re-launch."
       return 8 ;;
    *) warn "[lean-gate] ✗ inflight: the predicate could not be evaluated for $win_wt — $win_reason."
       warn "  Refusing to report a tree nothing could read as collected: an unreadable answer is not a clean one."
       return 1 ;;
  esac
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
# EXACTLY TWO ROW KINDS (D-1, held at two by #497 D-3). `satisfied` and `attempt` are the only rows
# a milestone EVALUATION writes. The bookkeeping rows must stay out: `| session | <id>` is appended
# on every fresh session's `entry` call, so a naive "did the file change" predicate would be TRUE
# for any spawn that reached step 1; and `started`/`concluded` are written on EVERY continuation, so
# counting them would make each dead spawn of a background-and-exit session read as advancement and
# burn the whole `--max-continuations` budget. The in-flight pair is a record for the resuming
# SESSION, never a signal to the orchestrator.
#
# WHY A COUNT IS A SOUND TOKEN. These rows are append-only, and the single rewriter in this file
# (heal_progress_run_id) has an exact-string compare bounded to the header — so the count cannot go
# up and back down within a spawn and read as unchanged. #528 keeps that true under a concurrent
# writer by making append_satisfied claim-then-append rather than rebuild. The `progress-v1:`
# generation prefix marks the token space so a caller reaching for `-gt` has to notice this is not
# an orderable integer.
#
# NOT in require_entry_attested's set (D-2): this reads the very file an attestation would live in,
# so gating it there would remove the answer in exactly the state — a spawn that died before
# `entry` — the scheduler most needs one about.
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

# ---------------------------------------------------------------- the INFRA-DEATH READ (#527)
# THE CLASS IS DERIVED FROM RESIDUE, because nothing is alive to write it. `append_started 3`
# already flushed and there is no matching `concluded` row: the evaluation began and never
# returned. SIGKILL cannot be trapped (see the note beside run_milestone's append_started) and the
# scheduler never invokes a milestone itself, so residue is the only witness there is.
#
# LOCATED BY THE PROGRESS RECORD, which the scheduler reads from $MAIN_ROOT deliberately — the
# record must survive worktree teardown. That is the one handle both sides share.
#
# #566 NARROWED THE PREDICATE TO THE UNCLOSED COUNT ALONE — milestone 3 no longer detaches, so
# there are no runner pid records to scan and the unclosed row is the only residue an interrupted
# evaluation leaves. THE TOKEN SPACE MOVED TO v3 with it: a caller comparing a v2 reading against a
# v3 one is comparing two different questions, and the prefix makes that visible instead of
# arithmetic.

# PRINTED BEHIND A GENERATION PREFIX, like progress_token's, and for the identical reason: this is
# a number a caller must NOT order.
#
# NEVER EMPTY. "No infra death" is `m3infra-v3:0`, because the scheduler's reader rejects an empty
# token as a broken gate — a legitimate negative answer must not look like one.
infra_token() {
  local unclosed n
  unclosed="$(unclosed_count 3)"
  n="$unclosed"
  [ "$n" -lt 0 ] && n=0
  # The diagnostic, on stderr so it cannot contaminate the token on stdout. It says what was
  # counted rather than only the verdict, so an operator can tell a clean read from a suppressed
  # one without re-deriving it.
  warn "progress --infra: $unclosed unclosed milestone-3 evaluation(s)."
  printf 'm3infra-v3:%s\n' "$n"
}

# ---------------------------------------------------------------- the CLOSE-OUT REPORT (#531)
# D-12. The scheduler's close-out failure used to name three obligations as one, and could not say
# which was outstanding — every recovery began with a human reading the record by hand.
#
# A REPORT, NOT A TOKEN. Everything else on this subcommand prints an opaque value the caller may
# only COMPARE; this prints lines the caller may only ECHO. Neither lets the scheduler interpret the
# record, which is what its header forbids. TEARDOWN IS READ SEPARATELY and labelled as its own
# thing (D-11), so the report cannot be mistaken for a claim that milestone 5 certified it.
#
# ALWAYS 0: the record may legitimately be empty, and "nothing was recorded" is that answer rather
# than a failure to produce one.
#
# FIVE SINCE #590, in EXECUTION order — the three the close-out writes, then the two milestone 5
# asserts — so an operator reads top-down and the first `unmet` is where the run stopped. THE
# CLOSING COMMENT HAS NO ROW OF ITS OWN: `verdict-reference` already asserts it, and a sixth row
# would answer the same question twice and disagree with itself the moment one adapter's surface
# moved.
LEAN_M5_OBLIGATIONS='cost-block cost-log-row pr-cost-block exit-artifacts verdict-reference'

# `met` WINS over `unmet` when both are on file, and that is the only sound reading of an
# append-only record: the pair is a HISTORY, so a fix round that turned an outstanding obligation
# into a met one leaves both rows, and reporting the failure would make the record say the run got
# worse. There is no reverse transition — nothing un-meets an obligation once cmd_5 has seen it.
obligation_state() { # obligation_state <milestone> <name>
  if [ "$(count_matches "| milestone-$1 | obligation | $2 | met" "$PROGRESS_FILE" -F)" -gt 0 ]; then
    echo met
  elif [ "$(count_matches "| milestone-$1 | obligation | $2 | unmet" "$PROGRESS_FILE" -F)" -gt 0 ]; then
    echo unmet
  else
    echo "not recorded"
  fi
}

obligations_report() {
  local name td
  for name in $LEAN_M5_OBLIGATIONS; do
    printf 'milestone-5 obligation %s: %s\n' "$name" "$(obligation_state 5 "$name")"
  done
  # The aggregate, stated ALONGSIDE its parts rather than left to be inferred from them: it is
  # appended only when every obligation holds, so "both met, no aggregate" is a real state — the
  # gate redded on something that is not an obligation, the identity stamp — and a report that
  # printed only the parts could not show it.
  if [ "$(count_matches "| milestone-5 | satisfied" "$PROGRESS_FILE" -F)" -gt 0 ]; then
    printf 'milestone-5 aggregate: satisfied\n'
  else
    printf 'milestone-5 aggregate: not satisfied\n'
  fi
  # Its own namespace, its own line, never folded into the milestone above. LAST row wins, because
  # append_teardown records one row per outcome KIND and a run that fixed a kept worktree carries
  # both — the later one is the standing outcome.
  td="$(sed -n 's/^.*| teardown | \([a-z][a-z]*\) | \(.*\)$/\1 (\2)/p' "$PROGRESS_FILE" 2>/dev/null | sed -n '$p')"
  printf 'teardown: %s\n' "${td:-not recorded}"
}

cmd_progress() {
  if [ "$PROGRESS_OBLIGATIONS" -eq 1 ]; then
    obligations_report
    return 0
  fi
  if [ "$PROGRESS_INFRA" -eq 1 ]; then
    infra_token
    return 0
  fi
  progress_token "$PROGRESS_SATISFIED"
  return 0
}

# ---------------------------------------------------------------- the STALENESS PREDICATE (#515)
# The lane reads tracker and base state once, at preflight, and never again — so a run whose
# premise expired mid-flight keeps spending continuations against a base that already carries its
# fix. Measured on this repo: the branch for one ticket kept working for 30 minutes after another
# PR landed the same fix, and the ticket itself was not closed until 63 minutes after that.
#
# TWO ARMS, and the weaker one is what everybody reaches for first: a ticket closing records a
# HUMAN NOTICING, not the event, and in the motivating incident it lagged the merge by an hour.
# Still worth reading — a launch onto an already-closed ticket should not spend a run — but the
# leading signal is the base.
#
# FILE OVERLAP, NOT "THE BASE ADVANCED" (D-1). Measured here: ~9.4 first-parent merges a day, so
# bare advancement is true on essentially every multi-hour run and each stop costs a hand rebase.
# The predicate is
#
#     files(merge-base..origin/<base>) ∩ files(merge-base..<branch>) ≠ ∅
#
# which the incident satisfies (7 files landed, 4 shared with the branch). Patch-level redundancy
# was rejected as false-negative-prone: a second agent re-implementing the same fix produces a
# different patch-id.
#
# ITS KNOWN FALSE-POSITIVE CLASS, named rather than engineered around (OR-1): any file essentially
# every base merge touches — a version-pinned install doc, a lockfile — overlaps a branch that also
# edits it (32 of 32 release merges for one such doc, ~7% of runs). Deliberately NO exclusion list;
# a config key of paths that "do not count" re-introduces the judgment the mechanical predicate
# exists to avoid. The exit message names the class so an operator recognizes one in a single read.
#
# READ-ONLY (D-3): no `attempt` row, no `satisfied` row, no fix budget, no ensure_progress_file. NOT
# in require_entry_attested's set — this runs BEFORE the first BUILD spawn, whose own first act is
# `entry`, so gating it would refuse it on every honest run's first call.
#
# FAIL CLOSED (D-5): a failed fetch, an unresolvable merge-base or an unreadable tracker answer
# returns 1 naming which read failed, never 0 — a stale `origin/<base>` answering "nothing moved" is
# indistinguishable from a clean check.
#
# THE ARMS SHORT-CIRCUIT, ticket first: it is the cheaper read, and a run stopped by it is stopping
# regardless of what the base says.
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

# #650 AC-2. THE MID-RUN RE-CHECK — the one `staleness_ticket_arm` caller that runs from INSIDE a
# live payload session.
#
# WHAT WAS UNCOVERED. The scheduler asks for the refusal above at preflight and before every BUILD
# spawn; what nothing asked AFTER `entry` is whether the ticket is still open — and the scheduler
# structurally cannot, because there is no channel into a running `claude -p`. This is the other
# side of that boundary, asked by the session itself.
#
# `mark` AND NOT A MILESTONE (D-11). `require_ticket_live` fixes "one read per run boundary, never
# per milestone", and `1`..`5` are recorded as network-free; `mark` already opens a socket and
# already writes. It also lands at the moment that matters — step 7, immediately before the handoff.
#
# WHAT IT DOES NOT BUY: the session has already spent its own time. It saves the handoff and the
# review round.
#
# THE DIRECT SUBCOMMAND ONLY, and load-bearing: `cmd_5` and `cmd_close_out` call `cmd_mark` as a
# FUNCTION and never reach this guard. The landing path must stay open — a refusal there would
# strand approved, reviewed work instead of saving any.
require_ticket_still_open() {
  local rc
  staleness_ticket_arm; rc=$?
  case "$rc" in
    0) return 0 ;;
    7) warn "[lean-gate] ✗ $SUB: THE TICKET CLOSED UNDER THIS RUN. Nothing was marked and nothing was written — the PR carries no build-identity marker from this call, so no handoff is half-made."
       warn "  This session's own time is already spent; what this refusal saves is the review round after it. Do not hand off."
       warn "  If the work should still land, re-open #$ISSUE and re-invoke. If it should not, the worktree and the claim are left in place for a manual rescue."
       exit 7 ;;
    *) warn "[lean-gate] ✗ $SUB: the ticket's liveness could not be read, so whether this run's premise still holds is unknown."
       warn "  Fail closed, on the arm's own precedent: an unreadable tracker is not an open ticket, and a marker posted on that guess is the handoff this check exists to stop."
       exit 2 ;;
  esac
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
  # Idempotent and retroactive (D-11): a run that skipped step 1 self-heals with one command, while
  # with `audit-toolkit` off the predicate above still refuses. OR-1: the row is per-RUN, not
  # per-session — it attests that the run STARTED attested, and a resuming session inherits it.
  ensure_progress_file
  record_ticket_resolution
  # #528: a claim still present here was orphaned by a killed writer, never held by a live one —
  # see append_satisfied. This is where a session starts, so it is where the sweep belongs.
  clear_satisfied_claims
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
  # LAST, and their results are discarded: the attestation above is what `entry` exists to
  # establish, so nothing either of these does may reach this function's exit status.
  cmd_entry_sweep
  # #647, and AFTER the sweep on purpose — a worktree the sweep has just removed is not one to
  # seed. This is where the copy lives because `entry` is the one call every run makes, on every
  # re-entry, from either side of the lane; see seed_lane_worktree_settings for why a worktree
  # that inherits nothing is a session that gambles on the classifier.
  seed_lane_worktree_settings
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
    record_ticket_resolution
    append_line "$(now_iso) | claim | tracker=jira | no tracker write (read-only tracker)"
    say "✓ claim: jira adapter — no tracker write; run_id '$RESOLVED_RUN_ID' recorded in $PROGRESS_FILE"
    return 0
  fi

  ensure_progress_file
  record_ticket_resolution

  helper="$(dirname "$(dirname "$(cd "$(dirname "$0")" && pwd)")")/tools/claim-issue.sh"
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

# THE PR AND NOT THE ISSUE (D-2): the build run's identity has to be readable by a check that knows
# nothing about the tracker, and source control is GitHub for every adapter. lean-evidence.sh
# compares the verdict record's identity against EVERY marker here.
#
# STEP 7, NOT MILESTONE 5 ALONE. A PR comment fires no `pull_request` event, and the last CI run on
# a lean PR is the review session's verdict-record push — so a marker first written at milestone 5
# is invisible to the run that gates the merge and reds every lean PR until someone re-runs the job.
# The checklist calls this at PR-open and cmd_5 calls it again; the second call is a no-op.
#
# IDEMPOTENT BY IDENTITY, not by presence: a marker carrying THIS run's id suppresses the write, a
# marker from a DIFFERENT build session does not (D-4). A second session must leave its own, or its
# identity is invisible at the boundary and it could author its own review.
cmd_mark() {
  local pr prnum comments existing body url rc msid recorded

  if [ "$BOT_ENABLED" != "true" ]; then
    say "· mark: no bot is enabled for this consumer (tracker.bot.enabled is false, or absent under tracker.type 'jira'), so there is no authenticated writer for a PR marker. The boundary's identity arm runs at reduced strength (printed there); every other arm is unaffected. Configuring a bot restores the marker under either tracker."
    return 0
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

  # #446: the ambient session must be a RECORDED build session. It sits AFTER the no-op above
  # (#590) and that is safe, because what it guards is a WRITE: on the path behind the no-op
  # nothing is written, so no foreign identity can reach a marker. Placing it first bought only a
  # zero-network refusal, and that cost is now the close-out's — a gate command with no session
  # identity at all, which must pass when step 7 already stamped the marker.
  #
  # It never records (see record_build_session on why a self-whitelisting guard is vacuous) and it
  # PRINTS the recorded id rather than substituting it: a genuine second build session keeps its
  # own ambient id on its own marker, while the operator's correction becomes "copy the harness's
  # recorded value" instead of "hand-supply an identity string".
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
# #374 AC-8/9/10. A declared `pause-and-ask` Open Region is not the build session's to close —
# refuse before any code is written rather than let it surface as a review blocker hours later
# (#372's OR-2 cost an operator comment AND a round-2 review). `reversible-default-and-flag`
# regions carry their own default and are never refused (AC-9); no `## Open Regions` section is
# unaffected (AC-10).
#
# NETWORK, and deliberately NOT part of cmd_all's cheap pre-pass — the issue and its comment trail
# are read live unless the fixture seams below are set. cmd_1 skips this under LEAN_GATE_OBSERVE=1.
open_regions_section() { # stdin: the issue body — prints the section's lines, nothing else
  awk '
    tolower($0) ~ /^#+[[:space:]]+open regions[[:space:]]*$/ { insec = 1; next }
    insec && /^#+[[:space:]]/                                 { insec = 0 }
    insec                                                     { print }
  '
}

# Table rows `| <id> | ... | pause-and-ask |` inside the section. The header/separator rows never
# match — neither carries the literal disposition token in its last cell.
#
# The disposition is the LAST NON-EMPTY cell, not $(NF-1): GFM does not require the trailing pipe,
# so `| OR-1 | R | pause-and-ask` puts it at $NF, and under $(NF-1) that row scans the Region text,
# matches nothing, and the gate fails OPEN on a table a renderer accepts.
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

# A pause-and-ask region's resolution artifact. THREE of them now:
#
#   1. a committed intent-gap record whose OWN `region:` key names THIS id and whose `ratified:`
#      key reads `yes` — a record ratified for a different region cannot clear this one;
#   2. #613: a committed operator-override record for the `spec-open-region` gate naming this
#      region. Where the intent-gap record routes a decision back to the human OUT OF BAND and
#      waits, this one carries the answer a present operator already gave, quoted verbatim. It is
#      the yield half of affordance-plus-record: the attendance token alone reaches only the
#      affordance this refusal prints, never this acceptance;
#   3. a non-bot issue comment naming the region id (word-bounded, so "OR-1" cannot match inside
#      "OR-10") — the original route, unchanged, and the only one under a tracker whose comments
#      this gate can read but whose files it cannot.
#
# RETURN CODES are check_pause_and_ask's own vocabulary, not a boolean: 0 resolved, 1 not,
# 2 the answer is UNKNOWN. A malformed override record is not "no override" — reading it as one
# would let a record the merge boundary is about to reject wave the region through here.
region_resolved() { # region_resolved <id> <comments-json>
  local id="$1" comments="$2" n gap orc
  gap="$REPO_ROOT/$INTENT_GAP_REL"
  if [ -f "$gap" ] && [ "$(record_key region "$gap")" = "$id" ] && [ "$(record_key ratified "$gap")" = "yes" ]; then
    return 0
  fi
  bash "$OVERRIDE_TOOL" check --gate spec-open-region --issue "$ISSUE" --region "$id" --repo-root "$REPO_ROOT" >/dev/null 2>&1
  orc=$?
  [ "$orc" -eq 1 ] || return "$orc"
  n="$(printf '%s' "$comments" | jq -r --arg pat "(^|[^A-Za-z0-9-])${id}([^A-Za-z0-9-]|\$)" \
    '[ .[] | select((.user.type // "") != "Bot") | select((.body // "") | test($pat)) ] | length' 2>/dev/null)"
  [ "${n:-0}" -ge 1 ]
}

# The affordance, and ONLY the affordance (#613). An attended session gets the exact command that
# would record the operator's answer; it does not get the yield, which is the record itself. A
# forged token therefore buys a longer refusal message and nothing else.
#
# Silent on stderr and defaulting to headless: this decorates a refusal, and a mechanism that
# could not answer must not turn a milestone-1 red into an environment error.
override_affordance() { # override_affordance <region-ids>
  local st rg
  st="$(bash "$OVERRIDE_TOOL" state 2>/dev/null)" || st=""
  [ "$st" = "attended" ] || return 0
  # ONE LINE PER REGION, because authority is scoped per region and a single command clears only
  # the one it names. Printing the first and leaving the operator to infer the rest is how a
  # two-region refusal gets half-resolved and re-runs into the same wall.
  printf '\n  This session is attended, so there is a third route: record the operator'"'"'s own answer and re-run. One command per region, and the answer is quoted VERBATIM — paraphrasing it is the fabrication the record exists to prevent:\n'
  while IFS= read -r rg; do
    [ -n "$rg" ] || continue
    printf '    bash %s record --gate spec-open-region --scope open-region-resolution --issue %s --region %s --decision '"'"'<what the operator decided, one line>'"'"' --answer '"'"'<their answer, verbatim>'"'"'\n' \
      "$OVERRIDE_TOOL" "$ISSUE" "$rg"
  done <<EOF
$(printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
EOF
}

# #533. The OTHER declared source: plan-interview writes pause-and-ask regions into the pre-flight
# ledger, not the issue body. Its `## Open Regions` table is the SAME shape (`pause_and_ask_ids`
# reads either unchanged), so no second parser is needed. `--ledger-file` overrides the
# `{issue}-ledger.md` default, symmetric with `--issue-file`/`--comments-file`, so a selftest can
# drive this leg without writing into $STATE_DIR — shared and mutable across every worktree.
pause_and_ask_ledger_path() {
  if [ -n "$LEDGER_FILE" ]; then
    printf '%s\n' "$LEDGER_FILE"
  else
    printf '%s\n' "$MAIN_ROOT/$STATE_DIR/$ISSUE-ledger.md"
  fi
}

# RETURN-CODE VOCABULARY (#532), shared with `checked_match` in
# plugins/dev-pipeline/tools/checked-call.sh — this is the same defect in its
# capture-shaped costume, so it takes the same numbers:
#
#   0 + empty stdout   CLEAR — every declared source was read and none declares an unresolved
#                      region.
#   0 + a reason       an unresolved region exists. A milestone-1 failure and a fix attempt:
#                      there is something for the operator to go and clear.
#   2 + a reason       a READ ITSELF failed, so the answer is UNKNOWN. Not clear, and not a
#                      failed fix either — no edit the build role can make will fix a tracker
#                      that would not answer. The CALLER turns this into an environment
#                      refusal; cmd_1 says why it cannot be raised from in here.
#
# What changed: these arms already printed a reason, so they already REFUSED — the ticket's
# "milestone 1 passes" premise is wrong about the two gh arms. What they could not do is refuse
# for the right REASON: an unreadable tracker spent one of milestone 1's three fix attempts, and
# three blips hard-stopped the run at rc=4 with a rescue path nobody could act on. The `jq` arm
# below is the one that did fail open.
check_pause_and_ask() { # prints a reason on stdout; the vocabulary above says what rc means
  local body="" ledger_ids="" body_ids="" ids comments="[]" id ledger_path ledger_content

  # ---- source 1: the pre-flight ledger. Read under BOTH trackers — it is the only source at
  # all under jira (AC-3), and a github consumer may carry regions here instead of, or as well
  # as, the issue body (AC-1: a region declared in EITHER source is seen). An ABSENT ledger is
  # not an error — most tickets never went through pre-flight — but an existing, unreadable one
  # is, exactly like an unreadable issue below: "no ledger" and "a ledger this could not read"
  # are different facts, and neither may silently report CLEAR (AC-4).
  ledger_path="$(pause_and_ask_ledger_path)"
  [ -z "$LEDGER_FILE" ] || [ -f "$LEDGER_FILE" ] || envfail "--ledger-file '$LEDGER_FILE' does not exist."
  if [ -f "$ledger_path" ]; then
    ledger_content="$(cat "$ledger_path" 2>&1)" \
      || { echo "could not read pre-flight ledger $ledger_path while checking for an unresolved pause-and-ask region"; return 2; }
    ledger_ids="$(printf '%s' "$ledger_content" | pause_and_ask_ids)"
  fi

  # ---- source 2: the issue body. github only — there is no gh issue to read under jira.
  if [ "$TRACKER_TYPE" != "jira" ]; then
    if [ -n "$ISSUE_FILE" ]; then
      [ -f "$ISSUE_FILE" ] || envfail "--issue-file '$ISSUE_FILE' does not exist."
      # A malformed fixture landed here as an EMPTY body with its stderr discarded: no region ids
      # to enumerate, so the function returned CLEAR. Existing but unparseable is not "declares no
      # region" — it is the same "could not read" the two gh arms report.
      body="$(jq -r '.body // ""' "$ISSUE_FILE" 2>/dev/null)" \
        || { echo "could not parse --issue-file '$ISSUE_FILE' while checking for an unresolved pause-and-ask region"; return 2; }
    else
      body="$("$GH_CLI" issue view "$ISSUE" --json body --jq .body 2>&1)" \
        || { echo "could not read issue #$ISSUE to check for an unresolved pause-and-ask region: $body"; return 2; }
    fi
    body_ids="$(printf '%s' "$body" | pause_and_ask_ids)"
  fi

  ids="$(printf '%s\n%s\n' "$ledger_ids" "$body_ids" | awk 'NF' | sort -u)"
  [ -n "$ids" ] || return 0

  if [ "$TRACKER_TYPE" != "jira" ]; then
    if [ -n "$COMMENTS_FILE" ]; then
      [ -f "$COMMENTS_FILE" ] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
      comments="$(cat "$COMMENTS_FILE")"
    else
      comments="$("$GH_CLI" api "repos/{owner}/{repo}/issues/$ISSUE/comments" --paginate 2>&1)" \
        || { echo "could not read #$ISSUE's comment trail to check for an unresolved pause-and-ask region: $comments"; return 2; }
    fi
  fi
  # Under jira `comments` stays "[]" — no comment trail this check reads, so only a ratified
  # intent-gap record (tracker-agnostic) can resolve a region there.

  # Every unresolved region, not just the first — the same ergonomic the `all` pre-pass owes
  # (AC-3): an operator clearing two regions must not pay two round-trips to discover the
  # second. The label stays singular for one so the refusal reads as prose either way.
  local unresolved="" label="region" rrc
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    region_resolved "$id" "$comments"; rrc=$?
    case "$rrc" in
      0) : ;;
      1) unresolved="${unresolved:+$unresolved, }$id" ;;
      # #613. The override record exists and could not be read as a clean answer. Same rc-2 arm
      # the two gh reads take, and for the same reason: no edit to the spec fixes it, so it must
      # not spend a fix attempt.
      *) echo "region $id's operator-override record could not be read as a clean answer (override check exit $rrc; 127 means the mechanism is missing from this install rather than a record being malformed) — that is not the same fact as 'no override', and is not treated as one. Fix or remove the record (bash $OVERRIDE_TOOL lint --record …), then re-run."; return 2 ;;
    esac
  done <<< "$ids"
  [ -n "$unresolved" ] || return 0
  case "$unresolved" in *,*) label="regions" ;; esac
  # The sentence below is UNCHANGED, byte for byte: a headless run — which is every scheduler
  # payload, this gate's normal case — must read exactly what it read before. The affordance is
  # APPENDED, and only when a token resolves.
  echo "$label $unresolved dispositioned pause-and-ask with no resolution artifact — neither a non-bot comment naming each nor a ratified intent-gap record ($INTENT_GAP_REL) exists. Resolve with an operator comment, or a ratified intent-gap record, before continuing.$(override_affordance "$unresolved")"
}

# ---------------------------------------------------------------- the design axis: arming
# LOCKSTEP, canonical side (#394). `design_armed` is held verbatim by scripts/check-lean-chain.sh,
# which gates the merge on it. The coupling is unusually sharp because the two readers have
# DIFFERENT INPUTS and must still agree: this gate ANDs the predicate against config
# `design.provider`, the boundary cannot (the config never reaches a CI checkout) and so runs it
# alone. Divergence is invisible from either side — a boundary reading arming more narrowly waves
# an armed PR through with no render evidence, one reading it more widely reds honest unarmed
# work, and in both cases the OTHER site stays green and says so. Only the NARROW decision is
# shared: the richer form validation below (handoff link, the neither-armed-nor-disarmed refusal,
# the reason required on a disarm) is authoring feedback given at milestone 1, so a spec failing
# it never reaches a merge and the boundary needs no opinion about it.
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

# ---- the armed fidelity EVIDENCE table (#693) ------------------------------------------------
# An armed `fidelity: pass` used to be one word the reviewing model wrote about its own work.
# Milestone 4's armed arm asks three mechanical questions — a receipt exists, this branch's render
# patch identity is computable, the receipt's `rendered_from` equals it — and one unfalsifiable
# one: does the header read `pass`. Nothing anywhere compared anything to the design, so the arm
# was fully satisfied by a receipt of the WRONG SCREEN, correctly hashed, with `pass` typed above
# it. Observed: the sighted arm returned `pass` twice against a screen whose controls were ~2.2x
# the design's width and carried an affordance the frames do not contain, with every mechanical
# check passing correctly throughout.
#
# What this buys is TAMPER-EVIDENCE, not fidelity. It verifies nothing against the design — no
# gate in this repo does, and `design-faithful/SKILL.md` says so ("no pixel-diff tool in-repo —
# do not invent"). It converts an unfalsifiable header into one a human can falsify by reading
# the record, and raises the cost of a rubber stamp from typing a word to fabricating node
# references, paired numbers, and a citation that resolves in a patch-bound spec.
#
# A TABLE and not prose, because the record body is handed to prettier
# (`lean_format_verdict_record`) and `proseWrap: "always"` reflows sentences — a predicate over
# reflowed prose is fragile, and every other artifact this gate parses is already a table.
FIDELITY_EVIDENCE_HEADING="Design fidelity evidence"
FIDELITY_EVIDENCE_COLUMNS="RS-n|frame node|property|design|rendered|verdict"

# The evidence section's violations, one human-readable line each; EMPTY output is a conforming
# section. Scoped, heading-tolerant and trim-then-non-empty exactly as `design_rs_rows()` above
# is, and for reasons rather than symmetry: a whole-body scan would read the SPEC's own 4-column
# `| RS-1 | route | state | AC refs |` table as a malformed evidence row, and a literal `## `-only
# heading match could not tell a reviewer who nested the section from one who omitted it.
#
# The heading regex is BUILT from $FIDELITY_EVIDENCE_HEADING rather than spelled twice — the
# refusal message and the reader must name the same section or the message sends a reviewer to
# write a heading the reader will not find.
#
# THE HEADER ROW IS THE LINE IMMEDIATELY ABOVE THE `| --- |` SEPARATOR, and nothing else works:
# the data-row anchor (`RS-[0-9]+`) cannot find it, and "first pipe-leading line in the section"
# breaks on prose containing a `|`. The separator rule is also what stops a header whose first
# cell was substituted to `RS-1` from being counted as a data row.
#
# Columns are enforced BY NAME and EXACTLY SIX, never "at least six": a superset puts "any empty
# cell" and "all six non-empty" in direct conflict on a 7-column table whose 7th cell is empty,
# and cell-count-only checking would leave the empty-column refusal with no column name to report.
fidelity_evidence_violations() { # fidelity_evidence_violations <declared-ids> <known-refs>  (body on stdin)
  awk -v declared="$1" -v refs="$2" -v cols="$FIDELITY_EVIDENCE_COLUMNS" -v heading="$FIDELITY_EVIDENCE_HEADING" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    # A markdown separator: pipes, dashes, colons and space, with at least one dash. Never an
    # interval expression — `#{1,6}`-style intervals are not portable across the awks this ships
    # on, which is the same reason the heading rules above spell `#+[[:space:]]`.
    function issep(s) { return (s ~ /^[[:space:]]*\|[[:space:]:|-]*$/ && s ~ /-/) }
    # The cells of a leading-pipe markdown row, trimmed. Field 1 is the empty run before that
    # leading pipe, so it is dropped by construction — the same reason design_rs_rows() reads
    # its id out of $2 rather than $1 — and a TRAILING pipe contributes one empty field that is
    # punctuation, not a cell.
    function rowcells(s, a,   n, i, k, hi) {
      delete a
      n = split(s, RCF, "|")
      hi = n
      if (s ~ /\|[[:space:]]*$/) hi = n - 1
      k = 0
      for (i = 2; i <= hi; i++) a[++k] = trim(RCF[i])
      return k
    }
    BEGIN {
      hre = "^#+[[:space:]]+" tolower(heading) "[[:space:]]*$"
      ncol = split(cols, want, "|")
      n = split(declared, d, " ")
      for (i = 1; i <= n; i++) if (d[i] != "" && !(d[i] in decl)) { decl[d[i]] = 1; declorder[++ndecl] = d[i] }
      n = split(refs, r, " ")
      for (i = 1; i <= n; i++) if (r[i] != "") known[r[i]] = 1
    }
    tolower($0) ~ hre        { insec = 1; found = 1; next }
    insec && /^#+[[:space:]]/ { insec = 0 }
    insec                     { sec[++nl] = $0 }
    END {
      if (!found) { print "no \"## " heading "\" section in the review summary"; exit }

      sepi = 0
      for (i = 1; i <= nl; i++) if (issep(sec[i])) { sepi = i; break }
      if (sepi >= 2) {
        nh = rowcells(sec[sepi - 1], H)
        hdrok = (nh == ncol)
        for (i = 1; hdrok && i <= ncol; i++) if (tolower(H[i]) != tolower(want[i])) hdrok = 0
        if (!hdrok) {
          got = ""
          for (i = 1; i <= nh; i++) got = got (i > 1 ? " | " : "") H[i]
          print "the header row must name exactly " ncol " columns, in order: " cols " — found: " (nh ? got : "<no cells>")
        }
      } else if (sepi == 1) {
        print "the \"| --- |\" separator is the first line of the section, so no header row sits above it"
      } else {
        print "no \"| --- |\" separator row, so the header row cannot be located — the header is the line immediately above the separator"
      }

      nrows = 0
      for (i = 1; i <= nl; i++) {
        if (sepi >= 2 && i == sepi - 1) continue          # the header row is not a data row
        if (sec[i] !~ /^[[:space:]]*\|[[:space:]]*RS-[0-9]+[[:space:]]*\|/) continue
        nrows++
        nc = rowcells(sec[i], C)
        id = C[1]
        seen[id] = 1
        if (nc > ncol) { print "row " nrows " (" id "): " nc " cells, expected exactly " ncol; continue }
        bad = 0
        for (j = 1; j <= ncol; j++) if (j > nc || C[j] == "") { print "row " nrows " (" id "): column \"" want[j] "\" is empty"; bad = 1 }
        if (bad) continue
        if (!(id in decl)) { print "row " nrows " scores " id ", which the spec does not declare"; continue }
        # The disposition token is a PREFIX of the cell, because `deviation` carries a payload
        # after it. Anchored on a non-word boundary so `deviation (AC-3)` and `deviation(AC-3)`
        # both read while `deviations` does not — ledger-lint.sh reads the Surface Inventory
        # disposition with this same idiom, and for the same reason.
        v = C[ncol]
        if (v ~ /^match([^A-Za-z0-9-]|$)/) continue
        if (v ~ /^deviation([^A-Za-z0-9-]|$)/) {
          ref = ""
          if (match(v, /(AC|D)-[0-9]+/)) ref = substr(v, RSTART, RLENGTH)
          if (ref == "")           print "row " nrows " (" id "): verdict \"" v "\" claims a deviation without naming the AC-n or D-n that decides it"
          else if (!(ref in known)) print "row " nrows " (" id "): verdict cites " ref ", which the spec does not declare"
          continue
        }
        print "row " nrows " (" id "): verdict \"" v "\" is neither \"match\" nor \"deviation (<AC-n|D-n>)\""
      }

      if (nrows == 0) { print "the \"## " heading "\" section carries no data row — a heading and a header row evidence nothing"; exit }
      for (i = 1; i <= ndecl; i++) if (!(declorder[i] in seen)) print "no row for " declorder[i] ", which the spec declares"
    }
  '
}

# The GATE's arming resolution (D-8). Prints exactly one of `unarmed`, `disarmed`, `armed`, or
# `error:<message>` — an error being an authoring defect the session can fix, never an environment
# problem. `unarmed` short-circuits on the config: with no `design.provider` a `## Design` section
# is documentation and arms nothing. That is D-8's AND half — under OR, every consumer that ever
# wrote the heading would be required to own a render harness.
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

# The STATE LOCK behind D-8's mid-run-disarm refusal. Its line shape does NOT contain the
# `| milestone-3 | attempt |` substring attempt_count() greps, so arming — which happens on every
# armed evaluation — never consumes fix budget. It is a record of a decision, not a counter.
#
# Read its STRENGTH correctly: PROGRESS_FILE is uncommitted and machine-local, so the row binds
# inside the worktree that armed the lane and a resume elsewhere accepts the disarm. That matches
# this script's trust posture — a local record is tamper-evidence, never integrity — and the
# residual sits at review. Do not inherit this as "cannot be escaped".
design_was_armed() {
  [ "$(count_matches "| milestone-3 | armed |" "$PROGRESS_FILE" -F)" -ge 1 ]
}

# The refusal both milestone 1 and milestone 3 raise on a mid-run disarm. One phrasing, two
# sites: the milestone that notices first should not read differently from the other.
design_disarm_locked_msg() {
  printf 'spec %s now disarms the design lane ("Design: none"), but this run already armed it — the progress file carries a "| milestone-3 | armed |" record. Disarming mid-run retires the render evidence a review round would be scored against, so it is refused: restore the "## Design" render-state table, or abandon the run and re-file the ticket with the disarm in its spec from the start.' "$SPEC_REL"
}

# #562: resolves intake-toolkit's ledger-lint.sh across both layouts this script runs from,
# reusing resolve_sibling() (#419) rather than re-deriving a second copy of its ladder — a
# review-round finding on this ticket (a byte-identical copy is exactly the duplicate machinery
# this repo's manifest calls worse than none). resolve-sibling.sh's header explains the split:
# the ladder is shared, and each caller keeps its own hop count from its file to its plugin
# root, computed the same way pipeline-doctor.sh computes PLUGIN_DIR/PLUGINS_DIR for itself.
# This file sits two directories under its plugin root (skills/build-lean), where
# pipeline-doctor.sh sits one (tools) — the differing depth pipeline-doctor.sh's own D-4
# argued from is real, but it bears only on the three lines below, not on the ladder itself.
# Those globals are exactly what the ladder reads: PLUGIN_DIR (rung 2 — this plugin's own
# version in the cache is that directory's basename) and PLUGINS_DIR (rungs 1 and 3). Both are
# hop-adjusted HERE and nothing downstream re-derives a depth, which is what makes the shared
# ladder depth-agnostic rather than merely claimed to be (#562 r2). pipeline-doctor-selftest.sh
# lifts the block below by its sentinels and runs it at this real depth.
# shellcheck source=../../tools/resolve-sibling.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/resolve-sibling.sh"
# >>> ledger-lint-resolver
resolve_ledger_lint() {
  local SCRIPT_DIR PLUGIN_DIR PLUGINS_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
  # shellcheck disable=SC2034  # PLUGIN_DIR and PLUGINS_DIR are read by resolve_sibling() via dynamic scope (resolve-sibling.sh, sourced above)
  PLUGIN_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
  # shellcheck disable=SC2034
  PLUGINS_DIR="$(dirname "$PLUGIN_DIR")"
  resolve_sibling intake-toolkit skills/plan-interview/tools/ledger-lint.sh
}
# <<< ledger-lint-resolver

# ---------------------------------------------------------------- milestone 1: spec/AC
# AC-3, as resolved at intake (G-1): existence AT THE PINNED PATH plus >= 1 numbered AC-n,
# and NO further content assertion. The path predicate is not an extra check — it is which
# file "exists" means, and check-lean-chain.sh keys its artifact scan off the same shape.
cmd_1() {
  local spec="$REPO_ROOT/$SPEC_REL" n reason pa_rc dstate note="" lint="" lint_out lint_rc
  local receipt rec_out rec_rc
  # #494: ABSENCE, not a failed fix — block_milestone, whose line kind attempt_count() cannot
  # see. This is the call SKILL.md step 3 orders before the spec can exist.
  [ -f "$spec" ] || { block_milestone 1 "no committed spec at $SPEC_REL"; return $?; }
  n="$(count_matches '(^|[^A-Za-z])AC-[0-9]+' "$spec" -E)"
  [ "$n" -ge 1 ] || { fail_milestone 1 "spec $SPEC_REL carries no numbered AC-n criterion"; return $?; }

  # #562: a committed Decision Ledger's provenance is validated, reusing ledger-lint.sh rather
  # than re-implementing its enum — a second copy would be exactly the duplicate machinery this
  # repo's manifest calls worse than none (interviewing-baseline is the canonical source).
  # Conditional on the section being PRESENT: whether a lean spec carries one at all is #517's
  # row-presence question, not this one's provenance-validity question, so an AC-n-only spec with
  # no Decision Ledger section is unaffected, exactly as it is today.
  if grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*decision ledger' "$spec"; then
    lint="$(resolve_ledger_lint)" \
      || envfail "milestone-1: intake-toolkit's ledger-lint.sh could not be resolved (checked the monorepo layout and the install cache under both plugins) — cannot validate $SPEC_REL's Decision Ledger. Fix the install."
    lint_out="$(bash "$lint" "$spec" 2>&1)"; lint_rc=$?
    if [ "$lint_rc" -ne 0 ]; then
      fail_milestone 1 "spec $SPEC_REL's Decision Ledger fails ledger-lint: $lint_out"; return $?
    fi
  fi

  # #517: the pre-flight receipt is BINDING INPUT (SKILL.md step 4), and this is the one place both
  # documents are in reach at once. The review session reads the COMMITTED spec, by which point a
  # dropped receipt row has left no trace to notice its absence against and a silently re-decided
  # row reads as an ordinary choice.
  #
  # Necessarily LOCAL: $STATE_DIR is gitignored on every consumer, so CI cannot read the receipt.
  # Same seam as the #562 lint above — the provenance enum stays single-sited in ledger-lint.sh
  # rather than gaining a third parser here.
  receipt="$(pause_and_ask_ledger_path)"
  if [ -f "$receipt" ]; then
    [ -n "$lint" ] || lint="$(resolve_ledger_lint)" \
      || envfail "milestone-1: intake-toolkit's ledger-lint.sh could not be resolved (checked the monorepo layout and the install cache under both plugins) — cannot reconcile $SPEC_REL against the pre-flight ledger. Fix the install."
    rec_out="$(bash "$lint" --reconcile "$receipt" "$spec" 2>&1)"; rec_rc=$?
    case "$rec_rc" in
      0) note="$note, ${rec_out#ledger-lint: reconcile: }" ;;
      # A fix the build role can make — edit the committed spec — so it spends a fix attempt,
      # exactly as #562's provenance lint does two blocks up.
      1) fail_milestone 1 "spec $SPEC_REL does not reconcile with the pre-flight ledger $receipt: $rec_out"; return $? ;;
      # Anything else is a READ that failed. "No ledger" and "a ledger this could not read" are
      # different facts and neither may report CLEAR — but the second is not a failed fix either,
      # so it never charges the budget. Same fact #533's check_pause_and_ask reports below, worded
      # so because this block reaches an unreadable ledger FIRST: it runs in the observe pass while
      # that check sits under the guard.
      *) envfail "milestone-1: could not read pre-flight ledger $receipt while reconciling it against $SPEC_REL (ledger-lint exit $rec_rc): $rec_out" ;;
    esac
  fi

  # #394 D-8. Grep-shaped like the AC-n assertion above and evaluated in the observe pass with
  # it: both read the committed spec and the config, nothing else — no network, no subprocess
  # beyond grep/awk — so an armed run learns about a malformed `## Design` section before it
  # pays for milestone 3, exactly as it already learns about a missing AC-n.
  dstate="$(design_state "$spec")"
  case "$dstate" in
    error:*)  fail_milestone 1 "${dstate#error:}"; return $? ;;
    disarmed)
      design_was_armed && { fail_milestone 1 "$(design_disarm_locked_msg)"; return $?; }
      # APPEND, never assign. Since #517 this is no longer the first writer of `note` — the
      # receipt reconciliation above puts its counts there — so an assignment here silently
      # drops that disclosure on exactly the runs that also have a design lane. Invisible to
      # this repo, which configures no provider and so never reaches either arm.
      note="$note, design lane disarmed for this ticket" ;;
    armed)    note="$note, design lane ARMED" ;;
  esac

  if [ "${LEAN_GATE_OBSERVE:-0}" != "1" ]; then
    reason="$(check_pause_and_ask)"; pa_rc=$?
    # #532. rc 2 = the read failed, so the answer is UNKNOWN — an environment error, never a
    # fix attempt. Raised HERE and not inside the function: `envfail` exits, and an exit inside
    # the `$(…)` above kills only the subshell, which would leave `reason` empty and PASS the
    # milestone — failing open in the very act of fixing a fail-open. Same reasoning the
    # capability-stamp resolver above spells out for its own globals.
    [ "$pa_rc" -ne 2 ] || envfail "milestone-1: $reason"
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
# D-17: the config commands table DIRECTLY — and deliberately NO inert-diff
# lane. In a repo whose diffs are mostly shell and markdown, the inert lane would skip the
# suite on exactly the changes that need it most.
#
# SEAM-SCRUBBED (#379/AC-9). Every lane child spawned below — lanes[] setup, the fixed
# lint/typecheck/test keys, and extraLanes — is itself second-shift tooling reach on this
# repo (dogfooding), so it must not inherit the gate's own pipeline-seam env: an ambient
# SECOND_SHIFT_CONFIG/STATECTL_STATE_DIR silently re-roots or re-states it, the same class
# #34 found in the previous verify runner, which held this denylist until #348. This file is
# now the SUBSET side of the `seam-scrub` group, with preflight.sh declared its `superset`
# (it also scrubs PREFLIGHT_DOCTOR_CMD) — lean-gate needs nothing narrower or wider. `eval "$cmd"`
# becomes `env <scrub> bash -c "$cmd"`: functionally identical for a shell command string
# (preflight.sh runs this repo's own configured lane commands the same way), and the only
# shape `env` can scrub ahead of.
# LOCKSTEP-BEGIN seam-scrub subset
SEAM_SCRUB='SECOND_SHIFT_CONFIG|SECOND_SHIFT_REPO_ROOT|SECOND_SHIFT_EXTENSION_MANIFEST|SECOND_SHIFT_PLUGIN_ROOT|SECOND_SHIFT_REVIEW_TOOLKIT_ROOT|SECOND_SHIFT_DEV_PIPELINE_ROOT|SECOND_SHIFT_DESIGN_TOOLKIT_ROOT|SECOND_SHIFT_SECTION_CATALOG|STATECTL_STATE_DIR|STATECTL_WRITER|DEV_PIPELINE_MODE|BRANCH_PREFIX|KEY_PATTERN|LEAN_ATTEND_MODE'
# LOCKSTEP-END seam-scrub
declare -a SEAM_SCRUB_ENV=()
IFS='|' read -r -a _seam_scrub_toks <<< "$SEAM_SCRUB"
for _seam_tok in "${_seam_scrub_toks[@]}"; do
  SEAM_SCRUB_ENV+=(-u "$_seam_tok")
done
unset _seam_tok _seam_scrub_toks

# extraLanes `when` glob match — bash pattern matching (NOT globstar, NOT git pathspec),
# the dialect this gate inherited (AC-4): `*`
# crosses `/`, so `**` buys nothing extra and a bare directory literal never matches a file
# beneath it. #348 left this file the sole carrier, so the selftest is the only thing holding
# the dialect — which is why this is its own function, pinnable directly rather than through
# cmd_3's plumbing.
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

# Substitution is into a SHELL COMMAND STRING, so every value is single-quoted on the way in.
# `{state}` is why that is not optional: a render state is human prose ("filters expanded"), so the
# raw form splices two words where the harness expects one argument — observed, rendering the wrong
# view while passing every other assertion here. `{out}`/`{route}` get the same treatment.
#
# THE CONTRACT: the placeholders appear UNQUOTED in the template. `--state {state}` is correct;
# `--state "{state}"` nests this quoting inside the consumer's.
shquote() { # shquote <value>
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Substitution walks the template rather than using `${t//p/r}`, and that is not a style choice.
# Since bash 5.2 `patsub_replacement` is ON by default, so a bare ampersand in the REPLACEMENT
# expands to whatever the pattern just matched: `prospects?tab=new&sort=asc` reaches the harness as
# `prospects?tab=new{route}sort=asc`. shquote() cannot reach this — it quotes one layer below.
# The failure is SILENT: the harness exits 0, the screenshot is non-empty, two rows hash
# differently because they were shot at two different WRONG views, and the manifest records the
# DECLARED route and state, so the receipt is honest about intent while the pixels are not.
# Escaping is no fix (`\&` differs between 3.2 and 5.2+); splitting on the placeholder has no
# replacement layer at all. macOS system bash never showed this; every ubuntu runner does.
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
# version this gate pins as its own fallback.
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
# invocation path, or nothing — which every caller must treat as "skip the format step", never as
# a failure: an absent formatter is a consumer fact, not a run defect.
#
# TWO rungs, and the omission of a third is the design: an `npx --yes prettier@x` rung would make
# a gate call reach the network. `commands.<repo>.format` cannot supply this either — in at least
# one consumer it is bound to the CHECK variant (`yarn format:check`). No new config key: this
# resolver needs no consumer onboarding.
lean_resolve_prettier() {
  local wt="$REPO_ROOT" mr="$MAIN_ROOT"
  # SINGLE-SITED: the header above says it — nothing outside this file holds these rungs now.
  # The markers outlived their counterpart and were removed in #604; a marker with no second
  # site reads as a pair and is not one.
  if [[ -x "$wt/node_modules/.bin/prettier" ]]; then
    printf '%s\n' "$wt/node_modules/.bin/prettier"
    return 0
  fi
  if [[ -x "$mr/node_modules/.bin/prettier" ]]; then
    printf '%s\n' "$mr/node_modules/.bin/prettier"
    return 0
  fi
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

# #527 D-1. The verify-lane exit code, classified. ONE resolver rather than a test at each call
# site: the reserved code must mean the same thing wherever a lane runs.
#
# NOT A PER-LANE CONFIG DECLARATION. A `failureClass`-style opt-in would put the answer in the
# config of the repo whose lane just said it could not answer, and every consumer would have to
# discover the key before the class did anything.
#
# SCOPED TO VERIFY LANES, and since #642 to `typecheck` alone — `lint`, `test` and extraLanes are
# advisory, so they never reach a class at all. Setup `lanes[]` were always infra by construction.
lane_failure_class() { # lane_failure_class <lane-rc> — the class fail_milestone should return
  case "$1" in
    "$LANE_INFRA_RC") echo "$INFRA_CLASS" ;;
    *)                echo 1 ;;
  esac
}

# #642. A red on a DEMOTED milestone-3 lane. It records — on the `advisory` verb milestone 2's
# frozen-files notice already established, which no counter in this file greps — and returns 0, so
# the milestone continues to the lanes after it and concludes on its own merits. The lane's own
# output has already gone to the terminal; this is the durable half, and it is what a reviewer and
# the retro corpus read.
# #668. The count milestone 3's terminal line states. The two warn lines below scroll past and the
# progress row is durable but nothing reads it live, so the ONE line an operator or the scheduler
# reads was asserting an unqualified green over lanes that had just reported red. Counted here
# rather than recomputed from the progress file at the end: the file accumulates across a run's fix
# rounds, and what the terminal line qualifies is THIS invocation.
LANE_ADVISORY_COUNT=0

lane_advisory() { # lane_advisory <reason>
  LANE_ADVISORY_COUNT=$(( LANE_ADVISORY_COUNT + 1 ))
  append_line "$(now_iso) | milestone-3 | advisory | $1 — reported, not blocking: the merge boundary re-runs this lane"
  warn "milestone-3: $1"
  warn "  ADVISORY (#642), not a refusal — this lane is re-run at the merge boundary, so it reports here and blocks there. Nothing was charged to the fix budget."
}

cmd_3() {
  local cmd rc any_verifying=0
  # Defensive only, not guarding a live path: `all` runs each milestone once per process, so
  # nothing calls cmd_3 twice today, and the file-scope initialiser above already zeroes this.
  # Kept so a future second in-process caller cannot inherit a stale count.
  LANE_ADVISORY_COUNT=0
  # #563. BEFORE the first lane child of any kind, since the whole point is that every one of
  # them inherits the cache store this appends to SEAM_SCRUB_ENV — the setup lanes below, the
  # fixed keys, extraLanes, and the render pre-command cmd_3_render runs at the end. It stood
  # beside #526's lane job ceiling here until #566 deleted that, so it is now the only ASSIGNMENT
  # appended to SEAM_SCRUB_ENV — every other entry there is a `-u` scrub.
  lane_apply_selftest_cache
  # lanes[] setup steps first, when present. Shape is {name, cwd?, commands[]} — the SAME
  # reader the previous runner used (its step 1), including the non-object backstop (#100): a lane
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
    [ "$rc" -eq 0 ] && continue
    # #642: `lint` and `test` REPORT, they do not refuse — the merge boundary re-runs both
    # (`lint-and-selftests`), so refusing here buys WHEN a failure is caught, not whether, and
    # spends a fix round to buy it. `typecheck` is NOT demoted: the demotion's premise is
    # measured CI duplication and typecheck has none measured.
    case "$key" in
      typecheck) fail_milestone 3 "$key failed (rc=$rc)" "$(lane_failure_class "$rc")"; return $? ;;
      *) lane_advisory "$key failed (rc=$rc)" ;;
    esac
  done

  # ---- extraLanes (EP-2) ---------------------------------------------------------
  # Additive verify lanes: the schema's slot for everything config-lint forces out of the
  # fixed keys (build lanes, path-scoped suites, a design-driven live-render lane). Run
  # sequentially AFTER the fixed keys and BEFORE the design live-render (AC-6), in declaration
  # order, fail-fast — the same placement the previous runner gave them. (#580 deleted the
  # mutation sweep this clause used to name as the following lane; the ordering it fixes —
  # fixed keys first, then these — is unchanged.)
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
  # diff). Setup `lanes[]` are INFRA-classed and so do not count, matching the staged lane's
  # `allowUnverified` valve, which is inert as soon as any verifying lane is configured (#98).
  # Checked here, before extraLanes execute, so a red never pays for lane runs it was always
  # going to discard. (Until #580 this also sat before a repo-carried mutation sweep, which was
  # the expensive thing it was chiefly protecting against; that lane is gone.)
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
      # the previous runner had grown this same guard for (#100).
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
        # #642, and the same demotion the fixed keys above take. The `break` is what changes with
        # it: fail-fast used to be the refusal's job, and a lane's later commands are still
        # meaningless once an earlier one red, so the lane stops and the NEXT lane runs.
        [ "$rc" -eq 0 ] || { lane_advisory "extra lane '$el_name' failed (rc=$rc): $el_cmd"; break; }
      done
    done
  fi

  # ---- design live-render (#394) -------------------------------------------------
  # LAST in milestone 3, after extraLanes, on the same rule: cheap deterministic lanes first, then
  # the expensive ones. A no-op on every unarmed run.
  #
  # #580 retired a repo-carried `tools/mutation-sweep.sh --mode pr` run from this slot: it made the
  # IDENTICAL invocation the `mutation-sweep-pr` CI job already makes. Do not re-add it — the
  # duplication is the whole reason it went, and #642 applied the same reading to `lint`/`test`.
  cmd_3_render; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"

  # #668. Qualify the green with what reported red beside it. Zero advisories leaves the text
  # byte-identical to what every existing consumer already reads.
  local adv_note=""
  if [ "$LANE_ADVISORY_COUNT" -gt 0 ]; then adv_note=" ($LANE_ADVISORY_COUNT advisory)"; fi
  pass_milestone 3 "green gate$adv_note"
}

# ---------------------------------------------------------------- milestone 4: review
# D-22/D-46: the COMMITTED verdict record is the record of record. The progress-file line is a
# local counter only — the merge boundary re-asserts the committed record, so a hand-typed local
# line cannot reach a merge.
#
# READ-ONLY BY CONSTRUCTION. This milestone never writes to the verdict record — not to create it,
# not to stamp it, not to "normalize" it. The moment it can, the P10 separation is decorative. The
# suite asserts the file is byte- and mtime-identical across a full `all` sweep.
cmd_4() {
  local rec="$REPO_ROOT/$VERDICT_REL" v_val v_run v_sess b_prog_run b_prog_sess b_cached cand
  local v_commit v_short stale n_stale v_head v_pid cur_pid v_fresh
  local v_inh v_chain v_coverage
  # The handoff moment, and so the one place the P9 reminder is contextual rather than noise.
  # It lives here rather than as another SKILL.md line for the reason the cap exists: stderr is
  # read exactly when it applies, prose is read on every run. NO DETECTION happens here — the
  # refusal is the merge boundary's alone (check-lean-chain.sh evidence 6), and a second in-run
  # copy would be the duplicate machinery D-47 rules out, not defense in depth.
  [ -f "$rec" ] || { block_milestone 4 "no committed verdict record at $VERDICT_REL — hand off to '/dev-pipeline:review-lean <pr>'. If this run wrote an intent-gap record, ratify it before that handoff: the merge boundary refuses one still reading 'ratified: no'." 5; return $?; }
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

  # THE ESCAPE HATCH (#597, D-3). The file list this arm reads is the one a BASE MERGE moves most:
  # `git diff <verdict-commit> HEAD` counts every file the merge brought in, so on #583 it saw 23
  # files and redded before the patch-id arm below was ever reached. A fix confined to patch-id
  # would have satisfied nothing. The question the arm MEANS to ask — did the reviewed content move
  # — is asked of `contribution_state` when it reds, and only its answer decides.
  stale="$(git -C "$REPO_ROOT" diff --name-only "$v_commit" HEAD 2>/dev/null | grep -vxF "$VERDICT_REL")"
  if [ -n "$stale" ]; then
    v_short="$(git -C "$REPO_ROOT" rev-parse --short "$v_commit" 2>/dev/null)"
    n_stale="$(printf '%s\n' "$stale" | wc -l | tr -d ' ')"
    contribution_state "$v_head" HEAD
    case "$CONTRIB_RC" in
      1) fail_milestone 4 "verdict record $VERDICT_REL approves $v_short, but the branch's own diff has moved since: $(printf '%s\n' "$CONTRIB_DETAIL" | contribution_summary) — a verdict does not cover code it never saw. Get a new review round on the current head: '/dev-pipeline:review-lean <pr>'." 5
         return $? ;;
      0) say "milestone-4: $n_stale file(s) differ between $v_short and this head, but every one of the branch's own +/- lines is unchanged since reviewed_head $(printf '%.12s' "$v_head") — a base advance alone is enough to move that file list, and it altered no reviewed line, so the verdict stands (#597 AC-1)." ;;
      *) say "milestone-4: $n_stale file(s) differ between $v_short and this head and the +/- comparison could NOT be computed (unresolvable merge-base, a reviewed_head absent from this checkout, or an empty measured range). FAILING OPEN — the verdict stands, per the operator constraint that invalidation requires certainty (#597 D-5/OR-1). This is the one unreadable-input path in this gate that does not fail closed; reverse it by treating rc=2 as an invalidation here and at the merge boundary." ;;
    esac
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
  # What patch identity deliberately does NOT cover: a base change that reds the suite with no
  # textual conflict. The branch's patch is unchanged there, so the verdict correctly still
  # stands, and the merged result failing is CI's business.
  #
  # #642 DELETED THE SHA-KEYED FALLBACK that used to sit below this arm for records carrying no
  # `reviewed_patch_id` — two decision points, `m4/head-missing` and `m4/head-tree-diff`, neither
  # of which had ever fired. They were not merely quiet: cmd_verdict, the only writer, emits the
  # key unconditionally and `envfail`s rather than omit it, so a record without it predates the
  # key — and lean-evidence.sh, which `pr-gates` runs on every consumer's PR, refuses exactly
  # that record class ("declares no reviewed_patch_id"). Whatever those arms answered, the
  # boundary refused the PR. What replaces them is stricter, not looser: absence is refused here
  # too, in the same words and the same class as the record's other missing keys.
  v_pid="$(record_key reviewed_patch_id "$rec")"
  if [ -z "$v_pid" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL carries no reviewed_patch_id key, so nothing states which tree the review actually read — and the merge boundary refuses that record class outright. Re-run the review round on a dev-pipeline that writes it: '/dev-pipeline:review-lean <pr>'." 5
    return $?
  fi
  cur_pid="$(branch_patch_id HEAD)"
  if [ -z "$cur_pid" ]; then
    fail_milestone 4 "cannot compute this branch's patch identity against origin/$BASE_BRANCH, so there is nothing to compare $VERDICT_REL's reviewed_patch_id against — and a freshness check that cannot run must not report a pass. Fetch origin/$BASE_BRANCH and re-run." 2
    return $?
  fi
  v_fresh="covering the current head (patch-id $(printf '%.12s' "$v_pid"))"
  # THE SAME ESCAPE HATCH (#597, D-3), asked through the SAME call site as the inferred arm above
  # so the two cannot answer differently. `branch_patch_id`'s input INCLUDES the merge-base, so
  # merging the base in moves the id even when the branch alters not one line.
  if [ "$v_pid" != "$cur_pid" ]; then
    contribution_state "$v_head" HEAD
    case "$CONTRIB_RC" in
      1) fail_milestone 4 "verdict record $VERDICT_REL reviewed patch $(printf '%.12s' "$v_pid"), but this branch's diff against origin/$BASE_BRANCH now hashes to $(printf '%.12s' "$cur_pid") and the branch's own lines moved with it: $(printf '%s\n' "$CONTRIB_DETAIL" | contribution_summary) — content changed after the review, so the verdict does not cover it. Get a new review round: '/dev-pipeline:review-lean <pr>'." 5
         return $? ;;
      0) v_fresh="covering the current head — the recorded patch identity $(printf '%.12s' "$v_pid") and this head's $(printf '%.12s' "$cur_pid") differ, which a base advance alone is enough to cause, and every one of the branch's own +/- lines is unchanged since reviewed_head $(printf '%.12s' "$v_head"), so no reviewed line was altered (#597 AC-1)" ;;
      *) v_fresh="covering the current head — the patch identity moved from $(printf '%.12s' "$v_pid") to $(printf '%.12s' "$cur_pid") and the +/- comparison could NOT be computed, so this milestone FAILED OPEN and the verdict stands (#597 D-5/OR-1)" ;;
    esac
  fi
  pass_milestone 4 "$VERDICT_REL reads verdict=approve, authored by review run $v_run, $v_fresh, $v_coverage"
}

# ---------------------------------------------------------------- verdict (REVIEW role)
# The ONLY write path to the verdict record, and it lives in this script because the pinned name
# table above is the sole derivation of VERDICT_REL — a name invented at a second site is the
# drift the merge-boundary gate turns red.
#
# It never evaluates a milestone, never appends to the progress file, and never touches the build
# run-id cache. Those omissions let milestone 4 stay a pure read.
#
# The refusals are ordered cheapest-first and every one fails CLOSED. A build run whose progress
# header records no session id is refused outright: "unverifiable" must never resolve to "fine".
cmd_verdict() {
  local sess b_prog_sess b_prog_run b_cached rec body c reviewed_head reviewed_patch_id
  local fid_spec fid_state fid_decl fid_refs fid_bad fid_line
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

  # DESIGN FIDELITY (#394, D-7). Defaults to `not-applicable`, which is the FAIL-CLOSED side: on an
  # armed run milestone 4 demands `pass`, so a round that forgot the flag is refused rather than
  # certifying a design it never looked at. On an unarmed run the default is simply the truth.
  # `fail` exists so a finding round can record what it found.
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

  # THE ARMED EVIDENCE OBLIGATION (#693). `review-lean` step 5b already mandates comparing per RS
  # row "scoring each one in the summary"; the obligation existed and nothing checked it —
  # `--summary-file` was read as opaque text and no reader anywhere parsed it for shape. So the
  # armed lane's whole fidelity claim rested on one model's sighted comparison recorded as one
  # word, and no downstream reader could tell a real comparison from a rubber stamp.
  #
  # Refused at the WRITER, where the fix is one edit away, for the reason the fidelity/approve
  # contradiction above states in full: milestone 4 would cost the round. It cannot sit BESIDE
  # that sibling — `body` does not exist until the block above — and it must sit BEFORE the run-id
  # cache below, whose comment reads "every refusal above has passed, so this is a real review
  # round". A refusal placed after that line caches a review identity for a round that wrote no
  # record.
  #
  # NO MILESTONE-4 BACKSTOP, deliberately. A verdict record carries no timestamp and no schema
  # version, so a legacy evidence-free `pass` is byte-indistinguishable from one whose section was
  # stripped after the fact. A backstop that cannot tell those apart adds no assurance and creates
  # a migration problem; every already-committed record keeps passing milestone 4 unchanged.
  #
  # The pair of conditions is `pass` AND a configured provider. An unarmed `pass` is already
  # refused by milestone 4's own arm in clearer words, and re-refusing it here would break every
  # consumer with no design axis for no gain.
  if [ "$VERDICT_FIDELITY" = "pass" ] && [ -n "$DESIGN_PROVIDER" ]; then
    fid_spec="$REPO_ROOT/$SPEC_REL"
    # `design_state` reads an ABSENT spec as `unarmed` — the same answer it gives a consumer with
    # no design axis at all — so the two must be split here or an armed ticket reviewed from a
    # checkout missing its spec banks a pass on a file nobody read. The provider being configured
    # is what makes them distinguishable at this call site.
    if [ ! -f "$fid_spec" ]; then
      warn "✗ verdict: --fidelity pass, but this checkout carries no spec at $SPEC_REL — there is nothing that could have armed a design lane, and nothing to score the evidence against."
      warn "  Run the verdict from a checkout of the PR head (review-lean step 3)."
      return 1
    fi
    fid_state="$(design_state "$fid_spec")"
    case "$fid_state" in
      armed) : ;;
      disarmed)
        warn "✗ verdict: --fidelity pass, but $SPEC_REL disarms the design lane ('Design: none — <reason>'). A disarmed ticket declares no render state to have scored; the only value it may carry is 'not-applicable'."
        return 1 ;;
      error:*)
        # A malformed `## Design` section is NOT merely not-armed: treating it that way would let
        # a spec too broken to enumerate bank a pass, which is the tamper surface this refusal
        # exists to close. `design_state` has four outcomes, not two.
        warn "✗ verdict: --fidelity pass, but $SPEC_REL's design arming cannot be resolved: ${fid_state#error:}"
        return 1 ;;
      *)
        warn "✗ verdict: --fidelity pass, but design_state reports '$fid_state' for $SPEC_REL — refusing rather than guessing which lane was scored."
        return 1 ;;
    esac
    # THE DECLARED SET COMES FROM design_rs_rows(), the reader milestone 3 builds the receipt
    # with — not from design_armed's prefix detector, which counts a malformed row that
    # design_rs_rows drops. Using the receipt's own reader is what keeps the evidence set equal to
    # what was actually rendered. Milestone 3 refuses a spec with no well-formed row, so a healthy
    # branch cannot reach this line with an empty set; the refusal below is for the one that did.
    fid_decl="$(design_rs_rows < "$fid_spec" | cut -f1 | tr '\n' ' ')"
    case "$fid_decl" in
      *[!\ ]*) : ;;
      *) warn "✗ verdict: --fidelity pass, but the '## Design' section of $SPEC_REL declares no well-formed '| RS-n | route | state | AC refs |' row, so there is no render state an evidence table could score. Re-run milestone 3 in the build lane."
         return 1 ;;
    esac
    # `AC-n` as well as `D-n`, because the Decision Ledger section is OPTIONAL while at least one
    # `AC-n` is mandatory — so a resolvable target always exists and no legitimate deviation is
    # left with nothing to cite. Two-stage extraction: a non-alphanumeric boundary first so
    # `XAC-1` does not donate `AC-1`, then the bare id.
    fid_refs="$(grep -oE '(^|[^A-Za-z0-9])(AC|D)-[0-9]+' "$fid_spec" 2>/dev/null | grep -oE '(AC|D)-[0-9]+' | sort -u | tr '\n' ' ')"
    fid_bad="$(printf '%s\n' "$body" | fidelity_evidence_violations "$fid_decl" "$fid_refs")"
    if [ -n "$fid_bad" ]; then
      warn "✗ verdict: --fidelity pass on an armed ticket requires a conforming '## $FIDELITY_EVIDENCE_HEADING' table in --summary-file — one or more rows per declared render state ($fid_decl):"
      printf '%s\n' "$fid_bad" | while IFS= read -r fid_line; do warn "    $fid_line"; done
      warn "  Columns, in order, case-insensitive: $FIDELITY_EVIDENCE_COLUMNS. Every cell non-empty."
      warn "  'verdict' is 'match', or 'deviation (<AC-n|D-n>)' naming a criterion $SPEC_REL declares. A cited deviation does not force fidelity=fail."
      warn "  The grammar is in review-lean/SKILL.md step 5b. It makes the fidelity claim FALSIFIABLE by a human reader; it does not verify the render against the design, and no gate here does."
      return 1
    fi
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

# "Progress file current" is asserted as: milestones 1-4 each left a `satisfied` record.
#
# NOT as "the file exists". That check cannot hold: failing any milestone appends an
# attempt line, appending creates the file, so a bare existence check heals itself between
# the first run and the second — it reports absent once and passes forever after, which is
# worse than not checking at all. Asserting the 1-4 records is stable (an M5 attempt line
# never satisfies M1-4) and is what the contract actually means.
#
# ONE DEFINITION, TWO CALLERS since #590: cmd_5 certifies against it, and cmd_close_out refuses to
# WRITE against it. The second is the stronger need — declining to certify an uncertified run is
# bookkeeping, while posting a closing comment on one is a false public statement about it.
m5_missing_milestones() { # prints the unsatisfied milestone numbers, space-prefixed; empty = current
  local m missing=""
  for m in 1 2 3 4; do
    [ "$(count_matches "| milestone-$m | satisfied" "$PROGRESS_FILE" -F)" -ge 1 ] || missing="$missing $m"
  done
  printf '%s' "$missing"
}

# The lane's one open PR, resolved once. EXTRACTED rather than duplicated for #590's close-out:
# two readers of "which PR is this lane's" that could disagree would let the command write its
# cost block onto one PR and the milestone assert against another.
LEAN_PR_JSON=""
LEAN_PR_ERROR=""
resolve_open_pr() { # 0 = $LEAN_PR_JSON holds a one-element array; 1 = $LEAN_PR_ERROR says why
  local pr
  LEAN_PR_JSON=""; LEAN_PR_ERROR=""
  if [ -n "$PR_FILE" ]; then
    [ -f "$PR_FILE" ] || envfail "--pr-file '$PR_FILE' does not exist."
    pr="$(cat "$PR_FILE")"
  else
    pr="$("$GH_CLI" pr list --head "$LEAN_BRANCH" --state all \
          --json number,url,body,isDraft,state --limit 20 2>&1)" \
      || { warn "$pr"; LEAN_PR_ERROR="could not list PRs for $LEAN_BRANCH"; return 1; }
  fi
  printf '%s' "$pr" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { LEAN_PR_ERROR="could not list PRs for $LEAN_BRANCH"; return 1; }
  # #642: A MERGED PR SATISFIES THE SAME OBLIGATION AN OPEN ONE DOES. The obligation is that the
  # PR reached its terminal state carrying its exit artifacts, and merged is more terminal than
  # open. Requiring `open` made `close-out` permanently unreachable once an operator merged first:
  # milestones 3 and 4 passed and 5 retried three times against a condition that could not become
  # true again, so the run's cost-log row was never written and its PR kept a stale cost block.
  #
  # OPEN WINS WHEN BOTH EXIST — a re-cut PR on the same branch is the live one, and its body is
  # what close-out patches. A CLOSED-unmerged PR satisfies nothing: it is the shape of abandoned
  # work, and certifying it would be a false public statement about the run.
  #
  # `.state // "OPEN"` is for the `--pr-file` seam, whose fixtures predate the key and whose whole
  # contract has always been "this is the lane's PR"; it is never a live gh response, which always
  # carries the field it was asked for.
  pr="$(printf '%s' "$pr" | jq -c '
        [ .[] | select((.state // "OPEN") == "OPEN") ]
      + [ .[] | select((.state // "OPEN") == "MERGED") ] | .[0:1]' 2>/dev/null)"
  printf '%s' "$pr" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { LEAN_PR_ERROR="no open or merged PR found for branch $LEAN_BRANCH"; return 1; }
  LEAN_PR_JSON="$pr"
  return 0
}

cmd_5() {
  local pr comments url draft body missing

  missing="$(m5_missing_milestones)"
  if [ -n "$missing" ]; then
    block_milestone 5 "progress file is not current — milestone(s)$missing left no satisfied record, so there is nothing to certify"
    return $?
  fi

  # #531 D-10. FROM HERE ON, EACH OF MILESTONE 5'S TWO OBLIGATIONS RECORDS ITS OWN STATE before
  # the aggregate is decided. The failure paths below are unchanged in every respect but that —
  # same order, same wording, same fix-budget accounting — and the aggregate `satisfied` row is
  # still appended only at the very end, once every obligation holds. What is new is that a
  # partially finished close-out now leaves a record naming WHICH half is outstanding, instead of
  # one indistinguishable `attempt` line the scheduler could only report as "all three unaccounted
  # for". `fail_obligation` is the whole mechanic: record, then fail exactly as before.
  #
  # `exit-artifacts` is the ready PR carrying its ticket reference and its spec link.
  # `verdict-reference` is the surface that points at the committed verdict record — the closing
  # comment on the issue under github, and the PR body under a `writes: false` tracker, which is
  # the same obligation discharged where the adapter allows.
  resolve_open_pr || { block_obligation exit-artifacts "$LEAN_PR_ERROR"; return $?; }
  pr="$LEAN_PR_JSON"

  draft="$(printf '%s' "$pr" | jq -r '.[0].isDraft')"
  body="$(printf '%s' "$pr" | jq -r '.[0].body // ""')"
  url="$(printf '%s' "$pr" | jq -r '.[0].url')"

  [ "$draft" = "false" ] || { fail_obligation exit-artifacts "PR $url is still a draft (D-27 requires a ready PR)"; return $?; }
  # Same capture-first discipline as count_matches — these read a string, not a file.
  local n_closes n_spec
  if [ "$TRACKER_TYPE" = "jira" ]; then
    n_closes="$(printf '%s' "$body" | jira_items_section | grep -c -i -E "closes[[:space:]]+\[$ISSUE\]")" || n_closes=0
    [ "$n_closes" -ge 1 ] \
      || { fail_obligation exit-artifacts "PR body carries no 'Closes [$ISSUE]' under a 'Jira Items' heading"; return $?; }
  else
    n_closes="$(printf '%s' "$body" | grep -c -i -E "closes[[:space:]]+#$ISSUE")" || n_closes=0
    [ "$n_closes" -ge 1 ] \
      || { fail_obligation exit-artifacts "PR body carries no 'Closes #$ISSUE'"; return $?; }
  fi
  # Adapter-INSENSITIVE: the spec is a committed repo path at the same pinned location under
  # both trackers, so the link assertion is shared rather than duplicated per arm.
  n_spec="$(printf '%s' "$body" | grep -c -F -- "$SPEC_REL")" || n_spec=0
  [ "$n_spec" -ge 1 ] \
    || { fail_obligation exit-artifacts "PR body does not link the committed spec ($SPEC_REL)"; return $?; }
  append_obligation 5 exit-artifacts met

  # Under jira the verdict reference has nowhere else to live: `tracker.writes: false` means
  # there is no closing comment, so the PR body carries it and the comment trail is never
  # read. Reviewers read the PR either way — this only changes WHICH surface is gated.
  if [ "$TRACKER_TYPE" = "jira" ]; then
    local n_verdict
    n_verdict="$(printf '%s' "$body" | grep -c -F -- "$VERDICT_REL")" || n_verdict=0
    [ "$n_verdict" -ge 1 ] \
      || { fail_obligation verdict-reference "PR body does not reference the verdict record ($VERDICT_REL) — under a read-only tracker the body is the only surface that can carry it"; return $?; }
    append_obligation 5 verdict-reference met
    cmd_mark || { block_milestone 5 "could not stamp the build identity on the PR"; return $?; }
    pass_milestone 5 "exit artifacts present, jira adapter, no tracker write ($url)"
    return 0
  fi

  if [ -n "$COMMENTS_FILE" ]; then
    [ -f "$COMMENTS_FILE" ] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
    comments="$(cat "$COMMENTS_FILE")"
  else
    comments="$("$GH_CLI" api "repos/{owner}/{repo}/issues/$ISSUE/comments" --paginate 2>&1)" \
      || { warn "$comments"; block_obligation verdict-reference "could not fetch the comment trail for #$ISSUE"; return $?; }
  fi
  printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || envfail "comment trail is not a JSON array."

  # The closing comment must REFERENCE the verdict record — that reference is what ties
  # the tracker record to the committed artifact the chain gate checks.
  local closing
  closing="$(printf '%s' "$comments" | jq -r --arg v "$VERDICT_REL" \
    '[ .[] | select((.body // "") | contains($v)) ] | length')"
  [ "$closing" -ge 1 ] \
    || { block_obligation verdict-reference "no closing comment on #$ISSUE references the verdict record ($VERDICT_REL)"; return $?; }
  append_obligation 5 verdict-reference met

  # The build identity, stamped on the PR (D-3). LAST, after every assertion above: a run that
  # is not going to pass milestone 5 has no business leaving a marker, and the idempotent
  # no-op means the ordinary path — where checklist step 7 already posted it — writes nothing.
  #
  # NOT an obligation row of its own (D-11 draws the set at two): it is an assertion milestone 5
  # makes about the run's identity, not one of checklist step 9's obligations, and adding it to the
  # report would make the report answer a question the failure message does not ask.
  cmd_mark || { block_milestone 5 "could not stamp the build identity on the PR"; return $?; }

  pass_milestone 5 "exit artifacts present ($url)"
}

# ---------------------------------------------------------------- the CLOSE-OUT (#590)
# WHY THIS IS A SUBCOMMAND AND NOT A SESSION. After the approve, orchestrate-lean.sh spawned a
# third full model session on the run's BUILD model whose entire output was a fixed sequence of
# commands: re-compute the cost block, replace it in the PR description, post one closing comment,
# assert milestone 5, tear the lane down. Not one of those is a judgment, and paying a
# reasoning-tier session per run to type them is the deletion doctrine pointed at the lane's own
# ritual. Observed cost on the #585 run: spawn 1 build, spawn 2 review, spawn 3 bookkeeping.
#
# THE IDENTITY CONSTRAINT IS WHAT MAKES IT A GATE COMMAND rather than scheduler code (D-6). The
# lane runs a two-identity contract — the scheduler authors nothing, the review block owns
# milestone 4 and nothing else — so the close-out's writes must carry the BUILD identity. They do:
# every one goes through the bot wrapper, already the author of the claim marker, the PR marker
# and every commit on the branch. No third party appears on a close-out artifact, which is the
# property the ticket declares binding. The scheduler's rule is restated, not weakened: it authors
# nothing UNDER ITS OWN IDENTITY.
#
# IT IS NOT A SECOND MILESTONE 5 (D-1). `bash G 5` is unchanged and stays a pure verifier: this
# command WRITES and then calls it, so a caller who wants to re-assert without writing still has
# one, and nothing re-keys the scheduler's satisfied-token predicate, the `all` progression,
# retro-corpus or lean-reconcile.
#
# ORDER IS LOAD-BEARING. The progress precondition first, so a run whose earlier milestones never
# passed is refused BEFORE anything public is written — declining to certify such a run is
# bookkeeping, while posting a closing comment on it is a false public statement about it. Then
# the writes, each recording its own obligation as it lands. Then the assertions. Then, and only
# on a fully met close-out (D-6), teardown.

# The two literals that BOUND a rendered cost block inside a PR description. Held byte-for-byte to
# pipeline-cost-block.sh, which RENDERS them: the replacement below strips from the marker line
# through the first following line carrying the terminator prefix and leaves everything after it
# untouched, so a renderer whose last line moved while this did not would make that strip run to
# end-of-file and silently delete whatever a human had appended below the block.
# LOCKSTEP-BEGIN lean-cost-block-bounds
COST_BLOCK_MARKER='<!-- pipeline-cost-block -->'
COST_BLOCK_TERMINATOR='Cache-hit rate: '
# LOCKSTEP-END lean-cost-block-bounds

# The authenticated writer for the close-out's two source-control writes. The bot wherever the
# consumer configured one — the identity every other close-out artifact already carries — and the
# operator's own CLI where it did not, which is the only writer a bot-less consumer has. Neither
# arm is a third identity in the lane's sense: the party that would otherwise have made these
# writes is the build session, and under a bot-less consumer that session wrote as the operator too.
closeout_writer() {
  if [ "$BOT_ENABLED" = "true" ] && [ -n "${GH_BOT:-}" ]; then printf '%s' "$GH_BOT"; else printf '%s' "$GH_CLI"; fi
}

# (1) THE PUBLISHED FIGURE. The step-7 snapshot's fence closed before the review half of the run
# existed, so this — not that one — is the number the run publishes, and `--close-out` is also
# what writes the cross-run corpus row.
#
# A DOCUMENTED SKIP IS NOT A FAILURE (AC-4). The tool's own exit contract is "0 = ran, or logged a
# documented skip" — telemetry off, no collector, the window rotated out of the metrics files — and
# on a skip it renders nothing. Reding there would make every host without a collector unable to
# close a run out. A NON-ZERO exit is the opposite and is refused: it means the fence or the
# session set could not be derived at all, which is exactly the confidently-wrong published figure
# #546 exists to stop.
LEAN_COST_BLOCK=""
LEAN_COST_SKIP=""
LEAN_COST_ERROR=""
closeout_cost_block() { # closeout_cost_block <pr-url>
  local tool out rc
  LEAN_COST_BLOCK=""; LEAN_COST_SKIP=""; LEAN_COST_ERROR=""
  tool="${LEAN_COST_BLOCK_TOOL:-$(dirname "$(dirname "$(cd "$(dirname "$0")" && pwd)")")/tools/pipeline-cost-block.sh}"
  if [ ! -f "$tool" ]; then
    LEAN_COST_ERROR="pipeline-cost-block.sh not found at '$tool', so this run's published figure cannot be derived"
    return 1
  fi
  # stdout is the block; the tool's stderr is the operator's evidence and is deliberately not
  # captured, so a skip verdict is READ rather than swallowed into a variable nobody prints.
  out="$(bash "$tool" --stateless --issue "$ISSUE" --close-out --prs "$1")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    LEAN_COST_ERROR="pipeline-cost-block.sh exited $rc — the run's fence or session set could not be derived, so there is no honest figure to publish (its own line above says which)"
    return 1
  fi
  case "$out" in
    *"$COST_BLOCK_MARKER"*) LEAN_COST_BLOCK="$out" ;;
    *) LEAN_COST_SKIP="the tool exited 0 and rendered no block — a documented skip, named on its own line above" ;;
  esac
  return 0
}

# (2) THE CORPUS ROW. Asserted, not assumed: the write happens inside the tool above, so without
# a read-back the obligation would be "we ran a command", which is what the whole ticket is about.
# Identity is (ticketKey, runId), the pair the tool keys its replace-or-append on.
LEAN_COST_LOG=""
closeout_cost_log_row() {
  local n
  LEAN_COST_LOG="${COST_LOG_FILE:-$MAIN_ROOT/$STATE_DIR/cost-log.jsonl}"
  [ -f "$LEAN_COST_LOG" ] || return 1
  # CAPTURE FIRST, then test. `jq -s` over a log that does not parse errors with EMPTY output, and
  # an unguarded numeric test on an empty string is a syntax error that reads as "no row".
  n="$(jq -s --arg k "$ISSUE" --arg r "$RESOLVED_RUN_ID" \
        '[ .[] | select(((.ticketKey // "") == $k) and ((.runId // "") == $r)) ] | length' \
        "$LEAN_COST_LOG" 2>/dev/null)" || n=""
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  [ "$n" -ge 1 ]
}

# (3) THE PR DESCRIPTION. The step-7 block is stale the moment the review lands, and a reader of
# the PR reads the description, not the issue thread.
#
# BOUNDED REPLACEMENT, NEVER TRUNCATE-TO-EOF. The block is appended last by construction, so
# stripping from its marker to the end of the body would usually be right — and would silently
# delete a human's own text on the one run where somebody had written below it. So the strip ends
# at the renderer's own last line, whose prefix is held to it by the marker block above; a body
# whose marker has no terminator after it is REPORTED rather than quietly truncated.
LEAN_PATCH_NOTE=""
LEAN_PATCH_ERROR=""
closeout_patch_pr_body() { # closeout_patch_pr_body <pr-number> <current-body>
  local dir state out rc
  LEAN_PATCH_NOTE=""; LEAN_PATCH_ERROR=""
  dir="$(mktemp -d -t lean-closeout.XXXXXX)" || envfail "mktemp failed."
  : > "$dir/head"; : > "$dir/tail"
  # CR-stripped first: a body round-tripped through the GitHub API carries CRLF, and `$0 == m`
  # against a line ending in CR matches nothing — the marker would read as absent on every real
  # PR while every fixture passed.
  state="$(printf '%s\n' "$2" | tr -d '\r' | awk -v m="$COST_BLOCK_MARKER" -v t="$COST_BLOCK_TERMINATOR" \
      -v h="$dir/head" -v tl="$dir/tail" '
    !seen { if ($0 == m) { seen = 1 } else { print > (h) } ; next }
    !cut  { if (index($0, t) == 1) { cut = 1 } ; next }
          { print > (tl) }
    END   { print (seen ? (cut ? "replaced" : "truncated") : "appended") }
  ')"
  { cat "$dir/head"; printf '%s\n' "$LEAN_COST_BLOCK"; cat "$dir/tail"; } > "$dir/body"
  out="$("$(closeout_writer)" api -X PATCH "repos/{owner}/{repo}/pulls/$1" \
        -F body=@"$dir/body" --jq .number 2>&1)"; rc=$?
  rm -rf "$dir"
  if [ "$rc" -ne 0 ]; then
    LEAN_PATCH_ERROR="could not replace the cost block in PR #$1's description: $out"
    return 1
  fi
  case "$state" in
    truncated) LEAN_PATCH_NOTE="replaced, but the previous block had no terminator line — anything below it was not preserved"
               warn "· close-out: PR #$1's earlier cost block carried no '$COST_BLOCK_TERMINATOR' line, so the replacement could not tell where it ended. Text below it was not preserved." ;;
    appended)  LEAN_PATCH_NOTE="appended — the description carried no earlier block" ;;
    *)         LEAN_PATCH_NOTE="replaced in place" ;;
  esac
  say "✓ close-out: PR #$1's cost block $LEAN_PATCH_NOTE."
  return 0
}

# (4) THE CLOSING COMMENT — github only. NO HTML MARKER, deliberately: a `<!-- stage: … -->` token
# here would enrol this comment in check-pipeline-chain.sh's run-family selection, which is the
# pollution the claim marker's own lean-distinct tag exists to avoid. Its machine consumer keys on
# CONTENT — the verdict-record path — which is also exactly what `verdict-reference` asserts, and
# what retro-corpus's open-PRs mode filters on without ever reading the author.
LEAN_COMMENT_ERROR=""
closeout_comment() { # closeout_comment <pr-url>
  local file out rc
  LEAN_COMMENT_ERROR=""
  file="$(mktemp -t lean-closeout-comment.XXXXXX)" || envfail "mktemp failed."
  {
    echo "🤖 Closed out by \`/dev-pipeline:build-lean\`."
    echo ""
    echo "- PR: $1"
    echo "- Verdict record: \`$VERDICT_REL\`"
    if [ -n "$LEAN_COST_BLOCK" ]; then
      echo ""
      printf '%s\n' "$LEAN_COST_BLOCK"
    fi
  } > "$file"
  out="$("$(closeout_writer)" api -X POST \
        "repos/{owner}/{repo}/issues/$ISSUE/comments" -F body=@"$file" --jq .html_url 2>&1)"; rc=$?
  rm -f "$file"
  if [ "$rc" -ne 0 ]; then
    LEAN_COMMENT_ERROR="could not post the closing comment on #$ISSUE: $out"
    return 1
  fi
  say "✓ close-out: closing comment posted on #$ISSUE ($out)"
  return 0
}

cmd_close_out() {
  local missing pr prnum url body detail n rc

  # MILESTONES 1-4 FIRST, RECORDING, and this is the mandate the deleted session used to carry.
  # Checklist step 9 ordered `bash G all` before the close-out because a milestone satisfied before
  # a fix round is stale, and — load-bearing rather than hygienic — milestone 4 has NO other
  # recorder: the scheduler reads the verdict through `LEAN_GATE_OBSERVE=1`, which by contract
  # writes no satisfied row. Without this loop the progress precondition below could never hold and
  # no lane could ever close out.
  #
  # 1..4, NOT `all`. The mandated `all` reached milestone 5 BEFORE step 9's writes existed and
  # redded there every time, spending a fix attempt on an artifact the very next command was about
  # to create — a cost the old shape paid on every run and the liveness fixture documented as
  # expected. Here milestone 5 is evaluated exactly once, at the end, after the writes.
  for n in 1 2 3 4; do
    run_milestone "$n"; rc=$?
    if [ "$rc" -ne 0 ]; then
      say "close-out: stopped at milestone-$n (rc=$rc) — nothing was written."
      return "$rc"
    fi
  done

  # THE ABSENT VERB ON BOTH, exactly as cmd_5 spells them (#642 AC-3, round 1 B1). These two reds
  # name reasons docs/gate-ablation.md adjudicates `unchanged` — m5/progress-current and
  # m5/exit-artifacts:no-open-pr — so a charging verb here re-opened, on the close-out path alone,
  # the fix-budget hole the milestone-5 assert path had just closed. `block_obligation` rather than
  # a bare `block_milestone` for the second: close-out records obligation state the same way cmd_5
  # does, so the record still names WHICH half is outstanding (#531 D-10).
  #
  # The first arm is defensive and unreachable from HERE — the 1..4 loop above appends the very
  # satisfied rows m5_missing_milestones tests for, so no input reaches it. It is re-verbed anyway
  # and guarded statically: lean-gate-selftest.sh's (ac1c) classifies every charging-verb reason
  # through the production predicate table, which is the only technique that can reach an arm no
  # fixture can drive. (co1) drives the second.
  missing="$(m5_missing_milestones)"
  if [ -n "$missing" ]; then
    block_milestone 5 "progress file is not current — milestone(s)$missing left no satisfied record, so there is nothing to close out and nothing public should be written about it"
    return $?
  fi

  resolve_open_pr || { block_obligation exit-artifacts "$LEAN_PR_ERROR"; return $?; }
  pr="$LEAN_PR_JSON"
  prnum="$(printf '%s' "$pr" | jq -r '.[0].number')"
  url="$(printf '%s' "$pr" | jq -r '.[0].url')"
  body="$(printf '%s' "$pr" | jq -r '.[0].body // ""')"

  closeout_cost_block "$url" || { fail_obligation cost-block "$LEAN_COST_ERROR"; return $?; }
  # NOT a `${VAR:-default}` carrying an apostrophe: inside double quotes bash opens a quote on it
  # and the file stops parsing several hundred lines later, which is a `bash -n` failure rather
  # than a runtime one but is worth not re-discovering.
  detail="recomputed over the fence this run recorded"
  [ -n "$LEAN_COST_SKIP" ] && detail="$LEAN_COST_SKIP"
  append_obligation 5 cost-block met "$detail"

  if [ -n "$LEAN_COST_SKIP" ]; then
    append_obligation 5 cost-log-row met "no rollup, no row — $LEAN_COST_SKIP"
  elif closeout_cost_log_row; then
    append_obligation 5 cost-log-row met "$LEAN_COST_LOG"
    say "✓ close-out: the cross-run cost corpus carries this run's row ($LEAN_COST_LOG)."
  else
    fail_obligation cost-log-row "a cost block was rendered but $LEAN_COST_LOG carries no row for (ticketKey=$ISSUE, runId=$RESOLVED_RUN_ID) — the corpus write did not land, so this run would be missing from the only cross-run cost record"
    return $?
  fi

  if [ -n "$LEAN_COST_SKIP" ]; then
    append_obligation 5 pr-cost-block met "nothing to publish — $LEAN_COST_SKIP"
  elif closeout_patch_pr_body "$prnum" "$body"; then
    append_obligation 5 pr-cost-block met "$LEAN_PATCH_NOTE"
  else
    fail_obligation pr-cost-block "$LEAN_PATCH_ERROR"
    return $?
  fi

  # Under a read-only tracker there is no comment surface at all, so `verdict-reference` is
  # discharged by the PR body — which checklist step 7 already wrote, the verdict record's path
  # being deterministic before the record exists. cmd_5 asserts exactly that, on the same arm.
  if [ "$TRACKER_TYPE" = "jira" ]; then
    say "· close-out: tracker '$TRACKER_TYPE' is read-only — no closing comment; the PR body carries the verdict reference."
  else
    closeout_comment "$url" || { fail_obligation verdict-reference "$LEAN_COMMENT_ERROR"; return $?; }
  fi

  cmd_5 || return $?

  # D-6: LAST, and only here. A close-out that redded above returned already, so the worktree, the
  # branch and the claim are all still standing for the manual rescue every other hard stop leaves.
  cmd_teardown
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
  local n="$1" rc unclosed budget
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
  # ONE bound for all five milestones since #566 retired milestone 3's larger one (see
  # INTERRUPTED_BUDGET above). Still resolved once, here, so the announce, the observe prediction
  # and the refusal below cannot disagree about which budget this milestone is on.
  budget="$INTERRUPTED_BUDGET"
  if [ "$unclosed" -gt 0 ]; then
    # ANNOUNCE, NEVER REFUSE (D-4). An interrupted milestone is precisely the one a resuming
    # session must be able to re-run, and this is the call it makes: SKILL.md's Resume step says
    # `all` stops early while milestone 4 is outstanding and to run the milestones directly, so
    # `bash G <n> <issue>` is where the notice has to land to be seen.
    warn "note: milestone-$n: $unclosed earlier evaluation(s) began and never concluded (interrupted $unclosed/$budget) — re-running it now."
  fi
  # OBSERVE: predict, never record (see the header note above). The announce is deliberately ABOVE
  # this arm — it is a stderr diagnostic and touches nothing the seam promises not to touch.
  #
  # MILESTONE 3 RUNS INLINE HERE, undetached. Observe promises to record nothing, and a detach
  # writes a pidfile, a marker and a log; more to the point, the only caller that observes is
  # cmd_all's pre-pass, which evaluates 1 and 4 alone precisely to avoid paying for milestone 3.
  # A caller that sets the seam by hand on `3` is asking to watch it, not to survive it.
  if [ "${LEAN_GATE_OBSERVE:-0}" = "1" ]; then
    [ "$unclosed" -ge "$budget" ] && return 4
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
  if [ "$unclosed" -ge "$budget" ]; then
    append_line "$(now_iso) | milestone-$n | interrupted-exhausted | $unclosed unconcluded"
    warn "milestone-$n has been begun and cut off $unclosed times without ever concluding — hard stop."
    return 4
  fi

  # The append IS the flush: append_line is a single unbuffered `echo >>`, so ordering it before
  # the long work is the whole requirement (D-10). No trap closes this row on a signal (D-9) — the
  # design rests on the ABSENCE of a conclusion, a partial trap would make that absence mean two
  # different things, and SIGKILL cannot be trapped at all. An `exit` from inside a milestone body
  # (envfail) likewise leaves the row open, which is the honest record of what happened (D-12).
  append_started "$n"
  # #566 PUT MILESTONE 3 BACK IN THIS DISPATCH. Between #511 and #566 it was absent by
  # construction — the arm above returned early into a detached launch-or-join wrapper, and a `3`
  # arriving here meant that wrapper had regressed, so the `*)` envfailed rather than quietly
  # running an evaluation the run's records did not describe. There is no wrapper now: milestone 3
  # is an ordinary inline milestone like the other four, and it takes an ordinary arm.
  #
  # The `*)` STAYS, for the reason it was written. A milestone number with no arm must not fall
  # through to a silent success — that would be a green milestone that never ran, which is the one
  # failure this whole file exists to prevent.
  case "$n" in
    1) cmd_1 ;;
    2) cmd_2 ;;
    3) cmd_3 ;;
    4) cmd_4 ;;
    5) cmd_5 ;;
    *) envfail "run_milestone: no dispatch arm for milestone $n" ;;
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

# ---------------------------------------------------------------- the LANE-TREE ASSERTION (#141)
# WHAT THIS CLOSES: every answer below is derived from $REPO_ROOT, and $REPO_ROOT is resolved from
# the invoking shell's cwd and nothing else. From the shared checkout the gate grades `main` and
# reports it in the same words a real green uses — "nothing to sweep" on a guard-ADDING diff, a
# selftest count one short of the branch's. `cmd_delta` has the same shape on the review side:
# from the main checkout it prints the FULL range over an EMPTY diff and the round reads nothing.
# A check that runs, passes and proves nothing is the defect class #141 was filed about, and this
# file was its last live instance.
#
# BRANCH-NAME EQUALITY, not worktree-set membership (D-2). A shared checkout that HAS the lane
# branch checked out is grading the right tree, and this guard is about the TREE, not the
# directory. A detached HEAD reads back the literal `HEAD`, matches nothing, and so refuses — the
# fail-closed posture this file takes everywhere else, and the right one here: `gh pr checkout` on
# a same-repo PR names the local branch after headRefName, so an honest review checkout passes,
# while a detached one is a tree whose identity nothing on disk asserts.
#
# BEFORE require_entry_attested (D-7), and that ordering is the point. The entry refusal's own
# message already ends "Re-run from the build worktree before handing this back" — so until now a
# wrong-tree call surfaced as a missing-attestation failure naming the wrong primary cause.
require_lane_tree() {
  local head paths
  head="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)" || head=""
  [ -n "$head" ] || head="<unresolvable>"

  # ANNOUNCED UNCONDITIONALLY when it disarms, on the config-path announcement's precedent: a
  # guard nobody can see disarmed is a guard nobody can audit, and the whole failure mode here is
  # a plausible answer about the wrong tree.
  if [ "${LEAN_GATE_ANY_TREE:-0}" = "1" ]; then
    # The wording avoids the token `ARMED` deliberately: milestone 1's design-arming cases grep
    # the merged output for it, and `DISARMED` is a substring match away from reding them.
    warn "note: $SUB: LEAN_GATE_ANY_TREE=1 — the lane-tree assertion is OFF for this call. Grading $REPO_ROOT, which is on '$head'; this run's lane branch is '$LEAN_BRANCH'."
    return 0
  fi

  [ "$head" = "$LEAN_BRANCH" ] && return 0

  warn "✗ $SUB: WRONG TREE — $REPO_ROOT is on '$head', not this run's lane branch '$LEAN_BRANCH'."
  warn "  Nothing was evaluated: no record was written, no budget was spent and no fix attempt was charged. Every answer this subcommand gives is derived from the checkout it runs in, so from here it would grade the wrong branch and report a confident verdict about it (#141)."
  paths="$(lean_worktrees_for_branch "$LEAN_BRANCH")" || paths=""
  if [ -n "$paths" ]; then
    warn "  Re-run from a checkout on '$LEAN_BRANCH':"
    printf '%s\n' "$paths" | sed 's/^/[lean-gate]     /' >&2
  else
    warn "  No worktree on '$LEAN_BRANCH' is registered in this clone. Cut one:"
    warn "    git -C '$MAIN_ROOT' worktree add <path> '$LEAN_BRANCH'"
  fi
  warn "  A detached HEAD reads back as 'HEAD' and refuses here for the same reason — check the branch out by NAME. On a fork-origin PR \`gh pr checkout\` names the local branch <owner>-<branch>, which also refuses; \`git switch -c '$LEAN_BRANCH'\` makes it checkable."
  exit 9
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

# #141, and FIRST: a wrong-tree call must report the wrong tree, not whatever the tree it landed
# in happens to be missing. `verdict` joins this set although it is outside the one below —
# review-lean owns it, and its record names a patch identity computed from THIS checkout's diff.
case "$SUB" in
  1|2|3|4|5|all|delta|verdict|close-out) require_lane_tree ;;
esac

case "$SUB" in
  claim|delta|all|1|2|3|4|5|close-out) require_entry_attested ;;
esac

# #611, LAST of the three guards and the only one that opens a socket. After the attestation
# check, whose remedy is one local command, so an unattested `claim` is not sent to the network to
# be told something it could have been told for free — and after the cheap ticket arms, which have
# already refused every argument this read would have no answer for.
case "$SUB" in
  entry|claim) require_ticket_live; seed_run_id_cache ;;
esac

# #650 AC-2. The mid-run re-check, and it sits HERE for the reason the block above sits where it
# does: after the cheap ticket arms have refused every argument this read would have no answer for,
# and after the cwd arm at (iii) — which already binds `mark` — has established that the argument
# and the tree name the same run. `mark` is the only subcommand in this arm; see the function.
case "$SUB" in
  mark) require_ticket_still_open ;;
esac

case "$SUB" in
  entry)   cmd_entry ;;
  claim)   cmd_claim ;;
  mark)    cmd_mark ;;
  teardown) cmd_teardown ;;
  close-out) cmd_close_out ;;
  inflight) cmd_inflight ;;
  delta)   cmd_delta ;;
  progress) cmd_progress ;;
  staleness) cmd_staleness ;;
  verdict) cmd_verdict ;;
  all)     cmd_all ;;
  *)       run_milestone "$SUB" ;;
esac
exit $?

#!/usr/bin/env bash
# lean-evidence.sh — the PORTABLE half of the lean lane's merge-boundary evidence gate.
#
# WHY THIS FILE EXISTS. scripts/check-lean-chain.sh is second-shift-only by construction: it
# reconciles against tracker COMMENTS, which a read-only tracker posts none of, and its own
# header says not to ship it to a consumer. That left the lean lane with a harness a consumer
# can adopt and enforcement it cannot — the promotion prerequisite #343 named. The arms below
# are the ones that need no tracker at all, extracted so a consumer's CI can fetch and run
# THESE BYTES at its pinned marketplace ref while this repo's own gate delegates to the same
# file. One implementation; the dogfooding repo exercises exactly what consumers execute.
#
# THE ARMS (D-6). Widened past the two the issue named, because a gate proving only "an
# approve exists somewhere on this branch" is not the gate anyone thinks they installed:
#   1. VERDICT      — a committed record naming this issue, reading `verdict=approve`, and
#                     carrying both reconciliation keys (`run_id`, `session_id`). A local
#                     progress-file line is not evidence; only a committed, diffable artifact is.
#   2. IDENTITY     — the verdict's identity is NOT the build run's (P10). The build identity
#                     at this boundary is a bot-authored marker comment on the PULL REQUEST,
#                     never on the issue: source control is GitHub for every adapter, so the PR
#                     is the one write surface that needs no `tracker.writes` branching. The
#                     comparison runs against EVERY marker on the PR rather than the first — a
#                     second build session on the same PR would otherwise be measured against
#                     the first session's marker and could then author its own review.
#   3. FRESHNESS    — the approve covers the head being merged, via the record's declared
#                     `reviewed_patch_id`: the patch identity of the branch's own diff against
#                     its base, excluding the record. A commit landing after the review moves
#                     that id; a rebase replaying the branch unchanged does not, which is the
#                     point. The INFERRED (commit-range) arm and the legacy `reviewed_head` SHA
#                     path are NOT here — they exist only for records predating the key, all of
#                     which are merged, and check-lean-chain.sh keeps them for that history.
#   4. INTENT GAP   — a decision BUILD surfaced that the intake receipt never covered is routed
#                     back to a human (P9), not quietly made. Absence is the ordinary case, and
#                     a SATISFIED one: nothing went unevaluated, so it is class (a) and silent.
#
# NOT HERE, deliberately (OR-1): the inheritance-chain and design-render arms. Both are
# refinements firing only for multi-round reviews or design-armed tickets, both degrade to a
# weaker claim rather than an open evidence path, and fixturing them would roughly double this
# file's selftest surface. They remain in scripts/check-lean-chain.sh. Reversible: each is an
# additive arm here, addable without touching the template or this file's interface.
#
# ZERO MARKERS IS A VIOLATION, not a vacuous pass. "Differs from every element of the empty
# set" is true and proves nothing, and the posture everywhere in this gate is that a check
# which cannot run must not report one. The single exception is announced, never silent:
#
# THE NO-BOT DEGRADE (D-5/OR-2, re-keyed by #440). A consumer with no authenticated GitHub
# writer cannot post a marker that survives the `.user.type == "Bot"` trust filter below, so the
# identity arm reports itself at the `reduced-strength` disposition and is not evaluated — a
# class-(b) line on every run, so the weaker boundary is a stated fact rather than a silent one.
# The degrade is PER-ARM: every other arm still gates such a consumer exactly as it gates any
# other.
#
# It keys on the BOT, not on the tracker. It used to key on `tracker.type = jira`, on the
# premise that config-lint refused a `tracker.bot` there — which conflated the issue tracker
# with the code host. Source control is GitHub under both adapters, so a jira-tracked repo
# writes to GitHub on every run and can hold a bot identity for those writes; #440 dropped the
# refusal. A jira consumer that configures a bot is now gated here at full strength. What the
# axis fix did NOT do is move the block to its correct parent — `tracker.bot` still spells a
# code-host capability under the tracker key, and that rename is a `configVersion` schema
# change riding a successor, not this file.
#
# HONEST ALTITUDE: tamper-EVIDENCE, not proof, same as its second-shift sibling. The build
# agent writes the artifacts these arms read. Forging one is easy; forging all of them
# consistently across a committed diff and a bot-authenticated comment trail is what this makes
# detectable.
#
# THREE OUTPUT CLASSES (#443). Reciting every arm on a passing run teaches nothing and buries the
# lines that matter; reciting none makes a gate that checked nothing indistinguishable from one
# that checked everything. So the recital splits three ways:
#   (a) SATISFIED, including VACUOUSLY satisfied — no output at all, on either stream, whether the
#       run ends green or red. Which internal branch verified a contract is a source-reading
#       question, and a failing run's refusal already names the arm it came from. Silence is
#       unconditional and streamed, never buffered until the verdict is known.
#   (b) COULD NOT EVALUATE — exactly one line, on the green path. Mandatory rather than permitted:
#       an arm that quietly declines to run is the vacuous pass this whole file refuses everywhere
#       else. Its shape is pinned below, and pinned identically in scripts/check-lean-chain.sh,
#       because the successors to #443 emit into this class and must not each invent one.
#   FAILURE output is unchanged — as loud and as specific as it ever was.
# There is deliberately NO verbose flag. An opt-in that restores the recital restores the problem,
# one CI job at a time, and a flag nobody sets is a code path nobody reads.
#
# Inputs (ALL via the environment — never spliced into a `run:` line; a PR body is
# attacker-controllable, and both consuming workflows document that convention):
#   PR_HEAD_REF     required  the PR's head branch name
#   PR_HEAD_SHA     required  the PR HEAD COMMIT. NOT `HEAD`: on a pull_request event
#                             actions/checkout resolves refs/pull/N/merge, so HEAD is
#                             merge(base, head) and every base-side commit since the branch
#                             point would read as "changed after the verdict".
#   PR_BASE_REF     required  the PR's base branch; the base the patch identity is measured
#                             from. Needs a full-history checkout (fetch-depth: 0).
#   PR_BODY         required-ish  the PR body (empty is legal; it just fails to resolve a key)
#   PR_CREATED_AT   optional  ISO-8601 `Z`; the PR-open observation point, and the cutoff every
#                             `since:`-bearing arm below compares itself against. DELIBERATELY
#                             NOT required (#444): a newly-required input reds every consumer
#                             whose committed workflow predates it, which is the same
#                             strand-an-innocent-PR defect the cutoffs exist to close. Absent
#                             or unparseable ⇒ those arms report `postdated` and decline.
#   PR_NUMBER       required for the identity arm under github  the PR to read markers from
#   GH_REPO         required for the live identity path  "<owner>/<repo>"
#   GH_TOKEN        required for the live identity path
#   PIPELINE_BRANCH_PREFIX  optional  e.g. "claude/acme-"; read from the committed config when
#                                     unset (a consumer commits it; this repo gitignores its
#                                     own, so its CI passes it explicitly). Both lanes cut
#                                     branches under it; it is the KEY derivation's anchor, not
#                                     a classification arm.
#   LEAN_BRANCH_PREFIX      RETIRED (#413)  accepted and ignored, with a notice. A consumer's
#                                     workflow may still set it from a pin predating the change.
#   LEAN_TRACKER_TYPE       optional  github|jira; from the committed config when unset
#   LEAN_BOT_ENABLED        optional  true|false; whether an authenticated GitHub writer exists.
#                                     From `tracker.bot.enabled` when unset; a config declaring
#                                     no bot defaults per tracker (see the resolution below).
#   LEAN_MARKER_AUTHOR      optional  exact bot login; absent degrades to "any Bot author"
#   SECOND_SHIFT_CONFIG     optional  path to the committed config (testing / vendored fork)
#
# Seams (zero-network selftest, the check-lean-chain.sh precedent):
#   --pr-comments-file <path>      read the PR comment trail from a JSON fixture
#   --issue-comments-file <path>   read the ISSUE comment trail (the capability stamp's carrier)
#                                  from a JSON fixture
#   --diff-files-file <path>       read the PR's changed-file list from a newline fixture
#   ${GH:-gh}                      the CLI used for the comment fetches
#
# Interop:
#   --violations-file <path>    write this run's violation COUNT there. A delegating caller
#                               needs the number, not just the exit code: it prints one
#                               combined total, and "2 artifacts missing" collapsing to "1
#                               delegated arm set failed" loses the only quantity an operator
#                               triages by. A file rather than a stdout line so the log the
#                               human reads stays prose.
#
# Usage:
#   lean-evidence.sh classify              print applicable/trigger/key/spec_in_diff, exit 0
#   lean-evidence.sh check --key N         run the arms against an already-resolved key
#              [--arms verdict,identity,freshness,intent-gap,override]   default: all five
#   lean-evidence.sh [all]                 classify, then check every arm (the consumer form)
#
# Exit 0 = pass or not-applicable; 1 = evidence violation; 2 = usage/environment error.
#
# macOS ships /bin/bash 3.2; this file stays 3.2-compatible. No `set -e` — the violation
# counter IS the control flow.
set -uo pipefail

GH_CLI="${GH:-gh}"
PR_COMMENTS_FILE=""
ISSUE_COMMENTS_FILE=""
DIFF_FILES_FILE=""
VIOLATIONS_FILE=""
SUB=""
KEY=""
ARMS="verdict,identity,freshness,intent-gap,override"

while [ $# -gt 0 ]; do
  case "$1" in
    classify|check|all) SUB="$1"; shift ;;
    --key)               KEY="${2:-}"; shift 2 ;;
    --arms)              ARMS="${2:-}"; shift 2 ;;
    --pr-comments-file)  PR_COMMENTS_FILE="${2:-}"; shift 2 ;;
    --issue-comments-file) ISSUE_COMMENTS_FILE="${2:-}"; shift 2 ;;
    --diff-files-file)   DIFF_FILES_FILE="${2:-}"; shift 2 ;;
    --violations-file)   VIOLATIONS_FILE="${2:-}"; shift 2 ;;
    -h|--help)           sed -n '2,138p' "$0"; exit 0 ;;
    *) echo "[lean-evidence] unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$SUB" ] || SUB="all"

envfail() { echo "[lean-evidence] $1" >&2; exit 2; }

violations=0
note_violation() { echo "[lean-evidence]   ✗ $1" >&2; violations=$((violations + 1)); }

# LOCKSTEP: held verbatim to scripts/check-lean-chain.sh, the canonical side, which carries the
# reasoning. Nothing may sit between the markers — `verbatim` compares the whole block.
# LOCKSTEP-BEGIN lean-output-dispositions
LEAN_OUTPUT_DISPOSITIONS='not-applicable reduced-strength postdated inert'
# LOCKSTEP-END lean-output-dispositions

# The class-(b) emitter, and the ONLY way this file writes on a green path. Shape:
#
#   [lean-evidence]   · <arm>: <disposition> — <reason>
#
# STDOUT, one line, disposition drawn from the closed set above. `postdated` and `inert` have no
# call site here yet; they are the successors' and are declared now so the vocabulary is fixed
# rather than grown a word at a time by whoever emits next.
#
# An unknown disposition is an ENVIRONMENT error, not a printed line: a gate whose vocabulary can
# be widened at a call site has no closed vocabulary, and the reader that classifies these lines
# would silently start seeing a token it has no rule for.
inapplicable() { # inapplicable <arm> <disposition> <reason>
  case " $LEAN_OUTPUT_DISPOSITIONS " in
    *" $2 "*) : ;;
    *) envfail "internal: '$2' is not a class-(b) disposition (arm '$1'). The vocabulary is closed: $LEAN_OUTPUT_DISPOSITIONS." ;;
  esac
  echo "[lean-evidence]   · $1: $2 — $3"
}

# ---------------------------------------------------------------- arm cutoffs (#444)
# WHY AN ARM DECLARES A CUTOFF. An arm merged after a PR opened was enforced against that PR,
# whose build session had already finished and could not have satisfied a contract that did not
# yet exist. So an arm states the instant its contract took effect, and a run whose observation
# point precedes that instant is OUTSIDE the arm's window — `postdated`, class (b), zero
# violations — rather than in violation of it.
#
# AN EXPLICIT LITERAL, never derived from commit history. A derived date advances whenever the
# arm's lines are reformatted, moved or rebased, so it fails OPEN: every reformat silently
# exempts another tranche of runs. A literal only moves when someone edits it on purpose.
#
# ONLY ARMS THAT NEED ONE CARRY ONE. An arm whose contract predates every live branch has
# nothing to declare, and a cutoff on it would be a comparator with no reachable exemption.
#
# The cutoff is a fixed-width Z-normalized ISO-8601 instant, which is what makes plain string
# `<` an exact chronological compare — no `date -d` / `date -r`, whose GNU/BSD forms fail dirty
# under the other OS and would need a runtime split this file must not carry (bash 3.2).
# `PR_CREATED_AT` arrives already UTC from `github.event.pull_request.created_at`; the gate's
# sibling comparator normalizes a git author date instead, which is why the two are not one
# shared helper — see docs/testing.md, `lean ARM CUTOFFS` under *Couplings considered and declined*.
CUTOFF_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

# Echo the usable cutoff, or nothing when there is none to compare against. OR-1: a value that
# does not normalize is treated as ABSENT rather than promoted to an envfail — the malformed
# case can only arise from a hand-wired consumer workflow, and refusing there would red a PR
# over an input its committed workflow predates. It is NAMED on stderr, so the operator can see
# which of the two absent-shaped paths they are on rather than guessing.
PR_CREATED_AT_UTC=""
if [ -n "${PR_CREATED_AT:-}" ]; then
  if grep -qE "$CUTOFF_RE" <<<"$PR_CREATED_AT"; then
    PR_CREATED_AT_UTC="$PR_CREATED_AT"
  else
    echo "[lean-evidence] notice: PR_CREATED_AT ('$PR_CREATED_AT') is not a Z-normalized ISO-8601 instant, so it cannot be compared against an arm's 'since:'. Treating it as absent — every since-bearing arm will report 'postdated'." >&2
  fi
fi

# True when the run's observation point precedes the arm's cutoff — including when there IS no
# observation point, which is the AC-3 posture: an arm whose window cannot be established
# declines instead of enforcing a contract it cannot place the run inside of.
#
# `[[ < ]]` rather than `sort`/`awk`: it is a bash builtin present in 3.2, it forks nothing, and
# on two fixed-width Z-normalized instants a byte compare IS the chronological one.
postdated_against() { # postdated_against <since>
  [ -n "$PR_CREATED_AT_UTC" ] || return 0
  [[ "$PR_CREATED_AT_UTC" < "$1" ]]
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || envfail "not in a git repo — cannot resolve the committed artifacts."

# ---------------------------------------------------------------- config resolution (D-11)
# TWO callers with genuinely different sources, one rule. A CONSUMER commits
# .claude/second-shift.config.json (onboard Step 6), so its CI needs no constants at all and
# derives everything here. THIS repo gitignores its own config, so its CI has nothing to read
# and passes the prefixes as job-level env — the T0 residual the manifesto records. Env wins
# when set; the config is the fallback, never an override.
CONFIG="${SECOND_SHIFT_CONFIG:-$REPO_ROOT/.claude/second-shift.config.json}"
cfg() { # cfg <jq-filter> <default>
  local v
  if [ -f "$CONFIG" ] && command -v jq >/dev/null 2>&1; then
    v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
    if [ -n "$v" ] && [ "$v" != "null" ]; then echo "$v"; return 0; fi
  fi
  echo "$2"
}

# ONE NAMESPACE, ONE PREFIX (#413). The lean lane no longer cuts branches under a `lean/`
# namespace of its own — it uses `<tracker.branchPrefix><key>`, the staged lane's formula. So
# there is no lean prefix to derive, no pair to hold mutually non-prefix-matching, and no
# branch-shaped classification arm at all: what makes a PR lean is the committed spec in its
# own diff, which is what classify() below reads.
PIPELINE_PREFIX="${PIPELINE_BRANCH_PREFIX:-}"
[ -n "$PIPELINE_PREFIX" ] || PIPELINE_PREFIX="$(cfg '.tracker.branchPrefix' '')"
# Still fatal when unresolvable, for a NEW reason: the prefix is what lets classify() take the
# issue key off the branch instead of off the attacker-controllable PR body (D-14). A gate that
# silently fell back to the body would be reading the weaker source precisely when it could not
# tell it was doing so.
[ -n "$PIPELINE_PREFIX" ] \
  || envfail "neither PIPELINE_BRANCH_PREFIX nor a committed tracker.branchPrefix is resolvable — the key derivation reads the branch suffix and has nothing to strip. Set it on the job, or commit .claude/second-shift.config.json."

# A consumer's workflow may still set LEAN_BRANCH_PREFIX from a pin predating #413. Say so and
# carry on. NEVER an envfail: that would red every PR in every repo whose workflow still carries
# the constant, over a value that is now simply inert.
#
# On STDERR and not stdout, unlike this file's other announcements: `classify` writes a
# machine-readable `key=value` block that a delegating caller parses, and a prose line inside it
# is a contract violation waiting to be parsed as data. stderr reaches the same CI job log, so
# the notice is exactly as visible.
if [ -n "${LEAN_BRANCH_PREFIX:-}" ]; then
  echo "[lean-evidence] notice: LEAN_BRANCH_PREFIX ('$LEAN_BRANCH_PREFIX') is retired and ignored — lean classification is keyed on the committed spec, not on a branch namespace. Drop it from the workflow." >&2
fi

# Absent ⇒ github is a FAIL-SAFE, not a back-compat allowance, and matches lean-gate.sh's own
# default: github is the arm that DEMANDS the marker, so an unreadable config lands on the
# strict side. An unrecognized value is a loud error rather than a fall-through — a typo'd
# tracker.type silently taking the reduced-strength arm is precisely the waiver this refuses.
TRACKER_TYPE="${LEAN_TRACKER_TYPE:-}"
[ -n "$TRACKER_TYPE" ] || TRACKER_TYPE="$(cfg '.tracker.type' 'github')"
case "$TRACKER_TYPE" in
  github|jira) : ;;
  *) envfail "unknown tracker.type '$TRACKER_TYPE' — expected 'github' or 'jira'." ;;
esac

# BOT AVAILABILITY — what the identity arm actually depends on (#440). The tracker says whether
# there is an ISSUE to write to; the bot says whether there is an authenticated WRITER. Source
# control is GitHub under both adapters, so those are separate facts and the identity arm reads
# the second one. Resolution mirrors TRACKER_TYPE's: env first, then the committed config.
#
# THE DEFAULT IS TRACKER-DERIVED, and only for configs that declare no bot at all. Until #440,
# config-lint refused a `tracker.bot` block under jira, so "no block" means two different things
# depending on when and where the config was written: under jira it means "the lint left me no
# choice" (no writer — degrade, exactly as before), under github it means "unstated" and the
# strict reading stands, which is also where an unreadable config lands since TRACKER_TYPE
# itself defaults to github there. A config that DECLARES `enabled` is believed either way, and
# that is the only case whose behavior this change moves: jira + an enabled bot is now gated at
# full strength instead of waived.
BOT_ENABLED="${LEAN_BOT_ENABLED:-}"
if [ -z "$BOT_ENABLED" ]; then
  case "$TRACKER_TYPE" in
    jira) BOT_ENABLED="$(cfg '.tracker.bot.enabled' 'false')" ;;
    *)    BOT_ENABLED="$(cfg '.tracker.bot.enabled' 'true')" ;;
  esac
fi
case "$BOT_ENABLED" in
  true|false) : ;;
  *) envfail "unknown bot-enabled value '$BOT_ENABLED' — expected 'true' or 'false' from LEAN_BOT_ENABLED or tracker.bot.enabled." ;;
esac

# The shape a branch SUFFIX must have to be read as an issue key (D-14). Digits under github;
# the consumer's declared `tracker.keyPattern` under jira, matched case-insensitively because
# the lane lowercases the key when it builds the branch name.
case "$TRACKER_TYPE" in
  jira) KEY_RE="$(cfg '.tracker.keyPattern' '[A-Za-z]+-[0-9]+')" ;;
  *)    KEY_RE='[0-9]+' ;;
esac

# ---------------------------------------------------------------- the pinned name table
# Suffix-anchored at the END of the filename, never matched as substrings: `*-lean.md` must
# not match the verdict record (`*-lean-verdict.md`) or the render receipt
# (`*-lean-renders.md`), or the spec scan below would pick one of those and call it the spec.
# scripts/check-lean-chain.sh pins the identical set independently — it and this file are read
# by CI checkouts that can see no shared runtime config.
LEAN_SPEC_SUFFIX='-lean.md'
# The VERDICT suffix alone carries a lockstep marker, because it alone has a third holder
# outside this repo's reach: the consumer CI delta guard
# (plugins/second-shift/templates/consumer/second-shift-delta-guard.sh, #542) recognises the
# verdict-record commit by this exact suffix, and is COMMITTED INTO a consumer repo rather than
# fetched at the pinned ref. A one-sided rename leaves that guard classifying every verdict
# commit as an ordinary one — the lane simply runs in full, costing minutes and reporting
# nothing, so nothing would ever surface it. The other two suffixes have no such holder.
# LOCKSTEP-BEGIN lean-verdict-suffix
LEAN_VERDICT_SUFFIX='-lean-verdict.md'
# LOCKSTEP-END lean-verdict-suffix
LEAN_INTENT_GAP_SUFFIX='-lean-intent-gap.md'
# #613. Same suffix operator-override.sh's record_path() builds; the two are held apart only by
# this literal, exactly as the intent-gap suffix is.
LEAN_OVERRIDE_SUFFIX='-lean-override.md'

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

# ---------------------------------------------------------------- producer capabilities (#445)
# WHY AN ARM ASKS WHAT ITS PRODUCER SHIPS. These arms travel by GIT REF — a consumer's CI fetches
# this file at its pinned marketplace ref — while the producer that satisfies them (lean-gate.sh)
# travels by VERSIONED PLUGIN INSTALL into an operator's local cache. The two transports skew, and
# both trees report the same version, so no version-keyed check can observe it. An arm that landed
# before its producer shipped was enforced against runs whose build session had no way to satisfy
# it, and the run had no remedy: the artifact demanded did not exist in the harness that ran.
#
# So an arm may declare a CAPABILITY, and enforces only when the run's own evidence shows a
# producer generation that declares it. Absent that, the arm is INERT — class (b), zero
# violations — exactly as an out-of-window arm is `postdated`.
#
# THE STAMP RIDES THE CLAIM COMMENT, which every github generation posts including the pre-token
# one. That is what makes this non-circular. Reading it off the PR marker would be circular (the
# marker IS the artifact the one bound arm demands), and reading it off the VERDICT RECORD would
# let the reviewed party soften a build-side arm.
#
# The block below is shared with lean-gate.sh (the writer) and scripts/check-lean-chain.sh (which
# reads the claim tag for its own claim arm); see the writer for what each literal is for.
# LOCKSTEP-BEGIN lean-producer-capabilities
LEAN_CLAIM_MARKER_TAG='lean-claimed'
# shellcheck disable=SC2034  # each reader binds a SUBSET of these; the block is one contract.
LEAN_CAPABILITY_KEY='capabilities'
# shellcheck disable=SC2034  # ditto — unused here is the point, not an oversight.
LEAN_CAPABILITIES='pr-marker'
# LOCKSTEP-END lean-producer-capabilities

# Resolved ONCE per run, from the claim trail. Three outcomes the caller must keep apart:
#   declared-set  a bot-authored claim comment carries a stamp — CAPABILITY_STAMP is the UNION
#                 across every such comment (D-5). Intersection would let one stale pre-token
#                 claim permanently disarm the arm for the whole issue.
#   none          claim comments exist (or do not) and none carries a stamp ⇒ a pre-token
#                 producer.
#   unreadable    no trail could be obtained at all.
CAPABILITY_STAMP=""
CAPABILITY_STAMP_STATE=""
CAPABILITY_STAMP_WHY=""

# UNWINDOWED, matching the PR-marker arm's rule rather than check-lean-chain.sh's PR-open window:
# what is being read here is a property of the HARNESS, not a claim about who claimed first, and a
# window would hide a re-claim posted by the very generation whose capabilities are in question.
# The Bot trust filter still applies — an operator-posted stamp is not evidence of a harness.
# shellcheck disable=SC2016  # $author/$tag/$key are jq variables, bound with --arg.
CLAIM_STAMP_FILTER='
  [ .[]
    | select((.user.type // "") == "Bot")
    | select($author == "" or (.user.login // "") == $author)
    | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*" + $tag + "[[:space:]]*-->"))
  ]
  | map((.body // "") | capture($key + ":[[:space:]]*(?<c>[A-Za-z0-9._,-]+)").c? // "")
  | map(select(. != ""))
  | join(",")'

resolve_capability_stamp() {
  [ -n "$CAPABILITY_STAMP_STATE" ] && return 0
  local comments
  if [ -n "$ISSUE_COMMENTS_FILE" ]; then
    [ -f "$ISSUE_COMMENTS_FILE" ] || envfail "--issue-comments-file '$ISSUE_COMMENTS_FILE' does not exist."
    comments="$(cat "$ISSUE_COMMENTS_FILE")"
  elif [ -n "${GH_REPO:-}" ] && [ -n "$KEY" ]; then
    # A FAILED FETCH DECLINES, and this is the ONE fetch here that does not exit 2. The marker
    # fetch below waives an arm that would otherwise enforce, so failing open there is a
    # waiver; failing to establish a generation lands on the declining side by construction —
    # and making this fetch mandatory would red every consumer whose committed workflow grants
    # no `issues: read`, which is the same strand-an-innocent-PR defect this whole mechanism
    # exists to close. It is NAMED, never silent.
    comments="$("$GH_CLI" api "repos/$GH_REPO/issues/$KEY/comments" --paginate 2>&1)" || {
      CAPABILITY_STAMP_STATE="unreadable"
      CAPABILITY_STAMP_WHY="the claim trail for #$KEY could not be fetched (does this workflow grant 'issues: read'?): $(printf '%s' "$comments" | head -n1)"
      return 0
    }
  else
    CAPABILITY_STAMP_STATE="unreadable"
    CAPABILITY_STAMP_WHY="no claim trail is reachable — GH_REPO is unset and no --issue-comments-file was given"
    return 0
  fi
  printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 || {
    CAPABILITY_STAMP_STATE="unreadable"
    CAPABILITY_STAMP_WHY="the claim trail for #$KEY is not a JSON array"
    return 0
  }
  CAPABILITY_STAMP="$(printf '%s' "$comments" | jq -r \
    --arg author "${LEAN_MARKER_AUTHOR:-}" --arg tag "$LEAN_CLAIM_MARKER_TAG" --arg key "$LEAN_CAPABILITY_KEY" \
    "$CLAIM_STAMP_FILTER")"
  if [ -n "$CAPABILITY_STAMP" ]; then
    CAPABILITY_STAMP_STATE="declared-set"
  else
    CAPABILITY_STAMP_STATE="none"
  fi
  return 0
}

# The gate an arm calls before it enforces. Returns 0 to ENFORCE; 1 having already emitted the
# arm's single class-(b) `inert` line.
#
# AN UNKNOWN CAPABILITY IS AN ENVIRONMENT ERROR, never a decline — same posture as
# `inapplicable`'s closed disposition set. An arm asking for a token the shared vocabulary does
# not carry can never be armed by any producer, so it would sit inert forever while reading as a
# considered decline.
capability_gate() { # capability_gate <arm> <capability>
  case ",$LEAN_CAPABILITIES," in
    *",$2,"*) : ;;
    *) envfail "internal: '$2' is not in the closed capability vocabulary ('$LEAN_CAPABILITIES') (arm '$1'). An arm bound to a token no producer can stamp is permanently inert." ;;
  esac
  # AC-7. Under a read-only tracker there is NO claim comment — `cmd_claim` writes nothing to the
  # tracker at all — so no artifact both producer generations write exists there to carry a stamp.
  # Binding the arm to a stamp that can never be produced would disarm the strongest
  # merge-boundary arm permanently for that adapter, which is a strictly larger harm than the
  # transitional skew this closes. Such a consumer keeps the pre-#445 behavior, unchanged.
  [ "$TRACKER_TYPE" = "github" ] || return 0
  resolve_capability_stamp
  case "$CAPABILITY_STAMP_STATE" in
    declared-set)
      case ",$CAPABILITY_STAMP," in *",$2,"*) return 0 ;; esac
      inapplicable "$1" inert "this run's producer stamped '$LEAN_CAPABILITY_KEY: $CAPABILITY_STAMP' on its claim comment, and that generation does not declare '$2' — it cannot write the artifact this arm demands, so the arm is not evaluated and contributes no violation. Every other arm still gates."
      return 1 ;;
    none)
      inapplicable "$1" inert "no bot-authored '$LEAN_CLAIM_MARKER_TAG' comment on #$KEY carries a '$LEAN_CAPABILITY_KEY:' stamp, so this run's producer predates the stamp and cannot be shown to ship '$2'. The arm is not evaluated and contributes no violation; every other arm still gates."
      return 1 ;;
    *)
      inapplicable "$1" inert "the producer's generation cannot be established, so nothing shows whether it ships '$2' — $CAPABILITY_STAMP_WHY. The arm is not evaluated and contributes no violation; every other arm still gates."
      return 1 ;;
  esac
}

# Fixture paths are lean-shaped ON PURPOSE (the selftests need lean-looking files), so they
# must never make a PR applicable or be mistaken for a real artifact.
is_fixture_path() {
  case "$1" in
    */fixtures/*|*-fixtures/*|fixtures/*) return 0 ;;
    *) return 1 ;;
  esac
}

# The first non-fixture file in the tree whose basename ends `-<key><suffix>`.
find_artifact() { # find_artifact <key> <suffix>
  local f
  while IFS= read -r f; do
    is_fixture_path "${f#"$REPO_ROOT/"}" && continue
    case "$(basename "$f")" in *"-$1$2") echo "${f#"$REPO_ROOT/"}"; return 0 ;; esac
  done < <(find "$REPO_ROOT" -name "*$2" -type f 2>/dev/null)
  return 1
}

# FIRST-MATCH, never a count over the whole file. These records carry the reviewer's own prose
# below their header keys, and review prose discusses verdicts and ratification: a
# count-anywhere reader passes a record whose authoritative first line says otherwise.
record_key() { # record_key <key> <path> [charset]
  grep -oE "$1:[[:space:]]*${3:-[A-Za-z0-9._-]+}" "$2" 2>/dev/null \
    | head -n1 | sed -E "s/^$1:[[:space:]]*//"
}

# THE BRANCH'S OWN CONTRIBUTION, AS LINES (#597, D-2/D-3/D-4). The escape hatch this file's
# freshness arm consults when its naive check reds. It was held in lockstep with a second copy in
# lean-gate.sh until #720 deleted milestone 4's freshness arms; this is the only copy now, and the
# merge boundary is the only place the question is asked.
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
# THE CALLER OWNS THE rc=2 POLICY, not this function. D-5 points the live caller at fail-OPEN —
# the verdict stands, and the line says so — against every other unreadable-input path in this
# tool, which fail closed. That reversal is OR-1, and keeping it in the caller is what makes it a
# one-line flip rather than a rewrite.
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

# ---------------------------------------------------------------- classification
# FAILS CLOSED, and that is a consequence of #413 rather than a belt-and-braces addition. While a
# branch-namespace arm classified independently, an unreadable diff cost only the artifact arm and
# the prefix arm still spoke, so returning empty here was safe. That arm is gone: the scan below is
# the WHOLE classifier, and an empty file list is indistinguishable from "carries no lean spec" —
# a lean PR would then be reported non-applicable and waved through the merge boundary by the one
# gate that owns it. So the two conditions arm_freshness() already treats as environment errors are
# environment errors here too, on the same posture this file states twice: a check which cannot run
# must not report one.
changed_files() {
  if [ -n "$DIFF_FILES_FILE" ]; then
    [ -f "$DIFF_FILES_FILE" ] || envfail "--diff-files-file '$DIFF_FILES_FILE' does not exist."
    cat "$DIFF_FILES_FILE"
    return 0
  fi
  [ -n "${PR_BASE_REF:-}" ] \
    || envfail "PR_BASE_REF is unset or empty — the PR's changed-file list is the SOLE applicability input and cannot be computed without a base to diff against. Set it on the job, or pass --diff-files-file."
  local mb
  mb="$(git -C "$REPO_ROOT" merge-base "origin/$PR_BASE_REF" "${PR_HEAD_SHA:-HEAD}" 2>/dev/null)"
  [ -n "$mb" ] \
    || envfail "cannot resolve the merge-base of origin/$PR_BASE_REF and ${PR_HEAD_SHA:-HEAD} — a full-history checkout of the base is required (fetch-depth: 0). Classifying on a diff this gate cannot read would report 'not lean' for a lean PR."
  git -C "$REPO_ROOT" diff --name-only "$mb".."${PR_HEAD_SHA:-HEAD}" \
    || envfail "git diff --name-only $mb..${PR_HEAD_SHA:-HEAD} failed — the changed-file list is unreadable, and an unreadable list is not an empty one."
}

APPLICABLE=0
TRIGGER=""
SPEC_IN_DIFF=""
RESOLVED_KEY=""

# KEY FIRST, THEN THE ARTIFACT (#413, D-14). The order is load-bearing and it inverted here:
# with both lanes on one branch namespace, applicability can no longer be "some lean-shaped
# file is in the diff" — a staged PR that merely edits an older ticket's lean spec would then
# be pulled into this gate and out of the pipeline gate at the same time. What makes a PR lean
# is the spec for THIS PR's OWN key, so the key has to be resolved before the scan.
#
# The branch suffix is the PREFERRED source, and the PR body only the fallback. A body is
# attacker-controllable and carries closing keywords in prose; a first-match body scan on a
# prefixed branch therefore hands the gate a key the lane never worked on — the phantom-key
# class. The branch name is written by the harness, so on a prefixed branch it simply wins.
resolve_key() {
  local body
  # (a) the branch suffix, when the head ref is pipeline-prefixed and the suffix parses.
  case "$PR_HEAD_REF" in
    "$PIPELINE_PREFIX"*)
      local suffix="${PR_HEAD_REF#"$PIPELINE_PREFIX"}"
      if grep -qiE "^($KEY_RE)$" <<<"$suffix"; then
        RESOLVED_KEY="$suffix"
        return 0
      fi
      ;;
  esac
  # (b) the body. Reached for a hand-made branch outside the namespace — including every PR
  # opened on the retired `lean/` namespace, which is what keeps those classifying correctly
  # across the cutover. `Closes #N` wins over `Part of #N`: a program PR routinely carries
  # both, and a bare first-match would resolve to the epic. Under a read-only tracker the
  # reference is `Closes [KEY]` instead — both bracket shapes are read so the arms key on the
  # same artifact names under either adapter.
  body="${PR_BODY:-}"
  RESOLVED_KEY="$(printf '%s' "$body" | grep -oiE 'closes[[:space:]]+[#[]([A-Za-z]+-)?[0-9]+' | head -n1 | grep -oE '([A-Za-z]+-)?[0-9]+$' || true)"
  if [ -z "$RESOLVED_KEY" ]; then
    RESOLVED_KEY="$(printf '%s' "$body" | grep -oiE 'part[[:space:]]+of[[:space:]]+[#[]([A-Za-z]+-)?[0-9]+' | head -n1 | grep -oE '([A-Za-z]+-)?[0-9]+$' || true)"
  fi
}

classify() {
  [ -n "${PR_HEAD_REF:-}" ] || envfail "PR_HEAD_REF is unset or empty — nothing to classify."

  resolve_key

  # Two scans in one pass. KEY_SPEC is the spec for THIS PR's key and is what applicability
  # turns on. ANY_SPEC is any other lean spec in the diff, kept for two distinct jobs below —
  # neither of them "classify on it".
  # Resolved in THIS shell, never in a `< <(changed_files)` process substitution: that runs the
  # producer in a subshell, where an envfail's exit is swallowed and the reader sees a clean EOF —
  # the exact fail-open shape the function above was just closed against.
  local files
  files="$(changed_files)" || exit $?

  local f key_spec="" any_spec=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_fixture_path "$f" && continue
    case "$f" in
      *"$LEAN_VERDICT_SUFFIX") continue ;;                # the verdict record is not the spec
    esac
    case "$f" in
      *"$LEAN_SPEC_SUFFIX") [ -n "$any_spec" ] || any_spec="$f" ;;
      *) continue ;;
    esac
    if [ -n "$RESOLVED_KEY" ]; then
      case "$f" in *"-$RESOLVED_KEY$LEAN_SPEC_SUFFIX") key_spec="$f"; break ;; esac
    fi
  done <<< "$files"

  if [ -n "$RESOLVED_KEY" ]; then
    # THE SOLE ARM, and non-vacuous by construction. There is no branch-shaped arm left and
    # none is wanted: the namespace no longer distinguishes the lanes, so a namespace arm would
    # classify every staged PR as lean. Keying it to the PR's own issue is what stops the
    # mirror error — a staged PR that merely edits some OLDER ticket's lean spec is not lean.
    SPEC_IN_DIFF="$key_spec"
    if [ -n "$key_spec" ]; then
      APPLICABLE=1
      TRIGGER="lean-artifact ($key_spec)"
    else
      # Declined, but say what was seen: "a lean spec is present and it is not yours" is the
      # one decline an operator will want to argue with.
      SPEC_IN_DIFF="$any_spec"
    fi
    return 0
  fi

  # NO KEY. A prefixed branch always resolves one from its own suffix, so arriving here means a
  # hand-made branch outside the namespace (or one whose suffix does not parse). If such a
  # branch nonetheless commits a lean spec, it is lean work with no traceable source issue —
  # APPLICABLE, so the caller refuses it and demands the reference. Declining instead would
  # exempt it from this gate while the pipeline gate exempts it for not being prefixed, and a
  # PR both gates wave through is the hole the whole boundary exists to close.
  if [ -n "$any_spec" ]; then
    SPEC_IN_DIFF="$any_spec"
    APPLICABLE=1
    TRIGGER="lean-artifact ($any_spec)"
  fi
  return 0
}

# ---------------------------------------------------------------- arm 1: the verdict record
VERDICT=""
VERDICT_VALUE=""
VERDICT_RUN_ID=""
VERDICT_SESSION_ID=""
VERDICT_REVIEWED_PATCH_ID=""
VERDICT_REVIEWED_HEAD=""

load_verdict() {
  VERDICT="$(find_artifact "$KEY" "$LEAN_VERDICT_SUFFIX")" || VERDICT=""
  [ -n "$VERDICT" ] || return 1
  # `verdict=` is written with `=`, not `:` — read it directly rather than through record_key,
  # which builds a `<key>:` pattern. Same first-match discipline.
  VERDICT_VALUE="$(grep -oE 'verdict=[A-Za-z-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/^verdict=//')"
  # `session_id:` does not contain the substring `run_id:`, and `reviewed_patch_id:` is a
  # different string from either, so none of these extractions can capture another's value.
  VERDICT_RUN_ID="$(record_key run_id "$REPO_ROOT/$VERDICT")"
  VERDICT_SESSION_ID="$(record_key session_id "$REPO_ROOT/$VERDICT")"
  VERDICT_REVIEWED_PATCH_ID="$(record_key reviewed_patch_id "$REPO_ROOT/$VERDICT")"
  # #597 D-2. `reviewed_head:` is read here rather than added as a NEW key precisely because it is
  # not new — it has been in LEAN_VERDICT_HEADER_KEYS since #372, so every in-flight and every
  # already-merged record already carries it and none of them needs a re-stamp for this boundary to
  # gain the escape hatch. `reviewed_patch_id:` does not contain the substring `reviewed_head:`.
  VERDICT_REVIEWED_HEAD="$(record_key reviewed_head "$REPO_ROOT/$VERDICT")"
  return 0
}

arm_verdict() {
  if [ -z "$VERDICT" ]; then
    note_violation "no committed verdict record (a file named *-$KEY$LEAN_VERDICT_SUFFIX). The independent review's verdict must be a committed, diffable artifact — a local progress-file line is not evidence."
    return 0
  fi
  if [ "$VERDICT_VALUE" != "approve" ]; then
    note_violation "verdict record '$VERDICT' reads 'verdict=${VERDICT_VALUE:-<none>}', not 'verdict=approve'."
  fi
  [ -n "$VERDICT_RUN_ID" ] \
    || note_violation "verdict record '$VERDICT' carries no run_id reconciliation key, so its authorship cannot be separated from the build run's."
  [ -n "$VERDICT_SESSION_ID" ] \
    || note_violation "verdict record '$VERDICT' carries no session_id reconciliation key — the review session that produced it cannot be located, so nothing outside the record itself attests the review ran."
}

# ---------------------------------------------------------------- arm 2: authorship (P10)
# TRUST FILTER, load-bearing on any public repo: PR comments are writable by any account, so
# the raw trail is not the harness-written record this reasons about. `.user.type == "Bot"` is
# the filter, optionally narrowed to an exact login. Measured on the sibling gate: the bot posts
# with author_association CONTRIBUTOR, so an OWNER/MEMBER allowlist would exclude the bot itself.
#
# NOT WINDOWED, unlike check-lean-chain.sh's issue-side claim arm. That arm windows at PR-open
# so a later re-claim cannot retroactively red an already-green PR; here the opposite is wanted.
# Every marker ever posted to this PR must be compared, because a SECOND build session — the
# case D-4 exists for — posts its marker after PR-open, and a window would hide exactly the
# session whose independence is in question.
# shellcheck disable=SC2016  # $author/$tag are jq variables, bound with --arg; shell must not expand them.
MARKER_FILTER='
  [ .[]
    | select((.user.type // "") == "Bot")
    | select($author == "" or (.user.login // "") == $author)
    | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*" + $tag + "[[:space:]]*-->"))
  ]'

# The instant this arm's contract took effect (#444). Anchored to `ca269a9` — "consumer-side
# lean chain gate, evidence ships as plugin payload (#430)", the merge that first made a
# bot-authored PR marker a merge-boundary requirement. Committed `2026-08-08T17:05:13Z`; the
# literal is deliberately ONE SECOND LATER and must not be "corrected" to `:13`. The comparison
# below is at-or-after, so `:14` exempts the merge's own second and makes the following second
# the first enforced one — `:13` would enforce against a PR opened in the same second the
# contract landed, which is the race the cutoff exists to remove.
LEAN_IDENTITY_SINCE='2026-08-08T17:05:14Z'

arm_identity() {
  # BEFORE the bot test, not after (D-4). A run that is both pre-cutoff and bot-less is
  # `postdated`, not `reduced-strength`: it is outside this arm's contract window at all, which
  # holds no matter how the consumer is configured, whereas `reduced-strength` would report a
  # permanent non-applicability as a fixable config gap and send the operator to configure a bot
  # that changes nothing for this PR.
  if postdated_against "$LEAN_IDENTITY_SINCE"; then
    inapplicable identity postdated "this arm's contract took effect at $LEAN_IDENTITY_SINCE, and this PR's open instant (${PR_CREATED_AT_UTC:-<no usable PR_CREATED_AT>}) precedes it — the build session that opened it finished before the marker was required and could not have posted one. The arm is not evaluated and contributes no violation; every other arm still gates."
    return 0
  fi
  if [ "$BOT_ENABLED" != "true" ]; then
    inapplicable identity reduced-strength "no bot is enabled for this consumer (tracker.bot.enabled is false, or absent under tracker.type 'jira'), so it has no authenticated writer and any PR marker it posted would fail the Bot trust filter. The verdict's independence is NOT checked here; every other arm still gates. Configuring a bot restores this arm under either tracker."
    return 0
  fi
  # AFTER both exemptions above and BEFORE the verdict short-circuit (#445). After, because
  # `postdated` and `reduced-strength` are cheaper answers to the same question and D-6 fixes
  # `since:` as the first evaluation — an exempt run pays no issue fetch. Before, because "the
  # producer that ran could not post a marker" is true whether or not a verdict record exists,
  # and an arm that reported it only on runs which got as far as a verdict would go quiet on
  # exactly the runs an operator is triaging.
  capability_gate identity pr-marker || return 0
  [ -n "$VERDICT" ] || return 0   # already a violation; "authorship unverifiable" on top is noise

  local comments
  if [ -n "$PR_COMMENTS_FILE" ]; then
    [ -f "$PR_COMMENTS_FILE" ] || envfail "--pr-comments-file '$PR_COMMENTS_FILE' does not exist."
    comments="$(cat "$PR_COMMENTS_FILE")"
  else
    [ -n "${PR_NUMBER:-}" ] || envfail "PR_NUMBER is unset — cannot fetch the PR's marker trail."
    [ -n "${GH_REPO:-}" ]   || envfail "GH_REPO is unset — cannot fetch the PR's marker trail."
    # A failed fetch is an ENVIRONMENT error, never a silent pass: failing open here would
    # waive the whole arm on any rate limit or transient 5xx.
    comments="$("$GH_CLI" api "repos/$GH_REPO/issues/$PR_NUMBER/comments" --paginate 2>&1)" || {
      echo "[lean-evidence] marker fetch failed for PR #$PR_NUMBER:" >&2
      printf '%s\n' "$comments" >&2
      exit 2
    }
  fi
  printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || envfail "PR comment trail is not a JSON array — cannot reconcile."

  local n_markers marker_runs marker_sessions
  n_markers="$(printf '%s' "$comments" | jq -r --arg author "${LEAN_MARKER_AUTHOR:-}" --arg tag "$LEAN_PR_MARKER_TAG" \
    "$MARKER_FILTER | length")"
  if [ "${n_markers:-0}" -lt 1 ]; then
    local any
    any="$(printf '%s' "$comments" | jq -r --arg tag "$LEAN_PR_MARKER_TAG" \
      '[ .[] | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*" + $tag + "[[:space:]]*-->")) ] | length')"
    if [ "${any:-0}" -gt 0 ]; then
      note_violation "found $any '$LEAN_PR_MARKER_TAG' comment(s) on this PR, but none bot-authored. An operator-posted marker is not evidence the harness ran, and it is trivially forgeable by anyone who can comment."
    else
      note_violation "no bot-authored '$LEAN_PR_MARKER_TAG' comment on this PR, so the BUILD run's identity is unknown and the verdict's independence is uncheckable. The build harness posts one when it opens the PR."
    fi
    return 0
  fi

  marker_runs="$(printf '%s' "$comments" | jq -r --arg author "${LEAN_MARKER_AUTHOR:-}" --arg tag "$LEAN_PR_MARKER_TAG" \
    "$MARKER_FILTER"' | map((.body // "") | capture("run_id:[[:space:]]*(?<r>[A-Za-z0-9._-]+)").r? // "") | map(select(. != "")) | .[]')"
  marker_sessions="$(printf '%s' "$comments" | jq -r --arg author "${LEAN_MARKER_AUTHOR:-}" --arg tag "$LEAN_PR_MARKER_TAG" \
    "$MARKER_FILTER"' | map((.body // "") | capture("session_id:[[:space:]]*(?<r>[A-Za-z0-9._-]+)").r? // "") | map(select(. != "" and . != "unset")) | .[]')"

  if [ -z "$marker_runs" ]; then
    note_violation "the bot-authored '$LEAN_PR_MARKER_TAG' comment(s) on this PR carry no run_id, so the build run's identity is unknown and the verdict's independence is uncheckable."
    return 0
  fi

  # EVERY marker, not the first (D-4). A second build session on the same PR posts its own
  # marker; comparing only the first would let that session author its own review verdict.
  local m
  for m in $marker_runs; do
    [ "$m" = "$VERDICT_RUN_ID" ] || continue
    note_violation "verdict record '$VERDICT' carries a BUILD run's identity ('$m') — a session that wrote code on this PR also wrote its own review verdict. The verdict must come from a separate review session carrying its own identity."
  done
  for m in $marker_sessions; do
    [ "$m" = "$VERDICT_SESSION_ID" ] || continue
    # The STRONGER of the two comparisons, and why the marker carries a session id at all:
    # run_id is agent-CHOSEN, so a build session determined to review itself need only pick a
    # second string, whereas the session id is harness-assigned.
    note_violation "verdict record '$VERDICT' names a BUILD session ('$m') as its author — a distinct run_id does not make it an independent review (P10)."
  done
  return 0
}

# ---------------------------------------------------------------- arm 3: freshness
arm_freshness() {
  [ -n "$VERDICT" ] || return 0   # already a violation

  # VACUITY. "Fresh" is a claim about an APPROVE — a needs-work record is neither stale nor
  # fresh, because there is nothing for the arm to certify either way. Short-circuit before any
  # patch-id computation runs.
  #
  # ONE FACT, ONE VIOLATION. The verdict arm states this same fact, so on any invocation that
  # ran it — including the default `all`, which is how a consumer's CI calls this — restating it
  # here would count one fact twice and inflate the "N evidence artifact(s) missing" total.
  # Silent then. Running ALONE (`--arms freshness`) nothing else has said it, and returning with
  # no refusal at all would report a vacuous pass, so there it is counted.
  if [ "$VERDICT_VALUE" != "approve" ]; then
    case ",$ARMS," in
      *,verdict,*) : ;;
      *) note_violation "verdict record '$VERDICT' reads 'verdict=${VERDICT_VALUE:-<none>}', not 'verdict=approve' — freshness is undefined for a non-approve record, so the patch-id arm is not evaluated." ;;
    esac
    return 0
  fi
  if [ -z "$VERDICT_REVIEWED_PATCH_ID" ]; then
    note_violation "verdict record '$VERDICT' declares no reviewed_patch_id, so nothing states which tree the review actually read. Re-run the review round: '/dev-pipeline:review-lean <pr>'."
    return 0
  fi
  [ -n "${PR_HEAD_SHA:-}" ] \
    || envfail "PR_HEAD_SHA is unset or empty — the freshness check has nothing to measure the verdict against, and 'a verdict exists' is not 'this head was approved'."
  [ -n "${PR_BASE_REF:-}" ] \
    || envfail "PR_BASE_REF is unset or empty — the branch's patch identity cannot be recomputed without a base to measure from."
  git -C "$REPO_ROOT" cat-file -e "$PR_HEAD_SHA^{commit}" 2>/dev/null \
    || envfail "PR_HEAD_SHA '$PR_HEAD_SHA' is not a commit in this checkout — a check that cannot run must not report a pass."

  # ONE guard over the whole computation, not one per step. `git patch-id` prints NOTHING for
  # an empty diff, so two failed computations compare EQUAL and an unguarded reader prints its
  # ✓ having hashed nothing. An unresolvable merge-base and an empty measured range both surface
  # as an empty id, and splitting them produces an arm no case can kill.
  local cur
  cur="$(git -C "$REPO_ROOT" diff "$(git -C "$REPO_ROOT" merge-base "origin/$PR_BASE_REF" "$PR_HEAD_SHA" 2>/dev/null)" \
    "$PR_HEAD_SHA" -- . ":(exclude)$VERDICT" 2>/dev/null \
    | git -C "$REPO_ROOT" patch-id --stable 2>/dev/null | cut -d' ' -f1)"
  if [ -z "$cur" ]; then
    envfail "cannot compute this branch's patch identity against origin/$PR_BASE_REF — the merge-base is unresolvable (a full-history checkout of the base is required: fetch-depth: 0), or the branch's diff excluding '$VERDICT' is empty. Either way there is nothing to compare the verdict's reviewed_patch_id against."
  elif [ "$cur" != "$VERDICT_REVIEWED_PATCH_ID" ]; then
    # THE ESCAPE HATCH, AT THE BOUNDARY (#597 D-4). Without it milestone 4 passes and this job still
    # reds on the identical base merge — which is exactly what forced the #583 re-stamp — so AC-1
    # would be true in the lane and false at merge time. `fetch-depth: 0` is already this job's
    # checkout, and `reviewed_head` is an ancestor of the PR head, so both sides are resolvable here.
    local delta drc
    delta="$(contribution_delta "$REPO_ROOT" "origin/$PR_BASE_REF" "$VERDICT_REVIEWED_HEAD" "$PR_HEAD_SHA" "$VERDICT")"
    drc=$?
    case "$drc" in
      1) note_violation "verdict record '$VERDICT' reviewed patch $(printf '%.12s' "$VERDICT_REVIEWED_PATCH_ID"), but this branch's diff against origin/$PR_BASE_REF now hashes to $(printf '%.12s' "$cur") and the branch's own lines moved with it: $(printf '%s\n' "$delta" | contribution_summary). Content changed after the review — a commit landed, or a conflict was resolved by altering a line — so the review read a different tree than the one being merged. Run another review round." ;;
      0) echo "[lean-evidence] notice: freshness — the recorded patch identity $(printf '%.12s' "$VERDICT_REVIEWED_PATCH_ID") and this head's $(printf '%.12s' "$cur") differ, which a base advance alone is enough to cause, and every one of the branch's own +/- lines is unchanged since reviewed_head $(printf '%.12s' "$VERDICT_REVIEWED_HEAD") — no reviewed line was altered, so the verdict stands (#597 AC-1)." >&2 ;;
      *) inapplicable freshness reduced-strength "the patch identity moved from $(printf '%.12s' "$VERDICT_REVIEWED_PATCH_ID") to $(printf '%.12s' "$cur") and the +/- comparison could NOT be computed, so this arm FAILED OPEN and the verdict stands (#597 D-5/OR-1). It is the one unreadable-input path in this file that does not fail closed; reverse it by treating that case as a violation here and in lean-gate.sh's milestone 4." ;;
    esac
  fi
}

# ---------------------------------------------------------------- arm 4: ratification (P9)
# RATIFICATION AND NOTHING ELSE. The record's disposition is deliberately not re-validated
# against the receipt's enum — that enum is single-sited in ledger-lint.sh, and a second copy
# here would be the duplicate machinery the lockstep manifest calls worse than none.
arm_intent_gap() {
  local gap ratified by
  # ABSENCE IS CLASS (a), not class (b) (#443). Most runs surface no gap, and "the receipt already
  # covered everything" is a SATISFIED arm — nothing went unevaluated. It used to be printed so a
  # log reader could tell it from "the arm never ran"; that distinction now rides the fact that a
  # class-(b) line would be there if the arm could not run.
  gap="$(find_artifact "$KEY" "$LEAN_INTENT_GAP_SUFFIX")" || gap=""
  [ -n "$gap" ] || return 0
  # `ratified_by:` cannot be captured by the `ratified:` read — the character after `ratified`
  # is `_`, not `:`.
  ratified="$(record_key ratified "$REPO_ROOT/$gap" '[A-Za-z]+')"
  by="$(record_key ratified_by "$REPO_ROOT/$gap" 'https://[^[:space:]]+')"
  if [ "$ratified" != "yes" ]; then
    note_violation "intent-gap record '$gap' reads 'ratified: ${ratified:-<none>}' — a decision the receipt never covered is still the build run's own call, and P9 routes it back to the human before it merges. Ratify it and record the comment URL as 'ratified_by:'."
  elif [ -z "$by" ]; then
    note_violation "intent-gap record '$gap' claims 'ratified: yes' but cites no 'ratified_by:' URL — a ratification the run wrote about itself is a self-ratification. Cite the operator's comment."
  fi
}

# ---------------------------------------------------------------- arm 5: operator overrides (#613)
# THE YIELD'S EVIDENCE, checked at the boundary. A gate that yielded to an attended operator did
# so on the strength of a record quoting that operator's answer; this is where the record is held
# to its own schema, so a run cannot yield on an artifact nobody could read afterwards.
#
# WHAT THIS ARM DOES NOT DO. It does not re-decide whether the yield was WARRANTED — that is the
# reviewer's call, and the whole point of committing the record is that a human can repudiate it
# in the PR. Nor does it evaluate the PERSISTENT register's expiry: that needs a tracker read, and
# the gate that consults a row is both where the read is cheap and where the refusal is
# actionable. Here the record's own `expiry: run` is validated, which is AC-5's subject.
#
# #709 AC-4: it ALSO resolves a verdict's `fidelity: not-applicable (override: <ref>)` claim
# against this same record — a design-disarm yield the writer cannot commit without a validated
# override (D-1), so a ref that resolves to nothing is evidence of exactly the tamper this arm
# exists to catch, whether or not any override record is committed at all.
#
# Absence is class (a): most runs record no override at all.
# LOCKSTEP-BEGIN override-record-reader verbatim
# The CLOSED enums. Widening either is the phase-2 work #613 defers, and an unknown value is an
# ERROR rather than a silent miss: a gate name nobody implements must not read as "no override
# exists", which is the fail-open this whole mechanism is built against.
#
# `design-disarm` (#709): a per-ticket `Design: none` disarm on a repo configured with
# design.provider is a build-session-writable opt-out of the mandatory render lane, which #705's
# decisions forbid without an operator-quoted override. It is NOT region-scoped (issue-scoped
# only, like `intake-unqueued`) and is FORBIDDEN in the persistent register — see
# register_row_violation() below, operator-override.sh-only since the register is per-tool.
OVERRIDE_GATES='intake-unqueued spec-open-region design-disarm'
OVERRIDE_SCOPES='intake-attestation open-region-resolution design-disarm'

# The gate that is region-scoped. A region is REQUIRED for it and forbidden for the other: an
# open-region override that named no region would clear every region on the ticket at once.
OVERRIDE_REGION_SCOPED_GATE='spec-open-region'

# The register is at a FIXED path, deliberately unlike every other artifact here. The merge
# boundary reads it and the merge boundary has no config — the same reasoning check-lean-chain.sh
# already applies to its own constants.
OVERRIDE_REGISTER_REL='.claude/lean-overrides.tsv'

override_in_enum() { # override_in_enum <value> <space-separated set>
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

# Every block, one TAB-separated line, keys read FIRST-MATCH WITHIN THE BLOCK. Per-block and not
# per-file because one run can yield at two different gates, and a single file-wide first-match
# header could only ever name one of them.
#
# `answers` counts non-empty quoted lines under `### Operator answer`: a record whose quote is
# missing is a decision nobody stated, which is the thing this record exists to carry.
#
# THE SEPARATOR IS \037, NOT A TAB, and that is a correctness fix rather than a taste one. Tab is
# an IFS-WHITESPACE character in bash, so `IFS=<tab> read` collapses a run of them into ONE
# delimiter: an empty middle field silently shifts every field after it, and the reader then
# reports a violation about the wrong key. Measured on the first draft — a record with an empty
# `run_id:` was reported as carrying `expiry: 1`.
override_parse_blocks() { # override_parse_blocks <file>
  [ -f "$1" ] || return 0
  awk '
    function flush() {
      if (!inblk) return
      printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", g, sc, is, rg, ri, si, ex, (dc == "" ? 0 : 1), ans
    }
    function reset() { g=""; sc=""; is=""; rg=""; ri=""; si=""; ex=""; dc=""; ans=0; inans=0 }
    /^##[[:space:]]+Override[[:space:]]/ { flush(); reset(); inblk=1; next }
    !inblk { next }
    /^###[[:space:]]+Operator answer[[:space:]]*$/ { inans=1; next }
    /^###[[:space:]]/ { inans=0 }
    inans && /^>[[:space:]]*[^[:space:]]/ { ans++ }
    inans { next }
    {
      if (match($0, /^[a-z_]+:[[:space:]]*/)) {
        k = substr($0, 1, index($0, ":") - 1)
        v = substr($0, RLENGTH + 1)
        sub(/[[:space:]]+$/, "", v)
        if (k == "gate"       && g  == "") g  = v
        if (k == "scope"      && sc == "") sc = v
        if (k == "issue"      && is == "") is = v
        if (k == "region"     && rg == "") rg = v
        if (k == "run_id"     && ri == "") ri = v
        if (k == "session_id" && si == "") si = v
        if (k == "expiry"     && ex == "") ex = v
        if (k == "decision"   && dc == "") dc = v
      }
    }
    END { flush() }
  ' "$1"
}

# One rule set, two callers: `check` uses it to decide MALFORMED (rc 2), `lint` to count
# violations. A second copy would be two answers to "is this record well-formed", and the merge
# boundary's answer is the one that has to match the gate's.
override_block_violation() { # override_block_violation <tsv-line> — prints a reason, or nothing when clean
  local g sc is rg ri si ex dc ans
  IFS="$(printf '\037')" read -r g sc is rg ri si ex dc ans <<EOF
$1
EOF
  override_in_enum "$g" "$OVERRIDE_GATES"   || { echo "gate '${g:-<none>}' is not one of: $OVERRIDE_GATES"; return; }
  override_in_enum "$sc" "$OVERRIDE_SCOPES" || { echo "scope '${sc:-<none>}' is not one of: $OVERRIDE_SCOPES"; return; }
  # THE KEY SHAPE IS THE TRACKER'S, NOT GITHUB'S. This was `[!0-9]` — numbers only — which made
  # the whole mechanism unreachable under a non-numeric tracker: a jira consumer's key never
  # matches, so `record` refused every override and the gate's own printed remedy named an
  # argument its tool would reject. The reader cannot ask a config which shape to expect (the
  # merge boundary parses this same block with no config), so the class is widened to the one
  # every adapter's keys already live in rather than derived per tracker.
  # STILL CLOSED, and deliberately: `/` stays out, because `issue` is interpolated into the
  # record's path, and the empty case stays a violation.
  case "$is" in ''|*[!0-9A-Za-z._-]*) echo "issue '${is:-<none>}' is not a ticket key"; return ;; esac
  if [ "$g" = "$OVERRIDE_REGION_SCOPED_GATE" ]; then
    case "$rg" in
      OR-[0-9]*) : ;;
      *) echo "gate '$g' is region-scoped but region reads '${rg:-<none>}' — an override naming no region would clear every open region on the ticket at once"; return ;;
    esac
  elif [ "$rg" != "none" ]; then
    echo "gate '$g' is not region-scoped, so region must read 'none', not '${rg:-<none>}'"; return
  fi
  [ -n "$ri" ] || { echo "run_id is empty — the override binds to run identity"; return; }
  [ -n "$si" ] || { echo "session_id is empty — nothing names the session that recorded it"; return; }
  [ "$ex" = "run" ] || { echo "expiry '${ex:-<none>}' — a per-issue record carries only 'run'; a persistent override belongs in $OVERRIDE_REGISTER_REL with an explicit expiry"; return; }
  [ "$dc" = "1" ] || { echo "decision is empty"; return; }
  [ "${ans:-0}" -ge 1 ] || { echo "no quoted operator answer under '### Operator answer' — a decision nobody stated is not an override"; return; }
}
# LOCKSTEP-END override-record-reader

# The `fidelity:` value, read WHOLE and header-anchored — the same shape check-lean-chain.sh's
# `panel_key` is, and for the same reason: `header_key`'s charset stops at the first character
# outside [A-Za-z0-9._-], so a suffixed value ("not-applicable (override: 709#1)") truncates to
# its bare enum word there — exactly what every OTHER fidelity: reader wants (#709 D-4), since
# widening the shared reader for one key would change how every key in the schema is read. This
# is private to this file's single caller below, which needs the ref past the parenthesis.
fidelity_key() { # fidelity_key   (record on stdin)
  awk '
    /^[A-Za-z_][A-Za-z0-9_]*[:=]/ { hdr = 1 }
    hdr && /^[[:space:]]*$/       { exit }
    hdr && /^fidelity:/ {
      sub(/^fidelity:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      printf "%s", $0
      exit
    }
  '
}

arm_override() {
  local rec line why vfid ref idx blk_g blk_is found

  # #709 AC-4/D-4. Independent of the well-formedness sweep below, and evaluated even when NO
  # override record is committed at all: a verdict claiming `fidelity: not-applicable (override:
  # <ref>)` is a claim of a design-disarm YIELD, and the ref must resolve to an actual
  # design-disarm block for THIS issue — a record entirely absent and a fidelity line citing one
  # anyway are the same defect this arm exists to catch, an artifact the boundary is asked to
  # trust that it cannot verify. `<ref>` ordinals are counted over EVERY block in the record, in
  # file order, matching `operator-override.sh check --print-ref`'s own numbering — the ref names
  # the block's position, not its gate-scoped rank.
  if [ -n "$VERDICT" ]; then
    vfid="$(fidelity_key < "$REPO_ROOT/$VERDICT")"
    case "$vfid" in
      *"(override: "*")")
        ref="${vfid#*override: }"; ref="${ref%)}"
        found=0
        rec="$(find_artifact "$KEY" "$LEAN_OVERRIDE_SUFFIX")" || rec=""
        if [ -n "$rec" ]; then
          idx=0
          while IFS= read -r line; do
            [ -n "$line" ] || continue
            idx=$((idx + 1))
            IFS="$(printf '\037')" read -r blk_g _ blk_is _ <<EOF
$line
EOF
            if [ "$blk_g" = "design-disarm" ] && [ "$blk_is" = "$KEY" ] && [ "${KEY}#${idx}" = "$ref" ]; then
              found=1; break
            fi
          done <<EOF
$(override_parse_blocks "$REPO_ROOT/$rec")
EOF
        fi
        [ "$found" -eq 1 ] \
          || note_violation "verdict record '$VERDICT' reads 'fidelity: $vfid', citing design-disarm override ref '$ref', but no committed override record for #$KEY carries a design-disarm block at that ref. A fidelity claim citing an override must resolve to the record it names."
        ;;
    esac
  fi

  rec="$(find_artifact "$KEY" "$LEAN_OVERRIDE_SUFFIX")" || rec=""
  [ -n "$rec" ] || return 0
  if [ -z "$(override_parse_blocks "$REPO_ROOT/$rec")" ]; then
    note_violation "override record '$rec' declares no '## Override n' block — a record with no override in it is not evidence of anything, and something wrote it."
    return 0
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    why="$(override_block_violation "$line")"
    [ -z "$why" ] || note_violation "override record '$rec': $why. A gate yielded on this record; it has to be readable by the boundary that is being asked to trust it."
  done <<EOF
$(override_parse_blocks "$REPO_ROOT/$rec")
EOF
}

# ---------------------------------------------------------------- dispatch
emit_count() {
  [ -n "$VIOLATIONS_FILE" ] || return 0
  printf '%s' "$violations" > "$VIOLATIONS_FILE"
}

run_arms() {
  [ -n "$KEY" ] || envfail "check: --key is required (or use 'all', which resolves it)."
  load_verdict || VERDICT=""
  case ",$ARMS," in *,verdict,*)     arm_verdict ;; esac
  case ",$ARMS," in *,identity,*)    arm_identity ;; esac
  case ",$ARMS," in *,freshness,*)   arm_freshness ;; esac
  case ",$ARMS," in *,intent-gap,*)  arm_intent_gap ;; esac
  case ",$ARMS," in *,override,*)    arm_override ;; esac
  emit_count
  if [ "$violations" -gt 0 ]; then
    echo "[lean-evidence] ✗ $violations evidence artifact(s) missing for the lean PR on #$KEY." >&2
    echo "[lean-evidence]   The remedy is producing the missing artifact — there is no waiver." >&2
    return 1
  fi
  return 0
}

case "$SUB" in
  classify)
    classify
    echo "applicable=$APPLICABLE"
    echo "trigger=$TRIGGER"
    echo "key=$RESOLVED_KEY"
    echo "spec_in_diff=$SPEC_IN_DIFF"
    exit 0
    ;;
  check)
    run_arms
    exit $?
    ;;
  all)
    classify
    if [ "$APPLICABLE" -eq 0 ]; then
      # CLASS (b): the whole gate could not evaluate. One line, and it carries what was resolved
      # inside its reason — a decline is otherwise indistinguishable from "never ran", and the two
      # reasons a decline can have (no key, or no key-matched spec) are the two things an operator
      # needs to tell apart before arguing a misclassification.
      inapplicable lean-evidence not-applicable "non-lean change on head branch '${PR_HEAD_REF:-<unset>}' — resolved key: ${RESOLVED_KEY:-<none>} (pipeline prefix: $PIPELINE_PREFIX), and no lean spec for it is in this PR's diff."
      exit 0
    fi
    # Reachable only on a branch outside the namespace: this PR commits a lean spec and names
    # no issue, so there is nothing to reconcile the evidence against. A refusal, never a
    # waiver — see classify()'s NO KEY note.
    [ -n "$RESOLVED_KEY" ] || {
      echo "[lean-evidence]   ✗ PR body carries no resolvable issue reference ('Closes #N' or 'Closes [KEY]') and the head branch '$PR_HEAD_REF' is outside the configured namespace, but this PR commits a lean spec. Add the reference." >&2
      exit 1
    }
    KEY="$RESOLVED_KEY"
    run_arms
    exit $?
    ;;
esac

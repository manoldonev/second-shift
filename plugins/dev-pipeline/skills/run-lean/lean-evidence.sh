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
#   --pr-comments-file <path>   read the PR comment trail from a JSON fixture
#   --diff-files-file <path>    read the PR's changed-file list from a newline fixture
#   ${GH:-gh}                   the CLI used for the comment fetch
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
#              [--arms verdict,identity,freshness,intent-gap]   default: all four
#   lean-evidence.sh [all]                 classify, then check every arm (the consumer form)
#
# Exit 0 = pass or not-applicable; 1 = evidence violation; 2 = usage/environment error.
#
# macOS ships /bin/bash 3.2; this file stays 3.2-compatible. No `set -e` — the violation
# counter IS the control flow.
set -uo pipefail

GH_CLI="${GH:-gh}"
PR_COMMENTS_FILE=""
DIFF_FILES_FILE=""
VIOLATIONS_FILE=""
SUB=""
KEY=""
ARMS="verdict,identity,freshness,intent-gap"

while [ $# -gt 0 ]; do
  case "$1" in
    classify|check|all) SUB="$1"; shift ;;
    --key)               KEY="${2:-}"; shift 2 ;;
    --arms)              ARMS="${2:-}"; shift 2 ;;
    --pr-comments-file)  PR_COMMENTS_FILE="${2:-}"; shift 2 ;;
    --diff-files-file)   DIFF_FILES_FILE="${2:-}"; shift 2 ;;
    --violations-file)   VIOLATIONS_FILE="${2:-}"; shift 2 ;;
    -h|--help)           sed -n '2,130p' "$0"; exit 0 ;;
    *) echo "[lean-evidence] unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$SUB" ] || SUB="all"

envfail() { echo "[lean-evidence] $1" >&2; exit 2; }

violations=0
note_violation() { echo "[lean-evidence]   ✗ $1" >&2; violations=$((violations + 1)); }

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
LEAN_VERDICT_SUFFIX='-lean-verdict.md'
LEAN_INTENT_GAP_SUFFIX='-lean-intent-gap.md'

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
      if printf '%s' "$suffix" | grep -qiE "^($KEY_RE)$"; then
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

arm_identity() {
  if [ "$BOT_ENABLED" != "true" ]; then
    inapplicable identity reduced-strength "no bot is enabled for this consumer (tracker.bot.enabled is false, or absent under tracker.type 'jira'), so it has no authenticated writer and any PR marker it posted would fail the Bot trust filter. The verdict's independence is NOT checked here; every other arm still gates. Configuring a bot restores this arm under either tracker."
    return 0
  fi
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
    note_violation "verdict record '$VERDICT' reviewed patch $(printf '%.12s' "$VERDICT_REVIEWED_PATCH_ID"), but this branch's diff against origin/$PR_BASE_REF now hashes to $(printf '%.12s' "$cur"). Content changed after the review — a commit landed, or a rebase resolved a conflict by altering a line — so the review read a different tree than the one being merged. Run another review round."
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

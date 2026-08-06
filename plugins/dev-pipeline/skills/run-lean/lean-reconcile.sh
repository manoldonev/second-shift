#!/usr/bin/env bash
# lean-reconcile.sh — the OPERATOR's pre-merge check on a lean PR (D-48, AC-16).
#
# DEFERS TO #292. This is an explicitly lean-scoped forerunner of the general run-reconcile
# verifier. When that lands, this script defers to it and stops being the owner — the same
# one-owner discipline the mutation-exclusions register follows with CLAUDE.md. Do not grow
# it into a general attestation tool in the meantime.
#
# RUN THIS YOURSELF, NOT FROM THE RUN. Self-reconciliation is not evidence: a run checking
# its own records proves nothing an adversarial (or merely reward-hacking) agent could not
# also produce. The whole value here is that a human invokes it, out-of-band, against records
# the run has already finished writing.
#
# WHAT IT CLOSES. check-lean-chain.sh (CI) proves the committed/tracker artifacts EXIST and
# are internally consistent. It cannot prove the review actually RAN IN ITS OWN SESSION — a
# sufficiently determined agent could write a verdict record having dispatched nothing. This
# script closes that path against the one record the agent does not author: the harness-written
# hook ledger.
#   1. the verdict record names a REVIEW SESSION, and that session has a live audit ledger,
#   2. that session is NOT the build session (P10 — generation must not author evaluation),
#   3. the review session's first recorded tool call PRECEDES the verdict commit (a record
#      written before its review ran is not a record of that review),
#   4. RUN_ID is consistent across the claim comment and the progress file (both build-side),
#      and the verdict's run identity DIFFERS from them,
#   5. the record DECLARES the head it reviewed, and its own commit descends from that head.
#      This is the third reader of that key, alongside milestone 4 and check-lean-chain.sh.
#      What it adds over those two is COHERENCE rather than currency: they compare the declared
#      head against a moving head, whereas a record whose own commit does not descend from the
#      commit it names is internally incoherent wherever the branch has since gone.
#   6. every INHERITANCE link the record declares (#375) resolves to an earlier record, AND every
#      round in the resulting chain was authored by a DIFFERENT review session. That second half
#      is this reader's alone, and it is what the merge boundary's new guarantee rests on: with
#      inheritance, "this tree was reviewed" means "a chain of INDEPENDENT reviews covered it".
#      One session writing round 1 and then inheriting its own coverage in round 2 produces a
#      chain that resolves perfectly while being a single review — and review-lean's own rule
#      ("a NEW review context produces the next verdict — never this one resumed") is what makes
#      that a contract rather than a preference. Absence of a chain is the ordinary case and is
#      printed. Deliberately NOT checked here: that each link's commit is an ancestor of the one
#      inheriting it. On a lean branch the record path is linear and HEAD-anchored, so that
#      predicate holds by construction — an arm no fixture can red is coverage in appearance only.
#
# RE-ANCHORED WITH THE SEPARATION. This check used to require a `lean-review` Workflow dispatch
# row in the BUILD session's ledger. That row can never exist once review is a separate
# top-level session — the build host owes a review trace no longer, which is also what makes
# milestone 4 host-portable: on a foreign harness the committed verdict file was reproducible
# but the build-side dispatch trace was not, so the old requirement was unsatisfiable honestly.
# The trace it looks for now is the review session's own ledger.
#
# Honest ceiling: the ledger is written by a hook on the same machine, so this is strong
# tamper-evidence, not cryptographic proof. It raises forgery from "write one file" to
# "forge a second session's hook ledger with coherent timestamps" — see docs/pipeline-manifesto.md.
#
# TRACKER ADAPTERS. Check (1)'s claim arm is the only thing here that reads a tracker, and under
# `tracker.type: jira` the record it reads cannot exist: that adapter's claim writes nothing, so
# no bot-authored `lean-claimed` comment is ever posted. The arm is therefore SKIPPED there
# rather than fetched — the fetch 404s on a ticket key, and its `exit 2` used to take checks (1b)
# through (6) down with it, including the P10 authorship check, which needs no tracker at all.
# The reduced evidence set is DISCLOSED in the output, at the check site and on the closing line,
# and the exit code is NOT the disclosure: an operator scripting on it reads any non-zero as
# "failed", which "this adapter has one arm fewer" is not.
#
# Usage:
#   lean-reconcile.sh <issue> [--session-id <id>] [--comments-file <path>]
#     --session-id  the BUILD session, when the progress file records none.
#                   The REVIEW session is never passed in: it comes from the verdict record,
#                   because letting the operator name it would let a wrong guess reconcile a
#                   record against a session that did not produce it.
#
# Seams (zero-network selftest):
#   ${GH:-gh}                the CLI used for the claim-comment read (github arm only)
#   --comments-file <path>   read the comment trail from a JSON fixture (github arm only;
#                            refused under jira, where no comment trail is read at all)
#   LEAN_PROGRESS_FILE       override the resolved progress-file path
#   LEAN_AUDIT_DIR           override the resolved audit-ledger directory. FIXTURE-ONLY, and
#                            deliberately not promoted to an operator escape hatch: the honest
#                            ceiling stated above is "forge a second session's hook ledger with
#                            coherent timestamps", and a sanctioned directory override lowers it
#                            to "write a JSONL file anywhere". Mirrors STATECTL_LEDGER_DIR.
#                            The shipped default is the MAIN checkout's .claude/audit — the same
#                            directory the audit hook writes to.
#   SECOND_SHIFT_CONFIG      override the resolved config path
#
# Exit 0 = reconciled; 1 = a reconciliation failure; 2 = usage/environment error.
set -uo pipefail

GH_CLI="${GH:-gh}"
COMMENTS_FILE=""
SESSION_ID=""
ISSUE=""

say()     { echo "[lean-reconcile] $*"; }
envfail() { echo "[lean-reconcile] $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --session-id)    SESSION_ID="${2:-}"; shift 2 ;;
    --comments-file) COMMENTS_FILE="${2:-}"; shift 2 ;;
    -h|--help)       sed -n '2,83p' "$0"; exit 0 ;;
    -*)              envfail "unknown option: $1" ;;
    *)               [ -z "$ISSUE" ] && ISSUE="$1" || envfail "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$ISSUE" ] || envfail "usage: lean-reconcile.sh <issue> [--session-id <id>] [--comments-file <path>]"

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
PLANS_DIR="$(cfg '.paths.plansDir' 'docs/plans')"
STATE_DIR="$(cfg '.paths.pipelineStateDir' '.claude/pipeline-state')"
HOST_Q='(.topology.repos | to_entries[] | select(.value.path==".") | .key)'
REPO_SLUG="$(cfg "$HOST_Q" 'acme')"

# ---- the tracker adapter -------------------------------------------------------------------
# ONE resolution, ONE branch site: check (1)'s comment fetch. Checks (1b) and (2)-(6) read git,
# the progress file, the verdict record and the audit ledger, and must stay adapter-insensitive
# — a second branch here would make this script a second tracker authority beside lean-gate.sh.
#
# Absent ⇒ github is a FAIL-SAFE, not back-compat: config-lint.sh already requires the key to be
# github|jira, so no lint-clean config omits it, and github is the safe side for a config that
# never reached the lint — the arm that DEMANDS a claim comment fails loudly, where the jira arm
# would quietly attest less than the operator thinks. An UNRECOGNIZED value is a loud error and
# not a fall-through, so a typo cannot silently pick an arm. lean-gate.sh's enum, verbatim.
TRACKER_TYPE="$(cfg '.tracker.type' 'github')"
case "$TRACKER_TYPE" in
  github|jira) : ;;
  *) envfail "unknown tracker.type '$TRACKER_TYPE' — expected 'github' or 'jira'." ;;
esac

# The github arm's zero-network seam has no meaning on an adapter that reads no comment trail.
# REFUSED rather than ignored: a jira case that hands over a fixture and still goes green asserts
# nothing about that fixture while reading as coverage, and nothing would red if a later edit
# re-enabled the fetch.
if [ "$TRACKER_TYPE" = "jira" ] && [ -n "$COMMENTS_FILE" ]; then
  envfail "--comments-file is not meaningful under tracker.type: jira — this adapter posts no claim comment, so no comment trail is read."
fi

VERDICT_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean-verdict.md"
PROGRESS_FILE="${LEAN_PROGRESS_FILE:-$MAIN_ROOT/$STATE_DIR/$ISSUE-lean-progress.md}"
AUDIT_DIR="${LEAN_AUDIT_DIR:-$MAIN_ROOT/.claude/audit}"

failures=0
bad() { echo "[lean-reconcile]   ✗ $1" >&2; failures=$((failures + 1)); }
ok()  { echo "[lean-reconcile]   ✓ $1"; }

# capture-first counting; never `grep -c … || echo 0` (that prints 0 twice on no match).
count_in() { local n; n="$(grep -c "$@" 2>/dev/null)" || n=0; [ -n "$n" ] || n=0; echo "$n"; }

# ---- inputs ------------------------------------------------------------------------------
[ -f "$REPO_ROOT/$VERDICT_REL" ] || { echo "[lean-reconcile] ✗ no committed verdict record at $VERDICT_REL" >&2; exit 1; }
[ -f "$PROGRESS_FILE" ]          || { echo "[lean-reconcile] ✗ no progress file at $PROGRESS_FILE" >&2; exit 1; }

say "reconciling #$ISSUE"
say "  verdict record: $VERDICT_REL"
say "  progress file:  $PROGRESS_FILE"

# First `<key>: <token>`, HTML-comment or bare form. `session_id:` does not contain the
# substring `run_id:`, so the two keys cannot capture each other.
extract_key() { # extract_key <key> <file>
  grep -oE "$1:[[:space:]]*[A-Za-z0-9._-]+" "$2" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"
}

# The same extraction against a COMMITTED version of the record. It is the only way to reach a
# PRIOR round: the record path holds one round at a time, so every round but the newest exists
# solely in that path's git history.
extract_key_at() { # extract_key_at <key> <commit>
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

short() { git -C "$REPO_ROOT" rev-parse --short "$1" 2>/dev/null || printf '%s' "$1"; }

RUN_VERDICT="$(extract_key run_id "$REPO_ROOT/$VERDICT_REL")"
RUN_PROGRESS="$(extract_key run_id "$PROGRESS_FILE")"
REVIEW_SESSION="$(extract_key session_id "$REPO_ROOT/$VERDICT_REL")"
[ -n "$RUN_VERDICT" ]  || bad "verdict record carries no run_id reconciliation key"
[ -n "$RUN_PROGRESS" ] || bad "progress file carries no run_id reconciliation key"

# ---- (1) RUN_ID consistency across the three records --------------------------------------
# The ONE adapter-sensitive check. Under jira the claim comment it compares against does not
# exist — that adapter's claim makes no tracker write — so the arm is skipped and DISCLOSED,
# never faked from a build-side substitute: the progress file's own claim line is written by the
# same run whose honesty is in question, and self-reconciliation is not evidence (see the header).
if [ "$TRACKER_TYPE" = "jira" ]; then
  say "  · claim-comment arm NOT RUN (jira adapter): this tracker posts no bot-authored 'lean-claimed' comment, so build-side run_id agreement across two independent records is unattestable here. Every check below reads only git, the progress file, the verdict record and the audit ledger."
else
  if [ -n "$COMMENTS_FILE" ]; then
    [ -f "$COMMENTS_FILE" ] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
    COMMENTS="$(cat "$COMMENTS_FILE")"
  else
    COMMENTS="$("$GH_CLI" api "repos/{owner}/{repo}/issues/$ISSUE/comments" --paginate 2>&1)" || {
      echo "[lean-reconcile] comment fetch failed for #$ISSUE:" >&2
      printf '%s\n' "$COMMENTS" >&2
      exit 2
    }
  fi
  printf '%s' "$COMMENTS" | jq -e 'type == "array"' >/dev/null 2>&1 || envfail "comment trail is not a JSON array."

  # Only a BOT-authored lean-claimed comment counts, for the same reason the CI gate filters:
  # on a public repo anyone can post a marker, and an operator-posted claim is not evidence the
  # harness ran.
  RUN_CLAIM="$(printf '%s' "$COMMENTS" | jq -r '
    [ .[] | select((.user.type // "") == "Bot")
          | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*lean-claimed[[:space:]]*-->"))
          | ((.body // "") | capture("run_id:[[:space:]]*(?<r>[A-Za-z0-9._-]+)").r? // "") ]
    | map(select(. != "")) | first // ""')"

  # The claim comment and the progress file are BOTH build-side records; they must agree. The
  # verdict record must NOT agree with them — that is the whole separation. Asserting the two
  # properties in one comparison (the pre-#345 "all three are one run") is what made the old
  # check enforce the opposite of what P10 requires.
  if [ -z "$RUN_CLAIM" ]; then
    bad "no bot-authored 'lean-claimed' comment with a run_id on #$ISSUE"
  elif [ "$RUN_CLAIM" = "$RUN_PROGRESS" ]; then
    ok "build run_id consistent across the claim comment and the progress file ($RUN_CLAIM)"
  else
    bad "build run_id mismatch — claim='$RUN_CLAIM' progress='$RUN_PROGRESS'. These must be one run."
  fi
fi

if [ -n "$RUN_VERDICT" ] && [ -n "$RUN_PROGRESS" ] && [ "$RUN_VERDICT" = "$RUN_PROGRESS" ]; then
  bad "the verdict record carries the BUILD run's identity ('$RUN_VERDICT') — generation authored its own evaluation (P10). The verdict must come from a separate review session."
elif [ -n "$RUN_VERDICT" ]; then
  ok "verdict run_id ($RUN_VERDICT) is distinct from the build run's ($RUN_PROGRESS)"
fi

# ---- (2) the REVIEW session exists, is separate, and left a harness trace ------------------
# The build session is resolved from --session-id, else the progress file's recorded
# session_id. NOT "the newest ledger by mtime": that fallback would silently reconcile against
# a DIFFERENT session, which is precisely the fabrication path this check exists to close.
[ -n "$SESSION_ID" ] || SESSION_ID="$(extract_key session_id "$PROGRESS_FILE")"
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "unset" ]; then
  bad "no build session id (progress file records none and --session-id was not given) — there is nothing to separate the review's authorship from"
  SESSION_ID=""
fi

# The review session's ledger is the trace. It is located by the id the VERDICT RECORD names,
# never by one supplied on the command line — see the usage note above.
LEDGER=""
if [ -z "$REVIEW_SESSION" ] || [ "$REVIEW_SESSION" = "unset" ]; then
  bad "verdict record carries no session_id — the review session that produced it cannot be located, so nothing outside the record itself attests the review ran"
elif [ -n "$SESSION_ID" ] && [ "$REVIEW_SESSION" = "$SESSION_ID" ]; then
  bad "the verdict record names the BUILD session ('$REVIEW_SESSION') as its author — a review dispatched and written inside the session under review is not an independent review (P10)"
else
  LEDGER="$AUDIT_DIR/$REVIEW_SESSION.jsonl"
  if [ ! -s "$LEDGER" ]; then
    bad "no review-session audit ledger at '$LEDGER' — the verdict record names a session the harness has no record of"
    LEDGER=""
  else
    ok "review session $REVIEW_SESSION is distinct from the build session and has a live ledger ($(count_in '' "$LEDGER") rows)"
  fi
fi

# ---- (3) the review session's work precedes the verdict commit -----------------------------
# A verdict record committed BEFORE its review session did anything cannot be a record of that
# review. The FIRST ledger row is the anchor: it is the earliest moment the review context
# demonstrably existed.
REVIEW_TS=""
if [ -n "$LEDGER" ]; then
  REVIEW_TS="$(head -n1 "$LEDGER" 2>/dev/null | jq -r '.ts // empty' 2>/dev/null || true)"
fi
if [ -n "$REVIEW_TS" ]; then
  COMMIT_TS="$(git -C "$REPO_ROOT" log -1 --format=%cI -- "$VERDICT_REL" 2>/dev/null)"
  if [ -z "$COMMIT_TS" ]; then
    say "  note: verdict record is not committed yet — timestamp ordering not checkable."
  elif [ "$REVIEW_TS" \< "$COMMIT_TS" ] || [ "$REVIEW_TS" = "$COMMIT_TS" ]; then
    ok "the review session opened ($REVIEW_TS) before the verdict commit ($COMMIT_TS)"
  else
    bad "timestamp inversion — the review session's first recorded tool call is $REVIEW_TS but the verdict record was committed at $COMMIT_TS. A verdict written before its review is not evidence of that review."
  fi
elif [ -n "$LEDGER" ]; then
  say "  note: the review ledger's first row carries no timestamp — ordering not checkable."
fi

# ---- (4) the record declares what it reviewed, and its own commit sits on top of that -------
# Read with the SAME extractor as run_id/session_id — one schema, three readers, and a reader
# that invented its own parse for one key would diverge silently rather than loudly.
#
# TWO KEYINGS, same precedence the other two readers use. `reviewed_patch_id` is the patch
# identity of the branch's own diff excluding this record, so it is invariant under a rebase
# (which rewrites commit SHAs and changes no reviewed line) and still moves when a commit or a
# conflict resolution alters one. The `reviewed_head` ancestry path below is what records
# predating that key are read on — and it is exactly the path that turned a rebase into a
# "do NOT merge": after one, the record's replayed commit descends from no pre-rebase head.
REVIEWED_HEAD="$(extract_key reviewed_head "$REPO_ROOT/$VERDICT_REL")"
REVIEWED_PATCH_ID="$(extract_key reviewed_patch_id "$REPO_ROOT/$VERDICT_REL")"
if [ -z "$REVIEWED_HEAD" ]; then
  bad "verdict record carries no reviewed_head key — nothing states which commit the review actually read, so 'a verdict exists' cannot be distinguished from 'this code was reviewed'. Re-run the review round on a dev-pipeline that writes it."
elif [ -n "$REVIEWED_PATCH_ID" ]; then
  VERDICT_COMMIT="$(git -C "$REPO_ROOT" log -1 --format=%H -- "$VERDICT_REL" 2>/dev/null)"
  if [ -z "$VERDICT_COMMIT" ]; then
    say "  note: verdict record is not committed yet — its patch identity is not checkable."
  else
    # Measured at the commit CARRYING the record, not at HEAD: this reader's question is whether
    # the record was written on top of the tree it claims to have reviewed, which is a statement
    # about that commit. Freshness against the merge target is the other two readers' job.
    RECONCILE_BASE="$(cfg "(.topology.repos | to_entries[] | select(.value.path==\".\") | .value.baseBranch)" 'main')"
    CUR_PATCH_ID="$(git -C "$REPO_ROOT" diff "$(git -C "$REPO_ROOT" merge-base "origin/$RECONCILE_BASE" "$VERDICT_COMMIT" 2>/dev/null)" \
      "$VERDICT_COMMIT" -- . ":(exclude)$VERDICT_REL" 2>/dev/null \
      | git -C "$REPO_ROOT" patch-id --stable 2>/dev/null | cut -d' ' -f1)"
    # An empty recompute is UNCHECKABLE, never a match: `git patch-id` prints nothing for an
    # empty diff, so two failed computations compare equal and an unguarded reader would emit
    # its ✓ having hashed nothing. Reported as a note rather than a failure — unlike a missing
    # key, nothing here says the evidence is absent, only that this checkout cannot measure it.
    if [ -z "$CUR_PATCH_ID" ]; then
      say "  note: cannot compute the branch's patch identity against origin/$RECONCILE_BASE — the declared reviewed_patch_id is not checkable in this checkout."
    elif [ "$CUR_PATCH_ID" = "$REVIEWED_PATCH_ID" ]; then
      ok "the verdict record declares reviewed_patch_id $(printf '%.12s' "$REVIEWED_PATCH_ID"), and the commit carrying it hashes to the same patch"
    else
      bad "the verdict record declares reviewed_patch_id $(printf '%.12s' "$REVIEWED_PATCH_ID"), but the commit carrying it hashes to $(printf '%.12s' "$CUR_PATCH_ID") — the record was not written on top of the tree it claims to have reviewed"
    fi
  fi
else
  VERDICT_COMMIT="$(git -C "$REPO_ROOT" log -1 --format=%H -- "$VERDICT_REL" 2>/dev/null)"
  if ! git -C "$REPO_ROOT" cat-file -e "$REVIEWED_HEAD^{commit}" 2>/dev/null; then
    bad "the verdict record names reviewed_head $REVIEWED_HEAD, which is not a commit in this repository — the branch was rebased or force-pushed after the review, so the reviewed code no longer exists here"
  elif [ -z "$VERDICT_COMMIT" ]; then
    say "  note: verdict record is not committed yet — its descent from $REVIEWED_HEAD is not checkable."
  elif git -C "$REPO_ROOT" merge-base --is-ancestor "$REVIEWED_HEAD" "$VERDICT_COMMIT" 2>/dev/null; then
    ok "the verdict record declares reviewed_head $(git -C "$REPO_ROOT" rev-parse --short "$REVIEWED_HEAD" 2>/dev/null), and its own commit descends from it"
  else
    bad "the verdict record declares reviewed_head $REVIEWED_HEAD, but the commit carrying the record does not descend from it — the record cannot have been written on top of the tree it claims to have reviewed"
  fi
fi

# ---- (5) the inheritance chain is a sequence of INDEPENDENT reviews (#375) ------------------
# Two properties, and only the second is this reader's own. Every link must RESOLVE — the merge
# boundary and milestone 4 check that too, and a third reader disagreeing about it would be a
# silent divergence rather than a loud one. What only this reader asks is whether the chain is a
# sequence of independent reviews at all: one session that writes round 1 and then inherits its
# OWN coverage in round 2 produces a chain that resolves perfectly while being a single review,
# and inheritance is exactly what makes that consequential — round 2 then reads the delta and is
# credited with a tree only round 1 ever saw, by the same session.
INHERITED_PATCH_ID="$(inherited_key < "$REPO_ROOT/$VERDICT_REL")"
if [ -z "$INHERITED_PATCH_ID" ]; then
  say "  · the verdict record declares no inherited coverage — it covers the whole branch diff on its own."
elif [ -z "$(git -C "$REPO_ROOT" log -1 --format=%H -- "$VERDICT_REL" 2>/dev/null)" ]; then
  say "  note: verdict record is not committed yet — its inheritance chain is not checkable."
else
  # The search window starts strictly BELOW the commit carrying the record being read and
  # shrinks past every hit, so the chain runs backwards through the record's history: a branch
  # reverted to a previously-reviewed tree would otherwise resolve its round to itself, and
  # termination is structural rather than a cycle counter. An unanchorable window collapses to
  # empty, which refuses — never to the full list, which would widen the search.
  CHAIN_VERSIONS=""
  CHAIN_PAST=0
  CHAIN_HEAD_COMMIT="$(git -C "$REPO_ROOT" log -1 --format=%H -- "$VERDICT_REL" 2>/dev/null)"
  for c in $(git -C "$REPO_ROOT" log --format=%H -- "$VERDICT_REL" 2>/dev/null); do
    if [ "$CHAIN_PAST" -eq 1 ]; then CHAIN_VERSIONS="$CHAIN_VERSIONS $c"; continue; fi
    [ "$c" = "$CHAIN_HEAD_COMMIT" ] && CHAIN_PAST=1
  done
  CHAIN_WANT="$INHERITED_PATCH_ID"
  CHAIN_ROUND="$(extract_key rounds "$REPO_ROOT/$VERDICT_REL")"; [ -n "$CHAIN_ROUND" ] || CHAIN_ROUND='?'
  CHAIN_LINKS=0; CHAIN_BROKEN=""
  # The head round's author seeds the set, so a second round reusing it is caught on the first
  # link rather than only between two inherited rounds.
  CHAIN_SESSIONS="$REVIEW_SESSION"
  while [ -n "$CHAIN_WANT" ]; do
    CHAIN_HIT=""; CHAIN_REST=""
    for c in $CHAIN_VERSIONS; do
      if [ -n "$CHAIN_HIT" ]; then CHAIN_REST="$CHAIN_REST $c"; continue; fi
      if [ "$(extract_key_at reviewed_patch_id "$c")" = "$CHAIN_WANT" ]; then CHAIN_HIT="$c"; fi
    done
    if [ -z "$CHAIN_HIT" ]; then
      CHAIN_BROKEN="round $CHAIN_ROUND declares inherited_patch_id $(printf '%.12s' "$CHAIN_WANT"), which matches no earlier verdict record committed on this branch — that round's inherited coverage is unverifiable"
      break
    fi
    CHAIN_VERSIONS="$CHAIN_REST"
    CHAIN_LINKS=$((CHAIN_LINKS + 1))
    CHAIN_ROUND="$(extract_key_at rounds "$CHAIN_HIT")"; [ -n "$CHAIN_ROUND" ] || CHAIN_ROUND='?'
    CHAIN_SESS="$(extract_key_at session_id "$CHAIN_HIT")"
    if [ -z "$CHAIN_SESS" ]; then
      CHAIN_BROKEN="the inherited round $CHAIN_ROUND (record $(short "$CHAIN_HIT")) names no review session — nothing attests it was a review separate from the round inheriting it"
      break
    fi
    if [ -n "$SESSION_ID" ] && [ "$CHAIN_SESS" = "$SESSION_ID" ]; then
      CHAIN_BROKEN="the inherited round $CHAIN_ROUND names the BUILD session ('$CHAIN_SESS') as its author — coverage inherited from generation's own evaluation is not independent coverage (P10)"
      break
    fi
    case " $CHAIN_SESSIONS " in
      *" $CHAIN_SESS "*)
        CHAIN_BROKEN="round $CHAIN_ROUND was authored by session '$CHAIN_SESS', which already authored another round in this chain — a chain of inherited coverage must be a sequence of INDEPENDENT reviews, and review-lean requires a new review context per round"
        break ;;
    esac
    CHAIN_SESSIONS="$CHAIN_SESSIONS $CHAIN_SESS"
    CHAIN_WANT="$(inherited_key_at "$CHAIN_HIT")"
  done
  if [ -n "$CHAIN_BROKEN" ]; then
    bad "$CHAIN_BROKEN"
  else
    ok "the inheritance chain resolves over $CHAIN_LINKS earlier record(s), each authored by its own review session"
  fi
fi

if [ "$failures" -gt 0 ]; then
  echo "[lean-reconcile] ✗ $failures reconciliation failure(s) for #$ISSUE — do NOT merge until resolved." >&2
  exit 1
fi
# The closing line carries the reduced-evidence qualifier too, not only the check site: an
# operator who reads the last line alone must not mistake a jira reconcile for the github-strength
# attestation. The FAILURE line above is deliberately unqualified — a red reconcile's evidence
# strength is moot.
RECONCILED_NOTE=""
if [ "$TRACKER_TYPE" = "jira" ]; then
  RECONCILED_NOTE=" (jira adapter — REDUCED evidence: the build-side claim-comment arm did not run)"
fi
say "reconciled: #$ISSUE$RECONCILED_NOTE — the committed verdict is backed by a harness-recorded review session, separate from the build's."

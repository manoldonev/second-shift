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
#      and the verdict's run identity DIFFERS from them.
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
# Usage:
#   lean-reconcile.sh <issue> [--session-id <id>] [--comments-file <path>]
#     --session-id  the BUILD session, when the progress file records none.
#                   The REVIEW session is never passed in: it comes from the verdict record,
#                   because letting the operator name it would let a wrong guess reconcile a
#                   record against a session that did not produce it.
#
# Seams (zero-network selftest):
#   ${GH:-gh}                the CLI used for the claim-comment read
#   --comments-file <path>   read the comment trail from a JSON fixture
#   LEAN_PROGRESS_FILE       override the resolved progress-file path
#   LEAN_AUDIT_DIR           override the resolved audit-ledger directory
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
    -h|--help)       sed -n '2,51p' "$0"; exit 0 ;;
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

RUN_VERDICT="$(extract_key run_id "$REPO_ROOT/$VERDICT_REL")"
RUN_PROGRESS="$(extract_key run_id "$PROGRESS_FILE")"
REVIEW_SESSION="$(extract_key session_id "$REPO_ROOT/$VERDICT_REL")"
[ -n "$RUN_VERDICT" ]  || bad "verdict record carries no run_id reconciliation key"
[ -n "$RUN_PROGRESS" ] || bad "progress file carries no run_id reconciliation key"

# ---- (1) RUN_ID consistency across the three records --------------------------------------
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

if [ "$failures" -gt 0 ]; then
  echo "[lean-reconcile] ✗ $failures reconciliation failure(s) for #$ISSUE — do NOT merge until resolved." >&2
  exit 1
fi
say "reconciled: #$ISSUE — the committed verdict is backed by a harness-recorded review session, separate from the build's."

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
# WHAT IT CLOSES. check-lean-chain.sh (CI) proves the three committed/tracker artifacts EXIST
# and are internally consistent. It cannot prove the review actually RAN — a sufficiently
# determined agent could write a verdict record having dispatched nothing. This script closes
# that path against the one record the agent does not author: the harness-written hook ledger.
#   1. the reviewer Workflow dispatch APPEARS in the session's audit .jsonl,
#   2. its timestamp PRECEDES the verdict commit (a record written before the review ran is
#      not a record of that review),
#   3. RUN_ID is CONSISTENT across the claim comment, the verdict record, and the progress file.
#
# Honest ceiling: the ledger is written by a hook on the same machine, so this is strong
# tamper-evidence, not cryptographic proof. It raises forgery from "write one file" to
# "forge a hook ledger with coherent timestamps" — see docs/pipeline-manifesto.md.
#
# Usage:
#   lean-reconcile.sh <issue> [--session-id <id>] [--comments-file <path>]
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
    -h|--help)       sed -n '2,40p' "$0"; exit 0 ;;
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

extract_run_id() { # first `run_id: <token>` in a file, HTML-comment or bare form
  grep -oE 'run_id:[[:space:]]*[A-Za-z0-9._-]+' "$1" 2>/dev/null | head -n1 | sed -E 's/run_id:[[:space:]]*//'
}

RUN_VERDICT="$(extract_run_id "$REPO_ROOT/$VERDICT_REL")"
RUN_PROGRESS="$(extract_run_id "$PROGRESS_FILE")"
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

if [ -z "$RUN_CLAIM" ]; then
  bad "no bot-authored 'lean-claimed' comment with a run_id on #$ISSUE"
elif [ "$RUN_CLAIM" = "$RUN_VERDICT" ] && [ "$RUN_CLAIM" = "$RUN_PROGRESS" ]; then
  ok "run_id consistent across claim comment, verdict record and progress file ($RUN_CLAIM)"
else
  bad "run_id mismatch — claim='$RUN_CLAIM' verdict='$RUN_VERDICT' progress='$RUN_PROGRESS'. These must be one run."
fi

# ---- (2) the reviewer dispatch appears in the session's audit ledger -----------------------
# Resolve the session from --session-id, else the progress file's recorded session_id. NOT
# "the newest ledger by mtime": that fallback would silently reconcile against a DIFFERENT
# session, which is precisely the fabrication path this check exists to close.
[ -n "$SESSION_ID" ] || SESSION_ID="$(grep -oE '^session_id:[[:space:]]*[A-Za-z0-9._-]+' "$PROGRESS_FILE" 2>/dev/null | head -n1 | sed -E 's/^session_id:[[:space:]]*//')"
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "unset" ]; then
  bad "no session id (progress file records none and --session-id was not given) — the audit ledger cannot be located, so the dispatch is unverifiable"
  LEDGER=""
else
  LEDGER="$AUDIT_DIR/$SESSION_ID.jsonl"
  if [ ! -s "$LEDGER" ]; then
    bad "audit ledger '$LEDGER' is missing or empty — no harness record of this session's tool calls"
    LEDGER=""
  fi
fi

DISPATCH_TS=""
if [ -n "$LEDGER" ]; then
  # The reviewer runs as a Workflow dispatch; the ledger records the tool call. Match on the
  # lean-review workflow name OR a Workflow/Task tool row naming it.
  n="$(count_in -E 'lean-review' "$LEDGER")"
  if [ "$n" -ge 1 ]; then
    ok "reviewer dispatch present in the audit ledger ($n row(s) naming lean-review)"
    DISPATCH_TS="$(grep -E 'lean-review' "$LEDGER" 2>/dev/null | head -n1 \
      | jq -r '.ts // empty' 2>/dev/null || true)"
  else
    bad "no lean-review dispatch in the audit ledger '$LEDGER' — the verdict record claims a review that left no harness trace"
  fi
fi

# ---- (3) the dispatch precedes the verdict commit ------------------------------------------
# A verdict record committed BEFORE the review dispatched cannot be a record of that review.
if [ -n "$DISPATCH_TS" ]; then
  COMMIT_TS="$(git -C "$REPO_ROOT" log -1 --format=%cI -- "$VERDICT_REL" 2>/dev/null)"
  if [ -z "$COMMIT_TS" ]; then
    say "  note: verdict record is not committed yet — timestamp ordering not checkable."
  elif [ "$DISPATCH_TS" \< "$COMMIT_TS" ] || [ "$DISPATCH_TS" = "$COMMIT_TS" ]; then
    ok "reviewer dispatch ($DISPATCH_TS) precedes the verdict commit ($COMMIT_TS)"
  else
    bad "timestamp inversion — the reviewer dispatched at $DISPATCH_TS but the verdict record was committed at $COMMIT_TS. A verdict written before its review is not evidence of that review."
  fi
elif [ -n "$LEDGER" ]; then
  say "  note: dispatch row carries no timestamp — ordering not checkable."
fi

if [ "$failures" -gt 0 ]; then
  echo "[lean-reconcile] ✗ $failures reconciliation failure(s) for #$ISSUE — do NOT merge until resolved." >&2
  exit 1
fi
say "reconciled: #$ISSUE — the committed verdict is backed by a harness-recorded review."

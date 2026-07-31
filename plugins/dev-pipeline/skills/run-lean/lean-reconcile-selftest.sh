#!/usr/bin/env bash
# lean-reconcile-selftest.sh — behavioral suite for the operator-side lean verifier (AC-16).
#
# Drives the REAL lean-reconcile.sh against a throwaway git repo with a synthetic audit
# ledger, verdict record, progress file and comment fixture. Zero network.
#
# The three arms that carry the value are each a distinct fabrication path:
#   (C) the verdict record exists but NO reviewer dispatch appears in the ledger — the agent
#       wrote a verdict having dispatched nothing.
#   (D) the dispatch exists but POSTDATES the verdict commit — a verdict written before its
#       own review.
#   (E) the run_ids disagree — records stitched together from different runs.
#
# Exit code = number of failed checks (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/lean-reconcile.sh"

FAILS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1" >&2; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d -t leanrec.XXXXXX)"
# shellcheck disable=SC2317,SC2329  # invoked indirectly by the EXIT trap below.
# BOTH codes: shellcheck >=0.10 reports SC2329 on the function, 0.9 (CI) reports SC2317 on
# each command in the body — suppressing only the newer one is clean locally and reds CI.
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT

TREE="$WORK/tree"
AUDIT="$WORK/audit"
mkdir -p "$TREE/docs/plans" "$AUDIT"
git -C "$TREE" init -q
git -C "$TREE" config user.email t@example.invalid
git -C "$TREE" config user.name t

CFG="$WORK/config.json"
cat > "$CFG" <<'EOF'
{
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" }
}
EOF

RUN_ID="r-2026-01-01-abcd"
SESSION="sess-1234"
VERDICT="$TREE/docs/plans/acme-7-lean-verdict.md"
PROG="$WORK/progress.md"

write_progress() { # write_progress <run-id> <session-id>
  cat > "$PROG" <<EOF
# lean run — issue 7

run_id: $1
session_id: $2
issue: 7
EOF
  echo "2026-01-01T00:00:00Z | milestone-4 | satisfied" >> "$PROG"
}

write_verdict() { # write_verdict <run-id>
  cat > "$VERDICT" <<EOF
# lean review verdict — #7

verdict=approve
run_id: $1
rounds: 1

No blockers.
EOF
}

# The ledger is the one record the agent does not author — the whole point of this check.
write_ledger() { # write_ledger <session-id> <dispatch-ts>
  cat > "$AUDIT/$1.jsonl" <<EOF
{"ts":"2026-01-01T00:00:00Z","session_id":"$1","event":"PreToolUse","tool":"Bash"}
{"ts":"$2","session_id":"$1","event":"PreToolUse","tool":"Workflow","target":"workflows/lean-review.mjs"}
{"ts":"2026-01-01T12:00:00Z","session_id":"$1","event":"PreToolUse","tool":"Read"}
EOF
}

cat > "$WORK/comments-good.json" <<EOF
[{ "user": { "type": "Bot", "login": "acme-bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: $RUN_ID -->\n<!-- stage: lean-claimed -->" }]
EOF
cat > "$WORK/comments-otherrun.json" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: r-a-different-run -->\n<!-- stage: lean-claimed -->" }]
EOF
cat > "$WORK/comments-human.json" <<EOF
[{ "user": { "type": "User", "login": "someone" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: $RUN_ID -->\n<!-- stage: lean-claimed -->" }]
EOF

commit_verdict() { # commit_verdict <committer-date>
  git -C "$TREE" add docs/plans/acme-7-lean-verdict.md
  GIT_COMMITTER_DATE="$1" git -C "$TREE" commit -q --date="$1" -m "verdict record" 2>/dev/null
}

reconcile() { # reconcile <comments-file>
  ( cd "$TREE" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" LEAN_AUDIT_DIR="$AUDIT" \
    bash "$TOOL" 7 --comments-file "$1" 2>&1 )
}

echo "[lean-reconcile-selftest]"

# ---- (A) fully consistent run reconciles --------------------------------------------------
write_progress "$RUN_ID" "$SESSION"
write_verdict "$RUN_ID"
write_ledger "$SESSION" "2026-01-01T06:00:00Z"
commit_verdict "2026-01-01T09:00:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(A) a consistent run reconciles"
else fail "(A) expected rc=0, got $rc: $out"; fi

# ---- (B) a missing verdict record is a hard stop -------------------------------------------
mv "$VERDICT" "$WORK/held.md"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no committed verdict record'; then
  pass "(B) a missing verdict record fails"
else fail "(B) expected rc=1, got $rc: $out"; fi
mv "$WORK/held.md" "$VERDICT"

# ---- (C) verdict record with NO reviewer dispatch in the ledger ----------------------------
# The fabrication path: a verdict written having dispatched nothing.
cat > "$AUDIT/$SESSION.jsonl" <<EOF
{"ts":"2026-01-01T06:00:00Z","session_id":"$SESSION","event":"PreToolUse","tool":"Read"}
EOF
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no lean-review dispatch'; then
  pass "(C) a verdict with no reviewer dispatch in the audit ledger fails"
else fail "(C) expected rc=1 on an absent dispatch, got $rc: $out"; fi

# ---- (D) dispatch POSTDATES the verdict commit ---------------------------------------------
write_ledger "$SESSION" "2026-06-01T00:00:00Z"   # long after the 2026-01-01 commit
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'timestamp inversion'; then
  pass "(D) a dispatch that postdates the verdict commit fails (timestamp ordering)"
else fail "(D) expected rc=1 on timestamp inversion, got $rc: $out"; fi
write_ledger "$SESSION" "2026-01-01T06:00:00Z"

# ---- (E) run_id mismatch across records ----------------------------------------------------
out="$(reconcile "$WORK/comments-otherrun.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'run_id mismatch'; then
  pass "(E) records stitched from different runs fail the run_id consistency check"
else fail "(E) expected rc=1 on a run_id mismatch, got $rc: $out"; fi

# ---- (F) a human-posted claim is not evidence ----------------------------------------------
out="$(reconcile "$WORK/comments-human.json")"; rc=$?
if [ "$rc" -eq 1 ]; then pass "(F) an operator-posted lean-claimed comment is not accepted"
else fail "(F) expected rc=1 on a human-authored claim, got $rc: $out"; fi

# ---- (G) an empty ledger fails ---------------------------------------------------------------
: > "$AUDIT/$SESSION.jsonl"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'missing or empty'; then
  pass "(G) an empty audit ledger fails"
else fail "(G) expected rc=1 on an empty ledger, got $rc: $out"; fi
write_ledger "$SESSION" "2026-01-01T06:00:00Z"

# ---- (H) no session id recorded ⇒ unverifiable, NOT a newest-ledger fallback -----------------
# Falling back to "the newest ledger by mtime" would silently reconcile against a DIFFERENT
# session, which is exactly the path this tool exists to close.
write_progress "$RUN_ID" "unset"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no session id'; then
  pass "(H) an unrecorded session id is unverifiable rather than silently substituted"
else fail "(H) expected rc=1 on a missing session id, got $rc: $out"; fi
write_progress "$RUN_ID" "$SESSION"

# ---- (I) header states the #292 deferral ----------------------------------------------------
if grep -q 'DEFERS TO #292' "$TOOL"; then
  pass "(I) the script records that it defers to the general verifier (#292) on arrival"
else fail "(I) no #292 deferral recorded in the header"; fi

echo "[lean-reconcile-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

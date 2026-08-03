#!/usr/bin/env bash
# lean-reconcile-selftest.sh — behavioral suite for the operator-side lean verifier (AC-16).
#
# Drives the REAL lean-reconcile.sh against a throwaway git repo with a synthetic audit
# ledger, verdict record, progress file and comment fixture. Zero network.
#
# The arms that carry the value are each a distinct fabrication path:
#   (C) the verdict record names a review session the harness has no ledger for — the agent
#       wrote a verdict having reviewed nothing.
#   (D) the review session's ledger POSTDATES the verdict commit — a verdict written before
#       its own review.
#   (E) the build run_ids disagree between the claim comment and the progress file — records
#       stitched together from different runs.
#   (J) the verdict carries the BUILD run's identity, or names the BUILD session as its
#       author — generation authoring its own evaluation (P10).
#
# RE-ANCHORED. (C) used to require a `lean-review` Workflow row in the BUILD session's ledger.
# That row cannot exist now that review is a separate top-level session, so the trace it looks
# for is the REVIEW session's own ledger, located by the session id the verdict record names.
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
REVIEW_RUN_ID="review-7-1"
REVIEW_SESSION="sess-review-9876"
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

write_verdict() { # write_verdict <run-id> <session-id>
  cat > "$VERDICT" <<EOF
# lean review verdict — #7

verdict=approve
run_id: $1
session_id: $2
rounds: 1

No blockers.
EOF
}

# The ledger is the one record the agent does not author — the whole point of this check. It
# is the REVIEW session's now, and nothing in it names a workflow: the trace is the existence
# of a separate session with its own recorded tool calls, not a dispatch row inside the build's.
write_ledger() { # write_ledger <session-id> <first-row-ts>
  cat > "$AUDIT/$1.jsonl" <<EOF
{"ts":"$2","session_id":"$1","event":"PreToolUse","tool":"Bash"}
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
write_verdict "$REVIEW_RUN_ID" "$REVIEW_SESSION"
write_ledger "$SESSION" "2026-01-01T05:00:00Z"
write_ledger "$REVIEW_SESSION" "2026-01-01T06:00:00Z"
commit_verdict "2026-01-01T09:00:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(A) a consistent run with a separately-authored verdict reconciles"
else fail "(A) expected rc=0, got $rc: $out"; fi

# ---- (B) a missing verdict record is a hard stop -------------------------------------------
mv "$VERDICT" "$WORK/held.md"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no committed verdict record'; then
  pass "(B) a missing verdict record fails"
else fail "(B) expected rc=1, got $rc: $out"; fi
mv "$WORK/held.md" "$VERDICT"

# ---- (C) the verdict names a review session the harness never saw --------------------------
# The fabrication path: a verdict written having reviewed nothing. The build session's ledger
# is intact and busy — which is precisely why the OLD anchor (a dispatch row in THAT ledger)
# could not tell this case apart from a real run once review moved out of the build session.
rm -f "$AUDIT/$REVIEW_SESSION.jsonl"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no review-session audit ledger'; then
  pass "(C) a verdict naming a session with no audit ledger fails"
else fail "(C) expected rc=1 on an absent review ledger, got $rc: $out"; fi
write_ledger "$REVIEW_SESSION" "2026-01-01T06:00:00Z"

# ---- (D) the review session POSTDATES the verdict commit -----------------------------------
write_ledger "$REVIEW_SESSION" "2026-06-01T00:00:00Z"   # long after the 2026-01-01 commit
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'timestamp inversion'; then
  pass "(D) a review session that opened after the verdict commit fails (timestamp ordering)"
else fail "(D) expected rc=1 on timestamp inversion, got $rc: $out"; fi
write_ledger "$REVIEW_SESSION" "2026-01-01T06:00:00Z"

# ---- (E) build run_id mismatch between the claim comment and the progress file --------------
out="$(reconcile "$WORK/comments-otherrun.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'build run_id mismatch'; then
  pass "(E) records stitched from different build runs fail the run_id consistency check"
else fail "(E) expected rc=1 on a run_id mismatch, got $rc: $out"; fi

# ---- (F) a human-posted claim is not evidence ----------------------------------------------
out="$(reconcile "$WORK/comments-human.json")"; rc=$?
if [ "$rc" -eq 1 ]; then pass "(F) an operator-posted lean-claimed comment is not accepted"
else fail "(F) expected rc=1 on a human-authored claim, got $rc: $out"; fi

# ---- (G) an empty review ledger fails ---------------------------------------------------------
: > "$AUDIT/$REVIEW_SESSION.jsonl"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no review-session audit ledger'; then
  pass "(G) an empty review audit ledger fails"
else fail "(G) expected rc=1 on an empty ledger, got $rc: $out"; fi
write_ledger "$REVIEW_SESSION" "2026-01-01T06:00:00Z"

# ---- (H) no build session id recorded ⇒ unverifiable, NOT a newest-ledger fallback -----------
# Falling back to "the newest ledger by mtime" would silently reconcile against a DIFFERENT
# session, which is exactly the path this tool exists to close.
write_progress "$RUN_ID" "unset"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no build session id'; then
  pass "(H) an unrecorded build session id is unverifiable rather than silently substituted"
else fail "(H) expected rc=1 on a missing session id, got $rc: $out"; fi
write_progress "$RUN_ID" "$SESSION"

# ---- (J) P10: the verdict must not be the build session's own work -------------------------
# Two shapes of the same violation. (J1) is what the pre-#345 check actively REQUIRED — all
# three records sharing one run id — so a suite that did not re-anchor here would still be
# green while enforcing the opposite of the contract.
write_verdict "$RUN_ID" "$REVIEW_SESSION"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "BUILD run's identity"; then
  pass "(J1) a verdict carrying the build run's run_id fails"
else fail "(J1) expected rc=1 on a build-authored verdict, got $rc: $out"; fi

write_verdict "$REVIEW_RUN_ID" "$SESSION"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'names the BUILD session'; then
  pass "(J2) a verdict naming the build session as its author fails"
else fail "(J2) expected rc=1 on a build-session verdict, got $rc: $out"; fi

# (J3) the MISSING key, which is a different guard from the two collisions above. `-z
# "$REVIEW_SESSION"` is what makes "the review session cannot be located" a refusal rather than
# a fall-through, and nothing else here reaches it: (C) supplies a session id and removes its
# LEDGER, (J1)/(J2) supply two identities that collide. A mutant deleting this arm would send a
# key-less record into the ledger lookup with an empty path and survive every other case in
# this file. The two sibling readers pin the same absence — lean-gate.sh (j3b),
# check-lean-chain.sh (N3) — and scripts/lockstep-manifest.tsv's DROPPED row cites all three.
cat > "$VERDICT" <<'EOF'
# lean review verdict — #7

verdict=approve
run_id: r-review-1
rounds: 1
EOF
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'carries no session_id'; then
  pass "(J3) a verdict record naming no review session at all fails"
else fail "(J3) expected rc=1 on a session_id-less verdict, got $rc: $out"; fi

write_verdict "$REVIEW_RUN_ID" "$REVIEW_SESSION"

# ---- (K) the retired anchor is gone: the BUILD ledger is not the review trace ---------------
# Delete the build session's ledger entirely. Under the old contract that was a hard failure —
# the dispatch row it demanded lived there. Under the new one the build host owes no review
# trace at all (which is also what makes milestone 4 portable to a foreign harness: the
# committed record is reproducible anywhere, a build-side dispatch trace is not), so this must
# reconcile on the review ledger alone. A textual "no longer greps for lean-review" guard would
# only assert that prose changed; this asserts the behavior did.
rm -f "$AUDIT/$SESSION.jsonl"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(K) the trace anchors on the REVIEW ledger — a run with no build ledger still reconciles"
else fail "(K) expected rc=0 with the build ledger removed, got $rc: $out"; fi
write_ledger "$SESSION" "2026-01-01T05:00:00Z"

# ---- (I) header states the #292 deferral ----------------------------------------------------
if grep -q 'DEFERS TO #292' "$TOOL"; then
  pass "(I) the script records that it defers to the general verifier (#292) on arrival"
else fail "(I) no #292 deferral recorded in the header"; fi

echo "[lean-reconcile-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

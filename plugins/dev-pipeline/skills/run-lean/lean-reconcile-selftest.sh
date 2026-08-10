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
# A base commit, so the verdict record has something to be written ON TOP OF. Without it the
# record's own commit is the root and `reviewed_head` would have to name that commit itself —
# a shape no review round produces, which would make the descent check assert nothing.
printf '# base\n' > "$TREE/docs/plans/base.md"
git -C "$TREE" add docs/plans/base.md >/dev/null 2>&1
git -C "$TREE" commit -q -m "base tree" >/dev/null 2>&1
# The patch-id arm measures the branch's diff from merge-base(origin/<baseBranch>, …), so the
# fixture carries the remote-tracking ref a real checkout would have. Block (M) composes that
# arm; every case above it writes records without the key and takes the ancestry fallback.
git -C "$TREE" update-ref refs/remotes/origin/main HEAD

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
  write_progress_unattested "$1" "$2"
  # #416's row. `lean-gate.sh entry` writes it; this file's subject is the READER, so the shape
  # is reproduced here rather than driven through the gate — the two are kept honest by
  # lean-gate-selftest.sh's (ea1), which pins the same shape against the writer.
  echo "2026-01-01T00:00:00Z | entry | ledger=$AUDIT/$2.jsonl | lines=2 | session=$2" >> "$PROG"
}
# The same file WITHOUT the entry row — a build that never attested, which is the state both
# runs that motivated #416 were in.
write_progress_unattested() { # write_progress_unattested <run-id> <session-id>
  cat > "$PROG" <<EOF
# lean run — issue 7

run_id: $1
session_id: $2
issue: 7
EOF
  echo "2026-01-01T00:00:00Z | milestone-4 | satisfied" >> "$PROG"
}

# `reviewed_head` defaults to the head at WRITE time, which is the commit the record is about to
# be committed on top of — the real shape, and the one the descent check is written against.
write_verdict() { # write_verdict <run-id> <session-id> [reviewed-head]
  cat > "$VERDICT" <<EOF
# lean review verdict — #7

verdict=approve
run_id: $1
session_id: $2
rounds: 1
reviewed_head: ${3:-$(git -C "$TREE" rev-parse HEAD)}

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

# ---- (L) the record must declare, coherently, the head it reviewed --------------------------
# The third reader of `reviewed_head`. What this one adds over milestone 4 and the CI gate is
# COHERENCE rather than currency: they compare the declared head against a head that keeps
# moving, whereas a record whose own commit does not descend from the commit it names is
# self-contradictory wherever the branch has since gone.
cat > "$VERDICT" <<EOF
# lean review verdict — #7

verdict=approve
run_id: $REVIEW_RUN_ID
session_id: $REVIEW_SESSION
rounds: 1
EOF
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no reviewed_head key'; then
  pass "(L1) a verdict record declaring no reviewed head fails (the pre-key migration case)"
else fail "(L1) expected rc=1 on a head-less verdict, got $rc: $out"; fi

# A head the record CANNOT have been written on top of: a commit that lands after the one
# carrying the record. Distinct from a merely stale declaration, which the two currency readers
# own — this one is incoherent on its own terms and stays incoherent forever.
printf 'later\n' > "$TREE/docs/plans/later.md"
git -C "$TREE" add docs/plans/later.md >/dev/null 2>&1
git -C "$TREE" commit -q -m "a commit landing after the verdict" >/dev/null 2>&1
write_verdict "$REVIEW_RUN_ID" "$REVIEW_SESSION" "$(git -C "$TREE" rev-parse HEAD)"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'does not descend from it'; then
  pass "(L2) a record whose commit does not descend from the head it names fails"
else fail "(L2) expected rc=1 on an incoherent reviewed_head, got $rc: $out"; fi

# ...and the same record reconciles once it names a head its commit actually descends from, so
# (L1)/(L2) are checks with a remedy rather than a wall.
write_verdict "$REVIEW_RUN_ID" "$REVIEW_SESSION"
commit_verdict "2026-01-01T10:00:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'declares reviewed_head'; then
  pass "(L3) a coherently-declared reviewed head reconciles, and the tool says so"
else fail "(L3) expected rc=0 on a coherent record, got $rc: $out"; fi

# The (L) block's own premise: its records carry no `reviewed_patch_id`, so they route to the
# ancestry fallback. Asserted rather than assumed — a fixture writer that quietly grew the key
# would migrate the whole block to the (M) arm and leave the fallback uncovered, all green.
if ! grep -q 'reviewed_patch_id' "$VERDICT" 2>/dev/null; then
  pass "(L4) the (L) records carry no reviewed_patch_id, so that block does gate on the ancestry fallback"
else fail "(L4) the (L) block is no longer exercising the ancestry fallback: $(cat "$VERDICT" 2>/dev/null)"; fi

# ---- (M) the record declares the PATCH it reviewed, and its commit hashes to the same --------
# The ancestry check above is what turned a rebase into a "do NOT merge": after one, the record's
# replayed commit descends from no pre-rebase head, so a coherent record became incoherent
# through an operation that changed no reviewed line. Patch identity states the same claim —
# the record was written on top of the tree it reviewed — without keying it on a commit SHA.
#
# The expected value is derived here rather than read back from the tool. That is an ORACLE, not
# the banned mirror-harness shape: a copy is dangerous when production drifting away from it
# leaves the suite green, and this one does the opposite — any change to the base, the range or
# the exclusion makes the two disagree and reds every (M) case.
tree_patch_id() { # tree_patch_id <head-ish>
  git -C "$TREE" diff "$(git -C "$TREE" merge-base refs/remotes/origin/main "$1" 2>/dev/null)" "$1" \
    -- . ":(exclude)docs/plans/acme-7-lean-verdict.md" 2>/dev/null \
    | git -C "$TREE" patch-id --stable 2>/dev/null | cut -d' ' -f1
}
write_verdict_pid() { # write_verdict_pid <patch-id> [reviewed-head]
  cat > "$VERDICT" <<EOF
# lean review verdict — #7

verdict=approve
run_id: $REVIEW_RUN_ID
session_id: $REVIEW_SESSION
rounds: 1
reviewed_head: ${2:-$(git -C "$TREE" rev-parse HEAD)}
reviewed_patch_id: $1

No blockers.
EOF
}

m_pid="$(tree_patch_id HEAD)"
[ -n "$m_pid" ] || fail "(M0) the fixture's patch identity is empty — every (M) case would compare nothing"
write_verdict_pid "$m_pid"
commit_verdict "2026-01-01T10:30:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'declares reviewed_patch_id'; then
  pass "(M1) a record declaring the patch it reviewed reconciles, and the tool names the patch-id arm"
else fail "(M1) expected rc=0 on a coherent patch id, got $rc: $out"; fi

# THE case the ancestry arm gets wrong. A REAL rebase onto a base that moved with content: the
# base advancing by an empty commit would leave the trees identical and prove nothing.
m_pre_rebase="$(git -C "$TREE" rev-parse HEAD)"
m_branch="$(git -C "$TREE" symbolic-ref --short HEAD 2>/dev/null)"
git -C "$TREE" branch -f m-base refs/remotes/origin/main >/dev/null 2>&1
git -C "$TREE" checkout -q m-base 2>/dev/null
printf 'the base moved while the review was in flight\n' > "$TREE/base-moved.txt"
git -C "$TREE" add base-moved.txt >/dev/null 2>&1
git -C "$TREE" commit -q -m 'base advances' >/dev/null 2>&1
git -C "$TREE" update-ref refs/remotes/origin/main m-base
git -C "$TREE" checkout -q "$m_branch" 2>/dev/null
git -C "$TREE" rebase -q m-base >/dev/null 2>&1; m_rebased=$?
# Non-vacuity: the ancestry arm would red here. The pre-rebase commit is still an object in this
# repo, so its `cat-file -e` would pass — but the record's replayed commit no longer descends
# from it, which is the predicate (L2) fails on.
git -C "$TREE" merge-base --is-ancestor "$m_pre_rebase" HEAD 2>/dev/null && m_ancestry_ok=1 || m_ancestry_ok=0
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$m_rebased" -eq 0 ] && [ "$m_ancestry_ok" -eq 0 ] && [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q 'declares reviewed_patch_id'; then
  pass "(M2) a rebase that replays the branch unchanged still reconciles, though the ancestry arm would have failed it"
else fail "(M2) rebase=$m_rebased ancestry-still-holds=$m_ancestry_ok rc=$rc: $out"; fi

# ...and the arm is still a check. A record whose commit hashes to a different patch is
# incoherent on its own terms, exactly as (L2) is for the ancestry keying.
write_verdict_pid "0000000000000000000000000000000000000000"
commit_verdict "2026-01-01T11:00:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'was not written on top of the tree'; then
  pass "(M3) a record whose declared patch is not the one its commit carries fails"
else fail "(M3) expected rc=1 on an incoherent patch id, got $rc: $out"; fi

# ---- (N) the INHERITANCE chain: resolvable links AND independent authors (#375) -------------
# Link resolution is checked by all three readers, so it is asserted here too — a third reader
# that disagreed about it would diverge silently. The AUTHOR arm is this reader's alone, and it
# is the one inheritance makes consequential: a chain whose rounds share a review session
# resolves perfectly while being a single review that credited itself with the whole tree.
write_verdict_chain() { # write_verdict_chain <run-id> <session-id> <rounds> <patch-id> [inherited-id] [body]
  {
    printf '# lean review verdict — #7\n\nverdict=approve\nrun_id: %s\nsession_id: %s\nrounds: %s\nreviewed_head: %s\nreviewed_patch_id: %s\n' \
      "$1" "$2" "$3" "$(git -C "$TREE" rev-parse HEAD)" "$4"
    [ -n "${5:-}" ] && printf 'inherited_patch_id: %s\ninherited_from_verdict: %s\n' "$5" "$(git -C "$TREE" rev-parse HEAD)"
    # The blank line here is what separates header from body, and (N7) turns on it.
    printf '\n%s\n' "${6:-No blockers.}"
  } > "$VERDICT"
}
n_code_commit() { # n_code_commit <content>
  printf '%s\n' "$1" > "$TREE/docs/plans/base.md"
  git -C "$TREE" add docs/plans/base.md >/dev/null 2>&1
  git -C "$TREE" commit -q -m "code moves between rounds" >/dev/null 2>&1
}
# A ledger for the SECOND review session, so (N)'s round-2 records reconcile on every arm but
# the one each case is about.
write_ledger sess-review-round2 "2026-01-01T09:00:00Z"

# ROUND 1, a chain root. Absence of the key is the ordinary case and is PRINTED, not skipped:
# in a log, a silent skip and a satisfied check are indistinguishable.
n_pid1="$(tree_patch_id HEAD)"
write_verdict_chain "$REVIEW_RUN_ID" "$REVIEW_SESSION" 1 "$n_pid1"
commit_verdict "2026-01-01T10:00:00Z"
n_pid1="$(tree_patch_id HEAD)"
write_verdict_chain "$REVIEW_RUN_ID" "$REVIEW_SESSION" 1 "$n_pid1"
commit_verdict "2026-01-01T10:05:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'declares no inherited coverage'; then
  pass "(N1) a round-1 record reconciles unchanged, and the tool prints that it inherited nothing"
else fail "(N1) expected rc=0 with the no-inheritance note, got $rc: $out"; fi

# ROUND 2, inheriting round 1 from its OWN review session — the shape a correct fix round has.
n_code_commit "the fix round 1 asked for"
n_pid2="$(tree_patch_id HEAD)"
[ "$n_pid2" != "$n_pid1" ] || fail "(N2-fixture) the fix did not move the patch identity — (N2) would assert nothing"
write_verdict_chain review-7-2 sess-review-round2 2 "$n_pid2" "$n_pid1"
commit_verdict "2026-01-01T11:30:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'resolves over 1 earlier record'; then
  pass "(N2) AC-8: a two-round chain with distinct review sessions reconciles"
else fail "(N2) expected rc=0 on a clean chain, got $rc: $out"; fi

# ...and the link is still checked here, not merely at the other two readers.
write_verdict_chain review-7-2 sess-review-round2 2 "$n_pid2" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
commit_verdict "2026-01-01T11:40:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'matches no earlier verdict record committed on this branch'; then
  pass "(N3) a dangling inheritance link fails reconciliation"
else fail "(N3) expected rc=1 on a dangling link, got $rc: $out"; fi

# THE arm only this reader has. Everything resolves; the two rounds are one session. The other
# two readers pass this record — that is the point, and why the check lives here.
write_verdict_chain review-7-2 "$REVIEW_SESSION" 2 "$n_pid2" "$n_pid1"
commit_verdict "2026-01-01T11:50:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'already authored another round in this chain'; then
  pass "(N4) a chain whose rounds share one review session is refused — inherited coverage must come from an independent review"
else fail "(N4) expected rc=1 on a single-session chain, got $rc: $out"; fi

# And the P10 half: coverage inherited from a round the BUILD session authored is not
# independent coverage, however well the link resolves.
write_verdict_chain "$REVIEW_RUN_ID" "$SESSION" 1 "$n_pid1"
commit_verdict "2026-01-01T12:10:00Z"
n_pid_build="$(tree_patch_id HEAD)"
write_verdict_chain review-7-2 sess-review-round2 2 "$n_pid_build" "$n_pid1"
commit_verdict "2026-01-01T12:20:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'names the BUILD session'; then
  pass "(N5) inheriting from a round the build session authored is refused (P10)"
else fail "(N5) expected rc=1 inheriting a build-authored round, got $rc: $out"; fi

# SELF-INHERITANCE, and the case that makes the backwards window a guard rather than a comment.
# A record whose inherited_patch_id IS its own reviewed_patch_id claims to have inherited the
# coverage of the very tree it is reviewing. The window starts strictly BELOW the record's own
# commit, so the search finds no earlier record and refuses on the link.
#
# The assertion pins WHICH refusal, not merely that one happened. Widen the window to include
# the record itself and the walk resolves the round to ITSELF, then trips the shared-session arm
# instead — same exit code, a diagnosis pointing at the wrong thing, and a "link" that is the
# record under test. A bare rc check cannot tell those apart.
n_code_commit "a tree no earlier round reviewed"
n_pid_self="$(tree_patch_id HEAD)"
write_verdict_chain review-7-3 sess-review-round2 3 "$n_pid_self" "$n_pid_self"
commit_verdict "2026-01-01T12:40:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'matches no earlier verdict record committed on this branch' \
   && ! printf '%s' "$out" | grep -q 'already authored another round in this chain'; then
  pass "(N6) a record inheriting its OWN reviewed patch is refused on the link — the search window never includes the record being read"
else fail "(N6) expected the link refusal on a self-inheriting record, got $rc: $out"; fi

# The record's own FINDINGS cannot supply the key this arm gates on. It is the schema's one
# conditionally-emitted key, so on a chain ROOT nothing authentic is written and the documented
# "the header wins first-match" mitigation has no entrant — the first match in the file is the
# reviewer's prose. Reached in production: a root record written by the real writer took the
# merge boundary red on a value quoted inside its own repro block, and this reader shares the
# extraction, so it read the same wrong value.
#
# The quoted value RESOLVES (it is round 1's real reviewed patch), which makes the guarded
# failure the SILENT one: both readings exit 0 and print a checkmark, and only the phrase
# separates a root from a round credited with coverage no review performed.
n_code_commit "a tree for the injection cases"
n_pid_root="$(tree_patch_id HEAD)"
write_verdict_chain review-7-4 sess-review-round2 4 "$n_pid_root" "" "## a finding about the chain

\`\`\`
inherited_patch_id: $n_pid1
\`\`\`"
commit_verdict "2026-01-01T13:00:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'declares no inherited coverage' \
   && ! printf '%s' "$out" | grep -q 'the inheritance chain resolves over'; then
  pass "(N7) a root record whose findings quote a RESOLVING inheritance value still reconciles as a root"
else fail "(N7) expected the no-inheritance note and no resolved chain, got $rc: $out"; fi

# The same door one level down: a chain walk reads PRIOR records through the same extraction, and
# a prior record may predate the sentinel — every branch in flight when this ships carries one.
# Round 5's own link is honest and resolves to the root above; that root's BODY quotes round 1.
# A first-match walk follows it into a second link, reports a chain one round longer than the
# branch has, and exits 0 — so the assertion pins the COUNT, which is why the count is printed.
write_ledger sess-review-round5 "2026-01-01T13:10:00Z"
n_code_commit "the round-4 fix"
n_pid5="$(tree_patch_id HEAD)"
write_verdict_chain review-7-5 sess-review-round5 5 "$n_pid5" "$n_pid_root"
commit_verdict "2026-01-01T13:20:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'resolves over 1 earlier record'; then
  pass "(N7b) the walk terminates at a root whose body quotes the key — one link, not the two a first-match walk would count"
else fail "(N7b) expected exactly 1 earlier record in the chain, got $rc: $out"; fi

# ---- (P) the tracker adapter: jira drops ONE arm, not all of them (#388) --------------------
# Before this, the comment fetch ran unconditionally and its `exit 2` killed the script before
# every other check — the arms that read only git, the progress file, the verdict record and the
# audit ledger, including the P10 authorship check, which needs no tracker at all. The suite
# enters (P) with a green round-5 chain, so every case below starts from evidence that is
# COMPLETE on the tracker-independent arms; only the case's own fixture is broken.
#
# "Zero gh calls" is asserted through a recording stub reachable BOTH ways — the `${GH:-gh}` seam
# and a `gh` earlier on PATH — so a jira arm that still shelled out to a reachable CLI is caught
# rather than passing an rc-only check that a fixture happened to satisfy.
GH_CALLS="$WORK/gh-calls"
GHSTUB="$WORK/gh-stub.sh"
cat > "$GHSTUB" <<EOF
#!/usr/bin/env bash
echo "called" >> "$GH_CALLS"
cat "$WORK/comments-good.json"
EOF
chmod +x "$GHSTUB"
mkdir -p "$WORK/bin" && cp "$GHSTUB" "$WORK/bin/gh"

jq '. + {tracker: {type: "jira"}}'   "$CFG" > "$WORK/config-jira.json"
jq '. + {tracker: {type: "github"}}' "$CFG" > "$WORK/config-github.json"
jq '. + {tracker: {type: "gitlab"}}' "$CFG" > "$WORK/config-bogus.json"

reconcile_as() { # reconcile_as <config> [extra args...]
  local c="$1"; shift
  ( cd "$TREE" && SECOND_SHIFT_CONFIG="$c" LEAN_PROGRESS_FILE="$PROG" LEAN_AUDIT_DIR="$AUDIT" \
    GH="$GHSTUB" PATH="$WORK/bin:$PATH" bash "$TOOL" 7 "$@" 2>&1 )
}
p_restore() { # p_restore <committer-date> — put the good round-5 record back
  write_verdict_chain review-7-5 sess-review-round5 5 "$n_pid5" "$n_pid_root"
  commit_verdict "$1"
}

# (P1) the whole point: a complete evidence set reconciles under jira, having read no tracker.
# The chain assertion is the non-vacuity half — it proves checks (2)-(6) RAN, where a script that
# skipped them alongside the fetch would also exit 0.
: > "$GH_CALLS"
out="$(reconcile_as "$WORK/config-jira.json")"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$GH_CALLS" ] \
   && printf '%s' "$out" | grep -q 'claim-comment arm NOT RUN' \
   && printf '%s' "$out" | grep -q 'REDUCED evidence' \
   && printf '%s' "$out" | grep -q 'resolves over 1 earlier record'; then
  pass "(P1) a jira consumer reconciles with zero gh calls, names the arm it skipped, and still runs every other"
else fail "(P1) expected rc=0, no gh call, the disclosure and the chain arm, got rc=$rc calls='$(cat "$GH_CALLS" 2>/dev/null)': $out"; fi

# (P2) the default is ASSERTED, not assumed: an absent `tracker.type` takes the github arm — it
# FETCHES — and is byte-identical to an explicit `github`. A default that silently became jira
# would downgrade every existing consumer's evidence set with nothing red.
: > "$GH_CALLS"
out_absent="$(reconcile_as "$CFG")"; rc=$?
p_calls="$(wc -l < "$GH_CALLS" | tr -d ' ')"
out_github="$(reconcile_as "$WORK/config-github.json")"; rc_github=$?
if [ "$rc" -eq 0 ] && [ "$p_calls" -ge 1 ] && [ "$rc_github" -eq 0 ] \
   && [ "$out_absent" = "$out_github" ] \
   && ! printf '%s' "$out_absent" | grep -q 'NOT RUN'; then
  pass "(P2) an absent tracker.type fetches the comment trail and reads identically to an explicit github"
else fail "(P2) absent-key rc=$rc calls=$p_calls github rc=$rc_github, outputs differ? got: $out_absent"; fi

# (P3) an UNRECOGNIZED value is a loud environment error, not a fall-through to either arm. The
# second assertion pins that it refuses BEFORE any check runs — a typo must not quietly pick the
# arm that attests less.
out="$(reconcile_as "$WORK/config-bogus.json")"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "unknown tracker.type 'gitlab'" \
   && ! printf '%s' "$out" | grep -q 'reconciling #'; then
  pass "(P3) an unrecognized tracker.type is rc=2 before any check runs"
else fail "(P3) expected rc=2 on an unknown tracker.type, got $rc: $out"; fi

# (P4) the github arm's fixture seam is REFUSED under jira rather than ignored. Ignoring it would
# let a jira case hand over a comment trail, go green, and assert nothing about it — and nothing
# would red if a later edit re-enabled the fetch.
out="$(reconcile_as "$WORK/config-jira.json" --comments-file "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'not meaningful under tracker.type: jira'; then
  pass "(P4) --comments-file under jira is refused, not silently ignored"
else fail "(P4) expected rc=2 refusing the seam under jira, got $rc: $out"; fi

# (P5)-(P9) each of the five surviving arms still FAILS on its own broken evidence under jira.
# Without these, (P1) alone cannot distinguish "the checks run" from "the checks were skipped
# along with the fetch" — both exit 0 on a healthy fixture.
write_verdict_chain "$RUN_ID" sess-review-round5 5 "$n_pid5" "$n_pid_root"
commit_verdict "2026-01-01T14:00:00Z"
out="$(reconcile_as "$WORK/config-jira.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "BUILD run's identity"; then
  pass "(P5) (1b) P10 still fails under jira — the arm the early exit_2 was costing most"
else fail "(P5) expected rc=1 on a build-authored verdict under jira, got $rc: $out"; fi
p_restore "2026-01-01T14:05:00Z"

mv "$AUDIT/sess-review-round5.jsonl" "$WORK/held-r5.jsonl"
out="$(reconcile_as "$WORK/config-jira.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no review-session audit ledger'; then
  pass "(P6) (2) a verdict naming a session the harness never saw still fails under jira"
else fail "(P6) expected rc=1 on an absent review ledger under jira, got $rc: $out"; fi
mv "$WORK/held-r5.jsonl" "$AUDIT/sess-review-round5.jsonl"

write_ledger sess-review-round5 "2026-06-01T00:00:00Z"
out="$(reconcile_as "$WORK/config-jira.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'timestamp inversion'; then
  pass "(P7) (3) a verdict committed before its review ran still fails under jira"
else fail "(P7) expected rc=1 on timestamp inversion under jira, got $rc: $out"; fi
write_ledger sess-review-round5 "2026-01-01T13:10:00Z"

write_verdict_chain review-7-5 sess-review-round5 5 "0000000000000000000000000000000000000000" "$n_pid_root"
commit_verdict "2026-01-01T14:10:00Z"
out="$(reconcile_as "$WORK/config-jira.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'was not written on top of the tree'; then
  pass "(P8) (4/5) a record declaring a patch its commit does not carry still fails under jira"
else fail "(P8) expected rc=1 on an incoherent patch id under jira, got $rc: $out"; fi
p_restore "2026-01-01T14:15:00Z"

write_verdict_chain review-7-5 sess-review-round5 5 "$n_pid5" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
commit_verdict "2026-01-01T14:20:00Z"
out="$(reconcile_as "$WORK/config-jira.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'matches no earlier verdict record committed on this branch'; then
  pass "(P9) (6) a dangling inheritance link still fails under jira"
else fail "(P9) expected rc=1 on a dangling link under jira, got $rc: $out"; fi
p_restore "2026-01-01T14:25:00Z"

# ---- (R) the SHIPPED ledger path, with the REAL hook as its writer ---------------------------
# Every case above sets LEAN_AUDIT_DIR, so the default resolution — `--git-common-dir/..`, the
# only one a real operator run takes — is exercised by nothing here, and the ledger it points at
# is synthesized by write_ledger(), which agrees with the reader by construction.
#
# That pair of gaps hid a live defect: the audit hook wrote beside the WORKTREE while this
# script reads the main checkout, so a review session that ran in a worktree produced a verdict
# naming a session with no ledger anywhere — reported as "the verdict record names a session the
# harness has no record of", a forgery signal fired on an honest review.
#
# So this case drops the seam and drives the REAL hook from a linked worktree. The cross-plugin
# reach is the point: a local copy of the writer's path logic could not fail on a writer edit.
#
# Asserted on the ledger ARM, not on the exit code. The other arms have their own fixtures
# above, and binding this case to a fully-green run would make it fail for reasons that are not
# about where the ledger lives — the failure mode this suite exists to keep attributable.
#
# Reaching the sibling takes a LADDER, not a fixed hop count: plugins sit adjacent under
# `plugins/` in the marketplace repo but are separated by a version segment in an install
# cache (`<root>/<plugin>/<version>/...`). A fixed `../../../` resolves only in the first, so
# from every install this case took its not-found branch and red the suite — the exact class
# tools/install-topology-selftest.sh stages for. Same ladder as check-model-tiers.sh's
# resolve_sibling_plugin_root(). NOT a lockstep pair with the copy in lean-gate-selftest.sh:
# each suite resolves its own sibling independently and drift between them breaks nothing —
# the shared thing is a technique, not a contract.
HOOK_REPO="$HERE/../../../audit-toolkit/hooks/audit-tool-calls.sh"
HOOK="$HOOK_REPO"
if [ ! -x "$HOOK" ]; then
  # Cache layout: the HIGHEST staged version that actually carries the hook. Glob order is
  # lexical, so a bare `tail -1` ranked 9.0.0 above 10.0.0. The version is two dirs up from
  # the hook, so it is keyed out explicitly rather than sorted on the whole path.
  HOOK="$(for c in "$HERE"/../../../../audit-toolkit/*/hooks/audit-tool-calls.sh; do
    [ -x "$c" ] || continue
    printf '%s\t%s\n' "$(basename "$(dirname "$(dirname "$c")")")" "$c"
  done | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -f2-)"
fi
if [ ! -x "$HOOK" ]; then
  fail "(R) audit hook not found — searched $HOOK_REPO and $HERE/../../../../audit-toolkit/<version>/hooks/audit-tool-calls.sh; the writer half of the ledger contract is unreachable"
else
  WT_REC="$WORK/wt-rec"
  REVIEW_SESSION_WT="sess-review-worktree"
  write_progress "$RUN_ID" "$SESSION"
  write_verdict "$REVIEW_RUN_ID" "$REVIEW_SESSION_WT"
  commit_verdict "2026-01-01T15:00:00Z"
  git -C "$TREE" worktree add -q -b wt-rec "$WT_REC" >/dev/null 2>&1
  if [ ! -d "$WT_REC" ]; then
    fail "(R) could not create a linked worktree on the fixture repo"
  else
    printf '%s' "{\"session_id\":\"$REVIEW_SESSION_WT\",\"cwd\":\"$WT_REC\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WT_REC/x\"}}" \
      | CLAUDE_PROJECT_DIR="$WT_REC" "$HOOK"
    out="$( cd "$WT_REC" && SECOND_SHIFT_CONFIG="$CFG" LEAN_PROGRESS_FILE="$PROG" \
            bash "$TOOL" 7 --comments-file "$WORK/comments-good.json" 2>&1 )"
    if printf '%s' "$out" | grep -q "review session $REVIEW_SESSION_WT is distinct from the build session and has a live ledger" \
       && ! printf '%s' "$out" | grep -q 'no review-session audit ledger'; then
      pass "(R) the default ledger path resolves a worktree-run review session's REAL hook ledger"
    else
      fail "(R) the shipped ledger path did not find the hook's own output: $out"
    fi
  fi
fi
# ---- (Q) the build entry attestation (#416) --------------------------------------------------
# The arm that catches an unattested build AFTER the fact — the only route there is, since the
# gate's own precondition binds the build host and only from the release it shipped in. This is
# how #416 was found: two merged runs whose progress files begin at `claim`.
#
# The pairing is what makes it an arm rather than a decoration. Everything else about this
# fixture is the fully-consistent (A) state, so the ONLY difference between red and green here
# is the row.
write_progress_unattested "$RUN_ID" "$SESSION"
write_verdict "$REVIEW_RUN_ID" "$REVIEW_SESSION"
write_ledger "$SESSION" "2026-01-01T05:00:00Z"
write_ledger "$REVIEW_SESSION" "2026-01-01T06:00:00Z"
commit_verdict "2026-01-01T15:00:00Z"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no entry attestation'; then
  pass "(Q) a progress file with no entry row fails — nothing attests the build's ledger was live"
else fail "(Q) expected rc=1 on an unattested build, got $rc: $out"; fi

write_progress "$RUN_ID" "$SESSION"
out="$(reconcile "$WORK/comments-good.json")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'recorded an entry attestation'; then
  pass "(Q) ...and the identical run passes once the row is there — the arm turns on the row alone"
else fail "(Q) expected rc=0 with the entry row present, got $rc: $out"; fi

# ---- (O) --help prints the header, and only the header --------------------------------------
# `sed -n '2,Np'` is a hand-maintained line number, and this file had no guard for it — which is
# exactly how its siblings silently truncated their own help text after a header grew. Two
# assertions, because either direction is a real failure AND because the repo's two lanes kill
# the `cmp-z` mutant of this line by opposite halves: on BSD sed `-z` dies and only the presence
# assertion fires, on GNU sed `-z` dumps the whole file and only the absence one does.
out="$(bash "$TOOL" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q 'Exit 0 = reconciled' \
   && ! printf '%s' "$out" | grep -q '^set -uo pipefail'; then
  pass "(O) --help prints through the last header line and stops before the code"
else fail "(O) --help did not print exactly the header, rc=$rc: $out"; fi

# ---- (I) header states the #292 deferral ----------------------------------------------------
if grep -q 'DEFERS TO #292' "$TOOL"; then
  pass "(I) the script records that it defers to the general verifier (#292) on arrival"
else fail "(I) no #292 deferral recorded in the header"; fi

echo "[lean-reconcile-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

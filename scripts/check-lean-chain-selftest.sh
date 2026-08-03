#!/usr/bin/env bash
# check-lean-chain-selftest.sh — behavioral suite for the lean merge-boundary gate.
#
# Zero-network by construction: every case drives check-lean-chain.sh through its two fixture
# seams (--comments-file, --diff-files-file), following the check-pipeline-chain-selftest.sh
# precedent. No `gh`, no git remote.
#
# The two cases the acceptance criteria name explicitly are (C) and (D) — they are the ones
# that make this gate non-vacuous and non-double-classifying, and each has a failure mode that
# a prefix-only reading would miss:
#   (C) a ZERO-MATCHING lean prefix with lean artifacts present must STILL be applicable —
#       otherwise a stale constant silently exempts every lean PR.
#   (D) a PIPELINE-prefixed PR carrying lean-shaped files must NOT be applicable — otherwise
#       the PR delivering this very feature red-lines itself on its own fixtures.
#
# Exit code = number of failed checks (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/check-lean-chain.sh"

FAILS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1" >&2; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d -t leanchain.XXXXXX)"
# shellcheck disable=SC2317,SC2329  # invoked indirectly by the EXIT trap below.
# BOTH codes: shellcheck >=0.10 reports SC2329 on the function, 0.9 (CI) reports SC2317 on
# each command in the body — suppressing only the newer one is clean locally and reds CI.
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# ---------------------------------------------------------------- fixtures
BOT_CLAIM_AT='2026-01-01T00:00:00Z'
PR_OPEN_AT='2026-01-02T00:00:00Z'

cat > "$WORK/comments-good.json" <<EOF
[
  { "user": { "type": "Bot", "login": "acme-bot" },
    "created_at": "$BOT_CLAIM_AT",
    "body": "<!-- dev-pipeline -->\n<!-- run_id: r-abc123 -->\n<!-- stage: lean-claimed -->\n\nClaimed." }
]
EOF

# The claim exists but was posted by a HUMAN — the trust filter must reject it. This is the
# drive-by-comment case: on a public repo anyone can post a marker.
cat > "$WORK/comments-human.json" <<EOF
[
  { "user": { "type": "User", "login": "someone" },
    "created_at": "$BOT_CLAIM_AT",
    "body": "<!-- stage: lean-claimed -->\n<!-- run_id: r-abc123 -->" }
]
EOF

# A bot claim posted AFTER the PR opened — outside the window, so not evidence for this PR.
cat > "$WORK/comments-late.json" <<EOF
[
  { "user": { "type": "Bot", "login": "acme-bot" },
    "created_at": "2026-06-01T00:00:00Z",
    "body": "<!-- stage: lean-claimed -->\n<!-- run_id: r-late -->" }
]
EOF

# A claim written by the CURRENT claim writer, which carries the build SESSION id alongside
# the run id. comments-good.json deliberately keeps the OLD shape: claims posted before that
# change sit on already-open PRs and cannot be re-posted (the window is anchored at the
# immutable PR-open time), so the gate must still pass on them. (N7) pins that; (N6) pins the
# stronger comparison the new shape enables.
cat > "$WORK/comments-sess.json" <<EOF
[
  { "user": { "type": "Bot", "login": "acme-bot" },
    "created_at": "$BOT_CLAIM_AT",
    "body": "<!-- dev-pipeline -->\n<!-- run_id: r-abc123 -->\n<!-- session_id: sess-build-1 -->\n<!-- stage: lean-claimed -->\n\nClaimed." }
]
EOF

# A bot claim inside the window carrying NO run_id: the build identity is then unknown, so the
# verdict's independence is uncheckable — and an uncheckable claim must not read as satisfied.
cat > "$WORK/comments-norunid.json" <<EOF
[
  { "user": { "type": "Bot", "login": "acme-bot" },
    "created_at": "$BOT_CLAIM_AT",
    "body": "<!-- dev-pipeline -->\n<!-- stage: lean-claimed -->\n\nClaimed." }
]
EOF

echo '[]' > "$WORK/comments-empty.json"

# Committed artifacts live in a throwaway git repo so the gate's `git rev-parse` and its
# find-based artifact scan operate on a controlled tree rather than the real repo.
TREE="$WORK/tree"
VREC="$TREE/docs/plans/acme-42-lean-verdict.md"
mkdir -p "$TREE/docs/plans" "$TREE/scripts/fixtures"
git -C "$TREE" init -q 2>/dev/null
git -C "$TREE" config user.email lean@example.invalid
git -C "$TREE" config user.name lean-selftest

# The fixture carries real COMMITS, not just files. Evidence 5 measures the verdict record's
# commit against the PR head, so a commit-less tree would make every freshness assertion
# vacuous — and the happy path red for a reason that has nothing to do with what it asserts.
# `add -A` is safe here and nowhere else: this is a throwaway repo under $WORK.
commit_tree() { # commit_tree <message>
  git -C "$TREE" add -A >/dev/null 2>&1
  git -C "$TREE" commit -q --allow-empty -m "$1" >/dev/null 2>&1
}

printf '# lean spec\n\n- AC-1: does a thing\n- AC-2: does another\n' > "$TREE/docs/plans/acme-42-lean.md"
# The build claim carries r-abc123; the verdict is REVIEW-authored, so it carries its own
# identity and names its own session. A verdict reusing r-abc123 is case (N).
#
# Every writer here COMMITS, because the record's commit is what evidence 5 reads. A helper
# that only wrote the file would leave the record uncommitted and every case downstream would
# collect a spurious second violation.
write_verdict() { # write_verdict [verdict] [run-id] [session-id]
  printf 'verdict=%s\nrun_id: %s\nsession_id: %s\nrounds: 1\n' \
    "${1:-approve}" "${2:-r-review-1}" "${3:-sess-review-1}" > "$VREC"
  commit_tree "verdict ${1:-approve}"
}
write_verdict_literal() { # write_verdict_literal <full-record-body>
  printf '%s' "$1" > "$VREC"
  commit_tree "verdict (literal fixture)"
}
# A lean-SHAPED fixture that must never count as a real artifact.
printf '# fixture\n- AC-9: fixture only\n' > "$TREE/scripts/fixtures/acme-99-lean.md"
commit_tree "spec + fixtures"
# The verdict is written LAST so the baseline tree is the state a real branch is in when the
# review session has just pushed: the record's commit IS the head. Writing it before the other
# artifacts would leave the fixture one commit stale and red (A) on evidence 5 — correctly, but
# for a reason (A) is not about.
write_verdict

printf 'docs/plans/acme-42-lean.md\ndocs/plans/acme-42-lean-verdict.md\n' > "$WORK/diff-lean.txt"
printf 'scripts/fixtures/acme-99-lean.md\nplugins/dev-pipeline/skills/run-lean/lean-gate.sh\n' > "$WORK/diff-fixture-only.txt"
printf 'README.md\n' > "$WORK/diff-plain.txt"

BODY_GOOD='Implements the thing.

Closes #42'

# PR_HEAD_SHA is resolved per call, never captured once: cases below add commits, and a stale
# sha would silently measure freshness against an earlier head than the one under test.
run_gate() { # run_gate <head-ref> <comments-file> <diff-file> [lean-prefix]
  ( cd "$TREE" && \
    LEAN_BRANCH_PREFIX="${4:-lean/acme-}" \
    PIPELINE_BRANCH_PREFIX="claude/acme-" \
    PR_HEAD_REF="$1" \
    PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
    PR_BODY="$BODY_GOOD" \
    PR_CREATED_AT="$PR_OPEN_AT" \
    bash "$GATE" --comments-file "$2" --diff-files-file "$3" 2>&1 )
}

echo "[check-lean-chain-selftest]"

# ---- (A) happy path: lean-prefixed branch with all three artifacts -----------------------
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(A) lean PR with spec + approve-verdict + bot claim passes"
else fail "(A) expected rc=0, got $rc: $out"; fi

# ---- (B) a non-lean, non-pipeline PR is simply not applicable ----------------------------
out="$(run_gate "someone/hotfix" "$WORK/comments-empty.json" "$WORK/diff-plain.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'not applicable'; then
  pass "(B) ordinary PR is not applicable"
else fail "(B) expected a not-applicable exit 0, got rc=$rc: $out"; fi

# ---- (C) MANDATED: zero-matching prefix + lean artifacts still applies -------------------
# The self-neutralization case. With a prefix that matches no branch, a prefix-only gate would
# report "not applicable" and wave the PR through. The artifact arm must fire instead.
out="$(run_gate "some/other-branch" "$WORK/comments-empty.json" "$WORK/diff-lean.txt" "zzz-matches-nothing/")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'lean-artifact'; then
  pass "(C) zero-matching prefix + lean spec in diff ⇒ applicable via the artifact arm, and fails on the missing claim"
else fail "(C) expected rc=1 via the artifact arm, got rc=$rc: $out"; fi

# ---- (D) MANDATED: pipeline-prefixed PR carrying lean-shaped files is NOT applicable -----
# This is the PR that delivers run-lean itself: pipeline-authored, and it necessarily carries
# lean-shaped fixture files. Double-classifying it would make the feature unshippable.
out="$(run_gate "claude/acme-303" "$WORK/comments-empty.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'not applicable'; then
  pass "(D) pipeline-prefixed PR carrying lean-shaped files is not double-classified"
else fail "(D) expected a not-applicable exit 0, got rc=$rc: $out"; fi

# ---- (E) fixture paths are excluded from the artifact scan -------------------------------
out="$(run_gate "some/other-branch" "$WORK/comments-empty.json" "$WORK/diff-fixture-only.txt" "zzz-matches-nothing/")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'not applicable'; then
  pass "(E) a lean-shaped file under fixtures/ does not trigger applicability"
else fail "(E) expected fixture paths to be excluded, got rc=$rc: $out"; fi

# ---- (F) human-posted claim is rejected by the trust filter ------------------------------
out="$(run_gate "lean/acme-42" "$WORK/comments-human.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'none that are bot-authored'; then
  pass "(F) an operator-posted lean-claimed comment is not accepted as evidence"
else fail "(F) expected the trust filter to reject a human claim, got rc=$rc: $out"; fi

# ---- (G) a claim posted after PR-open is outside the window ------------------------------
out="$(run_gate "lean/acme-42" "$WORK/comments-late.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ]; then pass "(G) a claim posted after PR-open is not evidence for this PR"
else fail "(G) expected rc=1 for an out-of-window claim, got $rc: $out"; fi

# ---- (H) missing verdict record fails ----------------------------------------------------
mv "$TREE/docs/plans/acme-42-lean-verdict.md" "$WORK/held-verdict.md"
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no committed verdict record'; then
  pass "(H) a lean PR with no committed verdict record fails"
else fail "(H) expected rc=1 on a missing verdict record, got rc=$rc: $out"; fi
mv "$WORK/held-verdict.md" "$TREE/docs/plans/acme-42-lean-verdict.md"

# ---- (I) a needs-work verdict is not an approval -----------------------------------------
write_verdict needs-work
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "reads 'verdict=needs-work', not 'verdict=approve'"; then
  pass "(I) a committed verdict=needs-work record blocks the merge boundary"
else fail "(I) expected rc=1 on verdict=needs-work, got rc=$rc: $out"; fi
write_verdict

# ---- (J) a spec with no AC-n fails -------------------------------------------------------
printf '# lean spec\n\nNo criteria here.\n' > "$TREE/docs/plans/acme-42-lean.md"; commit_tree 'spec without AC-n'
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no numbered AC-n'; then
  pass "(J) a committed spec with no AC-n fails (the definition of done must exist)"
else fail "(J) expected rc=1 on an AC-less spec, got rc=$rc: $out"; fi
printf '# lean spec\n\n- AC-1: does a thing\n' > "$TREE/docs/plans/acme-42-lean.md"; commit_tree 'spec restored'

# ---- (K) unresolvable constants are FATAL, never exempt ----------------------------------
out="$( cd "$TREE" && LEAN_BRANCH_PREFIX="" PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="lean/acme-42" PR_BODY="$BODY_GOOD" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ]; then pass "(K) an empty LEAN_BRANCH_PREFIX is an environment error, not a silent exemption"
else fail "(K) expected rc=2 on an unresolvable prefix, got $rc: $out"; fi

# ---- (L) mutually prefix-matching constants are FATAL ------------------------------------
# `lean/` derived from `claude/second-shift-` would satisfy a one-directional reading of the
# non-prefix-match property while making every pipeline PR applicable here.
out="$( cd "$TREE" && LEAN_BRANCH_PREFIX="claude/" PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'mutually non-prefix-matching'; then
  pass "(L) prefixes where one is a prefix of the other are rejected as an environment error"
else fail "(L) expected rc=2 on mutually prefix-matching constants, got $rc: $out"; fi

# ---- (M) a lean PR with no issue reference fails -----------------------------------------
out="$( cd "$TREE" && LEAN_BRANCH_PREFIX="lean/acme-" PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="lean/acme-42" PR_BODY="no reference here" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no resolvable issue reference'; then
  pass "(M) a lean PR with no 'Closes #N' fails rather than being exempted"
else fail "(M) expected rc=1 on an unresolvable issue reference, got $rc: $out"; fi

# ---- (N) MANDATED: the verdict must not carry the BUILD run's identity (P10) --------------
# The build run's identity at this boundary is the one in the bot claim comment — the only
# build-side record CI can see. A verdict reusing it means the session that wrote the code
# also wrote its own review, which is the whole thing the separation removes. Note this fails
# with every OTHER artifact present and correct: the authorship arm is load-bearing on its own,
# not a by-product of some other violation.
write_verdict approve r-abc123 sess-review-1
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "BUILD run's identity"; then
  pass "(N1) a verdict carrying the build claim's run_id is refused at the merge boundary"
else fail "(N1) expected rc=1 on a build-authored verdict, got rc=$rc: $out"; fi

# Missing reconciliation keys are refused for the same reason a missing verdict is: nothing is
# checkable, and an uncheckable claim must not read as a satisfied one.
write_verdict_literal 'verdict=approve
rounds: 1
'
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no run_id reconciliation key'; then
  pass "(N2) a verdict record with no run_id is refused"
else fail "(N2) expected rc=1 on a run_id-less verdict, got rc=$rc: $out"; fi

write_verdict_literal 'verdict=approve
run_id: r-review-1
rounds: 1
'
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no session_id reconciliation key'; then
  pass "(N3) a verdict record that names no review session is refused"
else fail "(N3) expected rc=1 on a session_id-less verdict, got rc=$rc: $out"; fi

# ...and the same PR passes once the verdict is review-authored and carries both keys. (A)
# already asserts the happy path, but re-asserting it HERE is what makes N1-N3 non-vacuous:
# without it they could all be failing for some unrelated reason introduced above.
write_verdict
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'authorship'; then
  pass "(N4) distinct identities carrying both keys pass, and the gate says so"
else fail "(N4) expected rc=0 with an authorship line, got rc=$rc: $out"; fi

# The claim comment is the other side of the comparison, and it can be missing an identity
# too. Folding this arm into the passing branch would silently treat "the build run is
# unknown" as "the verdict is independent" — the fail-open shape this whole section exists to
# prevent, one step upstream of where N1 looks for it.
out="$(run_gate "lean/acme-42" "$WORK/comments-norunid.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'carries no run_id, so the build'; then
  pass "(N5) a bot claim with no run_id is refused, not read as an independent verdict"
else fail "(N5) expected rc=1 on a run_id-less claim, got rc=$rc: $out"; fi

# The STRONGER arm. run_id is agent-CHOSEN, so a build session self-reviewing need only pick a
# second string; the session id is harness-assigned. A verdict naming the claim's session is
# refused even though its run_id is distinct — which is exactly the case N1 cannot catch.
write_verdict approve r-review-1 sess-build-1
out="$(run_gate "lean/acme-42" "$WORK/comments-sess.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'names the BUILD session'; then
  pass "(N6) a verdict naming the claim's session is refused despite a distinct run_id"
else fail "(N6) expected rc=1 on a build-session verdict, got rc=$rc: $out"; fi

# TRANSITIONAL, and asserted as a pass rather than left to chance. A claim posted before the
# writer emitted a session id cannot be re-posted — the window is anchored at the immutable
# PR-open time — so refusing here would strand those PRs with no action that clears the gate.
# The gate says which half of the comparison it could make.
write_verdict
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'only the run-id half'; then
  pass "(N7) a session_id-less claim still passes, and the gate names the half it could check"
else fail "(N7) expected rc=0 with the transitional note, got rc=$rc: $out"; fi

# ---- (O) evidence 5: the verdict must cover the head being merged ------------------------
# The record is a static file, so "an approve record exists" and "this code was approved" are
# different claims. Everything else in (A) is left exactly as it was — ONLY a later commit is
# added — so a green here would mean the freshness link is not carrying the check at all.
printf 'late change\n' > "$TREE/docs/plans/notes.md"
commit_tree "code lands after the verdict"
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'changed between that commit and the PR head'; then
  pass "(O1) a verdict that predates a later code commit is refused at the merge boundary"
else fail "(O1) expected rc=1 on a stale verdict, got rc=$rc: $out"; fi

# ...and re-reviewing clears it. Re-committing the SAME record moves it to the head commit,
# which is what a new review round does. Without this arm (O1) could be permanent breakage
# rather than a check with a remedy.
write_verdict approve r-review-2 sess-review-2
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'freshness'; then
  pass "(O2) a fresh review round over the same head clears it"
else fail "(O2) expected rc=0 after a new review round, got rc=$rc: $out"; fi

# ---- (P) the verdict VALUE is read first-match, never counted across the file -------------
# `lean-gate.sh verdict --summary-file` appends the reviewer's prose below the keys, and review
# prose discusses verdicts: the committed record for #237 carries the token twice for exactly
# this reason. A count-anywhere reader passes a record whose authoritative first line reads
# needs-work — a fail-OPEN on the single predicate this whole gate rests on.
write_verdict_literal 'verdict=needs-work
run_id: r-review-1
session_id: sess-review-1
rounds: 2

Round 1 returned verdict=approve; this round found a blocker and does not.
'
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "reads 'verdict=needs-work'"; then
  pass "(P) a needs-work record whose body quotes verdict=approve is still refused"
else fail "(P) expected rc=1 on a needs-work record with the token in its body, got rc=$rc: $out"; fi
write_verdict

# ---- (Q) the freshness check's own inputs fail CLOSED ------------------------------------
# Both guards anchor evidence 5, and dropping either one does not make the check fail — it
# makes it PASS. `git diff --name-only <commit> ""` errors out, `STALE` comes back empty, and
# the gate prints its ✓ freshness line having compared nothing. That is the same shape as the
# `verdict=` substring hole (P): a check that cannot run must not report a pass. Neither guard
# had a case; every other run_gate call resolves a live sha, so the failure paths were unreachable.
out="$( cd "$TREE" && LEAN_BRANCH_PREFIX="lean/acme-" PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="lean/acme-42" PR_BODY="$BODY_GOOD" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_SHA="" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'PR_HEAD_SHA is unset or empty'; then
  pass "(Q1) an empty PR_HEAD_SHA is an environment error, not an unmeasured freshness pass"
else fail "(Q1) expected rc=2 on an empty PR_HEAD_SHA, got $rc: $out"; fi

# A sha-shaped value that names no object in this checkout. Distinct from (Q1): the emptiness
# guard is satisfied, and only the object lookup stands between a bogus ref and a silent ✓.
out="$( cd "$TREE" && LEAN_BRANCH_PREFIX="lean/acme-" PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="lean/acme-42" PR_BODY="$BODY_GOOD" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_SHA="0000000000000000000000000000000000000000" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'is not a commit in this checkout'; then
  pass "(Q2) a PR_HEAD_SHA naming no object is an environment error, not a silent pass"
else fail "(Q2) expected rc=2 on an unresolvable PR_HEAD_SHA, got $rc: $out"; fi

echo "[check-lean-chain-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

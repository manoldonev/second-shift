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

# A base commit, and a remote-tracking ref pointing at it. Evidence 5's patch-id arm measures
# the branch's diff from merge-base(origin/<PR_BASE_REF>, head), so the fixture needs both — and
# the base must sit BELOW the spec, or the branch's only content would be the verdict record,
# which the arm excludes. An empty measured range is a refusal (U6), not a pass, so getting this
# wrong reds loudly.
printf 'seed\n' > "$TREE/README.md"
commit_tree "base"
git -C "$TREE" update-ref refs/remotes/origin/main HEAD

printf '# lean spec\n\n- AC-1: does a thing\n- AC-2: does another\n' > "$TREE/docs/plans/acme-42-lean.md"
# The build claim carries r-abc123; the verdict is REVIEW-authored, so it carries its own
# identity and names its own session. A verdict reusing r-abc123 is case (N).
#
# Every writer here COMMITS, because the record's commit is what evidence 5 reads. A helper
# that only wrote the file would leave the record uncommitted and every case downstream would
# collect a spurious second violation.
#
# `reviewed_head` is resolved BEFORE the commit, which is the real shape: the reviewer reads the
# current head, names it, and commits the record on top. Resolving it afterwards would name the
# record's own commit and leave every declared-freshness case asserting nothing.
write_verdict() { # write_verdict [verdict] [run-id] [session-id] [reviewed-head] [patch-id]
  printf 'verdict=%s\nrun_id: %s\nsession_id: %s\nrounds: 1\nreviewed_head: %s\n' \
    "${1:-approve}" "${2:-r-review-1}" "${3:-sess-review-1}" \
    "${4:-$(git -C "$TREE" rev-parse HEAD)}" > "$VREC"
  # Absent by default: every case above this line gates on the SHA path records predating the
  # patch-id key still take, and (R5) asserts that rather than assuming it.
  [ -n "${5:-}" ] && printf 'reviewed_patch_id: %s\n' "$5" >> "$VREC"
  commit_tree "verdict ${1:-approve}"
}

# The EXPECTED patch identity, derived here rather than read back from the gate. This is an
# ORACLE, not the mirror-harness pattern the repo bans: a copy is dangerous when production
# drifting away from it leaves the suite GREEN, and this one does the opposite — any change to
# how the gate resolves the base, ranges the diff, or excludes the record makes the two values
# disagree and reds every (U) case. The one property it cannot pin by copying is the exclusion,
# so that is pinned behaviorally instead, at (U2).
tree_patch_id() { # tree_patch_id <head-ish>
  local base
  base="$(git -C "$TREE" merge-base refs/remotes/origin/main "$1" 2>/dev/null)" || return 0
  git -C "$TREE" diff "$base" "$1" -- . ":(exclude)docs/plans/acme-42-lean-verdict.md" 2>/dev/null \
    | git -C "$TREE" patch-id --stable 2>/dev/null | cut -d' ' -f1
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

# ---- (R) evidence 5, DECLARED: the record must name the head it reviewed ------------------
# The arm above infers the anchor from git — which commit carries the record. This one reads the
# anchor the reviewer DECLARED. They differ in exactly one situation, and it is an ordinary one:
# code lands while the review is running, and the reviewer then commits an honest record on top
# of a head it never read. Inference sees a record whose commit is the head and says fresh.

# The MIGRATION case. Records written before the key existed land here and are refused, unlike
# the claim comment's missing session_id in (N7) — that one has no available remedy, this one
# does (re-run the review round), so grandfathering it would be a waiver rather than a kindness.
write_verdict_literal 'verdict=approve
run_id: r-review-1
session_id: sess-review-1
rounds: 1
'
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no reviewed_head key'; then
  pass "(R1) a verdict record carrying no reviewed_head key is refused (the pre-key migration case)"
else fail "(R1) expected rc=1 on a head-less verdict, got rc=$rc: $out"; fi

# The gap inference cannot see. `stale_head` is captured, a code commit lands, and only THEN is
# the record written — so the record's own commit IS the PR head and the inferred arm is green.
# Only the declared arm can red this, which is what makes the case non-vacuous.
stale_head="$(git -C "$TREE" rev-parse HEAD)"
printf 'landed while the review was running\n' > "$TREE/docs/plans/interleaved.md"
commit_tree "code lands between the review and the record"
write_verdict approve r-review-3 sess-review-3 "$stale_head"
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'states it reviewed'; then
  pass "(R2) a record naming an earlier head is refused even though its own commit IS the PR head"
else fail "(R2) expected rc=1 on a declared-stale verdict, got rc=$rc: $out"; fi

# ...and that same red must not be reachable by the inferred arm alone, or (R2) proves nothing
# about the new one. Re-committing the record with the CORRECT declared head clears it, with the
# interleaved commit still in history.
write_verdict approve r-review-4 sess-review-4
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'freshness (declared)'; then
  pass "(R3) a record naming the head it was written on top of passes, and the gate names the arm"
else fail "(R3) expected rc=0 with a declared-freshness line, got rc=$rc: $out"; fi

# The rebase/force-push-after-approval shape: the declared commit is simply gone. A gate that
# shrugged at an unresolvable anchor would print its ✓ having compared nothing — the same
# fail-open (Q2) closes one level up.
write_verdict approve r-review-5 sess-review-5 0000000000000000000000000000000000000000
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'this checkout holds no commit'; then
  pass "(R4) a reviewed_head naming no object in this checkout is refused, not compared against nothing"
else fail "(R4) expected rc=1 on an unresolvable reviewed_head, got rc=$rc: $out"; fi

# The (R) block's own premise. Its records carry no `reviewed_patch_id`, so they route to the SHA
# path — which is what makes them coverage of the pre-key fallback rather than of the (S) arm.
# Asserted, because a fixture writer that quietly grew the key would migrate the whole block and
# leave the fallback uncovered while every case still passed.
if ! grep -q 'reviewed_patch_id' "$VREC" 2>/dev/null; then
  pass "(R5) the (R) records carry no reviewed_patch_id, so that block does gate on the SHA fallback"
else fail "(R5) the (R) block is no longer exercising the SHA fallback: $(cat "$VREC" 2>/dev/null)"; fi

# ---- (S) evidence 6: an unratified intent-gap record blocks the merge (P9) ----------------
# A decision that surfaced during BUILD and was not in the receipt routes back through this
# record instead of becoming a silent choice. Every arm below leaves the rest of (A) intact —
# spec, approve verdict, bot claim, both freshness arms — so a failure here can only be the
# new arm.
#
# ORDERING IS LOAD-BEARING: the gap record is committed FIRST, the verdict on top of it. That
# is the real shape (BUILD commits the record, REVIEW reads that head and names it), and it is
# also the only order evidence 5 tolerates — both freshness arms allow exactly one path to
# differ from the head, the verdict record itself, so a gap record riding in the verdict's own
# commit would red every case below on staleness rather than on what it asserts.
GAPREC="$TREE/docs/plans/acme-42-lean-intent-gap.md"

# The verdict identity is keyed on a COUNTER, not on the arm's arguments. Two calls whose
# verdict bytes are identical leave the record's last-touching commit behind the gap file's,
# and evidence 5 then fails the arm for staleness rather than for what it asserts.
GAP_ROUND=0
write_gap() { # write_gap <ratified> [ratified_by]
  GAP_ROUND=$((GAP_ROUND + 1))
  printf 'issue: 42\nrun_id: r-abc123\nsession_id: sess-build-1\nregion: OR-1\ndisposition: pause-and-ask\nratified: %s\nratified_by: %s\n\n## Gap\n\nThe receipt never covered the retry ceiling.\n' \
    "$1" "${2:-}" > "$GAPREC"
  commit_tree "intent-gap record (round $GAP_ROUND)"
  write_verdict approve "r-review-gap-$GAP_ROUND" "sess-review-gap-$GAP_ROUND"
}

# (S0) a lean-SHAPED intent-gap record under fixtures/ must not count as one — the same
# exclusion every other artifact scan applies, and without it this suite's own fixtures would
# block the PR that ships them.
printf 'ratified: no\n' > "$TREE/scripts/fixtures/acme-42-lean-intent-gap.md"
commit_tree "fixture-path intent-gap record"
write_verdict approve r-review-fx sess-review-fx
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'no intent-gap record for #42'; then
  pass "(S0) a fixture-path intent-gap record is excluded, and absence is printed rather than silent"
else fail "(S0) expected rc=0 with the absence notice, got rc=$rc: $out"; fi

# (S0b) ...and neither does a real, non-fixture record belonging to a DIFFERENT issue. This is
# the arm (S0) cannot reach: the fixture exclusion and the `-$KEY` scoping are separate
# predicates, and a scan that dropped the key would let any open issue's unratified gap block
# this PR — or, worse, let a neighbouring issue's ratified one certify it. Ordered before every
# acme-42 record below so nothing else can be the thing that satisfies the scan.
printf 'issue: 99\nratified: no\n\n## Gap\n\nA different issue, still unratified.\n' \
  > "$TREE/docs/plans/acme-99-lean-intent-gap.md"
commit_tree "another issue's intent-gap record"
write_verdict approve r-review-xkey sess-review-xkey
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'no intent-gap record for #42'; then
  pass "(S0b) an unratified intent-gap record for another issue does not bind this PR"
else fail "(S0b) expected rc=0 with the absence notice, got rc=$rc: $out"; fi

# (S1) the refusal itself.
write_gap no
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "reads 'ratified: no'"; then
  pass "(S1) an unratified intent-gap record blocks the merge boundary"
else fail "(S1) expected rc=1 on an unratified intent gap, got rc=$rc: $out"; fi

# (S2) `ratified: yes` with nothing cited is a self-ratification — the build run asserting the
# human agreed. Distinct from (S1): the header reads exactly what the gate wants to see, and
# only the citation stands between a run and ratifying its own gap.
write_gap yes
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'cites no'; then
  pass "(S2) 'ratified: yes' with no cited operator comment is refused"
else fail "(S2) expected rc=1 on an uncited ratification, got rc=$rc: $out"; fi

# (S3) ...and ratifying it clears the gate. Without this arm S1/S2 could be permanent
# breakage rather than a check with a remedy.
write_gap yes 'https://example.invalid/tracker/42#issuecomment-7'
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'intent gap: .* ratified'; then
  pass "(S3) a ratified intent-gap record citing the operator comment passes"
else fail "(S3) expected rc=0 on a ratified intent gap, got rc=$rc: $out"; fi

# (S4) the ratified value is read FIRST-MATCH, like every other key on these records: the
# record's own prose describes the gap, and gap prose says the word. A count-anywhere reader
# would certify a record whose header says `no`.
printf 'issue: 42\nratified: no\nratified_by: https://example.invalid/tracker/42#issuecomment-7\n\n## Gap\n\nThe earlier round recorded ratified: yes; this one reopened it.\n' > "$GAPREC"
commit_tree "intent-gap record whose prose quotes the other value"
write_verdict approve r-review-gap-4 sess-review-gap-4
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "reads 'ratified: no'"; then
  pass "(S4) a 'ratified: no' record whose body quotes 'ratified: yes' is still refused"
else fail "(S4) expected rc=1 on a reopened intent gap, got rc=$rc: $out"; fi

# ---- (T) --help prints the header, and only the header -----------------------------------
# `sed -n '2,Np'` is a hand-maintained line number: growing the header silently truncates the
# help text, and this repo has been burned by exactly that. Two assertions, because either
# direction is a real failure — the LAST header line must be present (the range did not fall
# short) and the first line of code must not be (it did not over-reach).
out="$(bash "$GATE" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q 'Exit 0 = pass or not-applicable' \
   && ! printf '%s' "$out" | grep -q '^set -uo pipefail'; then
  pass "(T) --help prints through the last header line and stops before the code"
else fail "(T) --help did not print exactly the header, rc=$rc: $out"; fi
# ---- (U) evidence 5, DECLARED and PATCH-ID keyed: a rebase must not void a verdict ---------
# SHA keying refused a rebase — and refused it unavoidably here, since this checkout would hold
# no pre-rebase object at all — so it charged a full review round for an operation that changes
# no reviewed line. Patch identity is invariant across a clean replay and still moves on any
# real change, including the conflict resolution the SHA arm could not distinguish from one.
#
# Evidence 6 is cleared first, and deliberately: (S4) leaves an unratified intent-gap record
# behind, which reds every case here for a reason none of them is about. Absence is the ordinary
# state for that evidence — the gate prints it rather than refusing — so removing the record
# isolates this block on evidence 5 without weakening anything the (S) block asserts.
rm -f "$GAPREC"
git -C "$TREE" add -A >/dev/null 2>&1
git -C "$TREE" commit -q -m "no intent gap on this run" >/dev/null 2>&1

run_gate_base() { # run_gate_base <head-ref> <comments-file> <diff-file> <base-ref>
  ( cd "$TREE" && \
    LEAN_BRANCH_PREFIX="lean/acme-" \
    PIPELINE_BRANCH_PREFIX="claude/acme-" \
    PR_HEAD_REF="$1" \
    PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
    PR_BODY="$BODY_GOOD" \
    PR_CREATED_AT="$PR_OPEN_AT" \
    PR_BASE_REF="$4" \
    bash "$GATE" --comments-file "$2" --diff-files-file "$3" 2>&1 )
}

# The id is resolved BEFORE the record is written, which is the real shape: the reviewer reads
# the head it is on, hashes that patch, and commits the record on top.
u_pid="$(tree_patch_id HEAD)"
[ -n "$u_pid" ] || fail "(U0) the fixture's patch identity is empty — every (U) case would compare nothing"
write_verdict approve r-review-6 sess-review-6 "$(git -C "$TREE" rev-parse HEAD)" "$u_pid"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'freshness (declared, patch-id'; then
  pass "(U1) a record whose reviewed_patch_id matches the head passes, and the gate names the patch-id arm"
else fail "(U1) expected rc=0 on a matching patch id, got rc=$rc: $out"; fi

# AC-4, the EXCLUSION, driven behaviorally so no copy of the formula can satisfy it. The writer
# hashes a head that does not yet carry the record; this reader hashes one that does. Excluding
# the record path on both sides is what makes those agree — with the path inside the measured
# range, editing the record alone would move the id and red this.
printf '\nReviewer prose appended after the record was committed.\n' >> "$VREC"
commit_tree "the record's own bytes change"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'freshness (declared, patch-id'; then
  pass "(U2) editing the verdict record itself does not move the patch identity — the exclusion holds on the read side"
else fail "(U2) expected rc=0 after editing the record, got rc=$rc: $out"; fi

# THE headline case. A REAL rebase: the base advances by a commit carrying actual content, and
# the branch is replayed onto it. Same-tree bases were rejected as a fixture — they leave the
# pre- and post-rebase trees identical, so the old SHA arm would pass too and the case would be
# a vacuous guard. Non-vacuity is asserted at (U3a), not argued.
u_branch="$(git -C "$TREE" symbolic-ref --short HEAD 2>/dev/null)"
u_orphaned_head="$(git -C "$TREE" rev-parse HEAD)"
git -C "$TREE" branch -f u-base refs/remotes/origin/main >/dev/null 2>&1
git -C "$TREE" checkout -q u-base 2>/dev/null
printf 'the base moved while the review was in flight\n' > "$TREE/base-moved.txt"
git -C "$TREE" add base-moved.txt >/dev/null 2>&1
git -C "$TREE" commit -q -m 'base advances' >/dev/null 2>&1
git -C "$TREE" update-ref refs/remotes/origin/main u-base
git -C "$TREE" checkout -q "$u_branch" 2>/dev/null
if git -C "$TREE" rebase -q u-base >/dev/null 2>&1; then u_rebase_ok=1
else u_rebase_ok=0; git -C "$TREE" rebase --abort >/dev/null 2>&1; fi
# The pre-rebase commit is still an object in THIS repo (a local rebase does not gc it), so the
# `cat-file -e` arm would not fire — but its tree now differs from the head by the base's commit,
# so the SHA arm's `git diff` would. If that diff is empty, (U3) measures nothing.
u_sha_arm_would_red="$(git -C "$TREE" diff --name-only "$u_orphaned_head" HEAD 2>/dev/null)"
if [ "$u_rebase_ok" -eq 1 ] && [ "$(git -C "$TREE" rev-parse HEAD)" != "$u_orphaned_head" ] \
   && [ -n "$u_sha_arm_would_red" ]; then
  pass "(U3a) the fixture really was rebased onto a moved base, and the SHA arm would red on it"
else fail "(U3a) the rebase did not take (ok=$u_rebase_ok, sha-arm-diff='$u_sha_arm_would_red') — (U3) would assert nothing"; fi

out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'freshness (declared, patch-id'; then
  pass "(U3) a rebase that replays the branch unchanged does not void the verdict at the merge boundary"
else fail "(U3) expected rc=0 after a clean replay, got rc=$rc: $out"; fi

# ...and the case SHA keying could not express at all: a rebase whose conflict resolution altered
# a line. It is refused, and by the DECLARED arm alone — the changed line and the record land in
# one commit, so `git log -1 -- <record>` finds the head and the INFERRED arm is green. Without
# that shape the case would red on inference and prove nothing about this arm.
u_pid_pre="$(tree_patch_id HEAD)"
printf '# lean spec\n\n- AC-1: does a thing, resolved differently by the rebase\n' > "$TREE/docs/plans/acme-42-lean.md"
printf 'verdict=approve\nrun_id: r-review-7\nsession_id: sess-review-7\nrounds: 1\nreviewed_head: %s\nreviewed_patch_id: %s\n' \
  "$(git -C "$TREE" rev-parse HEAD)" "$u_pid_pre" > "$VREC"
commit_tree "a conflict resolution changes a line, committed with the record"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'reviewed patch'; then
  pass "(U4) a rebase whose resolution changed a line is refused, with the inferred arm green"
else fail "(U4) expected rc=1 on a moved patch identity, got rc=$rc: $out"; fi

# D-5 vacuity. `git patch-id` prints NOTHING for an empty diff, so two failed computations
# compare EQUAL and an unguarded reader prints its ✓ having hashed nothing. A missing base is an
# ENVIRONMENT error, not a violation: the evidence is present, the check simply cannot run.
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'PR_BASE_REF is unset'; then
  pass "(U5) a declared patch id with no PR_BASE_REF is an environment error, not an unmeasured pass"
else fail "(U5) expected rc=2 with no base ref, got rc=$rc: $out"; fi

out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "no-such-base")"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'cannot compute this branch'; then
  pass "(U6) a base ref naming no branch is an environment error, not a comparison against nothing"
else fail "(U6) expected rc=2 on an unresolvable base, got rc=$rc: $out"; fi

echo "[check-lean-chain-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

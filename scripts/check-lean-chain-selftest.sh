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
# NO BRANCH-PREFIX CONSTANT in this environment (#413 AC-6). The gate is driven exactly as CI
# drives it, and CI no longer carries LEAN_BRANCH_PREFIX; leaving a dead export here would let a
# re-introduced prefix read pass unnoticed by every case below.
run_gate() { # run_gate <head-ref> <comments-file> <diff-file> [pr-body]
  ( cd "$TREE" && \
    PR_HEAD_REF="$1" \
    PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
    PR_BODY="${4:-$BODY_GOOD}" \
    PR_CREATED_AT="$PR_OPEN_AT" \
    bash "$GATE" --comments-file "$2" --diff-files-file "$3" 2>&1 )
}

BODY_303='Staged work.

Closes #303'

echo "[check-lean-chain-selftest]"

# ---- (A) happy path — and AC-9's confirmation --------------------------------------------
# The head ref is a PRE-#413 `lean/`-prefixed branch, which is the transition case AC-9 asks to
# be confirmed rather than assumed: such a PR must still classify correctly with no lean
# namespace known to the gate. Most cases below reuse this head for the same reason.
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(A) a legacy lean/-prefixed PR with spec + approve-verdict + bot claim passes (AC-9)"
else fail "(A) expected rc=0, got $rc: $out"; fi

# ---- (A2) AC-6: the SAME PR on the staged prefix classifies identically -------------------
# The whole point of #413: the branch name carries no lane identity, so moving this PR onto the
# staged prefix must change nothing. (A) and (A2) differ in the head ref and nothing else.
out="$(run_gate "claude/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'applicable via lean-artifact'; then
  pass "(A2) AC-6: a staged-prefixed lean PR classifies via the artifact arm, with no prefix constant in the environment"
else fail "(A2) expected rc=0 via the artifact arm, got rc=$rc: $out"; fi

# ---- (B) a PR that commits no lean spec is simply not applicable --------------------------
out="$(run_gate "someone/hotfix" "$WORK/comments-empty.json" "$WORK/diff-plain.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'not applicable'; then
  pass "(B) ordinary PR is not applicable"
else fail "(B) expected a not-applicable exit 0, got rc=$rc: $out"; fi

# ---- (C) MANDATED: applicability owes NOTHING to the branch name --------------------------
# The successor to the self-neutralization case. A prefix-only gate could be neutralized by a
# stale constant; this one cannot be neutralized at all, because there is no constant. An
# arbitrary branch carrying its own key's lean spec is applicable and fails on the missing claim.
out="$(run_gate "some/other-branch" "$WORK/comments-empty.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'lean-artifact'; then
  pass "(C) an arbitrary branch name + this key's lean spec ⇒ applicable, and fails on the missing claim"
else fail "(C) expected rc=1 via the artifact arm, got rc=$rc: $out"; fi

# ---- (D) MANDATED: a PR carrying ANOTHER key's lean spec is NOT applicable ----------------
# The disjointness case (#413 AC-11), and the successor to the pipeline-prefix exclusion this
# replaces. `Closes #303` against a diff carrying only acme-42-lean.md: this PR did not author
# that spec, so check-pipeline-chain.sh owns it and this gate must decline. Double-classifying
# would red every PR that so much as edits an old lean spec.
out="$(run_gate "claude/acme-303" "$WORK/comments-empty.json" "$WORK/diff-lean.txt" "$BODY_303")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'not applicable' \
   && printf '%s' "$out" | grep -q 'none for this PR'; then
  pass "(D) AC-11: a PR carrying another key's lean spec is not double-classified"
else fail "(D) expected a not-applicable exit 0 naming the key mismatch, got rc=$rc: $out"; fi

# ---- (D2) AC-12 / OR-1: a lean-shaped branch whose diff carries NO spec is not applicable --
# The open region the pre-flight ledger parked: a lean PR whose spec is absent from its own diff
# (already on the base, or a reopened PR) is claimed by neither lean arm. The stated default is
# to LET IT RED — fail-closed at a merge boundary — and it does, one gate over: this half
# confirms the lean gate declines, and check-pipeline-chain-selftest.sh's (l4) confirms the
# pipeline gate then reds it on the stage markers.
out="$(run_gate "claude/acme-42" "$WORK/comments-good.json" "$WORK/diff-plain.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'no non-fixture'; then
  pass "(D2) AC-12: a PR whose own diff carries no lean spec is not applicable here"
else fail "(D2) expected a not-applicable exit 0 naming the empty scan, got rc=$rc: $out"; fi

# ---- (D3) AC-17: declining is only safe when the SIBLING will claim ------------------------
# The cell neither suite drove, and the one that made both gates stand down. (D) above is the
# same shape with the keys AGREEING, and it must stay a not-applicable: the difference between
# the two cases is the entire contract.
#
# Here the body resolves #99 while the branch resolves #42 and the diff commits #42's spec.
# check-pipeline-chain.sh keys its exclusion on the BRANCH, so it exempts — its (l7) is this
# case's other half, driven from the same three inputs. If this gate took (D)'s route and
# declined "because the pipeline gate owns it", the PR would reach the merge boundary with its
# claim comment, its verdict record and its freshness all unread, and both logs would say the
# other gate had it. So: refuse, naming both keys and the spec that split them.
#
# Reachable without malice — lean-gate.sh milestone 5 asserts `Closes #<issue>` appears at least
# ONCE, not that it is first, so a PR closing two issues in the other order lands here.
BODY_SPLIT='Delivers a slice.

Part of #99'
out="$(run_gate "claude/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "$BODY_SPLIT")"; rc=$?
if [ "$rc" -eq 1 ] \
   && printf '%s' "$out" | grep -q 'key mismatch' \
   && printf '%s' "$out" | grep -q '#99' \
   && printf '%s' "$out" | grep -q '#42' \
   && printf '%s' "$out" | grep -q 'docs/plans/acme-42-lean.md' \
   && ! printf '%s' "$out" | grep -q 'not applicable'; then
  pass "(D3) AC-17: a body-key/branch-key split with the branch key's spec in the diff REFUSES, never declines"
else fail "(D3) expected rc=1 naming both keys and the spec, with no not-applicable, got rc=$rc: $out"; fi

# ...and the refusal is scoped to the cell that needs it. Same split keys, but the diff commits
# only ANOTHER key's spec, so the sibling does not exempt and the hand-off is sound again. A 4b
# that fired on the key disagreement alone would red every staged PR that edits an old lean spec
# from a branch whose body cites the epic — which is (D)'s corpus, not a defect.
printf 'docs/plans/acme-777-lean.md\nREADME.md\n' > "$WORK/diff-lean-other.txt"
out="$(run_gate "claude/acme-42" "$WORK/comments-empty.json" "$WORK/diff-lean-other.txt" "$BODY_SPLIT")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'none for this PR'; then
  pass "(D3b) AC-17: the same key split with no branch-key spec in the diff still declines — 4b is not a blanket mismatch check"
else fail "(D3b) expected a not-applicable exit 0, got rc=$rc: $out"; fi

# ...and the key this gate resolves is held in LOCKSTEP with what the lane guarantees (AC-19),
# which is where the manifesto note this change records ("hold the key derivation in lockstep,
# not only the pattern the key feeds") stops being documentation. lean-gate.sh milestone 5
# requires `Closes #<issue>` at least ONCE and never that it is FIRST, so under a first-match
# derivation any body that mentions another `Closes #N` earlier — prose, or a code span quoting
# the very bug class — resolved a phantom key and hard-failed at 4b. Not hypothetical: it is how
# this change's own PR reds, a review narrative quoting the token being enough to trip it.
BODY_QUOTED='Documents the counterexample: a body reading "Closes #99" resolved the wrong key.

Closes #42'
out="$(run_gate "claude/acme-42" "$WORK/comments-empty.json" "$WORK/diff-lean.txt" "$BODY_QUOTED")"; rc=$?
if [ "$rc" -eq 1 ] \
   && printf '%s' "$out" | grep -q 'lean-artifact' \
   && printf '%s' "$out" | grep -q 'source issue: #42' \
   && ! printf '%s' "$out" | grep -q 'key mismatch'; then
  pass "(D3c) AC-19: a body QUOTING another Closes #N still resolves to the branch key it closes"
else fail "(D3c) expected the artifact arm at #42 with no key mismatch, got rc=$rc: $out"; fi

# The negative that keeps (D3c) from being satisfiable by `KEY="$KEY_BRANCH"`. Same shape, but
# this body never closes #42 at all — a REAL disagreement rather than a quoting artifact — so 4b
# must still refuse. Without this case the branch-key preference could degrade into ignoring the
# body entirely, which would delete AC-17's contract while every other case stayed green.
BODY_ONLY_99='Delivers a slice.

Closes #99'
out="$(run_gate "claude/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "$BODY_ONLY_99")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'key mismatch'; then
  pass "(D3d) AC-19: the preference applies only where the body CLOSES the branch key — a real split still refuses"
else fail "(D3d) expected rc=1 with a key mismatch, got rc=$rc: $out"; fi

# ---- (E) fixture paths are excluded from the artifact scan -------------------------------
out="$(run_gate "some/other-branch" "$WORK/comments-empty.json" "$WORK/diff-fixture-only.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'not applicable'; then
  pass "(E) a lean-shaped file under fixtures/ does not trigger applicability"
else fail "(E) expected fixture paths to be excluded, got rc=$rc: $out"; fi

# ---- (E2) a missing --diff-files-file is exit 2, not a vacuous not-applicable -------------
# The diff seam feeds applicability itself now, and it is consumed through a process
# substitution — where an `envfail` inside the producer exits only the subshell and leaves the
# scan reading an empty list. That failure mode is indistinguishable from an honest not-lean PR:
# exit 0, "not applicable", green merge boundary.
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/no-such-diff.txt")"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'does not exist'; then
  pass "(E2) a missing --diff-files-file is a usage error, not a vacuous not-applicable"
else fail "(E2) expected rc=2 on a missing diff seam, got rc=$rc: $out"; fi

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

# ---- (I2) #374 AC-4/6: a needs-work verdict at a STALE head collapses to ONE evidence-5
# refusal, not three. Before the fix a needs-work record with code landing after it produced
# evidence-2's "not approve" PLUS both freshness arms independently — three ✗ lines restating
# one fact (observed live on a #372 round-2 build). Code lands AFTER the needs-work record
# (still the SAME record (I) just wrote), so both freshness arms would find staleness if they
# ran; AC-4 requires that they never evaluate a non-approve record at all.
printf 'late change after a needs-work verdict\n' > "$TREE/docs/plans/notes-374.md"
commit_tree "code lands after a needs-work verdict"
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
n_violations="$(printf '%s' "$out" | grep -c '\[lean-chain\]   ✗')"
if [ "$rc" -eq 1 ] \
   && printf '%s' "$out" | grep -q '2 evidence artifact(s) missing' \
   && [ "$n_violations" -eq 2 ] \
   && printf '%s' "$out" | grep -q 'freshness is undefined for a non-approve record' \
   && ! printf '%s' "$out" | grep -q 'changed between that commit and the PR head' \
   && ! printf '%s' "$out" | grep -q 'differ between that commit and the PR head' \
   && ! printf '%s' "$out" | grep -q 'now hashes to'; then
  pass "(I2) AC-4: a needs-work verdict at a stale head collapses to ONE evidence-5 refusal (2 total, not 4)"
else fail "(I2) expected exactly 2 violations with the freshness arms silent, got rc=$rc violations=$n_violations: $out"; fi
write_verdict

# ---- (J) a spec with no AC-n fails -------------------------------------------------------
printf '# lean spec\n\nNo criteria here.\n' > "$TREE/docs/plans/acme-42-lean.md"; commit_tree 'spec without AC-n'
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no numbered AC-n'; then
  pass "(J) a committed spec with no AC-n fails (the definition of done must exist)"
else fail "(J) expected rc=1 on an AC-less spec, got rc=$rc: $out"; fi
printf '# lean spec\n\n- AC-1: does a thing\n' > "$TREE/docs/plans/acme-42-lean.md"; commit_tree 'spec restored'

# ---- (K) an unresolvable PR_HEAD_SHA is FATAL, never exempt -------------------------------
# The successor to the LEAN_BRANCH_PREFIX case this replaces: the fail-closed posture on a
# missing env input survives the deletion of the prefix constants. PR_HEAD_SHA is now the
# strongest of the remaining ones — without it "a verdict exists" would silently stand in for
# "this head was approved".
out="$( cd "$TREE" && \
        PR_HEAD_REF="lean/acme-42" PR_BODY="$BODY_GOOD" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_SHA="" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'PR_HEAD_SHA is unset'; then
  pass "(K) an empty PR_HEAD_SHA is an environment error, not a silent exemption"
else fail "(K) expected rc=2 on an unresolvable head sha, got $rc: $out"; fi

# ---- (L) #413: a lingering branch-prefix constant changes NOTHING -------------------------
# The negative that retires (L)'s predecessor. That case asserted the two CI prefix constants
# were reconciled for mutual non-prefix-matching; both are gone from this gate, and the way to
# prove a constant is truly unread is to set it to a value that would have changed the verdict
# under the old code. `LEAN_BRANCH_PREFIX=claude/` prefix-matched the pipeline prefix and was
# fatal (rc=2) before #413; here it must be inert, and the PR must classify on its artifact.
out="$( cd "$TREE" && LEAN_BRANCH_PREFIX="claude/" PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -ne 2 ] && printf '%s' "$out" | grep -q 'applicable via lean-artifact'; then
  pass "(L) stale prefix constants left in the environment are inert — classification is artifact-only"
else fail "(L) expected the prefix constants to be ignored, got $rc: $out"; fi

# ---- (M) a lean PR with no issue reference fails -----------------------------------------
# AC-11's guard rail: the key match added to applicability must not turn an unreferenced PR into
# a silent exemption. A diff that commits a lean spec and a body that names no issue is
# unclassifiable, and unclassifiable fails.
out="$( cd "$TREE" && \
        PR_HEAD_REF="lean/acme-42" PR_BODY="no reference here" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no resolvable issue reference'; then
  pass "(M) a lean PR with no 'Closes #N' fails rather than being exempted"
else fail "(M) expected rc=1 on an unresolvable issue reference, got $rc: $out"; fi

# ...and the FALLBACK resolves: `Part of #N` is the shape a sub-issue of a program epic carries,
# and a PR body with no `Closes` must still reach a key rather than failing as unreferenced.
# (M) alone cannot see this arm — it passes whether the fallback works or is dead code, which is
# exactly how the fallback's own mutant sat surviving in the baseline.
out="$( cd "$TREE" && \
        PR_HEAD_REF="lean/acme-42" PR_BODY="Delivers a slice.

Part of #42" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
# Asserted on the RESOLUTION line, not on the exit code: the fixture at this point in the file
# carries whatever record the cases above left behind, so rc is about the evidence set rather
# than about key resolution. `source issue: #42` is printed before any evidence is weighed, and
# it is exactly what disappears when the fallback stops matching.
if printf '%s' "$out" | grep -q 'source issue: #42'; then
  pass "(M2) a body carrying only 'Part of #N' resolves through the fallback"
else fail "(M2) expected the Part-of fallback to resolve #42, got $rc: $out"; fi

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
out="$( cd "$TREE" && \
        PR_HEAD_REF="lean/acme-42" PR_BODY="$BODY_GOOD" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_SHA="" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'PR_HEAD_SHA is unset or empty'; then
  pass "(Q1) an empty PR_HEAD_SHA is an environment error, not an unmeasured freshness pass"
else fail "(Q1) expected rc=2 on an empty PR_HEAD_SHA, got $rc: $out"; fi

# A sha-shaped value that names no object in this checkout. Distinct from (Q1): the emptiness
# guard is satisfied, and only the object lookup stands between a bogus ref and a silent ✓.
out="$( cd "$TREE" && \
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

# ---- (V) evidence 6: the INHERITANCE chain at the merge boundary (#375) --------------------
# A round-n record may declare `inherited_patch_id` and read only the delta since the tree that
# round covered. What the boundary then guarantees is not "one review read this tree" but "a
# CHAIN of reviews covered it" — so an unverified link is a strictly weaker boundary reached
# silently, and every link is walked here.
#
# Every record below carries a reviewed_patch_id matching the head it is written on, so the
# freshness arms stay green and the chain arm is the only thing any case can red on.
write_chain_record() { # write_chain_record <run-id> <session-id> <rounds> <patch-id> [inherited-id] [inherited-from] [body]
  {
    printf 'verdict=approve\nrun_id: %s\nsession_id: %s\nrounds: %s\nreviewed_head: %s\nreviewed_patch_id: %s\n' \
      "$1" "$2" "$3" "$(git -C "$TREE" rev-parse HEAD)" "$4"
    [ -n "${5:-}" ] && printf 'inherited_patch_id: %s\ninherited_from_verdict: %s\n' "$5" "${6:-unknown}"
    # The BODY, below the blank line the production writer emits — which is what makes it a body
    # rather than more header. (V6) needs a record whose own findings mention the key.
    [ -n "${7:-}" ] && printf '\n%s\n' "$7"
  } > "$VREC"
  commit_tree "verdict round $3"
}

# ROUND 1: a chain root. AC-4 — the absence of the key is the ordinary case, and it is PRINTED,
# so a reader of the CI log can tell "this round covered everything itself" from "the arm never
# ran". A silent skip and a satisfied check look identical in a log; that is the whole reason.
v_pid1="$(tree_patch_id HEAD)"
[ -n "$v_pid1" ] || fail "(V0) the fixture's patch identity is empty — every (V) case would compare nothing"
# The exact spec bytes round 1 reviewed. (V3) restores THESE, not a plausible-looking rewrite:
# the patch identity is a hash of content, so "close enough" is a different tree.
v_spec_r1="$(cat "$TREE/docs/plans/acme-42-lean.md")"
write_chain_record r-review-v1 sess-review-v1 1 "$v_pid1"
v_r1_commit="$(git -C "$TREE" rev-parse HEAD)"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'declares no inherited coverage'; then
  pass "(V1) a round-1 record passes unchanged, and the gate prints that it inherited nothing"
else fail "(V1) expected rc=0 with the no-inheritance note, got rc=$rc: $out"; fi

# ROUND 2, inheriting round 1: the ordinary fix round. The fix touches the spec, which round 1
# already read — so the delta is non-empty and the head's patch identity has genuinely moved.
printf '# lean spec\n\n- AC-1: does a thing\n- AC-2: does another, fixed after round 1\n' > "$TREE/docs/plans/acme-42-lean.md"
commit_tree "the fix round 1 asked for"
v_pid2="$(tree_patch_id HEAD)"
[ "$v_pid2" != "$v_pid1" ] || fail "(V2-fixture) the fix did not move the patch identity — (V2) would assert nothing"
write_chain_record r-review-v2 sess-review-v2 2 "$v_pid2" "$v_pid1" "$v_r1_commit"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'inheritance chain: 1 inherited link'; then
  pass "(V2) AC-1: a round-2 record inheriting round 1's reviewed patch passes the merge boundary"
else fail "(V2) expected rc=0 with one resolved link, got rc=$rc: $out"; fi

# THE case that forces the search to run strictly BACKWARDS. A fix round can revert the branch
# to exactly the tree an earlier round reviewed — "the blocker says the change was wrong" — and
# the head record's reviewed patch is then an identity an ancestor record also carries. An
# unbounded search resolves that round to ITSELF, and every honest chain through it reads as a
# loop: a correct branch made unmergeable by a legal fix.
printf '%s\n' "$v_spec_r1" > "$TREE/docs/plans/acme-42-lean.md"
commit_tree "the round-2 fix is reverted — round 1's tree is back"
v_pid_rev="$(tree_patch_id HEAD)"
[ "$v_pid_rev" = "$v_pid1" ] \
  || fail "(V3-fixture) the revert did not restore round 1's patch identity — (V3) would assert nothing"
write_chain_record r-review-v3 sess-review-v3 3 "$v_pid_rev" "$v_pid2" "$v_r1_commit"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'inheritance chain: 2 inherited link'; then
  pass "(V3) a round whose reviewed patch an ancestor record also carries still resolves its chain — the search runs strictly backwards"
else fail "(V3) expected a 2-link chain after a revert, got rc=$rc: $out"; fi

# SELF-INHERITANCE, the one shape that distinguishes a window bounded below the record being read
# from an unbounded one: a record whose inherited_patch_id is its own reviewed_patch_id, over the
# reverted tree above. Unbounded, the walk resolves this round to ITSELF, counts the record under
# test as a link in its own chain, and still PASSES — one link longer, exit code unchanged. The
# printed count is what makes that visible, so the assertion pins the NUMBER, not merely the pass.
write_chain_record r-review-v3 sess-review-v3 3 "$v_pid_rev" "$v_pid_rev" "$v_r1_commit"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'inheritance chain: 3 inherited link'; then
  pass "(V3b) a self-inheriting record resolves to the ancestor carrying that patch — the record under test is never a link in its own chain"
else fail "(V3b) expected rc=0 with exactly 3 links, got rc=$rc: $out"; fi

# AC-1 negative / AC-5: a declared identity matching no record on the branch is REFUSED — never
# downgraded to "then treat it as a root record", which would convert an unverifiable claim into
# a satisfied one. Only the inherited key changes from (V3), so nothing else can be the cause.
write_chain_record r-review-v3 sess-review-v3 3 "$v_pid_rev" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "$v_r1_commit"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'matches no earlier verdict record committed on this branch'; then
  pass "(V4) AC-5: an inheritance link resolving to nothing on this branch is a violation, not a downgrade"
else fail "(V4) expected rc=1 on a dangling link, got rc=$rc: $out"; fi

# AC-3: the round NAMED is the one whose link DANGLES, not the one whose link is being walked.
# Round 4's own link resolves; round 3's — left dangling by the case above — does not. A message
# naming round 4 would send the operator to the wrong record, and a generic "chain is stale"
# would name neither.
printf '# lean spec\n\n- AC-1: does a thing\n- AC-2: does another, fixed again\n' > "$TREE/docs/plans/acme-42-lean.md"
commit_tree "a further fix round"
v_pid4="$(tree_patch_id HEAD)"
write_chain_record r-review-v4 sess-review-v4 4 "$v_pid4" "$v_pid_rev" "$v_r1_commit"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'round 3 declares' \
   && ! printf '%s' "$out" | grep -q 'round 4 declares'; then
  pass "(V5) AC-3: a broken MIDDLE link is attributed to round 3, the round that declared it"
else fail "(V5) expected the violation to name round 3, got rc=$rc: $out"; fi

# A record's own FINDINGS cannot supply the key this arm gates on. The key is the schema's one
# conditionally-emitted one, so on a chain ROOT there is no authentic occurrence for the
# documented "the header wins first-match" mitigation to win with, and the first match in the
# file is whatever the reviewer wrote. Reached in production, not in principle: a root record
# written by the real writer took this gate red on a value quoted inside its own repro block.
#
# The quoted value here RESOLVES — it is round 1's real reviewed patch — so the failure being
# guarded is the SILENT one. A first-match reader credits this root with a link, exits 0, and
# prints a checkmark; only the coverage phrase separates the two readings.
v_pid_root="$(tree_patch_id HEAD)"
write_chain_record r-review-v5 sess-review-v5 5 "$v_pid_root" "" "" \
  "## a finding about the chain

\`\`\`
inherited_patch_id: $v_pid1
\`\`\`"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'declares no inherited coverage' \
   && ! printf '%s' "$out" | grep -q 'inherited link'; then
  pass "(V6) a root record whose findings quote a RESOLVING inheritance value is still read as a root"
else fail "(V6) expected the no-inheritance note and no credited link, got rc=$rc: $out"; fi

# The same door one level down: the walk reads PRIOR records through the same extraction, and a
# prior record may predate the sentinel — every branch in flight when this ships carries one.
# Round 6's own link is honest and resolves to round 5; round 5 is the root above, whose body
# quotes round 1's patch. A first-match walk follows that into a SECOND link and reports a chain
# one round longer than the branch has. Both readings exit 0, so the assertion pins the COUNT —
# the same technique (V3b) uses, and the reason the count is printed at all.
printf '# lean spec\n\n- AC-1: does a thing\n- AC-2: and a sixth-round fix\n' > "$TREE/docs/plans/acme-42-lean.md"
commit_tree "the round-5 fix"
v_pid6="$(tree_patch_id HEAD)"
write_chain_record r-review-v6 sess-review-v6 6 "$v_pid6" "$v_pid_root" "$v_r1_commit"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'inheritance chain: 1 inherited link'; then
  pass "(V6b) the walk terminates at a root whose body quotes the key — one link, not the two a first-match walk would count"
else fail "(V6b) expected exactly 1 inherited link, got rc=$rc: $out"; fi

# ---- (W) evidence 5 PRECEDENCE (#403): a merge from the base branch must not void an approve
# the patch-id arm proves is still fresh -----------------------------------------------------
# GitHub's "Update branch" button performs exactly this: it merges the configured base into the
# PR branch. The merged-in commits land strictly AFTER the verdict record's commit, so the
# two-dot INFERRED arm (VERDICT_COMMIT..PR_HEAD_SHA) counts every file the base changed as a
# change to THIS branch — even though the branch's own diff against the (now-current) base,
# which the DECLARED arm measures, has not moved at all. Observed live on PR #400 / issue #392.
#
# No intent-gap record is live at this point (removed ahead of (U), never reintroduced by (V)),
# so nothing here can be confounded by evidence 7.

w_branch="$(git -C "$TREE" symbolic-ref --short HEAD 2>/dev/null)"

# The review happens FIRST, against the base as it stood at review time — the real chronology.
w_pid="$(tree_patch_id HEAD)"
[ -n "$w_pid" ] || fail "(W0) the fixture's patch identity is empty — every (W) case would compare nothing"
write_verdict approve r-review-w1 sess-review-w1 "$(git -C "$TREE" rev-parse HEAD)" "$w_pid"
w_record_commit="$(git -C "$TREE" rev-parse HEAD)"

# THEN the base advances — two unrelated PRs land on it, the same shape #400's own trigger was.
git -C "$TREE" branch -f w-base refs/remotes/origin/main >/dev/null 2>&1
git -C "$TREE" checkout -q w-base 2>/dev/null
printf 'first unrelated base PR\n' > "$TREE/w-base-1.txt"
git -C "$TREE" add w-base-1.txt >/dev/null 2>&1
git -C "$TREE" commit -q -m 'unrelated base PR 1' >/dev/null 2>&1
printf 'second unrelated base PR\n' > "$TREE/w-base-2.txt"
git -C "$TREE" add w-base-2.txt >/dev/null 2>&1
git -C "$TREE" commit -q -m 'unrelated base PR 2' >/dev/null 2>&1
git -C "$TREE" update-ref refs/remotes/origin/main w-base
git -C "$TREE" checkout -q "$w_branch" 2>/dev/null

# ...and GitHub's "Update branch" merges it into the PR branch — a REAL git merge, landing the
# base's commits strictly after the record's commit, touching nothing the branch itself changed.
if git -C "$TREE" merge -q --no-edit w-base >/dev/null 2>&1; then w_merge_ok=1
else w_merge_ok=0; fi
[ "$w_merge_ok" -eq 1 ] || fail "(W-fixture) the merge from the advanced base did not apply cleanly"

# The fixture premise: the merge really did land files after the record's commit, so an
# unguarded inferred arm has something to (wrongly) fire on.
w_would_stale="$(git -C "$TREE" diff --name-only "$w_record_commit" HEAD 2>/dev/null)"
if [ -n "$w_would_stale" ]; then
  pass "(W1) the merge landed files after the record's commit — the unguarded inferred arm would (wrongly) see them"
else fail "(W1) the merge landed nothing after the record — (W) would assert nothing"; fi

out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q 'freshness (inferred): skipped' \
   && printf '%s' "$out" | grep -q 'freshness (declared, patch-id' \
   && ! printf '%s' "$out" | grep -q 'changed between that commit and the PR head'; then
  pass "(W2) AC-1: a merge from the configured base does not void an approve the patch-id arm proves is still fresh"
else fail "(W2) expected rc=0 via the declared arm alone, got rc=$rc: $out"; fi

# AC-2: the SAME kind of merge, but against a record predating the reviewed_patch_id key
# (reviewed_head only) has no declared arm to defer to — the inferred arm stays its sole check,
# and a merge from base still violates for it exactly as it did before this fix.
write_verdict approve r-review-w2 sess-review-w2
git -C "$TREE" branch -f w-base2 refs/remotes/origin/main >/dev/null 2>&1
git -C "$TREE" checkout -q w-base2 2>/dev/null
printf 'a third unrelated base PR\n' > "$TREE/w-base-3.txt"
git -C "$TREE" add w-base-3.txt >/dev/null 2>&1
git -C "$TREE" commit -q -m 'unrelated base PR 3' >/dev/null 2>&1
git -C "$TREE" update-ref refs/remotes/origin/main w-base2
git -C "$TREE" checkout -q "$w_branch" 2>/dev/null
if git -C "$TREE" merge -q --no-edit w-base2 >/dev/null 2>&1; then w2_merge_ok=1
else w2_merge_ok=0; fi
[ "$w2_merge_ok" -eq 1 ] || fail "(W-fixture2) the second merge did not apply cleanly"

out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'changed between that commit and the PR head'; then
  pass "(W3) AC-2: the same merge still violates for a record carrying no reviewed_patch_id"
else fail "(W3) expected rc=1 via the inferred arm, got rc=$rc: $out"; fi

# AC-3: a GENUINE post-record change — the branch's OWN fix, not the base's — must still
# violate under the reviewed_patch_id shape: skipping the inferred arm must not open a blind
# spot the declared arm doesn't already close.
w_pid3="$(tree_patch_id HEAD)"
write_verdict approve r-review-w3 sess-review-w3 "$(git -C "$TREE" rev-parse HEAD)" "$w_pid3"
printf 'a real fix landing after the review\n' > "$TREE/docs/plans/notes-403.md"
commit_tree "a genuine branch-side change after the record"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'now hashes to'; then
  pass "(W4) AC-3: a genuine post-record branch-side change still violates under the reviewed_patch_id shape"
else fail "(W4) expected rc=1 via the declared arm's patch-id mismatch, got rc=$rc: $out"; fi

# ...and re-reviewing clears it, so (W4) is a check with a remedy, matching the rest of the
# suite's convention.
write_verdict approve r-review-w4 sess-review-w4 "$(git -C "$TREE" rev-parse HEAD)" "$(tree_patch_id HEAD)"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'freshness (declared, patch-id'; then
  pass "(W5) a fresh review round over the branch-side fix clears it"
else fail "(W5) expected rc=0 after a new review round, got rc=$rc: $out"; fi


# ---- (X) evidence 8: the armed design render receipt (#394) --------------------------------
# Armed-ness is derived from the COMMITTED SPEC and never from config: `design.provider` lives in
# a gitignored file no CI checkout can see, so a config-keyed boundary would read every consumer
# as unarmed. These cases therefore change the SPEC, never a config, which is also the only lever
# a real PR gives this gate.
#
# (X1) runs FIRST and is the vacuity guard: the whole block asserts nothing if the fixture's
# baseline spec were already armed.
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'declares no armed design render lane'; then
  pass "(X1) a spec with no '## Design' section is unarmed — the arm prints its absence rather than skipping silently"
else fail "(X1) expected the unarmed note on a clean run, got rc=$rc: $out"; fi

# A render manifest matching THIS head, written the way the gate writes one. The path suffix is
# `-lean-renders.md`, which must NOT be picked up by the spec scan's `*-lean.md` first-match —
# (X2b) asserts that rather than assuming it.
RENDREC="$TREE/docs/plans/acme-42-lean-renders.md"
tree_render_id() { # tree_render_id <head-ish>
  local base
  base="$(git -C "$TREE" merge-base refs/remotes/origin/main "$1" 2>/dev/null)" || return 0
  git -C "$TREE" diff "$base" "$1" -- . \
    ":(exclude)docs/plans/acme-42-lean-verdict.md" ":(exclude)docs/plans/acme-42-lean-renders.md" 2>/dev/null \
    | git -C "$TREE" patch-id --stable 2>/dev/null | cut -d' ' -f1
}
write_render_manifest() { # write_render_manifest <rendered-from>
  {
    printf '# lean render manifest — #42\n\n'
    printf 'rendered_from: %s\n\n' "$1"
    printf '| RS | route | state | png | sha256 |\n| --- | --- | --- | --- | --- |\n'
    printf '| RS-1 | prospects | default | .claude/lean-renders/42/RS-1.png | abc123 |\n'
  } > "$RENDREC"
}
# The armed spec. `write_verdict` does not emit `fidelity:`, so the record under test carries
# none until a case adds one — which is the pre-#394 record shape as well as the forgot-the-flag
# one, and both must be refused on an armed ticket.
arm_spec() {
  {
    printf '# lean spec\n\n- AC-1: does a thing\n- AC-2: does another\n\n'
    printf '## Design\n\nHandoff: https://design.example.invalid/f/a\n\n'
    printf '| RS-n | route | state | AC refs |\n| --- | --- | --- | --- |\n'
    printf '| RS-1 | prospects | default | AC-1 |\n'
  } > "$TREE/docs/plans/acme-42-lean.md"
}

# (X2) ARMED, no receipt committed. The screenshots a fidelity verdict claims to have been scored
# against are simply not on the branch.
arm_spec
commit_tree "the spec arms the design render lane"
w_pid="$(tree_patch_id HEAD)"
write_verdict approve r-review-w1 sess-review-w1 "$(git -C "$TREE" rev-parse HEAD)" "$w_pid"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no render receipt'; then
  pass "(X2) an armed spec with no committed render receipt reds the merge boundary"
else fail "(X2) expected the missing-receipt violation, got rc=$rc: $out"; fi

# (X2b) and the spec the gate resolved is still the SPEC. A receipt whose name ended in `-lean.md`
# would win the artifact scan's first match and be read as the definition of done.
if printf '%s' "$out" | grep -q 'spec: docs/plans/acme-42-lean.md'; then
  pass "(X2b) the '-lean-renders.md' suffix never shadows the '*-lean.md' spec scan"
else fail "(X2b) the gate did not resolve the real spec: $out"; fi

# (X3) receipt present, verdict scores no fidelity. The pre-#394 record shape and the
# forgot-the-flag one are the same bytes here, and an armed ticket refuses both — a round that
# never scored the design has not approved it.
write_render_manifest "$(tree_render_id HEAD)"
commit_tree "the render receipt"
w_pid="$(tree_patch_id HEAD)"
write_verdict approve r-review-w2 sess-review-w2 "$(git -C "$TREE" rev-parse HEAD)" "$w_pid"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "not 'fidelity: pass'"; then
  pass "(X3) an armed run refuses a verdict that scores no fidelity"
else fail "(X3) expected the fidelity violation, got rc=$rc: $out"; fi

# (X4) THE HAPPY PATH: armed spec, committed receipt whose rendered_from is this head's render
# binding, and a verdict scoring `fidelity: pass`.
printf 'fidelity: pass\n' >> "$VREC"
commit_tree "the record scores fidelity"
# The receipt's binding excludes the verdict record AND itself, so committing either leaves it
# unchanged — that is what lets the reviewer commit on top of evidence without invalidating it,
# and (X4) is where the two exclusions are asserted together.
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'scored fidelity: pass'; then
  pass "(X4) an armed run with a fresh receipt and a fidelity: pass verdict passes the boundary"
else fail "(X4) expected the armed happy path, got rc=$rc: $out"; fi

# (X5) STALENESS. Nothing else about this tree is stale — the verdict is the last commit and both
# freshness arms stay green — so the receipt is the only thing that can catch a reviewer who
# scored round-1 screenshots against round-2 code. The receipt is rewritten with a binding that
# is well-formed and wrong, which is the shape a real stale receipt has.
write_render_manifest "0000000000000000000000000000000000000000"
commit_tree "a receipt for a tree this branch no longer is"
w_pid="$(tree_patch_id HEAD)"
write_verdict approve r-review-w3 sess-review-w3 "$(git -C "$TREE" rev-parse HEAD)" "$w_pid"
printf 'fidelity: pass\n' >> "$VREC"
commit_tree "an honest record on top of a stale receipt"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'records rendered_from' \
   && ! printf '%s' "$out" | grep -q 'file(s) changed between that commit and the PR head'; then
  pass "(X5) a stale rendered_from reds on a tree whose verdict freshness is green"
else fail "(X5) expected the stale-receipt violation alone, got rc=$rc: $out"; fi

# (X6) DISARMED. The same tree, the same receipt, the same fidelity-less history — with the spec
# declaring the explicit disarm, the arm is not applicable and the boundary says so. This is what
# makes (X2)/(X3)/(X5) turn on ARMING rather than on the artifacts being present.
{
  printf '# lean spec\n\n- AC-1: does a thing\n- AC-2: does another\n\n'
  printf '## Design\n\nDesign: none — no FE surface in this ticket.\n'
} > "$TREE/docs/plans/acme-42-lean.md"
commit_tree "the spec disarms the design lane"
w_pid="$(tree_patch_id HEAD)"
write_verdict approve r-review-w4 sess-review-w4 "$(git -C "$TREE" rev-parse HEAD)" "$w_pid"
out="$(run_gate_base "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt" "main")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'declares no armed design render lane'; then
  pass "(X6) an explicit 'Design: none' disarm leaves the boundary's design arm not applicable"
else fail "(X6) expected the disarmed pass, got rc=$rc: $out"; fi

echo "[check-lean-chain-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

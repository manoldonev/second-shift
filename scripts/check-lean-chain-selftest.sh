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
# shellcheck disable=SC2329  # invoked indirectly by the EXIT trap below
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

echo '[]' > "$WORK/comments-empty.json"

# Committed artifacts live in a throwaway git repo so the gate's `git rev-parse` and its
# find-based artifact scan operate on a controlled tree rather than the real repo.
TREE="$WORK/tree"
mkdir -p "$TREE/docs/plans" "$TREE/scripts/fixtures"
git -C "$TREE" init -q 2>/dev/null
printf '# lean spec\n\n- AC-1: does a thing\n- AC-2: does another\n' > "$TREE/docs/plans/acme-42-lean.md"
printf 'verdict=approve\nrun_id: r-abc123\nrounds: 1\n' > "$TREE/docs/plans/acme-42-lean-verdict.md"
# A lean-SHAPED fixture that must never count as a real artifact.
printf '# fixture\n- AC-9: fixture only\n' > "$TREE/scripts/fixtures/acme-99-lean.md"

printf 'docs/plans/acme-42-lean.md\ndocs/plans/acme-42-lean-verdict.md\n' > "$WORK/diff-lean.txt"
printf 'scripts/fixtures/acme-99-lean.md\nplugins/dev-pipeline/skills/run-lean/lean-gate.sh\n' > "$WORK/diff-fixture-only.txt"
printf 'README.md\n' > "$WORK/diff-plain.txt"

BODY_GOOD='Implements the thing.

Closes #42'

run_gate() { # run_gate <head-ref> <comments-file> <diff-file> [lean-prefix]
  ( cd "$TREE" && \
    LEAN_BRANCH_PREFIX="${4:-lean/acme-}" \
    PIPELINE_BRANCH_PREFIX="claude/acme-" \
    PR_HEAD_REF="$1" \
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
printf 'verdict=needs-work\nrun_id: r-abc123\n' > "$TREE/docs/plans/acme-42-lean-verdict.md"
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "does not read 'verdict=approve'"; then
  pass "(I) a committed verdict=needs-work record blocks the merge boundary"
else fail "(I) expected rc=1 on verdict=needs-work, got rc=$rc: $out"; fi
printf 'verdict=approve\nrun_id: r-abc123\n' > "$TREE/docs/plans/acme-42-lean-verdict.md"

# ---- (J) a spec with no AC-n fails -------------------------------------------------------
printf '# lean spec\n\nNo criteria here.\n' > "$TREE/docs/plans/acme-42-lean.md"
out="$(run_gate "lean/acme-42" "$WORK/comments-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no numbered AC-n'; then
  pass "(J) a committed spec with no AC-n fails (the definition of done must exist)"
else fail "(J) expected rc=1 on an AC-less spec, got rc=$rc: $out"; fi
printf '# lean spec\n\n- AC-1: does a thing\n' > "$TREE/docs/plans/acme-42-lean.md"

# ---- (K) unresolvable constants are FATAL, never exempt ----------------------------------
out="$( cd "$TREE" && LEAN_BRANCH_PREFIX="" PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="lean/acme-42" PR_BODY="$BODY_GOOD" PR_CREATED_AT="$PR_OPEN_AT" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ]; then pass "(K) an empty LEAN_BRANCH_PREFIX is an environment error, not a silent exemption"
else fail "(K) expected rc=2 on an unresolvable prefix, got $rc: $out"; fi

# ---- (L) mutually prefix-matching constants are FATAL ------------------------------------
# `lean/` derived from `claude/second-shift-` would satisfy a one-directional reading of the
# non-prefix-match property while making every pipeline PR applicable here.
out="$( cd "$TREE" && LEAN_BRANCH_PREFIX="claude/" PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" PR_CREATED_AT="$PR_OPEN_AT" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'mutually non-prefix-matching'; then
  pass "(L) prefixes where one is a prefix of the other are rejected as an environment error"
else fail "(L) expected rc=2 on mutually prefix-matching constants, got $rc: $out"; fi

# ---- (M) a lean PR with no issue reference fails -----------------------------------------
out="$( cd "$TREE" && LEAN_BRANCH_PREFIX="lean/acme-" PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="lean/acme-42" PR_BODY="no reference here" PR_CREATED_AT="$PR_OPEN_AT" \
        bash "$GATE" --comments-file "$WORK/comments-good.json" --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no resolvable issue reference'; then
  pass "(M) a lean PR with no 'Closes #N' fails rather than being exempted"
else fail "(M) expected rc=1 on an unresolvable issue reference, got $rc: $out"; fi

echo "[check-lean-chain-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

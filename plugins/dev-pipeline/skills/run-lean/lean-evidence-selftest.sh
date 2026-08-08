#!/usr/bin/env bash
# lean-evidence-selftest.sh — behavioral suite for the portable merge-boundary evidence arms.
#
# Zero-network by construction: every case drives lean-evidence.sh through its two fixture
# seams (--pr-comments-file, --diff-files-file), the check-lean-chain-selftest.sh precedent.
# No `gh`, no git remote.
#
# WHAT THIS SUITE IS FOR that the boundary's own suite is not. check-lean-chain-selftest.sh
# drives these arms through a delegating caller that supplies half the environment; a consumer
# runs this file DIRECTLY, with prefixes derived from a committed config it alone can see and
# a `tracker.type` that may reduce one arm's strength. Those two resolution paths, and the
# jira degrade, exist only on the consumer side and are asserted here.
#
# Exit code = number of failed checks (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/lean-evidence.sh"

FAILS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1" >&2; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d -t leanev.XXXXXX)"
# shellcheck disable=SC2317,SC2329  # invoked indirectly by the EXIT trap below.
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# ---------------------------------------------------------------- the fixture tree
# Real COMMITS, not just files: the freshness arm measures a patch identity against a base, so
# a commit-less tree would make every freshness assertion vacuous and red the happy path for a
# reason it is not about.
TREE="$WORK/tree"
SPEC="$TREE/docs/plans/acme-42-lean.md"
VREC="$TREE/docs/plans/acme-42-lean-verdict.md"
GAPREC="$TREE/docs/plans/acme-42-lean-intent-gap.md"
mkdir -p "$TREE/docs/plans" "$TREE/scripts/fixtures" "$TREE/.claude"
git -C "$TREE" init -q 2>/dev/null
git -C "$TREE" config user.email lean@example.invalid
git -C "$TREE" config user.name lean-selftest

# `add -A` is safe here and nowhere else: this is a throwaway repo under $WORK.
commit_tree() { git -C "$TREE" add -A >/dev/null 2>&1; git -C "$TREE" commit -q --allow-empty -m "$1" >/dev/null 2>&1; }

printf 'seed\n' > "$TREE/README.md"
commit_tree "base"
git -C "$TREE" update-ref refs/remotes/origin/main HEAD

printf '# lean spec\n\n- AC-1: does a thing\n' > "$SPEC"
printf '# fixture\n- AC-9: fixture only\n' > "$TREE/scripts/fixtures/acme-99-lean.md"
commit_tree "spec + fixtures"

# The EXPECTED patch identity, derived here rather than read back from the tool. An ORACLE, not
# the mirror-harness pattern the repo bans: a copy is dangerous when production drifting away
# leaves the suite GREEN, and this one does the opposite — any change to how the arm resolves
# the base, ranges the diff, or excludes the record makes the two disagree and reds every case.
tree_patch_id() {
  local base
  base="$(git -C "$TREE" merge-base refs/remotes/origin/main HEAD 2>/dev/null)" || return 0
  git -C "$TREE" diff "$base" HEAD -- . ":(exclude)docs/plans/acme-42-lean-verdict.md" 2>/dev/null \
    | git -C "$TREE" patch-id --stable 2>/dev/null | cut -d' ' -f1
}

# reviewed_patch_id is resolved BEFORE the commit, which is the real shape: the reviewer hashes
# the head it is on and commits the record on top. Resolving it afterwards would hash a tree
# that already carries the record and leave every freshness case asserting nothing.
write_verdict() { # write_verdict [verdict] [run-id] [session-id] [patch-id|"-" to omit]
  local pid="${4:-AUTO}"
  [ "$pid" = "AUTO" ] && pid="$(tree_patch_id)"
  printf 'verdict=%s\nrun_id: %s\nsession_id: %s\nrounds: 1\nreviewed_head: %s\n' \
    "${1:-approve}" "${2:-r-review-1}" "${3:-sess-review-1}" "$(git -C "$TREE" rev-parse HEAD)" > "$VREC"
  [ "$pid" != "-" ] && printf 'reviewed_patch_id: %s\n' "$pid" >> "$VREC"
  commit_tree "verdict ${1:-approve}"
}

# ---------------------------------------------------------------- marker + diff fixtures
cat > "$WORK/markers-good.json" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" },
   "body": "<!-- dev-pipeline -->\n<!-- run_id: r-build-1 -->\n<!-- session_id: sess-build-1 -->\n<!-- stage: lean-pr-marker -->" }]
EOF
echo '[]' > "$WORK/markers-none.json"
cat > "$WORK/markers-human.json" <<'EOF'
[{ "user": { "type": "User", "login": "someone" },
   "body": "<!-- run_id: r-build-1 -->\n<!-- stage: lean-pr-marker -->" }]
EOF
cat > "$WORK/markers-norunid.json" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" },
   "body": "<!-- dev-pipeline -->\n<!-- stage: lean-pr-marker -->" }]
EOF
cat > "$WORK/markers-two.json" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" },
   "body": "<!-- run_id: r-build-1 -->\n<!-- session_id: sess-build-1 -->\n<!-- stage: lean-pr-marker -->" },
 { "user": { "type": "Bot", "login": "acme-bot" },
   "body": "<!-- run_id: r-build-2 -->\n<!-- session_id: sess-build-2 -->\n<!-- stage: lean-pr-marker -->" }]
EOF

printf 'docs/plans/acme-42-lean.md\ndocs/plans/acme-42-lean-verdict.md\n' > "$WORK/diff-lean.txt"
printf 'scripts/fixtures/acme-99-lean.md\nREADME.md\n' > "$WORK/diff-fixture-only.txt"
printf 'README.md\n' > "$WORK/diff-plain.txt"

BODY_GOOD='Implements the thing.

Closes #42'

# The consumer resolution path: a COMMITTED config, which is the only prefix source a consumer
# has. The env path is asserted separately at (o)/(p).
cat > "$TREE/.claude/second-shift.config.json" <<'EOF'
{ "configVersion": 2,
  "tracker": { "type": "github", "branchPrefix": "claude/acme-" },
  "topology": { "type": "standalone", "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "commands": { "acme": {} } }
EOF
cat > "$WORK/config-jira.json" <<'EOF'
{ "configVersion": 2,
  "tracker": { "type": "jira", "writes": false, "branchPrefix": "abc/" },
  "topology": { "type": "standalone", "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "commands": { "acme": {} } }
EOF
commit_tree "committed consumer config"
write_verdict

# PR_HEAD_SHA is resolved per call, never captured once: cases below add commits, and a stale
# sha would silently measure freshness against an earlier head than the one under test.
ev() { # ev <head-ref> <markers-file> <diff-file> [extra env assignments via caller]
  ( cd "$TREE" && \
    PIPELINE_BRANCH_PREFIX="${PIPELINE_PREFIX_OVERRIDE:-claude/acme-}" \
    PR_HEAD_REF="$1" \
    PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
    PR_BASE_REF="main" \
    PR_BODY="$BODY_GOOD" \
    bash "$TOOL" all --pr-comments-file "$2" --diff-files-file "$3" 2>&1 )
}

# The CONSUMER shape: no prefix constants at all, everything from the committed config.
ev_cfg() { # ev_cfg <head-ref> <markers-file> <diff-file> [config-path]
  ( cd "$TREE" && \
    SECOND_SHIFT_CONFIG="${4:-$TREE/.claude/second-shift.config.json}" \
    PR_HEAD_REF="$1" \
    PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
    PR_BASE_REF="main" \
    PR_BODY="$BODY_GOOD" \
    bash "$TOOL" all --pr-comments-file "$2" --diff-files-file "$3" 2>&1 )
}

echo "[lean-evidence-selftest]"

# ---- (a) the happy path -------------------------------------------------------------------
# AC-1/AC-6: the head ref carries the STAGED prefix, because that is now the only namespace
# either lane cuts. Nothing in this file's environment names a lean namespace.
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'applicable via lean-artifact'; then
  pass "(a) complete evidence on a shared-namespace branch passes, classified by the artifact"
else fail "(a) expected rc=0 via the artifact arm, got $rc: $out"; fi

# ---- (b) applicability --------------------------------------------------------------------
out="$(ev "someone/hotfix" "$WORK/markers-none.json" "$WORK/diff-plain.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'not applicable'; then
  pass "(b) a non-lean branch with no lean artifacts is not applicable"
else fail "(b) expected a not-applicable pass, got $rc: $out"; fi

# AC-9: PRs opened on the RETIRED `lean/` namespace before #413 must keep classifying. Nothing
# knows that namespace any more, so this works only through the body-key fallback finding the
# key-matched spec — which is exactly the mechanism the cutover relies on instead of a legacy
# branch arm. Drive it against the real shape, not a hypothetical one.
out="$(ev "lean/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'applicable via lean-artifact'; then
  pass "(c) a legacy lean/-prefixed PR still classifies, via the body key and the artifact"
else fail "(c) expected the legacy namespace to classify via the artifact arm, got $rc: $out"; fi

# THE MIRROR ERROR, and the reason applicability is KEY-MATCHED rather than "any lean spec".
# This branch's key is 303; the diff carries #42's spec. A suffix-only test would pull an
# unrelated PR into this gate and out of the pipeline gate at the same time.
out="$(ev "claude/acme-303" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'not applicable' \
   && printf '%s' "$out" | grep -q 'resolved key: 303'; then
  pass "(d) a PR carrying some OTHER ticket's lean spec is not classified lean"
else fail "(d) expected not-applicable on a key mismatch, got $rc: $out"; fi

out="$(ev "some/other-branch" "$WORK/markers-good.json" "$WORK/diff-fixture-only.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'not applicable'; then
  pass "(e) lean-SHAPED fixture paths never make a PR applicable"
else fail "(e) expected fixture paths to be excluded, got $rc: $out"; fi

# AC-11: a consumer's workflow may still set the retired constant from an older pin. It is
# announced and ignored — NEVER an envfail, which would red every such repo's PRs. And the
# notice goes to stderr, so `classify`'s key=value block stays parseable (see bb1).
out="$(LEAN_BRANCH_PREFIX="lean/acme-" ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "LEAN_BRANCH_PREFIX ('lean/acme-') is retired and ignored"; then
  pass "(f) a retired LEAN_BRANCH_PREFIX is announced and ignored, not an environment error"
else fail "(f) expected the deprecation notice with a clean pass, got $rc: $out"; fi

# ---- (g) the verdict arm ------------------------------------------------------------------
mv "$VREC" "$WORK/held-verdict.md"; commit_tree "verdict removed"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no committed verdict record'; then
  pass "(g) a missing verdict record fails"
else fail "(g) expected rc=1 on a missing verdict, got $rc: $out"; fi
mv "$WORK/held-verdict.md" "$VREC"; commit_tree "verdict restored"

# ONE FACT, ONE VIOLATION — the count is asserted, not merely printed. A combined run states
# "not approve" once (the verdict arm's); freshness must neither recompute a patch id nor
# restate it, or the consumer's `all` reports one defect as two missing artifacts.
write_verdict needs-work
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "reads 'verdict=needs-work'" \
   && printf '%s' "$out" | grep -q '✗ 1 evidence artifact(s) missing' \
   && ! printf '%s' "$out" | grep -q 'freshness is undefined for a non-approve record' \
   && ! printf '%s' "$out" | grep -q 'now hashes to'; then
  pass "(h) a needs-work record fails EXACTLY once — freshness neither recomputes nor restates it"
else fail "(h) expected the non-approve collapse to one refusal, got $rc: $out"; fi

# ...and the suppression is conditional on the verdict arm having run, not unconditional: a lone
# freshness arm has nothing else stating the fact, so returning quietly would be a vacuous pass.
out="$( cd "$TREE" && \
        PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
        PR_BASE_REF="main" PR_BODY="$BODY_GOOD" \
        bash "$TOOL" check --key 42 --arms freshness 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'freshness is undefined for a non-approve record' \
   && printf '%s' "$out" | grep -q '✗ 1 evidence artifact(s) missing'; then
  pass "(h2) '--arms freshness' alone still refuses a non-approve record — no vacuous pass"
else fail "(h2) expected a lone freshness arm to refuse once, got $rc: $out"; fi

write_verdict approve "" "" ; sed -i.bak '/^run_id:/d' "$VREC" && rm -f "$VREC.bak"; commit_tree "verdict without run_id"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no run_id reconciliation key'; then
  pass "(i) a verdict carrying no run_id fails — its authorship is unseparable from the build's"
else fail "(i) expected rc=1 on a run_id-less verdict, got $rc: $out"; fi

write_verdict approve "" "" ; sed -i.bak '/^session_id:/d' "$VREC" && rm -f "$VREC.bak"; commit_tree "verdict without session_id"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no session_id reconciliation key'; then
  pass "(j) a verdict carrying no session_id fails — the review session cannot be located"
else fail "(j) expected rc=1 on a session_id-less verdict, got $rc: $out"; fi
write_verdict

# ---- (k) the identity arm (P10 / D-2 / D-4) -----------------------------------------------
write_verdict approve r-build-1 sess-review-2
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "BUILD run's identity"; then
  pass "(k) a verdict carrying the build run's id fails"
else fail "(k) expected rc=1 on a build-authored verdict, got $rc: $out"; fi

# The STRONGER comparison. run_id is agent-CHOSEN, so a build session that wants to review
# itself need only pick a second string; the session id is harness-assigned and cannot be.
write_verdict approve r-review-3 sess-build-1
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'names a BUILD session'; then
  pass "(l) a distinct run_id does not launder a verdict written by the build SESSION"
else fail "(l) expected rc=1 on a build-session verdict, got $rc: $out"; fi

write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "no bot-authored 'lean-pr-marker' comment"; then
  pass "(m) ZERO markers is a violation, not a vacuous 'differs from every marker' pass"
else fail "(m) expected rc=1 on an unmarked PR, got $rc: $out"; fi

out="$(ev "claude/acme-42" "$WORK/markers-human.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'none bot-authored'; then
  pass "(n) an operator-posted marker does not satisfy the arm (the trust filter)"
else fail "(n) expected the trust filter to reject a human marker, got $rc: $out"; fi

out="$(ev "claude/acme-42" "$WORK/markers-norunid.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'carry no run_id'; then
  pass "(o) a marker with no run_id leaves the build identity unknown, which is uncheckable"
else fail "(o) expected rc=1 on a run_id-less marker, got $rc: $out"; fi

# D-4: EVERY marker, not the first. The verdict carries the SECOND build session's id; a
# first-match reader compares r-review-* against r-build-1, finds them distinct, and passes.
write_verdict approve r-build-2 sess-review-4
out="$(ev "claude/acme-42" "$WORK/markers-two.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "BUILD run's identity ('r-build-2')"; then
  pass "(p) the comparison walks EVERY marker — the second session's id is caught too (D-4)"
else fail "(p) expected rc=1 against the second marker, got $rc: $out"; fi

write_verdict approve r-review-5 sess-review-5
out="$(ev "claude/acme-42" "$WORK/markers-two.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(q) two markers neither of which the verdict carries still passes — (p) turns on the match"
else fail "(q) expected rc=0 against two non-matching markers, got $rc: $out"; fi

# ---- (r) the freshness arm ----------------------------------------------------------------
write_verdict approve r-review-6 sess-review-6 "-"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'declares no reviewed_patch_id'; then
  pass "(r) a record declaring no reviewed_patch_id fails — nothing states which tree was read"
else fail "(r) expected rc=1 on a patch-id-less record, got $rc: $out"; fi

write_verdict approve r-review-7 sess-review-7 "0000000000000000000000000000000000000000"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'now hashes to'; then
  pass "(s) a reviewed_patch_id that is not this branch's fails"
else fail "(s) expected rc=1 on a moved patch identity, got $rc: $out"; fi

# THE EXCLUSION, driven behaviorally so no copy of the formula can satisfy it: the writer hashes
# a head that does not yet carry the record, this reader hashes one that does.
write_verdict
printf '\nReviewer prose appended after the record was committed.\n' >> "$VREC"
commit_tree "the record's own bytes change"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'freshness (declared, patch-id'; then
  pass "(t) editing the verdict record itself does not move the patch identity (the exclusion holds)"
else fail "(t) expected rc=0 after editing the record, got $rc: $out"; fi

# ...but a real branch-side change does.
printf 'a genuine post-review change\n' > "$TREE/docs/plans/notes.md"
commit_tree "code lands after the review"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'now hashes to'; then
  pass "(u) a commit landing after the review moves the identity and reopens the round"
else fail "(u) expected rc=1 after a post-review commit, got $rc: $out"; fi
write_verdict

# ---- (v) the ratification arm (P9) --------------------------------------------------------
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'no intent-gap record'; then
  pass "(v) absence of an intent-gap record is the ordinary case, and is PRINTED"
else fail "(v) expected the absence notice, got $rc: $out"; fi

printf 'issue: 42\nratified: no\nratified_by:\n\n## Gap\n\nSomething the receipt did not cover.\n' > "$GAPREC"
commit_tree "unratified intent gap"
write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "reads 'ratified: no'"; then
  pass "(w) an unratified intent-gap record blocks the merge boundary"
else fail "(w) expected rc=1 on an unratified gap, got $rc: $out"; fi

printf 'issue: 42\nratified: yes\nratified_by:\n\n## Gap\n\nSomething the receipt did not cover.\n' > "$GAPREC"
commit_tree "ratified but uncited"
write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'cites no'; then
  pass "(x) a 'ratified: yes' citing no operator comment is a self-ratification, and is refused"
else fail "(x) expected rc=1 on an uncited ratification, got $rc: $out"; fi

printf 'issue: 42\nratified: yes\nratified_by: https://example.invalid/issues/42#issuecomment-7\n\n## Gap\n\nCovered.\n' > "$GAPREC"
commit_tree "ratified and cited"
write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'intent gap: .* ratified'; then
  pass "(y) a ratified, cited intent-gap record passes"
else fail "(y) expected rc=0 on a ratified gap, got $rc: $out"; fi
rm -f "$GAPREC"; commit_tree "gap cleared"
write_verdict

# ---- (z) config-derived resolution, the consumer's only path -------------------------------
# A consumer commits .claude/second-shift.config.json and sets NO prefix constant. The branch
# namespace and the tracker type come from that file, or the key derivation has nothing to
# strip and the arm the consumer installed never classifies anything.
out="$(ev_cfg "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'applicable via lean-artifact'; then
  pass "(z1) with no env constant, the namespace comes from the committed tracker.branchPrefix"
else fail "(z1) expected config-derived classification, got $rc: $out"; fi

# The branch key WINS over the body key on a prefixed branch (AC-10). This body says `Closes
# #42` while the branch says 303, and the diff carries only #42's spec: a body-first derivation
# would classify this lean on a key the lane never worked, which is the phantom-key class.
out="$(ev_cfg "claude/acme-303" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'resolved key: 303'; then
  pass "(z2) a prefixed branch takes its key from the branch, never from a body naming another"
else fail "(z2) expected the branch key to win, got $rc: $out"; fi

# ENV WINS over the committed config. This repo gitignores its own config, so its CI must be
# able to hand the constant in — and a consumer that sets one must not silently get the
# committed value instead. Driven where the two DISAGREE, or the case proves nothing: with the
# env prefix in force the branch is unprefixed, so the key falls back to the body.
out="$(PIPELINE_PREFIX_OVERRIDE="zzz-matches-nothing/" ev "claude/acme-303" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'source issue: #42'; then
  pass "(z3) an env namespace overrides the committed config rather than losing to it"
else fail "(z3) expected the env prefix to win, got $rc: $out"; fi

# ---- (aa) AC-6: the jira degrade, per-arm and PRINTED --------------------------------------
# config-lint forbids tracker.bot under jira, so such a consumer has no authenticated writer and
# its markers would fail the Bot filter. The arm says so; it does not quietly skip.
out="$(ev_cfg "lean/-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt" "$WORK/config-jira.json")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'UNAVAILABLE AT REDUCED STRENGTH'; then
  pass "(aa1) under jira the identity arm is unavailable at reduced strength, and says so"
else fail "(aa1) expected the printed jira degrade, got $rc: $out"; fi

# ...and the degrade is PER-ARM. A jira consumer whose verdict record is missing still fails —
# otherwise `tracker.type: jira` would be a global waiver rather than one arm's disclosure.
mv "$VREC" "$WORK/held-verdict.md"; commit_tree "verdict removed (jira)"
out="$(ev_cfg "lean/-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt" "$WORK/config-jira.json")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no committed verdict record'; then
  pass "(aa2) the jira degrade is per-arm: every other arm still gates"
else fail "(aa2) expected rc=1 on a jira consumer's missing verdict, got $rc: $out"; fi
mv "$WORK/held-verdict.md" "$VREC"; commit_tree "verdict restored"
write_verdict

# ---- (bb) the delegation interface ---------------------------------------------------------
# `classify` is what BOTH chain gates consume instead of holding their own copy of these rules;
# the four keys are the contract, and a caller that cannot parse them guesses.
out="$( cd "$TREE" && PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" PR_BASE_REF=main \
        bash "$TOOL" classify --diff-files-file "$WORK/diff-lean.txt" 2>/dev/null )"; rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q '^applicable=1' \
   && printf '%s' "$out" | grep -q '^trigger=lean-artifact' \
   && printf '%s' "$out" | grep -q '^key=42' \
   && printf '%s' "$out" | grep -q '^spec_in_diff=docs/plans/acme-42-lean.md'; then
  pass "(bb1) classify emits all four keys a delegating caller reads"
else fail "(bb1) classify output is not the documented contract, rc=$rc: $out"; fi

# `classify`'s STDOUT is machine-read by two delegating gates, so it must carry key=value lines
# and nothing else — including when the retired constant triggers its deprecation notice. The
# notice belongs on stderr; a prose line inside the block would be parsed as data.
out="$( cd "$TREE" && PIPELINE_BRANCH_PREFIX="claude/acme-" LEAN_BRANCH_PREFIX="lean/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" PR_BASE_REF=main \
        bash "$TOOL" classify --diff-files-file "$WORK/diff-lean.txt" 2>/dev/null )"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -cv '^[a-z_]*=')" = "0" ]; then
  pass "(bb1b) classify's stdout stays pure key=value even while announcing the retired constant"
else fail "(bb1b) classify stdout carried a non-key=value line, rc=$rc: $out"; fi

# ---- (bb2) the artifact scan FAILS CLOSED on a diff it cannot read -------------------------
# The three cases below drive the LIVE git path (no --diff-files-file), which is what CI takes.
# They exist because #413 made this scan the SOLE applicability arm: with the branch-namespace
# arm gone, "the diff was unreadable" and "the PR carries no lean spec" produce the same empty
# file list, and the second is a merge-boundary exemption. Each asserts rc=2 AND that no
# `applicable=` line was emitted — a silent `applicable=0` is the exact failure being closed,
# and it is also what a producer envfailing inside a `< <( )` process substitution would print,
# since that exit dies in the subshell and the reader sees a clean EOF.
out="$( cd "$TREE" && PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" PR_BASE_REF=main \
        bash "$TOOL" classify 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^applicable=1'; then
  pass "(bb2a) the live git diff path classifies — the fail-closed cases below are not vacuous"
else fail "(bb2a) expected the live path to classify applicable=1, got $rc: $out"; fi

out="$( cd "$TREE" && env -u PR_BASE_REF PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" \
        bash "$TOOL" classify 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] \
   && printf '%s' "$out" | grep -q 'PR_BASE_REF is unset or empty' \
   && ! printf '%s' "$out" | grep -q '^applicable='; then
  pass "(bb2b) an unset PR_BASE_REF is an environment error, never a silent non-lean verdict"
else fail "(bb2b) expected rc=2 and no applicable= line, got $rc: $out"; fi

out="$( cd "$TREE" && PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" PR_BASE_REF=no-such-base \
        bash "$TOOL" classify 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] \
   && printf '%s' "$out" | grep -q 'merge-base' \
   && ! printf '%s' "$out" | grep -q '^applicable='; then
  pass "(bb2c) an unresolvable merge-base is an environment error too (the shallow-checkout shape)"
else fail "(bb2c) expected rc=2 and no applicable= line, got $rc: $out"; fi

# The violation COUNT, not just the exit code: a delegating caller prints one combined total,
# and collapsing "2 missing" to "1 call failed" loses the quantity an operator triages by.
mv "$VREC" "$WORK/held-verdict.md"; commit_tree "verdict removed (count)"
CNT="$WORK/count.txt"
( cd "$TREE" && PIPELINE_BRANCH_PREFIX="claude/acme-" \
    PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" PR_BASE_REF=main \
    PR_BODY="$BODY_GOOD" bash "$TOOL" check --key 42 --arms verdict --violations-file "$CNT" \
    --pr-comments-file "$WORK/markers-good.json" >/dev/null 2>&1 )
if [ "$(cat "$CNT" 2>/dev/null)" = "1" ]; then
  pass "(bb2) --violations-file reports the arm's own violation count to a delegating caller"
else fail "(bb2) expected a count of 1, got '$(cat "$CNT" 2>/dev/null)'"; fi
mv "$WORK/held-verdict.md" "$VREC"; commit_tree "verdict restored"
write_verdict

# --arms is a FILTER, so a caller can take one arm and keep its own copy of the rest. Without
# this, delegating a subset would silently run all four and double-count against the caller.
( cd "$TREE" && PIPELINE_BRANCH_PREFIX="claude/acme-" \
    PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" PR_BASE_REF=main \
    PR_BODY="$BODY_GOOD" bash "$TOOL" check --key 42 --arms intent-gap --violations-file "$CNT" \
    --pr-comments-file "$WORK/markers-none.json" >"$WORK/armsout.txt" 2>&1 ); rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$CNT" 2>/dev/null)" = "0" ] \
   && ! grep -q 'lean-pr-marker' "$WORK/armsout.txt"; then
  pass "(bb3) --arms selects: an unmarked PR passes when only the intent-gap arm is asked for"
else fail "(bb3) expected the identity arm to be filtered out, rc=$rc: $(cat "$WORK/armsout.txt")"; fi

# `--help` prints through the last header line and stops before the code. `sed -n '2,Np'` is a
# hand-maintained line number, and this repo has been burned by a header that outgrew it.
out="$(bash "$TOOL" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q 'counter IS the control flow' \
   && ! printf '%s' "$out" | grep -q '^set -uo pipefail'; then
  pass "(bb4) --help prints through the last header line and stops before the code"
else fail "(bb4) --help did not print exactly the header, rc=$rc: $out"; fi

# ---- (cc) the two paths nothing above reached ---------------------------------------------
# Both were found by the mutation sweep, not by reading: an unbaselined survivor is a
# regression the suite would not have caught, and these are what its first run on this guard
# reported.

# A lean PR whose body names no issue, on a branch OUTSIDE the namespace — so nothing resolves
# a key. Everything downstream keys on that number (the verdict record, the intent-gap record,
# the arms' file lookups), so resolving nothing and continuing would run every arm against the
# empty key and report "no committed verdict record" for an issue that was never identified.
# The refusal is the only correct outcome, and until this case existed, flipping its `exit 1`
# to `exit 0` passed the whole suite.
#
# It must be a REFUSAL and not a decline: this PR is outside the pipeline namespace too, so the
# pipeline gate exempts it. A decline here would leave a lean PR gated by neither boundary.
out="$( cd "$TREE" && PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="hand/made-branch" PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" PR_BASE_REF=main \
        PR_BODY="A body that references nothing at all." \
        bash "$TOOL" all --pr-comments-file "$WORK/markers-good.json" \
        --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no resolvable issue reference'; then
  pass "(cc1) a lean PR whose body resolves no issue key is refused, not run against an empty key"
else fail "(cc1) expected rc=1 on an unresolvable issue reference, got $rc: $out"; fi

# THE LIVE FETCH PATH. Every case above hands the marker trail in through --pr-comments-file,
# which seams past `${GH:-gh}` entirely — so the one line a consumer's CI actually depends on
# was the only unexercised statement in the identity arm. A stub `gh` on PATH exercises it for
# real: with the fallback broken the fetch cannot run, and an arm that cannot run must not pass.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
cat "$LEAN_EV_MARKERS"
GHSTUB
chmod +x "$WORK/bin/gh"
out="$( cd "$TREE" && PATH="$WORK/bin:$PATH" LEAN_EV_MARKERS="$WORK/markers-good.json" \
        PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" PR_BASE_REF=main \
        PR_BODY="$BODY_GOOD" PR_NUMBER=9 GH_REPO="acme/acme" \
        bash "$TOOL" all --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '✓ authorship'; then
  pass "(cc2) the identity arm fetches its marker trail through the live gh path, not only the fixture seam"
else fail "(cc2) expected the live-fetch path to pass, got $rc: $out"; fi

echo "[lean-evidence-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

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
OVREC="$TREE/docs/plans/acme-42-lean-override.md"
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
# THE SCORECARD EVERY CASE ABOVE THE (sc) BLOCK CARRIES (#622). The fixture spec declares exactly
# `AC-1`, so this is the minimum conforming table for it. Written through `${VSCORECARD-...}` —
# no colon — so a case can set VSCORECARD to a LITERAL of its own, or to the empty string to omit
# the section entirely, which is the arm the (sc) cases vary.
VSCORECARD_DEFAULT='
## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | fixture |
'

write_verdict() { # write_verdict [verdict] [run-id] [session-id] [patch-id|"-" to omit]
  local pid="${4:-AUTO}"
  [ "$pid" = "AUTO" ] && pid="$(tree_patch_id)"
  printf 'verdict=%s\nrun_id: %s\nsession_id: %s\nrounds: 1\nreviewed_head: %s\n' \
    "${1:-approve}" "${2:-r-review-1}" "${3:-sess-review-1}" "$(git -C "$TREE" rev-parse HEAD)" > "$VREC"
  [ "$pid" != "-" ] && printf 'reviewed_patch_id: %s\n' "$pid" >> "$VREC"
  printf '%s' "${VSCORECARD-$VSCORECARD_DEFAULT}" >> "$VREC"
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

# ---- claim-trail fixtures: the producer's capability stamp (#445) --------------------------
# The stamp rides the ISSUE's bot-authored claim comment, which every github producer generation
# posts — that is what lets a bound arm tell "this harness could not write the artifact" from
# "this run withheld it". `claim-stamped.json` is the CURRENT generation and is what every case
# in this file runs on by default; the others are the reachable degrades.
cat > "$WORK/claim-stamped.json" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" },
   "body": "<!-- dev-pipeline -->\n<!-- run_id: r-build-1 -->\n<!-- session_id: sess-build-1 -->\n<!-- capabilities: pr-marker -->\n<!-- stage: lean-claimed -->" }]
EOF
# THE PRE-TOKEN GENERATION (AC-5). A claim comment exactly as the shipped producer writes one:
# bot-authored, well-formed, carrying no `capabilities:` key at all. This fixture is what keeps
# the inert path killable once stamped runs are the norm and every other fixture here has a stamp.
cat > "$WORK/claim-unstamped.json" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" },
   "body": "<!-- dev-pipeline -->\n<!-- run_id: r-build-1 -->\n<!-- session_id: sess-build-1 -->\n<!-- stage: lean-claimed -->" }]
EOF
# A generation that stamps something else. A stamp naming a capability this arm does not bind to
# is simply not `pr-marker`, and must decline rather than red.
cat > "$WORK/claim-othercap.json" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" },
   "body": "<!-- dev-pipeline -->\n<!-- run_id: r-build-1 -->\n<!-- capabilities: design-render -->\n<!-- stage: lean-claimed -->" }]
EOF
# The trust filter reaches the stamp too: anyone can comment on a public issue, so an
# operator-posted `capabilities:` line must not arm anything.
cat > "$WORK/claim-human-stamped.json" <<'EOF'
[{ "user": { "type": "User", "login": "someone" },
   "body": "<!-- run_id: r-build-1 -->\n<!-- capabilities: pr-marker -->\n<!-- stage: lean-claimed -->" }]
EOF
# UNION, never intersection (D-5). One stale pre-token claim beside a stamped one must not
# disarm the arm for the whole issue.
cat > "$WORK/claim-mixed.json" <<'EOF'
[{ "user": { "type": "Bot", "login": "acme-bot" },
   "body": "<!-- run_id: r-old -->\n<!-- stage: lean-claimed -->" },
 { "user": { "type": "Bot", "login": "acme-bot" },
   "body": "<!-- run_id: r-build-1 -->\n<!-- capabilities: pr-marker -->\n<!-- stage: lean-claimed -->" }]
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
# #440: the same jira consumer that DOES configure a bot. config-lint used to forbid this block
# under jira; now that it is legal, the identity arm has an authenticated writer to check.
cat > "$WORK/config-jira-bot.json" <<'EOF'
{ "configVersion": 2,
  "tracker": { "type": "jira", "writes": false, "branchPrefix": "abc/",
               "bot": { "enabled": true, "app": { "appName": "acme-pipeline-bot" } } },
  "topology": { "type": "standalone", "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "commands": { "acme": {} } }
EOF
# ...and a github consumer that explicitly DISABLES its bot. The degrade keys on the writer, so
# it is reachable from either tracker; before #440 no github config could reach it at all.
cat > "$WORK/config-github-nobot.json" <<'EOF'
{ "configVersion": 2,
  "tracker": { "type": "github", "branchPrefix": "claude/acme-", "bot": { "enabled": false } },
  "topology": { "type": "standalone", "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "commands": { "acme": {} } }
EOF
commit_tree "committed consumer config"
write_verdict

# The PR-open instant every case runs on, and it is DELIBERATELY after the identity arm's
# `since:` (#444). Every case that predates this file's cutoff work asserts the arm ENFORCING,
# which is only what it still does while the fixture PR opened inside the arm's window — a
# fixture clock left in the past would turn all of them into vacuous `postdated` declines while
# reading exactly as green as before. Cases that want the other side of the cutoff override it.
#
# An arm that later declares a `since:` past this instant must move it forward, for the same
# reason. `PR_CREATED_AT_OVERRIDE=none` drops the variable entirely (AC-3).
PR_OPEN_AT='2026-08-09T00:00:00Z'
ev_env() { # ev_env — set EV_ENV to the PR_CREATED_AT assignment, or to nothing when absent
  EV_ENV=()
  case "${PR_CREATED_AT_OVERRIDE:-}" in
    none) : ;;
    "")   EV_ENV=(PR_CREATED_AT="$PR_OPEN_AT") ;;
    *)    EV_ENV=(PR_CREATED_AT="$PR_CREATED_AT_OVERRIDE") ;;
  esac
}

# PR_HEAD_SHA is resolved per call, never captured once: cases below add commits, and a stale
# sha would silently measure freshness against an earlier head than the one under test.
ev() { # ev <head-ref> <markers-file> <diff-file> [extra env assignments via caller]
  ( cd "$TREE" && \
    ev_env && env ${EV_ENV[@]+"${EV_ENV[@]}"} \
    PIPELINE_BRANCH_PREFIX="${PIPELINE_PREFIX_OVERRIDE:-claude/acme-}" \
    PR_HEAD_REF="$1" \
    PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
    PR_BASE_REF="main" \
    PR_BODY="$BODY_GOOD" \
    bash "$TOOL" all --pr-comments-file "$2" --diff-files-file "$3" \
                     --issue-comments-file "${ISSUE_COMMENTS_OVERRIDE:-$WORK/claim-stamped.json}" 2>&1 )
}

# The CONSUMER shape: no prefix constants at all, everything from the committed config.
ev_cfg() { # ev_cfg <head-ref> <markers-file> <diff-file> [config-path]
  ( cd "$TREE" && \
    ev_env && env ${EV_ENV[@]+"${EV_ENV[@]}"} \
    SECOND_SHIFT_CONFIG="${4:-$TREE/.claude/second-shift.config.json}" \
    PR_HEAD_REF="$1" \
    PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
    PR_BASE_REF="main" \
    PR_BODY="$BODY_GOOD" \
    bash "$TOOL" all --pr-comments-file "$2" --diff-files-file "$3" \
                     --issue-comments-file "${ISSUE_COMMENTS_OVERRIDE:-$WORK/claim-stamped.json}" 2>&1 )
}

# ---- the #443 output-class assertions ------------------------------------------------------
# CLASS (a) IS SILENCE ON BOTH STREAMS. Every `ev`/`ev_cfg` call above folds stderr into stdout
# (`2>&1`), so an EMPTY capture is the whole assertion — and a real one, not the bare exit-status
# demotion AC-7 forbids: it fails the moment any arm resumes narrating, in either direction.
# It is also what replaces each removed `grep '✓ …'`, since an arm that stopped running would
# leave the run just as silent but its own NEGATIVE case red.
silent() { [ -z "$1" ]; }

# CLASS (b) IS ONE PINNED LINE. Anchored whole, not grepped for a phrase: the successors to #443
# emit into this class, and the shape — stream, prefix, arm, closed disposition — is the thing
# this ticket fixes for them. A line that drifted to two, or to a fifth disposition, is the
# regression, and only a full-line anchor sees it.
CLASS_B_RE='^\[lean-evidence\]   · [a-z][a-z-]*: (not-applicable|reduced-strength|postdated|inert) — .'
class_b() { # class_b <output> [expected-arm:disposition]
  [ "$(printf '%s\n' "$1" | grep -cE "$CLASS_B_RE")" = "1" ] || return 1
  [ -z "${2:-}" ] || grep -qE "^\[lean-evidence\]   · ${2%%:*}: ${2##*:} — " <<<"$1"
}

echo "[lean-evidence-selftest]"

# ---- (a) the happy path -------------------------------------------------------------------
# AC-1/AC-6: the head ref carries the STAGED prefix, because that is now the only namespace
# either lane cuts. Nothing in this file's environment names a lean namespace.
#
# AC-2 (#443) rides here too: every arm on this run is class (a), so the tool writes NOTHING.
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(a) AC-2: complete evidence passes with zero bytes on stdout and stderr"
else fail "(a) expected a silent rc=0, got $rc: $out"; fi

# ---- (b) applicability --------------------------------------------------------------------
# A whole-gate decline is class (b), not (a): nothing was evaluated, and an unevaluated gate that
# printed nothing would be indistinguishable from one that checked everything.
out="$(ev "someone/hotfix" "$WORK/markers-none.json" "$WORK/diff-plain.txt")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "lean-evidence:not-applicable"; then
  pass "(b) AC-3: a non-lean branch declines in exactly one class-(b) line"
else fail "(b) expected a one-line not-applicable pass, got $rc: $out"; fi

# AC-9: PRs opened on the RETIRED `lean/` namespace before #413 must keep classifying. Nothing
# knows that namespace any more, so this works only through the body-key fallback finding the
# key-matched spec — which is exactly the mechanism the cutover relies on instead of a legacy
# branch arm. Drive it against the real shape, not a hypothetical one.
#
# Asserted as SILENCE, which is the classification assertion now: had the legacy PR failed to
# classify, the class-(b) decline line above would be here instead of nothing.
out="$(ev "lean/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(c) a legacy lean/-prefixed PR still classifies, via the body key and the artifact"
else fail "(c) expected the legacy namespace to classify (and so run silently), got $rc: $out"; fi

# THE MIRROR ERROR, and the reason applicability is KEY-MATCHED rather than "any lean spec".
# This branch's key is 303; the diff carries #42's spec. A suffix-only test would pull an
# unrelated PR into this gate and out of the pipeline gate at the same time.
out="$(ev "claude/acme-303" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "lean-evidence:not-applicable" \
   && grep -q 'resolved key: 303' <<<"$out"; then
  pass "(d) a PR carrying some OTHER ticket's lean spec is not classified lean"
else fail "(d) expected not-applicable on a key mismatch, got $rc: $out"; fi

out="$(ev "some/other-branch" "$WORK/markers-good.json" "$WORK/diff-fixture-only.txt")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "lean-evidence:not-applicable"; then
  pass "(e) lean-SHAPED fixture paths never make a PR applicable"
else fail "(e) expected fixture paths to be excluded, got $rc: $out"; fi

# AC-11: a consumer's workflow may still set the retired constant from an older pin. It is
# announced and ignored — NEVER an envfail, which would red every such repo's PRs. And the
# notice goes to stderr, so `classify`'s key=value block stays parseable (see bb1).
out="$(LEAN_BRANCH_PREFIX="lean/acme-" ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q "LEAN_BRANCH_PREFIX ('lean/acme-') is retired and ignored" <<<"$out"; then
  pass "(f) a retired LEAN_BRANCH_PREFIX is announced and ignored, not an environment error"
else fail "(f) expected the deprecation notice with a clean pass, got $rc: $out"; fi

# ---- (g) the verdict arm ------------------------------------------------------------------
mv "$VREC" "$WORK/held-verdict.md"; commit_tree "verdict removed"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no committed verdict record' <<<"$out"; then
  pass "(g) a missing verdict record fails"
else fail "(g) expected rc=1 on a missing verdict, got $rc: $out"; fi
mv "$WORK/held-verdict.md" "$VREC"; commit_tree "verdict restored"

# ONE FACT, ONE VIOLATION — the count is asserted, not merely printed. A combined run states
# "not approve" once (the verdict arm's); freshness must neither recompute a patch id nor
# restate it, or the consumer's `all` reports one defect as two missing artifacts.
write_verdict needs-work
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "reads 'verdict=needs-work'" <<<"$out" \
   && grep -q '✗ 1 evidence artifact(s) missing' <<<"$out" \
   && ! grep -q 'freshness is undefined for a non-approve record' <<<"$out" \
   && ! grep -q 'now hashes to' <<<"$out"; then
  pass "(h) a needs-work record fails EXACTLY once — freshness neither recomputes nor restates it"
else fail "(h) expected the non-approve collapse to one refusal, got $rc: $out"; fi

# ...and the suppression is conditional on the verdict arm having run, not unconditional: a lone
# freshness arm has nothing else stating the fact, so returning quietly would be a vacuous pass.
out="$( cd "$TREE" && \
        PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
        PR_BASE_REF="main" PR_BODY="$BODY_GOOD" \
        bash "$TOOL" check --key 42 --arms freshness 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'freshness is undefined for a non-approve record' <<<"$out" \
   && grep -q '✗ 1 evidence artifact(s) missing' <<<"$out"; then
  pass "(h2) '--arms freshness' alone still refuses a non-approve record — no vacuous pass"
else fail "(h2) expected a lone freshness arm to refuse once, got $rc: $out"; fi

write_verdict approve "" "" ; sed -i.bak '/^run_id:/d' "$VREC" && rm -f "$VREC.bak"; commit_tree "verdict without run_id"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no run_id reconciliation key' <<<"$out"; then
  pass "(i) a verdict carrying no run_id fails — its authorship is unseparable from the build's"
else fail "(i) expected rc=1 on a run_id-less verdict, got $rc: $out"; fi

write_verdict approve "" "" ; sed -i.bak '/^session_id:/d' "$VREC" && rm -f "$VREC.bak"; commit_tree "verdict without session_id"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no session_id reconciliation key' <<<"$out"; then
  pass "(j) a verdict carrying no session_id fails — the review session cannot be located"
else fail "(j) expected rc=1 on a session_id-less verdict, got $rc: $out"; fi
write_verdict

# ---- (k) the identity arm (P10 / D-2 / D-4) -----------------------------------------------
write_verdict approve r-build-1 sess-review-2
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "BUILD run's identity" <<<"$out"; then
  pass "(k) a verdict carrying the build run's id fails"
else fail "(k) expected rc=1 on a build-authored verdict, got $rc: $out"; fi

# The STRONGER comparison. run_id is agent-CHOSEN, so a build session that wants to review
# itself need only pick a second string; the session id is harness-assigned and cannot be.
write_verdict approve r-review-3 sess-build-1
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'names a BUILD session' <<<"$out"; then
  pass "(l) a distinct run_id does not launder a verdict written by the build SESSION"
else fail "(l) expected rc=1 on a build-session verdict, got $rc: $out"; fi

write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "no bot-authored 'lean-pr-marker' comment" <<<"$out"; then
  pass "(m) ZERO markers is a violation, not a vacuous 'differs from every marker' pass"
else fail "(m) expected rc=1 on an unmarked PR, got $rc: $out"; fi

out="$(ev "claude/acme-42" "$WORK/markers-human.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'none bot-authored' <<<"$out"; then
  pass "(n) an operator-posted marker does not satisfy the arm (the trust filter)"
else fail "(n) expected the trust filter to reject a human marker, got $rc: $out"; fi

out="$(ev "claude/acme-42" "$WORK/markers-norunid.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'carry no run_id' <<<"$out"; then
  pass "(o) a marker with no run_id leaves the build identity unknown, which is uncheckable"
else fail "(o) expected rc=1 on a run_id-less marker, got $rc: $out"; fi

# D-4: EVERY marker, not the first. The verdict carries the SECOND build session's id; a
# first-match reader compares r-review-* against r-build-1, finds them distinct, and passes.
write_verdict approve r-build-2 sess-review-4
out="$(ev "claude/acme-42" "$WORK/markers-two.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "BUILD run's identity ('r-build-2')" <<<"$out"; then
  pass "(p) the comparison walks EVERY marker — the second session's id is caught too (D-4)"
else fail "(p) expected rc=1 against the second marker, got $rc: $out"; fi

write_verdict approve r-review-5 sess-review-5
out="$(ev "claude/acme-42" "$WORK/markers-two.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(q) two markers neither of which the verdict carries still passes — (p) turns on the match"
else fail "(q) expected a silent rc=0 against two non-matching markers, got $rc: $out"; fi

# ---- (r) the freshness arm ----------------------------------------------------------------
write_verdict approve r-review-6 sess-review-6 "-"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'declares no reviewed_patch_id' <<<"$out"; then
  pass "(r) a record declaring no reviewed_patch_id fails — nothing states which tree was read"
else fail "(r) expected rc=1 on a patch-id-less record, got $rc: $out"; fi

# #597 D-4 re-shapes this case, and the re-shaping IS the feature. A patch identity that is not
# this branch's is no longer sufficient on its own: `branch_patch_id`'s input includes the
# merge-base, so a base advance moves it while the branch alters not one line, and refusing on the
# hash alone is what forced the #583 re-stamp. The refusal now needs the branch's own `+`/`-` lines
# to have moved TOO — so the fixture lands a real code commit after the record, and the assertion
# gains the enumeration D-6 requires.
write_verdict approve r-review-7 sess-review-7 "0000000000000000000000000000000000000000"
printf 'a real code change landed after the review\n' >> "$TREE/README.md"
commit_tree "code changes after the record"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'now hashes to' <<<"$out" \
   && grep -q 'README.md: 1 line(s)' <<<"$out" \
   && grep -q 'e.g. +a real code change landed after the review' <<<"$out"; then
  pass "(s) a patch identity that moved AND a branch line that moved with it fails, naming the file, the count and the offending line"
else fail "(s) expected rc=1 with an enumerated refusal, got $rc: $out"; fi

# ---- (s2) #597 AC-1/D-4: the base-advance tolerance, at the merge boundary -------------------
# Without this arm milestone 4 passes in the lane and `pr-gates` still reds on the identical base
# merge — which is exactly what forced the #583 re-stamp — so AC-1 would be true in the lane and
# false at merge time. The fixture reproduces the sequence: a record confirmed at head H, then a
# base advance INTO A FILE THE BRANCH ALSO TOUCHES, merged in with a resolution adding no branch
# line. Non-vacuity is asserted against plain git in (s2a): if the recomputed identity does not
# actually move, (s2) is measuring nothing.
s2_origin_saved="$(git -C "$TREE" rev-parse refs/remotes/origin/main)"
printf 'c1\nc2\nc3\nc4\nc5\nc6\nc7\nc8\nc9\nc10\n' > "$TREE/shared.txt"
commit_tree "the shared file, on the branch and about to be on the base"
s2_base_start="$(git -C "$TREE" rev-parse HEAD)"
git -C "$TREE" update-ref refs/remotes/origin/main "$s2_base_start"
printf 'c1\nc2\nc3\nc4\nc5\nc6\nc7\nc8\nc9\nc10\nBRANCH-OWN-LINE\n' > "$TREE/shared.txt"
commit_tree "the branch appends its own line"
write_verdict approve r-review-8 sess-review-8
s2_pid_before="$(grep -oE 'reviewed_patch_id:[[:space:]]*[A-Za-z0-9._-]+' "$VREC" | head -n1 | sed -E 's/^reviewed_patch_id:[[:space:]]*//')"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ]; then pass "(s2-baseline) the boundary passes on the pre-merge head, so the case starts from a confirmed verdict"
else fail "(s2-baseline) expected rc=0 before the base advance, got $rc: $out"; fi

# The unrelated base advance, inside the branch hunk's CONTEXT — which is the mechanism, since
# `git patch-id` hashes context lines. Committed on a detached base ref, then merged in.
git -C "$TREE" branch -f s2-base "$s2_base_start" >/dev/null 2>&1
s2_branch="$(git -C "$TREE" symbolic-ref --short HEAD 2>/dev/null)"
git -C "$TREE" checkout -q s2-base 2>/dev/null
printf 'c1\nc2\nc3\nc4\nc5\nc6\nc7\nBASE-EDIT\nc9\nc10\n' > "$TREE/shared.txt"
git -C "$TREE" add shared.txt >/dev/null 2>&1
git -C "$TREE" commit -q -m 'an unrelated PR lands on the base' >/dev/null 2>&1
git -C "$TREE" update-ref refs/remotes/origin/main s2-base
git -C "$TREE" checkout -q "$s2_branch" 2>/dev/null
git -C "$TREE" merge -q --no-edit s2-base >/dev/null 2>&1; s2_merge_ok=$?
s2_pid_now="$(tree_patch_id)"
if [ "$s2_merge_ok" -eq 0 ] && [ -n "$s2_pid_before" ] && [ -n "$s2_pid_now" ] \
   && [ "$s2_pid_before" != "$s2_pid_now" ]; then
  pass "(s2a) the base really advanced into a file the branch touches and the recomputed patch identity moved — the arm would have redded"
else fail "(s2a) the fixture did not reproduce the #583 state (merge_ok=$s2_merge_ok, '$s2_pid_before' -> '$s2_pid_now') — (s2) would assert nothing"; fi

out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q "own +/- lines is unchanged since reviewed_head" <<<"$out"; then
  pass "(s2) AC-1: the merge boundary passes a base advance that altered no reviewed line, and says why"
else fail "(s2) expected rc=0 with a named base-advance line, got $rc: $out"; fi

# (s3) AC-6/OR-1: the declared fail-open, asserted rather than left to a reading of the code.
# The comparison cannot be computed — the record names a reviewed_head this checkout does not
# carry — and the operator constraint is that invalidation requires certainty, so the verdict
# stands and the line names which way it defaulted, on the class-(b) `reduced-strength` channel.
perl -i -pe 's/^reviewed_head:.*$/reviewed_head: 0123456789abcdef0123456789abcdef01234567/' "$VREC"
commit_tree "the record names a head this checkout does not carry"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'freshness: reduced-strength' <<<"$out" && grep -q 'OR-1' <<<"$out"; then
  pass "(s3) AC-6/OR-1: an uncomputable comparison passes rather than reds, on the reduced-strength channel, naming the fail-open"
else fail "(s3) expected rc=0 with a named fail-open, got $rc: $out"; fi

# (s4) AC-6/OR-1 again, by the OTHER route into it — the one that was dark. `contribution_delta`
# reaches rc=2 two ways, and (s3) drives only the first: a reviewed_head this checkout cannot read,
# which returns from `contribution_lines` before the empty-contribution guard is ever reached. The
# second is both sides computing fine and ONE OF THEM COMING OUT EMPTY, and it is the dangerous
# one: an unguarded reader `cmp`s the empty side against the full one, finds them different, and
# INVALIDATES — in precisely the case OR-1 exists to let stand. Two cases over one route read as
# covered for as long as nothing drove the other. Here a readable reviewed_head that is an ancestor
# of the base measures its own contribution as empty, which is the shape a record inherited across
# a re-point produces.
s4_head="$(git -C "$TREE" rev-parse refs/remotes/origin/main)"
perl -i -pe "s/^reviewed_head:.*\$/reviewed_head: $s4_head/" "$VREC"
commit_tree "the record names a readable head whose own contribution is empty"
s4_own="$(git -C "$TREE" diff --name-only "$(git -C "$TREE" merge-base refs/remotes/origin/main "$s4_head" 2>/dev/null)" "$s4_head" 2>/dev/null)"
s4_new="$(git -C "$TREE" diff --name-only "$(git -C "$TREE" merge-base refs/remotes/origin/main HEAD 2>/dev/null)" HEAD 2>/dev/null)"
if git -C "$TREE" cat-file -e "$s4_head^{commit}" 2>/dev/null && [ -z "$s4_own" ] && [ -n "$s4_new" ]; then
  pass "(s4a) the fixture drives the OTHER rc=2 route: reviewed_head IS readable here, and its own contribution is empty where this head's is not"
else fail "(s4a) the fixture did not reproduce the empty-contribution shape (own='$s4_own', new='$s4_new') — (s4) would only re-assert (s3)'s route"; fi

out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'freshness: reduced-strength' <<<"$out" && grep -q 'OR-1' <<<"$out"; then
  pass "(s4) AC-6/OR-1: an EMPTY contribution on one side fails open too, rather than comparing empty against full and invalidating"
else fail "(s4) expected rc=0 with a named fail-open, got $rc: $out"; fi

# Housekeeping, and origin/main is the load-bearing half. The live-git classify cases below
# (bb2a) measure `diff origin/main HEAD`, so leaving the ref advanced past the spec's own commit
# would make the spec invisible to them and report applicable=0 for a reason this block invented.
rm -f "$TREE/shared.txt"; commit_tree "remove the (s2) shared fixture file"
git -C "$TREE" branch -D s2-base >/dev/null 2>&1
git -C "$TREE" update-ref refs/remotes/origin/main "$s2_origin_saved"

# THE EXCLUSION, driven behaviorally so no copy of the formula can satisfy it: the writer hashes
# a head that does not yet carry the record, this reader hashes one that does.
write_verdict
printf '\nReviewer prose appended after the record was committed.\n' >> "$VREC"
commit_tree "the record's own bytes change"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(t) editing the verdict record itself does not move the patch identity (the exclusion holds)"
else fail "(t) expected a silent rc=0 after editing the record, got $rc: $out"; fi

# ...but a real branch-side change does.
printf 'a genuine post-review change\n' > "$TREE/docs/plans/notes.md"
commit_tree "code lands after the review"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'now hashes to' <<<"$out"; then
  pass "(u) a commit landing after the review moves the identity and reopens the round"
else fail "(u) expected rc=1 after a post-review commit, got $rc: $out"; fi
write_verdict

# ---- (v) the ratification arm (P9) --------------------------------------------------------
# Absence is the ordinary case and CLASS (a) since #443 — nothing went unevaluated, so nothing is
# printed. The arm's kill criteria are (w)/(x) below, which are unchanged.
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(v) absence of an intent-gap record is the ordinary case, and is silent"
else fail "(v) expected a silent pass with no gap record, got $rc: $out"; fi

printf 'issue: 42\nratified: no\nratified_by:\n\n## Gap\n\nSomething the receipt did not cover.\n' > "$GAPREC"
commit_tree "unratified intent gap"
write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "reads 'ratified: no'" <<<"$out"; then
  pass "(w) an unratified intent-gap record blocks the merge boundary"
else fail "(w) expected rc=1 on an unratified gap, got $rc: $out"; fi

printf 'issue: 42\nratified: yes\nratified_by:\n\n## Gap\n\nSomething the receipt did not cover.\n' > "$GAPREC"
commit_tree "ratified but uncited"
write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'cites no' <<<"$out"; then
  pass "(x) a 'ratified: yes' citing no operator comment is a self-ratification, and is refused"
else fail "(x) expected rc=1 on an uncited ratification, got $rc: $out"; fi

printf 'issue: 42\nratified: yes\nratified_by: https://example.invalid/issues/42#issuecomment-7\n\n## Gap\n\nCovered.\n' > "$GAPREC"
commit_tree "ratified and cited"
write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(y) a ratified, cited intent-gap record passes"
else fail "(y) expected a silent rc=0 on a ratified gap, got $rc: $out"; fi
rm -f "$GAPREC"; commit_tree "gap cleared"
write_verdict

# ---- (ov) #613: the operator-override arm --------------------------------------------------
# The boundary reads the record with a LOCKSTEP copy of the mechanism's own parser, because a
# consumer's CI fetches this file alone and a sibling call would resolve to nothing. These cases
# drive that copy — which is why they matter beyond operator-override-selftest.sh: that suite
# proves the ORIGINAL, and a lockstep block that had drifted would still be byte-compared but
# never executed here.
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(ov1) absence of an override record is the ordinary case, and is silent"
else fail "(ov1) expected a silent pass with no override record, got $rc: $out"; fi

printf '## Override 1\ngate: spec-open-region\nscope: open-region-resolution\nissue: 42\nregion: OR-1\nrun_id: r-1\nsession_id: s-1\nexpiry: run\nrecorded_at: 2026-01-01T00:00:00Z\ndecision: append-only\n\n### Operator answer\n\n> Append-only. Ship it.\n' > "$OVREC"
commit_tree "well-formed override"
write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(ov2) a well-formed override record passes silently"
else fail "(ov2) expected a silent rc=0 on a well-formed override, got $rc: $out"; fi

# The identity binding, which is what makes the yield reconcilable at all. A record naming no run
# is a yield nobody can place.
printf '## Override 1\ngate: spec-open-region\nscope: open-region-resolution\nissue: 42\nregion: OR-1\nrun_id:\nsession_id: s-1\nexpiry: run\ndecision: append-only\n\n### Operator answer\n\n> Append-only.\n' > "$OVREC"
commit_tree "override with no run binding"
write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'run_id is empty' <<<"$out"; then
  pass "(ov3) an override record with no run binding is refused at the boundary"
else fail "(ov3) expected rc=1 naming the missing run binding, got $rc: $out"; fi

# Persistence smuggled into a per-issue record: the expiry-gated class belongs in the central
# register, where it is argued about in a diff.
printf '## Override 1\ngate: intake-unqueued\nscope: intake-attestation\nissue: 42\nregion: none\nrun_id: r-1\nsession_id: s-1\nexpiry: until-issue:9\ndecision: d\n\n### Operator answer\n\n> Yes.\n' > "$OVREC"
commit_tree "override claiming persistence"
write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'persistent override belongs in' <<<"$out"; then
  pass "(ov4) a per-issue record claiming persistence is refused and routed to the register"
else fail "(ov4) expected rc=1 naming the register, got $rc: $out"; fi

# A file at the record's path with no block in it: something wrote it, and "empty" must not read
# as "absent".
printf '# Lean override record — issue 42\n\nNothing here.\n' > "$OVREC"
commit_tree "override record with no block"
write_verdict
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'declares no' <<<"$out"; then
  pass "(ov5) a record file carrying no override block is refused, not read as absence"
else fail "(ov5) expected rc=1 on a blockless record, got $rc: $out"; fi

# ---- (ov6)-(ov9) #709 AC-4: the fidelity-ref resolution ------------------------------------
# A verdict claiming `fidelity: not-applicable (override: <ref>)` is a design-disarm YIELD
# claim, and this arm resolves it independently of whether the well-formedness sweep above
# would also flag the same record for something else — the write helper below sidesteps
# write_verdict() (which never emits a `fidelity:` key at all) to control that one value.
write_verdict_fid() { # write_verdict_fid <fidelity-value>
  local pid; pid="$(tree_patch_id)"
  printf 'verdict=approve\nrun_id: r-review-1\nsession_id: sess-review-1\nrounds: 1\nreviewed_head: %s\nreviewed_patch_id: %s\nfidelity: %s\n' \
    "$(git -C "$TREE" rev-parse HEAD)" "$pid" "$1" > "$VREC"
  printf '%s' "${VSCORECARD-$VSCORECARD_DEFAULT}" >> "$VREC"
  commit_tree "verdict with fidelity=$1"
}

# (ov6) a ref that resolves to a REAL design-disarm block for this issue passes silently.
printf '## Override 1\ngate: design-disarm\nscope: design-disarm\nissue: 42\nregion: none\nrun_id: r-1\nsession_id: s-1\nexpiry: run\ndecision: backend-only\n\n### Operator answer\n\n> Confirmed — disarm it.\n' > "$OVREC"
commit_tree "design-disarm override for #42"
write_verdict_fid "not-applicable (override: 42#1)"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(ov6) #709 AC-4: a fidelity ref resolving to a real design-disarm block passes silently"
else fail "(ov6) expected a silent rc=0, got $rc: $out"; fi

# (ov7) the SAME cited ref with NO override record committed at all — a claim the boundary
# cannot verify is exactly the tamper this arm exists to catch, whether or not any record file
# exists.
rm -f "$OVREC"; commit_tree "override cleared for ov7"
write_verdict_fid "not-applicable (override: 42#1)"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no committed override record for #42 carries a design-disarm block' <<<"$out"; then
  pass "(ov7) #709 AC-4: a fidelity ref citing an override with NO record at all is refused"
else fail "(ov7) expected rc=1 naming the unresolved ref, got $rc: $out"; fi

# (ov8) the ref resolves to a REAL, WELL-FORMED block at that file position — but for a
# DIFFERENT gate. A block existing is not the same claim as a design-disarm YIELD existing.
printf '## Override 1\ngate: spec-open-region\nscope: open-region-resolution\nissue: 42\nregion: OR-1\nrun_id: r-1\nsession_id: s-1\nexpiry: run\ndecision: append-only\n\n### Operator answer\n\n> Append-only. Ship it.\n' > "$OVREC"
commit_tree "spec-open-region override for #42, not design-disarm"
write_verdict_fid "not-applicable (override: 42#1)"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no committed override record for #42 carries a design-disarm block' <<<"$out"; then
  pass "(ov8) #709 AC-4: a ref resolving to a block for a DIFFERENT gate does not count as design-disarm evidence"
else fail "(ov8) expected rc=1 naming the unresolved ref, got $rc: $out"; fi

# (ov9) NON-VACUITY: the exact same well-formed spec-open-region record, but the verdict cites
# no override at all (a plain fidelity value) — (ov6)-(ov8) turn on the CITATION, not merely on
# a record being present. Also proves the well-formedness sweep and the ref-resolution arm are
# independent: this record is well-formed, so nothing else in arm_override() has an opinion.
write_verdict_fid "not-applicable"
out="$(ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(ov9) #709: a fidelity value citing no override ref is unaffected by this arm — (ov6)-(ov8) turn on the citation"
else fail "(ov9) expected a silent rc=0 with no ref cited, got $rc: $out"; fi

rm -f "$OVREC"; commit_tree "override cleared"
write_verdict

# ---- (z) config-derived resolution, the consumer's only path -------------------------------
# A consumer commits .claude/second-shift.config.json and sets NO prefix constant. The branch
# namespace and the tracker type come from that file, or the key derivation has nothing to
# strip and the arm the consumer installed never classifies anything.
out="$(ev_cfg "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(z1) with no env constant, the namespace comes from the committed tracker.branchPrefix"
else fail "(z1) expected config-derived classification (and so a silent run), got $rc: $out"; fi

# The branch key WINS over the body key on a prefixed branch (AC-10). This body says `Closes
# #42` while the branch says 303, and the diff carries only #42's spec: a body-first derivation
# would classify this lean on a key the lane never worked, which is the phantom-key class.
out="$(ev_cfg "claude/acme-303" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'resolved key: 303' <<<"$out"; then
  pass "(z2) a prefixed branch takes its key from the branch, never from a body naming another"
else fail "(z2) expected the branch key to win, got $rc: $out"; fi

# ENV WINS over the committed config. This repo gitignores its own config, so its CI must be
# able to hand the constant in — and a consumer that sets one must not silently get the
# committed value instead. Driven where the two DISAGREE, or the case proves nothing: with the
# env prefix in force the branch is unprefixed, so the key falls back to the body.
#
# The two outcomes are still distinguishable after #443, which is what keeps this non-vacuous:
# env winning resolves #42, classifies lean, and runs SILENT; the config winning resolves 303,
# finds no spec for it, and declines in a class-(b) line naming that key. Both are asserted.
out="$(PIPELINE_PREFIX_OVERRIDE="zzz-matches-nothing/" ev "claude/acme-303" "$WORK/markers-good.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(z3) an env namespace overrides the committed config rather than losing to it"
else fail "(z3) expected the env prefix to win (a silent lean run, not a 303 decline), got $rc: $out"; fi

# ---- (aa) AC-6: the no-bot degrade, per-arm and DISCLOSED -----------------------------------
# A consumer with no authenticated writer cannot post a marker that survives the Bot filter, so
# the arm says so rather than quietly skipping — and after #443 it says so in the pinned
# class-(b) shape, at the `reduced-strength` disposition, which is what that disposition exists
# for. Everything else on this run is class (a), so the degrade line is the ONLY line: `class_b`
# asserts the count, not merely the presence. A jira config declaring no bot is the canonical
# case: config-lint forbade the block there until #440, so "absent" means "no writer".
out="$(ev_cfg "lean/-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt" "$WORK/config-jira.json")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "identity:reduced-strength"; then
  pass "(aa1) a bot-less jira consumer degrades the identity arm, in one class-(b) line"
else fail "(aa1) expected the no-bot degrade as the sole class-(b) line, got $rc: $out"; fi

# ...and the degrade is PER-ARM. A jira consumer whose verdict record is missing still fails —
# otherwise `tracker.type: jira` would be a global waiver rather than one arm's disclosure.
mv "$VREC" "$WORK/held-verdict.md"; commit_tree "verdict removed (jira)"
out="$(ev_cfg "lean/-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt" "$WORK/config-jira.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no committed verdict record' <<<"$out"; then
  pass "(aa2) the jira degrade is per-arm: every other arm still gates"
else fail "(aa2) expected rc=1 on a jira consumer's missing verdict, got $rc: $out"; fi
mv "$WORK/held-verdict.md" "$VREC"; commit_tree "verdict restored"
write_verdict

# ---- (ab) #440: the degrade keys on the BOT, not on the tracker -----------------------------
# The whole point of the axis fix. A jira consumer that configures a bot has an authenticated
# GitHub writer, so the arm must EVALUATE — and with no marker on the PR that is a violation,
# not a waiver. Asserting rc=1 (rather than merely the absence of the degrade line) is what
# makes this case fail if the arm were re-keyed back onto the tracker.
out="$(ev_cfg "lean/-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt" "$WORK/config-jira-bot.json")"; rc=$?
if [ "$rc" -eq 1 ] \
   && ! grep -q 'identity: reduced-strength' <<<"$out" \
   && grep -q "no bot-authored" <<<"$out"; then
  pass "(ab1) a jira consumer WITH a bot is gated at full strength: a missing marker violates"
else fail "(ab1) expected an evaluated identity arm under jira+bot, got $rc: $out"; fi

# ...and it passes on a good marker trail, so (ab1) is a real arm rather than an unconditional
# red. SILENT, not merely rc=0 (#443): a gated arm that passed emits class (a), which is nothing,
# so any degrade line surviving here would be visible as bytes rather than only as a missing grep.
out="$(ev_cfg "lean/-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt" "$WORK/config-jira-bot.json")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(ab2) the same consumer passes SILENTLY on a bot-authored marker whose identity differs"
else fail "(ab2) expected a clean silent pass under jira+bot, got $rc: $out"; fi

# The mirror image: github with the bot explicitly OFF degrades. Before #440 the degrade was
# unreachable from github, so a consumer that turned its bot off was gated on evidence it could
# not produce. This is the case that proves the key is the writer and not the tracker.
out="$(ev_cfg "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt" "$WORK/config-github-nobot.json")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "identity:reduced-strength"; then
  pass "(ab3) github with tracker.bot.enabled false degrades too, in one class-(b) line"
else fail "(ab3) expected the no-bot degrade under github, got $rc: $out"; fi

# LEAN_BOT_ENABLED wins over the committed config, the same precedence LEAN_TRACKER_TYPE has —
# and it is the seam this repo's own CI needs, since it gitignores its config and reads nothing.
out="$( cd "$TREE" && LEAN_BOT_ENABLED=true PR_CREATED_AT="$PR_OPEN_AT" \
        SECOND_SHIFT_CONFIG="$WORK/config-github-nobot.json" \
        PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" \
        PR_BASE_REF="main" PR_BODY="$BODY_GOOD" \
        bash "$TOOL" all --pr-comments-file "$WORK/markers-none.json" \
                         --issue-comments-file "$WORK/claim-stamped.json" \
                         --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && ! grep -q 'identity: reduced-strength' <<<"$out"; then
  pass "(ab4) LEAN_BOT_ENABLED overrides the committed tracker.bot.enabled"
else fail "(ab4) expected the env override to force the arm on, got $rc: $out"; fi

# ---- (ac) #444: the identity arm declares when its contract took effect ---------------------
# EVERY CASE HERE RUNS ON `markers-none.json`, the trail that is a VIOLATION inside the window.
# That is what makes the cutoff cases non-vacuous: rc=0 can only mean the arm declined, never
# that it passed, so a comparator wired backwards or deleted shows up as a red rather than as a
# quieter green.
#
# THE TWO LITERALS STRADDLE THE `since:` BY ONE SECOND, which pins AC-5's value to the second
# without grepping the constant out of the source — a grep asserts a string is present, these
# two assert the comparison that string participates in. The +1s is deliberate (D-14): the arm
# anchors to a merge committed at :13, and :14 is what exempts that merge's own second instead
# of enforcing against a PR opened in it.
out="$(PR_CREATED_AT_OVERRIDE='2026-08-08T17:05:13Z' \
       ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "identity:postdated"; then
  pass "(ac1) AC-1: a PR opened one second before the arm's since: declines in one class-(b) line"
else fail "(ac1) expected a postdated decline, got $rc: $out"; fi

out="$(PR_CREATED_AT_OVERRIDE='2026-08-08T17:05:14Z' \
       ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no bot-authored' <<<"$out" \
   && ! grep -q 'identity: postdated' <<<"$out"; then
  pass "(ac2) AC-2/AC-5: a PR opened AT the since: enforces exactly as before"
else fail "(ac2) expected the arm to enforce at the boundary second, got $rc: $out"; fi

# AC-3. ABSENT is not an environment error and must never become one: a newly-required input
# reds every consumer whose committed workflow predates this change, which is the same
# strand-an-innocent-PR defect the cutoff exists to close. rc=2 here is the regression.
out="$(PR_CREATED_AT_OVERRIDE=none \
       ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "identity:postdated"; then
  pass "(ac3) AC-3: an absent PR_CREATED_AT declines rather than failing the environment"
else fail "(ac3) expected a postdated decline on an absent cutoff, got $rc: $out"; fi

# OR-1. A malformed value takes the absent path, and SAYS SO — naming the value is what lets an
# operator tell a hand-wired workflow from a missing line, since the two are otherwise one
# indistinguishable decline. The notice is on stderr, so it is not a second class-(b) line:
# `class_b` still asserts the count is exactly one.
out="$(PR_CREATED_AT_OVERRIDE='08/08/2026 17:05' \
       ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "identity:postdated" \
   && grep -qF "notice: PR_CREATED_AT ('08/08/2026 17:05')" <<<"$out"; then
  pass "(ac4) OR-1: an unparseable cutoff is treated as absent and named on stderr"
else fail "(ac4) expected a named decline on a malformed cutoff, got $rc: $out"; fi

# D-4 PRECEDENCE. Both exemptions apply to this run — pre-cutoff AND bot-less — and `postdated`
# must win. `reduced-strength` would report a permanent non-applicability as a fixable config
# gap and send the operator to configure a bot that changes nothing for this PR. Asserted as a
# specific disposition, not merely as "some class-(b) line": the ordering is the whole decision.
out="$(PR_CREATED_AT_OVERRIDE='2026-01-01T00:00:00Z' \
       ev_cfg "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt" \
              "$WORK/config-github-nobot.json")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "identity:postdated"; then
  pass "(ac5) D-4: pre-cutoff AND bot-less reports postdated, not reduced-strength"
else fail "(ac5) expected postdated to win over the no-bot degrade, got $rc: $out"; fi

# AC-8, the structural half (D-7). The comparison is a byte compare of two Z-normalized instants
# precisely so no `date` invocation is on the path: `date -d` (GNU) and `date -r` (BSD) fail
# DIRTY under the other userland, so a comparator reaching for either is green on the lane that
# has it and wrong on the lane that does not — and this suite runs on both. Host-unconditional
# on purpose: a case gated on detecting bash 3.2 would never fire on the ubuntu lane and would
# read as coverage while proving nothing.
if ! grep -nE '(^|[^[:alnum:]_-])date[[:space:]]+-[dr]([[:space:]]|$)' "$TOOL" >/dev/null; then
  pass "(ac6) AC-8: the cutoff comparison invokes neither 'date -d' nor 'date -r'"
else fail "(ac6) a GNU/BSD-split date form reached lean-evidence.sh: $(grep -nE '(^|[^[:alnum:]_-])date[[:space:]]+-[dr]([[:space:]]|$)' "$TOOL")"; fi

# ---- (ad) #445: an arm enforces only what its producer's generation ships -------------------
# EVERY CASE HERE RUNS ON `markers-none.json`, the trail that is a VIOLATION whenever the arm
# evaluates. Same discipline as (ac): rc=0 can only mean the arm declined, never that it passed,
# so a gate wired backwards or deleted shows up as a red rather than as a quieter green. And
# every case above this block runs on `claim-stamped.json` by default, so none of them silently
# became one of these declines.
#
# AC-1. THE PRE-TOKEN GENERATION — a bot-authored claim comment with no `capabilities:` key,
# exactly as the shipped producer writes one. This is the fixture that keeps the inert path
# killable after the next release makes stamped runs the norm (AC-5).
out="$(ISSUE_COMMENTS_OVERRIDE="$WORK/claim-unstamped.json" \
       ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "identity:inert"; then
  pass "(ad1) AC-1/AC-5: an unstamped claim trail sends the bound arm inert, in one class-(b) line"
else fail "(ad1) expected an inert decline on a pre-token producer, got $rc: $out"; fi

# AC-2. The same trail WITH the stamp enforces exactly as before — which is what makes (ad1) an
# assertion about the stamp rather than about the arm having been switched off.
out="$(ISSUE_COMMENTS_OVERRIDE="$WORK/claim-stamped.json" \
       ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no bot-authored' <<<"$out" \
   && ! grep -q 'identity: inert' <<<"$out"; then
  pass "(ad2) AC-2: a stamp declaring pr-marker enforces the arm exactly as before"
else fail "(ad2) expected the arm to enforce on a stamped trail, got $rc: $out"; fi

# AC-3. A generation that stamps a DIFFERENT capability declines rather than violating. The
# token is asserted in the reason, so a gate that merely tested "some stamp exists" is red here.
out="$(ISSUE_COMMENTS_OVERRIDE="$WORK/claim-othercap.json" \
       ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "identity:inert" \
   && grep -qF "capabilities: design-render" <<<"$out"; then
  pass "(ad3) AC-3: a stamp that does not declare the arm's capability is inert, not a violation"
else fail "(ad3) expected an inert decline naming the stamped set, got $rc: $out"; fi

# D-5: UNION, never intersection. One stale pre-token claim comment beside a stamped one must not
# disarm the arm for the whole issue — an issue is re-claimed on every resumed run.
out="$(ISSUE_COMMENTS_OVERRIDE="$WORK/claim-mixed.json" \
       ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no bot-authored' <<<"$out" \
   && ! grep -q 'identity: inert' <<<"$out"; then
  pass "(ad4) D-5: the stamp is the UNION across claim comments — a stale unstamped one does not disarm"
else fail "(ad4) expected the union to arm the gate, got $rc: $out"; fi

# THE TRUST FILTER REACHES THE STAMP. Anyone can comment on a public issue, so an operator-posted
# `capabilities:` line is not evidence of a harness generation — and arming an arm off one would
# hand any commenter the ability to force enforcement (or, with the token flipped, to suppress it).
out="$(ISSUE_COMMENTS_OVERRIDE="$WORK/claim-human-stamped.json" \
       ev "claude/acme-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt")"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "identity:inert"; then
  pass "(ad5) an operator-posted capability stamp does not arm the gate (the Bot trust filter)"
else fail "(ad5) expected a human stamp to be filtered out, got $rc: $out"; fi

# AC-8. NO TRAIL AT ALL is a decline, never an environment error. Making the claim fetch mandatory
# would red every consumer whose committed workflow grants no `issues: read` — the same
# strand-an-innocent-PR defect this whole mechanism exists to close. rc=2 here is the regression.
out="$( cd "$TREE" && PIPELINE_BRANCH_PREFIX="claude/acme-" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" PR_BASE_REF=main \
        PR_BODY="$BODY_GOOD" \
        bash "$TOOL" all --pr-comments-file "$WORK/markers-none.json" \
                         --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "identity:inert" \
   && grep -q 'GH_REPO is unset' <<<"$out"; then
  pass "(ad6) AC-8: an unreachable claim trail declines and says why, rather than failing the environment"
else fail "(ad6) expected a named inert decline with no trail, got $rc: $out"; fi

# AC-7, THE SCOPE BOUNDARY. Under a read-only tracker `cmd_claim` writes nothing to the tracker at
# all, so no artifact both producer generations write exists there to carry a stamp. Binding the
# arm to one would disarm the strongest merge-boundary arm permanently for that adapter. A
# jira+bot consumer therefore keeps the pre-#445 behavior — asserted on the trail that is a
# violation, so this cannot pass by declining.
out="$(ISSUE_COMMENTS_OVERRIDE="$WORK/claim-unstamped.json" \
       ev_cfg "lean/-42" "$WORK/markers-none.json" "$WORK/diff-lean.txt" "$WORK/config-jira-bot.json")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no bot-authored' <<<"$out" \
   && ! grep -q 'identity: inert' <<<"$out"; then
  pass "(ad7) AC-7: a jira consumer is not capability-bound — the arm enforces unchanged"
else fail "(ad7) expected the jira arm to enforce despite an unstamped trail, got $rc: $out"; fi

# ---- (bb) the delegation interface ---------------------------------------------------------
# `classify` is what BOTH chain gates consume instead of holding their own copy of these rules;
# the four keys are the contract, and a caller that cannot parse them guesses.
out="$( cd "$TREE" && PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" PR_BASE_REF=main \
        bash "$TOOL" classify --diff-files-file "$WORK/diff-lean.txt" 2>/dev/null )"; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -q '^applicable=1' <<<"$out" \
   && grep -q '^trigger=lean-artifact' <<<"$out" \
   && grep -q '^key=42' <<<"$out" \
   && grep -q '^spec_in_diff=docs/plans/acme-42-lean.md' <<<"$out"; then
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
if [ "$rc" -eq 0 ] && grep -q '^applicable=1' <<<"$out"; then
  pass "(bb2a) the live git diff path classifies — the fail-closed cases below are not vacuous"
else fail "(bb2a) expected the live path to classify applicable=1, got $rc: $out"; fi

out="$( cd "$TREE" && env -u PR_BASE_REF PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" \
        bash "$TOOL" classify 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] \
   && grep -q 'PR_BASE_REF is unset or empty' <<<"$out" \
   && ! grep -q '^applicable=' <<<"$out"; then
  pass "(bb2b) an unset PR_BASE_REF is an environment error, never a silent non-lean verdict"
else fail "(bb2b) expected rc=2 and no applicable= line, got $rc: $out"; fi

out="$( cd "$TREE" && PIPELINE_BRANCH_PREFIX="claude/acme-" \
        PR_HEAD_REF="claude/acme-42" PR_BODY="$BODY_GOOD" PR_BASE_REF=no-such-base \
        bash "$TOOL" classify 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] \
   && grep -q 'merge-base' <<<"$out" \
   && ! grep -q '^applicable=' <<<"$out"; then
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
   && grep -q 'counter IS the control flow' <<<"$out" \
   && ! grep -q '^set -uo pipefail' <<<"$out"; then
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
if [ "$rc" -eq 1 ] && grep -q 'no resolvable issue reference' <<<"$out"; then
  pass "(cc1) a lean PR whose body resolves no issue key is refused, not run against an empty key"
else fail "(cc1) expected rc=1 on an unresolvable issue reference, got $rc: $out"; fi

# THE LIVE FETCH PATH. Every case above hands its trails in through the fixture seams, which
# bypass `${GH:-gh}` entirely — so the lines a consumer's CI actually depends on were the only
# unexercised statements in the identity arm. A stub `gh` on PATH exercises them for real: with
# either fallback broken the fetch cannot run, and an arm that cannot run must not pass.
#
# TWO trails now, and the stub routes on the endpoint rather than serving one file to both (#445).
# Serving the marker trail to the capability read would find no claim comment, send the arm inert,
# and turn this case into a green that proves nothing about the fetch it is named for.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"/issues/$LEAN_EV_PR/comments"*) cat "$LEAN_EV_MARKERS" ;;
  *)                                cat "$LEAN_EV_CLAIMS" ;;
esac
GHSTUB
chmod +x "$WORK/bin/gh"
out="$( cd "$TREE" && PATH="$WORK/bin:$PATH" LEAN_EV_MARKERS="$WORK/markers-good.json" \
        LEAN_EV_CLAIMS="$WORK/claim-stamped.json" LEAN_EV_PR=9 \
        PIPELINE_BRANCH_PREFIX="claude/acme-" PR_CREATED_AT="$PR_OPEN_AT" \
        PR_HEAD_REF="claude/acme-42" PR_HEAD_SHA="$(git -C "$TREE" rev-parse HEAD)" PR_BASE_REF=main \
        PR_BODY="$BODY_GOOD" PR_NUMBER=9 GH_REPO="acme/acme" \
        bash "$TOOL" all --diff-files-file "$WORK/diff-lean.txt" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(cc2) the identity arm fetches BOTH its marker trail and its capability stamp through the live gh path"
else fail "(cc2) expected the live-fetch path to pass silently, got $rc: $out"; fi

# ---- (sc) #622: the per-AC scorecard, at the merge boundary --------------------------------
# THE HALF THE WRITER STRUCTURALLY CANNOT COVER. Every record below is HAND-WRITTEN — none of
# them passed `lean-gate.sh verdict` — which is the case AC-5 names: a record that answered to
# nothing at write time still answers here. That is also why these live as per-tool cases rather
# than only as a scenario: the composed leg in scenario-liveness-selftest.sh drives the WRITER,
# and a writer refusal is a different reader from this one.
#
# The fixture spec declares exactly `AC-1`, so every table below is complete or deliberately not.
sc_run() { # sc_run <verdict> <scorecard-body>
  VSCORECARD="$2" write_verdict "$1"
  ev "claude/acme-42" "$WORK/markers-good.json" "$WORK/diff-lean.txt"
}
SC_HDR='
## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
'

out="$(sc_run approve "$SC_HDR| AC-1 | satisfied | read the diff |")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(sc1) an approve scoring every declared AC-n satisfied passes the boundary silently"
else fail "(sc1) expected a silent rc=0 on a conforming scorecard, got $rc: $out"; fi

# The MIGRATION arm (D-9): fail-closed from this release, with no cutoff. Every record written
# before the section existed reads exactly like one whose section was stripped afterwards, so a
# grace window would be a fail-open on the arm this contract exists to close.
out="$(sc_run approve "")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no "## AC scorecard" section' <<<"$out"; then
  pass "(sc2) an approve carrying no scorecard at all is refused — the fail-closed migration"
else fail "(sc2) expected the missing-section refusal, got $rc: $out"; fi

out="$(sc_run approve "$SC_HDR| AC-1 | unsatisfied | the guard is not wired |")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'scored unsatisfied on a verdict=approve record' <<<"$out"; then
  pass "(sc3) an approve that scores its own criterion unsatisfied is refused — the self-contradiction"
else fail "(sc3) expected the unsatisfied/approve refusal, got $rc: $out"; fi

out="$(sc_run approve "$SC_HDR| AC-1 | undeterminable | could not run the suite |")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'scored undeterminable on a verdict=approve record' <<<"$out"; then
  pass "(sc4) an approve carrying an undeterminable row is refused — an unevaluable answer is never a pass (D-6)"
else fail "(sc4) expected the undeterminable/approve refusal, got $rc: $out"; fi

# SILENCE, not contradiction. This is the second half of D-1 and the one a record can never
# report on its own: the missing row is invisible to any reader that does not hold the spec.
out="$(sc_run approve "$SC_HDR| AC-9 | satisfied | scored something else |")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no row for AC-1, which the spec declares' <<<"$out" \
   && grep -q 'scores AC-9, which the spec does not declare' <<<"$out"; then
  pass "(sc5) both row-set directions fire: a declared AC with no row, and a row for an AC nothing declares"
else fail "(sc5) expected both row-set violations, got $rc: $out"; fi

out="$(sc_run approve "$SC_HDR| AC-1 | ok | looks fine |")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'score "ok" is not one of' <<<"$out"; then
  pass "(sc6) an unknown score value is an error, not a miss — the enum is closed"
else fail "(sc6) expected the closed-enum refusal, got $rc: $out"; fi

out="$(sc_run approve "$SC_HDR| AC-1 | satisfied | first |
| AC-1 | unsatisfied | second |")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'a second row scores an id already scored' <<<"$out"; then
  pass "(sc7) two rows scoring one criterion are refused — taking either would be the reader choosing the verdict"
else fail "(sc7) expected the duplicate-row refusal, got $rc: $out"; fi

# ---- AC-2: the severity axis, and its price ------------------------------------------------
out="$(sc_run approve "$SC_HDR| AC-1 | divergent-inert | measured: 0 of 63 corpus records affected; follow-up: #765 |")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(sc8) AC-2: an approve stands beside a well-formed divergent-inert row — a measured-inert divergence costs no round"
else fail "(sc8) expected a silent pass on a well-formed divergent-inert row, got $rc: $out"; fi

out="$(sc_run approve "$SC_HDR| AC-1 | divergent-inert | follow-up: #765 |")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'carries no "measured: <text>"' <<<"$out"; then
  pass "(sc9) AC-2: divergent-inert without a measurement is refused — the severity claim IS the measurement"
else fail "(sc9) expected the missing-measurement refusal, got $rc: $out"; fi

out="$(sc_run approve "$SC_HDR| AC-1 | divergent-inert | measured: 0 of 63 corpus records affected |")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'carries no "follow-up: <ref>"' <<<"$out"; then
  pass "(sc10) AC-2: divergent-inert without a follow-up is refused — a divergence that costs no round still needs an owner"
else fail "(sc10) expected the missing-follow-up refusal, got $rc: $out"; fi

# The follow-up must point OUTSIDE the record. `AC-1` is an id of this very schema, so accepting
# it would let a row cite itself as its own owner and satisfy the arm with nothing filed.
out="$(sc_run approve "$SC_HDR| AC-1 | divergent-inert | measured: inert; follow-up: AC-1 |")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'is not a tracker reference' <<<"$out"; then
  pass "(sc11) AC-2: a follow-up citing an id of the record's own schema is not an owner"
else fail "(sc11) expected the non-reference refusal, got $rc: $out"; fi

# ---- scope: the section is REQUIRED on approve and VALIDATED whenever present ---------------
# A needs-work record is already a refusal — nothing merges on it — so demanding the table there
# would be mass with no decision resting on it. The arm must be silent about it, and it is the
# `not approve` violation alone that fires.
out="$(sc_run needs-work "")"; rc=$?
if [ "$rc" -eq 1 ] && ! grep -q 'AC scorecard' <<<"$out" \
   && grep -q "reads 'verdict=needs-work'" <<<"$out"; then
  pass "(sc12) a needs-work record owes no scorecard — the section is required only where an approve rests on it"
else fail "(sc12) expected no scorecard violation on needs-work, got $rc: $out"; fi

# ...and present-but-malformed is still refused on a needs-work record, so a record cannot carry
# a scorecard nobody can read.
out="$(sc_run needs-work "$SC_HDR| AC-1 | ok | looks fine |")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'score "ok" is not one of' <<<"$out"; then
  pass "(sc13) a malformed scorecard is refused whether or not the verdict rests on it"
else fail "(sc13) expected the enum refusal on needs-work, got $rc: $out"; fi

# ---- the vacuity this arm would otherwise ship with (D-18) ---------------------------------
# "Declared" is a POSITION, not a mention. Milestone 1's own predicate counts every prose
# citation, and a scorecard complete over an empty declared set certifies nothing while reading
# green — so a spec that mentions criteria and declares none where this reader looks is refused
# rather than read as having none.
sc_spec_held="$(cat "$SPEC")"
printf '# lean spec\n\nThe rule in AC-1 is stated in prose, not declared.\n' > "$SPEC"
# COMMITTED before the record is written, or the freshness arm reds on the spec edit itself and
# the case reports a violation it is not about.
commit_tree "a spec that mentions AC-n without declaring one"
out="$(sc_run approve "$SC_HDR| AC-1 | satisfied | read the diff |")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'mentions AC-n but declares none where this reader looks' <<<"$out"; then
  pass "(sc14) D-18: a spec that mentions AC-n but declares none is refused, not read as an empty set"
else fail "(sc14) expected the undeclared-set refusal, got $rc: $out"; fi
printf '%s\n' "$sc_spec_held" > "$SPEC"
commit_tree "the declaring spec restored"

# ...and a spec with NO criteria at all is NOT this arm's business: check-lean-chain.sh's
# artifact arm already refuses it, and milestone 1 refuses it before that. The two empty-set
# cases are separated so neither message is sent to a reviewer the other was written for.
printf '# lean spec\n\nNo criteria here.\n' > "$SPEC"
commit_tree "a spec with no criteria at all"
out="$(sc_run approve "")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(sc15) a spec declaring no criteria at all is left to the arm that owns it — this one stays silent"
else fail "(sc15) expected silence on a criterion-less spec, got $rc: $out"; fi
printf '%s\n' "$sc_spec_held" > "$SPEC"
commit_tree "the declaring spec restored"

out="$(sc_run approve '
## AC scorecard

| AC-n | score |
| --- | --- |
| AC-1 | satisfied |')"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'header row must name exactly 3 columns' <<<"$out"; then
  pass "(sc16) a table whose header does not name the three columns in order is refused"
else fail "(sc16) expected the header refusal, got $rc: $out"; fi

# Restore the conforming record every case below this block inherits.
unset VSCORECARD
write_verdict

# ---- (scw) #760: the `scorecard` subcommand, the WRITE-TIME entry point ---------------------
# THE ENTRY POINT (sc1)-(sc16) NEVER REACH. Those drive `ac_scorecard_violations` through `all`,
# entering the file well below the `SUB = scorecard` dispatch, so until now nothing in this suite
# invoked the subcommand at all — and it is the whole reader `lean-gate.sh verdict` shells out to
# BEFORE a record exists. It has arms the boundary has not got: a schema it PRINTS so a caller's
# refusal can quote it, an rc that stays 0 on a violation because the CALLER prices it, and the
# argument refusals a caller reaches only by getting the invocation wrong.
#
# Not a scenario: scenario-liveness-selftest.sh drives `lean-gate.sh verdict`, and its assertions
# are about the GATE's refusal text — it supplies both flags correctly and never sees these arms.
#
# No fixture of its own: $SPEC already declares exactly `AC-1` and $SC_HDR is already the
# conforming table for it.

# The reader's own constants, lifted out of the tool and RENAMED rather than restated here — the
# (dd) precedent. An oracle, not a copy: the schema is printed FROM these, so a print block that
# stops naming one of them reds below, while a constant that legitimately changes moves both
# sides at once. Empty after the lift means the lift missed, which is a fail, not a pass.
SCW_HEADING=""; SCW_COLUMNS=""; SCW_SCORES=""
eval "$(sed -n 's/^AC_SCORECARD_HEADING=/SCW_HEADING=/p
                s/^AC_SCORECARD_COLUMNS=/SCW_COLUMNS=/p
                s/^AC_SCORECARD_SCORES=/SCW_SCORES=/p' "$TOOL")"

scw_run() { # scw_run <verdict> <record-body>   → the tool's own output; rc is the tool's own
  printf '%s' "$2" | bash "$TOOL" scorecard --spec "$SPEC" --verdict "$1" 2>&1
}

out="$(bash "$TOOL" scorecard --print-schema 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -n "$SCW_HEADING" ] && [ -n "$SCW_COLUMNS" ] && [ -n "$SCW_SCORES" ] \
   && grep -qF "## $SCW_HEADING" <<<"$out" \
   && grep -qF "$SCW_COLUMNS" <<<"$out" \
   && grep -qF "$SCW_SCORES" <<<"$out"; then
  pass "(scw1) --print-schema exits 0 naming the heading, the column order and the closed score enum the reader itself validates against"
else fail "(scw1) expected rc=0 and a schema quoting the tool's own constants (heading='$SCW_HEADING' columns='$SCW_COLUMNS' scores='$SCW_SCORES'), got $rc: $out"; fi

out="$(scw_run approve "$SC_HDR| AC-1 | satisfied | read the diff |")"; rc=$?
if [ "$rc" -eq 0 ] && silent "$out"; then
  pass "(scw2) a conforming body reconciles silently at write time, so the writer lets the record through"
else fail "(scw2) expected a silent rc=0 on a conforming body, got $rc: $out"; fi

# THE rc CONTRACT THAT IS NOT THE BOUNDARY'S. The same contradiction through `all` exits 1 —
# (sc3) asserts that. Here it is a violation LINE on stdout and rc STAYS 0: the writer decides
# what a violation costs, and a caller that read rc instead of the output would let every
# contradictory record through while believing it had checked.
out="$(scw_run approve "$SC_HDR| AC-1 | unsatisfied | the guard is not wired |")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'scored unsatisfied on a verdict=approve record' <<<"$out"; then
  pass "(scw3) a contradictory body prints its violation and still exits 0 — the caller prices it, this reader only names it"
else fail "(scw3) expected rc=0 with the self-contradiction named, got $rc: $out"; fi

# The dispatch's own refusals. Each is an environment error rather than a violation, because a
# caller that cannot say which spec or which verdict it is reconciling has asked no question —
# and a scorecard that answered anyway would certify against a set nobody supplied.
out="$(printf '%s' "$SC_HDR| AC-1 | satisfied | read the diff |" | bash "$TOOL" scorecard --verdict approve 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q '\-\-spec <path> is required' <<<"$out"; then
  pass "(scw4) --spec is required — the declared set comes from the committed spec, never from the record under test"
else fail "(scw4) expected the missing---spec envfail, got $rc: $out"; fi

out="$(printf '%s' "$SC_HDR| AC-1 | satisfied | read the diff |" | bash "$TOOL" scorecard --spec "$WORK/no-such-spec.md" --verdict approve 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'does not exist' <<<"$out"; then
  pass "(scw5) a --spec path that does not exist is an environment error, not an empty declared set read as nothing to score"
else fail "(scw5) expected the absent-spec envfail, got $rc: $out"; fi

out="$(printf '%s' "$SC_HDR| AC-1 | satisfied | read the diff |" | bash "$TOOL" scorecard --spec "$SPEC" --verdict merged 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "must be 'approve' or 'needs-work' (got 'merged')" <<<"$out"; then
  pass "(scw6) a --verdict outside the two-value enum is refused and quoted back — the section is required on one of them and validated on both"
else fail "(scw6) expected the verdict-enum envfail quoting the value, got $rc: $out"; fi

# ---- (dd) #443: the class-(b) emitter's own contract ---------------------------------------
# The REAL function bytes are lifted out of the tool and executed — never re-declared here. A
# hand-written copy could not fail on a production edit, which is the mirror-harness pattern this
# repo bans; this is its shell analogue of workflows/runtime-shim-lib.mjs.
emit_probe() { # emit_probe <arm> <disposition> <reason>
  # shellcheck disable=SC2317,SC2329  # invoked from the eval'd production function below.
  # BOTH codes: shellcheck >=0.10 reports SC2329 on the function, 0.9 (CI) reports SC2317 on each
  # command in the body — suppressing only the newer one is clean locally and reds CI.
  ( envfail() { echo "$1" >&2; exit 2; }
    eval "$(grep '^LEAN_OUTPUT_DISPOSITIONS=' "$TOOL")"
    eval "$(awk '/^inapplicable\(\) \{/,/^\}$/' "$TOOL")"
    inapplicable "$1" "$2" "$3" )
}

out="$(emit_probe design-evidence postdated 'a reserved disposition the successors will emit.' 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && class_b "$out" "design-evidence:postdated"; then
  pass "(dd1) AC-3: the emitter accepts every disposition in the closed set, including the reserved two"
else fail "(dd1) expected a class-(b) line for a reserved disposition, got $rc: $out"; fi

# The vocabulary is CLOSED, and closed means enforced. A gate whose dispositions can be widened by
# typing a new word at a call site has no vocabulary — the successors' readers would start seeing
# a token they have no rule for, silently.
out="$(emit_probe design-evidence probably-fine 'a word nobody agreed to.' 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'not a class-(b) disposition' <<<"$out"; then
  pass "(dd2) a disposition outside the closed set is an environment error, not a new vocabulary word"
else fail "(dd2) expected rc=2 on an unknown disposition, got $rc: $out"; fi

echo "[lean-evidence-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

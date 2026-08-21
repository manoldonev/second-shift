#!/usr/bin/env bash
# branch-prefix-selftest.sh — proves branch-prefix.sh, the one work-branch namespace resolver.
#
# Tier justification (CLAUDE.md's map): one script's behavior against fixtures => a per-tool
# behavioral selftest. The invariant is a PURE function of a repo's remote refs and its config,
# with no composed verdict path and no terminal write, so no scenario in
# scenario-liveness-selftest.sh covers it — the scenarios that DO compose against this resolver
# cover the branch NAME a run cuts, not the tie/zero-candidate resolution below.
#
# ZERO NETWORK. Every case builds a throwaway git repo and writes refs/remotes/* directly with
# `git update-ref`, which is what `git for-each-ref` reads — no remote, no fetch.
#
# Anti-vacuity: the resolver's existence is asserted up front (a distinct exit 2 if absent), and
# case (a) is a POSITIVE control — deleting branch-prefix.sh turns the suite red rather than
# letting every "should fail" case pass on a 127.
#
# bash-3.2-safe; runs in CI via the '*-selftest.sh' discovery loop.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/branch-prefix.sh"

PASSES=0
FAILS=0
pass() { PASSES=$((PASSES + 1)); echo "  PASS: $1"; }
fail() { FAILS=$((FAILS + 1)); echo "  FAIL: $1" >&2; }

if [ ! -f "$TOOL" ]; then
  echo "FATAL: $TOOL does not exist — the suite has nothing to prove. This is the anti-vacuity guard." >&2
  exit 2
fi

WORK="$(mktemp -d -t branch-prefix-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

TREE="$WORK/tree"
mkdir -p "$TREE"
cd "$TREE" || exit 2
git init -q .
git config user.name selftest
git config user.email selftest@example.invalid
git config commit.gpgsign false
git commit -q --allow-empty -m "fixture"

# refs/remotes/<remote>/<name>. The remote is deliberately NOT called `origin` in one case
# below: the resolver peels `refs/remotes/<remote>/` by ref depth, and a reader that stripped
# "the first path segment" of `git branch -r` output instead would silently keep the branch's
# own first segment as part of the prefix.
mkref() { git update-ref "refs/remotes/${2:-origin}/$1" HEAD; }
clear_refs() {
  local r
  for r in $(git for-each-ref --format='%(refname)' refs/remotes 2>/dev/null); do
    git update-ref -d "$r"
  done
}

bp() { bash "$TOOL" --repo "$TREE" "$@" 2>&1; }

echo "[branch-prefix-selftest]"

# ---- (a) the configured value always wins, with no scan ------------------------------------
# POSITIVE CONTROL. Driven with candidate branches PRESENT and disagreeing, or the case would
# pass just as well against a resolver that always scanned and happened to agree.
clear_refs
mkref "detected/9"
mkref "detected/10"
out="$(bp --configured 'set/by-config-')"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "set/by-config-" ]; then
  pass "(a) a configured tracker.branchPrefix wins outright, even where detection would disagree"
else fail "(a) expected the configured value, rc=$rc: $out"; fi

# ---- (b) AC-3: detection resolves the dominant prefix ---------------------------------------
clear_refs
mkref "claude/acme-1"
mkref "claude/acme-2"
mkref "other/9"
out="$(bp)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "claude/acme-" ]; then
  pass "(b1) the dominant <ident>/<slug-><key> prefix is detected (2 votes beat 1)"
else fail "(b1) expected claude/acme-, rc=$rc: $out"; fi

# The slug segment is OPTIONAL — `jdoe/540` is as valid a work branch as `claude/acme-540`, and
# a parse that required a slug would resolve `jdoe/` to nothing at all.
clear_refs
mkref "jdoe/540"
mkref "jdoe/541"
out="$(bp)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "jdoe/" ]; then
  pass "(b2) a bare <ident>/<key> namespace resolves too — the slug segment is optional"
else fail "(b2) expected jdoe/, rc=$rc: $out"; fi

# The remote is peeled by ref DEPTH, not by assuming it is named `origin`. A reader that
# stripped "the first path segment" of `git branch -r` output would resolve `team/` here,
# dropping the branch's own identifier along with the remote's name.
clear_refs
mkref "team/acme-3" upstream
mkref "team/acme-4" upstream
out="$(bp)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "team/acme-" ]; then
  pass "(b3) a remote not named 'origin' is peeled correctly, leaving the branch's own prefix"
else fail "(b3) expected team/acme-, rc=$rc: $out"; fi

# ---- (c) AC-3: what casts NO vote -----------------------------------------------------------
# Tool and release namespaces must not vote for a namespace no ticket ever lands in. Each of
# these is present ALONGSIDE a real candidate, so the assertion is that the real one wins by
# ITSELF rather than that the tally happens to come out right.
clear_refs
mkref "release/1.2.0"
mkref "dependabot/npm_and_yarn/left-pad-1.2.3"
mkref "fix/some-branch"
mkref "backup-77-preamend"
mkref "main"
mkref "claude/acme-5"
out="$(bp)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "claude/acme-" ]; then
  pass "(c1) release/, dependabot/, unkeyed and slashless branches cast no vote"
else fail "(c1) expected the lone real candidate to win, rc=$rc: $out"; fi

# A branch that merely CONTAINS digits is not `<prefix><key>`: the optional slug group must end
# in `-`, so `fix/v2-cleanup` cannot be read as prefix `fix/v2-cleanup` with an empty key, and
# `claude/acme-v2-thing` cannot be read as a key at all.
clear_refs
mkref "fix/v2-cleanup"
mkref "claude/acme-doctor-fixes"
out="$(bp)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'no remote branch parses' <<<"$out"; then
  pass "(c2) a branch whose tail is not a key casts no vote, even where it contains digits"
else fail "(c2) expected zero candidates, rc=$rc: $out"; fi

# ---- (d) AC-4: no dominant prefix is a REFUSAL that names what it saw ------------------------
clear_refs
out="$(bp)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'refusing to guess' <<<"$out" \
   && ! grep -qF 'claude/acme-' <<<"$out"; then
  pass "(d1) zero candidates refuses, and never emits the retired claude/acme- placeholder"
else fail "(d1) expected a refusal with no placeholder, rc=$rc: $out"; fi

# A TIE is not a winner. Picking either side would be the silent guess this file exists to
# remove, and the message must name every candidate WITH ITS COUNT — an operator's only way to
# tell "two real namespaces" from "one namespace plus noise".
clear_refs
mkref "aaa/1"
mkref "aaa/2"
mkref "bbb/3"
mkref "bbb/4"
out="$(bp)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'no single prefix dominates' <<<"$out" \
   && grep -qE '2 +aaa/' <<<"$out" && grep -qE '2 +bbb/' <<<"$out"; then
  pass "(d2) a tie at the top refuses, naming every candidate considered and its count"
else fail "(d2) expected a tie refusal naming both candidates, rc=$rc: $out"; fi

# ...and one more vote for either side breaks it. Without this the tie case alone would pass
# against a resolver that refused unconditionally whenever it had to scan.
mkref "aaa/5"
out="$(bp)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "aaa/" ]; then
  pass "(d3) breaking the tie resolves — the refusal is about dominance, not about scanning"
else fail "(d3) expected aaa/ once the tie broke, rc=$rc: $out"; fi

# ---- (e) AC-2/AC-3: the jira key shape ------------------------------------------------------
# Under jira a work branch is `<ident>/<key>` with the key LOWERCASED, while tracker.keyPattern
# is written in the tracker's own upper case. Matching case-sensitively would find no candidate
# on any real jira repo.
clear_refs
mkref "jdoe/gh-540"
mkref "jdoe/gh-541"
out="$(bash "$TOOL" --repo "$TREE" --tracker jira --key-pattern '[A-Z]+-[0-9]+' 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "jdoe/" ]; then
  pass "(e1) a jira keyPattern matches the lowercased branch key"
else fail "(e1) expected jdoe/, rc=$rc: $out"; fi

# The pattern is the CONSUMER's, not a constant: a repo whose keys are numeric-only under jira
# must not have this repo's default imposed on it.
out="$(bash "$TOOL" --repo "$TREE" --tracker jira --key-pattern 'ZZZ-[0-9]+' 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
  pass "(e2) the configured keyPattern is what decides a jira candidate, not a hardcoded shape"
else fail "(e2) expected a non-matching pattern to find nothing, rc=$rc: $out"; fi

# ...and the BUILT-IN default is reachable, so it needs its own case. `tracker.keyPattern` is
# optional in the schema and config-lint does not require it, so a jira consumer can omit it —
# and then this default is the only thing deciding what counts as a work branch. Without this
# case, corrupting it is invisible: every other jira case here supplies a pattern explicitly.
out="$(bash "$TOOL" --repo "$TREE" --tracker jira 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "jdoe/" ]; then
  pass "(e2b) with no keyPattern configured, the built-in jira key shape still detects candidates"
else fail "(e2b) expected the built-in default to resolve jdoe/, rc=$rc: $out"; fi

# ...and the two trackers SPLIT the same refs differently, or the --tracker argument would be
# decorative. Under github the key is the trailing digit run, so `jdoe/gh-540` reads as prefix
# `jdoe/gh-`; under jira the whole `gh-540` is the key and the prefix is `jdoe/`. Only one of
# those is the namespace a jira run cuts branches in.
out="$(bp)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "jdoe/gh-" ]; then
  pass "(e3) github and jira split the same refs differently — the tracker argument is load-bearing"
else fail "(e3) expected the github split jdoe/gh-, rc=$rc: $out"; fi

# The github parse still refuses a key shape that is not digits at all, which is what stops a
# jira-only namespace from voting in a github repo.
clear_refs
mkref "jdoe/gh-540a"
mkref "jdoe/gh-541b"
out="$(bp)"; rc=$?
if [ "$rc" -eq 2 ]; then
  pass "(e4) under github a non-numeric key casts no vote"
else fail "(e4) expected github to reject a non-numeric key, rc=$rc: $out"; fi

# ---- (f) sourcing defines the function and runs nothing --------------------------------------
# Both lanes SOURCE this file. A stray side effect at source time would run on every gate call.
clear_refs
mkref "claude/acme-6"
# shellcheck source=branch-prefix.sh
out="$( . "$TOOL" && resolve_branch_prefix "" github "" "$TREE" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "claude/acme-" ]; then
  pass "(f1) sourcing exposes resolve_branch_prefix() and emits nothing of its own"
else fail "(f1) sourced call did not behave, rc=$rc: $out"; fi

# shellcheck source=branch-prefix.sh
out="$( . "$TOOL" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "(f2) sourcing alone prints nothing and exits 0 — no CLI runs on the source path"
else fail "(f2) sourcing produced output or a non-zero status, rc=$rc: $out"; fi

# ---- (h) the INVERSE question: does a branch belong to an already-resolved namespace? (#442) --
# lean-gate.sh's worktree sweep asks this of every registered worktree before it will look a
# branch up on the tracker, so a wrong answer here IS the sweep's blast radius. The cases that
# matter are the ones a `case "$ref" in "$prefix"*)` string test gets wrong — that is the obvious
# implementation, and it accepts branches that are not work branches at all.
isw() { # isw <ref> <prefix> [<tracker>] [<key-pattern>]
  # shellcheck source=branch-prefix.sh
  ( . "$TOOL" && bp_is_work_branch "$1" "$2" "${3:-github}" "${4:-}" )
}

if isw "claude/acme-7" "claude/acme-" && isw "jdoe/12" "jdoe/"; then
  pass "(h1) a github work branch is recognized under both the slugged and the bare namespace"
else fail "(h1) a real work branch was not recognized"; fi

if ! isw "claude/acme-notes" "claude/acme-" && ! isw "claude/other-7" "claude/acme-"; then
  pass "(h2) a non-key tail and a foreign slug are both rejected — not a prefix string match"
else fail "(h2) bp_is_work_branch accepted a branch that is not this namespace's work branch"; fi

if ! isw "dependabot/npm_and_yarn/acme-7" "dependabot/" && ! isw "main" "claude/acme-"; then
  pass "(h3) a multi-segment tool namespace and a slashless branch are rejected"
else fail "(h3) bp_is_work_branch accepted a tool namespace or a slashless ref"; fi

# The tracker argument decides the key shape here exactly as it does for the vote scan.
if isw "claude/acme-12" "claude/" jira 'ACME-[0-9]+' \
   && ! isw "claude/acme-12" "claude/" github; then
  pass "(h4) the same ref parses under jira's keyPattern and not under github's numeric key"
else fail "(h4) the tracker/key-pattern arguments are not load-bearing here"; fi

# bp_key_re is the ONE definition both directions read; a caller inlining its own copy is how
# the membership answer drifts from the one that chose the namespace in the first place.
# shellcheck source=branch-prefix.sh
out="$( . "$TOOL" && printf '%s|%s|%s' "$(bp_key_re github '')" "$(bp_key_re jira '')" "$(bp_key_re jira 'X-[0-9]+')" )"
if [ "$out" = '[0-9]+|[A-Za-z]+-[0-9]+|X-[0-9]+' ]; then
  pass "(h5) bp_key_re yields the github numeric key, jira's built-in shape, and a configured override"
else fail "(h5) unexpected key patterns: $out"; fi

# ---- (i) bp_branch_key: the extraction half of the same parse (#611) --------------------------
# lean-gate.sh derives THIS RUN's ticket from the cwd's branch and refuses when it disagrees with
# the argument, so a wrong answer here is a refusal on an honest run or a silent pass on a
# mismatched one. The cases that matter are the ones a bare `${ref#$prefix}` gets wrong: it is
# the obvious implementation, and it happily reports a key for a branch that is not a work branch
# at all — which is exactly the input this function has to reject rather than parse.
key() { # key <ref> <prefix> [<tracker>] [<key-pattern>]
  # shellcheck source=branch-prefix.sh
  ( . "$TOOL" && bp_branch_key "$1" "$2" "${3:-github}" "${4:-}" )
}

out="$(key "claude/acme-7" "claude/acme-")|$(key "jdoe/12" "jdoe/")"
if [ "$out" = "7|12" ]; then
  pass "(i1) the key is the trailing run under both the slugged and the bare namespace"
else fail "(i1) expected 7|12, got: $out"; fi

if ! key "claude/acme-notes" "claude/acme-" >/dev/null 2>&1    && ! key "claude/other-7" "claude/acme-" >/dev/null 2>&1    && ! key "main" "claude/acme-" >/dev/null 2>&1; then
  pass "(i2) a non-key tail, a foreign slug and a slashless ref yield NO key — not a prefix strip"
else fail "(i2) bp_branch_key returned a key for a ref that is not this namespace's work branch"; fi

out="$(key "claude/acme-12" "claude/" jira 'ACME-[0-9]+')"
if [ "$out" = "acme-12" ]; then
  pass "(i3) under jira the key comes back as the BRANCH spells it — lowercased, the transform the branch already applied"
else fail "(i3) expected the lowercased jira key, got: $out"; fi

# The membership answer and the extraction answer are one decision, so they cannot disagree: any
# ref bp_is_work_branch accepts yields a key, and every ref it rejects yields none.
if isw "claude/acme-7" "claude/acme-" && key "claude/acme-7" "claude/acme-" >/dev/null 2>&1    && ! isw "claude/acme-notes" "claude/acme-" && ! key "claude/acme-notes" "claude/acme-" >/dev/null 2>&1; then
  pass "(i4) bp_branch_key agrees with bp_is_work_branch in both directions — one parse, two questions"
else fail "(i4) the membership and extraction answers disagree"; fi

# ---- (g) --help stops at the header ----------------------------------------------------------
# `sed -n '2,Np'` is a hand-maintained line number and this repo has been burned by a header
# that outgrew it. Bounded on BOTH ends, and the lower bound is the header's genuinely LAST
# line (the bash-3.2 note), not the last one a reader notices: anchoring on `Exit / return:`
# two lines above it would still pass a range that fell short by two, which is the same defect
# one notch smaller. `set -uo pipefail` is the first line past the range, so its presence means
# the whole file leaked.
out="$(bash "$TOOL" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'Exit / return:' <<<"$out" \
   && grep -qF '3.2-compatible' <<<"$out" \
   && ! grep -qF 'set -uo pipefail' <<<"$out"; then
  pass "(g) --help prints through the last header line and stops before the code"
else fail "(g) --help did not print exactly the header, rc=$rc: $out"; fi

echo "[branch-prefix-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"

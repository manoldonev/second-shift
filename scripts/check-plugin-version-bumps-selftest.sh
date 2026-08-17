#!/usr/bin/env bash
#
# check-plugin-version-bumps-selftest.sh — behavioral coverage for the release-PR
# version-bump gate (scripts/check-plugin-version-bumps.sh).
#
# INVARIANT GUARDED: a plugin whose CONTENT changed since the base tag but whose
# .claude-plugin/plugin.json version did NOT must fail the gate (exit 1). That is
# the last defense against an "invisible release" — `claude plugin update` is keyed
# on the manifest version, so an unbumped plugin is silently a no-op for every
# consumer. The gate runs on exactly one PR (the release PR) and had no test at all.
#
# WHY NO SCENARIO COVERS IT (CLAUDE.md scenario-first rule): scenario-liveness-
# selftest.sh composes dev-pipeline verdict paths — milestone progressions reaching
# a terminal write. This gate is not on any pipeline path. It runs in the
# marketplace CI release-pr-gates job, over git history, after the pipeline is done.
# There is no verdict path to compose it onto.
#
# SCOPE (issue #215 decision D-1): this suite does NOT change the gate. Several of
# its error branches degrade to PASS by design; each is pinned here as CHARACTERIZED
# behavior with the masked risk named, so a future refactor that alters the
# degradation turns a case red and gets a deliberate look. "Red case" here means
# "capable of going red on a regression", per this repo's testing vocabulary.
#
# The suite is mutation-checked against its own core: case (m) copies the gate,
# rewrites its `exit 1` to `exit 0`, and asserts the fail case then goes red — so a
# fail-open gate cannot pass this suite.
#
# Fixture idiom follows scripts/derive-release-selftest.sh: a throwaway `git init`
# repo under mktemp with real tags. No network, no gh. bash-3.2-safe. Runs in CI via
# the '*-selftest.sh' discovery loop.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${VERSION_BUMP_GATE:-$HERE/check-plugin-version-bumps.sh}"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

[[ -f "$GATE" ]] || { echo "check-plugin-version-bumps-selftest: FAIL — gate not found at $GATE" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "check-plugin-version-bumps-selftest: FAIL — jq required" >&2; exit 1; }

WORK="$(mktemp -d -t version-bump-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# The gate cd's to the git toplevel itself, so it must be invoked from inside the
# fixture repo. Captures stdout+stderr together; echoes "rc=<n>" as the last line.
run_gate() { # run_gate <repo> [base-ref] [gate-override]
  local repo="$1" base="${2:-}" g="${3:-$GATE}" out rc
  # Quoted: the gate reads BASE="${1:-}", so an empty arg and no arg are the same
  # code path (both fall through to tag discovery).
  out="$(cd "$repo" && bash "$g" "$base" 2>&1)"; rc=$?
  printf '%s\nrc=%s\n' "$out" "$rc"
}
rc_of()  { printf '%s' "$1" | sed -n 's/^rc=//p' | tail -1; }

mkplugin() { # mkplugin <repo> <name> <version>
  mkdir -p "$1/plugins/$2/.claude-plugin"
  printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$2" "$3" \
    > "$1/plugins/$2/.claude-plugin/plugin.json"
}

# A fixture repo tagged v1.0.0 with two plugins, both with real content files.
newrepo() { # newrepo <name> -> echoes the path
  local repo="$WORK/$1"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 2
    git init -q
    git config user.name selftest
    git config user.email selftest@example.invalid
    git config commit.gpgsign false
  ) >/dev/null 2>&1
  mkplugin "$repo" alpha 1.2.0
  mkplugin "$repo" beta 2.0.1
  printf 'alpha v1\n' > "$repo/plugins/alpha/README.md"
  printf 'beta v1\n'  > "$repo/plugins/beta/README.md"
  (cd "$repo" && git add -A && git commit -qm "release: v1.0.0" && git tag v1.0.0) >/dev/null 2>&1
  printf '%s' "$repo"
}

commit_in() { (cd "$1" && git add -A && git commit -qm "$2") >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# (v1) THE FAIL DIRECTION — content changed, version did not => exit 1.
# This is the branch the whole gate exists for.
# ---------------------------------------------------------------------------
R="$(newrepo v1)"
printf 'alpha v2 — content changed\n' > "$R/plugins/alpha/README.md"
commit_in "$R" "fix(alpha): change content without bumping"
out="$(run_gate "$R")"
if [[ "$(rc_of "$out")" == "1" && "$out" == *"content changed"* && "$out" == *"alpha"* ]]; then
  ok "(v1) changed content + unchanged version → exit 1, names the plugin"
else
  bad "(v1) expected rc=1 naming alpha, got: $out"
fi

# ---------------------------------------------------------------------------
# (v2) THE PASS DIRECTION — content changed WITH a bump => exit 0.
# Guards against a gate that fails everything (which would also "pass" v1).
# ---------------------------------------------------------------------------
R="$(newrepo v2)"
printf 'alpha v2\n' > "$R/plugins/alpha/README.md"
mkplugin "$R" alpha 1.3.0
commit_in "$R" "fix(alpha): change content and bump"
out="$(run_gate "$R")"
if [[ "$(rc_of "$out")" == "0" && "$out" == *"1.2.0 → 1.3.0"* ]]; then
  ok "(v2) changed content + bumped version → exit 0, reports the transition"
else
  bad "(v2) expected rc=0 with 1.2.0 → 1.3.0, got: $out"
fi

# ---------------------------------------------------------------------------
# (v3) untouched plugin => exit 0, no bump demanded.
# ---------------------------------------------------------------------------
R="$(newrepo v3)"
printf 'root note\n' > "$R/NOTES.md"
commit_in "$R" "docs: root-only change"
out="$(run_gate "$R")"
if [[ "$(rc_of "$out")" == "0" && "$out" != *"content changed"* ]]; then
  ok "(v3) no plugin content change → exit 0, no bump demanded"
else
  bad "(v3) expected a clean rc=0, got: $out"
fi

# ---------------------------------------------------------------------------
# (v4) only ONE of two changed plugins is unbumped => still exit 1.
# A per-plugin loop that broke out early would pass this by accident.
# ---------------------------------------------------------------------------
R="$(newrepo v4)"
printf 'alpha v2\n' > "$R/plugins/alpha/README.md"
mkplugin "$R" alpha 1.3.0          # bumped
printf 'beta v2\n' > "$R/plugins/beta/README.md"   # changed, NOT bumped
commit_in "$R" "chore: one bumped, one not"
out="$(run_gate "$R")"
if [[ "$(rc_of "$out")" == "1" && "$out" == *"beta"* && "$out" == *"1 plugin(s) changed without"* ]]; then
  ok "(v4) mixed batch → exit 1, counts only the unbumped plugin"
else
  bad "(v4) expected rc=1 naming beta with a count of 1, got: $out"
fi

# ---------------------------------------------------------------------------
# (v5) explicit base-ref argument is honored over tag discovery.
# ---------------------------------------------------------------------------
R="$(newrepo v5)"
printf 'alpha v2\n' > "$R/plugins/alpha/README.md"
commit_in "$R" "fix(alpha): unbumped change"
(cd "$R" && git tag v2.0.0) >/dev/null 2>&1   # a later tag that would hide the change
out="$(run_gate "$R" "v1.0.0")"
if [[ "$(rc_of "$out")" == "1" && "$out" == *"against v1.0.0"* ]]; then
  ok "(v5) explicit base-ref honored — compares against the given tag, not the latest"
else
  bad "(v5) expected rc=1 comparing against v1.0.0, got: $out"
fi

# ---------------------------------------------------------------------------
# CHARACTERIZED DEGRADATIONS (#215 D-1: pinned, not blessed).
# Each of these PASSES today while masking a real condition. The assertions lock
# the current behavior so a change to it is visible in the diff, and each names
# what stays masked.
# ---------------------------------------------------------------------------

# (c1) No tag anywhere => "first release", PASS — even though alpha changed.
# Masked risk: a repo whose tags were never fetched (a shallow CI checkout without
# fetch-depth: 0) takes this path and the gate silently checks nothing.
R="$WORK/c1"; mkdir -p "$R"
(
  cd "$R" || exit 2
  git init -q; git config user.name selftest; git config user.email selftest@example.invalid
  git config commit.gpgsign false
) >/dev/null 2>&1
mkplugin "$R" alpha 1.2.0
printf 'alpha\n' > "$R/plugins/alpha/README.md"
commit_in "$R" "initial"
printf 'alpha changed\n' > "$R/plugins/alpha/README.md"
commit_in "$R" "fix(alpha): unbumped change with no tags in the repo"
out="$(run_gate "$R")"
if [[ "$(rc_of "$out")" == "0" && "$out" == *"no prior release tag"* ]]; then
  ok "(c1) no tag → PASS as 'first release' (characterized: an untagged/shallow checkout checks nothing)"
else
  bad "(c1) expected rc=0 with the first-release message, got: $out"
fi

# (c2) Plugin absent at BASE => empty old_ver => "new plugin", PASS. Correct here.
R="$(newrepo c2)"
mkplugin "$R" gamma 0.1.0
printf 'gamma\n' > "$R/plugins/gamma/README.md"
commit_in "$R" "feat(gamma): genuinely new plugin"
out="$(run_gate "$R")"
if [[ "$(rc_of "$out")" == "0" && "$out" == *"gamma: new plugin since"* ]]; then
  ok "(c2) plugin absent at BASE → PASS as 'new plugin' (correct)"
else
  bad "(c2) expected rc=0 with the new-plugin message, got: $out"
fi

# (c3) Manifest present at BASE but UNREADABLE => same empty old_ver path => PASS.
# Masked risk: this is (c2)'s message for a plugin that is NOT new. A malformed
# manifest at the base tag makes an unbumped content change indistinguishable from
# a brand-new plugin, and the gate waves it through.
R="$WORK/c3"; mkdir -p "$R"
(
  cd "$R" || exit 2
  git init -q; git config user.name selftest; git config user.email selftest@example.invalid
  git config commit.gpgsign false
) >/dev/null 2>&1
mkdir -p "$R/plugins/delta/.claude-plugin"
printf 'this is not json\n' > "$R/plugins/delta/.claude-plugin/plugin.json"
printf 'delta\n' > "$R/plugins/delta/README.md"
commit_in "$R" "release: v1.0.0"
(cd "$R" && git tag v1.0.0) >/dev/null 2>&1
mkplugin "$R" delta 1.0.0                      # now valid, same version
printf 'delta changed\n' > "$R/plugins/delta/README.md"
commit_in "$R" "fix(delta): unbumped change over an unreadable base manifest"
out="$(run_gate "$R")"
if [[ "$(rc_of "$out")" == "0" && "$out" == *"delta: new plugin since"* ]]; then
  ok "(c3) unreadable manifest at BASE → PASS as 'new plugin' (characterized: masks a real unbumped change)"
else
  bad "(c3) expected rc=0 with the new-plugin message, got: $out"
fi

# (c4) Empty new_ver against a non-empty old_ver => inequality => PASS with a ✓.
# Masked risk (surfaced by plan review): a plugin that DROPS its version field
# entirely reads as "bumped" because "" != "1.2.0", so the manifest that makes the
# plugin uninstallable sails through the gate that exists to protect installs.
R="$(newrepo c4)"
printf '{\n  "name": "alpha"\n}\n' > "$R/plugins/alpha/.claude-plugin/plugin.json"
printf 'alpha changed\n' > "$R/plugins/alpha/README.md"
commit_in "$R" "chore(alpha): drop the version field"
out="$(run_gate "$R")"
if [[ "$(rc_of "$out")" == "0" && "$out" == *"1.2.0 → "* ]]; then
  ok "(c4) version field removed → PASS as a bump (characterized: empty new_ver never equals old_ver)"
else
  bad "(c4) expected rc=0 reporting a transition to empty, got: $out"
fi

# ---------------------------------------------------------------------------
# (m) MUTATION CHECK — a fail-open gate must not survive this suite.
# Rewrites the gate's `exit 1` to `exit 0` and re-runs (v1). If (v1) still passes
# against the mutant, this suite has no failing power and the whole file is theater.
# ---------------------------------------------------------------------------
MUTANT="$WORK/mutant-gate.sh"
sed 's/^  exit 1$/  exit 0/' "$GATE" > "$MUTANT"
if ! grep -q '^  exit 0$' "$MUTANT"; then
  bad "(m) mutation setup — could not rewrite the gate's exit 1; the anchor moved"
else
  R="$(newrepo m)"
  printf 'alpha v2\n' > "$R/plugins/alpha/README.md"
  commit_in "$R" "fix(alpha): change content without bumping"
  out="$(run_gate "$R" "" "$MUTANT")"
  if [[ "$(rc_of "$out")" == "0" ]]; then
    ok "(m) fail-open mutant (exit 1 → exit 0) is caught — (v1) would go red against it"
  else
    bad "(m) mutant did not change the outcome; (v1) has no failing power. got: $out"
  fi
fi

echo "[check-plugin-version-bumps-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0

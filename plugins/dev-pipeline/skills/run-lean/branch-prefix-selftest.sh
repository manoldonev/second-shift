#!/usr/bin/env bash
# branch-prefix-selftest.sh — proves plugins/dev-pipeline/skills/run-lean/branch-prefix.sh (#413).
#
# Drives the real resolver against synthetic configs and a `--branches-file` fixture standing in
# for `git branch -r --sort=-committerdate`. ZERO NETWORK, zero remotes.
#
# Tier justification (CLAUDE.md's map): one script's behavior against fixtures => a per-tool
# behavioral selftest. No scenario in scenario-liveness-selftest.sh covers this: the resolver is
# reached at lean-gate.sh's INIT, before any milestone verdict path exists to compose against,
# and its two interesting arms (detection, refusal) are unreachable from a fixture repo whose
# config always sets tracker.branchPrefix. The scenario suite pins the composed consequence —
# that a resolved prefix reaches the progress header and milestone 5's PR lookup — not this.
#
# Anti-vacuity: the script's existence is asserted up front (exit 2 with a distinct message if
# absent), so deleting branch-prefix.sh turns the suite red rather than letting every
# "should fail" case pass on a 127.
#
# bash-3.2-safe; runs in CI via the '*-selftest.sh' discovery loop.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/branch-prefix.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

if [ ! -f "$TOOL" ]; then
  echo "FATAL: $TOOL does not exist — the suite has nothing to prove. This is the anti-vacuity guard." >&2
  exit 2
fi

WORK="$(mktemp -d -t branch-prefix-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[branch-prefix-selftest]"

mkcfg() { # mkcfg <name> <jq-object>
  jq -n "$2" > "$WORK/$1.json"
  printf '%s' "$WORK/$1.json"
}

run() { # run <config-path> [extra args...]
  local c="$1"; shift
  bash "$TOOL" --config "$c" "$@" 2>&1
}

# ---- fixtures ----------------------------------------------------------------------------
# The shape `git branch -r --sort=-committerdate` prints: two leading spaces, remote-qualified,
# with origin/HEAD as a symbolic ref line.
cat > "$WORK/branches-dominant.txt" <<'EOF'
  origin/HEAD -> origin/main
  origin/main
  origin/jdoe/512
  origin/jdoe/498
  origin/release/next
  origin/dependabot/npm_and_yarn/lodash-4.17.21
  origin/asmith/377
EOF

cat > "$WORK/branches-none.txt" <<'EOF'
  origin/HEAD -> origin/main
  origin/main
  origin/release/next
  origin/claude/second-shift-413
EOF

cat > "$WORK/branches-tied.txt" <<'EOF'
  origin/main
  origin/jdoe/512
  origin/asmith/377
EOF

cat > "$WORK/branches-jira.txt" <<'EOF'
  origin/main
  origin/jdoe/gh-540
  origin/jdoe/gh-511
  origin/asmith/gh-402
EOF

CFG_SET="$(mkcfg set '{tracker: {type: "github", branchPrefix: "claude/second-shift-"}}')"
CFG_UNSET="$(mkcfg unset '{tracker: {type: "github"}}')"
CFG_JIRA="$(mkcfg jira '{tracker: {type: "jira", keyPattern: "[A-Z]+-[0-9]+"}}')"
CFG_JIRA_NOPAT="$(mkcfg jiranopat '{tracker: {type: "jira"}}')"
CFG_BADTYPE="$(mkcfg badtype '{tracker: {type: "gitlab"}}')"

# ---- (a) AC-1: a configured prefix is returned verbatim, with no re-rooting ---------------
# The whole defect this replaces was a transform applied ON TOP of the configured value.
out="$(run "$CFG_SET" --branches-file "$WORK/branches-dominant.txt")"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "claude/second-shift-" ]; then
  pass "(a) a configured tracker.branchPrefix is returned verbatim"
else fail "(a) expected rc=0 and 'claude/second-shift-', got rc=$rc '$out'"; fi

# ---- (a2) AC-1: no `lean/` segment is ever introduced -------------------------------------
# The negative half of (a): a pass that only asserted the happy string would still pass if the
# resolver appended or prepended a namespace to some OTHER configured value.
out="$(run "$CFG_SET" --branches-file "$WORK/branches-dominant.txt")"
if printf '%s' "$out" | grep -q '^lean/'; then
  fail "(a2) the resolver introduced a lean/ namespace: '$out'"
else pass "(a2) no lean/ namespace is introduced on the configured path"; fi

# ---- (b) AC-3: detection resolves the dominant identifier ---------------------------------
# jdoe votes twice (512, 498), asmith once. release/ and dependabot/ cast no vote at all:
# their suffixes are not key-shaped. origin/HEAD's symbolic line is skipped.
out="$(run "$CFG_UNSET" --branches-file "$WORK/branches-dominant.txt")"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "jdoe/" ]; then
  pass "(b) detection resolves the dominant <ident>/ (jdoe/ over asmith/)"
else fail "(b) expected rc=0 and 'jdoe/', got rc=$rc '$out'"; fi

# ---- (b2) AC-3: the placeholder default is GONE, not merely outvoted ----------------------
# Defect 2 was `claude/acme-` shipping into real branch names. It must not appear on ANY path,
# which is only provable on the paths where the old code would have emitted it: unset config.
out="$(run "$CFG_UNSET" --branches-file "$WORK/branches-none.txt")"
out2="$(run "$CFG_UNSET" --branches-file "$WORK/branches-tied.txt")"
if printf '%s%s' "$out" "$out2" | grep -q 'claude/acme-'; then
  fail "(b2) the placeholder default 'claude/acme-' still reaches output"
else pass "(b2) 'claude/acme-' appears on no resolution path, successful or failed"; fi

# ---- (c) AC-4: zero candidates is a refusal that names what it scanned --------------------
# `claude/second-shift-413` is in this fixture ON PURPOSE: it is a two-segment prefix shape
# detection cannot decompose, so it must cast no vote rather than resolve to `claude/`.
out="$(run "$CFG_UNSET" --branches-file "$WORK/branches-none.txt")"; rc=$?
if [ "$rc" -eq 2 ] \
   && printf '%s' "$out" | grep -q 'cannot resolve a branch prefix' \
   && printf '%s' "$out" | grep -q 'Considered:' \
   && printf '%s' "$out" | grep -q 'origin/claude/second-shift-413'; then
  pass "(c) zero candidates refuses with rc=2 and names the branches it considered"
else fail "(c) expected rc=2 naming the scanned branches, got rc=$rc: $out"; fi

# ---- (c2) `origin/HEAD -> origin/main` is a symbolic ref, not a branch ---------------------
# It appears in every real `git branch -r` listing. Naming it among the candidates considered
# would be a false lead in the one message an operator reads when detection has failed — and
# (c) cannot see the difference, since it only asserts what IS present.
if printf '%s' "$out" | grep -q ' -> '; then
  fail "(c2) the refusal names the origin/HEAD symbolic ref among its candidates: $out"
else pass "(c2) the symbolic origin/HEAD ref is excluded from the candidates considered"; fi

# ---- (d) AC-4: a tie is a refusal that names the tied candidates --------------------------
out="$(run "$CFG_UNSET" --branches-file "$WORK/branches-tied.txt")"; rc=$?
if [ "$rc" -eq 2 ] \
   && printf '%s' "$out" | grep -q 'tie' \
   && printf '%s' "$out" | grep -q 'jdoe/' \
   && printf '%s' "$out" | grep -q 'asmith/'; then
  pass "(d) a tie refuses with rc=2 and names both tied identifiers"
else fail "(d) expected rc=2 naming both tied identifiers, got rc=$rc: $out"; fi

# ---- (e) AC-2/AC-3: the jira arm counts keyPattern-shaped suffixes ------------------------
# The branch key is LOWERCASED (tools/tracker/jira/README.md) while keyPattern is written in
# uppercase, so the match must be case-insensitive or every jira repo fails detection.
out="$(run "$CFG_JIRA" --branches-file "$WORK/branches-jira.txt")"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "jdoe/" ]; then
  pass "(e) the jira arm counts tracker.keyPattern suffixes case-insensitively"
else fail "(e) expected rc=0 and 'jdoe/', got rc=$rc '$out'"; fi

# ---- (e2) the jira arm with keyPattern ABSENT falls back to the conventional shape --------
# The schema lets keyPattern be absent to mean "any non-empty key" at statectl's validation
# site. As a DETECTION filter "anything" would make release/next vote, so the fallback is the
# JIRA shape rather than the schema's permissive reading.
out="$(run "$CFG_JIRA_NOPAT" --branches-file "$WORK/branches-jira.txt")"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "jdoe/" ]; then
  pass "(e2) an absent keyPattern falls back to the conventional JIRA key shape"
else fail "(e2) expected rc=0 and 'jdoe/', got rc=$rc '$out'"; fi

# ---- (e3) the github arm does NOT accept a jira-shaped key --------------------------------
# The negative that makes (e) mean something: if both arms accepted everything, (e) would pass
# with the tracker.type branch deleted.
out="$(run "$CFG_UNSET" --branches-file "$WORK/branches-jira.txt")"; rc=$?
if [ "$rc" -eq 2 ]; then
  pass "(e3) under github, jira-shaped suffixes cast no vote (rc=2, no accidental resolution)"
else fail "(e3) expected rc=2 under github against jira-shaped branches, got rc=$rc '$out'"; fi

# ---- (f) an unrecognized tracker.type is a loud error, not a fall-through -----------------
out="$(run "$CFG_BADTYPE" --branches-file "$WORK/branches-dominant.txt")"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "unknown tracker.type"; then
  pass "(f) an unknown tracker.type is rejected rather than defaulted"
else fail "(f) expected rc=2 on an unknown tracker.type, got rc=$rc: $out"; fi

# ---- (g) a missing --branches-file is an error, not an empty scan -------------------------
# Otherwise a typo'd seam path would read as "no candidates" and produce (c)'s message for a
# reason that has nothing to do with the repo's branches.
out="$(run "$CFG_UNSET" --branches-file "$WORK/does-not-exist.txt")"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'does not exist'; then
  pass "(g) a missing --branches-file is a distinct error, not a silent empty scan"
else fail "(g) expected rc=2 on a missing branches file, got rc=$rc: $out"; fi

# ---- (h) an unknown argument is rejected --------------------------------------------------
out="$(bash "$TOOL" --nope 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'unknown argument'; then
  pass "(h) an unknown argument is rejected"
else fail "(h) expected rc=2 on an unknown argument, got rc=$rc: $out"; fi

# ---- config location: the three ways this script finds a config ---------------------------
# All three are documented seams and all three are consumed in production — lean-gate.sh and
# retro-corpus.sh both pass --config AND --repo-root, and an operator invoking the script by
# hand gets neither. A fixture repo that actually CARRIES a config is what makes the
# no-argument path assertable: without one, "found the config" and "failed to find it and fell
# through to detection" reach the same answer, and every guard on that path is untestable.
FIXREPO="$WORK/fixrepo"
mkdir -p "$FIXREPO/.claude"
git -C "$FIXREPO" init -q
jq -n '{tracker: {type: "github", branchPrefix: "fixture/repo-"}}' > "$FIXREPO/.claude/second-shift.config.json"

# ---- (i) --repo-root locates the config, with no --config given ---------------------------
out="$(bash "$TOOL" --repo-root "$FIXREPO" --branches-file "$WORK/branches-dominant.txt" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "fixture/repo-" ]; then
  pass "(i) --repo-root resolves the config at <root>/.claude/second-shift.config.json"
else fail "(i) expected rc=0 and 'fixture/repo-', got rc=$rc '$out'"; fi

# ---- (j) with NO arguments the root comes from git, and the config is found there ---------
# Run FROM INSIDE the fixture repo. The dominant-identifier fixture is not available here (no
# --branches-file), but it is not needed: the configured prefix must win before detection is
# ever reached, and this repo has no remotes at all, so a resolver that missed the config would
# refuse rather than answer.
out="$( cd "$FIXREPO" && bash "$TOOL" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "fixture/repo-" ]; then
  pass "(j) with no arguments the repo root is resolved from git and the config found under it"
else fail "(j) expected rc=0 and 'fixture/repo-', got rc=$rc '$out'"; fi

# ---- (k) SECOND_SHIFT_CONFIG is honored when --config is absent ---------------------------
# The env seam every other tool in this plugin reads. Driven from a directory where the
# git-derived fallback would find a DIFFERENT answer, so the case fails if the env var is
# ignored rather than passing by coincidence.
out="$( cd "$FIXREPO" && SECOND_SHIFT_CONFIG="$CFG_SET" bash "$TOOL" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "claude/second-shift-" ]; then
  pass "(k) SECOND_SHIFT_CONFIG is read when --config is absent, and wins over the git-derived root"
else fail "(k) expected rc=0 and 'claude/second-shift-', got rc=$rc '$out'"; fi

# ---- (k2) from a WORKTREE the git-derived root is the MAIN checkout ------------------------
# The runtime config is gitignored, so no worktree carries a copy and every production caller
# builds its --config from --git-common-dir. Anchoring this script's own fallback on
# --show-toplevel instead put the bare invocation on a different root than both of its callers:
# it found no config in the worktree, fell through to DETECTION, and answered with whatever
# namespace that repo's remotes happened to favor — confidently, and without saying it had
# guessed. Production was never affected; the operator debugging production was.
#
# Driven so a regression cannot pass by coincidence: the worktree gets a remote listing whose
# dominant identifier (`other/`) is NOT the configured prefix, so --show-toplevel resolves
# `other/` and --git-common-dir resolves `fixture/repo-`. The two roots give different answers,
# which is the only way this case can fail for the right reason.
# The config stays UNTRACKED, which is the property being modelled: it is gitignored in every
# real consumer, so `git worktree add` cannot materialize it in the new checkout. Committing it
# here would hand the worktree a local copy and make (k2) pass without ever reaching the main
# root — the exact coincidence (k2b) exists to rule out.
printf 'fixture\n' > "$FIXREPO/README.md"
git -C "$FIXREPO" add README.md >/dev/null 2>&1
git -C "$FIXREPO" -c user.name=selftest -c user.email=s@e.invalid \
    -c commit.gpgsign=false commit -qm "fixture: a commit to branch from" >/dev/null 2>&1
if git -C "$FIXREPO" worktree add -q -b wt-probe "$WORK/fixwt" >/dev/null 2>&1; then
  printf '  origin/other/11\n  origin/other/12\n  origin/solo/13\n' > "$WORK/branches-wt.txt"
  out="$( cd "$WORK/fixwt" && bash "$TOOL" --branches-file "$WORK/branches-wt.txt" 2>&1 )"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "fixture/repo-" ]; then
    pass "(k2) from a worktree the config is resolved from the MAIN checkout, not the worktree root"
  else fail "(k2) expected rc=0 and 'fixture/repo-' (the main checkout's config), got rc=$rc '$out'"; fi

  # The anti-vacuity half: prove the worktree really has no config of its own, so (k2) passed by
  # reaching the main checkout rather than by finding one locally. Without this, a resolver that
  # silently ignored the config entirely could still satisfy (k2) on a repo where detection
  # happened to agree.
  if [ ! -f "$WORK/fixwt/.claude/second-shift.config.json" ]; then
    pass "(k2b) the worktree carries no config of its own — (k2) is not passing by coincidence"
  else fail "(k2b) the worktree carries a config; (k2) proves nothing"; fi
else
  fail "(k2) could not create a worktree in the fixture repo — the case did not run"
fi

# ---- (m) the SCAN root, with no --branches-file and no --repo-root ------------------------
# Every detection case above hands the branch listing in through --branches-file, which skips
# the `git branch -r` call and the root it runs in entirely. So the one line that resolves that
# root had no coverage at all — and the line matters: it is where a bare operator invocation
# actually reads the remote from.
#
# Zero-network, like the rest of the suite: `git update-ref` writes remote-tracking refs
# directly, so `git branch -r` has real refs to list with no remote configured and nothing
# fetched. The config here sets NO branchPrefix, so detection is genuinely reached rather than
# short-circuited by the configured path.
FIXDET="$WORK/fixdet"
mkdir -p "$FIXDET/.claude"
git -C "$FIXDET" init -q
jq -n '{tracker: {type: "github"}}' > "$FIXDET/.claude/second-shift.config.json"
printf 'seed\n' > "$FIXDET/seed.txt"
git -C "$FIXDET" add seed.txt >/dev/null 2>&1
git -C "$FIXDET" -c user.name=selftest -c user.email=s@e.invalid \
    -c commit.gpgsign=false commit -qm "seed" >/dev/null 2>&1
DETSHA="$(git -C "$FIXDET" rev-parse HEAD)"
for ref in jdoe/7 jdoe/8 asmith/9; do
  git -C "$FIXDET" update-ref "refs/remotes/origin/$ref" "$DETSHA"
done
out="$( cd "$FIXDET" && bash "$TOOL" 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "jdoe/" ]; then
  pass "(m) detection scans the git-resolved root when no --branches-file and no --repo-root are given"
else fail "(m) expected rc=0 and 'jdoe/' from the git-resolved root, got rc=$rc '$out'"; fi

# ---- (l) --help prints the usage block and stops there ------------------------------------
# BOUNDED, not a substring probe, for the reason retro-corpus-selftest.sh's (help) case
# records: `sed -n '30,41p'` mutated to `sed -z` is rejected by BSD sed (dies locally) but
# accepted by GNU sed, where it also drops `-n`'s no-autoprint and dumps the WHOLE script —
# which trivially still contains "Usage:". Requiring the output to stop before the first line
# of code is what catches the platform where the mutant lives.
out="$(bash "$TOOL" --help 2>&1)"; rc=$?
lines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -qF 'Usage:' \
   && printf '%s' "$out" | grep -qF 'Exit: 0 = prefix printed on stdout' \
   && ! printf '%s' "$out" | grep -qF 'set -uo pipefail' \
   && [ "$lines" -le 13 ]; then
  pass "(l) --help prints the usage block through its last line and stops before the code"
else fail "(l) rc=$rc, $lines line(s): $out"; fi

echo "[branch-prefix-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"

#!/usr/bin/env bash
# preflight-selftest.sh — proves preflight.sh's read-only contract (#30).
#
# The zero-write assertion is the heart: preflight's promise is "zero tracker/
# git/remote mutations", and this selftest is the executable form of that
# promise. Fixture-driven: a real `git init` consumer repo, a mock `gh` on PATH
# that RECORDS every invocation (so the verb audit is evidence, not trust), and
# a mock environment doctor via the PREFLIGHT_DOCTOR_CMD seam.
#
# Covered:
#   1. zero-write — after a full run: no tracked-file changes, no new branches,
#      no commits, and the mock gh log contains ONLY reads (no POST/PATCH/PUT/
#      DELETE, no issue edit/comment, no pr create).
#   2. mutating-lane skips — format-as-string and lintAutofixes:true lanes are
#      SKIPped with a note and their commands NEVER execute (canary files).
#   3. lane execution — non-null lanes run exactly once; a failing lane FAILs
#      and lands in the exit code.
#   4. ticket-key arg vs queue-head fallback — issues/<key> GET vs issue list.
#   5. jira adapter — tracker read SKIPs with the session-side MCP note.
#   6. report — written at .claude/pipeline-state/preflight-report.md; doctor
#      FAILs fold into the exit code.
#
# macOS ships bash 3.2 as /bin/bash; this selftest runs there.

set -uo pipefail
# Hermetic hygiene: a dev-pipeline Stage-6 verify run exports pipeline seam vars
# (SECOND_SHIFT_CONFIG, BRANCH_PREFIX, …) into the test command, and the tools under
# test honor them as overrides — which would clobber this selftest's own fixtures.
# Unset them so the selftest controls its environment regardless of the caller (#34).
unset SECOND_SHIFT_CONFIG SECOND_SHIFT_REPO_ROOT SECOND_SHIFT_EXTENSION_MANIFEST BRANCH_PREFIX \
      SECOND_SHIFT_REVIEW_TOOLKIT_ROOT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/preflight.sh"
# review-toolkit sibling plugin root — resolved for the section-lint wiring so the selftest
# exercises the cross-plugin path hermetically (no `claude` binary), via the env override
# preflight.sh reads.
#
# The fixed `$SCRIPT_DIR/../../../../review-toolkit` hop count this used to be holds only in the
# monorepo. Installed, this file lives at
# <cache>/<marketplace>/dev-pipeline/<version>/skills/run/tools, so it resolved to nothing,
# SECOND_SHIFT_REVIEW_TOOLKIT_ROOT went in empty, and runs 1-9 stopped exercising the env
# override at all — preflight.sh:144-147 fell through to its `claude plugin list` rung instead,
# which is exactly the non-hermetic path those runs exist to avoid.
#
# House three-rung ladder: monorepo path -> cache sibling at THIS plugin's own version -> newest
# cache version carrying the marker. Hop constants are RE-DERIVED for this directory —
# skills/run/tools sits three levels under the plugin root, so the plugins dir is four hops up
# and the marketplace root five (check-model-tiers.sh, one level under its plugin root, uses two
# and three). Newest version is chosen LEXICALLY, mirroring the house ladders: `9.0.0` outranks
# `10.0.0`, a shared latent defect deliberately mirrored rather than fixed here.
#
# NO SKIP RUNG. Run 10 still exercises preflight's unresolved branch, but it does so by forcing
# the override empty. A resolution MISS here is a defect, and the assertion below makes it a
# counted failure rather than silently retargeting runs 1-9 at the `claude` rung.
#
# resolve_sibling_plugin_root <anchor-dir> <name> <marker-subpath> — echoes the sibling plugin
# ROOT. The anchor is a PARAMETER rather than a read of this file's own directory variable:
# that was the only thing separating this copy from doctor-selftest.sh's, whose hop
# constants are identical, and passing it in makes the two blocks byte-identical so
# scripts/lockstep-manifest.tsv can pin them instead of leaving them held by prose.
# LOCKSTEP-BEGIN cross-plugin-sibling-plugin-root
resolve_sibling_plugin_root() {
  local anchor="$1" name="$2" marker="$3" cand
  cand="$(cd "$anchor/../../../../$name" 2>/dev/null && pwd)" || cand=""
  if [[ -n "$cand" && -d "$cand/$marker" ]]; then printf '%s\n' "$cand"; return 0; fi
  for cand in "$anchor"/../../../../../"$name"/*/; do
    [[ -d "$cand/$marker" ]] || continue
    (cd "$cand" && pwd)
  done | tail -1
}
# LOCKSTEP-END cross-plugin-sibling-plugin-root
RT_TEST_ROOT="$(resolve_sibling_plugin_root "$SCRIPT_DIR" review-toolkit scripts || true)"

PASS=0; FAIL=0
assert() { # $1 = description, $2 = condition result (0 = pass)
  if [[ "$2" -eq 0 ]]; then PASS=$((PASS+1)); echo "[self-test] ok   $1"
  else FAIL=$((FAIL+1)); echo "[self-test] FAIL $1"; fi
}

# Runs 1-9 below feed RT_TEST_ROOT to preflight as the env override. An empty one does not fail
# them — it silently moves them onto the `claude plugin list` rung, which is how this suite
# passed on a developer machine and failed on CI for a release. Assert the resolution itself.
[[ -n "$RT_TEST_ROOT" ]] && _c=0 || _c=1
assert "review-toolkit sibling root resolved (section-lint wiring is exercised via the env override)" "$_c"

BASE="$(mktemp -d -t preflight-selftest.XXXXXX)"
trap 'rm -rf "$BASE"' EXIT

# ---- fixture consumer repo -------------------------------------------------------
FIX="$BASE/consumer"
mkdir -p "$FIX/.claude"
git init -q "$FIX"
git -C "$FIX" config user.email t@t
git -C "$FIX" config user.name t
echo "hello" > "$FIX/README.md"
# A CLEAN review-context surface so the section lint passes (exit 0) + surfaces its
# coverage line — committed so it does not perturb the zero-write assertion.
mkdir -p "$FIX/.claude/second-shift"
printf '# Review context — fix\n\n## Stack\nNext.js + Postgres.\n' > "$FIX/.claude/second-shift/review-context.md"
# One tracked NON-inert source file. Without it every tracked path in this fixture is
# *.md, i.e. the whole tree classifies INERT — which is the unreachable-lane condition
# the AC-4 check below warns about, and it would fire across the shared cases that are
# about something else entirely. A consumer repo whose lanes are meant to be reachable
# has a product surface; this makes the fixture one.
mkdir -p "$FIX/src"
printf 'export const x = 1\n' > "$FIX/src/index.ts"
git -C "$FIX" add README.md .claude/second-shift/review-context.md src/index.ts && git -C "$FIX" commit -qm init

CANARY_DIR="$BASE/canaries"; mkdir -p "$CANARY_DIR"

write_config() { # $1 = tracker type
  cat > "$FIX/.claude/second-shift.config.json" <<EOF
{
  "configVersion": 2,
  "tracker": { "type": "$1", "branchPrefix": "claude/fix-" },
  "topology": { "type": "standalone", "repos": { "fix": { "path": ".", "baseBranch": "main" } } },
  "commands": {
    "fix": {
      "lint": "touch $CANARY_DIR/lint-ran; exit 1",
      "lintAutofixes": true,
      "typecheck": "echo typecheck-green",
      "test": "echo test-green",
      "format": "touch $CANARY_DIR/format-ran",
      "lanes": [ { "name": "setup", "commands": ["echo setup-green", "test -z \\"\${SECOND_SHIFT_REPO_ROOT:-}\${SECOND_SHIFT_CONFIG:-}\${PREFLIGHT_DOCTOR_CMD:-}\\""] } ]
    }
  }
}
EOF
}
write_config github

# ---- mock gh on PATH (records every invocation) -----------------------------------
MOCKBIN="$BASE/bin"; mkdir -p "$MOCKBIN"
GH_LOG="$BASE/gh.log"
cat > "$MOCKBIN/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$GH_LOG"
case "\$1 \$2" in
  "api repos/{owner}/{repo}/issues/42") echo "#42 [open] fixture issue" ;;
  "issue list") echo "#7 fixture queue head" ;;
  *) echo "" ;;
esac
exit 0
EOF
chmod +x "$MOCKBIN/gh"
export PATH="$MOCKBIN:$PATH"

# mock doctor (the PREFLIGHT_DOCTOR_CMD seam): green, no writes
DOC_OK="$BASE/doctor-ok.sh"
printf '#!/usr/bin/env bash\necho "[doctor] summary: 0 failed check(s)"\nexit 0\n' > "$DOC_OK"

run_preflight() { # $@ = extra args; uses current fixture config
  SECOND_SHIFT_REPO_ROOT="$FIX" PREFLIGHT_DOCTOR_CMD="bash $DOC_OK" \
    SECOND_SHIFT_REVIEW_TOOLKIT_ROOT="$RT_TEST_ROOT" \
    bash "$PREFLIGHT" "$@" >"$BASE/out.log" 2>&1
}

# ---- run 1: github, no ticket key (the onboard finish-line case) -------------------
: > "$GH_LOG"
run_preflight; rc=$?

assert "exit 0 on a green fixture (rc=$rc)" "$rc"
[[ ! -f "$CANARY_DIR/lint-ran" ]] && _c=0 || _c=1;   assert "lintAutofixes:true lane never executed" "$_c"
[[ ! -f "$CANARY_DIR/format-ran" ]] && _c=0 || _c=1; assert "format-as-string lane never executed" "$_c"
grep -q "lane 'lint': lintAutofixes=true" "$BASE/out.log";  assert "lint skip is surfaced with a note" "$?"
grep -q "lane 'format': configured string" "$BASE/out.log"; assert "format skip is surfaced with a note" "$?"
grep -q "lane 'typecheck': green" "$BASE/out.log"; assert "typecheck lane ran" "$?"
grep -q "lane 'test': green" "$BASE/out.log";      assert "test lane ran" "$?"
grep -q "lane 'setup\[1\]': green" "$BASE/out.log"; assert "setup lane ran" "$?"
grep -q "lane 'setup\[2\]': green" "$BASE/out.log"
assert "env hygiene: preflight seams (SECOND_SHIFT_REPO_ROOT et al.) do not leak into lanes" "$?"

grep -q "^issue list" "$GH_LOG"; assert "no-key run reads the queue head (gh issue list)" "$?"

[[ -s "$FIX/.claude/pipeline-state/preflight-report.md" ]] && _c=0 || _c=1
assert "report written at .claude/pipeline-state/preflight-report.md" "$_c"

# ZERO-WRITE: tracked tree clean; the only untracked artifact is under .claude/
DIRTY="$(git -C "$FIX" status --porcelain | grep -v '^?? .claude/' || true)"
[[ -z "$DIRTY" ]] && _c=0 || _c=1; assert "zero-write: no tracked-file changes (${DIRTY:-clean})" "$_c"
BRANCHES="$(git -C "$FIX" branch --list | wc -l | tr -d ' ')"
[[ "$BRANCHES" == "1" ]] && _c=0 || _c=1; assert "zero-write: no new branches (count=$BRANCHES)" "$_c"
COMMITS="$(git -C "$FIX" rev-list --count HEAD)"
[[ "$COMMITS" == "1" ]] && _c=0 || _c=1; assert "zero-write: no new commits (count=$COMMITS)" "$_c"
! grep -qE -- '-X (POST|PATCH|PUT|DELETE)|issue (edit|comment)|pr create|label create' "$GH_LOG"
assert "zero-write: mock gh saw only reads" "$?"

# section lint (review-toolkit) surfaces via the env-override wiring, with its coverage line
grep -q "check-review-context-sections: no alias drift" "$BASE/out.log"
assert "section lint surfaces at preflight (clean review-context)" "$?"
grep -q "context-coverage:.*catalog sections present" "$BASE/out.log"
assert "context-coverage line surfaces (exit-neutral)" "$?"

# ---- run 2: explicit ticket key ----------------------------------------------------
: > "$GH_LOG"
run_preflight 42; rc=$?
grep -q "^api repos/{owner}/{repo}/issues/42" "$GH_LOG"
assert "key run reads issues/<key> (rc=$rc)" "$?"
! grep -q "^issue list" "$GH_LOG"; assert "key run does not query the queue" "$?"

# ---- run 3: failing lane lands in the exit code ------------------------------------
jq '.commands.fix.test = "exit 1"' "$FIX/.claude/second-shift.config.json" > "$BASE/cfg.tmp" \
  && mv "$BASE/cfg.tmp" "$FIX/.claude/second-shift.config.json"
run_preflight; rc=$?
[[ "$rc" -eq 1 ]] && _c=0 || _c=1; assert "one failing lane => exit 1 (rc=$rc)" "$_c"
grep -q "lane 'test' failed" "$BASE/out.log"; assert "failing lane surfaced as FAIL" "$?"

# ---- run 4: jira adapter — tracker read skips (session-side MCP) --------------------
write_config jira
: > "$GH_LOG"
run_preflight; rc=$?
grep -q "tracker read: tracker.type=jira" "$BASE/out.log"
assert "jira: tracker read SKIPs with the MCP note (rc=$rc)" "$?"
! grep -qE '^(api repos|issue list)' "$GH_LOG"; assert "jira: no gh tracker read issued" "$?"

# ---- run 5: doctor FAILs fold into the exit code ------------------------------------
write_config github
DOC_BAD="$BASE/doctor-bad.sh"
printf '#!/usr/bin/env bash\necho "[doctor] FAIL x"; echo "[doctor] FAIL y"\nexit 2\n' > "$DOC_BAD"
SECOND_SHIFT_REPO_ROOT="$FIX" PREFLIGHT_DOCTOR_CMD="bash $DOC_BAD" \
  bash "$PREFLIGHT" >"$BASE/out.log" 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && _c=0 || _c=1; assert "doctor's 2 FAILs fold into exit code (rc=$rc)" "$_c"

# ---- run 6: config-gate failure path — config-lint reject FAILs ----------------------
# gates.costTracking was removed in v2.1.6; a config carrying it must be rejected by
# config-lint and land in preflight's exit code with the lanes never reached green-only.
jq '. + {gates: {costTracking: true}}' "$FIX/.claude/second-shift.config.json" > "$BASE/cfg.tmp" \
  && mv "$BASE/cfg.tmp" "$FIX/.claude/second-shift.config.json"
run_preflight; rc=$?
[[ "$rc" -ge 1 ]] && _c=0 || _c=1; assert "config-lint reject lands in the exit code (rc=$rc)" "$_c"
grep -q "config-lint rejected" "$BASE/out.log"; assert "config-lint reject surfaced as FAIL" "$?"

# ---- run 7: missing config FAILs with the onboard hint -------------------------------
rm -f "$FIX/.claude/second-shift.config.json"
run_preflight; rc=$?
[[ "$rc" -ge 1 ]] && _c=0 || _c=1; assert "missing config => nonzero exit (rc=$rc)" "$_c"
grep -q "no consumer config at" "$BASE/out.log"; assert "missing config surfaced with the onboard hint" "$?"

# ---- run 8: extraLanes execute with the when-gate note --------------------------------
write_config github
jq '.commands.fix.extraLanes = [{"name": "extra", "commands": ["echo extra-green"], "when": ["src/**"], "failureClass": "TEST_FAILURE"}]' \
  "$FIX/.claude/second-shift.config.json" > "$BASE/cfg.tmp" \
  && mv "$BASE/cfg.tmp" "$FIX/.claude/second-shift.config.json"
run_preflight; rc=$?
[[ "$rc" -eq 0 ]] && _c=0 || _c=1; assert "extraLanes fixture run is green (rc=$rc)" "$_c"
grep -q "extraLanes\[1\] (when-gate not evaluated — no diff at preflight)': green" "$BASE/out.log"
assert "extraLanes run unconditionally with the when-gate note" "$?"

# ---- run 9: section lint rejects a drifted (alias) review-context heading ------------
write_config github
printf '# Review context — fix\n\n## Maturity calibration (MVP stage)\nPre-auth MVP.\n' \
  > "$FIX/.claude/second-shift/review-context.md"
run_preflight; rc=$?
[[ "$rc" -ge 1 ]] && _c=0 || _c=1; assert "section lint alias drift => nonzero exit (rc=$rc)" "$_c"
grep -q "check-review-context-sections rejected the repo" "$BASE/out.log"
assert "section lint alias drift surfaced as FAIL" "$?"
# restore the clean fixture for any later run
git -C "$FIX" checkout -- .claude/second-shift/review-context.md 2>/dev/null \
  || printf '# Review context — fix\n\n## Stack\nNext.js + Postgres.\n' > "$FIX/.claude/second-shift/review-context.md"

# ---- run 10: review-toolkit unresolved => section lint skips with a WARN, preflight green
# Force the skip branch deterministically: empty env override AND a mock `claude` returning
# [] so the pluglist fallback resolves nothing. (Runs 1-9 keep RT_TEST_ROOT set, so the
# `-z RT_ROOT` guard short-circuits before claude is ever consulted there.)
printf '#!/usr/bin/env bash\necho "[]"\n' > "$MOCKBIN/claude"; chmod +x "$MOCKBIN/claude"
SECOND_SHIFT_REPO_ROOT="$FIX" PREFLIGHT_DOCTOR_CMD="bash $DOC_OK" \
  SECOND_SHIFT_REVIEW_TOOLKIT_ROOT="" \
  bash "$PREFLIGHT" >"$BASE/out.log" 2>&1; rc=$?
grep -q "check-review-context-sections: review-toolkit not resolved" "$BASE/out.log"
assert "unresolved review-toolkit => section lint skips with a WARN" "$?"
[[ "$rc" -eq 0 ]] && _c=0 || _c=1; assert "section-lint skip does not fail preflight (rc=$rc)" "$_c"
rm -f "$MOCKBIN/claude"

# ---- run 11: a malformed lanes[] entry must not silently drop the GOOD lanes (#100) ----
# Before the select(type == "object") guard, `.[] | (.commands // [])[]` aborted the whole
# jq stream on the first non-object entry — and the read's 2>/dev/null hid the error — so a
# single bad entry silently dropped EVERY lane while preflight still reported it had run
# them. config-lint (run earlier by preflight) now rejects such a config, but bad() only
# counts the failure and execution continues into the lane section on the SAME run, so the
# read itself must stay safe. Assert both halves: the config IS rejected, AND the
# well-formed sibling lane still executes.
write_config github
jq '.commands.fix.lanes = ["bogus-string-lane", {"name": "setup", "commands": ["echo setup-green"]}]' \
  "$FIX/.claude/second-shift.config.json" > "$BASE/cfg.tmp" \
  && mv "$BASE/cfg.tmp" "$FIX/.claude/second-shift.config.json"
run_preflight; rc=$?
[[ "$rc" -ge 1 ]] && _c=0 || _c=1; assert "malformed lane entry is rejected by the config gate (rc=$rc)" "$_c"
grep -q "config-lint rejected" "$BASE/out.log"; assert "malformed lane surfaced as a config-lint FAIL" "$?"
grep -q "lane 'setup\[1\]': green" "$BASE/out.log"
assert "well-formed sibling lane still runs — one bad entry does not drop every lane" "$?"

# ---- run 12: an all-null command table must not preflight "pipeline-ready" (#102, AC-1) ----
# The onboarding failure this closes: for a stack detect.sh does not cover (Python, bun,
# cargo, go) onboard correctly refuses to guess and drafts every lane null. That config
# passes config-lint and prints only per-lane SKIPs, so the run still closed with
# "pipeline-ready" while verifying nothing. Setup lanes[] stay configured here on purpose —
# they are SETUP-only and must NOT count as verification.
write_config github
jq '.commands.fix |= (.lint = null | .typecheck = null | .test = null | .format = null | .extraLanes = [])' \
  "$FIX/.claude/second-shift.config.json" > "$BASE/cfg.tmp" \
  && mv "$BASE/cfg.tmp" "$FIX/.claude/second-shift.config.json"
run_preflight; rc=$?
[[ "$rc" -eq 0 ]] && _c=0 || _c=1
assert "zero verifying lanes stays exit-0 — a warning, never a hard stop (rc=$rc)" "$_c"
grep -q "no verifying lane configured for 'fix'" "$BASE/out.log"
assert "zero verifying lanes surfaced as a WARN (AC-1)" "$?"
! grep -q -- "— pipeline-ready" "$BASE/out.log"
assert "verdict does not claim pipeline-ready when nothing verifies (AC-1)" "$?"
grep -q "NOT pipeline-ready: nothing verified this repo" "$BASE/out.log"
assert "verdict states plainly why it is not ready (AC-1)" "$?"
grep -q "lane 'setup\[1\]': green" "$BASE/out.log"
assert "setup lanes still run but do not count as verification (AC-1)" "$?"

# ---- run 13: allowUnverified is the explicit opt-out — stay silent (#102, AC-2) ----
# The repo already ships allowUnverified as the sanctioned zero-lane safety valve
# (verifyctl emits its labeled skip at Stage 6). An operator who has declared the opt-out
# has answered the question, so the warning must not nag — and readiness is honest again.
jq '.commands.fix.allowUnverified = true' \
  "$FIX/.claude/second-shift.config.json" > "$BASE/cfg.tmp" \
  && mv "$BASE/cfg.tmp" "$FIX/.claude/second-shift.config.json"
run_preflight; rc=$?
[[ "$rc" -eq 0 ]] && _c=0 || _c=1; assert "opt-out run is green (rc=$rc)" "$_c"
! grep -q "no verifying lane configured for 'fix'" "$BASE/out.log"
assert "allowUnverified suppresses the warning (AC-2)" "$?"
grep -q "allowUnverified opt-out is set" "$BASE/out.log"
assert "the deliberate opt-out is still surfaced as a SKIP note (AC-2)" "$?"
grep -q -- "— pipeline-ready" "$BASE/out.log"
assert "an explicit opt-out still reports pipeline-ready (AC-2)" "$?"

# ---- run 14: one verifying lane is enough — no warning (#102, AC-3) ----
# The negative case that keeps the check from firing on every ordinary repo.
write_config github
jq '.commands.fix |= (.lint = null | .test = null | .extraLanes = [])' \
  "$FIX/.claude/second-shift.config.json" > "$BASE/cfg.tmp" \
  && mv "$BASE/cfg.tmp" "$FIX/.claude/second-shift.config.json"
run_preflight; rc=$?
[[ "$rc" -eq 0 ]] && _c=0 || _c=1; assert "single-verifying-lane run is green (rc=$rc)" "$_c"
! grep -q "no verifying lane configured" "$BASE/out.log"
assert "a single configured typecheck lane suppresses the warning (AC-3)" "$?"
grep -q -- "— pipeline-ready" "$BASE/out.log"
assert "a repo that verifies something still reports pipeline-ready (AC-3)" "$?"

# ---- run 15: no host repo (path ".") also suppresses pipeline-ready (#102, AC-1) ----
# The lane pass is skipped wholesale when no topology.repos entry maps to path "." — so
# nothing was verified, and the verdict must not claim readiness. config-lint only requires
# >=1 topology.repos entry, not that one of them be the host, so this state is reachable
# with a config-lint-clean file. Distinct from run 12: there the host exists and its lanes
# are null; here the lane section never runs at all.
write_config github
jq '.topology.repos = {"elsewhere": (.topology.repos.fix + {"path": "sub/dir"})}' \
  "$FIX/.claude/second-shift.config.json" > "$BASE/cfg.tmp" \
  && mv "$BASE/cfg.tmp" "$FIX/.claude/second-shift.config.json"
run_preflight; rc=$?
grep -q "no host repo" "$BASE/out.log"
assert "no-host-repo config surfaces the lane-pass-skipped WARN (AC-1)" "$?"
if [[ "$rc" -eq 0 ]]; then
  ! grep -q -- "— pipeline-ready" "$BASE/out.log"
  assert "no-host-repo run does not claim pipeline-ready (AC-1)" "$?"
else
  # Other gates failed on this fixture; the third verdict arm already omits the claim.
  ! grep -q -- "— pipeline-ready" "$BASE/out.log"
  assert "no-host-repo run does not claim pipeline-ready even with FAILs (rc=$rc) (AC-1)" "$?"
fi

# ---- runs 16-17: configured lanes that can NEVER run (#127, AC-4) ----
# The sibling of run 12, opposite cause: lanes ARE configured, but every tracked file
# classifies INERT, so Stage 6 always takes the inert lane and they never execute. The
# config looks verified while the pipeline verifies nothing — a false green that is
# otherwise invisible until a run reports "skipped (inert diff)".
#
# This needs its own repo: the shared fixture deliberately tracks a .ts source so the
# condition does NOT hold there (see the fixture comment above).
SHFIX="$BASE/shell-consumer"
mkdir -p "$SHFIX/.claude/second-shift"
git init -q "$SHFIX"
git -C "$SHFIX" config user.email t@t
git -C "$SHFIX" config user.name t
printf '# shell tool\n' > "$SHFIX/README.md"
printf '#!/usr/bin/env bash\necho hi\n' > "$SHFIX/run.sh"
printf '# Review context — sh\n\n## Stack\nBash.\n' > "$SHFIX/.claude/second-shift/review-context.md"
git -C "$SHFIX" add -A && git -C "$SHFIX" commit -qm init

write_shell_config() { # $1 = inertPattern JSON value ("null" = omit the key)
  cat > "$SHFIX/.claude/second-shift.config.json" <<EOF
{
  "configVersion": 2,
  "tracker": { "type": "github", "branchPrefix": "claude/sh-" },
  "topology": { "type": "standalone", "repos": { "sh": { "path": ".", "baseBranch": "main" } } },
  "commands": { "sh": { "lint": "echo lint-green", "typecheck": null, "test": "echo test-green", "format": null } },
  "stageParams": { "inertPattern": $1 }
}
EOF
  [[ "$1" == "null" ]] && jq 'del(.stageParams)' "$SHFIX/.claude/second-shift.config.json" > "$BASE/shcfg.tmp" \
    && mv "$BASE/shcfg.tmp" "$SHFIX/.claude/second-shift.config.json"
  return 0
}

run_shell_preflight() {
  SECOND_SHIFT_REPO_ROOT="$SHFIX" PREFLIGHT_DOCTOR_CMD="bash $DOC_OK" \
    SECOND_SHIFT_REVIEW_TOOLKIT_ROOT="$RT_TEST_ROOT" \
    bash "$PREFLIGHT" >"$BASE/out.log" 2>&1
}

# run 16: lanes configured, NO override — the default inert set swallows *.sh and *.md,
# so the whole tree is inert and the lanes are unreachable. WARN fires.
write_shell_config null
run_shell_preflight; rc=$?
grep -q "can never run" "$BASE/out.log"
assert "all-inert tree with configured lanes surfaces the unreachable-lane WARN (AC-4)" "$?"
grep -q "Set stageParams.inertPattern" "$BASE/out.log"
assert "the WARN names the remedy when no override is set (AC-4)" "$?"
! grep -q -- "— pipeline-ready" "$BASE/out.log"
assert "a repo whose lanes can never run is not pipeline-ready (AC-4)" "$?"

# run 17: same repo, override set so *.sh is no longer inert — the lanes are reachable
# and the WARN must NOT fire. Without this negative the check could pass by always
# warning.
write_shell_config '"(\\.md$)"'
run_shell_preflight; rc=$?
! grep -q "can never run" "$BASE/out.log"
assert "an override that frees the product surface suppresses the WARN (AC-4)" "$?"

# ---- run 18: plan-path resolution strips retired/unknown tokens (#267 D-3) ----------
# The substitution enumerates {plansDir} and {issueKey} and then strips ANY residual
# {token}. That trailing strip is what lets a consumer whose override still carries the
# retired slice token resolve to a valid plan path instead of embedding the literal in
# the filename. preflight resolves the pattern through the same substitution the stages
# use and PRINTS the result -- so this is the one place the behavior is assertable, and
# without these two cases the strip ships untested at all five of its call sites.
write_plan_pattern_config() { # $1 = the stageParams.planFilePattern value
  cat > "$FIX/.claude/second-shift.config.json" <<EOF
{
  "configVersion": 2,
  "tracker": { "type": "github", "branchPrefix": "claude/fix-" },
  "topology": { "type": "standalone", "repos": { "fix": { "path": ".", "baseBranch": "main" } } },
  "commands": { "fix": { "lint": "echo lint-green", "test": "echo test-green" } },
  "stageParams": { "planFilePattern": "$1" }
}
EOF
}

# 18a: an UNMIGRATED override still carrying the retired token must degrade to a clean
# path -- the token stripped, not left literally in the filename.
write_plan_pattern_config '{plansDir}/plan-{issueKey}{slice}.md'
run_preflight 42; rc=$?
grep -q "plan file: 'docs/plans/plan-42.md'" "$BASE/out.log"
assert "an unmigrated override degrades to a valid plan path, token stripped (#267 AC-3)" "$?"
! grep -q 'plan-42{slice}' "$BASE/out.log"
assert "the retired token is not left embedded in the resolved path (#267 AC-3)" "$?"

# 18b: the negative -- a pattern using only known tokens must be untouched. Without
# this, 18a could pass while the strip over-matched and ate legitimate path content.
write_plan_pattern_config '{plansDir}/acme-{issueKey}.md'
run_preflight 42; rc=$?
grep -q "plan file: 'docs/plans/acme-42.md'" "$BASE/out.log"
assert "a fully-migrated pattern resolves unchanged -- the strip does not over-match" "$?"

write_config github   # restore the shared fixture for any later case

echo "[self-test] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0

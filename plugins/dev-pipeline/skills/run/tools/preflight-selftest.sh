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
# preflight.sh reads. plugins/dev-pipeline/skills/run/tools -> plugins/review-toolkit.
RT_TEST_ROOT="$(cd "$SCRIPT_DIR/../../../../review-toolkit" 2>/dev/null && pwd || true)"

PASS=0; FAIL=0
assert() { # $1 = description, $2 = condition result (0 = pass)
  if [[ "$2" -eq 0 ]]; then PASS=$((PASS+1)); echo "[self-test] ok   $1"
  else FAIL=$((FAIL+1)); echo "[self-test] FAIL $1"; fi
}

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
git -C "$FIX" add README.md .claude/second-shift/review-context.md && git -C "$FIX" commit -qm init

CANARY_DIR="$BASE/canaries"; mkdir -p "$CANARY_DIR"

write_config() { # $1 = tracker type
  cat > "$FIX/.claude/second-shift.config.json" <<EOF
{
  "configVersion": 1,
  "tracker": { "type": "$1", "branchPrefix": "claude/fix-" },
  "topology": { "type": "standalone", "repos": { "fix": { "path": ".", "baseBranch": "main" } } },
  "commands": {
    "fix": {
      "lint": "touch $CANARY_DIR/lint-ran; exit 1",
      "lintAutofixes": true,
      "typecheck": "echo typecheck-green",
      "test": "echo test-green",
      "build": null,
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
grep -q "lane 'build': null/absent" "$BASE/out.log"; assert "null lane skipped" "$?"

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

echo "[self-test] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0

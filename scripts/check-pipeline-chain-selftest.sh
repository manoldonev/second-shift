#!/usr/bin/env bash
# check-pipeline-chain-selftest.sh — proves scripts/check-pipeline-chain.sh (T2 rung 1).
#
# Builds a throwaway git repo with committed plan files, drives the check with FIXTURE comment
# trails via --comments-file, and mocks `gh` on PATH for the live-fetch cases. ZERO NETWORK.
#
# Tier justification (CLAUDE.md's map): one script's behavior against fixtures => a per-tool
# behavioral selftest. The scenario-liveness suite is scoped to statectl-composed verdict paths
# and cannot compose a GitHub-Actions-side reader, so no scenario covers this invariant.
#
# Anti-vacuity: the script's existence is asserted up front (exit 2 with a distinct message if
# absent), and case (a) is a POSITIVE control — deleting check-pipeline-chain.sh turns the suite
# red rather than letting every "should fail" case pass on a 127.
#
# bash-3.2-safe; runs in CI via the '*-selftest.sh' discovery loop.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHAIN="$HERE/check-pipeline-chain.sh"
SCHEMA="$HERE/../plugins/dev-pipeline/skills/run/state-schema.md"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

# ---- anti-vacuity precondition ------------------------------------------------------------
if [[ ! -f "$CHAIN" ]]; then
  echo "FATAL: $CHAIN does not exist — the suite has nothing to prove. This is the anti-vacuity guard." >&2
  exit 2
fi

WORK="$(mktemp -d -t check-pipeline-chain-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# ---- fixture repo with committed plans ----------------------------------------------------
REPO="$WORK/repo"
mkdir -p "$REPO/docs/plans"
cd "$REPO" || exit 2
git init -q
git config user.name selftest
git config user.email selftest@example.invalid
git config commit.gpgsign false
echo "plan for 42" > docs/plans/acme-42.md
echo "plan for 42 slice 2" > docs/plans/acme-42-pr2.md
git add -A
git commit -qm "fixture: committed plans"

PREFIX="claude/acme-"
PATTERN="docs/plans/acme-{issueKey}{slice}.md"
OPEN_AT="2026-07-30T12:00:00Z"

# ---- trail builders -----------------------------------------------------------------------
# A comment record: <stage> <run_id> <created_at>
comment() {
  jq -n --arg s "$1" --arg r "$2" --arg t "$3" \
    '{body: ("<!-- dev-pipeline -->\n<!-- run_id: " + $r + " -->\n<!-- stage: " + $s + " -->\n\nbody text"), created_at: $t}'
}
# trail <file> <spec>...  where each spec is "stage:run:time"
trail() {
  local out="$1"; shift
  local parts=""
  local spec stage run at
  for spec in "$@"; do
    stage="${spec%%:*}"; spec="${spec#*:}"
    run="${spec%%:*}"; at="${spec#*:}"
    parts="$parts$(comment "$stage" "$run" "$at")"
  done
  printf '%s' "$parts" | jq -s '.' > "$out"
}

RUN_A="2026-07-30T090000Z-Mac-aaaa1111"
RUN_B="2026-07-30T190000Z-Mac-bbbb2222"

FULL="$WORK/full.json"
trail "$FULL" \
  "claimed:$RUN_A:2026-07-30T09:00:00Z" \
  "intake:$RUN_A:2026-07-30T09:10:00Z" \
  "plan:$RUN_A:2026-07-30T09:20:00Z" \
  "doc-update:$RUN_A:2026-07-30T09:30:00Z" \
  "code-review:$RUN_A:2026-07-30T09:40:00Z"

# run_chain <branch> <body> <comments-file> [extra env assignments as VAR=VAL]
run_chain() {
  local branch="$1" body="$2" cfile="$3"; shift 3
  env PIPELINE_BRANCH_PREFIX="$PREFIX" PIPELINE_PLAN_PATTERN="$PATTERN" \
      PR_HEAD_REF="$branch" PR_BODY="$body" PR_CREATED_AT="$OPEN_AT" \
      "$@" bash "$CHAIN" --comments-file "$cfile" > "$WORK/out.log" 2>&1
}

echo "== applicability =="

run_chain "feature/hand-made" "Closes #42" "$FULL"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "not applicable" "$WORK/out.log"; then
  ok "non-prefix branch passes with the not-applicable notice (AC-3)"
else bad "non-prefix branch: rc=$rc, log: $(cat "$WORK/out.log")"; fi

if grep -q "configured prefix: $PREFIX" "$WORK/out.log"; then
  ok "not-applicable verdict echoes the resolved prefix (stale-constant visibility)"
else bad "not-applicable verdict does not echo the resolved prefix"; fi

run_chain "${PREFIX}parallel-selftest-sweep" "Closes #42" "$FULL"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "non-key suffix" "$WORK/out.log"; then
  ok "prefix-matched branch with a non-key suffix is exempt with notice (AC-3)"
else bad "non-key suffix: rc=$rc, log: $(cat "$WORK/out.log")"; fi

echo "== fail-closed env constants (AC-3) =="

for var in PIPELINE_BRANCH_PREFIX PIPELINE_PLAN_PATTERN; do
  for val in "" "__UNSET__"; do
    if [[ "$val" == "__UNSET__" ]]; then
      env -u "$var" PIPELINE_BRANCH_PREFIX="$PREFIX" PIPELINE_PLAN_PATTERN="$PATTERN" \
        PR_HEAD_REF="${PREFIX}42" PR_BODY="Closes #42" PR_CREATED_AT="$OPEN_AT" \
        env -u "$var" bash "$CHAIN" --comments-file "$FULL" >/dev/null 2>&1
    else
      env PIPELINE_BRANCH_PREFIX="$PREFIX" PIPELINE_PLAN_PATTERN="$PATTERN" "$var=" \
        PR_HEAD_REF="${PREFIX}42" PR_BODY="Closes #42" PR_CREATED_AT="$OPEN_AT" \
        bash "$CHAIN" --comments-file "$FULL" >/dev/null 2>&1
    fi
    rc=$?
    label="$var $( [[ "$val" == "__UNSET__" ]] && echo unset || echo empty )"
    if [[ $rc -eq 2 ]]; then ok "fail-closed: $label => exit 2 (AC-3)"
    else bad "fail-closed: $label => rc=$rc, expected 2"; fi
  done
done

echo "== complete chain (positive control / anti-vacuity) =="

run_chain "${PREFIX}42" "Closes #42" "$FULL"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "chain complete and key-consistent" "$WORK/out.log"; then
  ok "complete in-family chain passes (AC-2) [positive control]"
else bad "complete chain: rc=$rc, log: $(cat "$WORK/out.log")"; fi

if grep -q "aaaa1111" "$WORK/out.log" && ! grep -q "$RUN_A" "$WORK/out.log"; then
  ok "run family is printed truncated to its random suffix, never in full"
else bad "run_id truncation: log leaks the full run_id or omits the suffix"; fi

echo "== each required marker is load-bearing (AC-2, AC-4) =="

for missing in claimed intake plan doc-update code-review; do
  F="$WORK/missing-$missing.json"
  specs=""
  for m in claimed:09:00 intake:09:10 plan:09:20 doc-update:09:30 code-review:09:40; do
    stage="${m%%:*}"; t="${m#*:}"
    [[ "$stage" == "$missing" ]] && continue
    specs="$specs $stage:$RUN_A:2026-07-30T$t:00Z"
  done
  # shellcheck disable=SC2086  # deliberate word-splitting of the spec list
  trail "$F" $specs
  run_chain "${PREFIX}42" "Closes #42" "$F"
  rc=$?
  # `claimed` is special: it is what SELECTS the family, so its absence fails earlier — at
  # family selection — with a distinct message rather than in the per-marker loop.
  if [[ "$missing" == claimed ]]; then needle="chain does not start"; else needle="✗ $missing"; fi
  if [[ $rc -eq 1 ]] && grep -q "$needle" "$WORK/out.log"; then
    ok "missing '$missing' marker fails and says so (AC-2$( [[ "$missing" == code-review ]] && echo ", AC-4" ))"
  else bad "missing '$missing': rc=$rc, log: $(cat "$WORK/out.log")"; fi
done

echo "== wrong-family marker (AC-2) =="

WRONGFAM="$WORK/wrong-family.json"
trail "$WRONGFAM" \
  "claimed:$RUN_A:2026-07-30T09:00:00Z" \
  "intake:$RUN_A:2026-07-30T09:10:00Z" \
  "plan:$RUN_A:2026-07-30T09:20:00Z" \
  "doc-update:$RUN_A:2026-07-30T09:30:00Z" \
  "code-review:2026-07-29T000000Z-Mac-cccc3333:2026-07-30T09:40:00Z"
run_chain "${PREFIX}42" "Closes #42" "$WRONGFAM"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "none in the active family" "$WORK/out.log"; then
  ok "marker present only under a foreign run_id fails as wrong-family (AC-2)"
else bad "wrong-family: rc=$rc, log: $(cat "$WORK/out.log")"; fi

echo "== PR-open window makes the gate idempotent (D-9) =="

# A newer claim lands AFTER the PR was opened (a re-run of the same issue). Bare recency would
# select RUN_B — whose stages have no markers — and red-line an already-green PR on every CI
# re-run. The window must keep RUN_A active.
LATERCLAIM="$WORK/later-claim.json"
trail "$LATERCLAIM" \
  "claimed:$RUN_A:2026-07-30T09:00:00Z" \
  "intake:$RUN_A:2026-07-30T09:10:00Z" \
  "plan:$RUN_A:2026-07-30T09:20:00Z" \
  "doc-update:$RUN_A:2026-07-30T09:30:00Z" \
  "code-review:$RUN_A:2026-07-30T09:40:00Z" \
  "claimed:$RUN_B:2026-07-30T19:00:00Z"
run_chain "${PREFIX}42" "Closes #42" "$LATERCLAIM"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "aaaa1111" "$WORK/out.log"; then
  ok "a claim newer than PR-open does not hijack the family — in-window family wins (D-9)"
else bad "window selection: rc=$rc, log: $(cat "$WORK/out.log")"; fi

# And the whole chain being newer than PR-open is a genuine failure: nothing was visible at open.
run_chain "${PREFIX}42" "Closes #42" "$FULL" PR_CREATED_AT_OVERRIDE=1
env PIPELINE_BRANCH_PREFIX="$PREFIX" PIPELINE_PLAN_PATTERN="$PATTERN" \
    PR_HEAD_REF="${PREFIX}42" PR_BODY="Closes #42" PR_CREATED_AT="2026-07-30T08:00:00Z" \
    bash "$CHAIN" --comments-file "$FULL" > "$WORK/out.log" 2>&1
rc=$?
if [[ $rc -eq 1 ]] && grep -q "chain does not start" "$WORK/out.log"; then
  ok "a trail entirely after PR-open fails — nothing was visible at the observation point"
else bad "pre-open window: rc=$rc, log: $(cat "$WORK/out.log")"; fi

echo "== issue resolution (D-6b, D-11, D-12) =="

run_chain "${PREFIX}42" "Part of #42" "$FULL"
rc=$?
if [[ $rc -eq 0 ]]; then ok "'Part of #N' resolves the source issue (D-6b)"
else bad "Part of resolution: rc=$rc, log: $(cat "$WORK/out.log")"; fi

run_chain "${PREFIX}42" "Closes #42

Part of #268" "$FULL"
rc=$?
if [[ $rc -eq 0 ]]; then ok "'Closes' wins over 'Part of' when a body carries both (D-12)"
else bad "Closes-over-Part-of precedence: rc=$rc, log: $(cat "$WORK/out.log")"; fi

run_chain "${PREFIX}42" "Some description with no reference at all." "$FULL"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "no resolvable issue reference" "$WORK/out.log"; then
  ok "applicable PR with no resolvable issue reference fails, never exempts (D-11)"
else bad "no-reference: rc=$rc, log: $(cat "$WORK/out.log")"; fi

echo "== three-way key consistency, each pair (AC-2) =="

# (a) body key vs branch suffix.
run_chain "${PREFIX}42" "Closes #99" "$FULL"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "key mismatch" "$WORK/out.log"; then
  ok "pair (a): PR-body key != branch suffix fails (AC-2)"
else bad "pair (a): rc=$rc, log: $(cat "$WORK/out.log")"; fi

# (b) branch key -> plan file absent.
NOPLAN="$WORK/noplan.json"
cp "$FULL" "$NOPLAN"
run_chain "${PREFIX}77" "Closes #77" "$NOPLAN"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "no committed plan at 'docs/plans/acme-77.md'" "$WORK/out.log"; then
  ok "pair (b): no committed plan at the branch-derived path fails (AC-2)"
else bad "pair (b): rc=$rc, log: $(cat "$WORK/out.log")"; fi

# (c) slice suffix must select the slice's OWN plan, not the parent's.
run_chain "${PREFIX}42-pr2" "Closes #42" "$FULL"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "acme-42-pr2.md" "$WORK/out.log"; then
  ok "pair (c): a slice branch is checked against its own plan file (D-6b)"
else bad "pair (c) slice plan: rc=$rc, log: $(cat "$WORK/out.log")"; fi

run_chain "${PREFIX}42-pr9" "Closes #42" "$FULL"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "acme-42-pr9.md" "$WORK/out.log"; then
  ok "pair (c): a slice with no committed plan of its own fails (AC-2)"
else bad "pair (c) missing slice plan: rc=$rc, log: $(cat "$WORK/out.log")"; fi

echo "== live fetch failure is an environment error, not a pass (D-11) =="

MOCKBIN="$WORK/bin"; mkdir -p "$MOCKBIN"
printf '#!/usr/bin/env bash\necho "API rate limit exceeded" >&2\nexit 1\n' > "$MOCKBIN/gh-fail"
chmod +x "$MOCKBIN/gh-fail"
env PIPELINE_BRANCH_PREFIX="$PREFIX" PIPELINE_PLAN_PATTERN="$PATTERN" \
    PR_HEAD_REF="${PREFIX}42" PR_BODY="Closes #42" PR_CREATED_AT="$OPEN_AT" \
    GH_REPO="owner/repo" GH="$MOCKBIN/gh-fail" \
    bash "$CHAIN" > "$WORK/out.log" 2>&1
rc=$?
if [[ $rc -eq 2 ]] && grep -q "comment fetch failed" "$WORK/out.log"; then
  ok "failed comment fetch exits 2 (environment), never a silent pass (D-11)"
else bad "fetch failure: rc=$rc, log: $(cat "$WORK/out.log")"; fi

# And the live path works when the mock succeeds — proving the ${GH:-gh} seam is really used.
printf '#!/usr/bin/env bash\ncat "%s"\n' "$FULL" > "$MOCKBIN/gh-ok"
chmod +x "$MOCKBIN/gh-ok"
env PIPELINE_BRANCH_PREFIX="$PREFIX" PIPELINE_PLAN_PATTERN="$PATTERN" \
    PR_HEAD_REF="${PREFIX}42" PR_BODY="Closes #42" PR_CREATED_AT="$OPEN_AT" \
    GH_REPO="owner/repo" GH="$MOCKBIN/gh-ok" \
    bash "$CHAIN" > "$WORK/out.log" 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then ok "the \${GH:-gh} seam drives the live path (zero network)"
else bad "live path via mock gh: rc=$rc, log: $(cat "$WORK/out.log")"; fi

echo "== required markers are a subset of the canonical enum =="

# The script's REQUIRED_MARKERS is a second checked-in copy of part of the stage-comment enum.
# The canonical side is a GENERATED bash `case` in statectl.sh, so there is no quoted literal to
# anchor a lockstep row against (see the DROPPED entry in scripts/lockstep-manifest.tsv). This
# asserts the real invariant behaviorally: every required marker must exist in state-schema.md's
# authoritative table — parsed from the canonical source, never re-declared here.
if [[ -f "$SCHEMA" ]]; then
  REQ_LINE="$(grep -E "^REQUIRED_MARKERS='" "$CHAIN" | head -n1 | sed -e "s/^REQUIRED_MARKERS='//" -e "s/'.*$//")"
  if [[ -z "$REQ_LINE" ]]; then
    bad "could not parse REQUIRED_MARKERS out of $CHAIN"
  else
    ENUM="$(awk '
      /^#### Stage-comment markers/ { in_s = 1; next }
      in_s && /^#### / { in_s = 0 }
      in_s && /^### / { in_s = 0 }
      in_s && /^## / { in_s = 0 }
      in_s && /^\| `/ { line = $0; sub(/^\| `/, "", line); sub(/`.*$/, "", line); print line }
    ' "$SCHEMA")"
    missing=""
    OLD_IFS="$IFS"; IFS='|'
    # shellcheck disable=SC2206  # deliberate split on the enum delimiter
    REQ_ARR=($REQ_LINE)
    IFS="$OLD_IFS"
    for m in "${REQ_ARR[@]}"; do
      grep -qx "$m" <<< "$ENUM" || missing="$missing $m"
    done
    if [[ -z "$missing" ]]; then
      ok "every REQUIRED_MARKERS entry exists in state-schema.md's stage-comment enum"
    else
      bad "REQUIRED_MARKERS contains marker(s) absent from the canonical enum:$missing"
    fi
    [[ -n "$ENUM" ]] && ok "the canonical enum parsed non-empty (the subset check is not vacuous)" \
                     || bad "parsed an empty enum from $SCHEMA — the subset check would be vacuous"
  fi
else
  bad "state-schema.md not found at $SCHEMA — cannot verify the marker subset"
fi

echo
echo "check-pipeline-chain-selftest: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1

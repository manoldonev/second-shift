#!/usr/bin/env bash
#
# exitplan-ledger-gate-selftest.sh — behavioral coverage for the ExitPlanMode
# PreToolUse hook (hooks/exitplan-ledger-gate.sh).
#
# INVARIANT GUARDED: a plan without a well-formed Decision Ledger is BLOCKED
# (exit 2), and a plan with one is allowed (exit 0) — and the hook never exits 1.
#
# The dangerous direction is silent. Every resolution failure in this hook lands in
# warn-and-ALLOW, so a regression anywhere in the 3-tier plan-content resolution
# turns the gate permanently vacuous: it approves every plan forever, with nothing
# red anywhere to notice. That is why the allow paths below are asserted as
# deliberately as the block paths — an all-allow hook would otherwise look healthy.
#
# WHY NO SCENARIO COVERS IT (CLAUDE.md scenario-first rule): scenario-liveness-
# selftest.sh composes dev-pipeline verdict paths inside a run. This hook fires in
# the HARNESS, on the operator's ExitPlanMode tool call, before and outside any
# pipeline run — it has no statectl state, no ticket, and no stage. There is no
# verdict path to compose it onto. Its callee ledger-lint.sh has its own suite
# (ledger-lint-selftest.sh); this file covers the resolution and exit contract
# around it, which that suite cannot reach.
#
# Technique follows tools/pre-commit-typecheck-selftest.sh (fixture-driven, pure
# local, no network, no Claude CLI). The hook reads stdin unconditionally at its
# top and has no sourcing guard, so it is driven as a subprocess with a fixture
# payload rather than sourced for a predicate.
#
# bash-3.2-safe. Runs in CI via the '*-selftest.sh' discovery loop.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${EXITPLAN_LEDGER_GATE:-$SCRIPT_DIR/exitplan-ledger-gate.sh}"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

[[ -f "$HOOK" ]] || { echo "exitplan-ledger-gate-selftest: FAIL — hook not found at $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "exitplan-ledger-gate-selftest: FAIL — jq required" >&2; exit 1; }

WORK="$(mktemp -d -t exitplan-ledger-gate-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
mkdir -p "$REPO/.claude/plans"

VALID_LEDGER='# Plan

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | which index shape | partial unique index | codebase-derived |
'
# Header present, but the row carries a provenance value outside the closed enum —
# ledger-lint exits 1, so the hook must block.
INVALID_LEDGER='# Plan

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | which index shape | partial unique index | assumed |
'

# Run the hook with a payload on stdin. Extra args are env assignments.
# SECOND_SHIFT_CONFIG is scrubbed: the operator's own environment exports it, and
# an inherited value would silently retarget resolve_plans_dir mid-suite.
RC=0; OUT=""
run_hook() { # run_hook <payload> [VAR=val ...]
  local payload="$1"; shift
  OUT="$(printf '%s' "$payload" | env -u SECOND_SHIFT_CONFIG -u PLAN_INTERVIEW_SKIP \
    SECOND_SHIFT_REPO_ROOT="$REPO" "$@" bash "$HOOK" 2>&1)"
  RC=$?
}

# Every case funnels through here so the never-exit-1 contract is checked on all of
# them, not just in a dedicated case.
NEVER_ONE_VIOLATIONS=0
assert_rc() { # assert_rc <label> <want-rc> [needle]
  local label="$1" want="$2" needle="${3:-}"
  if [[ "$RC" == "1" ]]; then
    NEVER_ONE_VIOLATIONS=$((NEVER_ONE_VIOLATIONS + 1))
  fi
  if [[ "$RC" != "$want" ]]; then
    bad "$label — want rc=$want, got rc=$RC: $OUT"; return
  fi
  if [[ -n "$needle" && "$OUT" != *"$needle"* ]]; then
    bad "$label — rc ok but missing [$needle] in: $OUT"; return
  fi
  ok "$label"
}

payload_inline() { jq -n --arg p "$1" '{tool_input: {plan: $p}}'; }
payload_field()  { jq -n --arg f "$1" --arg v "$2" '{tool_input: {}} | .tool_input[$f] = $v'; }

# ---------------------------------------------------------------------------
# Tier 1 — inline plan content in tool_input.plan
# ---------------------------------------------------------------------------
run_hook "$(payload_inline "$VALID_LEDGER")"
assert_rc "(t1a) tier 1 inline valid ledger → allow" 0 "payload tool_input.plan"

run_hook "$(payload_inline "$INVALID_LEDGER")"
assert_rc "(t1b) tier 1 inline invalid ledger → BLOCK" 2 "BLOCKED"

run_hook "$(payload_inline '# Plan

Just prose, no ledger section at all.
')"
assert_rc "(t1c) tier 1 inline missing Decision Ledger → BLOCK" 2 "Decision Ledger"

# The explicit empty form is legal for trivial work — a hook that blocked it would
# make the escape valve unusable and push operators to PLAN_INTERVIEW_SKIP.
run_hook "$(payload_inline '# Plan

## Decision Ledger

No material decisions — all choices codebase-derived.
')"
assert_rc "(t1d) tier 1 explicit empty form → allow" 0 "OK"

# ---------------------------------------------------------------------------
# Tier 2 — a plan-file path in the payload. All three field names must resolve.
# ---------------------------------------------------------------------------
printf '%s' "$VALID_LEDGER"   > "$WORK/good-plan.md"
printf '%s' "$INVALID_LEDGER" > "$WORK/bad-plan.md"

for field in plan_path plan_file_path file_path; do
  run_hook "$(payload_field "$field" "$WORK/good-plan.md")"
  assert_rc "(t2-$field) tier 2 .$field valid → allow" 0 "payload .tool_input.$field"
done

run_hook "$(payload_field plan_path "$WORK/bad-plan.md")"
assert_rc "(t2b) tier 2 invalid ledger at path → BLOCK" 2 "BLOCKED"

# A path field naming a file that does not exist must fall THROUGH to tier 3, not
# resolve to nothing and allow. Here tier 3 finds no plans dir content, so the
# observable is the tier-3 warning rather than a tier-2 message.
run_hook "$(payload_field plan_path "$WORK/does-not-exist.md")"
assert_rc "(t2c) tier 2 missing file → falls through to tier 3" 0 ""
if [[ "$OUT" != *"payload .tool_input.plan_path"* ]]; then
  ok "(t2d) tier 2 missing file did not claim to have linted it"
else
  bad "(t2d) tier 2 missing file wrongly reported as linted: $OUT"
fi

# Tier 1 wins over tier 2 when both are present.
both="$(jq -n --arg p "$VALID_LEDGER" --arg f "$WORK/bad-plan.md" \
  '{tool_input: {plan: $p, plan_path: $f}}')"
run_hook "$both"
assert_rc "(t2e) tier 1 precedence — inline wins over a path field" 0 "payload tool_input.plan"

# ---------------------------------------------------------------------------
# Tier 3 — session-fresh plan files under the consumer repo's plans dir.
#
# The tier-3 candidate scan uses BSD `find -newermB` (birth time). GNU find has no
# -newermB, so on Linux the find errors, `|| true` yields zero candidates, and the
# hook warn-and-allows: tier 3 is PERMANENTLY VACUOUS there and can never lint a
# session-fresh plan. That is a real gap (#215 plan Decision Ledger D-6, deferred —
# a behavior change, not coverage). Rather than skip on Linux — which would report
# success for cases that never ran — the suite probes support and asserts the
# platform-correct contract on each. Both platforms get live assertions.
# ---------------------------------------------------------------------------
NEWERMB=0
if find "$WORK" -maxdepth 0 -newermB "$WORK" >/dev/null 2>&1; then NEWERMB=1; fi
echo "  info: find -newermB supported: $NEWERMB (0 = GNU find, tier-3 candidate scan is vacuous)"

TRANSCRIPT="$WORK/transcript.jsonl"
payload_t3() { jq -n --arg t "$TRANSCRIPT" '{transcript_path: $t, tool_input: {}}'; }

# -newermB compares BIRTH time, and `>` truncates an existing file without changing
# it. Every (re)creation below therefore deletes first — otherwise the transcript
# keeps its original birth and every plan file looks session-fresh forever.
new_transcript() { rm -f "$TRANSCRIPT"; printf '{}\n' > "$TRANSCRIPT"; }
reset_plans()    { rm -rf "$REPO/.claude/plans"; mkdir -p "$REPO/.claude/plans"; }
new_plan()       { rm -f "$REPO/.claude/plans/$1"; printf '%s' "$2" > "$REPO/.claude/plans/$1"; }

reset_plans
new_transcript

# No plans dir at all → allow with the no-plans-dir warning (platform-independent).
mv "$REPO/.claude/plans" "$REPO/.claude/plans-hidden"
run_hook "$(payload_t3)"
assert_rc "(t3a) no plans dir → allow with warning" 0 "no plans dir"
mv "$REPO/.claude/plans-hidden" "$REPO/.claude/plans"

# No transcript_path → allow (freshness cannot be anchored). Platform-independent.
run_hook "$(jq -n '{tool_input: {}}')"
assert_rc "(t3b) no transcript_path → allow with warning" 0 "no transcript_path"

# Zero session-fresh candidates: the plan is born BEFORE the transcript. A stale
# plan with a valid ledger must not be linted — "never lint a stale file silently"
# is the hook's stated contract, and a false PASS here is the vacuous-gate failure.
reset_plans
new_plan stale.md "$VALID_LEDGER"
sleep 1
new_transcript
run_hook "$(payload_t3)"
assert_rc "(t3c) no plan newer than the transcript → allow without linting" 0 "no plan file newer"

# Exactly one session-fresh candidate, invalid → lint it and BLOCK.
sleep 1
new_plan fresh.md "$INVALID_LEDGER"
run_hook "$(payload_t3)"
if [[ "$NEWERMB" == "1" ]]; then
  assert_rc "(t3d) one session-fresh plan, invalid ledger → BLOCK" 2 "BLOCKED"
else
  assert_rc "(t3d) GNU find — tier 3 degrades to allow (D-6: vacuous, cannot lint)" 0 "no plan file newer"
fi

# Exactly one session-fresh candidate, valid → allow, and say which file.
reset_plans
new_transcript
sleep 1
new_plan fresh-ok.md "$VALID_LEDGER"
run_hook "$(payload_t3)"
if [[ "$NEWERMB" == "1" ]]; then
  assert_rc "(t3e) one session-fresh plan, valid ledger → allow, names the file" 0 "session-fresh plan"
else
  assert_rc "(t3e) GNU find — tier 3 degrades to allow (D-6)" 0 "no plan file newer"
fi

# Ambiguous: two session-fresh candidates → warn-and-allow, never lint one at random.
new_plan fresh-2.md "$INVALID_LEDGER"
run_hook "$(payload_t3)"
if [[ "$NEWERMB" == "1" ]]; then
  assert_rc "(t3f) two session-fresh plans → ambiguous, allow without linting" 0 "ambiguous"
else
  assert_rc "(t3f) GNU find — tier 3 degrades to allow (D-6)" 0 "no plan file newer"
fi

# (t3h) D-6, proven on EVERY platform rather than only where GNU find happens to be
# the userland: with a `find` that rejects -newermB, the candidate scan errors, the
# `|| true` swallows it, and the hook allows — even though a session-fresh plan with
# an INVALID ledger is sitting right there. This is the vacuous-gate failure mode in
# a single case. Deferred as a behavior change (#215 D-6), pinned here as a fact.
FIND_SHIM="$WORK/find-shim"
mkdir -p "$FIND_SHIM"
for c in bash cat dirname jq mktemp basename; do
  src="$(command -v "$c")"
  [[ -n "$src" ]] && ln -sf "$src" "$FIND_SHIM/$c"
done
REAL_FIND="$(command -v find)"
cat > "$FIND_SHIM/find" <<GNUFIND
#!/usr/bin/env bash
# Stands in for GNU find, which has no -newermB (a BSD birth-time predicate).
for a in "\$@"; do
  if [[ "\$a" == "-newermB" ]]; then
    echo "find: unknown predicate \\\`-newermB'" >&2
    exit 1
  fi
done
exec "$REAL_FIND" "\$@"
GNUFIND
chmod +x "$FIND_SHIM/find"

reset_plans
new_transcript
sleep 1
new_plan fresh-invalid.md "$INVALID_LEDGER"
OUT="$(printf '%s' "$(payload_t3)" \
  | env -u SECOND_SHIFT_CONFIG -u PLAN_INTERVIEW_SKIP SECOND_SHIFT_REPO_ROOT="$REPO" \
    PATH="$FIND_SHIM:$PATH" bash "$HOOK" 2>&1)"; RC=$?
assert_rc "(t3h) no -newermB support → tier 3 allows an invalid fresh plan (D-6 vacuity)" 0 "no plan file newer"

# resolve_plans_dir honors config paths.plansDir over the .claude/plans default.
# Asserted via the absent-dir message, which is the only branch that echoes the
# resolved path — so the assertion proves WHICH dir was resolved, not just that
# some dir was scanned.
printf '{"paths":{"plansDir":"custom-plans"}}\n' > "$REPO/.claude/second-shift.config.json"
run_hook "$(payload_t3)"
assert_rc "(t3g) config paths.plansDir honored — resolves to the configured dir" 0 "custom-plans"
rm -f "$REPO/.claude/second-shift.config.json"

# ---------------------------------------------------------------------------
# Escape hatch and fail-open branches.
#
# These three all ALLOW. They are the hook's designed degradations, and they are
# exactly how a vacuous gate would look in production — so each is pinned with the
# specific reason string, not just rc=0. A regression that routed real plans into
# one of these would otherwise be invisible.
# ---------------------------------------------------------------------------

# PLAN_INTERVIEW_SKIP=1 short-circuits before any resolution — even for a plan that
# would otherwise block.
run_hook "$(payload_inline "$INVALID_LEDGER")" PLAN_INTERVIEW_SKIP=1
assert_rc "(e1) PLAN_INTERVIEW_SKIP=1 → allow without linting" 0 "PLAN_INTERVIEW_SKIP"

# ledger-lint.sh missing/non-executable → allow with a "fix the install" warning.
# Reproduced by running a copy of the hook from a directory where its
# script-relative lint path does not resolve.
ORPHAN_DIR="$WORK/orphan-hooks"
mkdir -p "$ORPHAN_DIR"
cp "$HOOK" "$ORPHAN_DIR/exitplan-ledger-gate.sh"
OUT="$(printf '%s' "$(payload_inline "$INVALID_LEDGER")" \
  | env -u SECOND_SHIFT_CONFIG -u PLAN_INTERVIEW_SKIP SECOND_SHIFT_REPO_ROOT="$REPO" \
    bash "$ORPHAN_DIR/exitplan-ledger-gate.sh" 2>&1)"; RC=$?
assert_rc "(e2) ledger-lint.sh unresolvable → allow, names the install problem" 0 "ledger-lint.sh not found"

# jq unavailable → allow. Built by putting ONLY the commands the hook needs before
# its jq probe on PATH — bash to run it, cat for the payload read, dirname for the
# script-relative lint resolution. Resolved via command -v so it is portable across
# BSD and GNU userlands (jq's own location differs by platform, so a hardcoded
# minimal PATH like /usr/bin:/bin would exclude jq on macOS but include it on Linux).
SHIM="$WORK/shim-bin"
mkdir -p "$SHIM"
for c in bash cat dirname; do
  src="$(command -v "$c")"
  [[ -n "$src" ]] && ln -sf "$src" "$SHIM/$c"
done
if command -v jq >/dev/null 2>&1 && PATH="$SHIM" command -v jq >/dev/null 2>&1; then
  bad "(e3) setup — jq is still reachable on the shim PATH; the case would be vacuous"
fi
OUT="$(printf '%s' "$(payload_inline "$INVALID_LEDGER")" \
  | env -u SECOND_SHIFT_CONFIG -u PLAN_INTERVIEW_SKIP SECOND_SHIFT_REPO_ROOT="$REPO" \
    PATH="$SHIM" bash "$HOOK" 2>&1)"; RC=$?
assert_rc "(e3) jq unavailable → allow with the jq warning" 0 "jq unavailable"

# ---------------------------------------------------------------------------
# The exit contract, aggregated over every case above.
# ---------------------------------------------------------------------------
if [[ "$NEVER_ONE_VIOLATIONS" -eq 0 ]]; then
  ok "(x1) never exit 1 — every case above returned 0 or 2"
else
  bad "(x1) never exit 1 — $NEVER_ONE_VIOLATIONS case(s) exited 1"
fi

echo "[exitplan-ledger-gate-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0

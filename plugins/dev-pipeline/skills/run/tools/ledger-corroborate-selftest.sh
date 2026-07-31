#!/usr/bin/env bash
# ledger-corroborate-selftest.sh — behavioral selftest for tools/ledger-corroborate.sh.
#
# Harness shape is predecessor-gate-selftest.sh's: a one-line helper pipes literal
# fixture JSONL into the tool and the cases assert on the emitted verdict token.
# The tool is pure logic by contract (statectl owns ledger resolution and every
# state read), so there is nothing to mock — zero network, zero git, zero state.
#
# Exit code = number of failed checks (repo selftest convention).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/ledger-corroborate.sh"
FIX="$HERE/ledger-corroborate-fixtures"

[[ -x "$TOOL" ]] || { echo "[ledger-corroborate-selftest] FATAL: $TOOL not executable"; exit 99; }
[[ -d "$FIX" ]]  || { echo "[ledger-corroborate-selftest] FATAL: $FIX missing"; exit 99; }

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# lc <fixture-basename> <args...> — run the tool over a fixture, verdict token only.
lc() {
  local f="$1"; shift
  bash "$TOOL" "$@" < "$FIX/$f" 2>/dev/null | cut -f1
}

# lc_detail <fixture-basename> <args...> — the detail half of the emitted line.
lc_detail() {
  local f="$1"; shift
  bash "$TOOL" "$@" < "$FIX/$f" 2>/dev/null | cut -f2-
}

# check <expected> <actual> <label>
check() { [[ "$2" == "$1" ]] && pass "$3" || fail "$3 → got '$2' (want '$1')"; }

echo "== ledger-corroborate.sh =="

# ---------------------------------------------------------------------------
# Skill leg — exact equality on the qualified name (AC-1)
# ---------------------------------------------------------------------------

check corroborated "$(lc main-loop.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]')" \
  "(lc1) matching main-loop Skill row corroborates (AC-1)"

check refused "$(lc main-loop.jsonl --class skill --claims '["review-toolkit:review-lead"]')" \
  "(lc2) wrong target refuses (AC-1)"

check refused "$(lc main-loop.jsonl --class skill --claims '["intake-orchestrator"]')" \
  "(lc3) bare name does not satisfy a qualified claim — exact equality, not suffix (AC-1)"

# The zero-rows arm must fire only when something was actually claimed. The two
# cases below are the pair D-14/D-15 exist to keep apart.
check refused "$(lc no-skill-rows.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]')" \
  "(lc4) zero rows of the class WITH a non-empty claim set refuses (AC-2b arm 1)"

check vacuous "$(lc no-skill-rows.jsonl --class skill --claims '[]')" \
  "(lc5) empty claim set is vacuous, never a refusal (AC-6)"

check vacuous "$(lc empty.jsonl --class skill --claims '[]')" \
  "(lc6) empty claim set on an empty ledger is still vacuous, not a refusal (AC-6)"

# ---------------------------------------------------------------------------
# The degrade arm and its ordering (AC-2b arm 2)
# ---------------------------------------------------------------------------

check degraded "$(lc all-empty-target.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]')" \
  "(lc7) >=1 row with uniformly empty target degrades (AC-2b arm 2)"

check degraded "$(lc absent-target.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]')" \
  "(lc8) an ABSENT target key degrades identically to an empty one (AC-4)"

check degraded "$(lc null-target.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]')" \
  "(lc9) a literal-null target normalizes to empty (AC-4)"

# The ordering guard. `[] | all(.target == "")` is true in jq, so a zero-row
# ledger evaluated target-first would report `degraded` — failing OPEN in exactly
# the fabricated-evidence case. lc4 asserts the token; this asserts the reason,
# so a regression that swaps the two arms cannot pass by coincidence.
got=$(lc_detail no-skill-rows.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]')
case "$got" in
  *"no admissible row"*) pass "(lc10) zero rows refuses via the ZERO-ROWS arm, not the degrade arm (AC-2b)" ;;
  *) fail "(lc10) zero-rows detail names the wrong arm → '$got'" ;;
esac

# Two-era ledger: one absent-target row and one populated row in the same file.
# The populated row must still corroborate — the degrade arm is all-or-nothing.
check corroborated "$(lc two-era.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]')" \
  "(lc11) a two-era file corroborates off its populated row (AC-4)"

# ---------------------------------------------------------------------------
# Subagent-row exclusion — main-loop legs only (AC-7)
# ---------------------------------------------------------------------------

check refused "$(lc subagent-only.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]')" \
  "(lc12) a subagent-attributed Skill row does NOT corroborate a main-loop claim (AC-7)"

check refused "$(lc subagent-only.jsonl --class stage-file --claims '["1-intake.md"]')" \
  "(lc13) a subagent-attributed Read row does NOT corroborate a main-loop claim (AC-7)"

# ---------------------------------------------------------------------------
# Stage-file leg — basename EQUALITY, path normalization, windowless (AC-4/AC-9)
# ---------------------------------------------------------------------------

check corroborated "$(lc path-roots.jsonl --class stage-file --claims '["1-intake.md"]')" \
  "(lc14) plugin-cache-rooted absolute path corroborates a bare-basename claim (AC-4)"

check corroborated "$(lc path-roots.jsonl --class stage-file --claims '["5-implement.md"]')" \
  "(lc15) worktree-rooted absolute path corroborates a bare-basename claim (AC-4)"

check corroborated "$(lc path-roots.jsonl --class stage-file --claims '["9-open-pr.md"]')" \
  "(lc16) main-checkout-rooted absolute path corroborates a bare-basename claim (AC-4)"

check corroborated "$(lc path-roots.jsonl --class stage-file --claims '["1-intake.md","5-implement.md","9-open-pr.md"]')" \
  "(lc17) every claim must match — all three together corroborate (AC-1)"

# Equality, not suffix: the fixture's only Read row is `x9-open-pr.md`.
check refused "$(lc suffix-trap.jsonl --class stage-file --claims '["9-open-pr.md"]')" \
  "(lc18) 'x9-open-pr.md' does NOT satisfy a '9-open-pr.md' claim — basename equality (AC-4)"

# The measured Stage-1 trap: the main-loop Read lands BEFORE stages.N.startedAt.
# Windowed, this refuses a run that genuinely did the work; the leg is windowless.
check corroborated "$(lc pre-started-read.jsonl --class stage-file --claims '["1-intake.md"]')" \
  "(lc19) a Read row timestamped BEFORE startedAt corroborates — the leg is windowless (AC-9)"

# Same fixture, same row, with a window imposed: proves lc19 is the windowless
# behavior rather than a fixture whose timestamps happen to fall in range.
check refused "$(lc pre-started-read.jsonl --class stage-file --claims '["1-intake.md"]' --since 2026-07-31T13:30:34Z)" \
  "(lc20) the same row IS excluded when a --since window is imposed (AC-9)"

# ---------------------------------------------------------------------------
# Windowing on the windowed legs (AC-1)
# ---------------------------------------------------------------------------

check corroborated "$(lc main-loop.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]' --since 2026-07-31T09:00:00Z)" \
  "(lc21) an in-window Skill row corroborates (AC-1)"

check refused "$(lc main-loop.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]' --since 2026-07-31T23:00:00Z)" \
  "(lc22) an out-of-window Skill row refuses (AC-1)"

# ---------------------------------------------------------------------------
# Stage-8 Workflow cardinality — both target arms (AC-1)
# ---------------------------------------------------------------------------

check corroborated "$(lc workflow-rows.jsonl --class workflow --min-count 1)" \
  "(lc23) a code-review.mjs scriptPath row satisfies one claimed round (AC-1)"

check corroborated "$(lc workflow-name-arm.jsonl --class workflow --min-count 1)" \
  "(lc24) the bare 'code-review' name fallback arm also matches (AC-1)"

check refused "$(lc workflow-rows.jsonl --class workflow --min-count 3)" \
  "(lc25) fewer rows than claimed rounds refuses (AC-1)"

check refused "$(lc workflow-wrong-script.jsonl --class workflow --min-count 1)" \
  "(lc26) an intake-review.mjs Workflow row does not satisfy a code-review claim (AC-1)"

check vacuous "$(lc workflow-rows.jsonl --class workflow --min-count 0)" \
  "(lc27) min-count 0 is vacuous — the be-fe-pair exemption shape (AC-2b)"

# ---------------------------------------------------------------------------
# SubagentStop cardinality — the carve-out (AC-7)
# ---------------------------------------------------------------------------

check corroborated "$(lc subagent-stop-named.jsonl --class subagent-stop --min-count 1)" \
  "(lc28) NAMED-subagent SubagentStop rows satisfy the cardinality leg (AC-7)"

check corroborated "$(lc subagent-stop-anon.jsonl --class subagent-stop --min-count 1)" \
  "(lc29) anonymized (empty-subagent) SubagentStop rows also satisfy it (AC-7)"

# The carve-out must not resurrect the degrade arm: every current-hook
# SubagentStop row carries `target: ""`, so a degrade arm applied here would
# downgrade every single run that dispatched reviewers.
check corroborated "$(lc subagent-stop-named.jsonl --class subagent-stop --min-count 2)" \
  "(lc30) empty targets do NOT degrade the cardinality-only leg (AC-7)"

check refused "$(lc no-skill-rows.jsonl --class subagent-stop --min-count 1)" \
  "(lc31) zero SubagentStop rows refuses when a round was claimed (AC-1)"

# A main-loop Agent call mints event:"PostToolUse", never a SubagentStop row —
# so the carve-out admits nothing a main-loop call can forge.
check refused "$(lc main-loop-agent.jsonl --class subagent-stop --min-count 1)" \
  "(lc32) a main-loop Agent PostToolUse row cannot forge a SubagentStop (AC-7)"

check vacuous "$(lc subagent-stop-named.jsonl --class subagent-stop --min-count 0)" \
  "(lc33) min-count 0 is vacuous — the be-fe-pair exemption shape (AC-2b)"

# ---------------------------------------------------------------------------
# Robustness — a torn trailing line must not make a run unverifiable
# ---------------------------------------------------------------------------

check corroborated "$(lc torn-line.jsonl --class skill --claims '["intake-toolkit:intake-orchestrator"]')" \
  "(lc34) a malformed trailing line is dropped, the good rows still corroborate (AC-8)"

# ---------------------------------------------------------------------------
# Usage errors exit non-zero — callers must distinguish a broken tool from
# missing evidence.
# ---------------------------------------------------------------------------

bash "$TOOL" --class bogus </dev/null >/dev/null 2>&1
[[ $? -ne 0 ]] && pass "(lc35) an unknown --class exits non-zero (AC-8)" \
  || fail "(lc35) an unknown --class did not exit non-zero"

bash "$TOOL" --class skill --claims 'not-json' </dev/null >/dev/null 2>&1
[[ $? -ne 0 ]] && pass "(lc36) malformed --claims exits non-zero (AC-8)" \
  || fail "(lc36) malformed --claims did not exit non-zero"

# --min-count is the third validated input and was the only one with no case at
# all — the mutation sweep found its rejection path untested (cmp-eq survivor).
# Assert the MESSAGE, not just the exit code: a rejection that does not tell the
# operator what shape was wanted is the failure mode worth pinning, and the exit
# code alone cannot distinguish it from any other usage error.
mc_err=$(bash "$TOOL" --class workflow --min-count -3 </dev/null 2>&1 >/dev/null)
mc_rc=$?
case "$mc_rc:$mc_err" in
  0:*) fail "(lc37) a negative --min-count was accepted (rc=0)" ;;
  *non-negative\ integer*) pass "(lc37) a negative --min-count is refused, naming the wanted shape (AC-8)" ;;
  *) fail "(lc37) --min-count rejection did not name the wanted shape — rc=$mc_rc err='$mc_err'" ;;
esac

# --help is a real user-facing path and was entirely untested, so nothing noticed
# when the sweep rewrote its `sed -n` extractor into `sed -z` (cmp-z survivor):
# the arm still exited 0 while printing nothing usable. Assert it emits the usage
# block, not merely that it succeeds.
help_out=$(bash "$TOOL" --help 2>/dev/null)
help_rc=$?
if [[ "$help_rc" -eq 0 && "$help_out" == *"--class skill|stage-file|workflow|subagent-stop"* ]]; then
  pass "(lc38) --help exits 0 and prints the usage block (AC-8)"
else
  fail "(lc38) --help — rc=$help_rc, $(printf '%s' "$help_out" | wc -l | tr -d ' ') line(s) emitted"
fi

echo
echo "[ledger-corroborate-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"

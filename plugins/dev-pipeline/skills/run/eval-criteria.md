# Dev Pipeline Eval Criteria

**This file is LOCKED during optimization runs. Never edit eval criteria mid-loop.**
**If the eval is wrong, stop the run, fix the eval, restart from scratch.**

These criteria are scored after each pipeline run. Each is binary: PASS or FAIL.
Pass rate = (criteria passed across all runs) / (total criteria scored).

**Runtime note:** any criterion that reasons about a run's duration must read **effective** (compute) time — `tools/stage-times.sh`'s effective total / per-stage output, which subtracts recorded `pauseSpans[]` — not the raw `lastUpdatedAt − startedAt` wall difference. A paused/resumed run (session-quota exhaustion → resume hours later) inflates wall time by the idle gap; effective time is the trustworthy signal. (No criterion below references runtime today; this is forward-looking guidance.)

Derived from real pipeline sessions in the acme repo and the hardening patterns the skill has accumulated.

---

## Criteria (5 binary)

### 1. Autonomous Pre-flight

**PASS:** Before claiming the issue (Stage 1), the run established its target — repo, base branch, issue number, and working-tree status — and the dirty-base guard behaved correctly (proceeded only on a clean **configured base branch** — the host repo's `topology.repos.<host>.baseBranch`, which may be `develop`/`alpha`, not necessarily `main` — or surfaced and handled a dirty/wrong base rather than silently building on it).

**FAIL:** The run targeted the wrong repo/branch/diff, OR proceeded on a dirty base or a base other than the configured base branch without the guard firing.

_Failure mode this catches: "wrong branch/repo/diff" — the single most common pipeline failure mode. (Scored against the autonomous pre-flight, not user confirmation: `auto` mode's no-input-prompts invariant means a correct run never waits for the user.)_

---

### 2. Plan Grounding

**PASS:** Every file path and function/class name in the implementation plan (Stage 4) exists in the current codebase, verified by grep or read. New code to be created is tagged `[NEW]`. Zero `[UNVERIFIED]` tags survive into Stage 6.

**FAIL:** The plan references a file path that does not exist, a function name that cannot be found via grep, or a module structure that does not match the actual codebase — AND the reference is not tagged `[NEW]` or `[UNVERIFIED]`.

_Failure mode this catches: hallucinated file paths and function names that cause cascading implementation failures._

---

### 3. Implementation Resilience

**PASS:** When the initial approach produces 2+ consecutive test failures on the same logical change, the pipeline stops and presents alternatives to the user (circuit breaker fires). OR: the implementation hits 1+ test failures and recovers within the per-class retry budget without tripping the breaker. (PASS requires the resilience mechanism to have been **exercised** — there was a real test failure and it was handled correctly.)

**N/A:** The diff has no executable test surface (e.g. an inert docs/shell-only change) or otherwise produced zero test failures, so the circuit breaker had no opportunity to fire. Score **N/A**, not PASS — the resilience mechanism was never exercised, and N/A is excluded from the pass-rate denominator. (This is the common case for inert-lane runs.)

**FAIL:** The pipeline iterates 3+ times on the same broken approach without stopping to reconsider, resulting in a complete rewrite or user-initiated abort.

_Failure mode this catches: "validity.badInput" class — hours wasted iterating on a fundamentally wrong approach instead of rethinking._

---

### 4. Scope Compliance

**PASS:** Every file modified during Stage 6 is either (a) listed in the plan's "Affected files/modules" section, (b) a test file for a listed module, or (c) a shared dependency explicitly flagged before commit. No unplanned files are modified without user approval.

**FAIL:** A file not in the plan is modified and committed without the user being asked, OR changes are made to files outside the GitHub issue's scope.

_Failure mode this catches: scope creep — the primary vector for unintended side effects and bloated PRs._

---

### 5. Review Precision

**PASS:** All findings rated major or blocker in Stage 8 are verified against the actual diff source. Zero false positives at major+ severity. Any unverifiable finding is marked `[UNVERIFIED]` and excluded from the blocker count.

**FAIL:** A major or blocker finding is reported that does not exist in the diff (false positive), OR a finding claims a field/function/validation is missing when it actually exists in the current codebase.

_Failure mode this catches: false positive review findings that erode trust and waste triage time._

---

## Scoring

After each pipeline run, score all 5 binary criteria. Record in `.claude/pipeline-state/{issue-number}-eval.json`:

```json
{
  "ticketKey": 42,
  "date": "2026-04-17",
  "skillVersion": "git SHA or description",
  "criteria": {
    "target_confirmation": "PASS",
    "plan_grounding": "PASS",
    "implementation_resilience": "N/A",
    "scope_compliance": "FAIL",
    "review_precision": "PASS"
  },
  "passRate": "75%",
  "notes": "Scope: modified shared types file without flagging"
}
```

The five binary criteria above are the sole inputs to the pass-rate calculation.

Use `N/A` when a criterion is not exercised (e.g., `implementation_resilience` when there are no test failures). N/A criteria are excluded from the pass rate denominator.

The eval output path (`.claude/pipeline-state/{issue-number}-eval.json`) is covered by the existing `.gitignore` entry for `.claude/pipeline-state/` — eval files are local-only and not version-controlled.

## Keep-or-Revert Threshold

When running the autoresearch optimization loop on SKILL.md:

- **Keep** a change if pass rate improves by 10+ percentage points across 3+ test runs.
- **Revert** if pass rate drops or improves by less than 10 points (noise, not signal).
- **Never** modify this eval file during a loop run.

# Intake-Orchestrator Fixture Audit

**Date:** 2026-04-19
**Auditor:** post-campaign review after round 3 KEEP at 95.0%
**Scope:** All 10 fixtures in `docs/eval-fixtures/intake-orchestrator/`
**Method:** Each fixture evaluated against (a) the current `.claude/agents/intake-orchestrator.md` Step 4 rubric, (b) the fixture's own mocks + spec on their face, (c) direct run data from the round-2-clean (50 runs) and round-3 (30 runs) evals, (d) results of the 30-run offline rescore under the post-calibration rubric.
**Result:** 1 fixture needs `expected.json` update (06). 1 fixture needs expected-field loosening (10). 8 fixtures PASS.

## Architectural change — 2026-04-29

The intake-orchestrator was converted from an agent to a skill, and the
`dependency-analyzer` sub-agent was inlined as an in-session subroutine
(no Task hop). This audit's `dep-analyzer` mock references no longer
correspond to a dispatched sub-agent — the harness's
`agents-template.json` no longer lists `dependency-analyzer` and the
canned `dep-analyzer` text in each fixture is now consumed inline (or
ignored, depending on how the harness is rewired).

**Impact on fixture 06 (`subagent-false-positive`):** the audit's
existing call-out at the per-fixture section below — that the d2
verdict implicitly tests TRUST of the dep-analyzer's hedged SOFT-dep
recommendation — still stands semantically. Under the inlined
architecture, the same trust test applies to the skill's own in-session
reasoning over the canned dep-analysis evidence rather than to a
sub-agent's output. **The rubric implications (specifically d2 vs d3
double-counting) are tracked as follow-up work outside the scope of
the agent→skill port; do not retroactively re-author rubric.py here.**

## Summary table

| # | Fixture | Status | Verdict-as-expected? | Name matches scoring? | Action |
|---|---|---|---|---|---|
| 01 | clean-bug-fix | **PASS** | yes (no-split, bug) | yes | none |
| 02 | clean-chore-config | **PASS** | yes (no-split, chore) | yes | none |
| 03 | small-feature-atomic | **PASS** | yes (no-split) | yes | none |
| 04 | mid-feature-parallel | **PASS-WITH-NOTE** | yes (sub-issues, 3) | yes | monitor for variance; no edit |
| 05 | large-feature-stacked | **PASS** | yes (stacked-prs, 3) | yes | none |
| 06 | subagent-false-positive | **FLAG / expected-update** | NO | NO (see below) | flip expected.verdict to no-split |
| 07 | threshold-breach-subissues | **PASS** | yes (escalate) | yes | none |
| 08 | threshold-breach-blockers | **PASS** | yes (escalate) | yes | none |
| 09 | resume-guard-stacked | **PASS** | yes (skip) | yes | none |
| 10 | rewrite-mislabeled-bug | **FLAG / expected-loosen** | partially | yes | accept feature OR refactor for reclassification |

## Pre-identified findings — detail

### Fixture 06 — `06-subagent-false-positive` — FLAG / expected-update

#### Evidence

- **Spec**: per-user compact/comfortable activity-card toggle, localStorage-only, explicit "no backend" and "deferred to post-auth" in Out-of-scope section. 4 files in `apps/web`, 1 module.
- **Mocks**: spec-reviewer plants 2 fake blockers (server-persistence, auth-header) that contradict the spec's explicit out-of-scope clause. codebase-explorer reports 4 files / 1 module. dep-analyzer identifies 2 work items with a **SOFT** dependency and explicit hedge ("could ship first with a hardcoded default").
- **Expected**: `verdict=sub-issues`, `count=2`.
- **Observed**: 11/11 runs across rounds 2-clean (5 runs), round-3 (3 runs), and round-3-rescored (3 runs) picked `no-split`. All 11 runs applied the prompt's counterfactual test and concluded "inherently atomic."
- **Under post-calibration rubric**: d2 0 → 1 on all 3 r3 runs (fixture lifts 70% → 80%). Rubric correctly identifies the agent's reasoning as defensible: 2 of 3 `no-split` criteria hold, while 0 of 4 `sub-issues` criteria hold.

#### Why the fixture is wrong (not the agent)

Evaluating `expected.verdict=sub-issues` against the **prompt's own Step 4 criteria**:

| sub-issues criterion | holds on fixture 06? |
|---|---|
| "distinct capabilities that don't share state" | ✗ — all 3 pieces coordinate through one `cardDensity` localStorage key |
| "dependency analysis shows independent groups" | ✗ — SOFT dep, not independent |
| "each part in a different module or bounded context" | ✗ — all in `apps/web` |
| "parts can be merged in any order" | ✗ — card-variants alone has no affordance; hook alone is dead code |

**0/4.** `sub-issues` is the wrong verdict by the prompt's own criteria.

Evaluating `no-split` (agent's actual choice):

| no-split criterion | holds? |
|---|---|
| "touches ≤3 files across ≤2 modules" | ✗ (4 files, 1 module — fails by 1 file) |
| "work is inherently atomic" | ✓ |
| "splitting would create PRs too thin to be meaningful" | ✓ |

**2/3.** Closer match than `sub-issues`.

#### Secondary finding: fixture name doesn't match rubric scoring

The fixture is named `06-subagent-false-positive`. Its d3 (sub-agent skepticism) test scores ONLY on whether the 2 spec-reviewer planted blockers are dismissed. But its d2 (decomposition verdict) test implicitly requires the agent to **TRUST** the dep-analyzer's hedged SOFT-dep parallel recommendation. That's a second, latent sub-agent trust test that:

- is not named in the fixture (name focuses on false-positive handling)
- is not listed in `planted_false_positives` (so d3 doesn't score it)
- is scored indirectly through d2 without the agent having any signal about which sub-agent to trust on what

The prompt's "Critical Principle: Sub-Agent Output Is Advisory" section explicitly tells the agent to distrust ALL sub-agent findings. A fixture that requires selective trust without signaling how is internally inconsistent.

#### Proposed fix

```diff
# 06-subagent-false-positive/expected.json
 {
   "type": "feature",
-  "verdict": "sub-issues",
-  "sub_issue_count": 2,
+  "verdict": "no-split",
+  "sub_issue_count": 0,
   "stacked_pr_count": 0,
   "escalation_reason": null,
   "pass": true,
   "planted_false_positives": [
     "Blocker: 'Preference should be server-persisted for multi-device sync'...",
     "Blocker: 'Missing auth header on the preference API call'..."
   ],
-  "gh_writes": [
-    "issue create",
-    "issue create",
-    "issue edit",
-    "issue comment"
-  ]
+  "gh_writes": [
+    "issue comment"
+  ]
 }
```

The `planted_false_positives` list stays — the d3 test (dismissing fake spec-reviewer blockers) is still the real intended test of this fixture and it works correctly.

Optional rename: `06-spec-review-false-positive` to clarify that d3 is the primary test.

#### Expected impact after fix (estimated from rescore data)

- Fixture 06: 80% → 100% in a fresh eval (agent's `no-split` verdict now matches expected).
- Overall: ~96.0% → ~97.0% (+1 pp from fixture 06 alone lifting from 8/10 → 10/10).
- No impact on other fixtures.

#### Why not apply now?

Fixture edits require rebaselining the eval before future keep-criterion comparisons are valid. Recommend applying the fix and running a fresh 50-run baseline at the start of the next intake-orchestrator campaign, not opportunistically.

### Fixture 10 — `10-rewrite-mislabeled-bug` — FLAG / expected-loosen

#### Evidence

- **Spec**: issue labeled `bug` but body explicitly says "This is NOT a bug fix. It's a rebuild of a system we never finished" (greenfield auth rewrite).
- **Expected**: `type=refactor`, `reclassified_from=bug`, `reclassified_to=refactor`.
- **Observed**: 3/3 runs in round-3 reclassified `bug` → **`feature`** (not refactor). All 3 runs scored d1=1 (adjacent-type partial credit) and landed on the correct pipeline path (escalate). All 3 scored 9/10 (the 1-pt loss is only d1).

#### Why the fixture is over-specific

The prompt's Step 1 Edge Case (line 60):

> "If a 'bug' is actually a rewrite (e.g., 'auth flow is fundamentally broken — rebuild it'), reclassify as **feature/refactor** and proceed with full analysis."

The prompt EXPLICITLY lists both `feature` and `refactor` as valid reclassifications for a rewrite. The fixture pins to one specific answer (`refactor`), but the agent's `feature` reclassification is prompt-sanctioned equivalent.

Also, the prompt's Step 1 signals table says:

| Type | Signals |
|---|---|
| Feature | "add", "new", "implement", **"build"** |
| Refactor | "refactor", "restructure", "migrate", "extract" |

The word "rebuild" contains "build" → feature signal. The issue body uses "greenfield" which is classically a feature signal too. The agent's reading is consistent with the prompt's own signal table.

#### Proposed fix (two options)

**Option A — expected.json field change:**

```diff
-  "reclassified_to": "refactor",
+  "reclassified_to": ["feature", "refactor"],
```

Requires the rubric to check list-membership instead of exact string. Small rubric code change.

**Option B — rubric text change:**

Update JUDGE_SYSTEM's d1 scoring so that when `reclassification_expected=true`, both `feature` and `refactor` outcomes earn d1=2 (not 1) as long as the agent proceeded on the correct pipeline path (which it did — escalated with needs-intake-review, matching expected.verdict).

Either option lifts fixture 10 from 90% → 100% with no change to agent behavior. Option B is more general (handles future rewrite fixtures without expected.json edits); option A is minimal.

#### Confidence

**High** that the current expected is over-specific vs the prompt's own guidance. Apply alongside fixture 06 fix at the start of the next campaign.

### Fixture 04 — `04-mid-feature-parallel` — PASS-WITH-NOTE

#### Evidence

- **Spec**: 3 new widgets + 1 grid slot edit in a single `page.tsx`. 4 files, 1 module (apps/web).
- **Expected**: `sub-issues`, count=3.
- **Observed**: Round-3 at 90% (2/3 runs perfect; 1/3 at 7/10 with d2=0, d7=0). The failing run chose `no-split` citing "3 widgets collide on page.tsx" as an argument against parallelism.
- **Under post-calibration rubric**: the failing run's d2 stayed at 0 (did not lift to 1). The judge correctly identified that fixture 04's `sub-issues` criteria actually DO hold (widgets are distinct capabilities, independent, mergeable in any order — 3/4 criteria met), so the defensibility clause doesn't trigger.

#### Why this is still a PASS

The variance is real (1/3 runs of the r3 eval genuinely reasoned wrong) but the fixture itself is internally consistent:

- Expected `sub-issues` IS the prompt-correct verdict (3/4 criteria hold).
- The failing run's "widgets collide on page.tsx" argument is weak — parallel sub-issues on independent widget files CAN coexist with small page.tsx touches (a classic merge-conflict concern, not a decomposition concern).
- The judge refusing to elevate d2 to 1 via defensibility is the right call — the agent's argument doesn't pass the bar.

This is an agent-reasoning variance issue, not a fixture issue. Worth monitoring across future campaigns but does not warrant fixture edit.

## Fixtures that PASS clean

All seven have scored ≥100% across rounds 2-clean and 3, their expected verdicts follow cleanly from the prompt's Step 4 rubric applied to the fixture spec+mocks, and the rescore produced identical scores:

### Fixture 01 — `01-clean-bug-fix`

- Bug + no-split. Unambiguous. Agent path: spec-review-only, no decomposition. 100% across all rounds.

### Fixture 02 — `02-clean-chore-config`

- Chore + no-split. Unambiguous. Scored 76% in round-2-clean due to the "non-negotiable" rigor bleed (since fixed in round 3 counterfactual reframe). 100% in round 3.

### Fixture 03 — `03-small-feature-atomic`

- Feature + no-split. 3 files, 1 module, tightly coupled. Matches no-split criteria cleanly. 100% across all rounds.

### Fixture 05 — `05-large-feature-stacked`

- Feature + stacked-prs, count=3. 4 work items consolidating naturally into 3 stacked PRs via shared `DiversityService.compute()` abstraction. Matches stacked-prs criteria (chain dependency, shared module, each part reviewable). 100% in round 3 after round-3 counterfactual rescued the round-2 regression.

### Fixture 07 — `07-threshold-breach-subissues`

- Feature + escalate (7 work items, threshold breach). Unambiguous once round-2's anti-gaming rule was added. 100% in rounds 2 + 3.

### Fixture 08 — `08-threshold-breach-blockers`

- Feature + escalate (>3 true blockers). Unambiguous escalation case. 100% in round 3.

### Fixture 09 — `09-resume-guard-stacked`

- Feature + skip-already-decomposed. Prior-intake-comment resume-guard test. 100% in round 3.

## Recommendations

1. **Apply both flagged fixture changes together** at the start of the next intake-orchestrator campaign. Do NOT apply mid-production or between rounds of the current campaign (which is already CLOSED).
2. **Rebaseline** after applying. One fresh 50-run eval at the current HEAD `9c52807` against the updated fixture set. Cost ~$39. Produces the new canonical baseline for future campaigns.
3. **Combined expected impact** if both fixes applied + judge-calibration kept:
   - Fixture 06: 70% → 100% (was 80% rescored; full recovery after expected flip)
   - Fixture 10: 90% → 100% (after `reclassified_to` loosened to accept `feature`)
   - Overall: 95.0% → ~97.5–98.0% under fully-calibrated eval
4. **No prompt change required**. The current prompt at `9c52807` is scoring correctly against its own criteria on all 10 fixtures. The remaining gaps are eval-infrastructure issues, not agent-prompt issues.

## Summary

- Agent prompt is well-calibrated: no edits recommended at HEAD `9c52807`.
- Judge calibration (applied 2026-04-19): moves overall 95.0% → 96.0% with no regressions. Stage 1 validated, Gate 3 PASS.
- Fixture audit (this document): 1 clear fixture error (06), 1 over-specific fixture field (10), 8 fixtures clean.
- Combined post-fix overall projects to ~97.5–98% against a calibrated yardstick — a ~3 pp lift from the round-3 keep number achieved through eval-infrastructure hygiene rather than prompt-tuning risk.

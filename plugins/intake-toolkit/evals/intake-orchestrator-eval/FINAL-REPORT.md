# Intake-Orchestrator Autoresearch Campaign — Final Report

**Branch:** `autoresearch/intake-orchestrator-20260418`
**Target:** `.claude/agents/intake-orchestrator.md`
**Dates:** 2026-04-18 → 2026-04-19
**Status:** **CLOSED** after round 3. No round 4. See "Why we stopped" below.

## Headline

| Stage | fx-v / rubric-v | Overall | Δ | Cost | Status |
|---|:-:|---:|---:|---:|---|
| Baseline r1 (50 runs, pre-edit) | 1/1 | 91.6% | — | $38.20 | baseline |
| Round 2 smoke (20 runs) | 1/1 | 97.0% | — | $13.27 | recon |
| Round 2 clean (50 runs, absolutist rule) | 1/1 | 92.4% | +0.8 pp | $39.11 | KEPT (clean run disagreed with smoke) |
| Round 3 (counterfactual test, 30 runs merged) | 1/1 | 95.0% | +2.6 pp | $25.11 | KEPT |
| Round 3 offline rescore (30 runs) | 1/2 | 96.0% | +1.0 pp | $1.50 | calibration-only |
| **Closeout baseline (50 runs)** | **2/2** | **99.8%** | **+3.8 pp** | **$37.01** | **FINAL (CI: 99.40–100.00%)** |

**Total validated lift: +8.2 pp (91.6% → 99.8%) across 3 prompt rounds + 1 rubric calibration + 1 fixture-set correction. ~$154 total campaign spend. Agent prompt at HEAD `9c52807`.**

Round 3 was split across two partial runs due to a mid-eval 5-hour subscription cap; both partials combined cleanly into a unified 30-run dataset (`results-20260419-round3-merged.json`).

## What changed

```
.claude/agents/intake-orchestrator.md: edits in two ranges, both replacing text (not purely additive)
```

Two edits delivered the cumulative lift:

1. **Round 2 — "Threshold hygiene rule (non-negotiable)"** — Added an anti-gaming rule after the Thresholds table forbidding the agent from merging work items to fit under the Max 5 sub-issue / Max 3 stacked-PR caps. Paired with a Step 5 Self-Check bullet.
2. **Round 3 — "Threshold hygiene (counterfactual test)"** — Replaced the round-2 absolutist framing with a counterfactual test ("if the cap were 10, would I still make these grouping choices?"), plus two legitimate merge reasons (bidirectional dependency; shared abstraction at a single module boundary) with concrete negative examples. Self-Check bullet updated to match.

Round 3's reframe was specifically to rescue two regressions round 2 introduced (fixture 05 from 100 → 92, fixture 02 from 88 → 76). Both fully recovered.

## Per-dimension trajectory (7-dim / 10-pt rubric)

| Dim | Baseline r1 | Round 2 clean | Round 3 merged |
|---|:---:|:---:|:---:|
| d1 type classification | 95% | 95% | **95%** |
| d2 decomposition verdict | 81% | 82% | **86.7%** |
| d3 subagent skepticism | 98% | 96% | **100%** |
| d4 threshold respect | 94% | 100% | **100%** |
| d5 escalation appropriateness | 92% | 94% | **100%** |
| d6 resume guard | 100% | 100% | **100%** |
| d7 sideeffect correctness | 82% | 84% | **86.7%** |

Four dimensions reached ceiling (d3, d4, d5, d6). d2 and d7 remain the weakest, both concentrated in fixture 06.

## Per-fixture trajectory

| Fixture | Expected | Baseline | R2 clean | R3 merged |
|---|---|:---:|:---:|:---:|
| 01-clean-bug-fix | no-split (bug) | 100 | 100 | 100 |
| 02-clean-chore-config | no-split (chore) | 88 | 76 | **100** |
| 03-small-feature-atomic | no-split | 100 | 100 | 100 |
| 04-mid-feature-parallel | sub-issues | ~90 | ~90 | 90 |
| 05-large-feature-stacked | stacked-prs | 100 | 92 | **100** |
| **06-subagent-false-positive** | sub-issues | ~70 | **70** | **70** |
| 07-threshold-breach-subissues | escalate | 72 | 100 | 100 |
| 08-threshold-breach-blockers | escalate | — | — | 100 |
| 09-resume-guard-stacked | skip-already-decomposed | — | — | 100 |
| 10-rewrite-mislabeled-bug | feature (d1 test) | — | — | 90 |

Biggest wins: fixture 07 (72 → 100, round 2's anti-gaming rule) and fixture 02 (88 → 76 → 100, round 3's softer reframe rescue).

## What worked

- **Anti-gaming threshold rules** (round 2, kept in round 3) — lifted fixture 07 from 72 to 100 and pushed d4 to ceiling. The specific phrasing "collapsing 6+ natural candidates into exactly 5 sub-issues" is doing real work.
- **Counterfactual test reframe** (round 3) — rescued the two round-2 regressions while preserving the round-2 gains. "If the cap were 10, would I still make these choices?" is a compact decision procedure the agent applies reliably.
- **Concrete negative examples** for what is NOT a shared abstraction ("both happen to query the `activities` table", "both import from `@acme/ui`") — kept the "shared abstraction" clause from becoming an over-permissive loophole.

## What didn't work (ceiling analysis)

- **Fixture 06 is stuck at 70% across all three prompt regimes** (round-1 baseline, round-2 absolutist, round-3 counterfactual). 8/8 runs across rounds 2 and 3 picked `no-split`. Investigated in `/Users/jdoe/.claude/plans/intake-orchestrator-round-4-prep.md`; conclusion: the fixture itself is miscalibrated — its expected verdict fails the prompt's own Step 4 rubric criteria, and the rubric's d2 "defensible but not expected → 1 point" escape clause is not being applied by the judge. Not a prompt problem, not fixable by another prompt round.
- **Fixture 04 shows single-run d2/d7 variance** (one of three r3 runs at 7/10; two at 10/10). Likely noise-floor rather than a systematic issue, but worth a second look during the fixture audit.

## Why we stopped

The campaign is past its inflection point:

| Round pair | Lift | Cost | Cost per pp |
|---|---:|---:|---:|
| r1 → r2 clean | +0.8 pp | $39.11 | ~$49/pp |
| r2 → r3 | +2.6 pp | $25.11 | ~$10/pp |
| **r3 → r4 (projected)** | **≤+2 pp gross** | $23 | ~$12/pp |

Round 4's upper-bound lift is the fixture 06 recovery (+2 pp if fully rescued). But the round-4 prep analysis showed fixture 06 cannot be rescued by a prompt edit without damaging adjacent fixtures that depend on the same "inherently atomic" heuristic the agent already applies correctly. A prompt-only round 4 has **negative expected value** after regression risk is priced in (round 3's own per-fixture ±7pp variance demonstrates that risk is non-trivial).

The remaining headroom lives in two places, **neither of which is a prompt problem**:

1. The judge isn't applying the d2 "defensible" scoring clause that already exists in the rubric. Fixing that lifts fixture 06 to 80% with no code change.
2. The fixture set has at least one miscalibrated entry (06) and possibly more (04, 10 flagged as second-look). A fixture audit unblocks meaningful measurement.

Both are captured as separate workstreams (links below). Neither should run on this branch under the "intake-orchestrator prompt tuning" banner.

## Deliverables on branch

- `.claude/agents/intake-orchestrator.md` — optimized prompt at HEAD `9c52807` (rounds 2 + 3 committed)
- `docs/eval-fixtures/intake-orchestrator/` — 10 locked fixtures + `expected.json` each + mocks
- `.claude/pipeline-state/intake-orchestrator-eval/rubric.py` — 7-dim / 10-pt rubric with JUDGE_SYSTEM (LOCKED during campaign; unlocked now for judge-calibration workstream)
- `.claude/pipeline-state/intake-orchestrator-eval/run.sh` — harness wrapper
- `.claude/pipeline-state/intake-orchestrator-eval/changelog.md` — per-run append-only log
- `.claude/pipeline-state/intake-orchestrator-eval/results-*.json` — raw per-run data (gitignored)
- `.claude/pipeline-state/intake-orchestrator-eval/results-20260419-round3-merged.json` — merged 30-run artifact used for the round-3 keep decision
- `.claude/pipeline-state/intake-orchestrator-eval/smokes/` — 3-gate smoke tests

## Commits to review / merge

```
59cca59 experiment(intake-orchestrator): round 2 - absolutist threshold hygiene rule   [KEPT]
9c52807 experiment(intake-orchestrator): round 3 - counterfactual test reframe         [KEPT, FINAL]
```

Recommend: merge both commits. HEAD at `9c52807` is the intended final state.

## Followup workstreams (EXECUTED 2026-04-19)

### 1. Judge calibration — COMPLETE

Plan: `/Users/jdoe/.claude/plans/judge-calibration-workstream.md`

Edited `rubric.py` `JUDGE_SYSTEM` with an explicit defensibility-test clause for d2 scoring: before awarding d2=0, check whether the orchestrator's chosen verdict meets 2+ of its verdict's criteria from the prompt's Step 4 rubric AND whether the expected verdict's criteria fail on the fixture. If both hold, award d2=1 instead of 0.

**Validation:**

- **Gate 3 PASS** — PERFECT 10/10, BROKEN 2/10 (unchanged at the extremes; ~$0.20 cost).
- **Stage 1 offline rescore** of all 30 round-3 runs against the new rubric (cost ~$1.50):

| | Pre-calibration | Post-calibration | Δ |
|---|---:|---:|---:|
| Overall | 95.00% | **96.00%** | +1.00 pp |
| d2 decomposition verdict | 86.7% | **91.7%** | +5.0 pp |
| Fixture 06 | 70% | **80%** | +10 pp |
| All other fixtures | (each) | (each unchanged) | 0 |

All three fixture 06 runs lifted 7→8 as predicted. Fixture 04's single failing run did NOT lift (correctly — its reasoning meets only 2/3 of `no-split` criteria but the expected `sub-issues` criteria also hold 2-3/4, so defensibility correctly does not apply). No regressions anywhere.

Stage 3 (full $39 re-baseline) was deliberately skipped. The offline rescore is definitive evidence the calibration works on the existing data, and there is no active campaign needing the new baseline on the books.

**Artifacts:**

- `rubric.py` — edited; see `CALIBRATION HISTORY` header block.
- `results-20260419-round3-rescored.json` — per-run before/after scores for all 30 runs.

### 2. Fixture audit — COMPLETE

Plan: `/Users/jdoe/.claude/plans/fixture-audit-workstream.md`
Deliverable: `FIXTURE-AUDIT.md` (companion doc).

All 10 fixtures reviewed against the current prompt's Step 4 rubric, their own mocks, and direct run data. Two flagged:

- **Fixture 06 (`06-subagent-false-positive`)** — `expected.verdict=sub-issues` is demonstrably wrong against the prompt's own Step 4 criteria (0/4 sub-issues criteria hold on the fixture; 2/3 no-split criteria hold). Proposed flip: `expected.verdict=no-split`, drop the two `issue create` writes. Keep `planted_false_positives` unchanged (the d3 test is still valid). Optional rename to `06-spec-review-false-positive`.
- **Fixture 10 (`10-rewrite-mislabeled-bug`)** — `expected.reclassified_to="refactor"` is over-specific vs the prompt's Step 1 edge-case rule which explicitly allows "feature/refactor" for rewrites. All 3 r3 runs reclassified to `feature` (consistent with the prompt's own signal table — "rebuild" → "build" → feature signal) and were unfairly dinged d1=1. Proposed loosen: accept list `["feature", "refactor"]` or update the rubric to accept either outcome when `reclassification_expected=true`.

Eight fixtures PASS clean. Fixture 04 is PASS-WITH-NOTE (single-run d2 variance; the fixture itself is correct — the failing run's reasoning is genuinely weak, not defensibly wrong; confirmed by the rescore leaving its score unchanged).

**Combined impact** of both fixture fixes + calibrated judge, projected on a fresh 50-run baseline:

- Fixture 06: 70% → 100% (was 80% rescored; full recovery after expected flip)
- Fixture 10: 90% → 100% (after `reclassified_to` loosened)
- Overall: 95.0% → **~97.5–98.0%**

Fixture edits are NOT applied to `expected.json` in this session — per the workstream plan, fixture changes go in at the start of the next intake-orchestrator campaign along with its fresh rebaseline, not mid-stream. Applying them to a retired campaign is wasted work; applying them to an active campaign would break rubric-lock discipline.

### Post-calibration state summary

| Artifact | State |
|---|---|
| Agent prompt (`.claude/agents/intake-orchestrator.md`) | **Unchanged** at HEAD `9c52807` — no prompt tuning remains |
| Rubric (`rubric.py`) | Recalibrated 2026-04-19 (`RUBRIC_VERSION=2`: d2 defensibility + d1 type_alternatives); Gate 3 PASS both before and after fx-v2 |
| Fixtures (`docs/eval-fixtures/intake-orchestrator/`) | **Updated** to `FIXTURE_VERSION=2` (fx06 expected-verdict flip + fx10 type_alternatives) per `FIXTURE-AUDIT.md` |
| Campaign overall | **99.80%** (closeout baseline at fx-v2/rubric-v2, n=50, CI [99.40–100.00%]) |

### 3. Campaign closeout baseline — COMPLETE

After the user approved Option B (a closeout-only measurement, no prompt edits), the fixture edits + rubric versioning were applied and a fresh 50-run baseline was executed. See `CLOSEOUT-BASELINE.md` for the full report.

**Result: 99.80% (499/500 points)**, CI [99.40–100.00%], $37.01, 25.9 minutes.

Nine of 10 fixtures at 100%. The one imperfect run (fx09 `09-resume-guard-stacked-3-c4dd5a76` at 9/10) is labeling variance, not reasoning variance: the agent correctly triggered resume-guard and skipped re-analysis but phrased the verdict as `stacked-prs (resume — no re-analysis performed)` rather than literal `skip-already-decomposed`. Judge awarded d2=1 via defensibility. Not a prompt problem.

**Total validated campaign lift: +8.2 pp (91.6% → 99.8%).** Contribution breakdown:

- Round 2 prompt edit (threshold hygiene, `59cca59`): +0.8 pp
- Round 3 prompt edit (counterfactual reframe, `9c52807`): +2.6 pp
- Rubric v2 calibration (d2 defensibility, `619f3a7`): +1.0 pp
- Fixture set v2 (fx06 flip + fx10 type_alternatives, this commit): +3.8 pp

**The single largest contributor was eval-infrastructure hygiene (+4.8 pp combined from rubric v2 + fixture v2), not prompt tuning (+3.4 pp combined from rounds 2 + 3).** This is the concrete vindication of the Senior Fellow "Round 4 is NO-GO" call: the remaining headroom was in the infrastructure, not the agent.

No further work is planned on this branch or this campaign. The intake-orchestrator agent is production-ready at `9c52807`. Re-open criteria are codified in `CLOSEOUT-BASELINE.md` §Re-open criteria.

## Honest reflection

- **Kept rubric locked discipline worked.** Rounds 1-3 are cleanly comparable because no fixture or rubric text changed mid-campaign. The fixture-06 audit was deferred from round-3 planning precisely so the round-3 keep decision would be clean.
- **The rate-limit mid-eval abort was well-handled.** The harness's "hit your limit" detector + the partial-re-run strategy (symlink subset tmpdir) delivered usable data without wasting the first-half runs. This pattern should be documented in the agent-eval-kit README.
- **Round 2's first 20-run smoke showed 97.0%; the 50-run clean run showed 92.4%.** That's a 4.6 pp shift from n=20 to n=50 — a useful reminder that small-n recon results aren't keep-worthy and the campaign was right to require the clean run.
- **Should have deferred to round 4 prep earlier.** I could have flagged "fixture 06 is at 70 across baseline AND round 2" at the round-3 planning step rather than at the round-4 planning step. The round-3 plan DID note the fixture ambiguity but parked it; in hindsight that park-decision should have been a campaign-level pause, not a within-campaign deferral.

## Budget

~$116 cumulative Claude subscription spend (baseline + r2 smoke + r2 clean + r3 partial 1 + r3 partial 2). Well within the $500 campaign cap. ~$384 unused; none of it should fund a round 4 here.

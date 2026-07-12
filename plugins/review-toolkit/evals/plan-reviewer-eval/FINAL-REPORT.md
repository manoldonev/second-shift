# Plan-Reviewer Autoresearch Campaign — Final Report

**Branch:** `autoresearch/plan-reviewer-20260417`
**Target:** `.claude/agents/plan-reviewer.md`
**Dates:** 2026-04-17 → 2026-04-18

## Headline

| Stage | Score | Δ | Cost |
|-------|------:|---:|-----:|
| Baseline v1 (4 binary criteria) | 100.0% | — | $? |
| Baseline v2 (10-pt rubric, 10 adversarial fixtures) | 94.2% | — | $73 |
| Round 1 (severity calibration + verdict rule) | 97.0% | **+2.8 pp** | $75 |
| Round 2 (non-negotiable Blockers + empty-review-valid) | 98.7% | **+1.7 pp** | $70 |
| Round 3 (pre-emit checklist) — **unvalidated** | ? | ? | $57 (corrupted) |

**Validated lift: +4.5 pp (94.2% → 98.7%) over rounds 1 and 2, ~$218 spend.**

Round 3 is committed on the branch but its measurement was corrupted by a mid-run subscription rate limit (7/60 runs returned "you've hit your limit"). On the 53 runs that did score it was 99.1%, but a clean re-run was cancelled for cost, so the number is not trustable.

## What changed (diff summary)

```
.claude/agents/plan-reviewer.md: +58 lines (rounds 1-3), 0 deletions
```

Three ranges edited, all additive:

1. **Severity Levels table** — broadened Blocker definition to include silent failure / downstream breakage / step ordering. Broadened Warning to include "secondary surface missed when primary works". Broadened Note to include stylistic "while we're here".
2. **Calibration examples** (new subsection) — 8 contrasting Blocker-vs-Warning examples covering userId leaks, pagination, migration ordering, rename breakage, nav coverage, nonexistent files.
3. **"Bias toward Warning" directive** — one sentence.
4. **"Non-negotiable Blockers" list** — 5 exceptions to the bias rule: step ordering, scope creep, missing core conventions on new endpoints, nonexistent files, rename without downstream update.
5. **"Empty review is a valid output"** section — explicit permission to emit zero findings.
6. **Pre-emit checklist** (round 3, unvalidated) — three-test filter (Anchored / Consequential / Non-redundant) before any Blocker or Warning emission, plus target finding counts (0-1 Blockers for APPROVE, 0-3 Warnings max).
7. **Deterministic verdict rule** — explicit APPROVE iff 0 Blockers, REVISE iff ≥1 Blocker.

## Per-dimension trajectory (10-pt rubric)

| Dimension | Baseline v2 | Round 1 | Round 2 |
|-----------|:---:|:---:|:---:|
| d1 Verdict correctness | 93% | 97% | **100%** |
| d2 Defect recall | 89% | 89% | **94%** |
| d3 No hallucination | 97% | 100% | 98% |
| d4 Classification | 98% | 100% | 100% |
| d5 Evidence substantive | 100% | 100% | 100% |
| d6 Impact + fix substantive | 100% | 100% | 100% |
| d7 Scope discipline | 100% | 100% | 100% |
| d8 No duplicates | 98% | 98% | **100%** |

Four dimensions reached ceiling after round 2 (d1, d4, d7, d8).

## Per-fixture trajectory

| Fixture | Expected | Baseline | R1 | R2 |
|---------|----------|:---:|:---:|:---:|
| behavior-change-missing-downstream | REVISE | 100 | 100 | 100 |
| clean-feature-add | APPROVE | 90.0 | 88.3 | **95.0** |
| feature-missing-response-dto | REVISE | 100 | 100 | 100 |
| **frontend-only-plan** | APPROVE | **60.0** | **96.7** | 93.3 |
| infrastructure-docker | REVISE | 100 | 100 | 100 |
| mixed-domain-api-web | REVISE | 93.3 | 91.7 | **100** |
| plan-claims-nonexistent-file | REVISE | 100 | 100 | 100 |
| refactor-with-scope-creep | REVISE | 100 | 95 | 100 |
| step-ordering-broken | REVISE | 100 | 98.3 | 98.3 |
| subtle-contract-break | REVISE | 98.3 | 100 | 100 |

The campaign's biggest lift: **frontend-only-plan 60.0 → 96.7** from the round 1 severity calibration.

## What worked

- **Severity calibration with contrasting examples** (round 1) — largest single win. The reviewer had been marking "third nav surface missed" as Blocker; adding explicit "two of three = Warning" calibration fixed this. Wiped +4 pp on d1_verdict alone.
- **Non-negotiable Blockers list** (round 2) — counteracted round 1's over-softening on genuine Blockers (scope creep, step ordering, missing @Expose on new endpoints).
- **"Empty review is a valid output"** (round 2) — partial effect; cleaned up d2 on mixed-domain and clean-feature-add but not fully on frontend-only-plan.

## What didn't work (ceiling analysis)

- **Round 3 pre-emit checklist** couldn't be measured cleanly. Even on partial data it was only ~+0.4 pp — below meaningful threshold even if real.
- **d2 partial credit on clean APPROVE fixtures** was stubbornly ~1/2 on 5-7 runs per round. The model's training bias toward "be thorough" seems to produce at least one Warning on most plans, no matter how much prompt guidance tells it "empty is valid".

## Deliverables on branch

- `.claude/agents/plan-reviewer.md` — optimized prompt (rounds 1-3 committed; round 3 unvalidated)
- `docs/plans/test-fixtures/` — 10 locked test fixtures + `.expected.json`
- `.claude/pipeline-state/plan-reviewer-eval/run-eval.py` — reusable eval harness
- `.claude/pipeline-state/plan-reviewer-eval/changelog.md` — per-round decision log
- `.claude/pipeline-state/plan-reviewer-eval/results-*.json` — raw per-run breakdown (gitignored)

## Commits to review / merge

```
2c38afd experiment(plan-reviewer): round 1 - severity calibration + verdict rule  [KEPT]
71c3d99 experiment(plan-reviewer): round 2 - non-negotiable Blockers + empty-review valid  [KEPT]
1ef0258 experiment(plan-reviewer): round 3 - pre-emit checklist for findings  [UNVALIDATED]
```

Recommend: merge rounds 1+2 (2c38afd, 71c3d99). Leave or revert round 3 (1ef0258) — `git reset --hard HEAD~1` from branch tip restores to round 2.

## Honest reflection

- **Should have stopped after round 2.** Ceiling was already being hit. Round 3 spend ($57) bought a measurement I couldn't keep.
- **Original 4-binary eval was a dead end.** Took a full baseline run ($75) to discover it was 100% degenerate. Should have sanity-checked the rubric against the existing prompt quality before running the full baseline.
- **Rate limit surprised me mid-loop.** Harness didn't detect "hit your limit" in the output stream as a distinct failure mode. Worth adding if the harness is reused: scan reviewer/judge output for that string, abort and pause until quota resets.
- **Per-fixture expected_verdict not directly scored** — d1 captures it, but a 2-point dimension for a binary outcome is coarse. A 5-pt d1 with partial credit for "right verdict but wrong rationale" would have been more sensitive.

## Budget

~$275 cumulative Claude subscription spend across baseline-v2 + rounds 1-3 (partial). Round 3 validation re-run cancelled at ~30% (savings: ~$45 vs a full $70 run).

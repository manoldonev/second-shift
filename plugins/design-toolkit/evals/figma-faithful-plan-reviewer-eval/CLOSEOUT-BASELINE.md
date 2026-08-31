# `figma-faithful-plan-reviewer` — pre-edit baseline

**This is a BASELINE, not a closeout.** #704 built the instrument and took the first reading. The
keep-or-revert campaign that acts on it is **#707**, and nothing here has been tuned.

**Date:** 2026-08-30
**Branch:** `claude/second-shift-704`
**Campaign status:** OPEN — baseline only. No prompt change has been applied to this agent.

## Headline

| Measurement | Value |
| --- | ---: |
| **Overall score** | **99.17%** (119/120 points) |
| **n** | 12 runs (3 per fixture × 4 fixtures) |
| **Reviewer cost** | $4.24 (reviewer only; $5.36 including the judge) |
| **Wall clock** | 11.8 minutes (concurrency 2) |
| **Agent prompt SHA** | `6dd9f70` — last commit touching `agents/figma-faithful-plan-reviewer.md` |
| **Fixture set version** | v1 (`FIXTURE_VERSION` in `rubric.py`) |
| **Rubric version** | v1 (`RUBRIC_VERSION` in `rubric.py`) |

## Per-fixture

| # | Fixture | Expected | Score | Verdict correct |
| --- | --- | --- | ---: | --- |
| 01 | `missing-dimension-rows` | `block` | **100.0%** | 3/3 |
| 02 | `name-match-resolution` | `block` | **100.0%** | 3/3 |
| 03 | `spacing-arithmetic` | `block` | **96.7%** | 3/3 |
| 04 | `control-clean` | `pass` | **100.0%** | 3/3 |

## Per-dimension

| Dimension | Score | Notes |
| --- | ---: | --- |
| `d1_verdict_correctness` | **100%** (72/72) | every run called every fixture correctly |
| `d2_finding_grounding` | **100%** (24/24) | every planted defect named and anchored |
| `d3_no_fabrication` | **95.8%** (23/24) | one over-reach, below |

## The one imperfect run (for the record)

Fixture 03 run 3 scored 9/10. It found all three planted defects — both `16px → rowGap={2}`
arithmetic rows and the raw-`px` sizing row on the branded surface — and then added a fourth
Warning claiming the plan's Layout-context sentence contradicts its file list about who owns the
header block. The judge scored that as unsupported: the token table's own inter-block rows show
the header, form, upload and footer blocks are siblings inside the single form column, so there is
no contradiction to find.

That is one over-reach in twelve runs, on a dimension already at 95.8%. It is model variance, not
a prompt gap.

## Reading this number

**99.17% is a ceiling result, and it is the interesting one.** The three defect fixtures encode
#692's observed failures — a control-bearing screen with an empty `dimensions` table, a
`why this component` cell that restates the layer name, and token arithmetic that halves a 16px
gap — and the agent caught every one, 3/3, first try.

That is evidence the agent's checklist is right and that #692's failure was **dispatch**, not
capability: at the time this baseline was cut, the reviewer was "dispatched by the OPERATOR at
`figma-faithful` step 7" and by nothing else. An agent that scores 99% on the defects that
shipped, and does not run on the lane where they shipped, is a routing problem — which was #705's
subject, not this ticket's. #705 closed it: the lean lane's build session dispatches this agent at
milestone 3 and commits its verdict for the gate to assert. **The number above is unaffected** —
it measures the agent against fixtures, not the lane that reaches it.

**A ceiling result is also a weak comparator.** With 0.83 percentage points of headroom, this eval
cannot show a +10pp improvement for any prompt change #707 might make; the most it can show is a
regression. #707 should treat this set as a **guard** for this agent, and put its tuning effort
where the headroom is (the spec reviewer, at 64%).

## Provenance

- **Agent prompt:** `plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md` @ `6dd9f70`.
- **What actually ran:** the INSTALLED plugin, `design-toolkit@second-shift` **4.0.3**, because
  `claude -p --agent` resolves a plugin agent from the installed cache and not from the branch.
  Verified byte-identical to the branch before the run:
  `diff plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md ~/.claude/plugins/cache/second-shift/design-toolkit/4.0.3/agents/figma-faithful-plan-reviewer.md` → no output.
  This agent is not modified by #704, so cache and branch still agree at merge.
- **Rubric:** `rubric.py` @ `RUBRIC_VERSION = 1`, committed alongside this report.
- **Fixtures:** `fixtures/` @ `FIXTURE_VERSION = 1`, committed alongside this report.
- **Harness:** `plugins/review-toolkit/evals/agent-eval-kit/run-eval.py` @ `808aa29`.
- **Repo state at run time:** `fee85c8` (recorded as `sha=` in `changelog.md`).
- **Raw results:** `results-20260830T144141Z.json` (gitignored).

### Exact invocation

```
cd plugins/design-toolkit/evals/figma-faithful-plan-reviewer-eval
REVIEWER_MODEL=<pin> JUDGE_MODEL=<pin> ./run.sh "704-baseline-pre-ac4"
```

The model pins are recorded in the `changelog.md` row for this run — that is where they belong,
and `scripts/check-eval-model-identity.sh` requires they not appear in the runnable surface.
Defaults applied: `--runs-per-fixture 3 --concurrency 2 --effort high`.

## Reproducibility checklist

- [x] Deterministic rubric module (`rubric.py` @ v1, no hidden state)
- [x] Deterministic, committed fixture set (`fixtures/` @ v1, nothing gitignored feeds the reviewer)
- [x] Version constants in `rubric.py` (`FIXTURE_VERSION`, `RUBRIC_VERSION`)
- [x] Changelog row written, carrying the reviewer model
- [x] Smoke run passed before the full run
- [x] Installed-plugin prompt verified identical to the branch prompt
- [ ] LLM determinism: **No** — the reviewer is stochastic at high effort. n=3 per fixture is the
      smallest sample the +10pp/3-run rule can consume, and it is a floor, not a comfortable one:
      the single 9/10 above is 1/12 of the corpus.

## What #707 inherits

- This baseline, at fixture-set v1 / rubric v1, `6dd9f70`.
- The observation that headroom here is 0.83pp, so a keep-or-revert decision on this agent will be
  decided by the regression side of the rule, not the improvement side.

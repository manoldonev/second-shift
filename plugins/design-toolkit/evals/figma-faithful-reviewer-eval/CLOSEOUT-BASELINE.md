# `figma-faithful-reviewer` — pre-edit baseline

**This is a BASELINE, not a closeout.** #704 built the instrument and took the first reading. The
keep-or-revert campaign that acts on it is **#707**, and nothing here has been tuned.

**Date:** 2026-08-30
**Branch:** `claude/second-shift-704`
**Campaign status:** OPEN — baseline only. No prompt change has been applied to this agent.

## Headline

| Measurement | Value |
| --- | ---: |
| **Overall score** | **100.00%** (120/120 points) |
| **n** | 12 runs (3 per fixture × 4 fixtures) |
| **Reviewer cost** | $2.33 (reviewer only; $3.31 including the judge) |
| **Wall clock** | 10.2 minutes (concurrency 2) |
| **Agent prompt SHA** | `6dd9f70` — last commit touching `agents/figma-faithful-reviewer.md` |
| **Fixture set version** | v1 (`FIXTURE_VERSION` in `rubric.py`) |
| **Rubric version** | v1 (`RUBRIC_VERSION` in `rubric.py`) |

## Per-fixture

| # | Fixture | Expected | Score | Verdict correct |
| --- | --- | --- | ---: | --- |
| 01 | `branded-raw-literals` | `revise` | **100.0%** | 3/3 |
| 02 | `hand-rolled-primitive` | `revise` | **100.0%** | 3/3 |
| 03 | `physical-style-props` | `revise` | **100.0%** | 3/3 |
| 04 | `control-clean` | `approve` | **100.0%** | 3/3 |

## Per-dimension

| Dimension | Score | Notes |
| --- | ---: | --- |
| `d1_verdict_correctness` | **100%** (72/72) | — |
| `d2_finding_grounding` | **100%** (24/24) | — |
| `d3_no_fabrication` | **100%** (24/24) | zero false positives on the clean control, 3/3 |

## Reading this number

**A clean sweep is a statement about the fixtures as much as the agent.** Two things are worth
saying plainly rather than being read into the 100%.

**What it does establish.** The two-surface distinction the synthetic reference exists to encode
is being applied, not guessed: the agent flagged raw `px` and hardcoded `rem` sizing on the
storefront (branded) fixture and did **not** flag the `theme.typography.pxToRem(180)` call in the
same file, which is the abstraction the branded rules require. It also held its stated "bias
toward passing" calibration across all three control runs, against four planted near-misses — an
off-scale `px` that IS correctly named-and-commented, a bare `'1px solid'` hairline with no
matching token, a logical prop taking a string, and layout containers. That calibration surviving
3/3 is the result this fixture was built to produce, and it is the one #707 must not destroy.

**What it does not establish.** These fixtures are drawn from the agent's own checklist (#704
pre-flight D-5), so they test whether it applies rules it already holds — not whether the rule set
is complete. #692's actual failure was a control shipped at roughly twice its design width, and
**no fixture here could have caught that**, because this agent is explicitly blind to it: "you
never assert 'this doesn't match the mock'". A 100% here is fully consistent with the #692 defect
shipping again.

**A ceiling result is a weak comparator**, with zero headroom for a +10pp improvement. #707 should
treat this set as a **regression guard** for this agent and spend its tuning budget where the
headroom is (the spec reviewer, at 64%).

## Provenance

- **Agent prompt:** `plugins/design-toolkit/agents/figma-faithful-reviewer.md` @ `6dd9f70`.
- **What actually ran:** the INSTALLED plugin, `design-toolkit@second-shift` **4.0.3**, because
  `claude -p --agent` resolves a plugin agent from the installed cache and not from the branch.
  Verified byte-identical to the branch before the run:
  `diff plugins/design-toolkit/agents/figma-faithful-reviewer.md ~/.claude/plugins/cache/second-shift/design-toolkit/4.0.3/agents/figma-faithful-reviewer.md` → no output.
  This agent is not modified by #704, so cache and branch still agree at merge.
- **Rubric:** `rubric.py` @ `RUBRIC_VERSION = 1`, committed alongside this report.
- **Fixtures:** `fixtures/` @ `FIXTURE_VERSION = 1`, committed alongside this report, including the
  synthetic design-system reference under `fixtures/design-tokens/` and the greppable component
  export stubs under `fixtures/app/`.
- **Harness:** `plugins/review-toolkit/evals/agent-eval-kit/run-eval.py` @ `808aa29`.
- **Repo state at run time:** `fee85c8` (recorded as `sha=` in `changelog.md`).
- **Raw results:** `results-20260830T144141Z.json` (gitignored).

### Exact invocation

```
cd plugins/design-toolkit/evals/figma-faithful-reviewer-eval
REVIEWER_MODEL=<pin> JUDGE_MODEL=<pin> ./run.sh "704-baseline-pre-ac4"
```

The model pins are recorded in the `changelog.md` row for this run — that is where they belong,
and `scripts/check-eval-model-identity.sh` requires they not appear in the runnable surface. This
agent declares `model: sonnet` in its own frontmatter, and the run used a Sonnet-tier pin to match
what production dispatches; the other two evals used an Opus-tier pin for the same reason.
Defaults applied: `--runs-per-fixture 3 --concurrency 2 --effort high`.

## Reproducibility checklist

- [x] Deterministic rubric module (`rubric.py` @ v1, no hidden state)
- [x] Deterministic, committed fixture set (`fixtures/` @ v1, nothing gitignored feeds the reviewer)
- [x] Version constants in `rubric.py` (`FIXTURE_VERSION`, `RUBRIC_VERSION`)
- [x] Changelog row written, carrying the reviewer model
- [x] Smoke run passed before the full run
- [x] Installed-plugin prompt verified identical to the branch prompt
- [ ] LLM determinism: **No** — the reviewer is stochastic at high effort. n=3 per fixture is the
      smallest sample the +10pp/3-run rule can consume. A 12/12 clean sweep at n=3 does not
      establish that the true rate is 100%.

## What #707 inherits

- This baseline, at fixture-set v1 / rubric v1, `6dd9f70`.
- Zero headroom, so a keep-or-revert decision on this agent is decided entirely by the regression
  side of the rule.
- The open question this eval cannot answer: whether the rule SET is complete. Widening it is a
  fixture-authoring job, and #707 puts fixture changes explicitly out of scope — so that is a
  third ticket, not a mid-campaign edit.

# `figma-faithful-spec-reviewer` — pre-edit baseline

**This is a BASELINE, not a closeout.** #704 built the instrument and took the first reading. The
keep-or-revert campaign that acts on it is **#707**, and nothing here has been tuned.

**Date:** 2026-08-30
**Branch:** `claude/second-shift-704`
**Campaign status:** OPEN — baseline only. The AC-4 prompt edit lands in #704 **after** this
measurement and is therefore an **unmeasured delta** at #707's start. Re-measuring it is #707's
first act, not an assumption anyone may make from this file.

## Headline

| Measurement | Value |
| --- | ---: |
| **Overall score** | **72.50%** (87/120 points) |
| **n** | 12 runs (3 per fixture × 4 fixtures) |
| **Reviewer cost** | $4.19 (reviewer only; $5.72 including the judge) |
| **Wall clock** | 13.8 minutes (concurrency 2) |
| **Agent prompt SHA** | `6dd9f70` — the pre-AC-4 prompt |
| **Fixture set version** | **v2** (`FIXTURE_VERSION` in `rubric.py`) — see the correction below |
| **Rubric version** | v1 (`RUBRIC_VERSION` in `rubric.py`) |

## Per-fixture

| # | Fixture | Expected | Score | Verdict correct |
| --- | --- | --- | ---: | --- |
| 01 | `lean-spec-no-visual-contract` | `block` | **20.0%** | **0/3** |
| 02 | `placeholder-copy` | `block` | **86.7%** | 3/3 |
| 03 | `unresolvable-node-ref` | `block` | **93.3%** | 3/3 |
| 04 | `control-clean` | `pass` | **90.0%** | 3/3 |

## Per-dimension

| Dimension | Score | Notes |
| --- | ---: | --- |
| `d1_verdict_correctness` | **72.2%** (52/72) | 18 of the 20 lost points are fixture 01 (0/18); the other 2 are the control, fixture 04 (16/18) |
| `d2_finding_grounding` | **70.8%** (17/24) | 6 of the 7 lost points are fixture 01 (0/6); the other 1 is fixture 04 (5/6) |
| `d3_no_fabrication` | **75.0%** (18/24) | fixture 01 is **clean** here (6/6) — the 6 lost points are fixtures 02 (2/6) and 03 (4/6) |

## Fixture 01 is the finding

**0/3. Three runs, three `N/A`s, at both fixture-set versions — six identical refusals in total.**

This is the defect #704's AC-4 exists to fix, measured rather than argued. The agent's
explicit-input discipline fired on "the input has no Copy Index / Components / Screens sections",
and its own prompt said outright that *every* lean-lane input returns `N/A`. So the checklist row
written for exactly this shape — **"a token table is not a visual contract"** — never ran on the
lane where it was needed.

The sharpest evidence is in the refusal text itself. One baseline run enumerated the checks it was
declining to run:

> Per my input discipline I do not run the spec checklist against it — doing so would manufacture
> findings ("no Element Inventory", "no visual contract", "no Copy Index") that are simply
> restatements of the artifact being a different genre, not defects in it.

The middle item is not a genre restatement. The fixture is a control-bearing screen — a
`NumberField`, a `Select`, a `DataTable` — and it records no dimensions, no per-state border, no
truncation rule and no default state. That is a real, statically visible defect, named by the
agent, in the sentence explaining why it would not report it.

**The excluded alternative.** This is not the harness handing the agent an input it was never
meant to see. The agent is the only reachable spec-side owner on the lean lane, and the sibling
plan reviewer's own prompt deferred component identity to it — a deferral to an agent that returns
`N/A` is a dropped check, which is the failure mode both agents' prompts already name.

## The control fixture was corrected before this baseline (fixture-set v1 → v2)

The first run of this eval scored `04-control-clean` at **56.7%**, and two of the three findings
driving that were **correct**:

1. the digest-frequency picker's four option labels are visible text, and had no Copy Index row;
2. the States column read `all` on rows the loading-state prose replaces with a skeleton.

Both were defects in the fixture, not reviewer false positives. A control fixture that is not
actually clean makes its own baseline unfalsifiable — the same failure AC-2 exists to prevent one
level up — so the fixture was corrected and the whole eval re-run, rather than the score being
recorded against a control that was wrong. The pre-correction measurement is kept below.

| Measurement | fx-v | rubric-v | Overall | fixture 01 | fixture 04 |
| --- | :-: | :-: | ---: | ---: | ---: |
| First run (control miscalibrated) | 1 | 1 | 64.17% | 20.0% | 56.7% |
| **Baseline of record** | **2** | **1** | **72.50%** | **20.0%** | **90.0%** |

**Fixture 01 did not move.** Six runs across two fixture versions, all `N/A`, all 2/10. That
stability is what makes it a usable oracle for #707.

## Reading this number

**72.5% with 27.5 percentage points of headroom, virtually all of it in one fixture.** Of the three
agents #704 measured, this is the only one not at a ceiling — the plan reviewer scored 99.17% and
the diff reviewer 100% — so it is where #707's tuning budget belongs.

**Four of the twelve runs** over-reached on `d3_no_fabrication`, all of them on fixtures 02 (all
three runs) and 03 (run 2). Fixtures 01 and 04 are clean at 6/6 — **the control fabricated
nothing**, which is what the section above exists to establish. Two of the four hit `rubric.py`'s
most severe `0` band ("two or more are, or any single one is extreme"), and fixture 02 run 0's
over-reach was filed as a **Blocker** (F3), not a Warning. That is the secondary signal: worth
watching during a campaign, not worth a prompt edit on n=3.

## Provenance

- **Agent prompt:** `plugins/design-toolkit/agents/figma-faithful-spec-reviewer.md` @ `6dd9f70`,
  **before** #704's AC-4 edit.
- **What actually ran:** the INSTALLED plugin, `design-toolkit@second-shift` **4.0.3**, because
  `claude -p --agent` resolves a plugin agent from the installed cache and not from the branch.
  Verified byte-identical to the branch before the run:
  `diff plugins/design-toolkit/agents/figma-faithful-spec-reviewer.md ~/.claude/plugins/cache/second-shift/design-toolkit/4.0.3/agents/figma-faithful-spec-reviewer.md` → no output.
  **This is the one agent #704 changes**, so cache and branch diverge from the AC-4 commit onward:
  anyone re-running this eval before the plugin is released and updated will re-measure the
  baseline, not the edit. #707 must confirm the installed version carries the AC-4 change before
  it records a delta against it.
- **Rubric:** `rubric.py` @ `RUBRIC_VERSION = 1`, committed alongside this report.
- **Fixtures:** `fixtures/` @ `FIXTURE_VERSION = 2`, committed alongside this report.
- **Harness:** `plugins/review-toolkit/evals/agent-eval-kit/run-eval.py` @ `808aa29`.
- **Repo state at run time:** `fee85c8` (recorded as `sha=` in `changelog.md`).
- **Raw results:** `results-20260830T145540Z.json` (gitignored). The superseded fx-v1 run is
  `results-20260830T144141Z.json`, also gitignored; its `changelog.md` row survives it.

### Exact invocation

```
cd plugins/design-toolkit/evals/figma-faithful-spec-reviewer-eval
REVIEWER_MODEL=<pin> JUDGE_MODEL=<pin> ./run.sh "704-baseline-pre-ac4-fx-v2"
```

The model pins are recorded in the `changelog.md` row for this run — that is where they belong,
and `scripts/check-eval-model-identity.sh` requires they not appear in the runnable surface.
Defaults applied: `--runs-per-fixture 3 --concurrency 2 --effort high`.

## Reproducibility checklist

- [x] Deterministic rubric module (`rubric.py` @ v1, no hidden state)
- [x] Deterministic, committed fixture set (`fixtures/` @ v2, nothing gitignored feeds the reviewer)
- [x] Version constants in `rubric.py` (`FIXTURE_VERSION`, `RUBRIC_VERSION`)
- [x] Changelog rows written for both the superseded and the recorded run
- [x] Smoke run passed before the full run
- [x] Installed-plugin prompt verified identical to the branch prompt AT RUN TIME
- [ ] LLM determinism: **No** — the reviewer is stochastic at high effort. n=3 per fixture is the
      smallest sample the +10pp/3-run rule can consume. Fixture 01's 0/3 is the one result here
      that n=3 establishes firmly, because six runs across two fixture versions all agreed.

## What #707 inherits

- This baseline: 72.50% at fixture-set v2 / rubric v1, agent prompt `6dd9f70`.
- **One unmeasured delta**: #704's AC-4 narrowing of the `N/A` condition, landed after this
  measurement. Re-measuring it against this file is #707's AC-1.
- Fixture 01 as a clean oracle — 0/3 before the edit, and the only fixture in the set with real
  headroom.
- The corrected control fixture, and the standing obligation not to reshape it mid-campaign: a
  fixture found miscalibrated during #707 is a finding to record, and correcting it re-baselines.

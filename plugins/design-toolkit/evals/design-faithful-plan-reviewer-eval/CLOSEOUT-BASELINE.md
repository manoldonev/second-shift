# `design-faithful-plan-reviewer` — baseline OWED

**No reading exists, and that is a decision rather than an omission.** The instrument shipped with
the agent (#739); the measurement is owed to the operator after the release that ships
`design-faithful-plan-reviewer` into the plugin cache.

| Measurement | Value |
| --- | ---: |
| **Overall score** | **OWED** |
| **n** | 0 runs |
| **Fixture set version** | v1 (`FIXTURE_VERSION` in `rubric.py`) |
| **Rubric version** | v1 (`RUBRIC_VERSION` in `rubric.py`) |

## Why no number

`claude -p --agent` resolves a plugin agent from the **installed cache**, not from the branch. A
brand-new agent is absent from that cache until the release that ships it, so a run taken now
exits 1 in under a second with `not found. Available agents: …` and every fixture scores 0. That
zero measures the environment, not the agent — and a checked-in zero is worse than no number,
because a later reader compares against it.

This is the same fact `../README.md` states as the prerequisite for every eval in this directory.
It bites hardest on the first run of a new agent, which is exactly this case.

## What the operator does when the reading is taken

1. Confirm `design-toolkit@second-shift` is enabled and its installed version ships the agent:
   `ls ~/.claude/plugins/cache/second-shift/design-toolkit/<version>/agents/design-faithful-plan-reviewer.md`
2. Confirm the installed prompt is byte-identical to the branch, and record the answer here:
   `diff plugins/design-toolkit/agents/design-faithful-plan-reviewer.md ~/.claude/plugins/cache/second-shift/design-toolkit/<version>/agents/design-faithful-plan-reviewer.md`
3. Smoke first, then the full run:
   ```
   cd plugins/design-toolkit/evals/design-faithful-plan-reviewer-eval
   REVIEWER_MODEL=<pin> JUDGE_MODEL=<pin> ./run.sh "smoke" --smoke
   REVIEWER_MODEL=<pin> JUDGE_MODEL=<pin> ./run.sh "739-baseline"
   ```
4. Replace this file's headline table with the measured numbers and fill the provenance block
   below. The model pins belong in `changelog.md`, not here —
   `scripts/check-eval-model-identity.sh` requires they not appear in the runnable surface.

Nothing downstream binds to the absent number. The `+10pp` / 3-run keep-or-revert rule in
`../../dev-pipeline/eval-criteria.md` needs a prior reading to compare against, and until one
exists this agent simply has no campaign — not a failing one.

## Provenance (to be filled at the first reading)

- **Agent prompt:** `plugins/design-toolkit/agents/design-faithful-plan-reviewer.md` @ `<sha>`.
- **What actually ran:** the INSTALLED plugin, `design-toolkit@second-shift` `<version>`.
- **Rubric:** `rubric.py` @ `RUBRIC_VERSION = 1`, committed alongside this report.
- **Fixtures:** `fixtures/` @ `FIXTURE_VERSION = 1`, committed alongside this report.
- **Harness:** `plugins/review-toolkit/evals/agent-eval-kit/run-eval.py` @ `<sha>`.
- **Repo state at run time:** `<sha>` (recorded as `sha=` in `changelog.md`).

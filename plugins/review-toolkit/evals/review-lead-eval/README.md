# review-lead synthesis eval

Eval campaign for the **highest-stakes synthesis in the pipeline** (dev-pipeline
Stage 8): review-lead consolidating a set of reviewer findings into one verdict —
deduplication, the confidence filter, triage, the Scope Completeness hard gate, and
the final "Ready to merge?" call. This path had **no eval** before #149.

## Why a wrapper agent (`review-lead-synth`)

`review-lead` is a **skill**, not an `--agent` target, and its synthesis runs over
findings that `code-review.mjs` already produced (synthesis-only mode). The generic
harness (`agent-eval-kit/run-eval.py`) drives `claude -p --agent <name>` against
fixtures, so it cannot invoke a skill directly. The campaign therefore drives a thin
wrapper agent, [`.claude/agents/review-lead-synth.md`](../../agents/review-lead-synth.md),
which loads the review-lead skill (`skills: review-lead`) and consolidates the
**canned** reviewer-findings set from each fixture. The wrapper delegates entirely
to the skill's Synthesis Rules — it does not re-implement them, to avoid drift.

## Layout

- `rubric.py` — 5-dim / 6-pt rubric (d1 verdict, d2 dedup, d3 confidence filter,
  d4 scope gate, d5 no-hallucination). Maps to the skill's Synthesis Rules steps.
- `run.sh` — wires `run-eval.py` with `--agent-name review-lead-synth`, this rubric,
  and the fixtures at `docs/eval-fixtures/review-lead/`.
- `smokes/validate-fixtures.sh` — **$0**, no Claude CLI. Validates every fixture's
  shape (parseable findings JSON, required `expected_verdict` key, `.md`/`.expected.json`
  pairing). Run this in CI / pre-flight; it is the only piece exercised without cost.
- Fixtures live at [`docs/eval-fixtures/review-lead/`](../../../docs/eval-fixtures/review-lead/)
  (see its README for the fixture format).

## Status — scaffolding, no baseline yet

**No baseline has been run.** A real run spawns `claude -p` reviewer + judge
subprocesses and costs money, so it is intentionally NOT run by the dev-pipeline and
NOT part of automated verification. To establish the first baseline:

```bash
# $0 pre-flight first:
./smokes/validate-fixtures.sh

# then the real (paid) baseline:
./run.sh "first-baseline"
```

Once a baseline exists, treat `rubric.py` as **LOCKED** for the duration of any
optimization loop (see its header).

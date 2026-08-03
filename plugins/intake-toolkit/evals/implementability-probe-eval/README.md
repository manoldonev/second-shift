# implementability-probe eval

Measures whether the probe reports the gaps a spec was deliberately built to hide.

**Operator-run and model-billed. Never in CI** — CI in this repo is model-free by design, and a
lane that dispatches an agent would break that on every push. Run it when the probe's agent doc
changes, or when a model generation turns over.

## Run

1. Dispatch `intake-toolkit:implementability-probe` (via `Task`) against
   `fixtures/underspecified-spec.md`, with the repo root as the grounding surface.
2. Tell it explicitly to read **only** the spec and the repo's code — not this directory, not
   `docs/plans/`, not git history. Blindness is the measured property, and an eval that leaks
   the answer key measures nothing.
3. Score the returned report against `fixtures/seeded-gaps.md` (withheld from step 1). A gap is
   *reported* when the probe names the same fork, in its own words and possibly under a
   different class.
4. Append the result to `BASELINE.md`: gaps reported / 5, class agreement, extra guess-points,
   and the dispatch shape used.

## What a regression looks like

- **Hit count drops.** The probe stopped finding forks it used to find.
- **Extras balloon while hits fall.** Padding — the failure mode the agent doc names. A probe
  that reports thirty guess-points on a well-specified spec teaches its reader to skip it.
- **Blindness leaks.** The report cites the ledger, the issue thread, or a decision record. The
  number then means nothing, regardless of how good it looks.

Class disagreement on its own is **not** a regression. `human` vs `codebase` turns on whether
the repo actually settles the question, and the probe grounds that against live code while the
answer key was written once. A disagreement the probe defends with a citation is a better
answer than the key's, and the key is what gets corrected.

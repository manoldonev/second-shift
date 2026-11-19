# implementability-probe eval

Measures whether the probe reports the defects a decision record was deliberately built to hide.

**Operator-run and model-billed. Never in CI** — CI in this repo is model-free by design, and a
lane that dispatches an agent would break that on every push. Run it when the probe's agent doc
changes, or when a model generation turns over.

## Run

1. Dispatch `intake-toolkit:implementability-probe` (via `Task`), handing it
   `fixtures/underspecified-spec.md` and `fixtures/planted-record.md`, with the repo root as the
   grounding surface.
2. Tell it explicitly to read **only** the spec, the record and the repo's code — not the rest of
   this directory, not `docs/plans/`, not git history. Blindness is the measured property, and an
   eval that leaks the answer key measures nothing.
3. Score the report against `fixtures/planted-defects.md` (withheld from step 1). Score the
   guess-points from the spec body that the record leaves open against `fixtures/seeded-gaps.md`
   when you need to. A gap is *reported* when the probe names the same fork, in its own words and
   possibly under a different class.
4. Append the result to `BASELINE.md`: defects reported / 4, whether P-1's departure stayed off
   the guess-point list, whether the report came back partial or with an `unverified` item, and
   the dispatch shape used.

## What a regression looks like

- **Hit count drops.** The probe stopped finding forks it used to find.
- **Extras balloon while hits fall.** Padding — the failure mode the agent doc names. A probe
  that reports thirty guess-points on a well-specified spec teaches its reader to skip it.
- **Blindness leaks.** The report cites the issue thread, the session's context, or a ledger or
  decision record the probe was not handed. The number then means nothing, regardless of how good
  it looks. A record the probe was handed is its input, not a leak.

Class disagreement on its own is **not** a regression. `human` vs `codebase` turns on whether
the repo actually settles the question, and the probe grounds that against live code while the
answer key was written once. A disagreement the probe defends with a citation is a better
answer than the key's, and the key is what gets corrected.

# Known Issues — plan-reviewer eval rubric

## Deferred: drop the ceilinged `d5_evidence_substantive` at the next rubric revision

`d5_evidence_substantive` (worth 1 pt, see [`rubric.py`](./rubric.py) `MAX_POINTS`)
scored **100% from baseline across every round** of this campaign — it carries no
discriminating signal. The `reviewer-baseline` skill already enforces the
four-field finding structure (severity / Issue / Evidence / Recommendation), so by
the time the reviewer emits any finding, evidence-anchoring is structural. A 1-pt
dim with no headroom is a wasted rubric slot.

**Pending change (apply only at the next rubric revision / fresh baseline):**

- Drop `d5_evidence_substantive` and redistribute its 1 point — either onto a
  discriminating dim, or by splitting an existing dim (the security-reviewer
  campaign proposes splitting its FP dim into Critical-FP / Warning-FP halves to
  exploit asymmetric costs; the plan-reviewer analog is to fold the point into
  `d2_defect_recall` or `d4_classification`).

## Why deferred (not applied now)

`rubric.py` carries a hard header:

> This rubric is LOCKED during an optimization loop — do not edit mid-campaign
> or you invalidate comparisons across rounds.

Dropping d5 changes `MAX_POINTS` and the point denominator, which breaks
comparability with every prior baseline. It must be done **at a fresh baseline**,
bundled with the next deliberate rubric revision — not opportunistically.

_Filed by #149 (eval/observability coverage). Tracked, deliberately deferred._

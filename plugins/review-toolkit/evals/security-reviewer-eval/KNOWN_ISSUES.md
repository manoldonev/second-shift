# Known Issues — security-reviewer eval rubric

## Deferred: drop the ceilinged `d5_evidence_substantive` at the next rubric revision

`d5_evidence_substantive` (worth 1 pt, see [`rubric.py`](./rubric.py) `MAX_POINTS`)
was **already at ceiling pre-campaign (100% across all rounds)** and carried no
signal — the campaign's [`FINAL-REPORT.md`](./FINAL-REPORT.md) flags it explicitly
("d5 ceilinged immediately and was effectively dead weight", "NOT done in this
campaign — rubric was locked"). The `reviewer-baseline` skill already enforces the
four-field finding structure, so evidence-anchoring is structural by construction.

**Pending change (apply only at the next rubric revision / fresh baseline)** — both
options are from FINAL-REPORT.md's recommendations:

- **Drop d5** → a 4-dim / 9-pt rubric; redistribute its 1 point, **and/or**
- **Split `d4_no_fp_on_negatives`** into `d4a_critical_fp` + `d4b_warning_fp` to
  exploit the asymmetric cost of a Critical false positive (~5× the noise of a
  Warning FP per the campaign brief). FINAL-REPORT estimates the refactor forces a
  fresh re-baseline (~$70).

## Why deferred (not applied now)

`rubric.py` carries a hard header:

> This rubric is LOCKED during an optimization loop — do not edit mid-campaign
> or you invalidate comparisons across rounds.

Dropping d5 / splitting d4 changes `MAX_POINTS` and the point denominator, breaking
comparability with every prior baseline. It must be done **at a fresh baseline**,
bundled with the next deliberate rubric revision — not opportunistically.

_Filed by #149 (eval/observability coverage). Tracked, deliberately deferred._

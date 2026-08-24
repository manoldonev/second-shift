# Measure the three drive-modes and execute the arm #643's criterion selects

Phase 2 of #643. #643 delivered the measurement instrument and the retrospective audit; this
ticket owns the measurement campaign and the execution of whichever arm it selects.

**Do not re-litigate the criterion.** It is committed at
`docs/plans/second-shift-643-preregistration.md` and was audited by an independent session before
any number was read. Amending it now, with the retrospective result known, is exactly what the
pre-registration exists to prevent. If it must change, the change and its basis go in a new
revision with the old one left standing.

## What #643 established

*(Refreshed 2026-08-23 by the operator after PR #651 rounds 1–3 — the original text pre-dated
the corpus correction. Figures below match the committed audit as merged; the audit file is
authoritative if they ever disagree.)*

- **The retrospective corpus does not support the delete arm.** Spawn-level `M1ᵗ` is
  **0.873–0.905**, both ends in the keep row, over the corrected 63-spawn corpus. The session
  that predicted 0.30–0.50 recorded the refutation.
- **The corpus cannot select an arm anyway**, for three reasons in
  `docs/plans/second-shift-643-audit.md`: the launch unit is unrecoverable (the scheduler
  truncates each spawn log before appending — launch floor 18, launch-level bound 0.667); four
  of the **six** transport failures pre-date #566, which deleted that mechanism on 2026-08-21 —
  **the post-#566 corpus is nine spawns with two T (`0.778`, the reshape row)**, so the only
  slice measuring today's transport is thin and reads worst for the scheduler, and resolving
  that tension is this campaign's job; and class M — mis-dispatch onto already-merged issues,
  two confirmed of the four first assigned — is a real scheduler cost the rubric cannot charge
  it for (the two reclassified spawns also carry a documented cost while sitting in `clean`;
  audit warning W-7).

## Scope

1. **Build variant (c)** as a time-boxed spike: keep only the spawns that genuinely need a model
   session, replace the rest with direct `lean-gate.sh` calls per #590's landed template. It is an
   instrument, not a ship — it lands only if it wins.
2. **Departed to #652** (operator amendment below) — **Run the campaign** AC-2 specifies: at least three runs per arm — (a) `run-lean` as it stands,
   (b) manual two-terminal, (c) the spike — on comparable tickets. Record wall-clock, session
   count, and **operator-attention minutes**, which the criterion makes the primary metric.
3. **Departed to #652** (operator amendment below) — **Score against the committed criterion** and execute the selected arm.
4. **Fix the audit blocker first, or the campaign cannot be scored.** Give each launch its own log
   directory, or stamp `SPAWN_N` with a per-launch token. Until then a launch's evidence is
   destroyed by its successor, and this ticket would reproduce #643's central limitation.
5. **Wire the mid-run staleness re-check** (routed here by #643's `D-12`): `lean-gate.sh:2502`
   already carries the refusal for a ticket that closed under a running spawn, and nothing calls
   it. The corrected class-M shape from PR #651's round 2 (B-7) — spawns alive across their
   ticket's close — is this defect, not mis-dispatch. Lands with whichever arm survives; under
   arm A it still lands, because the manual lane has the same hole.

## Two things the delete arm must argue past

Recorded in the pre-registration so arm A cannot win by silence:

- **Concurrency.** Epic #525's whole direction dies with the scheduler; nothing in the criterion
  prices that.
- **Non-author operators.** `run-lean` ships as the marketplace front door, and a manual baseline
  measured on the system's own author bounds nobody else's cost.

## Sequencing

#617, #638 and #639 stay blocked behind this — all three repair a transport this may still delete.

Provenance: #643's `D-1`/`D-2`, ratified by the operator on 2026-08-23. Body refreshed by the
operator 2026-08-23 discharging PR #651 round 3's carried blocker (figures + `D-12` routing).


---

## Operator amendment — scope split (2026-08-23)

Scope items 2 (the nine-run campaign) and 3 (score and execute the selected arm) are **departed
to #652**, per PR #653's ledger; this ticket delivers the instruments only — per-launch spawn
evidence, the mid-run staleness re-check, variant (c) `--attended`, revision 5 of the criterion,
and the committed evidence-file skeleton. #650 closing on PR #653's merge does not decide an arm;
#652 (deliberately `needs-spec-work`, not queued — its work is operator-driven lane runs over
days) owns the decision. #617/#638/#639 remain gated on the arm selection, now via #652.

Ratified by the operator, 2026-08-23.



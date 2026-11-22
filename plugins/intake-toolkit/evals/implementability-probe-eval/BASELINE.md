# Baseline

One row per fixture and arm. The row format is in `README.md`, "Recording a run".

| Date | Fixture | Arm | Commit | Subject model | Judge model | Runs | Case score | departure-reported | departure-kept-off-guess-points | changed-meaning-reported | absent-criterion-reported | thin-row-fork-reported | no-padding | no-blindness-leak | control-reported-covered | Dispatched | Complete | 12 or fewer |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

No scored run set is recorded yet.

## Manual runs, before the runner case

These runs were dispatched and scored by hand, with no fixed graders. They are not comparable
with the rows above.

### 2026-11-19 — opus, the record round

Dispatched by body (`general-purpose`, the agent file below its frontmatter as the prompt), because
the installed plugin did not yet carry the changed agent. A by-body dispatch does not carry the
frontmatter, so its `maxTurns` does not apply. Re-run by registered name after a release that
carries the agent, and note here if the numbers move.

**The spec plus a record written for this run with three planted defects: 3 / 3 reported, and the
thin row too.** AC-1 departed by a `user-answered` row (reported `departed — D-2`), AC-2's Test
intent line changed to a count (reported under Changed meaning), AC-3 missing from the `ACs:` line
(reported `absent`), and a one-word Resolution (reported as a guess-point with its fork). The probe
also listed the operator's departure as a blocking guess-point, which would re-ask a settled
decision; the agent doc now says a departure an `intent` row records (`user-answered`,
`user-delegated` or `ticket-sourced`) is not a guess-point.

**Re-run, after that change, with D-2 made `user-delegated`: 4 / 4 on `planted-defects.md` (P-1 to
P-4), and D-2 kept off the guess-point list.** That record is the committed
`fixtures/planted-record.md`. Its two blocking guess-points were the thin row and the stdout
summary lines that D-1 leaves open. One run.

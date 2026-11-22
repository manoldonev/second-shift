# Baseline

One row per fixture and arm. The row format is in `README.md`, "Recording a run".

| Date | Fixture | Arm | Commit | Subject model | Judge model | Runs | Case score | departure-reported | departure-kept-off-guess-points | changed-meaning-reported | absent-criterion-reported | thin-row-fork-reported | no-padding | no-blindness-leak | notes-file-not-read | control-reported-covered | Dispatched | Complete | 12 or fewer |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-22 | tuning | with | cb8a8d44 | claude-opus-5-5 | `sonnet` | 5 | 0.98 | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 | 4/5 | n/a | 5/5 | 5/5 | 5/5 |
| 2026-11-22 | tuning | without | cb8a8d44 | claude-opus-5-5 | `sonnet` | 5 | 0.77 | 5/5 (3,3,3,3,3) | 0/5 (0,0,0,0,0) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 0/5 (0,0,0,0,0) | 5/5 | 5/5 | n/a | n/a | n/a | n/a |
| 2026-11-22 | held-out | with | cb8a8d44 | claude-opus-5-5 | `sonnet` | 5 | 0.96 | 5/5 (3,3,3,3,3) | 4/5 (1,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 | 4/5 | 5/5 (3,3,3,3,3) | 5/5 | 5/5 | 5/5 |
| 2026-11-22 | held-out | without | cb8a8d44 | claude-opus-5-5 | `sonnet` | 5 | 0.76 | 5/5 (3,3,3,3,3) | 0/5 (0,1,0,0,0) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 0/5 (0,0,0,0,0) | 5/5 | 3/5 | 5/5 (3,3,3,3,3) | n/a | n/a | n/a |

The held-out fixture is kept outside the repo. The subject id is the one the traces name. The
report names the judge only by its alias, so the judge cell holds the alias.

The run sets of 2026-11-22, both run with `CLAUDE_CODE_EFFORT_LEVEL=high`:

| Fixture | With | Without | Difference | Timeouts or turn caps | Blindness leaks, without |
| --- | --- | --- | --- | --- | --- |
| tuning | 0.98 | 0.77 | 0.22 | 0 | 0 |
| held-out | 0.96 | 0.76 | 0.20 | 0 | 0 |

- Both arms reported every planted defect in every run. The whole difference comes from two
  graders: the plain session listed the settled departure as a guess in 10 of 10 runs, and it listed
  more than 12 guess-points or padded the list in 10 of 10 runs.
- The with-arm score is above 0.80 on both fixtures, and `no-blindness-leak` passed in all 20 runs.
- Hand-read, not rescored: all four `notes-file-not-read` fails are false. The pattern matched a
  search that excludes `docs/plans` (`grep -v docs/plans`, or a glob that starts with `!`). No trace
  of the 20 runs holds text from the notes file.
- Hand-read, not rescored: the one held-out with-arm fail of `departure-kept-off-guess-points`
  (1 of 3 votes) is a judge miss. That report says the departure is settled and lists two other
  guess-points.
- Read by hand, the with-arm scores 1.00 on both fixtures, and the held-out without-arm 0.79.
- The graders are as committed at cb8a8d44. The two false-fail patterns above are known and not
  fixed.

One unscored run per arm checked the case before any scored run (2026-11-22, the commit before
this file's change). It showed one grader defect: two of three judge votes failed
`thin-row-fork-reported` on a report that named the record's own two options. The criterion now
says that those two options count as two concrete alternatives. `notes-file-not-read` was added
after the same run showed that the trace holds the dispatched agent's tool calls.

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

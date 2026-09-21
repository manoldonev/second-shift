# #868 — Review scores the code against the decision record

Review scored the build-written `AC-n` list and graded the ticket, and nothing held the code
against the operator's decision record, so a departure the build never declared could be approved.
This change points review at the record. When the committed spec's `## Decision Ledger` declares
intent rows (`user-answered` / `user-delegated`), the scope reviewer scores each row against the
diff, the verdict summary carries a `## Decision scorecard` in place of the `## AC scorecard`, and
the one scorecard validator at the writer and at the merge boundary is keyed by which id set the
spec declares.

## Acceptance criteria

- **AC-1** — `boundary-evidence.sh`'s scorecard reader reads a spec's declared intent rows: every
  `| D-n |` row whose Provenance cell is `user-answered` or `user-delegated`, and among them the
  rows whose Resolution opens with `DEPARTURE`. With one or more intent rows it validates a
  `## Decision scorecard` table (columns `D-n`, `score`, `evidence`, every cell non-empty, exactly
  one row per intent row and no others); with none it validates the `## AC scorecard` exactly as
  before. One reader, reached by the writer (`scorecard` subcommand) and by the boundary's verdict
  arm, as today. The writer's refusal quotes the schema for the spec it was handed.
- **AC-2** — Decision scores are `honored`, `violated`, `departed`, `undeterminable`. Beside
  `verdict=approve` the reader refuses a `violated` row, an `undeterminable` row, a `departed` row
  on a spec row with no `DEPARTURE` marker, and a `departed` row whose evidence cell does not carry
  `decided_by: user-answered` or `decided_by: user-delegated`. A spec with intent rows and a record
  with no Decision scorecard is refused on approve — there is no legacy arm (D-6).
- **AC-3** — `scope-completeness-reviewer` is rewritten in place. Handed a committed lane spec
  path that declares intent rows, it scores every such row cold against the three-dot diff with a
  file and line, reads the intent-gap record for a departed row's decider (a row counts as decided
  only when the record's `## Gap` names its `D-n` and `decided_by:` is `user-answered` /
  `user-delegated`, or the legacy `ratified: yes` pair), and grades only the ticket items no row
  covers. Where a ticket item and a row conflict, the row governs and the ticket item is not a
  finding. `violated`, `undeterminable`, or an undecided departure is FAIL. With no spec path, or
  a spec with no intent rows, it grades the ticket as before.
- **AC-4** — `review-lead` forwards the committed lane spec path to `scope-completeness-reviewer`
  as evidence when one exists — the path only, never a paraphrase of its rows.
- **AC-5** — `/dev-pipeline:review` step 5 tells the review session to transcribe the scope
  reviewer's row table into the summary as `## Decision scorecard` (no AC scorecard beside it)
  when the spec declares intent rows, and the AC scorecard otherwise. It states the known limit of
  the source: the committed ledger is build-authored, and its fidelity to the gitignored receipt is
  attested only by milestone 1's `ledger-lint --reconcile` on the build host. Step 5d says that
  where the ticket and the record disagree, the record governs.
- **AC-6** — `scenario-liveness-selftest.sh` is extended with a spec carrying a departed row and a
  violated row, driven through the writer and the boundary. `boundary-evidence-selftest.sh`
  covers the reader's Decision arms. No new selftest file.
- **AC-7** — The docs that describe the AC scorecard as review's scope contract
  (`tools/capability-parity.tsv`, `docs/testing.md`) name the Decision scorecard too.
- **AC-8** — Net diff outside `docs/plans/` is not positive, stated in the PR body. No new gate,
  register, record kind, record key or refusal reason beyond the re-keyed scorecard reader.

## Notes

- The reader does not refuse an `## AC scorecard` section sitting beside a Decision scorecard; it
  reads only the one the spec keys. "Never both" (D-3) is the review skill's instruction. A refusal
  would deadlock any PR reviewed with a writer that predates this change while its boundary runs
  this one, which is exactly this ticket's own PR.
- The validator does not parse the intent-gap record's prose (D-13); tying a decider to a row is
  the scope reviewer's reading. The boundary's existing intent-gap arm still refuses a record
  whose `decided_by:` is not decided.
- OR-1 (the consumer-head replay): the reversible default is taken. The PR opens without a replay
  result and flags that the operator's replay is owed before merge authorization (D-7, D-8).

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Sequencing against the ceremony removal (open PR #872, which edits review/SKILL.md, milestone-gate.sh, boundary-evidence.sh and interviewing-baseline) | Build only on a base that contains #872. A departed row's decider is read from the intent-gap record's `decided_by:` key as #872 defines it, including #872's own legacy read of `ratified: yes` plus its URL. "Where the ticket and the record disagree, the record governs" is written where #872 removed review step 5d, not beside a surviving hand-back. If the base lacks `decided_by:`, stop and say so rather than building against `ratified:`. | user-answered |
| D-2 | Which artifact is "the decision record" review scores | The committed spec's `## Decision Ledger`: its intent rows, identified by provenance `user-answered` / `user-delegated` (the committed ledger is four columns and has no Kind cell). No new committed file and no new record key. The skill states the known limit in plain words: the copy is build-authored, and its fidelity to the gitignored receipt is attested only by milestone 1's `ledger-lint --reconcile` on the build host, and only when the receipt exists there. | user-answered |
| D-3 | When the row table replaces the AC scorecard | Spec ledger declares one or more intent rows: the verdict summary carries the row table and no AC scorecard. Zero intent rows, the explicit-empty form, or no ledger section: today's `## AC scorecard`, unchanged. Never both on one record. One validator in `boundary-evidence.sh`, keyed by which id set the spec declares, run at the verdict writer and at the merge boundary as today. The writer's existing scorecard refusal is retargeted, not joined by a second one. | user-answered |
| D-4 | Who scores the rows, and whether the ticket is still read | In the lane, `scope-completeness-reviewer` is handed the committed spec path and scores every intent row cold against the three-dot diff, with a file and line per row. It still fetches the ticket itself, but grades only the items no row covers; where a ticket item and a row conflict the row wins and the ticket item is not a finding. Its independence contract is kept: review-lead passes the spec path as evidence, never a paraphrase of the rows. The agent is rewritten in place under its existing name, so consumer `reviewers.remove[]` / `reviewers.default[]` entries and the `--panel` value are unchanged. With no lane spec (standalone `review-lead`, `pr-revision`), or a lane spec declaring zero intent rows, it grades the ticket exactly as today. The review session transcribes the reviewer's row table into the `--summary-file`; it does not re-score it. | user-answered |
| D-5 | The score enum and what blocks | Four values: `honored`, `violated`, `departed`, `undeterminable`. One table row per declared intent row, all of them and no others (the rule the RS fidelity table already uses). `violated` is a blocker. `departed` requires the spec row to carry its `DEPARTURE — <reason>` marker and the evidence cell to name the decider read per D-1; a departed row whose record reads `decided_by: pending`, or that has no intent-gap record, is a blocker. A code departure the spec does not mark is `violated`, not `departed`. The D-3 validator refuses a `violated`, an `undeterminable`, or an undecided `departed` row beside an `approve`, at the writer and at the boundary, exactly as it refuses `unsatisfied` today; the reviewer's FAIL keeps review-lead's hard "No". There is no skip value: a process row (a `review panel` row) is determinable from the branch's own records. | user-answered |
| D-6 | Verdict records written before this ships, on a spec with intent rows | No legacy arm. The boundary demands the row table; an approved-but-unmerged PR on such a spec goes red at merge and takes one fresh review round under the new skill. The Changelog trailer's Migration line says so. | user-answered |
| D-7 | Who runs the acceptance replay on the consumer head, and where the result lives | The operator, after the PR opens, with the pinned-base recipe in `docs/consumer-eval.md`. The anonymized result (departed row named: yes or no, minutes, cost) goes in the PR body at merge authorization. The build ships the contract and its selftests and does not run, simulate or pre-write the replay. | user-answered |
| D-8 | The replay result itself | parked under OR-1 (owner: operator; due before merge authorization of this ticket's PR) | deferred |
| D-9 | Table heading and columns in the verdict summary | `## Decision scorecard`, columns `D-n`, `score`, `evidence`, every cell non-empty. Mirrors the shipped `AC-n`, `score`, `evidence` schema in `boundary-evidence.sh` (`AC_SCORECARD_COLUMNS`) so one reader serves both. A `departed` row's evidence cell carries `decided_by: <value>`. | codebase-derived |
| D-10 | Liveness coverage | The re-keyed validator is a gate contract, so `scenario-liveness-selftest.sh` is extended (a spec with a departed row and a violated row), per CLAUDE.md "a new gate contract must extend the liveness scenario" and the `writing-tests` skill. No new selftest file. | codebase-derived |
| D-11 | Commit verb and changelog | `feat(dev-pipeline)` with a `Changelog:` trailer carrying the D-6 migration line; no version or CHANGELOG.md edit (CLAUDE.md: commit verbs, frozen release files). | codebase-derived |
| D-12 | Basis for "net diff not positive" | Counted outside `docs/plans/` and stated in the PR body, the basis PR #870 used for the sibling ticket's net-diff constraint. | codebase-derived |
| D-13 | Tying a decider to a specific departed row, given one intent-gap record per issue with no row-id key | A departed row counts as decided only when the intent-gap record's `## Gap` prose names that row's `D-n`. A `DEPARTURE` row the record does not name is a blocker, the same as `decided_by: pending`. No schema change to the record. The scope reviewer reads this; the validator does not parse the prose. | user-answered |
| D-14 | Build-model sizing | `opus`, already on the ticket. Basis: the ticket body's own sizing line (it changes a shipped review contract consumers read), a machine-read validator re-keyed at two layers, and one open region left by this receipt. | codebase-derived |

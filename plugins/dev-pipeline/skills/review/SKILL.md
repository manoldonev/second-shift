---
name: review
description: The REVIEW half of the pipeline — review an open pipeline PR from a fresh top-level session, score every row of its decision record, and post one verdict comment for the human who decides the merge. The manual form of what /dev-pipeline:run's review session does; use it when a run ends review-unbound, or to review a lane PR by hand.
---

# review

Input a PR number. Output **one PR comment** in the verdict grammar (step 8): two fixed lines, the
record's row table, then the findings — and the same verdict as the `second-shift/review` commit
status on the sha it names, posted only when the comment backs its own verdict line. Nothing is
committed.

This runs as its own top-level session, and that is the entire point: the session that wrote the
code does not grade it. Never run it inside the build's session, and never resume an earlier
review's context.

> **Tracker delta (`tracker.type: jira`).** The checklist is the github default. Under jira the
> ticket key resolves from `Closes [<KEY>]` under the PR body's `### Jira Items` heading, not
> `Closes #N`. The verdict comment and its commit status are code-host writes, not tracker ones,
> so they post the same under both adapters. Nothing else differs.
> [Adapter contract](../../tools/tracker/jira/README.md).

## Checklist

1. `gh pr view <pr> --json number,headRefName,headRefOid,url`, then take only the body's
   references, not its prose — the filter prints the tokens alone, never the line around them:
   `gh pr view <pr> --json body --jq '.body | split("\n")[] | (capture("^\\s*(?<l>(closes|fixes|resolves)\\s+(#\\d+|\\[[A-Za-z][A-Za-z0-9]*-\\d+\\]))\\s*$"; "i").l), (capture("^(?<l>Record baseline: [0-9a-f]{7,40})\\s*$").l), scan("[^\\s()<>\\[\\]]*decisions\\.md")'`.
   They name the ticket (`Closes #N`), the `Record baseline:` and the decision record
   (`<plansDir>/<repo>-<key>-decisions.md`). **Read the build's own account last.** The PR
   description and the build's PR comments are read only after step 5's scores and step 6's
   findings are written, to reconcile the departures and rebuttals they state. An author's
   framing measurably lowers what a reviewer finds. If that reading changes a score or a finding,
   say so in the verdict's `## Notes`: `revised after reading the build's account: <what changed>`.
2. Check out the PR head and confirm `git rev-parse HEAD` equals `headRefOid`. That sha is the one
   you review and the one you name.
3. **Read the record at its first commit and at the head.** The first commit is the one that added
   it: `FIRST=$(git log --format=%H --diff-filter=A -- <record> | tail -n 1)`. Read
   `git show $FIRST:<record>` — what was decided before the build started — and the file at the
   head. A row edited since `FIRST` is a departure; the edit must name who decided. A row added
   since `FIRST` is a decision made during the build: score it too, and it must name who decided.
   When the PR body carries `Record baseline: <sha>`, that sha is the baseline. If it differs from
   the `FIRST` you computed, or is not an ancestor of the head, the record commit was rewritten:
   that alone is a blocker.
4. **Look at what the scheduler would have handed you**, from `git diff $FIRST..HEAD`: deleted or
   renamed test files (a top-level `tests/`, `__tests__/`, `test_*.py`, `conftest.py`, `_spec.`,
   `*-selftest.*` count too), added skips or forced-green lines (`.skip(`, `.only(`, `|| true`, pytest
   `skip`/`skipif`/`xfail`, Go `t.Skip(`, JUnit `@Disabled`, Rust `#[ignore]`, …), edits to CI or
   check configuration (`pyproject.toml`, `pytest.ini`, `setup.cfg`, `.coveragerc`, `Makefile` and a
   nested `package.json` included), modified existing test or snapshot files (`__snapshots__/`
   or `.snap`) and their removed expectations, each traced to an acceptance criterion or a record
   row (an untraced one is a `[blocker]` that requires the citation), every `when`-scoped `extraLanes` entry no changed file
   matched — a configured lane that did not run on this diff — and every added, edited, deleted or
   renamed review-policy file (`git diff --name-status $FIRST..HEAD`, both sides of a rename):
   `.claude/second-shift.config.json`, anything under `.claude/second-shift/`, and
   `.claude/agents/<name>.md` for each bare name under the config's `reviewers.add[]`. The
   reviewers load those from the head, so the PR is reviewed against policy it edits: trace each
   to an acceptance criterion or a record row; an untraced one is a `[blocker]` that requires the
   citation — the edit itself is never blocked. Each is a question the diff must answer, whatever
   the stack.
   Then run the plan's AC coverage check, as the scheduler does after its checks: with the record
   at `FIRST` in a file (`git show $FIRST:<record> > <file>`),
   `bash <this skill's base directory>/../../tools/plan-coverage.sh <record at FIRST> <plan at the head>`,
   the plan being `<plansDir>/<repo>-<key>-plan.md` beside the record
   ([the script](../../tools/plan-coverage.sh)). Exit 1 (an AC with no test task, a tag the record
   does not define, an unparseable task line, or no plan) is a `[blocker]` that names what it
   printed; exit 3 is not-applicable (the record carries no `## Test intent`, or the ticket has no
   AC block), never a blocker; exit 2 means it could not read the record's AC set, which you say in
   `## Notes`. `post-review-status.sh` runs the same check and posts no `success` while it is red.
   The next check, that each tagged test file fails on the record commit's tree, is the
   scheduler's alone: a lane run makes it before its review and reports it in the PR body's run
   block, and you do not run it — a session running tests in a worktree it controls is not that
   proof. On a PR built through `/dev-pipeline:build` (the `--handoff` path: the ticket's latest
   lane comment is a `build-handoff` one, and the body carries no `## second-shift run` block) nothing ran
   it: say so in `## Notes` as `fails without the change: not run on the handoff path` — a note,
   never a blocker.
5. **Score EVERY row of the record** against the code: `honored`, `violated`, `departed` (the row
   was edited; name who decided, per its provenance), or `undeterminable` (say what you could not
   read). A violated or undeterminable row is a blocker; neither may stand beside an approve.
   A row that names a deferred, unmeasured or inherited cost, load or performance risk is still
   scored on whether the code matches it — the row is the operator's decision, and a score never
   overrides it. Its risk is also required performance work: the review states the worst-case
   bound as a finding, at the severity the performance rules give it, and the row licenses the
   out-of-diff reads that check it. "The file it names is untouched" scores the row; it does not
   bound the risk.
6. **Run `review-toolkit:review-lead` over the PR diff, pass it the ticket from step 1 yourself, and
   declare the pipeline default panel**
   when you invoke it: the fan-out defaults to `scope-completeness-reviewer`; `security-reviewer`,
   `a11y-reviewer`, `unit-test-mutation-reviewer` and `performance-reviewer` are selected only by
   an opt-in — a `review panel` row in the record with `user-answered` or `user-delegated`
   provenance naming `security`, `a11y`, `unit-test-mutation` or `performance`, or the config's
   `reviewers.default[]`.
   `review-lead` never infers this; an undeclared panel leaves the surface triggers in force.
   Opting one of the four back in is your call, and **the expected call whenever the diff
   introduces a surface** rather than editing an existing one: `security` for a new
   authentication, session, tenancy or ownership-scoping path, or a new query built from external
   input; `a11y` for new form controls or a new interactive component; `unit-test-mutation` for
   new logic with a co-located spec; `performance` for a new entry point (a route, handler,
   consumer or SDK method) that reaches a data read or existing heavy work. A change to a file that already sits on one of those
   surfaces is your call either way. Pass each short name to `review-lead` with a one-line
   reason. Do not stand in for a specialist on a surface the diff introduces: your lead pass is
   one reader over the whole diff, not that reviewer's checklist. The trim stays the default
   because it was measured; a diff it was never measured on is yours to judge. Declining a
   reviewer whose surface the diff introduces is itself a decision: pass the decline to
   `review-lead` with a one-line reason, it is written into the panel line of the review, and
   the human who reads the verdict reads that line. An introduced surface with neither a
   reviewer nor a reason is a silent decision.
   **A record-named cost risk makes performance a required decision.** When a `D-n` row or an
   `OR-n` Open Region of the record names a cost, load or performance risk, opt `performance` in,
   or pass its decline with a reason that answers that row. Opted in, pass `review-lead` that row
   and the new entry point's `path:line`, so the seat traces the risk rather than the whole diff.
   A record-named risk with neither a dispatch nor a decline is a process `[blocker]` on your
   verdict; whether a decline answers the row is your judgment, and the panel line shows it.
   If it reports that the review did not run (its panel went dark), you have no verdict to give:
   say which reviewer went dark in a plain comment and post no `verdict:` line.
7. **Design frames.** When the record's `## Design frames` (or `## Design`) section carries
   `| RS-n |` rows, render every screen at the head with the repo's render command
   (`design.liveRender.command`) and compare it with its frame. If you cannot render, you cannot
   approve: post `verdict: needs-work` with line 3 `reason: render-unavailable`.
8. **Post ONE PR comment**, through [`gh-bot.sh`](../../tools/gh-bot.sh) when its `--status` is
   `ok`, plain `gh` otherwise, its body passed with `--body-file`. The body follows this grammar
   exactly — the same one `run.sh`'s review prompt states:

   <!-- LOCKSTEP-BEGIN verdict-grammar -->
   The verdict comment has these parts, in this order and nothing else:
   - Line 1 is exactly `verdict: approve` or `verdict: needs-work`. Line 2 is exactly `reviewed: <the full sha of the head you reviewed>`. An optional line 3 is exactly `reason: render-unavailable`.
   - `## Decision record rows`, then a table headed `| Row | Score | Evidence |` and its `| --- | --- | --- |` line, with one row for every `D-n` row of the record at its first commit and at the head: a row the build deleted and a row it added are both scored. The Row cell's first token is the row's `D-n` id, and the Score cell's first word is one of `honored`, `violated`, `departed`, `undeterminable`. The section holds the table and blank lines only: per-row detail goes in the Evidence cell, anything else in `## Notes`. Other row kinds, such as `RS-n`, are not scored in this table.
   - `## Findings`, which runs to the next `## ` heading. Each finding starts with `- [blocker] B<n> ` or `- [note] N<n> `, and its continuation lines are indented two or more spaces. Suppressed findings are `[note]`s. A section with no findings holds the single line `None.`.
   - After its id and one space, a finding from review-lead's report carries that report's reviewer, file:line and confidence in its form: `- [blocker] B1 [Reviewer] file:line (confidence: N) — <text>`, file:line only where the finding has one. A finding you raise from a rule (a violated or undeterminable row, an untraced test-expectation change) or as a process note names its rule and carries no number: never invent a score.
   - `## Panel` (optional): the panel lines review-lead writes.
   - `## Notes` (optional): free prose for the human, such as process notes or `revised after reading the build's account: <what changed>`. Nothing in it counts toward the verdict.

   `Ready to merge?` is never written anywhere in the body.

   A `[blocker]` is something that must change before merge, an edit to the PR description included. A `[note]` requires nothing. review-lead's findings translate one way: a Critical is a `[blocker]`; a Warning you would hold the merge for is a `[blocker]`, and any other Warning is a `[note]`; its "Ready to merge?" and "With fixes" are never written on this comment.

   `verdict: approve` means mergeable as-is: every record row is scored, none is `violated` or `undeterminable`, and there is no `[blocker]` and no `reason: render-unavailable` line. `verdict: needs-work` carries at least one `[blocker]`, a `violated` or `undeterminable` row, or the `reason: render-unavailable` line; under that line the rows need not be scored, and the findings may be `None.`.
   <!-- LOCKSTEP-END verdict-grammar -->

   <!-- LOCKSTEP-BEGIN kb-contributions -->
   Knowledge-base contributions: when review-lead's report has a `### Knowledge-base contributions` block, carry it into the verdict's `## Notes` as review-lead wrote it — the lead line `Knowledge-base contributions:` with one proposal per line under it, or the single line `Knowledge-base contributions: none`. review-lead applied the inclusion test the repo's review-context.md declares: do not apply it again, and add, drop or reword no proposal. Carry the whole list on every verdict, never only what changed since an earlier one: the earlier verdicts are collapsed once one binds. When the report has no such block, the verdict carries no contributions line. A proposal is a draft the operator files in the knowledge base: never a finding, and it never makes a verdict `needs-work`.
   <!-- LOCKSTEP-END kb-contributions -->

   **Check the draft before you post it.** Write the body to a file, and the record at `FIRST` to
   another (`git show $FIRST:<record> > <file>`), then run
   `bash <this skill's base directory>/../../tools/verdict-check.sh <draft> <record at the head> <record at FIRST>`
   ([the checker](../../tools/verdict-check.sh)). It prints every rule the draft breaks; fix the
   draft until it exits 0. Exit 2 means it could not read a file: fix the path, never post on a
   check that did not run. The format matches the lane's own verdicts, but no scheduler reads this
   one: a finished run has exited, and a re-launch builds before it reviews. It is for the human who
   decides the merge. Never edit it.
   Then collapse the PR's earlier verdicts as outdated, with the same `gh` you posted through:
   `GH=<that gh> bash <this skill's base directory>/../../tools/minimize-verdicts.sh <pr> <comment id>`
   ([the script](../../tools/minimize-verdicts.sh); the id is the number after `#issuecomment-` in
   the URL your post printed). It minimizes only lane-authored `verdict:` comments posted before yours,
   never a notice or anyone else's. If it fails, say so in your session output — not in a PR
   comment — and go on; never retry it as yourself in the bot's place.
   Then re-check `headRefOid`. If it is no longer the sha on your `reviewed:` line, the head moved
   under your review: post no status, and say so in a plain PR comment. Otherwise post the same
   verdict as a commit status on that sha, with the same `gh` (the bot when `--status` is `ok`),
   never with a raw `gh api` call:
   `GH=<that gh> bash <this skill's base directory>/../../tools/post-review-status.sh <pr> <sha> <body file> <record at the head> <record at FIRST> <your comment's URL>`
   ([the script](../../tools/post-review-status.sh)). It re-runs the checker on the body you
   posted and posts `success` for approve, `failure` for needs-work, under `second-shift/review`;
   an approve whose plan coverage is red posts nothing. A consumer that requires
   `second-shift/review` in branch protection cannot merge a PR without it. When it exits 1 the
   body breaks a rule, or the approve's plan coverage is red, and no status was posted: say so in
   a plain PR comment that names the failed rules or the coverage lines it printed (never a
   `verdict:` line). When it exits 3 the
   post failed: say so in a plain PR comment (a 403/404 through the bot means its GitHub App lacks
   "Commit statuses: write"); never retry it as yourself in the bot's place. On an `approve` whose
   status posted, mark the PR ready for review with the same `gh` (`gh pr ready <pr>`): a lane PR
   stays a draft until a review approves its head, because GitHub refuses to merge a draft. If
   that fails, say so in a plain PR comment. Then stop.

## Rules that are not negotiable

- **Review the head you name.** Re-check `headRefOid` just before posting; if the branch moved
  while you were reviewing, review the new commits and name the new head. A verdict naming an
  older head binds nothing.
- **Do not soften a blocker to keep a run moving, and do not invent one to look thorough.**
- **Never end a turn with work this turn started and has not collected.** A `review-lead`
  Workflow dispatch re-enters the session when it completes: await it. A `&`-detached command or
  an armed `Monitor` at turn end is abandoned, not deferred.

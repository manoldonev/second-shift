---
name: review
description: The REVIEW half of the pipeline. Review an open pipeline PR from a fresh top-level session, score every row of its decision record, and post one verdict comment for the human who decides the merge. This is the manual form of the review session of /dev-pipeline:run. Use it when a run ends review-unbound, or to review a lane PR by hand.
---

# review

Input: a PR number. Output: **one PR comment** in the verdict grammar (step 8). The comment has two
fixed lines, the row table of the record, then the findings. The same verdict goes on the
`second-shift/review` commit status of the sha that the comment names. The status is posted only
when the comment supports its own verdict line. Nothing is committed.

Run this as its own top-level session. That is the entire point: the session that wrote the code
does not grade it. Never run it inside the build's session. Never resume the context of an earlier
review.

> **Tracker delta (`tracker.type: jira`).** The checklist is the github default. Under jira, the
> ticket key comes from `Closes [<KEY>]` under the `### Jira Items` heading of the PR body, not from
> `Closes #N`. The verdict comment and its commit status are code-host writes, not tracker writes.
> They post the same way under both adapters. Nothing else is different.
> [Adapter contract](../../tools/tracker/jira/README.md).

## Checklist

1. Run `gh pr view <pr> --json number,headRefName,headRefOid,url`. Then take only the references
   from the body, not its prose. The filter prints the tokens alone, never the line around them:
   `gh pr view <pr> --json body --jq '.body | split("\n")[] | (capture("^\\s*(?<l>(closes|fixes|resolves)\\s+(#\\d+|\\[[A-Za-z][A-Za-z0-9]*-\\d+\\]))\\s*$"; "i").l), (capture("^(?<l>Record baseline: [0-9a-f]{7,40})\\s*$").l), scan("[^\\s()<>\\[\\]]*decisions\\.md")'`.
   The tokens name the ticket (`Closes #N`), the `Record baseline:` and the decision record
   (`<plansDir>/<repo>-<key>-decisions.md`).
   **Read the build's own account last.** First write the row scores of step 5 and the findings of
   step 6. Only then read the PR description and the build's PR comments. Use them to reconcile
   the departures and rebuttals they state. Measurements show that an author's framing lowers
   what a reviewer finds. If that reading changes a score or a finding, say so in the verdict's
   `## Notes`: `revised after reading the build's account: <what changed>`.
2. Check out the PR head. Confirm that `git rev-parse HEAD` equals `headRefOid`. You review that
   sha, and you name it.
3. **Read the record at its first commit and at the head.** The first commit is the commit that
   added the record: `FIRST=$(git log --format=%H --diff-filter=A -- <record> | tail -n 1)`. Read
   `git show $FIRST:<record>`. It shows what was decided before the build started. Then read the
   file at the head.
   - A row edited since `FIRST` is a departure. The edit must name who decided.
   - A row added since `FIRST` is a decision made during the build. Score it too. It must also
     name who decided.
   - When the PR body has `Record baseline: <sha>`, that sha is the baseline. The baseline can
     differ from the `FIRST` you computed, or it can be no ancestor of the head. Then the record
     commit was rewritten, and that alone is a blocker.
4. **Look at what the scheduler would have given you.** Read `git diff $FIRST..HEAD` and check
   each item below. Each item is a question that the diff must answer, whatever the stack.
   - Deleted or renamed test files. A top-level `tests/`, `__tests__/`, `test_*.py`,
     `conftest.py`, `_spec.` and `*-selftest.*` count too.
   - Added skips or forced-green lines: `.skip(`, `.only(`, `|| true`, pytest
     `skip`/`skipif`/`xfail`, Go `t.Skip(`, JUnit `@Disabled`, Rust `#[ignore]`, and similar.
   - Edits to CI or check configuration. `pyproject.toml`, `pytest.ini`, `setup.cfg`,
     `.coveragerc`, `Makefile` and a nested `package.json` count too.
   - Modified existing test or snapshot files (`__snapshots__/` or `.snap`), and their removed
     expectations. Trace each one to an acceptance criterion or a record row. An untraced one is
     a `[blocker]` that requires the citation.
   - Every `when`-scoped `extraLanes` entry that no changed file matched. That is a configured
     lane that did not run on this diff.
   - Every added, edited, deleted or renamed review-policy file. List them with
     `git diff --name-status $FIRST..HEAD`, and check both sides of a rename. The review-policy
     files are `.claude/second-shift.config.json`, anything under `.claude/second-shift/`, and
     `.claude/agents/<name>.md` for each bare name under the config's `reviewers.add[]`. The
     reviewers load these files from the head, so the PR is reviewed against the policy it edits.
     Trace each one to an acceptance criterion or a record row. An untraced one is a `[blocker]`
     that requires the citation. The edit itself is never the blocker.

   Then run the AC coverage check of the plan, as the scheduler does after its checks. Write the
   record at `FIRST` to a file (`git show $FIRST:<record> > <file>`). Then run
   `bash <this skill's base directory>/../../tools/plan-coverage.sh <record at FIRST> <plan at the head>`.
   The plan is `<plansDir>/<repo>-<key>-plan.md`, beside the record
   ([the script](../../tools/plan-coverage.sh)).
   - Exit 1 is a `[blocker]` that names what the check printed. The causes are an AC with no test
     task, a tag the record does not define, an unparseable task line, or no plan.
   - Exit 3 is not-applicable: the record has no `## Test intent`, or the ticket has no AC block.
     It is never a blocker.
   - Exit 2 means that the check could not read the AC set of the record. Say so in `## Notes`.

   `post-review-status.sh` runs the same check and posts no `success` while the check is red.
   The next check proves that each tagged test file fails on the tree of the record commit. Only
   the scheduler makes it. A lane run makes it before its review and reports it in the run block
   of the PR body. Do not run it: a session that runs tests in a worktree it controls does not
   give that proof. A PR built through `/dev-pipeline:build` took the `--handoff` path. On that
   path, the latest lane comment on the ticket is a `build-handoff` comment, and the body has no
   `## second-shift run` block. Nothing ran the check there. Say so in `## Notes` as
   `fails without the change: not run on the handoff path`. This is a note, never a blocker.
5. **Score EVERY row of the record** against the code. The scores are `honored`, `violated`,
   `departed` or `undeterminable`. A departed row was edited: name who decided, per its
   provenance. For an undeterminable row, say what you could not read. A violated or
   undeterminable row is a blocker. Do not approve when a row has either score.
   A row can name a deferred, unmeasured or inherited cost, load or performance risk. Still score
   that row on whether the code matches it. The row is the operator's decision. A score never
   overrides it. Its risk is also required performance work: the review states the worst-case
   bound as a finding, at the severity the performance rules give it. The row permits the
   out-of-diff reads that check the bound. The row can name a file that the diff does not touch.
   That fact scores the row. It does not bound the risk.
6. **Run `review-toolkit:review-lead` over the PR diff.** Pass it the ticket from step 1 yourself.
   **Declare the pipeline default panel** when you invoke it. Under that panel the fan-out
   defaults to `scope-completeness-reviewer`. The other four reviewers (`security-reviewer`,
   `a11y-reviewer`, `unit-test-mutation-reviewer` and `performance-reviewer`) run only on an
   opt-in. An opt-in comes from one of two sources. The first is a `review panel` row in the
   record with `user-answered` or `user-delegated` provenance, naming `security`, `a11y`,
   `unit-test-mutation` or `performance`. The second is the config's `reviewers.default[]`.
   `review-lead` never infers this. An undeclared panel leaves the surface triggers in force.

   You can opt one of the four back in. **That is the expected call whenever the diff introduces
   a surface.** It is not expected when the diff only edits an existing surface.
   - Opt in `security` for a new authentication, session, tenancy or ownership-scoping path, or
     for a new query built from external input.
   - Opt in `a11y` for new form controls or a new interactive component.
   - Opt in `unit-test-mutation` for new logic with a co-located spec.
   - Opt in `performance` for a new entry point that reaches a data read or existing heavy work.
     An entry point is a route, handler, consumer or SDK method.

   For a change to a file that already sits on one of those surfaces, you decide either way. Pass
   each short name to `review-lead` with a one-line reason.

   Do not stand in for a specialist on a surface the diff introduces. Your lead pass is one reader
   over the whole diff. It is not that reviewer's checklist. The trimmed panel stays the default
   because it was measured. You judge a diff that it was never measured on.

   Declining a reviewer whose surface the diff introduces is itself a decision. When you decline
   one, pass the decline to `review-lead` with a one-line reason. `review-lead` writes the decline
   into the panel line of the review. The human who reads the verdict reads that line. An
   introduced surface with neither a reviewer nor a reason is a silent decision.

   **A record-named cost risk makes performance a required decision.** A `D-n` row or an `OR-n`
   Open Region of the record can name a cost, load or performance risk. When one does, opt
   `performance` in, or pass its decline with a reason that answers that row. When you opt in,
   pass `review-lead` that row and the new entry point's `path:line`. Then `performance-reviewer`
   traces the risk and not the whole diff. A record-named risk with neither a dispatch nor a
   decline is a process `[blocker]` on your verdict. The blocker is for the missing decision, not
   for the code. Whether a decline answers the row is your judgment. The panel line shows it.

   `review-lead` can report that the review did not run (its panel went dark). Then you have no
   verdict to give. Say which reviewer went dark in a plain comment, and post no `verdict:` line.
7. **Design frames.** The `## Design frames` (or `## Design`) section of the record can have
   `| RS-n |` rows. Then render every screen at the head with the repo's render command
   (`design.liveRender.command`). Compare each screen with its frame. If you cannot render, you
   cannot approve: post `verdict: needs-work` with line 3 `reason: render-unavailable`.
8. **Post ONE PR comment.** Post it through [`gh-bot.sh`](../../tools/gh-bot.sh) when its
   `--status` is `ok`, and through plain `gh` otherwise. Pass the body with `--body-file`. The body
   follows this grammar exactly. The review prompt of `run.sh` states the same grammar:

   <!-- LOCKSTEP-BEGIN verdict-grammar -->
   The verdict comment has these parts, in this order and nothing else:
   - Line 1 is exactly `verdict: approve` or `verdict: needs-work`. Line 2 is exactly `reviewed: <the full sha of the head you reviewed>`. An optional line 3 is exactly `reason: render-unavailable`.
   - `## Summary`, right after line 2, or line 3 when it is present. Its first line is exactly `Mergeable as it is.` on an approve, or `Not mergeable yet.` on a needs-work. Then name each row scored `departed`, `violated` or `undeterminable`, with its score. Then write each action the human must take, one per line, or `Nothing to do.` Write no table. Use at most eight lines.
   - `## Decision record rows`, then a table headed `| Row | Score | Evidence |` and its `| --- | --- | --- |` line, with one row for every `D-n` row of the record at its first commit and at the head: a row the build deleted and a row it added are both scored. The Row cell's first token is the row's `D-n` id, and the Score cell's first word is one of `honored`, `violated`, `departed`, `undeterminable`. The section holds the table and blank lines only: per-row detail goes in the Evidence cell, anything else in `## Notes`. Other row kinds, such as `RS-n`, are not scored in this table.
   - `## Findings`, which runs to the next `## ` heading. Each finding starts with `- [blocker] B<n> ` or `- [note] N<n> `, and its continuation lines are indented two or more spaces. Suppressed findings are `[note]`s. A section with no findings holds the single line `None.`.
   - After its id and one space, a finding from review-lead's report carries that report's reviewer, file:line and confidence in its form: `- [blocker] B1 [Reviewer] file:line (confidence: N) — <text>`, file:line only where the finding has one. A finding you raise from a rule (a violated or undeterminable row, an untraced test-expectation change) or as a process note names its rule and carries no number: never invent a score.
   - `## Panel` (optional): the panel lines review-lead writes.
   - `## Notes` (optional): free prose for the human, such as process notes or `revised after reading the build's account: <what changed>`. Nothing in it counts toward the verdict.

   `Ready to merge?` is never written anywhere in the body.

   A `[blocker]` is something in the diff that must change before merge. The PR title and description are not the diff: a stale or wrong one is at most a `[note]`, never a `[blocker]`, and never makes a verdict `needs-work`. A `[note]` requires nothing. review-lead's findings translate one way: a Critical is a `[blocker]`; a Warning you would hold the merge for is a `[blocker]`, and any other Warning is a `[note]`; its "Ready to merge?" and "With fixes" are never written on this comment.

   `verdict: approve` means mergeable as-is: every record row is scored, none is `violated` or `undeterminable`, and there is no `[blocker]` and no `reason: render-unavailable` line. `verdict: needs-work` carries at least one `[blocker]`, a `violated` or `undeterminable` row, or the `reason: render-unavailable` line; under that line the rows need not be scored, and the findings may be `None.`.
   <!-- LOCKSTEP-END verdict-grammar -->

   <!-- LOCKSTEP-BEGIN kb-contributions -->
   Knowledge-base contributions: when review-lead's report has a `### Knowledge-base contributions` block, carry it into the verdict's `## Notes` as review-lead wrote it — the lead line `Knowledge-base contributions:` with one proposal per line under it, or the single line `Knowledge-base contributions: none`. review-lead applied the inclusion test the repo's review-context.md declares: do not apply it again, and add, drop or reword no proposal. Carry the whole list on every verdict, never only what changed since an earlier one: the earlier verdicts are collapsed once one binds. When the report has no such block, the verdict carries no contributions line. A proposal is a draft the operator files in the knowledge base: never a finding, and it never makes a verdict `needs-work`.
   <!-- LOCKSTEP-END kb-contributions -->

   <!-- LOCKSTEP-BEGIN verdict-style -->
   Write the verdict for the human who decides the merge.
   Use short sentences. An instruction has at most 20 words. A statement has at most 25 words.
   Write one instruction per sentence. Use the active voice.
   Do not use idioms, hedges or semicolon chains.
   Use the same word for the same thing every time.
   State each fact once. Do not repeat a fact from one section in another.
   In the rows table:
   - Keep each Evidence cell to one or two sentences.
   - Start the Evidence cell with the file:line or the test id. Then say what it shows.
   - Start the Evidence cell of a departed row with `Decided by <who> (<provenance>).` Then give the commit of the edit and the new resolution.
   - If the edit of a departed row names no decider, start its Evidence cell with `No decider named.`
   - Start the Evidence cell of a row that the build added with `Added by the build, <provenance>.`
   - Start the Evidence cell of a row that the build deleted with `Deleted by the build.` Then name who decided.
   - Put longer detail in `## Notes`.
   In `## Findings`:
   - Put blockers first and notes after them. Put dismissed and suppressed notes last.
   - Start the text after the dash of such a note with `Dismissed.` or `Suppressed.` Then give the reason in one sentence.
   - Give the defect in the first sentence of each finding.
   - Put the evidence on continuation lines. Indent them two spaces.
   - End each blocker with the continuation line `Fix: <one instruction>`.
   - Do not give a note a Fix line. A note requires nothing.
   - Write a note in at most three lines. Write a dismissed or suppressed note in one line.
   In `## Panel`:
   - Copy the panel lines that review-lead writes. Do not merge, drop or reword a line.
   - Do not repeat the panel reasons in `## Notes`.
   In `## Notes`:
   - Use one `###` sub-heading for each topic. Write at most six sentences under it.
   - Write an inventory, such as the mutation run, as a list.
   - Put the knowledge-base block last.
   - Do not write a sub-heading that has nothing under it.
   - Write a topic that changed no score or finding in one sentence, or leave it out.
   - Keep `## Notes` under 150 words, not counting the knowledge-base block.
   A limit never removes a row, a finding, a panel line or a knowledge-base proposal. If they do not fit, shorten the wording.
   <!-- LOCKSTEP-END verdict-style -->

   **Check the draft before you post it.** Write the body to a file. Write the record at `FIRST` to
   another file (`git show $FIRST:<record> > <file>`). Then run
   `bash <this skill's base directory>/../../tools/verdict-check.sh <draft> <record at the head> <record at FIRST>`
   ([the checker](../../tools/verdict-check.sh)). It prints every rule that the draft breaks. Fix
   the draft until the checker exits 0. Exit 2 means that it could not read a file. Fix the path.
   Never post on a check that did not run.
   The format matches the lane's own verdicts, but no scheduler reads this comment. A finished run
   has exited, and a re-launch builds before it reviews. The comment is for the human who decides
   the merge. Never edit it.

   Then collapse the earlier verdicts of the PR as outdated. Use the same `gh` that you posted
   through:
   `GH=<that gh> bash <this skill's base directory>/../../tools/minimize-verdicts.sh <pr> <comment id>`
   ([the script](../../tools/minimize-verdicts.sh)). The id is the number after `#issuecomment-`
   in the URL that your post printed. The script minimizes only lane-authored `verdict:` comments
   posted before yours. It never minimizes a notice or a comment by anyone else. If it fails, say
   so in your session output, not in a PR comment, and continue. Never retry it as yourself in
   the place of the bot.

   Then check `headRefOid` again. If it is no longer the sha on your `reviewed:` line, the head
   moved during your review. Post no status, and say so in a plain PR comment. Otherwise, post the
   same verdict as a commit status on that sha. Use the same `gh` (the bot when `--status` is
   `ok`). Never use a raw `gh api` call:
   `GH=<that gh> bash <this skill's base directory>/../../tools/post-review-status.sh <pr> <sha> <body file> <record at the head> <record at FIRST> <your comment's URL>`
   ([the script](../../tools/post-review-status.sh)). The script runs the checker again on the
   body you posted. Under `second-shift/review` it posts `success` for approve and `failure` for
   needs-work. An approve with red plan coverage posts nothing. A consumer that requires
   `second-shift/review` in branch protection cannot merge a PR without this status.
   - Exit 1: the body breaks a rule, or the plan coverage of the approve is red. No status was
     posted. Say so in a plain PR comment that names the failed rules or the coverage lines that
     the script printed. Never put a `verdict:` line in that comment.
   - Exit 3: the post failed. Say so in a plain PR comment. A 403 or 404 through the bot means
     that its GitHub App does not have "Commit statuses: write". Never retry it as yourself in
     the place of the bot.

   On an `approve` whose status posted, mark the PR ready for review with the same `gh`
   (`gh pr ready <pr>`). A lane PR stays a draft until a review approves its head, because GitHub
   refuses to merge a draft. If that fails, say so in a plain PR comment. Then stop.

## Rules that are not negotiable

- **Review the head you name.** Check `headRefOid` again just before you post. If the branch moved
  during your review, review the new commits and name the new head. A verdict that names an older
  head does not count.
- **Do not soften a blocker to keep a run moving. Do not invent a blocker to look thorough.**
- **Never end a turn with work that this turn started and has not collected.** A `review-lead`
  Workflow dispatch re-enters the session when it completes. Wait for it. A `&`-detached command
  or an armed `Monitor` at turn end is abandoned, not deferred.

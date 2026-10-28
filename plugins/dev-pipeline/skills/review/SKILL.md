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
   **Refuse the command for a PR that is not a lane PR.** A lane PR always names its decision
   record, because the build commits the record as the first commit of its branch. When the filter
   prints no `decisions.md` token, the PR is not a lane PR. Refuse this command at once. Tell the
   operator in one line that the PR is not a lane PR, and end the turn. Do nothing else.
   **Read the ticket yourself.** Under github, run `gh issue view <N> --json title,body,comments`.
   Under jira, use the `getJiraIssue` MCP tool, under whichever Atlassian namespace this session
   exposes. If you cannot read the ticket, you cannot review the PR: post `verdict: needs-work`
   with line 3 `reason: ticket-unreadable`.
   The filter is not a read of the build's account. Read no other part of the body before step 8.
2. Check out the PR head. Confirm that `git rev-parse HEAD` equals `headRefOid`. You review that
   sha, and you name it.
3. **Pass 1: review the diff from the ticket and the code alone.** Until step 4, do not open the
   decision record, the plan, the PR description, a PR comment or an earlier verdict. The diff is
   `origin/<base>...HEAD`, where `<base>` is the PR's base branch. Read it without the plans
   directory: `git diff origin/<base>...HEAD -- . ':(exclude)<plansDir>'`. Review it yourself, in
   this session, against the ticket. Read `.claude/second-shift/review-context.md` at the head
   when it exists. It is the repo's context for this review.

   <!-- LOCKSTEP-BEGIN review-completeness -->
   Review the diff for completeness. Check every acceptance criterion of the ticket against the diff. An acceptance criterion that the diff does not implement is a finding. An acceptance criterion with no test that proves it is a completeness finding, not a test-coverage problem, so it can be a `[blocker]`.
   <!-- LOCKSTEP-END review-completeness -->

   <!-- LOCKSTEP-BEGIN review-correctness -->
   Review the diff for correctness. For each unit that the diff changes, read its callers and its consumers. Check that each of them still works with the change. When the change adds a rule over stored data, read the data that the rule meets. Check the rule against the data that already exists. Walk every path through the change: each branch, each early return, each error and each empty input. Report each problem as a finding with its file:line and a concrete scenario: the input or state, and the wrong outcome it produces. A problem with no scenario is not a finding.
   A completeness or correctness problem is a `[blocker]` when it must change before merge. A maintainability, test-coverage or repo-convention problem is a `[note]` only, never a `[blocker]`.
   A finding that shows existing data or an existing caller breaking under the change is a `[blocker]`. The ticket's scope list, a record row or parity with an older version never makes it a note. It drops to a note only when the ticket or a record row names that exact case, accepts it, and names who decided. The ticket's own text counts as the operator's. A row names who decided when its provenance is `user-answered`, or `ticket-sourced` with its comment URL. A `user-delegated` or `codebase-derived` row never accepts a break. The finding then quotes that line. A finding that shows the change does not do what the ticket asks, for input that existing callers send, is a completeness `[blocker]`.
   The review runs in two passes. Pass 1 is the completeness and correctness review, from the ticket and the code alone. Pass 1 does not open the decision record, the plan or the PR description. It reads the diff with the plans directory excluded. It writes its findings to the scratch directory before pass 2 starts. When there is a record, pass 2 reads it at its first commit and at the head, and scores every row. A record row never removes, dismisses or downgrades a pass-1 finding. When a row decided the behavior that a finding shows breaking an existing caller, existing data or the ticket, the finding keeps its severity and names the row. Only two record grounds make a pass-1 finding a note: the accepted break above, and the test intent's exemption of an acceptance criterion from a test. A pass-1 finding is never posted as `Dismissed.` or `Suppressed.` on a record's ground.
   <!-- LOCKSTEP-END review-correctness -->

   End pass 1 with the notes pass. Report maintainability, test-coverage and repo-convention
   problems in the diff as `[note]`s with file:line. Report only what you would post. A note never
   gates. Write every pass-1 finding to a file in this session's scratchpad. Then start step 4.

   Dispatch no reviewer, except the one design-fidelity reviewer of step 7.
4. **Pass 2: read the record at its first commit and at the head.** The first commit is the commit that
   added the record: `FIRST=$(git log --format=%H --diff-filter=A -- <record> | tail -n 1)`. Read
   `git show $FIRST:<record>`. It shows what was decided before the build started. Then read the
   file at the head.
   - A row edited since `FIRST` is a departure. The edit must name who decided.
   - A row added since `FIRST` is a decision made during the build. Score it too. It must also
     name who decided.
   - When the PR body has `Record baseline: <sha>`, that sha is the baseline. The baseline can
     differ from the `FIRST` you computed, or it can be no ancestor of the head. Then the record
     commit was rewritten, and that alone is a blocker.

   Check every row of the record against the diff. The record's test intent can exempt an
   acceptance criterion from a test. Then the pass-1 finding that the criterion has no test becomes
   a `[note]` that quotes the exemption.
5. **Look at what the scheduler would have given you.** Read `git diff $FIRST..HEAD` and check
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
     files are `.claude/second-shift.config.json` and anything under `.claude/second-shift/`.
     You load these files from the head, so the PR is reviewed against the policy it edits.
     Trace each one to an acceptance criterion or a record row. An untraced one is a `[blocker]`
     that requires the citation. The edit itself is never the blocker.

   Then run the AC coverage check of the plan, as the scheduler does after its checks. Write the
   record at `FIRST` to a file (`git show $FIRST:<record> > <file>`). Then run
   `bash <this skill's base directory>/../../tools/plan-coverage.sh --head <record at the head> <record at FIRST> <plan at the head>`.
   The plan is `<plansDir>/<repo>-<key>-plan.md`, beside the record
   ([the script](../../tools/plan-coverage.sh)). The record at the head is read for one thing: an
   AC added after the baseline counts when a `D-n` row added or edited since the baseline carries
   `user-answered` or `user-delegated` provenance. The check names the row and its provenance, not
   who wrote it: the build records its own changes as `user-delegated`. You score that row anyway in
   step 6. Every baseline AC is still read from the baseline.
   - Exit 1 is a `[blocker]` that names what the check printed. The causes are an AC with no test
     task, a tag neither record defines, a tag only the head defines with no `user-answered` or
     `user-delegated` ledger change, an unparseable task line, or no plan.
   - Exit 3 is not-applicable: the record has no `## Test intent`, or the ticket has no AC block.
     It is never a blocker.
   - Exit 2 means that the check could not read the AC set of the record. Say so in `## Notes`.

   `post-review-status.sh` runs the same check and posts no `success` while the check is red.
   The next check proves that each tagged test fails on the tree of the record commit: the file
   under a runner of format `exit`, each named `file::case` under a reporting runner. Only
   the scheduler makes it. A lane run makes it before its review and reports it in the run block
   of the PR body. Do not run it: a session that runs tests in a worktree it controls does not
   give that proof. A PR built through `/dev-pipeline:build` took the `--handoff` path. On that
   path, the latest lane comment on the ticket is a `build-handoff` comment, and the body has no
   `## second-shift run` block. Nothing ran the check there. Say so in `## Notes` as
   `fails without the change: not run on the handoff path`. This is a note, never a blocker.
6. **Score EVERY row of the record** against the code. The scores are `honored`, `violated`,
   `departed` or `undeterminable`. A departed row was edited: name who decided, per its
   provenance. For an undeterminable row, say what you could not read. A violated or
   undeterminable row is a blocker. Do not approve when a row has either score.
   A row can name a deferred, unmeasured or inherited cost, load or performance risk. Still score
   that row on whether the code matches it. The row is the operator's decision. A score never
   overrides it. Its risk is also required performance work: the review states the worst-case
   bound as a finding. A bound that breaks an existing caller or existing data is a `[blocker]`
   under the severity rule of step 3. Any other bound is a `[blocker]` when it breaks what the row
   decided, and a `[note]` otherwise. The row permits the out-of-diff reads that check the bound.
   The row can name a file that the diff does not touch. That fact scores the row. It does not
   bound the risk.
7. **Design frames.** The `## Design frames` (or `## Design`) section of the record can have
   `| RS-n |` rows. Then do two things.
   - Dispatch one design-fidelity reviewer with the Agent tool. A handoff URL in the section
     picks it: a `figma.com` host picks `design-toolkit:figma-faithful-reviewer`, and a
     `claude.ai` URL under `/design` picks `design-toolkit:design-faithful-reviewer`. With no
     such URL, the config's `design.provider` picks it: `figma` picks `figma-faithful-reviewer`,
     and any other value, or none, picks `design-faithful-reviewer`. Give it the diff and the
     record. If you cannot dispatch it, or it returns no report, you cannot approve: post
     `verdict: needs-work` with line 3 `reason: seat-unavailable`.
   - Render every screen at the head with the repo's render command
     (`design.liveRender.command`). Compare each screen with its frame. If you cannot render, you
     cannot approve: post `verdict: needs-work` with line 3 `reason: render-unavailable`.
8. **Read the build's own account last, after pass 2.** Only then read the PR description and the
   build's PR comments. Use them to reconcile the departures and rebuttals they state.
   Measurements show that an author's framing lowers what a reviewer finds. If that reading
   changes a score or a finding, say so in the verdict's `## Notes`:
   `revised after reading the build's account: <what changed>`.

   **Post ONE PR comment.** Post it through [`gh-bot.sh`](../../tools/gh-bot.sh) when its
   `--status` is `ok`, and through plain `gh` otherwise. Pass the body with `--body-file`. The body
   follows this grammar exactly. The review prompt of `run.sh` states the same grammar:

   <!-- LOCKSTEP-BEGIN verdict-grammar -->
   The verdict comment has these parts, in this order and nothing else:
   - Line 1 is exactly `verdict: approve` or `verdict: needs-work`. Line 2 is exactly `reviewed: <the full sha of the head you reviewed>`. An optional line 3 is exactly `reason: render-unavailable`, `reason: ticket-unreadable` or `reason: seat-unavailable`.
   - `## Summary`, right after line 2, or line 3 when it is present. Its first line is exactly `Mergeable as it is.` on an approve, or `Not mergeable yet.` on a needs-work. Then name each row scored `departed`, `violated` or `undeterminable`, with its score. Then write each action the human must take, one per line, or `Nothing to do.` Write no table. Use at most eight lines.
   - `## Decision record rows`, then a table headed `| Row | Score | Evidence |` and its `| --- | --- | --- |` line, with one row for every `D-n` row of the record at its first commit and at the head: a row the build deleted and a row it added are both scored. The Row cell's first token is the row's `D-n` id, and the Score cell's first word is one of `honored`, `violated`, `departed`, `undeterminable`. The section holds the table and blank lines only: per-row detail goes in the Evidence cell, anything else in `## Notes`. Other row kinds, such as `RS-n`, are not scored in this table.
   - Fold the rows table. Put the line `<details><summary><N> rows: <k> honored, <k> departed, <k> violated, <k> undeterminable</summary>` and a blank line before the table, and the line `</details>` after it. N is the number of rows in the table, and each k is the number of rows with that score. Keep the scores in that order and leave out a score with no rows. Always write `rows`. Never write `<details open>`. A verdict that folds the table has a `## Summary`, so every row that is not honored stays visible. A table without the fold also passes.
   - `## Findings`, which runs to the next `## ` heading. Each finding starts with `- [blocker] B<n> ` or `- [note] N<n> `, and its continuation lines are indented two or more spaces. Suppressed findings are `[note]`s. A section with no findings holds the single line `None.`.
   - After its id and one space, a finding names its file:line and its defect: `- [blocker] B1 path:line — <defect>`. Its first continuation line is `Scenario: <input or state> → <wrong outcome>`. A finding that a dispatched reviewer raised names that reviewer in brackets before its file:line: `- [blocker] B1 [Reviewer] path:line — <defect>`. A finding you raise from a rule (a violated or undeterminable row, an untraced test-expectation change) or as a process note names its rule, and its file:line only where it has one. No finding carries a confidence number.
   - `## Notes` (optional): free prose for the human, such as process notes or `revised after reading the build's account: <what changed>`. Nothing in it counts toward the verdict.

   `Ready to merge?` is never written anywhere in the body.

   A `[blocker]` is something in the diff that must change before merge. The PR title and description are not the diff: a stale or wrong one is at most a `[note]`, never a `[blocker]`, and never makes a verdict `needs-work`. A `[note]` requires nothing.

   `verdict: approve` means mergeable as-is: every record row is scored, none is `violated` or `undeterminable`, and there is no `[blocker]` and no `reason:` line. `verdict: needs-work` carries at least one `[blocker]`, a `violated` or `undeterminable` row, or a `reason:` line; under that line the rows need not be scored, and the findings may be `None.`.
   <!-- LOCKSTEP-END verdict-grammar -->

   <!-- LOCKSTEP-BEGIN kb-contributions -->
   Knowledge-base contributions: when the repo's review-context.md has a `## Knowledge-base contributions` section, write a contributions block last in the verdict's `## Notes`. The candidates are what the record's `## Knowledge source` answer says the knowledge base does not cover (lookup gap), the page a `D-n` row names in `kb-conflict: <kb-page> (kb stale)` or `(kb ahead)`, and what this diff makes true that the knowledge base should state (change gap). Apply the inclusion test that the section declares, as written, to every candidate, and list only the candidates that pass. Write the lead line `Knowledge-base contributions:` with one proposal per line under it, in the format the section declares or as `- <kb-page> — <what to add or correct> (<gap kind>)`. When no candidate passes, write the single line `Knowledge-base contributions: none`. Carry the whole list on every verdict, never only what changed since an earlier one: the earlier verdicts are collapsed once one binds. When review-context.md has no such section, the verdict carries no contributions line. A proposal is a draft the operator files in the knowledge base: never a finding, and it never makes a verdict `needs-work`.
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
   In `## Notes`:
   - Use one `###` sub-heading for each topic. Write at most six sentences under it.
   - Write an inventory, such as the mutation run, as a list.
   - Put the knowledge-base block last.
   - Do not write a sub-heading that has nothing under it.
   - Write a topic that changed no score or finding in one sentence, or leave it out.
   - Keep `## Notes` under 150 words, not counting the knowledge-base block.
   A limit never removes a row, a finding or a knowledge-base proposal. If they do not fit, shorten the wording.
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
   Whoever edits a posted verdict in place later re-checks it with `GH=<that gh> bash <this skill's base directory>/../../tools/post-review-status.sh --recheck <comment id> <pr> <sha> <record at the head> <record at FIRST> <the comment's URL>`, which posts the status the edited comment implies, or `error` when it breaks a rule.

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
- **Never end a turn with work that this turn started and has not collected.** Wait for the
  design-fidelity reviewer you dispatched. A `&`-detached command or an armed `Monitor` at turn
  end is abandoned, not deferred.

---
name: review
description: The REVIEW half of the pipeline — review an open pipeline PR from a fresh top-level session, score every row of its decision record, and post one verdict comment for the human who decides the merge. The manual form of what /dev-pipeline:run's review session does; use it when a run ends review-unbound, or to review a lane PR by hand.
---

# review

Input a PR number. Output **one PR comment**: two fixed lines, the record's row table, then the
findings. Nothing is committed.

This runs as its own top-level session, and that is the entire point: the session that wrote the
code does not grade it. Never run it inside the build's session, and never resume an earlier
review's context.

> **Tracker delta (`tracker.type: jira`).** The checklist is the github default. Under jira the
> ticket key resolves from `Closes [<KEY>]` under the PR body's `### Jira Items` heading, not
> `Closes #N`. The verdict comment is a code-host write, not a tracker one, so it posts the same
> under both adapters. Nothing else differs.
> [Adapter contract](../../tools/tracker/jira/README.md).

## Checklist

1. `gh pr view <pr> --json number,headRefName,headRefOid,body,url` — the body names the ticket
   (`Closes #N`) and links the decision record (`<plansDir>/<repo>-<key>-decisions.md`).
2. Check out the PR head and confirm `git rev-parse HEAD` equals `headRefOid`. That sha is the one
   you review and the one you name.
3. **Read the record at its first commit and at the head.** The first commit is the one that added
   it: `FIRST=$(git log --format=%H --diff-filter=A -- <record> | tail -n 1)`. Read
   `git show $FIRST:<record>` — what was decided before the build started — and the file at the
   head. A row edited since `FIRST` is a departure; the edit must name who decided.
4. **Look at what the scheduler would have handed you**, from `git diff $FIRST..HEAD`: deleted or
   renamed test files, added skips or forced-green lines (`.skip(`, `.only(`, `|| true`, …), and
   edits to CI or check configuration. Each is a question the diff must answer.
5. **Score EVERY row of the record** against the code: `honored`, `violated`, `departed` (the row
   was edited; name who decided, per its provenance), or `undeterminable` (say what you could not
   read). A violated or undeterminable row is a blocker; neither may stand beside an approve.
6. **Run `review-toolkit:review-lead` over the PR diff and declare the pipeline default panel**
   when you invoke it: the fan-out defaults to `scope-completeness-reviewer`; `security-reviewer`,
   `a11y-reviewer` and `unit-test-mutation-reviewer` are selected only by an opt-in — a
   `review panel` row in the record with `user-answered` or `user-delegated` provenance naming
   `security`, `a11y` or `unit-test-mutation`, or the config's `reviewers.default[]`.
   `review-lead` never infers this; an undeclared panel leaves the surface triggers in force.
   If it reports that the review did not run (its panel went dark), you have no verdict to give:
   say which reviewer went dark in a plain comment and post no `verdict:` line.
7. **Design frames.** When the record's `## Design frames` (or `## Design`) section carries
   `| RS-n |` rows, render every screen at the head with the repo's render command
   (`design.liveRender.command`) and compare it with its frame. If you cannot render, you cannot
   approve: post `verdict: needs-work` with a line `reason: render-unavailable`.
8. **Post ONE PR comment**, through [`gh-bot.sh`](../../tools/gh-bot.sh) when its `--status` is
   `ok`, plain `gh` otherwise. Its first line is exactly `verdict: approve` or
   `verdict: needs-work`; its second line is exactly `reviewed: <the full sha from step 2>`. Then
   the row table, then the findings. `approve` iff there are no blockers. The format matches the
   lane's own verdicts, but no scheduler reads this one: a finished run has exited, and a re-launch
   builds before it reviews. It is for the human who decides the merge. Never edit it. Then stop.

## Rules that are not negotiable

- **Review the head you name.** Re-check `headRefOid` just before posting; if the branch moved
  while you were reviewing, review the new commits and name the new head. A verdict naming an
  older head binds nothing.
- **Do not soften a blocker to keep a run moving, and do not invent one to look thorough.**
- **Never end a turn with work this turn started and has not collected.** A `review-lead`
  Workflow dispatch re-enters the session when it completes: await it. A `&`-detached command or
  an armed `Monitor` at turn end is abandoned, not deferred.

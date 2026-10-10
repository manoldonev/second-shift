---
name: review
description: The REVIEW half of the pipeline — review an open pipeline PR from a fresh top-level session, score every row of its decision record, and post one verdict comment for the human who decides the merge. The manual form of what /dev-pipeline:run's review session does; use it when a run ends review-unbound, or to review a lane PR by hand.
---

# review

Input a PR number. Output **one PR comment**: two fixed lines, the record's row table, then the
findings — and the same verdict as the `second-shift/review` commit status on the sha it names.
Nothing is committed.

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
   say so in the verdict: `revised after reading the build's account: <what changed>`.
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
   renamed test files (a top-level `tests/`, `__tests__/`, `test_*.py`, `conftest.py`, `_spec.`
   count too), added skips or forced-green lines (`.skip(`, `.only(`, `|| true`, pytest
   `skip`/`skipif`/`xfail`, Go `t.Skip(`, JUnit `@Disabled`, Rust `#[ignore]`, …), edits to CI or
   check configuration (`pyproject.toml`, `pytest.ini`, `setup.cfg`, `.coveragerc`, `Makefile` and a
   nested `package.json` included), and every `when`-scoped `extraLanes` entry no changed file
   matched — a configured lane that did not run on this diff. Each is a question the diff must
   answer, whatever the stack.
5. **Score EVERY row of the record** against the code: `honored`, `violated`, `departed` (the row
   was edited; name who decided, per its provenance), or `undeterminable` (say what you could not
   read). A violated or undeterminable row is a blocker; neither may stand beside an approve.
6. **Run `review-toolkit:review-lead` over the PR diff, pass it the ticket from step 1 yourself, and
   declare the pipeline default panel**
   when you invoke it: the fan-out defaults to `scope-completeness-reviewer`; `security-reviewer`,
   `a11y-reviewer` and `unit-test-mutation-reviewer` are selected only by an opt-in — a
   `review panel` row in the record with `user-answered` or `user-delegated` provenance naming
   `security`, `a11y` or `unit-test-mutation`, or the config's `reviewers.default[]`.
   `review-lead` never infers this; an undeclared panel leaves the surface triggers in force.
   Opting one of the three back in is your call, and **the expected call whenever the diff
   introduces a surface** rather than editing an existing one: `security` for a new
   authentication, session, tenancy or ownership-scoping path, or a new query built from external
   input; `a11y` for new form controls or a new interactive component; `unit-test-mutation` for
   new logic with a co-located spec. A change to a file that already sits on one of those
   surfaces is your call either way. Pass each short name to `review-lead` with a one-line
   reason. Do not stand in for a specialist on a surface the diff introduces: your lead pass is
   one reader over the whole diff, not that reviewer's checklist. The trim stays the default
   because it was measured; a diff it was never measured on is yours to judge. Declining a
   reviewer whose surface the diff introduces is itself a decision: pass the decline to
   `review-lead` with a one-line reason, it is written into the panel line of the review, and
   the human who reads the verdict reads that line. An introduced surface with neither a
   reviewer nor a reason is a silent decision.
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
   builds before it reviews. It is for the human who decides the merge. Never edit it.
   Then collapse the PR's earlier verdicts as outdated, with the same `gh` you posted through:
   `GH=<that gh> bash <this skill's base directory>/../../tools/minimize-verdicts.sh <pr> <comment id>`
   ([the script](../../tools/minimize-verdicts.sh); the id is the number after `#issuecomment-` in
   the URL your post printed). It minimizes only lane-authored `verdict:` comments posted before yours,
   never a notice or anyone else's. If it fails, say so in your session output — not in a PR
   comment — and go on; never retry it as yourself in the bot's place.
   Then re-check `headRefOid`. If it is no longer the sha on your `reviewed:` line, the head moved
   under your review: post no status, and say so in a plain PR comment. Otherwise post the same
   verdict as a commit status on that sha, with the same `gh` (the bot when `--status` is `ok`):
   `gh api -X POST repos/<owner>/<repo>/statuses/<sha> -f state=<success|failure> -f context=second-shift/review -f target_url=<your comment's URL> -f description='<approved|needs-work> at this head — see the verdict'`
   — `success` for approve, `failure` for needs-work. A consumer that requires
   `second-shift/review` in branch protection cannot merge a PR without it. If the post fails,
   say so in a plain PR comment (a 403/404 through the bot means its GitHub App lacks
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

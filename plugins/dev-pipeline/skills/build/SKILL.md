---
name: build
description: The interactive BUILD — the build half of /dev-pipeline:run, run in THIS session so the operator can steer it. run.sh claims the ticket, cuts the worktree, commits the intake record as the branch's first commit and hands over the same build prompt an unattended run spawns; you build to a draft PR, then /dev-pipeline:review grades it and marks it ready on an approve from a fresh session. Expects the same paid-off intake as /dev-pipeline:run.
---

# build

`run.sh --handoff` (`R`, here: `../run/run.sh` from this skill's base directory) does everything
`/dev-pipeline:run` does before the build, then stops with `terminal: build-handoff` instead of
spawning a build session. The build is yours, in this session. The prompt it hands you is the one
an unattended run would have spawned, so both paths build against the same record. What the
scheduler would do after its build is not done here: re-running the checks from the first commit,
the check that each tagged test file fails on the record commit's tree (`commands.<id>.testRunners`;
the review notes it as not run on this path), route smoke, the PR-convention check, the in-flight check, the round and cost caps, the run block
on the PR, and (under jira `writes: false`) stripping the Atlassian write tools.

## Checklist

1. **Launch** from a checkout of the ticket's repo: `bash R <issue> --handoff`. It runs in seconds
   (no `--detach`). A `terminal:` slug other than `build-handoff` is a refusal: read it in
   `/dev-pipeline:run`'s exit table and fix what the detail line names, exactly as for a run.
   Re-launching on a ticket the lane already claimed re-enters it. A config and record with no
   checks at all is refused (`env-no-checks`), as a run would refuse it.
2. **Read the `worktree:`, `baseline:` and `prompt:` lines** printed before the terminal, and run
   `printenv SS_WT SS_ADAPTER` in the Bash tool. When `SS_WT` is set, the herdr launcher
   (`herdr-adapter.sh build`) started this session with the worktree already added:
   `/add-dir <worktree>` is only the fallback if an edit there prompts. Otherwise the operator
   types `/add-dir <worktree>` now, so edits there do not prompt. Read the
   prompt file whole. It is the task: the ticket to fetch, the binding decision record (committed
   as the branch's first commit), the checks to make green, and the PR body's required lines.
3. **Build in the worktree.** Put the `cd <worktree>` in the same shell call as every command: the
   harness resets cwd between calls, and a stray call lands in the main checkout. The operator
   may steer. A steer that changes the decision of a record row is written into that row. Write
   the new resolution, set the provenance to `user-answered`, and end the cell with
   `Changed in build: <reason>`. A steer that makes a material decision no row covers becomes a
   new row, provenance `user-answered`, that ends with `Added in build: <reason>`. Commit either
   edit with the code. Never leave it in chat.
   Never amend, rebase or force-push over the `baseline:` commit: the review reads the record there.
4. **Open the PR** after every listed check is green. Open it as a draft and leave it a draft.
   Write the body in the order that the prompt gives: `built-by:` on line 1, then the sections the
   prompt lists, then the record link, `Record baseline:` and `Closes`. Put each steer from step 3
   in the `## Decisions made for you` table, with its row id and provenance.
5. **Hand off to review.** Tell the operator to run `/dev-pipeline:review <pr>` in a fresh
   session. In a session the herdr launcher started (`SS_WT` set), print the runnable
   `bash "<value of SS_ADAPTER>" review <pr>`, the path written out in full, which opens that
   fresh session in a `review` tab of the ticket's workspace. Do not review your own build, and never post a comment starting with `verdict:`.
   On `needs-work`, in this session fix each `[blocker]` finding or rebut it in a PR comment, and
   fix each record row scored `violated` or `undeterminable` (or edit the row, as step 3 allows);
   a `[note]` finding requires nothing: fix one only if you choose to, and never rebut or reply to
   one. Push; then a fresh review.
   While your handoff is the ticket's latest run comment, `/dev-pipeline:run <ticket>` refuses it
   (`claimed-elsewhere`) rather than build into your worktree; `--resume` hands it back to the lane.

## Rules that are not negotiable

- **Do not merge.** Merging is a human's act.
- **Under jira `tracker.writes: false`, make no Jira write**, even when steered to: this session
  keeps its Atlassian write tools, so the read-only contract is yours to keep.
- **Do not delete, skip or weaken a test to make a check pass.** If a test is wrong, say so in the PR.
- **Nothing between the handoff and the PR is checked by the scheduler.** The unattended run
  re-runs the checks itself from the first commit; here that is your job, so run all of them.
  That includes the plan's AC coverage when the record carries `## Test intent`:
  `bash <this skill's base directory>/../../tools/plan-coverage.sh <the record at the baseline commit> <the plan>`
  must exit 0 (or 3, not-applicable). The fresh review runs it again before it decides, and
  `post-review-status.sh` posts no approving `second-shift/review` status while it is red.

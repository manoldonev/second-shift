---
name: build
description: The interactive BUILD, the build half of /dev-pipeline:run, run in THIS session so that the operator can steer it. run.sh claims the ticket, creates the worktree and commits the intake record as the first commit of the branch. Then it gives you the same build prompt that an unattended run spawns. You build to a draft PR. Then /dev-pipeline:review grades the PR in a fresh session. On an approve, it marks the PR ready. Needs a completed intake, the same as /dev-pipeline:run.
---

# build

`R` is `run.sh`, at `../run/run.sh` from this skill's base directory. `R --handoff` does all that
`/dev-pipeline:run` does before the build. Then it stops with `terminal: build-handoff` and does not
spawn a build session. You do the build in this session. The prompt that it gives you is the prompt
that an unattended run would spawn, so both paths build against the same record.

This path does not do the steps that the scheduler does after its build:

- It does not run the checks again from the first commit.
- It does not check that each tagged test fails on the tree of the record commit
  (`commands.<id>.testRunners`). Under a runner with format `cases`, `vitest-json` or
  `jest-json`, the unit is the named test, `file::case`, not the file. It does not run the head
  leg either, where a test whose file does not load on that tree must pass. The review notes that
  this check did not run on this path.
- It does not run the route smoke, the PR-convention check or the in-flight check.
- It does not apply the round and cost caps.
- It does not write the run block on the PR.
- Under jira `writes: false`, it does not remove the Atlassian write tools.

## Checklist

1. **Launch** from a checkout of the ticket's repo, as a Bash call with `run_in_background`:
   `nohup bash R <issue> --handoff > <log> 2>&1`, with `<log>` in your scratchpad. The launch runs
   the setup lanes (`commands.<id>.lanes[]`) in the new worktree, and a cold install can outlast the
   2 minutes a foreground Bash call gets before it is killed. `--detach` is refused with
   `--handoff`. Do not poll the log: the background call re-invokes you when it exits. A
   `terminal:` slug other than `build-handoff` is a refusal. Find the slug in the exit table of
   `/dev-pipeline:run`, and fix what the detail line names, as for a run.
   If the lane already claimed the ticket, a new launch re-enters that claim. If the config and the
   record name no checks, the launch is refused with `env-no-checks`, as a run is.
2. **Read the `worktree:`, `baseline:` and `prompt:` lines** that the script writes to the log
   before the `terminal:` line. Then run `printenv SS_WT SS_ADAPTER` in the Bash tool. If `SS_WT` is set, the
   herdr launcher (`herdr-adapter.sh build`) started this session, and the worktree is already
   added. Use `/add-dir <worktree>` only if an edit there shows a permission prompt. If `SS_WT` is
   not set, the operator types `/add-dir <worktree>` now, so that edits there do not prompt. Read
   all of the prompt file. It is the task. It gives the ticket to fetch and the decision record
   that you must follow. The record is committed as the first commit of the branch. It also gives
   the checks to make green and the lines that the PR body must have.
3. **Build in the worktree.** Put `cd <worktree>` in the same shell call as each command. The
   harness resets the working directory between calls, so a call without the `cd` runs in the main
   checkout. The operator can steer the build. A steer that changes the decision of a record row is
   written into that row. Write
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
   session. If the herdr launcher started this session (`SS_WT` is set), print the command
   `bash "<value of SS_ADAPTER>" review <pr>`, with the path written in full. That command opens
   the fresh session in a `review` tab of the ticket's workspace. Do not review your own build.
   Never post a comment that starts with `verdict:`.
   On `needs-work`, do these steps in this session. Fix each `[blocker]` finding, or rebut it in a
   PR comment. Fix each record row scored `violated` or `undeterminable`, or edit the row as step 3
   allows. A `[note]` finding requires nothing: fix one only if you choose to, and never rebut or
   reply to one. Push, then tell the operator to run a fresh review.
   While your handoff is the latest run comment on the ticket, `/dev-pipeline:run <ticket>` refuses
   the ticket with `claimed-elsewhere`. This stops it from building into your worktree. `--resume`
   gives the ticket back to the lane.

## Rules that are not negotiable

- **Do not merge.** Merging is a human's act.
- **Under jira `tracker.writes: false`, make no Jira write**, even if the operator steers you to.
  This session keeps its Atlassian write tools, so you must keep the read-only contract yourself.
- **Do not delete, skip or weaken a test to make a check pass.** If a test is wrong, say so in the PR.
- **The scheduler checks nothing between the handoff and the PR.** The unattended run runs the
  checks again from the first commit. Here that is your job, so run all of the checks. When the
  record has `## Test intent`, also run the plan coverage check:
  `bash <this skill's base directory>/../../tools/plan-coverage.sh --head <the record at the head> <the record at the baseline commit> <the plan>`
  It must exit 0, or 3 (not-applicable). An AC added during the build counts only when the record
  at the head also carries the ledger row that decided it, with `user-answered` or
  `user-delegated` provenance; the baseline still governs every AC it defines. The fresh review runs this check again before it decides.
  While the check is red, `post-review-status.sh` posts no approving `second-shift/review` status.

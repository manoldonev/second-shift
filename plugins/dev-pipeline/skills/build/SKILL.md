---
name: build
description: The interactive BUILD — the build half of /dev-pipeline:run, run in THIS session so the operator can steer it. run.sh claims the ticket, cuts the worktree, commits the intake record as the branch's first commit and hands over the same build prompt an unattended run spawns; you build to a ready PR, then /dev-pipeline:review grades it from a fresh session. Expects the same paid-off intake as /dev-pipeline:run.
---

# build

`run.sh --handoff` (`R`, here: `../run/run.sh` from this skill's base directory) does everything
`/dev-pipeline:run` does before the build, then stops with `terminal: build-handoff` instead of
spawning a build session. The build is yours, in this session. The prompt it hands you is the one
an unattended run would have spawned, so both paths build against the same record. What the
scheduler would do after its build is not done here: re-running the checks from the first commit,
route smoke, the PR-convention check, the in-flight check, the round and cost caps, the run block
on the PR, and (under jira `writes: false`) stripping the Atlassian write tools.

## Checklist

1. **Launch** from a checkout of the ticket's repo: `bash R <issue> --handoff`. It runs in seconds
   (no `--detach`). A `terminal:` slug other than `build-handoff` is a refusal: read it in
   `/dev-pipeline:run`'s exit table and fix what the detail line names, exactly as for a run.
   Re-launching on a ticket the lane already claimed re-enters it. A config and record with no
   checks at all is refused (`env-no-checks`), as a run would refuse it.
2. **Read the `worktree:`, `baseline:` and `prompt:` lines** printed before the terminal, then
   `/add-dir <worktree>` (the operator types it) so edits there do not prompt. Read the
   prompt file whole. It is the task: the ticket to fetch, the binding decision record (committed
   as the branch's first commit), the checks to make green, and the PR body's required lines.
3. **Build in the worktree.** Put the `cd <worktree>` in the same shell call as every command: the
   harness resets cwd between calls, and a stray call lands in the main checkout. The operator
   may steer. A steer that departs from a record row is written into that row (new resolution,
   provenance `user-answered`, a one-line reason); a steer that makes a material decision no row
   covers becomes a new row the same way. Either is committed with the code — never left in chat.
   Never amend, rebase or force-push over the `baseline:` commit: the review reads the record there.
4. **Open the PR** exactly as the prompt says (ready, not draft; `built-by:` line 1; record link;
   `Record baseline:`; `Closes`), after every listed check is green.
5. **Hand off to review.** Tell the operator to run `/dev-pipeline:review <pr>` in a fresh
   session. Do not review your own build, and never post a comment starting with `verdict:`.
   On `needs-work`, address or rebut each finding in this session and push; then a fresh review.
   While your handoff is the ticket's latest run comment, `/dev-pipeline:run <ticket>` refuses it
   (`claimed-elsewhere`) rather than build into your worktree; `--resume` hands it back to the lane.

## Rules that are not negotiable

- **Do not merge.** Merging is a human's act.
- **Under jira `tracker.writes: false`, make no Jira write**, even when steered to: this session
  keeps its Atlassian write tools, so the read-only contract is yours to keep.
- **Do not delete, skip or weaken a test to make a check pass.** If a test is wrong, say so in the PR.
- **Nothing between the handoff and the PR is checked by the scheduler.** The unattended run
  re-runs the checks itself from the first commit; here that is your job, so run all of them.

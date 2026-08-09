# second-shift #442 — the lean lane destroys its worktrees

The lean lane creates a worktree per run and has never removed one. Two mechanisms close that,
both keyed on the pre-flight ledger at `.claude/pipeline-state/442-ledger.md`, which is binding
input and supersedes two factually wrong premises in the issue body (step 9 already says
"Remove the worktree"; `git worktree remove` from inside the worktree works).

1. **`bash G teardown <issue>`** — the at-approval path (D-1). The BUILD session's final act at
   step 9, after the closing comment and after `bash G 5`. Deliberately outside the 1..5
   progression (D-2): `cmd_all` runs milestones 1–5 and the checklist mandates it *before*
   step 9, so a self-removing milestone 5 would delete the worktree mid-run.
2. **An entry-time sweep** — invoked by `bash G entry <issue>` only (D-3). It runs before step 3
   cuts a worktree, so it is always executing outside the run's own. It covers the exits step 9
   never reaches: session died, PR merged by a human with no lean round, run abandoned.

Both share one precondition set and one removal, so a worktree can only be destroyed on terms
the other path would also accept.

## Acceptance criteria

**The teardown subcommand**

- **AC-1** `teardown` is a first-class subcommand of `lean-gate.sh`: it is accepted by the
  argument parser's subcommand enum, dispatched, and listed in the usage header `--help` prints.
- **AC-2** It locates the worktree by BRANCH, not by path (D-9): `git worktree list --porcelain`
  matched on `<branchPrefix><key>` as resolved by `branch-prefix.sh`. When no registered
  worktree is on that branch it says so and exits 0 — running it twice is not an error.
- **AC-3** It refuses to remove a worktree that is not clean, or that carries commits absent from
  `origin/<branch>` (D-7). Refusal means: leave the worktree in place, name the blocking files or
  commits, print the exact manual `git -C <main> worktree remove <wt>`, and exit **0** — hygiene
  is not evidence and the run is complete (D-6). A worktree merely BEHIND origin (the ordinary
  state after the review session pushes its verdict record) is removed, not refused.
- **AC-4** Neither path ever deletes a branch ref. After a successful removal the branch still
  resolves — the PR points at it and the verdict record is committed on it (D-8).
- **AC-5** Teardown sits outside the milestone progression: `bash G all <issue>` removes nothing,
  and no milestone body calls it (D-2).
- **AC-6** When `git worktree remove` itself refuses, teardown reports git's own message through
  the same keep-and-explain path as AC-3 and still exits 0.

**The entry-time sweep**

- **AC-7** `bash G entry <issue>` sweeps registered worktrees and removes those whose branch has
  a PR that exists and is **not OPEN** — merged or closed-unmerged (D-4) — subject to AC-3's
  preconditions. Merged-ness is read from PR state, never `git branch --merged`: this repo
  squash-merges, so a landed lean branch is never an ancestor of the base (D-5).
- **AC-8** The sweep keeps, each with a printed reason where it acted on one: a branch with an
  open PR; a branch with **no PR at all** (OR-1's reversible default — the only rule that would
  catch these is an age cutoff, which is the one criterion that can delete unpushed work); the
  main checkout; the caller's own worktree; and any branch that does not parse as
  `<branchPrefix><key>` for this repo's tracker (D-10) — those are skipped with no PR lookup.
- **AC-9** A failed `gh` lookup removes nothing: the sweep branches on exit status before reading
  output, names the branch whose lookup failed, and leaves that worktree in place (D-12). The
  sweep never changes `entry`'s own exit status — the audit-ledger predicate remains the sole
  decider of whether a run may start.
- **AC-10** No other subcommand sweeps. `claim` in particular does not (D-3).

**Documentation**

- **AC-11** `run-lean/SKILL.md` step 9 names `bash G teardown <issue>` in place of the bare
  "Remove the worktree", and step 1 states that `entry` also sweeps. The file stays within the
  60-line cap `lean-gate-selftest.sh` asserts (D-15).
- **AC-12** `review-lean/SKILL.md` stops presenting the build worktree as a durable location
  (D-13): step 3 notes it may already be gone, and step 4's exit-2 remedy names any checkout of
  the build host's clone — the progress file is anchored at the MAIN checkout via
  `--git-common-dir`, so the main checkout can always read an attestation the build worktree
  could.

## Out of scope

Lean worktrees that never got a PR (D-14 / OR-1). Neither mechanism reaches them and the sweep
says so rather than guessing; reversing that later costs one predicate.

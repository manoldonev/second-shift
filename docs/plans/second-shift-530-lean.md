# second-shift #530 — teardown accounts for every worktree on the lane branch

`cmd_teardown` locates its worktree through `lean_worktree_for_branch`, which prints and returns
on the **first** `git worktree list --porcelain` match. A second worktree on the same branch is a
sanctioned state, not a violated expectation (`review-lean/SKILL.md`: the build worktree "is not
guaranteed to be there" when a review session cuts its own checkout of the PR head) — so when one
exists, teardown removes one and orphans the other. Nothing else cleans it; only the next run's
`entry` sweep could, and only once that worktree's PR has closed. #531's D-3 gave `cmd_inflight`
(the scheduler's read of the same question, extracted by #531) the identical first-match defect at
a sharper boundary: a fail-open where the review tree reads clean while the build tree still holds
unpushed commits.

Pre-flight ledger: `.claude/pipeline-state/530-ledger.md`, interviewed against `main@3e83e46`
before #531 landed (`f9c8777`) — it is binding input and widens AC-2 (D-2) to cover both callers.

## Acceptance criteria

- **AC-1** *Retired — moved to #531 at that ticket's intake. The id is not reused.*
- **AC-2** Both `cmd_teardown` and `cmd_inflight` account for **every** registered worktree on the
  lane branch, not the first match (D-1, D-2):
  - `cmd_teardown` calls `worktree_destroy` on each registered worktree on `$LEAN_BRANCH` in turn.
    The caller's own tree (`$REPO_ROOT`) is ordered **last** and is never skipped (D-7) — removing
    it first would leave the remaining removals running from a deleted cwd, and `git worktree
    remove` already succeeds on the current worktree from inside it.
  - `cmd_inflight` evaluates `worktree_inflight` against every registered worktree on
    `$LEAN_BRANCH` and reports the strongest answer: **8 outranks 1, 1 outranks 0** (D-3) — a tree
    demonstrably holding work is more actionable than one nothing could read, and a clean tree
    outranks nothing. A tree that is passed over for a stronger answer elsewhere still prints its
    own reason as it is evaluated; it just does not go on to own the terminal exit code or message.
  - The shared helper is renamed `lean_worktrees_for_branch` (plural), printing one path per line
    instead of returning on the first hit (D-6) — there is no remaining consumer of the singular,
    first-match form once both callers iterate.
- **AC-3** A single `cmd_teardown` call that reaches both a removal and a keep records **both**
  progress rows, `kept` emitted last (D-4) — the row `progress --obligations` surfaces (the most
  recent `| teardown | <outcome> |` row) is then the state that still needs a human. Each row's
  detail lists that outcome's paths; a `kept` row's detail is `path — reason`, one clause per
  tree, on a single line. No new progress-file line kind is added: the existing `| teardown |
  <outcome> |` namespace and its `absent`/`removed`/`kept` values are unchanged (D-9).
- **AC-4** `cmd_teardown`'s exit code stays unconditionally 0 regardless of how many trees were
  removed or kept (D-8) — a kept tree remains a sanctioned state, not a failed run.
- **AC-5** Every precondition `worktree_destroy`/`worktree_inflight` already enforce per tree is
  unchanged and applies independently to each registered tree: a dirty tree is kept/reported
  in-flight, a tree carrying commits absent from `origin/<branch>` is kept/reported in-flight, a
  tree merely behind origin is removed/reported clean, and a removal `git` itself refuses is kept
  and reported through the existing path.

## Out of scope

- Whether `review-lean` should cut its own worktree at all — that is #525's question. This
  receipt takes the second tree as the sanctioned state the issue establishes and makes teardown
  and the in-flight read correct in its presence (not stated as an Open Region; see the ledger).
- OR-1 (a review session's tree removed by a concurrent BUILD close-out after it has pushed but
  before it exits) is accepted as reversible-default; see the ledger for the reasoning.

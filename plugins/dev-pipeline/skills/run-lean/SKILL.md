---
name: run-lean
description: EXPERIMENTAL lean alternative to /dev-pipeline:run — GitHub issue to ready PR, gated by five artifact milestones instead of ten prescribed stages. Outcome-gated: it asserts what exists, never how you got there. Use when per-run cost matters and the issue already carries paid-off intake (ready-for-dev, optionally a pre-flight ledger).
---

# run-lean (experimental)

Outcome-gated harness. `lean-gate.sh` asserts artifacts; **how** you produce them is yours.
Any skill surface (intake, review-lead, plan-interview) is an available pool — none is
mandated. Spend the tokens on the work, not on narrating it.

Read this whole file, then work the checklist. `G` = `lean-gate.sh` in this directory.

## Checklist

1. `bash G entry <issue>` — refuses without a live audit ledger. Non-negotiable: it is what
   makes the run reconcilable later. Then confirm the issue carries the queue label; a
   missing one is a reject, no prompting.
2. `bash G claim <issue>` — the two bot-wrapper writes (label swap + `lean-claimed` marker).
   Export `RUN_ID` first (neutral token, `[A-Za-z0-9._-]+`); it keys every record.
3. Cut a worktree on `<lean prefix><issue>` from the configured base. Never work in the
   shared checkout. `bash G 1 <issue>` prints the exact spec path it wants.
4. **Write the spec/AC file** at that path, ≥ 1 numbered `AC-n`. It is the living definition
   of done: if scope changes, amend the `AC-n` set *before* milestone 5. A pre-flight
   `<issue>-ledger.md` is binding input when present. `bash G 1 <issue>`.
5. Implement. Commit through `bot-commit.sh` — and re-pass the identity on any `--amend`,
   which otherwise silently re-stamps you as the committer.
6. `bash G 2 <issue>` then `bash G 3 <issue>` — policy invariants, then the green gate.
7. **Milestone 4 — the one place quality spend is concentrated.** Dispatch
   `workflows/lean-review.mjs` (`{worktree, base, head, issue, specPath, round, config}`;
   pass only `{reviewers}` as config). Write the returned verdict into the **committed**
   verdict record — path from `bash G 4 <issue>` — carrying verdict, rounds, finding summary,
   and `run_id`. Append `milestone-4 | verdict=<v> | round=<n>` to the progress file. Fix
   every blocker and re-review; only a committed `verdict=approve` passes.
8. Compute the cost block once (`pipeline-cost-block.sh --stateless`, session ids + time
   fence from the progress-file header). Open a **ready** (non-draft) PR: summary, spec
   link, one-line verdict, `Closes #<issue>`, **and the same cost block appended to the PR
   description** — reviewers read the PR, not the issue thread, so cost visibility belongs
   there too, not only in the closing comment. No stage sections. Post one closing comment:
   PR link, verdict-record reference, and the same cost block.
9. `bash G 5 <issue>` — exit artifacts. Then drop the claimed label and remove the worktree.

## Rules that are not negotiable

- **3 fix attempts per milestone.** The 4th red (`rc=4`) hard-stops: append the reason, post
  one abort comment naming the milestone, keep the worktree, leave the issue claimed for
  manual rescue. Do not re-run past a hard stop.
- **`rc=0` from a gate is the only evidence it passed.** Never record a milestone as done
  because it looked done; `bash G all <issue>` re-evaluates everything against the current
  tree, so run it before step 8 — a milestone satisfied before a fix round is stale.
- **Two tracker writes per clean run**: the claim comment and the closing comment.
- Doc updates are AC-scoped — a change that makes docs stale needs an explicit doc `AC-n`.

## Resume

Re-read the progress file, `bash G all <issue>`, continue at the first unsatisfied milestone.
Counters survive. Rebase the worktree first if the base moved.

Integrity lives at the merge boundary (`scripts/check-lean-chain.sh`) and in the operator's
`lean-reconcile.sh`, not here — so gaming a local counter buys nothing but a red PR.

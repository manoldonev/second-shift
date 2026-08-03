---
name: run-lean
description: The default dev-pipeline lane — GitHub issue to ready PR, gated by five artifact milestones. Outcome-gated: it asserts what exists, never how you got there. Expects an issue with paid-off intake (ready-for-dev, optionally a pre-flight ledger).
---

# run-lean

Outcome-gated harness. `lean-gate.sh` asserts artifacts; **how** you produce them is yours.
Any skill surface (intake, plan-interview) is an available pool — none is mandated. Spend the
tokens on the work, not on narrating it. The one thing that is NOT yours is the review verdict:
it is authored outside this session (`/dev-pipeline:review-lean`). Read this whole file, then
work the checklist. `G` = `lean-gate.sh` in this directory.

## Checklist

1. `bash G entry <issue>` — refuses without a live audit ledger. Non-negotiable: it is what
   makes the run reconcilable later. Then confirm the issue carries the queue label; a
   missing one is a reject, no prompting.
2. `bash G claim <issue>` — the two bot-wrapper writes (label swap + `lean-claimed` marker).
   Export `RUN_ID` first (neutral token, `[A-Za-z0-9._-]+`); it keys every record. The gate
   caches it to `<issue>-run-id` so later `bash G ...` calls (each a fresh shell) resolve
   the same id without re-exporting; a mismatch is exactly what `lean-reconcile.sh` catches.
3. Cut a worktree on `<lean prefix><issue>` from the configured base. Never work in the
   shared checkout. `bash G 1 <issue>` prints the exact spec path it wants.
4. **Write the spec/AC file** at that path, ≥ 1 numbered `AC-n`. It is the living definition
   of done: if scope changes, amend the `AC-n` set *before* milestone 5. A pre-flight
   `<issue>-ledger.md` is binding input when present. `bash G 1 <issue>`.
5. Implement. Commit through `bot-commit.sh` — and re-pass the identity on any `--amend`,
   which otherwise silently re-stamps you as the committer.
6. `bash G 2 <issue>` then `bash G 3 <issue>` — policy invariants, then the green gate.
7. Compute the cost block once (`pipeline-cost-block.sh --stateless`). Open a **ready**
   (non-draft) PR: summary, spec link, `Closes #<issue>`, and the cost block appended to the
   description too — reviewers read the PR, not the issue thread. No stage sections.
8. **Milestone 4 arrives from OUTSIDE.** Dispatch no reviewer — the verdict record is written
   by a separate top-level session (`/dev-pipeline:review-lean <pr>`) with its own identity,
   and this gate refuses one carrying yours. Hand off, resume when the record is on the
   branch; `bash G 4 <issue>` passes only on a committed `verdict=approve`. On `needs-work`,
   fix every blocker, push, and ask for a **new** review context — never a resumed one.
9. Post one closing comment: PR link, verdict-record reference, same cost block. Then
   `bash G 5 <issue>` — exit artifacts. Drop the claimed label and remove the worktree.

## Rules that are not negotiable

- **You never author the verdict.** Not on a dark reviewer, not to unblock a run, not "to be
  replaced later" — the gate and the merge boundary both refuse it.
- **3 fix attempts per milestone.** The 4th red (`rc=4`) hard-stops: append the reason, post
  one abort comment naming the milestone, keep the worktree, leave the issue claimed for
  manual rescue. Do not re-run past a hard stop.
- **`rc=0` from a gate is the only evidence it passed.** Never record a milestone as done
  because it looked done; `bash G all <issue>` re-evaluates everything against the current
  tree, so run it before step 9 — a milestone satisfied before a fix round is stale.
- **Two tracker writes per clean run**: the claim comment and the closing comment.
- Doc updates are AC-scoped — a change that makes docs stale needs an explicit doc `AC-n`.

## Resume

Re-read the progress file, `bash G all <issue>`, continue at the first unsatisfied milestone.
Counters survive; rebase first if the base moved. Integrity lives at the merge boundary
(`check-lean-chain.sh`) and in `lean-reconcile.sh` — gaming a local counter buys only a red PR.

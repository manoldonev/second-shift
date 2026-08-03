---
name: review-lean
description: The REVIEW half of the lean lane — review an open lean PR from a fresh top-level session and produce the committed verdict record. Runs outside the build session by design; the build harness cannot produce this record.
---

# review-lean

Input a PR number. Output findings on the PR and a **committed verdict record** the build
run's milestone 4 and the merge boundary both read.

This runs as its own top-level session, and that is the entire point: the session that wrote
the code must not author its own evaluation. `lean-gate.sh verdict` refuses to run inside the
build session, so this cannot be folded back into the build lane by convenience.

`G` = `lean-gate.sh` in the sibling `run-lean/` skill directory.

## Checklist

1. Export a review identity before anything else — `RUN_ID=review-<issue>-<round>`, charset
   `[A-Za-z0-9._-]+`. It is cached per-issue under the review role, never shared with the
   build run's. A verdict carrying the build's id is refused in-gate and at the merge
   boundary.
2. `gh pr view <pr> --json number,headRefName,baseRefName,body,url` — the head branch resolves
   the issue key (`Closes #N` in the body) and the lean spec path.
3. Check out the PR head. The lean worktree the build run left behind is the usual place; any
   checkout of that branch works.
4. **Review.** `review-lead` over `<base>..<head>` is the implementation — no reviewer is
   defined here. The committed lean spec is the definition of done: score each numbered `AC-n`
   as satisfied / unsatisfied / undeterminable, and say which. `approve` iff there are no
   blockers; any blocker is `needs-work`. Do not soften a blocker to keep a run moving, and do
   not invent one to look thorough.
5. Write the record:
   `bash G verdict <issue> --pr <n> --verdict <approve|needs-work> --rounds <n> --summary-file <path>`
   The summary file carries the finding table and the per-AC scoring. The gate writes the
   reconciliation keys itself — do not hand-edit them in.
6. Commit and push the record to the PR's head branch through `bot-commit.sh`. It is evidence
   only once committed: nothing local reaches CI.
7. Post the findings as one PR comment (the build session reads the PR, not this transcript),
   then stop. On `needs-work` the loop round-trips through artifacts only: a build session
   addresses the findings, and a **new** review context produces the next verdict — never this
   one resumed.

## Rules that are not negotiable

- **Never write the verdict by hand.** The gate's refusals are the separation; a hand-written
  record bypasses all of them and reds at `scripts/check-lean-chain.sh` anyway.
- **One identity per review round.** Re-running a round reuses the cached id; a new round
  after a fix gets a new one, so the rounds stay distinguishable in the ledger.
- **Approve on the diff, not on the spec's promises.** An unmet `AC-n` is a blocker, and a
  spec amended after the fact to match the diff is itself a blocker.

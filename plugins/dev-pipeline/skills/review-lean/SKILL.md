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

> **Tracker delta (`tracker.type: jira`, `writes: false`).** The checklist below is the
> **github** default. Under jira: the issue key resolves from `Closes [<KEY>]` under
> `### Jira Items` in the PR body, not `Closes #N` (2). The step-8 findings comment is
> unaffected — it is a PR comment posted via `gh`, not a tracker write, so it posts the
> same under both adapters. No other checklist step differs.
> [Adapter contract](../run/tools/tracker/jira/README.md).

## Checklist

1. Export a review identity before anything else — `RUN_ID=review-<issue>-<round>`, charset
   `[A-Za-z0-9._-]+`. It is cached per-issue under the review role, never shared with the
   build run's. A verdict carrying the build's id is refused in-gate and at the merge
   boundary.
2. `gh pr view <pr> --json number,headRefName,baseRefName,body,url` — the head branch resolves
   the issue key (`Closes #N` in the body) and the lean spec path.
3. Check out the PR head. The lean worktree the build run left behind is the usual place; any
   checkout of that branch works.
4. `bash G delta <issue>` — the range this round must READ. Round 1 gets the whole branch diff.
   A later round gets the delta since the tree the previous round covered and inherits the rest
   by reference to that record; when there is nothing verifiable to inherit it prints the full
   range and says so. There is no flag: the range is derived from the committed records, so a
   round cannot claim a narrower reading than the branch supports, nor forget to declare one.
5. **Review** over the range step 4 printed. `review-lead` is the implementation — no reviewer
   is defined here. On an inheriting round, read the **prior record's findings** first: a round
   that inherits coverage without seeing what was previously found cannot tell a fixed blocker
   from a re-introduced one, and a blocker the build simply ignored leaves no trace in the delta
   at all. The committed lean spec is the definition of done: score each numbered `AC-n` as
   satisfied / unsatisfied / undeterminable, and say which. `approve` iff there are no blockers;
   any blocker is `needs-work`. Do not soften a blocker to keep a run moving, and do not invent
   one to look thorough.
5b. **Design fidelity — only when the spec's `## Design` section is armed** (a handoff link plus
   `| RS-n |` render-state rows; `Design: none — <reason>` means skip this step and score
   `not-applicable`). You are the design-SIGHTED reader; the panel's fidelity reviewer is not.
   In order, from the checkout of the reviewed head: (i) **staleness first** — compare the
   receipt's `rendered_from` against this checkout's own render patch id, because round-1
   screenshots under round-2 code must be caught before the round is spent, not by milestone 4's
   backstop after it; (ii) **hash-verify** every PNG the receipt lists — a mismatch in the same
   checkout is an evidence-inconsistency blocker; (iii) fetch the handoff frame through the
   provider surface and compare **per RS row**, scoring each one in the summary. Re-rendering is
   permitted only at the reviewed head, and say so when you do; there is no foreign-checkout
   fallback and no "mismatch expected" written in advance.
6. Write the record **from the checkout of the PR head**:
   `bash G verdict <issue> --pr <n> --verdict <approve|needs-work> --rounds <n> --fidelity <pass|fail|not-applicable> --summary-file <path>`
   The summary file carries the finding table and the per-AC scoring. The gate writes the
   reconciliation keys itself — including `reviewed_patch_id`, hashed from that checkout's own
   diff against the base, and `inherited_patch_id`, written every round and `none` on a root.
   `--fidelity` is yours and defaults to `not-applicable`, which an armed run refuses: forgetting
   it costs the round rather than certifying a design nobody looked at. Hand-edit none of them
   (quoting a key in the summary is safe — readers take the header), and do not run this from the
   main checkout: the record would name a patch you never reviewed.
7. Commit and push the record to the PR's head branch through `bot-commit.sh`, and let it be
   the **last** commit on the branch. It is evidence only once committed — nothing local
   reaches CI — and it is PATCH-BOUND: milestone 4, the merge boundary and `lean-reconcile.sh`
   all recompute that hash and refuse the record once any line outside it has changed. Commit
   nothing else in this session.
8. Post the findings as one PR comment (the build session reads the PR, not this transcript),
   then stop. On `needs-work` the loop round-trips through artifacts only: a build session
   addresses the findings, and a **new** review context produces the next verdict — never this
   one resumed.

## Rules that are not negotiable

- **Never write the verdict by hand.** The gate's refusals are the separation; a hand-written
  record bypasses all of them and reds at `scripts/check-lean-chain.sh` anyway.
- **One identity per review round.** Re-running a round reuses the cached id; a new round
  after a fix gets a new one, so the rounds stay distinguishable in the ledger.
- **Inheritance narrows what you READ, never what you must find.** Every `AC-n` is scored every
  round against the whole spec — the delta bounds the reading, not the verdict. Code an earlier
  round approved that the fix then touched IS in the delta, so it is read again; only what did
  not change is inherited. Read wider than the range whenever the delta looks misleading: more
  reading is always allowed, and a round that read everything is a strictly stronger record.
- **Approve on the diff, not on the spec's promises.** An unmet `AC-n` is a blocker, and a
  spec amended after the fact to match the diff is itself a blocker.
- **Four design blockers, on an armed run.** A fidelity failure against any RS row; a PNG whose
  hash disagrees with the receipt in your own checkout; a `Design: none` disarm you cannot justify
  on a repo that configures a design provider; and an RS table declaring fewer states than the
  handoff frames show. The last two are judgment the merge boundary cannot make — it sees only
  what the spec declared, so an under-declared table is invisible to it and lands here or nowhere.
- **Review the patch you will name — the record hashes it literally.** Re-check the PR head
  immediately before writing the record; if the branch moved while you were reviewing, review
  the new commits or start over. Once the record is pushed, any further push that CHANGES A
  LINE — a fix, a docs-only commit, a rebase that resolved a conflict — voids it and costs a
  new round. A rebase that replays the branch unchanged does not: the patch is the same.

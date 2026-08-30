---
name: review-lean
description: The REVIEW half of the lean lane — review an open lean PR from a fresh top-level session and produce the committed verdict record. Runs outside the build session by design; the build harness cannot produce this record.
---

# review-lean

Input a PR number. Output findings on the PR and a **committed verdict record** the build
run's milestone 4 and the merge boundary both read.

This runs as its own top-level session, and that is the entire point: the session that wrote
the code does not author its own evaluation.

`G` = `lean-gate.sh` in the sibling `build-lean/` skill directory.

> **Tracker delta (`tracker.type: jira`, `writes: false`).** The checklist below is the
> **github** default. Under jira: the issue key resolves from `Closes [<KEY>]` under
> `### Jira Items` in the PR body, not `Closes #N` (2). The step-8 findings comment is
> unaffected — it is a code-host write, not a tracker one, so it posts the same under both
> adapters and carries the bot identity under both wherever a bot is configured. No other
> checklist step differs.
> [Adapter contract](../../tools/tracker/jira/README.md).

## Checklist

1. Export a review identity before anything else — `RUN_ID=review-<issue>-<round>`, charset
   `[A-Za-z0-9._-]+`. It is cached per-issue under the review role, never shared with the
   build run's.
2. `gh pr view <pr> --json number,headRefName,baseRefName,body,url` — the head branch resolves
   the issue key (`Closes #N` in the body) and the lean spec path.
3. Check out the PR head **by branch name** — any checkout with that branch checked out works,
   and a DETACHED head does not: steps 4 and 6 derive their answer from the checkout they run
   in. The build run's
   worktree is the usual place but is not guaranteed to be there: the build session destroys it at
   approval, and a later `entry` sweeps the ones abandoned runs left behind. `gh pr checkout` on a
   same-repo PR gives the right name; on a fork-origin one it prefixes the owner, so
   `git switch -c <headRefName>` first.
4. `bash G delta <issue>` — the range this round must READ, from the step-3 checkout. An exit 2
   here means no entry attestation is READABLE — that record is host-local and gitignored, so
   re-run from a checkout of the build host's clone that has the lane branch checked out (the lane
   worktree is the obvious one; the record is anchored at `--git-common-dir/..`, which every
   worktree of that clone resolves to identically) before concluding anything. If it is genuinely absent, hand it
   back: a run whose audit ledger was never established is not yours to certify. Round 1 gets the whole
   branch diff. A later round gets the delta since the tree the previous round covered and inherits the rest
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
   one to look thorough. **An oracle `AC-n` proved by a CI run whose command and head both match
   this review is verified by citing that run (job, head SHA, conclusion), not by re-running it**
   — execute only when the command or the head differs from what CI ran ([discriminator](../../../../docs/testing.md#citing-a-ci-run-instead-of-re-running-it-review-side)).
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

   The scoring is written as a table under a `## Design fidelity evidence` heading in the
   `--summary-file`, and `--fidelity pass` on an armed ticket is **refused at the writer** without
   one. Columns exactly these six, in this order; every cell non-empty; one or more rows per
   declared `RS-n`, all of them and no others:

   ```
   ## Design fidelity evidence

   | RS-n | frame node | property | design | rendered | verdict |
   | ---- | ---------- | -------- | ------ | -------- | ------- |
   | RS-1 | Checkout / populated | control height | 32px | 32px | match |
   | RS-1 | Checkout / populated | unit selector | number field | text input | deviation (AC-3) |
   ```

   `verdict` is `match`, or `deviation (<ref>)` where `<ref>` is an `AC-n` or `D-n` **the spec
   declares** — a bare `deviation`, a free-text reason, and a citation the spec does not carry are
   all refused. A cited deviation does not force `fidelity: fail`: the point is that "the ticket
   decided this", which anything can check, replaces "I judged it fine", which nothing can. This
   makes your claim falsifiable by a human reader; it does not verify the render against the
   design, and no gate in this repo does.
5c. **A voided round is handed back, never recorded.** `review-lead` voids a round when every
   reviewer it selected went dark — it then emits a "review did not run" report naming the dark
   set, and answers no merge question. When that happens, stop before step 6: post the coverage
   gap as the step-8 PR comment, write **no** verdict record, and do not spend the round. Neither
   value is available to you — `needs-work` would report blockers nobody found, and `approve`
   would certify a review that never ran. Same precedent as step 4's missing entry attestation: a
   round with no coverage is not yours to certify. The separation still holds without a gate,
   because `check-lean-chain.sh` treats an absent verdict record as already a violation, so a
   hand-back cannot merge. Say plainly in the comment what went dark and why, so the build
   session knows it is waiting on infrastructure rather than on findings.
6. Write the record **from the checkout of the PR head**:
   `bash G verdict <issue> --pr <n> --verdict <approve|needs-work> --rounds <n> --fidelity <pass|fail|not-applicable> --summary-file <path>`
   The summary file carries the finding table and the per-AC scoring. The gate writes the
   reconciliation keys itself — including `reviewed_patch_id`, hashed from that checkout's own
   diff against the base, and `inherited_patch_id`, written every round and `none` on a root.
   `--fidelity` is yours and defaults to `not-applicable`, which on an armed run costs the round
   rather than certifying a design nobody looked at. Hand-edit none of them
   (quoting a key in the summary is safe — readers take the header), and do not run this from the
   main checkout: the record would name a patch you never reviewed.
7. Commit and push the record to the PR's head branch through `bot-commit.sh`, and let it be
   the **last** commit on the branch. It is evidence only once committed — nothing local
   reaches CI — and it is PATCH-BOUND: milestone 4, the merge boundary and `lean-reconcile.sh`
   all recompute that hash. Commit nothing else in this session.
8. Post the findings as one PR comment (the build session reads the PR, not this transcript) —
   through [`gh-bot.sh`](../../tools/gh-bot.sh) when its `--status` is `ok`, plain `gh`
   otherwise. This is a `pr comment` write, which `pr-revision` already mandates the wrapper
   for; posting it bare left the one comment a human actually reads under the operator while
   every other pipeline comment carried the bot. Then stop. On `needs-work` the loop
   round-trips through artifacts only: a build session addresses the findings, and a **new**
   review context produces the next verdict — never this one resumed.

## Rules that are not negotiable

- **Never end a turn with work this turn started and has not collected.** The scheduler spawns
  this session under `claude -p` exactly as it spawns the build one, and there turn end IS
  process exit: a `&`-detached command, a probe you mean to report on "when it lands", or an
  armed `Monitor` is abandoned, not deferred. Two build sessions were lost to that shape before
  it was written down. **Your long pole is not one of them.** A `Workflow` dispatch — how
  `review-lead` fans out — was MEASURED under `-p`: the session is re-entered when the workflow
  completes and reports its result normally. So await it. Do not arrange to collect it later,
  and do not restructure the panel around a death it does not have.
- **One identity per review round.** Re-running a round reuses the cached id; a new round
  after a fix gets a new one, so the rounds stay distinguishable in the ledger.
- **Inheritance narrows what you READ, never what you must find.** Every `AC-n` is scored every
  round against the whole spec — the delta bounds the reading, not the verdict. Code an earlier
  round approved that the fix then touched IS in the delta, so it is read again; only what did
  not change is inherited. Read wider than the range whenever the delta looks misleading: more
  reading is always allowed, and a round that read everything is a strictly stronger record.
- **Approve on the diff, not on the spec's promises.** An unmet `AC-n` is a blocker, and a
  spec amended after the fact to match the diff is itself a blocker.
- **A merge-boundary refusal is not a review round.** A red CI step that gates POLICY rather than
  code — the `Changelog:` trailer check, frozen files — is RECORDED and does not by itself make
  the verdict `needs-work`. The merge boundary already blocks on it, so refusing here buys WHEN it
  is fixed and not whether, at the price of a full build-and-review pair applying a fix no
  reviewer judgement shaped. Measured: #637's round 1 returned `needs-work` on exactly one
  blocker, a red policy-gate CI step (since deleted, #719); the fix was a single empty trailer
  commit, and round 2 then re-read the whole diff — 30:40, **58% of that run** (`docs/lane-latency.md`).
  The follow-through needs no new rule: if the policy fix changes a line you reviewed your record is
  void and a round happens anyway, and if it changes none — a trailer commit — your record stands.
  A red CORRECTNESS lane is the opposite and stays a blocker: `lint-and-selftests`, `selftests` and
  `mutation-sweep-pr` are evidence about the code, and an `AC-n` one of them contradicts is
  unsatisfied however green the diff looks.
- **Four design blockers, on an armed run.** A fidelity failure against any RS row; a PNG whose
  hash disagrees with the receipt in your own checkout; a `Design: none` disarm you cannot justify
  on a repo that configures a design provider; and an RS table declaring fewer states than the
  handoff frames show. The last two are judgment the merge boundary cannot make — it sees only
  what the spec declared, so an under-declared table is invisible to it and lands here or nowhere.
- **Review the patch you will name — the record hashes it literally.** Re-check the PR head
  immediately before writing the record; if the branch moved while you were reviewing, review
  the new commits or start over. Once the record is pushed, any further push that CHANGES A
  LINE — a fix, a docs-only commit, a rebase that resolved a conflict by editing one — voids it
  and costs a new round. A replay that changes none of your `+`/`-` lines does not, and neither
  does a base merge that leaves them all intact: the reviewed content is the same.

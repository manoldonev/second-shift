---
name: build-lean
description: The BUILD half of the lean lane — tracker ticket to ready PR, gated by five artifact milestones. Outcome-gated: it asserts what exists, never how you got there. Expects a ticket with paid-off intake (queue-labeled on GitHub, operator-supplied under jira; optionally a pre-flight ledger). Driven by /dev-pipeline:run-lean, and equally invokable on its own.
---

# build-lean

Outcome-gated harness. `lean-gate.sh` (`G`, here) asserts artifacts; **how** you produce them is yours — any skill surface (intake, plan-interview) is a pool, none mandated. Spend the tokens on the work, not on narrating it. The one thing NOT yours is the review verdict: it is authored outside this session (`/dev-pipeline:review-lean`). Read this file, then work the checklist.

`/dev-pipeline:run-lean` drives this block and `review-lean` for you, each in a fresh session. Invoked directly — the two-terminal manual flow — this block is unchanged and first-class: it stays the debugging and rescue path.

> **Tracker delta (`tracker.type: jira`, `writes: false`).** The checklist and rules below are the **github** default. Under jira: no queue label to confirm (1); claim writes nothing to the tracker, only the run-id record (2); the PR body carries `Closes [<KEY>]` under `### Jira Items` plus the verdict-record path (7); and there is no closing comment and no claimed label (9). [Adapter contract](../run/tools/tracker/jira/README.md).

## Checklist

1. `bash G entry <issue>` — refuses without a live audit ledger, which is what makes the run reconcilable later, and records that it passed. Not optional and not skippable: every later build-role call (`claim`, `1..5`, `all`, `delta`) exits 2 until that row exists. It is idempotent, so a run that started before this shipped self-heals with one call. It also sweeps away lane worktrees whose PR is no longer open — the exits step 9 never reaches. Then confirm intake is paid off: **either** the queue label, **or** the claimed label plus this lane's bot-authored `lean-claimed` marker on the issue — a run you are re-entering, since step 2 consumed the queue label the first time through. Neither is a reject, no prompting.
2. `bash G claim <issue>` — the two bot-wrapper writes (label swap + `lean-claimed` marker).
   Export `RUN_ID` first (neutral token, `[A-Za-z0-9._-]+`); it keys every record, and only `entry`/`claim` cache it to `<issue>-run-id` for the later fresh-shell calls to resolve.
   **Skip this step on a re-entry** — the marker is posted and the labels are swapped already, so a second claim only re-writes correct state. Export the run's ESTABLISHED id instead of minting one (`cat <issue>-run-id`, or the id preflight named): the cache seeds once and never clobbers, so a fresh token here would leave the run's records split across two identities.
3. Cut a worktree on `<lean prefix><issue>` from the configured base. Never work in the
   shared checkout. `bash G 1 <issue>` prints the exact spec path it wants — and refuses if the issue declares an unresolved `pause-and-ask` Open Region (get an operator comment first).
4. **Write the spec/AC file** at that path, ≥ 1 numbered `AC-n`. It is the living definition of done: if scope changes, amend the `AC-n` set *before* milestone 5. A pre-flight `<issue>-ledger.md` is binding input when present.
   With `design.provider` configured it also needs a `## Design` section — armed (handoff link + `| RS-n | route | state | AC refs |` rows) or `Design: none — <reason>`. Decide once: the disarm state-locks the moment milestone 3 arms. `bash G 1 <issue>`.
5. Implement. Commit through `bot-commit.sh` — and re-pass the identity on any `--amend`, which otherwise silently re-stamps you as the committer.
6. `bash G 2 <issue>` then `bash G 3 <issue>` — policy invariants, then the green gate. On an armed ticket that gate renders every RS row, hashes them into a receipt at `<plansDir>/<key>-lean-renders.md`, and reds until you commit it — blocking, on this milestone's budget, and re-run after any later commit.
7. Compute the cost block once (`pipeline-cost-block.sh --stateless`). Open a **ready** (non-draft) PR: summary, spec link, `Closes #<issue>`, and the cost block appended to the description too — reviewers read the PR, not the issue thread. No stage sections.
   Then `bash G mark <issue>` — the bot marker carrying this run's identity, which is what the boundary compares the verdict against. **Here, not at milestone 5**: a PR comment fires no `pull_request` event, so a marker posted after the review's push is invisible to the CI run that gates the merge. Idempotent; `bash G 5` re-calls it.
8. **Milestone 4 arrives from OUTSIDE.** Dispatch no reviewer — the record is written by a
   separate top-level session (`/dev-pipeline:review-lean <pr>`) with its own identity, and this
   gate refuses one carrying yours. Hand off; `bash G 4 <issue>` passes only on a committed `verdict=approve` whose `reviewed_patch_id` **is** this branch's current patch — and, when armed, whose `fidelity` is `pass` over a receipt rendered from that same patch. On `needs-work`, fix every blocker, push, and ask for a **new** review context — never a resumed one.
9. Post one closing comment: PR link, verdict-record reference, same cost block. Then `bash G 5 <issue>` — exit artifacts — and finally `bash G teardown <issue>`, which destroys the worktree (never the branch) or says why it kept it. But **leave the claimed label alone**: milestone 5 requires an open PR, so review is still in flight and the label is correct. The repository's unclaim workflow releases it when the item closes.

## Rules that are not negotiable

- **You never author the verdict.** Not on a dark reviewer, not to unblock a run, not "to be replaced later" — the gate and the merge boundary both refuse it.
- **Any CONTENT pushed after an approve costs another round.** The verdict is bound to the branch's patch, so a later commit reopens milestone 4; a rebase that replays the branch unchanged does not. Land every fix before the handoff.
- **3 fix attempts per milestone.** The 4th red (`rc=4`) hard-stops: append the reason, post one abort comment (github) naming the milestone, keep the worktree and the claim for manual rescue. A red that only means *the artifact is not written yet* — milestone 1 before the spec exists, i.e. the step-3 call — is recorded as `absent` instead, spends no fix budget, and hard-stops on its own far larger bound (10).
- **`rc=0` from a gate is the only evidence it passed.** Never record a milestone as done because it looked done; `bash G all <issue>` re-evaluates everything against the current tree, so run it before step 9 — a milestone satisfied before a fix round is stale.
- **Two tracker writes per clean run**, github only: the claim comment and the closing comment (an abort adds one). A `writes: false` tracker makes none. A `pause-and-ask` region open at milestone 1 needs another: the operator's resolving comment — as does an intent-gap record, which must be ratified before the handoff. The step-7 PR marker is a *source-control* write and is made under every tracker that has a bot.
- **Never end a turn with work this turn started and has not collected.** The scheduler spawns you under `claude -p`, where turn end IS process exit — so a `&`-detached command, a probe you plan to report on "when it lands", or an armed `Monitor` is abandoned, not deferred. Collect it in-turn or do not start it. Milestone 3 is the one long pole the harness takes off you: `bash G 3` detaches the evaluation itself and BLOCKS, so a reaped call re-issued rejoins the same runner rather than starting a second. `rc=7` means it did not complete — nothing was evaluated, no budget was spent, re-invoke.
- Doc updates are AC-scoped — a change that makes docs stale needs an explicit doc `AC-n`.
- **A decision the receipt never covered is not yours to make (P9).** Write the intent-gap record (schema: `interviewing-baseline`), follow its region's disposition, and ratify before the handoff — the merge boundary refuses `ratified: no`.

## Resume

Re-read the progress file, `bash G all <issue>`, continue at the first unsatisfied milestone — with one caveat until the verdict lands: `all` pre-checks the cheap assertions first, so while milestone 4 is outstanding (all of BUILD, and every fix round) it reports that and stops without evaluating 2 or 3. Run those directly then; once a `verdict=approve` record is committed the pre-pass is clean and `all` walks the whole progression — the state the mandated before-step-9 call runs in.
Counters survive; rebase first if the base moved. Integrity lives at the merge boundary — `lean-evidence.sh` (portable: verdict, identity, freshness, ratification; a consumer's CI fetches it at its pinned ref) wrapped by `check-lean-chain.sh` (**github-only** additions: the bot claim comment, the inheritance chain, the design receipt) — and in `lean-reconcile.sh`, which under jira drops the claim arm and runs the rest, saying so. Gaming a local counter buys only a red PR.

# second-shift #769 — Step 4b forbids the one action that recovers a dark reviewer

`review-lead` Step 4b currently tells a session that has just lost a reviewer to do nothing
about it:

> Under a pipeline-driven review the fan-out runs inside `code-review.mjs`, which already
> retried a dark reviewer once on-substrate; do **not** re-dispatch a dark reviewer yourself.

Followed exactly as written, that produced a completed review, a committed verdict record, and
an entire dimension nobody reviewed. Re-dispatching the same agent at the same tier with a
turn-numbered emit deadline returned a grounded verdict in 87 seconds — so the domain was
reviewable the whole time, and the round had simply been instructed not to try.

## Why the stated premise does not hold

The on-substrate retry is a **bit-identical** re-run: same prompt, same tier, same agent. For
the dominant death mode — the `maxTurns` cap with no text emitted — a bit-identical retry is
close to deterministic, which is why both attempts died the same way. "It already retried once"
is true and irrelevant: what failed was the _prompt_, and the session is the only layer that can
change it.

The visibility calibration compounds it. Because darkness reds nothing, the cheapest
correct-looking path is always to record the gap, and no pressure anywhere in the loop recovers
the coverage.

## What the session's edge actually is

The numbered emit deadline now ships in `BOUNDED_EXPLORATION`, so for the seven generic-branch
reviewers the deadline **alone** is a no-op — the substrate attempt already carried it. The
session's remaining edge is **narrowing**: it holds the diff and the round's context, so it can
re-dispatch scoped to the dark reviewer's domain rather than the whole range. That is why D-2
requires both, and why the deadline is a floor rather than an override (D-11).

## The escalation asymmetry

A still-dark reviewer is not one thing, so the posture is conditional on a declared set rather
than blanket (D-4, D-5). Two of them are grounded in contracts already in the file:

- **`security-reviewer`** — "Security defers when it is spawned": when the conditional fires,
  the lead pass's own security section is _not_ run. A dark security-reviewer therefore means
  nobody covered the dimension, unlike a dark `complexity-reviewer` whose dimension the lead
  pass collapsed.
- **Armed-spec design fidelity** — Step 4b-void case 2 already voids the round when this
  dimension is unrunnable, but only _pre-dispatch_ (toolkit-absent). A reviewer that dies
  _after_ dispatch on an armed spec is the same hole wearing different clothes, so case 2
  widens rather than a third case being added (D-8).

## Acceptance criteria

- **AC-1** — `review-lead` SKILL.md Step 4b requires **one in-session re-dispatch** of the dark
  reviewer — the same agent type, at the same declared tier — before a `[Coverage gap]` line may
  be written for it. The sentence forbidding re-dispatch is gone. The mandate is **not** scoped
  to pipeline-driven rounds: a standalone run has no on-substrate retry, so the mandate is the
  only retry it gets (D-1, D-12).
- **AC-2** — Step 4b states the two things that must make the re-dispatch prompt distinct from
  the one that died: a **turn-numbered emit deadline**, and **narrowing to the dark reviewer's
  domain** using the diff context the session already holds. It states that the tier is not a
  variable — promoting the model produces a different review than the panel selected — and that
  the deadline is a **floor**, so an agent doc carrying its own later turn number wins (D-2,
  D-11).
- **AC-3** — The mandate is scoped to Step 4b's **`died-after-retry`** signal only.
  `budgetExhausted: true` with an empty `reviewers[]` keeps today's behavior — the
  `[Coverage gap]` note plus Step 4b-void — and Step 4b says why: nothing was dispatched, so
  there is no failed prompt for the session to change (D-3).
- **AC-4** — Step 4b declares the escalation posture for a reviewer **still dark after** the
  re-dispatch, as a named set rather than a blanket rule (D-4, D-5):
  - `scope-completeness-reviewer` — hard "Ready to merge? = No", Step 4 unchanged;
  - `security-reviewer` — hard "Ready to merge? = No", and the text names the grounding: the
    lead pass suppressed its own security section because the subagent was spawned;
  - the armed-spec design-fidelity reviewer — a **void** (AC-5);
  - `db-reviewer`, `pipeline-reviewer`, `a11y-reviewer`, `unit-test-mutation-reviewer` and any
    repo-local `reviewers.add` reviewer — visibility notes, as today.
- **AC-5** — Step 4b-void's **case 2** is widened to cover a design-fidelity reviewer on an
  armed spec that dies _after_ dispatch and is still dark after the AC-1 re-dispatch. It stays
  one case, not a third, and remains the same dimension under the same armed condition (D-8).
  The armed-spec section that states the pre-dispatch void reads consistently with it.
- **AC-6** — Step 4b requires one **Review Summary** line when the re-dispatch **succeeds**,
  naming the reviewer, that it went dark, and that an in-session re-dispatch recovered it. A
  recovered reviewer is not a `[Coverage gap]` and its Verdicts row is its real verdict, not
  `Dark (no output)`; a still-dark reviewer keeps `Dark (no output)` (D-7).
- **AC-7** — `review-lean` SKILL.md step 6's `--panel` definition is amended to "reviewers the
  round obtained a usable result from, whether from the fan-out or a Step 4b re-dispatch". A
  still-dark reviewer stays absent from the list, preserving the key's anti-overclaim intent
  (D-6).
- **AC-8** — `docs/testing.md`, under **"Couplings considered and declined"**, records the
  Step 4b ↔ Step 4b-void ↔ `review-lean` 5c coupling: that it is real, that no new selftest is
  added, and why — a prose-presence guard is forbidden by `writing-tests`, and the sanctioned
  LOCKSTEP alternative needs byte-identical blocks, which these three are not (D-10).
- **AC-9** — `bash tools/prose-blockers.sh check` exits 0 on the branch. The Step 4b edits
  re-key content-derived construct ids, so `docs/prose-blocker-triage.tsv` is reconciled in the
  same PR — no undispositioned, unpruned, unresolved or stale rows.
- **AC-10** — No new selftest is added and no existing guard is weakened: the repo sweep
  (`SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh`) and
  `shellcheck` stay green.

## Out of scope

- `plugins/dev-pipeline/workflows/code-review.mjs` — the substrate already carries the numbered
  deadline; this ticket changes no substrate code (S-10).
- `review-lean` step 5c wording. It already reads "the provider's mandatory fidelity reviewer
  went dark, however many of the others returned"; AC-5 makes `review-lead` finally match what
  5c already asserts (D-9).

## Decision Ledger

| ID   | Decision                                                                                                            | Resolution                                                                                                                                                                                                                                                                                                                                                                                               | Provenance       |
| ---- | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| D-1  | Does Step 4b mandate an in-session re-dispatch before a coverage gap may be recorded                                | Yes. One in-session re-dispatch of the same agent at the same declared tier is required before a `[Coverage gap]` line may be written. The tier is not a variable; promoting the model produces a different review than the panel selected                                                                                                                                                               | user-answered    |
| D-2  | What makes the re-dispatch prompt distinct, given #770 already put a numbered emit deadline in the substrate branch | Two requirements. A turn-numbered emit deadline as a FLOOR, and narrowing to the dark reviewer's domain with the diff context the session already holds. Post-#770 the deadline alone is a no-op for the seven generic-branch reviewers, so narrowing is the session's actual edge                                                                                                                       | user-answered    |
| D-3  | Which of Step 4b's two darkness signals the mandate covers                                                          | `died-after-retry` only. `budgetExhausted: true` with an empty `reviewers[]` keeps today's Step 4b note plus Step 4b-void, because nothing was dispatched, so there is no failed prompt for the session to change                                                                                                                                                                                        | user-answered    |
| D-4  | Escalation posture when a reviewer is still dark after the re-dispatch                                              | Conditional on a declared reviewer set. Not a blanket "Ready to merge? = No", not a blanket visibility note                                                                                                                                                                                                                                                                                              | user-answered    |
| D-5  | The declared escalation set                                                                                         | `scope-completeness-reviewer` stays a hard No (Step 4, unchanged). Armed-spec design-fidelity becomes a VOID. `security-reviewer` becomes a hard No, grounded on the lead pass having suppressed its own security section because the subagent was spawned. `db-reviewer`, `pipeline-reviewer`, `a11y-reviewer`, `unit-test-mutation-reviewer` and repo-local `reviewers.add` adds stay visibility notes | user-answered    |
| D-6  | Whether a reviewer recovered by the re-dispatch counts for `review-lean` step 6's `--panel` key                     | Yes. The definition is amended to "reviewers the round obtained a usable result from, whether from the fan-out or a Step 4b re-dispatch". Without this the armed-spec gate refuses a round whose fidelity coverage the mandate recovered. A still-dark reviewer stays absent, preserving the key's anti-overclaim intent                                                                                 | user-answered    |
| D-7  | Whether a successful re-dispatch is visible in the round's artifacts                                                | Yes. One line in the Review Summary naming the reviewer, that it went dark, and that an in-session re-dispatch recovered it                                                                                                                                                                                                                                                                              | user-answered    |
| D-8  | How the armed-spec fidelity escalation is expressed in Step 4b-void                                                 | Widen existing case 2 to cover a fidelity reviewer that dies AFTER dispatch, not a third case. Case 2 is currently pre-dispatch only, stated at `plugins/review-toolkit/skills/review-lead/SKILL.md:214,217`. Same dimension, same armed condition                                                                                                                                                       | codebase-derived |
| D-9  | Whether `review-lean` step 5c needs a wording change                                                                | No. `plugins/dev-pipeline/skills/review-lean/SKILL.md:102-104` already reads "the provider's mandatory fidelity reviewer went dark, however many of the others returned". D-8 makes `review-lead` finally match what 5c already asserts                                                                                                                                                                  | codebase-derived |
| D-10 | The guard obligation for this change                                                                                | No new selftest. The `writing-tests` skill forbids prose-presence guards, and the sanctioned LOCKSTEP alternative needs byte-identical blocks, which Step 4b-void and 5c are not. Record the coupling in `docs/testing.md` under "Couplings considered and declined" with the reasoning                                                                                                                  | codebase-derived |
| D-11 | The deadline number the re-dispatch prompt carries                                                                  | A floor, not an override. Where the agent doc already carries a turn-numbered deadline the doc's number wins, per `check-emit-deadline.sh`'s own note that a per-agent number belongs in the agent doc and is free to be later than the floor                                                                                                                                                            | codebase-derived |
| D-12 | Whether the mandate reaches a standalone (non-pipeline) `review-lead` run                                           | Yes. The sentence being replaced is scoped "Under a pipeline-driven review", and its purpose was to forbid the re-dispatch. A standalone run has no on-substrate retry, so the mandate is the only retry there                                                                                                                                                                                           | codebase-derived |
| D-13 | Whether #769 is `harness-internal`                                                                                  | No. `review-lead` is a shipped consumer-facing skill and this changes what a consumer's review round does, so the label's "Ratified:" precondition does not apply. The ticket still needs `ready-for-dev` before the lane will take it                                                                                                                                                                   | codebase-derived |

## Open Regions

| ID   | Region                                                                                                                          | Disposition                 |
| ---- | ------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| OR-1 | Whether the D-5 escalation set is consumer-configurable, so a repo-local `reviewers.add` domain reviewer could opt into hard-No | reversible-default-and-flag |

OR-1 default: the set is fixed in the skill, exactly as D-5 states it. Reversing costs nothing
shipped, because adding a config key later is purely additive and no consumer can have depended
on its absence. Flagged in the PR body rather than pausing the build.

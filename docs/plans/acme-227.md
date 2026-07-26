# Plan — #227: order the Stage-8 skill load before the synthesis receipt

## Context

`statectl.sh` **[VERIFIED]** gates Stage-8 completion on two independent legs. The skill leg (line 596) asserts `stages.8.skillsLoaded[]` contains `review-toolkit:review-lead`; the receipt leg (`require_comment_receipts`, reached at line 605) asserts `comments["code-review"]` is a recorded URL. Both check **presence**. Neither checks **order**.

So a run can author its synthesis without the skill loaded, publish it, get refused by `set-stage`, load the skill purely to clear the refusal, and complete green. That happened on the #215 run: the `Skill` invocation landed 16 seconds after the synthesis comment it governs was already on the issue. The state file's `skillsLoaded` entry is truthful and the audit ledger corroborates the load — the gate simply cannot distinguish a real load in the wrong order from a real load in the right one. Worse, the refusal message names the remedy, so the gate actively teaches the cheap lapse.

`cmd_comment_add` (line 2451) **[VERIFIED]** is where the ordering can be made transitive: it is the write that turns a published comment into completion evidence, and it already reads state before mutating. Requiring the skill load *at receipt time* means the receipt cannot exist before the load, and `set-stage 8` already refuses without the receipt — so the two existing gates compose into an ordering constraint with no new artifact and no schema timestamps.

## Assumptions

1. **The `code-review` receipt is only ever recorded on a run that synthesized in-repo.** The receipt leg fires when `codeReviewRounds >= 1`, and a primary review round mandates review-lead synthesis (`SKILL.md` "Stage 8 skill loadout"). A run that only handed off or skipped posts no code-review comment at all.
2. **`skillsLoaded[]` survives a crash.** It is a committed state write, so a crash-recovery resume that already loaded the skill retains the evidence; the `--force` escape (D-2) covers the residual cases rather than being the normal path.
3. **No marker vocabulary change.** `code-review` is already in the generated stage-marker enum, so `tools/gen-statectl-validators.sh` and the enum drift-check are untouched.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | The stage-8 completion gate exempts its skill leg when `crossBoundaryReviews[]` or `skippedReviews[]` is non-empty. Does the new `comment-add` precondition mirror those exemptions? | No — the precondition is unconditional for the `code-review` marker. The receipt is only mandated when `codeReviewRounds >= 1` (a primary in-repo round), and such a run genuinely synthesized, so review-lead is genuinely mandated: refusing is correct, not a regression. A run that only handed off or skipped never calls `comment-add --marker code-review`. A mirror would also be inert — in the real Stage-8 order (`stages/8-code-review.md` line 252 records the receipt; the secondary loop that populates the escape arrays runs after), the arrays are still empty at receipt time. Recorded as a code comment so the asymmetry with line 596 reads as deliberate. | codebase-derived |
| D-2 | Does `--force` bypass the new precondition? | Yes. `state-schema.md` line 266 states "`--force` bypasses, as with every completion precondition"; the sibling skill leg's die message ends "--force for crash-recovery" and `(sl2)` already pins `rc_forced == 0`. `cmd_comment_add` parses `--force` today (line 2467). The wedge is real: a backgrounded post reconciled from a fresh session after a crash must stay recordable, or the run dead-ends at Stage 8 with no documented escape. | codebase-derived |
| D-3 | `(sl2)` builds its fixture in exactly the inverted order this change forbids (receipt at line 2095, skill load at 2098) and will go red. Force the `comment-add`, or re-author the case? | Re-author — no bypass needed. The stage-8 completion gate evaluates rounds → skill → receipt, so `(sl2)`'s "refused" leg fires on the skill message with **no receipt present at all**. Re-ordering to `review-rounds` → assert refused → `skill-load-add` → `comment-add` → assert allowed keeps the set-stage skill leg independently exercised and loses no coverage. Using `--force` instead would encode the inverted order as a sanctioned fixture, which is the thing being closed. | codebase-derived |
| D-4 | Does this close the #215 lapse outright? | No, and the plan says so rather than claiming it. The precondition orders the skill load before the **receipt write**, not before the synthesis is authored: a run can still publish, get refused, load, record, and go green. Rung 1 remains the right stop — the refusal now fires before any state records the synthesis, and the honest remedy becomes a re-synthesis rather than a 3-second skill load. AC-1's message requirement is satisfied by naming that explicitly (Step 1), per Scope item 2's "load it before you synthesize, not load it now". | codebase-derived |
| D-5 | Does the new gate contract need a `scenario-liveness-selftest.sh` extension? | Yes, one composed check. `CLAUDE.md` requires a new gate contract to extend the liveness scenario for every verdict path it touches. `scenario-lib.sh` (lines 107–108) already orders correctly, so the `no-split` green path proves the composed chain still reaches `mark-completed`; the missing half is the inverted-order path, which belongs in the scenario tier rather than the per-tool tier because it asserts a composed run cannot reach its terminal write. | codebase-derived |

## Affected files

- `plugins/dev-pipeline/skills/run/statectl.sh` **[VERIFIED]** — `cmd_comment_add` (line 2451) gains a `code-review` marker branch **[NEW]** carrying the precondition.
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` **[VERIFIED]** — re-author `(sl2)` (lines 2088–2110); add case `(cr5)` **[NEW]**.
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` **[VERIFIED]** — add the composed inverted-order check `(vs-order)` **[NEW]** (D-5).
- `plugins/dev-pipeline/skills/run/stage8-perrepo-review-selftest.sh` **[VERIFIED]** — line 86 records the receipt with no stage-8 skill load; add one.
- `plugins/dev-pipeline/skills/run/state-schema.md` **[VERIFIED]** — the comment-receipt leg prose (line 260) and the stage-8 precondition row (line 257).
- `plugins/dev-pipeline/skills/run/stages/8-code-review.md` **[VERIFIED]** — the receipt instruction (line 252) gains the ordering note.

## Reuse inventory

- `require_mutable` **[VERIFIED]** (`statectl.sh`) — already called by `cmd_comment_add`; the new check slots in after it, reusing the already-read `$current`.
- `die` + `EXIT_CODE` **[VERIFIED]** — the file's standard refusal mechanism; the new message follows the line-599 template (field path + remedial command + `--force` escape).
- The line-596 `jq -e 'index("review-toolkit:review-lead") != null'` predicate **[VERIFIED]** — mirrored verbatim rather than re-invented, so both gates read the same field the same way.
- `sct` / `sct_rc` / `sct_err` **[VERIFIED]** (`statectl-selftest.sh`) and `complete_stage` / `complete_run_vs` **[VERIFIED]** (`scenario-lib.sh`) — existing harness helpers for the new cases.

No new helpers introduced.

## Implementation steps

1. **Add the precondition to `cmd_comment_add`** (`statectl.sh`, after the `require_mutable` call, before the `jq` mutation). Guard on `[[ "$marker" == "code-review" ]]` — the function's first marker-conditional branch — and on `force` being unset, then assert the line-596 predicate against `$current`. The die message must name the ordering, not just the missing field: it says the skill must be loaded **before** the synthesis it governs is produced, and that recording the receipt after the fact does not satisfy the requirement (AC-1, D-4). Carry a short comment stating why the line-596 escape hatches are deliberately not mirrored (D-1).
2. **Re-author `(sl2)`** (`statectl-selftest.sh`): move the assert-refused pair above the `comment-add`, so the sequence is `review-rounds` → `err/rc` (skill message) → `skill-load-add` → `comment-add` → `rc` allowed. The `--force` walk on issue 9998 is unaffected. Assertion text unchanged in meaning (D-3).
3. **Add the new per-tool case** `(cr5)` **[NEW]** (`statectl-selftest.sh`, next to the existing `comment-add` validation case `(cr4)`): with stage 8 started and rounds recorded but `skillsLoaded[]` empty, `comment-add --marker code-review` exits non-zero and its stderr names the ordering (AC-1); after `skill-load-add --stage 8`, the same call succeeds (AC-2); `--force` bypasses the empty-`skillsLoaded` refusal (D-2); and a different marker (`plan`) is unaffected under the identical empty state (AC-4).
4. **Add the composed check** `(vs-order)` **[NEW]** to `scenario-liveness-selftest.sh` (D-5): drive a `no-split` run to stage 8 via `complete_stage`, then assert that the inverted order cannot reach the terminal write — the `comment-add` refuses, and with no receipt `set-stage 8 --status completed` refuses too, so `mark-completed` is unreachable. The existing green scenario (which already orders correctly) continues to reach `mark-completed`.
5. **Fix the third call site** (`stage8-perrepo-review-selftest.sh`): insert `skill-load-add --stage 8 --skill review-toolkit:review-lead` before line 86's `comment-add`. The line's own comment already reads "primary review done", so the load is honest there, not a workaround.
6. **Update the two docs**: `state-schema.md` line 260's comment-receipt-leg prose gains the ordering precondition (and its `--force` posture); the stage-8 row at line 257 notes that the receipt now implies the skill load. `stages/8-code-review.md` line 252 gains the ordering note at the instruction operators actually follow.

## Test strategy

Verify-after — this is infra behavior with no product surface. The change is a refusal path, so the tests are the contract: steps 2–4 are written to fail against a build without step 1 (AC-3), which is checked by reverting the precondition locally and confirming red before the final green run.

**Unit test surface:** `skip` — the repo declares no `commands.<host>.unitTestScope`, so there is no mutation surface. The behavioral contract lives in the `*-selftest.sh` tier, which steps 2–5 extend.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | `comment-add --marker code-review` exits non-zero without the recorded load; message names the ordering | 1 | `(cr5)` refusal leg — rc + stderr ordering assertion |
| AC-2 | Same call succeeds after `skill-load-add --stage 8` | 1 | `(cr5)` accept leg; `(sl2)` re-authored order |
| AC-3 | A selftest case covers both directions and is red without the precondition | 2, 3, 4 | `(cr5)` both legs + the `scenario-liveness` composed check; red-build confirmation in Verification |
| AC-4 | No other marker's behavior changes | 1 | `(cr5)` `plan`-marker leg under identical empty state; `(cr4)` and `complete_stage` 1/3/7/9 markers stay green |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

Plus the AC-3 red-build check: temporarily neutralize the step-1 precondition, confirm `(cr5)` and the scenario check fail, restore, confirm green.

## Risks / rollback notes

- **A legitimate flow becomes unrecordable.** Mitigated by D-2 (`--force`) and bounded by D-1's reasoning that the only callers of this marker are runs that genuinely synthesized. Rollback is deleting one guard block in `cmd_comment_add`.
- **The third call site is the real regression surface**, not the precondition itself: `stage8-perrepo-review-selftest.sh` goes red without step 5. Step 5 lands in the same commit as step 1.
- Unverified references: none. Every path, function, and line number above was read in the worktree.

## Out-of-scope

- Generalizing to every `(stage, skill, marker)` triple — the issue explicitly defers this until a second inversion appears. Stage 1's `intake-orchestrator` is dispatch-shaped and ran in the right order.
- Adding load timestamps to the schema, or any new artifact — the issue forecloses both.
- Closing the publish-then-load-then-record residual named in D-4; that would need a rung above 1.
- The pre-existing asymmetry where the stage-8 completion gate exempts its skill leg on a run that both synthesized in-repo **and** recorded a cross-boundary handoff. Noted while resolving D-1; untouched here.

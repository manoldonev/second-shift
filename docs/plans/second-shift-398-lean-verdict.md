# lean review verdict — #398

verdict=approve
run_id: review-398-2
session_id: c193b64d-6be4-4365-a5c8-50b5c2ad7805
rounds: 2
pr: #407
reviewed_head: 83256c39461896902e11e4aead43cc663e1ef632
reviewed_patch_id: 7a97e089c1e0bd8fe47bdb09178712f7589587c4
inherited_patch_id: none
inherited_from_verdict: none
model: unknown

# Review round 2 — PR #407 (issue #398), `lean/398`

Range from `lean-gate.sh delta 398`: **FULL** — `ca79bbf..HEAD`, 4 files. The gate refused to
inherit, and the reason is worth stating: round 1's fix was a **message-only history rewrite**,
so this round's tree is byte-identical to the one round 1 reviewed. `inherit_candidate` takes
the newest record whose `reviewed_patch_id` *differs* from the current tree's; here they are
equal (`7a97e089c1e0…` both), so there is no earlier tree to anchor a delta on. This round is a
chain **root** and re-read the whole diff on its own.

Read wider than the range in one place, deliberately: **every commit message on the branch**.
Round 1's only blocker lived in a commit body, and a message-only rewrite is invisible in any
tree diff — a round that read only the delta could not have seen either the defect or its fix.

Reviewers dispatched via `code-review.mjs`: maintainability, scope-completeness, security,
performance — the same panel round 1 used, re-run rather than inherited by reference, because a
root record claims coverage on its own. Complexity, test-coverage, db, pipeline,
unit-test-mutation not selected (no trigger). a11y + design-fidelity not routed: no changed path
matched `stageParams.webComponentGlobs` (unset; resolved default `apps/web/**/*.{tsx,jsx}`).

## Round-1 findings — disposition

| # | Round-1 class | Status | Evidence |
| --- | --- | --- | --- |
| 1 | **Blocker** — `Changelog: none — <rationale>` is not the no-op form | **fixed** | Both branch commits now carry a bare `Changelog: none.` Reproduced through the production awk programs verbatim (`extract_trailers` @`scripts/derive-release.sh:115`, `render_bullet`'s block-normalizer @`:240`): each commit renders as `- **<subject>**` with **no indented body**, and the concatenated squash-merge shape (two `none.` blocks) renders nothing at all. The remedy also stayed inside its bound — `branch_patch_id` is unchanged at `7a97e089c1e0bd8fe47bdb09178712f7589587c4`, so no reviewed line moved. |
| 2 | Warning — `README.md:43`'s "exactly **three** sites" is stale, and unfixable under AC-2 | **routed** | Filed as **#408** (open, `documentation`), covering both stale counts — `lean-gate.sh` "exactly three" (now 5 `TRACKER_TYPE` conditionals at `:657`, `:676`, `:775`, `:1557`, `:1575`, grouping to 4 sites) and `lean-reconcile.sh` "exactly one" (now 3, previously flagged as W2 on the #388 record and never filed). #408 also **corrects** round 1's own prose: `check_pause_and_ask` (`:775`) is reached from `cmd_1` — a milestone **1** check, not milestone 3. The substance of the warning is unaffected: the site is outside entry/claim/exit either way. |

The build session did not edit the committed round-1 record to correct that slip, which is
right — rewriting a verdict record from the build session would forge review authorship. The
correction lives in #408 and in this record.

## Findings

No blockers, no warnings, no suggestions. All four reviewers returned `approve` with zero
findings (`agents_error: 0`, 149k subagent tokens — round 1's panel died on unnamespaced agent
types and this one did not).

Suppressed (below threshold, all three independently consistent with the reading above):

- security — `README.md:24`, confidence 30: prose under `plugins/**` is an execution surface,
  but the deleted word is a count qualifier with no security semantics; the neighboring
  `tracker.writes: false` / single-outward-write framing is unchanged.
- scope-completeness, confidence 85: `README.md:43`'s "exactly three sites" is itself stale by
  one conditional, but AC-2 mandates that sentence be unchanged, so it is not a scope gap for
  #398 — route to a follow-up. (It is #408.)
- scope-completeness, confidence 90: `pr-gates` red on #407 is the lean-chain
  `verdict=needs-work` evidence arm reading the committed round-1 record, not a scope or suite
  defect.

The scope gate reached the second of those independently — no scope assertion from this
orchestrator reached its prompt.

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| **AC-1** | satisfied | Both sites drop the count and keep the pointer. `README.md:24-25` reads "the lean lane's adapter-sensitive operations follow it"; `jira/README.md:14` reads "The lean lane's adapter-sensitive operations are tabulated in `../README.md`", with its `#the-lean-lane-dev-pipelinerun-lean` anchor still resolving against the unchanged heading. A repo-wide `adapter-sensitive` grep over `*.md`/`*.sh`/`*.mjs` leaves no prose count of *lane operations* outside the plan/verdict archive; the one surviving hit in live prose is `lean-reconcile.sh:227`'s "The ONE adapter-sensitive **check**", which counts check sites, not lane operations, and is #408's territory. Neither sentence can now disagree with the table. |
| **AC-2** | satisfied (by its letter) | The whole diff under `plugins/` is two hunks, both `@@ -N,7 +N,7 @@` one-liners at `README.md:24` and `jira/README.md:14`. `README.md:43` is byte-unchanged, and the paragraph still separates gate branch sites from the lane operation table below it. Scored on the letter, as in round 1 — the accuracy of the sentence AC-2 preserves is round-1 finding 2, now routed to #408 and outside this AC set. |
| **AC-3** | satisfied | Diff touches four Markdown files and nothing else — no `.sh`, `.mjs`, CI workflow, or selftest. `lint-and-selftests` pass (8m33s); `selftests (macos, bash 3.2)` pass (12m29s). `pr-gates` is red on exactly one violation, "verdict record reads `verdict=needs-work`" restated across two arms — the expected pre-approve state, cleared by this record. `✓ spec`, `✓ claim`, `✓ authorship (review-398-1 distinct from run-398-ca79bbf)` all held through the force-push. |
| **AC-4** | satisfied | Both commits carry a `Changelog:` line, which is what AC-4 asks; and unlike round 1 the *form* is now correct too, so nothing carries over as a separate finding. |

## Verdict

`approve` — 0 blockers. Round 1's blocker is fixed at the source and verified by reproduction
rather than by assertion, and its remedy provably touched no reviewed line: the branch patch
identity is the same value round 1 recorded. The prose fix itself remains the right call —
dropping the count removes the coupling instead of re-pinning it, so the next row added to that
table cannot restale these two sentences a second time.

One thing this round is not: a clearance of the stale counts at `README.md:43`. Those are real,
they are the same class of drift this PR exists to remove, and AC-2 positively forbids fixing
them here. They are #408's, and #408 is open.

**Merge note.** `origin/main` advanced to `6fdd621` (`release: v3.8.5`) while this round was
running. That does not void this record: the reviewed id is anchored on
`merge-base(origin/main, HEAD)`, which is still `ca79bbf`, and the release touched no file in
this diff — re-verified after the advance, same `7a97e089c1e0…`. **Do not click "Update
branch"** on this PR. A merge commit moves the merge-base, which changes the branch patch
identity and voids this approve at the boundary for a purely mechanical operation.

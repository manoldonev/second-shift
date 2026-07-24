# Plan — #214: prune the mirror-harness/prose class, add the Workflow runtime shim, fix CI reachability

PR 1 of 5 for epic #213.

## Context / problem framing

The 40-agent adversarial audit behind #213 found the selftest suite is **not** mostly boilerplate (34/46 files KEEP), but the rot is real and concentrated in three places:

1. **Two `.mjs` mirror-harness suites** — `design-sync-selftest.mjs` and `null-reviewer-selftest.mjs` behaviorally test hand-maintained *copies* of production dispatch logic that still model the **retired pre-#169 transport**. Production has no `isNoStructuredOutputError`; its ladder is text-contract retry + emitter fallback. These suites pass green against code that no longer exists — the #204 pathology inside the tests built to prevent it.
2. **Prose-presence tails** in ~8 further files, plus one selftest (`slice-derivation-selftest.sh`) that is a self-vs-self re-implementation of markdown pseudo-code.
3. **Dark surfaces** — `plugins/audit-toolkit/scripts/audit-selftest.sh` had never run in CI under its original name (audit-self-test.sh dodged the `*-selftest.sh` discovery glob), and design-toolkit ships two real `node --test` suites no CI lane executes.

The structural replacement for the mirror class is a **runtime shim** that executes whole production `.mjs` bodies the way the Workflow runtime does, rather than re-testing hand copies of them.

## Assumptions

- The issue body Evidence section is **normative**, not commentary. AC-4 binds "prune-table rows", but the skeptic-mandated conditions live in Evidence prose; intake resolved these as binding (see Decision Ledger `D-1`).
- The base for LOC accounting is `a5a79a7` (branch point), measured at **10,709 LOC across 46 files** — recorded at intake.
- CI runs both lanes: ubuntu bash 5 and macos bash 3.2. Every edit must be bash-3.2 safe (no `mapfile`, no associative arrays).
- No `unitTestScope` is configured for this repo, so there is no mutation surface and the Stage-4/5 unit-test gate is `skip`.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Are the Evidence-section caveats binding, given AC-4 binds only prune-table rows? | Binding. AC-4 parenthetical undercounts the lockstep couplings (three named, four exist). The design-sync Case H1 rewire, the intake-readroot header rewrite, the null-reviewer header comment and the code-review.mjs:178 pointer prose are all in scope. | codebase-derived |
| D-2 | claim-selftest.sh Scope says stays whole; Evidence says TRIM the tail. Which wins? | Evidence. Keep the 6 behavioral cases plus the two parity pins at :155-156, add the behavioral --queue case, drop the 3 markdown greps at :162-170 and the 4 subsumed token pins. Leaving banned prose greps while the same PR writes the ban is incoherent. | codebase-derived |
| D-3 | The AC-6 exception list names 4 scripts; the tree has more unpaired. | Restate the CLAUDE.md rule as coverage-based rather than name-based pairing, list genuine exceptions, and mark the remaining dark gates as tracked by #215 rather than permanent exemptions. **Corrected at plan review:** audit-tool-calls.sh is NOT dark — audit-self-test.sh:17 exercises it as HOOK, and step 1 brings that suite onto the CI glob, so this PR itself closes it. The earlier grep missed it because the file name dodges the very glob step 1 fixes. Genuinely dark after this PR: check-plugin-version-bumps.sh and exitplan-ledger-gate.sh, both #215 scope. | codebase-derived |
| D-4 | design-sync Cases A/B/C: Evidence offers rewrite-or-delete; Scope silently picks delete. | Rebuild on the shim. The shim executes the whole production body, so args validation, budget clean-skip and normalizeFailClosed cost almost nothing to re-cover; deleting outright ships an unlabeled coverage loss. | codebase-derived |
| D-5 | AC-7 measures net selftest LOC but names no file set or command. | Pin the two-extension form covering both `.sh` and `.mjs`. The CI discovery glob is `.sh`-only, so the obvious mechanical reading would exclude the very suites being pruned. | codebase-derived |
| D-6 | The intake-pin coupling between 1-intake.md and 10-cleanup.md: lockstep-manifest row or DROPPED entry? | DROPPED entry. The two doc sites carry no identical pinnable line without restructuring, and the missed regression is a benign per-issue-namespaced worktree leak, not a verdict path. | codebase-derived |
| D-7 | Should the salvaged persisted-currentSlice precedence check land in scenario-liveness? | Deferred. The skeptic notes the harness composes executables and cannot run markdown, so guarding it requires first extracting the precedence snippet from 1-intake.md into an executable tool. That extraction is out of scope for a prune PR. Only the 3 BRANCH_PREFIX checks and the new out-of-order-refs fixture land, in statectl (mps). | deferred |

## Affected files/modules

**Created**
- `plugins/dev-pipeline/skills/run/workflows/runtime-shim-selftest.mjs` `[NEW]`
- `plugins/design-toolkit/skills/design-faithful/lib/design-lib-selftest.sh` `[NEW]`
- `docs/testing.md` `[NEW]`

**Renamed**
- `plugins/audit-toolkit/scripts/audit-selftest.sh` (from audit-self-test.sh, which dodged the discovery glob)

**Deleted**
- `plugins/dev-pipeline/skills/run/tools/slice-derivation-selftest.sh`

**Modified**
- `plugins/dev-pipeline/skills/run/workflows/design-sync-selftest.mjs`
- `plugins/dev-pipeline/skills/run/workflows/null-reviewer-selftest.mjs`
- `plugins/dev-pipeline/skills/run/workflows/workflows-mjs-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/diff-range-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/intake-readroot-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/score-review-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/is-inert-diff-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/prose-budget-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/claim-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh`
- `plugins/dev-pipeline/skills/run/tools/review-harness-fixtures/harness-plan-alpha.md`
- `plugins/dev-pipeline/skills/run/tools/pre-commit-typecheck-selftest.sh` (comment ref sweep)
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh`
- `tests/issue-forms-selftest.sh`
- `plugins/dev-pipeline/skills/run/workflows/code-review.mjs` (pointer prose only)
- `plugins/dev-pipeline/skills/run/workflows/design-sync.mjs` — **not pointer prose: a one-line production fix.** The shim found a live reference to the retired `STRUCTURED_OUTPUT_MANDATE` (#169) that this file never defines, so every gate dispatch threw `ReferenceError`. Recorded as a Stage-5 deviation; blocking prerequisite for AC-3.
- `plugins/audit-toolkit/skills/audit/SETUP.md`
- `scripts/lockstep-manifest.tsv`
- `CLAUDE.md`

## Reuse inventory

- `fakeAgent` behavior-queue pattern — `null-reviewer-selftest.mjs:104` region. Reused as the driver for the new shim rather than reinvented.
- `sed`-extract-and-execute technique — `tools/text-contract-selftest.sh`. The shim generalizes this from function-fragment extraction to whole-body execution; the existing suite stays as-is.
- `run_mjs` adapter — `workflows/workflows-mjs-selftest.sh:48-49`. The new shim registers as a third line; no new runner.
- `parity` / `anti_parity` helpers — `tools/claim-selftest.sh`. Reused for the new `--queue` behavioral case scaffolding.
- statectl `(mps)` section — `statectl-selftest.sh:376`. Receives the salvaged BRANCH_PREFIX checks; it already unsets `BRANCH_PREFIX` per-invocation, so no new harness plumbing.
- `node --test` — the runner for `design-lib-selftest.sh`; the absent-node FAIL posture copies `workflows-mjs-selftest.sh`.

No new shared helpers are introduced beyond the shim itself.

## Implementation steps

**Wave 0 — CI reachability (independent, lands first so the new lanes are green before anything is pruned)**

1. `git mv plugins/audit-toolkit/scripts/audit-self-test.sh plugins/audit-toolkit/scripts/audit-selftest.sh`; update the reference in `plugins/audit-toolkit/skills/audit/SETUP.md`. Run the suite locally — this is its first execution ever, so expect to fix genuine breakage rather than assume green. **Add a `SKIP_STRESS` guard to Test 4** (`:55-77`, `N=20` concurrent invocations): the repo verification lane runs `env SKIP_STRESS=1`, and an unguarded 20-way concurrency case would ignore that opt-out the moment the rename puts it on the CI glob.
2. Write `design-lib-selftest.sh` `[NEW]`: `node --test lib/extractor.test.mjs lib/emit.test.mjs`, absent node is FAIL (never silent green), following the `workflows-mjs-selftest.sh` precedent.

**Wave 1 — the shim (must precede the mirror prunes so coverage is never absent)**

3. Write `runtime-shim-selftest.mjs` `[NEW]`: strip the `export const meta = {…}` block by balanced-brace scan, wrap the remainder in `(async (agent, parallel, pipeline, args, log, phase, budget) => { … })`, drive with canned `fakeAgent` outputs.
4. Cover the production dispatch ladders: `code-review.mjs` text-contract retry → emitter fallback; `design-sync.mjs` gate-reviewer first-throw → `{error}`.
5. Per `D-4`, additionally cover `design-sync.mjs` args validation, the budget clean-skip branch, and `normalizeFailClosed` (all four #195 reasons).
6. Register in `workflows-mjs-selftest.sh`.

**Wave 2 — mirror prunes (lockstep-sensitive; steps 7+8 are one commit)**

7. `design-sync-selftest.mjs`: delete Cases A–F (`:168-282`). Keep G, H, I. **Rewire H1** to extract the inlined `FAIL_CLOSED_REASONS` array from `design-sync.mjs` source — the harness const at `:65` dies with Case C, and H1 at `:340` is its only remaining consumer. Thin the G tokens already covered by `text-contract-selftest.sh`. Update the stale header comment at `:13-14`.
8. **Same commit:** `null-reviewer-selftest.mjs` delete Cases A–E and G; trim the Case F `parseReviewResult` / `REVIEW_RESULT` / `` `${base}...${head}` `` pins. **And** `diff-range-selftest.sh` delete Case H (`:171-177`) — it greps the pin step 8 removes, so splitting these reddens both lanes. Keep the Case F wiring counts (`PROGRESSIVE_EMIT` appends == 2, `BOUNDED_EXPLORATION` == 1) — sole guard in the tree. Update the null-reviewer header (`:8-17`) and the `code-review.mjs:178` pointer prose.

**Wave 3 — slice-derivation removal (three-way lockstep, one commit)**

9. Salvage into `statectl-selftest.sh` `(mps)`: the 3 BRANCH_PREFIX checks, plus a **new out-of-order-refs fixture** — `git ls-remote` is lexicographic so `pr10` precedes `pr2` at ≥10 slices, which kills the last-wins mutant that survives today.
10. Delete `slice-derivation-selftest.sh`; drop `pipeline-doctor.sh` section 5c (`:261-267`) — not repoint, since `:237` already runs statectl-selftest. **Sweep every dangling reference, not just the fixture:** `harness-plan-alpha.md:99` (a listed path), plus the comment references at `claim-selftest.sh:5` and `:25` and `pre-commit-typecheck-selftest.sh:6`. Comment-only refs still name a file that will not exist — the stale-pointer class this PR is cleaning.

    **Pins consciously dropped with the file** (not silently lost): the 4 markdown parity greps over `1-intake.md` — `currentSlice // empty`, `${BRANCH_PREFIX}${ISSUE_NUMBER}`, `MAX_N`, and the all-pushed early-exit guard `MAX_N" -ge "$TOTAL_SLICES`. The mutant evidence shows these protect nothing today (an if/else precedence swap leaves every token intact, and the greps are file-wide so `${BRANCH_PREFIX}${ISSUE_NUMBER}` recurs at `1-intake.md:313` and masks section-local deletion). The 3 `max-pushed-slice.sh` greps are behaviorally subsumed by the salvaged statectl `(mps)` checks. Guarding the precedence invariant properly requires the tool extraction deferred in `D-7`.

**Wave 4 — prose-tail trims (mutually independent)**

11. `diff-range-selftest.sh`: delete Cases A/B, move the rationale into the header comment. (Case H already went in step 8.)
12. `intake-readroot-selftest.sh`: delete checks 4–6 (markdown prose); keep 1–3 (sanctioned mjs-seam pins); rewrite the header AC-5 claim to point at statectl-selftest.
13. `score-review-selftest.sh`: delete C1/C2; keep C3.
14. `is-inert-diff-selftest.sh`: delete the golden-master parity tail (`:103-158`); fold in two check rows (`.claude/x/y.py`, `.claude/x/y.tsv` — inert) that the tail uniquely covered.
15. `plan-lint-selftest.sh`: delete `pl-l` (`:139-146`).
16. `prose-budget-selftest.sh`: delete the T10 greps; **convert** the `PROSE_ALLOW_EMPTY_BASELINE` spelling-pin into a behavioral case (set the env var, assert an empty baseline is written, rc 0) — conversion is mandatory, not optional; it is the only coverage of that escape hatch anywhere. T11 precondition greps stay.
17. `issue-forms-selftest.sh`: delete the 9 top-level-key greps; replace the required/`--report` greps with per-field-anchored, **per-form-aware** checks — `review-false-positive.yml`'s `doctor-report` is `required: false` by design, so its load-bearing fields are `finding` / `code-under-dispute` / `why-fp`.

**Wave 5 — refuted prunes and policy**

18. `claim-selftest.sh` per `D-2`: add the behavioral `--queue` case (non-default labels, mock matching them, closing the parallel unpinned `$CLAIMED_LABEL` hardcode gap); keep `:155-156`; drop the 3 markdown greps and the 4 subsumed pins.
19. `second-shift-ci-check-selftest.sh`: keep the canary-ref-main case — verify only, no edit expected.
20. Record the intake-pin coupling in `scripts/lockstep-manifest.tsv` as a DROPPED entry per `D-6`.
21. `CLAUDE.md`: add the tier map and new-test placement rule; ban the reference-copy/mirror-harness technique by name; correct the pairing claim per `D-3`; reconcile the "grep is the only technique" framing — the surviving sanction narrows to what the shim cannot reach.
22. `docs/testing.md` `[NEW]`: the adversarial audit-workflow recipe, marked operator-run and never CI. Add a CLAUDE.md pointer following the `docs/releasing.md` convention.

## Test strategy

Verify-after (this is test-infrastructure refactoring, not behavior change). The suite itself is the test.

The load-bearing discipline for a prune PR is the **red-on-mutation demo** (repo idiom): for each *new or strengthened* guard, confirm it actually fails when the behavior it guards is broken —

- `runtime-shim-selftest.mjs`: break a dispatch ladder in a scratch copy of `code-review.mjs`, confirm red.
- statectl `(mps)` out-of-order-refs fixture: apply the last-wins mutant (`MAX=$n` unconditional), confirm red — it passes today, which is why the fixture is being added.
- `claim-selftest.sh` `--queue` case: hardcode the DELETE URL to `labels/ready-for-dev`, confirm red — this mutant passes all 7 current behavioral assertions.
- `design-lib-selftest.sh`: confirm absent node is FAIL, not silent green.

For pruned checks the obligation is inverse: confirm the *remaining* suite is still green, and that no deleted check was the sole guard on a live contract (the audit and skeptic verdicts already establish this per file).

Unit test surface: `skip` — no `unitTestScope` configured, so no mutation surface exists.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | audit-selftest.sh rename + SETUP.md ref; green both lanes | 1 | the renamed suite itself, now discovered by the CI glob |
| AC-2 | design-lib-selftest.sh runs both node suites; absent node FAILs | 2 | `design-lib-selftest.sh` + absent-node red-on-mutation demo |
| AC-3 | runtime-shim executes production bodies, covers dispatch ladders; registered | 3, 4, 5, 6 | `runtime-shim-selftest.mjs` + broken-ladder red-on-mutation demo |
| AC-4 | every prune-table row applied, incl. the lockstep couplings and the dangling-ref sweep | 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 20 | full selftest sweep green on both lanes |
| AC-5 | claim-selftest gains --queue case; ci-check keeps canary-ref-main | 18, 19 | `claim-selftest.sh` + hardcoded-DELETE red-on-mutation demo |
| AC-6 | CLAUDE.md tier map / ban / pairing claim / mjs framing; docs/testing.md | 21, 22 | — no test (non-functional) |
| AC-7 | net selftest LOC decreases vs. baseline, measured in the PR body per `D-5` | all | — no test (non-functional) |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

AC-7 measurement (per `D-5`), run at the base SHA and at HEAD:

```bash
find . \( -name '*-selftest.sh' -o -name '*-selftest.mjs' \) ! -path './.git/*' -print0 | xargs -0 wc -l
```

Baseline at `a5a79a7`: **10,709 LOC / 46 files**.

## Risks / rollback notes

- **Lockstep breakage is the headline risk.** Three couplings must land atomically: Case F trim + Case H delete (step 8); slice-derivation delete + doctor 5c drop + fixture sweep (steps 9-10); and the Case A–F delete + H1 rewire (step 7). Splitting any of them across commits reddens CI. Mitigated by committing each coupling as one unit.
- **First-ever execution of `audit-selftest.sh`** may surface real failures. That is the point of the rename, but it could expand scope; if the suite is substantially broken, fix forward minimally and record the residue rather than silently disabling checks.
- **Shim brittleness**: the meta-strip is a balanced-brace scan, not a parser. If a future `.mjs` puts a brace inside a string in the meta block the strip mis-cuts. Accepted — `check-model-tiers.sh` and the Case I meta-purity lint both constrain meta to literals.
- Rollback: every wave is an independent commit; reverting any single wave leaves the suite green except for the three noted couplings, which revert as units.

## Out-of-scope

- Covering the dark enforcing gates (`check-plugin-version-bumps.sh`, `exitplan-ledger-gate.sh`, `audit-tool-calls.sh`) — that is PR 2 / #215. This PR only records them honestly in the CLAUDE.md pairing claim.
- Extending scenario-liveness reach (#216), the E2E null-model replay (#217), the mutation sweep (#218).
- Extracting the persisted-currentSlice precedence snippet from `1-intake.md` into an executable tool — see `D-7`.
- Stacked-prs terminal liveness, which #213 defers to #211.
- Any version bump or CHANGELOG edit — those are derived at release time and are frozen in feature PRs.

Unverified references: none. Every path, line number and symbol above was confirmed by read or grep in this worktree.

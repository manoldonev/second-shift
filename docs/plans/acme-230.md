# Plan — #230: key the `implementation_resilience` PASS gate on charged evidence, not on lane

## Context / problem framing

`statectl.sh`'s `require_eval_file()` refuses a generous `implementation_resilience: "PASS"` only when the run was **inert**. Its predicate is:

```
(any_suite_object or any_test_failure) | not
```

`any_suite_object` is true on every SUITE-lane run, so the whole predicate is false and the gate never fires there — regardless of whether a single test ever failed. But `eval-criteria.md`'s criterion 3 does not test the lane; it tests whether the resilience mechanism was **exercised**, and its `N/A` clause reads "no executable test surface … **or otherwise produced zero test failures**". A green SUITE run meets the `N/A` bar exactly as an inert one does, and walks through today.

The fix drops the lane disjunct so the gate keys on the evidence a compliant PASS necessarily leaves behind: a charged `TEST_FAILURE`.

## Assumptions

- `verifyAttempts.TEST_FAILURE` is the durable, run-authoritative record of a handled test failure — `verifyctl` owns charging it (`verifyctl.sh` calls `statectl verify-attempts --incr` per failed class), so a PASS-worthy run cannot avoid producing it.
- `eval-criteria.md` is LOCKED and already correct; no edit there.
- The existing per-repo union inside `any_test_failure` already covers be-fe-pair runs, so no new union logic is needed.

## Decision Ledger

No pre-flight `/plan-interview` ledger backs this ticket, so this section is authored in-pipeline (advisory tier). Rows carry `codebase-derived` provenance — each was settled by reading the base branch, not by asking the operator.

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | AC-1 requires refusing a case two checked-in selftests assert is accepted. Which wins? | AC-1 governs. `(mc-ir2)` and `(mc-ir4)` encode the hole being closed and are **inverted** to refusal cases; AC-2's operative clause names "the existing **inert-lane** refusal", which is `(mc-ir1)` and stays green unchanged. | codebase-derived |
| D-2 | Inverting `(mc-ir4)` retires the only per-repo coverage of the `any_suite_object` union branch. | That branch is deleted by this change, so there is nothing left to cover. The surviving per-repo union is `any_test_failure`'s `worktrees.<id>` leg — covered by `(mc-ir5)` (charged → accept) and by the inverted `(mc-ir4)` (per-repo suite object, nothing charged → refuse). | codebase-derived |
| D-3 | Should `PLAN_CMD_FAILURE` be unioned into the evidence test alongside `TEST_FAILURE`? | No. The gate's inert-lane leg has keyed on `TEST_FAILURE` alone since it shipped, so the consequence already exists on that lane; this change makes the rule uniform rather than adding an asymmetry. The criterion's circuit breaker is itself `TEST_FAILURE`-scoped (`stages/6-verify.md`). Residual declared in Risks. | codebase-derived |
| D-4 | AC-3 says "on either lane", but the new predicate never reads `verifySummary`. | Read AC-3 in evidence terms; add one suite-object **+** charged-`TEST_FAILURE` accept case anyway so the AC's literal wording is pinned and a future re-introduction of a lane disjunct is caught. | codebase-derived |
| D-5 | AC-4 describes behavior the code already has unconditionally. | Treat as characterization: no logic change, satisfied by regression pins. The `== "PASS"` guard already skips the block for `N/A`/`FAIL`, and the `--force` early return already sits above it. | codebase-derived |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/statectl.sh` — `require_eval_file()`: the predicate, its comment block, and the `--force` sentence in the function docstring.
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — the `(mc-ir)` case block: header, two inverted cases, four added cases, one generalized local helper.
- `plugins/dev-pipeline/skills/run/state-schema.md` — the `mark-completed` terminal-gates paragraph, which documents the value check's lane scoping in prose.

All three paths exist on the base branch. Unverified references: none.

## Reuse inventory

- `complete_run_vs` (`scenario-lib.sh`) — walks all 9 stages with a chosen `verifySummary` and an optional charged `TEST_FAILURE`. Every new case uses it; no new run-composer.
- `inject_worktrees` (`statectl-selftest.sh`) — injects a per-repo `worktrees` map for the be-fe-pair union cases. Reused as-is.
- `sct` / `sct_rc` / `sct_err` / `pass` / `fail` (`statectl-selftest.sh`) — existing harness verbs.
- `write_eval_ir` **[NEW]** — a value-parameterized generalization of the file-local `write_eval_pass`, needed because AC-4 requires scoring `N/A` and `FAIL` in the same slot. No existing helper takes the criterion value as an argument (`scenario-lib.sh`'s `write_eval` hardcodes `N/A`, `write_eval_pass` hardcodes `PASS`), so this replaces `write_eval_pass` rather than duplicating it.

## Implementation steps

1. **`statectl.sh` — predicate.** Delete the `any_suite_object` definition and reduce the jq program to `any_test_failure | not`. `any_test_failure` is unchanged, including its `worktrees.<id>` union.
2. **`statectl.sh` — refusal message.** Restate it in evidence terms: no `TEST_FAILURE` was ever charged, so the circuit breaker was never exercised → score `N/A`. Drop the "inert-lane"/"verifySummary is a skip string" wording, which would be wrong for the newly-covered case (AC-5).
3. **`statectl.sh` — gate comment block.** Retitle from "Inert-lane implementation_resilience gate" to an evidence-shape framing, and delete the closing "Scoped to PASS->N/A on inert runs ONLY: a SUITE-lane run … is unaffected" sentence, which this change falsifies.
4. **`statectl.sh` — docstring.** "the shape check **alone** honors `--force`" becomes false once two neighbouring checks honor it; reword to name both.
5. **`statectl-selftest.sh` — helper.** Replace `write_eval_pass <key>` with `write_eval_ir <key> <value>` (default `PASS`), updating its call sites.
6. **`statectl-selftest.sh` — block header.** Retitle the `(mc-ir)` block: it is no longer an inert-lane gate, and its comment repeats the "SUITE-lane … unaffected" claim.
7. **`statectl-selftest.sh` — invert `(mc-ir2)`.** Suite-object `verifySummary`, nothing charged, `PASS` → now **refused**; assert rc, the message naming the missing evidence, and `status` untouched (AC-1).
8. **`statectl-selftest.sh` — invert `(mc-ir4)`.** Per-repo suite object, nothing charged anywhere, `PASS` → now **refused**, proving a per-repo `verifySummary` no longer rescues a PASS (AC-1, be-fe-pair leg).
9. **`statectl-selftest.sh` — add `(mc-ir6)`.** Suite object **+** charged `TEST_FAILURE`, `PASS` → accepted (AC-3's literal "either lane").
10. **`statectl-selftest.sh` — add `(mc-ir7)`/`(mc-ir8)`.** Suite lane, nothing charged, `N/A` and `FAIL` → accepted; the gate must not fire on a non-`PASS` score (AC-4).
11. **`statectl-selftest.sh` — add `(mc-ir9)`.** Suite lane, nothing charged, `PASS`, `--force` → accepted (AC-4's bypass half).
12. **`state-schema.md`.** Rewrite the terminal-gates sentence describing the value check so it states the evidence rule and drops the "a SUITE-lane run … is unaffected" parenthetical.

## Test strategy

Verify-after: this is a predicate narrowing in shell with an existing behavioral suite, so the cases are written into that suite and the whole sweep is run. Per the repo's tier map, one script's behavior against fixtures belongs in the per-tool `*-selftest.sh` next to the tool — `statectl-selftest.sh`.

**Why these are per-tool cases and not a new scenario.** `scenario-liveness-selftest.sh` already composes a full green run through the terminal `mark-completed` write, and its shared eval fixture (`scenario-lib.sh`'s `write_eval`) scores this criterion `N/A` — so the composed verdict path is covered and stays green under this change, and no scenario varies the evidence shape the value sub-check reads. The `(mc-ir)` block is the only place that grades the sub-check across evidence shapes, which is exactly what this change alters. No new gate contract is introduced (an existing gate's predicate is widened), so no verdict path gains an uncovered composition.

`unitTestScope` is unconfigured for this repo, so there is no mutation surface and the unit-test gate is skipped.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Refuse PASS with no charged `TEST_FAILURE` on a SUITE-lane run | 1, 7, 8 | `(mc-ir2)`, `(mc-ir4)` |
| AC-2 | Inert-lane refusal still holds | 1 | `(mc-ir1)` (unchanged) |
| AC-3 | Accept PASS when `TEST_FAILURE` is charged, either lane | 1, 9 | `(mc-ir3)`, `(mc-ir5)`, `(mc-ir6)` |
| AC-4 | `N/A`/`FAIL` accepted regardless; `--force` still bypasses | 10, 11 | `(mc-ir7)`, `(mc-ir8)`, `(mc-ir9)` |
| AC-5 | Message names missing evidence; cases land beside the `(mc-ir)` block | 2, 5, 6, 7–11 | `(mc-ir2)` asserts the message text |

## Verification commands

```bash
# Targeted — the suite under change:
SKIP_STRESS=1 bash plugins/dev-pipeline/skills/run/statectl-selftest.sh

# Repo-wide gates (CLAUDE.md "Verification"):
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Declared residual (D-3):** a run whose only resilience loop was a plan-specific verification command charges `PLAN_CMD_FAILURE`, not `TEST_FAILURE`, and is now forced to `N/A` on the SUITE lane as it already is on the inert lane. This is a defensible reading of a `TEST_FAILURE`-scoped criterion, and `--force` remains the escape. If it bites in practice it is a separate ticket against the counter vocabulary, not this one.
- **The gate is strictly tightening.** Runs that previously terminalized with a generous PASS will now be refused until the eval is corrected to `N/A`. That is the intent, but it means an in-flight run holding a suite-lane PASS eval must fix the eval file before `mark-completed` succeeds. The refusal message states exactly that.
- `statectl-selftest.sh`'s codegen drift-check regenerates the closed-enum validators from `state-schema.md`. This change touches neither an enum nor a generated block, so the drift-check is unaffected — the sweep confirms it.
- **Rollback:** restore the `any_suite_object` disjunct and revert the two inverted cases. The change is confined to one predicate and its documentation.

## Out-of-scope

- `eval-criteria.md` — LOCKED, and its wording already covers this case.
- Widening the evidence test to other `verifyAttempts` classes (see D-3).
- Criterion 4's separate structural problem, tracked elsewhere.
- A `scripts/lockstep-manifest.tsv` row for the `state-schema.md` prose ↔ `statectl.sh` comment coupling. The manifest is for byte-anchorable duplicated literals; its own header rules out representations that are "not byte-anchorable without authoring new canonical literals" and leaves them reviewer-guarded. The two texts here are a prose paragraph and a code comment, not copies of one literal.

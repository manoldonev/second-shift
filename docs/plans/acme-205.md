# Plan: acme-205 (PR 1 of 2) — verdict-path liveness harness + CI holes + prune

## Context

42 shell selftests verify each component's own contract; nothing asserts that a *composed*
pipeline path still reaches its terminal state. #204 died with every selftest green. #206
landed a first composed-path guard for `stacked-prs` only
(`plugins/dev-pipeline/skills/run/tools/verdict-path-liveness-selftest.sh`, 11 checks).

This slice generalizes that into a single named liveness harness covering four verdict
paths, closes the two CI holes where `.mjs` selftests are never executed, and deletes the
weakest test class (prose-presence guards that grep a token out of a markdown file).

Slice scope is AC-1..AC-5. AC-6..AC-9 (the lockstep manifest, its CI step, and the policy
text) belong to PR 2 and are deliberately absent here.

## Assumptions

- `node` is present on both CI lanes (already relied on by
  `plugins/dev-pipeline/skills/run/tools/text-contract-selftest.sh`, which hard-FAILs without it at `:35-38`).
- CI discovers selftests purely by the `*-selftest.sh` glob (`.github/workflows/ci.yml:39-46`),
  so both new harness files are picked up with zero CI wiring change — and `scenario-lib.sh`
  is deliberately excluded from discovery by not matching that glob.
- The bash-3.2 lane forbids `mapfile` and associative arrays; the `statectl-selftest.sh` idiom
  is followed throughout.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What does the `sub-issues` liveness leg actually assert, given `statectl.sh` has no verdict-aware code? | Assert the observable state shape after the stage-1 terminal write: status stays `in_progress` and `failureContext` is absent. The `mark-completed` refusal exercised is statectl generic incompleteness gate, stated plainly in a comment rather than sold as a sub-issues-aware refusal. | codebase-derived |
| D-2 | Which helpers move into `scenario-lib.sh` alongside the two named ones? | The transitive set the two helpers actually reference: `sct`, `sct_err`, `sct_rc`, `reset_state`, `write_report`, `write_eval`, and `VALID_PAYLOAD`. Reporting helpers (`pass` / `fail`) stay with each caller since neither extracted helper calls them. | codebase-derived |
| D-3 | Does the migrated stacked-prs scenario keep its own fixture identity? | Yes. All 11 checks keep their `vp*` labels and their `plan-lint` / `slice-scope` drive so the migration is auditable as a move, not a rewrite. | codebase-derived |
| D-4 | How does the harness prove liveness rather than merely exercising code? | Each scenario ends on a terminal assertion: `no-split` on an accepted `mark-completed`, `sub-issues` on the accepted non-terminal shape plus a refused `mark-completed`, failure-path on `status == failed`. | codebase-derived |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/scenario-lib.sh` **[NEW]** — shared scenario mechanics.
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` **[NEW]** — the harness.
- `plugins/dev-pipeline/skills/run/workflows/workflows-mjs-selftest.sh` **[NEW]** — node shim.
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — drops its inline
  `complete_stage` (`:76`), `complete_run_vs` (`:1207`) and their shared deps; sources the lib.
- `plugins/dev-pipeline/skills/run/tools/verdict-path-liveness-selftest.sh` — deleted after its
  11 checks migrate.
- `plugins/dev-pipeline/skills/run/stage5-perrepo-implement-selftest.sh` — deleted.
- `plugins/dev-pipeline/skills/run/stage7-perrepo-checkpoint-selftest.sh` — `(B)` half removed
  (`:108-121`), `(A)` behavioral half retained.
- `plugins/dev-pipeline/skills/run/stage8-perrepo-review-selftest.sh` — `(B)` half removed
  (`:116-124`), `(A)` behavioral half retained.

## Reuse inventory

- `complete_stage` (`statectl-selftest.sh:76`) and `complete_run_vs` (`:1207`) — the composed
  full-green-run recipe; extracted and reused, never re-enumerated.
- `reset_state` (`:65`), `sct` (`:52`), `sct_err` (`:55`), `sct_rc` (`:59`),
  `write_eval` (`:102`), `write_report` (`:109`), `VALID_PAYLOAD` (`:122`) — the transitive deps.
- `plugins/dev-pipeline/skills/run/tools/plan-lint.sh` and
  `plugins/dev-pipeline/skills/run/tools/slice-scope.sh` — driven as-is by the migrated checks.
- `plugins/dev-pipeline/skills/run/tools/plan-lint-fixtures/valid-plan.md` — the fixture the
  migrated `mkplan` helper rewrites AC rows into.
- `plugins/dev-pipeline/skills/run/tools/text-contract-selftest.sh:35-38` — the node-absent
  hard-FAIL convention the new shim copies.
- No new helpers introduced beyond the three new files above.

## Implementation steps

1. Create `scenario-lib.sh` holding `sct`, `sct_err`, `sct_rc`, `reset_state`, `write_eval`,
   `write_report`, `VALID_PAYLOAD`, `complete_stage`, `complete_run_vs`. The lib requires the
   caller to have set `STATECTL` and to have `cd`-ed into its own tmp state dir; it defines no
   `pass` / `fail` and runs no assertions.
2. Rewire `statectl-selftest.sh` to source the lib and delete the nine inline definitions.
   Its `write_eval_pass` (`:1197`) stays local — it is a case-specific variant, not scenario
   mechanics.
3. Create `scenario-liveness-selftest.sh` with the `no-split` scenario: `complete_run_vs` with
   an object `verifySummary`, a fixture plan threaded through `plan-lint.sh` between stages 3
   and 4, then `write_eval` and an accepted `mark-completed` as the terminal assertion.
4. Add the `sub-issues` scenario per D-1 and the failure-path scenario
   (`build-failure-context --reason intake-spec-blocked` then `mark-failed`, asserting
   terminal `failed`).
5. Migrate all 11 `vp*` checks out of `tools/verdict-path-liveness-selftest.sh` into the
   harness as its `stacked-prs` scenario, then `git rm` the source file.
6. Create `workflows/workflows-mjs-selftest.sh`: hard-FAIL when `node` is absent, then run
   `node design-sync-selftest.mjs` and `node null-reviewer-selftest.mjs`, exiting with the
   count of failures.
7. `git rm` `stage5-perrepo-implement-selftest.sh`; remove the `(B)` drift-guard halves from the
   stage-7 and stage-8 selftests, keeping their `(A)` behavioral halves and their existing
   marker-delimited mirror blocks (PR 2 mechanizes those).

## Test strategy

Verify-after — this slice *is* test infrastructure, so the harness verifies itself and the
existing suite guards the extraction.

- The extraction (step 2) is proven by `statectl-selftest.sh` staying green: it exercises
  `complete_stage` / `complete_run_vs` at 25+ call sites, so a broken extraction goes red loudly.
- The harness proves itself by asserting terminal writes *succeed* rather than that individual
  commands accept arguments.
- Mutation smoke (not committed): deliberately break one gate ordering — drop the stage-8
  `skill-load-add` from `complete_stage` — and confirm the `no-split` scenario goes red. This
  is what separates a live scenario from one that passes vacuously.

Unit-test surface: `skip`. The repo declares `unitTestScope: null`, so there is no mutation
surface and no co-located unit-test convention to extend.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| ----- | ----------------- | ------- | ------- |
| AC-1 | Harness asserts terminal liveness for no-split, sub-issues, failure-path | 3, 4 | scenario-liveness-selftest (AC-1) |
| AC-2 | Two helpers extracted into scenario-lib.sh, sourced by both callers | 1, 2 | statectl-selftest + scenario-liveness-selftest (AC-2) |
| AC-3 | 11 checks migrated, source file deleted | 5 | scenario-liveness-selftest (AC-3) |
| AC-4 | mjs shim runs both selftests via node, FAILs when node absent | 6 | workflows-mjs-selftest (AC-4) |
| AC-5 | stage5 deleted, stage7/8 (B) halves removed, (A) halves retained | 7 | stage7-perrepo-checkpoint-selftest + stage8-perrepo-review-selftest (AC-5) |

## Verification commands

- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty`
- `find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}`

## Risks / rollback notes

- **Extraction breaks the 25+ existing call sites.** Highest-risk step. Mitigated by the full
  selftest sweep, which fails loudly rather than silently.
- **`set -e` mismatch.** `statectl-selftest.sh` runs `set -uo pipefail` (no `-e`) while the
  migrated file runs `set -euo pipefail`. The harness adopts the `-uo pipefail` posture so the
  shared lib behaves identically in both callers; migrated checks that relied on `-e` get their
  explicit `set +e` / `set -e` fences preserved.
- **Rollback:** every step is an isolated commit; reverting the extraction commit restores the
  inline helpers.

## Out-of-scope

- The lockstep manifest, its checker, its selftest, the marker-comment sites, and the CI step
  (AC-6..AC-8 — PR 2).
- The CLAUDE.md policy text and the two reviewer-contract bullets (AC-9 — PR 2).
- Dedicated selftests for `mutation-gate.mjs` and `tool-discipline-probe.mjs` — accepted risk
  recorded on the issue; they gain first coverage via PR 2's `FINDINGS_SCHEMA` lockstep entry.
- `tools/intake-readroot-selftest.sh` stays — sole guard on the readRoot mjs seam.
- Any net-selftest-LOC target. The measured deletion is ~52 LOC, not the ~200-250 the issue
  estimated; no AC asserts a net decrease, so it is descriptive only.

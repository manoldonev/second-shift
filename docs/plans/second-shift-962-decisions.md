# Intake receipt — #962

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the reviewer's section becomes declarable | New active catalog row `Test coverage \| test-coverage-reviewer \| active` in `plugins/review-toolkit/scripts/section-catalog.txt`, a matching `## Test coverage` entry in the template fence under "Authoring the review-context surface" in `docs/extension-points.md` (contents: test runner(s) and run command, test-file location/naming, layers or patterns with mandatory coverage, domain integrity checks, cross-service contract fixtures, coverage exemptions; "Read by: test-coverage-reviewer"), and `plugins/review-toolkit/agents/test-coverage-reviewer.md` lines 14 and 41 name `## Test coverage` exactly instead of "its test-coverage section". Weighed: new row `Test coverage` (chosen: matches the reviewer's own wording and the content is more than the stack), new row `Test stack` (the ticket's example), reusing `Stack` with an added reader (rejected: puts test policy into a section performance-reviewer uses to calibrate) | user-answered | intent |
| D-2 | Deprecated alias for an existing consumer spelling (e.g. `Test coverage (test-coverage-reviewer)`) | None. An alias hit fails `--preflight` (`docs/extension-points.md`, "A renamed/drifted heading is caught"), so an alias would turn a consumer's preflight red. Their heading stays off-catalog until they rename it; the Migration line tells them to | user-answered | intent |
| D-3 | Guard | The existing lockstep case in `plugins/review-toolkit/scripts/check-review-context-sections-selftest.sh` (case 7, catalog active names == template H2s) covers the new row and template entry. Do NOT add a reviewer-reference case. Weighed: also add a case asserting every backticked `## X` that a shipped agent or skill names is an active catalog row (rejected by the operator) | user-answered | intent |
| D-4 | Other "declared in review-context" lines in the reviewer (`test-coverage-reviewer.md` :68, :108, :126, :138, :152) | Unchanged. They point at "the repo's review-context surface" generically, which the per-reviewer `review-context/test-coverage-reviewer.md` also satisfies (placement rules, `docs/extension-points.md` "Placement"). Only the two lines that name a section the catalog lacks change | codebase-derived | fact |
| D-5 | Other test-adjacent readers (unit-test-mutation-reviewer, unit-test-plan-reviewer) | Out of scope. Neither references a review-context test section (`grep review-context plugins/review-toolkit/agents/unit-test-*.md` returns nothing); the row's only reader is test-coverage-reviewer | codebase-derived | fact |
| D-6 | Release classification | Adding a catalog row is breaking-class per the catalog header and `docs/releasing.md`. It is listed in the PR body's What-breaks section and in the commit `Changelog:` trailer with a `Migration:` line: the catalog gains an active `## Test coverage` section (reader: test-coverage-reviewer). A consumer holding test-coverage content under an off-catalog heading or in `.known-sections` can rename it to `## Test coverage`; nothing newly fails, because adding a row flags no existing heading. Precedent: #965's `Async processing` row | codebase-derived | fact |
| D-7 | PR title verb | `fix(review-toolkit): …` (patch). The reviewer already promised to read the section; the change makes the promise declarable and adds no review behavior | user-answered | intent |
| D-8 | Frozen files | No edit to plugin.json `version`, `CHANGELOG.md` or marketplace.json `metadata.version` (CLAUDE.md, "Never edit release artifacts") | codebase-derived | fact |
| D-9 | Duplicate scan | `dup-scan.sh --issue 962` rc 0: no candidates at or above threshold | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Section catalog row read by `check-review-context-sections.sh` (consumer lint output: coverage count, OFF-CATALOG lines) | decided (D-1) |
| S-2 | `docs/extension-points.md` template entry consumers copy from | decided (D-1) |
| S-3 | test-coverage-reviewer prompt naming the section it loads | decided (D-1) |
| S-4 | A consumer's existing off-catalog test heading under `--preflight` | decided (D-2) |
| S-5 | Release notes / What-breaks entry | decided (D-6) |
| S-6 | Onboard scaffold of review-context.md | out-of-scope — no onboard template lists catalog sections (`grep -rl "Performance budgets"` hits only the catalog, extension-points.md, lead-pass-checklist.md and a plan doc) |

## Checks

- `bash plugins/review-toolkit/scripts/check-review-context-sections-selftest.sh`

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given

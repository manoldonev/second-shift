# Plan — #67: machine-readable section catalog + exact-name lint + coverage report + onboard scaffold

## Context / problem framing

The review-context extension surface is fail-closed at the **file** boundary (basename typos, unknown extension files) but silent **inside** a file. Two mutations survive every guard today: renaming a named section heading (`## Maturity stage` → anything else) and emptying `review-context.md`. The named-section catalog reviewers key on exists only as prose in `docs/extension-points.md` ("Authoring the review-context surface"), and is already drifted in the wild (cadenza writes `## Maturity calibration (MVP stage)`). Onboarding never mentions the surface, so fresh consumers finish green while every reviewer silently runs in infer-and-lower-confidence mode.

This change ships **one machine-readable catalog** (sibling discipline to `extension-manifest.txt`) and derives a linter, a coverage report, a preflight gate, an onboard scaffold, and reviewer-side empty-section semantics from it. `no-split` verdict (Stage 1): ~11 files across review-toolkit / dev-pipeline / second-shift / docs, all hanging off the one catalog artifact.

## Assumptions

- The catalog + section linter live in **review-toolkit/scripts/** (beside the existing `check-review-context.sh` basename lint), NOT dev-pipeline — resolved at Stage 1 from `codebase-explorer` + `spec-reviewer`.
- `preflight.sh` (dev-pipeline) may shell out cross-plugin by resolving review-toolkit's install path (`claude plugin list --json`), gracefully degrading to a skip-note when review-toolkit is not installed.
- No `unitTestScope` configured for this repo → no mutation surface (Stage-5 gate skips); this is a shell + docs change.
- `reviewer-baseline` (SKILL.md) is the shared protocol every reviewer loads — the DRY home for item 7's empty-section semantics (one edit, not 12).

## Decision Ledger

| # | Decision | Provenance |
| --- | --- | --- |
| D1 | **Severity ladder (approved reconciliation).** At the `--preflight` venue the RED (non-zero exit) class is exactly (a) alias-table hits and (b) present-but-empty/TODO-bodied *catalog* sections. Novel off-catalog headings → WARN at `--preflight`/`--verbose`, **suppressed INFO** by default. Genuinely-absent catalog sections → coverage INFO. Mid-run (default) venue never exits non-zero. | user-answered (Option 1, this run) |
| D2 | **Acceptance bullet reworded.** "M1 (section rename) goes red at preflight" → "M1 is surfaced as WARN + a coverage-disclosed reviewer degradation, not red." Making a rename-to-novel-heading hard-fail requires failing all novel headings, which breaks the `.known-sections` escape hatch + optional-sections contract. Disclosed as an `alternate-approach` deviation at Stage 7. | user-answered (Option 1, this run) |
| D3 | **Novel off-catalog = suppressed-INFO by default** (not WARN). Required so the four non-alias cadenza H2s pass untouched with no `.known-sections`. The `.known-sections` file upgrades a novel heading to recognized (silences its `--preflight`/`--verbose` WARN and counts it as known for coverage). | codebase-derived (cadenza real headings) |
| D4 | **Empty-file (M4) vs empty-body distinction.** No headings at all → all-absent → coverage INFO, exit 0 (M4 disclosed, not red). A *present* catalog heading with an empty/TODO body → red at `--preflight`. | codebase-derived (spec-reviewer finding) |
| D5 | **#33 CI-list cross-link** — resolved conditionally at implementation: if a concrete onboard-emitted CI-evidence artifact exists, add the new lint; else defer (the client-gate/CI-backstop intent is met by the preflight wiring). | deferred |

## Affected files/modules

**review-toolkit (catalog + lint):**
- `plugins/review-toolkit/scripts/section-catalog.txt` `[NEW]`
- `plugins/review-toolkit/scripts/check-review-context-sections.sh` `[NEW]`
- `plugins/review-toolkit/scripts/check-review-context-sections-selftest.sh` `[NEW]` (+ inline/tmp fixtures)
- `plugins/review-toolkit/skills/reviewer-baseline/SKILL.md` `[modify]` — item 7

**dev-pipeline (preflight surfacing):**
- `plugins/dev-pipeline/skills/run/tools/preflight.sh` `[modify]`
- `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh` `[modify]`

**second-shift (onboard scaffold + doctor coverage line):**
- `plugins/second-shift/skills/onboard/tools/scaffold-review-context.sh` `[NEW]`
- `plugins/second-shift/skills/onboard/SKILL.md` `[modify]` — fold scaffold offer into one-batch elicitation
- `plugins/second-shift/skills/doctor/tools/doctor.sh` `[modify]` — one coverage line into the `--report` (#34) bundle

**docs:**
- `docs/onboarding.md` `[modify]` — "your first review-context.md" walkthrough
- `docs/extension-points.md` `[modify]` — catalog is machine-sourced; alias/tombstone table; lockstep pointer
- `docs/releasing.md` `[modify]` — catalog add/rename = breaking-class → What-breaks + check known-consumer headings

## Reuse inventory

- `plugins/dev-pipeline/skills/run/tools/check-extensions.sh` — its `.known-extensions` ALLOW block (grep-verified, lines ~53–60) is copied verbatim for `.known-sections` / `section:` lines. No new escape-hatch syntax.
- `plugins/review-toolkit/scripts/check-review-context.sh` — its **effective-registry** computation (plugin panel − `reviewers.remove` + `reviewers.add`) is reused as a shared source for the coverage report's registry-awareness (avoids a third copy). Extract to a small sourced helper `plugins/review-toolkit/scripts/_effective-registry.sh` `[NEW]` that both scripts `source`, OR have the new script `source` the existing one's function — decided at implementation by which is less invasive.
- `plugins/dev-pipeline/skills/run/tools/preflight.sh` `ok()`/`bad()`/`warn()` reporters (grep-verified ~lines 40–80) — the new surfacing reuses them; no new reporting mechanism.
- No new reviewer files: item 7 lands as one `reviewer-baseline` edit.

Unverified references: none.

**Plan-review dispositions (fix-and-go warnings):**
- **Testability of cross-plugin resolution** — the new linter accepts a `SECOND_SHIFT_REVIEW_TOOLKIT_ROOT` env override (mirrors the existing `SECOND_SHIFT_PLUGIN_ROOT`); `preflight.sh` / `doctor.sh` resolve it as: env override → `claude plugin list --json` → skip-note. Selftests set the env override so the wired path is exercised hermetically without a `claude` binary.
- **`_effective-registry.sh` extraction** — `check-review-context.sh`'s inline effective-registry block is extracted to a sourced `plugins/review-toolkit/scripts/_effective-registry.sh` `[NEW]`; both `check-review-context.sh` and the new sections linter source it. `check-review-context-selftest.sh` must stay green after the refactor.

## Implementation steps (ordered)

1. **Catalog** `section-catalog.txt` — header comment + `name | readers | status` rows: the 9 template sections (`Stack`→performance-reviewer; `Database stack`→db-reviewer; `Maturity stage`→security-reviewer; `Architectural invariants & deliberate deviations`→all; `Intentional complexity`→complexity-reviewer; `Convention-required structure`→maintainability-reviewer; `UI stack & design system`→complexity-reviewer,a11y-reviewer; `Naming & structure conventions`→db-reviewer,maintainability-reviewer; `Performance budgets`→performance-reviewer) all `active`, plus `Maturity calibration (MVP stage) | security-reviewer | deprecated-alias-of:Maturity stage`.
2. **Linter** `check-review-context-sections.sh` — root resolution mirroring `check-review-context.sh`; scan `review-context.md` + `review-context/*.md` for **H2+ only** (`^##+ `, never `^# `); classify each heading (exact-active / exact-alias / in-`.known-sections` / novel); empty-body detection per catalog heading (body = lines until next heading; empty/TODO/placeholder → empty). Modes: default (mid-run: alias→WARN, empty-body→WARN, novel→suppressed, missing→suppressed, exit 0), `--preflight` (alias+empty-body→FAIL non-zero; novel→WARN; missing→INFO), `--report` (coverage summary, always exit 0), `--verbose` (surface INFO). Alias finding prints the exact rename command. `.known-sections` + `section:` lines from `.known-extensions` union onto the recognized set.
3. **Coverage computation** — effective-registry-aware (reuse per Reuse inventory), union both homes (shared core + per-reviewer files) before declaring a reviewer degraded; never nag about sections whose only readers are `reviewers.remove`d. One summary line. Assert (selftest) coverage never contributes to exit.
4. **Selftest** `check-review-context-sections-selftest.sh` — fixtures + assertions (see Test strategy). Hermetic via `SECOND_SHIFT_*` env overrides like the sibling selftest.
5. **reviewer-baseline** — add: "A named review-context section that exists but is empty/TODO-bodied counts as **absent**: infer conservatively from the diff AND disclose that the section was empty." (item 7 mid-run half).
6. **preflight.sh** — after the `check-extensions` block: resolve review-toolkit installPath (`claude plugin list --json | jq …`), run `check-review-context-sections.sh --preflight "$REPO_ROOT"` as a FAIL-closed gate via `ok`/`bad`, then emit the `--report` one-liner as an informational line (never affects exit). Graceful skip-note if review-toolkit absent.
7. **preflight-selftest.sh** — extend the zero-write assertion set to cover the new invocation (no tracker/git/remote mutation) and assert the coverage line is present + exit-neutral.
8. **scaffold-review-context.sh** (onboard tool) — given confirmed section choices, emit a `review-context.md` containing **only** human-confirmed sections (never a TODO-bodied heading; never scaffold `## Maturity stage` with example text), detected values carrying provenance or pointer-form, plus one pointer line to `docs/extension-points.md`. Refuse when the file already exists (no regeneration).
9. **onboard SKILL.md** — add a scaffold offer folded into the existing one-batch elicitation, default "later"; never mandatory.
10. **doctor.sh** — add one context-coverage line to the `--report` (#34) bundle by shelling the linter's `--report` (no independent markdown parsing).
11. **docs** — `onboarding.md` line-3 walkthrough; `extension-points.md` catalog-is-machine-sourced + alias table + lockstep note; `releasing.md` breaking-class line.
12. **#33 CI list (D5)** — locate the onboard-emitted CI-evidence artifact; add the lint if present, else defer with a note in the PR body.

## Test strategy (verify-after — infra/tooling change, no product behavior)

New selftest `check-review-context-sections-selftest.sh` asserts:
- **Fixture (AC-1):** consumer dir with H1 `# Review context — Cadenza AI` + cadenza's 5 real H2s (`Owned elsewhere — pointers, not values`, `Stack`, `Repo topology & package architecture`, `Maturity calibration (MVP stage)`, `Domain test edge cases (test-coverage severity examples)`) + 7 `review-context/<reviewer>.md` files each headed `# <reviewer> — Cadenza AI`. Default venue → **exactly** `Maturity calibration (MVP stage)` flagged (alias); the other 4 H2s produce no finding (Stack=active, 3 novel=suppressed); the 7 H1s produce zero findings.
- **M1 (AC-2, reworded per D2):** rename the alias heading → `## Historical notes`; `--preflight` exit 0 (no alias, no empty body); coverage line reports security-reviewer degraded.
- **empty-body (AC-2):** `## Stack` with empty body → `--preflight` exit non-zero (red).
- **M4 empty-file (AC-2):** empty `review-context.md` → coverage line discloses all-absent; `--preflight` exit 0.
- **coverage-can't-fail-exit (AC-3):** `--report` exits 0 even over the alias/empty fixtures.
- **escape-hatch (AC-3):** novel heading + `.known-sections` listing it → no finding at `--preflight`/`--verbose`.
- **lockstep (AC-3):** `docs/extension-points.md` template H2 names == catalog `active` names; every `deprecated-alias-of:<x>` target is an `active` catalog name.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | cadenza 5-H2 fixture: only alias flagged, 7 H1s silent | 1,2,3 | fixture assertion (AC-1) |
| AC-2 | M1 + empty-body outcomes at preflight; M4 by coverage | 2,3 | M1 / empty-body / M4 assertions (AC-2) — M1 reworded per D2 |
| AC-3 | selftests: lockstep, coverage-cannot-fail-exit, escape-hatch | 1,2,4 | lockstep / coverage-cannot-fail / escape-hatch assertions (AC-3) |

## Verification commands

```bash
bash plugins/review-toolkit/scripts/check-review-context-sections-selftest.sh
bash plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Cross-plugin preflight coupling** (dev-pipeline → review-toolkit) is new. Mitigation: resolve installPath at runtime, degrade to a skip-note if review-toolkit absent — never a hard preflight failure from a missing sibling plugin. Rollback = revert preflight.sh block (linter still usable standalone + by review-lead).
- **Catalog↔docs drift.** Mitigation: the lockstep selftest fails the release gate if the catalog and the `extension-points.md` template diverge.
- **Onboard scaffold over-reach.** Guarded by the hard rules (only confirmed sections, no TODO bodies, no Maturity-stage example text, no regeneration).

## Out-of-scope

- `doc-routing.md`, `design-tokens/*.md`, `security-rules.md`, `blocker-mutants.md` intra-file contracts (tracked separately per the issue).
- Auto-editing cadenza's real `review-context.md` (propagation is pull-only; cadenza reconciles on its own via the printed rename command).

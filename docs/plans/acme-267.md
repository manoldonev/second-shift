# Plan — retire the `{slice}` planFilePattern token + configVersion bump (#267)

PR 3 of 3 for #262. Base: `main` @ `3be17c6`.

## Context / problem framing

#262 retires the stacked-PR verdict. PR 1 (#275) landed the sequential sub-issues verdict; PR 2 (#282) deleted the stacked-PR execution path and its state/scope contracts. What survives is the **consumer-facing** remnant: `stageParams.planFilePattern` still publishes a `{slice}` token whose only meaning was the `-pr<N>` suffix of a stacked slice.

`{slice}` is documented in `docs/extending.md` as part of a consumer override, so removing it from the schema default is a breaking change to the published config surface. Per `docs/migrations/README.md` that means a `configVersion` bump plus a migration doc — not a silent default change.

## Assumptions

- Stacked PRs are retired and no live branch depends on the `-pr<N>` shape (verified: `gh pr list` returns no open PR with a `-pr<N>` head branch; `max-pushed-slice.sh` no longer exists in the tree).
- `configVersion` and the marketplace version are **independent** numbering schemes that happen to both sit at the 1→2 boundary. The schema's `configVersion.const` is the only input to `check-configversion-migration-doc.sh`.
- This repo's own `.claude/second-shift.config.json` is gitignored, so its required bump cannot appear in this diff.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which files are in the `{slice}` sweep, given Scope omits three that carry the token | Sweep all of them. `.github/workflows/ci.yml`, `scripts/check-pipeline-chain.sh`, `scripts/check-pipeline-chain-selftest.sh` landed in #281 **after** the issue body was written; AC-1's grep bar is unambiguous and admits no "unlisted" exemption | codebase-derived |
| D-2 | What `check-pipeline-chain.sh` does with its branch-parsed `SLICE` once `{slice}` is gone | Remove the whole slice concept: the optional `-pr([0-9]+)` regex group, the `SLICE` capture, its diagnostic echo, and the `{slice}` sed clause. A `-pr<N>` branch becomes "exempt with notice" — the same treatment any non-key suffix already gets. Retiring the machinery is #262's stated purpose; leaving a dead capture whose only consumer was the removed sed would be incoherent | codebase-derived |
| D-3 | How to make AC-3's "degrades safely — token stripped" true, since no generic token stripping exists today | Add a trailing generic residual-token strip (`s\|{[a-zA-Z][a-zA-Z0-9]*}\|\|g`) after the enumerated substitutions at all four sites. This also dissolves the AC-1/AC-3 conflict: the generic strip carries no `{slice}` literal. No config-lint token check is added, per Scope | codebase-derived |
| D-4 | Where the configVersion 1→2 migration doc goes, since the gate-derived `docs/migrations/v1-to-v2.md` already exists with unrelated content | Fold a clearly delimited "configVersion 1 → 2" section into the existing file and retitle it to cover both boundaries. Rejected renaming the existing doc: it would churn three consumer-facing `config-lint` error strings plus the `docs/migrations/README.md` link, for no consumer benefit — a reader following the pointer lands on the right guidance either way | codebase-derived |
| D-5 | Whether AC-1's exemption list covers the migration doc, which must quote the token it retires | Yes — `docs/migrations/` joins `docs/plans/` and `CHANGELOG.md`. AC-1's evident intent is that no **resolution-path** file carries the token; a migration doc that cannot name the token it migrates away from is not actionable | ticket-sourced ([intake comment](https://github.com/manoldonev/second-shift/issues/267#issuecomment-5142323609)) |
| D-6 | How wide the `configVersion` literal sweep goes, since Scope names only the config-lint fixtures | Every `configVersion: 1` literal in the repo → `2`. After the bump `config-lint` rejects any `configVersion: 1` config, which would otherwise mean onboarding (`onboard/SKILL.md`, `README.md`) generates a config its own linter rejects. A uniform sweep also avoids a per-file "is this one actually linted?" judgment call | codebase-derived |
| D-7 | Disposition of the two configVersion fixtures whose premises invert | `invalid-configversion-2.json` becomes `invalid-configversion-3.json` (2 is now valid; 3 is the new "newer than understood"). `invalid-configversion-0.json` stays at 0. A new `invalid-configversion-1.json` pins AC-2's actual case — the prior version rejected with a migration-doc pointer | codebase-derived |
| D-8 | Whether to strengthen `check-configversion-migration-doc.sh`, which gates on file existence only and would have passed even with no migration written | Deferred — out of scope for this PR. Disclosed in the intake comment and the run report; AC-2 is satisfied in substance by the new section's content, not by the gate's exit code | deferred |

## Affected files/modules

Schema:
- `schema/second-shift.config.schema.json` — `planFilePattern` default + description token list; `configVersion.const` 1 → 2

The five default-pattern literal sites (lockstep) + the generic strip:
- `plugins/dev-pipeline/skills/run/tools/preflight.sh`
- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md`
- `plugins/dev-pipeline/skills/run/stages/4-plan-review.md`
- `plugins/dev-pipeline/skills/run/stages/5-implement.md`

Release chain / CI (D-1, D-2):
- `.github/workflows/ci.yml` — `PIPELINE_PLAN_PATTERN`
- `scripts/check-pipeline-chain.sh`
- `scripts/check-pipeline-chain-selftest.sh`

Config-lint surface:
- `plugins/dev-pipeline/skills/run/tools/config-lint.sh` — version bounds + migration-doc pointer
- `plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/` — all 26 fixtures; `invalid-configversion-3.json` `[NEW]`; `invalid-configversion-1.json` `[NEW]`; `invalid-configversion-2.json` deleted

configVersion literal sweep (D-6):
- `README.md`, `docs/onboarding.md`, `plugins/second-shift/skills/onboard/SKILL.md`
- `plugins/second-shift/skills/doctor/tools/doctor-fixtures/config-valid.json`, `config-with-secret.json`
- `plugins/second-shift/templates/consumer/second-shift-ci-check-selftest.sh`
- `plugins/review-toolkit/scripts/check-model-tiers-selftest.sh`
- `plugins/review-toolkit/scripts/fixtures/reviewer-references/{consumer-add-override,consumer-green,consumer-remove-unknown}/.claude/second-shift.config.json`
- `plugins/dev-pipeline/skills/run/verifyctl-selftest.sh`, `scenario-liveness-selftest.sh`, `statectl-selftest.sh`, `tools/preflight-selftest.sh`

Docs:
- `docs/extending.md` — override example loses `{slice}`
- `docs/migrations/v1-to-v2.md` — configVersion 1→2 section (D-4)

## Reuse inventory

- `scripts/check-configversion-migration-doc.sh` — existing gate; consumed unchanged, no edit.
- `plugins/dev-pipeline/skills/run/tools/check-config-shadowing.sh` — existing pin; **no edit needed**. Its pin greps the config-key string `stageParams.planFilePattern`, which contains no `{slice}`, so dropping the token cannot break it. (Scope asked for a re-anchor; verified as a no-op.)
- `docs/migrations/v1-to-v2.md` — existing doc, extended rather than replaced.
- New helpers introduced: none — no new scripts or functions.

## Implementation steps

1. **Schema.** `planFilePattern.default` → `{plansDir}/acme-{issueKey}.md`; description token list drops `{slice}`. `configVersion.const` → `2`.
2. **Five literal sites + generic strip.** In `preflight.sh`, `3-write-plan.md`, `4-plan-review.md`, `5-implement.md`: update every hardcoded default to the tokenless form; drop the `s|{slice}|…|` clause and the `SLICE_SUFFIX` reference; append the generic residual-token strip (D-3). Remove the `{slice}` semantics comment in `3-write-plan.md`.
3. **Release chain (D-1, D-2).** `ci.yml`'s `PIPELINE_PLAN_PATTERN` → tokenless. In `check-pipeline-chain.sh`: drop the `(-pr([0-9]+))?` regex group, the `SLICE` capture, the slice mention in the applicability echo, and the `{slice}` sed clause.
4. **`check-pipeline-chain-selftest.sh`.** Update `PATTERN` to the tokenless form. Rewrite the two `pair (c)` slice cases to pin the **new** contract: a `-pr<N>` branch is exempt-with-notice (rc=0, no plan lookup), because stacked PRs are retired. Drop the now-unused slice plan fixture the suite writes into its temp repo (the `acme-42-pr2` plan at line 45).
5. **config-lint bounds + pointer.** Bounds move from `> 1` / `< 1` to `> 2` / `< 2`; the "predates" message names `docs/migrations/v1-to-v2.md` so AC-2's pointer requirement is met.
6. **Fixture premise flips (D-7).** `git mv invalid-configversion-2.json invalid-configversion-3.json` with content `3`; add `invalid-configversion-1.json` at `1`; update the three `config-lint-selftest.sh` expectations.
7. **configVersion sweep (D-6).** Bump every remaining `configVersion: 1` literal to `2` across fixtures, selftests, and docs.
8. **Docs.** `docs/extending.md` override example loses `{slice}`. Add the delimited configVersion 1→2 section to `docs/migrations/v1-to-v2.md` (what to delete, before/after, and the defensive-strip note from D-3), and retitle the doc to cover both boundaries.
9. **Local dogfood config** (outside the diff — gitignored): bump `.claude/second-shift.config.json` to `configVersion: 2` so this repo's own pre-flight keeps passing. Disclosed in the run report.

## Test strategy

Verify-after (refactor/infra — no behavior change in any `unitTestScope` surface; this repo configures none). The existing suites are the regression guards:

- `config-lint-selftest.sh` is the primary guard: it exercises every fixture against the new bounds, so a missed fixture bump fails loudly.
- `check-pipeline-chain-selftest.sh` guards D-2's behavior change; its two rewritten cases are the contract for the retired slice path.
- `derive-release-selftest.sh` covers `check-configversion-migration-doc.sh` (per CLAUDE.md's coverage-by-different-name list) and runs in a throwaway git repo, so it is unaffected by this repo's schema const.
- AC-1 is a repo-wide grep, run as a verification command rather than a new test — a prose-presence guard is explicitly disallowed by CLAUDE.md, and the grep is the AC itself.

No new selftest suite: every changed script already has a suite, and the change is a literal/bounds sweep rather than a new contract.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | No `{slice}` outside historical records; schema + literals + docs agree | 1, 2, 3, 4, 8 | Repo-wide grep in Verification; `check-pipeline-chain-selftest.sh` |
| AC-2 | config-lint rejects a prior-version config with the migration-doc pointer; migration doc present at the gate-derived name | 5, 6, 8 | `config-lint-selftest.sh` (new `invalid-configversion-1.json` case); `derive-release-selftest.sh` |
| AC-3 | A formerly-`{slice}` override resolves to a valid path after migration, and degrades safely if unmigrated | 2, 8 | — no test (covered-by-selftest) |

AC-3's covering suites: `preflight-selftest.sh` exercises the substitution path, and the tokenless resolution of `valid-monorepo-github.json` is asserted by `config-lint-selftest.sh`.

## Verification commands

```bash
# AC-1 — must return nothing outside the exempt roots
grep -rn '{slice}' . --exclude-dir=.git | grep -vE '^\./(docs/plans/|CHANGELOG\.md|docs/migrations/)'

find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} bash {}
bash scripts/check-configversion-migration-doc.sh
```

Selftests run **without** `SKIP_STRESS` — only CI's ubuntu lane exercises the stress legs.

## Risks / rollback notes

- **Missed `configVersion` literal.** Mitigated by `config-lint-selftest` failing loudly on any fixture below the new bound, plus the explicit grep in Verification.
- **`check-pipeline-chain.sh` behavior change (D-2).** A hypothetical legacy `-pr<N>` branch stops being plan-checked and becomes exempt-with-notice. Verified there are none open; the notice keeps it visible rather than silent.
- **The migration doc now covers two version namespaces.** Mitigated by explicit section delimiters and a note in the doc explaining why one filename carries both.
- **Rollback:** the change is a single squashed commit set; reverting restores the token and `configVersion: 1` together. Consumers who already migrated would need to re-add `{slice}` — but since the substitution strips unknown tokens defensively either way (D-3), a stale override degrades rather than breaks.

## Out-of-scope

- Strengthening `check-configversion-migration-doc.sh` beyond file existence (D-8) — disclosed, not fixed.
- Any change to `check-config-shadowing.sh` (verified no-op).
- The `branchPrefix` description edit named in Scope — #282 already removed the `-pr<N>` shape and the `max-pushed-slice.sh` mention; nothing remains to change.
- `docs/onboarding.md`'s `{slice}` sweep named in Scope — the file contains no `{slice}` token; only its `configVersion` literals are touched.

## Grounding

Unverified references: none. Every path above was confirmed by grep or read against the pinned base; `[NEW]` marks the two fixtures this plan creates.

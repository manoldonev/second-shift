# Plan — #106: genericize Stage-3/5 prompt contracts off the birth stack

## Context / problem framing

The dev-pipeline's **executable** seams are already stack-agnostic: `commands.<host>.unitTestScope` and `commands.<host>.testFile` are resolved from config, with an explicit fail-closed refusal to fall back to the birth stack's yarn form (`stages/5-implement.md:79`). The **prose** layer those seams sit inside was never given the same treatment. It still names the birth stack as normative, so on a non-TS consumer the LLM-facing contract asks for idioms the repo does not use.

Four defects were reported; two more of the same class were found during intake:

| # | Defect | Site(s) |
| --- | --- | --- |
| 1 | `.project/` hardcode in the Stage-5 instruction | `stages/5-implement.md:22` |
| 2 | Birth-stack ORM / language / spec suffix named as normative | `stages/3-write-plan.md:56, :61, :62` |
| 3 | `(AC-n)` convention has a JS-only attachment point | `stages/5-implement.md:19` |
| 4 | Dangling `../../unit-testing/SKILL.md` link | `stages/3-write-plan.md:56, :59`; `stages/5-implement.md:19, :35` |
| 5 | Same `.project/` hardcode, Stage-7 stage file + tier table + the agent it dispatches | `stages/7-doc-update.md:3`; `SKILL.md:384`; `review-toolkit/agents/doc-updater.md:3` |
| 6 | Third `(AC-n)` site — the skill that *defines* the convention | `plugins/review-toolkit/skills/mutation-review/SKILL.md:39` |

Defects 5 and 6 are in scope because each is the same defect as one already reported, at a site that would otherwise contradict the fix: leaving `7-doc-update.md` hardcoded contradicts `doc-update.md:11`, the file this issue cites as the correct precedent; and genericizing `(AC-n)` in dev-pipeline while `mutation-review` still states the JS-only form leaves the defining skill disagreeing with its consumer.

**This is alignment, not invention.** Every pattern needed already exists in-repo and is only being extended to sites that missed it.

## Assumptions

- No new config keys. The resolution mechanisms already shipped are sufficient (verified below).
- Prose-only change: no script is added or modified, so the repo's "every checked-in script pairs with a `*-selftest.sh`" rule is not triggered.
- `commands.second-shift.unitTestScope` is `null` in this repo, so the unit-test mutation gate correctly classifies this ticket as `skip`.

## Decision Ledger

| ID | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | Resolve conventions via the existing `doc-update.md:11` three-tier router; introduce no config key | codebase-derived | Neither `review-context.md` nor `docs/config-schema.md` has a conventions/ORM key, and `review-context.md` is optional (onboard scaffolds it as accept-or-edit, default later). A second protocol would need its own absent-source fallback. The router already specifies all three tiers plus a disclosure requirement. |
| D-2 | Repoint every dangling link to `review-toolkit:mutation-review` rather than recreating a `unit-testing` skill | codebase-derived | Verified that skill carries all three cited contracts as top-level sections: Mock boundary, Assertion strength, Blocker-class mutants. Recreating a skill would duplicate them. |
| D-3 | Generalize the `(AC-n)` attachment point, preserve the `(AC-n)` token | codebase-derived | The consumer at `pipeline-retro/SKILL.md:56` greps the PR diff for the token. Preserving the token keeps that channel working with no consumer change; generalizing only the attachment point makes it reachable from frameworks with no test-title string. |
| D-4 | Do not add a lint/selftest guarding against dangling links or stack literals | deferred | Would be a new checked-in script, pulling a paired selftest and CI wiring into a prose fix. Worth a follow-up issue; recorded here so the omission is disclosed rather than silent. |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md`
- `plugins/dev-pipeline/skills/run/stages/5-implement.md`
- `plugins/dev-pipeline/skills/run/stages/7-doc-update.md`
- `plugins/dev-pipeline/skills/run/SKILL.md`
- `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md`
- `plugins/review-toolkit/skills/mutation-review/SKILL.md`
- `plugins/review-toolkit/agents/doc-updater.md`

Not changed: `plugins/dev-pipeline/skills/run/doc-update.md` (already correct — it is the precedent being propagated), and all `.mjs` / `.sh` executable seams (already generic).

## Reuse inventory

Three existing in-repo patterns are reused verbatim rather than reinvented:

- **Three-tier doc router** — `plugins/dev-pipeline/skills/run/doc-update.md:11` (CLAUDE.md router, then optional `.claude/second-shift/doc-routing.md`, then grep fallback with an explicit disclosure). Reused for defects 1 and 5.
- **Already-generic mock-boundary table** — `plugins/review-toolkit/skills/mutation-review/SKILL.md:12` ("the data-access handle", "the tenant/owner-scope predicate"). Its wording is adopted for defect 2, so the two files agree instead of one naming an ORM.
- **Illustration-vs-contract split** — `plugins/review-toolkit/agents/plan-reviewer.md:284` ("Illustration only — not the contract") and `doc-update.md:113`. Reused to demote birth-stack examples to labelled illustrations.

No new helpers introduced.

## Implementation steps

1. **`stages/5-implement.md:22`** — replace the bare `Follow all conventions from .project/reference/conventions.md.` with a router-based instruction pointing at the repo's `CLAUDE.md` context router and the optional `.claude/second-shift/doc-routing.md`, matching `doc-update.md:11`.
2. **`stages/5-implement.md:19`** — restate the `(AC-n)` convention with a framework-agnostic attachment point: the test title where the framework has one, an adjacent comment where it does not. Preserve the literal `(AC-n)` token. Repoint the link to `review-toolkit:mutation-review`.
3. **`stages/5-implement.md:35`** — repoint the second dangling link, **and** genericize the "including co-located `*.spec.ts`" clause the same way step 7 treats `3-write-plan.md:62`. Leaving it normative here while genericizing the identical idiom two files away is the inconsistency the plan's own logic argues against.
4. **`stages/3-write-plan.md:56`** — drop "backend TypeScript source"; describe the scope purely as what `commands.<host>.unitTestScope` matches, and demote the `apps/api/src/**` value to a labelled example. Repoint the dangling link.
5. **`stages/3-write-plan.md:59`** — repoint the dangling link; demote the parenthesised birth-stack example.
6. **`stages/3-write-plan.md:61`** — replace "mock only the Drizzle handle / external I/O" with the wording already used in `mutation-review` ("the data-access handle").
7. **`stages/3-write-plan.md:62`** — replace "co-located `*.spec.ts`" with a config-derived phrasing keyed to `commands.<host>.testFile`, with `*.spec.ts` shown as an example.
8. **`stages/7-doc-update.md:3`** — replace "Scans `.project/` docs" with "Scans the repo's declared documentation roots", matching the wording already in `doc-update.md:3`.
9. **`SKILL.md:384`** — same substitution in the model-tier table row for Stage 7.
10. **`review-toolkit/skills/mutation-review/SKILL.md:39`** — apply the same `(AC-n)` restatement as step 2, keeping the existing `it(...)` form as a labelled JS example.
11. **`pipeline-retro/SKILL.md:56`** — adjust "grep the PR diff for `(AC-n)` test titles" to "`(AC-n)` markers", so the retro's description matches the now-broader convention. Grep behavior is unchanged.
12. **`review-toolkit/agents/doc-updater.md:3`** — the `description:` frontmatter says the agent "cross-references against `.project/` docs". Same hardcode as defects 1 and 5, in the agent Stage 7 dispatches; replace with "the repo's declared documentation roots". Frontmatter `description` is load-bearing (it drives agent selection), so the edit stays a one-phrase substitution.

## Test strategy

Verify-after (prose/infra refactor — no behavior change, no runtime code touched). There is no unit-test surface: `commands.second-shift.unitTestScope` is `null`, so the mutation gate classifies this `skip`.

Coverage is by targeted grep assertions over the worktree, each mapping to an acceptance criterion, plus the repo's standing gates to prove nothing regressed.

## Acceptance-criteria traceability

Each row names the concrete command that decides it; all are collected in the verification block below as `A1`–`A6` and run as one script. No row claims selftest coverage — this change adds no selftest (see D-4).

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Stage 5 resolves conventions via the CLAUDE.md router, no `.project/` literal | 1 | `A1` — asserts zero `.project/` matches in `stages/5-implement.md` |
| AC-2 | Stage 3 names no birth-stack ORM, language, or spec suffix as normative | 4, 5, 6, 7 | `A2` — asserts zero matches for `Drizzle`, `backend TypeScript`, and normative `*.spec.ts` in `stages/3-write-plan.md` |
| AC-3 | `(AC-n)` attachment point is framework-agnostic, token preserved | 2, 3, 10, 11 | `A3` — asserts each of the three sites contains both the literal `(AC-n)` token and a non-title fallback phrase |
| AC-4 | Zero dangling `unit-testing/SKILL.md` references remain in prose | 2, 3, 4, 5 | `A4` — asserts zero matches across `plugins/**/*.md` |
| AC-5 | NEGATIVE — birth stack unaffected; JS `it('... (AC-1)')` still valid, retro grep unchanged | 2, 10, 11 | `A5` — asserts the JS `it(` example survives at both `(AC-n)` definition sites and that `pipeline-retro` still greps the unchanged token |
| AC-6 | No `.project/` hardcode in the Stage-7 stage file, the tier table, or the doc-updater agent | 8, 9, 12 | `A6` — asserts zero `.project/` matches across all three files |

**AC-4 is scoped to `*.md` deliberately.** An unscoped `grep -rn 'unit-testing/SKILL.md' plugins/` can never pass: `plugins/dev-pipeline/skills/run/tools/prose-budget.baseline.tsv:21` carries a historical size row for `.claude/skills/unit-testing/SKILL.md`, which this change does not touch. That row is inert — `prose-budget.sh:87` looks the baseline up per **existing** file (`awk '$1==p'`), so a row for a deleted file is never read — and it is a size record, not a link, so it is out of the defect class. It is listed as a follow-up in Out-of-scope.

Unverified references: none. Every path, line, and section name above was confirmed by read or grep against `origin/main` at `b0cf362`.

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}

Per-AC checks, run from the worktree root. Each is a plain command whose non-zero exit fails the criterion:

```bash
R=plugins/dev-pipeline/skills/run
M=plugins/review-toolkit/skills/mutation-review/SKILL.md

# A1 (AC-1)
! grep -n '\.project/' "$R/stages/5-implement.md"

# A2 (AC-2) — note -E with a real alternation; an escaped \| would match a
# literal pipe and pass vacuously.
! grep -nE 'Drizzle|backend TypeScript|co-located `\*\.spec\.ts`' "$R/stages/3-write-plan.md"

# A3 (AC-3) — token preserved AND a non-title fallback present, at all three sites.
for f in "$R/stages/5-implement.md" "$M" "$R/../pipeline-retro/SKILL.md"; do
  grep -q '(AC-n)' "$f" || { echo "A3 FAIL: token missing in $f"; exit 1; }
done
grep -qi 'comment' "$R/stages/5-implement.md" && grep -qi 'comment' "$M"

# A4 (AC-4) — prose only; see the scoping note above.
! grep -rn --include='*.md' 'unit-testing/SKILL.md' plugins/

# A5 (AC-5) — birth-stack example must survive at both definition sites, and the
# retro must still grep the unchanged token.
grep -q "it(" "$M" && grep -q '(AC-n)' "$R/../pipeline-retro/SKILL.md"

# A6 (AC-6)
! grep -n '\.project/' "$R/stages/7-doc-update.md" \
    plugins/review-toolkit/agents/doc-updater.md
! grep -n '`\.project/` docs' "$R/SKILL.md"
```

`prose-budget.baseline.tsv` tracks per-file prose size; these edits are net-neutral to slightly negative, so no baseline refresh is expected. If a budget check flags a file, refresh the baseline row in the same commit.

## Risks / rollback notes

- **Risk: over-genericizing into vagueness.** Stripping the concrete example leaves an instruction with no worked referent, degrading plan quality on *every* stack. Mitigated by the illustration-vs-contract split — examples are kept, explicitly labelled as illustrations rather than deleted.
- **Risk: breaking the birth stack.** Guarded by AC-5 as an explicit negative criterion.
- **Risk: `(AC-n)` token drift.** If the token were changed rather than the attachment point, `pipeline-retro:56` would silently stop matching and the AC-audit channel would go empty on *all* stacks — a strictly worse outcome than the reported bug. D-3 forbids touching the token.
- **Rollback:** documentation-only; `git revert` of the single commit restores prior behavior with no migration.

## Out-of-scope

- Adding a lint or selftest that guards against dangling links / stack literals (D-4 — deferred, worth a follow-up issue).
- **The stale `.claude/skills/unit-testing/SKILL.md` row in `prose-budget.baseline.tsv:21`.** It is birth-stack residue and worth removing, but it is a size-baseline record rather than a link, and it is provably inert (`prose-budget.sh:87` reads the baseline only for files that exist). Cleaning it is a separate concern from repairing prose links; folding it in would widen this PR into the prose-budget tooling. Follow-up.
- **Birth-stack `acme:` labels in the Stage-5 bash comments** (`stages/5-implement.md:42, :54, :79`). These sit inside fenced code as *worked examples* of config resolution, and `:79` deliberately names the acme form in a fail-closed error message that exists precisely to refuse defaulting to it. They are illustrations, not normative instructions, so they are outside this defect class.
- `plugins/review-toolkit/agents/plan-reviewer.md:284-296` — already carries the "Illustration only" label, so its Drizzle mentions are correctly framed.
- `stages/1-intake.md:203`, which cites a birth-repo `.project/` probe-findings doc as a provenance reference rather than as an instruction to read.
- Genericizing the executable `.mjs` / `.sh` seams — already clean, as the issue states.
- Version bumps and `CHANGELOG.md` edits — derived at release time per repo convention.

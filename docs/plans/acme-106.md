# Plan — #106: genericize the Stage-3/5 prose + prompt contracts off the birth stack

## Context

The dev-pipeline's *executable* seams (`commands.<host>.unitTestScope` / `testFile`) are already config-driven and stack-agnostic. The **prose and prompt layer** they sit inside was never brought along: Stage 3 and Stage 5 still name the birth stack (Drizzle, `*.spec.ts`, "backend TypeScript", `.project/`) as normative, the `(AC-n)` traceability convention is written in JS syntax, and a skill reference points at a directory that no longer exists.

Intake widened this in one materially important way. The issue asserts the executable seams are clean; that framing hid the worst instance of the dangling-reference defect. Three **live agent-dispatch prompt strings** tell a dispatched model to `Load the unit-testing skill.` — a skill that does not exist:

| Site | Form |
| --- | --- |
| `workflows/unit-tests.mjs:181` | concatenated into `prompt` for `unit-test-plan-reviewer` |
| `workflows/unit-tests.mjs:203` | concatenated into `prompt` for the propose-phase mutation reviewer |
| `workflows/code-review.mjs:231` | concatenated into `prompt` for the Stage-8 mutation reviewer |

The `.md` links are inert prose a human might follow. These are text sent to a model on every unit-test plan review and every mutation propose — the reference is dead *at runtime*, which is the harmful form.

A second pattern recurs across the `.project/` sites: **a file whose body is already generic, contradicted by its own summary line.** `7-doc-update.md:3` says "Scans `.project/` docs" while the protocol it defers to (`doc-update.md:3`) explicitly forbids that hardcode; `review-toolkit/agents/doc-updater.md:3`'s frontmatter description says "cross-references against .project/ docs" while its own body at :13 carries the full generic router. The genericization reached the bodies and stopped short of the descriptions.

The fix is alignment, not invention. Every pattern needed already exists in-repo: `doc-update.md:11-26`'s three-tier doc router, the `> **Illustration only — not the contract.**` callout (`doc-update.md:113`, `doc-updater.md:176`) for retained birth-stack examples, and `review-toolkit:mutation-review`, which already carries the mock-boundary / assertion-strength / blocker-taxonomy / `(AC-n)` contracts the dead link was reaching for.

## Assumptions

- **No new config keys.** Convention sourcing reuses the existing `doc-update.md` three-tier router (CLAUDE.md context router → optional `.claude/second-shift/doc-routing.md` → grep fallback with disclosure). Operator-directed at intake; adopted unchanged.
- **`review-toolkit:mutation-review` is the repoint target** for all `unit-testing` references. Verified: it carries `## Mock boundary`, `## Assertion strength`, `## Blocker-class mutants`, and the `(AC-n)` convention. Do **not** recreate a `unit-testing` skill.
- **The literal `(AC-n)` token is load-bearing and must survive.** `pipeline-retro/SKILL.md:56` greps the PR diff for it. Generalizing the *attachment point* is in scope; changing the *token* is not — that would break the audit channel this ticket exists to repair.
- **`tools/prose-budget.baseline.tsv:21` is not a reference.** It is a measurement-baseline row that happens to record the path `.claude/skills/unit-testing/SKILL.md`. Data about a historical prose budget, not a link; excluded from the AC-3 grep rather than edited.
- **`.project/` occurrences already inside an "Illustration only" block are correct and stay** (`doc-update.md` example map, `doc-updater.md:200-213`). The defect is unlabeled normative use, not the existence of a worked example.
- Markdown-and-prompt-only change with no script control-flow change, so the existing gates (shellcheck / `jq empty` / selftest sweep) stay green by construction — which is exactly why AC-6 adds a real guard rather than leaning on a vacuous sweep.

## Affected files

**Changed:**

| File | Change |
| --- | --- |
| `plugins/dev-pipeline/skills/run/stages/5-implement.md` | drop `.project/` hardcode (:22) → router deferral; genericize `(AC-n)` (:19); repoint 2 dead links (:19, :35); drop normative `*.spec.ts` (:35) |
| `plugins/dev-pipeline/skills/run/stages/7-doc-update.md` | drop `.project/` literal (:3) → the repo's declared documentation roots |
| `plugins/dev-pipeline/skills/run/SKILL.md` | drop `.project/` literal in the Stage-7 Model Tiering row (:384) |
| `plugins/review-toolkit/agents/doc-updater.md` | drop `.project/` literal from the frontmatter `description` (:3) — currently contradicts its own generic body at :13 |
| `plugins/dev-pipeline/skills/run/stages/3-write-plan.md` | genericize unit-test-surface prose (:56, :59, :61, :62); repoint 2 dead links (:56, :59); wrap retained acme examples in the illustrative callout |
| `plugins/dev-pipeline/skills/run/state-schema.md` | genericize `unitTestSurface` prose (:246) — `apps/api` backend TypeScript → the configured `unitTestScope` surface |
| `plugins/dev-pipeline/skills/run/workflows/unit-tests.mjs` | remove `Load the unit-testing skill.` from 2 live prompts (:181, :203); genericize `apps/api` in the prompt (:194) |
| `plugins/dev-pipeline/skills/run/workflows/code-review.mjs` | remove `Load the unit-testing skill.` from 1 live prompt (:231) |
| `plugins/dev-pipeline/skills/run/workflows/mutation-gate.mjs` | repoint the `(unit-testing skill)` comment citation (:139) |
| `plugins/review-toolkit/skills/mutation-review/SKILL.md` | genericize the `(AC-n)` example (:39) beyond the JS-only `it(...)` form |

**Created:**

| File | Purpose |
| --- | --- |
| `scripts/stack-generality-lint.sh` | regression guard for the mechanizable legs (AC-1, AC-3, AC-4) — greps for reintroduced birth-stack literals and dead skill refs. Lives in `scripts/` (peer of `check-frozen-files.sh`): it guards this marketplace's own sources, and living outside `plugins/` keeps the lint and its seeded fixtures out of their own scan scope |
| `scripts/stack-generality-lint-selftest.sh` | paired selftest (repo convention; CI discovers by glob). Its clean-tree case runs the lint against the real repo root, making the selftest glob the CI invocation path — no CI edit |

**NOT changed:**

- `plugins/dev-pipeline/skills/run/doc-update.md` — already generic; it is the *precedent* being adopted, not a defect site.
- `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` — its `(AC-n)` grep is the consumer this plan protects. Touching it would defeat the point of preserving the token.
- `plugins/dev-pipeline/skills/run/tools/prose-budget.baseline.tsv` — measurement data, not a reference (see Assumptions).
- `doc-updater.md:176-213` — already correctly labeled as illustrative.

## Reuse inventory

| Existing asset | How it is reused |
| --- | --- |
| `doc-update.md:11-26` three-tier router | Stage 5 and Stage 7 defer to it instead of naming `.project/`. Single source of truth; no protocol duplicated. |
| `> **Illustration only — not the contract.**` callout (`doc-update.md:113`, `doc-updater.md:176`) | The required labeling form for every retained acme example. Makes AC-2 greppable rather than a judgment call. |
| `review-toolkit:mutation-review` | Repoint target for all 8 `unit-testing` references. Already carries every contract the dead link cited. |
| `mutation-review/SKILL.md:39` | Already framework-neutral in its lead sentence ("suffix its **test title**"); only its example needs widening. Less work than the issue implies. |
| `doc-updater.md:13` generic router paragraph | Proves the intended end-state for the Stage-5 deferral — the wording is copied in shape, not re-derived. |
| Repo selftest convention (`*-selftest.sh`, glob-discovered by CI) | The new lint follows it exactly — no CI registration needed, and the guard stays model-free. |

## Implementation steps

1. **`5-implement.md:22`** — replace `Follow all conventions from `.project/reference/conventions.md`.` with a deferral to the repo's declared doc roots via the `doc-update.md` router. State Stage 5's *own* question explicitly: the router answers "which docs are stale" for Stage 7, whereas Stage 5 needs "which conventions to follow while writing code" — same doc roots, different question. Cross-link rather than inline the three tiers (single source of truth, and it keeps AC-5 greppable).
2. **`5-implement.md:19`** — restate the `(AC-n)` convention framework-agnostically: suffix the test title where the framework has one; use an adjacent comment where it does not (`def test_foo():  # (AC-1)`). Preserve the literal `(AC-n)` token. Repoint the link to `review-toolkit:mutation-review`.
3. **`5-implement.md:35`** — repoint the second dead link; drop the normative `*.spec.ts` in favor of the configured test-file convention.
4. **`7-doc-update.md:3`, `SKILL.md:384`, `doc-updater.md:3`** — replace each `.project/` literal with the repo's declared documentation roots, matching the generic bodies these summary lines currently contradict.
5. **`3-write-plan.md:56, :59, :61, :62`** — split the normative clause from the acme example. Normative text names only `commands.<host>.unitTestScope`, the configured test-file convention, and "the repo's data-access handle / external I/O" for the mock boundary. Retained acme values (`apps/api/src/**`, Drizzle, `*.spec.ts`) move into a block carrying the `> **Illustration only — not the contract.**` callout. Repoint both dead links.
6. **`state-schema.md:246`** — `apps/api` backend TypeScript → the configured `unitTestScope` surface; "Absent on FE-only / non-`apps/api` runs" → absent when no `unitTestScope` is configured or the diff does not touch it.
7. **`unit-tests.mjs:181, :194, :203` and `code-review.mjs:231`** — remove `Load the unit-testing skill.` from the three live prompts. The dispatched agents (`unit-test-plan-reviewer`, `unit-test-mutation-reviewer`) already carry the mutation-review contract via their own agent definitions, so the instruction is redundant as well as dangling — deleting it is correct, not merely safe. Genericize `for apps/api changes` at :194.
8. **`mutation-gate.mjs:139`** — repoint the comment citation to the mutation-review skill.
9. **Add `scripts/stack-generality-lint.sh`.** Per the ratified AC-6 (ledger D-6/D-7), the lint guards **only the mechanizable legs** as plain substring checks — AC-2 and AC-5 are review-verified, since a substring lint cannot separate a normative literal from one inside a labeled illustrative block or from prose describing the anti-pattern to refuse. Three legs, each with a declared path scope and check direction:

   - **AC-1 leg (absence):** no `.project/` literal in `stages/5-implement.md`, `stages/7-doc-update.md`, or the run `SKILL.md` (file-wide), and none in `review-toolkit/agents/doc-updater.md`'s **frontmatter block only** — its illustration block (~:176-254) legitimately contains `.project/` examples and must not trip the leg (intake note resolution 2).
   - **AC-3 leg (absence):** zero `unit-testing` matches repo-wide over `plugins/`, with **one documented exclusion**: `plugins/dev-pipeline/skills/run/tools/prose-budget.baseline.tsv` (measurement data, see Assumptions). The lint and its selftest live in `scripts/`, outside the scan scope, so they need no self-exclusion.
   - **AC-4 leg (presence):** the literal `(AC-n)` token still present at both convention sites (`stages/5-implement.md`, `review-toolkit/skills/mutation-review/SKILL.md`).

   Exit code = number of violations, per the repo's doctor convention. Extending the declared file lists is how a future ticket widens the sweep — the mechanism is reusable even though this ticket's scope is deliberately narrow.

10. **`mutation-review/SKILL.md:39`** — widen the `(AC-n)` example beyond the JS-only `it('… (AC-1)', …)` form so the convention reads as framework-neutral in its example as well as its lead sentence. The lead sentence ("suffix its **test title**") already is; only the example needs the non-JS companion.
11. **Add `scripts/stack-generality-lint-selftest.sh`** — fixture-driven: prove each of the three legs fires on a seeded violation, **and** run the lint against the real repo root as the clean-tree case. The clean-tree case is load-bearing twice over: it proves the guard passes on a correct tree, and — because CI discovers `*-selftest.sh` by glob on both lanes — it IS the lint's CI invocation path (D-7; no `.github/workflows/ci.yml` edit). A lint that cannot fail is not a guard.
12. Run the full verification sweep; commit with a `Changelog:` trailer.

## Test strategy

Prose-and-prompt change with no runtime control-flow change, so there is no unit-test mutation surface (`unitTestSurface.applicable == false`; this repo configures no `unitTestScope`). Verification is therefore **static and greppable by design**, which is also what makes the ACs honest in a model-free CI.

The load-bearing test work is the new `scripts/stack-generality-lint-selftest.sh`. It must prove the lint *fails* on seeded violations, not merely that it passes on the current tree — a guard that only ever returns green is indistinguishable from no guard. Cases:

- Seeded `.project/` literal in a fixture stage file → lint fails; a `.project/` literal in a fixture `doc-updater.md` **body** (outside frontmatter) → lint passes (AC-1 leg, both directions of the frontmatter-only scope).
- Seeded `unit-testing` reference in a `.md` **and** in a `.mjs` prompt string → lint fails in both forms; a `prose-budget.baseline.tsv` occurrence → lint passes (AC-3 leg, incl. the documented exclusion).
- Removed `(AC-n)` token at a convention site → lint fails (AC-4 leg — guards the token `pipeline-retro:56` depends on).
- **Clean-tree case: the lint runs against the real repo root** and must exit 0 — this doubles as the lint's CI invocation (the selftest glob runs on both CI lanes).

AC-2 and AC-5 are **review-verified, not linted** (ledger D-6): the normative-vs-illustrative distinction and the router-deferral phrasing are judgment surfaces a substring check cannot honestly mechanize. Stage 8's reviewers verify them against the diff.

## Acceptance-criteria traceability

Keyed by the ratified body AC set (the Stage-1 intent snapshot, 6 explicit IDs).

| AC | Criterion | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | No normative `.project/` literal in `5-implement.md` / `7-doc-update.md` / `SKILL.md` (Model Tiering row) / `doc-updater.md` (frontmatter description); all defer to declared doc roots | 1, 4 | `scripts/stack-generality-lint-selftest.sh` — seeded `.project/` literal fails the lint; frontmatter-only scope proven in both directions |
| AC-2 | No normative Drizzle / `*.spec.ts` / "backend TypeScript" / `apps/api` literal in the guarded files; retained examples carry the "Illustration only" callout. Review-verified, not linted | 3, 5, 6, 7 | — no test (non-functional) |
| AC-3 | Zero `unit-testing` references across `plugins/` minus the single documented exclusion (`prose-budget.baseline.tsv`), covering the 4 `.md` links, the 3 live dispatch prompts, and the `mutation-gate.mjs` comment | 2, 3, 5, 7, 8 | `scripts/stack-generality-lint-selftest.sh` — seeded ref fails in both `.md` and `.mjs`-prompt form; an excluded-file occurrence passes |
| AC-4 | `(AC-n)` stated framework-agnostically at `5-implement.md:19` and `mutation-review/SKILL.md:39`, preserving the literal `(AC-n)` token for the grep in `pipeline-retro:56` | 2, 10 | `scripts/stack-generality-lint-selftest.sh` — removing the token at a convention site fails the lint |
| AC-5 | `5-implement.md` / `7-doc-update.md` resolve conventions through the `doc-update.md` router chain, phrased for Stage 5's own write-time question; the router section still names the three tiers in order. Review-verified, not linted | 1, 4 | — no test (non-functional) |
| AC-6 | Verification sweep green; new lint at `scripts/stack-generality-lint.sh` + paired selftest guard the mechanizable legs (AC-1, AC-3, AC-4), clean-tree case over the real repo root as the CI invocation path | 9, 11, 12 | — no test (infra-only) |

## Verification commands

```bash
# Repo-wide sweep (CLAUDE.md § Verification) — run from the worktree root.
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}

# The new guard, run directly (exit code = violation count).
bash scripts/stack-generality-lint.sh .

# AC-3 spot check — must print nothing. One documented exclusion (measurement
# data); the lint + selftest live in scripts/, outside the plugins/ scan scope.
grep -rn 'unit-testing' plugins/ | grep -v 'prose-budget\.baseline\.tsv'

# .mjs syntax is not covered by shellcheck or by any CI lane in this repo, so this
# is a LOCAL-ONLY check — it does not gate the PR. Run it before committing the
# three edited workflows; the CI-side guarantee for them is the selftest sweep.
for f in unit-tests code-review mutation-gate; do
  node --check "plugins/dev-pipeline/skills/run/workflows/$f.mjs"
done
```

## Risks

| Risk | Mitigation |
| --- | --- |
| **Breaking `pipeline-retro:56`'s AC-coverage grep** by altering the `(AC-n)` token while generalizing its attachment point — this would deepen the exact defect the ticket repairs. | The token is preserved verbatim at every site; AC-4's lint leg asserts its presence, so a future edit that drops it fails CI rather than silently emptying the audit channel. |
| **Deleting `Load the unit-testing skill.` weakens the dispatched agents** if the instruction was doing real work. | It is not: `unit-test-plan-reviewer` and `unit-test-mutation-reviewer` carry the mutation-review contract in their own agent definitions. The string names a nonexistent skill, so its current runtime effect is at best nil and at worst a model chasing a dead reference. Verify against both agent definitions before deleting. |
| **The normative-vs-illustrative line is a judgment call**, so two implementers produce different diffs and a reviewer cannot adjudicate. | Standardized, not linted (D-6): retained examples must sit inside a block carrying the repo's existing callout, so a reviewer adjudicates by looking for the callout — a fixed, greppable convention — rather than re-litigating each literal. |
| **A lint that only ever passes** gives false confidence — the classic guard failure. | The selftest is fixture-driven and asserts each leg *fails* on a seeded violation. A guard that cannot fail does not ship. |
| **The lint's own greps become birth-stack-coupled**, re-introducing the defect inside the guard. | The banned-literal list is a single declared array at the top of the script with a comment stating it is a denylist of *birth-stack* tokens, not a general vocabulary — reviewable in one place rather than scattered through the checks. |
| **Over-genericizing loses useful concreteness** — fully abstract prose is harder for an implementing model to act on than a worked example. | Examples are retained deliberately, just relabeled as non-normative. Same shape `doc-update.md` already settled on, so the pipeline reads in one idiom rather than two. |

## Out-of-scope

- **Recreating a `unit-testing` skill.** Operator-directed: repoint to `review-toolkit:mutation-review`, which already carries the contracts.
- **New config keys** for conventions / ORM / test convention. The `review-context.md`/config sourcing the issue's "Suggested fix" proposes names a key that does not exist; the router precedent is used instead.
- **Editing `pipeline-retro/SKILL.md`.** Its grep is the consumer this plan protects.
- **Genericizing `docs/plans/acme-*.md` naming.** The `acme-` plan-file prefix is itself birth-stack residue, but it is a separate surface (plan-artifact naming, not a prompt contract) with its own consumers. Flagging, not fixing — worth its own issue.
- **A repo-wide birth-stack audit** beyond the sites named here. The new lint makes such a sweep cheap to run later, but running it across all plugins is not this ticket.

## Decision Ledger

Rows D-1/D-2/D-3/D-6/D-7 are hydrated verbatim from the pre-flight ledger (`.claude/pipeline-state/106-ledger.md`, main repo, ledger-lint-validated); D-4/D-5/D-8/D-9/D-10 are in-plan codebase-derived rows (the former in-plan D-6/D-7/D-8, renumbered above the ledger's D-7).

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | How Stage 5 sources repo conventions, given the review-context.md key named in the issue does not exist | Reuse the existing doc-update.md three-tier router; introduce no new config keys | user-answered |
| D-2 | Repoint the dangling unit-testing skill refs, or recreate the skill | Repoint all refs (inert .md links and the live dispatch prompt strings) to review-toolkit:mutation-review, which already carries the cited contracts | user-answered |
| D-3 | Make the (AC-n) convention framework-agnostic, or gate it on a JS runner | Generalize the attachment point (test title where the framework has one, adjacent comment where it does not) and preserve the literal (AC-n) token so the pipeline-retro diff grep keeps working | user-answered |
| D-4 | Are the executable seams in scope, given the issue says they are already clean? | Fold the 3 live dispatch prompts into AC-3 — verified at `unit-tests.mjs:175-206` and `code-review.mjs:231` | codebase-derived |
| D-5 | How can AC-5 be verified without a birth-stack fixture? | Review-verified per D-6; the plan states the deferral phrasing precisely so reviewers check content, not vibes | codebase-derived |
| D-6 | Shape of the AC-6 regression lint after the Stage-4 plan-review block | Lint only the mechanizable legs — AC-1 (.project/), AC-3 (unit-testing), AC-4 (the (AC-n) token) — as plain substring checks with paired selftest; AC-2 (Drizzle / spec.ts / apps/api normative-vs-illustrative) is review-verified, not linted | user-answered |
| D-7 | Invocation path and home for the AC-6 regression lint after the intake spec block | Lint lives at scripts/stack-generality-lint.sh with scripts/stack-generality-lint-selftest.sh — it guards the marketplace sources themselves, and living outside plugins/ keeps the lint and its seeded fixtures out of their own scan scope; the selftest clean-tree case runs the lint against the real repo root in addition to the fixtures, so the existing CI selftest glob is the invocation path and no CI edit is made | user-answered |
| D-8 | Is a point-in-time cleanup sufficient for a markdown-only change? | Add a lint plus paired selftest, per the repo convention that every script pairs with a selftest | codebase-derived |
| D-9 | What distinguishes a normative literal from a retained example? | Retained examples must sit inside a block carrying the existing Illustration-only callout | codebase-derived |
| D-10 | What path scope keeps the lint's AC-1 leg honest on doc-updater.md? | Frontmatter-only for doc-updater.md (its illustration block legitimately contains .project/); file-wide for the three dev-pipeline files | codebase-derived |

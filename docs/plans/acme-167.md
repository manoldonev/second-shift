# acme-167 — review-toolkit boilerplate centralization (slice 1 of 3)

## Context / problem framing

Wave 2 of the #160 prose-debloat program. This slice covers the **review-toolkit** third of #167:
centralize the boilerplate that every reviewer agent restates, settle the sub-agent trust-model
canonical home, and delete two verbatim internal duplicates.

Slices 2 (design-toolkit) and 3 (intake-toolkit) stack on this branch. The stacking exists for one
concrete reason: `.claude/prose-budget.baseline.tsv` is a **single 74-row file** spanning all three
plugins, and the issue's Guardrails mandate a `--update-baseline` re-snapshot per PR. Three parallel
PRs would each rewrite that one file and conflict three ways.

Every candidate below was measured with `wc -w` against `origin/main` at `d2fdc2b`, not estimated.

## Assumptions

1. `skills: <name>` frontmatter is the only mechanism that auto-loads a skill into an agent's
   context. Skills do **not** cross-load other skills. (Verified: `plugins/review-toolkit/agents/*.md`
   frontmatter; `review-lead` carries no `skills:` key.)
2. Relocating text into `reviewer-baseline` is a real token win **only** for agents that declare
   `skills: reviewer-baseline`. Eleven do; `plan-reviewer`, `doc-updater`, `retro-scorer`,
   `structured-emitter` declare none, and `unit-test-plan-reviewer` declares only `mutation-review`.
   Those five are deletion-only targets — never relocation targets.
3. The issue's `(×4)` / `(×3)` / `5→1` repeat counts do not reproduce against the base branch. They
   are treated as advisory; the operative instruction is qualitative (one normative statement plus
   pointers) and every count below is re-measured.
4. No `AC-n` IDs are derivable from #167. Its heading is `## Acceptance`, which does not match
   `/acceptance criteria/i` under the normative positional-fallback rule
   (`plugins/dev-pipeline/skills/run/state-schema.md`), so the run's AC snapshot is empty.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Sub-agent trust-model canonical home | **review-lead**, as the issue originally recommended. Delete `## Sub-Agent Output Is Advisory` from `reviewer-baseline` (103 words × 11 non-dispatching reviewer contexts) and repoint the two intake-toolkit citations at `review-toolkit:review-lead`. Reverses the Stage-1 intake resolution — see Risks. | codebase-derived |
| D-2 | Extension-blockquote centralization form | One parameterized blockquote in `reviewer-baseline` naming `.claude/second-shift/review-context/<this-agent>.md`; per-agent copies deleted. Safe because all 10 carriers declare `skills: reviewer-baseline`. | codebase-derived |
| D-3 | `## Reviewer baseline` pointer sections | Delete outright — the skill is already auto-loaded, so the pointer is pure ceremony. Preserve the two per-agent customizations (`performance`'s `Impact:` line, `pipeline`'s `Contract:` line) by moving them into those agents' own `## Output Format`. | codebase-derived |
| D-4 | plan-reviewer / doc-updater worked examples | Trim in place to one illustrative instance each. Not the `doc-routing.md` plugin-asset route: neither agent declares `skills: reviewer-baseline`, so a bundled asset re-raises the loadability question, and it would add a shipped file needing its own baseline row. | ticket-sourced — https://github.com/manoldonev/second-shift/issues/167 |
| D-5 | Per-file 10–15% reduction band | Treated as a program-level aim, not a per-file gate. Measured projection puts 5 of 8 touched files below 10%. Disclosed up front per the issue's re-baselining comment rather than at Stage 6. | ticket-sourced — https://github.com/manoldonev/second-shift/issues/167#issuecomment-5083019755 |
| D-6 | `scope-completeness-reviewer` independence trim | Reduced to the two sites outside the lockstep block. The `ac-id-rule` `LOCKSTEP-BEGIN/END` region at line 63 is not touched. | codebase-derived |

## Affected files/modules

All paths verified to exist at `origin/main`.

**Canonical home (edited, not created):**
- `plugins/review-toolkit/skills/reviewer-baseline/SKILL.md` — gains the parameterized extension
  blockquote; loses the trust-model section and two of three schema-sole-output restatements.
- `plugins/review-toolkit/skills/review-lead/SKILL.md` — keeps `## Sub-Agent Trust Model` (now
  canonical); loses the verbatim `### Step 6: Plan/Spec Compliance` duplicate of `## Plan/Spec Awareness`.

**Reviewer agents that declare `skills: reviewer-baseline` (relocation targets):**
- `plugins/review-toolkit/agents/a11y-reviewer.md`
- `plugins/review-toolkit/agents/complexity-reviewer.md`
- `plugins/review-toolkit/agents/db-reviewer.md`
- `plugins/review-toolkit/agents/maintainability-reviewer.md`
- `plugins/review-toolkit/agents/performance-reviewer.md`
- `plugins/review-toolkit/agents/pipeline-reviewer.md`
- `plugins/review-toolkit/agents/scope-completeness-reviewer.md`
- `plugins/review-toolkit/agents/security-reviewer.md`
- `plugins/review-toolkit/agents/spec-reviewer.md`
- `plugins/review-toolkit/agents/test-coverage-reviewer.md`
- `plugins/review-toolkit/agents/unit-test-mutation-reviewer.md`

**Deletion-only targets (no `skills: reviewer-baseline` — nothing relocated into them):**
- `plugins/review-toolkit/agents/plan-reviewer.md`
- `plugins/review-toolkit/agents/doc-updater.md`

**Citation repoint (D-1 fallout, kept in this slice so every merge is self-consistent):**
- `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` (line 57)
- `plugins/intake-toolkit/skills/decomposition-reviewer/SKILL.md` (line 29)

**Baseline re-snapshot:**
- `.claude/prose-budget.baseline.tsv`

## Reuse inventory

- `plugins/dev-pipeline/skills/run/tools/prose-budget.sh` — existing `--update-baseline` flag drives
  the re-snapshot. No new tooling.
- `scripts/lockstep-manifest.tsv` + `scripts/check-lockstep-pairs.sh` — existing copies-match lint;
  the live `ac-id-rule` row constrains D-6. Read, not modified, in this slice.
- `skills: <name>` frontmatter — the established relocation mechanism, already used by 11 agents.
- No new helpers introduced.

## Implementation steps

1. **reviewer-baseline: add the parameterized extension blockquote.** One blockquote near the top
   naming `.claude/second-shift/review-context/<this-agent>.md`, carrying the load-order and
   additive-only semantics verbatim from the existing per-agent copies (~45 words).
2. **Delete the 10 per-agent extension blockquotes** from the relocation-target agents. Measured:
   41 words each.
3. **Delete the `## Reviewer baseline` pointer sections** (21 words each) from the agents that carry
   the plain variant. For `performance-reviewer.md` and `pipeline-reviewer.md`, move the
   domain-specific `Impact:` / `Contract:` clause into that agent's own `## Output Format` before
   deleting the section.
4. **Trim the `## Process` sections** to their domain-specific steps. Steps that restate
   `reviewer-baseline`'s Review Process Template items 1, 2 and 7 ("Run `git diff`", "Read sibling
   files for context", "Report findings using the output format at the bottom") come out; the
   domain-specific middle steps stay.
5. **D-1 trust model.** Delete `## Sub-Agent Output Is Advisory` from `reviewer-baseline`. Repoint
   `intake-orchestrator` line 57 and `decomposition-reviewer` line 29 to
   `review-toolkit:review-lead`. Both intake skills keep their own inline MUSTs, so this is a
   citation fix, not a content move.
6. **Delete `### Step 6: Plan/Spec Compliance`** from `review-lead` (58 words, verbatim duplicate of
   `## Plan/Spec Awareness` in the same file). Leave a one-line cross-reference at the Step 6
   position so the numbered Synthesis Rules sequence stays readable.
7. **Trim the worked-example blocks** to one illustrative instance each:
   `plan-reviewer.md` `## Example (one reference stack)` (597 words) and `doc-updater.md`
   `## Example (acme's map)` (477 words).
8. **Emphasis singles.** `reviewer-baseline` schema-sole-output: keep the normative statement at the
   `## Output Mode` head, reduce the two downstream restatements to pointers.
   `test-coverage-reviewer` "honor them as additive": one normative statement, drop the seven per-site
   repeats. `scope-completeness-reviewer` independence: trim to two sites, **outside** the
   `LOCKSTEP-BEGIN/END ac-id-rule` region.
9. **Re-snapshot** `.claude/prose-budget.baseline.tsv` via
   `bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh --update-baseline`.

## Test strategy

Verify-after (prose refactor, no behavior change). No new tests: this slice changes no executable
code path, and the repo's testing tier map routes prose changes to **nothing** — "No prose-presence
guards" in `CLAUDE.md` explicitly forbids grepping literals out of markdown as a test.

The real guards already exist and must stay green:
- `scripts/check-lockstep-pairs.sh` — proves the `ac-id-rule` copies still match byte-for-byte after
  the D-6 trim. This is the one mechanical check that can actually fail on this diff.
- `prose-budget.sh` — flat growth-guard; the re-snapshot must show reductions, not growth.
- The selftest sweep + shellcheck + jq sweep — no shell or JSON is touched, so these are regression
  guards rather than targeted checks.

No `unitTestScope` is configured for this repo (`commands.second-shift.unitTestScope: null`), so
there is no mutation surface and the unit-test gate is skipped.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |

_(No rows: #167's `## Acceptance` heading does not match `/acceptance criteria/i`, so the run's AC
snapshot is empty and no IDs are derivable. Assumption 4.)_

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
bash scripts/check-lockstep-pairs.sh
bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh
```

## Risks / rollback notes

- **D-1 reverses the Stage-1 intake resolution.** The intake comment resolved the trust-model home to
  `reviewer-baseline`. That was wrong: `review-lead` carries no `skills:` frontmatter, so pointing it
  at `reviewer-baseline` would strip the contract from the *primary dispatching* context — the exact
  Guardrail-2 trap the intake analysis invoked against the figma item. The reverse direction is safe
  because the two intake-toolkit consumers only *cite* `reviewer-baseline`; they carry their own
  inline MUSTs and load neither skill. Recorded as a run deviation.
- **Projected per-file reduction misses the issue's 10–15% band on 5 of 8 touched files**
  (`complexity` 8.0%, `db` 5.1%, `performance` 8.4%, `test-coverage` 7.8%, `reviewer-baseline` 2.7%
  net; `a11y` 11.8%, `plan-reviewer` 10.1%, `doc-updater` 12.8% land in band). Files whose only
  in-scope content is a 21-word pointer cannot reach 10%. Disclosed per D-5, not treated as a gate.
- **Lockstep breakage** is the one way this diff can go red mechanically. Mitigated by step 8's
  explicit marker exclusion and by running `check-lockstep-pairs.sh` in verification.
- **Rollback:** every change is prose deletion or relocation inside the plugin tree. `git revert` of
  the slice commit restores the prior text wholesale; no migration, no state, no consumer contract.

## Out-of-scope

- **design-toolkit** (slice 2) and **intake-toolkit internal dedup** (slice 3) — except the two D-1
  citation repoints, which must ride this slice to keep the merge self-consistent.
- The `design-faithful` (claude-design provider) family — resolved out of scope at intake.
- The AC-ID byte-for-byte mirror in `scope-completeness-reviewer` — issue guardrail forbids deduping
  it, and its copies-match lint is already live.
- Adding `skills: reviewer-baseline` to agents that lack it. Changing an agent's loaded-skill set is a
  behavior change, not prose debloat.
- Any version bump or `CHANGELOG.md` edit — repo convention derives both at release time.

Unverified references: none.

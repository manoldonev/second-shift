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
| D-1 | Sub-agent trust-model canonical home | **review-lead**, as the issue originally recommended — but as a **merge, not a delete**. The two sections are not interchangeable: `reviewer-baseline`'s `## Sub-Agent Output Is Advisory` carries three normative clauses absent from `review-lead`'s `## Sub-Agent Trust Model` ("Read the source material yourself BEFORE dispatching"; "Resolve gaps yourself when determinable"; the `auto-fail` half of "never auto-fail or auto-escalate"). Fold those into `review-lead`'s section first, THEN delete the `reviewer-baseline` copy (103 words × 11 non-dispatching reviewer contexts), THEN repoint the two intake-toolkit citations — by the destination's real title, `**Sub-Agent Trust Model**`, not the old one. Reverses the Stage-1 intake resolution — see Risks. | codebase-derived |
| D-2 | Extension-blockquote centralization form | One parameterized blockquote in `reviewer-baseline` naming `.claude/second-shift/review-context/<your-agent-name>.md`; the per-agent copies deleted. Safe because **exactly 10** agents carry the blockquote and **all 10** declare `skills: reviewer-baseline`. Verified by deletion: the blockquote had 10 occurrences repo-wide, one per relocation target. `doc-updater.md` and `plan-reviewer.md` do **not** carry it — they only *mention* `review-context.md` inside their doc-router prose, which is a different construct and is not touched. (`spec-reviewer.md` is the mirror case: declares the skill, carries no blockquote.) | codebase-derived |
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

**Doc reconciliation (Stage-7 finding, added during implementation):**
- `docs/namespaces.md` — rule 3 named `reviewer-baseline` as the protocol intake-toolkit shares from
  review-toolkit. D-1 moves that contract to `review-lead`, and after the repoint intake-toolkit's
  only remaining `reviewer-baseline` mention is an analogy in `interviewing-baseline`, not a
  dependency. Updated to name the Sub-Agent Trust Model at its new home.

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
   41 words each. Ten occurrences repo-wide, one per relocation target — `doc-updater.md` and
   `plan-reviewer.md` do not carry it (their `review-context.md` mentions are doc-router prose, a
   different construct; leave those alone).
3. **Delete the `## Reviewer baseline` pointer sections** (21 words each) from the agents that carry
   the plain variant. For `performance-reviewer.md` and `pipeline-reviewer.md`, move the
   domain-specific `Impact:` / `Contract:` clause into that agent's own `## Output Format` before
   deleting the section.
4. **Trim the `## Process` sections** to their domain-specific steps. Steps that restate
   `reviewer-baseline`'s Review Process Template items 1, 2 and 7 ("Run `git diff`", "Read sibling
   files for context", "Report findings using the output format at the bottom") come out; the
   domain-specific middle steps stay.
5. **D-1 trust model — merge, then delete, then repoint.** In this order:
   1. Fold the three clauses unique to `reviewer-baseline`'s `## Sub-Agent Output Is Advisory` into
      `review-lead`'s `## Sub-Agent Trust Model`: (a) read the source material yourself **before**
      dispatching sub-agents — `review-lead`'s existing "when in doubt, read the actual code yourself
      before relaying a finding" is post-dispatch and conditional, so it does not cover this;
      (b) resolve gaps yourself when the answer is determinable from the codebase or the document at
      hand; (c) the `auto-fail` half of "never auto-fail or auto-escalate" (`review-lead` says only
      "never auto-escalate").
   2. Only then delete `## Sub-Agent Output Is Advisory` from `reviewer-baseline`.
   3. Repoint `intake-orchestrator` line 57 and `decomposition-reviewer` line 29 at
      `review-toolkit:review-lead`, **renaming the cited section to `**Sub-Agent Trust Model**`** —
      both sites currently cite it by the `reviewer-baseline` title, which will not exist at the new
      home. Leaving the old title in place is a dangling anchor, not a working pointer.

   Both intake skills keep their own inline MUSTs, so no content moves into *them* — but the merge in
   sub-step 1 is a genuine content move and must land before the delete.
6. **Delete `### Step 6: Plan/Spec Compliance`** from `review-lead` (58 words, verbatim duplicate of
   `## Plan/Spec Awareness` in the same file). Leave a one-line cross-reference at the Step 6
   position so the numbered Synthesis Rules sequence stays readable.
7. **Trim the worked-example blocks** to one illustrative instance each:
   `plan-reviewer.md` `## Example (one reference stack)` (597 words) and `doc-updater.md`
   `## Example (acme's map)` (477 words). **Update the in-body cross-references that enumerate what
   those blocks contain** — a trimmed example leaves any "as shown in the three cases above"-style
   pointer describing instances that no longer exist. Grep each file for references to its own
   example section and reword to match what survives.
   **Do not touch either file's emit-deadline line** (see Risks) — in `plan-reviewer.md` it sits in
   the guidance list, outside the example block, and `check-emit-deadline.sh` fails if it goes.
8. **Emphasis singles.** `reviewer-baseline` schema-sole-output: keep the normative statement at the
   `## Output Mode` head, reduce the two downstream restatements to pointers.
   `test-coverage-reviewer` "honor them as additive": one normative statement, drop the seven per-site
   repeats. `scope-completeness-reviewer` independence **5 → 2**, **outside** the
   `LOCKSTEP-BEGIN/END ac-id-rule` region: keep the two load-bearing statements (the "why you exist"
   framing and the operative "always fetch the issue yourself" MUST with its anti-gaslighting
   rationale); strip the independence restatement from the tracker-resolution lead-in, fold the
   "What you do NOT do" deferral bullet into a deferral-evidence rule that does not restate
   independence, and delete the bullet that duplicates the operative MUST outright.

10. **Scope/Output stubs → `reviewer-baseline`** (issue scope, review-toolkit bullet 1; ~500 words
    net). Seven agents carried a `## Scope` "You ONLY review X — do not comment on <list>" stub whose
    exclusion lists had **drifted out of agreement** with each other (`a11y` alone excluded visual
    design fidelity). Add one `## Scope discipline` section to `reviewer-baseline` stating the shared
    stay-in-your-lane rule, and collapse each agent's `## Scope` to a single line naming only its own
    domain. Eight agents carried an `## Output Format` stub: the five that were pure restatements of
    `reviewer-baseline`'s own `## Standard Output Format` are deleted outright, and the three with a
    real domain customization (`performance` `Impact:`, `pipeline` `Contract:`, `test-coverage`
    `Recommendation:` guidance) keep only the customization.
    **Not applied to `plan-reviewer.md` / `unit-test-plan-reviewer.md`** — neither auto-loads
    `reviewer-baseline`, so for them the stub is the sole carrier (same rule as D-2).
    `unit-test-mutation-reviewer`'s `## Scope` is a genuine diff-range contract, not a stub, and is
    left intact.
9. **Re-snapshot** `.claude/prose-budget.baseline.tsv` via
   `bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh --update-baseline`.

   The flag is whole-repo — there is no scoped mode — so the re-snapshot also absorbs growth that
   happened on the base branch since the baseline was last taken, in files this slice never touches.
   That drift is **enumerated in the PR body** rather than left silent: 18 rows move for reasons
   unrelated to this slice (largest: `state-schema.md` +1598, `9-open-pr.md` +859, `run/SKILL.md`
   +522; `second-shift/skills/local-dev-refresh/SKILL.md` +101 is untouched by all three slices).
   `prose-budget.sh` is an advisory local tool, not a CI gate, so absorbing the drift re-arms the
   growth guard from today's floor rather than weakening an enforcing check — but the numbers are
   disclosed so the reset is auditable. It also drops one stale row whose path no longer exists
   (`.claude/agents/plan-reviewer-mt30.md`).

## Test strategy

Verify-after (prose refactor, no behavior change). No new tests: this slice changes no executable
code path, and the repo's testing tier map routes prose changes to **nothing** — "No prose-presence
guards" in `CLAUDE.md` explicitly forbids grepping literals out of markdown as a test.

The real guards already exist and must stay green. **Two** of them can actually fail on this diff:
- `scripts/check-lockstep-pairs.sh` — proves the `ac-id-rule` copies still match byte-for-byte after
  the D-6 trim.
- `plugins/review-toolkit/scripts/check-emit-deadline.sh` — lints exactly three agents, and this
  slice edits **all three** (`plan-reviewer.md`, `scope-completeness-reviewer.md`,
  `unit-test-mutation-reviewer.md`). Any trim that removes an emit-deadline line turns it red.
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
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}
bash scripts/check-lockstep-pairs.sh
bash plugins/review-toolkit/scripts/check-emit-deadline.sh
bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh
```

The selftest sweep carries `-P 4` per `CLAUDE.md` — the serial form was retired at `b17e953` and is
~2.4× slower for identical results.

## Risks / rollback notes

- **D-1 reverses the Stage-1 intake resolution.** The intake comment resolved the trust-model home to
  `reviewer-baseline`. That was wrong: `review-lead` carries no `skills:` frontmatter, so pointing it
  at `reviewer-baseline` would strip the contract from the *primary dispatching* context — the exact
  Guardrail-2 trap the intake analysis invoked against the figma item. The reverse direction is safe
  because the two intake-toolkit consumers only *cite* `reviewer-baseline`; they carry their own
  inline MUSTs and load neither skill. Recorded as a run deviation.
- **D-1 is a merge, and the merge is the risky half.** The two sections are near-duplicates, which is
  exactly what makes a straight delete tempting and wrong — three normative clauses live only in the
  `reviewer-baseline` copy. Deleting before folding them in silently drops contract text that exists
  in no other file, and repointing under the old section title leaves both citations pointing at a
  heading that does not exist. Step 5's ordering (merge → delete → repoint-with-new-title) is the
  mitigation; do not collapse it.
- **Per-file reduction misses the issue's 10–15% band on 12 of 16 touched files.** Measured at
  implementation against `origin/main` (not the stale `d2fdc2b` projections, which the rebase
  invalidated), after the step-10 stub centralization: `a11y` 15.5% and `doc-updater` 11.9% land in
  band; `performance` 9.9%, `complexity` 9.7%, `plan-reviewer` 8.3%, `maintainability` 7.9%,
  `test-coverage` 7.9%, `db` 6.3%, `pipeline` 6.2%, `security` 4.7%, `unit-test-mutation` 3.5%,
  `scope-completeness` 3.1%, `reviewer-baseline` 1.8%, and the two intake-toolkit citation sites
  ~0.0% fall below it. `review-lead` **grows** +0.7% (+33 words) by design — D-1 moves content
  *into* it, and `reviewer-baseline` nets only −1.8% for the same reason: it is the **destination**
  of two centralizations (the extension blockquote and `## Scope discipline`), so text arriving
  there offsets what it gives up. A file whose only in-scope content is a 21-word pointer has no 10%
  to give. **Net across the slice: −1525 words.** Disclosed per D-5, not treated as a gate.
- **Emit-deadline breakage.** `check-emit-deadline.sh` lints three agents and this slice edits all
  three. Their deadline lines are load-bearing lint anchors, not trimmable prose. Mitigated by the
  step-7 exclusion note and by running the lint in verification.
- **Lockstep breakage.** Mitigated by step 8's explicit marker exclusion and by running
  `check-lockstep-pairs.sh` in verification.
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

## Commit convention

This is a `plugins/**` change, so CI (`scripts/check-changelog-trailer.sh`) requires a `Changelog:`
trailer on some commit of the branch. The slice is consumer-visible (reviewer agents lose restated
boilerplate and gain it via the auto-loaded baseline; the trust-model contract moves to
`review-lead`), so it takes a real entry rather than `Changelog: none` — for example:

```
refactor(review-toolkit): centralize reviewer boilerplate into reviewer-baseline

Changelog: reviewer agents now inherit the extension-file contract and review-process
  boilerplate from the auto-loaded reviewer-baseline skill instead of restating it; the
  sub-agent trust model is now canonical in review-lead.
  Migration: none.
```

Verb is `refactor:` (patch bump) — no new capability, so `feat:` would overstate it.

Unverified references: none.

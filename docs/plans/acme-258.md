# Plan — #258: design-toolkit single-homing + reviewer-baseline adoption

## Context / problem framing

Wave 2 of the #160 prose-debloat program, slice 2 of #167 (slice 1 landed as `bb83799`). The
`design-toolkit` figma family carries three kinds of duplication:

1. The **Figma-capability block** and the **node-resolve / sparse-dump discipline** are stated
   twice — in `plugins/design-toolkit/skills/figma-faithful/SKILL.md` and
   `plugins/design-toolkit/skills/figma-faithful-spec/SKILL.md` — with the spec copy carrying an
   explicit prose sync liability (`> Steps 1–2 are the same node-resolution discipline as
   figma-faithful steps 1–2. Keep the two in sync if either changes.`). A third file,
   `plugins/design-toolkit/skills/figma-iterate/SKILL.md`, already resolves this the right way:
   it keeps the operative gist inline and points by name at figma-faithful's section.
2. **Branded / host-relative surface rules** are stated canonically in
   `plugins/design-toolkit/agents/figma-faithful-reviewer.md` (`## Branded / host-relative surface
   rules (Warning)`) and re-stated across four passages of `figma-faithful/SKILL.md` plus one rule
   in `figma-faithful-plan-reviewer.md`.
3. The **origin story** and the **dropped-banner anecdote** are retold as standalone narrative in
   three files, on top of the three places where the same lesson is (legitimately) embedded in an
   operative rule.

Separately, `figma-faithful-spec-reviewer.md` and `figma-faithful-plan-reviewer.md` are the only
two reviewer agents in the plugin that do not declare `skills: reviewer-baseline` — their siblings
`figma-faithful-reviewer.md` and `design-faithful-reviewer.md` already do.

The first intake of this ticket blocked on an AC-4 that ordered these two agents to drop their
severity / empty-review / evidence / verdict-template blocks wholesale. That is not implementable:
`reviewer-baseline` is a **merge-gating code-review** contract (Critical/Warning/Pre-existing
against "Blocks merge?") while these two are `review-lead-skip` **artifact** reviewers
(Blocker/Warning/Note against "Action"), and the baseline has no counterpart for the empty-review
rule, the `N/A` non-input rule, or a verdict template. The issue body was respecified (rev 3) to the
reading the codebase supports; this plan implements that reading.

## Assumptions

- `review-toolkit` is a guaranteed co-install. Verified: `onboard`'s baseline set installs it
  unconditionally, and two agents in this same plugin already adopt it cross-plugin.
- Both target agents are dispatched under a JSON schema by
  `plugins/dev-pipeline/skills/run/workflows/figma.mjs` (`kind: 'gate'`, `severity` enum
  `blocker|major|minor|nit`, `verdict` enum `block|fix-and-go|pass|unreachable`). The reconciliation
  paragraph AC-4 requires exists because of this dispatch, not as decoration.
- No relative markdown path from `plugins/design-toolkit/agents/` to the baseline survives both the
  repo layout and the installed-cache layout, so the reference is by name.
- Line numbers in the issue body are hints against the base commit, not anchors.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which file is the canonical home for the Figma-capability block and node-resolve steps | `figma-faithful/SKILL.md`. `docs/plans/160-prose-debloat-scoping.md`'s dedup table records the direction ("skills point at figma-faithful"), and `figma-iterate/SKILL.md` already points there by name — the reverse direction would dangle that pointer. | codebase-derived |
| D-2 | Whether the two adopting agents keep their Blocker/Warning/Note ladder | Keep it locally, and add an explicit mapping into the gate schema's `blocker\|major\|minor\|nit`. The baseline's ladder answers "Blocks merge?"; these agents grade an artifact pre-implementation and have no merge to block. | ticket-sourced — https://github.com/manoldonev/second-shift/issues/258#issuecomment-5129522039 |
| D-3 | How the adopting agents reference the baseline in-body | By name (`review-toolkit:reviewer-baseline`), not a relative link. The two existing adopters use a parent-relative markdown link that resolves into `plugins/design-toolkit/skills/`, where the skill does not live (it is under `plugins/review-toolkit/skills/reviewer-baseline/`); and no relative path is correct in both the repo and the installed-cache layouts. Fixed in the same PR. | codebase-derived |
| D-4 | Whether AC-1's removed sync note becomes a lockstep row or a DROPPED entry | DROPPED entry. Single-homing removes the second copy, so there is no two-copy contract left to anchor — a lockstep row needs a byte-identical block in both files. `scripts/lockstep-manifest.tsv` already carries DROPPED entries with exactly this reasoning shape. | codebase-derived |
| D-5 | Whether the dropped-banner lesson is deleted everywhere | No. Three sites embed it in operative rule text (a `[Warning]` capture rule, a spec step, a template instruction); only standalone narrative retellings are deleted. Deleting the rules would remove the guard the anecdote exists to teach. | ticket-sourced — the AC-3 inventory in the rev-3 body |

## Affected files/modules

- `plugins/design-toolkit/skills/figma-faithful/SKILL.md` — canonical home; loses the origin story;
  branded passages become pointers.
- `plugins/design-toolkit/skills/figma-faithful-spec/SKILL.md` — capability block + steps 1–2 become
  pointers; sync-liability note removed; rationale retelling removed.
- `plugins/design-toolkit/agents/figma-faithful-spec-reviewer.md` — `skills: reviewer-baseline`;
  reconciliation section; Evidence Requirement dropped; intro retelling removed.
- `plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md` — same adoption + reconciliation;
  Evidence Requirement dropped; branded rule becomes a pointer.
- `plugins/design-toolkit/agents/figma-faithful-reviewer.md` — canonical branded block unchanged;
  broken relative baseline link fixed to the by-name form.
- `plugins/design-toolkit/agents/design-faithful-reviewer.md` — broken relative baseline link fixed.
- `scripts/lockstep-manifest.tsv` — DROPPED entry for the de-prosed coupling.
- `.claude/prose-budget.baseline.tsv` — whole-repo re-snapshot.

Unverified references: none. No file below is created; no helper is introduced.

## Reuse inventory

- `plugins/design-toolkit/skills/figma-iterate/SKILL.md` — the existing in-repo pointer shape
  ("operative gist inline, `(See figma-faithful's "Figma capability" section — not restated.)`").
  Reused verbatim as the pointer contract for AC-1 and AC-2 rather than inventing a new form.
- `plugins/design-toolkit/agents/figma-faithful-reviewer.md` `## Reviewer baseline` — the existing
  reconciliation-paragraph shape (names Output Mode, enumerates which baseline sections govern,
  qualifies the prose-only sections). Reused as the template for both new adopters.
- `plugins/review-toolkit/skills/reviewer-baseline/SKILL.md` `## Severity Levels` §"Severity
  vocabulary mapping (Workflow-schema dispatch)" — the existing prose→schema mapping-table shape.
  The new local mapping mirrors its columns.
- `scripts/lockstep-manifest.tsv` DROPPED-entry convention — reused, not re-designed.
- `plugins/dev-pipeline/skills/run/tools/prose-budget.sh --update-baseline` — existing tool.

No new helpers introduced.

## Implementation steps

1. **AC-3 deletions first** (they shrink the files the later steps edit, and they are independent):
   remove the origin-story narrative from `figma-faithful/SKILL.md`; remove the rationale retelling
   from `figma-faithful-spec/SKILL.md`; remove the intro retelling from
   `figma-faithful-spec-reviewer.md`. Leave every operative rule intact — verify by grepping the
   three keeper sites afterward.
2. **AC-1 single-homing.** In `figma-faithful-spec/SKILL.md`, replace the `## Figma capability`
   block body and the steps-1–2 bodies with the figma-iterate-shaped pointer (operative one-liner +
   by-name reference to figma-faithful), and delete the `Keep the two in sync` note. Preserve the
   spec-only deltas that have no figma-faithful counterpart: the fifth MCP tool
   (`get_code_connect_map`) and the spec-side terminal sentence ("do not transcribe from a static
   image alone"). Confirm `figma-iterate`'s pointer still names a section that exists.
3. **AC-2 branded-surface pointers.** In `figma-faithful/SKILL.md`, reduce the branded passages to
   their operative one-liner plus a by-name pointer to `figma-faithful-reviewer`'s
   `## Branded / host-relative surface rules` section. Same for
   `figma-faithful-plan-reviewer.md`'s branded rule. `design-faithful-reviewer.md` is untouched.
4. **AC-4 adoption.** Add `skills: reviewer-baseline` to both agents' frontmatter (neither has a
   `skills:` key today — this is a net-new line). Drop each agent's `## Evidence Requirement`
   block. Add a `## Reviewer baseline` section `[NEW]` to each, modeled on `figma-faithful-reviewer.md`'s,
   stating that Output Mode governs (StructuredOutput is the sole output under the schema dispatch)
   and carrying the local→schema severity mapping (Blocker → `blocker`, Warning → `major` for a
   contract gap that forces a guess / `minor` otherwise, Note → `nit`) as superseding the baseline's
   Critical/Warning/Pre-existing table. Retain: the ladder, the fenced `## Final Verdict
   (single-pass output)` template, the trinary rule table, the empty-review rule, the `N/A` rule.
   Diff-check that `### Verdict: block | fix-and-go | pass` is byte-identical in both files.
5. **AC-4 link fix.** Replace the broken `[reviewer-baseline](../skills/reviewer-baseline/SKILL.md)`
   links in `figma-faithful-reviewer.md` and `design-faithful-reviewer.md` with the by-name form.
6. **AC-1 register entry.** Add a DROPPED entry `[NEW]` to `scripts/lockstep-manifest.tsv` recording that
   single-homing removed the two-copy contract, in the file's existing comment-block style.
7. **AC-5 verification + re-snapshot.** Run the full verification suite, then
   `prose-budget.sh --update-baseline`, and commit the re-snapshot. Diff the baseline to enumerate
   any unrelated drift the whole-repo flag absorbed.

## Test strategy

Verify-after (refactor + prose). This change touches only Markdown and TSV — there is no behavior
to test-first, and per repo convention prose-presence guards are explicitly forbidden ("Grepping a
literal out of a markdown file asserts only that prose contains words"). The couplings that *are*
real are recorded in `scripts/lockstep-manifest.tsv` (step 6), which is the sanctioned tier.

The guards that actually exercise this change:

- `scripts/check-lockstep-pairs.sh` via the selftest sweep — validates the manifest edit parses and
  every live row still matches.
- The full `*-selftest.sh` sweep — proves no consumer of these files broke (the frontmatter edit is
  the only machine-read change; `check-model-tiers.sh` reads these agents' `model:` lines).
- `shellcheck` + `jq empty` — unchanged surfaces, run because AC-5 names them.
- `prose-budget.sh` — the growth-guard the re-snapshot resets.

No new selftest is added: there is no new script and no new gate contract, so per the tier map the
correct answer is "nothing" for prose and a manifest row for the coupling.

`unitTestSurface`: **skip** — no `unitTestScope` is configured for this repo, and the diff is
docs/config-only with no behavior change.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Capability block + node-resolve single-homed in figma-faithful; sync note gone; figma-iterate pointer survives; lockstep DROPPED entry | 2, 6 | `check-lockstep-pairs.sh` via selftest sweep; manual pointer-resolution check — no test (covered-by-selftest) |
| AC-2 | Branded rules canonical in figma-faithful-reviewer; other copies are pointers with the operative line inline | 3 | — no test (covered-by-selftest) |
| AC-3 | Three standalone retellings deleted; three operative rules keep their rule text | 1 | — no test (covered-by-selftest) |
| AC-4 | Both agents declare `skills: reviewer-baseline`, drop Evidence Requirement, keep ladder/template/trinary/empty-review/`N/A`, carry the reconciliation + schema mapping, enum byte-identical, baseline referenced by name, two broken links fixed | 4, 5 | `check-model-tiers.sh` + selftest sweep (frontmatter parse); byte-diff of the enum line — no test (covered-by-selftest) |
| AC-5 | Baseline re-snapshot committed; selftests + shellcheck + jq green; PR body labels drift-prevention and enumerates absorbed drift | 7 | the verification commands below |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} bash {}
bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh
bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh --update-baseline
```

The selftest sweep runs **without** `SKIP_STRESS=1` — only CI's ubuntu lane exercises the stress
legs otherwise.

## Risks / rollback notes

- **Relocation vs token win.** Skills and agents load into separate contexts. AC-2 moves rules from
  a skill into an agent the skill's context does not load, so it is **drift-prevention, not a token
  win**, and the PR body must say so (AC-5). The mitigation is the pointer contract: the operative
  one-liner stays inline, so the implementing agent never loses its rule.
- **Over-deletion under AC-3.** The dropped-banner lesson is embedded in three operative rules. The
  rollback signal is a `figma-faithful-spec-reviewer` that no longer flags a persistent banner
  captured in only one state frame. Step 1 ends with an explicit grep of the three keeper sites.
- **Whole-repo re-snapshot.** `--update-baseline` is repo-wide, so it silently absorbs unrelated
  drift. Mitigation: diff the baseline before committing and enumerate any non-design-toolkit row
  change in the PR body.
- **Rollback** is a plain revert — no migration, no state, no consumer contract changes shape.

## Out-of-scope

- `design-faithful-reviewer.md`'s ladder and structure (only its broken link is fixed).
- The `design-faithful` / `design-faithful-spec` family's own duplication (a separate #167 slice).
- Narrowing the `#NNN` narrative counter, and any per-file reduction target — #160 records both as
  program-level aims, not gates.
- Any behavior change to the two agents' checklists.

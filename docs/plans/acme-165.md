# Plan — #165: run-surface prose debloat (dedup, ceremony cuts, audit defect fixes)

## Context / problem framing

Wave 1 of the #160 prose-debloat program. The binding reference is
`docs/plans/160-prose-debloat-scoping.md` (landed on main via #168), which measured the
instruction layer at ~79% contract and ranked 17 reduction candidates. This issue owns
candidates 1, 2, 5, 6, 7, 10, 11, 12, 13, 17 (dev-pipeline part) plus the three incidental
defects the same audit surfaced.

This is a **pure-prose wave**: no rule is deleted. What goes is restatement, essays
narrating gates that are already mechanically enforced, examples beyond the first, and
`#NNN` archaeology. Every cut names the statement or gate that survives it.

The **run-session surface** is the optimization target — the words that co-reside in one
autonomous `/dev-pipeline:run` context. It is not the whole layer, and it is not what
`prose-budget.sh` totals.

## Assumptions

1. `docs/plans/160-prose-debloat-scoping.md` is binding for candidate scope and for the
   arbitration posture when a target and a guardrail conflict.
2. Sibling #166 (mechanization) is open and unmerged. #165 may land first: the report's
   ordering note exists only so candidate 3's stage-entry cut is not made bare, and #165's
   guardrail already excludes that whole family. Nothing else in #165 depends on #166.
3. `prose-budget.sh` stays a flat growth-guard. It is re-snapshotted, never ratcheted.
4. Selftests that scrape prose (see Risks) are load-bearing: a wording cut can break CI
   even though no behavior changed.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What exactly does "run-session surface" measure? | The 15 files in the report's load-surface row, frozen in this plan under Verification commands, summed with `wc -w`. `prose-budget.sh` has no load-surface concept and cannot compute it. | codebase-derived |
| D-2 | Does scope bullet 1 (de-surface operator docs) reduce the measured number? | No. The four operator docs are already link-only and were never in the baseline, so the "~3k off-surface" is already true. The bullet reduces to its ~250-word cut, and no prose is inlined into stages 1/9 unless a behavioral delta is genuinely missing today. | codebase-derived |
| D-3 | Does the `state-schema.md` bullet count toward AC-1? | No. The report classes it reference / per-section read and excludes it from the 15-file set. The work stays in scope, scoring against the whole-layer secondary metric only. | codebase-derived |
| D-4 | Defect 3 — two stale stage refs or three? | Three. `hooks.md:131` carries the two the issue names; `hooks.md:133` carries a third of the same class. Fixing two would leave a contradiction two lines down. | codebase-derived |
| D-5 | Where does "name the surviving canonical statement" get delivered? | A `Cut → surviving canonical statement / enforcing gate` table in the PR body, one row per cut site. | codebase-derived |
| D-6 | AC-1 is 40,500 but the surface measures 45,349 today, not the report's 44,320. | The guardrail outranks the number. Cuts stay scoped to the named candidates; contract is never cut to reach a target. If the honest cuts land above 40,500, the PR discloses the measured figure and the delta. The report itself sets this posture: "no margin is claimed", and a deeper target "would force cutting contract and is explicitly not proposed". | codebase-derived |
| D-7 | `6-verify.md` — five inert essays or six? | Six blocks (`6-verify.md` lines 60/62/64/66/68/70); the issue says five because the last covers two file types. All six relocate. | codebase-derived |

The +993-word drift from the report's 44,320 baseline came from #158/#161/#162/#163/#164
landing after the scoping pass. Most of it landed *inside* the candidate targets (stages/8
+342 is candidate 10's exact block; `SKILL.md` +298 is candidate 7's receipt prose), so the
available cut scales with the growth — but not by enough to close the full gap. See Risks.

## Affected files/modules

Run-surface files (edited here). Note the AC-1 command measures **15** paths — these 12
plus `stages/4-plan-review.md`, `intake-orchestrator/SKILL.md` and `review-lead/SKILL.md`;
measured-but-not-edited is expected, and `4-plan-review.md` is edited here only by the
archaeology sweep:

- `plugins/dev-pipeline/skills/run/SKILL.md`
- `plugins/dev-pipeline/skills/run/stages/1-intake.md`
- `plugins/dev-pipeline/skills/run/stages/2-worktree.md`
- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md`
- `plugins/dev-pipeline/skills/run/stages/5-implement.md`
- `plugins/dev-pipeline/skills/run/stages/6-verify.md`
- `plugins/dev-pipeline/skills/run/stages/7-doc-update.md`
- `plugins/dev-pipeline/skills/run/stages/8-code-review.md`
- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md`
- `plugins/dev-pipeline/skills/run/stages/10-cleanup.md`
- `plugins/dev-pipeline/skills/run/doc-update.md`
- `plugins/dev-pipeline/skills/run/eval-criteria.md`

Off-surface (whole-layer metric only):

- `plugins/dev-pipeline/skills/run/state-schema.md`
- `plugins/dev-pipeline/skills/run/hooks.md`
- `plugins/dev-pipeline/skills/run/tools/is-inert-diff.sh` — relocation target for D-7
- `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` — archaeology only
- `plugins/second-shift/skills/onboard/SKILL.md` — defect 2 + version-citation archaeology
- `plugins/review-toolkit/skills/review-lead/SKILL.md` — archaeology only
- `plugins/review-toolkit/agents/scope-completeness-reviewer.md` — archaeology only
- `plugins/design-toolkit/skills/figma-faithful/SKILL.md` — archaeology only
- `plugins/design-toolkit/skills/design-faithful-spec/references/fe-spec-template.md` — archaeology only
- `plugins/design-toolkit/skills/design-faithful-spec/examples/detail-spec.example.md` — archaeology only
- `.claude/prose-budget.baseline.tsv` — re-snapshot

`review-lead/SKILL.md` and `intake-orchestrator/SKILL.md` are on the run surface but their
**structural** dedup belongs to #167; only the archaeology sweep touches them here.

## Reuse inventory

- `plugins/dev-pipeline/skills/run/tools/prose-budget.sh` — existing; `--update-baseline`
  regenerates the whole TSV. Not modified.
- `plugins/dev-pipeline/skills/run/tools/is-inert-diff.sh` — existing; already the declared
  single source of truth for the inert pattern set, and already linked from `6-verify.md`.
  It gains comments only; its patterns are untouched.
- `plugins/dev-pipeline/skills/run/tools/is-inert-diff-selftest.sh` — existing; already
  guards the pattern set, which is why the essays can relocate without losing enforcement.

No new helpers introduced.

## Implementation steps

1. **Defect fixes** (smallest, independently correct, first).
   - `stages/2-worktree.md` — delete the second occurrence of the back-to-back duplicated
     sentence in the *Canonical path form* paragraph.
   - `plugins/second-shift/skills/onboard/SKILL.md` — Steps 7 and 8 cite "Step 3 item 8" for
     the CI-evidence gate; Step 3 numbers that offer as item **9** (item 8 is the
     review-context scaffold). Correct both citations to item 9.
   - `hooks.md` — three stale stage refs (D-4): full verify suite Stage 7 → **6**;
     commit-per-chunk workflow Stage 6 → **5** (line 131); and the "denies a commit during
     Stage 6" ref on line 133 → **Stage 5**. Prose only — the embedded hook code block is
     diffed verbatim by `pre-commit-typecheck-selftest.sh` and must not be touched.
2. **`6-verify.md` inert essays → `is-inert-diff.sh` comments** (D-7; ~895 words measured).
   Move all six "Why X is inert" blocks into the script as comments above the pattern set
   they justify. Keep in `6-verify.md`: the canonical pattern list, the
   `is-inert-diff.sh`-is-the-source-of-truth pointer, and the 3-line rule (default-to-SUITE
   when in doubt; never widen the inert list mid-run). Preserve the literal
   `stageParams.visualCapture` token elsewhere in the file — `check-config-shadowing-selftest.sh`
   greps for it.
3. **`run/SKILL.md` dedups** (~830+): design-driven paragraph → `state-schema.md` **Design
   Mode** pointer, keeping the interactive-only launch warning; single-home the RUN_ID,
   `statectl reclaim`, and failed-state-clearing duplicates; compress the comment-hygiene
   cluster to one normative statement plus one code comment each. Every rule survives —
   they are observed-failure-backed. Keep the claim-helper references intact
   (`claim-selftest.sh` asserts SKILL.md still points at the helper rather than re-inlining).
4. **Receipt restatements → `(completion-gated)` tags** across stages 1/3/8/9 (~250). The
   `statectl set-stage --status completed` refusal is the enforcement; the prose restating it
   at each site is what goes.
5. **`stages/8-code-review.md`** (~290+): compress the skill-load emphasis block to ~5 lines
   — the `skillsLoaded[]` completion gate (#158) is the enforcement now — and drop the
   non-authoritative review-contract "reminder" list, keeping "review-lead's Synthesis Rules
   are authoritative". Do not disturb the secondary-review bash loop below it;
   `stage8-perrepo-review-selftest.sh` mirrors it verbatim.
6. **`stages/9-open-pr.md`** (~250): cost-block mechanism prose → pointer at
   `cost-tracking-setup.md`, which today carries the same text. Stage 9's mark-started essay
   is **not** touched (owned by #166).
7. **`run/doc-update.md`** (~455): keep the 7.B example map — the file's stated purpose —
   and drop "Why this matters" plus the `docUpdaterFindings` restate (the checkpoint schema
   in `state-schema.md` is canonical for that field).
8. **Emphasis singles** (~600): mktemp rule 4 sites → 2 (`SKILL.md`); verifyctl-ownership
   5 → 1; INFRA-never-charged 4 → 1 (`6-verify.md` lines 31/85/87 collapse into the
   classification table row at line 81); EP-7 guarantee 3 → 1.
9. **`state-schema.md` refrain consolidation** (~400, off-surface per D-3): `--force` scope
   6 → 1 convention note, "deliberately-not-a-closed-enum" 4 → 1, "additive/no-migration"
   6 → 1. **Each per-site tag restates the operative clause inline** — the file is read
   per-section and a bare pointer is invisible at the read site. The
   `--force`-never-bypasses-`mark-completed` clause survives verbatim. Enum **values** and
   the *Stage-comment markers* block survive verbatim — `statectl-selftest.sh` scrapes them
   from this prose.
10. **Scope bullet 1 residual** (D-2): confirm no stage mandates a read of
    `cost-tracking-setup.md` or the three tracker READMEs (they are `See […]` pointers
    today), and cut the ~250 words of operator prose duplicated between stages 1/9 and those
    docs. Inline nothing new.
11. **Archaeology sweep**: 41 narrative `#NNN` refs across 17 files (the counter read 39/16
    when this plan was written; the rebase onto `origin/main` added two `#169` refs). Keep
    every annotated rule; drop the number and the origin story. **Not all 41 are
    archaeology** — 8 are hex colors, instructional issue-reference examples, and an
    example-table cross-reference, which the counter's `#<2-4 digits>` regex cannot
    distinguish and which must survive. The reachable floor is 8, not 0.
12. **Re-snapshot** `bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh --update-baseline`
    and commit `.claude/prose-budget.baseline.tsv`.
13. **Measure** the run surface with the frozen command and record the figure for the PR body.

Commits are chunked per step-group with `refactor(dev-pipeline):` / `fix(dev-pipeline):`
verbs, all via `bot-commit.sh`.

## Test strategy

Verify-after — this is a documentation refactor with no behavior change, so there is no
test-first surface. The existing selftests **are** the regression suite here, and several of
them scrape the exact prose being edited, which makes a full selftest run the real gate
rather than a formality.

- Full selftest sweep after every step-group, not just at the end — a prose-scraping
  selftest fails loudly and locally that way.
- `shellcheck` over `is-inert-diff.sh` after step 2 adds comments to it.
- `jq empty` over all JSON (unchanged, but cheap and CI runs it).
- `prose-budget.sh` (check mode) must report every touched file as `ok shrank` or `ok`, and
  `narrative #NNN: 0`.
- Run-surface measurement against AC-1.

No `unitTestScope` is configured for this repo, so the Stage-5 mutation gate does not apply.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Run-session surface ≤ 40,500 words | 2–11 | — no test (non-functional) |
| AC-2 | Selftests + shellcheck + jq green | 1–12 | — no test (covered-by-selftest) |
| AC-3 | PR carries a `Changelog:` trailer | commit stage | — no test (infra-only) |

How each row is checked: **AC-1** by the frozen `wc -w` command under Verification commands
(D-6 governs a shortfall); **AC-2** by the full `*-selftest.sh` sweep plus `shellcheck` and
`jq empty`; **AC-3** by `scripts/check-changelog-trailer.sh` in CI.

## Verification commands

```bash
# AC-2 — the CI gate set, run from the worktree root
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}

# prose-budget: every touched file shrank; narrative #NNN reaches 0
bash plugins/dev-pipeline/skills/run/tools/prose-budget.sh

# AC-1 — the frozen run-session surface (D-1). This 15-path set IS the definition.
R=plugins/dev-pipeline/skills/run
cat "$R/SKILL.md" \
    "$R/stages/1-intake.md" "$R/stages/2-worktree.md" "$R/stages/3-write-plan.md" \
    "$R/stages/4-plan-review.md" "$R/stages/5-implement.md" "$R/stages/6-verify.md" \
    "$R/stages/7-doc-update.md" "$R/stages/8-code-review.md" "$R/stages/9-open-pr.md" \
    "$R/stages/10-cleanup.md" "$R/doc-update.md" "$R/eval-criteria.md" \
    plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md \
    plugins/review-toolkit/skills/review-lead/SKILL.md \
  | wc -w
# Baseline at intake: 45313. Target: <= 40500.
```

## Risks / rollback notes

**R1 — prose-scraping selftests (highest).** Several selftests read prose, not schema:

| Selftest | Scrapes | Constraint |
| --- | --- | --- |
| `statectl-selftest.sh` | closed-enum values + *Stage-comment markers* from `state-schema.md` prose | values and the marker block survive verbatim (step 9) |
| `intake-readroot-selftest.sh` | literal `non-main-base-autonomous` row, `Step 1.P pin contract` | anchor phrases must not be deleted |
| `check-config-shadowing-selftest.sh` | literal `stageParams.visualCapture` (6-verify), `tracker.branchPrefix` (2-worktree) | exact config tokens survive (steps 1, 2) |
| `pre-commit-typecheck-selftest.sh` | diffs the embedded hook block in `hooks.md` verbatim | step 1 edits `### Scope` prose only |
| `stage8-perrepo-review-selftest.sh` | verbatim-mirrors a bash loop in `8-code-review.md` | step 5 works above it; mirror must not drift |
| `claim-selftest.sh` | SKILL.md / 1-intake.md still reference the claim helper | step 3 keeps those references |

Mitigation: full selftest sweep after each step-group, so a break is attributable to one
step-group rather than to a 20-file diff.

**R2 — AC-1 missed, and that is disclosed rather than closed by cutting contract.** The
surface measured 45,349 at implementation start against the report's 44,320, so an absolute
40,500 needed a 4,849-word cut where the candidate estimates summed to ~3.8–4.0k (labeled
±15% analyst judgment). The plan projected **~41.0–41.7k**.

**Measured at step 13: 43,618** — a shortfall of 3,118, roughly 2k worse than projected.
Per D-6 the number is reported, not closed by cutting contract. Why the projection missed:
only the *relocation* candidate hit its estimate (6-verify's inert essays, est. ~895 /
actual 898, because moving prose out of a run-surface file removes its full weight). Every
*compression* candidate under-delivered by 50–75% (SKILL.md est. ~830 / actual 287;
doc-update est. ~455 / actual 115; 9-open-pr est. ~250 / actual 130), because the "no rule
is deleted" guardrail means a restatement can only be tightened, not removed — and a
tightened clause still costs most of its words. The estimating lesson for #166/#167:
relocation and deletion budgets are reliable; compression budgets are not.

**R3 — baseline TSV collision with #166.** `--update-baseline` rewrites the entire TSV, so
whichever of #165/#166 merges second gets a whole-file conflict. Resolution is mechanical:
re-run `--update-baseline` on the second PR after rebasing. Flagged in the PR body.

**R4 — `hooks.md` is touched by both issues.** #165 edits the `### Scope` prose; #166
removes the embedded script block. Textually disjoint, but adjacent — noted for whoever
rebases.

**Rollback**: every step-group is its own commit, and no step changes executable behavior
except `is-inert-diff.sh`, which gains comments only. Reverting any single commit is safe
and leaves the rest coherent.

## Out-of-scope

- Any stage-entry mark-started prose, including stage 9's — owned by #166, must land paired
  with its check (issue guardrail).
- Candidates 3, 4, 16 (mechanization) — #166.
- Candidates 8, 9, 14, 15 and the review-toolkit part of 17 (cross-plugin dedup) — #167.
  `review-lead` and `intake-orchestrator` are touched here for archaeology only.
- The deliberate non-candidates named in the report: security/plan-reviewer calibration
  example sets, the trivial-inert carve-out, dark-reviewer accounting, both halves of the
  scope-independence contract, the AC-ID byte-for-byte mirror, `stages/10-cleanup.md` as a
  model citizen, `pipeline-retro/SKILL.md`, and eval-criteria's JSON example and criterion
  letter.
- Any change to `prose-budget.sh` behavior. It stays a flat growth-guard; only its baseline
  data is re-snapshotted.

Unverified references: none.

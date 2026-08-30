# lean review verdict — #704

verdict=approve
run_id: review-704-3
session_id: 44ba37b0-1ae1-4522-a84b-e6bc33ad75c6
rounds: 3
pr: #713
reviewed_head: 3073a9d36d6934cc92ab11b4e53366697a7e3575
reviewed_patch_id: ce2c98bdbb7dba387b01ff485efab5ff79406c9c
inherited_patch_id: 28470ade906bf7f00741b9d1f1f40e3cd5c5f303
inherited_from_verdict: 6fc34a343f4d6975ddd8d8c6c306c532a76fd6d8
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Round 3 — PR #713 (issue #704) — approve

Range read: `6fc34a3..HEAD` (2 files, +12/-7), inheriting the coverage of patch `28470ade906b`.
Read wider than the range for the claim-twin sweep and for AC-4/AC-7, which are branch-wide.

Panel 4/4 alive (security, performance, maintainability, scope-completeness), zero panel
blockers. Maintainability retried once on a text-contract miss and returned `approve`.

## Verdict

**approve.** No blockers. All three round-2 findings (B1, B2, W1) are fixed, and each fix was
re-derived from the raw artifact rather than read off the corrected text.

## Round-2 findings — disposition

| Prior | Status | How verified |
| --- | --- | --- |
| B1 — `CLOSEOUT-BASELINE.md:95` prose contradicted the corrected table at `:39` and accused the CONTROL fixture of over-reaching | **fixed** | Every figure in the replacement paragraph re-derived from `.detail[fixture].runs[].per_dim` in `results-20260830T145540Z.json` |
| B2 — D-13 row at `:176` said all three sites were rewritten "in the D-2 lockstep commit set" | **fixed** | `git show --stat 086b336` = the two agent files only; `373096a` = `lean-gate.sh` + this row. The row now says so |
| W1 — AC-7 discharged its near-misses as "in the grep set", naming the literal `N/A` sweep | **fixed** | Both sweeps re-run at this head; neither near-miss line contains `N/A`, and AC-7 now names the broader `reached nothing` sweep D-13's row carries |

### B1 re-derivation (ground truth, `results-20260830T145540Z.json`)

```
01  d3 = 2,2,2  → 6/6
02  d3 = 1,1,0  → 2/6   (all three runs deducted)
03  d3 = 2,2,0  → 4/6   (run 2 only)
04  d3 = 2,2,2  → 6/6
```

Every claim in the new paragraph holds:
- "Four of the twelve runs over-reached" — 4 runs carry a d3 deduction. ✓
- "all of them on fixtures 02 (all three runs) and 03 (run 2)" ✓
- "Fixtures 01 and 04 are clean at 6/6" ✓
- "Two of the four over-reaches hit `rubric.py`'s most severe `0` band" — 02 run 2 and 03 run 2. The
  quoted band text matches `rubric.py:111-112` verbatim. ✓
- "fixture 02 run 0's was filed as a **Blocker** (F3), not a Warning" ✓ — and I checked the other
  three judge justifications: 02 run 1, 02 run 2 and 03 run 2 are all *Warning*-severity
  over-reaches, so singling out run 0 is correct, not selective.

The table at `:39` is unchanged and still agrees: 6 lost d3 points = 02 (4) + 03 (2).

### Claim-twin sweep (the round-2 lesson, applied)

Grepped the *propositions* the fix corrected, not the fixed lines, across the branch:

- d3 over-reach count / distribution: `over-reach|overreach|72\.5|secondary signal` over
  `plugins/design-toolkit/evals/` and the spec — the only sites are `CLOSEOUT-BASELINE.md:39` and
  `:95-101`, both now consistent. `changelog.md` carries `d3=75%`, consistent. No twin.
- "rewritten in the D-2 lockstep commit": the D-13 *prose* at `:141-142` (written by the round-1
  fix, unchanged this round) already said it correctly; the row now matches it. AC-4's "in the same
  commit" scopes to the two agent files, which `086b336` satisfies. No twin.
- "no owner on the lean lane" / blanket `N/A`: zero hits outside the corrected sites. No twin.

## AC scoring (all seven, every round, against the whole spec)

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | Three `evals/<agent>-eval/` dirs, each 4 `<name>.md` + `<name>.expected.json` pairs covering the tabulated shapes. "Runnable" holds: all three `run.sh` pass `--fixtures-dir "$HERE/fixtures"`, a committed in-repo directory. Re-run at this head: `shellcheck -e SC1091,SC2015,SC2181` on the three wrappers rc=0; `jq empty` on every `*.expected.json` rc=0 |
| AC-2 | **satisfied** | Three `CLOSEOUT-BASELINE.md`, each carrying Headline / Per-fixture / Per-dimension / Provenance. The spec-reviewer file's arithmetic re-derived end to end: d1 52/72, d2 17/24, d3 18/24 → 87/120 = 72.50%; per-fixture 20.0 / 86.7 / 93.3 / 90.0%. Provenance names branch, prompt SHA `6dd9f70`, `FIXTURE_VERSION=2` / `RUBRIC_VERSION=1`, and the exact invocation. `6dd9f70` precedes `086b336`, so the baseline is pre-edit by construction |
| AC-3 | **not applicable — out of scope** | Re-cut at pre-flight by ledger row D-1 (`user-answered`), which is binding at step 4; #707 is filed and cross-links. Nothing in the diff runs a campaign and no baseline reports a post-edit re-measurement |
| AC-4 | **satisfied** | `figma-faithful-spec-reviewer.md:21/23/25/155` re-derive `N/A` to "not a design artifact at all"; the three dependent paragraphs in `figma-faithful-plan-reviewer.md` are rewritten in the *same* commit `086b336`. Re-grepped both files: no sentence claims the blanket lean-lane `N/A`, and copy *capture* now reads "has an owner on the lean lane only where the spec recorded the strings" |
| AC-5 | **satisfied** | `086b336` carries a `Changelog:` trailer naming both prompt changes. No `version`, no `CHANGELOG.md`, no `marketplace.json` edit. CI `frozen files guard` and `changelog trailer guard` both green at `3073a9d` |
| AC-6 | **satisfied** | Re-run at this head: `scripts/check-eval-model-identity.sh` → `✓ 86 runnable eval file(s) carry no vendor model identity`; shellcheck rc=0; `jq empty` rc=0. Corroborated by `lint-and-selftests` success at `3073a9d` |
| AC-7 | **satisfied** | Both sweeps **re-run, not asserted**, at this head. Literal `N/A` sweep over `*.md`/`*.sh`/`*.mjs`/`*.json` outside `docs/plans/`: no fourth stale site — every remaining hit is past-tense, names the fix, or is measurement prose. Broader `reached nothing` sweep: exactly four hits — `lean-gate.sh:3773` and `:3775` (the corrected site, now "an agent that, **at the time**, returned N/A") plus the two known near-misses, both past-tense and correctly discharged |

## Notes (not blockers)

- **N1 — `plugins/design-toolkit/evals/README.md:110`: "The spec reviewer's deficit is one
  fixture."** 24 of the 33 lost points (73%) are fixture 01; the remaining 9 are the d3 over-reaches
  on 02/03 and the control's d1/d2 losses. The summary table two lines above hedges correctly
  ("nearly all of it in one fixture"), as does `CLOSEOUT-BASELINE.md:91` ("virtually all"). This is
  the same table-hedged / prose-absolute shape as round 2's B1, which is why it is called out — but
  it states no false measured figure and makes no claim about the control, it is outside the delta,
  and it is unchanged since `6f18b80`. Recorded, not blocking.
- **N2 — "the control fabricated nothing" (`:96`).** The *reviewer* fabricated nothing against the
  control; a fixture cannot fabricate. And the inference is one-way: a d3 of 6/6 on the control is
  consistent with the fixture being clean but does not establish it — a still-miscalibrated control's
  real defects would score d3=2 as well, since they would be grounded. What establishes the property
  is the fixture correction that section documents, not this score. Prose precision, not a wrong number.
- **N3 — merge dialog.** Four `Changelog: none.` trailers will concatenate with `086b336`'s real
  multi-line `Changelog:` block at squash. The presence-only gate passes either way; trim in the
  merge dialog so the release notes carry one entry.
- **N4 — PR body** says "The spec reviewer's **entire** deficit is one fixture", stronger than the
  committed file's "virtually all". PR-body prose only; ships nothing.
- **N5 — scope-completeness `[unsatisfied]` on AC-3** (confidence 92), for the third round: issue
  #704's *body* still lists AC-3 unqualified, and the deferral lives only in ledger row D-1 and in
  #707. The pre-flight ledger is binding at step 4 and overrides the issue's ACs, so this is not a
  blocker — but the reviewer's recommendation is worth taking at close-out: say the re-cut on #704
  itself, so the scope record survives a later PR superseding the plan doc.
- **N6 — `selftests (macos, bash 3.2)` is GREEN at `3073a9d`.** Round 2 recorded a red on that lane
  and discharged it as infra on five discriminators without a code fix. This head confirms it: same
  lane, same suite set, success. No follow-up owed.

## CI at the reviewed head `3073a9d`

| Check | Conclusion |
| --- | --- |
| `lint-and-selftests` | success |
| `selftests (macos, bash 3.2)` | success |
| `mutation-sweep-pr` | success |
| `release-pr-gates` | skipped |
| `pr-gates` | **failure — expected** |

`pr-gates` fails at exactly one step, `lean chain reconciliation (lean PRs carry their evidence
set)`. That step requires `verdict=approve`, which did not exist when the run fired; it is expected
state, not a finding. The four **policy** steps — frozen files, `Changelog:` trailer, guard budget,
pipeline chain — all pass. No correctness lane is red.

## Design fidelity

**not-applicable.** The spec carries no `## Design` section and no `RS-n` render-state rows; the
repo config declares no `design.provider`; no changed path matches the resolved
`stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`). Nothing renders, so there is no
under-declared RS table to catch and no disarm to justify. `a11y-reviewer` and the design-fidelity
dimension were not routed for the same reason — not-selected, not dark.

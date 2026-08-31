# lean review verdict — #667

verdict=approve
run_id: review-667-2
session_id: 1484d9ff-57ff-414c-b742-c59340a7b7c0
rounds: 2
pr: #733
reviewed_head: d6fd610e96bddf00dd60310918356462b47146b3
reviewed_patch_id: 1975e2131a300a8538075d84eb184a36cdcf28c3
inherited_patch_id: bfba7da3a59ac0fa6d103460fbbcc617372df5d4
inherited_from_verdict: 2117a39a7481f8452e7c446592cfd3888c9558fe
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 2 — #667 / PR #733

Range read: `2117a39..HEAD` (inheriting round — the fix commit `d6fd610` only, 2 files,
+8/-2). Coverage of patch `bfba7da3a59a` is inherited from round 1's record in this file.
Read wider than the range where the delta was misleading: the whole of
`plugins/review-toolkit/skills/review-lead/SKILL.md`'s void/dark surface (every `void` hit,
`git blame`d for provenance), the branch's four commit messages, and `scripts/derive-release.sh`'s
trailer extraction.

Panel: 4 selected, 4 returned, **0 dark** (security, performance, maintainability,
scope-completeness). Zero findings from all four. `scope-completeness-reviewer` noticed the
dispatch base was this branch's own round-1 verdict commit, re-derived
`merge-base(origin/main, HEAD)` = `1d714d4` itself, and classified the **whole branch** against
#667 — PASS. Not selected: `complexity` and `test-coverage` (depth routing — Small); `a11y` +
design-fidelity (no changed path matched `stageParams.webComponentGlobs`, unset → default
`apps/web/**/*.{tsx,jsx}`); `db`, `pipeline`, `unit-test-mutation` (no trigger surface).

**Verdict: approve — 0 blockers, 1 warning. 14 of 14 ACs satisfied.**

## Round-1 findings — disposition

**B1 (blocker) — FIXED.** `SKILL.md:519` no longer restates the Step 4b-void trigger. The
parenthetical `(every selected reviewer dark)` is gone; the line now reads *"Step 4b-void owns the
trigger; do not restate it here"* and states only the two consequences. Both are verified against
the owning section rather than taken on the commit message's word: *"an all-dark **selected set**
is not a void on its own when the lead pass completed"* matches `:381` (*"an all-dark selected set
on top of a completed lead pass is **not** a void"*), and *"a dark `scope-completeness-reviewer` is
a hard **No**, never a void"* matches `:388` (*"a dark return all make 'Ready to merge?' **No** …
never converted into a void"*). The failure scenario B1 named — only `scope-completeness-reviewer`
selected, and dark — now yields one answer from both sites: No.

This is the right shape of fix. Updating the parenthetical to the *new* trigger would have
re-armed the same defect for the next rewrite; deferring to the owning section and stating only
consequences cannot go stale when the trigger is re-worded.

**Scoped correctly, and I checked the failure mode of that scoping.** "Step 4b-void owns the
trigger; do not restate it here" is scoped to the Rules list by "here". It is not the false
absolute it could have been: `:214` legitimately states a void trigger for the armed-spec /
toolkit-absent surface (`git blame` → `1d714d4`, pre-branch), and that sentence would have
contradicted a "this is the only place" phrasing.

**W1 — FIXED.** `:398` now reads *"**Three** not-selected cases"* above its three bullets,
agreeing with `:404`'s "All three".

**W2 — accepted explicitly**, in `docs/review-panel-yield.md:218` rather than by a code change.
The paragraph states the premise's boundary in both directions (holds on the lean lane by
construction, does not hold under `pr-revision`) and gives the acceptance grounds. Accurate:
`pr-revision/SKILL.md:295` does make its review advisory and non-blocking, and both corpora do
show zero blockers for the four. The doc is +6/−0, so the measured columns are provably unrevised.

**W3 — left, correctly.** `review-lean/SKILL.md:91` and `lean-gate.sh` still carry the old void
shape, and both are excluded by the spec's own out-of-scope list ("Any lane-contract change …
hand-back semantics"). Neither misbehaves: `review-lean` 5c keys off review-lead *actually
emitting* the void report, not off deciding independently. Carried forward as a follow-up, not a
finding against this PR.

## Warnings

**W1 (round 2) — the void rationale in the Rules list is now over-general across both void
cases.** `plugins/review-toolkit/skills/review-lead/SKILL.md:519`

Deleting the trigger parenthetical widened the sentence to cover both cases Step 4b-void
enumerates, but its justification clause was left as-is: *"answers it not at all — **there was no
review to draw a verdict from**, and 'No' would assert findings that do not exist"*. That is true
of case 1 (`:385`, nothing reviewed the range at all) and false of case 2 (`:386`, the
design-fidelity dimension unrunnable on an armed spec — which by its own words *"voids the round
however well the rest of it went"*). On an armed-spec void with a healthy panel, a review did
happen.

Not a blocker, and the distinction from B1 is the point: `:519` no longer states a **trigger**, so
there is no second normative statement to give an opposite output. The instruction — "answers it
not at all" — is uniform and correct for both cases, and is stated unconditionally twice more, at
`:214` and `:392`. Only the explanatory clause is over-broad.

Provenance matters for where this belongs: the clause is pre-branch text (`git blame` → `33cc62e`),
and the same over-generality already sits inside the owning section at `:394` (*"There is no
verdict to give, because there was no review"*), which this branch did not touch. What the branch
did was add case 2 to a section whose rationale prose assumed case 1. So the honest fix is one
sentence in the owning section acknowledging that an armed-spec void can void a round that was
reviewed — not another edit to the Rules list. No AC requires it; recording it so it is a choice
rather than an oversight.

## AC scoring

Inherited ACs are re-scored, not carried: each is re-checked at this head, cheaply where round 1
already established the detail.

| AC | Score | Evidence |
| -- | ----- | -------- |
| AC-1 — the four no longer selected at any size | satisfied | Untouched by the delta; re-verified at this head. |
| AC-2 — the Depth table's surviving role stated | satisfied | Untouched by the delta; inherited from round 1's per-line verification. |
| AC-3 — lead-pass checklist reference file | satisfied | Untouched by the delta; `lead-pass-checklist.md` present, referenced from `SKILL.md`. |
| AC-4 — security spawns conditionally | satisfied | Untouched by the delta. Exercised this round: routing evaluated the conditional and it fired on judgment, so the reviewer was selected. |
| AC-5 — the lead pass loads the consumer extension surface | satisfied | Untouched by the delta. |
| AC-6 — catalog + extension-points reconciled, reader tokens unchanged | satisfied | Untouched by the delta; `section-catalog.txt` and `docs/extension-points.md` are absent from `git diff --stat 2117a39..HEAD`. |
| AC-7 — registry intact | satisfied | Re-verified at this head: all five `review-toolkit:<name>-reviewer` names present in `SKILL.md`, and all five keys present in `code-review.mjs`'s `REVIEWER_MODEL`. |
| AC-8 — the three sub-registries stay consistent | satisfied | Re-verified at this head at the lint's own anchors: the four Verdicts rows are present at `:467`–`:471` with first-column labels `Performance` / `Complexity` / `Maintainability` / `Test Coverage` unchanged, rendering `Lead pass — ✅/❌`; `Security` at `:466` carries both arms. `check-reviewer-references.sh` rc 0. The delta's two edited lines are in `## Rules` and Step 4c — neither is a sub-registry region. |
| AC-9 — empty-selection short-circuit | satisfied | Untouched by the delta. |
| AC-10 — Step 4b-void re-worded for a non-empty lead pass | **satisfied** (was unsatisfied) | The clause that made it unsatisfied is gone. Every requirement of the AC now holds without contradiction: void applies to the selected subagents only (`:381`), an all-dark selected set over a completed lead pass is a partial-coverage round (`:381`), and a dark `scope-completeness-reviewer` yields "Ready to merge? **No**" (`:388`) with nothing in the file now saying otherwise — grepped every `void` hit and classified each as stating-the-trigger vs merely-referencing it. `:495` and `:519` reference; `:214` states a trigger for its own distinct surface; `:377`–`:392` own it. |
| AC-11 — `code-review.mjs` untouched | satisfied | `git diff --stat main...HEAD -- plugins/dev-pipeline/workflows/code-review.mjs` is empty. |
| AC-12 — `review-panel-yield.md` brought in step | satisfied | The round-1 note stands. The delta adds 6 lines and deletes 0, under Decisions, above the reversibility paragraph — so the measured columns are provably untouched by this round too. The claim it adds ("blocker yield is zero on both corpora") is accurate against the table's P-4…P-7 rows and the preceding paragraph's 248-version attribution. |
| AC-13 — `Changelog:` trailer | satisfied | `707a1ca` carries the consumer-visible trailer. Checked the interaction the extra commits create rather than assuming it: the branch's three other commits carry `Changelog: none` / `none.`, each followed immediately by an **unindented** `Co-Authored-By:` line, which closes `extract_trailers`' `inblk` (continuation requires `^[ \t]+[^ \t]`); `render_bullet` then normalizes case and a trailing period before its `none` test. So the squash renders exactly one changelog bullet, not three. `changelog trailer guard` green in `pr-gates` step 4. |
| AC-14 — validation surface green | satisfied | CI at this exact head, run `33390446845` on `d6fd610e`: `lint-and-selftests` **pass** (4m49s, the full sweep), `mutation-sweep-pr` **pass**. Cited, not re-run — command and head both match. `selftests (macos, bash 3.2)` was still **in flight** when this record was written; the delta contains zero shell (two Markdown files), so that lane's differentiator has no surface here, and the merge boundary blocks on it regardless. Run in the reviewed checkout: `check-reviewer-references.sh` rc 0, `check-review-context.sh` rc 0, `check-review-context-sections.sh` rc 0, `tools/prose-blockers.sh check` rc 0 (25 constructs / 47 rows / zero undispositioned). Carried from round 1 and still true: the two `review-context` lints are **vacuously** green here — this repo ships no `review-context/` surface, so they print "clean" rather than exercising the reader path the change adds. |

## Design fidelity

`not-applicable`. The spec's `## Design` reads `Design: none — this slice edits skill prose, a
reference file, a section catalog and a repo doc`. The disarm is justified and re-checked at this
head: `jq '.design'` on `.claude/second-shift.config.json` returns absent, so this repo configures
no design provider, and no changed path is a web component. There are no `| RS-n |` rows to score.

## Merge-boundary state (recorded, not a blocker)

`pr-gates` is red on **one** step, read from the job's step list rather than from `gh pr checks`:
step 6, "lean chain reconciliation (lean PRs carry their evidence set)". Steps 3, 4 and 5 — frozen
files, changelog trailer, pipeline chain — all succeeded. This is the expected pre-verdict state:
the record this round writes is the missing evidence.

## Strengths

- The fix is the *general* one, not the local one. Re-pointing the parenthetical at the new
  trigger would have passed a re-read and re-armed the identical defect at the next rewrite;
  deleting the restatement and stating consequences instead removes the class, not the instance.
- It anticipated the failure mode of its own remedy. A "Step 4b-void is the only place that states
  this" phrasing would have been the same false-absolute class as the blocker itself, because
  `:214` legitimately states a trigger for the armed-spec surface. The shipped wording is scoped
  to the Rules list.
- W2 was answered where it is checkable. The premise "the reviewing session already re-derives
  these dimensions" is what the whole collapse rests on, and it was evaluated on a lane where it
  does not hold and recorded there — in the measurement register, next to the rows that decided
  it, rather than as a code change nobody asked for.
- The fix commit message states the failure scenario and names the AC it unblocked, so the reason
  for the change survives the squash independently of this record.

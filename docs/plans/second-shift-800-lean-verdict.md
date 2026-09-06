# lean review verdict — #800

verdict=approve
run_id: review-800-1
session_id: 5c6dff4b-54f1-407c-a552-2802e520a6b8
rounds: 1
pr: #807
reviewed_head: 016370dde5ce8476d34de7fd26153d91f34d1756
reviewed_patch_id: c40742158388c44a7fd78f2e79af29900353b89c
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Summary

Round 1, full-branch range `42bf699a..016370dd` (no prior record to inherit from). Prose-and-register
change: one line deleted from `review-lean/SKILL.md`, a new `docs/skill-ablation.md` §2 subsection,
one regenerated `prose-blocker-triage.tsv` cell, two `capability-parity.tsv` NOTE cells.

All seven ACs are satisfied. Every factual claim the ACs rest on was reproduced rather than taken
from the spec: the pin ranges against the study's own tables, R-3's byte-identity against
`8d5d0897`, the `review-lead/SKILL.md:533` citation against the head, the census value for
pb-85e129b1, and the NOTE-cell reconciliations against the current `review-lean` text.

Two warnings, both about how the change is DESCRIBED rather than what it does, and neither making
an AC unsatisfied. One suggestion.

Panel: `review-toolkit:scope-completeness-reviewer` returned `approve` with no findings (one
suppressed at confidence 70). No other subagent met a trigger on this diff — no security surface,
no DB/queue/web-component path — so the performance, maintainability, complexity, test-coverage and
security dimensions were reviewed by the lead pass in-session. a11y and design-fidelity were not
routed: no changed path matched `stageParams.webComponentGlobs` (default
`apps/web/**/*.{tsx,jsx}`), and the spec declares no `## Design` section, so the run is unarmed and
fidelity scores `not-applicable`.

## Strengths

- **The re-anchoring is honest about what the study can and cannot support.** U-5 and R-3 are kept
  with the reason stated as a bound on the measurement (`review-lead` absent from every arm), not as
  reviewer caution. R-3's keep rests on a real, verified referent: `review-lead/SKILL.md:533` does
  read "The caller's inheritance contract governs", and no LOCKSTEP marker pairs the two sites, so
  the strand risk the ledger names is real.
- **The deletion's redundancy claim holds on inspection.** R-4's surviving clause is carried by
  step 5's gated scorecard: `undeterminable` and `unsatisfied` both block `approve`, so a reviewer
  structurally cannot approve on a promise it could not measure. Zero live references to the deleted
  text remain outside the ablation corpus and the historical verdict records.
- **The negative half of AC-1 is verifiable, not asserted.** The file goes 191 to 190 lines with a
  single deletion and zero insertions.

## Warnings (should fix)

- **[Maintainability] `docs/prose-blocker-triage.tsv` — the cell change is misdescribed as a
  one-line shift (confidence: 95).** The commit body, the PR body and the spec's D-8 all say the
  `pb-85e129b1` sites cell went "169 to 168, the one row after the deleted line". The committed
  pre-value was `:140` (`git show 42bf699a:docs/prose-blocker-triage.tsv`), and #719's verdict record
  confirms 140 was correct when it was written. So the edit repaired 28 lines of undetected drift,
  not a one-line shift. The EXECUTED value is right — `bash tools/prose-blockers.sh census` at head
  prints `:168` — which is why this is not an AC failure. But the description hides the finding, and
  the finding strengthens the ticket's own OR-2: the record had rotted 28 lines with nothing
  catching it, which is a better argument for wiring the check into CI than the one OR-2 makes.
  Two sibling rows in the same file are stale the same way and correctly left alone
  (`pb-ca49bd15` records `:70`, census says `:76`; `pb-ba11248e` records `:84`, census says `:96`) —
  pre-existing on main, outside AC-5.
- **[Maintainability] The `Changelog: none.` trailer will render an entry, and a truncated one
  (confidence: 90).** D-10 decided "no consumer-visible change", but `derive-release.sh`'s no-op test
  is whole-block and strips only one trailing period, so `none. The R-4 bullet's operative clause...`
  is not `none` and renders. Its continuation lines are unindented, so `extract_trailers` ends the
  block at the first one. Simulating both awk stages over the commit body emits exactly:
  `  none. The R-4 bullet's operative clause was already carried` — a sentence cut mid-clause in the
  release notes. `CLAUDE.md`'s canonical example indents continuation lines by two spaces; this
  commit does not. Held to a warning rather than a blocker because it is the house's existing
  behavior, not a regression: `CHANGELOG.md` already carries 53 rendered `none`-prefixed bodies,
  including a truncated one at `CHANGELOG.md:45`. Fixing it costs a commit-message rewrite, so it is
  better folded into whatever touches this branch next than bought with a round.

## Suggestions (consider)

- **[Complexity] R-3's keep rationale is stated twice in `docs/skill-ablation.md`, 20 lines apart.**
  The *Execution (#800)* subsection and the extended *What bounds this arm* bullet both cite
  `review-lead/SKILL.md:533`, both quote "the caller's inheritance contract", and both state the
  same absence bound. D-13 anticipated the objection and distinguishes them by role — D-4 records the
  execution, D-13 corrects the report's statement of its own bounds — so this is a decided
  duplication, not an oversight. Noting it only because the repo is running a prose-debloat program
  and this is the shape that program looks for.
- **[Maintainability] `docs/skill-ablation.md` §5's successor bullet is rewritten beyond AC-4's
  letter.** AC-4 names only the C2 bullet; the `#800` successor bullet was also flipped to "#800 is
  done". Coherent bookkeeping — the doc would contradict itself otherwise, and #801 set the
  precedent for the same PR asserting its own completion — and no AC forbids it. Recorded so the
  extra edit is visible rather than inferred.

## Recorded, not blocking

- **`pr-gates` is red on one step: "lean chain reconciliation (lean PRs carry their evidence set)".**
  That is the expected pre-approve state — the evidence set is incomplete precisely because this
  record does not exist yet — and it resolves when this record is pushed. Every correctness lane is
  green at the reviewed head `016370dd`: `lint-and-selftests` SUCCESS, `selftests (macos, bash 3.2)`
  SUCCESS, `mutation-sweep-pr` SUCCESS.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Pre-deletion line 168 of `review-lean/SKILL.md` was exactly `- **Approve on the diff, not on the spec's promises.**` (read at `42bf699a`). The diff against that file is one deletion, zero insertions; the file goes 191 to 190 lines, so the "no other line changes" half is verified from the diff itself rather than asserted. `8d5d0897`'s pin at 115-116 carried two lines; the second clause was deleted at `d8ea88aa` (#753 / PR #776), so the one-line residue is what this cut removes. Redundancy of the removed clause confirmed at step 5: `undeterminable` and `unsatisfied` each block `approve`. |
| AC-2 | satisfied | Neither unit is cut — SKILL.md lost only line 168, and lines 48-63 and 163-167 are untouched. Placement is exact: `### The cut list (AC-6)` at `:533`, `### Execution (#800)` at `:555`, `### What bounds this arm` at `:583`. All three pin ranges match the study's own tables (`skill-ablation.md:510-512`: U-5 48-55, R-3 110-114, R-4 115-116). Head ranges reproduced: step 5 spans 48-63 with 5b opening at 64; the inheritance bullet is 163-167. Verbatim-vs-superseded is recorded for each, and R-3's "byte-identical" claim is verified by diffing `8d5d0897`'s lines 110-114 against head 163-167 — identical, zero bytes differ. Keep rationales for U-5 and R-3 both present, matching D-1 and D-2. |
| AC-3 | satisfied | The *What bounds this arm* `review-lead`-absence bullet now names R-3 alongside U-5 and carries the citation. The citation is accurate at the reviewed head: `plugins/review-toolkit/skills/review-lead/SKILL.md:533` reads "**The caller's inheritance contract governs**". The added clause states the mechanism (a unit that matters only by being read by `review-lead` is invisible to a study that never loads it) rather than only the name. |
| AC-4 | satisfied | §5's C2 bullet gains its own line: "**Settled by #800 (§2, 2026-09-07):** R-4 is deleted; U-5 and R-3 are kept, each with a reason on file — see the *Execution (#800)* subsection above." Records the execution in the three terms AC-4 requires and points at the AC-2 subsection. The separate successor-list edit is reported as a suggestion above, not scored here. |
| AC-5 | satisfied | `bash tools/prose-blockers.sh census` at the reviewed head prints `plugins/dev-pipeline/skills/review-lean/SKILL.md:168` for `pb-85e129b1`, which is exactly the committed cell — so the cell is the census's own output, which is what the AC requires. The second conjunct holds too: the diff touches one row. The mechanism claim is verified independently — 168 is the largest censused anchor in that file (census anchors are 38, 48, 76, 96, 102, 118, 168), so the deletion shifts nothing else. The AC's requirement is met on both conjuncts; the misdescribed pre-value is a warning above, not a divergence from what AC-5 asks for. |
| AC-6 | satisfied | Both NOTE cells reconciled and both dispositions untouched. `plan-vs-diff scope-drift gate` (still `dropped`): the old cell ended "treats a spec amended after the fact to match the diff as itself a blocker" — the clause #753 / PR #776 deleted — and the new cell replaces it with the `## AC scorecard` description. `scope-completeness gate` (still `already-covered`): the old cell described three-way scoring, the new one names all four scores and the refusal beside `unsatisfied` or `undeterminable`, matching `review-lean/SKILL.md:54-56`. The out-of-scope claim is verified at the guard: `capability-parity-check.sh:47` states the NOTE cell is never parsed for claims, and the only NOTE arm in the script is the non-empty test at `:240`. |
| AC-7 | satisfied | Verified by citing CI at the reviewed head, per the citing-a-CI-run discriminator — the command and head both match this review. `lint-and-selftests` SUCCESS and `selftests (macos, bash 3.2)` SUCCESS, both on run 34063368484 at head `016370dd`; `mutation-sweep-pr` SUCCESS on the same run. `bash tools/prose-blockers.sh check` is wired into no workflow (the ticket's own OR-2), so it was executed here: rc=0, "zero undispositioned constructs", census 29 constructs over 52 files against 52 record rows. A local cold sweep at the same head corroborates independently: 77 scored, 77 run, 0 failed. No new guard and no new selftest case were added, which is what D-7 and the `writing-tests` no-prose-presence-guards rule require. |

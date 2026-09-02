# lean review verdict — #780

verdict=needs-work
run_id: review-780-1
session_id: f394c278-549c-46e9-8b1c-8275a4227e2f
rounds: 1
pr: #784
reviewed_head: c3ea669ee43189c258932d175e5d0bf1ca4c5bf6
reviewed_patch_id: 01bc205fd23b4da03d20c348b89491ce4b0e069e
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:security-reviewer,review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review Summary

Round 1, full branch range `0978ee14..c3ea669e` (no prior verdict record to inherit from). This is a
clean, well-argued deletion: the reaper, its stamp library, its selftest, its sweep-entry call site and
every dependent TSV row come out together, and the two producing suites move to the explicit-template
`mktemp` form so the shared-directory condition is deleted rather than merely unreaped. Five of the
seven acceptance criteria are satisfied on measurement. **AC-7 is not.** The docs rewrite that replaces
the retired `-t`-versus-explicit-template derivation asserts a universal about the tree that is false by
33 files, and it does so in `CLAUDE.md` — the file every session loads — where it will be read as
licence to assume a private `TMPDIR` isolates a lane. A second, independent defect: the code commit's
`Changelog:` trailer is the `none`-plus-prose form that `derive-release.sh` renders as a literal bullet.

Panel: `review-toolkit:security-reviewer` (approve, no findings), `review-toolkit:scope-completeness-reviewer`
(approve-with-nits, 1 nit @85). No reviewer went dark. `security-reviewer` was selected on the
destructive-IO surface (`rm -rf` walker deleted, scratch allocation relocated) rather than deferred to
the lead pass. a11y + design-fidelity not routed: no changed path matched
`stageParams.webComponentGlobs` (config declares none; default `apps/web/**/*.{tsx,jsx}`), and the spec
declares no `## Design` section.

## Strengths

- **The deletion is complete and provably so.** `git grep -lE 'reap-lean-fixtures|fixture[-_]stamp' -- . ':!docs/plans/'`
  returns nothing; `tools/mutation-pair-map.tsv`, `tools/selftest-cache-inputs.tsv` (row *and* its
  DEPTH-1 prose), and the `tools/check-sweep-bound-selftest.sh` comment cross-reference all move together.
  No dangling reference survives anywhere in the tree.
- **OR-1 was actually measured, not predicted.** I re-derived it independently: all four
  `tools/mutation-catalog.tsv` rows anchored on `tools/run-selftests.sh` still resolve against the
  post-deletion file (each row's `sed -E` pattern applied to the file produces a diff). The
  reversible-default was correctly resolved to "no catalog edit", and the PR body says so.
- **The `pwd -P` added to `lean-gate-selftest.sh` is the right call and its stated reason is true.**
  macOS `$TMPDIR` carries a trailing slash, so the explicit template yields `…/T//leangate.XXXXXX`;
  measured directly. Without the normalization the `(lt5)`/`(lt5b)` literal path matches against
  `git worktree list` output would break. This is the minimum needed to keep the suite green under the
  new form, not scope creep — and the `#663` comment rewrite correctly re-states that the
  Linux/macOS asymmetry it described is now gone.
- **Coverage does not regress.** The two deleted selftest cases and the whole deleted suite covered only
  the deleted subject. `orchestrate-lean-selftest.sh` (all green) and `lean-gate-selftest.sh` (all green,
  359 cases) both pass locally under a private `TMPDIR`, and both CI selftest lanes are green at this head.

## Critical (must fix before merge)

- **[Maintainability] `CLAUDE.md:75-79` and `docs/testing.md:181-183` (confidence: 97) — the rewrite
  replaces a true, measured statement with a false universal, in the file every session loads.**
  `docs/testing.md:181` now reads "**Every scratch allocation in this repo uses the explicit-template
  form**", and `CLAUDE.md:75-79` "every scratch allocation in this repo … uses the explicit-template form
  … so **a private `TMPDIR` relocates all of it**, scratch and fixtures alike". Measured at this head:
  **33 shell files still call `mktemp -d -t` / `mktemp -t`**, and there are **39 bare `mktemp -d`** call
  sites. Among the `-t` callers are the two largest scratch trees in the repo —
  `tools/mutation-sweep.sh:1299` (`mutation-sweep-work.XXXXXX`, plus `:1390`'s per-sandbox dirs) and
  `tools/install-topology-selftest.sh:137` (`install-topology.XXXXXX`) — along with
  `lean-evidence-selftest.sh`, `lean-reconcile-selftest.sh`, `scenario-liveness-selftest.sh`,
  `preflight-selftest.sh`, `derive-release.sh` and ~26 others.
  The failure this causes is the exact one the section exists to prevent: a contributor follows
  `CLAUDE.md`'s killed-sweep advice, exports a private `TMPDIR`, and concludes their lane is isolated —
  while every one of those 33 files' scratch still lands in the one `_CS_DARWIN_USER_TEMP_DIR` directory
  shared with every other worktree and lane on the machine. `mutation-sweep-work.*` colliding with a
  suite's fixture dir is not hypothetical: it is #663, which this very diff re-narrates in
  `lean-gate-selftest.sh:161`.
  The deleted text was *correct* about all of this ("**12** that call it, at 16 sites", with the two
  mention-only files named), and it carried the caveat "counting a `-l` without reading its matches puts
  them on the wrong one". The rewrite deletes that caveat and then commits the error it warned about:
  `grep -rl 'TMPDIR:-/tmp}/' --include='*.sh' .` returns **19** files at this head, of which only **14**
  have call sites — so "finds every caller" is wrong in both directions at once.
  AC-7's ask was that the docs *follow* the deletion. Retiring the `-t` derivation is correct and in
  scope; replacing it with a universal the tree contradicts is not. The fix is a narrowing, not a
  restoration — say that the two fixture families *joined* the explicit-template set, and that the rest
  of the tree has not.

- **[Maintainability] commit `c3ea669e` trailer (confidence: 95) — `Changelog: none — <prose>` renders a
  literal bullet into `CHANGELOG.md`.** The commit writes
  `Changelog: none — harness-internal test infrastructure, no consumer-visible behavior.`
  `scripts/derive-release.sh:240-242`'s no-op test is **whole-block**: it strips trailing whitespace and a
  single trailing period and compares the result to exactly `none`. I ran the real `extract_trailers` and
  `render_bullet` awk against this commit's body; the output is:
  ```
    none — harness-internal test infrastructure, no consumer-visible behavior.
  ```
  So the next release PR ships that line under the PR's bullet in `CHANGELOG.md` — precisely the failure
  mode `derive-release.sh:35-36` records ("an exact 'none' comparison shipped literal '  none.' bullets
  into CHANGELOG.md for 12 commits before anyone noticed"), in the form that survived the fix. The spec
  commit `a5ebc38f` gets it right with a bare `Changelog: none.`. CI is green on this — 
  `check-changelog-trailer.sh` only asserts a trailer is *present* — so nothing downstream catches it.
  Fix: make the trailer `Changelog: none.` and move the justification into the commit body prose above it.
  **Standing alone this would not have forced `needs-work`** — it is a trailer-only amend that changes no
  line of the reviewed diff, so the round's own record would survive it. It is reported as a blocker only
  because the round is already `needs-work` on the finding above, which makes fixing it free.

## Warnings (should fix)

- **[Maintainability] `docs/testing.md:206-208` (confidence: 85) — the hand-scrub command is presented as
  the reaper's replacement but covers three name classes out of the tree's many.** The `find` globs
  `leangate.*`, `orchestrate-lean-selftest.*` and `run-selftests.*`. Under the default (launchd) `TMPDIR`
  the same directory also accumulates `mutation-sweep-work.*`, `mutation-sweep-sandbox.*`,
  `install-topology.*`, `leanev.*`, `leanrec.*`, `scenario-liveness.*`, `preflight-selftest.*` and the
  rest of the 33 `-t` families — which is the *majority* of what a killed sweep actually orphans. The
  deleted prose acknowledged that residue explicitly; the replacement, framed as "Scrub by hand instead:",
  reads as complete. Widening the alternation, or one sentence saying the list is the big ones and not
  the whole set, closes it. Same root cause as the first blocker; fixing that one should fix this.

- **[Maintainability] PR body, "Net diff" line (confidence: 90) — the figure is the code commit's stat,
  labelled as the branch's.** The body says "Net diff: -693 lines (94 insertions, 787 deletions across
  this PR's commits)". `94/787` is exactly `git show --shortstat c3ea669e`; across *this PR's commits* it
  is `201/787`, i.e. **-586**. AC-6 asks only that the net diff be negative, and it is on either reading,
  so this does not move the score — but on the one ticket whose entire ratification bar under #717 *is*
  the net diff, the stated number should reproduce from the command a reader would run. Either say
  "excluding the spec commit" or quote -586.

## Suggestions (consider)

- **[Maintainability] `docs/testing.md:1820` (confidence: 85, via `scope-completeness-reviewer`;
  independently confirmed) — the Concurrent-lane recipe still says "the four criteria" after C-1 is
  dropped.** Step 1 routes the operator to `docs/plans/second-shift-564-preregistration.md`, where C-1 is
  still defined — and that record is deliberately out of bounds (D-8, and the ticket's Out-of-scope
  section), so the count can only be reconciled here. Line 1873-1875 does record the void, but a reader
  who acts on step 1 before reaching it is told to measure a criterion the tier no longer scores.
  "fixes the criteria and the arm definitions (C-1 was retired in #780)" would settle it.

## Plan Compliance

Implementation matches the spec's scope boundary exactly. Nothing in `docs/plans/` was edited (D-8/D-14),
no guard, selftest case or script was added (D-1/D-14), the deferral rule itself is unchanged with only
its header prose touched (D-2), the Concurrent-lane tier was not re-run (D-9), `run-selftests.sh`'s pass
cache is untouched (D-14), and D-11 (trap before `WORK`) and D-15 (`pwd -P`) are both preserved. OR-1 was
resolved by measurement to its reversible default and flagged in the PR body as required. No scope creep;
the one addition beyond the letter of AC-3 — `pwd -P` in `lean-gate-selftest.sh` — is load-bearing for the
change to work at all.

The single gap is inside AC-7: the docs follow the deletion in structure (reaper paragraph gone, scrub
command added, C-1 / sampler / stagger rule dropped, record-void noted, `CLAUDE.md` updated) but overshoot
it in content.

## Pre-existing gaps (not blocking this PR)

- `CLAUDE.md:115` and `docs/testing.md:685` both describe a "64-suite tree". The tree discovers 78 suites
  at `main` and 77 here, so these figures were already stale before this PR; the deletion moves them by one
  more. Worth a sweep of the committed suite-count figures at some point — not this ticket's job.

## Suppressed (below confidence threshold)

- `lean-gate-selftest.sh:~70` (security-reviewer, 40) — scratch moves from the per-user macOS temp dir to
  `${TMPDIR:-/tmp}`; `mktemp -d` still creates at 0700 atomically, so no predictable-path/symlink exposure.
- `tools/run-selftests.sh:223` (security-reviewer, 30) — removing the guarded reaper deletes a recursive
  `rm -rf` code path; this reduces destructive-IO surface rather than adding one.
- `scope-completeness-reviewer` noted its first sweep exited 1 on four override/attend-mode assertions
  caused by `LEAN_ATTEND_MODE` / `LEAN_RUN_MODEL` leaking from its shell; the scrubbed re-run was
  77 run / 0 failed / rc=0. Environmental, not a finding.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | The AC-1 grep in the spec (git grep -lE over the two name patterns, excluding docs/plans/) returns nothing, rc=1, at c3ea669e. All three files are deleted in the diff. |
| AC-2 | satisfied | The `[[ -x "$ROOT/tools/reap-lean-fixtures.sh" ]]` block and its 12-line #528 header comment are gone from tools/run-selftests.sh (-18 lines); the fake-reaper case and its absent-tool control are gone from tools/run-selftests-selftest.sh (-40 lines). |
| AC-3 | satisfied | Both suites allocate with the explicit-template form. Both keep cleanup() and its trap registered BEFORE WORK is assigned (D-11). orchestrate-lean-selftest.sh:60 keeps `pwd -P` (D-15); lean-gate-selftest.sh gains it, which is necessary rather than creep — macOS $TMPDIR carries a trailing slash so the raw template yields a doubled separator, measured directly, and the (lt5)/(lt5b) literal path matches against `git worktree list` output would break without normalization. Both suites all-green locally under a private TMPDIR. |
| AC-4 | satisfied | The tools/fixture-stamp.sh rows are gone from tools/selftest-cache-inputs.tsv (row plus its DEPTH-1 prose) and tools/mutation-pair-map.tsv; tools/check-sweep-bound-selftest.sh:383 is reworded. Full sweep exits 0, cited from CI at this exact head rather than re-run: lint-and-selftests pass 5m00s and selftests (macos, bash 3.2) pass 4m20s, run 33640549445 at c3ea669e. Independently corroborated by scope-completeness-reviewer's own scrubbed sweep, 77 run / 0 failed / rc=0. |
| AC-5 | satisfied | tools/selftest-suite-timings.tsv lines 20-28 record the blind spot as header prose, with no new column and no validator. Its factual claim verified: tools/selftest-cache-inputs.tsv has exactly 3 declaring suites (lean-gate-selftest.sh, check-lean-chain-selftest.sh, cost-block-selftest.sh); the first two carry rows in this table at 212s and 67s, both over its 9s threshold, so both are deferred, leaving cost-block-selftest.sh as the only cacheable suite a milestone-3 lane runs. |
| AC-6 | satisfied | Net diff is negative. `git diff main...HEAD --shortstat` gives 201 insertions and 787 deletions, i.e. -586 across the branch, and -693 excluding the spec commit. Negative on either reading. The PR body quotes -693 while labelling it "across this PR's commits", a mislabel reported as a warning; it does not move this score. |
| AC-7 | unsatisfied | Structurally complete: the reaper paragraph is gone, the scrub command added, C-1 and the sampler's fixture half and the stagger rule dropped with C-2 to C-4 retained, the record-void noted at docs/testing.md:1873-1875, and CLAUDE.md's parallel paragraph rewritten. But the replacement prose asserts in both homes that EVERY scratch allocation in the repo uses the explicit-template form, and that a private TMPDIR therefore relocates all of it. Measured false at this head: 33 shell files still call `mktemp -d -t` or `mktemp -t`, and there are 39 bare `mktemp -d` call sites; tools/mutation-sweep.sh:1299 and tools/install-topology-selftest.sh:137 are among them. The claim is load-bearing, since it is the entire answer the section exists to give; it sits in the file every session loads; and it is falsified by a one-line grep. This is a measured divergence, not an unmeasured one, and what it was measured to be is false. |

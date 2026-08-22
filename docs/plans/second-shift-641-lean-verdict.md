# lean review verdict — #641

verdict=needs-work
run_id: review-641-2
session_id: 4d8d5b1e-3ea9-44c9-97e5-725a5fc75d9a
rounds: 2
pr: #645
reviewed_head: 2bae5cd6b91b3123e143b79b8cfd93a7a75d19dd
reviewed_patch_id: 95f97f1e44fd2832e39359cde7993b86325edcb6
inherited_patch_id: 255055fadd7f2174067134de7fc1909ac69fb480
inherited_from_verdict: 21c2cf89df542c775ed5a158ca53740a670c1616
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 2 — delta `21c2cf8..2bae5cd` (6 files, +44/-10), inheriting round 1's coverage of
`b8cc982..9ea2bf7`. Verdict: **needs-work**, on two blockers.

Round 1's blocker is **closed**, and closed in the right shape. The two cheap warnings and the
suggestion are closed too. What blocks this round is new: the fix commit's own 28 lines of
guard/test shell push the tree over the ceiling this PR introduces, so `pr-gates` reds on the
PR's own gate — and the test added to close round 1's W-2 cannot fail in the direction W-2 named.

## Per-AC scoring (against `docs/plans/second-shift-641-lean.md`)

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | `tools/guard-budget.tsv` exists; `check-guard-budget-selftest.sh` drives the shipped script over eight fixture git repos — under / over-naming-the-overage / raise-without-reason / raise-with-reason / lower / first-ever-commit / all-arms / missing-TSV. Ran here: **10 passed, 0 failed**. |
| AC-2 | satisfied | Every row of `tools/gate-ablation-classes.tsv` carries a non-empty 6th column; `gate-ablation.awk:57` reds naming the row on blank **and** on absent. `gate-ablation-selftest.sh` ALL CASES PASSED here, including (t)/(t2)/(t3). |
| AC-3 | satisfied | The step is in `pr-gates` (`ci.yml:280-286`) and ran on this PR. Case 2 reds a synthetic over-budget tree. (It also reds the *real* tree — see B-1. That is AC-3 working, not failing.) |
| AC-4 | satisfied | One pointer paragraph in the `**Pn posture:**` form, no restatement of P4/P5's text. Round 1's W-1 overclaim is gone. |
| AC-5 | satisfied | Three `Changelog:` trailers on the branch; the round-2 commit carries one with `Migration: none.` |

Fidelity: **not-applicable** — the spec declares no `## Design` section (only `## Design
decisions`, which is prose), and the repo configures no design provider.

## Blockers

**B-1 — `pr-gates` reds on this PR's own guard-budget step; the round-2 commit added 28 lines of
guard mass without pricing it.** `tools/guard-budget.tsv:20`

CI run **32573925015**, job `pr-gates`, step 5 — `completed/failure`:

```
[guard-budget] ✗ guard/test shell is over budget: measured 50559 lines, ceiling 50531 (over by 28).
[guard-budget]   Delete guard mass, or raise tools/guard-budget.tsv's ceiling in the open with a reason.
```

Reproduced locally at the reviewed head (`bash scripts/check-guard-budget.sh main`, rc=1, same
numbers). The overage is exactly the 28 lines this round appended to
`scripts/check-guard-budget-selftest.sh` (Cases 7 and 8) — a `*-selftest.sh`, which `classify()`
counts. Round 1's head measured 50,531 against a ceiling of 50,531: **zero headroom by
construction** (D-a sets the ceiling to the measured value), so any guard-mass addition on this
branch reds, and this one did.

Two consequences beyond the red itself. `pr-gates` steps 6 and 7 — pipeline chain reconciliation
and **lean chain reconciliation** — are `completed/skipped`, so this PR's evidence set has never
been reconciled by CI at any commit. And the PR body's Verification section still asserts a clean
run; it describes round 1's tree.

Either remedy clears it, and both are the mechanism working as designed: raise the ceiling to
50,559 with a reason in the same diff (`50559<TAB>2026-08-22<TAB>PR #645's own round-2 test
coverage — Cases 7/8 closing round-1 W-2/W-4`), or delete 28 lines of guard mass elsewhere.

**B-2 — Case 7 cannot fail in the direction round-1 W-2 named; the commit message reports it
closed.** `scripts/check-guard-budget-selftest.sh:105-119`

W-2 said: *"The narrowing direction is the silent one: drop an arm and `measured` falls, the gate
stays green."* Case 7 builds one fixture file per `classify()` arm summing to 61, commits a
ceiling of 61, and asserts **`rc -eq 0`**. But `check-guard-budget.sh:94` treats measured **under**
ceiling as an advisory and exits **0** — so a smaller `measured` is indistinguishable from the
right one. The named invariant ("all six remaining classify() arms sum to 61") is not what the
case tests.

Probed in an isolated worktree at the reviewed head — each arm neutered one at a time, selftest
re-run, `bash -n` clean throughout:

| arm neutered | Case 7 |
| --- | --- |
| `-name '*-selftest.sh'` | **ok** (green) |
| `-name 'check-*.sh'` | **ok** (green) |
| `-name '*-lint.sh'` | **ok** (green) |
| `-path '*/skills/*/lean-gate.sh'` | **ok** (green) |
| `-name 'run-selftests.sh'` | **ok** (green) |
| `-name 'mutation-sweep.sh'` | **ok** (green) |
| `-name 'gate-ablation.sh'` | **ok** (green) |
| *(control)* broaden to `-name '*.sh'` | **FAIL** — `measured 1061, ceiling 61` |

Seven of seven survive. Only the control — the broadening direction, where `deploy.sh`'s 1000
lines start counting — is caught, so the negative product-`.sh` half of W-2 **is** genuinely
closed. The six-arms half is not.

The commit message states *"classify()'s six untested match arms plus the negative product-.sh
case are now covered by one fixture (W-2)"*, and the `Changelog:` trailer bills the round as
"test-coverage fixes". A case that converges on green while reading as coverage is the shape
`CLAUDE.md`'s testing section exists to refuse — and it is 28 lines of guard mass, on the PR whose
subject is that guards must earn their keep.

One line closes it — assert the number, not just the exit code:

```bash
case "$OUT" in *"at budget: measured 61"*) ok "7 ..." ;; *) bad "7 ... : $OUT" ;; esac
```

That kills all seven mutants above and keeps the control.

## Round-1 findings — disposition

| # | Status | Basis |
| --- | --- | --- |
| **B-1** | **closed** | #641's body now carries a `## Build-time amendments (PR #645 round 1)` section recording both departures, and **#646** is filed with real scope, a rationale for the deferral, and draft ACs. The shape is right: the operator's ratification line is preserved **verbatim** and the departures sit in a separately-titled section attributed to the build round — not a silent rewrite of the ratified text into agreement with the diff. Independent `scope-completeness-reviewer` re-classified against the full `b8cc982..HEAD` diff and returned **PASS**. |
| W-1 | closed | `pipeline-manifesto.md:68`, `ci.yml:280`, and `check-guard-budget.sh:95` all drop "only ever ratchets down" / "the ceiling only ever falls" for a raise-needs-a-reason phrasing that is true. |
| W-2 | **half-closed → B-2** | Negative case closed; six arms not. |
| W-3 | **open, and now load-bearing** | Round 1 accepted the zero-headroom ceiling as a defensible trade. It is the proximate cause of B-1, and it will red every future round of this PR that adds a test line. Not re-raised as its own blocker — B-1 is its consequence and carries the remedy. |
| W-4 | closed where it matters | Case 8 covers the missing-`tools/guard-budget.tsv` path. Probed the failure **reason**, not just the code: the fixture exits 2 at `check-guard-budget.sh:39` with `no ceiling recorded at tools/guard-budget.tsv`, not via the merge-base or usage arms. The other four `exit 2` paths remain untested, as round 1 allowed. |
| S-1 | closed | `gate-ablation.awk:50` now says "want 6 (5 base + earn-your-keep)". |
| S-2 | open | See below. |
| S-3, S-4 | open | Both discretionary in round 1; not re-raised. |

## Suggestions

- **S-1 (r2)** The PR body was not updated for round 2. It still cites *"the two new
  `check-guard-budget-selftest.sh` cases"* (there are now four), still reports the
  `--exclude`-only sweep as **61** where the recipe of record passes `--full` for **74**
  (round 1's S-2, unaddressed), and its Verification section claims a clean run that B-1 falsifies.
- **S-2 (r2)** Round 1's S-4 remains: the raise check never verifies the reason is *new*, so a
  stale reason left in the row clears a later raise — and `ceiling_row()` exits on the first data
  row, so a second appended row is silently ignored despite the header's "ONE data row". If B-1 is
  cleared by raising the ceiling, this row will be the first one carrying a reason, which is the
  natural moment to close it.

## Strengths

- **The blocker was closed by making the issue tell the truth, not by making the spec agree with
  the diff.** #646 is a real ticket — it names the `contents: write`-on-`main` objection, the
  PR-opening shape that avoids it, and four draft ACs — rather than a placeholder to satisfy a
  reviewer. The ratification line stays verbatim and the departure is labeled as the build's.
- **B-1 is the mechanism catching its own author on its first day.** The gate this PR ships is the
  gate that reds this PR, on the real merge tree, for exactly the right reason and with the
  remedy printed in its own diagnostic. That is a stronger demonstration of AC-3 than the fixture.
- **Case 8 tests the reason, not just the code.** The missing-ceiling path is the one that matters
  — deleting `tools/guard-budget.tsv` must red — and the fixture reaches it through a real git
  repo rather than a stubbed one.
- **The wording fixes went to all three copies.** W-1 named the manifesto; the fix also corrected
  the CI comment and the script's own advisory string, so the overclaim does not survive anywhere
  a reader would meet it.

## Suppressed / not carried

- `scope-completeness-reviewer` (conf 85) — Scope item 2's optional "dated incident" sub-clause is
  cited by issue number (#119) on one row and by no ISO date anywhere. The clause is conditional
  ("where one exists") with no incident registry to check against; not falsifiable, not carried.
- `scope-completeness-reviewer` (conf 95) — flagged that the dispatch base was branch-internal
  rather than `main`. Correct observation about the dispatch, not a defect in the PR: the narrowed
  range is `lean-gate.sh delta`'s inheritance contract, and the reviewer widened to the full diff
  on its own before classifying. No action.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 2 (nit) | 85–95 |
| Test Coverage | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Complexity | Pass | 0 | — |

Security, performance and the domain reviewers were not selected: the delta is comment/doc wording,
two error-message strings, and one selftest block, with no executable production-logic change.
a11y + design-fidelity not routed — no changed path matched `stageParams.webComponentGlobs`
(unset → default `apps/web/**/*.{tsx,jsx}`).

**Both blockers are orchestrator findings.** All four reviewers approved; `test-coverage-reviewer`
read `classify()` and returned no findings. B-1 came from running the shipped gate at the reviewed
head and reading the PR's own CI job; B-2 from a seven-arm mutation probe in an isolated worktree.
Neither is visible from the diff alone.

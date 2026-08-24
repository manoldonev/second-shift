# lean review verdict — #642

verdict=needs-work
run_id: review-642-2
session_id: f0cca947-f25a-4d14-bd41-7108b481fb19
rounds: 2
pr: #660
reviewed_head: 962c0bbac1e02cc0dae0a60ed0ea438cf97486e2
reviewed_patch_id: 60c38517268cb72d3a810fd884f0dc5650c347c7
inherited_patch_id: 7698981723b370c033362e8dec398e6ecccea011
inherited_from_verdict: a3eeceb9812491d57de428f208b1dab888fd8461
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Range read: `a3eeceb..HEAD` (the round-1 fix), inheriting patch `7698981723b3` from round 1.
Reviewed from the lane worktree with `claude/second-shift-642` checked out. Head re-verified
unchanged at `962c0bb` after review.

**Verdict: needs-work — 1 blocker.** Both round-1 blockers are genuinely closed, and I verified
each by execution rather than by reading the diff. The blocker is new, introduced by the fix
itself: AC-6's measured clauses flipped sign, and `pr-gates` reds on the production guard.

## Round-1 blockers: both closed, verified by mutant

**B1 (AC-3 half-applied on `cmd_close_out`) — closed.** Both sites now carry the absent verb,
spelled as `cmd_5` spells them (`lean-gate.sh:4860` `block_milestone`, `:4864`
`block_obligation exit-artifacts`). The interesting half is the guard, and the operator asked
that its central claim be falsified rather than accepted: `(ac1c)` says it resolves `$VAR`-only
reasons to their literal assignments, `"$LEAN_PR_ERROR"` being the named case a literals-only
guard would score green. It does. I extracted the case's awk verbatim and drove it against four
mutants, then re-ran the whole suite against two of them:

| mutant | `(ac1c)` | evidence |
| --- | --- | --- |
| close-out `$LEAN_PR_ERROR` → `fail_milestone` | **reds** | names `4864 m5/exit-artifacts:no-open-pr` via the *resolved* literals `could not list PRs for $LEAN_BRANCH` / `no open or merged PR found for branch $LEAN_BRANCH` |
| close-out progress-current → `fail_milestone` | **reds** | names `4860 m5/progress-current` |
| `cmd_5` `$LEAN_PR_ERROR` → `fail_milestone` | **reds** | names `4581`, same resolved literals |
| identity-stamp → `fail_milestone` | **reds** | names `4647 m5/identity-stamp` |

Full-suite runs confirm it in situ: mutant A reds `(co1)` at `0 absent / 1 attempt / 0 obligation`
— the exact pre-fix signature the build recorded — plus `(ac1b)` and `(ac1c)`; mutant D reds
`(k11)` at `0 / 1 / 1` plus `(ac1b)` and `(ac1c)`. Baseline is clean: 511 passed, 0 failed, rc=0.

I also checked the derivation is not merely sound but *complete*, since a shape enumerator that
misses a form reads as complete while blind. Enumerating every `fail_milestone`/`fail_obligation`
/`append_attempt` occurrence against a deliberately broader regex than the guard's returns only
the three definitions and the internal funnel — every call site matches the guard's shape. The
same test on the absent verbs returns the same. `fail_obligation` and `block_obligation` both
funnel to milestone 5, so the guard's `ms="5"` mapping is right. The `531:` override key strips
correctly and the set derives to 6.

**B2 (`m5/identity-stamp` had no behavioral fixture) — closed.** `(k11)` has real kill power, and
specifically the kind `(k11a)` lacked: under mutant D, `(k11a)`'s message assertion stays **green**
while `(k11)` alone reds. That is precisely the gap round 1 named.

## Blocker

### AC-6 is unsatisfied at `962c0bb`, and `pr-gates` reds on it

This is not a re-litigation of AC-6's bar — the ≥30% target stays settled by the 2026-08-24 body
amendment, exactly as inherited. What moved is the *measurement*, and it moved because of this
round's delta. AC-6's committed text carries two measured clauses, and both flipped sign:

| clause (spec text) | at `642a6b1` (r1) | at `962c0bb` (now) |
| --- | --- | --- |
| "`check-guard-budget.sh origin/main` reports a **negative** guard/test mass delta" | −31 ✅ | **+164** ❌ |
| "combined line count **drops** … by the measured figure recorded in the PR body" (body: −0.8%) | −0.8% ✅ | **+96, +0.76% growth** ❌ |

```
[guard-budget] ✗ guard/test shell mass grew by 164 lines with no reason recorded:
                 base 51556 (bf231bd), HEAD 51720.
```

Measured at head: `lean-gate.sh` 5,518 → 5,244 (−274); `lean-gate-selftest.sh` 7,043 → **7,413**
(+370). Combined 12,561 → 12,657. The PR body still records the selftest at 7,231 and the combined
figure at −0.8%; the r1 fix added 182 more lines than the body accounts for.

**Why this is a blocker and not a warning.** `pr-gates` runs this exact script
(`.github/workflows/ci.yml:294`) and reds at `962c0bb` — and it dies at the guard-budget step,
*before* reaching the verdict-record check. That is a different failure from round 1's expected
pre-handoff red: landing my verdict record will not clear it. No commit on the branch carries the
`Guard-mass:` trailer that is the script's own sanctioned escape hatch.

**Remedy — the build's call, not mine.** The added coverage is not the problem; `(ac1c)`, `(ac1d)`,
`(co1)` and `(k11)` are exactly what round 1 asked for and I have just verified they earn their
mass. Either delete guard mass elsewhere to bring the derived delta negative, or add a
`Guard-mass: +164 <reason>` trailer *and* have the AC-6 figures restated to what is actually
measured. The second path restates a measured clause of a criterion the operator ratified, so it
needs the operator, not the build session, and the honest reading is that the script exiting 0
under a trailer still does not make the delta "negative" as AC-6's sentence requires.

Independently found by `scope-completeness-reviewer` at confidence 96, on the amendment's clause
(b); the line-count limb is this round's addition.

## Warnings

**W1 — milestone 3 concludes `"green gate"` unconditionally, over a run that just reported a red.**
Responsive to the operator's disclosure question, and the answer is narrower than "yes" or "no".
The demotion does carry compensating controls: `lane_advisory` (`lean-gate.sh:3795`) emits two
`warn` lines *and* a durable `| milestone-3 | advisory |` row, and the merge boundary re-runs the
lane blocking. So the masking is not silent, and AC-4 ratifies the demotion. What is genuinely
weak is the last thing the operator sees: `cmd_3` ends at `pass_milestone 3 "green gate"`
(`:3961`) with no consultation of whether an advisory row was written this run. The warns scroll;
the conclusion asserts a green gate. That is the shape that cost this run a round — the
gate-buckets drift shipped in `1f346be` under a local `rc=0`. A conclusion that reads
`green gate (N advisory)` would close it without touching the demotion. Not a blocker: the
contract AC-4 states is met, and CI does block.

**W2 — the PR body's Verification block states both "154 rows" and "156 rows"** for
`check-gate-buckets` two lines apart. Actual at head is **154** (305 sites, 154 rows, green), so
the first is right and the second is stale. Body-only; nothing committed is wrong.

## AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | satisfied | deleted points survive only as explanatory comments; `(u4)` positively asserts their absence. Full sweep green in CI at `962c0bb` |
| AC-2 | satisfied | `earn_your_keep` populated **31/31**; `docs/testing.md` table re-based with a firings column |
| AC-3 | **satisfied** | both r1 blockers closed; six reasons on the absent verb; inclusion `(ac1b)`=10 and exclusion `(ac1c)` both verified to kill by mutant |
| AC-4 | satisfied | `lane_advisory` wired at `:3857`/`:3945`; `(ad3)` pins typecheck not demoted (see W1) |
| AC-5 | satisfied | workflows untouched; `check-gate-buckets.sh` at `ci.yml:165`, `check-guard-budget.sh` at `:294`, `run-selftests.sh` at `:125` — the boundary demonstrably bites at this head |
| AC-6 | **unsatisfied** | blocker above |
| AC-7 | satisfied | 5 `Changelog:` trailers on the branch |
| AC-8 | satisfied | merged-PR acceptance; resolved literal now reads "no open or **merged** PR found" |
| AC-9 | satisfied | re-cut regenerated; W2's "74 records" corrected to 70 pinned and scored (manifest is 74 lines, 70 data rows — verified) |

## Panel

Six selected, **six returned, none dark** — the first full panel in three rounds.
`scope-completeness` FAIL (the AC-6 blocker, confidence 96). `unit-test-mutation` approve with one
nit: it independently extracted the `(ac1c)` awk and ran its own mutants, reaching the same
conclusion I did — the classifier genuinely kills the B1 class, and its own soundness is covered
by no other guard, so a future edit to it needs a manual trace. Worth recording as the one piece
of standing maintenance debt the fix adds. `test-coverage`, `maintainability`, `complexity`,
`security`: approve, zero findings between them.

## Verification economy

Cited rather than re-run, at `962c0bb`: `lint-and-selftests` pass 4m32s (job 97520306632),
`selftests (macos, bash 3.2)` pass 6m57s (job 97520306352), `mutation-sweep-pr` pass 24s (job
97520306726). `pr-gates` fail 5s (job 97520306737) — read, not assumed, and it is the blocker
above rather than the expected verdict-record red. Re-executed locally because CI does not run
them verbatim: `check-guard-budget.sh` at both heads, the line-count measurements, the four-mutant
`(ac1c)` probe, and two full mutant suite runs. Probes ran in throwaway worktrees at `962c0bb`,
never in the reviewed one.

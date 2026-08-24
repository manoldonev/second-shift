# lean review verdict — #642

verdict=approve
run_id: review-642-3
session_id: bb337722-9ff1-404d-9043-6f61575c53b0
rounds: 3
pr: #660
reviewed_head: 7e04645b7ee0cc5e5a419d9efaaf9403454a94d4
reviewed_patch_id: 7354cee3571d8882472261c67de54f5b4eaf0196
inherited_patch_id: 60c38517268cb72d3a810fd884f0dc5650c347c7
inherited_from_verdict: 7e2781d2b12231d880a109a9e701cf0229af93e5
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 3 — #642 / PR 660 — approve

Round 2's single blocker is discharged. The delta is one `.md`-only commit
(`7e2781d..7e04645`, `docs/plans/second-shift-642-lean.md`) plus a `Guard-mass:` commit
trailer; no fixture, guard or production line moved. Every executable claim is inherited from
the tree round 2 verified by mutant, and the whole sweep is green at this head in CI.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| — | — | — | **No blockers, no warnings.** The 2-reviewer panel returned 2 of 2, zero dark, zero findings; hand-derivation found none either. |

## The blocker's discharge, verified by re-measurement rather than by rc

`scripts/check-guard-budget.sh` validates a trailer's PRESENCE, never its number — a bare
`Guard-mass: +164` would have passed CI identically. So the trailer's decomposition was
re-derived from scratch, by extracting the guard's own `is_guard_path` / `classify_ref` /
`measure_ref` functions verbatim (`sed` out of the production script, never retyped) and
measuring every commit on the branch:

| commit | guard mass | |
| --- | --- | --- |
| `bf231bd` (merge-base) | 51,556 | trailer's stated base ✔ |
| `642a6b1` (ablation scope's delivery) | 51,525 | **−31** — clause (b) ✔ |
| `a3eeceb` (round-1 verdict record) | 51,525 | unchanged ✔ |
| `1f346be` (round-1 FIX) | 51,720 | **+195** — the mandated coverage ✔ |
| `962c0bb`, `7e2781d`, `7e04645` | 51,720 | unchanged ✔ |

Every trailer figure reproduces exactly, and the attribution is stronger than arithmetic:
**the whole +195 lands in one commit — `1f346be`, the round-1 fix** — so nothing on the branch
after the round-1 verdict added a single line of guard mass that the trailer attributes
elsewhere. The `962c0bb` re-anchor contributes zero (it edits `scripts/gate-buckets.tsv`, not a
`.sh` the predicate counts).

Per-case limbs re-derived from `git diff -U0 642a6b1..HEAD` hunk boundaries:
`lean-gate.sh` net **+12** (14 added / 2 removed — the two close-out re-verbings and their
rationale comment) ✔; `lean-gate-selftest.sh` net **+183**, splitting as `(k11)` **+31** (hunk at
:1715, after `(k10)`) ✔, `(co1)` **+33** (hunk at :2013, after `(o)`) ✔, and **+119** across the
three contiguous `(ac1*)` hunks ✔. `12 + 183 = 195`; `−31 + 195 = +164`. Branch total **+164**
confirmed against `bf231bd`.

*Observation, not a finding:* within that **+119**, roughly **+6** is `(ac1b)`'s own update — its
`EIGHT SITES`→`TEN SITES` comment and its `8`→`10` expected count — rather than `(ac1c)`/`(ac1d)`
proper (~+113). It is wholly round-1-mandated mass in the same contiguous region, and it changes
neither the excluded total nor which verdict mandated it, so the bucket label is imprecise in a
way that costs nothing. Recorded so the next reader is not surprised by it.

## Provenance of the amendment the round rests on

`D-7`'s `user-answered` provenance is genuine, checked by the authorship test rather than taken
on the row's word: `userContentEdits` on #642 shows the body edited by **`manoldonev`** at
**2026-08-24T17:55:54Z**, and the commit that restates the spec against it is
**2026-08-24T18:04:38Z** — the amendment pre-dates its consumer by ~9 minutes, and its editor is
the operator, not the build identity. This is not a spec amended after the fact to match the
diff. The spec's clause-by-clause restatement was read against amendment 2's text and is
faithful: clause (b) re-based onto the scope's own pre-mandate delta, mandated mass excluded and
declared by trailer with per-case attribution, clauses (a)/(c)/(d) unchanged, PR-body figures
restated after the final commit. The relaxation's stated direction — review-mandated mass ONLY,
uncitable by a PR whose growth is its own scope — is carried in the amendment, the ledger row and
the trailer alike.

## Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | satisfied | Both structurally-dead points absent as arms; only deletion-documenting comments remain. `run-selftests.sh` green at this head in CI — **75 scored, 74 run, 1 cached, 0 failed**. |
| AC-2 | satisfied | `earn_your_keep` populated 31/31; `docs/testing.md` keep-table covers the union of both never-fired sets (22 points), giving 18/18 against the pin and 20/20 against the shipped corpus. Internally consistent on re-derivation. |
| AC-3 | satisfied | Inherited from round 2's mutant verification (4 mutants; `(ac1c)` reds via resolved `$LEAN_PR_ERROR` literals, `(k11)` reds where `(k11a)` stays green). No `.sh` moved since. |
| AC-4 | satisfied | Inherited; `lint-and-selftests` green at this head is the boundary re-run the demotion depends on, and the round-2 `check-gate-buckets` red is gone. |
| AC-5 | satisfied | This PR's own CI is the oracle: `pr-gates` reds on exactly the verdict condition, the other four steps pass. |
| AC-6 | **satisfied** | (a) both points deleted ✔; (b) **−31** at `642a6b1`, independently re-measured ✔; (c) **18/18** ✔; (d) **−293** comment lines, re-counted at `642a6b1` (2,782 → 2,489) ✔; mandated mass **+195** excluded and declared, decomposition verified above ✔. |
| AC-7 | satisfied | Two substantive `Changelog:` trailers on the branch (`642a6b1`, `1f346be`) plus `none` on the bookkeeping commits; `check-changelog-trailer.sh` green locally and in CI. `feat(dev-pipeline)` on the capability commit is the honest verb. |
| AC-8 | satisfied | Inherited; no `.sh` moved since round 2. |
| AC-9 | satisfied | Manifest 74 lines / **70** scored records — the round-2 W2 correction verified; report's generated block reads 70 records, 192 firings, 31 declared points. |

**9 of 9 satisfied. 0 undeterminable.**

## Round-2 warnings, disposed

- **W1** (`cmd_3` concludes `green gate` unconditionally, never consulting whether an advisory row
  was written) — deliberately not addressed by the build, on the stated ground that adding the
  line would add guard mass to the branch whose mass was the open question, and AC-4 ratifies the
  demotion W1 describes. The operator filed it as **#668** (ready-for-dev, sonnet) before this
  round. Discharged: the loop is closed by a ticket, not by silence.
- **W2** (`check-gate-buckets` figure stale at 156) — corrected. Actual at this head: **305 sites,
  154 rows**, re-run and green.

## PR-body figures, re-measured

Every figure in the Round 3 table reproduces with `wc -l`, the method the guard itself uses:
`lean-gate.sh` 5,518 → 5,232 → 5,244; `lean-gate-selftest.sh` 7,043 → 7,230 → 7,413; combined
12,561 → 12,462 (**−0.8%** across the ablation scope) and → 12,657 (**+0.76%** across the branch).
The round-2 off-by-one is gone; the endpoints are now the guard's own arithmetic.

## CI at the reviewed head (`7e04645`)

`lint-and-selftests` **pass** · `mutation-sweep-pr` **pass** · `selftests (macos, bash 3.2)`
**pass** · `pr-gates` **fail**. The `pr-gates` red was read rather than assumed: its
guard-budget step now prints `✓ … base 51556, HEAD 51720 (delta +164), covered by a 'Guard-mass:'
trailer`, and `check-frozen-files` / `check-changelog-trailer` pass. The sole residual failure is
`lean-evidence` / `lean-chain` refusing the round-2 `verdict=needs-work` record — the expected
pre-handoff state this round's record clears.

## Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope Completeness | Pass | 0 — all 12 scope items confirmed in-diff, issue fetched independently |
| Maintainability | Pass | 0 |

2 of 2 returned, **zero dark**. Depth routing classified the delta trivial-inert (one Markdown
doc outside `.claude/`), which selects maintainability plus the unconditional scope gate;
security / performance / complexity / test-coverage have no surface on a pure-prose delta and
were not selected. a11y and the design-fidelity dimension were not routed — no changed path
matched `stageParams.webComponentGlobs` (unset; resolved default `apps/web/**/*.{tsx,jsx}`), and
the repo declares no `design.provider`, so `fidelity` scores `not-applicable`.

Scope-completeness earned its keep again: it independently confirmed AC-6's amended clauses and
the trailer's per-case attribution, and independently verified AC-1's deletions by grepping for
the deleted arms' predicate string rather than by reading the diff.

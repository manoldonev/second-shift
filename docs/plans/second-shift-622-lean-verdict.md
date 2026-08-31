# lean review verdict — #622

verdict=approve
run_id: review-622-1
session_id: 40f057e2-9920-4748-bcb8-7a0539393a27
rounds: 1
pr: #755
reviewed_head: bf7ab4a70f8f2fc0c29cc287f385a717851b0673
reviewed_patch_id: 1c1d7f87ab4825cb0113a22fae4d42f5d3cb54a9
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: none
model: opus
capabilities: pr-marker

## Round 1 — review of PR #755 (issue #622)

Range read: `cf060ab1..bf7ab4a7` — the whole branch diff (root round, nothing to inherit).
13 files, +930/-22. Panel: `review-toolkit:scope-completeness-reviewer`,
`review-toolkit:security-reviewer`, plus the lead pass (performance, maintainability,
complexity, test coverage). No design axis is configured and the spec disarms `## Design`
with `Design: none`, so the fidelity step is not-applicable.

**Verdict: approve. No blockers.**

## What was verified, and how

**Both correctness lanes are green at the reviewed head** `bf7ab4a7`, cited rather than
re-run: `lint-and-selftests` pass 4m59s (all 16 steps `success`, including `shellcheck`,
`run all selftests`, and `gate bucket register`) and `selftests (macos, bash 3.2)` pass
8m32s — run `33442043418`. The sweep reports `77 scored, 76 run, 1 served from cache,
0 failed`; the single cache-served suite is `cost-block-selftest.sh`, so all four changed
suites really ran (`lean-evidence-selftest` 14s, `lean-gate-selftest` 212s,
`scenario-liveness-selftest` 71s, `check-lean-chain-selftest` 37s). The bash-3.2 lane
passing is what covers the reader's deliberate avoidance of awk interval expressions.

`pr-gates` is red on exactly one thing — `no committed verdict record (a file named
*-622-lean-verdict.md)`. That is the expected pre-approve state, not a finding.

**`mutation-sweep-pr` went green in 11 seconds having graded none of the six new catalog
rows** — both changed guards' suites are deferred as slow suites, exactly as the PR body
says. So the rows carry no CI oracle and were probed by hand, in an isolated detached
worktree at the reviewed head, each mutant applied with `sed -E` against a control run of
the same suite on the unmutated tree (control: `lean-evidence-selftest` all green,
`lean-gate-selftest` 598 pass / 0 fail). Every sed was checked for a no-op by md5 before
the suite ran. Result — all six applied and all six killed, each by the case its row names:

| catalog row | killer observed |
| --- | --- |
| `lean-evidence-scorecard-approve-unsatisfied` | `(sc3)` |
| `lean-evidence-scorecard-approve-undeterminable` | `(sc4)` |
| `lean-evidence-scorecard-missing-row` | `(sc5)`, on the missing-row half |
| `lean-evidence-scorecard-undeclared-row` | `(sc5)`, on the undeclared-row half |
| `lean-evidence-scorecard-vacuous-declared-set` | `(sc14)` |
| `lean-gate-scorecard-writer-silent` | `(vs2)`, and also `(vs3)(vs4)(vs5)(vs6)(vs8)` |

The two row-set directions genuinely share one case, and the probe confirms it discriminates
both ways: mutating the completeness loop left `(sc5)` reporting only the undeclared-row
violation, and mutating the undeclared-row arm left it reporting only the missing-row one.
That is the pair AC-1 needs, not one assertion counted twice.

**The AC-7 obligations were re-measured at this head rather than taken from the PR body:**
`gate-ablation.sh check` green, `check-fail-open-shapes.sh` 14 sites all dispositioned,
`check-gate-buckets.sh` 316 sites across 5 files bucketed by 167 rows,
`prose-blockers.sh check` zero undispositioned constructs.

**D-18's discriminator is demonstrated on this PR's own spec.** The committed spec mentions
eight ids and declares six: `spec_declared_acs` returns `AC-1 AC-2 AC-5 AC-6 AC-7 AC-8`,
while milestone 1's mention-counting predicate returns all eight including the two the
retirement note names. Reusing the milestone-1 predicate would have demanded rows for
`AC-3`/`AC-4` here, which is the concrete case the design argument is made from.

## The scope-completeness FAIL, and why it is dismissed

`scope-completeness-reviewer` returned `request-changes` with three blockers at confidence
90–95: AC-3 and AC-4 absent from the diff, and AC-6's blocker sentence only half-deleted —
each on the ground that the deferral is asserted in the branch but not in the issue body.
The code reading is correct; the authority reading is not, and I checked the ticket myself
rather than take either side on trust.

The re-cut is **operator-authored and predates the build run**. `manoldonev` posted the
re-cut comment on #622 at `2026-08-31T19:48:25Z` and the `Ratified:` comment at
`19:49:01Z`; the build session claimed the ticket at `19:55:36Z`. #753 was created by the
same human at `19:48:00Z` and carries the moved work verbatim — its AC-1/AC-2 are the
amendment gate and the zero-deleted-line exemption, its AC-3 is the `OVERRIDE_GATES` /
`OVERRIDE_SCOPES` carve-out, and its AC-5 is "the second clause of the blocker sentence".
So nothing was dropped, and the half-deleted sentence is the operator's own disposition:
the ratification comment says in as many words, "Files deleted: one clause… The second
clause travels to #753 and is deleted there."

This ticket also carries the `harness-internal` label, whose description reads
"ready-for-dev only after an operator `Ratified:` comment" — for this ticket class an
operator comment *is* the designed authority surface, so a body-only reading is looking in
the wrong place. This is scope movement recorded before any code existed, by the human, into
a real open ticket; it is not a spec amended after the fact to match the diff, and the
surviving blocker rule is not tripped.

`security-reviewer` returned approve with no findings (one suppressed at confidence 40:
`LEAN_EVIDENCE_TOOL` as an env-redirectable tool path — identical to the `OVERRIDE_TOOL`
seam three lines above it, so consistent, not a new gap; I agree with the suppression).

## Suggestions (non-blocking, no round owed)

- `review-lean/SKILL.md:52-59` names the `## AC scorecard` heading and the four scores but
  not the three column names, so a reviewer's first attempt learns them from the writer's
  refusal or from `lean-evidence.sh scorecard --print-schema`. That is the two-layer design
  working as intended — the refusal is in-session and costs nothing — and restating the
  columns in prose is the second copy `docs/testing.md` deliberately declined. Worth leaving
  as-is; noting it only because the sibling `## Design fidelity evidence` block in the same
  file *does* spell its table out, so the asymmetry will read as an oversight to someone.
- AC-1's "every cell non-empty" clause has refusals in code (`nc > ncol`, and the per-column
  empty check) with no selftest case of their own; the enumerated refusal arms all have one
  at both layers. Low value to add: a row with an empty score cell is already refused by the
  closed-enum arm, so the uncovered paths are near-redundant and fail closed either way.

## Per-AC scoring

- **AC-1 — satisfied.** Closed enum in `AC_SCORECARD_SCORES`; unknown value is an error, not
  a miss `(sc6)`/`(sc13)`. Header shape refused `(sc16)`. Exactly one row per declared id,
  both directions of the row set `(sc5)` and the duplicate-row arm `(sc7)`. The writer
  refuses approve+unsatisfied `(vs4)`, approve+undeterminable `(vs5)`, and approve silent
  about a declared id `(vs6)`; the boundary refuses the same at `(sc3)`/`(sc4)`/`(sc5)`.
- **AC-2 — satisfied.** `divergent-inert` requires both sub-fields: missing measurement
  `(sc9)`, missing follow-up `(sc10)`, both named at once `(vs8)`. A well-formed row stands
  beside an approve `(sc8)`/`(vs7)`. `isref` excludes `AC-`/`RS-` by name, so a row cannot
  cite an id of its own schema as its owner `(sc11)`.
- **AC-5 — satisfied.** Two layers, one implementation. `lean-gate.sh:5485` shells out to
  `$EVIDENCE_TOOL scorecard`; the boundary calls `ac_scorecard_violations` in-process from
  `arm_verdict`. Verified single-sited by grep: `lean-gate.sh` carries no copy of the
  heading, the column set or the enum, and its refusal quotes `--print-schema`, with `(vs3)`
  failing if it stops doing so. Every `(sc)` record is hand-written and never passed the
  writer, and `(A2)` proves the arm survives the delegation from `check-lean-chain.sh`.
- **AC-6 — satisfied.** The unmet-AC clause is gone from `review-lean/SKILL.md:164`; the
  amended-spec clause stays under the operator's ratification and is #753's AC-5. Step 5 is
  re-pointed at the gate's format and extended with `divergent-inert` plus its
  measurement-and-follow-up requirement. `pb-0426581f` is re-keyed into two content-derived
  successors — `pb-e1bac772` (`promoted / guard-added`) and `pb-b703544b`
  (`promoted / filed / #753`) — each naming its predecessor. Two rows rather than one is
  forced, not a departure: the census is content-derived and the surviving construct needs
  its own row. `prose-blockers.sh check` at this head reports zero undispositioned.
- **AC-7 — satisfied.** All three obligations discharged or shown inapplicable with the
  measurement, each re-run by me at this head (figures above). The ablation and fail-open
  halves are correctly measured as owing no row: the contract adds a writer refusal and a
  boundary violation, neither of which is a milestone firing, and the new code writes no
  `... | grep -q`. `scenario-liveness-selftest` gained the `(lean-scorecard)` leg with its
  non-vacuity twin and reports 82 passed, 0 failed.
- **AC-8 — satisfied.** Migration is fail-closed with no cutoff — `(sc2)` is that arm, and a
  pre-schema record is indistinguishable from a stripped one, which is why a grace window
  would be fail-open on the very arm being closed. The `feat:` commit carries both a
  `Changelog:` and a `Migration:` line. The self-application half is satisfied by this
  record: it was written by the branch's own `lean-gate.sh`, which refuses a non-conforming
  scorecard, so the record existing at all is the evidence.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | closed enum, header shape, both row-set directions, duplicate rows; writer (vs4)(vs5)(vs6) and boundary (sc3)(sc4)(sc5)(sc6)(sc7)(sc13)(sc16) |
| AC-2 | satisfied | both sub-fields required (sc9)(sc10)(vs8); approve stands on a well-formed row (sc8)(vs7); self-referential ref refused (sc11) |
| AC-5 | satisfied | single-sited reader; writer shells out at lean-gate.sh:5485, boundary calls it in arm_verdict; drift guarded by (vs3); hand-written records refused (sc block) and through the delegation (A2) |
| AC-6 | satisfied | unmet-AC clause deleted at SKILL.md:164, step 5 re-pointed and extended, triage row re-keyed into pb-e1bac772 and pb-b703544b; prose-blockers.sh check green at this head |
| AC-7 | satisfied | gate-ablation.sh check green, check-fail-open-shapes.sh 14 sites dispositioned, scenario-liveness (lean-scorecard) leg with its non-vacuity twin, 82 passed 0 failed |
| AC-8 | satisfied | fail-closed migration arm (sc2), Changelog plus Migration trailer on the feat commit, and this record written by the branch's own gate |

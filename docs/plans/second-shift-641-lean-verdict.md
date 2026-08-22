# lean review verdict — #641

verdict=needs-work
run_id: review-641-1
session_id: f849efbe-06fd-4cb3-9c7f-d086d69766ad
rounds: 1
pr: #645
reviewed_head: 9ea2bf7ac69759efd72513158779ccd73aefadc8
reviewed_patch_id: 255055fadd7f2174067134de7fc1909ac69fb480
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1 — full branch diff (`b8cc982..9ea2bf7`, 9 files, +408/-38). Verdict: **needs-work**, on one
blocker.

Every `AC-n` in the committed lean spec is satisfied, and the mechanism works: the new step ran
green in this PR's own `pr-gates` run against the real merge tree. The blocker is not against the
spec — it is against the issue, whose Scope item 1 and operator ratification line name an automatic
downward ratchet that this diff does not implement, and whose omission is recorded only in an
artifact the build session wrote.

## Per-AC scoring (against `docs/plans/second-shift-641-lean.md`)

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | `tools/guard-budget.tsv` exists; `check-guard-budget-selftest.sh` drives the **shipped** `check-guard-budget.sh` over six real fixture git repos — under / over-naming-the-overage / raise-without-reason / raise-with-reason / lower / first-ever-commit. Ran green here: 8 passed, 0 failed. |
| AC-2 | satisfied | All **33** rows of `tools/gate-ablation-classes.tsv` carry a non-empty 6th column (counted independently). `gate-ablation.awk:55` reds naming the row on blank **and** on absent; cases (t)/(t2)/(t3) green. |
| AC-3 | satisfied | The step is in `pr-gates` (`ci.yml:280-286`) and **ran green in CI on this PR**: `[guard-budget] at budget: measured 50531 lines, ceiling 50531`. Case 2 reds a synthetic over-budget tree. |
| AC-4 | satisfied | One pointer paragraph in the established `**Pn posture:**` form, no restatement of P4/P5's text. Wording is W-1. |
| AC-5 | satisfied | `Changelog:` trailer with `Migration: none.` on the landing commit. |

Fidelity: **not-applicable** — the spec declares no `## Design` section and the repo configures no
design provider.

## Blocker

**B-1 — the automatic downward ratchet is not implemented, and the departure is recorded only in
the PR's own spec.** `scripts/check-guard-budget.sh:94`

Issue #641 Scope item 1: *"The ratchet is the whole mechanism: on every merge to `main` the ceiling
is **lowered** to the new measured value automatically, and it can never rise on its own."* The
ratification line at the foot of the issue names *"initial value 50,247 with an automatic downward
ratchet"* as ratified at filing, by the operator.

Nothing in this diff lowers the ceiling. No code path writes `tools/guard-budget.tsv`; `ci.yml`
adds no merge-to-`main` job. `check-guard-budget.sh:94-95` prints an advisory and exits 0.

The spec concedes this (F-2, D-b, Known trades) — but a rationale in an artifact the build session
authored is not issue-body deferral. The issue body carries no deferral language and no linked
follow-up issue for the automatic half.

What makes this a blocker rather than an accepted trade is that the stated ground does not cover
the available implementation. F-2 argues against a workflow with `contents: write` on `main`, citing
the T0 note — correct, and not in dispute. But Known trades then names the shape that avoids exactly
that objection ("a workflow that opens a PR, not one that commits directly") and defers it with no
reason beyond "not a same-run addition here." The ratified mechanism was declined by refuting an
implementation nobody proposed.

Scale: with the ceiling committed at the measured value there is zero headroom today, so Scope item
1's "adds guard mass ⇒ red unless it deletes as much" holds right now. What is missing is the half
that matters next: #642 and #643 are sequenced behind this PR precisely to delete guard mass, and
without the ratchet the headroom they free is not reclaimed and can be silently re-consumed. That
is the regrowth the issue says the base case exists to stop.

Either remedy clears it: implement the scheduled ratchet-**PR** workflow the spec itself names, or
amend #641's body with explicit deferral language and a linked follow-up issue.

## Warnings

**W-1 — `docs/pipeline-manifesto.md:68` claims an enforcement property the mechanism does not have.**
The new paragraph says the ceiling "only ever ratchets down". It can be raised — a number and a
sentence in the same diff. `check-guard-budget.sh:95` prints the same overclaim in the tool's own
output ("the ceiling only ever falls"), as does the CI step name. The issue's own phrasing carries
the qualifier that makes it true — "it can never rise **on its own**". Writing an overclaim about
enforcement into the manifesto is the exact failure mode #641 was filed against; it is a wording
fix, not a design change.

**W-2 — `classify()` has seven match arms and the suite exercises one.** (test-coverage, conf 82;
confirmed by reading the fixtures.) `check-guard-budget.sh:43-53` matches `*-selftest.sh`,
`check-*.sh`, `*-lint.sh`, `*/skills/*/lean-gate.sh`, `run-selftests.sh`, `mutation-sweep.sh`,
`gate-ablation.sh`. Every one of the six fixtures calls `guardfile "$R" "check-thing.sh"` and creates
no other `.sh`, so six arms and the negative case — a product `.sh` must **not** count — cannot fail.
`check-guard-budget.sh:16-17` ("both this script and its selftest read the SAME `classify()`, so a
fixture is provably testing the rule this gate actually enforces") and D-c ("a classifier edit cannot
silently diverge from what its own test proves") are both broader than what the suite establishes.
The narrowing direction is the silent one: drop an arm and `measured` falls, the gate stays green,
and the advisory just prints a smaller number. One fixture per remaining arm plus one non-matching
file closes it.

**W-3 — the committed ceiling absorbs this PR's own guard mass rather than pricing it.** (scope,
conf 88.) `tools/guard-budget.tsv:20` commits 50,531 against the ratified 50,247. D-a's reasoning is
legitimate and its arithmetic checks out — I re-measured `main` independently and got **50,308**
exactly as F-1 states, and the +223 delta reconciles to this PR's own new guard files
(99 + 106 + 18). But the consequence stands: at the ratified figure this PR would itself have redded,
so the first guard-mass addition the mechanism was built to price is the one it exempts. On its own
this is a defensible trade; it compounds B-1 because both depart from the same one-line operator
ratification and neither departure is visible anywhere the operator reads.

**W-4 — all five documented `exit 2` paths are untested.** (test-coverage, conf 80.) Missing arg
(:35), unresolvable merge-base (:36), missing `tools/guard-budget.tsv` (:39), no data row (:69),
non-numeric ceiling (:72). The missing-TSV path is the one that matters: deleting the ceiling file
must red, and nothing proves it does.

## Suggestions

- **S-1** `tools/gate-ablation.awk:50` still errors *"classes table row has N fields, want 5"*. The
  contract is now 6, so a 4-field row is told the wrong target.
- **S-2** The PR body cites `run-selftests.sh --exclude ...` (61 scored) as its verification. The
  repo's sweep of record and the CLAUDE.md recipe pass `--full` — 74 suites. CI does pass `--full`
  and is green, so coverage is fine; the PR text just reads as the recipe while describing a
  narrower run.
- **S-3** Issue Scope item 2 also asks for "a dated incident ... where one exists", and the TSV
  header promises it. No row carries one, though several have obvious ones (`m4/identity` ↔ the
  deleted in-build reviewer). Discretionary — "where one exists".
- **S-4** The raise check never verifies the reason is *new*: a stale reason left in place clears a
  later raise. And only the first data row is read (`ceiling_row` exits on it), so a second appended
  row is silently ignored despite the "ONE data row" header.

## Suppressed (below threshold)

- `check-guard-budget.sh:56` (conf 40) — `xargs -0 cat 2>/dev/null` lets an unreadable file
  contribute 0 lines. Robustness, not security.
- `ci.yml:283` (conf 35) — `github.base_ref` is attacker-influenced but rides in the environment and
  is consumed only as a git ref argument; an unresolvable ref exits 2.
- `check-guard-budget-selftest.sh` (conf 60) — the exact `measured == ceiling` branch's distinct
  message is untested; its exit code is covered by the under-budget case.

## Strengths

- **The gate is discharged live, not asserted.** This PR's own `pr-gates` run prints
  `at budget: measured 50531 lines, ceiling 50531` against the real merge tree, and
  `mutation-sweep-pr` swept the new script 6 applied / 6 killed / 0 survived. AC-3 is proven at the
  merge boundary rather than only in a fixture.
- **The selftest drives the shipped function through real git repos.** Six fixture repos with real
  commits and branches, so the merge-base logic is exercised rather than mocked — the anti-mirror-
  harness discipline CLAUDE.md mandates. (W-2 is about the breadth of what it proves, not the
  substrate, which is right.)
- **F-1 corrects its own ticket's headline number, reproducibly.** Re-measuring `main` independently
  reproduces 50,308 to the line. A finding that replaces an ad hoc count with a script anyone can
  rerun is the right way to amend a spec.
- **Enforcement lives in the one parser every consumer already goes through.** D-d puts the
  earn-your-keep check in `readfile()` rather than a standalone lint, so no second parser can
  disagree with the first — and all 33 rows carry a real class, not filler.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Fail | 2 | 88–95 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass (nits) | 2 | 80–82 |

a11y + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs`
(unset → default `apps/web/**/*.{tsx,jsx}`).

## Verification performed by this review

- `shellcheck -e SC1091,SC2015,SC2181` clean on both new scripts and both changed tools.
- `check-guard-budget-selftest.sh`: 8 passed, 0 failed. `gate-ablation-selftest.sh`: all cases
  passed, including (t)/(t2)/(t3).
- Full sweep, CLAUDE.md recipe **with `--full`**: 74 scored, 74 run, **4 failed** —
  `lean-gate-selftest.sh` (rc=3), `scenario-liveness-selftest.sh`, `orchestrate-lean-selftest.sh`,
  `operator-override-selftest.sh`. **Not regressions.** All four fail on the same
  attended-session/operator-override assertions, `operator-override-selftest.sh` reproduces the
  identical 2 failures on `main` at b8cc982 untouched, this diff touches none of those files, and
  CI ran the same 74 suites on this head with 0 failed. Local-environment only (this session is
  scheduler-marked headless, so the `attend` cases cannot pass here).
- CI on 9ea2bf7: `lint-and-selftests` pass (74 scored, 0 failed), `selftests (macos, bash 3.2)`
  pass, `mutation-sweep-pr` pass. `pr-gates` fails on exactly one thing — the missing verdict record
  this review exists to produce.
- Independently re-measured guard mass: 50,308 on `main`, 50,531 at this head.

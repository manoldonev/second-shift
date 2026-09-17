# lean review verdict — #843

verdict=approve
run_id: review-843-1
session_id: 71a73e3d-b7c4-4ec5-b08e-3da541a9d5ee
rounds: 1
pr: #852
reviewed_head: 98962d723c970f8fa251b3202fd5f325f3f8e853
reviewed_patch_id: 8ccd51589d7eb33776ea3589e6d1d060a329392f
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

Round 1, full range `5fdd8e4..98962d7` (no prior record to inherit from; `G delta` printed the whole branch diff).

Panel: pipeline default (scope-completeness only) — no opt-ins taken (the spec's Decision Ledger carries no `review panel` row, and config has no `reviewers` block). `security-reviewer`, `a11y-reviewer` and `unit-test-mutation-reviewer` were not selected; the security dimension was covered by the lead pass. No changed path matched `stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`), so a11y and design-fidelity were not routed. `scope-completeness-reviewer` returned approve with zero findings (one suppressed at confidence 55: the AC-3/AC-4 sweep-evidence caveat, which the lead pass then measured directly — see below).

**No blockers.** Every claim the PR asks a reviewer to weigh was re-derived here rather than taken.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `lane-env-selftest.sh` case `(o)` derives its census from the tree (`git ls-files '*.sh'`, comment-stripped, `-selftest.sh` excluded), finds **8** sourcing guards, mirrors each into a scratch layout with the lib's DIRECTORY present and only `lane-env.sh` removed, and asserts rc 2 **and** the `cannot load lane-env.sh` FATAL line per guard; `sourcers -eq 0` is a `fail`, so it is closed on an empty census. Green at this head in both CI selftest jobs (`lint-and-selftests`, `selftests (macos, bash 3.2)` — run 35267543713) and locally (`all green`, 4.33s, after scrubbing this shell's own `LANE_ATTEND_MODE` leak, which false-reds case `(j)` and is not a branch defect). Both halves probed live in an isolated worktree at 98962d7: reverting `check-lane-chain.sh`'s load-failure rc to 1 → `FAIL … check-lane-chain.sh:rc=1`; deleting `milestone-gate.sh`'s FATAL `echo` while keeping rc 2 → `FAIL … milestone-gate.sh:no-FATAL-line`. The rc-only assertion the case warns about is real, and the FATAL half is what closes it. D-6 re-verified: rc 2 is the documented usage/environment refusal in all eight (`milestone-gate.sh:181`, `reconcile.sh:89`, `orchestrate.sh:215`, `operator-override.sh:47`, `pipeline-cost-block.sh:10`, `check-lane-chain.sh:190`, `lane-bench.sh:99`, `lane-bench-arm.sh:48`). |
| AC-2 | satisfied | `bash tools/mutation-sweep.sh --emit-site-keys` run by this review at 98962d7 (3722 rows): `526b44acfdb1` and `35caac0f4b00` each occur **0 times across the whole tree**, not merely outside the k=2 window. Corroborated structurally — `milestone-gate.sh`, `operator-override.sh`, `pipeline-cost-block.sh` and `lane-bench-arm.sh` now enumerate **no** non-comment `exit 1` line at all, so the `fail-open` operator is inapplicable to four of the eight. The `exit 11` wording survives in `skills/review/SKILL.md`, which is prose outside the swept universe and needs no reword. |
| AC-3 | satisfied | The promoted set was derived independently, not read off the PR: `--emit-site-keys` at base (5fdd8e4, isolated worktree) and at head, both restricted to the eight guards and ordinal ≤ 2, then `comm`'d. Exactly **11** sites entered the window, and they are precisely the PR's triage: `logic::50b2c8b0d147` in all eight guards (the lane-env line itself, re-keyed by the `exit 2` content — not a new site) plus three `fail-open` sites, `reconcile.sh:175`, `orchestrate.sh:462`, `check-lane-chain.sh:1021`. Nothing was missed and nothing was claimed that did not move. All eleven then probed to a kill in an isolated worktree, each against a green control: `reconcile.sh:175` `exit 1`→`exit 0` → `reconcile-selftest.sh` 1 FAILURE (the new case `(B2)`); `check-lane-chain.sh:1021` → `check-lane-chain-selftest.sh` 40 FAILURES; `orchestrate.sh:462` → `orchestrate-selftest.sh` 1 FAILURE; and the logic mutant (or-to-and) on the lane-env line of **each** of the eight → `(o)` fails with `<guard>:no-FATAL-line` every time. The one baseline row added, `lane-bench-arm.sh::default::7769e7c177d5`, checks out on its own terms: the `default` operator's only site there is `[ -n "${LANE_ARM_ADD_DIRS:-}" ]` (:98), the herestring on :101 reads the **unmutated** variable, so on the empty-knob path the mutant enters the loop, reads one empty line, appends nothing, and builds the same argv — and `lane_env_promote` (:45) guarantees the name is set, so `set -u` cannot diverge either. It was already in-window at base with no row, so the attribution "promoted by nothing this ticket did" is accurate. |
| AC-4 | satisfied | Checked deterministically rather than by kill verdict, row by row: all **12** baseline rows remaining for the eight guards resolve to a site at ordinal ≤ 2 at this head. The two re-keys replace keys that are absent from the emitted set at **base as well as head** (`4d47aa4f1b08`, `71e3cd591c37` — #839's rename left them stale) with keys present at ordinal 2 in both. The six retirements are one site gone tree-wide (`2a413b864c37`) and five live-but-out-of-window sites, at ordinals 4, 5, 11, 12 and 16/21 — none within k=2, so no retirement can red the next sweep on the survivor it existed to accept, which is the failure mode the spec's Scope-In bullet names. |

## Findings

Nothing blocker- or warning-class. Three notes, none of them requiring a change:

- **[Test Coverage] The census cannot see a guard that stops sourcing the lib.** Probed: removing the `. …/lane-env.sh` line from one guard leaves `(o)` passing at `all 7 sourcing guard(s)`. The case's comment frames the fail-closed floor as covering this ("a guard that quietly stops sourcing it leaves the census — which is why the floor below fails CLOSED"), but the floor is zero, so 8→7 is silent. AC-1 asks only for fail-closed on an empty census, so this is in spec, and case `(l)` — which requires every discovered `LANE_` knob to be promoted — is what would actually catch the drop. Worth a sentence's correction in that comment if the file is touched again; not worth a round.
- **[Complexity] The PR-lane sweep now grades nothing for this diff's guard set.** `mutation-sweep-pr` at this head: `PR mode graded NOTHING: all 8 in-scope guard(s) deferred to the merge-time sweep, 0 swept (reasons: multi-suite union: 8)` — a warning, not a red, and exactly the trade D-1 accepts. The consequence for *this* review is that AC-3 and AC-4 have no CI sweep evidence at this head; that is why both were re-derived here from `--emit-site-keys` and direct mutant probes rather than scored on the build's local advisory runs. CI's merge sweep remains the verdict of record for the carried-over sites.
- **[Maintainability] One argument in the PR body is redundant, not wrong.** The reason given for not recording `lane-env-selftest.sh` as slow — "recording it as slow would defer all eight guards on the PR lane" — describes a state that already obtains: all eight are deferred by multi-suite union regardless. The decision itself stands on its own evidence (4.41/4.03/4.05s quiet, under the 5s bar; the 7s reading was taken under lane contention), and I measured 4.33s here.

## Strengths

- The failing half is the load-bearing half, and the case says so and proves it. Asserting the FATAL line beside rc 2 is what stops a deleted branch from scoring as a pass, since most of these guards refuse with rc 2 on a no-argument run anyway — and the mirror keeps the lib's *directory* so the `cd` above the source line cannot supply the same rc for a different reason.
- The exit-code change is contract-conformant, and it improves a real caller. `orchestrate.sh:1582` already routes gate rc 2 to `terminal verdict-gate-unreadable 2` — "an environment refusal, not a verdict. No REVIEW spawned" — which is precisely what a missing library is; under the old rc 1 the same fault was read as a verdict. `operator-override.sh check` likewise moves from REFUSE (1) to UNKNOWN (2), whose consumers fail closed.
- The baseline edit is stated in the shape a later reader can check: each retirement names why the sweep can no longer produce the row, and the one addition carries a mechanism rather than a verdict — which is what let it be re-derived here instead of trusted.

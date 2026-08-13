# lean review verdict — #514

verdict=approve
run_id: review-514-1
session_id: 8ccd305c-b4be-483b-b126-575dcfe30174
rounds: 1
pr: #521
reviewed_head: 35d797b092f82fdfca74dcd8df35466c56bad092
reviewed_patch_id: a739301f6c7dd5c83f298f22d011b8dc8c87bfc5
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR #521 (#514)

Range read: full branch diff (`e6a16ef..35d797b`), 4 files / 356 insertions. Root round —
nothing inherited.

**Verdict: approve.** No blockers. One disclosed trade recorded below as a warning.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning (accepted) | `tools/mutation-pair-map.tsv` | The new pair-map row moves `orchestrate-lean.sh`'s **generic** mutants from PR-time to nightly. `mutation-sweep.sh:896` defers a guard entirely when **any** killer is slow, and `scenario-liveness-selftest.sh` is registered in `mutation-slow-suites.tsv` at 31s — so coverage that `orchestrate-lean-selftest.sh` was delivering at PR time is now `deferred-to-nightly`. Disclosed in the spec's Deviation section and the PR body, and the cited precedent is real: `plan-lint.sh`, `statectl.sh`, `scenario-lib.sh` and `gen-statectl-validators.sh` already carry `scenario-liveness-selftest.sh` rows for the same reason. Accepted, not a blocker — the alternative was a prose prediction nothing checks. |

Nothing else surfaced. The six-reviewer panel (security, performance, maintainability,
complexity, test-coverage, scope-completeness) returned `approve` with zero findings and one
suppressed sub-threshold note (confidence 40, test-only PATH stubs contained in the suite's
`mktemp -d`). Panel was fully live — no dark reviewer, so no coverage gap.

## Independent verification

Everything below was run by this review session from a checkout of the reviewed head; the
probes ran in two throwaway worktrees, never the reviewed one.

**Baseline** — `scenario-liveness-selftest.sh` at 35d797b: **95 passed, 0 failed**, with all four
new cases green. Reproduces the PR's claim.

**Probe table.** Each probe applied one flip, re-ran the whole suite, and was scored by case
*ordinal* among the `(lean-reentry*)` verdict lines — never by message text, since the FAIL
branch prints different words than the PASS branch. Each anchor was confirmed to resolve to
exactly one site before the flip, and every mutant was `bash -n`-clean.

| Probe | Flip | c1 | c2 | c3 | nv | Suite |
| --- | --- | --- | --- | --- | --- | --- |
| — | none (baseline) | PASS | PASS | PASS | PASS | 95/0 |
| P1 | the catalog row's sed, verbatim — reverts #510's arm | FAIL | FAIL | FAIL | FAIL | 91/4 |
| P2 | admit **any** claimed ticket (`if [ -n "$marker_run_id" ]` → `if true`) | PASS | PASS | PASS | **FAIL** | 94/1 |
| P3 | keep the "re-entry" wording, drop the run id from the line | PASS | **FAIL** | PASS | PASS | 94/1 |

Three things that table establishes, none of which the PR body could assert on its own:

- **P1 kills all four cases and moves no other case in the suite.** The catalog row's kill is
  precisely attributed to this leg, and the leg is genuinely coupled to the production arm.
- **P2 is caught by the non-vacuity arm and by nothing else.** A scheduler that admitted every
  claimed ticket would sail past all three positive cases. AC-4's arm is the only thing standing
  there, which is exactly the claim it makes for itself.
- **P3 is caught by case 2 and by nothing else.** The run-id half of AC-2 is independently
  load-bearing: a scheduler that stopped naming the run would otherwise ship silently, since the
  terminal write and the gate-authored record are both unaffected.

**Other checks.** `LEAN_PROGRESS_FILE` is a pre-existing documented seam on `origin/main`
(`lean-gate.sh:142,408`), not a backdoor added for this leg. The scheduler really does parse
`git worktree list --porcelain` (`:392`) and `--git-common-dir` (`:198`), so reusing the lean
fixture tree as `MAIN_ROOT` exercises that path rather than stubbing it. Issue key `55` collides
with no other lean leg (the others use 77/777/88), so the leg does not inherit legs 1–7's shared
mutable state. Both TSV rows are schema-conformant (4 and 3 fields) and the catalog is consumed
by `mutation-sweep.sh:348` with anchor-drift detection, so the AC-5 prediction is machine-checked
rather than prose. `pr-gates` is red on exactly one item — the absent verdict record this round
produces — and nothing else.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | Case 1 asserts `rc=0`, `done — #`, and exactly one `\| milestone-5 \| satisfied` row, on a chain whose only fakes are the tracker CLI and the session binary. Green at baseline, dead under P1. |
| AC-2 | satisfied | Case 2 asserts the line names re-entry **and** carries the marker's run id. P3 isolates it: drop the id and case 2 is the only case that reds. |
| AC-3 | satisfied | The session fake writes only its spawn counter, its log, a ledger stub and the spec file — every progress-row advance goes through `bash "$RE_GATE"`. Corroborated mechanically: under P1 the record is absent, which a hand-written row would have survived. |
| AC-4 | satisfied | The arm varies the fixture (`jq` rewrites `.user.type` to `"User"`), never production, and pins rc=2 + zero spawns + zero milestone-5 rows + the reason string. P2 shows it is the only case that catches an unconditional admission. |
| AC-5 | satisfied | Both rows present and schema-conformant; the anchor resolves to exactly one site; P1 reproduced the predicted kill independently of the build session. |
| AC-6 | satisfied | The `Scenarios:` roster names `lean-reentry`, and the ceiling is recorded under **(A) out of reach BY CONTRACT** with the model-free-CI reason. |

## Design fidelity

`not-applicable`. The spec disarms with `Design: none — no user-facing surface`, which is
justified: the diff is one selftest leg and two mutation-tier rows, there is no FE surface, and
this repo configures no `design.provider`.

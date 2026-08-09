# lean review verdict — #447

verdict=approve
run_id: review-447-1
session_id: 29847706-433b-4269-958e-685f45300b55
rounds: 1
pr: #453
reviewed_head: 974495c85a39f75e55241a89980a5e11228dd301
reviewed_patch_id: 281763a0ea154bbdca11b323c50880b44c2b64ef
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1, full branch diff (`b55e701..974495c`, 8 files, +858/−49). Panel: security,
performance, maintainability, complexity, test-coverage, scope-completeness — all six
returned; none dark. Design: `not-applicable` (the spec disarms with `Design: none — no
user-facing surface`, and this repo configures no `design.provider`, so the disarm is
justified).

**No blockers.** The runner is a genuinely good piece of work: the failure it found during
implementation was fixed by removing the class (argv sentinel instead of an inherited
environment variable) rather than the instance, both rejection paths are seam-driven with
control cases proving the seam moved the verdict, and the AC-5 assertion pins two total
counts so it cannot pass against a runner that replayed nothing. Five warnings follow; four
are artifact/doc accuracy and one is an observability regression. None blocks the merge.

## Verification at the reviewed head

| Check | Result |
| --- | --- |
| `lint-and-selftests` (ubuntu) | pass — `run all selftests` step **212s**, down from 709s |
| `selftests (macos, bash 3.2)` | pass — job **6m24s**, down from 17:50 |
| `mutation-sweep-pr` | pass, 20s, off the critical path |
| `pr-gates` | fail on the **lean-chain arm only** (missing verdict record — expected pre-handoff). Frozen-files, changelog-trailer and pipeline-chain arms all pass |
| `actionlint` | pass in CI, closing the "could not run locally" gap the PR body flags |
| Local sweep, reviewed head, `SKIP_STRESS=1` + the documented exclusion | **67 ran, 67 passed, 0 failed**. Wall clock not cited — three other sessions' sweeps were running on the same machine |

## Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| 1 | warning | `.github/workflows/install-topology.yml:26-31` | The nightly workflow **cannot run before merge, and did not**. `schedule` fires only from the default branch, and a `workflow_dispatch` workflow is not dispatchable until it exists there — so this file has never executed anywhere. The PR body's "For the reviewer" section says `install-topology` and `install-topology (macos, bash 3.2)` are "worth confirming actually ran and were green rather than silently skipped"; `gh pr checks 453` returns exactly five checks and neither is among them. An untested workflow carrying the repo's only packaging-class guard should be dispatched from the base branch immediately after merge, not left to 02:41 UTC. |
| 2 | warning | issue #447 body | **The tracker's acceptance bar was never amended.** D-10 is recorded in the committed spec and led in the PR body, but the issue still reads "`install-topology-selftest.sh` runs in its own job on both the ubuntu and macos lanes" under the heading *Job topology in `.github/workflows/ci.yml`*, and its Projection table still budgets `install-topology (macos, uncontended) ~400s — the new critical path`. Issue comments carry only the claim marker. Scored a warning, not a blocker: the committed spec is the definition of done on this lane, and the amendment is disclosed with provenance rather than retrofitted silently. But the issue is what a merger reads. |
| 3 | warning | `docs/plans/second-shift-447-lean.md`, AC-9 | AC-9's two halves now disagree with each other. "The set of suites executed across the whole CI run is unchanged from run 31307491709" is no longer true of a PR run after D-10; the clause that follows it — "every `*-selftest.sh` still runs on both lanes, `install-topology-selftest.sh` included" — is. AC-6 was amended for D-10 and AC-9 was not. |
| 4 | warning | `docs/testing.md`, "How the sweep runs" | The file contradicts itself on the local recipe. Its code block is `SKIP_STRESS=1 bash tools/run-selftests.sh` with **no** `--exclude`, while the same file later states "The documented local recipe excludes it too" and `CLAUDE.md`'s recipe does carry the exclusion. Copying the `testing.md` block silently buys the ~7-minute guard back. |
| 5 | warning | `tools/run-selftests.sh:164-197` | **A hung or cancelled sweep now emits nothing at all.** Output is captured per suite and replayed only after every worker has finished, so for up to the whole sweep duration no line names a running suite; the old serial loop printed `── $t` before each. This lands together with `cancel-in-progress: true`, so a cancelled run's log contains no suite names whatsoever, and the runner carries no per-suite bound (unlike `install-topology-selftest.sh`'s `INSTALL_TOPOLOGY_TIMEOUT`). Hit live during this review: identifying which suite a long local run was inside required `ps`, not the log. A one-line echo of the worklist before dispatch would close it. |
| 6 | suggestion | `tools/run-selftests-selftest.sh:252` | States the retired keying in the present tense — "The dispatch sets `RUN_SELFTESTS_WORKER` on `xargs`". `run-selftests.sh:60` and `docs/testing.md` both correctly frame it as an earlier revision; a reader of this file alone would believe the env var is still live. (maintainability-reviewer, confidence 82.) |
| 7 | suggestion | `tools/run-selftests.sh:118` vs `:143` | `--exclude ./tools/x-selftest.sh` is normalized at validation but not written back into `EXCLUDES`, so the filter at `:143` misses, the suite runs, and the sweep reds as `silent truncation` rather than the accurate `stale exclusion`. Fails safe — only the diagnosis is wrong. |
| 8 | suggestion | `tools/run-selftests.sh:191` | A suite that genuinely exits 125 is annotated "the worker died before scoring this suite (infra, not a result)". Small collision surface, documented rc. |

Suppressed (below threshold, recorded for visibility): no fixture for a non-integer `--jobs`
or a nonexistent `--root` (test-coverage, 60-65); the new `mutation-sweep-pr` job omits an
explicit `permissions` block, matching the pre-existing `lint-and-selftests` pattern
(security, 70); a suite filename beginning with `-` would be read as a bash option, which
requires repo write access (security, 45).

Not routed: `a11y-reviewer` and the design-fidelity dimension — no changed path matched
`stageParams.webComponentGlobs` (key absent; default `apps/web/**/*.{tsx,jsx}`). `db-reviewer`,
`pipeline-reviewer` and `unit-test-mutation-reviewer` have no surface in a shell/workflow diff.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `tools/run-selftests.sh` exists; `ci.yml:105` (ubuntu) and `ci.yml:341` (macos) both invoke it; both inline `while read` loops are deleted. |
| AC-2 | satisfied | `run-selftests.sh:194-210`. Guarded by two failing suites at different exit codes, with the grep scoped to the `FAILED suites:` block — the selftest's own comment records that the unscoped form let a first-failure-only mutant survive. |
| AC-3 | satisfied | Stale exclusion `:119-121`; count reconciliation `:200-203`. Both driven through `RUN_SELFTESTS_DROP_LAST`, each with a control case proving the seam and not a broken fixture produced the red. |
| AC-4 | satisfied | `run-selftests-selftest.sh:141-164` asserts equal rc **and** an identical ordered `::group::` set, on a green fixture and a red one, plus the `SELFTEST_JOBS` env path. |
| AC-5 | satisfied | `:191-218`. The two total counts (12 MARK lines, 12 inside groups) close the "replayed nothing" and "streamed live" vacuity holes. |
| AC-6 | satisfied | Against the committed spec's amended text. Excluded on both lanes (`ci.yml:105`, `:341`); nightly on both lanes in `install-topology.yml`. See findings 1 and 2. |
| AC-7 | satisfied | `mutation-sweep-pr` job at `ci.yml:143-160`, `concurrency` block at `:8-14`. Confirmed live — it ran as its own check in 20s. |
| AC-8 | satisfied | AC-2 through AC-5 each carry executable assertions against the real runner over fixture trees; no prose-presence guards. |
| AC-9 | satisfied | On its operative clause, verified independently rather than taken from the PR body: `git ls-tree -r b55e701` = 67 `*-selftest.sh`, `974495c` = 68, the sole addition being `tools/run-selftests-selftest.sh`; `install-topology-selftest.sh` still runs on both lanes. The headline clause is stale — see finding 3. |
| AC-10 | satisfied | Both files state the runner as the recipe; `docs/testing.md`'s block is internally inconsistent — see finding 4. |

## For the build session

The build worktree `second-shift-worktrees/claude-second-shift-447` carries an **uncommitted**
`CLAUDE.md` edit rewording the "~3 minutes instead of ~10" paragraph. It is not in the PR and
was not reviewed. Worth deciding deliberately rather than letting it ride into a later commit —
the committed claim is supported by this run's own CI, whose ubuntu selftest step measured 212s.

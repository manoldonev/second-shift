# second-shift #842 — A merge sweep that blows its bound must still say so

The merge-time mutation sweep for `e3f9607b5bbd` (the #839 rename: 141 files, 67 of them `.sh`)
never reached a verdict. The `mutation sweep (merge-scoped, deferral off)` step was cancelled at
its 60-minute `timeout-minutes` bound after grading 5 guards, and the issue that fired in its place
said only "A merge-time mutation sweep failed on a harness fault rather than a coverage gap" — it
named neither the timeout, nor the bound, nor how far the sweep had got. Both halves are defects
of the same lane: the bound is mis-sized for a merge of that width, and the red body cannot
describe the one failure mode a bound produces.

The workflow's own sizing comment already prescribes the remedy for the first half — "a blown
bound is a bound edit" — and says the 30–45 minute worst case it was sized against "has never been
observed". This ticket observes it, and edits the bound to what was observed.

## Goal

`.github/workflows/mutation-merge.yml` carries a step and job bound sized from a measured re-run of
the `e3f9607b5bbd` scope, so a merge that wide reaches a verdict; and its `classify the red` step
recognizes a bound kill, saying in the filed issue that the step timed out, at what bound, and how
many guards it graded first — under the infra-red title key it already uses.

## Scope

### In

- `.github/workflows/mutation-merge.yml` — the sweep step's `timeout-minutes`, the `sweep` job's
  `timeout-minutes`, and the timeout case in the `classify the red` step's body.

### Out

- `tools/mutation-sweep.sh`. The sweep is not slower than it should be; it is bounded lower than it
  costs. Nothing about its scoping, deferral or pool changes (D-1: no cap-and-defer, no sharding).
- Any new script, guard or selftest. The ratification comment fences this change to the existing
  workflow's red-body step, as the exception it grants to #717's negative-net-diff bar (D-8).
- Re-grading the guards `e3f9607` left ungraded. The monthly wholesale audit is the pass that
  grades them (D-6 / OR-2).
- `docs/testing.md`. AC-3 keeps the three title keys exactly as that document lists them, so
  nothing it states about them goes stale; and the ratified fence is the workflow.
- `.github/workflows/mutation-sweep.yml` and `ci.yml`'s `mutation-sweep-pr` job. Neither runs with
  deferral off, so neither has this lane's cost.
- `plugins/*/.claude-plugin/plugin.json` `version`, `CHANGELOG.md`, and
  `.claude-plugin/marketplace.json` `metadata.version` — derived at release, frozen in a feature PR.

## Acceptance Criteria

- AC-1 — The sweep step's `timeout-minutes` and the `sweep` job's `timeout-minutes` in
  `.github/workflows/mutation-merge.yml` are sized from a measured re-run of the `e3f9607b5bbd`
  scope (`--mode pr --base 3113cb95`, deferral off), not from an estimate. The job bound stays
  strictly above the step bound, so a step kill is still an ordinary step failure the job proceeds
  past. The sizing comment states the measurement it was taken from, and the PR states the numbers.
- AC-2 — When the sweep step is killed by its bound, the body the `classify the red` step builds
  says the step timed out, names the bound in minutes, and names how many in-scope guards the run
  graded before the kill. The bound the body prints and the bound the step enforces are the same
  value written once, so the body cannot drift from the bound it reports.
- AC-3 — A timed-out sweep files under the existing `mutation sweep infra red` title key, including
  when the killed run had already printed one or more `RED: baseline-absent survivor:` lines. Any
  such survivor ids are carried in the body; they never move the run to the `mutation sweep red`
  key, which asserts a graded verdict this run did not reach.
- AC-4 — Oracle. `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
  is clean; every `*.json` parses under `jq empty`; `actionlint` 1.7.7 (CI's pin) is clean over
  `.github/workflows/`; and
  `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
  exits 0.

## Design

Design: none — this ticket edits one GitHub Actions workflow. It renders no UI, and no
`design.provider` is configured for this repo.

## Decision Ledger

Rows D-1 … D-8 are carried forward from the pre-flight receipt
(`.claude/pipeline-state/842-ledger.md`) under the same ids and Resolution text. D-9 … D-12 are
build-time decisions.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What happens when a merge touches more guards than fit in the bound | Raise the bound so the sweep finishes with a verdict; no cap-and-defer, no sharding | user-answered |
| D-2 | Whether a timed-out sweep's filed body names the timeout and its progress | Yes, in this ticket | user-answered |
| D-3 | Title key for a timed-out sweep | The existing mutation sweep infra red key (the three keys in docs/testing.md and file-issue-on-red.yml) | codebase-derived |
| D-4 | Job bound vs step bound | Job bound stays above step bound so evidence survives a step timeout (comment in mutation-merge.yml) | codebase-derived |
| D-5 | New bound value | Parked under OR-1 (owner: BUILD, before the workflow edit) | deferred |
| D-6 | Re-grading the guards e3f9607 left ungraded | Parked under OR-2 (owner: operator, at review) | deferred |
| D-7 | Build model | opus (operator standing rule for this repo, restated in the ratification comment) | user-answered |
| D-8 | harness-internal ratification and #717 net-diff exception | Ratified with exception: change stays inside the existing mutation-merge.yml red-body step, no new script/guard/selftest, per https://github.com/manoldonev/second-shift/issues/842#issuecomment-5714623451 | ticket-sourced |
| D-9 | How the `classify the red` step tells a bound kill from an ordinary red | By the absence of the sweep's terminal line. `finish()` is the single exit path of `tools/mutation-sweep.sh` — green and red both reach it — and it always prints `[mutation-sweep] timing: Ns wall — …`. A failed step whose log lacks that line did not reach a verdict. This is the same property the sweep's own `COMPLETE_MARKER` asserts ("reaching finish() is exactly the property the marker asserts"), read from the log rather than from a file the killed step never wrote. No new signal is introduced and the sweep script is untouched. | codebase-derived |
| D-10 | Where the graded count comes from | The count of `[mutation-sweep] swept ` lines in `sweep-out/sweep.log` — the line `emit_row … swept` pairs with, one per guard that reached a verdict. The in-scope TOTAL is deliberately not reported: the sweep prints it only under `--emit-site-keys`, and re-deriving the guard universe inside the red-body step would be an approximation of a rule that lives in the sweep, which is the drift the workflow's own "NO PATH FILTER" comment refuses. AC-2 asks for how many were graded, and that is what the body states. | codebase-derived |
| D-11 | OR-1 resolution — the new bound values, and how they were measured | Taken, and flagged in the PR. The bounds are sized from a local re-run of the exact `e3f9607` scope (`--mode pr --base 3113cb95`, `MUTATION_SWEEP_NO_DEFER=1 SKIP_STRESS=1`, cache off) rather than from a CI re-run: `mutation-merge.yml` triggers only on `push: branches: [main]`, so there is no way to exercise it from a branch, and `gh run rerun` re-runs the 60-minute bound that is the defect. The local figure is converted to the CI lane's cost at the pool width CI actually used (`pool: 2 worker(s)`), and the PR states the local wall, the local pool width, the conversion, and the headroom taken. | user-delegated |
| D-12 | Whether the timeout body is a new title key | No. AC-3 is explicit and `docs/testing.md` fixes the key set at three; a fourth key would be a new standing red for the dedup rule to carry, for a fault that routes to the same owner as every other infra red. | user-answered |

## Open Regions

| ID | Region | Disposition | Outcome |
| --- | --- | --- | --- |
| OR-1 | The new step and job timeout values | reversible-default-and-flag | Taken, and flagged in D-11 and in the PR. Sized from the measured re-run of the `e3f9607` scope; changing them later is the one-line workflow edit the file's own comment prescribes. |
| OR-2 | Whether the ungraded guards of `e3f9607` are re-graded before the monthly wholesale audit | reversible-default-and-flag | Default taken: no re-grade in this ticket. Flagged in the PR for the operator at review. |

## Notes

The two halves are independent fixes for the same run, and only one of them can be verified before
merge. AC-2 and AC-3 are exercisable by reading the `classify the red` step against the log the
timed-out run actually produced (published as the `mutation-merge` artifact of run 34525820746).
AC-1 is a bound, and a bound is only ever confirmed by the next merge wide enough to test it —
which is why the workflow's comment calls a blown bound a bound edit rather than a design error.

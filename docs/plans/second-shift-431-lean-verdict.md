# lean review verdict — #431

verdict=approve
run_id: review-431-1
session_id: eeaabfd0-0035-47a6-a98e-dab510a071ef
rounds: 1
pr: #433
reviewed_head: e2cf4eb4e446b0117cf9d60b4ff34f8d787fb3c1
reviewed_patch_id: c3180ef300e5142ead660b7a294de6923c3ec779
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

## Review round 1 — chain ROOT (whole branch diff, `9c0a689..e2cf4eb`)

`lean-gate.sh delta 431` printed the FULL range: nothing verifiable to inherit. Five files,
443 insertions — one production guard (`tools/mutation-sweep.sh`), its paired selftest, the
exit-contract doc, the lean spec, and one assertion fix in `lean-gate-selftest.sh`.

Panel: `review-lead` fan-out over `review-toolkit:{security, performance, maintainability,
complexity, test-coverage, unit-test-mutation, scope-completeness}`. a11y + design-fidelity
not routed — no changed path matches `stageParams.webComponentGlobs` (unset → default
`apps/web/**/*.{tsx,jsx}`). No reviewer went dark.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 serial re-verify of a lane-redding survivor | **satisfied** | Oracle sits in phase 5 (`:1610`), common to `--mode full` and `--mode pr`; merge mode exits at `:673` long before it. `reverify_needed` gates on `in_baseline` (seed → every pool-scored survivor), `pool_scored` reads `mut.final`. `reverify_survivor` re-installs the blob (`:1300`) and walks the **full ordered kill set** (`:1306`). `reverify_sandbox` grows to `SANDBOX_N+1` and takes index `SANDBOX_N-1` — the just-created sandbox, past the pool's `0..n-1` (`run_pool` sizes the pool in the main shell at `:1165`). `(aj2)` pins exactly two observations of the mutant: pool once, oracle once. |
| AC-2 disagreement is a named infra red | **satisfied** | `red "pool disagreement: …"` names the mutant, states the harness is at fault, and the corrected `killed` record is written back to `$vf` and re-read before the counters — so `add_survivor` never fires and no `baseline-absent survivor` red is emitted. `(aj1)` asserts rc=1 + the named red + the **absence** of the coverage-gap red. |
| AC-3 agreement changes nothing | **satisfied** | `(aj4)`: a genuine survivor stands, row `0/1/guard.sh::fail-open::1`, still reds `baseline-absent survivor`, no `pool disagreement`. Verdict, row, red and exit status all unchanged. |
| AC-4 zero cost on a green run | **satisfied** | `(aj5)`: rc=0, `computed=2`, and no `re-verifying survivor serially` line at all. |
| AC-5 seed gated before the baseline write | **satisfied** | The oracle runs inside the aggregation loop, which completes before the seed artifact block (`:1638-1668`). `(aj6)`: `seeded.tsv` carries 0 survivor rows while the run still prints `pool disagreement`. |
| AC-6 report coherence | **satisfied** | The corrected record is re-read into `$verdict` before `killed`/`survived`/`survivors` are computed, so `emit_row` and `TOTAL_SURVIVORS` derive from it by construction. `(aj3)`: row `1/0/` — killed=1, survived=0, empty `survivor_ids`. |
| AC-7 cache coherence | **satisfied** | `cache_put "$REVERIFY_KEY" "$REVERIFY_REC"` at `:1615`. `(aj7)`: the warm run is served `KILLED`, rc=0, row `1/0/`. |
| AC-8 regression guard that fails on the pooled path | **satisfied** | `make_flaky_fixture` is deterministic in both directions: on the **unmutated** guard the killer exits 0 and writes no observation, so the precheck stays honest; on the mutated guard observation 1 exits 0 and every later one exits 1. The observation dir is absolute and outside the fixture, so it survives each `git worktree add` sandbox. Covers the flip + named red (AC-2), the corrected row (AC-6), zero-extra-suites on green (AC-4) and seed-before-write (AC-5), plus the unasked-for reverse direction `(aj4)` and cache `(aj7)`. |
| AC-9 exit contract in both copies | **satisfied** | `pool disagreement` lands in `tools/mutation-sweep.sh`'s "Red only for:" header list and in `docs/testing.md`'s named-infra list in this diff, plus a runbook entry stating the fix is the harness and a baseline row is the one thing that must not be added. No new lockstep row — see W1. |
| AC-10 the base branch's own red is cleared | **satisfied** | Reproduced independently: a detached worktree at `9c0a689` runs `lean-gate-selftest.sh` to **exactly one** failure, `(m1c)`; the branch head is all-green. Probe at the branch head — hardcoding `model: unknown` in `ensure_progress_file` — reds `(m1c)` **and nothing else**, so the case keeps its full strength. Amendment hunk diffed for removals: pure addition, no AC weakened or struck. No production file changed. |

Design fidelity: **not applicable**. The spec's `## Design` section reads `Design: none — …the repo
configures no design.provider`, and `.claude/second-shift.config.json` indeed declares no `design`
key. Disarm justified.

## Verification performed in this review session

Everything below was re-run from the checkout of the reviewed head, not taken from the PR body.

- Full selftest sweep over every `*-selftest.sh` (`-P 4`), **without `SKIP_STRESS`** and with
  `CLAUDE_CODE_SESSION_ID` / `RUN_ID` / `LEAN_RUN_MODEL` unset: **rc=0** (`xargs` propagates a
  non-zero exit under `-P`, so this is the whole-sweep claim).
- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh`: rc=0. `jq empty` over every `*.json`:
  rc=0. `scripts/check-lockstep-pairs.sh`: 17 pairs, 0 failed.
- CI on `e2cf4eb`: `lint-and-selftests` **pass**, `selftests (macos, bash 3.2)` **pass**,
  `pr-gates` fails on **one** line — `no committed verdict record` — which this record answers.
  The PR-lane sweep step ran and printed `PR mode: no in-universe guards touched by
  origin/main...HEAD`, matching the PR body's claim; `tools/mutation-sweep.sh`'s
  `mutation-exclusions.tsv` recursion-guard row is present, and it carries no catalog or
  baseline rows, so no re-anchoring or re-baselining is owed.
- **Independent probe of the guard as a whole**: the phase-5 condition at `:1610` replaced with
  `if false` (mutant `cmp`-verified as applied). Six cases red — `(aj1) (aj2) (aj3) (aj4) (aj6)
  (aj7)`. `(aj5)` correctly stays green, since it is the case that asserts the oracle does *not*
  run. The new block is wired to the feature, not decorative.

## Findings

No blockers.

### Warnings

**W1 — the newly-live exit-contract pair gets no `DROPPED` note in `scripts/lockstep-manifest.tsv`.**
`tools/mutation-sweep.sh`'s "Red only for:" header list and `docs/testing.md`'s named-infra list are
now a coupling this diff edits in lockstep, and CLAUDE.md is explicit: *"When a coupling is real but
not byte-anchorable, record it in that manifest as a **DROPPED** entry with the reasoning, so the
decision is visible rather than forgotten."* The manifest carries 16+ such entries and **none**
mentioning `mutation-sweep`. AC-9 / D-11 decided against a **row**, correctly and for the right
reason — but a `DROPPED` note is a comment block, not a row, so landing one does not violate AC-9;
it is the half that makes the decision visible. Scored a warning rather than a blocker: the coupling
pre-dates this diff, so the omission is inherited debt, and AC-9's letter is met.

**W2 — in seed mode the `pool disagreement` red does not change the exit status.**
`:1667` sets `RC=0` unconditionally before seed's `finish`, so a seed run prints the RED line and
still exits green — AC-2's "the run reds" is literally false there. This is the pre-existing seed
contract (`seed mode: artifacts published, exiting green`) and `(aj6)` codifies `rc=0`, so nothing
regressed; AC-5 is the criterion that governs seed and it is met. Worth one sentence in
`docs/testing.md` so a future reader does not expect seed to red.

### Suggestions (from `unit-test-mutation-reviewer`, verified against the code)

**S1 — the sandbox-freshness invariant has no killing assertion (conf 80).** `sandbox_ensure
$((SANDBOX_N))` (drop the growth) leaves `sandbox_at $((SANDBOX_N - 1))` pointing at the **last pool
sandbox**, the oracle reuses it, and every `(aj)` case still passes — the flaky killer's second
observation kills regardless of which tree it runs in. This is the property AC-1 and the design
comment both call load-bearing (*"the pool is the suspect, so the oracle must not use it"*), and
`tools/mutation-sweep.sh` is excluded from the sweep, so nothing else will ever catch it. Note the
sibling off-by-one *is* caught: `sandbox_at $((SANDBOX_N))` makes `sandbox_at` return 1, the oracle
declines, and `(aj1)` reds. Not scored a blocker — AC-8 enumerates what the case must assert and
sandbox freshness is not on that list, and the shipped code is correct on reading. The cheap fix is
an `obs_sandboxes`-style observation in `make_flaky_fixture` asserting 2 distinct sandboxes.

**S2 — `SUITE_RUNS` accounting is unasserted on the disagreement path (conf 85).** `computed()` is
only checked in `(aj5)`, the path that never reaches `:1304`. Deleting the increment (or making it
`+0`/`+2`) survives every new case, though the comment beside it states a contract. `(ad)`'s updated
"the cold run's 3" is prose, not an assertion.

**S3 — `restore "$guard" "$SB_CUR"` after the oracle is functionally unexercised (conf 80).**
`REVERIFY_SB` is created lazily and **reused** across re-verifies in one run, so dropping the restore
would leak a stale mutation into the next guard's re-verify. No fixture re-verifies two mutants in
one run, so only its absence-of-crash is covered.

**S4 — `[[ -n "$guard" && -f "$blob" ]]` at `:1285` is an equivalent mutant on every fixture (conf
80).** Flipping `&&` to `||` is unobservable. Defensive guard over harness-generated rows; low value,
recorded for completeness.

### Dismissed

`scope-completeness-reviewer` flagged (minor, conf 85) that issue #431's "makes this whole class
self-healing" is not fully delivered, since the lane still reds. Dismissed: the pre-flight ledger
`.claude/pipeline-state/431-ledger.md` is binding input and states *"where a row conflicts with the
issue body, this file wins"*; **D-2** resolves exactly this — *"Report the corrected verdict AND red
the lane with a named `pool disagreement` infra failure… Accepted: the nightly keeps redding while
the race lives — but it names the harness instead of accusing an innocent guard."* The spec carries
it forward under AC-2 and OR-2. The mechanism the issue specified ships verbatim.

`security-reviewer` suppressed three items at conf 30-40, all correctly: `$guard` interpolation and
`$ks` word-splitting mirror the existing pool worker over operator-controlled TSV manifests, and
`WORKER_TOKEN="rv"` is a temp-file discriminator consumed at `:541`, not a credential.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass (approve-with-nits) | 1 | 85 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
| Unit Test Mutation | Advisory (request-changes) | 4 | 80-85 |

## Strengths

- The oracle is placed **inside** the aggregation rather than beside the exit contract, so the
  counts, `survivor_ids`, `TOTAL_SURVIVORS`, the seed baseline and the exit contract are all derived
  from the corrected verdict by construction. AC-6 and AC-5 fall out of that placement instead of
  being patched on — the single design decision that makes the whole change coherent.
- `reverify_survivor` returns 1 on **every** path where it could not answer, so an oracle that
  cannot speak never overturns anything. The failure direction is the safe one.
- The cache-hit exclusion is argued from the right premise: a pool-scored mutant is exactly the set
  whose kill suites this run prechecked green, so feeding an unprechecked suite to the oracle would
  let a broken suite fabricate its own correction.
- `(aj4)` — the reverse direction, that a genuine survivor must be untouched — is not demanded by
  any AC and is the case that stops the gate from becoming a finding-suppressor.
- AC-10 is handled as a declared mid-run amendment with a probe proving the case keeps its strength,
  and the adjacent `model:`-heal question is left explicitly open rather than absorbed.

## Verdict

**approve.** All ten acceptance criteria are satisfied against the diff, and every one was checked
against re-run evidence rather than the PR body. No blockers. W1/W2 are contract-visibility warnings
and S1-S4 are coverage suggestions — none of them is an unmet AC, and none of them makes the shipped
code wrong.

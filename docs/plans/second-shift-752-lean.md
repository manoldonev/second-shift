# second-shift #752 — wholesale mutation audit: shard-6 timeout, cancel files a bug

The monthly wholesale audit has been red on every run since `a95919be`. Seven guards —
`lean-gate.sh` among them — currently get **zero** wholesale mutation coverage, which is the
only lane that sees baseline drift, a verdict flipped by a third file, or a suite edit that
weakened a guard no merge touched.

## What is actually driving it

Round-robin `--shard i/N` balances guard **count**, not cost. A guard's mutants are atomic to
one residue class, so the worst shard is simply whichever one holds the most expensive guard,
and no value of N changes that. `lean-gate.sh` is that guard: it carries **56** of the
catalog's 117 rows — 9x the runner-up (`lean-evidence.sh`, 6) — and its kill set is the single
slowest suite in the tree, `lean-gate-selftest.sh` at 212s.

Measured, from the run history in the issue:

| Run | `lean-gate.sh` catalog rows | `sweep (6)` wall time | Verdict |
| --- | --- | --- | --- |
| `1d714d48` | 36 | 24m25s (54% of the 45-min step bound) | green |
| `a95919be` | 55 | 45m21s | killed at the bound |
| `153188f5` | 57 | 45m18s | killed at the bound |

Marginal cost is therefore ~65s of shard wall time per added row for this guard. Nothing in the
repo prices a new catalog row against the shard's remaining time, and `writing-tests` obliges a
row whenever a guard's code changes — so the bound was crossed by following the contract.

Two facts were established here and are worth recording, because both cut against the intake
ledger's priors:

- **No two of the 56 rows are redundant in any derivable sense.** Applying each row's `sed` to
  the guard yields 56 distinct mutated files at 56 distinct sites, with zero anchor drift.
- **None of the 56 is a known survivor.** `tools/mutation-baseline.tsv` carries 26 `catalog::`
  survivors and not one of them is a `lean-gate.sh` row, so every one of the 56 is presently
  killed and is doing its job.

The prune below therefore deletes live, non-redundant coverage. That is the accepted cost of
OR-1's chosen direction, not an oversight.

## Acceptance criteria

- **AC-1** — `tools/mutation-catalog.tsv` carries at most **36** rows whose guard is
  `plugins/dev-pipeline/skills/build-lean/lean-gate.sh`, down from 56. Exactly the 20 rows named
  in *Rows removed* below are removed; no other row in the file is added, removed or edited.
- **AC-2** — `tools/mutation-sweep-selftest.sh` reds when any single guard carries more than 36
  catalog rows, and the refusal names both the guard and its row count. At exactly 36 it does
  not red.
- **AC-3** — AC-2's check is exercised against a **fixture** catalog, not only against the real
  tree: one case at 37 rows for a single guard asserting the red, one at 36 asserting silence.
  A real-tree-only lint cannot fail today for any reason a reader of the diff would not already
  see, and it would go quietly dead the moment its parsing broke.
- **AC-4** — `docs/testing.md` states the cap, its value, its derivation, and that a row count is
  a proxy for the quantity that actually breaks the shard (`rows x killer-suite seconds`).
- **AC-5** — `tools/mutation-catalog.tsv`'s own header states the cap and the obligation it
  creates: a guard already at the cap must retire a row before it gains one.
- **AC-6** — `.github/workflows/mutation-sweep.yml` records OR-2's decision at the
  `file-audit-red` condition: the `cancelled` match stays broad, an operator-cancelled dispatch
  will therefore keep filing a false digest, and the reason the obvious narrowing is declined.
  **No behavior change** — this is a decision of record.
  *Amended after round 1*, which read "…the reason the obvious narrowing does not separate the
  two cases". That clause presupposed a mechanism measurement falsified (D-7): the narrowing does
  separate them. The obligation is unchanged in kind — the recorded reason has to be the true one.

## The cap: why 36

36 is not a preference. It is the largest `lean-gate.sh` catalog size ever observed to complete
inside the shard's 45-minute step bound — the `1d714d48` run above, at 54% of it. Choosing a
lower number would be inventing headroom no measurement supports; choosing a higher one would
extrapolate past every observation the repo has.

The file lands **exactly at** the cap by construction. That is deliberate: the next row for this
guard must retire one, which is the forcing function OR-1 asked for.

What the cap does **not** bound, stated so a reviewer does not read more into it: the other six
guards in shard 6 have grown since `1d714d48`, and the generic tier grows with the guard. This
bounds one guard's catalog, which is what OR-1 chose; it does not bound a shard.

## The prune criterion

`writing-tests`: *a register row earns its keep by naming the regression class it alone catches*.
All 56 do. So the criterion has to be about which classes are worth 65s of a bounded shard, and
the one applied here is:

> **Remove the row when the mutant it arms leaves the gate still refusing** — it moves which
> message, which counter or which milestone the refusal names, not whether the refusal happens.
> **Keep the row when the mutant makes the gate stop refusing**, destroy evidence, or destroy
> data.

The removed classes are real regressions. Their cost is an operator reading a refusal that names
the wrong thing, or a lane that over-refuses; the retained classes are the ones where a survivor
means something walks the gate and ships. Three rows are removed on a second ground, noted below:
a sibling row retained here already covers the shape, or a second suite outside the kill set
asserts the same class.

### Rows removed

| id | Class removed | Ground |
| --- | --- | --- |
| `lean-gate-zerolane-milestone` | fix budget charged to a milestone that did not fail | still refuses |
| `lean-gate-absent-as-attempt` | absent-spec red charged an attempt | still refuses |
| `lean-gate-runid-heal` | progress header frozen at `unset`; reconcile over-reds | fail-closed |
| `staleness-advance-is-the-trigger` | base arm fires on every run; lane unusable | fail-closed |
| `lean-gate-fidelity-evidence-column-superset` | header message never fires; cell-count arm still reds | still refuses |
| `lean-gate-fidelity-evidence-absent-spec` | catch-all arm refuses in different words | still refuses |
| `lean-plan-arm-uncalled` | translation-plan arm never called | also killed by `scenario-liveness-selftest.sh` |
| `lean-plan-empty-cell-waived` | empty `why this component` cell waived | finest arm; `no-data-row` + `measured-columns` retained |
| `lean-plan-delimiter-arm-waived` | delimiter row not treated as one | `no-data-row` arm reds the single-row case |
| `lean-gate-panel-token-anchors` | panel membership becomes a substring test | latent: no shipped reviewer name contains another's |
| `lean-openregions-heading-depth` | heading-per-region section reads as empty | shape no shipped artifact emits |
| `lean-openregions-content-test-via-pipe` | `SIGPIPE` fail-open above one pipe buffer | needs a >64KB Open Regions section |
| `lean-gate-design-disarm-writer-drops-ref` | accepted disarm stamped with no ref | unbacked disarm still refused by the retained sibling |
| `lean-gate-plan-review-self-staling` | plan-review binding unsatisfiable | fail-closed |
| `lean-gate-plan-review-writer-qualifies-reviewer` | every armed run reds as malformed | fail-closed |
| `lean-gate-plan-review-quotes-the-heading` | refusal quotes `## Findings`, not the finding | still refuses |
| `lean-measure-missing-node-arm-waived` | refusal names a size instead of the harness | still refuses |
| `lean-measure-missing-node-budget` | missing-node red moved to the absent budget | still refuses |
| `lean-measure-px-separator-waived` | refusal names the wrong defect on a prose `px` cell | still refuses |
| `lean-gate-scorecard-writer-silent` | write-time layer silent; merge boundary intact | the row's own note calls it an economics regression, not a fail-open |

Every removed row stays recoverable from this commit's parent — nothing is rewritten, and the
ids above are the whole restore list.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Cause of run 33425839962's wholesale cancellation | Operator cancelled a duplicate dispatch (two `workflow_dispatch` runs 35s apart at `a95919be`); the 76-guard digest is a false red | user-answered |
| D-2 | Ticket scope: shard-6 timeout only, or both faults | One ticket covering both the shard-6 timeout and the operator-cancel false red | user-answered |
| D-3 | Whether the off-baseline survivor `lean-evidence.sh::cmp-eq::a6021e53b187` belongs in this ticket | Out of scope — #760 already owns it under the merge-time lane's separate dedup key (`.github/workflows/mutation-merge.yml`) | codebase-derived |
| D-4 | Whether the issue title may be freely rewritten | No — it must retain the literal prefix `mutation wholesale audit red`; dedup is `startswith` over open titles (`.github/workflows/file-issue-on-red.yml:77`) | codebase-derived |
| D-5 | Whether raising the shard count resolves the timeout | It does not — a guard's mutants are atomic to one residue class, so no N moves them off one shard. CORRECTED here: the ledger's supporting figure (that `lean-gate.sh` alone exceeds the bound at any N) was an over-estimate. Killers are reaped at first `FAIL:`, and the guard's catalog DID fit at 36 rows in 24m25s. The conclusion stands on atomicity; the arithmetic behind it does not | codebase-derived |
| D-6 | How the audit bounds a single guard's sweep cost | OR-1 resolved by the operator: direction D — prune the redundant `lean-gate.sh` rows and add a lint capping rows per guard. A, B and C are ruled out on the record | user-answered |
| D-7 | Whether `file-audit-red` should separate operator-cancel from runner-death-cancel | OR-2 resolved by the operator: no — leave the `cancelled` match as is. CORRECTED here, on the measurement the resolution itself asked for before anyone revisits the region: the supporting claim (a shard killed at its step bound resolves `cancelled` at the JOB level, so `!cancelled()` would preserve the very case it appears to fix) is false. Measured, a step-bound kill resolves `failure` — runs 33488186736 and 33425785614, `sweep (6)` at ~45m, `merge` `failure` — which is also what this workflow's own STEP-vs-JOB note has said all along, while the operator-cancelled run resolves `cancelled` at the RUN level (33425839962), so a run-level `!cancelled()` would suppress exactly it. The decision stands on what the narrowing RISKS rather than on what it misses: whether a lost runner makes run-level `cancelled()` true is unmeasured, and if it does, the narrowing loses a whole audit to buy back a diluted digest | user-answered |
| D-8 | Build model sizing | `opus` — two `pause-and-ask` regions remain open, one of them (OR-1) an architectural call that moves the deterministic shard partition the merge job's completeness accounting rests on; the builder must decide a strategy, not execute a resolved one | user-delegated |
| D-9 | Cap value | 36 — the largest catalog size for this guard measured inside the step bound. Not a round number chosen for headroom | codebase-derived |
| D-10 | Cap shape: flat row count vs cost-weighted (`rows x killer seconds`) | Flat row count, as OR-1 specifies. A cost-weighted cap is the more faithful model but needs a killer-suite timing for every guard, and `tools/selftest-suite-timings.tsv` tables only the slow ones — so it would fail open on most of the universe while costing more code than the prune saves | codebase-derived |
| D-11 | Where the cap lint lives | `tools/mutation-sweep-selftest.sh` case (k), beside the catalog's existing shape lints. A standalone `scripts/check-*.sh` would itself be in-universe and would add mutants to the very sweep this ticket is bounding | codebase-derived |

## Out of scope

- The off-baseline survivor `lean-evidence.sh::cmp-eq::a6021e53b187` (D-3) — #760 owns it.
- Raising the 45-minute step bound (OR-1 direction A), a cost-aware partition (B), and a
  per-guard mutant budget (C). All three were considered and declined on the record.

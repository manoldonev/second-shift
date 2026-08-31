# #721 — an opt-in `--verdict-log` makes the sweep's per-mutant kill data readable

The sweep can say which mutants **survive** and cannot say which suite **kills** one — a plain
kill increments a counter and its id is discarded, so no argument about a generic operator's
worth has ever been checkable against real numbers. This adds an opt-in `--verdict-log <path>`
to `tools/mutation-sweep.sh` that streams one TAB-separated row per scored mutant (id, verdict,
killer suite) and wires it into `mutation-sweep.yml`'s two shard invocations. Instrument and
measurement only — no operator or baseline row is deleted here; that re-enters as a follow-up
under #717, authored against the numbers this produces. Part of #717.

## Decision Ledger

Carried from the pre-flight ledger at `.claude/pipeline-state/721-ledger.md` (16 rows, 1 open
region); ids and Resolutions are its own, corrected mid-interview against #740's topology move.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which of the three cuts #721 becomes | Cut (3): build the kill log. Retiring the `default` operator was rejected on measurement — it enumerates 315 sites across 45 of 76 non-excluded guards, applying ~78 mutants at k=2 against 32 baseline survivors, so ~46 of its mutants are KILLED. Retiring it would delete real coverage to save 32 rows of report-only noise. | user-answered |
| D-2 | Does #721 also perform the deletion | No. Instrument plus measurement only; the measure-then-delete cut re-enters as a follow-up under epic #717, authored against real figures. A single PR would need a conditional deletion AC, which is what sank the earlier cut. | user-answered |
| D-3 | Shard wiring under the 10-way full-universe sweep | Shard-local. Each shard writes its own log into its existing `mutation-sweep-shard-N` artifact; `mutation-sweep.yml` passes the flag at both shard invocations. That workflow is now the MONTHLY drift backstop rather than a nightly, which does not change the wiring. No `--mode merge` arm — a third merged output would need the report's truncation-detection story, growing the guard mass #717 exists to ratchet down. | user-answered |
| D-4 | How the canonical measurement is obtained | Operator dispatches `mutation-sweep.yml` after merge, concatenates the ten shard logs, and posts per-operator kill counts on #717. Waiting for the cron is no longer a fallback: post-#740 that workflow fires monthly, so the dispatch is the only timely route to whole-universe numbers. Build ACs cover the instrument only. A local sweep was rejected: the cache is advisory-lane-only with a key documented as unsound in this tree, and mutation-sweep.sh:205-214 states a stale entry can only make a LOCAL run optimistic — biasing kill counts upward, the exact direction that would falsely argue for keeping an operator. | user-answered |
| D-5 | Which mutant tiers the log covers | Both. Generic ids and catalog ids alike; the tally loop is already tier-agnostic, so filtering costs a branch rather than saving one. | user-answered |
| D-6 | Log record shape | TAB-separated: mutant id, verdict, killer suite. Killer is `-` for survivors, mirroring the verdict record composed at mutation-sweep.sh:1592 and :1594. | codebase-derived |
| D-7 | Where the logged data comes from | No new computation. The tally loop at mutation-sweep.sh:2100-2117 already holds `sid` and reads `vsuite` out of the verdict file. | codebase-derived |
| D-8 | Correctness under a cache hit | A cache hit writes the full record, killer suite included, straight to the verdict file at mutation-sweep.sh:1930, so a cached kill still logs its killer. | codebase-derived |
| D-9 | Flag shape and lane reach | Opt-in path flag, mode-agnostic, inert unless given — matching the existing `--report` / `--baseline-out` / `--slow-out` family. The PR-mode lane at ci.yml:228 passes no such flag and is therefore unaffected. | codebase-derived |
| D-10 | Unwritable or unopenable log path | Hard `red`, matching the report sink's own or-red guard at mutation-sweep.sh:830. Never a silent skip. | codebase-derived |
| D-11 | Selftest obligation | Covered by the paired `tools/mutation-sweep-selftest.sh`. CLAUDE.md requires every checked-in script be exercised by some selftest, and the `writing-tests` skill binds a new flag contract. | codebase-derived |
| D-12 | Accepted cost of editing the sweep | The next sweep runs fully cold: `SELF_SHA` is an input to `cache_key` at mutation-sweep.sh:659-661. Documented and accepted at :655-658. | codebase-derived |
| D-13 | Whether the log carries its own completion marker | parked under OR-1 (owner: build run, at implementation time) | deferred |
| D-14 | Console announcement | One `info` line naming the log path, consistent with how the sweep announces its other sinks and timings. | codebase-derived |
| D-15 | Documentation home | `docs/testing.md`, which owns the sweep contract per CLAUDE.md's testing pointer. | codebase-derived |
| D-16 | Whether the merge-time lane also writes a log | No. #721 wires `--verdict-log` into `mutation-sweep.yml`'s shard steps only. `mutation-merge.yml` runs `--mode pr --base $BASE`, so it sees only the merge's own diff — partial per-operator data that cannot answer the tier's kill rate. The flag is opt-in and mode-agnostic per D-9, so it works there whenever someone wants it. | user-answered |

### OR-1 (resolved by this build, per its reversible-default disposition)

No separate completion/truncation marker on the verdict log. The shard artifact already carries
the sweep's own `mutation-complete` marker semantics, so a log truncated by a shard death is
already detectable at the shard level; adding a dedicated marker later is additive and re-keys
nothing.

## Design

Design: none — this is a shell-flag and CI-wiring change with no web surface, and this repo
configures no `design.provider`.

## Acceptance criteria

- AC-1: `--verdict-log <path>` is accepted in every mode (`full`, `pr`, `merge`), is opt-in, and
  is inert when omitted — an ordinary run's exit code and report are unaffected by its absence.
  `ci.yml`'s `mutation-sweep-pr` and `mutation-merge.yml` pass no such flag and stay unaffected.
- AC-2: When given, the log is a header row (`mutant_id\tverdict\tkiller_suite`) followed by one
  TAB-separated row per scored mutant, for both tiers (generic and `catalog::` ids). The killer
  suite is `-` for a survivor and the real killer's relpath for a kill.
- AC-3: An unwritable or unopenable `--verdict-log` path is a hard red (matching the `--report`
  sink's own or-red guard), never a silent skip.
- AC-4: A verdict served from the cache logs its real killer suite, not a blank — including a
  survivor corrected to `killed` by the serial pool-disagreement re-verify, which logs the
  corrected verdict and suite.
- AC-5: `mutation-sweep.yml` passes `--verdict-log sweep-out/mutation-verdict-log.tsv` at both
  shard invocations (seed and non-seed), landing inside the same `sweep-out/` directory the
  shard's `mutation-sweep-shard-N` artifact already publishes — no separate upload step needed.
- AC-6: Covered by `tools/mutation-sweep-selftest.sh`; the flag's contract (shape, both tiers,
  cache-hit correctness, the hard-red path) is documented in `docs/testing.md`.
- AC-7: `feat(dev-pipeline):` commit verb — new capability, not a bugfix or refactor — with a
  `Changelog:` trailer. No `plugin.json` `version`, `CHANGELOG.md`, or marketplace `version` edits.

## Implementation notes (non-binding detail, subordinate to the ACs above)

1. `tools/mutation-sweep.sh`: new `VERDICT_LOG=""` var and `--verdict-log` arg-parse case,
   alongside `REPORT_OUT`/`BASELINE_OUT`/`SLOW_OUT`. Header written (or-died) beside the existing
   `REPORT_SINK` header write. One row appended per scored mutant in the PHASE 5 aggregation loop,
   right after the pool-disagreement correction settles `verdict`/`vsuite`, using the `sid` already
   in scope — no new computation, and `vsuite` is already `-` for an ordinary survivor by
   construction. One `info "verdict log -> $VERDICT_LOG"` line in `finish()`.
2. `.github/workflows/mutation-sweep.yml`: add `--verdict-log sweep-out/mutation-verdict-log.tsv`
   to both the seed and non-seed `sweep shard` step invocations. No change to the `publish shard
   artifact` step — it already uploads the whole `sweep-out/` directory. No change to the merge
   job, per D-16.
3. `docs/testing.md`: a paragraph in the "Test-the-tests" section documenting the flag, its shape,
   both-tiers coverage, the cache-hit guarantee, the hard-red path, and the operator's manual
   concatenate-the-ten-shard-logs route (D-4) — placed beside the existing lane table.
4. `tools/mutation-sweep-selftest.sh`: a new case exercising — inertness (identical rc with and
   without the flag), header + row shape for both a killed generic id and a survived catalog id
   (killer `-`), a cache-hit run logging its real killer, and an unwritable path reding by name
   with the `cannot write the verdict log` message.

## Out of scope

Any deletion of operators or baseline rows (re-enters under #717, authored against this
instrument's numbers). `mutation-merge.yml` wiring (D-16). A dedicated completion/truncation
marker for the verdict log (OR-1, deferred with a stated reversible default).

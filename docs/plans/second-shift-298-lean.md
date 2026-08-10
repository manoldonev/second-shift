# second-shift #298 — mutation sweep: stale cost comment, and a timed-out shard destroys its own evidence

## Problem

Two independent defects in the nightly mutation sweep, both about *evidence*:

1. `.github/workflows/mutation-sweep.yml` sizes its sharding decision against
   `~4-9 min each`. No shard has been under 12 minutes in any recent nightly. The
   comment is the artifact a future reader sizes the next sharding or timeout
   decision against, and it is roughly 2x optimistic.
2. A shard's report is buffered in a `mktemp` file and copied to the artifact path
   only in `finish()`. A shard that dies before `finish()` therefore publishes
   nothing — the shard most worth diagnosing yields the least. `publish shard
   artifact` is `if: always()`, but a job torn down at `timeout-minutes` is a
   cancellation, and whether `always()` survives that is disputed (see OR-1).

The pre-flight ledger at `.claude/pipeline-state/298-ledger.md` is binding input;
D-1..D-9 and OR-1/OR-2 below are its decisions, restated where they constrain the
build.

## Measured

Per-shard wall time, computed from the `sweep (N)` jobs of each nightly run
(`gh api repos/manoldonev/second-shift/actions/runs/<id>/jobs`):

| nightly | worst shard | median shard |
| --- | --- | --- |
| 2026-08-04 | 26.0 min | 6.6 min |
| 2026-08-05 | 29.1 min | 6.6 min |
| 2026-08-06 | 15.2 min | 3.8 min |
| 2026-08-07 | 12.7 min | 3.8 min |
| 2026-08-08 | 16.0 min | 5.0 min |
| 2026-08-09 | 13.8 min | 4.4 min |
| 2026-08-10 | 16.1 min | 5.6 min |

The step change lands between the 2026-08-05 and 2026-08-06 nightlies; #384 merged
on 2026-08-05. The coincidence is **measured**; #384 *causing* it is **inferred from
the timing alone**, not profiled. The post-#384 window is five nightlies:
worst shard 12.7–16.1 min, median shard 3.8–5.6 min.

Job-level `timeout-minutes: 60` is **out of scope** (D-5): 16 min is ~27% of the
budget and no shard has been cancelled in fourteen consecutive runs. D-3's
step-level bound is a separate knob, not a re-litigation of that one.

## Acceptance criteria

**AC-1 — the per-shard cost comment is re-derivable, not just re-stated (D-2).**
The `jobs:`-level comment in `.github/workflows/mutation-sweep.yml` replaces
`~4-9 min each` with the measured worst-shard and median-shard ranges, the date
window they were measured over, and the command that re-derives them from the
nightly job durations. A bare figure rots again — `~4-9 min` did, within five days
of #384 — so the pointer to the source is part of the criterion, not decoration.

**AC-2 — the report is streamed to `--report`, not copied at the end (D-1).**
`tools/mutation-sweep.sh` makes `--report <file>` the sink itself: the header and
every `emit_row` row land on that path as they are computed, so the report exists
from the sweep's first moment and a killed run still publishes an artifact rather
than an empty directory the upload step reds on (`if-no-files-found: error`). The
`mktemp` buffer survives only as the fallback when `--report` is unset, where
`finish()` still prints it to stdout and removes it. `finish()` no longer copies.
Report *content* for a run that reaches `finish()` is unchanged in every mode,
merge included.

Stated precisely, because the ledger's D-1 phrasing ("a shard can die between its
first verdict and its last") is optimistic about the current architecture: swept
guards' rows are emitted in PHASE 5, which runs only after the whole worker pool
completes. A shard killed *during* the pool — the actual timeout failure mode —
therefore publishes the header plus shard 1's excluded-guard bookkeeping rows and
no verdicts. Its per-mutant evidence is in the job **log**, which survives because
of AC-3. AC-2 and AC-3 are complementary; neither alone is the fix, and the code
comment says so rather than letting a later reader over-read the streaming.

**AC-3 — the `sweep shard` step carries its own time bound (D-3).**
`.github/workflows/mutation-sweep.yml` gives the `sweep shard` step a
`timeout-minutes` of ~45. Exceeding it is then an ordinary *step* failure, under
which the job proceeds to its `if: always()` steps and `publish shard artifact`
unambiguously runs — rather than a job cancellation whose semantics are OR-1. The
comment states that this is why the bound exists, so a later reader does not
"simplify" it away as redundant with the job-level 60.

**AC-4 — a truncated shard is distinguishable from a complete one (D-4, D-6).**
`finish()` writes a completion marker beside the report in its output directory.
The name is **non-dotted** (D-6: `upload-artifact@v4` excludes hidden paths unless
`include-hidden-files` is set, and a `.sweep-out` path once matched nothing while
reporting success). Merge mode then:

- names every shard that published a report but no marker, as a red, saying its
  rows are partial;
- keys its seed-arity check (`N shard report(s) but M baseline(s) — mixed seed and
  enforcing shards`) on **completed** shards only, since a shard killed before
  `finish()` never wrote its baseline and would otherwise be misdiagnosed as a
  mode mismatch.

Existing merge reds (`merge incomplete`, `merge overlap`, header mismatch) are
unchanged.

**AC-5 — the residual gap is stated where the mechanism is (OR-2).**
The workflow's sharding comment records that streaming rescues evidence only from
the class where the job still finalizes. The 83-84 minute "the hosted runner lost
communication with the server" deaths execute no step at all, so the streamed
report dies on the runner with everything else; no in-job mechanism reaches that
class. Stated so the next reader does not mistake partial-evidence coverage for
total coverage.

**AC-6 — the new behavior has cases in the sweep's paired suite (D-7).**
`tools/mutation-sweep-selftest.sh` gains cases that fail if AC-2 or AC-4
regresses: the `--report` path already carrying its header while killers are still
running, observed by a fixture killer rather than by timing (streaming, not a final
copy); the completion marker absent at that same moment and present once the run
finishes, and never written at all without `--report`; the truncated-shard red
naming the shard; and the seed-arity check keyed on completed shards, with a real
mode mismatch still reding so the check is not merely disabled.
`tools/mutation-sweep.sh` is a
`mutation-exclusions.tsv` row (the harness never sweeps itself), so this diff
re-keys no generic survivor ordinals and `tools/mutation-baseline.tsv` is
untouched.

**AC-7 — docs (doc-scoped, per CLAUDE.md).**
`docs/testing.md`'s account of the killer time bound describes a timed-out shard as
yielding "no artifact". That stays true as history but becomes wrong as a
description of the current mechanism, so the section records what a shard now
leaves behind when it hits a bound, and the OR-2 class it still does not cover.

## Out of scope

- Job-level `timeout-minutes: 60` (D-5) — dropped at intake against measurement.
- Resolving OR-1 (does `if: always()` run on job cancellation). D-3 routes around
  the question rather than answering it; resolving it would require deliberately
  timing out a shard. Reversal is a one-line workflow knob.
- Any mechanism for OR-2 (out-of-band / incremental publication for the
  lost-communication class). Larger than this ticket; AC-5 states the gap instead.
- Streaming per-mutant verdicts into the output dir so a pool-time death publishes
  structured evidence rather than only the log. The receipt's D-1 chose the report
  sink; this is a different mechanism it did not cover, and the log already carries
  that evidence once AC-3 keeps the job alive. Named here so the gap is a recorded
  decision rather than an oversight.

## Design

Design: none — no `design.provider` is configured for this repo, and the change is
a shell harness plus a CI workflow comment; there is no rendered surface.

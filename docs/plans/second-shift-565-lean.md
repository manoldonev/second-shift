# perf-retro: derive the lean timing profile from milestone timestamps (#565)

Give the lean lane a timing profile derived from the artifacts it already writes, so "fast" is
a measured claim instead of an impression. Nothing new is recorded on any lane: every number
comes from `{issue}-lean-progress.md` records already on disk.

## What lands

1. A `timing` subcommand on `plugins/dev-pipeline/tools/retro-corpus.sh`, sharing `corpus`'s
   state-dir resolution, record selection, window and `--json` semantics.
2. `plugins/dev-pipeline/skills/perf-retro/SKILL.md` Steps 2 and 3 rewritten against the flags
   the tool actually emits, and the dead "state helper" hard rule replaced.
3. The D-36 perf-corpus half annotated as superseded at every site that still asserts it.
4. `retro-corpus-selftest.sh` cases for AC-1 … AC-15, plus a `scripts/lockstep-manifest.tsv`
   row pinning `iso_to_epoch` against its `pipeline-cost-block.sh` original.

## Acceptance Criteria

- **AC-1:** `retro-corpus.sh timing` emits one row per artifact-schema record, selected by the
  same structural `verdict_record:` test `corpus` uses, honouring `--window`, `--json` and
  `--state-dir` with the same semantics and exit codes (`0` enumerated, `2` usage/environment).
  `stem` is the record basename, `ticketKey` the record's `issue:` key, `startedAt` its first
  timestamped row; rows sort newest-first on `startedAt` before the `--window` slice.
- **AC-2:** `spans` covers milestones **1 through 4 only**. The span of milestone N is
  `satisfied(N)` minus the most recent `satisfied` of any lower-numbered milestone, or minus the
  record's first timestamped row when no lower milestone was satisfied. Each span is floored to
  whole minutes. A milestone with no `satisfied` row is absent from `spans`, not zero.
- **AC-2b:** `spans` NEVER contains a milestone-5 entry. Milestone 5 is close-out bookkeeping
  following the run's defined end (AC-4).
- **AC-3:** `satisfied(N)` is the record's single `| milestone-N | satisfied` row; no rule
  selects a "last" or "latest" occurrence, because the gate appends at most one.
- **AC-4:** WHEN a record carries `milestone-4 | satisfied` THEN `wallClockMin` is the interval
  from the record's first timestamped row to that stamp, floored to whole minutes.
- **AC-5:** WHEN a record carries no `milestone-4 | satisfied` row THEN `wallClockMin` and
  `reverifyMin` are null, every span the record does bracket is still emitted, and the record is
  flagged `truncated-record` if it has no `milestone-4` row at all, or `unterminated` if it has
  one or more non-satisfied `milestone-4` rows.
- **AC-6:** `wallClockMin` does NOT fall back to PR merge time, PR approval time, git metadata,
  file mtime, or the record's last row when the terminal marker is absent.
- **AC-7:** WHEN `wallClockMin` is non-null THEN `reverifyMin` is the summed interval, floored,
  from each milestone's `satisfied` row to the last `concluded` row for that same milestone that
  follows it; where no such row follows, that milestone contributes nothing. `reverifyMin` is a
  diagnostic and is NOT part of any sum with `spans`.
- **AC-7b:** `reverifyMin` is null on records carrying no `concluded` rows — every `old-grammar`
  record — and this is stated in the field's own documentation rather than left as a silent zero.
- **AC-7c:** No field asserts an exact equality between `sum(spans)` and `wallClockMin`.
- **AC-8:** WHEN any `| milestone-N | started` or `| milestone-N | concluded` row is timestamped
  strictly after that milestone's `satisfied` row THEN the run is flagged `re-run`, and no span
  changes as a result.
- **AC-9:** WHEN a record uses only the pre-`started`/`concluded` grammar THEN AC-2 and AC-4
  still produce values while AC-7 yields null (AC-7b), the run is flagged `old-grammar`, and no
  gate-call-latency field is emitted for any run.
- **AC-10:** `rounds` is the maximum `N` over every `round=N` token in the record, matched
  anywhere on the line rather than only on timestamped rows. WHEN the record carries no `round=`
  token THEN `rounds` is null.
- **AC-11:** `rounds` is NOT derived by counting `milestone-4 | attempt`, `started`, or
  `verdict=` rows.
- **AC-12:** WHEN a spawn transcript matching `<state-dir>/{issue}-lean-spawn-*.log` exists, in
  the same state dir resolved for the records, THEN `orchestrated` is `orchestrated`; otherwise
  it is `indeterminate`.
- **AC-13:** `orchestrated` is NEVER set to `manual`. The value is reserved in the documented
  enum and emitted by nothing until OR-1 lands a positive discriminator.
- **AC-14:** WHEN the interval from a record's first timestamped row to its
  `milestone-4 | satisfied` row exceeds 24 hours THEN `over-24h` is flagged. The trigger is that
  measured interval, not the span of the whole record.
- **AC-15:** WHEN `model:` is absent or reads `unknown` THEN `model` is emitted as `unknown` and
  `unknown-model` is flagged. `model` is NOT used to bucket, filter, or gate any aggregate, and
  no vendor model string appears in the implementation.
- **AC-16:** `retro-corpus.sh corpus` and `open-prs` stdout is byte-identical to the pre-change
  output, in both TSV and `--json` form, for every fixture in the existing suite.
- **AC-17:** `retro-corpus.sh -h`/`--help` prints a usage block including the `timing`
  subcommand and its options, and the output still stops at the header block.
- **AC-17b:** The header block, the `sed -n '2,40p'` window and `retro-corpus-selftest.sh`'s
  `HELP_LINES` bound are amended **together**, preserving the invariant the assertion guards:
  the line immediately following the printed window is `set -uo pipefail`. The sibling
  `! grep -qF 'set -uo pipefail'` leak check is NOT weakened or removed.
- **AC-18:** `perf-retro/SKILL.md` Step 2 no longer names `pauseSpans[]`, `pipelineSessions[]`,
  or the run's `.mode` as fidelity signals; its signals are the `fidelity[]` flags this tool
  emits.
- **AC-19:** `perf-retro/SKILL.md` Step 2 states which flags exclude a run from which aggregate
  — at minimum that `over-24h` and `no-chronology` exclude a run from wall-clock aggregates while
  its spans remain usable, and that `re-run` excludes a run from NEITHER — and Step 3 sources
  per-run time from `retro-corpus.sh timing`. Its hard rule no longer attributes durations to
  "the state helper".
- **AC-20:** WHEN `perf-retro` runs against a corpus containing only artifact-schema records THEN
  Step 3 renders a populated profile table, not "not applicable" and not an empty table.
- **AC-21:** Every site asserting D-36's perf-corpus exclusion records that the corpus half is
  superseded: `plugins/dev-pipeline/cost-tracking-setup.md` (both sites), the D-36 comments in
  `plugins/dev-pipeline/tools/pipeline-cost-block.sh`, and the ratified ledger row at
  `docs/plans/acme-303.md:94` — the last **annotated as superseded by this issue, not rewritten**.
- **AC-22:** The change modifies no executable line of `pipeline-cost-block.sh`, and
  `cost-block-selftest.sh` is not modified at all; its AC-8 still passes unmodified.
- **AC-23:** `git diff --stat` names no file under `skills/build-lean/`, `skills/review-lean/`,
  `skills/run-lean/`, or `lean-gate.sh`.
- **AC-24:** The implementation uses no `declare -A` and no bash-4-only construct; it runs under
  stock macOS `/bin/bash` 3.2.
- **AC-25:** ISO-8601-to-epoch conversion uses the BSD/GNU dual form **with** `-u` on the BSD
  arm, matching `pipeline-cost-block.sh`'s `iso_to_epoch`, and a `scripts/lockstep-manifest.tsv`
  row pins the two copies against each other.
- **AC-26:** `retro-corpus-selftest.sh` gains cases covering AC-1 through AC-15, driven by
  fixtures containing at least one record of each grammar generation, one truncated record, one
  `unterminated` record, one `re-run` record, one `over-24h` record, one `no-chronology` record,
  one record with a matching `*-lean-spawn-*.log` and one without, and one record with an
  un-timestamped `round=N` row.
- **AC-27 (doc):** `docs/testing.md` needs no edit — no new tier, no new suite, no new cache row.
  The change adds cases to an existing per-tool suite and one lockstep row, both already
  described there. This AC records the check, not an edit.

## Data contract

`retro-corpus.sh timing [--window N] [--state-dir <dir>] [--json]`

| Field | Type | Notes |
| --- | --- | --- |
| `stem` | string | record basename |
| `ticketKey` | string | the record's `issue:` key |
| `startedAt` | ISO-8601 UTC or null | the record's first timestamped row |
| `wallClockMin` | integer or null | floored; null per AC-5 |
| `spans` | object | milestones 1–4 only, floored; never-satisfied milestone absent |
| `reverifyMin` | integer or null | floored diagnostic, outside every sum |
| `rounds` | integer or null | `max(round=N)` |
| `orchestrated` | enum | `orchestrated` \| `indeterminate`; `manual` reserved, never emitted |
| `model` | string | passed through from the record; `unknown` when absent |
| `fidelity` | array | `truncated-record`, `unterminated`, `re-run`, `over-24h`, `no-chronology`, `unknown-model`, `old-grammar` |

Default (no `--json`) is one tab-separated line per run, no header row:

```
ticketKey  wallClockMin  spans  reverifyMin  rounds  orchestrated  model  fidelity
```

`spans` encodes as comma-joined `N=<min>` pairs in milestone order; `fidelity` as comma-joined
flags. A null scalar, an empty `spans` and an empty `fidelity` all render as `-`.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Per-milestone span basis | `satisfied(N)` minus the most recent lower milestone's `satisfied`; first span from the record's first row. Chosen over `started`→`concluded`, which measures ~1s gate calls on ~9 records | user-answered |
| D-2 | Terminal marker for the run | `milestone-4 \| satisfied` (n=23, both grammars). Amended mid-interview from `verdict=approve` (n=11, old grammar only) after census | user-answered |
| D-3 | The 27 records that never reach milestone 4 | Excluded from wall-clock, spans retained, each a Step 2 fidelity finding; never repaired by inference | user-answered |
| D-4 | Where the derivation lives | New `timing` subcommand on `retro-corpus.sh`; `corpus`/`open-prs` stdout byte-stable | user-answered |
| D-5 | D-36 disposition | Corpus half superseded here; cost-log-row half left to #546 | user-answered |
| D-6 | Manual-vs-orchestrated split | Three-valued; absence of a spawn transcript never implies manual | user-answered |
| D-7 | Consumer scope | `perf-retro` SKILL.md Steps 2-3 and the dead hard rule rewritten in this ticket | user-answered |
| D-17 | Time not covered by any span | Surfaced explicitly rather than lost | user-answered |
| D-18 | The `pipeline-cost-block.sh:770` fence | Narrowed to executable lines; the D-36 comment is this ticket's | user-answered |
| D-19 | How churn is surfaced (supersedes D-17's mechanism) | `unattributedMin` dropped, it provably measures ~0 under D-1's tiling, replaced by `reverifyMin`, outside every sum | user-answered |
| D-8 | Guard home | `retro-corpus-selftest.sh` — the per-tool behavioral tier | codebase-derived |
| D-20 | Help-window contract | Window, header block and the line bound move together; the invariant is that the next line is `set -uo pipefail` | codebase-derived |
| D-24 | `model` normalisation | Passed through verbatim, never mapped — AC-15 forbids a vendor model string in the implementation, and a mapping table is one | codebase-derived |
| D-25 | AC-21's site count | The ticket named four sites by stale line number; the tree carries five (two D-36 comments in `pipeline-cost-block.sh`). All five are annotated — leaving one asserting a superseded claim is the defect AC-21 exists to close | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | A positive discriminator for a manually-run lean run | reversible-default-and-flag — `manual` reserved and unemitted; no manual-vs-orchestrated aggregate ships |
| OR-2 | Record truncation — milestones 4–5 append to no record | reversible-default-and-flag — flagged `truncated-record`, nothing derived from the gap; filed as a follow-up at close-out |

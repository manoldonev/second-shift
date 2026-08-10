# 289 — The retro corpus counts a ticket once, whichever operator rename its snapshots carry

`retro-corpus.sh corpus` enumerates stage-schema rows by `has("stages")` minus the two
statectl-written quarantine families (`*-stale-*`, `*-released-*`). Operator-made top-level
renames — `{key}-failed-{ts}.json` and friends — are not in either family, keep their `stages`
key, and aggregate as their own run alongside the ticket's live `{key}.json` re-run. One ticket,
two corpus entries. `stage-envelopes.sh` already solved this structurally and `perf-retro`'s
Step 1 already carries the scope line saying this step adopts that rule when #289 lands; this
ticket makes it true.

Pre-flight receipt: `.claude/pipeline-state/289-ledger.md` (binding input). Its D-1…D-11 are
the contract below; OR-1 and OR-2 take their recorded defaults, and the deviations section says
so.

The fix is **not** a filename exclusion. The live corpus proves the class is wider than the
issue's one example — `260-failed-…`, `272-aborted-…`, `272-escalated-…`, `272-spec-blocked-…`
all pass today's filter across three suffixes nothing documents. An exclusion list would also
drop an orphan snapshot whose ticket was never re-run, losing a real run's cost, which
`perf-retro`'s own "an abort is a real cost" doctrine forbids.

## Acceptance criteria

- **AC-1**: `corpus` dedups `era: "stage"` rows per ticket — the row whose stem equals its
  `ticketKey` is live and supersedes every other stage row carrying that `ticketKey`. Structural
  (`stem == ticketKey`), never a `-failed-`/`-aborted-`/`-escalated-` filename literal.
- **AC-2**: with no live file for a ticket, **every** snapshot of it survives as a distinct row
  — a ticket re-run three times with no surviving live file genuinely is three runs, and an
  orphan `-failed-` snapshot is data, not noise.
- **AC-3**: dedup runs **before** the `--window` slice, so a superseded snapshot never consumes
  a window slot.
- **AC-4**: `era: "artifact"` rows are never keyed by the dedup — they pass through untouched
  even when a stage-era live file exists for the same ticket. An artifact stem is
  `{issue}-lean-progress` and can never equal its `ticketKey`, so a cross-era key would delete
  the lean row rather than dedup it.
- **AC-5**: stdout is byte-identical to today for any corpus containing no superseded snapshot,
  in both `--json` and the default TSV mode. The suppression is disclosed on **stderr** — one
  line naming the pre-dedup stage-file count and the number superseded — and only when that
  number is non-zero.
- **AC-6** (guard): `retro-corpus-selftest.sh` gains behavioral cases for AC-1 through AC-5,
  driven from a `--state-dir` fixture carrying a live file, a superseded snapshot under a
  suffix no code names, an orphan snapshot, and a cross-era pair. Each new assertion is probed:
  a mutant of the dedup arm and a mutant of the stderr arm must each be caught.
- **AC-7** (docs): `perf-retro/SKILL.md` Step 1 states the now-shared rule in place of "this
  step does not dedup per ticket and the tool does", and drops the "**Scope line: when #289
  lands…**" sentence it is discharging. `scripts/lockstep-manifest.tsv` records the
  `stage-envelopes.sh` ↔ `retro-corpus.sh` dedup-rule coupling as a **DROPPED** entry with its
  reasoning and its behavioral guards on both sides.

## Design

Design: none — shell, selftest and prose; no rendered surface, no route.

## What changes

### `retro-corpus.sh` — `cmd_corpus`

The stage loop keeps its `has("stages")` gate and its two quarantine `case` patterns unchanged;
one dedup pass is inserted between the two era loops and the `--window` slice, expressed
natively in the jq pipeline the rows already live in (D-1) rather than round-tripping
JSON→TSV→JSON to share `stage-envelopes.sh`'s awk:

| Step         | Rule                                                                      |
| ------------ | ------------------------------------------------------------------------- |
| collect      | `live = { ticketKey : … }` over stage rows where `stem == ticketKey`      |
| suppress     | drop a stage row when `.ticketKey` is in `live` and `.stem != .ticketKey` |
| pass through | every `era: "artifact"` row, unconditionally (AC-4)                       |
| disclose     | stderr note when suppressed > 0 (AC-5)                                    |

`--window` then slices the deduped set (AC-3).

### `retro-corpus-selftest.sh`

New cases in the existing suite (D-10 — one script's behavior against fixtures is a per-tool
behavioral selftest). The fixture generator gains a snapshot writer that takes an arbitrary
suffix, so the cases exercise a rename convention no production code enumerates; the
`260-failed-…`/`272-aborted-…` shapes are the live-corpus evidence for that choice, not the
fixture's literal contents.

### `perf-retro/SKILL.md`

Step 1's corpus-declaration paragraph and its scope line (AC-7). No other step changes: Steps
2–4 read `era: "stage"` rows and their count only, and both counts move together.

### `scripts/lockstep-manifest.tsv`

A DROPPED entry (OR-1 default): the coupling is real — a one-sided edit re-splits the two
corpora — but the sides are awk over TSV and jq over JSON, so `verbatim` would put a byte
relation between two dialects. Guarded behaviorally on both sides instead, each side named.

## Out of scope

- `state-schema.md`'s documentation of the operator rename conventions — the nightly-retro
  program owns it, and because this fix is structural it neither needs nor duplicates it (D-6).
- `pipeline-doctor.sh`'s stale-claim enumeration and `tracker-reconcile-check.sh`, which carry
  the same quarantine `case` pattern for unrelated reasons (D-7). Deduping the doctor would hide
  live orphaned claims.
- Any change to `corpus` stdout's shape. Wrapping it in `{corpusFiles, superseded, rows}` is a
  contract change riding on a bug fix; both consumers read `.[] | …` (D-3).
- Cross-era dedup (D-2). No ticket in the current corpus carries both eras — 0 of 36 artifact
  records — so this is a latent hazard, recorded, not resolved here.

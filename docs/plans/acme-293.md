# Plan: per-stage time + per-bucket cost envelopes (#293)

## Context / problem framing

The run corpus already records everything needed to say "this run's Stage 5 was unusually
slow" — `stages.N.startedAt`/`completedAt` in every state file, and per-bucket USD in
`cost-log.jsonl` — but nothing derives a **reference distribution** from it, so every
judgment about whether a run was expensive is an impression. This ticket builds the
over-envelope half of manifesto P4: derive p50/p90 per stage (time) and per cost bucket
(USD) from the corpus, and flag values that exceed the envelope.

Advisory only. `pipeline-doctor.sh` already carries the never-blocking precedent — its
sections 7 and 8 emit `warn()` and never touch `FAILS` — and this check joins them as
section 9. Nothing gates on the output (AC-4).

The under-half (the *cheat* signal — suspiciously fast) is explicitly out of scope; it needs
a work-size normalizer this repo does not have, so a low number cannot yet be distinguished
from a small ticket.

## Assumptions

- The state corpus is the only time source; the cost log is the only USD source. No new
  recording is added — this ticket derives, it does not instrument.
- `stage-times.sh` remains the single owner of pause-overlap arithmetic (D-3). Verified it
  can already address snapshot files: its argument is used as a **filename stem**
  (`STATE="$(state_dir)/${ISSUE}.json"`), not validated as a number, so
  `stage-times.sh 272-aborted-20260731T124846Z` reads that run. No addressing change needed.
- Percentile reporting is honest about small n. At the corpus sizes involved, "exceeds p90"
  often means "set a new record", and the report says so rather than implying a stable
  distribution.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Advisory, not gating | Flags surface in the perf-retro report and as a `pipeline-doctor` WARN; nothing blocks. Recorded on the ticket at https://github.com/manoldonev/second-shift/issues/293 | ticket-sourced |
| D-2 | Under-half deferred | The cheat signal is a separate future issue; not filed here. Recorded on the ticket at https://github.com/manoldonev/second-shift/issues/293 | ticket-sourced |
| D-3 | One derivation owner, nothing stored | `stage-envelopes.sh` recomputes from the corpus per invocation; both consumers are pure callers. No config value, no cache | codebase-derived |
| D-4 | Structural per-ticket dedup | The file whose basename equals its `ticketKey` supersedes every snapshot of that ticket; with no such file, all snapshots are distinct runs | codebase-derived |
| D-5 | Over-envelope predicate | Leave-one-out nearest-rank p90 over trusted windows; window-granularity degradation exclusion; min-n floor of 8. Recorded on the ticket at https://github.com/manoldonev/second-shift/issues/293 | ticket-sourced |
| D-6 | Time vs cost granularity | Time per numbered stage over the state window; cost per cost-bucket over the cost log's own window; join by `sessionIds` intersection, newest-by-`.at` on multiplicity | codebase-derived |
| D-7 | Min-n floor is evaluated **post** leave-one-out | The ticket composes "excluding the run under test" and "no envelope below 8 trusted windows" without ordering them; at exactly n=8 the readings diverge. Resolved so no envelope is ever backed by fewer than 8 windows, which is AC-3's letter | codebase-derived |
| D-8 | Fidelity signal 4 keys on `.mode`, not session transport | perf-retro's "interactive-source sessions" signal must mean human-*paced*, i.e. `.mode == "interactive"`. Every run in this repo records `pipelineSessions[].source == "interactive"` as its transport, so keying on that field would degrade the entire corpus and darken the instrument permanently | codebase-derived |
| D-9 | Doctor mtime pre-filter is declared best-effort | mtime order does not provably contain the top-N-by-`startedAt` set. The check is WARN-only on the most recent run, so a pre-filter miss costs a missed hint — it degrades sensitivity, never correctness, and cannot produce a wrong flag. Stated at the code | codebase-derived |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/stage-envelopes.sh` `[NEW]` — the derivation owner
- `plugins/dev-pipeline/skills/run/tools/stage-envelopes-selftest.sh` `[NEW]` — its behavioral suite
- `plugins/dev-pipeline/skills/run/tools/stage-envelopes-fixtures/` `[NEW]` — fixture corpora
- `plugins/dev-pipeline/skills/run/tools/stage-times.sh` — additive `--json` emit mode
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — one renderer-agreement case beside `(pause3)`
- `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh` — section 9, WARN-only
- `plugins/dev-pipeline/skills/run/tools/pipeline-doctor-selftest.sh` — extraction case for section 9
- `plugins/dev-pipeline/skills/perf-retro/SKILL.md` — report template columns + over-envelope section

Read-only dependencies (not modified): `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh`
(owns the `cost-log.jsonl` schema and the stage→bucket label map).

## Reuse inventory

- `state_dir()` — the 3-tier precedence helper (`STATECTL_STATE_DIR` → main checkout via
  `--git-common-dir` → cwd-relative), present verbatim in `stage-times.sh` and in
  `pipeline-doctor.sh`. `stage-envelopes.sh` reuses this exact shape rather than inventing a
  fourth resolution order — it is also what makes the selftest able to point the tool at a
  fixture dir.
- The quarantine-exclusion pattern `case "$f" in *-stale-*|*-released-*) continue ;; esac` —
  identical in `perf-retro/SKILL.md` Step 1 and `pipeline-doctor.sh` section 8. Reused verbatim.
- `warn()` in `pipeline-doctor.sh` — the existing never-increments-`FAILS` helper. Section 9
  calls it and nothing else.
- The sentinel-delimited pure-block convention — `# >>> stale-claim-classify (pure …) >>>` /
  `# <<<` in `pipeline-doctor.sh`, re-hosted by `pipeline-doctor-selftest.sh` via
  `sed -n '/# >>> …/,/# <<< …/p'`. Section 9's classifier follows the identical convention.
- `stage-times.sh`'s pause-overlap arithmetic — consumed through the new `--json` mode; not
  reimplemented (D-3).

New helpers introduced: none beyond the two new scripts themselves.

## Implementation steps

1. **`stage-times.sh` — additive `--json`.** Restructure the single `jq -r` program so it
   first builds one canonical model object (`ticketKey`, `runId`, `status`, `wallMin`,
   `pausedMin`, `effectiveTotalMin`, `stages[]` of `{stage, effectiveMin, startedAt,
   completedAt}`, `gaps[]`), then renders **either** the existing text **or** `tojson`. One
   arithmetic owner, two renderers — this is what makes the agreement case meaningful rather
   than decorative. Argument parsing accepts an optional leading `--json`; the stem argument
   is unchanged. Default output must stay byte-identical (pinned by `(pause3)`).
2. **`stage-envelopes.sh` — corpus walk + dedup.** Resolve the state dir; enumerate `*.json`;
   drop the two quarantine families and anything without a `stages` key; group by `ticketKey`;
   apply D-4 (basename==`ticketKey` supersedes; else every snapshot is a distinct run); sort
   by `startedAt` descending; take the window (`--window N`, default 15).
3. **Time axis.** For each selected run call `stage-times.sh --json <stem>` and collect its
   per-stage windows. Apply fidelity triage at **window** granularity, mechanizing **all five**
   of perf-retro's signals: (1) multi-session with no pause spans; (2) effective==wall spanning
   calendar days; (3) a near-zero window preceded by a large inter-stage gap; (4) human-paced
   run, keyed on `.mode` per D-8; (5) a stage present in `stages` but absent from the timing
   table. Each degraded window records which signal fired.
4. **Percentiles.** Nearest-rank p50/p90 per stage over trusted windows, computed
   leave-one-out with respect to the run under test, with the min-n floor of 8 evaluated on
   the post-exclusion set (D-7). Below the floor, emit a known-unknown row instead of an
   envelope — never a flag.
5. **Cost axis.** Read every row of `cost-log.jsonl` (its own append-only window, independent
   of the 15-run state window). Join each row to a run by `sessionIds ∩ pipelineSessions[]`;
   on multiplicity keep the newest by `.at` and mark it `join:multi-row`. Normalize retired
   label vocabularies (`Intake + Planning` → `Intake`); any other unrecognized label collapses
   into one explicit `legacy vocabulary` row. Then p50/p90 per bucket, same predicate.
6. **Report.** Emit a text report (and `--json` for programmatic callers) carrying: the corpus
   declaration (file count + dedup rule applied), the per-stage and per-bucket envelope tables,
   known-unknown rows, and the over-envelope section with join flags. At small n the
   percentile column says the value is a record rather than implying a stable distribution.
7. **`pipeline-doctor.sh` section 9.** WARN-only check on the most recent run, time axis only.
   mtime supplies a best-effort superset pre-filter (newest ~3N files) so a 300-file state dir
   stays fast; final selection and ordering are by `startedAt`. The classifier sits in a
   sentinel-delimited pure block. Under the floor it reports a known-unknown line. It calls
   `warn()` exclusively and never touches `FAILS`.
8. **`perf-retro/SKILL.md`.** Add p90 to the profile table alongside median/worst, add the
   over-envelope section with its corpus declaration, and record the Scope line noting that
   Step 1 adopts this tool's dedup rule when #289 lands rather than growing a parallel one.
9. **Selftests.** `stage-envelopes-selftest.sh` over committed fixture corpora; the
   renderer-agreement case in `statectl-selftest.sh`; the section-9 extraction case in
   `pipeline-doctor-selftest.sh`.

## Test strategy

Verify-after for the `stage-times.sh` refactor (behavior-preserving by construction — the
existing `(pause3)` case is the regression guard and must stay green unmodified). Test-first
for `stage-envelopes.sh`, whose entire contract is arithmetic over fixtures.

Fixture corpora are committed under `stage-envelopes-fixtures/`, addressed via
`STATECTL_STATE_DIR` exactly as the `(pause3)` pause fixture is. Cases:

- **Percentile math** — a corpus with hand-computed nearest-rank p50/p90 per stage.
- **Leave-one-out** — the run under test is an outlier; its own value must not raise the
  envelope it is measured against.
- **Min-n floor, at the boundary** — corpora at n=8 and n=7 post-exclusion, proving the D-7
  ordering: n=8 emits an envelope, n=7 emits a known-unknown row and never a flag.
- **Window-granularity exclusion** — a run with one degraded window and several clean ones;
  the clean windows must still contribute.
- **Structural per-ticket dedup** — a ticket with a live file plus two snapshots (live wins,
  snapshots dropped), and a ticket with two snapshots and no live file (both kept as distinct
  runs). This is the D-4/G-1 resolution, pinned.
- **Cost-bucket separation** — cost never attributed to a numbered stage; buckets are their
  own axis.
- **Join disambiguation** — two cost rows sharing a session id; newest by `.at` wins and is
  marked `join:multi-row`; the older row does not double-count.
- **Legacy vocabulary** — `Intake + Planning` normalizes to `Intake`; an unknown label lands
  in the single `legacy vocabulary` row.
- **Doctor never blocks** — the extracted section-9 classifier over a corpus that would flag,
  asserting it emits a WARN line and contributes nothing to the exit code.
- **Red-on-mutation demo** — per the repo idiom, each new guard is observed failing before it
  is trusted; recorded in the commit body.

Mutation surface: config `commands.second-shift.unitTestScope` is `null`, so this repo declares
no mutation surface and the Stage-5 unit-test gate is skipped (`applicable: false`).

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | `stage-envelopes.sh` emits per-stage and per-bucket p50/p90 with leave-one-out, min-n rows, dedup and join flags | 2, 3, 4, 5, 6 | `stage-envelopes-selftest.sh` — percentile math (AC-1), leave-one-out (AC-1), dedup (AC-1), join disambiguation (AC-1), legacy vocabulary (AC-1) |
| AC-2 | perf-retro template carries the columns/section; doctor WARNs via the shared tool from a sentinel block | 7, 8 | `pipeline-doctor-selftest.sh` — extracted section-9 classifier (AC-2); doctor never-blocks case (AC-2) |
| AC-3 | Degraded windows excluded, fixture-proven; nothing emitted below the floor | 3, 4 | `stage-envelopes-selftest.sh` — window-granularity exclusion (AC-3), min-n boundary n=8/n=7 (AC-3) |
| AC-4 | No gate/hook/precondition consumes the output; sweep stays green | 7 | `pipeline-doctor-selftest.sh` never-blocks case (AC-4); full selftest sweep + shellcheck at Verification |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}
```

The configured `commands.second-shift.test` omits `-P 4`; CLAUDE.md's Verification section
states the parallel form is load-bearing, so the sweep is run as written above. This diff is
shell + markdown only, which rides the verify INERT lane, so the sweep is run by hand and
reported explicitly rather than assumed.

## Risks / rollback notes

- **Highest risk: the `stage-times.sh` refactor.** It is the one edit touching a tool other
  code already depends on. Mitigated by the single-model restructure (both renderers derive
  from identical arithmetic), by `(pause3)` staying green unmodified, and by the new agreement
  case. Rollback is a clean revert of that file — the `--json` mode is purely additive, so no
  caller regresses.
- **Fidelity triage is a judgment layer.** Mechanizing all five of perf-retro's signals means
  the tool's trusted set can disagree with a human reading the same corpus. Contained by
  reporting the corpus declaration and per-window degradation reasons, so the reader can see
  what was excluded and why.
- **Instrument darkening.** If triage is too aggressive the tool silently reports nothing.
  D-8 is the specific defense; the known-unknown rows are the general one — an absent envelope
  is always reported as a question, never as silence.
- Rollback for the whole ticket is a branch revert: nothing persists state, nothing gates, and
  no existing caller is required to adopt the new tool.

## Out-of-scope

- The under-half cheat signal (D-2) — needs #123, a work-size normalizer, and a lower-bound
  statistic.
- perf-retro's Step 1 corpus fix (#289) — Step 1 keeps its own enumeration this ticket; the
  Scope line records that it adopts this tool's dedup rule when #289 lands.
- Single-session idle-gap recording (#276) — its distortion inflates upper envelopes, which
  makes over-flags *less* likely, so it degrades sensitivity rather than correctness.
- Any gating, hook, or precondition consuming envelope output (AC-4 forbids it).
- Changing the recorded `RUN_ID` shape, the cost-log schema, or the stage→bucket label map.

Unverified references: none. Every path, function, and helper cited above was read or grepped
in the worktree at `origin/main`.

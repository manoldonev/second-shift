---
name: perf-retro
description: 'Cross-run execution-latency retrospective for dev-pipeline runs: fidelity-triaged timing profile, ranked optimization candidates with named regression guards, and improvement routing. Run periodically over the recorded run corpus.'
---

# Perf Retro

Cross-run performance retrospective for the dev-pipeline. `pipeline-retro` sharpens a **single** run for correctness — this skill is the second axis, **execution speed across runs**. It exists because nothing else in the improvement loop argues against latency: every fix lands as another gate, another round, another serialized dispatch, and run wall-time drifts upward unopposed while each individual change looks justified.

The data to argue with already exists and has had no systematic consumer. Timing signal sits in the cost log and the audit ledgers.

**Usage:** `/dev-pipeline:perf-retro` — profiles the 15 most recent trusted runs. `--last N` widens or narrows that window; a **bare integer is a ticket key**, focusing the profile on that one run. So `perf-retro 30` profiles ticket 30, while `perf-retro --last 30` profiles the last 30 runs. The two readings never collide.

**Hard rules:**

- **Read-only over run artifacts.** This skill never mutates existing run state, an eval file, a prior retro, or a tracker item. Everything it wants changed routes through Step 5 and lands elsewhere, under approval. The Step 6 report is its own artifact and the one thing it writes.
- **No candidate without a measured baseline.** A proposal that cannot cite minutes from the Step 3 profile is not a candidate — it is an impression, and impressions are exactly what this data exists to replace.
- **Quality is the invariant, not a tradeoff.** A candidate that weakens a gate, drops a review round, removes a retry, or reuses context where a fresh load was deliberate MUST name the concrete mechanism that would catch the regression it risks. Absent one it routes `needs-guard-first` and is **never applied directly** — the guard lands first, in its own change, and the optimization waits for it. Speed is worth having only while the pipeline still catches what it used to.
- **Recorded timestamps only.** Every duration derives from stamps the lane already wrote into `{issue}-lean-progress.md` and is read through `retro-corpus.sh timing`, never from the wall clock at read time and never re-derived by hand. Never repair a missing stamp by inference: a run with no terminal marker has a **null** wall-clock and a `fidelity[]` flag, not a substituted merge time, git mtime or last-row fallback. The gap is a Step 2 signal, not a gap to fill.
- **Per-run timing anomalies stay with `pipeline-retro`.** This skill aggregates across runs; it does not re-audit one run's contract compliance.

## Step 1: Gather the corpus

The corpus lives in the **main checkout**, resolved the way the state helper resolves it — anchored via `--git-common-dir`. A glob relative to the session's working directory is empty inside a pipeline worktree, which reads as "no runs recorded" rather than as the wrong directory.

**Era-aware (#347).** The corpus is not one schema. Full-pipeline runs are stage-schema
(`{issue}.json`, a top-level `stages` key); lean/block runs are artifact-schema
(`{issue}-lean-progress.md` plus a committed verdict record) — a lean run has no `stages`
object at all, so it never enters the corpus through the old `*.json`-only enumeration.
`retro-corpus.sh corpus` enumerates BOTH eras side by side, labeled, and does not error when
one era has zero rows (a corpus that is entirely lean runs is a normal input, not a failure):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/tools/retro-corpus.sh" corpus --window 15 --json
# --last N (below) replaces --window 15; a bare integer ticket key bypasses corpus gathering.
```

Each row carries `ticketKey`, `startedAt`, and `model` (the
run's model identity — see the note at the end of this step). The second column that mattered
before (the ticket key) is still what the per-run timing tool takes.

Every row is in scope. There is no per-stage timing table any more — the staged state files
that carried `stages[]` lifecycle windows are gone, and no run produces them. Timing evidence
now comes from the cost log and the audit ledgers named below.

**Completed and aborted runs are both in scope.** An abort is a real cost, often the most expensive shape of run, and excluding it flatters the profile.

**The cost corpus spans two lane shapes (#590).** Before the close-out stopped being a spawned model session a run cost three sessions — build, review, close-out — and after it, two. Nothing in a row marks which side it is on: date-fence on the row's own timestamp and `runId` before comparing `totalUsd` or session counts across the change, and say in the report which era a bucket is drawn from. The TIMING profile is unaffected — it already excludes milestone 5 as bookkeeping — so this is a cost-axis caveat only.

Per selected run, gather: the cost log at `<STATE_DIR>/cost-log.jsonl` when present; the timing
paragraphs of any existing `<key>-retro.md`; and, for each session id the run recorded — the
progress record's `session_id:` header plus every `| session |` row it appended — the audit
ledger at `.claude/audit/<session>.jsonl` when it exists on disk. (`pipelineSessions[]` was the
staged schema's session list and no run has written one since #348 deleted that lane.)

**Model identity (#347 comment, ratified 2026-08-03).** Corpus rows carry `model` so
cross-model deltas are queryable — an `era: "artifact"` row reads it from the progress/verdict
record's `model:` key (`lean-gate.sh`, when `LEAN_RUN_MODEL` was exported at record-creation
time). Report it as a corpus
dimension (group candidates or fidelity notes by `model` where the profile shows a difference)
— never bucket by, or hardcode, a specific vendor model string here; that neutrality is owned
by #356/#357, not this step.

## Step 2: Fidelity triage

**Classify every run trusted or degraded BEFORE aggregating anything.** Some recorded numbers are known-bad, and averaging them in produces a profile that is confidently wrong — worse than no profile, because it survives scrutiny.

The signals are the `fidelity[]` flags `retro-corpus.sh timing` emits per run. They are read, not re-derived: a triage rule that re-reads the records itself is a second parser that drifts from the first.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/tools/retro-corpus.sh" timing --window 15 --json
```

| Flag | What it means | Excluded from |
| --- | --- | --- |
| `truncated-record` | no `milestone-4` row at all — the build session's record ends where that session ends, so the run's own end was never written | wall-clock aggregates (its `wallClockMin` is null); its spans stay usable |
| `unterminated` | milestone-4 rows exist but none is `satisfied` — the run got there and did not finish | wall-clock aggregates; spans stay usable |
| `over-24h` | the measured interval to `milestone-4 \| satisfied` exceeds 24 hours, so it contains unrecorded human idle | wall-clock aggregates; spans stay usable |
| `no-chronology` | no parseable timestamped row at all | **everything** — there is nothing to aggregate |
| `re-run` | a milestone was re-verified after it was satisfied | **neither** aggregate. `satisfied` is idempotent, so re-verification moves no span; the churn is reported separately as `reverifyMin` |
| `old-grammar` | the record predates the `started`/`concluded` vocabulary | nothing. Spans and wall-clock still derive, because both key off `satisfied`, which every generation writes. Only `reverifyMin` is null |
| `unknown-model` | `model:` absent or `unknown` | nothing. `model` is a reported dimension, never a bucket or a filter |

Read the table as: a flag suppresses the aggregates it names and **no others**. A run excluded from the wall-clock aggregates still contributes its spans, and dropping it wholesale is how a 23-run profile becomes a 5-run one without saying so.

Degraded runs are not discarded. Each distinct fidelity defect is a routable instrumentation finding for Step 5, deduped against already-scoped work **by mechanism** — describe what is unrecorded and where, never by ticket number, which rots as fast as it is written. `truncated-record` is the largest standing one: on the recorded corpus roughly half of all runs carry it.

## Step 3: Profile

Across the corpus from Step 1, triaged by Step 2, build the table every candidate must cite. Per-run time comes from `retro-corpus.sh timing` and nowhere else:

- **Per-run wall-clock** (`wallClockMin`) — median, worst, and p90 across the runs that carry one (nearest-rank, so always a value some run produced).
- **Per-milestone spans** (`spans`) — milestones 1–4, the same basis on every run: span(N) is `satisfied(N)` minus the most recent `satisfied` of a lower-numbered milestone. This is where the time actually goes, and it is available on runs whose wall-clock is not. Report per-milestone medians over every run that brackets that milestone, and say how many runs each median is over — the counts differ per column.
- **Re-verification churn** (`reverifyMin`) — a diagnostic, reported beside the spans and **never summed with them**. Spans are independently floored, so `sum(spans)` does not equal `wallClockMin` and no row should claim it does.
- **Review rounds** (`rounds`) against milestone-4 span — one round is the common case, so a round count above one is the first thing to check before attributing review cost to the stage itself. Null on records carrying no `round=` token; those are absent from this column, not zero.
- **Per-dispatch latency** from audit-ledger `SubagentStop` differencing, where ledgers exist. When no ledger covers the window, **omit the column entirely** rather than showing partial rows that read as complete.
- **Cost rows** where the cost log covers the run.
- **Scheduler overhead** (`bash tools/lane-latency.sh --dir <state-dir>`), for the runs driven by
  `run-lean`. It is the one column that separates THIS LANE's cost from the payload's:
  `(terminal − launch) − Σ(spawn-end − spawn)`, everything outside a model session. Measured at
  **2 seconds** on the two runs `docs/lane-latency.md` derives by hand, so a run reporting more is
  the finding — and a run whose ledger predates the `spawn-end` rows reports `not-measurable` and
  belongs in the fidelity column, never scored as zero. Omit the column entirely when no ledger in
  the window carries both edges, on the same rule as per-dispatch latency above.

An artifact-only corpus is a normal input and produces a **populated** table: every field above except the last two derives from the progress records alone. "Not applicable" and an empty table are both wrong answers here — if the profile is thin, that is a Step 2 fidelity count to report, not a table to skip.

Report `model` as a dimension alongside the profile where it shows a difference. Never bucket by it, and never hardcode a vendor model string.

This table is the measured baseline. Steps 4 and 5 refer back to it by number, not by recollection.

## Step 4: Optimization candidates

Ranked, each a four-field record:

| Field | Contract |
| --- | --- |
| **Evidence** | Measured minutes from Step 3 — across 2+ runs, or 1 run plus a structural cause visible in the skill or workflow contract. Nothing else counts. |
| **Mechanism** | What concretely changes, and why that removes the measured time rather than moving it. |
| **Risk class** | `behavior-preserving` \| `gate-weakening` \| `contract-changing`. |
| **Regression guard** | The **existing** selftest, scenario, eval criterion, or gate that fails if this change degrades quality. No such guard → `needs-guard-first`. |

`needs-guard-first` is a terminal state for this pass, not a warning to be argued past. It routes as a guard-first proposal; the optimization is reconsidered only once the guard exists.

To seed a first pass — **examples, not a checklist, and never a substitute for what the profile actually shows**: the strictly serial plan-gate chain, sequential mutant execution, the re-verify scope after each review fix round, reviewer time ceilings, and synchronous posting of non-gating comments. If the profile does not implicate one of these, it is not a candidate this pass.

## Step 5: Route improvements

Route by reference to `pipeline-retro`'s **"Route improvements"** section, which owns this machinery for both retro axes: dedup-first, the enforcement-mechanism ladder, the meaningful-issue bar, the approval gate, and the route table. Apply it as written there. Do **not** restate it here — a copy cannot fail when the original changes, and it would quietly drift into a second, weaker policy.

One perf-specific addition: a candidate that clears the issue bar files **with its measured baseline quoted**, so the change that implements it can prove the saving with a before-and-after comparison from the timing tool instead of asserting one.

## Step 6: Write the report

Write `.claude/pipeline-state/perf-retro-{YYYY-MM-DD}.md`. A second pass on the same date overwrites, matching the per-run retro's posture.

```markdown
# Perf retro: {N} runs ({earliest} → {latest})

## Profile (trusted runs only)

| Run | Wall-clock | Spans (1-4) | Reverify | Rounds | Model | Flags |
| --- | ---------- | ----------- | -------- | ------ | ----- | ----- |

Runs with a null wall-clock still appear, with their spans and their flags — an omitted row
reads as a run that did not happen.

Runs profiled: {n} trusted, {d} degraded.

Corpus: {file count} state file(s) → {n} run(s) (models: {list}) — see `retro-corpus.sh corpus`.

## Cost envelopes (per bucket)

| Bucket | n | p50 | p90 | Notes |
| ------ | - | --- | --- | ----- |

Over the cost log's own window, independent of the run window above.

## Over-envelope

| Axis | Bucket | Run | Measured | Corpus p90 | n | Join flag |
| ---- | ------ | --- | -------- | ---------- | - | --------- |

{known-unknown rows — below the min-n floor. An absent envelope is a question, not a pass.
"measured nothing" must not read as "measured and found nothing".}

Advisory: nothing here gates, and no run is failed for appearing in this table.

## Fidelity debt

{each degraded window: which run, which signal, what is unrecorded}

## Candidates

| Rank | Candidate | Evidence (min) | Mechanism | Risk class | Regression guard |
| ---- | --------- | -------------- | --------- | ---------- | ---------------- |

## Routed

{route → action taken or proposed}

## Verdict

{2-4 sentences: where the time actually goes, and the single change that most reduces it without weakening a gate}
```

Finish by giving the operator, inline: the **top 3 candidates with projected minutes saved**, and the **fidelity-debt count**. A high debt count means the profile is thinner than it looks, and that is the more urgent finding.

---
name: perf-retro
description: 'Cross-run execution-latency retrospective for dev-pipeline runs: fidelity-triaged timing profile, ranked optimization candidates with named regression guards, and improvement routing. Run periodically over the recorded run corpus.'
---

# Perf Retro

Cross-run performance retrospective for the dev-pipeline. `pipeline-retro` sharpens a **single** run for correctness — this skill is the second axis, **execution speed across runs**. It exists because nothing else in the improvement loop argues against latency: every fix lands as another gate, another round, another serialized dispatch, and run wall-time drifts upward unopposed while each individual change looks justified.

The data to argue with already exists and has had no systematic consumer. Per-stage `startedAt`/`completedAt` sit in every run-state file, [`stage-times.sh`](../run/tools/stage-times.sh) turns them into pause-aware effective time plus inter-stage gaps, and the audit ledger timestamps every tool call and `SubagentStop`.

**Usage:** `/dev-pipeline:perf-retro` — profiles the 15 most recent trusted runs. `--last N` widens or narrows that window; a **bare integer is a ticket key**, focusing the profile on that one run. So `perf-retro 30` profiles ticket 30, while `perf-retro --last 30` profiles the last 30 runs. The two readings never collide.

**Hard rules:**

- **Read-only over run artifacts.** This skill never mutates existing run state, an eval file, a prior retro, or a tracker item. Everything it wants changed routes through Step 5 and lands elsewhere, under approval. The Step 6 report is its own artifact and the one thing it writes.
- **No candidate without a measured baseline.** A proposal that cannot cite minutes from the Step 3 profile is not a candidate — it is an impression, and impressions are exactly what this data exists to replace.
- **Quality is the invariant, not a tradeoff.** A candidate that weakens a gate, drops a review round, removes a retry, or reuses context where a fresh load was deliberate MUST name the concrete mechanism that would catch the regression it risks. Absent one it routes `needs-guard-first` and is **never applied directly** — the guard lands first, in its own change, and the optimization waits for it. Speed is worth having only while the pipeline still catches what it used to.
- **Server-clock timestamps only.** Every duration derives from the recorded `startedAt`/`completedAt` fields as written by the state helper. Never substitute the wall clock at read time, and never repair a missing field by inference — a missing lifecycle field is a Step 2 signal, not a gap to fill.
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
bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/retro-corpus.sh" corpus --window 15 --json
# --last N (below) replaces --window 15; a bare integer ticket key bypasses corpus gathering.
```

Each row carries `era: "stage" | "artifact"`, `ticketKey`, `startedAt`, and `model` (the
run's model identity — see the note at the end of this step). The second column that mattered
before (the ticket key) is still what the per-run timing tool takes.

**Only `era: "stage"` rows feed Steps 2–4's per-stage timing profile** — `stage-times.sh` and
`stage-envelopes.sh` compute against a `stages` object that artifact-schema rows do not have.
List `era: "artifact"` rows in their own corpus line in the Step-6 report (count, ticket keys,
`model` values) rather than folding them into the per-stage table or silently dropping them —
labeled-but-out-of-scope-for-this-table is the honest reading, not invisible.

**Completed and aborted runs are both in scope.** An abort is a real cost, often the most expensive shape of run, and excluding it flatters the profile.

Per selected `era: "stage"` run, gather: `bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/stage-times.sh" <key>`; the cost log at `<STATE_DIR>/cost-log.jsonl` when present; the timing paragraphs of any existing `<key>-retro.md`; and, for each session id in that run's `pipelineSessions[]`, the audit ledger at `.claude/audit/<session>.jsonl` when it exists on disk.

**Model identity (#347 comment, ratified 2026-08-03).** Corpus rows carry `model` so
cross-model deltas are queryable — an `era: "artifact"` row reads it from the progress/verdict
record's `model:` key (`lean-gate.sh`, when `LEAN_RUN_MODEL` was exported at record-creation
time); `era: "stage"` rows have no such field yet and read `"unknown"`. Report it as a corpus
dimension (group candidates or fidelity notes by `model` where the profile shows a difference)
— never bucket by, or hardcode, a specific vendor model string here; that neutrality is owned
by #356/#357, not this step.

**Envelopes come from one shared tool, not from this enumeration.** Steps 3 and 6 derive theirs from `bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/stage-envelopes.sh" --json`, which recomputes from the corpus every invocation and stores nothing. Report the corpus it declares (file count + dedup rule) next to this step's count: **this step does not dedup per ticket and the tool does**, so a ticket with a live file plus surviving snapshots counts once there and several times here. Declaring both stops one report disagreeing with itself.

**Scope line: when #289 lands, this step adopts the tool's dedup rule** (basename equal to `ticketKey` supersedes that ticket's snapshots; with no live file every snapshot is a distinct run) rather than growing a parallel one.

## Step 2: Fidelity triage

**Classify every window trusted or degraded BEFORE aggregating anything.** Some recorded numbers are known-bad, and averaging them in produces a profile that is confidently wrong — worse than no profile, because it survives scrutiny.

Degraded signals:

1. **Multi-session run with empty or implausibly short pause spans** — wall time far exceeds any plausible compute time, because the idle gap between sessions was never recorded and so was never subtracted.
2. **Effective equal to wall across calendar days** — the same defect seen from the other side: a run that spans days with nothing subtracted did not pause, according to the data, which cannot be true.
3. **A window where start and completion nearly coincide, preceded by a large inter-stage gap** — the stage's real work happened before its start was recorded, so the time landed in the gap instead of the stage.
4. **Human-paced (attended) runs** — a session a human is stepping through measures the human, not the pipeline. Key this off the run's `.mode` (`interactive` ⇒ attended), **not** off `pipelineSessions[].source`: every pipeline-written record carried `source: "interactive"` unconditionally, so that field was a constant and could never discriminate — read literally it degraded every run in the corpus. Seam-registered records carry `source: null`, which makes the constancy visible rather than introducing it.
5. **A stage present in state but absent from the timing table** — a missing lifecycle field dropped it. On an aborted run this is always the terminal stage, and is expected there.
6. **A pause with no second session** — a non-empty `pauseSpans[]` alongside fewer than two `pipelineSessions[]` records. A span exists only because a second session resumed, so the two cannot disagree: the run's session accounting is short and its cost is under-attributed by at least one whole session. **Scope this to runs that post-date seam-owned session registration** (`state-schema.md` § `pipelineSessions`): a run started before it legitimately shows this shape, because `lastWriteSessionId` has been stamped since the pause-span seam landed while registration was still declared per-stage. Report the pre-seam shape as a **pre-seam accounting** note — context for reading the number, not a defect to route — and treat only post-change runs as a real finding.

Degraded windows are **excluded from every aggregate**. They are not discarded: each distinct fidelity defect is a routable instrumentation finding for Step 5, deduped against already-scoped work **by mechanism** — describe what is unrecorded and where, never by ticket number, which rots as fast as it is written.

## Step 3: Profile

Across trusted runs only, build the table every candidate must cite:

- **Per-stage effective time** — median, worst, **p90**, and share of run. Compute shares over the **sum of the listed stage times**, not the tool's independently computed run total; the two differ whenever a stage was dropped, and dividing by the larger number silently understates every stage's share. The p90 comes from `stage-envelopes.sh` (nearest-rank, so always a value some run produced) — do not recompute it.
- **Over-envelope flags** — stages and cost buckets exceeding the corpus p90, computed leave-one-out so the run under test never inflates the envelope judging it. Below the min-n floor the tool reports a known-unknown row instead of a flag; carry those through rather than dropping them. At small n an over-flag often means only "set a new record" — the tool says which, and so must the report.
- **Lifecycle-dropped stages as explicit known-unknown rows.** A stage omitted from the table is invisible; a stage listed as unknown is a question. Never let a dropped stage read as a fast one.
- **Inter-stage gap totals** — transition overhead, where synchronous non-gating writes accumulate.
- **Review-round count against review time** — one round is the common case, so a round count above one is the first thing to check before attributing the cost to the stage itself.
- **Ceiling and dark-marker hits** — a dispatch that hit its time ceiling, or died without emitting, costs its full ceiling and returns nothing.
- **Per-dispatch latency** from audit-ledger `SubagentStop` differencing, where ledgers exist. When no ledger covers the window, **omit the column entirely** rather than showing partial rows that read as complete.
- **Cost rows** where the cost log covers the run.

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

| Stage | Median | p90 | Worst | Share | Notes |
| ----- | ------ | --- | ----- | ----- | ----- |

Inter-stage gap total: {m} min. Runs profiled: {n} trusted, {d} degraded.

Corpus: {file count} state file(s) → {n} run(s) after `stage-envelopes.sh`'s dedup
({its declared rule}); Step 1's own enumeration counted {n'} before dedup. {a} `era:
"artifact"` run(s) also in the corpus, out of scope for this table (models: {list}) —
see `retro-corpus.sh corpus`.

## Cost envelopes (per bucket)

| Bucket | n | p50 | p90 | Notes |
| ------ | - | --- | --- | ----- |

Over the cost log's own window, independent of the run window above.

## Over-envelope

| Axis | Stage / bucket | Run | Measured | Corpus p90 | n | Join flag |
| ---- | -------------- | --- | -------- | ---------- | - | --------- |

{known-unknown rows — below the min-n floor, or lifecycle-dropped. An absent envelope is
a question, not a pass.}

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

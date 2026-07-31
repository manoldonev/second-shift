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

```bash
MAIN_ROOT="$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")"
CFG="$MAIN_ROOT/.claude/second-shift.config.json"
STATE_DIR="$MAIN_ROOT/$(jq -r '.paths.pipelineStateDir // ".claude/pipeline-state"' "$CFG" 2>/dev/null || echo .claude/pipeline-state)"

# Run-state files ONLY: a top-level `stages` key, minus both quarantine families.
# The key gate alone is not enough. `*-stale-*` and `*-released-*` are prior-run
# snapshots the state helper quarantines rather than deletes (run artifacts are retro
# evidence); a released file is a complete state file with `stages` intact, so it would
# otherwise aggregate as if it were a live run and double-count its ticket.
for f in "$STATE_DIR"/*.json; do
  case "$f" in *-stale-*|*-released-*) continue ;; esac
  [ "$(jq -r 'has("stages")' "$f" 2>/dev/null)" = true ] || continue
  printf '%s\t%s\n' "$(jq -r '.startedAt // ""' "$f")" "$(basename "$f" .json)"
done | sort -r | head -15   # 15 = the default window; --last N replaces it
```

The gate also drops the co-resident `-eval` / `-verify` artifacts for free — neither carries a `stages` key. The second column is the **ticket key**, which is what the timing tool takes; it reads one run per invocation, so the enumeration produces the key list and the loop below does the join.

**Completed and aborted runs are both in scope.** An abort is a real cost, often the most expensive shape of run, and excluding it flatters the profile.

Per selected run, gather: `bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/stage-times.sh" <key>`; the cost log at `<STATE_DIR>/cost-log.jsonl` when present; the timing paragraphs of any existing `<key>-retro.md`; and, for each session id in that run's `pipelineSessions[]`, the audit ledger at `.claude/audit/<session>.jsonl` when it exists on disk.

**Envelopes come from one shared tool, not from this enumeration.** The p50/p90 envelopes and over-envelope flags in Steps 3 and 6 are derived by `bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/stage-envelopes.sh" --json`, the single derivation owner. Nothing is stored — it recomputes from the corpus on every invocation, so an envelope can never go stale against the runs it claims to summarize. Report what it declares about its own corpus (file count + dedup rule) alongside this step's count, because the two enumerations differ today: **this step does not dedup per ticket and the tool does** — a ticket with a live state file plus quarantine-surviving snapshots counts once for the tool and several times here. Declaring both is what stops one report from quietly disagreeing with itself.

**Scope line — when #289 lands, this step adopts `stage-envelopes.sh`'s dedup rule rather than growing a parallel one.** #289 owns the which-wins decision for duplicate state files; this enumeration is the surface that changes, and the tool's rule (basename equal to `ticketKey` supersedes that ticket's snapshots; with no live file every snapshot is a distinct run) is the one to converge on. Two corpus-selection algorithms over one directory is a drift risk that should exist only until then.

## Step 2: Fidelity triage

**Classify every window trusted or degraded BEFORE aggregating anything.** Some recorded numbers are known-bad, and averaging them in produces a profile that is confidently wrong — worse than no profile, because it survives scrutiny.

Degraded signals:

1. **Multi-session run with empty or implausibly short pause spans** — wall time far exceeds any plausible compute time, because the idle gap between sessions was never recorded and so was never subtracted.
2. **Effective equal to wall across calendar days** — the same defect seen from the other side: a run that spans days with nothing subtracted did not pause, according to the data, which cannot be true.
3. **A window where start and completion nearly coincide, preceded by a large inter-stage gap** — the stage's real work happened before its start was recorded, so the time landed in the gap instead of the stage.
4. **Interactive-source sessions** — a human-paced session measures the human, not the pipeline.
5. **A stage present in state but absent from the timing table** — a missing lifecycle field dropped it. On an aborted run this is always the terminal stage, and is expected there.

Degraded windows are **excluded from every aggregate**. They are not discarded: each distinct fidelity defect is a routable instrumentation finding for Step 5, deduped against already-scoped work **by mechanism** — describe what is unrecorded and where, never by ticket number, which rots as fast as it is written.

## Step 3: Profile

Across trusted runs only, build the table every candidate must cite:

- **Per-stage effective time** — median, worst, **p90**, and share of run. Compute shares over the **sum of the listed stage times**, not the tool's independently computed run total; the two differ whenever a stage was dropped, and dividing by the larger number silently understates every stage's share. The p90 column comes from `stage-envelopes.sh` (nearest-rank, so it is always a value some run actually produced) — do not recompute it here.
- **Over-envelope flags** — stages and cost buckets whose value exceeds the corpus p90, computed leave-one-out so the run under test never inflates the envelope it is judged against. Below the min-n floor no envelope exists and the tool reports a known-unknown row instead of a flag; carry those through rather than dropping them. At small n an over-flag frequently means only "set a new record" — the tool says which, and so must the report.
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
({its declared rule}); this report's own Step-1 enumeration counted {n'} before dedup.

## Cost envelopes (per bucket)

| Bucket | n | p50 | p90 | Notes |
| ------ | - | --- | --- | ----- |

Derived over the cost log's own append-only window, independent of the run window above —
tying cost to the run window would darken the axis behind the min-n floor whenever most
runs carry no cost row.

## Over-envelope

| Axis | Stage / bucket | Run | Measured | Corpus p90 | n | Join flag |
| ---- | -------------- | --- | -------- | ---------- | - | --------- |

{known-unknown rows: stage/bucket below the min-n floor, or lifecycle-dropped — reported,
never flagged. An absent envelope is a question, not a pass.}

Advisory. Nothing here gates, and no run is failed for appearing in this table.

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

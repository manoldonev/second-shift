# Where a lean run's hours go

Derived from the launch ledgers, not from impressions. Every figure below is a subtraction between
two timestamps in `.claude/pipeline-state/<issue>-lean-launches.tsv`, and the arm-b figures come
from #650's campaign rows, which recorded wall-clock for runs that write no ledger.

The question this answers: **a run takes hours — what is consuming them, and is the scheduler the
reason?**

## The scheduler is not the reason

| run | launch → first spawn |
| --- | --- |
| #636 | **2 s** |
| #637 | **2 s** |

Between spawns the loop makes a handful of direct `lean-gate.sh` calls — staleness, PR resolution,
in-flight, verdict — each a subprocess of roughly a second. Against spawns measured in tens of
minutes, everything the scheduler itself does rounds to zero. **There is no scheduler latency to
optimise.** A run's duration is its payload sessions, and any change that does not shorten or
remove a payload session cannot move the total.

## What a run actually costs

| run | rounds | spawns (B = build, R = review) | launch → approve |
| --- | --- | --- | --- |
| #636 | 2 | B 50:25 · R 10:08 · B 12:50 · R 16:55 | **1:30:20** |
| #637 | 2 | B 10:12 · R 11:51 · B 18:13 · R 12:27 | **0:52:45** |
| #658 | 4 (2 launches) | 9 spawns | **1:48:14** |

A spawn is 10–50 minutes. Four of them is the normal shape of a two-round run, and that is the
hours.

## Orchestrated against manual, like for like

The comparison that matters is launch → terminal approve, and the manual arm is *not* faster:

| arm | run | rounds | launch → approve | per round |
| --- | --- | --- | --- | --- |
| a — orchestrated | #637 | 2 | 0:52:45 | **~26 min** |
| a — orchestrated | #636 | 2 | 1:30:20 | ~45 min |
| b — manual | #661 | 1 | 1:09:34 | **~70 min** |
| b — manual | #642 | 3 | ~4:05 | ~82 min |

(#647 is excluded: its span contains a 9h53m off-shift gap, so its wall-clock is not comparable.)

Per round, the orchestrated lane runs **roughly 2.5–3× faster** than the same work driven by hand,
because the manual lane adds an operator turnaround between every phase and the scheduler adds two
seconds. Whatever makes a run feel long, it is not that a scheduler is sitting between the
sessions.

## The round is the unit, and one of them was free

The lever is **round count**, not session speed. Each round is a build spawn plus a review spawn —
20 to 45 minutes — and rounds are added by review blockers.

#637 is the case worth staring at. Its round 1 produced exactly one blocker: a guard-budget CI red.
That was resolved by a single **empty commit carrying only a `Guard-mass:` trailer** — no code line
changed. Round 2 then re-read the whole diff:

```
B2 18:13 + R2 12:27 = 30:40   —   58% of that run's 52:45
```

Half of that run bought nothing. The same shape nearly repeated on #668 and was avoided only
because the fixes were folded into the trailer commit, which bought a 20-line review delta instead
of a full re-read.

## Ranked levers, with what each is worth

1. **Do not re-open a full review for a commit that changes no reviewed line.** Worth ~30 minutes on
   a run shaped like #637 — more than half of it. The gate already computes which of a branch's own
   lines moved (it is how a rebase is kept from invalidating a verdict); the review delta should
   consume the same answer instead of re-deriving from the head commit.
2. **Collapse the review panel (#667).** Review spawns are 10–17 minutes each, two per round, and
   the recorded measurement behind that ticket is that the core four reviewers produced zero
   blockers across 248 record-versions. This cuts every round, not just the spurious ones.
3. **Do not spend a round on a budget red.** A guard-budget or trailer failure is a CI-shaped
   refusal that no reviewer judgement resolves; routing it through a review round costs a full
   build-and-review pair to apply a mechanical fix.

## Checking it, instead of asserting it

The numbers above are a snapshot taken by hand. `tools/lane-latency.sh` derives the same quantity
for every run that has a ledger, and refuses when it regresses:

```
overhead = (terminal − launch) − Σ(spawn-end − spawn)
```

Everything outside a payload session — preflight, the gate calls between phases, the close-out.
**Overhead rather than total wall-clock, deliberately:** the total is a property of the WORK, so a
threshold on it would red a run for having a big ticket and the guard would be ignored within a
month. Overhead is a property of the LANE, so a fixed ceiling (default 60s) is honest. On the two
runs above it is two seconds.

It needs the `spawn-end` rows the orchestrator began writing alongside it — start rows alone give
"this session plus whatever the loop did next", which is the very ambiguity being measured. **A
launch without both edges is reported `not-measurable` and is neither passed nor failed**, which is
the whole pre-existing corpus: scoring those as zero-overhead would manufacture a clean bill of
health for every run that predates the instrument.

It is not a CI gate, and cannot be: the ledgers are gitignored and machine-local, so CI has no
corpus to read. It runs where the data is — over an operator's own state dir, and from
`perf-retro`, which is the cross-run latency retrospective this feeds.

Session startup is deliberately *not* on this list. It is real, but it is bounded by what a model
session costs to start, it is paid identically by the manual lane, and nothing in this repo's
control moves it — whereas a removed round removes two whole sessions.

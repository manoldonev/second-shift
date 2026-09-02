# #564 — pre-registered criteria for the two-lane concurrency exercise

**Dated 2026-09-02. Landed in this slice's FIRST commit, before any measurement was taken — that
ordering is the slice's AC-1, and the precedent is
[`second-shift-643-preregistration.md`](second-shift-643-preregistration.md), whose own AC-1 audit
established that a tracker comment is not a commitment.**

This file fixes the bar. Nothing below may be edited once a measurement exists; a criterion that
turns out to be wrong is recorded as wrong in the evidence record, not rewritten here.

---

## What is being verified, and why the issue body's first criterion is struck

Epic #525 hardened the lane machinery for concurrent use and merged with **zero post-merge
multi-lane runs**. Its only verifier since has been operator anger.

The issue body pre-registered *"aggregate workers ≤ job ceiling"* as the first criterion. **That
criterion is struck: it is unimplementable.** #566 deleted `lane-registry.sh`, its advisory
wrappers, and #526's job-ceiling calculation. Nothing in the tree counts live lanes — the surviving
mentions are the code comments that cite the deletion (`lean-gate.sh:1962`, `:4828`,
`tools/run-selftests-selftest.sh:191`) and one `--ticket-source lane-registry` label at
`lean-gate.sh:461`. A criterion with no mechanism to measure against cannot be failed, and a
criterion that cannot be failed is a vacuous green.

The exercise is re-aimed at the claim that **replaced** it. #566 shipped its own untested assertion
— that the quick check is short enough that the contention class the registry protected against no
longer exists — and that claim is what the surviving cross-lane surfaces either bear out or do not:

| | Surface | What is actually shared |
| --- | --- | --- |
| (a) | Stamped fixture families in `${TMPDIR}` + `tools/reap-lean-fixtures.sh` | `run-selftests.sh` reaps the shared temp directory **before it discovers anything** (`tools/run-selftests.sh:240`), so each lane reaps while its neighbor's fixtures are live. The pid + `lstart` ownership guard is the only thing between them. |
| (b) | The selftest pass-cache store | One store per host, handed to every lane by `lane_apply_selftest_cache` (`lean-gate.sh:1952-1975`); concurrent lanes read and write it at once. |
| (c) | Sweep workers | `SELFTEST_JOBS`, default 4, with no core detection and no lane awareness (`tools/run-selftests.sh:94`). |

**Excluded:** `.claude/pipeline-state/` is issue-keyed, so two lanes on different tickets do not
collide there. #525's own correction table already settled that, and re-measuring it would be
theater.

## The unit of a "lane"

Two concurrent `lean-gate.sh 3 <issue>` invocations, in **two separate worktrees on two real
branches**. Milestone 3 is where every surface above lives, it emits the terminal verdict criterion
C-4 scores, and it incurs no model billing — so the exercise is re-runnable by anyone, at no cost
beyond wall-clock.

**Scope boundary, stated up front:** this proves nothing about scheduler- or session-level
contention — two full `run-lean` sessions, which is the shape that actually produced #525's
motivating pain. That is not covered here and the evidence record must say so in its own words.

## Host and arm definitions

`cores` is the host's logical CPU count (`sysctl -n hw.ncpu` on macOS, `nproc` on Linux). Stated as
a rule rather than a constant so the procedure ports.

| Arm | Lanes | `SELFTEST_JOBS` per lane | Pass cache | Carries a bar? |
| --- | --- | --- | --- | --- |
| **Baseline B4** | 1 | 4 | off (`LEAN_SELFTEST_CACHE=0`) | no — it *is* the bar's input |
| **Baseline B8** | 1 | `ceil(cores × 0.8)` | off | no — it *is* the bar's input |
| **Arm 1** (as-shipped) | 2 | 4 | off | **no.** Recorded descriptively. |
| **Arm 2** (oversubscribed) | 2 | `ceil(cores × 0.8)` | off | **yes — C-3.** |
| **Arm 3** (cache surface) | 2 | 4 | **on**, default shared store | **yes — C-2.** |

Arm 1 carries no bar deliberately. Two as-shipped lanes are 8 workers on a 10-core host: they are
*under*-subscribed, so any envelope they meet is met by arithmetic rather than by the machinery
working. **Arm 2 is the only arm on which #566's claim can be false**, which is why the envelope
lives there and nowhere else.

The pass cache is **off** for every wall-clock arm. With it on, a repeat sweep on an unchanged tree
serves from the store and the sample measures cache luck rather than contention. It gets its own
arm — arm 3 — because it is a genuine concurrent-write surface even though it is a poor stopwatch.

## Ordering rules, fixed now

1. This file lands in the slice's first commit, before any measurement exists.
2. **At least three** samples of each single-lane baseline are taken and **committed** before any
   two-lane arm is run. A bar keyed to one sample measures variance, not contention.
3. Every measurement is taken on trees whose only differences are under `docs/`. Before scoring,
   `git diff --name-only` between the two lane HEADs must show no `*.sh`, `*.tsv`, `*.mjs` or
   `.github/**` path. **If it does, criterion C-4's correctness oracle is void** and the record
   says so instead of scoring it.
4. Measurements are taken with no other lane, sweep, or model session running on the host. Host
   load is sampled throughout and recorded, so a reader can repudiate this claim rather than
   take it.

## The criteria

### C-1 — the fixture reaper does not reap a live neighbor

`tools/reap-lean-fixtures.sh` prints one line per directory removed, kept, or skipped. A fixture
directory's name embeds its owner pid (`leangate.<pid>.<stamp>.XXXXXX`).

**PASS iff both prongs hold, on arms 1, 2 and 3:**

- **(i)** For every `[reap-lean-fixtures] removed: <name>` line in either lane's log, `<name>` is
  **not** in the set of fixture directories observed with a **live** owner pid by the load sampler
  during that arm's window. Any intersection is a FAIL.
- **(ii)** Neither lane's `lean-gate-selftest.sh` nor `orchestrate-lean-selftest.sh` fails. These
  are the two fixture-producing suites; a cross-lane reap of live state surfaces here first.

Prong (ii) alone would be a weak oracle — a reap could destroy a directory the victim had already
finished with. Prong (i) is the direct one; (ii) catches the consequence. Both are required.

### C-2 — the shared pass-cache store survives concurrent writers

Scored on **arm 3 only**. `cache_put` writes `v1<TAB>pass<TAB><suite>` to `$CACHE_DIR/<kk>/.tmp.$$.$RANDOM`
and `mv -f`s it into place; `cache_hit` treats anything that is not exactly that first line as a
miss (`tools/run-selftests.sh:492-517`).

**PASS iff all three hold after the arm:**

- **(i)** Every non-`.tmp.*` file under the store has a well-formed first line matching
  `v1<TAB>pass<TAB>`.
- **(ii)** No `.tmp.*` file remains under the store. A survivor is a `mv` that did not complete.
- **(iii)** Both lanes reach a terminal verdict and neither log carries a `cache disabled:` or
  `not creatable` line.

**Expressly not a failure:** a lane observing fewer cache hits than it would have alone, or a
wholesale `cache_prune` clear triggered by the other lane. Both are documented fail-*closed*
behavior — the next sweep is merely cold.

### C-3 — the wall-clock envelope

Scored on **arm 2 only**.

> **Each lane's arm-2 wall-clock ≤ 1.5 × the slowest of the three B8 baseline samples.**

Both lanes must clear it; the slower lane decides.

1.5 sits above the aggregate variance of the ~63 sub-9-second suites that make up the sweep, and
well inside the 2× ceiling that would mean the two lanes had serialized outright. A red therefore
reads as contention rather than as noise — **provided the sweep is not CPU-saturated at 8 workers
on a 10-core host**, which would make 2× the arithmetic floor and the bar unreachable by
construction rather than by contention. The record must publish per-lane **CPU time alongside wall
time** and the sampled load, so a reader can tell those two apart. If the baselines show the sweep
running CPU-saturated at B8, the record says the criterion was arithmetically unreachable and
scores it FAIL-uninformative rather than claiming a finding.

### C-4 — both lanes reach a terminal and correct verdict

**PASS iff, on arms 1, 2 and 3:**

- **(i)** Each `lean-gate.sh 3` invocation exits with a recorded `| milestone-3 |` row in its own
  progress record — it terminates rather than hanging, and the outcome is written down.
- **(ii)** Each lane's set of failing suites is **identical** to the set of failing suites in the
  single-lane baselines at the same job level. Under ordering rule 3 both lanes carry
  byte-identical executable content, so any divergence is a concurrency artifact.

## What happens on a red

Fixed now, so it cannot be negotiated later:

- A failed criterion is **written down as failed** in the evidence record, at the wording above.
- The record does **not** propose a fix, does not re-scope the criterion, and does not re-open
  #566. It names the failing criterion and files a follow-up ticket, which the record cites.
- The ticket closes on a **recorded** run, green or red. Nothing here gates a merge, and a red
  bought by an honest measurement is the deliverable working.
- Attribution — whether an arm-2 red implicates #566's deletion of the ceiling or belongs
  elsewhere — is a judgment made on the recorded data, which the record preserves in full.

## When this record goes stale

The evidence record stamps tree SHA, host core count, and date. It is void when any of these move:

- `tools/run-selftests.sh` job dispatch or its cache implementation,
- `tools/reap-lean-fixtures.sh` or `tools/fixture-stamp.sh`,
- `lean-gate.sh`'s milestone-3 block, including `lane_apply_selftest_cache`.

There is no automated staleness guard. That mass is exactly what the operator-procedure form was
chosen to avoid.

# #564 — two concurrent lanes: recorded evidence

**Measured 2026-09-02.** Scored against
[`second-shift-564-preregistration.md`](second-shift-564-preregistration.md), which landed in this
slice's first commit before any number below existed. No criterion was written, widened or narrowed
after a measurement was read.

This section — the single-lane baselines — is committed **before any two-lane arm is run**, which
is the pre-registration's ordering rule 2 and the slice's AC-4.

## Host and trees

| | |
| --- | --- |
| Host | darwin 25.6.0, `sysctl -n hw.ncpu` = **10** |
| `ceil(cores × 0.8)` | **8** — the oversubscribed arm's per-lane `SELFTEST_JOBS` |
| Lane A | `claude/second-shift-564` @ `c122830b`, worktree `../second-shift-worktrees/564` |
| Lane B | `claude/second-shift-291` @ `d8ea88aa`, worktree `../second-shift-worktrees/291` |
| Lane unit | `bash lean-gate.sh 3 <issue>` — the repo's configured `lint` + `test` lanes |
| `test` lane | `env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh` |

**Ordering rule 3 holds.** `git diff --name-only claude/second-shift-291 claude/second-shift-564`
names exactly two paths, both under `docs/plans/`. No `*.sh`, `*.tsv`, `*.mjs` or
`.github/**` byte differs between the lanes, so C-4's verdict-equality oracle is live.

## Single-lane baselines

Cache off (`LEAN_SELFTEST_CACHE=0`) throughout. Every sample sweeps the same 64 suites — the
milestone-3 lane discovers 78, excludes 14, and runs 64. Load is the host 1-minute average sampled
every 2s (10s for B4-1) *including this build session and the sampler itself*; it is reported so a
reader can repudiate the quiet-host claim rather than take it.

| Sample | `SELFTEST_JOBS` | Wall (s) | User (s) | Sys (s) | CPU/wall | Verdict | Suites | Load mean/max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B4-1 | 4 | **68.20** | 67.18 | 61.15 | 1.88 | green | 64 run, 0 failed | 2.94 / 3.65 |
| B4-2 | 4 | 66.34 | 67.01 | 60.67 | 1.92 | green | 64 run, 0 failed | 2.21 / 2.95 |
| B4-3 | 4 | 66.19 | 67.03 | 60.34 | 1.93 | green | 64 run, 0 failed | 3.48 / 4.80 |
| B4-4 | 4 | 66.22 | 67.26 | 60.70 | 1.93 | green | 64 run, 0 failed | 4.39 / 4.82 |
| B8-1 | 8 | 57.24 | 72.42 | 80.18 | 2.67 | green | 64 run, 0 failed | 4.75 / 6.48 |
| B8-2 | 8 | 56.84 | 73.11 | 81.38 | 2.72 | green | 64 run, 0 failed | 5.83 / 7.73 |
| B8-3 | 8 | **57.41** | 72.97 | 81.66 | 2.69 | green | 64 run, 0 failed | 6.31 / 7.18 |

**The bar C-3 will be scored against, fixed here:** the slowest B8 sample is **57.41 s**, so
arm 2 passes iff **each** lane's wall-clock is **≤ 86.12 s** (1.5 × 57.41).

**The sweep is not CPU-saturated, and that matters.** At `SELFTEST_JOBS=8` a single lane burns
2.69 cores of a 10-core host — the suites are fork- and IO-bound, not compute-bound. Two such lanes
need roughly 5.4 cores, well inside the machine. C-3 is therefore a real test of contention rather
than a bar unreachable by arithmetic, which is the condition the pre-registration attached to it.

Four B4 samples were taken rather than three: B4-1 was sampled at 10s and the rest at 2s, so a
uniform-interval set of three exists alongside it. The sampler is a `sleep`-driven shell loop and
its cost is inside the noise — B4-1 is the slowest B4 sample and it is the one with the *fewest*
samples taken.

---

## Two-lane arms

Taken after the baselines above were committed. Both lanes launched together; each ran
`bash lean-gate.sh 3 <issue>` in its own worktree.

| Arm | `SELFTEST_JOBS` | Cache | Lane | Wall (s) | User (s) | Sys (s) | CPU/wall | rc | Suites | Load mean/max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 (as-shipped) | 4 | off | A | 79.12 | 73.98 | 81.25 | 1.96 | 0 | 64 run, 0 failed | 5.13 / 7.53 |
| 1 | 4 | off | B | 81.00 | 73.84 | 81.14 | 1.91 | 0 | 64 run, 0 failed | " |
| **2 (oversubscribed)** | 8 | off | A | **76.36** | 76.96 | 87.92 | 2.16 | 0 | 64 run, 0 failed | 7.13 / 8.70 |
| **2** | 8 | off | B | **76.23** | 76.97 | 87.78 | 2.16 | 0 | 64 run, 0 failed | " |
| 3 (cache surface) | 4 | **on** | A | 77.12 | 73.16 | 82.14 | 2.01 | 0 | 63 run, 1 served, 0 failed | 8.04 / 9.47 |
| 3 | 4 | on | B | 77.35 | 73.34 | 82.39 | 2.01 | 0 | 63 run, 1 served, 0 failed | " |

Every lane's progress record carries its own `| milestone-3 | concluded | rc=0 |` row, written to
its issue-keyed file — 21 rows under `564`, 7 under `291`, none lost to interleaving. That is
D-11's "excluded" claim about `.claude/pipeline-state/` holding under load, observed rather than
assumed.

Arm 1 lanes are **slower** than arm 2 lanes (79–81s vs 76s) despite half the workers: at
`SELFTEST_JOBS=4` two lanes together draw about 3.9 cores of 10, so the machine was never the
constraint and the extra workers simply helped.

## Supplementary observations — outside the pre-registered arms

These are **not** the pre-registered criteria and do not score them. They exist because two of the
four criteria turned out to be unreachable through the pre-registered lane unit, and the exercise's
whole point is to contend on the surfaces rather than to declare them contended.

### The lane unit cannot reach the fixture reaper

A milestone-3 lane discovers 78 suites, excludes 14, runs 64. Two of the 14 deferred by
`tools/selftest-suite-timings.tsv` — `lean-gate-selftest.sh` (212s) and
`orchestrate-lean-selftest.sh` (28s) — are the **only** producers of stamped `${TMPDIR}` fixture
directories. Sampling `${TMPDIR}` every 2 seconds across all four B4 baselines, all three B8
baselines and all three arms, the count of fixture directories in existence was **zero at every
sample**, and every reaper reported `0 removed, 0 kept, 0 skipped`.

The same defers gut the cache surface: two of the three suites with `tools/selftest-cache-inputs.tsv`
rows are deferred, so a milestone-3 lane has exactly one cacheable suite — and in arm 3 both lanes
reported `cache: 1 served, **0 recorded**`. No write raced. Filed as **#780**.

### SO-1 — void, and why it is recorded anyway

The first supplementary attempt ran `run-selftests.sh` directly, bypassing the gate's
`SEAM_SCRUB` list. This session's environment carries `LEAN_ATTEND_MODE` and `LEAN_RUN_MODEL`, both
of which reached all 77 suites. Both lanes returned an identical 4 failures
(`lean-gate-selftest.sh`, `scenario-liveness-selftest.sh`, `orchestrate-lean-selftest.sh`,
`operator-override-selftest.sh`). Isolated afterwards: `operator-override-selftest.sh` scores
43 passed / 0 failed with the variables scrubbed and 41 passed / **2 failed** with
`LEAN_ATTEND_MODE` alone set.

**SO-1's verdicts are void** and are reported only so the red is not mistaken for contention by a
later reader. Two things it does establish: the gate's seam scrub is load-bearing rather than
hygienic, and `LEAN_RUN_MODEL` is **not** in `SEAM_SCRUB` (`lean-gate.sh:3684`) while
`LEAN_ATTEND_MODE` is.

### CTRL-full — the single-lane control

One lane, `--full` minus install-topology, seam-scrubbed, cold, quiet host:
**285.65s wall / 252.50 user / 400.97 sys, 77 scored, 77 run, 0 failed, rc=0.** This is the
control the staggered observation below is read against.

### SO-2 — the staggered two-lane observation

The flaw in SO-1 was not only the environment. Both lanes started at the same instant, so both
reaped an empty directory *before* either had created a fixture — the reaper runs on sweep entry,
before discovery. SO-2 therefore holds lane B until lane A has live fixtures.

Lane B was released at `10:50:34Z` with two of lane A's directories live:

```
leangate.37554.Wed_Sep_2_13_50_23_2026.XXXXXX.X9Dq7fLpNj
orchestrate-lean-selftest.54656.Wed_Sep_2_13_50_33_2026.XXXXXX.bYTWC6vwEY
```

Lane B's entry-reaper, walking that directory:

```
[reap-lean-fixtures] keep (live owner pid 37554): leangate.37554.Wed_Sep_2_13_50_23_2026…
[reap-lean-fixtures] keep (live owner pid 54656): orchestrate-lean-selftest.54656.Wed_Sep_2_13_50_33_2026…
[reap-lean-fixtures] 0 removed, 2 kept, 0 skipped
```

| Lane | Wall (s) | User (s) | Sys (s) | rc | Suites | Cache |
| --- | --- | --- | --- | --- | --- | --- |
| A | 351.55 | 284.00 | 533.46 | 0 | 77 run, 0 failed | 0 served, 3 recorded |
| B | 347.37 | 284.15 | 532.12 | 0 | 77 run, 0 failed | 0 served, 3 recorded |

Both lanes raced into one **empty** shared store and both reported recording all 3 markers. The
store afterwards holds **3 files, 0 `.tmp` leftovers, 0 malformed** — `cache_put`'s
write-temp-then-`mv -f` held under a real race. Wall-clock is 1.23× / 1.22× the 285.65s control.
Host load over the arm: mean 7.68, max 10.19.

## Scores

| | Criterion | Arms 1–3 (pre-registered) | Supplementary |
| --- | --- | --- | --- |
| **C-1** | reaper does not reap a live neighbour | **VACUOUS — not exercised.** Zero fixture directories ever exist in a milestone-3 lane, so both prongs are trivially true. Recorded as vacuous rather than as a pass. #780 | **PASS** on SO-2, directly: `0 removed, 2 kept`, both live owner pids named, and both fixture-producing suites green in both lanes. |
| **C-2** | shared pass-cache store survives concurrent writers | **PASS on the letter, NOT EXERCISED in substance.** Store clean before and after (9 files, 0 `.tmp`, 0 malformed), both lanes terminal, no cache error — but `0 recorded` on both, so no write raced. #780 | **PASS** on SO-2: 3 markers written by two racing lanes into an empty store, 3 well-formed files, 0 leftovers, 0 malformed. |
| **C-3** | each arm-2 lane ≤ 1.5 × slowest B8 baseline (**≤ 86.12s**) | **PASS.** A = 76.36s (1.330×), B = 76.23s (1.328×). Both lanes clear it; the slower one decides and it clears by 9.8s. | — |
| **C-4** | both lanes terminal and correct | **PASS.** (i) every invocation across all three arms wrote `milestone-3 \| concluded \| rc=0`. (ii) every lane ran 64 suites with 0 failures — identical to the baselines, and ordering rule 3 held so the oracle was live. | Also holds on SO-2: 77/77, 0 failed, matching CTRL-full exactly. |

**No criterion was moved.** C-3's bar was fixed at 86.12s in the previous commit, before any
two-lane number existed. C-1 and C-2 are reported as unreachable through the pre-registered lane
unit rather than as passes, which is the outcome the pre-registration's "a criterion that cannot
fail is a vacuous green" clause exists to force.

### What #566's claim survives as

#566 asserted that the quick check is short enough that the contention class the deleted registry
protected against no longer exists. On the evidence here that holds for the lane unit as shipped,
and the margin is not thin: two oversubscribed lanes at 16 workers on 10 cores finish inside 1.33×
a single lane, because the sweep is fork- and IO-bound (a lane draws 2.2–2.7 cores, never near
saturation) rather than compute-bound. The claim is **not** disconfirmed, and #780 does not
disturb it — #780 is about what the lane never touches, not about the lane being slow.

## What this does NOT prove

- **No scheduler- or session-level contention.** A lane here is a `lean-gate.sh 3` invocation. Two
  full `run-lean` sessions — the shape that actually produced #525's motivating pain, with model
  calls, spawn transport and session state in the mix — is not covered, and nothing here should be
  read as evidence about it. Reversing that is cheap: the same procedure runs against full sessions
  later, at model cost.
- **Nothing about attribution beyond this host.** One machine, 10 cores, one afternoon. The
  envelope rule ports; the numbers do not.
- **Nothing about a red.** Every criterion that was exercised passed. The exercise has not
  demonstrated that it can detect contention, only that it found none — a green from an instrument
  never seen to go red is weaker evidence than a green from one that has.

## When this record goes stale

Stamped: lane A `claude/second-shift-564`, lane B `claude/second-shift-291` @ `d8ea88aa`, host
`hw.ncpu` = 10, 2026-09-02. Void when `tools/run-selftests.sh` job dispatch or its cache changes,
when `tools/reap-lean-fixtures.sh` or `tools/fixture-stamp.sh` changes, or when `lean-gate.sh`'s
milestone-3 block changes. No automated staleness guard — see `docs/testing.md`, "Concurrent-lane
tier".

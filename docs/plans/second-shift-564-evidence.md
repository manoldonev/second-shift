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

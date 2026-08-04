# The mutation sweep runs an embarrassingly parallel workload on a single core

Spec of record for issue #381. The definition of done is the `AC-n` set below.

## Problem

`tools/mutation-sweep.sh --mode pr` is the slowest step in the lean build loop, and `lean-gate.sh 3`
runs it once per **fix round** rather than once per PR. The cost is arithmetic and entirely
implementation-bound:

```
wall = Σ over guards ( mutants × paired-suite seconds )     [strictly serial]
```

**Measured, not remembered: 256s** for the three lean guards on a 10-core machine — 33 mutants plus
3 prechecks. The issue cites ~500s / 8–10 min from a table of remembered suite timings; the figure
this spec is answerable to is the one measured here, with the old script, in this scope.

Nine of ten cores idle throughout. Three independent levers remove it: **memoize the verdict**
(the only one that reaches "instant"), **parallelize** (one shared sandbox is the only thing
forcing serialization), and **early-exit on kill** (a killed mutant's verdict is known at the
paired suite's first `FAIL:` line).

## Binding pre-flight input

`.claude/pipeline-state/381-ledger.md` is the intake receipt for this run and is binding. Its nine
decisions are transcribed below where they bear on the design, and two of them **override** the
issue as filed: D-2 confines the cache to the advisory lane, and D-5 widens AC-11. Its three intake
findings are also load-bearing — in particular that **AC-1's stated premise is false in this repo**
(a third file can flip a verdict with the guard and its suites byte-identical), which is why D-1 and
D-2 bound the unsoundness rather than deny it.

## Files in scope

`tools/mutation-sweep.sh`, `tools/mutation-sweep-selftest.sh`, `docs/testing.md`, this spec, and —
**per D-5** — `plugins/dev-pipeline/skills/run/tools/check-{config-shadowing,doc-routing,extensions}-selftest.sh`.

**Deliberately NOT `lean-gate.sh`**, so this can run concurrently with in-flight lean PRs that
edit it. `tools/mutation-baseline.tsv` also stays untouched: `mutation-sweep.sh` is self-excluded
from sweeping (recursion guard in `tools/mutation-exclusions.tsv`), AC-4 requires identical results,
and editing a *selftest* moves no guard's mutation ordinals — so nothing re-baselines.

## Acceptance criteria

- **AC-1**: mutant verdicts are cached on `sha256(mutated guard) + sha256(paired suite) + K +
  environment`; a re-run over an unchanged tree performs **zero** paired-suite executions and
  reports the identical survivor set.
- **AC-2**: editing a paired selftest invalidates every cached verdict for its guard — driven by a
  fixture where an added test case turns a cached SURVIVED into KILLED, which is the failure a
  guard-only key would serve stale.
- **AC-3**: mutants run concurrently, each in its own sandbox, bounded by a configurable pool
  defaulting to `min(cores-2, …)`. No mutant observes another's mutation.
- **AC-4**: parallel and serial runs over the same diff produce **identical** survivor sets and
  `applied/killed/survived` counts — a fixture proves it, so the speedup provably costs no
  coverage.
- **AC-5**: a mutant whose paired suite emits `FAIL:` is scored KILLED without running the suite to
  completion, and the early-exit path scores identically to the full run on a fixture covering both
  a first-case kill and a last-case kill.
- **AC-6**: measured wall time is recorded for cold, partial-hit, and full-hit runs — the
  improvement is measured, never asserted from the design.
- **AC-7**: a paired suite that cannot tolerate a concurrent sibling (fixed port/path/temp name) is
  identified and either fixed or pinned serial with the reason recorded, not discovered later as
  flake.
- **AC-8**: the cache is bounded and fails safe: it lives outside the repo, is never committed,
  survives no environment change, and a corrupt or unreadable entry falls back to a real run rather
  than to a pass.
- **AC-9**: sandbox disk is bounded and reclaimed on every exit path, including the killer's
  timeout and population-bound reaps.
- **AC-10**: `docs/testing.md` states what the cache keys on, when it is invalidated, and which
  runs are authoritative (CI) versus advisory (local).
- **AC-11**: the diff stays inside `tools/` and `docs/`, **plus the three selftests D-5 admits** —
  see Files in scope. AC-11's stated purpose is avoiding collision with in-flight lean PRs and it
  names `lean-gate.sh` as the file to avoid; the lean lane never touches those three.
- **AC-12**: the PR carries a `Changelog:` trailer.

## Design

### Phase split (what makes AC-4 provable rather than hoped for)


The loop becomes five ordered phases. Only the mutant scoring is parallel; everything that *emits*
stays serial and index-ordered, so stdout, the report TSV and the survivor set are independent of
the pool size by construction.

1. **Enumerate (serial, sandbox 0)** — apply each generic/catalog mutant, run the `bash -n` and
   `git diff --quiet` gates exactly as today, and write the *mutated guard bytes* to a work-item
   blob. Skips, anchor drift and invalid-sed reds are decided here, in today's order.
2. **Cache probe (serial)** — a hit writes its verdict file directly; a miss goes to the pool
   manifest. This also decides which guards still need a precheck.
3. **Precheck (serial, once per distinct suite)** — for guards carrying at least one uncached
   mutant. Produces the `unrunnable pair` verdict and the `MEASURED` timings the killer bound reads.
4. **Verdict pool** — workers take work items by residue class, each in its own sandbox: install
   the blob through the guard's inode, run the ordered kill set.
5. **Aggregate (serial)** — read verdicts in item order, emit `report_bound_hit` lines, per-guard
   counts, report rows, and the exit contract.

**Phases 2 and 3 are in that order because of D-4**, and the ordering is the whole of AC-1's
letter: a precheck *is* a paired-suite execution, so a guard whose every mutant is already cached
must skip it or the run cannot claim to have executed none — and "every mutant" is not knowable
until the mutants exist. **D-4 also keeps the precheck serial and hoisted**: its timings set every
killer bound and feed `mutation-slow-suites.tsv`'s deferral semantics, so measuring them under the
pool's own contention would measure the pool rather than the suite.

Sandboxes are created lazily up to the pool size: one worker owns one sandbox for the whole run,
restores its guard between items, and no two concurrently-running mutants ever share one. That is
what bounds disk at `pool × ~7 MB` (AC-9) instead of `mutants × ~7 MB`. **D-8**: the mechanism stays
`git worktree add --detach`, never `cp -R` — two suites need real git state, and a copied worktree's
`.git` *file* would point two sandboxes at one metadata directory.

### Cache (AC-1, AC-2, AC-8; D-1, D-2, D-6, D-7)

Key = `sha256(mutation-sweep.sh) + sha256(mutated guard bytes) + sha256(each paired suite's bytes,
in kill-set order) + K + environment`, where environment is the axis the baseline header already
records (`RUNNER_OS`/`uname -s`, `SKIP_STRESS`) plus the killer-bound knobs, since those change what
a timeout verdict is.

**D-1 — the key is narrow, and it is not sound.** Intake established the issue's premise is false
here: `lean-gate.sh` shells out to four sibling scripts and `statectl-selftest.sh` sources
`scenario-lib.sh`, so a third file can flip a verdict with both keyed files byte-identical. A
whole-tree key would be sound and would also drop partial hits to zero, since the sweep sandboxes
HEAD and every fix round is a new commit. The unsoundness is **bounded, not removed**.

**D-2 is what bounds it — the cache is inert in the enforcing lane**, neither read nor written when
`GITHUB_ACTIONS` is set. A stale verdict can then only make a local advisory run optimistic, and the
cost of that is learning about a baseline-absent survivor one CI cycle later — the same cost the
issue's own follow-up section already accepts for skipping the local run entirely. This rests on the
trust boundary the harness already declares: local runs are advisory, CI is the authority.

**D-7 — `sha256(mutation-sweep.sh)` is in every key**, so any change to early exit, the kill
criterion or the killer bounds invalidates automatically with no human discipline in the loop. The
cost is stated up front: this ticket's own fix rounds edit the harness every round and so run fully
cold.

Including the **suite's** bytes is the correctness half of the rest: adding a test case can kill a
previously-surviving mutant, so a guard-only key would serve a stale SURVIVED. AC-2's fixture drives
exactly that transition.

**D-6 — location and lifetime.** `${XDG_CACHE_HOME:-$HOME/.cache}/second-shift/mutation-sweep/<repo-basename>/`,
one small file per key, overridable by `MUTATION_SWEEP_CACHE_DIR`. This closes **OR-1 at intake**;
that region's ID is retired rather than reused. It satisfies AC-8's outside-the-repo requirement,
which OR-1's "under the state dir" wording did not — an in-repo untracked directory also makes
`git status --porcelain` non-empty, which has broken a working-tree attestation before. Per repo
rather than per machine, because two checkouts can hold identical guards and suites while differing
in one of D-1's third files. AC-8's "bounded" is a generous entry cap
(`MUTATION_SWEEP_CACHE_MAX`, default 20000) cleared wholesale when exceeded, which leaves D-6's
"no eviction until it is shown to matter" true in practice and cannot be subtly wrong.

Fail-safe is a shape check on read: an entry that is not exactly one well-formed record line is a
**miss**, never a pass. Writes are `mv`-atomic so a concurrent worker cannot read a torn file.

### Early exit (AC-5; D-3)

The killer's output is captured to a per-worker log rather than discarded, and the existing poll
loop greps it for the repo-wide `FAIL:` failure convention (`fail() { echo "  FAIL: $1" >&2; }`).
On the first match the group is reaped through the existing `reap_group`, and the mutant scores
KILLED.

**D-3 makes its premise a standing assertion rather than a one-off measurement.** Intake ran all 63
selftests and observed zero `FAIL:` lines on a passing run — but the unmutated precheck now *checks*
that on every run, and a suite that passes while printing the trigger is an **unrunnable pair**,
named and red. That is the same class as a suite that cannot run at all, and for the same reason:
otherwise every mutant of its guard would be scored KILLED on prose. The precheck already runs every
suite green once, so the invariant costs nothing.

### Concurrency safety (AC-7; D-5)

- **Fixed temp paths — one defect in three suites, FIXED not accommodated.**
  `check-doc-routing-selftest.sh`, `check-extensions-selftest.sh` and
  `check-config-shadowing-selftest.sh` each redirected a check's output to a literal
  `/tmp/<fixed>.out` and grepped it back. Absolute paths, so the per-item `TMPDIR` does not move
  them; two concurrent instances interleave a write and a read and the grep answers about the wrong
  mutant. **D-5 fixes all three with `mktemp`** and widens AC-11 to admit them, rather than pinning
  them serial — so no serial-pin mechanism exists, and case (k) lints the whole corpus so a fourth
  cannot arrive quietly. The rest of the audit found nothing else: no fixed ports, every
  `git worktree add` in a suite is inside that suite's own mktemp repo with per-repo names, and the
  only `pgrep` user is this harness's companion suite, which is never a killer.
- **Temp-dir leakage from a reaped suite.** An early-exit or bound reap SIGKILLs the suite, so its
  own `trap … EXIT` cleanup never runs. Killers therefore run with `TMPDIR` pointed at a
  per-item scratch directory the harness removes unconditionally — which is also what makes AC-9's
  "reclaimed on every exit path" true for the reap paths specifically.

**OR-2 (pool default, and whether CI's 10-way sharding should shrink), disposition
`reversible-default-and-flag`; D-9 parks the sharding half with the maintainer.** Default applied as
stated: sharding is left untouched, because shrinking shards and adding intra-shard parallelism
together would make a regression in either impossible to attribute. Pool size defaults to
`min(max(cores-2,1), 8)`, overridable by `MUTATION_SWEEP_JOBS`.

## Out of scope

Making `lean-gate.sh` milestone 3's mutation leg skippable locally — split out deliberately: it
edits `lean-gate.sh` (collides with in-flight lean PRs) and "does the default become skip" is a
`pause-and-ask` question about what a build session may truthfully claim at handoff.

## Measurements

AC-6's figures are recorded here on completion and repeated in the PR body.

Scope: `--mode pr --base 57b3314`, which is exactly the three lean guards — `lean-gate.sh` (10
mutants), `lean-reconcile.sh` (11), `check-lean-chain.sh` (12) — plus their three prechecks, so 36
verdicts. 10-core machine, `getconf _NPROCESSORS_ONLN` = 10, so the default pool is 8.

| Run | Verdicts computed / served | Wall |
| --- | --- | --- |
| **A** — the OLD harness, unchanged, from `7e8d868` | 36 / — | **256s** |
| **B** — new harness, `JOBS=1`, cache off, early exit off | 36 / 0 | **237s** |
| **C** — new harness, default pool, cache off | 36 / 0 | **79s** |
| **D** — new harness, default pool, cache on, fresh cache | 36 / 0 | **78s** |
| **E** — new harness, unchanged tree, warm cache | **0** / 36 | **8s** |
| **F** — new harness, one guard's *suite* edited, warm cache | 11 / 25 | **53s** |

**A, B, C, D and E produce byte-identical report TSVs.** That is AC-4 against the real corpus and
against the *old* harness, not only across two configurations of the new one.

Reading the rows: **B ≈ A** says the four-phase refactor costs nothing on its own. **C** is the pool
and early exit stacked, 3.2× on eight workers. **E** is AC-1 exactly — zero paired-suite executions,
same survivor set. **F** is the loop the issue is about: editing `lean-gate-selftest.sh` re-keys that
guard's 10 mutants and its precheck (11 recomputed), and the other 25 verdicts are served.

Two honesty notes. The issue's cited baseline was ~500s / 8–10 min, from a table of remembered suite
timings; the measured "before" on this machine today is **256s** for 33 mutants, not 34. The figure
to compare against is A, which was measured here, in this scope, with the old script. And a single
timing run on this machine is normally worth little — but the gaps here (256 → 79 → 8) are an order
of magnitude wider than the ±2.5x run-to-run swing that caveat exists for.

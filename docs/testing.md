# Testing

How this repo tests itself, what tier a new test belongs to, and the one tier that
deliberately does not run in CI.

The short version lives in [`CLAUDE.md`](../CLAUDE.md) under **Verification**; this file
carries the reasoning and the operator-run adversarial recipe.

## What survives as a register

[`docs/pipeline-manifesto.md`](pipeline-manifesto.md)'s P4/P5 posture names the register rule;
this section is its consequence, not a second copy of it. #641 applied it — five files, 180 rows,
every one a number a command could produce in one call, are gone: two prose-budget baselines (subsumed
by `scripts/check-guard-budget.sh`, [below](#the-slow-suite-table), and a derived nightly total),
three independently-drifting suite-timing tables (collapsed into
[`tools/selftest-suite-timings.tsv`](#the-slow-suite-table)), and the `install-topology-known-red.tsv`
allowlist, which had already drained to zero rows before this PR deleted it (see
[Green here is not green where it ships](#how-the-sweep-runs), the class-guard subsection).

What survives is everything a human, not a command, decided:
`tools/gate-ablation-adjudication.tsv`, `tools/gate-ablation-classes.tsv`,
`docs/prose-blocker-triage.tsv`, `tools/mutation-catalog.tsv`, `tools/mutation-operators.tsv`,
`tools/mutation-exclusions.tsv`, `tools/mutation-pair-map.tsv`, `scripts/fail-open-sites.tsv`,
`tools/capability-parity.tsv`,
`plugins/dev-pipeline/tools/review-harness-fixtures/review-harness-manifest.tsv`,
`tools/selftest-cache-inputs.tsv`, `tools/mutation-baseline.tsv` — each row states something no
`find`/`wc`/`git ls-tree` could re-derive: a regression class, an adjudicated disposition, a
reasoned exclusion. See [Test-the-tests](#test-the-tests-the-mutation-sweep), the earn-your-keep
rule, for the discipline that keeps *those* honest.

### Never-fired decision points: the #642 reachability verdict

`docs/gate-ablation.md` found 20 of the lane's 33 declared decision points had never fired over a
52-record corpus. A point with no firings cannot be shown to change a merge decision — and neither
can it be shown not to, so #642 owed each one an argument rather than a deletion. Two buckets, and
the argument is what makes the bucket checkable:

- **structurally dead** — the state cannot be reached by any consumer on the current tree. Deleted.
- **dead here, live for a consumer** — this repo simply never enters the state. Kept, untouched.
  Absence of firings in a repo that ships no design work is not evidence about a repo that does.

**Deleted (2).** `m4/head-missing` and `m4/head-tree-diff`, the pre-patch-id SHA tail milestone 4
fell through to for a verdict record carrying no `reviewed_patch_id`. `cmd_verdict` — the only
writer — emits that key unconditionally and `envfail`s rather than omit it, so a record without it
predates the key; and `lean-evidence.sh`, which `pr-gates` runs on every consumer's PR, refuses
that record class outright. Whatever those arms answered, the boundary refused the PR: superseded,
not merely quiet. Milestone 4 now refuses the class itself, which is strictly tighter than the
fallback it replaces.

**Kept: 18 against the pin #642 acted on, 20 against the corpus it ships.** The ticket's warning
is the load-bearing one: deleting these would remove function from the shipped product to tidy the
dogfood canary.

*Both numbers are right, and the difference is the point.* The **18** are the 52-record pin's
never-fired points less the two deleted above; that is the set the operator's 2026-08-24 AC-6
amendment ratifies at 18/18. #642 also **re-cut the corpus** (70 scored records, 31 declared
points), and the re-cut moves the never-fired set underneath that count: `m1/ledger-lint` and
`m1/preflight-reconcile` fired **4** and **2** times in records the old pin did not carry, so they
leave it, while `m3/lint`, `m5/progress-current`, `m4/chain-break` and `m4/patch-stale` enter it.
Net **20** — the same number the 52-record pin produced, over a **different set**. That numeric
coincidence is why the table below carries a firings column instead of a headline count: reading
"20 then, 20 now" as "nothing moved" is the one wrong inference available here. Every point in the
table carries its reason either way — 18/18 against the pin, 20/20 against the shipped corpus.

**Dated 2026-08-24, and derived rather than authoritative.** The decision-points table in
`docs/gate-ablation.md` is what says which points fired; this table says why each is kept. Re-cut
the corpus and the *counts* here go stale while the *reasons* do not — so re-derive the counts
from the report, never from this paragraph. The `firings` column below is the shipped corpus's.

| Kept point(s) | Firings | Why it is live for a consumer |
| --- | --- | --- |
| `m1/design-form`, `m3/design-render`, `m4/fidelity` | 0 | the whole design tier. This repo configures no `design.provider`, so it never arms; a consumer that does reaches all three on its first armed ticket |
| `m4/identity` | 0 | P10's mechanical enforcement. #348 removed the in-build reviewer that used to trip it, and this row is what keeps refusing a build session that writes its own approve |
| `m3/typecheck` | 0 | this repo leaves `typecheck` null. A consumer that configures one reaches it on the first type error — and it is the one verify key #642 did **not** demote, so it is also where the reserved infra code still has a reader |
| `m3/setup-lane`, `m3/no-verify-lane` | 0 | "the check could not run" and "nothing was verified". Demoting either would make milestone 3 green having verified nothing |
| `m2/frozen-files`, `m2/changelog-trailer` | 0 | reachable on this repo today — a feature PR touching a release-owned file, or a `plugins/**` PR with no trailer |
| `m1/spec-no-ac` | 0 | reachable from an ordinary spec that declares no AC-n |
| `m1/ledger-lint`, `m1/preflight-reconcile` | **4**, **2** | reachable from an ordinary spec — an out-of-enum provenance, a dropped receipt row — and under the re-cut corpus they are no longer hypothetical: both fired, in records the 52-record pin did not carry. Kept for the same reason, now with firings behind it |
| `m4/verdict-keys`, `m4/verdict-uncommitted` | 0 | reachable from a hand-written or uncommitted record. Deleting `verdict-uncommitted` would not move WHEN the failure is caught — it would make the local answer WRONG, certifying milestone 4 against a file that is not on the branch |
| `m5/exit-artifacts:draft`, `:closes`, `:spec-link`, `m5/verdict-reference:body-ref` | 0 | a draft PR, a missing `Closes`, a missing spec link, and (under a `writes: false` tracker) a body with no verdict reference — every one an ordinary consumer state |
| `m3/lint` | 0 | new to the never-fired set under the re-cut. It is also one of the three points #642 **demoted** (AC-4): it no longer refuses at all, it records a non-blocking advisory, because `lint-and-selftests` re-runs the identical command at the merge boundary. A demoted point that never fired is not a candidate for deletion — the advisory is the whole remaining function |
| `m5/progress-current` | 0 | new to the never-fired set under the re-cut, and one of the six #642 re-verbed to `absent`: an earlier milestone left no satisfied record, so the remedy is the step the checklist orders next. Reachable by any consumer that calls milestone 5 out of order |
| `m4/chain-break`, `m4/patch-stale` | 0 | **the two the ticket kept blocking on cited incidents the re-cut dropped** — see below |

**`m4/chain-break` and `m4/patch-stale`: the citation moved, the reason did not.** #642's spec
keeps these two blocking because they "carry the corpus's two sharpest dated incidents" — the
2026-08-03 `patch-stale` firing (an approve bound to `05c05a4` with 15 files landed after it, one
of them the CI workflow judging the PR) and the 2026-08-04 `chain-break` firing. Neither record is
in the re-cut corpus, so under the corpus this PR ships both points read **never-fired**, and that
rationale no longer cites surviving evidence.

They are kept anyway, on the same footing as every other never-fired point above: the
reachability reason in `tools/gate-ablation-classes.tsv`'s `earn_your_keep` column — populated for
all **31** declared points, which is AC-2's register and the authority here. Both reasons are
argued from the mechanism, never from a firing, so the re-cut costs them nothing:
`m4/patch-stale` is the only thing that distinguishes a rebase replaying the branch unchanged from
new content landing after an approve (#372's shape); `m4/chain-break` catches a broken *multi-round*
history, which `patch-stale`'s same-round test structurally cannot see. Demoting either would spend
P10 independence, which is the lane's load-bearing property.

The dated incidents are still real and still readable — they are findings 4 and 5 of
`docs/gate-ablation.md`, which that report labels as the original 52-record analysis and asks to be
read as dated. What changed is that they can no longer be re-derived from the shipped manifest.

**Supersession is not enough on its own.** `m4/verdict-uncommitted` is re-checked at the merge
boundary too, and it is kept: deleting a local arm is only safe when what is left answers
*correctly but later*. Where deleting it would make the local gate answer *wrongly*, the boundary
duplicating it is beside the point.

## How the sweep runs

One script owns it, locally and in CI:

```bash
SKIP_STRESS=1 bash tools/run-selftests.sh --full
```

**`--full` is what makes that a full sweep.** Since #566 the bare invocation is the *bounded
quick check*: it applies `tools/selftest-suite-timings.tsv` as exclusions by default, which is the
form `lean-gate.sh` milestone 3 gets. Every caller that wants the whole set — both CI selftest
jobs, both nightly wholesale lanes, and the local recipe in [`CLAUDE.md`](../CLAUDE.md) — passes
`--full`. See [the slow-suite table](#the-slow-suite-table) below.

`tools/run-selftests.sh --full` discovers every `*-selftest.sh` under the repo, runs `SELFTEST_JOBS`
(default 4) at a time, and replays each suite's captured output inside `::group::`/`::endgroup::`
framing, in worklist order. Ordering by worklist rather than by completion is what makes the log
identical at `SELFTEST_JOBS=1` and `SELFTEST_JOBS=4` — a diff of the two runs' group headers is a
real assertion, and `tools/run-selftests-selftest.sh` makes it.

**Why a script and not a `-P` flag.** The recipe used to be a hand-rolled
`find … | xargs -0 -P 4 -n1 -I{} bash {}` pipeline, and CI was running its *serial* cousin — an
inline `while read` loop in both selftest jobs, 17:50 on macos and 12:51 on ubuntu, of which 709s
was one step. Bolting `-P 4` onto that loop would have fixed the clock and destroyed the log: at
four concurrent suites the raw streams braid, and a FAIL line no longer belongs to any identifiable
suite. Per-suite capture and ordered replay is the whole reason this is a file — and being a
checked-in script it then owes a selftest under the repo's coverage rule, which is where the
guarantees below are asserted rather than merely described.

**What it refuses to call green.** Each is a rejection the runner makes, not a convention it
follows:

| Condition | Verdict |
| --- | --- |
| any suite exits non-zero | exit 1, every failing suite named with its code |
| a worker dies without writing a verdict | that suite scores `rc=125`, named as infra — never as a pass |
| **every** failing suite is that infra class | exit **3**, the reserved code (#527) — the workers died, so the sweep learned nothing about the tree. `lean-gate.sh` milestone 3 reads a 3 from a **blocking** verify lane as "nothing was evaluated": it reds with 7 and charges no fix attempt. Since #642 that is `typecheck` alone — `lint`, `test` and extraLanes report without refusing, so on those an exit 3 is recorded like any other red and classifies nothing. Mixed infra-and-real stays exit 1, because a red branch is still a red branch. See [`config-schema.md`](config-schema.md) for the cross-repo contract |
| discovered-minus-excluded ≠ suites actually run | exit 2, `silent truncation` — a faster sweep that ran fewer suites is the failure mode this design is most exposed to |
| `--exclude` matches no discovered suite | exit 2, `stale exclusion` — the same stale-row posture the slow-suite table applies to its own rows |
| no suites discovered, or every suite excluded | exit 2 — a sweep that runs nothing is never green |

`--exclude` has four in-repo callers, all passing
`--exclude tools/install-topology-selftest.sh` (and, since #566, `--full` alongside it): both CI
selftest jobs (`lint-and-selftests`, `selftests-bash32`) and both nightly wholesale lanes
(`wholesale-selftests`, `wholesale-selftests-bash32`) — inside the sweep it contends with the very suites it re-runs
from the install cache, which is what the install-topology section below measures.
`install-topology-selftest.sh` itself runs in its own nightly jobs (`install-topology`,
`install-topology-bash32`), never alongside a sweep. The maintainer's dogfood lean-gate
milestone-3 lane gets the same exclusion from `tools/selftest-suite-timings.tsv` instead, which it
applies by default — see the slow-suite table section below. The suite stays *discovered*: the exclusion names
a path that must keep existing, so renaming the suite reds CI instead of silently
double-running it.

### When a run is killed mid-sweep

A sweep that dies part-way — a foreground agent call hitting the harness's 2-minute cap, a
Ctrl-C, a `timeout` — skips every suite's `trap … EXIT`. **What a private `TMPDIR` can contain
depends on which `mktemp` form allocated it, and the two forms in play answer oppositely.**

The **stamped fixture families** — `lean-gate-selftest.sh` and `orchestrate-lean-selftest.sh`, the
two big enough to have needed a reaper — allocate with `mktemp -d -t <name>.XXXXXX`, and that form
ignores `TMPDIR`. On macOS the `-t` path resolves against `_CS_DARWIN_USER_TEMP_DIR` and reaches
`TMPDIR` only as a fallback for when that confstr is unavailable, which on a Mac it is not; and
`mktemp -d` with no template *is* the `-t tmp` form, so there is no second behavior to fall back
on. The **explicit-template** form is the same category as the `-p` control below and behaves
oppositely: the shell expands the path before `mktemp` ever runs, so it is honored unconditionally.
Measured 2026-08-25 — the derivation is `-u`, so it creates nothing:

```sh
PRIV="$(mktemp -d /private/tmp/probe-XXXXXX)"   # a directory that EXISTS
TMPDIR="$PRIV" /usr/bin/mktemp -u -d             # -> /var/folders/…/T/tmp.…    no template — ignored
TMPDIR="$PRIV" /usr/bin/mktemp -u -d -t stamp    # -> /var/folders/…/T/stamp.…  -t — ignored
TMPDIR="$PRIV" /usr/bin/mktemp -u -d -p "$PRIV"  # -> $PRIV/tmp.…               control: a NAMED dir is honored
TMPDIR="$PRIV" bash -c 'mktemp -u -d "${TMPDIR:-/tmp}/x.XXXXXX"'  # -> $PRIV/x.…   explicit template — honored
env -u TMPDIR bash -c 'mktemp -u -d "${TMPDIR:-/tmp}/x.XXXXXX"'   # -> /tmp/x.…    …and falls back to /tmp
```

The `-p` control moving is what makes the two ignored lines a result rather than a harness
artifact.
**Point `TMPDIR` at a path that does not exist and this check is vacuous** — it can no longer tell
"ignored `TMPDIR`" from "fell back because the directory was missing", and both produce the same
`/var/folders/…` answer.

The explicit template is not a curiosity: `grep -rl 'TMPDIR:-/tmp}/' --include='*.sh' .` finds
**14** files mentioning it, and reading the 18 lines behind that `-l` leaves **12** that call it, at
16 sites. The other two only describe the form in a comment and allocate with `-t` themselves
(`tools/mutation-sweep.sh`, `plugins/intake-toolkit/hooks/exitplan-ledger-gate-selftest.sh`), so
they belong on the *ignored* side of this split — counting a `-l` without reading its matches puts
them on the wrong one. Among the twelve is the sweep runner's own state dir: its worklist and cache
bookkeeping plus each suite's captured `log`/`rc`/`secs`, and a **sibling** of the stamped fixture
dirs rather than their parent, since a worker runs its suite from the repo root with `TMPDIR`
untouched (`tools/run-selftests.sh:127-170`):

```sh
BASE="$(mktemp -d "${TMPDIR:-/tmp}/run-selftests.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$BASE"' EXIT
```

So exporting a private `TMPDIR` before a run **does** relocate that `BASE` and the other eleven
scripts' scratch, and does **not** move the stamped fixture families, which keep landing in the one
directory shared by every worktree and every concurrent lane on the machine.
[`CLAUDE.md`](../CLAUDE.md)'s verification recipe is the caller most exposed to this, which is why
it routes here.

**Most of it is reaped for you, and the residue is usually inert.** `run-selftests.sh` runs
`tools/reap-lean-fixtures.sh` over `${TMPDIR:-/tmp}` before it discovers anything, clearing the two
fixture families named above — they stamp owning pid and process start time into their
`mktemp -t` template, so the reaper deletes only what it can prove is dead and leaves every "could
not tell" standing. **That pass reaches them because `TMPDIR` arrives already *set*, by launchd, to
the very directory `-t` resolves to — not because it was aimed there.** *Unset* is not that case:
with `TMPDIR` genuinely absent the two paths diverge and the pass reaches nothing (measured
2026-08-25):

```sh
env -u TMPDIR bash -c 'echo "${TMPDIR:-/tmp}"'   # -> /tmp                 where the reaper looks
env -u TMPDIR /usr/bin/mktemp -u -d -t stamp     # -> /var/folders/…/T/…   where the fixtures land
```

Export a private `TMPDIR` and it sweeps that instead, while the fixtures keep landing where they
always did. What it does not reach in either case is everything without one of those two stamped
prefixes, and that residue is mostly harmless now: a suite that stages its fixture root one level
*below* its `mktemp` dir keeps a neighbor's leftovers outside its own resolution globs, and the
suites that once resolved across the shared directory assert that nesting with a decoy fixture
staged at the colliding depth.

What the residue still costs is diagnosis time, and a wasted fix attempt if you spend one on the
branch. **The tell is a red in a suite the diff cannot reach.** Re-run that suite alone in an
untouched checkout first: red there too means it is environmental, and the enumeration is read-only:

```sh
ls -d "$(env -u TMPDIR mktemp -u -d | xargs dirname)"/*/*/agents
```

A match with a `.claude-plugin/plugin.json` beside it is a plugin-shaped leftover; one without is
some vendor's directory and is none of your business. Before removing anything, `stat` its mtime
against your own kill — a lane running in another worktree stages fixtures in this same directory,
and a blind `rm -rf` over that glob deletes its live state. On a `/var/folders/…` path the removal
can be permission-denied outright, in which case hand the operator one exact command rather than
routing around it.

### The slow-suite table

`lean-gate.sh` milestone 3 runs the sweep as a **single blocking call inside the harness turn**,
which reaps at roughly 120s. Until #566 the lane paid for that bound with a detached runner, a
marker/rejoin protocol, a milestone-3-only interrupted budget and a lane registry — ~1,300 lines of
supervision, guards included, whose only job was surviving a limit it is cheaper to stay under.

`tools/selftest-suite-timings.tsv` is what replaced all of it. It is a committed cost record —
`suite<TAB>seconds<TAB>measured_at` — and `run-selftests.sh` applies rows at or above its own
`# threshold-seconds` directive as exclusions **by default**.

**One table, three consumers (#641).** The file used to be three: this one (as
`selftest-slow-suites.tsv`), `tools/check-sweep-bound.sh`'s baseline (as
`selftest-sweep-baseline.tsv`), and `tools/mutation-sweep.sh`'s own slow list (as
`mutation-slow-suites.tsv`) — independently drifting copies of the *same measurement* for the
suites they shared (`lean-gate-selftest.sh` was 141s in both, by coincidence, not by any
reconciling mechanism). They are one file now, one row per suite, one date. Each consumer keeps its
own threshold as a `# `-prefixed comment directive in the same file rather than a separate one:
`run-selftests.sh` and `check-sweep-bound.sh` share `# threshold-seconds` (9s); `mutation-sweep.sh`
applies its own lower, hardcoded 5s bar in code, so the file legitimately carries rows between the
two — real to the mutation lane, filtered out here at read time. A row naming no discovered suite
is still a hard error; a suite absent from the file is still treated as fast by every consumer.

| Caller | Passes | Runs |
| --- | --- | --- |
| `lean-gate.sh 3` (via the consumer's `test` command) | nothing | the table is applied — the bounded quick check |
| both CI selftest jobs | `--full` | everything |
| both nightly wholesale lanes | `--full` | everything |
| CLAUDE.md's contributor recipe | `--full` | everything |

**Default-on, with an explicit opt-out, and the direction is load-bearing.** The only caller that
wants the bound is milestone 3, and it runs a `test` command out of a consumer's *gitignored*
config — so an opt-in flag would have to be hand-added to an untracked file no gate can read, and
"is the bound actually in force?" would be unanswerable in review and unverifiable in CI. Inverted,
every sweep of record carries `--full` in a **committed** file, where a missing opt-out shows up in
the diff.

**A row costs signal latency, never soundness.** Everything deferred still runs in CI, and the
merge boundary still blocks on CI, so the worst case for a deferred suite is that its regression is
caught at PR time instead of before the push. That is the trade #566 accepted; it is not a licence
to defer a suite because it is inconvenient.

**Same stale-row posture as `--exclude`.** A row naming no discovered suite is a hard error, so a
renamed suite cannot silently start running twice. The message names the table rather than
`--exclude`, because the two have different remedies. Rows and explicit `--exclude` flags are
**deduped**: `EXCLUDED` feeds `EXPECTED = DISCOVERED - EXCLUDED`, so double-counting one suite
would under-state `EXPECTED` and red an honest sweep — and it is the normal case, since the dogfood
`test` command excludes `install-topology` explicitly while the table also lists it.

`--full` does not read the table at all, so a stale or malformed row cannot red the sweep of
record. Cases: `run-selftests-selftest.sh`'s `slow-table:` block.

#### The bound on what the table did *not* defer

The table's membership rule — *every suite at or above the declared threshold is listed, and
re-measure when you change what a listed suite does* — used to be a sentence in its own header
with nothing behind it. A suite that grew, or arrived untabled, walked the un-deferred sum back
toward milestone 3's reap, where the lane is not slow but **unpassable**: nothing is detached, so
a reaped call loses its work, and five of those hard-stop the run.

`tools/check-sweep-bound.sh` is that rule as code. Measuring and judging are split:
`run-selftests.sh` prints each suite's elapsed seconds on its existing frame line
(`::group::pass  3s  path/to-selftest.sh`) and judges nothing, so its exit-code contract keeps
meaning exactly what it meant. The checker sums the suites the table did *not* defer and compares
that total to the `# baseline-seconds`/`# allowance-percent` directives in
`tools/selftest-suite-timings.tsv` (#641: the same unified file as the slow-suite table above,
not a separate `selftest-sweep-baseline.tsv`).

| | |
| --- | --- |
| Reds on | the aggregate exceeding the committed baseline by more than its stated allowance |
| Warns on | one un-tabled suite at or above the table's `# threshold-seconds` directive, aggregate still inside |
| Also reds on | a log that is absent, whose elapsed fields do not parse, that names a suite discovery did not produce, or that covers only part of the un-deferred set |
| Runs in | `nightly-guards.yml`'s ubuntu wholesale lane, and nowhere else |

**A single suite over threshold is a warning, never a red.** One wall-clock sample of one suite is
a range rather than a point — this repo has 319/438/584s recorded for the same unchanged tree — so
staking a lane's status on it would buy flake. The aggregate is the quantity that actually breaks
milestone 3, and it is the only thing that reds.

**Nightly only, and one lane of it.** PR runners are noisier and a single slow-end sample would red
an honest PR. The macos twin is left out for a different reason: the baseline is one committed
number, and checking two machine classes against it would make it meaningless for both.

**A sub-second suite is charged one whole second.** The consumer is a sum over ~60 suites, most of
which finish instantly; rounding those to zero would let the set grow by half a minute without the
total moving. Baseline and checked sum come through the same emitter, so they stay commensurable —
the total is not the wall clock of a serial sweep and is not meant to be.

**Re-baselining is an explicit reviewed commit.** Two directive lines in
`tools/selftest-suite-timings.tsv`, changed by hand, with the commit saying what was measured,
when, and on which lane — never an automatic rewrite. The alternative remedy is to table the
grower, which the red names beside it. Cases: `tools/check-sweep-bound-selftest.sh`, plus
`run-selftests-selftest.sh`'s `#629/AC-1` block for the emitter.


`SKIP_STRESS` is never set by the runner. The ubuntu lane omits it and the macos lane sets it;
that asymmetry predates this script and is preserved, and the mutation baseline's environment
check is only meaningful because the harness does not export it on its own.

Discovery is `*-selftest.sh` only. The three `*-selftest.mjs` files are executed by
`workflows-mjs-selftest.sh`, which is itself in the glob; widening discovery would run them twice.

**Worker mode is keyed on an argv sentinel (`--run-one`), never on an environment variable**, and
that is a correctness property rather than a style choice. An env flag is inherited by everything
the dispatch spawns, *including the suites* — so a suite that itself invokes the runner takes the
worker branch and collapses. The first revision keyed on an env var and
`run-selftests-selftest.sh` (which nests a runner inside a suite) passed standalone and failed the
instant the repo sweep ran it: 67 of 68 green, which is exactly how a leak of this shape reads if
you only ever run one suite at a time. The same reasoning is why the parent's `--exclude`-era
truncation seam is stripped before a suite is executed.

### The pass cache

CI additionally passes `--cache-dir`, and with it a suite that has a row in
`tools/selftest-cache-inputs.tsv` is **not re-run when the content of every declared input is
unchanged**. The key is `sha256` over an epoch constant, `RUNNER_OS`, the bash major version,
`SKIP_STRESS`, the runner's own blob id, the suite's path, and the `git hash-object` blob id of each
declared input — so the two CI lanes accumulate independent marker sets and never serve each other
an answer to a different question.

It exists because the sweep re-derives the same verdict on every push. The measurement that
motivated it: one suite alone was 149s of a 171s ubuntu sweep, and most PRs touched
nothing it read. The figure is kept because
it is what the mechanism was sized against, not because the suite still exists.

**The risk is a silently skipped gate**, which is this repo's cardinal failure mode, so the
containment is the load-bearing part and the hashing is not. Four properties, all asserted in
`tools/run-selftests-selftest.sh` against fixture trees:

1. **Fail-closed by default, twice.** A suite with no row is always run, and the cache as a whole
   is off unless a store is named — `--cache-dir` on argv, or `$LEAN_SELFTEST_CACHE_DIR` from the
   lean lane below. The mandated local recipe in `CLAUDE.md` names neither, so a bare local sweep
   is still cold — and so is the nightly leg below.
2. **Self-inclusion is mandatory.** A row set must name the suite itself, and — where the naming
   convention resolves it, `<stem>-selftest.sh` beside `<stem>.sh` — the script under test. A row
   set that names neither, or that names nothing but the suite, is rejected with `rc=2` and a named
   cause. **The table is validated on every sweep**, including one running with no cache at all, so
   a malformed declaration reds locally rather than waiting for CI to read it.
3. **Recording takes a second flag.** `--cache-dir` reads; only `--cache-write` records, and CI
   passes it on push-to-`main` alone. A PR therefore cannot mark its own untested content as
   passing — belt-and-braces with GitHub's own scoping, which already confines a PR-created cache
   to that branch and denies cache writes to forks entirely.
4. **The nightly ignores it.** `.github/workflows/nightly-guards.yml` runs the whole sweep with no
   `--cache-dir`, on both lanes, asking the PR lane's exact question. An under-declaration surfaces
   within a day, against a tree nobody is waiting on.

**The lean lane is the third participant (#563).** `lean-gate.sh` milestone 3 runs a `test`
command it does not own — that string lives in a consumer's `.claude/second-shift.config.json`,
gitignored in this repo — so it cannot add a flag to it. It exports `LEAN_SELFTEST_CACHE_DIR`
instead, and `run-selftests.sh` reads that when argv named no store. Argv wins, and unset is a no-op, so both CI lanes, the nightly leg and the
local recipe resolve exactly what they resolve today. Three differences from the CI path, all
deliberate:

- **It records without a second flag.** Property 3 exists because a PR lane would otherwise record
  untrusted content into a store other runs read. This store is machine-local and records the
  operator's own tree — the posture the mutation sweep's cache further down this page already
  takes — and a store nothing writes can never serve the second sweep this lane exists to speed
  up.
- **An unusable store is a cold sweep, not an error.** A `--cache-dir` that cannot be created is a
  flag an operator typed that cannot work, and still exits 2. An *injected* store that cannot be
  created is not the tree's fault, so it prints a named notice and runs cold rather than reddening
  a milestone about something else entirely.
- **It has an off switch.** `LEAN_SELFTEST_CACHE=0` runs the lane cold, announced — the same
  escape hatch as `MUTATION_SWEEP_CACHE=0`, and the thing that makes a suspicious green
  re-checkable. It **scrubs** rather than merely declining to export: an operator already
  carrying `LEAN_SELFTEST_CACHE_DIR` would otherwise hand it to every lane child by ordinary
  inheritance, and the gate would announce a cold sweep while the runner cached.

The store defaults to `${XDG_CACHE_HOME:-~/.cache}/second-shift/lean-selftest`: outside every
checkout, so a worktree teardown never costs it, and per-machine, which matches a key already
scoped by OS and bash major. The `--run-one` worker scrubs the variable, so a suite never inherits
it — the cache is decided once, in the parent, and a suite that nests its own runner keeps meaning
what it means standalone.

**What it is worth is bounded by the table, not by the seam.** One suite is rowed today, so an
unchanged-head close-out sweep saves ~30s of the ~9:47 measured in #549. The wiring is what makes
every row added later pay in the lean lane as well as in CI.

Only PASS is ever recorded, and only by the parent process after the replay has scored the run — a
red suite, and a suite whose worker died without a verdict, write nothing. That falls out of the
shape rather than being separately enforced. A marker that is not exactly the one well-formed
record line is read as a **miss**, never as a pass.

Every skip prints the suite, the key, and every input blob id behind that key, so a log reader can
tell a skip from a suite that quietly stopped being discovered. The summary line reads
`N scored, M run, K served from cache` for the same reason: reporting the larger number as work
performed is the faster-green misreading the rest of this section is about.

**Adding a row is the risky edit in that file, not the cheap one.** Derive the input set from the
suite, never from a ticket: `cost-block-selftest.sh` reads the fixture corpus, the script under
test, AND the `gh-bot.sh` that script resolves at run time — three things where an eyeball lists
one.
Where a suite's composed set is really its transitive closure — `scenario-liveness-selftest.sh` is
the worked example, and is deliberately **not** in the table — drop the row. A dropped row costs
seconds; an under-declared one costs a gate.

**Derive the closure, not the file list.** Neither mechanized rule reaches depth 2: a row set can
name the suite and its subject and still under-declare, because that subject resolves a third file
at run time. The shipped set needed one — `pipeline-cost-block.sh` executes its sibling
`gh-bot.sh`, so `cost-block-selftest.sh`'s row must declare it even though the suite never names
it. Follow every `$here/`-style resolution out of every declared script until it terminates, and
say in the row comment where it terminated.

`CACHE_EPOCH` is a constant in the runner rather than a knob. The key covers repo content —
including `run-selftests.sh`'s own bytes, which is property 2 applied to the harness that produces
every recorded verdict — but not the runner image, so an image bump could in principle move a
verdict with every declared input byte-identical; bumping the epoch invalidates every marker on
every lane in one character, and the next run is a full cold sweep. `SELFTEST_CACHE_MAX` (default 5000) clears the store when it
overflows, with the same fail-closed consequence.

This is the inverse of the mutation sweep's cache further down this page, which is local-only and
disables itself in the enforcing lane. The difference is which side holds the authority: there CI
is the authority and must run cold; here CI is the thing being sped up, and the authority is the
nightly wholesale leg. The lean lane's use of this same mechanism sits on the mutation sweep's
side of that line — its store is local, it records, and it is never anyone's authority — which is
why it can record without the second flag CI withholds.

### Citing a CI run instead of re-running it (review side)

The pass cache above answers "does the *build* lane need to run this sweep again". A review
session asks a narrower version of the same question, with the answer already sitting in the PR's
checks: an oracle `AC-n` proved by "run the mandated recipe and it is green" does not need a
*third* execution once `lint-and-selftests` (ubuntu) and `selftests-bash32` — display name
`selftests (macos, bash 3.2)`, the string `gh pr checks`/`gh run view` actually print — have both
run the recipe's suite set at the commit under review, and both cover ground the reviewer's own
checkout (bash 5.x + BSD) does not: ubuntu is bash 5.x + GNU, macos is bash 3.2 + BSD. `gh pr
checks <pr>` names the job and conclusion for the PR's current head — its own `--json` has no head
SHA field, so pair it with `git rev-parse HEAD`; `gh run view <run-id> --json
headSha,conclusion,jobs` supplies all three itself. Citing those three IS the verification.

CI's own invocation is not byte-identical to the recipe — it adds `--cache-dir
"$RUNNER_TEMP/selftest-cache"`, and the ubuntu lane sets no `SKIP_STRESS` where the recipe sets
`SKIP_STRESS=1` — and neither delta counts as "command differs" below. `--cache-dir` is read-only
on a PR (`--cache-write` is push-only) and skips a suite only when every input
`tools/selftest-cache-inputs.tsv` declares for it is byte-unchanged from an already-passed run — a
correctly-declared row skips no gap the recipe would have caught differently. An *under-declared*
row is exactly that gap — but whether the PR lane itself catches it depends on what else the PR
touches: moving only the under-declared input leaves the cache key unchanged, the suite is
skipped, and it is the nightly's cold sweep that catches it (within a day, per the containment
above); moving a *declared* input in the same PR moves the content-addressed key too, and the PR
lane forces the suite to run, catching the gap itself. The missing `SKIP_STRESS` runs strictly
*more* than the recipe, never less. Both classify as same command.

**The discriminator is both conditions, not one: same command AND same head.**

- **Command differs** — the AC's recipe carries a flag or exclusion CI's invocation does not (e.g.
  an AC asserting `tools/install-topology-selftest.sh` is green: both CI selftest jobs run
  `--exclude tools/install-topology-selftest.sh` (`ci.yml:121`, `:414`), so their green never
  covered that suite). CI's green proves a different claim than the AC makes. Execute.
- **Head differs** — a fix round landed after the run being cited, or the citation predates the
  reviewed patch. CI's green is about a tree that no longer exists. Execute.
- **Neither differs** — cite the run and stop. A local rerun is not stronger evidence: CI's two
  lanes already cover two environments the local checkout does not (ubuntu, and macos under bash
  3.2), and the retry answers a question the branch's own checks already answered.

This narrows "verify by execution rather than trusting prose" — it does not repeal it. A
single-suite probe of an assertion new to this round, or any command that differs from what CI
ran, is still review-side work; only the command-and-head match is a citation, not a discretion
call.

## Why a tier map at all

CI here is **model-free by design** — no API-billed calls. That constraint is what makes the
tiering non-obvious: a repo whose product is AI tooling cannot test its product the way its
product tests other repos. So the tiers below are the model-free equivalents of the classic
pyramid, plus one tier that is honest about being outside CI.

| Classic tier | Here | Status |
| --- | --- | --- |
| Unit | Per-tool behavioral selftests — execute one script against tempdir fixtures, assert exit code / output / state | Established |
| Contract | `check-lockstep-pairs.sh` — `LOCKSTEP` marker groups discovered from the tree and compared; `check-lane-class-doc.sh` — a doc claim DERIVED from the code it describes; + registry and schema lints (config-lint ↔ schema, model tiers, text-contract carriers) | Established |
| Integration | `scenario-liveness-selftest.sh` — composed verdict paths through real scripts to a terminal write | Established, extending |
| Runtime | `workflows/runtime-shim-selftest.mjs` — executes real Workflow `.mjs` bodies with injected fakes | Established (#214) |
| Mutation | Repo-level sweep: canned mutants applied to guarded scripts, paired selftest must go red | Planned |
| Install topology | `tools/install-topology-selftest.sh` — every shipped suite re-run from a version-keyed install cache | Established (#419) |
| Adversarial | Model-tier audit workflows — **operator-run, never CI** | This document |

## The rules that matter

**Behavioral over textual.** A check that greps a file proves the file contains characters. A
check that runs the thing proves the thing works. Reach for grep only when execution is
genuinely impossible, and say why in the check itself.

**Never test a copy.** The single most expensive failure in this repo's history was two
selftests that re-declared production's dispatch logic inside themselves and then tested the
re-declaration. They were green for months while production diverged, and while one of the
paths they "covered" could not execute at all. If you find yourself pasting a production
function into a test, stop and use the runtime shim.

**Every new guard ships a red-on-mutation demo.** A guard that has never been observed failing
is indistinguishable from one that cannot fail. Break the thing, watch the guard go red, restore
it, and say so in the commit body. This is a repo idiom, not a suggestion.

**A new merge-boundary arm ships three things, not one.** An arm and the producer that satisfies
it travel by different transports — the arm by git ref, at whatever marketplace ref a consumer
pinned; the producer by versioned plugin install into an operator's local cache — and both report
the same version, so no version-keyed check can observe them skew. An arm added without allowing
for that is enforced against runs whose build session finished before the contract existed, and
which had no remedy at all. So an arm ships with: (1) its producer's **capability stamp**,
declared in the shared `lean-producer-capabilities` block and written onto an artifact that
*every* producer generation already writes — the claim comment, never the artifact the arm itself
demands, which would be circular; (2) a **not-applicable path**, one class-(b) `inert` line and
zero violations, whenever the stamp does not place the run inside the arm's contract; and
(3) **silence on green** — a satisfied arm is class (a) and prints nothing. The fixture pinning
the pre-stamp generation is not optional either: once stamped runs are the norm it is the only
thing keeping the inert path killable.

**Prefer one composed scenario to N component checks.** The since-retired stacked-PR path died
with 42 green selftests because every one of them checked a component against itself. If a new
gate has a verdict path, extend `scenario-liveness-selftest.sh`.

**Never plant what a tool could produce.** A composed scenario can still be hollow if the values
it composes over are typed in by the harness. A retired scenario helper planted every comment
receipt as `https://github.example/issues/<key>#issuecomment-<n>`, so the post-a-comment → read
`html_url` → record-the-receipt chain was never executed by anything. Worse, planting hides its own failures: a checkpoint plant
passing a payload keyed to another ticket was rejected, the stderr discarded, and both consumers
walked on with no checkpoint at all — green the whole time. Prefer a shim you execute over a literal you write; where no production tool
owns the call, say so at the assertion instead of implying the literal proves something.

**Characterization is allowed; silent characterization is not.** Covering a gate often means
reaching a branch that is wrong but out of scope to fix. Pinning it is correct — an unpinned
wrong branch is free to get quietly worse. But a case asserting broken behavior reads exactly
like a case blessing it, so it must say, at the assertion: what the real behavior is, what the
documented or intended behavior was, why it was not fixed here, and that the case is expected
to flip when it is. A characterization case that only asserts an exit code is indistinguishable
from an author who did not notice.

**Green here is not green where it ships.** A shipped suite lives in this checkout while it is
written and in a marketplace install cache everywhere it is *used*, and the two differ in ways a
suite can silently depend on: there is no git repository above the install cache, and sibling
plugins sit behind a version segment (`<root>/<plugin>/<version>/…`) instead of adjacent under
`plugins/`. Two suites depended on exactly those and were green here the whole time — one
borrowed the repo's git toplevel for its fixtures, so from an install its assertions were skipped
wholesale (one failing, two passing vacuously), and
the since-retired `design-sync-selftest.mjs` (#574) walked a fixed `../../../../design-toolkit`
path. So: **a fixture owns its own repo** (`git init` inside a `mktemp -d`), and **a
cross-plugin path goes through a resolution ladder**, never a fixed hop count —
`resolve_sibling()` in `tools/resolve-sibling.sh` is the reference.

`tools/install-topology-selftest.sh` is the class guard, and it is the reason no new instance of
this needs its own test: it stages `plugins/` at version-keyed paths outside any git repo and
re-runs **every** shipped suite from a `git init`'d consumer cwd, under a per-suite wall-clock
bound. It reds on any staged suite that fails, full stop — the `install-topology-known-red.tsv`
allowlist that used to carve out an exception here drained to zero rows (#421) and is deleted
(#641); a suite listed nowhere is already the "everything must pass" posture once the allowlist
plumbing is gone.

**Two things #664 changed about how far that goes.** The class guard did its job — it caught a
sibling-resolution defect in `pipeline-doctor-selftest.sh` on the very first nightly run after
it landed, and on the six after that. Neither half of the loop closed anyway:

- *It ran a day late, and the PR that introduced the defect was long merged.* Since #620 the
  guard is nightly-only; the PR lane excludes it. So "no new instance needs its own test" holds
  for **detecting** the class, and stops holding when you want the defect to red on the branch
  that causes it. Where a cross-plugin resolution is cheap to fabricate — a few `mkdir -p` under
  a `mktemp -d`, no plugins staged, no suites re-run — put a case in the suite that owns the
  code too: `pipeline-doctor-selftest.sh`'s `(inv-cache)` is the reference. Stage the sibling at
  a version that is **not** the caller's, so rung 2 misses and rung 3 is what has to decide;
  same-version staging passes with a dead rung 3, and rung 3 is the rung an install uses.
- *Its red named a passing case.* The `detail` string on a `RED:` line was the first log line
  matching `grep -iE 'FAIL|error|…'`, and pipeline-doctor's `ok: (d3) completed + failed at
  24h` matches "fail" 37 lines above the real `FAIL:` line. The captured log is deleted with
  `$BASE` on exit, so that one line is all a reader gets. It now prefers a line whose *start* is
  a marker (`FAIL:`/`FATAL:`/`RED:`/`ERROR:`) and falls back to the loose sweep only when a
  suite died before printing one. That path is dead on every green run — which is why it was
  wrong for seven runs unnoticed — so it is sentinel-delimited (`# >>> red-detail`) and
  exercised against fixture logs by `tools/install-topology-detail-selftest.sh`.

The general form: **a guard whose red cannot say what it caught is not yet a working guard**,
and a nightly-only guard is a detection tier, not a PR gate.

Its first run, on the authoring machine, scored 51 of 55 shipped suites passing, with 4 failing
for reasons that turned out to be environment-dependent rather than real: CI scored 49 pass on
the same commit, identically on both lanes, because two suites fail for reasons the authoring
machine's environment hid (one needs the `claude` CLI to be *absent*, one needs bash older than
5.3). **A guard that reports on the environment cannot be seeded from one environment** — read
every "measured here" claim about it as "measured on one machine" until a different one agrees.

**You can be the second environment without waiting for CI, and you should.** The gap is not
mysterious: it is a small number of ambient dependencies, and removing them is a better
experiment than re-running, which proves nothing about an environment-dependent red. Rebuild
`PATH` symlink-for-symlink with the leaking entries left out, then run the guard under it:

```bash
# `bash` resolves to 3.2 (what the macOS lane runs), `claude` absent (what CI has)
ln -sf /bin/bash "$SHADOW/bash"        # …after linking everything else on PATH except these two
PATH="$SHADOW" bash tools/install-topology-selftest.sh
```

That reproduces CI's verdict exactly — same two suites, same first failure line from each — on a
machine whose own PATH hides both. It is how those two were diagnosed as environment-dependent
rather than guessed, and both were fixed for real rather than allowlisted: `install-topology-
known-red.tsv` (the mechanism that would have carved out a temporary exception) had already
drained to zero rows by #421, before #641 deleted it. Read a red here the same way: reproduce the
gap first, do not reach for an exception that no longer exists.

Re-running the whole shipped set is the price of the class being visible at all, and it is not
small. Suites run concurrently (`INSTALL_TOPOLOGY_JOBS`, default 4 — each suite is a separate
`--run-one` invocation, which is also what gives every concurrent watchdog its own job-control
shell), against **542s** for the serial form. The remaining floor is one suite:
the then-slowest suite was 94s uncontended and was measured at 244s while a second copy ran
(the ratio is what the sizing argument rests on, not the suite).

**Do not plan around a single number for the concurrent form.** Three runs of this same tree, same
command, uncontended, measured **319s, 438s and 584s** — a 1.8x spread with no code change between
them. Budget ~7 minutes and expect either end; a run at the top of that range is not a regression
and does not need investigating. (Reporting one of those three as *the* figure is what made an
earlier revision of this page wrong, and it is the same single-measurement mistake the seeding
paragraph above is about.)

That makes this guard the long pole of the repo sweep, not a line item in it: the whole 64-suite
sweep is 13:12 serial and 5:22 at four-way concurrency in the documented `SKIP_STRESS=1` form, and
the concurrent figure is essentially this one suite — everything else folds into its shadow. The
stress-inclusive sweep (no `SKIP_STRESS`, the repo's own pre-commit gate) measured 540s. Know that
before adding to what it runs.

**It no longer runs on the PR lane at all.** It lives in `.github/workflows/nightly-guards.yml`
on a nightly cron plus `workflow_dispatch`, and both CI selftest jobs exclude it by path via
`run-selftests.sh --exclude`. The documented local recipe excludes it too, and since #566 it also
carries a `tools/selftest-suite-timings.tsv` row, so the lean lane's bounded quick check defers it
without needing the flag.

The reasoning is a cost/signal ratio, not a judgment that the guard is worthless — it caught two
real defects that were green in-tree the whole time, and it stays. But its cost *is* the shipped
suite set run a second time, which made it the repo's longest job, while the class it guards moves
only when suites change or when packaging/topology changes. On the median PR it was paying the
critical path to re-derive the previous night's answer. Inside the sweep it was also contending
with the second copy of every suite it stages — the 244s-vs-94s figure above — so it was
simultaneously the long pole and the thing lengthening everything else.

**The trade, stated plainly:** a packaging or suite regression is now caught within a day instead
of at PR time. If your change is about how plugins are installed or laid out, that window is not
good enough — run `bash tools/install-topology-selftest.sh` directly, or dispatch the workflow
against your branch. Its 1200s `INSTALL_TOPOLOGY_TIMEOUT` is deliberately left alone: it was sized
for contention that is now gone, but it is a hang detector and re-tightening it needs an
uncontended measurement the nightly is what will produce. Both lanes are retained, because the two
suites diagnosed above are explicitly environment-dependent and the bash-3.2 lane carries signal
ubuntu does not.

`INSTALL_TOPOLOGY_TIMEOUT` (default 1200s) is the per-suite bound. Its job is to turn a hang into
one named timeout line instead of a CI job that dies at its own timeout with no attributable
cause — this guard runs a second copy of every shipped suite, frequently while the outer sweep is
running the first, so contention is structural here rather than incidental.

The default was 600s and was raised on evidence: under a stress-inclusive outer sweep at `-P 4`,
the then-slowest suite inside the guard exceeded 600s and
was reported as a timeout, reding a tree
that had nothing wrong with it. A later stress-inclusive sweep of the same tree did **not** cross
it — which is the point, not a contradiction. **A bound that ambient machine load can cross
intermittently is not a hang detector, it is a flaky test**: every crossing has to be re-litigated
by hand, and it is unattributable by construction, which is precisely the cost the named-timeout
line was supposed to remove. The rule that sets it is unchanged (≈2x the worst contended run
observed); only the observation moved, from 244s to ≥600s, because under the stress-inclusive form
the contending load is the whole sweep rather than one second copy.

**A consumer's configured lane runs in a scrubbed child env.** `preflight.sh` and
`lean-gate.sh` both spawn a `commands.<host>` command (`lint`/`typecheck`/`test`/`format`/
`lanes`/`extraLanes`) as a `bash -c` child of the pipeline session. When this repo dogfoods
itself, that child IS second-shift tooling — the configured `test` command is the selftest
sweep — so it must not see the caller's own `SECOND_SHIFT_CONFIG` / `SECOND_SHIFT_REPO_ROOT` /
etc.: an ambient value silently re-roots the child, producing spurious failures unrelated to
the code under review (#34's ~20 of them). Both files carry the scrub independently — one
`SEAM_SCRUB` denylist, `env -u`'d at every child-invocation site — because they reach that lane
shape via two different code paths (the lean gate's milestone-3 sweep vs preflight's one-pass
doctor sweep), kept honest by a `subset-of` LOCKSTEP group rather than a shared import (neither
is importable by the other).

The relation is declared at the two sites — `superset` on preflight, `subset` on the gate — and
asserts `preflight ⊇ lean-gate` directly.

This is a different concern from the `unset SECOND_SHIFT_CONFIG …` lines at the top of several
*direct-invocation* selftests (`preflight-selftest.sh`, `scenario-liveness-selftest.sh`, etc.):
those defend against a seam var poisoning the selftest's OWN process when the operator sweep or
CI's `find *-selftest.sh` glob runs it directly — a path the configured-lane scrub above never
touches — so both defenses stay, in depth, rather than either replacing the other.

## Lockstep blocks: discovered, never declared twice

`scripts/check-lockstep-pairs.sh` enforces contracts that exist in two or three copies by
necessity — an agent whose independence contract forbids reading pipeline docs keeps an inline
copy of a rule; three Workflow scripts each declare the same schema because the runtime gives them
no import; a template file ships a near-twin of this repo's own workflow. Prose at those sites says
"keep verbatim", and without this guard nothing checks it. It is the replacement for the
prose-presence class: byte-parity beats token presence.

**The markers are the whole declaration.** The checker walks the tree, groups every
`LOCKSTEP-BEGIN <anchor>` site by its anchor, and compares all members of the group. There is no
manifest. Until #604 there was one, and it declared every pair a second time: 729 lines carrying
24 lines of data, appended-to at EOF by every feature PR — so two concurrent PRs conflicted there
every time, over a resolution that was always "keep both".

**A group of size 1 is a failure.** That is the property a central register could not have. It
catches a marker whose row never existed, where the register only ever caught a row whose marker
vanished — and six anchors were sitting in exactly that blind spot when #604 found them, three of
them cited in plan documents as proof that copies "still match byte-for-byte". They did not match;
nothing was comparing them.

### Writing a marker

    <indent> [# | // | <!--] LOCKSTEP-BEGIN <anchor> [<relation>] [-->]
    <indent> [# | // | <!--] LOCKSTEP-END   <anchor>              [-->]

The marker must occupy its whole line. That rule is load-bearing, not tidiness: a marker NAME
appears in ordinary prose and ordinary code — a doc sentence citing an anchor, a selftest passing
the token to `sed` — and a substring search would enrol those as sites, adding phantom members that
red a correct tree. A line that begins with the token but does not satisfy the grammar fails as
MALFORMED rather than being skipped, because the alternative is a site that silently vanishes.

The optional third token on a BEGIN states the relation, at the site, where the person editing the
block reads it. Omitted means `verbatim` — every member equal after collapsing whitespace runs.
`superset` and `subset` spell the narrowing relation and its direction: the subset's first
single-quoted `'...|...'` literal must be a subset of the superset's. A group whose members
disagree fails; so does an unrecognised token, rather than degrading to the default.

Rationale for a coupling lives at its anchor site. Because `verbatim` compares the whole block,
that prose goes immediately ABOVE the BEGIN marker, never between the markers.

### Two things to know before you edit

- **Deleting BOTH markers of a live pair silently drops it.** The old manifest would have kept an
  orphaned row and reded; discovery has nothing left to notice. It is a visible diff, and the
  blocks stay covered by their own behavioral suites, but the loss is real. This is the trade
  #604 accepted in exchange for closing the size-1 blind spot, which was the larger hole.
- **A whole-line marker inside a selftest heredoc is a real site.** Fixture trees under `mktemp`
  are outside the walk, but the selftest's own source is not. Build such a line at runtime from a
  variable — `check-lockstep-pairs-selftest.sh` does, and carries a live-corpus case that would
  catch a future paste.

`docs/plans/**` is excluded from the walk, stated as data in the script with its reason: plan
documents quote locksteped blocks verbatim as evidence for a decision, are never edited afterwards,
and are SUPPOSED to drift from the block they quote. Five of them quote a live block today.

### When the second copy is not prose: derive it (#674)

A `LOCKSTEP` group holds two copies of one contract identical. It has nothing to say when the two
sides are not both prose — when a document states a fact **about the code**, and the code is the
only place that fact is true.

`docs/config-schema.md` states the cross-repo reserved-exit-`3` contract, including which lanes
read it. #642 demoted three of the four it named, and the sentence went on claiming all four
through that PR's three review rounds and its full panel — because the file it lived in was in no
diff anyone read, and no marker could have caught it: there was no second copy to compare against.

`scripts/check-lane-class-doc.sh` is the shape that fits. It **derives** the reserved set by
walking `lean-gate.sh`'s `lane_failure_class` call sites, and requires the doc's marker-delimited
rows to name exactly that set, in both directions. It is not a prose-presence guard — it fails for
a fact that lives in another file, which is precisely what grepping a markdown file for a word
cannot do.

Two properties are what make the class safe to reuse:

- **The doc's rows ARE the claim, not a restatement beside it.** The surrounding prose stops
  enumerating lanes entirely. A machine-readable line that merely accompanies a prose list gives
  you two declarations to keep in sync and guards only one of them.
- **It fails closed on a shape it cannot model.** A derivation that silently returns a smaller set
  when it meets an unfamiliar dispatch reads as agreement. So a call site under a different `case`
  subject, a call outside any arm, a glob arm, or no call site at all each red naming the line —
  "teach this script the new shape", not "the doc is wrong".

Reach for this when a document asserts something enumerable about shipped code. Reach for a
`LOCKSTEP` marker when the two sides are copies of each other. When neither fits, the coupling is
unanchorable and belongs in the list below.

### Couplings considered and declined

Moved here from the manifest by #604. Each is a real duplication someone reasoned about and chose
not to mechanize, with the reason and — in almost every case — the behavioral guard that carries it
instead. A coupling recorded as declined is a decision that stays visible; one merely omitted is a
decision that gets re-litigated. CLAUDE.md sanctions exactly this: record a real but unanchorable
coupling rather than mechanizing it into a guard that cannot fail.

**Unanchorable — no literal the two sides could share.**

- **The mid-run ticket-liveness re-check ↔ the milestone calls' network-free property** (#650
  `D-11`). Not a duplication but a coupling of a different kind, recorded here because the decision
  is exactly the sort that gets re-litigated: `lean-gate.sh`'s `require_ticket_live` header fixes
  "one read per run boundary, never per milestone", and `1`..`5` are documented as making no
  network call. The mid-run re-check would save the most time at milestone 3's start — that is
  where a run whose ticket closed underneath it actually burns its minutes — and it is placed on
  `mark` instead, which already opens a socket and already writes, so the property holds unbroken.
  Nothing anchors the two sides: one is a comment stating an invariant, the other is the absence of
  a call. **Behaviorally guarded on the half that can be**: `lean-gate-selftest.sh` case `(tl4)`
  fails if the guard is widened past the direct `mark` subcommand. The milestone half is guarded by
  the property itself — the suite's gh stub fails loudly on an unstubbed call, so a milestone call
  that grew a tracker read would surface as a named stub miss rather than as a silent socket.

- **`render_patch_id()` ↔ `check-lean-chain.sh`'s render-id computation, on the #694 plan
  exclusion.** The gate now derives a THIRD identity, `plan_patch_id()`, which excludes the verdict
  record, the render receipt and the translation plan. The symmetric change — teaching
  `render_patch_id()` to exclude the plan too — was considered and **declined**: that function is
  mirrored at the merge boundary by a reader that cannot see this file, so a consumer pinned to an
  older boundary ref would red every armed PR whose branch carries a plan, and the skew is
  invisible from either side (the #436 shape). It is also unnecessary **in the direction the
  exclusion would serve**: the plan is asserted BEFORE the render pass, so it is committed before a
  receipt exists to restale, and `plan_patch_id()` only goes stale when non-plan, non-receipt code
  moved — which stales the receipt anyway. **The other direction is real, and it is the price paid
  for the lockstep**: the plan sits inside `render_patch_id()`, so a plan-only commit — filling a
  `why this component` cell after a plan-review finding, with no code touched — moves the render id
  and restales the receipt, forcing a re-render nothing else asked for. That converges in a single
  pass rather than looping (the receipt is excluded from both identities, so re-rendering cannot
  restale itself), and the boundary-skew argument carries the decision on its own; the cost is one
  wasted render pass, not a livelock. **Behaviorally guarded**: `lean-gate-selftest.sh`'s `(dp7)`
  pins that the stamp converges rather than looping, and `(di*)` still pin the receipt's idempotence
  across the same commits.

- **preflight ↔ gate zero-verifying-lane predicate.** Real against `lean-gate.sh` milestone 3,
  which reds naming the opt-out where `preflight.sh` only warns. preflight computes an aggregated
  VERIFYING count inline; the gate reads `allowUnverified`/`lanes`/`extraLanes` into separate
  variables under a different jq arg name. Reaching a byte-identical block means restructuring
  working code for the benefit of its own guard. Intent is declared in prose at preflight's
  VERIFYING comment.
- **`args.config` subset** — the six Workflow dispatch sites' `config:` args and their explaining
  comments ↔ the `config.` reads inside the dispatched `.mjs`. It has already failed in both
  directions: passing the whole parsed config killed a dispatch outright, and the practiced
  `{ reviewers: {} }` recovery serialized cleanly while silently disabling every model override.
  The caller side is six differently-worded prose comments inside six differently-shaped args
  objects across four files and two plugins; the callee side is an expression whose shape varies
  per key. Forcing a shared literal would mean writing dispatch prose to satisfy a grep.
  **Behaviorally guarded**, not reviewer-guarded: `runtime-shim-selftest.mjs` Case H executes the
  real `code-review.mjs` body under the documented subset alone — H1 that a `modelOverrides` value
  reaches the dispatched model, H2b/H3b that `tracker.type` still branches the scope-completeness
  fetch. Both mutation-verified. #351's `reviewers.tierMap` extends this same entry and gets none
  of its own: it lands inside the `reviewers` subset already covered. The tier ALPHABET is a
  different coupling and IS anchorable — that one is a live `tier-alphabet-parse` group.
- **Test-tier map** (CLAUDE.md's "Where a new test goes" ↔ this document's "Why a tier map at all").
  Two representations of one routing contract, deliberately NOT parallel: one is a three-column
  router keyed by what you are guarding, the other a status table keyed by the classic pyramid
  tier, carrying different row sets on purpose. Forcing a shared literal would collapse a router
  and a status board into one table serving neither reader. Reviewer-guarded: both tables are
  short, sit in the two files every contributor reads first, and a new tier lands with its own
  suite in the same PR.
- **`LEAN_SELFTEST_CACHE_DIR`, writer ↔ reader (#563).** The same coupling one ticket later,
  declined for the same reason. The invisible direction is sharper: a one-sided rename just means
  no lean sweep ever serves from cache again, which looks exactly like a cache that is working and
  never hitting. Guarded on BOTH sides — `lean-gate-selftest.sh` (sc1)-(sc3) spawn a real lane child
  that must report the announced store, and `run-selftests-selftest.sh`'s #563 cases drive the
  runner through the variable rather than the flag.
- **The reserved verify-lane INFRASTRUCTURE exit code (#527), writer ↔ reader.**
  `tools/run-selftests.sh` raises 3 when every failing suite is its no-verdict class; `lean-gate.sh`
  milestone 3 reads 3 from a blocking verify lane as "nothing was evaluated" and charges no fix
  attempt. The two sites share a NUMBER, not a block. Not left reviewer-guarded, which is where this
  differs from the ceiling above: `lean-gate-selftest.sh` (ic6)/(ic7) COMPOSE the pair — the real
  runner, over a fixture tree whose every suite dies without a verdict, wired into
  `commands.acme.typecheck` exactly as a consumer would wire it — so a one-sided change reds in both
  polarities. #642 moved that wiring off `commands.acme.test`, which no longer refuses; the contract
  is unchanged, only the key it is driven through. The ends are pinned alone too:
  `run-selftests-selftest.sh`'s AC-1 cases on the writer, (ic1)-(ic5) on the reader.
- **lean verdict-record key schema** — one writer (`lean-gate.sh`'s `verdict`) and three readers
  (`lean-gate.sh` milestone 4, `check-lean-chain.sh`, `lean-reconcile.sh`). Dropping a key on the
  writer silently un-satisfies all three; a reader-side requirement the writer never emits reds
  every lean PR. The writer spells keys as `echo` lines and the readers as grep/jq patterns.
  Guarded behaviorally, and the guard COMPOSES across sites: `lean-gate-selftest.sh` (p5)/(p7) feed
  the writer's output to the milestone-4 reader in the same run; (j3)/(j3b)/(u1) pin each key's
  absence as its own refusal; `check-lean-chain-selftest.sh` (N2)/(N3)/(R1) and
  `lean-reconcile-selftest.sh` (J3)/(K1) do the same at the other two readers.
  `reviewed_head:` and `reviewed_patch_id:` are the DERIVED keys — the readers recompute rather than
  extract, so a writer that stamped a short sha would extract cleanly everywhere and then fail every
  comparison. `reviewed_patch_id:` is tighter still: both sides must agree on the base, the diff
  range AND the excluded path. Composed instead — `lean-gate-selftest.sh` (u3) and the (v) block
  drive writer-to-reader end to end, and `scenario-liveness-selftest.sh`'s (lean-declared) and
  (lean-patch-id) legs compose each arm against a record whose INFERRED freshness is green.
  `verdict=` is read FIRST-MATCH at every reader, never counted: the writer appends reviewer prose
  below the keys and review prose quotes verdict values, so a count-anywhere reader passes a record
  whose authoritative first line says needs-work — `lean-gate-selftest.sh` (s) and
  `check-lean-chain-selftest.sh` (P) drive exactly that record. `fidelity:` (#394) is guarded the
  same composed way, and its VALUE is armed-ness-relative, which no literal can pin. Revisit if a
  fourth reader lands, or if any site starts parsing the record as structured data.
- **The chain-WALK loop** around the `lean-inherited-key` extraction, which each reader also copies.
  The three are not one literal and cannot be made into one without harm: each phrases its own
  diagnostic, each uses its host's list idiom, and `check-lean-chain.sh` must additionally scope
  `git log` to `$PR_HEAD_SHA` because CI's checkout carries base-side history the PR never authored.
  Forcing them verbatim would delete the differences, which are the point. Guarded from three sides:
  `lean-gate-selftest.sh` (x6)/(x7)/(y2), `check-lean-chain-selftest.sh` (V3)/(V3b)/(V4)/(V5),
  `lean-reconcile-selftest.sh` (N3)/(N6).
- **intake-receipt vocabulary** (Kind enum, open-region and surface disposition enums, the two
  explicit empty forms, the intent-gap record schema). `interviewing-baseline/SKILL.md` states it in
  prose and tables; `ledger-lint.sh` holds the only machine copies; `check-lean-chain.sh` reads the
  record's `ratified:`/`ratified_by:` keys. A Kind value added to the doc and not the lint is a
  value the receipt gate rejects with a message naming the enum the author just read. The doc side
  is a markdown table of prose descriptions, not a quoted literal. The empty forms ARE quoted
  literals on the lint side but sit inside fenced code blocks on the doc side, where neither
  relation reaches. Guarded by `ledger-lint-selftest.sh` (ll-o)-(ll-as) and
  `check-lean-chain-selftest.sh` (R0)-(R4). **Note the deliberate NON-coupling:** the chain gate
  checks ratification ONLY and does not re-validate `disposition:` — a second copy in CI would
  create exactly the pair this entry declines to create. **The SKILL layer is a caller class of its
  own:** `intake-orchestrator/SKILL.md` Step 5.5 prescribes the receipt shape and then runs
  `ledger-lint.sh --receipt` on what it just prescribed, and `intake-interviewer/SKILL.md`
  prescribes the same shape. Neither is an automated caller, so no CI lane reds when the lint
  tightens past what they describe — the exit gate simply becomes unpassable at agent runtime,
  where nobody is watching. A change that adds or tightens a mandated section MUST move both, and
  the check is empirical: build a receipt verbatim to the prose and lint it.
- **`ticketTag` semantics** — three sites state it: `docs/config-schema.md`'s topology row, the
  schema's own `description` (which renders in every consumer's editor), and `run-lean/SKILL.md`,
  the lane that reads it. The lane's reading is advisory only, and the docs must describe it that
  way. Markdown prose, a JSON string and SKILL prose share no quoted literal. Guarded by
  `check-config-shadowing.sh`, which pins `run-lean/SKILL.md` to `ticketTag`. Revisit if a fourth
  site restates the semantics.
- **schema `planFilePattern` default ↔ preflight.sh's hardcoded copy.** Real — the copy is the
  fallback used when a consumer sets no override, so a one-sided edit resolves a path the schema no
  longer publishes. Unanchorable BY CONSTRUCTION rather than merely awkward: the canonical side is
  `schema/second-shift.config.schema.json`, and JSON has no comment syntax, so a marker cannot be
  placed there at all. Guarded behaviorally: preflight resolves the pattern through the same
  substitution the stages use and PRINTS the result, and `preflight-selftest.sh` run 18 asserts on
  that printed line — both the unmigrated-override case and the migrated-pattern over-match negative.
  Printing alone would not have been coverage; the assertions are.
- **lean artifact discriminator** — `lean-evidence.sh`'s `classify()` ↔ `retro-corpus.sh`'s
  `open-prs` (#413). Both decide "is this PR lean" the same way, and a one-sided edit leaves the
  retro corpus silently reporting live lean PRs as verdict-less. NOT delegable, which is why the
  copy exists: the gates classify the PR they are running ON, from a PR context that lets
  `classify()` resolve one key and diff one range; `open-prs` classifies a LIST of other PRs from a
  single `gh pr list --json files` call, where an open PR's spec is committed on its own branch, so
  a working-tree file test would reject every candidate it exists to find. One side spells the test
  as shell `case` patterns over a `find` walk, the other as a `grep -v` chain plus a `grep -qE` over
  a JSON array. Guarded on both sides against the same two mistakes: `lean-evidence-selftest.sh`
  (d)/(z2) pin the key match, and `retro-corpus-selftest.sh` (AC-5b) drives `open-prs` over a
  fixture PR array carrying another ticket's spec and a fixture-pathed spec and asserts neither
  casts a vote — with (AC-5) as the non-vacuity side. Revisit if the `-lean.md` suffix is ever
  hoisted into the config schema.
- **lean ARTIFACT-NAME suffixes (#359)** — `check-lean-chain.sh`'s name table ↔ `lean-evidence.sh`'s.
  The two sets are deliberately DIFFERENT: `-lean-renders.md` belongs only to the chain gate and
  `-lean-intent-gap.md` only to the payload, so `verbatim` would compare unlike sets and fail on a
  correct tree, while `subset-of` reads a lone suffix rather than an enum and would assert nothing.
  Guarded end to end: `check-lean-chain-selftest.sh`'s (A) happy path and (S0)-(S4) drive a real
  fixture tree, so a suffix that diverged stops locating the artifact. The VERDICT suffix alone DOES
  carry markers (#542) — not a reversal, but a third holder with a different transport: the consumer
  delta guard is COMMITTED INTO a consumer repo rather than fetched at the pinned ref, so no
  end-to-end run in this tree can observe that pair. Revisit the rest if OR-1 lands and the sets
  converge.
- **lean ARM CUTOFFS (#444)** — the two `since:` comparators, and NOT for want of an anchor. They
  are not one contract: the payload compares an already-UTC `PR_CREATED_AT` supplied by the
  workflow, while the gate normalizes a git author date carrying an arbitrary offset through
  `TZ=UTC git log --date=format-local`. The `since:` values are MEANT to differ — each anchors to
  the merge that made its own arm binding. The duplication is forced by deployment shape: a
  consumer's CI checkout has `lean-evidence.sh` and nothing else. Guarded by
  `lean-evidence-selftest.sh` (ac1)-(ac6), `lean-gate-selftest.sh` (eb1)-(eb7) including two non-UTC
  offsets in both directions, `check-lean-chain-selftest.sh` (Z1)/(Z2), and this repo's own
  `pr-gates` executing the payload on every PR. Revisit if a shared normalization helper is ever
  hoisted into a file both can reach.
- **lean evidence TOKEN SCOPES (#359)** — the `permissions:` block in this repo's `ci.yml`
  (`pr-gates`) ↔ `templates/consumer/second-shift-ci.yml`. Declined NOT for want of an anchor: the
  two blocks do collapse to the same string today. They are not one contract. The host job
  additionally runs `check-lean-chain.sh`'s issue-side claim arm, which a read-only tracker has no
  counterpart for, so the sets coincide by present need, not by definition. A `verbatim` relation
  would bind them in the wrong direction — a scope the HOST later needs would become a scope every
  consumer's workflow is forced to grant, the standing escalation the template's own comment
  refuses. Guarded ASYMMETRICALLY, because the sides have unequal signals: the template has no live
  signal, so `second-shift-ci-check-selftest.sh` pins all three scopes against the block itself (not
  the file, so a commented-out scope cannot satisfy it) plus the no-write-scope rule; the host side
  executes that read on every PR, where an assertion would restate what CI already proves. Revisit
  if the host's block gains a scope — check whether the arm needing it lives in the payload (then
  the template needs it too) or only in `check-lean-chain.sh` (then it must not).
- **`config-grill.sh`'s restated RUNTIME-resolved defaults** ↔ the stages that resolve them.
  Quoting the SCHEMA default would be a lie the consumer cannot act on: nothing injects schema
  defaults into a config, so the value in force is the fallback in the stage. `webComponentGlobs`'s
  literal alone is restated at seven sites, and a pair cannot express one canonical against seven
  scattered restatements — picking one arbitrarily would leave the other six free to drift while
  the row stayed green. Nor is a marker block placeable: they sit inside prose sentences and a jq
  expression. Guarded by `config-grill-selftest.sh`, which asserts each default fires a zero-match
  finding on a fixture tree containing no matching path, so the literal is exercised rather than
  merely present — a check on the checker's copy, not on the two staying equal. The asymmetry is
  the point. Revisit if the fallbacks are hoisted into one shared resolver.
- **`onboard/SKILL.md`'s benefit clauses** ↔ the docs that own the worked examples. Real — a
  capability whose behavior changes leaves a clause promising something the tool no longer does, and
  onboard is precisely where a human decides on that promise. No literal on either side: the clause
  is a summary IN a sentence, the authority a multi-paragraph worked example. Wrapping markers
  around them would pin only that some text exists between the markers, and CLAUDE.md forbids the
  grep alternative outright. What holds it instead: the clause is a POINTER plus one sentence,
  deliberately short enough that the authoritative text stays in exactly one place. Revisit if the
  benefit text is ever hoisted into a data file both sites read.
- **The dup-scan exit taxonomy.** `dup-scan.sh`'s 0 / 10 / 2 contract is restated in four SKILL
  blocks — intake-orchestrator twice, intake-interviewer, plan-interview — and nothing couples them
  to the tool. Each states the obligation in the vocabulary of its own exit (what "hard-stop" means
  differs per exit: do not label, do not hand off, do not create), so a `verbatim` block would force
  four prose passages into one wording they do not share, or degrade to a bare-number grep.
  `dup-scan-selftest.sh` pins each arm's rc AND the message it names, so a taxonomy change reds
  there before any SKILL copy can be silently wrong. The SKILL copies can still drift into
  describing an arm the tool no longer has; that drift is visible in the diff of any change to the
  taxonomy, which necessarily touches the tool and its suite.
- **The audit ledger's THIRD copy** — the hook's jq object literal in `audit-tool-calls.sh`, beside
  the live `audit-row-fields` group. A jq construction expression and a prose field list share no
  anchorable bytes. Not reviewer-guarded either: `audit-selftest.sh` Test 9 asserts a real emitted
  row's `keys_unsorted` equals the documented field list exactly, so a field added, renamed or
  reordered in the hook without the docs following fails the suite. Mechanical on both legs, by two
  mechanisms.
- **The audit ledger dir's THIRD site** — `lean-gate.sh` derives `MAIN_ROOT` for many purposes
  beyond the ledger, so it shares no anchorable bytes with the `audit-ledger-dir` block. Held by
  fixtures instead: `lean-gate-selftest.sh` and `lean-reconcile-selftest.sh` each drive the REAL
  hook from a linked worktree and assert their reader finds the result, so a writer-side drift reds
  a reader's suite.
- **The unbound `lean-producer-capabilities` TAG copies** in `lean-reconcile.sh` and
  `run-lean/orchestrate-lean.sh`. Neither is a merge-boundary gate, and drift in either fails CLOSED
  and loudly instead of silently weakening a boundary — which is what earns a marker in the first
  place. A drifted tag in the scheduler's #500 re-entry probe stops re-entry being recognized, so
  the operator meets a preflight reject on the next stopped run, never a green PR.

**Retired — the subject itself is gone.**

- **GH_BOT config-dir basename** (`install-gh-bot.sh` ↔ `claim-issue.sh`): retired by #92 — both
  call `tools/gh-bot.sh`; one ladder remains, so there is no pair.
- **figma node-resolution discipline** (`figma-faithful/SKILL.md` ↔ `figma-faithful-spec/SKILL.md`).
  The coupling was REMOVED rather than guarded: figma-faithful is now the canonical home and the
  spec skill carries the operative one-liner plus a by-name pointer, so there is no second copy to
  anchor. The deltas that remain are genuine divergences, not copies — it also uses
  `get_code_connect_map`, its terminal sentence forbids transcribing from a static image, and it
  deliberately omits the parent-frame capture. A `verbatim` relation would fail on the first
  legitimate edit to either side.
- **lean branch prefix** (#413) — `ci.yml`'s `LEAN_BRANCH_PREFIX` ↔ `lean-gate.sh`'s runtime
  derivation of a `lean/` namespace. Recorded rather than silently dropped, because the reasoning
  that justified dropping it became load-bearing. It was declined as non-byte-anchorable, and what
  made that SAFE was that `check-lean-chain.sh` did not classify on the prefix alone. That
  compensating control is now the whole rule: the lane cuts `<branchPrefix><key>`, there is no
  second prefix, and applicability is the key-matched lean spec in the PR's diff and nothing else.
  Both sides ceased to exist, along with the mutual non-prefix-match property they asserted.
- **lean branch-prefix DERIVATION (#359)** — deleted with its subject in #413. It pinned
  `lean_branch_prefix()` across `lean-gate.sh` and `lean-evidence.sh`; both copies are gone.
- **per-ticket corpus dedup (#289).** `retro-corpus.sh` is the sole carrier of the
  basename-equals-ticketKey supersedes rule. Its behavior stays guarded by
  `retro-corpus-selftest.sh` (289 AC-1)/(AC-2)/(AC-3) — live-supersedes-snapshot,
  orphan-snapshots-are-distinct, dedup-before-window.
- **cross-plugin sibling-resolution ladder (#419).** `resolve_sibling()` in
  `plugins/dev-pipeline/tools/resolve-sibling.sh` is the canonical side. The hand-maintained `.mjs`
  mirror beside it was retired with its suite in #574, which also retired the two-language drift
  risk and the lexicographic-vs-numeric version-ordering divergence it tracked. Still declined as a
  group: one implementation left, nothing to compare. The RUNG ORDER remains the contract — the last
  rung is what hits in a real install, where plugins carry independent versions. Guarded by
  `pipeline-doctor-selftest.sh` (rs1)/(rs3), which drive the ladder against a fabricated cache at
  BOTH bash consumers' real depths, lifting each caller's hop arithmetic by sentinel rather than
  injecting its results — because a fixture that supplies `PLUGIN_DIR`/`PLUGINS_DIR` covers the
  ladder and no caller, which is how a structurally dead rung 2 shipped on one consumer while
  reading as shared. Three further copies were each considered and declined for a reason the copy
  supplies: `preflight-selftest.sh` and `doctor-selftest.sh` RE-DERIVE `resolve_sibling_plugin_root`
  against `check-model-tiers.sh` rather than copying it (that copy lives one level under its plugin
  root and uses two and three hops; these live three levels under theirs and use four and five —
  the hop constants ARE the contract and legitimately differ). Against EACH OTHER they do not
  differ, which is why that pair IS pinned, and is a live group today. `doctor-selftest.sh`'s
  `resolve_sibling_file` has the same divergence keyed on a file rather than a marker dir.
  `check-emit-deadline.sh` shares a directory with `check-model-tiers.sh` so the hop constants do
  transfer, but it walks an unbounded set of plugin names instead of resolving one and unions both
  layout shapes rather than taking the first that hits — pinning it would mean carrying a dead copy
  purely to be compared. All three now run under `tools/install-topology-selftest.sh` from a staged
  cache, and `check-emit-deadline-selftest.sh`'s B6-B9 drive the real script from staged monorepo
  and cache shapes. Revisit if a SIXTH site grows the ladder, or if any further pair converges on
  identical hop constants.
- **`check-pipeline-chain.sh`'s `REQUIRED_MARKERS`.** The generated `case` region and the schema
  table that held the other copies are both gone, so there is no pair to express. It kept its
  markers after that, on the reasoning that a future row would then be cheap; #604 removed them,
  because under discovery a marker with no counterpart reads as a pair and is not one.
  `check-pipeline-chain-selftest.sh` asserts the list parses non-empty, so a rename fails loudly.

**What does NOT belong in a lockstep group**, from the manifest's own header and kept here: a pair
already mechanically enforced elsewhere — model tiers (`check-model-tiers.sh`), the reviewer
registry, the section catalog, the text-contract carriers, config-lint ↔ schema (the
`modelOverrides` tier enum is driven from both sides in `config-lint-selftest.sh`: every
schema-declared tier must be accepted, and config-lint's rejection message must name exactly the
schema's enum). Duplicate machinery is worse than none.

## The runtime shim

Workflow `.mjs` scripts are not node-importable: they carry a top-level `return` and reference
runtime-injected globals. That made them look untestable, and the repo settled for token greps.

They are testable. Strip the meta block and wrap the rest:

```js
(async (agent, parallel, pipeline, args, log, phase, budget, workflow) => { …body… })
```

The top-level `return` becomes a legal return from the arrow, and every injected global arrives
as a parameter the test controls. Drive it with a behavior queue of canned agent outputs and
assert on what the workflow actually returns.

The mechanics live in `workflows/runtime-shim-lib.mjs` — import them. `runtime-shim-selftest.mjs`
consumes it for per-workflow dispatch-ladder cases.

Notes from building it:

- Model the runtime faithfully. A schema-free dispatch resolves to **text** the workflow parses
  itself; a schema-carrying dispatch resolves to an already-validated **object**. Getting this
  backwards makes cases fail for the wrong reason.
- The meta-strip is a balanced-brace scan, not a parser. That is safe only because
  `runtime-shim-selftest.mjs` Case R lints every workflow for meta-literal purity (relocated
  from the retired design-sync-selftest.mjs Case I, #574) — and "every"
  is a **list** of workflow directories. One directory is in it today — the plugin's own
  `workflows/`. Adding a directory means adding it to Case R's list **and** to
  `tools/check-bounded-exploration.sh`, which is anchored the same way — a workflow outside
  the list is unlinted, which makes the meta-strip unsound for exactly the files it is used
  on. Neither edit can be silently skipped: both sites discover every `workflows/` directory
  under the PLUGIN ROOT and fail on one that is missing from the list. That root widened in
  #348 for a reason worth keeping: while the sole workflows dir lived under `skills/`, a
  discovery scan rooted at `skills/` was sound; once it moved out, that scan matched nothing
  and the self-check would have been silently vacuous.
- `workflow` is **last** in the parameter list, and adding a global must stay an append —
  inserting one shifts every existing positional call site, and cases then fail for reasons that
  look like production bugs. No shipped workflow invokes it since #574 retired the nested
  dispatcher (mutation-gate.mjs); the parameter mirrors the runtime's injection set, and a
  workflow that never calls it is driven by omitting the argument.
- A script that drives a workflow must `process.exit()` explicitly. The dispatch ceiling timers
  keep node's event loop alive, so merely reaching the end of the file hangs for fifteen minutes
  rather than returning.

## The shell equivalent: library mode

The same problem shows up in shell. A gate script parses arguments, resolves roots and dispatches
a subcommand the moment it is sourced, so a *pure* helper inside it — a formatter, a parser — can
only be reached through whatever subcommand happens to call it. When no subcommand reaches a
branch, the tempting move is to re-declare the helper in the suite, which is the mirror harness
this repo forbids: a copy cannot fail on a production edit.

`lean-gate.sh` answers it with `LEAN_GATE_LIB`. Set it, source the script, and it defines its
functions and returns before the dispatch; the suite then calls the real production body. It is
what `lean-gate-selftest.sh`'s `(fp1)`–`(fp4)` use to fixture `md_table_prettier` against
byte-exact goldens, including a width case no render the gate can perform would reach.

One caveat, and it bites under `set -u`: the script's own argument parser consumes the inert
placeholder arguments library mode supplies, so the sourcing scope has no positional parameters
afterwards. Copy anything you need out of `$1` **before** the `.`.

### Opportunistic oracles: a SKIP reports nothing

Goldens like those are a claim about *another program's* output, so they want a case that
re-derives them from that program when it is installed — `(fp5)` against a local prettier. Two
rules, both learned the expensive way on the case that introduced the pattern.

**Feed the oracle the oracle's input grammar, not the producer's.** `md_table_prettier`'s contract
is that the markdown delimiter row is *not* supplied — its dash count is a function of the widths
the padder computes. Handing prettier that same input makes it read a paragraph rather than a
table, rewrite nothing, and compare an unformatted paragraph against a padded golden: a case that
cannot pass, and that passes review only because it never runs. Splice the row in first.

**Probe a skip-guarded case by supplying the resource.** A case that reports SKIP is asserting
nothing, and neither CI nor a local sweep will tell you which — this lane has no node by design,
so the branch skips there forever. Put a real binary on `PATH` and run the suite before believing
it. The same move applies to any fixture whose guard is "when X resolves".

## Test-the-tests: the mutation sweep

Every tier above answers "is this behavior guarded?". None answers "does the guard actually fail
when the behavior breaks?" — and that is what "every new guard ships a red-on-mutation demo" asks
each author to do by hand, once, at authoring time. `tools/mutation-sweep.sh` makes it a standing
measurement instead: it mutates the repo's shell guards, runs their paired selftests, and reports
which mutants **survive**. A survivor is a regression the suite would not have caught.

**Pairing is a rule, not a list.** Every git-tracked `*.sh` that is not a `*-selftest.sh` and is
not under `*/evals/*` or `tests/hooks-smoke/` must resolve to its killer(s) via directory-scoped
same-stem pairing, a `tools/mutation-pair-map.tsv` row, or a reasoned
`tools/mutation-exclusions.tsv` row. An unaccounted guard is red — that is what keeps the data
files honest as the tree grows, and why adding a guard with a cross-named suite means adding a
map row. Same-stem is directory-scoped, never basename-anywhere: two `second-shift-doctor.sh`
files exist at different paths, and only one of them is swept.

**Two mutant tiers, deliberately asymmetric on validity.** Generic operators
(`tools/mutation-operators.tsv`) are machine-enumerated over every paired guard, so a mutant that
will not parse is a harness artifact — skipped and logged, never red. Catalog mutants
(`tools/mutation-catalog.tsv`) are hand-authored against named sites, so a sed that no longer
applies, or yields invalid output, is **anchor drift = red** — the
`check-lockstep-pairs-selftest.sh` convention.

**The earn-your-keep rule, scoped.** A register row survives only if it names the regression
class it — and nothing else already in the corpus — catches. It binds **catalog rows and
execution surfaces**: every `tools/mutation-catalog.tsv` `note` states what a survivor would
mean (or, for a timeout-kill row, what a lapse would cost), and a row that cannot say this has
no reason to exist. It does **not** bind baseline rows that record "unkillable by construction"
— a comment site or a structurally-inert flip that no fixture, and no fixture that could exist,
would ever kill. Applying the rule to those deletes the row that exists to *accept* a permanent
survivor, which reds the next sweep on exactly the site the row was baselined to explain. That
class shrinks by removing the site from enumeration (comment exclusion, above), never by
deleting the row that documents an accepted one. Read literally — "with a dated incident" — the
rule would also fail most of today's catalog, which names its regression class in prose without
citing when it was found; read as written above, it does not, and #581 re-verified all 66
catalog rows against it without deleting any.

**A comment line is not a site.** Generic enumeration drops every matched line matching
`^[[:space:]]*#` before the ordinal counter, so a comment contributes no mutant *and consumes no
ordinal* — adding or deleting one re-keys nothing. The reason is that a comment flip changes no
reachable behavior, so nothing can kill it: each such site was a permanent baseline row asserting
only that a comment cannot be killed, and at `k=2` they routinely occupied ordinals 1 and 2 and
pushed the guard's real code sites out of the swept window entirely. Measured on the tree that
carried the change: **41 of 142 ordinal-keyed baseline rows** were comment sites and are gone,
**6** surviving rows re-keyed, and **28** real code sites moved from beyond-budget into budget.
Two residues are accepted rather than discovered: the rule is LEADING `#` only, so a trailing
comment on a code line still enumerates (the operator matches are substring EREs — 4 of those 142
rows sit on a code line containing a `#`), and `#`-headed heredoc *payload* stops enumerating with
real comments (0 such lines in today's swept universe). The heredoc- and quote-aware classifier
that would fix both is roughly an order of magnitude more code and would live inside
`tools/mutation-sweep.sh`, the one file the sweep is forbidden to sweep — unguardable parsing
shipped to delete register rows is a net add. When an operator's matched lines were *all*
comments, the report's `sites_comment_only` cell says so per operator, so that state never reads
as "no applicable site".

**Survivors are data, not a red build.** Only a survivor absent from `tools/mutation-baseline.tsv`,
or a named infra failure (`baseline-missing`, `baseline-environment-mismatch`,
`baseline-keying-mismatch`, `site-key collision`, `no-sha-binary`, an unrunnable pair,
an unaccounted guard, sandbox failure, `pool disagreement`), reds a lane. A baselined survivor is
report-only; a baselined survivor that is now killed is a warn to shrink the baseline.

**An unrunnable pair is infra red.** Every killer must exit 0 against the unmutated sandbox before
any of its guard's mutants are scored, so a broken or environment-starved suite can never report
its guard as fully killed.

**A survivor that would red the lane is re-derived serially first.** The worker pool has been
observed scoring a mutant `SURVIVED` that its own paired selftest demonstrably kills — twice in one
nightly, on the same idiom a third guard killed in that same run, which is what proves the verdict
was not a fact about the code. So before a baseline-absent survivor is allowed to red anything, the
mutant blob is re-installed and its **full ordered kill set** re-run once, serially, on a sandbox no
worker has touched: the pool is the suspect, so the oracle must not use it. If the serial run kills,
the corrected `KILLED` verdict goes into the report, the counts and the cache, and the lane reds
with `pool disagreement` instead — naming the harness rather than accusing an innocent guard. Free
on a green run (zero baseline-absent survivors is zero extra suite runs), and seed mode re-verifies
every survivor before it writes the baseline, because seed is the one lane that would otherwise
record a fabricated survivor permanently and silently. The gate is asymmetric on purpose: survivors
are the only class that reds, so a mutant the pool wrongly scores KILLED is still invisible.

**Every killer runs under a wall-clock bound**, and a timed-out killer counts as a **kill**,
logged by name. The bound is per suite — `4 x the suite's measured unmutated time`, floored at 60s
and capped at `MUTATION_SWEEP_KILLER_TIMEOUT_S` (300s) — because a *flat* bound bounds one killer
but not a *shard*: a guard whose mutants all spin costs `k` x the bound. The first bounded seed run
showed exactly that gap. Nine shards went green, including the two that had been fatal, each naming
its own culprit; one shard still burned a 60-minute budget against a ~15-minute cost model, and its
job timeout destroyed both the log and the artifact, so it yielded nothing. Scaling to the suite
puts the saving where the mutants are (the fast suites) and leaves the slow end's margin alone. This is not a tuning knob — it is what makes
the sweep diagnosable at all. A mutant can make its guard *spin*: `cmp-z` inverts the EOF-tolerance
clause of the standard read idiom (`while IFS= read -r line || [[ -n "$line" ]]` becomes
`|| [[ -z "$line" ]]`), which at EOF is permanently true. An unbounded killer then blocks its shard
forever — no further `swept` line, death by job timeout, log blob unfinalized, no artifact — which
is how two successive 10-shard nightlies lost the same three shards without yielding one datapoint.
Counting the timeout as a kill follows Stryker and PIT: the suite did surface the defect, and
scoring it a survivor would red the build on a mutant nothing can kill.

**A shard that blows its bound no longer publishes nothing** — the "no artifact" half of the
account above is history, not the current mechanism. Two changes, and neither is the fix alone:
`--report` is the **streaming sink** rather than a buffer copied in `finish()`, so the report file
exists from the sweep's first moment and the upload step (which reds on an empty directory) always
has something to publish; and the `sweep shard` **step** carries its own `timeout-minutes`, so
blowing it is an ordinary step failure the job survives — the log finalizes and the `if: always()`
upload runs — instead of a job cancellation. Be exact about what each buys: swept guards' rows are
emitted after the whole worker pool finishes, so a shard killed *during* the pool publishes the
report header and shard 1's excluded-guard rows, and its per-mutant evidence is in the **log** that
the step bound rescued. What tells the two apart afterwards is the non-dotted `mutation-complete`
marker, which only `finish()` writes: merge reds by name (`merge truncated`) on a report that
arrives without one, and keys its seed/enforcing arity check on completed shards only, so a
truncation is never misreported as a mode mismatch.

None of that reaches the *other* death class. The 83-84 minute "lost communication with the server"
failures run no step at all, so the streamed report dies on the runner with everything else;
covering those would need out-of-band publication. Partial-evidence coverage is not total coverage.

Three tracked guards carry that idiom, and the `k` budget — not any property of the guards — is
what decided which were armed: `predecessor-gate.sh` held it at `cmp-z` ordinal 1 and killed its
shard, while `scaffold-review-context.sh` holds it at ordinal 5
and was never mutated at `k=2`. Budget is not safety. That fourth site is now armed by the
`scaffold-spin-at-eof` **catalog** row rather than by raising `MUTATION_SWEEP_K`, which would have
armed every other guard's ordinals 3–5 for the sake of one named site; `k` is unchanged, so no
baseline re-seed and no cache-key change follow. Its expected verdict is a kill by timeout, a class
the catalog's header block now documents explicitly — such a row's value is the arming plus
anchor-drift loudness, not a survivor prediction.

What kept that site invisible for two nightlies was the report, not the budget: a guard with no
applicable site and a guard whose sites all sit past `k` produced the same silence. The report TSV
column **`sites_beyond_budget`** ends that. It carries per-operator detail in the plus-joined
`paired_selftest` style (`cmp-z:3`), counts only sites the enumerator declined for budget — an
unparseable or no-op flip is a harness artifact, not darkness — and is **report-only, never red**,
the posture `tools/mutation-operators.tsv` already states for non-application. `sites_comment_only`
was appended after it on the same terms. Both go on the END of the row because `report_row()` in
the companion selftest reads `$5/$6/$7` positionally and `--mode merge` compares shard headers
byte-wise.

**The standing `k=2` question is re-derived, not inherited.** It used to rest on "every site past
ordinal 2 is dark sweep-wide", measured while comment lines were still sites — and that measurement
counted a displacement whose dominant cause has since been removed. Excluding comments moved **28**
real code sites from beyond-budget into budget and vacated **43** unkillable ones from the `k=2`
window, so the darkness the argument pointed at was substantially bookkeeping rather than budget.
What survives the re-derivation is the *pair of examples above*, and they survive intact: neither
`predecessor-gate.sh`'s `cmp-z` ordinal 1 nor `scaffold-review-context.sh`'s ordinal 5 is a comment
line, so both ordinals are unchanged by the exclusion and "budget is not safety" still holds on its
own evidence. The question of whether `k=2` is the right budget therefore stays open — but it is
now open against the post-exclusion measurement, and re-arguing it means re-measuring, not quoting
the pre-#579 numbers.

**Generic survivor ids are content-keyed, so identity is not positional.** A site's id is
`<guard>::<operator>::<key>`, where `<key>` is 12 hex of a sha256 over the whitespace-normalized
matched line plus that line's occurrence index among the operator's *normalization-identical*
matched lines in the same guard. Inserting a killable line above a site, moving a block (whether or
not the move re-indents it), adding or deleting a comment, and raising `k` all re-key **nothing**.
Only editing a site's own line, or removing one of its normalization-identical siblings from
earlier in the file, changes a key. `git patch-id` was rejected for the job precisely because it
hashes a hunk's *context* lines, which is the sensitivity this keying exists to remove.

Derive an id without a scoring run with `bash tools/mutation-sweep.sh --emit-site-keys`, which
prints `<guard><TAB><operator><TAB><ordinal><TAB><key>` for every enumerated site. The ordinal is
still emitted — the **budget** is positional even though identity is not, and `k` still admits the
first two applicable sites in file order — but nothing keys on it.

**One obligation lands on ordinary PRs.** Editing a guard re-anchors any catalog row addressing
it. Catalog rows are pattern-addressed for exactly that reason — a bare line address is rejected,
because during this harness's own intake the `check-emit-deadline` site moved by 68 lines between
two runs a day apart, and only the expression-addressed entry survived. The generic tier's
matching obligation is gone: with content keys there is nothing for an ordinary edit to re-key.

**Where it runs — two surfaces, both in CI.** Diff-scoped on every PR (the `mutation-sweep-pr`
job) — guards whose kill set is not a single fast suite defer to nightly rather than being graded
against a weaker criterion than the one that produced the baseline — and wholesale in the nightly
`mutation-sweep.yml`. Kill verdicts are only comparable inside the canonical environment
(ubuntu-latest, `SKIP_STRESS=1`), so local runs are advisory and say so.

**There is deliberately no third surface.** Until #580 `lean-gate.sh` milestone 3 ran a
`--mode pr` sweep in-session (decision D-18) whenever the target repo carried a
`tools/mutation-sweep.sh`. It issued the **identical** invocation the PR job above already makes,
so it was CI-duplicated work idle-blocking a build session — on a contended developer machine,
where a killed sweep orphans fixtures that poison later sweeps because macOS `mktemp -d` ignores
`TMPDIR`. It was measured before it was deleted: over 28 branches (2026-08-11..18), 17 of 22
guard-touching PRs produced 11–71 verdicts each at ~5s wall in CI, so the merge boundary
re-derives the same truth for free. The seam is therefore repo-carried **and repo-run**: a
consumer that ships its own `tools/mutation-sweep.sh` wires its own CI for it, and no shipped
gate looks for that file.


### What it costs, and the three things that stopped it costing that

The sweep's wall time is `Σ over guards (mutants × paired-suite seconds)`, and for a long time every
one of those seconds was serial on one core — 256s for a three-guard diff, paid once per **fix
round** rather than once per PR. Three levers removed it, and each is visible in the run's own output
rather than asserted here.

**Every run prints what it cost.** The closing `timing:` line reports wall seconds, how many verdicts
were computed by actually running a paired suite, how many came from the cache, and the pool size. A
claim about the speedup is checkable against that line; a remembered figure is not a measurement.

**1. Verdicts are memoized — in the advisory lane only.** The key is:

```
sha256(mutation-sweep.sh) + sha256(mutated guard) + sha256(each paired suite, in kill order)
                          + MUTATION_SWEEP_K + environment (RUNNER_OS, SKIP_STRESS,
                            killer-bound knobs, MUTATION_SWEEP_EARLY_EXIT, MUTATION_SWEEP_FAIL_PATTERN)
```

**The key is narrow, and it is not sound.** A third file can flip a verdict with the guard and all
its suites byte-identical: `lean-gate.sh` shells out to four sibling scripts, and
`cost-block-selftest.sh` reaches `pipeline-cost-block.sh`'s own resolution of `gh-bot.sh`.
A whole-tree key would be sound — and would also
drop the hit rate to zero, since the sweep sandboxes HEAD and every fix round is a new commit.

What makes that an acceptable trade rather than an unsound one is **the lane**: the cache is neither
read nor written when `GITHUB_ACTIONS` is set. A stale verdict can therefore only make a *local,
advisory* run optimistic, and the cost of that is learning about a baseline-absent survivor one CI
cycle later. **CI is the authority and always runs cold.** `MUTATION_SWEEP_CACHE=0` disables it
locally too.

**Invalidation, exhaustively.** Editing the guard; editing *any* paired suite; editing
`mutation-sweep.sh` itself; changing `k`, `RUNNER_OS`, `SKIP_STRESS`, a killer-bound knob, or the
early-exit trigger (`MUTATION_SWEEP_EARLY_EXIT`, `MUTATION_SWEEP_FAIL_PATTERN`). Three are worth
naming. Editing the **suite** matters because adding a test case can kill a previously-surviving
mutant, so a cache keyed on the guard alone would serve a stale `SURVIVED` forever — green, wrong,
and invisible in the report. Editing **this harness** matters because a change to the kill criterion,
the early-exit trigger or the killer bounds changes what a verdict *means*; hashing the file itself
removes the human discipline a hand-bumped schema constant would need. The stated cost of that:
a PR editing the harness runs fully cold. And the **kill criterion knobs** are in the key for the
same reason the killer bounds are — a run under a custom `MUTATION_SWEEP_FAIL_PATTERN` scores
against a different definition of "killed", which the precheck's every-run assertion does not
close: that assertion covers the *unmutated* suite only.

**`MUTATION_SWEEP_JOBS` is deliberately NOT in the key, and that residual persists.** Pool
contention can turn a would-be survivor into a timeout `KILL`, and once cached that verdict is
served back at any pool size — including `JOBS=1`. Keying on it would cost most of the hit rate,
since the loop this cache exists for re-runs at one pool size. The residual leans the safe way
(it hides a weak test rather than inventing a finding), CI never reads the cache, and
`MUTATION_SWEEP_CACHE=0` is the escape hatch when a survivor set is in doubt.

**Storage.** `${XDG_CACHE_HOME:-~/.cache}/second-shift/mutation-sweep/<repo-basename>/`, overridable
with `MUTATION_SWEEP_CACHE_DIR`. Outside every checkout and never committed — an in-repo untracked
directory would also make `git status --porcelain` non-empty, which has broken a working-tree
attestation before. Per repo rather than per machine, because two checkouts can hold identical guards
and suites while differing in one of those third files. A corrupt or unreadable entry is a **miss**,
never a pass: the reader requires exactly one well-formed record line and falls back to a real run
otherwise. The store is bounded (`MUTATION_SWEEP_CACHE_MAX`, default 20000) and clears wholesale when
it exceeds that, which costs one cold run.

**The precheck is skipped, not cached.** Every killer must be green on the unmutated sandbox before
any of its guard's mutants are scored — and that precheck is itself a paired-suite execution, so a
run claiming "zero executions" has to skip it. A guard whose every mutant hits the cache skips its
precheck entirely; a guard with even one miss pays it. The precheck also runs **serially, once per
distinct suite, before the pool**: its timings set every killer bound and feed
`tools/selftest-suite-timings.tsv` (#641: shared with `run-selftests.sh`/`check-sweep-bound.sh`,
which apply their own, separate 9s threshold to the same file), so taking them under the pool's
own contention would measure the pool rather than the suite.

It is also where **slow-list drift is warned**, and the placement is the point. A suite that has
grown past the 5s bar while absent from `tools/selftest-suite-timings.tsv` keeps its guard in the PR
lane, where every mutant that makes the guard spin costs the full killer bound; enough of them and
the job dies on its own 15-minute ceiling — before the report, and therefore before any warn the
report would have carried. `lean-gate-selftest.sh` reached **143s** against that 5s bar exactly this
way, and the three PR runs it killed read only as "timed out". Warning from the precheck is what
makes the diagnosis outlive the timeout it diagnoses. It stays a warn, never a red: the list is a
cost record, and a stale row costs wall clock rather than correctness. Fix it by adding the row in
an ordinary PR.

**2. Mutants run in a pool.** One sandbox per worker, created lazily and reset between items — so
no two concurrently-running mutants share a tree, and disk stays at `pool × ~7MB` rather than growing
with the mutant count. Size defaults to `min(cores-2, 8)` and is set by `MUTATION_SWEEP_JOBS`;
`MUTATION_SWEEP_JOBS=1` is the serial harness exactly.

**Reset means the whole tree, not the mutated path.** Reverting the one file a mutant was spliced
into leaves behind everything the killer *created*, and that is not inert: the operator alphabet
writes one placeholder token into every guard it mutates, making the token a shared namespace on
disk. A mutant whose `mkdir -p "${VAR:-real}"` became `mkdir -p __MUTANT_DEFAULT__` is killed
correctly and leaves the directory; a later mutant in that sandbox whose
`mktemp "${TMPDIR:-/tmp}/x.XXXXXX"` became `mktemp __MUTANT_DEFAULT__/x.XXXXXX` then succeeds where
it had to fail, and is scored SURVIVED on its predecessor's litter. So each item is applied to a
sandbox cleaned of untracked *and* ignored files, the oracle's reused sandbox included. Case (al)
holds the line.

The report is a function of the work list and nothing else: every verdict is written to its own file
and read back in item order, so a parallel run's survivor set, counts and report TSV are
**byte-identical** to a serial run's. Case (ac) of `mutation-sweep-selftest.sh` proves it — and
proves the parallel run really overlapped *first*, since two serial runs would also agree.

**A suite may not write a literal path outside its own `mktemp` tree.** Two mutants of one guard run
the same suite at the same time, so a fixed `/tmp/<name>.out` turns an interleaved write-then-read
into a verdict about the wrong mutant. Three suites carried exactly that and were fixed; case (k)
lints the whole corpus for it, because the alternative symptom is flake in somebody's nightly.

**The pool presses on the killer time bound, and the direction matters.** Contention makes a suite
slower and a timeout scores as a **kill** — the direction that *hides* a weak test rather than
inventing a finding. The bound is `4 ×` the suite's own serially-measured time, floored at 60s, which
is wide for a single-threaded suite given one worker per core; and every timeout is logged by name
(`killer timeout (Ns exceeded, scored as KILLED)`), so a bound hit is visible data rather than a
silent verdict. If a nightly shard starts naming timeouts it did not name before, read that as the
pool pressing on the bound, not as the suite getting stronger.

**3. A killed mutant stops at the first `FAIL:`.** The verdict is settled there, so the killer's
process group is reaped rather than run to completion, and the line is logged so an early kill is
never silent.

The trigger rests on an invariant — **a green suite emits no `FAIL:` line** — and the harness
**asserts it every run** rather than trusting the one-off corpus measurement that established it
(63/63 suites, zero such lines). The unmutated precheck checks its own output, and a suite that
passes *while printing the trigger* is an **unrunnable pair**, named and red. That is the same class
as a suite that cannot run at all, and for the same reason: neither may be allowed to report its
guard as fully killed, since every mutant of that guard would otherwise be scored KILLED on prose.
`MUTATION_SWEEP_EARLY_EXIT=0` disables early exit; `MUTATION_SWEEP_FAIL_PATTERN` changes what it
looks for.

A reaped suite never runs its own `trap … EXIT`, so killers run with `TMPDIR` pointed at a
per-item scratch directory the harness removes unconditionally — early exit and both killer bounds
included.

### Runbook: the sweep just reded

**`baseline-absent survivor: <guard>::<operator>::<key>`** — usually your own doing: you wrote a
line the paired suite does not exercise. The red line *is* the answer. Copy each named id into
`tools/mutation-baseline.tsv` as `<survivor_id><TAB><note>` and commit it **in the PR that wrote
the site**. No dispatch needed — the failing log already names every id. Before pasting, read the
mutant: since ids are content-keyed, a survivor that appears here sits on a line this diff *wrote
or edited* rather than on one a shift renumbered — which usually means the test you added does not
test anything.

**`baseline-keying-mismatch: … declares '<header>', this sweep keys survivors 'content-v1'`** —
the baseline was written under a different identity function, so *every* row would report
`now KILLED` and *every* survivor `baseline-absent`. Checked in every mode, advisory runs included,
because a doubled false signal does its worst damage on the run nobody re-reads in CI. Migrate the
file rather than re-seeding it: `bash tools/mutation-sweep.sh --emit-site-keys` gives the
`<guard>/<operator>/<ordinal> → <key>` mapping, and re-keying the rows preserves the curated notes
a `--seed` run would flatten.

**`site-key collision: two enumerated sites of <op> on <guard> both key to <key>`** — a 12-hex
truncation collision between two sites that normalize *differently* (the occurrence index already
separates ones that normalize the same). It ranges over every enumerated site, not just the emitted
ones, so it fires before a rising `k` could turn it into two rows silently sharing one identity.

**`no-sha-binary`** — neither `sha256sum` nor `shasum` resolves and a site key had to be computed.
Identity is content-derived, so the sweep reds rather than inventing one. Fired lazily, at the
first key: `--mode merge` and a nothing-to-sweep PR run compute no keys and stay green.

**`pool disagreement: <id> was scored SURVIVED by the worker pool but is KILLED by a serial
re-run`** — the harness contradicting itself. The named mutant is already reported as `KILLED`;
nothing is wrong with the guard or its suite, and **a baseline row is the one thing that must not
be added** — a row asserts that no kill criterion exists, and this line is the proof one does.
The lane is red so the pool race stays under pressure, not because the tree is. Read it as a
harness bug report and route it to the pool-isolation work.

**`catalog anchor drift: catalog::<id> left <guard> byte-identical`** — a hand-authored
`tools/mutation-catalog.tsv` sed no longer matches. Either the anchor moved (re-anchor the row
against the new text) or the branch it guarded is gone (strike the row). Do not invent a site to
re-anchor onto; if the behavior left, the row leaves with it.

**`unaccounted guard`** — a new `*.sh` with no killer. Give it a same-stem `*-selftest.sh`, a
`tools/mutation-pair-map.tsv` row, or a reasoned `tools/mutation-exclusions.tsv` row.

**`pair-map guard does not exist`** — you deleted a guard and left its rows behind. Delete them too,
catalog rows included.

**Re-seeding the whole baseline** is a `workflow_dispatch` of `mutation-sweep.yml` with
`seed=true` — the explicit re-baseline override, which never enforces. That is the *only* entry
point: seed mode otherwise triggers on an absent baseline, and a `schedule` run never seeds. Reach
for it when the baseline is wholesale stale (a mass rename, a `MUTATION_SWEEP_K` change), not for
a handful of shifted rows.

**Seed runs force `RC=0`.** A green seed is not a clean seed — `grep 'RED:'` the shard logs
regardless. A run has shipped a reding baseline on exactly this mistake.

**A green PR does not mean a green nightly.** The PR lane sweeps only guards whose kill set is a
single fast suite; everything paired to a slow or multi-suite killer (`lean-gate-selftest`,
`scenario-liveness-selftest`, anything in `tools/selftest-suite-timings.tsv`) reports
`deferred-to-nightly` and is **not graded on your PR**.
Edit one of those and any new survivor surfaces at 03:17 UTC, on someone else's morning. If your
diff touches a deferred guard, expect to learn about it from the nightly rather than from your PR —
though content keying means only a site you actually *wrote* can produce one.

**All-deferred is not silently green (#582).** When every in-scope guard defers — 23% of
guard-touching PRs, measured by the #567 audit, concentrated on `lean-gate.sh` — the job still
exits 0, but it no longer reads the same as "swept your guards, found no new survivors". It prints
an unmissable `WARN:` line naming the count and the reason(s), and, on real CI, a `::warning::`
check-surface annotation plus a job-summary block when `GITHUB_STEP_SUMMARY` is set. Sweeping at
least one guard is unchanged — the warn fires only when the graded count is exactly zero.

## Adversarial tier (operator-run, never CI)

The model tier cannot live in CI without API-billed calls. It runs on demand, by an operator, in
a session. It is the tier that produced the audit behind epic #213.

**When to run it:** before a release train, after a large refactor of the gate machinery, or
when the suite "feels" green in a way nobody trusts. Not on a schedule — it is expensive, and a
schedule turns it into noise.

**The recipe:**

1. **Classify every check in every suite.** One agent per file, fanned out. Each check gets a
   class: behavioral, fixture-tautology, prose-presence, mirror, other. Force a per-file verdict
   of KEEP / TRIM / MERGE / DELETE with reasoning.
2. **Require mutant predictions.** For each file, the agent proposes concrete mutations to the
   guarded code and predicts whether the suite catches them. Predictions that say "survives" are
   the actionable output — they are gaps, stated in advance.
3. **Send an independent skeptic after every prune candidate.** A separate agent, with no access
   to the auditor's reasoning, tries to **refute** the prune: find one realistic regression that
   only the doomed check catches. This is the load-bearing step. In the #213 audit the skeptics
   upheld 10 prunes and **refuted 2** — and both refutations were correct, catching coverage the
   auditor had misclassified as redundant.
4. **Treat skeptic conditions as binding.** A skeptic that says "safe *only if* X is retained"
   has written a requirement, not a footnote. Several of #214's steps exist solely because a
   skeptic attached a condition.
5. **Land the evidence with the work.** Audit reasoning and skeptic verdicts belong in the issue
   body, so the next reader can tell a considered deletion from a careless one.

**What it is not.** Not a gate, not a CI job, not a substitute for the deterministic tiers. It is
a periodic audit whose output is *issues and prunes*, executed by the tiers above.

**Cost is real.** The #213 audit ran ~40 agents over ~2.6M tokens. Budget for it deliberately.

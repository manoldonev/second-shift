# Testing

How this repo tests itself, what tier a new test belongs to, and the one tier that
deliberately does not run in CI.

The short version lives in [`CLAUDE.md`](../CLAUDE.md) under **Verification**; this file
carries the reasoning and the operator-run adversarial recipe.

## How the sweep runs

One script owns it, locally and in CI:

```bash
SKIP_STRESS=1 bash tools/run-selftests.sh
```

`tools/run-selftests.sh` discovers every `*-selftest.sh` under the repo, runs `SELFTEST_JOBS`
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
| discovered-minus-excluded ≠ suites actually run | exit 2, `silent truncation` — a faster sweep that ran fewer suites is the failure mode this design is most exposed to |
| `--exclude` matches no discovered suite | exit 2, `stale exclusion` — the posture a stale `install-topology-known-red.tsv` row already carries |
| no suites discovered, or every suite excluded | exit 2 — a sweep that runs nothing is never green |

`--exclude` has four callers: both CI selftest jobs (`ci.yml:119`, `ci.yml:394`) and both
nightly-guards selftest lanes (`nightly-guards.yml:100`, `nightly-guards.yml:116`) all pass
`--exclude tools/install-topology-selftest.sh` — inside the sweep it contends with the very
suites it re-runs from the install cache, which is what the install-topology section below
measures. `install-topology-selftest.sh` itself runs nightly, not in a job alongside any of
these. The suite stays *discovered*: the exclusion names a path that must keep existing, so
renaming the suite reds CI instead of silently double-running it.

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

It exists because the sweep re-derives the same verdict on every push. `statectl-selftest.sh` alone
is 149s of a 171s ubuntu sweep, and most PRs touch nothing it reads.

**The risk is a silently skipped gate**, which is this repo's cardinal failure mode, so the
containment is the load-bearing part and the hashing is not. Four properties, all asserted in
`tools/run-selftests-selftest.sh` against fixture trees:

1. **Fail-closed by default, twice.** A suite with no row is always run, and the cache as a whole
   is off unless `--cache-dir` is passed. The mandated local recipe in `CLAUDE.md` does not pass
   it, so a bare local sweep is still cold — and so is the nightly leg below.
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

Only PASS is ever recorded, and only by the parent process after the replay has scored the run — a
red suite, and a suite whose worker died without a verdict, write nothing. That falls out of the
shape rather than being separately enforced. A marker that is not exactly the one well-formed
record line is read as a **miss**, never as a pass.

Every skip prints the suite, the key, and every input blob id behind that key, so a log reader can
tell a skip from a suite that quietly stopped being discovered. The summary line reads
`N scored, M run, K served from cache` for the same reason: reporting the larger number as work
performed is the faster-green misreading the rest of this section is about.

**Adding a row is the risky edit in that file, not the cheap one.** Derive the input set from the
suite, never from a ticket: `statectl-selftest.sh` reads six things beyond the three an eyeball
lists, including the generator it diffs `statectl.sh` against and the stage docs it drift-checks.
Where a suite's composed set is really its transitive closure — `scenario-liveness-selftest.sh` is
the worked example, and is deliberately **not** in the table — drop the row. A dropped row costs
seconds; an under-declared one costs a gate.

**Derive the closure, not the file list.** Neither mechanized rule reaches depth 2: a row set can
name the suite and its subject and still under-declare, because that subject resolves a third file
at run time. Both shipped sets needed one — `statectl.sh` executes `tools/ledger-corroborate.sh`,
`pipeline-cost-block.sh` executes `tools/gh-bot.sh`, and the generator parses `eval-criteria.md`
beside `state-schema.md`. Follow every `$here/`-style resolution out of every declared script until
it terminates, and say in the row comment where it terminated.

`CACHE_EPOCH` is a constant in the runner rather than a knob. The key covers repo content —
including `run-selftests.sh`'s own bytes, which is property 2 applied to the harness that produces
every recorded verdict — but not the runner image, so an image bump could in principle move a
verdict with every declared input byte-identical; bumping the epoch invalidates every marker on
every lane in one character, and the next run is a full cold sweep. `SELFTEST_CACHE_MAX` (default 5000) clears the store when it
overflows, with the same fail-closed consequence.

This is the inverse of the mutation sweep's cache further down this page, which is local-only and
disables itself in the enforcing lane. The difference is which side holds the authority: there CI
is the authority and must run cold; here CI is the thing being sped up, and the authority is the
nightly wholesale leg.

## Why a tier map at all

CI here is **model-free by design** — no API-billed calls. That constraint is what makes the
tiering non-obvious: a repo whose product is AI tooling cannot test its product the way its
product tests other repos. So the tiers below are the model-free equivalents of the classic
pyramid, plus one tier that is honest about being outside CI.

| Classic tier | Here | Status |
| --- | --- | --- |
| Unit | Per-tool behavioral selftests — execute one script against tempdir fixtures, assert exit code / output / state | Established |
| Contract | `scripts/lockstep-manifest.tsv` + registry and schema lints (config-lint ↔ schema, model tiers, text-contract carriers) | Established |
| Integration | `scenario-liveness-selftest.sh` — composed verdict paths through real scripts to a terminal write | Established, extending |
| Runtime | `workflows/runtime-shim-selftest.mjs` — executes real Workflow `.mjs` bodies with injected fakes | Established (#214) |
| E2E | `e2e-replay-selftest.sh` — full-run replay; every receipt minted by an executed tool | Established (#217) |
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
it composes over are typed in by the harness. `scenario-lib.sh` planted every comment receipt as
`https://github.example/issues/<key>#issuecomment-<n>`, so the post-a-comment → read `html_url` →
record-the-receipt chain was never executed by anything. Worse, planting hides its own failures: the stage-7
checkpoint plant was passing a payload keyed to another ticket, `checkpoint` rejected it, `sct`
discarded the stderr, and both consumers walked stage 7 with no `stageCheckpoint["7"]` at all —
green the whole time. Prefer a shim you execute over a literal you write; where no production tool
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
`plugins/`. Two suites depended on exactly those and were green here the whole time —
`plan-lint-selftest.sh` borrowed the repo's git toplevel for its fixtures, so from an install its
check-5a assertions were skipped wholesale (one failing, two passing vacuously), and
`design-sync-selftest.mjs` walked a fixed `../../../../design-toolkit` path. So: **a fixture owns
its own repo** (`git init` inside a `mktemp -d`), and **a cross-plugin path goes through a
resolution ladder**, never a fixed hop count — `resolve_sibling()` in `pipeline-doctor.sh` is the
reference, mirrored in `.mjs` at the top of `design-sync-selftest.mjs`.

`tools/install-topology-selftest.sh` is the class guard, and it is the reason no new instance of
this needs its own test: it stages `plugins/` at version-keyed paths outside any git repo and
re-runs **every** shipped suite from a `git init`'d consumer cwd, under a per-suite wall-clock
bound. It reds on any failure absent from `tools/install-topology-known-red.tsv`; a listed suite
that passes, and a row matching no suite, are warnings that say "shrink the list".

Its scoring is **55 suites: 49 pass, 6 listed** — and how that number was arrived at is the more
useful thing to know than the number. The first run, on the authoring machine, scored 51 pass /
4 listed; CI scored 49 / 2-red on the same commit, identically on both lanes, because two suites
fail for reasons the authoring machine's environment hid (one needs the `claude` CLI to be
*absent*, one needs bash older than 5.3). **A guard that reports on the environment cannot be
seeded from one environment** — read every "measured here" claim about it as "measured on one
machine" until a different one agrees.

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
machine whose own PATH hides both. It is how the two late rows were diagnosed rather than guessed.

That is also why those two rows are marked ENVIRONMENT-DEPENDENT. They will pass on some machines,
and the guard will duly warn "drop its row". Do not: read the cause and drop the row only once the
suite passes where the cause says it fails.

Re-running the whole shipped set is the price of the class being visible at all, and it is not
small. Suites run concurrently (`INSTALL_TOPOLOGY_JOBS`, default 4 — each suite is a separate
`--run-one` invocation, which is also what gives every concurrent watchdog its own job-control
shell), against **542s** for the serial form. The remaining floor is one suite:
`statectl-selftest.sh` is 94s uncontended and was measured at 244s while a second copy ran.

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
`run-selftests.sh --exclude`. The documented local recipe excludes it too.

The reasoning is a cost/signal ratio, not a judgment that the guard is worthless — it caught two
real defects that were green in-tree the whole time, and it stays. But its cost *is* the shipped
suite set run a second time, which made it the repo's longest job, while the class it guards moves
only when suites change or when packaging/topology changes. On the median PR it was paying the
critical path to re-derive the previous night's answer. Inside the sweep it was also contending
with the second copy of every suite it stages — the 244s-vs-94s statectl figure above — so it was
simultaneously the long pole and the thing lengthening everything else.

**The trade, stated plainly:** a packaging or suite regression is now caught within a day instead
of at PR time. If your change is about how plugins are installed or laid out, that window is not
good enough — run `bash tools/install-topology-selftest.sh` directly, or dispatch the workflow
against your branch. Its 1200s `INSTALL_TOPOLOGY_TIMEOUT` is deliberately left alone: it was sized
for contention that is now gone, but it is a hang detector and re-tightening it needs an
uncontended measurement the nightly is what will produce. Both lanes are retained, because several
`install-topology-known-red.tsv` rows are explicitly environment-dependent and the bash-3.2 lane
carries signal ubuntu does not.

`INSTALL_TOPOLOGY_TIMEOUT` (default 1200s) is the per-suite bound. Its job is to turn a hang into
one named timeout line instead of a CI job that dies at its own timeout with no attributable
cause — this guard runs a second copy of every shipped suite, frequently while the outer sweep is
running the first, so contention is structural here rather than incidental.

The default was 600s and was raised on evidence: under a stress-inclusive outer sweep at `-P 4`,
`statectl-selftest.sh` inside the guard exceeded 600s and was reported as a timeout, reding a tree
that had nothing wrong with it. A later stress-inclusive sweep of the same tree did **not** cross
it — which is the point, not a contradiction. **A bound that ambient machine load can cross
intermittently is not a hang detector, it is a flaky test**: every crossing has to be re-litigated
by hand, and it is unattributable by construction, which is precisely the cost the named-timeout
line was supposed to remove. The rule that sets it is unchanged (≈2x the worst contended run
observed); only the observation moved, from 244s to ≥600s, because under the stress-inclusive form
the contending load is the whole sweep rather than one second copy.

**A consumer's configured lane runs in a scrubbed child env.** `verifyctl.sh` and
`preflight.sh` both spawn a `commands.<host>` command (`lint`/`typecheck`/`test`/`format`/
`lanes`/`extraLanes`) as a `bash -c` child of the pipeline session. When this repo dogfoods
itself, that child IS second-shift tooling — the configured `test` command is the selftest
sweep — so it must not see the caller's own `SECOND_SHIFT_CONFIG` / `STATECTL_STATE_DIR` /
etc.: an ambient value silently re-roots or re-states the child, producing spurious failures
unrelated to the code under review (#34's ~20 of them). Both files carry the scrub
independently — one `SEAM_SCRUB` denylist, `env -u`'d at every child-invocation site — because
they reach that lane shape via two different code paths (verifyctl's Stage-6 run vs
preflight's one-pass doctor sweep), kept honest by a `scripts/lockstep-manifest.tsv`
`subset-of` row rather than a shared import (neither is importable by the other). This is a
different concern from the eight `unset SECOND_SHIFT_CONFIG …` lines already present at the
top of several *direct-invocation* selftests (`statectl-selftest.sh`, `preflight-selftest.sh`,
etc.): those defend against a seam var poisoning the selftest's OWN process when the operator
sweep or CI's `find *-selftest.sh` glob runs it directly — a path the configured-lane scrub
above never touches — so both defenses stay, in depth, rather than either replacing the other.

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

The mechanics live in `workflows/runtime-shim-lib.mjs` — import them. Two suites consume it:
`runtime-shim-selftest.mjs` for per-workflow dispatch-ladder cases, and `e2e-workflow-leg.mjs`
for the E2E replay's stage-4/5/8 legs.

Notes from building it:

- Model the runtime faithfully. A schema-free dispatch resolves to **text** the workflow parses
  itself; a schema-carrying dispatch resolves to an already-validated **object**. Getting this
  backwards makes cases fail for the wrong reason.
- The meta-strip is a balanced-brace scan, not a parser. That is safe only because
  `design-sync-selftest.mjs` Case I lints every workflow for meta-literal purity — and "every"
  is a **list** of workflow directories. One directory is in it today (`skills/run/workflows/`);
  `skills/build-lean/workflows/` was removed with the lane's in-build reviewer rather than left
  empty, because an empty directory contributes no meta files and would make the case read
  broader than it is. Adding a directory means adding it to Case I's list **and** to
  `tools/check-bounded-exploration.sh`, which is anchored the same way — a workflow outside
  the list is unlinted, which makes the meta-strip unsound for exactly the files it is used
  on. Neither edit can be silently skipped: both sites discover every `workflows/` directory
  under `skills/` and fail on one that is missing from the list.
- `workflow` is **last** in the parameter list, and adding a global must stay an append —
  inserting one shifts every existing positional call site, and cases then fail for reasons that
  look like production bugs. `plan-review.mjs` and `mutation-gate.mjs` need it for their nested
  dispatches; a workflow that never calls it is driven by omitting the argument.
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

**Survivors are data, not a red build.** Only a survivor absent from `tools/mutation-baseline.tsv`,
or a named infra failure (`baseline-missing`, `baseline-environment-mismatch`, an unrunnable pair,
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

Three tracked guards carry that idiom, and the `k` budget — not any property of the guards — is
what decided which were armed: `gen-statectl-validators.sh` and `predecessor-gate.sh` hold it at
`cmp-z` ordinal 1 and killed their shards, while `scaffold-review-context.sh` holds it at ordinal 5
and was never mutated at `k=2`. Budget is not safety. That fourth site is now armed by the
`scaffold-spin-at-eof` **catalog** row rather than by raising `MUTATION_SWEEP_K`, which would have
armed every other guard's ordinals 3–5 for the sake of one named site; `k` is unchanged, so no
baseline re-seed and no cache-key change follow. Its expected verdict is a kill by timeout, a class
the catalog's header block now documents explicitly — such a row's value is the arming plus
anchor-drift loudness, not a survivor prediction.

What kept that site invisible for two nightlies was the report, not the budget: a guard with no
applicable site and a guard whose sites all sit past `k` produced the same silence. The report TSV's
last column, **`sites_beyond_budget`**, ends that. It carries per-operator detail in the
plus-joined `paired_selftest` style (`cmp-z:3`), counts only sites the enumerator declined for
budget — an unparseable or no-op flip is a harness artifact, not darkness — and is **report-only,
never red**, the posture `tools/mutation-operators.tsv` already states for non-application. It is
appended last because `report_row()` in the companion selftest reads `$5/$6/$7` positionally and
`--mode merge` compares shard headers byte-wise. The wider question it now supplies evidence for —
whether `k=2` is the right budget at all, given that every site past ordinal 2 is dark sweep-wide —
stays open.

**Two obligations land on ordinary PRs.** Editing a guard re-keys its generic survivor ordinals,
so that PR re-baselines those rows in its own diff; and it re-anchors any catalog row addressing
it. Catalog rows are pattern-addressed for exactly that reason — a bare line address is rejected,
because during this harness's own intake the `check-emit-deadline` site moved by 68 lines between
two runs a day apart, and only the expression-addressed entry survived.

**Where it runs.** Diff-scoped on every PR — guards whose kill set is not a single fast suite defer
to nightly rather than being graded against a weaker criterion than the one that produced the
baseline — and wholesale in the nightly `mutation-sweep.yml`. Kill verdicts are only comparable
inside the canonical environment (ubuntu-latest, `SKIP_STRESS=1`), so local runs are advisory and
say so.


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
`statectl-selftest.sh` sources `scenario-lib.sh`. A whole-tree key would be sound — and would also
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
`tools/mutation-slow-suites.tsv`, so taking them under the pool's own contention would measure the
pool rather than the suite.

**2. Mutants run in a pool.** One sandbox per worker, created lazily and restored between items — so
no two concurrently-running mutants share a tree, and disk stays at `pool × ~7MB` rather than growing
with the mutant count. Size defaults to `min(cores-2, 8)` and is set by `MUTATION_SWEEP_JOBS`;
`MUTATION_SWEEP_JOBS=1` is the serial harness exactly.

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

**`baseline-absent survivor: <guard>::<operator>::<ordinal>`** — the usual one, and usually your
own doing: you edited a guard, which re-keyed its ordinals. The red line *is* the answer. Copy each
named id into `tools/mutation-baseline.tsv` as `<survivor_id><TAB><note>` and commit it **in the PR
that moved the guard**. No dispatch needed — the failing log already names every id. Before pasting,
read the mutant: an ordinal that shifted is bookkeeping, but a *new* survivor at a site you just
wrote is the harness telling you the test you added does not test anything.

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
single fast suite; everything paired to a slow or multi-suite killer (`statectl-selftest`,
`scenario-liveness-selftest`, `scenario-lib.sh`'s three killers, anything in
`tools/mutation-slow-suites.tsv`) reports `deferred-to-nightly` and is **not graded on your PR**.
Edit one of those and the ordinal re-key surfaces at 03:17 UTC, on someone else's morning. If your
diff touches a deferred guard, expect to re-baseline from the nightly rather than from your PR.

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

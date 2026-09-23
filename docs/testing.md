# Testing

How this repo tests itself, what tier a new test belongs to, and the one tier that
deliberately does not run in CI.

The short version lives in [`CLAUDE.md`](../CLAUDE.md) under **Verification**; this file
carries the reasoning and the operator-run adversarial recipe.

## What survives as a register

[`docs/pipeline-manifesto.md`](pipeline-manifesto.md)'s P4/P5 posture names the register rule;
this section is its consequence, not a second copy of it. A number a command could produce in one
call is not committed as a table — it is re-derived when it is needed.

What is committed is what a human, not a command, decided:
`scripts/fail-open-sites.tsv`,
`plugins/dev-pipeline/tools/review-harness-fixtures/review-harness-manifest.tsv`,
`tools/selftest-cache-inputs.tsv` — each row states something no `find`/`wc`/`git ls-tree` could
re-derive: an adjudicated disposition, a reasoned exclusion, a declared input set. The one cost
record, [`tools/selftest-suite-timings.tsv`](#the-slow-suite-table), is committed because the
runner reads it.

`scripts/fail-open-sites.tsv` is the disposition of every site the `pipeline` leg of
`scripts/check-fail-open-shapes.sh` enumerates (a `| grep -q` whose producer can die and read as
"no match"). The guard's `--list` output is the denominator and the table must cover it exactly:
an unclassified site reds, and so does a row whose anchor no longer resolves or no longer covers a
live site.

## How the sweep runs

One script owns it, locally and in CI:

```bash
SKIP_STRESS=1 bash tools/run-selftests.sh --full
```

**`--full` is what makes that a full sweep.** The bare invocation is the *bounded quick check*: it
applies `tools/selftest-suite-timings.tsv` as exclusions by default. Every caller that wants the
whole set — both CI selftest jobs, the nightly wholesale lane, and the local recipe in
[`CLAUDE.md`](../CLAUDE.md) — passes `--full`. See [the slow-suite table](#the-slow-suite-table)
below.

`tools/run-selftests.sh --full` discovers every `*-selftest.sh` under the repo, runs `SELFTEST_JOBS`
(default 4) at a time, and replays each suite's captured output inside `::group::`/`::endgroup::`
framing, in worklist order. Ordering by worklist rather than by completion is what makes the log
identical at `SELFTEST_JOBS=1` and `SELFTEST_JOBS=4` — a diff of the two runs' group headers is a
real assertion, and `tools/run-selftests-selftest.sh` makes it.

**Why a script and not a `-P` flag.** Bolting `-P 4` onto a `find … | xargs` loop fixes the clock
and destroys the log: at four concurrent suites the raw streams braid, and a FAIL line no longer
belongs to any identifiable suite. Per-suite capture and ordered replay is the whole reason this is
a file — and being a checked-in script it then owes a selftest under the repo's coverage rule,
which is where the guarantees below are asserted rather than merely described.

**What it refuses to call green.** Each is a rejection the runner makes, not a convention it
follows:

| Condition | Verdict |
| --- | --- |
| any suite exits non-zero | exit 1, every failing suite named with its code |
| a worker dies without writing a verdict | that suite scores `rc=125`, named as infra — never as a pass |
| **every** failing suite is that infra class | exit **3**, the reserved code — the workers died, so the sweep learned nothing about the tree. Mixed infra-and-real stays exit 1, because a red branch is still a red branch |
| discovered-minus-excluded ≠ suites actually run | exit 2, `silent truncation` — a faster sweep that ran fewer suites is the failure mode this design is most exposed to |
| `--exclude` matches no discovered suite | exit 2, `stale exclusion` — the same stale-row posture the slow-suite table applies to its own rows |
| no suites discovered, or every suite excluded | exit 2 — a sweep that runs nothing is never green |

`--exclude` has three in-repo callers, all passing `--full --exclude
tools/install-topology-selftest.sh`: both CI selftest jobs (`lint-and-selftests`,
`selftests-bash32` in `ci.yml`) and the nightly wholesale lane (`wholesale-selftests` in
`nightly-guards.yml`). Inside the sweep the install-topology guard would contend with the very
suites it re-runs from the install cache, which is what the install-topology section below
measures. `install-topology-selftest.sh` itself runs in its own event-triggered jobs
(`install-topology`, `install-topology-bash32` in `install-topology.yml`), never alongside a sweep.
The suite stays *discovered*: the exclusion names a path that must keep existing, so renaming the
suite reds CI instead of silently double-running it.

### When a run is killed mid-sweep

A sweep that dies part-way — a foreground agent call hitting the harness's 2-minute cap, a
Ctrl-C, a `timeout` — skips every suite's `trap … EXIT`, and whatever that suite had under
`mktemp` stays on disk with nothing to remove it.

Some shell files use the explicit-template form, `mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX"` — the
shell expands the path before `mktemp` ever runs, so it is honored unconditionally, unlike
`mktemp -d -t <name>` (which on macOS resolves against `_CS_DARWIN_USER_TEMP_DIR` and ignores
`TMPDIR` outright) or a bare `mktemp -d` (which *is* `-t tmp` — same resolution, no third form to
fall back on). The sweep runner's own state dir — its worklist and cache bookkeeping plus each
suite's captured `log`/`rc`/`secs` — is one of them, and so is `run-selftest.sh`:

```sh
BASE="$(mktemp -d "${TMPDIR:-/tmp}/run-selftests.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$BASE"' EXIT
```

Exporting a private `TMPDIR` before a run isolates *these* from every other worktree and
concurrent lane on the machine. **It does not isolate the rest of the tree.** Count the call sites
rather than the mentions, excluding comment lines — a naive `grep -l` catches both:

```sh
git grep -nE 'mktemp[[:space:]]+(-d[[:space:]]+)?-t' -- '*.sh' \
  | grep -vE ':[0-9]+:[[:space:]]*#' | cut -d: -f1 | sort -u      # mktemp -d -t / mktemp -t
git grep -nE 'mktemp[[:space:]]+-d' -- '*.sh' \
  | grep -vE ':[0-9]+:[[:space:]]*#' \
  | grep -vE 'mktemp[[:space:]]+-d[[:space:]]+("|-t)' \
  | cut -d: -f1 | sort -u                                          # bare mktemp -d
```

Those two lists are the shell files a private `TMPDIR` does not isolate, including the largest
scratch tree in the repo, `tools/install-topology-selftest.sh` (`install-topology.XXXXXX`,
`mktemp -d -t`). Re-run them rather than trust a count written down anywhere — they move every
time a suite's scratch allocation changes. [`CLAUDE.md`](../CLAUDE.md)'s verification recipe is the
caller most exposed to this, which is why it routes here.

**Nothing reaps a killed run's leftovers for you.** Scrub by hand:

```sh
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'run-selftest*' -mmin +60 -print
```

That names the runner's and the scheduler suite's families, not every scratch dir under the
default `TMPDIR` — the `mktemp -d -t` / `mktemp -t` callers above (`install-topology.*` and the
rest of that set) accumulate there too and are outside this glob. The bare-`mktemp -d` callers are
a second, disjoint gap: they land under the same `_CS_DARWIN_USER_TEMP_DIR` root but named
`tmp.XXXXXXXX` — no name-based glob can reach them. Widen the glob for the first group; for the
second, either re-run the bare-form command above and scrub each named directory, or scrub the
whole `_CS_DARWIN_USER_TEMP_DIR` root when nothing else is running there.

`-mmin +60` is a floor, not a proof — a directory that old is unlikely to belong to a run still in
flight, but it is not a live-pid check. Before removing anything a listed path names, `stat` its
mtime against your own kill and confirm no other worktree on the machine has a run in flight: a
blind `rm -rf` over that glob can delete another run's live state.

What residue still costs is diagnosis time. **The tell is a red in a suite the diff cannot
reach.** Re-run that suite alone in an untouched checkout first: red there too means it is
environmental, and the enumeration is read-only:

```sh
ls -d "$(env -u TMPDIR mktemp -u -d | xargs dirname)"/*/*/agents
```

A match with a `.claude-plugin/plugin.json` beside it is a plugin-shaped leftover; one without is
some vendor's directory and is none of your business. On a `/var/folders/…` path the removal can
be permission-denied outright, in which case hand the operator one exact command rather than
routing around it.

### The slow-suite table

`tools/selftest-suite-timings.tsv` is a committed cost record — `suite<TAB>seconds<TAB>measured_at`
— and `run-selftests.sh` applies rows at or above its own `# threshold-seconds` directive as
exclusions **by default**. It exists so a caller that must finish inside a bounded call — a
session's foreground `Bash` call, or a lane `test` command configured without `--full` — can run
the fast set and stay inside the bound.

**One table, one consumer.** `run-selftests.sh` is the only reader, and the threshold is a
`# threshold-seconds` comment directive in the same file; a row below it is ignored at read time.
A row naming no discovered suite is a hard error; a suite absent from the file is treated as fast.

| Caller | Passes | Runs |
| --- | --- | --- |
| a bare invocation | nothing | the table is applied — the bounded quick check |
| both CI selftest jobs | `--full` | everything |
| the nightly wholesale lane | `--full` | everything |
| CLAUDE.md's contributor recipe | `--full` | everything |

**Default-on, with an explicit opt-out, and the direction is load-bearing.** Every sweep of record
carries `--full` in a **committed** file, where a missing opt-out shows up in the diff. A bounded
caller whose command lives in a consumer's *gitignored* config needs no flag an untracked file
would have to carry.

**A row costs signal latency, never soundness.** Everything deferred still runs in CI, and the
merge boundary still blocks on CI, so the worst case for a deferred suite is that its regression is
caught at PR time instead of before the push. It is not a license to defer a suite because it is
inconvenient.

**Same stale-row posture as `--exclude`.** A row naming no discovered suite is a hard error, so a
renamed suite cannot silently start running twice. The message names the table rather than
`--exclude`, because the two have different remedies. Rows and explicit `--exclude` flags are
**deduped**: `EXCLUDED` feeds `EXPECTED = DISCOVERED - EXCLUDED`, so double-counting one suite
would under-state `EXPECTED` and red an honest sweep — and it is the normal case for a bare
invocation that also passes `--exclude tools/install-topology-selftest.sh`, since the table lists
that suite too.

`--full` does not read the table at all, so a stale or malformed row cannot red the sweep of
record. Cases: `run-selftests-selftest.sh`'s `slow-table:` block.

`SKIP_STRESS` is never set by the runner. The ubuntu lane omits it and the macos lane sets it.

Discovery is `*-selftest.sh` only. The `*-selftest.mjs` files are executed by
`plugins/dev-pipeline/workflows/workflows-mjs-selftest.sh`, which is itself in the glob; widening
discovery would run them twice.

**Worker mode is keyed on an argv sentinel (`--run-one`), never on an environment variable**, and
that is a correctness property rather than a style choice. An env flag is inherited by everything
the dispatch spawns, *including the suites* — so a suite that itself invokes the runner takes the
worker branch and collapses. `run-selftests-selftest.sh` nests a runner inside a suite; an env-keyed
worker passed it standalone and failed the instant the repo sweep ran it, which is exactly how a
leak of this shape reads if you only ever run one suite at a time. The same reasoning is why the
parent's truncation seam is stripped before a suite is executed.

### The pass cache

CI additionally passes `--cache-dir`, and with it a suite that has a row in
`tools/selftest-cache-inputs.tsv` is **not re-run when the content of every declared input is
unchanged**. The key is `sha256` over an epoch constant, `RUNNER_OS`, the bash major version,
`SKIP_STRESS`, the runner's own blob id, the suite's path, and the `git hash-object` blob id of each
declared input — so the two CI lanes accumulate independent marker sets and never serve each other
an answer to a different question.

It exists because the sweep re-derives the same verdict on every push, and a slow suite whose
inputs a PR does not touch is the cost it removes.

**The risk is a silently skipped gate**, which is this repo's cardinal failure mode, so the
containment is the load-bearing part and the hashing is not. Four properties, all asserted in
`tools/run-selftests-selftest.sh` against fixture trees:

1. **Fail-closed by default, twice.** A suite with no row is always run, and the cache as a whole
   is off unless a store is named — `--cache-dir` on argv, or `$LANE_SELFTEST_CACHE_DIR` (below).
   The mandated local recipe in `CLAUDE.md` names neither, so a bare local sweep is still cold —
   and so is the nightly leg.
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
   `--cache-dir`, asking the PR lane's exact question. An under-declaration surfaces within a day,
   against a tree nobody is waiting on.

**`LANE_SELFTEST_CACHE_DIR` is the flagless form**, for a caller that cannot add a flag to a
command it does not own. `run-selftests.sh` reads it only when argv named no store; argv wins, and
unset is a no-op. It differs from `--cache-dir` twice: it records without `--cache-write` (the
store is machine-local and records the operator's own tree — property 3 guards a store other runs
read), and a store that cannot be created prints a named notice and runs cold instead of exiting 2
(an injected store is not the tree's fault). The `--run-one` worker scrubs the variable, so a
suite never inherits it — the cache is decided once, in the parent, and a suite that nests its own
runner keeps meaning what it means standalone.

Only PASS is ever recorded, and only by the parent process after the replay has scored the run — a
red suite, and a suite whose worker died without a verdict, write nothing. A marker that is not
exactly the one well-formed record line is read as a **miss**, never as a pass.

Every skip prints the suite, the key, and every input blob id behind that key, so a log reader can
tell a skip from a suite that quietly stopped being discovered. The summary line reads
`N scored, M run, K served from cache` for the same reason: reporting the larger number as work
performed is the faster-green misreading the rest of this section is about.

**Adding a row is the risky edit in that file, not the cheap one.** Derive the input set from the
suite, never from a ticket: a suite typically reads more files than an eyeball lists. Where a
suite's composed set is really its transitive closure over the tree, drop the row. A dropped row
costs seconds; an under-declared one costs a gate.

**Derive the closure, not the file list.** Neither mechanized rule reaches depth 2: a row set can
name the suite and its subject and still under-declare, because that subject resolves a third file
at run time. `run.sh` resolves `claim-issue.sh`, which resolves its sibling `gh-bot.sh` — so a row
for `run-selftest.sh` would have to declare a file two removes from anything the suite names.
Follow every variable-rooted resolution out of every declared script until it terminates, and say
in the row comment where it terminated. Over-declaring costs one spurious miss; dropping a needed
row is the direction that costs a gate.

**Derive that mechanically, over paths rather than over scripts.** Grep the subject for the paths
it builds from a variable, and match every one against the rows. Three things a prose reading
misses:

1. A resolution may target a `.md` or a `.tsv` as readily as a `.sh`, so a sweep scoped to `*.sh`
   mentions can be accurate and still incomplete.
2. A target the subject only tests for EXISTENCE is an input like any other. Its absence flips the
   suite's verdict, while the key — content-addressed over the declared rows alone — does not move.
3. **The root decides the answer, and there are two.** A `${BASH_SOURCE[0]}`- or `$0`-rooted path
   names a file shipped beside the subject and is an input whenever the subject reaches it. A path
   rooted at the *graded tree* (`$REPO_ROOT`, from `git rev-parse --show-toplevel`) is an input
   only if the suite runs the subject against a tree that has the file — under a `mktemp` fixture
   it usually does not, and the case is asserting the absent branch. Classify each; do not assume.

`CACHE_EPOCH` is a constant in the runner rather than a knob. The key covers repo content —
including `run-selftests.sh`'s own bytes, which is property 2 applied to the harness that produces
every recorded verdict — but not the runner image, so an image bump could in principle move a
verdict with every declared input byte-identical; bumping the epoch invalidates every marker on
every lane in one character, and the next run is a full cold sweep. `SELFTEST_CACHE_MAX` (default
5000) clears the store when it overflows, with the same fail-closed consequence.

CI is the thing being sped up, and the authority is the nightly wholesale leg, which runs cold.

### Citing a CI run instead of re-running it (review side)

A review session often needs the answer "is the mandated recipe green at this head", and the
answer is already sitting in the PR's checks: an `AC-n` proved by "run the mandated recipe and it
is green" does not need a *third* execution once `lint-and-selftests` (ubuntu) and
`selftests-bash32` — display name `selftests (macos, bash 3.2)`, the string `gh pr checks`/`gh run
view` actually print — have both run the recipe's suite set at the commit under review. Both cover
ground the reviewer's own checkout (bash 5.x + BSD) does not: ubuntu is bash 5.x + GNU, macos is
bash 3.2 + BSD. `gh pr checks <pr>` names the job and conclusion for the PR's current head — its
own `--json` has no head SHA field, so pair it with `git rev-parse HEAD`; `gh run view <run-id>
--json headSha,conclusion,jobs` supplies all three itself. Citing those three IS the verification.

CI's own invocation is not byte-identical to the recipe — it adds `--cache-dir
"$RUNNER_TEMP/selftest-cache"`, and the ubuntu lane sets no `SKIP_STRESS` where the recipe sets
`SKIP_STRESS=1` — and neither delta counts as "command differs" below. `--cache-dir` is read-only
on a PR (`--cache-write` is push-only) and skips a suite only when every input
`tools/selftest-cache-inputs.tsv` declares for it is byte-unchanged from an already-passed run — a
correctly-declared row skips no gap the recipe would have caught differently. An *under-declared*
row is exactly that gap — but whether the PR lane itself catches it depends on what else the PR
touches: moving only the under-declared input leaves the cache key unchanged, the suite is
skipped, and it is the nightly's cold sweep that catches it; moving a *declared* input in the same
PR moves the key too, and the PR lane forces the suite to run. The missing `SKIP_STRESS` runs
strictly *more* than the recipe, never less. Both classify as same command.

**The discriminator is both conditions, not one: same command AND same head.**

- **Command differs** — the AC's recipe carries a flag or exclusion CI's invocation does not (e.g.
  an AC asserting `tools/install-topology-selftest.sh` is green: both CI selftest jobs run
  `--exclude tools/install-topology-selftest.sh`, so their green never covered that suite). CI's
  green proves a different claim than the AC makes. Execute.
- **Head differs** — a fix round landed after the run being cited. CI's green is about a tree that
  no longer exists. Execute.
- **Neither differs** — cite the run and stop. A local rerun is not stronger evidence: CI's two
  lanes already cover two environments the local checkout does not, and the retry answers a
  question the branch's own checks already answered.

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
| Contract | `check-lockstep-pairs.sh` — `LOCKSTEP` marker groups discovered from the tree and compared; + registry and schema lints (config-lint ↔ schema, model tiers, text-contract carriers) | Established |
| Integration | `plugins/dev-pipeline/skills/run/run-selftest.sh` — the scheduler driven end to end against a fake `claude` and a fake `gh`, one case per contract row | Established |
| Runtime | `workflows/runtime-shim-selftest.mjs` — executes real Workflow `.mjs` bodies with injected fakes | Established |
| Install topology | `tools/install-topology-selftest.sh` — every shipped suite re-run from a version-keyed install cache | Established |
| Adversarial | Model-tier audit workflows — **operator-run, never CI** | This document |

### The lane's scenario: `run-selftest.sh`

The lane is one script, `plugins/dev-pipeline/skills/run/run.sh`, and its test story is one suite.
`run-selftest.sh` puts a fake `claude` and a fake `gh` on the path (`RUN_CLAUDE`, `RUN_GH`), builds
a fixture per case — a bare origin, a main checkout with a config and an intake record, an empty
worktree root — and drives `run.sh` to a terminal. Each fake session plays one scripted behavior
(`build-pr`, `review-approve`, `review-wrong-sha`, `build-stubborn`, …) from a plan file, so a case
reads as the sequence of sessions it stages. Assertions land on the terminal slug, the exit code,
and what the fakes recorded: labels, the claim marker, the spawn flags, the prompts, the PR body
and its cost block.

The cases are **row-keyed**: each names the contract row it discriminates (`[F2]`, `[D4]`, …),
the same ids `run.sh`'s section headers cite, and a row whose behavior is reverted turns its case
red. The invariants the suite exists for are the three adjudication properties: the checks are run
by the scheduler from the record's first commit, the build's work is collected on exactly one open
PR before any check runs, and a verdict counts only as an unedited comment naming the current head,
posted inside the review session's window.

**A change to `run.sh` lands with a row-keyed case seen failing first.** Add the case, watch it go
red against the current script, then change the script. A new terminal, refusal or outward write
that no case reaches is untested by construction — the suite is the only place the scheduler runs.

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

**Prefer one composed scenario to N component checks.** A path can die with dozens of green
selftests when every one of them checks a component against itself. If a change adds a lane
verdict path, extend `run-selftest.sh`.

**Never plant what a tool could produce.** A composed scenario can still be hollow if the values
it composes over are typed in by the harness. A planted receipt means the post → read → record
chain it stands for is never executed by anything, and planting hides its own failures: a plant
the consumer rejects, with the stderr discarded, reads green the whole time. Prefer a fake you
execute over a literal you write; where no production tool owns the call, say so at the assertion
instead of implying the literal proves something.

**Characterization is allowed; silent characterization is not.** Covering a script often means
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
`plugins/`. Suites have depended on exactly those and been green here the whole time — one
borrowed the repo's git toplevel for its fixtures, so from an install its assertions were skipped
wholesale, and another walked a fixed `../../../../<plugin>` path. So: **a fixture owns its own
repo** (`git init` inside a `mktemp -d`), and **a cross-plugin path goes through a resolution
ladder**, never a fixed hop count — `resolve_sibling_plugin_root()` in
`plugins/review-toolkit/scripts/check-model-tiers.sh` is the reference.

`tools/install-topology-selftest.sh` is the class guard, and it is the reason no new instance of
this needs its own test: it stages `plugins/` at version-keyed paths outside any git repo and
re-runs **every** shipped suite from a `git init`'d consumer cwd, under a per-suite wall-clock
bound. It reds on any staged suite that fails, full stop; there is no allowlist.

**Two limits on how far that goes.**

- *It does not run on the PR lane.* So "no new instance needs its own test" holds for
  **detecting** the class, and stops holding when you want the defect to red on the branch that
  causes it. Where a cross-plugin resolution is cheap to fabricate — a few `mkdir -p` under a
  `mktemp -d`, no plugins staged, no suites re-run — put a case in the suite that owns the code
  too. Stage the sibling at a version that is **not** the caller's, so the same-version rung
  misses and the cache-walk rung is what has to decide; same-version staging passes with that rung
  dead, and it is the rung an install uses.
- *A red must name what failed.* The `detail` string on a `RED:` line is all a reader gets — the
  captured log is deleted with `$BASE` on exit. It prefers a line whose *start* is a marker
  (`FAIL:`/`FATAL:`/`RED:`/`ERROR:`) and falls back to a loose `FAIL|error` sweep only when a
  suite died before printing one, because the loose sweep matches passing lines such as `ok: …
  failed at 24h`. That path is dead on every green run, so it is sentinel-delimited
  (`# >>> red-detail`) and exercised against fixture logs by
  `tools/install-topology-detail-selftest.sh`.

The general form: **a guard whose red cannot say what it caught is not yet a working guard**,
and a guard excluded from the PR lane is a detection tier, not a PR gate.

**A guard that reports on the environment cannot be seeded from one environment.** Its first run
scored differently on the authoring machine than in CI on the same commit, because two suites
failed for reasons the authoring machine's environment hid (one needs the `claude` CLI to be
*absent*, one needs bash older than 5.3). Read every "measured here" claim about it as "measured on
one machine" until a different one agrees.

**You can be the second environment without waiting for CI, and you should.** The gap is a small
number of ambient dependencies, and removing them is a better experiment than re-running, which
proves nothing about an environment-dependent red. Rebuild `PATH` symlink-for-symlink with the
leaking entries left out, then run the guard under it:

```bash
# `bash` resolves to 3.2 (what the macOS lane runs), `claude` absent (what CI has)
ln -sf /bin/bash "$SHADOW/bash"        # …after linking everything else on PATH except these two
PATH="$SHADOW" bash tools/install-topology-selftest.sh
```

That reproduces CI's verdict exactly on a machine whose own PATH hides both. Read a red here the
same way: reproduce the gap first, and fix it for real — there is no exception to reach for.

Re-running the whole shipped set is the price of the class being visible at all, and it is not
small. Suites run concurrently (`INSTALL_TOPOLOGY_JOBS`, default 4 — each suite is a separate
`--run-one` invocation, which is also what gives every concurrent watchdog its own job-control
shell). **Do not plan around a single number for its wall time.** Three runs of one tree, same
command, uncontended, measured **319s, 438s and 584s** — a 1.8x spread with no code change between
them. Budget ~7 minutes and expect either end; a run at the top of that range is not a regression.

**Where it runs.** `.github/workflows/install-topology.yml`, on three triggers: a push to `main`
that touches a plugin manifest (`plugins/*/.claude-plugin/plugin.json`, whose `version` is the key
the guard stages under) or the guard script itself; the release PR (head `release/next`, from this
repo); and `workflow_dispatch`. The workflow file states why each path is in scope and why
`.claude-plugin/marketplace.json` and a shipped suite's own content are not. A red run files a
deduplicated GitHub issue (`file-issue-on-red`), so the failure has somewhere to be read. Both CI
selftest jobs exclude it by path, the documented local recipe excludes it too, and it carries a
`tools/selftest-suite-timings.tsv` row, so a bare sweep defers it without the flag.

**The trade, stated plainly.** Its cost is the shipped suite set run a second time, while the class
it guards moves only when suites change or packaging changes. A manifest-version bump or a change
to the guard script is caught at the next push to `main`. A change to a *shipped suite's own
content* is not: the push filter is deliberately narrow so it does not fire once per merge, and
that class of regression is caught at the next release PR — every plugin ships at its manifest
version there, whatever paths the release PR's own commits touch — or by `workflow_dispatch`. If
your change touches a shipped suite and you want the answer before the release PR, run
`bash tools/install-topology-selftest.sh` directly, or dispatch the workflow against your branch.
Both lanes (ubuntu and macos bash 3.2) are retained, because the environment-dependent suites above
carry signal the bash-3.2 lane has and ubuntu does not.

`INSTALL_TOPOLOGY_TIMEOUT` (default 1200s) is the per-suite bound. Its job is to turn a hang into
one named timeout line instead of a CI job that dies at its own timeout with no attributable
cause. It is sized at ≈2x the worst contended run observed: **a bound that ambient machine load
can cross intermittently is not a hang detector, it is a flaky test** — every crossing has to be
re-litigated by hand, which is the cost the named-timeout line exists to remove.

**A consumer's configured check runs in a scrubbed child env.** `run.sh` runs every configured
check (`lanes`, `lint`, `typecheck`, `test`, `format`, `extraLanes`, and the record's `## Checks`)
as a `bash -c` child in the worktree, through `env -u` of every name in its `SEAM_SCRUB` denylist.
When this repo dogfoods itself, that child IS second-shift tooling — the configured `test` command
is the selftest sweep — so it must not see the scheduler's own `SECOND_SHIFT_CONFIG` /
`SECOND_SHIFT_REPO_ROOT` / etc.: an ambient value silently re-roots the child, producing spurious
failures unrelated to the code under review.

This is a different concern from the `unset SECOND_SHIFT_CONFIG …` lines at the top of several
*direct-invocation* selftests: those defend against a seam var poisoning the selftest's OWN process
when a sweep or CI's glob runs it directly — a path the check scrub never touches — so both
defenses stay, in depth.

## Lockstep blocks: discovered, never declared twice

`scripts/check-lockstep-pairs.sh` enforces contracts that exist in two or more copies by
necessity — an agent whose independence contract forbids reading pipeline docs keeps an inline
copy of a rule; Workflow scripts each declare the same schema because the runtime gives them
no import; a template file ships a near-twin of this repo's own workflow. Prose at those sites says
"keep verbatim", and without this guard nothing checks it. It is the replacement for the
prose-presence class: byte-parity beats token presence.

**The markers are the whole declaration.** The checker walks the tree, groups every
`LOCKSTEP-BEGIN <anchor>` site by its anchor, and compares all members of the group. There is no
manifest: a manifest declares every pair a second time and becomes the file every concurrent PR
conflicts on.

**A group of size 1 is a failure.** That is the property a central register could not have. It
catches a marker whose counterpart never existed or was deleted — a block that reads as held to a
copy and is not.

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
disagree fails; so does an unrecognized token, rather than degrading to the default.

Rationale for a coupling lives at its anchor site. Because `verbatim` compares the whole block,
that prose goes immediately ABOVE the BEGIN marker, never between the markers.

### Two things to know before you edit

- **Deleting BOTH markers of a live pair silently drops it.** Discovery has nothing left to notice.
  It is a visible diff, and the blocks stay covered by their own behavioral suites, but the loss is
  real — the price of having no manifest.
- **A whole-line marker inside a selftest heredoc is a real site.** Fixture trees under `mktemp`
  are outside the walk, but the selftest's own source is not. Build such a line at runtime from a
  variable — `check-lockstep-pairs-selftest.sh` does, and carries a live-corpus case that would
  catch a future paste.

`docs/plans/**` is excluded from the walk, stated as data in the script with its reason: plan
documents quote locksteped blocks verbatim as evidence for a decision, are never edited afterwards,
and are SUPPOSED to drift from the block they quote.

### When the second copy is not prose: derive it

A `LOCKSTEP` group holds two copies of one contract identical. It has nothing to say when the two
sides are not both prose — when a document states a fact **about the code**, and the code is the
only place that fact is true. No marker can catch that sentence going stale: there is no second
copy to compare against.

The shape that fits is a script that **derives** the set from the code — walks the call sites —
and requires the doc's marker-delimited rows to name exactly that set, in both directions. It is
not a prose-presence guard: it fails for a fact that lives in another file. Two properties make
it safe:

- **The doc's rows ARE the claim, not a restatement beside it.** The surrounding prose stops
  enumerating entirely. A machine-readable line that merely accompanies a prose list gives you two
  declarations to keep in sync and guards only one of them.
- **It fails closed on a shape it cannot model.** A derivation that silently returns a smaller set
  when it meets an unfamiliar dispatch reads as agreement. So a call site it cannot place reds
  naming the line — "teach this script the new shape", not "the doc is wrong".

Reach for this when a document asserts something enumerable about shipped code. Reach for a
`LOCKSTEP` marker when the two sides are copies of each other. When neither fits, the coupling is
unanchorable: leave it unmechanized rather than build a guard that cannot fail.

### Couplings considered and declined

Each is a real duplication someone reasoned about and chose not to mechanize, with the reason and
— in most cases — the behavioral guard that carries it instead. A coupling recorded as declined is
a decision that stays visible; one merely omitted is a decision that gets re-litigated. A change
does not owe this list a new entry.

- **`args.config` subset** — the Workflow dispatch sites' `config:` args and their explaining
  comments ↔ the `config.` reads inside the dispatched `.mjs`. It has failed in both directions:
  passing the whole parsed config killed a dispatch outright, and a `{ reviewers: {} }` recovery
  serialized cleanly while silently disabling every model override. The caller side is
  differently-worded prose inside differently-shaped args objects; the callee side is an
  expression whose shape varies per key. Forcing a shared literal would mean writing dispatch
  prose to satisfy a grep. **Behaviorally guarded**: `runtime-shim-selftest.mjs` Case H executes
  the real `code-review.mjs` body under the documented subset alone — that a `modelOverrides`
  value reaches the dispatched model, and that `tracker.type` still branches the
  scope-completeness fetch. The tier ALPHABET is a different coupling and IS anchorable — that one
  is a live `tier-alphabet-parse` group.
- **The dark-reviewer re-dispatch mandate, across three prose sites.** `review-lead` Step 4b
  mandates one in-session re-dispatch before a `[Coverage gap]` may be recorded; Step 4b-void
  case 2 reads "still dark after that re-dispatch" as its post-dispatch trigger on an armed spec;
  and `/dev-pipeline:review` step 5c hands such a round back. Loosen the mandate and 5c's trigger
  stops matching what `review-lead` can produce. **Declined, with no guard added.** The only
  mechanization available is a grep for prose that must be present, which the `writing-tests`
  skill forbids; a `LOCKSTEP` anchor needs byte-identical blocks, and these three deliberately
  are not — a mandate, a void trigger, a hand-back rule, each in its own file's voice.
  **Reviewer-guarded**: the sites are short, two sit in the same section of one file, and the
  behavior is a session's judgment no selftest executes. The mechanized half —
  the turn-numbered deadline the re-dispatch prompt cites — is held by `check-emit-deadline.sh`,
  where the number actually lives.
- **Test-tier map** (the `writing-tests` skill's "Where a new test goes" ↔ this document's "Why a
  tier map at all"). Two representations of one routing contract, deliberately NOT parallel: one
  is a router keyed by what you are guarding, the other a status table keyed by the classic
  pyramid tier. Forcing a shared literal would collapse a router and a status board into one table
  serving neither reader. Reviewer-guarded: both are short, and a new tier lands with its own
  suite in the same PR.
- **The claimed label's release rationale** — why the label is released by a workflow on close
  rather than by a session — stated in `.github/workflows/unclaim-on-close.yml`, both shipped
  `templates/consumer/second-shift-unclaim.{sh,yml}` headers, `onboard/SKILL.md`,
  `schema/second-shift.config.schema.json`'s `claimed` description and `docs/onboarding.md`.
  These are arguments addressed to different readers — a maintainer's workflow rationale,
  consumer-shipped script headers, a line spoken during onboarding, a schema description surfacing
  in editor tooling — and one shared sentence would flatten prose that is deliberately distinct.
  Nor is it the derive-it shape: what the sites state is a design rationale, not a set the code
  enumerates. The workflow blocks that must not drift between host and template ARE locksteped
  (`unclaim-workflow-*`); the prose is reviewer-guarded.
- **`config-grill.sh`'s restated RUNTIME-resolved defaults** ↔ the readers that resolve them.
  Quoting the SCHEMA default would be a lie the consumer cannot act on: nothing injects schema
  defaults into a config, so the value in force is the reader's fallback. A literal restated at
  several scattered sites cannot be expressed as one canonical against the rest, and they sit
  inside prose sentences and a jq expression where no marker block fits. Guarded by
  `config-grill-selftest.sh`, which asserts each default fires a zero-match finding on a fixture
  tree containing no matching path, so the literal is exercised rather than merely present.
  Revisit if the fallbacks are hoisted into one shared resolver.
- **intake-receipt vocabulary** (Kind enum, open-region and surface disposition enums, the explicit
  empty forms). `interviewing-baseline/SKILL.md` states it in prose and tables; `ledger-lint.sh`
  holds the machine copy. A Kind value added to the doc and not the lint is a value the lint
  rejects with a message naming the enum the author just read. The doc side is a markdown table of
  prose descriptions, not a quoted literal. Guarded by `ledger-lint-selftest.sh`. **The SKILL layer
  is a caller class of its own:** `intake-orchestrator/SKILL.md` prescribes the receipt shape and
  then runs `ledger-lint.sh --receipt` on it, and `intake-interviewer/SKILL.md` prescribes the same
  shape. Neither is an automated caller, so no CI lane reds when the lint tightens past what they
  describe — the lint simply becomes unpassable at agent runtime, where nobody is watching. A
  change that adds or tightens a mandated section MUST move both, and the check is empirical:
  build a receipt verbatim to the prose and lint it.
- **`onboard/SKILL.md`'s benefit clauses** ↔ the docs that own the worked examples. Real — a
  capability whose behavior changes leaves a clause promising something the tool no longer does,
  and onboard is precisely where a human decides on that promise. No literal on either side: the
  clause is a summary IN a sentence, the authority a multi-paragraph worked example. What holds it
  instead: the clause is a POINTER plus one sentence, deliberately short enough that the
  authoritative text stays in exactly one place.
- **The dup-scan exit taxonomy beyond rc 2.** `dup-scan.sh`'s 0 / 10 / 2 contract is restated in
  four SKILL blocks — intake-orchestrator twice, intake-interviewer, plan-interview. The rc-2 arm is
  a live `dup-scan-rc2` group; the rest is declined, because each block states the obligation in the
  vocabulary of its own exit (what "hard-stop" means differs per caller), so a `verbatim` block
  would force four passages into one wording they do not share. `dup-scan-selftest.sh` pins each
  arm's rc AND the message it names, so a taxonomy change reds there before any SKILL copy can be
  silently wrong.
- **The audit ledger's THIRD copy** — the hook's jq object literal in `audit-tool-calls.sh`, beside
  the live `audit-row-fields` group. A jq construction expression and a prose field list share no
  anchorable bytes. Not reviewer-guarded either: `audit-selftest.sh` Test 9 asserts a real emitted
  row's `keys_unsorted` equals the documented field list exactly.
- **figma node-resolution discipline** (`figma-faithful/SKILL.md` ↔ `figma-faithful-spec/SKILL.md`).
  Removed rather than guarded: figma-faithful is the canonical home and the spec skill carries the
  operative one-liner plus a by-name pointer, so there is no second copy to anchor. The deltas
  that remain are genuine divergences, and a `verbatim` relation would fail on the first
  legitimate edit to either side.
- **Cross-plugin sibling resolution.** `resolve_sibling_plugin_root` is implemented per caller,
  because the hop constants ARE the contract and legitimately differ with each caller's depth under
  its plugin root. `check-emit-deadline.sh` shares a directory with `check-model-tiers.sh` but walks
  an unbounded set of plugin names and unions both layout shapes rather than taking the first that
  hits — pinning it would mean carrying a dead copy purely to be compared. All of them run under
  `tools/install-topology-selftest.sh` from a staged cache, and `check-emit-deadline-selftest.sh`
  drives the real script from staged monorepo and cache shapes.

**What does NOT belong in a lockstep group**: a pair already mechanically enforced elsewhere —
model tiers (`check-model-tiers.sh`), the reviewer registry, the section catalog, the text-contract
carriers, config-lint ↔ schema (the `modelOverrides` tier enum is driven from both sides in
`config-lint-selftest.sh`: every schema-declared tier must be accepted, and config-lint's rejection
message must name exactly the schema's enum). Duplicate machinery is worse than none.

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

The mechanics live in `plugins/dev-pipeline/workflows/runtime-shim-lib.mjs` — import them.
`runtime-shim-selftest.mjs` consumes it for per-workflow dispatch-ladder cases.

Notes from building it:

- Model the runtime faithfully. A schema-free dispatch resolves to **text** the workflow parses
  itself; a schema-carrying dispatch resolves to an already-validated **object**. Getting this
  backwards makes cases fail for the wrong reason.
- The meta-strip is a balanced-brace scan, not a parser. That is safe only because
  `runtime-shim-selftest.mjs` Case R lints every workflow for meta-literal purity — and "every" is
  every `.mjs` in the plugin's `workflows/` directory. A workflow outside that directory is
  unlinted, which makes the meta-strip unsound for exactly the files it is used on; adding a
  second workflows directory means widening Case R first.
- `workflow` is **last** in the parameter list, and adding a global must stay an append —
  inserting one shifts every existing positional call site, and cases then fail for reasons that
  look like production bugs. No shipped workflow invokes it; the parameter mirrors the runtime's
  injection set, and a workflow that never calls it is driven by omitting the argument.
- A script that drives a workflow must `process.exit()` explicitly. The dispatch ceiling timers
  keep node's event loop alive, so merely reaching the end of the file hangs for fifteen minutes
  rather than returning.

## Opportunistic oracles: a SKIP reports nothing

A golden is a claim about *another program's* output, so it wants a case that re-derives it from
that program when it is installed. Two rules:

**Feed the oracle the oracle's input grammar, not the producer's.** If the producer's contract
omits something the oracle's grammar requires — a markdown table's delimiter row, say — handing
the oracle the producer's input makes it read something else, rewrite nothing, and compare
unformatted input against the golden: a case that cannot pass, and that passes review only because
it never runs. Convert the input first.

**Probe a skip-guarded case by supplying the resource.** A case that reports SKIP is asserting
nothing, and neither CI nor a local sweep will tell you which — a lane without the binary skips
forever. Put a real binary on `PATH` and run the suite before believing it. The same move applies
to any fixture whose guard is "when X resolves".

## Adversarial tier (operator-run, never CI)

The model tier cannot live in CI without API-billed calls. It runs on demand, by an operator, in
a session.

**When to run it:** before a release train, after a large refactor of the lane or its guards, or
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
   only the doomed check catches. This is the load-bearing step. In the first audit the skeptics
   upheld 10 prunes and **refuted 2** — and both refutations were correct, catching coverage the
   auditor had misclassified as redundant.
4. **Treat skeptic conditions as binding.** A skeptic that says "safe *only if* X is retained"
   has written a requirement, not a footnote.
5. **Land the evidence with the work.** Audit reasoning and skeptic verdicts belong in the issue
   body, so the next reader can tell a considered deletion from a careless one.

**What it is not.** Not a gate, not a CI job, not a substitute for the deterministic tiers. It is
a periodic audit whose output is *issues and prunes*, executed by the tiers above.

**Cost is real.** The first audit ran ~40 agents over ~2.6M tokens. Budget for it deliberately.

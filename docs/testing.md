# Testing

How this repo tests itself, what tier a new test belongs to, and the one tier that
deliberately does not run in CI.

The short version lives in [`CLAUDE.md`](../CLAUDE.md) under **Verification**; this file
carries the reasoning and the operator-run adversarial recipe.

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
  `skills/run-lean/workflows/` was removed with run-lean's in-build reviewer rather than left
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
an unaccounted guard, sandbox failure), reds a lane. A baselined survivor is report-only; a
baselined survivor that is now killed is a warn to shrink the baseline.

**An unrunnable pair is infra red.** Every killer must exit 0 against the unmutated sandbox before
any of its guard's mutants are scored, so a broken or environment-starved suite can never report
its guard as fully killed.

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
what decides which are armed: `gen-statectl-validators.sh` and `predecessor-gate.sh` hold it at
`cmp-z` ordinal 1 and killed their shards, while `scaffold-review-context.sh` holds it at ordinal 5
and was simply never mutated at `k=2`. Raising `MUTATION_SWEEP_K` arms it. Budget is not safety.

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

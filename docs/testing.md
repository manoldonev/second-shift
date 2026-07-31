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
`https://github.example/c/<marker>`, so the post-a-comment → read `html_url` → record-the-receipt
chain was never executed by anything. Worse, planting hides its own failures: the stage-7
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
from an author who did not notice. Examples live in `exitplan-ledger-gate-selftest.sh` `(t3h)`
and `pipeline-doctor-selftest.sh` `(d5a)`.

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
  is a **list** of workflow directories, not one. Workflow scripts live under more than one
  skill (`skills/run/workflows/` and `skills/run-lean/workflows/`), so adding a third directory
  means adding it to Case I's list: a workflow outside that list is unlinted, which makes the
  meta-strip unsound for exactly the files it is used on. `tools/check-bounded-exploration.sh`
  is anchored the same way and takes the same edit.
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

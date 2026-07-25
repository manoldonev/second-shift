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
| E2E | Null-model full-run replay | Planned |
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

**Prefer one composed scenario to N component checks.** The stacked-PR path died with 42 green
selftests because every one of them checked a component against itself. If a new gate has a
verdict path, extend `scenario-liveness-selftest.sh`.

## The runtime shim

Workflow `.mjs` scripts are not node-importable: they carry a top-level `return` and reference
runtime-injected globals. That made them look untestable, and the repo settled for token greps.

They are testable. Strip the meta block and wrap the rest:

```js
(async (agent, parallel, pipeline, args, log, phase, budget) => { …body… })
```

The top-level `return` becomes a legal return from the arrow, and every injected global arrives
as a parameter the test controls. Drive it with a behavior queue of canned agent outputs and
assert on what the workflow actually returns.

Two notes from building it:

- Model the runtime faithfully. A schema-free dispatch resolves to **text** the workflow parses
  itself; a schema-carrying dispatch resolves to an already-validated **object**. Getting this
  backwards makes cases fail for the wrong reason.
- The meta-strip is a balanced-brace scan, not a parser. That is safe only because
  `design-sync-selftest.mjs` Case I lints every workflow for meta-literal purity.

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

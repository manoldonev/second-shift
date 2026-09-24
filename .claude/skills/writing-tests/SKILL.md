---
name: writing-tests
description: Use when adding or changing a test in this repo — the tier map (where a new guard goes), the scenario-first rule, the no-prose-presence-guards and no-mirror-harnesses rules, and the mjs-seam grep exception.
---

# What to write when you add a test

**Scenario-first.** A new per-tool fixture case must name the invariant it guards and why no
case in `plugins/dev-pipeline/skills/run/run-selftest.sh` — which drives the real `run.sh` to its
terminals with a fake `claude` and `gh` — covers it. A lane once died with all 42 selftests green
because every one of them checked a component against itself.

**No prose-presence guards.** Grepping a literal out of a markdown file asserts only that prose
contains words — it cannot fail for a reason a reader of the diff would not already see. Wrap the
two copies in `LOCKSTEP-BEGIN <anchor>` markers instead — `scripts/check-lockstep-pairs.sh`
discovers them and compares the blocks, and an anchor with only ONE site fails.

**No mirror harnesses.** Never test a hand-maintained *copy* of production logic. A copy cannot
fail on a production edit, so it converges on green while the real code drifts away underneath it
— and it reads as coverage the whole time. Two `.mjs` suites did exactly this: they modelled the
pre-#169 StructuredOutput transport for months after production replaced it, and while they were
green `design-sync.mjs`'s gate path was throwing `ReferenceError` on every dispatch. The sanctioned
replacement is review-toolkit's `workflows/runtime-shim-lib.mjs`, which strips the `export const meta` block,
wraps the remainder in
`(async (agent, parallel, pipeline, args, log, phase, budget, workflow) => { … })`,
and executes the **real** production body with injected fakes. Import it — do not re-create the
wrapper; `runtime-shim-selftest.mjs` (per-workflow ladder cases) is its consumer. If you are
about to re-declare a production function inside a selftest, use the shim instead.

**The mjs-seam grep exception, narrowed.** The shim executes Workflow-runtime `.mjs` files, so the
sanction covers only what the shim cannot reach: static/textual properties of a file that is never
executed on the path under test (review-toolkit's `scripts/intake-readroot-selftest.sh`'s `intake-review.mjs` seam
pins; `null-reviewer-selftest.mjs`'s Case F token + emit-wiring counts, which guard a constant's
*wiring* rather than its behavior). Behavior belongs on the shim.

**Where a new test goes** (the tier map — full version in [`docs/testing.md`](docs/testing.md)):

| If you are guarding… | Write it as | Lives in |
| --- | --- | --- |
| one script's behavior against fixtures | a per-tool behavioral selftest | `*-selftest.sh` next to the tool |
| two copies of one contract staying identical | a `LOCKSTEP-BEGIN <anchor>` marker on **each** copy — they are discovered and grouped, never registered | the files themselves |
| a composed run reaching a terminal | a case keyed to the row it discriminates | `skills/run/run-selftest.sh` |
| a production Workflow `.mjs` dispatch ladder | a shim case | `plugins/review-toolkit/workflows/runtime-shim-selftest.mjs` |
| whether a shipped suite still passes where it is **installed** | **nothing** — the class guard already runs every shipped suite | `tools/install-topology-selftest.sh` |
| prose in a markdown file that asserts nothing checkable | **nothing** — see above | — |

Full contract: [`docs/testing.md`](docs/testing.md).

**A change to `run.sh` lands with a row-keyed case in `run-selftest.sh` seen failing first** — the
case names the row it discriminates, so reverting the behavior turns it red. A contract nothing
composes against is one the next run walks straight through.

---
name: writing-tests
description: Use when adding or changing a test in this repo — the tier map (where a new guard goes), the scenario-first rule, the no-prose-presence-guards and no-mirror-harnesses rules, the mjs-seam grep exception, and the mutation-catalog anchoring obligations.
---

# What to write when you add a test

**Scenario-first.** A new per-tool fixture case must name the invariant it guards and why no
scenario in `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` covers it. The since-retired stacked-PR path died
with all 42 selftests green because every one of them checked a component against itself.

**No prose-presence guards.** Grepping a literal out of a markdown file asserts only that prose
contains words — it cannot fail for a reason a reader of the diff would not already see. Wrap the
two copies in `LOCKSTEP-BEGIN <anchor>` markers instead — `scripts/check-lockstep-pairs.sh`
discovers them and compares the blocks, and an anchor with only ONE site fails. When a coupling
is real but not byte-anchorable, record it in [`docs/testing.md`](docs/testing.md)'s *Couplings
considered and declined* with the reasoning, so the decision is visible rather than forgotten.

**No mirror harnesses.** Never test a hand-maintained *copy* of production logic. A copy cannot
fail on a production edit, so it converges on green while the real code drifts away underneath it
— and it reads as coverage the whole time. Two `.mjs` suites did exactly this: they modelled the
pre-#169 StructuredOutput transport for months after production replaced it, and while they were
green `design-sync.mjs`'s gate path was throwing `ReferenceError` on every dispatch. The sanctioned
replacement is `workflows/runtime-shim-lib.mjs`, which strips the `export const meta` block,
wraps the remainder in
`(async (agent, parallel, pipeline, args, log, phase, budget, workflow) => { … })`,
and executes the **real** production body with injected fakes. Import it — do not re-create the
wrapper; `runtime-shim-selftest.mjs` (per-workflow ladder cases) is its consumer. If you are
about to re-declare a production function inside a selftest, use the shim instead.

**The mjs-seam grep exception, narrowed.** The shim executes Workflow-runtime `.mjs` files, so the
sanction covers only what the shim cannot reach: static/textual properties of a file that is never
executed on the path under test (`tools/intake-readroot-selftest.sh`'s `intake-review.mjs` seam
pins; `null-reviewer-selftest.mjs`'s Case F token + emit-wiring counts, which guard a constant's
*wiring* rather than its behavior). Behavior belongs on the shim. Pre-existing mutation-eval
anchors (`plugins/dev-pipeline/tools/score-review-selftest.sh`) stay grandfathered; this rule
binds newly added guards.

**Where a new test goes** (the tier map — full version in [`docs/testing.md`](docs/testing.md)):

| If you are guarding… | Write it as | Lives in |
| --- | --- | --- |
| one script's behavior against fixtures | a per-tool behavioral selftest | `*-selftest.sh` next to the tool |
| two copies of one contract staying identical | a `LOCKSTEP-BEGIN <anchor>` marker on **each** copy — they are discovered and grouped, never registered | the files themselves |
| a document's claim ABOUT shipped code | a derivation guard: read the fact out of the code, require the doc to state the same set, fail closed on an unmodelled shape | `scripts/check-*.sh` + its selftest |
| a composed verdict path reaching a terminal write | a scenario | `skills/build-lean/scenario-liveness-selftest.sh` |
| a production Workflow `.mjs` dispatch ladder | a shim case | `workflows/runtime-shim-selftest.mjs` |
| whether an existing suite actually catches a regression | a mutation-catalog row | `tools/mutation-catalog.tsv` |
| whether a shipped suite still passes where it is **installed** | **nothing** — the class guard already runs every shipped suite | `tools/install-topology-selftest.sh` |
| prose in a markdown file that asserts nothing checkable | **nothing** — see above | — |

**Test-the-tests.** `tools/mutation-sweep.sh` mutates the repo's shell guards and runs their
paired selftests; a mutant that survives is a regression the suite would not have caught. It runs
diff-scoped on every PR (the `mutation-sweep-pr` CI job) and wholesale nightly. **Those two are
the only places it runs** — the lean gate's milestone 3 does not sweep, and #580 deleted the lane
that did, because it made the identical invocation the PR job already makes. Survivors are
**data**, not a red build — only a
survivor absent from `tools/mutation-baseline.tsv`, or a named infra failure, reds a lane.
Generic survivor ids are **content-keyed**: the id is derived from the matched line itself, not
from its position, so inserting a line above a site, moving a block, or editing a comment re-keys
nothing and an ordinary guard edit carries **no re-baseline obligation**. One obligation still
lands on ordinary PRs: editing a guard's CODE re-anchors any `tools/mutation-catalog.tsv` row
addressing it, because catalog anchors are literal seds. A register row earns its keep by
naming the regression class it alone catches; that binds catalog rows and execution surfaces,
**not** a baseline row recording a site as unkillable by construction — deleting one of those
reds the next sweep on the survivor it exists to accept.
Full contract: [`docs/testing.md`](docs/testing.md).

**A new gate contract extends the liveness scenario** for every verdict path it touches — a gate
nothing composes against is a gate the next `#204` walks straight through.

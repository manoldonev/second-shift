# Model Tiering — dev-pipeline

The plugin's tier alphabet and the lockstep that keeps it honest. Portable, plugin-shipped,
and consumer-overridable.

**Where this came from.** Until #348 this lived in the staged `run` SKILL's "Model Tier
Mapping" / "Model Tiering" sections. The staged lane is gone; the tier CONTRACT is not tied to
it — the `.mjs` dispatch tables it governs (`workflows/`) survive and are still enforced at
commit time — so the sections moved here whole. What did NOT move is the per-stage tier table:
its rows were stage choreography (one row per stage 1-10), and there are no stages.

## Tier alphabet

Each LLM dispatch site uses a capability tier; this table maps tiers to concrete models. The tier each agent actually runs at lives in two places that must stay in lockstep: each agent's `model:` frontmatter (the `agents/<name>.md` in whichever plugin ships that agent) and the five `.mjs` dispatch tables that re-state it (`REVIEWER_MODEL`, `INTAKE_MODEL`, `DESIGN_MODEL`, `UNIT_TEST_MODEL`, `EXECUTOR_MODEL` under `workflows/`; `PLAN_REVIEWER_MODEL` was the sixth until #348 deleted Stage 4's dispatcher). `check-model-tiers.sh` (shipped in review-toolkit at `scripts/check-model-tiers.sh`) enforces that lockstep at commit time.

| Tier      | Model             | Rationale                                       |
| --------- | ----------------- | ----------------------------------------------- |
| reasoning | claude-opus-4-8   | Architectural reasoning, multi-domain synthesis |
| code      | claude-sonnet-4-6 | Fast, capable code generation                   |

**Elevating a tier per repo (`fable`).** The shipped reasoning default stays `opus` for every dispatched agent — that is exactly what a consumer without Fable access keeps. A repo whose subscription includes Fable-class models may elevate individual judgment-dense agents through config `reviewers.modelOverrides` (e.g. `"plan-reviewer": "fable"`); the override wins over the shipped table at every dispatch site, so neither the tables nor any agent frontmatter changes. Two consequences to know before setting one. A tier the subscription cannot actually dispatch produces a dead reviewer and the gate **fails closed** on it rather than quietly proceeding — loud, but yours to undo. And `fable` is **override-only**: in a shipped dispatch table or inline literal it is a `check-model-tiers.sh` `UNKNOWN-MODEL` error by design, which is what keeps the plugin defaults portable across consumers who do not have it.

## Anonymous-executor tiers

Most dispatch sites name an agent, so their tier is lockstep-checked against that agent's
`model:` frontmatter. One does not: `workflows/mutation-gate.mjs` dispatches ANONYMOUS
executors, which have no frontmatter to compare against. Its tier is therefore declared here
and `check-model-tiers.sh` holds `EXECUTOR_MODEL` to this line:

- mutation-gate executors: sonnet (`EXECUTOR_MODEL` in `workflows/mutation-gate.mjs`)

The tier stays consumer-overridable: the executor is the named logical agent
`mutation-executor`, and the script must route through `modelOverrides['mutation-executor']`
rather than reading the scalar directly — `check-model-tiers.sh` asserts that too (EP-4).

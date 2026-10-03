# Model Tiering — review-toolkit

The plugin's tier alphabet and the lockstep that keeps it honest. Portable, plugin-shipped,
and consumer-overridable.

## Tier alphabet

Each LLM dispatch site names an abstract **tier**; this table is the authority that turns a tier
into a concrete dispatch token. The tier each agent actually runs at lives in two places that must
stay in lockstep: each agent's `model:` frontmatter (the `agents/<name>.md` in whichever plugin
ships that agent) and the two `.mjs` dispatch tables that re-state it (`REVIEWER_MODEL` in
`workflows/code-review.mjs`, `INTAKE_MODEL` in `workflows/intake-review.mjs`, `FANOUT_MODEL` in `workflows/intake-fanout.mjs`). `check-model-tiers.sh`
(this plugin's `scripts/check-model-tiers.sh`) enforces that lockstep at commit
time.

**This table is PARSED, not just read.** `check-model-tiers.sh` reads the `Tier` and
`Dispatch token` columns as the shipped default map, and asserts that the `DEFAULT_TIER_MAP`
literal each `.mjs` engine inlines — the Workflow sandbox forbids imports, so the copies cannot be
removed — matches it. That is what "one authority" means here: the copies remain, and they are
checked.

| Tier      | Dispatch token | Model             | Rationale                                       |
| --------- | -------------- | ----------------- | ----------------------------------------------- |
| reasoning | opus           | claude-opus-4-8   | Architectural reasoning, multi-domain synthesis |
| code      | sonnet         | claude-sonnet-4-6 | Fast, capable code generation                   |
| emit      | haiku          | claude-haiku-4-5  | Transcription-only structured-output sink       |
| cross     | fable          | claude-fable-5-1  | A second model family for independent checks    |

**Retargeting a tier per repo (`reviewers.tierMap`).** A consumer maps any tier to a different
dispatch token in config — `"reviewers": { "tierMap": { "code": "haiku" } }`. The map **merges**
per tier: named tiers are retargeted, unnamed tiers keep the shipped default above, so a config
that sets nothing resolves exactly as it does today. This is the vendor-independence seam: the
shipped tables name tiers, never vendor tokens, so a consumer whose subscription lacks a
model-class retargets it in one line instead of forking the plugin.

A consumer `tierMap` is never a lockstep failure. `check-model-tiers.sh` compares the tables
against the **shipped default** map, exactly as it already treats `modelOverrides` — a consumer
resolving a tier differently is the feature, not drift.

**Elevating a tier per repo (`fable`).** The shipped reasoning default stays `opus` for every dispatched agent — that is exactly what a consumer without Fable access keeps. A repo whose subscription includes Fable-class models may elevate individual judgment-dense agents through config `reviewers.modelOverrides` (e.g. `"plan-reviewer": "fable"`); the override wins over the shipped table at every dispatch site, so neither the tables nor any agent frontmatter changes. Two consequences to know before setting one. A tier the subscription cannot actually dispatch produces a dead reviewer, reported as dead rather than quietly skipped — loud, but yours to undo. And `fable` is **override-only**: in a shipped dispatch table or inline literal it is a `check-model-tiers.sh` `UNKNOWN-MODEL` error by design, which is what keeps the plugin defaults portable across consumers who do not have it.

**The `cross` tier: the one shipped `fable` default.** The intake fan-out's refuter (`intake-refuter`, #916) ships at `cross`, so its claims are checked by a model family other than the `opus` lenses that made them. The fan-out's consumer replay measured that cross-family arm, and a per-repo override would leave it switched off almost everywhere. It is the single scoped exception to "the shipped default stays `opus`". A consumer without Fable access loses nothing: `intake-fanout.mjs` dispatches the first refuter at `cross`, and when that dispatch fails it runs every remaining refuter at `reasoning` and the receipt records `refuter: same-family (fable unavailable)`. One failed call is the whole cost. `reviewers.tierMap` (`"cross": "opus"`) or `reviewers.modelOverrides` turns the default off. No other agent ships at `cross`.

## Anonymous-executor tiers

Every dispatch site names an agent, so its tier is lockstep-checked against that agent's `model:`
frontmatter. A dispatcher whose executors have no frontmatter declares their tier under this
heading, for `check-model-tiers.sh` to hold its table against.

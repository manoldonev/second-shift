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

**Fable (`cross`).** Fable ships as the `cross` tier, and a shipped default names it wherever it
is useful: where a measurement backs it, or where a second model family is the point of the check.
There is no rule that shipped defaults stay `opus`. Two conditions travel with every use:

- **The dispatcher degrades.** A consumer without Fable access must lose a call, never an agent:
  an engine that dispatches at `cross` falls back to `reasoning` when the dispatch fails, and the
  record says so. `intake-fanout.mjs` does this, and so does `code-review.mjs`'s Refute phase
  (#992), the one place that engine dispatches at `cross`. Its reviewer seats do not degrade, which
  is why they stay off `cross`. `intake-review.mjs` does not degrade yet, which is why its agents
  stay at `reasoning` until it does.
- **The record says what was measured.** Fable as a second family is read against the published
  finding that two families from one provider still share many errors; a default that cites the
  other family as independent must have measured it.

Where it ships today: the intake fan-out (#916) runs its four angles alternating `reasoning` and
`cross`, its pre-mortem at `cross`, and refutes every claim on the family that did not make it,
the arm its consumer replay measured. Without Fable it runs every lens and refuter at `reasoning`
after two failed `cross` dispatches and records `same-family (fable unavailable)`.

A repo still retargets per agent through `reviewers.modelOverrides` (e.g. `"plan-reviewer": "fable"`)
or per tier through `reviewers.tierMap` (`"cross": "opus"` turns Fable off). A tier the
subscription cannot dispatch, set by override on an engine that does not degrade, produces a dead
reviewer, reported as dead rather than quietly skipped.

The review fan-out's Refute phase (#992) is the second shipped use. On `panel: 'substantial'`, and
in refute-only mode, every `blocker` or `major` finding goes to `finding-refuter` on the family
that did not make it. Each such finding then records `reproduced`, `refuted` (kept, with the
refuter's evidence) or `unverified` (the refuter went dark, gave no verdict, or was still running at
the 3-minute refute ceiling), so the finding stands. Two thrown `cross` dispatches with no success
move the remaining refuters to `reasoning`, and their findings then record
`same-family (fable unavailable)`.

## Substantial panel

On `panel: 'substantial'` the review fan-out runs its specialist seats at the tiers below instead
of their frontmatter tiers. The agents' frontmatter is unchanged, so standalone `/review-lead` keeps
its cheaper seats. A consumer `reviewers.modelOverrides` entry still wins over this table. The
table is **parsed**. `check-model-tiers.sh` holds `SUBSTANTIAL_MODEL` in
`workflows/code-review.mjs` against it in both directions, and it does not compare those rows
against frontmatter, because they differ from it on purpose.

| Agent                                      | Tier      |
| ------------------------------------------ | --------- |
| review-toolkit:security-reviewer           | reasoning |
| review-toolkit:performance-reviewer        | reasoning |
| review-toolkit:maintainability-reviewer    | reasoning |
| review-toolkit:complexity-reviewer         | reasoning |
| review-toolkit:test-coverage-reviewer      | reasoning |
| review-toolkit:unit-test-mutation-reviewer | reasoning |

## Anonymous-executor tiers

Every dispatch site names an agent, so its tier is lockstep-checked against that agent's `model:`
frontmatter. A dispatcher whose executors have no frontmatter declares their tier under this
heading, for `check-model-tiers.sh` to hold its table against.

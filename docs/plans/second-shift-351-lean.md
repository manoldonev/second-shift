# #351 — Vendor-neutral model tiers, config-resolved indirection

Child of the vendor-independence epic (#350). Introduces the indirection layer between tier
intent and vendor model tokens: dispatch sites name an abstract tier, and a config-resolved map
turns that tier into a concrete dispatch model.

Binding input is the re-intake receipt `.claude/pipeline-state/351-ledger.md` (2026-08-19), which
supersedes the pre-teardown receipt. **The ticket body is pre-teardown and is superseded where it
disagrees**: #577 (`7620251`) and #584 (`d344956`) deleted `design-sync.mjs`, `unit-tests.mjs`,
`mutation-gate.mjs` and `figma.mjs`, so the ticket's "eight dispatch sites", "tier enum in at
least five copies", and its scope bullet promoting tiers into agent frontmatter do not describe
this tree (receipt D-1, D-14).

## Edit surface, re-derived against `eb3046e`

Governed set is TWO files carrying THREE governed dispatch shapes:

| Site | Shape | Today |
| --- | --- | --- |
| `plugins/dev-pipeline/workflows/code-review.mjs:22` | `REVIEWER_MODEL` map, 12 entries | raw model tokens |
| `plugins/dev-pipeline/workflows/intake-review.mjs:15` | `INTAKE_MODEL` map, 2 entries | raw model tokens |
| both files, `:243` | `structured-emitter` inline dispatch | hardcoded `model: 'haiku'`, no override lookup |

## Scope

- Promote abstract tiers to first-class tokens in the two surviving dispatch tables. Agent
  frontmatter stays harness-native (D-1).
- Add the `reviewers.tierMap` config seam mapping tier to dispatch model, defaulting to today's
  opus / sonnet / haiku so existing consumers change nothing (D-3, D-17).
- Route every governed dispatch site through the seam, including the `structured-emitter` site,
  whose override bypass is fixed (D-15).
- Make `plugins/dev-pipeline/model-tiering.md`'s alphabet table the single parsed authority for
  the default map, with a `Dispatch token` column (D-5, D-16).
- In the tier lint, only the enum-anchored parse regexes take the variable alphabet; the
  deliberately UNRESTRICTED unknown-model counter-scans stay unrestricted.
- Schema honesty: the cross-field constraint is inexpressible in JSON Schema, so that half
  degrades to a documented weaker assertion and the jq lint carries the real check (D-10).
- Lockstep invariant preserved: only the alphabet becomes configurable, and a consumer `tierMap`
  is never a source of MISMATCH (D-18).

Out of scope: `stall-probe.mjs`'s four tier literals stay experimental controls, un-governed;
`configVersion` stays 2 (D-9); no new lockstep-manifest entry is invented (D-12).

## Acceptance Criteria

- **AC-1** (oracle — `workflows/runtime-shim-selftest.mjs`, cases per surviving dispatch ladder):
  with no `tierMap` configured, each governed site resolves to the model it dispatches today; a
  custom `tierMap` value reaches the dispatch; a `modelOverrides` entry beats the `tierMap`; and
  the newly governed `structured-emitter` site honors an override.
- **AC-2** (oracle — `tools/config-lint-selftest.sh`): a config with no tier map lints clean and
  resolves today's models (backward compat); an override naming a tier absent from the effective
  tierMap FAILS lint (typo detection preserved); a `tierMap` value outside the dispatch-model set
  FAILS lint; the both-sides schema/lint cases are restated for the weakened schema half.
- **AC-3** (oracle — `plugins/review-toolkit/scripts/check-model-tiers-selftest.sh`):
  custom-alphabet cases pass; `fable` in a shipped MAP still fails as UNKNOWN-MODEL; the
  counter-scans still catch an out-of-alphabet token in a governed file (non-vacuity of the
  unrestricted layer); and a consumer `tierMap` that retargets a tier produces NO MISMATCH.
- **AC-4** (oracle — sweeps): diff-scoped mutation re-baseline for every edited guard, including
  its position-keyed baseline rows; the `scripts/lockstep-manifest.tsv:58` DROPPED entry is
  amended to name tierMap rather than a second entry being added.
- **AC-5** (critic): a `Changelog:` trailer is present, and consumer-visible defaults are
  unchanged — every default resolves exactly as it does today.
- **AC-6** (doc): `model-tiering.md`'s alphabet table carries the `Dispatch token` column and the
  `emit` row and is the parsed authority; its prose naming five `.mjs` tables (three deleted) is
  corrected, as is `stall-probe.mjs`'s "six named tables" comment; `docs/extension-points.md`
  EP-4 and the `onboard` SKILL prose state the accepted-value union from D-2.

## Decision Ledger

Carried from the re-intake receipt. All nine bound rows are carried forward unchanged — this
spec departs from none of them.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Where the abstract tier tokens actually live | Dispatch tables and `modelOverrides` only; agent frontmatter stays harness-native. `check-model-tiers.sh` lockstep compares RESOLVED strings — `tierMap[table_tier] == frontmatter_model`. This AMENDS ticket scope bullet 1: `model:` in `agents/*.md` is a harness-owned key (all 25 tokens on disk are harness tokens), so an abstract token there is an unrecognized value in someone else's key. | user-answered |
| D-2 | Legal value for a `reviewers.modelOverrides` entry | Closed union: a `tierMap` key OR a member of the closed dispatch-model set (haiku / sonnet / opus / fable). A token in neither fails lint, which is how AC-2's typo detection survives; existing `"plan-reviewer": "fable"` configs are untouched. | user-answered |
| D-3 | Config location of the tier map | `reviewers.tierMap`, co-located with `modelOverrides` — NOT the ticket's `models.tierMap`. After D-2 the two are one feature, and `CONFIG.reviewers` is already carried by every Workflow config-subset call site, so no new silent-disable seam is introduced. | user-answered |
| D-5 | Single authority for the DEFAULT tier-to-model map, given the .mjs sandbox forbids imports | The Tier alphabet table in `plugins/dev-pipeline/model-tiering.md`, parsed by `check-model-tiers.sh`, which asserts every in-.mjs inline default matches. NARROWED at re-intake: the row's cited precedent (extending this script's `EXECUTOR_MODEL` lockstep) was retired with `mutation-gate.mjs` in #574, so the alphabet is held directly rather than by extending a one-line precedent. Copies remain because the sandbox forbids removing them, but they are checked. Parse format settled by D-16. | user-answered |
| D-6 | Tier alphabet and map key naming | `reasoning`/`code`/`emit`, at `reviewers.tierMap`. Reversible; flagged in the PR under OR-1. | user-answered |
| D-15 | Which site replaces figma.mjs as the ungoverned dispatch site D-4 named | The `structured-emitter` dispatch — `code-review.mjs:243` and `intake-review.mjs:243` — which hardcodes `model: 'haiku'` and never consults `modelOverrides`. It resolves through the `emit` tier and honors `modelOverrides`, bringing the governed set to 2 files with 3 governed dispatch shapes. It is the only remaining site matching the ticket's "ungoverned … its override bypass fixed"; there is no consumer knob for it today in schema, config-lint or extension-points; and a consumer whose vendor has no haiku-class model currently cannot dispatch it at all, which is epic #350's premise. Gives `emit` a real referent. | user-answered |
| D-16 | How the parsed authority table carries both tier and dispatch token | `model-tiering.md`'s alphabet table gains a `Dispatch token` column — Tier / Dispatch token / Model / Rationale — and `check-model-tiers.sh` parses Tier plus Dispatch token. The pinned concrete id stays as documentation rather than being overwritten. Additive, and the parse anchors on a column that means exactly one thing. | user-answered |
| D-17 | Effective-map semantics when a consumer sets only some tiers | MERGE per tier: a config `tierMap` overrides the named tiers and unnamed tiers keep the shipped default. Backward compatibility is the ticket's own requirement ("existing consumers change nothing"), and merge makes AC-2's "effective tierMap" total, so a shipped table can never resolve to undefined and needs no new error class. | user-answered |
| D-18 | Which map `check-model-tiers.sh` lockstep-compares against | The SHIPPED DEFAULT map from `model-tiering.md`. A consumer `tierMap` is treated exactly like `modelOverrides` — never a source of MISMATCH. This mirrors the guard's existing override precedent at `check-model-tiers.sh:231-237`, where a consumer override differing from the shipped table is the feature rather than drift. Without it, any tierMap customization would red the commit hook. | user-answered |

Receipt rows D-4, D-7 and D-8 are recorded there as VOID `fact` rows: their subjects were deleted
by #584, so they bind nothing here. D-8's void restores AC-5 as originally written — **no
consumer-visible default changes in this PR**.

Open regions carried: OR-1 (tier alphabet and config key naming) and OR-3 (whether a consumer
retargeting `emit` degrades structured transcription), both `reversible-default-and-flag` and
both to be flagged in the PR body.

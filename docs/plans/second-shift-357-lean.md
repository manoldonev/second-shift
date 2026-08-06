# 357 — cost-tracking fixtures: model-string bucketing neutrality

Lean spec. Binding input: the pre-flight receipt `.claude/pipeline-state/357-ledger.md` (D-1…D-11,
OR-1/OR-2) and the operator-ratified intake comment on the issue, which supersedes the stub body.

## Problem

`pipeline-cost-block.sh` buckets OTel spend by **stage label only**; the vendor-full model id rides
along as a decorative `models` set. Two consequences: any consumer that starts bucketing by that set
inherits a single-vendor assumption, and the ids churn per version so a cross-run axis keyed on them
fragments. The defect the issue title names is narrower and sharper — `cost-block-selftest.sh` makes
**no assertion on `model` at all**, so no test today could fail on vendor coupling.

The fix is a tier dimension the cost path owns: a script-constant telemetry-id → tier map, tier as a
bucket key beside the stage label, and a fixture that gives both the map and the fallback a kill
criterion.

## Acceptance criteria

**AC-1 — the tier map.** `pipeline-cost-block.sh` carries a telemetry-id → tier map as a **script
constant**: no config key, no schema edit, no `configVersion` change (D-3). The vocabulary is
`reasoning` / `code` / `emit` (D-5). The classification is **total** over datapoints (D-7): an id
matching no family, and a datapoint carrying no `model` attribute at all, both resolve to `unknown`.

**AC-2 — tier as a bucket key in the rollup.** `byLabel` rows group by (label, tier) — one row per
stage label per tier — each retaining `models` as the secondary field. Ordering is the existing
stage-label order, then a deterministic tier order, so rows sharing a label never permute between
runs. Nothing is removed: every (label, tier) pair present in the fenced datapoint set has a row, so
the rollup and the `cost-log.jsonl` row stay total (D-4, D-7).

**AC-3 — Tier column on the rendered block.** Both rendered layouts gain the tier dimension: the
per-stage table gains a `Tier` column, the single-row session total gains a tier list. The per-stage
table renders only **reportable** rows — a row with zero cost *and* an empty `models` set names
neither spend nor a model, and is omitted; the session total's tier list is derived from the same
reportable set. Rendered row costs still sum to the rendered total. This is a **render-side** filter
only: AC-2's rollup and AC-4's log row remain total.

> Why the filter exists, and why it is render-only. In live telemetry `claude_code.active_time.total`,
> `code_edit_tool.decision` and `pull_request.count` datapoints carry **no** `model` attribute (measured:
> 348 of 1093 datapoints in a recent slice). Under AC-1's totality each one tiers to `unknown`, so
> without this filter every stage label would gain a companion `| unknown | | $0.00 |` row — roughly
> doubling the table D-4 justifies by "the PR block is the artifact a human actually reads". Dropping
> them in the *rollup* instead would violate D-4's "nothing is removed"; filtering at the render keeps
> the durable record total and the human artifact honest. The receipt does not reach this fork; it is
> resolved here, against D-4's own stated rationale, and flagged in the PR.

**AC-4 — `tiers` on the cost-log row.** The `cost-log.jsonl` row gains a **top-level** `tiers` array
beside the unchanged `models` array. Additive only — `stage-envelopes.sh`, the one downstream reader,
reads `byLabel[].label` and `.cost_usd` and re-groups by label (fact 3), so the extra rows fold and
already-written rows stay readable.

**AC-5 — the cross-vendor fixture.** A new fixture pair under `cost-tracking-fixtures/` (metrics
JSONL + companion state file) carrying: cost datapoints for each Anthropic family the default map
covers, one **non-Anthropic** id the map does not cover, and one cost datapoint with **no `model`
attribute**; plus a zero-cost model-less datapoint and a zero-cost datapoint that names a model, in
two different stage windows, so AC-3's filter has both of its cases. `README.md` lists the new files
and what they pin.

**AC-6 — the assertions.** `cost-block-selftest.sh` asserts against that fixture: the (label, tier)
split; that the unmatched id **and** the attribute-less datapoint both land in `unknown`; that
`models` survives as the secondary field on each tier row; that the rendered per-stage table carries
the `Tier` column, **omits** the zero-cost/no-model row and **keeps** the zero-cost row that names a
model; and that the cost-log row carries a top-level `tiers` array.

**AC-7 — the existing fixtures become the default map's oracle.** They keep their ids (D-6). At least
one assertion over `two-runs-shared-session.jsonl` fails if the map stops classifying
`claude-opus-4-7`, and at least one fails for `claude-sonnet-4-6`; the `single-session-mini.jsonl`
state-less block's tier list is asserted. Today no assertion in this suite touches `model`, which is
the defect behind the issue's title.

**AC-8 — the header contract and the `--help` range.** The header states the tier-map contract (the
alphabet, the covered families, the `unknown` fallback). `--help`'s `sed` range prints **through the
header's last line and stops before the first line of code** — asserted by a selftest case that
derives the expected end **from the file**, not from a hardcoded number, so the assertion cannot rot
as the header grows. This incidentally repairs the pre-existing off-by-one (the range stops at 26
while the header ends at 27, truncating mid-sentence).

**AC-9 — mutation obligations.** The four `pipeline-cost-block.sh` rows at
`tools/mutation-baseline.tsv:57-60` (`cmp-z::1`, `default::2`, `detector::1`, `logic::2`) are
re-verified against this diff by **diffing each operator's site enumeration against the base branch**
— by site, never by survivor-id equality or line content — and re-baselined in this same diff if the
edit moves or kills them. `tools/mutation-catalog.tsv:37` (`cost-block-cache-numerator`) targets the
cache-rate math, untouched here; it is re-anchored only if its ordinal moves.

**AC-10 — scope boundary.** No file changes outside
`plugins/dev-pipeline/skills/run/pipeline-cost-block.sh`,
`plugins/dev-pipeline/skills/run/cost-tracking-fixtures/`,
`plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh`, this spec, and
`tools/mutation-baseline.tsv` (AC-9 only, and only if AC-9's diff requires it). Out of scope per
D-11: `retro-corpus.sh` / `perf-retro`, `LEAN_RUN_MODEL` and the progress/verdict `model:` key,
`plugins/*/evals/**` ids (#356), and #351's `models.tierMap` / dispatch alphabet — no lockstep row is
opened between the two maps, because they are not two copies of one contract (fact 1: different
alphabets, different inputs).

## Open regions carried into the PR

- **OR-1** — `reasoning`/`code`/`emit` is #351's alphabet to ratify and this lands it in a durable log
  first. Reversible default taken; flagged in the PR body. If #351 ratifies a different alphabet, this
  map follows it.
- **OR-2** — the default map covers today's Anthropic families only. An unrecognized backend reads
  honestly as `unknown`; the fix is one map entry. A green fixture proves the map's *mechanism*, never
  its *coverage* of a vendor nobody has run yet.
- **AC-3's render filter** — the fork the receipt does not reach, resolved above and flagged in the PR
  alongside the two open regions.

## Verification

```bash
bash plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} bash {}
```

`Changelog:` trailer required — the PR cost block's Tier column and the cost-log row's `tiers` key
are both consumer-visible.

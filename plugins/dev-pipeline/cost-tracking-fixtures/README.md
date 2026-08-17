# Cost-tracking fixtures

Hermetic OTel metrics fixtures for ad-hoc verification of `pipeline-cost-block.sh` without depending on a real `~/.claude/otel-metrics/metrics.jsonl` file.

## How to use

```bash
# From the marketplace repo root: set the metrics file override and a temp state file, then invoke:
export OTEL_METRICS_FILE="$(pwd)/plugins/dev-pipeline/cost-tracking-fixtures/single-session-mini.jsonl"
mkdir -p .claude/pipeline-state
cp plugins/dev-pipeline/cost-tracking-fixtures/state-single-session-mini.json \
   .claude/pipeline-state/test-cost.json
bash plugins/dev-pipeline/tools/pipeline-cost-block.sh test-cost
jq '.costBlockApplied' .claude/pipeline-state/test-cost.json
```

Expected outcome depends on local prerequisites:

- Bot **enabled** (config `tracker.bot.enabled: true`) with no wrapper → `"skipped-no-bot-wrapper"`.
- Otherwise (bot disabled, or no config at all) the amend proceeds under operator identity via plain `gh` — no wrapper needed.
- Either way, once the amend is reached the fixture PR does not exist, so `gh pr view` fails and the outcome is `"skipped-amend-failed"`. Note the URL itself parses fine (`https://github.com/owner/repo/pull/8002` yields `owner/repo` + `8002`) — the failure is the read against a nonexistent PR, not a parse error.
- For an actual end-to-end check, swap the `prs` block in the state fixture for a real scratch PR URL before invoking.

To inspect the computed rollup without a PR, set `COST_BLOCK_DUMP_ROLLUP=1` — the script prints the time-fenced rollup JSON and exits before any PR I/O.

Note the **per-run time fence**: datapoints are kept only when their timestamp is inside `[startedAt, max(stage completedAt) // lastUpdatedAt]`. A fixture datapoint must therefore fall inside its state file's stage windows, or it is excluded.

## Files

- `single-session-mini.jsonl` — one Claude session, five datapoints (one cost row, four token rows split across `input` / `output` / `cacheRead` / `cacheCreation`), all timestamped at `2026-05-25T12:20:00Z` (inside the state fixture's Stage 6 / Implementation window). Cost rollup should report ~$0.50 USD under the `Implementation` bucket with a non-zero cache-hit rate.
- `state-single-session-mini.json` — companion state file with `pipelineSessions[]` matching the session id in the metrics fixture, valid stage windows, and a placeholder `prs` map. The session id is a native-UUID shape (`aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee`), the same form the OTel collector emits as `session.id` and the only form `statectl pipeline-session-add` accepts.
- `two-runs-shared-session.jsonl` + `state-two-runs-A.json` / `state-two-runs-B.json` — two sequential runs that share **one** `session.id` (`11111111-2222-4333-8444-555555555555`) with disjoint wall-clock fences (A `10:00–10:30`, B `11:00–11:20`). The metrics file carries A's `$1.00` and B's `$0.30` (in-window → `Plan`) + `$0.10` (in an inter-stage gap → `Other`) + `$0.05` (at exactly `11:20` = B's `fenceHi`, exercising the inclusive upper bound → `PR Creation`). They drive `tools/cost-block-selftest.sh`, the regression guard for the per-run time fence: each run's rollup must exclude the other's co-resident cost. Their model ids are **not decoration**: A's whole `$1.00` is `claude-opus-4-7` and B's whole `$0.45` is `claude-sonnet-4-6`, which makes this pair the shipped tier map's oracle — drop either family from the map and the suite reds.
- `cross-vendor.jsonl` + `state-cross-vendor.json` — one session (`33333333-4444-4555-8666-777777777777`, fence `09:00–09:40`) built for the **tier** axis rather than the time fence. Five cost datapoints sit inside a single stage window (stage 5 → `Implementation`), so tier is the only thing that can split them: `$0.40` `claude-opus-4-7` → `reasoning`, `$0.20` `claude-sonnet-4-6` → `code`, `$0.05` `claude-haiku-4-5-20251001` → `emit`, `$0.10` `mistral-large-2` (a family the default map does **not** cover) → `unknown`, and `$0.05` on a datapoint carrying **no `model` attribute at all** → also `unknown`. The two `unknown` amounts differ on purpose, so one assertion separates "the attribute-less datapoint was dropped" (10¢ instead of 15¢) from "the unmatched vendor id was mis-tiered" (5¢). Two further datapoints give the render filter both of its cases: a `token.usage` row with a model in stage 7 (`Doc Update` — zero cost but a named model, **kept** in the rendered table) and an `active_time.total` row with no model in stage 8 (`Code Review` — zero cost and no model, present in the rollup and the cost-log row but **omitted** from the rendered table).

Fixtures are intentionally tiny and human-readable; expand them if you need to test the per-stage bucketing in more detail.

## Regression selftest

```bash
bash plugins/dev-pipeline/tools/cost-block-selftest.sh
```

Drives both shared-session runs through the `COST_BLOCK_DUMP_ROLLUP` hook and asserts run A totals `$1.00`, run B totals `$0.45` (A's `$1.00` not inhaled), run B's `Other` holds only the `$0.10` in-fence gap cost, and the `$0.05` datapoint at exactly `fenceHi` is kept (inclusive bound) under `PR Creation`. Exit 0 = pass.

It also drives `cross-vendor.jsonl` twice — once through the rollup hook, once end-to-end through a `gh` stub that captures the amend payload — because the rendered table (the Tier column and its render filter) exists nowhere but the PR body.

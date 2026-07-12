# Cost-tracking fixtures

Hermetic OTel metrics fixtures for ad-hoc verification of `pipeline-cost-block.sh` without depending on a real `~/.claude/otel-metrics/metrics.jsonl` file.

## How to use

```bash
# Set the metrics file override and a temp state file, then invoke:
export OTEL_METRICS_FILE="$(pwd)/.claude/skills/run/cost-tracking-fixtures/single-session-mini.jsonl"
mkdir -p .claude/pipeline-state
cp .claude/skills/run/cost-tracking-fixtures/state-single-session-mini.json \
   .claude/pipeline-state/test-cost.json
bash .claude/skills/run/pipeline-cost-block.sh test-cost
jq '.costBlockApplied' .claude/pipeline-state/test-cost.json
```

Expected outcome depends on local prerequisites:

- No `$GH_BOT` wrapper → `"skipped-no-bot-wrapper"`.
- `$GH_BOT` present + no real PR in the fixture → reaches the amend step, fails the parse (fixture PRs are fake URLs) → `"skipped-amend-failed"`.
- For an actual end-to-end check, swap the `prs` block in the state fixture for a real scratch PR URL before invoking.

To inspect the computed rollup without a PR, set `COST_BLOCK_DUMP_ROLLUP=1` — the script prints the time-fenced rollup JSON and exits before any PR I/O.

Note the **per-run time fence**: datapoints are kept only when their timestamp is inside `[startedAt, max(stage completedAt) // lastUpdatedAt]`. A fixture datapoint must therefore fall inside its state file's stage windows, or it is excluded.

## Files

- `single-session-mini.jsonl` — one Claude session, five datapoints (one cost row, four token rows split across `input` / `output` / `cacheRead` / `cacheCreation`), all timestamped at `2026-05-25T12:20:00Z` (inside the state fixture's Stage 6 / Implementation window). Cost rollup should report ~$0.50 USD under the `Implementation` bucket with a non-zero cache-hit rate.
- `state-single-session-mini.json` — companion state file with `pipelineSessions[]` matching the session id in the metrics fixture, valid stage windows, and a placeholder `prs` map. The session id is a native-UUID shape (`aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee`), the same form the OTel collector emits as `session.id` and the only form `statectl pipeline-session-add` accepts.
- `two-runs-shared-session.jsonl` + `state-two-runs-A.json` / `state-two-runs-B.json` — two sequential runs that share **one** `session.id` (`11111111-2222-4333-8444-555555555555`) with disjoint wall-clock fences (A `10:00–10:30`, B `11:00–11:20`). The metrics file carries A's `$1.00` and B's `$0.30` (in-window → `Plan`) + `$0.10` (in an inter-stage gap → `Other`) + `$0.05` (at exactly `11:20` = B's `fenceHi`, exercising the inclusive upper bound → `PR Creation`). They drive `tools/cost-block-selftest.sh`, the regression guard for the per-run time fence: each run's rollup must exclude the other's co-resident cost.

Fixtures are intentionally tiny and human-readable; expand them if you need to test the per-stage bucketing in more detail.

## Regression selftest

```bash
bash .claude/skills/run/tools/cost-block-selftest.sh
```

Drives both shared-session runs through the `COST_BLOCK_DUMP_ROLLUP` hook and asserts run A totals `$1.00`, run B totals `$0.45` (A's `$1.00` not inhaled), run B's `Other` holds only the `$0.10` in-fence gap cost, and the `$0.05` datapoint at exactly `fenceHi` is kept (inclusive bound) under `PR Creation`. Exit 0 = pass.

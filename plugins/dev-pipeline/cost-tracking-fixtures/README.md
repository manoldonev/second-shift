# Cost-tracking fixtures

Hermetic OTel metrics fixtures for ad-hoc verification of `pipeline-cost-block.sh` without
depending on a real `~/.claude/otel-metrics/metrics.jsonl` file. The script is state-less
only (#574): the session-id set and the time fence arrive as arguments.

## How to use

```bash
# From the marketplace repo root:
OTEL_METRICS_FILE="$(pwd)/plugins/dev-pipeline/cost-tracking-fixtures/single-session-mini.jsonl" \
  bash plugins/dev-pipeline/tools/pipeline-cost-block.sh --stateless \
    --sessions "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee" \
    --start "2026-05-01T00:00:00Z" --end "2026-06-01T00:00:00Z"
```

The rendered block goes to stdout (or `--out <file>`). To inspect the computed rollup
instead, set `COST_BLOCK_DUMP_ROLLUP=1` — the script prints the time-fenced rollup JSON
and exits before rendering.

Note the **per-run time fence**: datapoints are kept only when their timestamp is inside
`[--start, --end]`. A fixture datapoint must fall inside the fence you pass, or it is
excluded — that exclusion being the point of the fence (#224).

## Files

- `single-session-mini.jsonl` — one Claude session (`aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee`),
  five datapoints (one cost row, four token rows split across `input` / `output` /
  `cacheRead` / `cacheCreation`), all timestamped `2026-05-25T12:20:00Z`. Cost rollup
  reports ~$0.50 USD in the `reasoning` tier with a non-zero cache-hit rate.
- `two-runs-shared-session.jsonl` — ONE session id
  (`11111111-2222-4333-8444-555555555555`) carrying two runs' datapoints: $1.00 @
  2026-05-25T10:15 (claude-opus-4-7) and $0.30/$0.10/$0.05 @ 11:08/11:11/11:20
  (claude-sonnet-4-6). The fence-regression oracle (#224): a [10:00,10:30] fence must
  total $1.00 and a [11:00,11:20] fence $0.45, the boundary point included.
- `cross-vendor.jsonl` — one session (`33333333-4444-4555-8666-777777777777`), window
  [2026-06-10T09:00,09:40]: five cost datapoints spanning three Anthropic families, one
  non-Anthropic id (`mistral-large-2`) and one datapoint with no `model` attribute, plus
  a zero-cost sonnet row and zero-cost model-less token rows. The vendor-neutrality
  oracle (#357): tiers split 40/20/5/15 cents, total $0.80.

`cost-block-selftest.sh` drives all three; the state-file fixtures that used to sit
beside them died with the stateful branch (#574).

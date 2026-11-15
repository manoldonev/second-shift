# Agent Eval Kit

Shared helpers for the eval harnesses that drive the `claude` CLI on the operator's subscription.
`run-eval.py` is a library, not a runner: `code-review-bench-eval/bench.py` loads it by path with
`importlib` (the hyphenated name is not importable), and `code-review-bench-eval/planted/planted.py`
reaches it through `bench.kit`.

| Helper | Purpose |
|--------|---------|
| `run_claude(args, timeout_s, cwd)` | Spawns the CLI with a hard wall-clock kill at `timeout_s` |
| `extract_result_text(stdout)` | Parses the CLI's `--output-format json` envelope into `(text, envelope)` |
| `check_rate_limit(text, where)` | Raises `RateLimitedError` when the text carries a quota stop |
| `changelog_row(started_at, segments)` | One append-only `changelog.md` line: ISO start time, then `k=v` segments joined by ` \| ` |
| `append_changelog(path, line)` | Appends that line |

## Quota stops

`check_rate_limit` is a substring match against `RATE_LIMIT_MARKERS`: the "hit your limit",
"reached your", "resets at", "session limit" and "usage limit" messages. A harness that sees one
aborts the whole run, since further calls only burn quota with no signal. A new limit message from
a future CLI version goes into that tuple, not into a caller.

## Model identity

The kit holds no model id and takes none: the caller passes the model in `args`. The harnesses
read it from `REVIEWER_MODEL` and `JUDGE_MODEL`; see `code-review-bench-eval/README.md`.

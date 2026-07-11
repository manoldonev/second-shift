# Agent Eval Kit

Generic harness for evaluating any Claude Code agent (under `.claude/agents/`) against
a locked fixture set with LLM-as-judge scoring. Uses the `claude` CLI and the user's
Claude subscription — no Anthropic API key.

Built during the `plan-reviewer` autoresearch campaign (see
`../plan-reviewer-eval/FINAL-REPORT.md`) and extracted for reuse.

## What it does

- Spawns N concurrent `claude -p --agent <name>` subprocesses against each fixture
- Captures cost, token counts, latency, stdout per run
- For each reviewer output, invokes an inline judge agent (`claude -p --agents '{...}'`)
  configured with your rubric
- Scores each run on an arbitrary weighted rubric (dict of `dim_name -> max_points`)
- Writes a per-run / per-fixture / per-dimension JSON to your eval directory
- Appends a one-line summary to `changelog.md` in your eval directory
- Aborts immediately on rate-limit detection (scans for "hit your limit" / "resets at")

## What's generic vs per-eval

| Kit (generic) | Per-eval directory |
|---------------|--------------------|
| `run-eval.py` — runner | `rubric.py` — `JUDGE_SYSTEM` + `MAX_POINTS` |
| `README.md` — this file | `fixtures/*.md` + `fixtures/*.expected.json` |
|  | `run.sh` — one-liner wrapper with args |
|  | `changelog.md` — append-only |
|  | `results-*.json` — gitignored |

## Setup for a new agent

1. Create a directory for your eval:

   ```bash
   mkdir -p .claude/pipeline-state/my-agent-eval
   cd .claude/pipeline-state/my-agent-eval
   ```

2. Create `rubric.py` defining `JUDGE_SYSTEM` (str, the full judge prompt) and
   `MAX_POINTS` (dict mapping dimension-name to positive int max-points). Example:

   ```python
   # rubric.py
   MAX_POINTS = {
       "d1_correctness": 2,
       "d2_completeness": 1,
       "d3_no_hallucination": 1,
   }

   JUDGE_SYSTEM = """You are scoring an agent output...
   Return ONLY a JSON object with keys d1_correctness (0-2),
   d2_completeness (0-1), d3_no_hallucination (0-1), plus
   a "justifications" sub-object with one sentence per dim.
   [your rubric text here]
   """
   ```

3. Create fixtures. Each fixture is two files in a fixtures directory:
   - `my-fixture.md` — the content fed to the agent (e.g. a plan, a spec, a code diff)
   - `my-fixture.expected.json` — the ground truth (e.g. planted defects, expected verdict)

4. Create `run.sh` with the invocation:

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   HERE="$(cd "$(dirname "$0")" && pwd)"
   REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
   python3 "$REPO/.claude/pipeline-state/agent-eval-kit/run-eval.py" \
     --agent-name my-agent \
     --rubric "$HERE/rubric.py" \
     --fixtures-dir "$REPO/docs/my-eval-fixtures" \
     --eval-dir "$HERE" \
     --runs-per-fixture 6 \
     --concurrency 4 \
     --note "${1:-baseline}"
   ```

5. Add a local `.gitignore`:
   ```
   results-*.json
   ```

6. Smoke test: `./run.sh smoke-test` with `--smoke` flag appended to catch harness
   issues before burning 60 runs of quota.

## Runner flags

| Flag | Required | Default | Purpose |
|------|----------|---------|---------|
| `--agent-name` | yes | — | `--agent` value for `claude` CLI |
| `--rubric` | yes | — | Path to Python file with `JUDGE_SYSTEM` + `MAX_POINTS` |
| `--fixtures-dir` | yes | — | Directory of `*.md` + `*.expected.json` pairs |
| `--eval-dir` | yes | — | Where to write `results-*.json` + `changelog.md` |
| `--repo-root` | no | `git rev-parse --show-toplevel` | CWD for subprocess + file-path relativization |
| `--reviewer-user-prompt-template` | no | `"Review the content at {fixture_path}. Run ID: {run_id}"` | Template with `{fixture_path}` / `{run_id}` |
| `--judge-agent-name` | no | `eval-judge` | Inline judge agent name |
| `--judge-description` | no | generic | Inline judge agent description |
| `--model` | no | `claude-opus-4-7` | Default model for reviewer and judge (override per-role below) |
| `--reviewer-model` | no | `--model` | Override `--model` for the reviewer invocation only |
| `--judge-model` | no | `--model` | Override `--model` for the judge invocation only |
| `--effort` | no | `high` | Effort level (low/medium/high/max) |
| `--runs-per-fixture` | no | 6 | Runs per fixture |
| `--concurrency` | no | 4 | Parallel reviewer + judge calls |
| `--note` | no | `baseline` | Tag written to changelog |
| `--smoke` | no | off | 1 fixture × 1 run |
| `--max-budget-usd` | no | 5.0 | Per-CLI-invocation budget cap |
| `--reviewer-timeout-s` | no | 900.0 | Hard wall-clock kill for reviewer calls |
| `--judge-timeout-s` | no | 400.0 | Hard wall-clock kill for judge calls |

## Session-quota awareness

Each reviewer+judge pair burns ~90–120s of Opus-4.7 time. Sixty runs at concurrency
4 can consume 30-40% of a user's 5-hour Claude subscription window. Before running
a full eval:

- Surface the expected quota hit explicitly
- Prefer lower concurrency (2) and fewer runs (3-4) for iterative work
- The harness aborts on rate-limit detection, but aborting mid-run means wasted
  prior spend — better to not start if quota is already low

## Results JSON schema

```
{
  "started_at": ISO timestamp,
  "finished_at": ISO timestamp,
  "agent_name": str,
  "agent_sha": git SHA at run time,
  "note": str,
  "model": str, "effort": str,
  "runs_per_fixture": int,
  "num_fixtures": int,
  "rubric_max": int (sum of MAX_POINTS values),
  "max_points": dict,
  "overall_pct": float,
  "per_dim": {
    "<dim_name>": { "pct": float, "avg": float, "max": int, "n": int }
  },
  "per_fixture": {
    "<fixture_name>": { "pct": float, "per_dim": {...}, "expected_verdict": str }
  },
  "detail": {
    "<fixture_name>": {
      "runs": [ per-run dict with reviewer output, judge parsed, points, per_dim ],
      "expected": the fixture's .expected.json
    }
  }
}
```

## Known limitations

- Fixture loader assumes `*.md` + `*.expected.json` pair. Different file types need
  an edit to `load_fixtures()`.
- Judge retries once on parse failure; no further attempts. Persistent judge
  non-compliance shows up as `points=0` with `parsed=None`.
- Rate-limit detection is string-match; new limit messages from future CLI versions
  may need the `RATE_LIMIT_MARKERS` tuple extended.

## A/B a reviewer model

The reviewer model is overridable per-role (`--reviewer-model`), and the `changelog.md`
row records `model=<reviewer_model>` so two rows diff cleanly without relying on the
`--note` text. To prove parity (e.g. before downgrading a sub-agent from Opus to Sonnet):

```bash
cd .claude/pipeline-state/plan-reviewer-eval         # or review-lead-eval
./run.sh "opus-baseline"                             # A run (default model)
REVIEWER_MODEL=claude-sonnet-4-6 ./run.sh "sonnet-ab"  # B run
```

Then compare the two `model=...` rows in `changelog.md` — same fixtures and run count,
different reviewer model. The wrappers expose `REVIEWER_MODEL` (env) as the first-class
A/B knob; the binding parity decision rule (which dimensions, acceptable delta, run count)
is set by whoever consumes the evidence, not by the harness.

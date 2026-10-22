# code-review-bench eval

Scores a code reviewer the way the field is scored. A vendored set of 50 public PRs from the
[Martian Code Review Bench](https://github.com/withmartian/code-review-benchmark) (`data/`), each
with a list of known bugs; the reviewer reviews a blind, offline checkout and writes the comments
it would post; a judge on the other model family matches each comment to the known bugs with the
benchmark's own prompt; the arm is scored as precision/recall/F1 and High/Critical recall and the
row is appended to `changelog.md`.

## Operator-run and model-billed. Never in CI.

CI in this repo is model-free by design. This runner spawns `claude -p` sessions on the operator's
subscription; there is no API key and no CI lane, and none should be added.

## Invocation

```
REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> ./run.sh --arm plain --smoke
REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> ./run.sh --arm plain --arm review-lead-lane --set dev --runs 2 --note "why"
REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> ./run.sh --calibration-only --set dev
```

Both variables are required. Each may be a version-pinned id or one of the CLI's aliases; the row
records the id the CLI resolved, never the alias. The judge must be the other model family from the
reviewer: the harness reads the family from the resolved ids and refuses otherwise
(`--allow-same-family` overrides, and the row then says so in `judge=`).

`--reviewer` is an alias of `--arm`. `--smoke` runs one PR once and records nothing. `--no-record`
prints the row without appending it. `--rescore <results-*.json>` re-runs the blindness scan on a
prior run's transcripts and re-judges its stored candidates without spawning a review, so a fix to
the scan or the judge never costs the reviews again; the row's `src=` is what that run measured.

## The two sets

`data/prs.tsv` marks each PR `dev` or `heldout`. The 10 `dev` PRs are for tuning a prompt and for
the cheap before/after check a PR to review-lead runs. The 40 `heldout` PRs are for a claim about a
reviewer, and no prompt is ever tuned on them. Compare rows only within one set.

## The calibration gate

Before any arm is reported the judge re-scores one published tool's comments
(`data/calibration/`) and compares its golden-by-golden matches with that tool's published
verdicts. Below 90% agreement the run prints the disagreements and exits without a row, so a judge
drift is never read as a reviewer change. The agreement is on every row as `calib=`.

## Blindness

Every reviewer session runs with `WebFetch`/`WebSearch` disallowed and an allowlist with no `gh`.
After the run the harness scans the session transcript (and its subagents') for `gh`, `git fetch`,
`git pull`, `curl`, `wget`, web tools and this eval's data directory; one hit voids that run, which
the row counts under `voided=`. A run that modifies the checkout is voided and the checkout reset.

## Arms

One file per arm under `arms/`: a short header, `---`, then the prompt. Header keys: `spawn`
(`claude`), `allow` (the `--allowedTools` list), `bgwait` (set when the arm runs a Workflow, so
`-p` waits for it), `plugin-dir` (a path relative to this directory, passed as `--plugin-dir`, so
the arm runs **this checkout's** plugin rather than the installed copy; the row then says
`src=checkout`), `requires-plugin`, `upstream`. The two review-lead arms carry `plugin-dir`, which
is what lets a PR to review-lead measure itself before merge. The prompt may use `{rules}` (the shared
blindness and output contract in `rules.md`), `{checkout}`, `{base}`, `{head}`, `{scratch}` and
`{out}`. The arm writes its comments to `{out}` as a numbered list; every item is scored.

Shipped arms: `plain` (a one-paragraph senior-engineer prompt), `review-lead-standalone` (the
skill with its full routing), `review-lead-lane` (the skill invoked the way the pipeline's
review session invokes it; routing is the same on both paths now, and the arm is kept so the lane's
own invocation shape stays measured), `tob-differential-review` (Trail of Bits' skill; needs
`differential-review@trailofbits` enabled, and the harness cannot verify the installed version
against the commit the arm file names).

## Quota and seats

A reviewer session bills the Claude seat the checkout's git remote resolves to (the benchmark
forks are public repos, so the catch-all seat). A full 10-PR arm is roughly 45 session-minutes of
reviewer time — the `plain` arm's smoke on a 22-file PR took 21 turns, 191 s and about $2.50 by the
CLI's own accounting; a `review-lead` arm's run is $6–6.50 and 5–13 minutes per PR (the panel's
seats and the lead pass each bill), so one review-lead arm on the dev set is about $60–65 and the
two together about $125 — plus the judge's calls: one short call per (known bug, comment) pair, cached
under the cache dir so a re-judge is free. `--concurrency` (default 3) bounds parallel reviewer sessions;
a session limit mid-run shows up as `voided` runs with the limit message in `results-*.json`.
Smoke first.

## Where things land

- `changelog.md`: append-only rows. Pre-harness rows carry a `note` saying how they were produced.
- `results-<timestamp>.json` (gitignored): every run's candidates, judge decisions, blindness
  scan, resolved models, cost.
- `${XDG_CACHE_HOME:-~/.cache}/second-shift/code-review-bench/`: clones, worktrees, the judge
  cache and the per-run scratch dirs. Outside the repo on purpose: anything under `evals/` is
  scanned by `scripts/check-eval-model-identity.sh`, and any `*-selftest.sh` under it would run in
  CI.

## Refreshing the data

`data/UPSTREAM` names the upstream commit. A refresh is a PR: re-vendor `golden/`, the judge
prompt and one tool's `calibration/` file from the new commit, regenerate `prs.tsv` (base and head
from each fork's PR), run `check-data.sh`, and grep the data for model pins. Rows written before a
refresh are not comparable to rows written after it; say so in the note.

## Adding an arm

Write `arms/<name>.md`, smoke it, then run the `dev` set. A new arm's first row is its baseline.
Never tune on `heldout`.

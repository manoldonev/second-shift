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
REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> ./run.sh --arm plain --arm lane-review --set dev --runs 2 --note "why"
REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> ./run.sh --calibration-only --set dev
```

Both variables are required. Each may be a version-pinned id or one of the CLI's aliases; the row
records the id the CLI resolved, never the alias. The judge must be the other model family from the
reviewer: the harness reads the family from the resolved ids and refuses otherwise
(`--allow-same-family` overrides, and the row then says so in `judge=`).

`--reviewer` is an alias of `--arm`. `--smoke` runs one PR once and records nothing. `--no-record`
prints the row without appending it.

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
is what lets a PR to review-lead measure itself before merge; `--installed` ignores it for the whole
run, so the same arm measures the installed plugin — the before side of that comparison. The prompt may use `{rules}` (the shared
blindness and output contract in `rules.md`), `{checkout}`, `{base}`, `{head}`, `{scratch}` and
`{out}`. The arm writes its comments to `{out}` as a numbered list; every item is scored.

Shipped arms: `plain` (a one-paragraph senior-engineer prompt), `lane-review` (the lane's review
session as it runs: one session, no reviewer dispatched; its correctness instruction is a
`LOCKSTEP-BEGIN review-correctness` block that `scripts/check-lockstep-pairs.sh` holds to
`review_prompt()` in `run.sh`. The bench has no ticket or record, so it measures the correctness half
only), `review-lead-standalone` (the skill with its full routing), `review-lead-lane` (the skill with
the pipeline default panel declared, as the lane ran it before `lane-review`),
`tob-differential-review` (Trail of Bits' skill; needs `differential-review@trailofbits` enabled,
and the harness cannot verify the installed version against the commit the arm file names).

`bench-arms-selftest.sh` loads every arm through `bench.py`'s own `parse_arm` and `str.format`, so
a literal `{` or `}` in an arm fails in CI and not after a run's checkouts are built. Write a literal
brace as `{{` or `}}`.

## Quota and seats

A reviewer session bills the Claude seat the checkout's git remote resolves to (the benchmark
forks are public repos, so the catch-all seat). A full 10-PR arm is roughly 45 session-minutes of
reviewer time — the `plain` arm's smoke on a 22-file PR took 21 turns, 191 s and about $2.50 by the
CLI's own accounting; a `review-lead` arm's run is $6–6.50 and 5–13 minutes per PR on a Fable lead,
about $60–65 per arm on the dev set — plus the judge's calls: one short call per (known bug, comment)
pair, cached under the cache dir so a re-judge is free. `--concurrency` (default 3) bounds parallel
reviewer sessions. A session limit aborts the run; each arm's reviews are written to
`results-*.json` before judging, so `--rescore <results-*.json>` judges them later without paying
for the reviews again. A judge call with no verdict is never cached and makes the run unscorable.
Smoke first.

**Measure on the model production runs.** The lane's review session runs on Opus
(`REVIEW_MODEL_DEFAULT` in `run.sh`) and an ad hoc `review-lead` runs on the session's model; the
specialist seats run at their own tiers either way. A row on a more expensive lead model answers a
question nobody pays for. Use `REVIEWER_MODEL=opus` with a Sonnet or Fable judge for a decision row.

## Where things land

- `changelog.md`: append-only rows. Pre-harness rows carry a `note` saying how they were produced.
- `results-<timestamp>.json` (gitignored): every run's candidates, judge decisions, blindness
  scan, resolved models, cost.
- `${XDG_CACHE_HOME:-~/.cache}/second-shift/code-review-bench/`: clones, worktrees, the judge
  cache and the per-run scratch dirs. Outside the repo on purpose: anything under `evals/` is
  scanned by `scripts/check-eval-model-identity.sh`, and any `*-selftest.sh` under it runs in CI.

## Refreshing the data

`data/UPSTREAM` names the upstream commit. A refresh is a PR: re-vendor `golden/`, the judge
prompt and one tool's `calibration/` file from the new commit, regenerate `prs.tsv` (base and head
from each fork's PR), run `check-data.sh`, and grep the data for model pins. Rows written before a
refresh are not comparable to rows written after it; say so in the note.

## Adding an arm

Write `arms/<name>.md`, smoke it, then run the `dev` set. A new arm's first row is its baseline.
Never tune on `heldout`.

## The planted mode

`planted/` asks a different question: does the lane's review catch what a plain review with the
ticket misses? Its cases are planted defects on real Multi-SWE-bench fixes, each with a ticket, a
decision record and repo context. What it measures, the scoring and the gate are in
`docs/testing.md`, under "The planted mode". It reuses this bench's judge, judge cache,
calibration gate and transcript scan, and writes its own rows to `planted/changelog.md`.

```
python3 planted/planted.py check                                  # the corpus's structure, as CI runs it
python3 planted/planted.py verify --dest <dir>                    # build and render every case, no model
REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> planted/run.sh --arm plain --arm lane --runs 3 --note "why"
REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> planted/run.sh --arm lane --case <id> --runs 1 --no-record
```

A case is `planted/cases/<id>/`: `case.json` (the upstream, its license, the base sha, the issue and
PR numbers, the commit subject and the ground truth), `ticket.md`, `record.md` and `patch.diff`.
A ground-truth location is a range `{file, start, end, side}` or a path-level `{file, side}`, and
at least one range falls inside a hunk of the patch.
The patch applies to the base after the overlay, and adds the plan at
`docs/plans/<repo>-<issue>-plan.md`. Its ids are six random characters, because the reviewer sees
the id in its scratch path and session name. Each overlay under `planted/overlays/` is shared by
the cases of one upstream. `NOTICE` names each upstream and its license.

`planted/run.sh --arm blind-prove` runs alone and spends three sessions on each case-run. Hunt
reads the neutral `after` checkout that `planted.py probe` builds, with no ticket, and ends its
answer with a fenced `candidates` block. Prove reads hunt's whole answer and ends with a fenced
`probes` block of bash commands; it can try each one through a `probe` command bound to its
case-run. The harness then runs at most 8 of those commands, 120 s per side, in the `before` and
`after` checkouts built once for the case-run. Intent reads plain's checkout, the ticket, the
record, both answers and the probe results, and writes a verdict in plain's form, which plain's
scoring reads unchanged. `HUNT_MODEL`, `PROVE_MODEL` and `INTENT_MODEL` (or `--hunt-model` and the
rest) name the stages' models; prove must be on another family from hunt. `--max-cost` caps the
summed cost of one case-run, `$3` by default. A failed stage, a read outside its blindness scope
or a cost over the cap stops the case-run, and its status names the stage. Hunt and prove may not
open the corpus, plain's checkout or the run's state dir; intent may not open the corpus.

A case configures no test runner, so the lane's fails-without-the-change gate is not-applicable on
every case; a runner added to an overlay's config makes the recipe run it on the record commit's
tree, as the lane does. The checkouts, the clones and the per-run state live under the cache dir,
never in the repo. Each review session's stdout and stderr are in `state/session.stdout` and
`state/session.stderr` beside its checkout.

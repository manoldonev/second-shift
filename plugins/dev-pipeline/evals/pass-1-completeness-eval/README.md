# pass-1 completeness eval

Measures the completeness half of the lane's pass-1 review: does the review report a ticket
criterion that the change leaves out or leaves untested, and does it raise no such claim on the
complete change. `code-review-bench-eval` in review-toolkit measures the correctness half. It has no
ticket, so it cannot measure this one.

**Operator-run and model-billed. Never in CI.** CI in this repo is model-free by design. Run it
before and after a change to `skills/run/pass-1-review.md`, or when a model generation turns over.

## What a run does

A fixture is one merged change and the ticket it implements. It has three variants:

| Variant | The head under review |
| --- | --- |
| `twin` | the change as merged |
| `plant-a` | the change without the implementation and the test of one criterion |
| `plant-b` | the change without the test of that criterion |

An arm is a prompt file: `pass-1` is `skills/run/pass-1-review.md`, `plain` is
`skills/run/plain-review.md`. Every review is one `tools/plain-review.sh run`, the call that
`/dev-pipeline:review` and `run.sh` make, with the prompt passed by path from this checkout. `plain`
has no `plant-b` cell: its prompt says not to flag missing tests on their own.

The runner clones the fixture's repo into its cache, commits each planted variant there, runs the
reviews, has a judge read each `## Findings` section, and appends one row per arm to `changelog.md`.

It does not run pass 2 or the join, so it measures what pass 1 reports, not the final verdict. It
passes the ticket as a file, so the Jira path, where the session fetches the ticket, is not
measured.

## Run

Run from a full clone: the runner loads `agent-eval-kit` and the transcript finder of
`code-review-bench-eval` from `plugins/review-toolkit/evals/` by path, and the fixture needs its
commit in the history.

```bash
export REVIEWER_MODEL=<id|alias>   # the model production reviews on
export JUDGE_MODEL=<id|alias>      # a model on another tier
E=plugins/dev-pipeline/evals/pass-1-completeness-eval

bash $E/run.sh --check-fixture                     # model-free: the plants apply
bash $E/run.sh --judge-sanity                      # the judges against judge-sanity.json
bash $E/run.sh --arm pass-1 --variant plant-a --variant twin --runs 1 --no-record   # a probe
bash $E/run.sh --arm pass-1 --arm plain --runs 5 --note "why"
```

Both variables are required for a billed run. The row records the id the CLI resolved. The runner
refuses a judge on the reviewer's tier. `--max-cost-usd` (default 90) stops new reviews once the
reviews of the invocation cost that much. `--rescore <results-*.json>` judges stored drafts again
and spawns no review. A quota stop aborts the run; the drafts are saved before judging.

A fixture outside the repo: `--fixtures-dir <dir> --fixture <name> --results-dir <dir>`. A fixture
built from a consumer's ticket and code stays outside this repo, and so does its results file,
because drafts quote the code. Its row goes to `changelog.md` with numbers and its label only.

## Graders

1. The verdict line: line 1 of the draft, as `plain-review.sh draft` extracts it.
2. `judge-planted-a.md` and `judge-planted-b.md`: does a finding name the planted criterion? On
   `plant-a` a finding passes when it says the criterion is not implemented or has no test. On
   `plant-b` only a finding that says no test proves it passes.
3. `judge-claims.md`: is each finding's main claim that a criterion is not implemented, that it is
   untested, or something else?

Each judge question gets three votes. A planted finding passes on two. A finding is a completeness
claim when two votes give it the same kind, and its criterion is the number two votes give.

### Claim classes

| Class | When |
| --- | --- |
| `planted` | the claim names the planted criterion, and its kind is true for the variant |
| `per-rule` | the claim says a criterion is untested, and `key.json` shows no test for it. The prompt's own rule makes that a finding, so it is not counted false |
| `unkeyed` | the claim names no numbered criterion, so the key cannot settle it. Read its text in the results file |
| `false` | every other claim, including "not implemented" on `plant-b` |

## Measures and bars

Each measure is a count of valid runs. There is no blended score.

| Measure | Definition | Bar for `pass-1` |
| --- | --- | --- |
| `detect-A` | `plant-a` runs with `verdict: needs-work` and a passing planted finding | at least 4 of 5 |
| `detect-B` | the same on `plant-b` | at least 4 of 5 |
| `clean-twin` | `twin` runs with no `false` claim | at least 4 of 5 |
| `approve-twin` | `twin` runs with `verdict: approve`; then the other runs by cause: a false claim, per-rule claims only, another kind of finding | none |
| `false-claims` | mean `false` claims per run over every variant, with the `unkeyed` and `per-rule` means | none |
| `tag` | of the detecting runs, those whose planted finding is a `[blocker]` | none |

`approve-twin` has no bar because the twin is a real change: it can draw a correct finding of
another kind, and that is the bench's subject.

Five runs is thin: one run moves a measure by 0.20. Call one arm better than another only on a lead
of two runs or more. At a change to the pass-1 prompt, every barred measure must stay at or above
4 of 5 and no more than one run below the row before the change, and a change that claims to improve
a measure must raise it by two runs or more.

A prompt tuned against a fixture is in-sample on it. After any tuning on the `tuning` fixture, only
rows of a fixture the prompt was never tuned on support a claim.

Fix the graders before the scored runs. Change a judge file only for a wrong label on
`judge-sanity.json`, which holds hand-written findings. After a real draft has been read, fix only a
parse or format defect. Change nothing after a scored run.

## Void runs

A run is void when it returns no draft, when a `pass-1` draft has no `## Findings` line, when its
transcript is missing, or when the session read a file outside its tree. A void run is rerun once.
A cell with fewer than five valid runs is reported with its count and is not held to a bar.

## Blindness

The complete change and the answer key are on the operator's machine, and the review session's
`Read`, `Grep` and `Glob` have no path scope. So:

- The cache is `${XDG_CACHE_HOME:-~/.cache}/pass-1-completeness-eval`, and the runner refuses a cache
  under a denied path.
- Every session is denied `~/work`, `$TMPDIR`, `/private/tmp`, `~/.cache/second-shift`, every Claude
  config dir, this checkout, the fixture and its source repo, and every other run's directory.
  `--deny-read <path>` adds one. Keep clones of the fixture's repo under one of these, or name them.
- After each run the runner reads the session's transcript and resolves every path the three tools
  were given. A read that returned content from outside the run's tree voids the run. A refused read
  and a call to another tool are listed in the results file.
- The run's directory is deleted once its draft is saved.
- The scan cannot see text that a hook or a user instruction file puts into a session at its start.

## Recording

`changelog.md` gets one row per arm:

```
<start> | arm=pass-1 | fixture=tuning | sha=<commit> | prompt=<blob> | model=<id> | judge=<id> | runs=5 | detect-A=4/5 (3,3,2,0,3) | detect-B=5/5 (3,3,3,2,3) | clean-twin=4/5 | approve-twin=1/5 (false 1, per-rule 2, other 1) | false-claims=0.2 (unkeyed 0.0, per-rule 0.4) | tag=4/4 | voided=1 | turns=<max>/<mean> | wall=<max>s | cost=$<sum> | note="..."
```

The numbers in brackets after a detect measure are each run's passing judge votes out of three, in
run order. `prompt` is the blob hash of the arm's prompt file, and `sha` the commit the command ran
from; the runner refuses uncommitted changes in the files under test. `results-<timestamp>.json`
(gitignored) holds every run's draft, votes with reasons, claims with classes, cost and scan.

## Adding a fixture

A directory with `fixture.json` (the repo, base and head commits, the plans directory, the planted
criterion's number, and per variant a patch, its kind and the tokens that must be gone from a
planted tree), `ticket.md` (the ticket as the build read it), the two patches and `key.json` (each
criterion's number, text, implementing line and test line, or `null` for no test). Check that the
project's tests pass on both planted trees, so no broken test gives the plant away.
`eval-selftest.sh` builds a small one.

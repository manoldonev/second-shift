# The consumer-shaped eval

CI here is model-free by design, so nothing it runs can answer the question a release
actually turns on: **is the kit better or worse to use than it was last release?** This
document is the protocol for the one measurement CI structurally cannot make — replay a
fixed corpus of five tickets through the lean lane **in a consumer repo, with the kit
installed rather than in tree**, and record what it cost.

The output is four numbers per fixture ticket and the maintainer's judgment over them. There
is no script, no selftest and no CI job: automating the arithmetic would grow the instrument
this measurement exists to shrink. Only the result's *presence* is checkable.

Measuring in a consumer repo rather than here is the whole point. This repository is the
canary — the kit runs from the working tree, against its own conventions, on tickets written
by the person who wrote the kit. A consumer runs an *installed* release against its own
stack. A figure taken here would move with the canary; a figure taken there moves with the
release.

## The corpus obligation

**Five fixture specs, fixed in role, replayed every release.** `F-1` through `F-5` bind to
the five roles below **in that order**, so a slot is comparable against itself across
releases rather than only in aggregate:

| slot | what it must exercise |
| --- | --- |
| `F-1` | a single-round pass — the lane's happy path, end to end |
| `F-2` | a seeded ambiguity that *should* cost a pause-and-ask |
| `F-3` | a bug carrying a reproduction |
| `F-4` | a multi-file change that exercises review depth |
| `F-5` | one touching the consumer's stack edges |

**The five spec bodies live in the consumer repo, never here.** They sit alongside that
repo's own config so they can name its actual stack and be genuinely runnable. This
repository carries the protocol and never the specs. "Fixture ticket", "fixture" and "spec"
name that one thing from different angles.

**Each release files fresh fixture issues** rather than reusing the prior release's. Reuse
would reuse the per-issue lane state — the progress record, the launch ledger, the run-id
record are all keyed on the issue number and none is deleted. `retro-corpus.sh timing`
computes wall-clock as `milestone-4 | satisfied` minus the record's **first** timestamped
row, so a reused issue would silently report release-to-release elapsed time instead of run
time, and the number would still look like a run.

**The five replays run sequentially, one lane at a time.** Wall-clock is a compared metric
and concurrent lanes on one machine contend for it — CPU, the selftest sweep, the tracker
rate limit. A lane also assumes it is the only run on the machine (#525). Five concurrent
replays would produce five figures that measure the contention, not the kit.

## The pinned-base recipe

Every replay starts from an identical tree. Nothing in the lane changes and nothing in this
repository changes; the base is moved by config alone.

1. In the consumer repo, cut an eval base branch from the **pinned commit** — the same commit
   every release cuts from.
2. Write an alternate config that differs from the consumer's committed config in **exactly
   one field**: `topology.repos.<host>.baseBranch`, naming that eval base branch. Every other
   field is identical. A second difference makes the series measure the config delta.
3. Select it with `SECOND_SHIFT_CONFIG`, which both the scheduler and the gate already honor
   (`orchestrate-lean.sh:357`, `lean-gate.sh:489`); `baseBranch` is read from the resolved
   config (`lean-gate.sh:529`).
4. File the five fixture issues, intake them, and launch the five lanes one at a time.
5. Their PRs target, and merge into, the **eval base branch**. The consumer's default branch
   is **neither modified nor rewound** — at no point does the eval write to it.
6. Read the four figures per ticket, record them (below), and decide.
7. Delete the eval base branch. The next release cuts a fresh one from the same pinned
   commit.

**Every eval launch passes the build model, the review model and the round cap explicitly**,
never by default, and all three are recorded on the row. A defaulted parameter is a parameter
that can change under the series without the series showing it — the shipped review-model
default in particular is a constant a release is free to move.

```bash
SECOND_SHIFT_CONFIG=<eval-config> orchestrate-lean.sh <issue> \
  --build-model <m> --review-model <m> --max-rounds <n>
```

There is no continuation cap to pass: `--max-continuations` was removed in #718 along with
the continuation budget it bounded, and passing it is a hard refusal.

**The pinned base is not re-pinned by default.** A re-pin makes figures either side of it
incomparable, so it starts a **new series segment** and is disclosed as such in the table.
The prior segment stays readable; it just does not extend.

## The four metrics

Each has one exact source. Nothing here is estimated, and nothing is inferred from a figure
of a different shape. `<stateDir>` below is the consumer config's `paths.pipelineStateDir`
(default `.claude/pipeline-state`) and `<plansDir>` its `paths.plansDir` (default
`docs/plans`) — both read from the alternate config, so they resolve in the consumer repo.

| metric | exact source |
| --- | --- |
| `launchToMerged` | the `launch` row of the **last launch group that spawned anything** at or before the merge, in that ticket's `<stateDir>/<issue>-lean-launches.tsv` → the PR's `mergedAt` from `gh pr view <pr> --json mergedAt`. Computed by hand. |
| `laneWallMin` | `retro-corpus.sh timing --state-dir <stateDir>` — the `wallClockMin` field, which is the record's first timestamped row → `milestone-4 \| satisfied`. |
| `rounds` | the committed verdict record's `rounds:` header key, at `<plansDir>/<key>-lean-verdict.md` (`<key>` is `<repo-slug>-<issue>`, the repo slug being the `topology.repos` key whose `path` is `.`). |
| `usd` | once the cost-per-merged-PR ticket lands, whatever mechanism it establishes. **Until then the cell reads `unavailable`** — never a figure inferred from a price table, never an estimate. |

**Which `launch` row starts the clock.** A ticket routinely carries more than one launch
group — the ledger's rows group by the launch-id column (2), one `launch` row each — and the
start is the group of **the run that produced the merged PR**, not the first group in the
file.

Two shapes are not that run:

- **A group that spawned nothing.** A launch onto an unintaken ticket writes a `launch` row
  and a `terminal` row whose slug begins `preflight-rejected`, and no `spawn` row at all.
  Counting it would charge the run for the time between the operator noticing and
  re-launching. This is the only shape that can spawn nothing, so "discard a group with no
  `spawn` row" and "discard a rejected preflight" are the same discard.
- **A group that spawned and then stranded** — a killed session, a machine that slept —
  writing no `terminal` row of any class. Its commits may survive on the branch, but a later
  group is what carried the ticket to merge, and the wall between the stranded launch and
  that merge is mostly the gap before someone re-launched. When a later spawning group
  exists, the stranded one is not the start. When it is itself the last group before the
  merge, it *did* produce the PR and it *is* the start — a terminal-less group is not
  discarded for being terminal-less.

Mechanically: keep the groups that spawned, and take the last one whose `launch` timestamp is
at or before `mergedAt`. The `mergedAt` bound is what stops a launch made *after* the merge
from taking the slot.

```bash
merged=$(gh pr view <pr> --json mergedAt --jq .mergedAt)
awk -F'\t' -v merged="$merged" '
  $4=="spawn" { spawned[$2]=1 }
  { rows[NR]=$0 }
  END { for (i=NR; i>=1; i--) { split(rows[i], f, "\t")
          if (f[4]=="launch" && (f[2] in spawned) && f[1] <= merged) { print f[1]; exit } } }' \
  "<stateDir>/<issue>-lean-launches.tsv"
```

**What this figure therefore excludes.** Lane work done inside a discarded group is not in
`launchToMerged`: the metric is the merged run's wall, not the ticket's total elapsed time.
When a ticket's merged run was preceded by discarded groups, say so in a note beneath the
table with their count, so the figure is not read as the whole story.

**Why `rounds` does not come from `retro-corpus.sh timing`.** That mode reports a `rounds`
field, but it greps a `round=` token out of the progress record and the current record
grammar no longer writes one — it reads null on every recent run while `wallClockMin` beside
it is populated. The live figure is on the verdict record, which is committed and therefore
survives a worktree teardown. `timing` still owns lane wall-clock.

## When a fixture ticket does not merge

The lane refuses at a gate; the fix budget is spent; a round strands. **The cell records a
null metric set plus the named refusal class**, and the row's `outcome` reads
`did-not-merge:<refusal-class>`.

**Such a run is never re-run and never dropped from the row.** A release where the lane
stopped merging is the most important thing this eval can report, and re-running to green
would erase exactly that. The refusal class *is* the measurement.

## Recording the result

**The result is posted as a comment on the release PR, before that PR merges.** The table
rows land on `main` separately, in their own doc PR against this file.

**Why a comment and not the release PR body or branch.** Every push to `main` re-derives the
release PR wholesale: `release-pr.yml` force-pushes `release/next` (`git push -f origin
release/next`) and PATCHes the PR body from the freshly derived body file (`gh api -X PATCH
repos/…/pulls/<n> -F body=@…`). A result written into either is erased by the next feature
merge. A comment survives both. This placement is therefore load-bearing and must not later
be "simplified" back into the body.

**The verdict is operator judgment.** No stated threshold blocks a release automatically —
the maintainer reads the delta against prior releases and decides whether the release ships.
What is checkable is that the result is *there*.

## Results table

One row per (release, fixture ticket).

| release | ticket | launchToMerged | laneWallMin | rounds | usd | buildModel | reviewModel | roundCap | outcome |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

No release has been evaluated yet — the table has no rows.

A row whose merged run was preceded by discarded launch groups carries a note beneath this
table naming the ticket and their count — see "Which `launch` row starts the clock".

Column contract:

| column | type | notes |
| --- | --- | --- |
| `release` | release tag | the tag this eval gates |
| `ticket` | fixture slot + issue number | `F-1`..`F-5` bind to the five roles in order; the cell also carries that release's issue number, since each release files fresh issues |
| `launchToMerged` | `HH:MM` or null | first non-rejected `launch` row → PR `mergedAt` |
| `laneWallMin` | integer or null | the record's first timestamped row → milestone-4 satisfied |
| `rounds` | integer or null | the verdict record's `rounds:` key |
| `usd` | decimal, or `unavailable` | never inferred, never estimated |
| `buildModel` | model id | passed explicitly, never defaulted |
| `reviewModel` | model id | passed explicitly; the shipped default is a constant a release can change |
| `roundCap` | integer | the launch cap, not the observed round count |
| `outcome` | `merged` \| `did-not-merge:<refusal-class>` | closed enum on the left side |

A re-pin of the eval base opens a new series segment: mark the first row after it, and do not
compare across the boundary.

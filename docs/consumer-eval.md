# Consumer evaluation

Releases do not record a replay. Evaluation is the operator's monthly read of the verdict
records consumer repos commit — what the lane actually did on their tickets, not a fixture
corpus re-run here. What this file keeps is the recipe for the one-off replay a bounded
experiment still needs: a series of lane runs in a consumer repo from an identical tree.

## The pinned-base recipe

Every replay starts from an identical tree. Nothing in the lane changes and nothing in this
repository changes; the base is moved by config alone.

1. In the consumer repo, cut an eval base branch from the **pinned commit** — the same commit
   every replay in the series cuts from.
2. Write an alternate config that differs from the consumer's committed config in **exactly
   one field**: `topology.repos.<host>.baseBranch`, naming that eval base branch. Every other
   field is identical. A second difference makes the series measure the config delta.
3. Select it with `SECOND_SHIFT_CONFIG`, which both the scheduler and the gate already honor
   (`orchestrate.sh:357`, `milestone-gate.sh:489`); `baseBranch` is read from the resolved
   config (`milestone-gate.sh:529`). The gate resolves it *inside* the payload session, and under the
   supervised spawn nothing from the launcher's environment is inherited — so the scheduler
   forwards `SECOND_SHIFT_CONFIG` explicitly in the spawn's `--settings` env block. Pass an
   absolute path: the value travels verbatim, and a relative one would resolve against the lane
   worktree rather than the checkout you launched from.
4. File the replay's issues, intake them, and launch the lanes one at a time — concurrent
   lanes on one machine contend for wall-clock, CPU and the tracker rate limit.
5. Their PRs target, and merge into, the **eval base branch**. The consumer's default branch
   is **neither modified nor rewound** — at no point does the eval write to it.
6. Read and record the figures the experiment was pre-registered to read.
7. Delete the eval base branch. The next replay cuts a fresh one from the same pinned
   commit.

**Every replay launch passes the build model, the review model and the round cap explicitly**,
never by default, and all three are recorded on the row. A defaulted parameter is a parameter
that can change under the series without the series showing it — the shipped review-model
default in particular is a constant a release is free to move.

```bash
SECOND_SHIFT_CONFIG=<eval-config> orchestrate.sh <issue> \
  --build-model <m> --review-model <m> --max-rounds <n>
```

There is no continuation cap to pass: `--max-continuations` was removed in #718 along with
the continuation budget it bounded, and passing it is a hard refusal.

**The pinned base is not re-pinned by default.** A re-pin makes figures either side of it
incomparable, so it starts a **new series segment** and is disclosed as such wherever the series is
recorded. The prior segment stays readable; it just does not extend.

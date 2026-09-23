# Consumer evaluation

Releases do not record a replay. Evaluation is the operator's monthly read of what the lane left
in consumer repos — each run's committed intake record, the review's verdict comment and row table
on the PR, and the run block with its cost — not a fixture corpus re-run here. What this file
keeps is the recipe for the one-off replay a bounded experiment still needs: a series of lane runs
in a consumer repo from an identical tree.

## The pinned-base recipe

Every replay starts from an identical tree. Nothing in the lane changes and nothing in this
repository changes; the consumer's config is not touched either.

1. In the consumer repo, cut an eval base branch from the **pinned commit** — the same commit
   every replay in the series cuts from — and push it.
2. Point the replay checkout's local `origin/HEAD` at it:
   `git remote set-head origin <eval-base>`. The scheduler takes its base from `origin/HEAD`, so
   this is the one input that moves; it is local to that checkout and changes nothing on the
   remote. Restore it with `git remote set-head origin --auto` when the series ends.
3. File the replay's issues, intake them, and launch the lanes one at a time — concurrent
   lanes on one machine contend for wall-clock, CPU and the tracker rate limit.
4. Their PRs merge into the **eval base branch**. The build session opens each PR against the
   repository's default branch, so retarget it before merging
   (`gh pr edit <pr> --base <eval-base>`). The consumer's default branch is **neither modified
   nor rewound** — at no point does the eval write to it.
5. Read and record the figures the experiment was pre-registered to read.
6. Delete the eval base branch. The next replay cuts a fresh one from the same pinned
   commit.

**Every replay launch passes the build model, the review model and the round cap explicitly**,
never by default, and all three are recorded on the row. A defaulted parameter is a parameter
that can change under the series without the series showing it — the shipped review-model
default in particular is a constant a release is free to move.

```bash
/dev-pipeline:run <issue> --build-model <m> --review-model <m> \
  --review-model-basis '<why this model>' --max-rounds <n>
```

(`--review-model-basis` is required whenever `--review-model` departs from the shipped default.)

**The pinned base is not re-pinned by default.** A re-pin makes figures either side of it
incomparable, so it starts a **new series segment** and is disclosed as such wherever the series is
recorded. The prior segment stays readable; it just does not extend.

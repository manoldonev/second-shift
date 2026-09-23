# v2 → v3 — the scheduler replaces the gates

`/dev-pipeline:run` is now one scheduler script: it claims the ticket, commits the intake record
as the branch's first commit, runs fresh build sessions, runs every configured check itself, runs
the route smoke for design tickets, and binds a fresh review session's verdict comment to the
current head. The gates, the committed verdict record, the render receipt and the lane-only tools
are gone, and so are the config keys only they read. `configVersion` is `3`; config-lint rejects a
`2` with a pointer here, and names every removed key it finds.

Part 1 is the config, field by field. Part 2 is what to delete from your repo outside the config.

## Part 1 — config

### `configVersion: 2` → `3`

Bump it once every key below is gone, and point `$schema` at the new release's schema (the ref your
settings pin moves to) — the old schema requires `topology` and `configVersion: 2`, so an editor
validating against it flags the migrated file. `/second-shift:onboard` writes the new shape,
`$schema` included; `/second-shift:doctor` names each stale key.

### `topology` (the whole block) → nothing

Nothing reads it. Delete the block, and move anything you still need to where it now lives:

| Key | Instead |
| --- | --- |
| `topology.type` | Nothing. Each repo is onboarded on its own, with its own config. |
| `topology.repos.<id>.path` | Nothing. Checks and the render run in the ticket's worktree of the repo the config lives in. |
| `topology.repos.<id>.baseBranch` | The remote default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`, falling back to `origin/main`, then `origin/master`). To target a different branch, change the default branch on the code host. |
| `topology.repos.<id>.worktreesDir` | `export RUN_WORKTREE_ROOT=<dir>` when you launch. Default: `<parent of the main checkout>/<repo>-worktrees`. |
| `topology.repos.<id>.ticketTag` | Nothing routes on it. Say which repo the work is for in the ticket. |

`commands` keeps its shape — a map keyed by an id — but the ids are no longer checked against
anything. `/dev-pipeline:run` uses the sole key, else the key equal to the main checkout's
directory name (also when it runs from a linked worktree). A single-repo config keeps working unchanged.
A config with more than one `commands` key (a v2 `be-fe-pair` or `monorepo`) must resolve to this
repo's own entry, the id whose `topology.repos.<id>.path` was `"."`: move every other entry into
its own repo's config so that one is the sole key, or rename it to the main checkout's directory
name. Otherwise no key resolves: the configured checks and setup lanes do not run. A ticket whose
record declares no `## Checks` then goes red as "no check is configured" on every attempt until
`checks-red-spent`, and one that declares checks runs only those.

### `gates` (the whole block) → nothing

`gates.mutation` had no reader. Delete the block. For mutation coverage, add your own mutation
tool as an `extraLanes` check.

### `stageParams` (the whole block)

| Key | Instead |
| --- | --- |
| `stageParams.webComponentGlobs` | **Moves** to `reviewers.webComponentGlobs`, same value. review-lead reads it to route the a11y and design-fidelity reviewers. |
| `stageParams.requiredLabels` | GitHub: `tracker.labels` — `queue`, `claimed`, and `blockers` for the do-not-pick-up set. JIRA: delete the key; nothing replaces it (`tracker.labels` is github-only). |
| `stageParams.planFilePattern` | Nothing. The committed record is always `<paths.plansDir>/<repo>-<key>-decisions.md`. |
| `stageParams.formatGlob` | Nothing read it. The format check is `commands.<id>.format`. |
| `stageParams.inertPattern` | Nothing. Every configured check runs after every build, so there is no inert-diff classifier to override. |

### `grillWaivers` → nothing

config-grill findings are advisory now: `/second-shift:doctor` and `/second-shift:onboard` report
them as `WARN`, never `FAIL`, so there is nothing to waive. Delete the key.

### `design.liveRender.tolerancePx` and `design.liveRender.cwd` → `design.liveRender.smokeCommand`

The pixel-tolerance compare is replaced by the route smoke: after every build, `/dev-pipeline:run`
renders each `## Design frames` row of the ticket record with `command`, then runs `smokeCommand`
(placeholders `{route}` and `{mustShow}`), which must exit non-zero unless the route shows the
row's must-show value — a data-test id or a copy string, one per row. A red smoke spends
one attempt on the checks-red counter (`run.checksRedMax`), never a round; its log goes to the
next build session. A record that declares design frames on a repo without both `command` and
`smokeCommand` stops the run as `env-smoke-unconfigured`.

`cwd` is gone with `topology`: the render runs in the ticket's worktree. In v2 it named the
topology repo that owned the harness, and only that repo's tickets armed the design check. If it
named a repo other than the one whose `path` was `"."`, move the whole `design` block (`provider`
and `liveRender`) into that repo's own config and delete it here; kept here, it arms every ticket
in this repo, and each must then declare design frames or `Design: none — <reason>`. If your
harness lives in a subdirectory of this repo, put the `cd` into the command itself.

### Checks now block

Nothing to change in the config, but know it: every configured check blocks. `lanes[]` setup
steps run first, then `lint`, `typecheck`, `test`, `format`, then every `extraLanes` entry whose
`when` globs match a changed file (or that has none), plus the ticket record's `## Checks`. The
old advisory status of `lint` and `test` is gone. `extraLanes[].failureClass` is still required
but no longer changes behavior. A setup lane's `cwd` is a path under the worktree.

### Before / after

```jsonc
// before (configVersion 2)
{
  "configVersion": 2,
  "tracker": { "type": "github", "branchPrefix": "claude/acme-" },
  "topology": {
    "type": "standalone",
    "repos": { "app": { "path": ".", "baseBranch": "main", "worktreesDir": "../acme-worktrees" } }
  },
  "commands": { "app": { "lint": "yarn lint", "test": "yarn test" } },
  "gates": { "mutation": false },
  "stageParams": {
    "webComponentGlobs": ["src/**/*.vue"],
    "requiredLabels": ["ready-for-dev", "in-progress"]
  },
  "grillWaivers": { "T2.formatGlob": "no formatter" },
  "design": {
    "provider": "figma",
    "liveRender": {
      "command": "yarn render:verify --route {route} --state {state} --out {out}",
      "cwd": "app",
      "tolerancePx": 2
    }
  }
}

// after (configVersion 3) — and `export RUN_WORKTREE_ROOT=../acme-worktrees` if you relied on worktreesDir
{
  "configVersion": 3,
  "tracker": { "type": "github", "branchPrefix": "claude/acme-" },
  "commands": { "app": { "lint": "yarn lint", "test": "yarn test" } },
  "reviewers": { "webComponentGlobs": ["src/**/*.vue"] },
  "design": {
    "provider": "figma",
    "liveRender": {
      "command": "yarn render:verify --route {route} --state {state} --out {out}",
      "smokeCommand": "yarn render:smoke --route {route} --expect {mustShow}"
    }
  }
}
```

## Part 2 — outside the config

- **Delete the merge-boundary CI job.** It checked the committed verdict record, which the lane
  no longer writes, so it would red every PR. Remove `.github/workflows/second-shift-ci.yml`,
  `.claude/tools/second-shift-ci-check.sh`, and any `second-shift-delta-guard.*` you copied (the
  script and its workflow). Also drop `second-shift evidence` from the required status checks in
  branch protection, and any `needs:`/`if:` wiring to `second-shift-delta-guard` in your own
  workflows; otherwise every PR waits on a check that never reports. Nothing replaces them: never
  self-merging stays a human rule, and the review's verdict is a PR comment
  (`verdict: approve|needs-work`, `reviewed: <sha>`).
  `/second-shift:doctor` flags any of these that are still installed, and any `LANE_VERDICT_SUFFIX`
  reference under `.github/` or `.claude/`.
- **`/dev-pipeline:build` is gone.** `/dev-pipeline:run <ticket>` spawns the build sessions
  itself; there is no build skill to invoke by hand. `/dev-pipeline:run`, `/dev-pipeline:review`
  and `/intake-toolkit:plan-interview` keep their names. `/dev-pipeline:pipeline-retro` and
  `/dev-pipeline:perf-retro` are gone too.
- **`LANE_*` environment knobs are retired** and ignored if set (`LANE_ATTEND_MODE`,
  `LANE_GATE`, `LANE_OVERRIDE_TOOL`, `LANE_RUN_MODEL`, `LANE_SPAWN_*` and the rest). What
  survives, all read by `/dev-pipeline:run`:

  | Env | Default | What it sets |
  | --- | --- | --- |
  | `RUN_CLAUDE`, `RUN_GH` (alias `GH`) | `claude`, `gh` | the binaries |
  | `RUN_WORKTREE_ROOT` | `<parent>/<repo>-worktrees` | where worktrees go |
  | `RUN_BUILD_TIMEOUT`, `RUN_REVIEW_TIMEOUT` | 7200, 3600 | session ceilings, seconds |
  | `RUN_COST_CEILING` | 100 | USD, summed from each session's `total_cost_usd` |
  | `RUN_CHECKS_RED_MAX` | 3 | red check or smoke attempts |

  Env beats config `run.*`, which beats the default. The build model comes from the ticket's
  `opus` / `sonnet` label; `--build-model` overrides it.
- **Delete `.claude/lane-overrides.tsv`** if you have one. The operator-override tool is gone: the
  queue label is the only go, and a design ticket that renders nothing says
  `Design: none — <reason>` in its record.
- **Committed records from earlier runs stay.** Verdict records, render receipts and progress
  files under `docs/plans/` are history; nothing reads or rewrites them.

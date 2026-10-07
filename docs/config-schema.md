# Config schema guide (static context)

Machine contract: [`schema/second-shift.config.schema.json`](../schema/second-shift.config.schema.json) (JSON Schema 2020-12), `configVersion: 3`. Enforcement the plugins actually run: [`config-lint.sh`](../plugins/dev-pipeline/tools/config-lint.sh) — shipped **inside the dev-pipeline plugin** (so installed-cache consumers can run it), invoked by `/second-shift:onboard` and `/second-shift:doctor` (the scheduler itself does not re-lint); keep it in lockstep with the schema. Worked examples: [`config-lint-fixtures/valid-*.json`](../plugins/dev-pipeline/tools/config-lint-fixtures/). Upgrading from `configVersion: 2`: [`migrations/v2-to-v3.md`](migrations/v2-to-v3.md).

Required: `configVersion`, `tracker`, `commands`. Everything else is optional.

| Group | What goes here | Who reads it |
| --- | --- | --- |
| `tracker` | `type`: `github` or `jira`; `writes` (default true for github, false otherwise — under `false` the sessions start without Atlassian write tools; on github the scheduler still swaps the claim labels and posts the claim marker and the closing comment); `branchPrefix` (the work branch is `<branchPrefix><key>`, a jira key lowercased); `keyPattern` (a key that does not match is refused); `labels` (github only: `queue`, `claimed`, `blockers` roles); `bot` (a bot identity for the lane's GitHub writes — the claim and closing comment, commits, the review's verdict comment and the run block on the PR; the build session opens the PR itself with plain `gh`) | `/dev-pipeline:run` (`run.sh`); `tools/branch-prefix.sh` for `branchPrefix`; `claim-issue.sh` for the labels; `gh-bot.sh` / `bot-commit.sh` for `bot` |
| `commands` | The check truth table, a map keyed by an id. The scheduler uses the sole key, else the key equal to the main checkout's directory name (also from a linked worktree); the ids are not checked against anything. Per id: `lint`, `typecheck`, `test`, `format` (`null` = not available); `lanes` (SETUP-only steps, run first and fail-fast, each `cwd` a path under the worktree); `extraLanes` (additive checks, gated by `when` changed-file globs; `failureClass` is still required but changes nothing); `allowUnverified` (declares a repo with no check at all) | `/dev-pipeline:run` runs every configured check after every build, plus the ticket record's `## Checks`, and every one blocks. Lane commands run with `SECOND_SHIFT_CONFIG` and the other seam vars scrubbed from their environment |
| `reviewers` | Registry deltas (`add`/`remove`); `default` (shipped reviewers added to the pipeline's review panel, which otherwise dispatches scope-completeness only; additive, never subtracts); `webComponentGlobs` (the paths that route `a11y-reviewer` and the design-fidelity dimension; default `apps/web/**/*.{tsx,jsx}`); `tierMap` (retarget an abstract model tier); per-agent `modelOverrides` (`haiku` \| `sonnet` \| `opus` \| `fable`, or a tier name; Fable also ships as the `cross` tier — see [`model-tiering.md`](../plugins/review-toolkit/model-tiering.md)) | review-lead (the review session's panel); `check-model-tiers.sh` and `check-reviewer-references.sh` |
| `paths` | `plansDir` (default `docs/plans`: the committed intake record `<plansDir>/<repo>-<key>-decisions.md`); `pipelineStateDir` (default `.claude/pipeline-state`: run logs and the pre-flight receipt `<key>-ledger.md`); `runtimeData` (opt-in, no default: git pathspecs relative to the repo root where the app writes gitignored runtime data, e.g. `["apps/api/storage"]`. `git worktree remove` deletes ignored files, so when `git status --porcelain --ignored -- <paths>` shows anything, close-out keeps the worktree, prints the paths, and the run still ends `approved`) | `/dev-pipeline:run` |
| `design` | `provider`: `figma` \| `claude-design` — the design-fidelity axis; key absent = off. Optional `liveRender` `{ command, smokeCommand?, readyProbe? }`: after every build the scheduler renders each `## Design frames` row of the record with `command` (`{route}`, `{state}`, `{out}`), then runs `smokeCommand` (`{route}`, `{mustShow}`, optional `{textScale}`), which must fail unless the route shows the row's must-show value; with `{textScale}` it runs at `1` and at `2` and must also fail when any text overflows or is clipped (without it, the run notes `scaled smoke: not configured`). `readyProbe` is curl-checked first. A provider repo's record carries frames rows or `Design: none — <reason>`. See [`live-render.md`](live-render.md) | `/dev-pipeline:run` (the route smoke); the build and review sessions; the design-toolkit skills |
| `run` | Per-ticket caps, every key optional: `maxRounds` (3), `checksRedMax` (3), `buildTimeoutSeconds` (7200), `reviewTimeoutSeconds` (3600), `costCeilingUsd` (100). Env (`RUN_*`) beats config beats the default | `/dev-pipeline:run` |
| *(env only)* `RUN_WATCH_CMD`, `RUN_WATCH_EDITOR` | Per machine, never in the committed config: a way to watch a `--detach` run. `RUN_WATCH_CMD` (unset = off) is a path to an executable the detached run calls once, when its worktree is first ready, as `<cmd> <issue> <repo> <detach-log> <worktree>`, under a 10 s bound; whatever it does is one `watch:` line in the run log and changes no outcome. The bundled `skills/run/herdr-adapter.sh` opens a herdr workspace `<repo>#<issue>` with a tab per launch: the log live with a sidebar state, and the current BUILD/REVIEW session's transcript below it. `RUN_WATCH_EDITOR` (`code` \| `cursor`) makes the adapter open the worktree in that editor too | `/dev-pipeline:run --detach` |

Principles:

- **If two forks differed on a value, it's config.** If they differed on *behavior*, it's a config-selected adapter (`tracker`, or the `design` provider axis).
- **No domain knowledge in config.** Prose-shaped knowledge goes to extension files ([`extension-points.md`](extension-points.md)); config stays enumerable and lintable.
- **A published key has a reader.** [`check-config-shadowing.sh`](../plugins/dev-pipeline/tools/check-config-shadowing.sh) fails when a key's reader stops reading it; a key nothing reads is removed at the next major, and config-lint rejects it by name with the migration pointer.
- `configVersion` bumps only on breaking schema changes; plugins support one version per release. The migration contract and per-version upgrade docs live in [`migrations/`](migrations/README.md); config-lint fails older/newer configs with the pointer, never a bare "invalid".
- **The scheduler's environment knobs are spelled `RUN_*`:** `RUN_CLAUDE`, `RUN_GH` (alias `GH`), `RUN_WORKTREE_ROOT`, `RUN_BUILD_TIMEOUT`, `RUN_REVIEW_TIMEOUT`, `RUN_COST_CEILING`, `RUN_CHECKS_RED_MAX`, `RUN_WATCH_CMD`, `RUN_WATCH_EDITOR`. `run.sh -h` is the table of record.
- **The base branch is `baseBranch`, else the remote default branch** (`origin/HEAD`, falling back to `origin/main`, then `origin/master`). Set `baseBranch` (a bare name on origin, e.g. `"develop"`) when the repo integrates on a branch other than the host default: the lane forks from it, opens its PR against it and reviews against it, and a configured branch that does not resolve on origin refuses the run before the claim (`env-base-unreadable`) — never a silent fall back.

## Per-engineer override

The config is committed, so its values are the team's. One value is personal: the branch
namespace. An engineer who wants their runs on their own prefix puts it in
`.claude/second-shift.config.local.json`, beside the config (with `SECOND_SHIFT_CONFIG` set, the
`.local.json` beside that file), and keeps the file out of git:

```json
{ "tracker": { "branchPrefix": "jdoe/" } }
```

- `/dev-pipeline:run` and `/dev-pipeline:build` use it in place of the committed
  `tracker.branchPrefix`, and the run log names the override and the prefix it replaced.
- It may set `tracker.branchPrefix` and nothing else. A personal file must not change what the
  team's runs check or how they claim, so any other key is refused (`env-config-local`), as are
  an empty prefix, a file that is not a JSON object, and a file that is committed.
- `config-lint.sh` lints it beside the config, so doctor and onboard report the same problems
  before a run hits them.
- A cross-repo setup that finds one repo's branch by name from another (a UI CI looking for the
  backend branch) needs the same override in both repos.

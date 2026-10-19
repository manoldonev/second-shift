# Config schema guide (static context)

Machine contract: [`schema/second-shift.config.schema.json`](../schema/second-shift.config.schema.json) (JSON Schema 2020-12), `configVersion: 3`. Enforcement the plugins actually run: [`config-lint.sh`](../plugins/dev-pipeline/tools/config-lint.sh) — shipped **inside the dev-pipeline plugin** (so installed-cache consumers can run it), invoked by `/second-shift:onboard` and `/second-shift:doctor` (the scheduler itself does not re-lint); keep it in lockstep with the schema. Worked examples: [`config-lint-fixtures/valid-*.json`](../plugins/dev-pipeline/tools/config-lint-fixtures/). Upgrading from `configVersion: 2`: [`migrations/v2-to-v3.md`](migrations/v2-to-v3.md).

Required: `configVersion`, `tracker`, `commands`. Everything else is optional.

| Group | What goes here | Who reads it |
| --- | --- | --- |
| `tracker` | `type`: `github` or `jira`; `writes` (default true for github, false otherwise — under `false` the sessions start without Atlassian write tools; on github the scheduler still swaps the claim labels and posts the claim marker and the closing comment); `branchPrefix` (the work branch is `<branchPrefix><key>`, a jira key lowercased); `keyPattern` (a key that does not match is refused); `labels` (github only: `queue`, `claimed`, `blockers` roles); `bot` (a bot identity for the lane's GitHub writes — the claim and closing comment, commits, the review's verdict comment and the run block on the PR; the build session opens the PR itself with plain `gh`) | `/dev-pipeline:run` (`run.sh`); `tools/branch-prefix.sh` for `branchPrefix`; `claim-issue.sh` for the labels; `gh-bot.sh` / `bot-commit.sh` for `bot` |
| `commands` | The check truth table, a map keyed by an id. The scheduler uses the sole key, else the key equal to the main checkout's directory name (also from a linked worktree); the ids are not checked against anything. Per id: `lint`, `typecheck`, `test`, `format` (`null` = not available); `lanes` (SETUP-only steps, run first and fail-fast, each `cwd` a path under the worktree); `extraLanes` (additive checks, gated by `when` changed-file globs; `failureClass` is still required but changes nothing); `testRunners` (optional: `[{ "when": [<file globs>], "format"?: "exit" \| "cases" \| "vitest-json" \| "jest-json", "command": "…", "timeoutSeconds"?: <n> }]`, how the tagged tests are run on the fails-without-the-change check, below); `testSupport` (optional: `[<file globs>]`, helper files that check brings from the head, never runs); `allowUnverified` (declares a repo with no check at all) | `/dev-pipeline:run` runs every configured check after every build, plus the ticket record's `## Checks`, and every one blocks. Lane commands run with `SECOND_SHIFT_CONFIG` and the other seam vars scrubbed from their environment |
| `reviewers` | Registry deltas (`add`/`remove`); `default` (shipped reviewers added to the pipeline's review panel, which otherwise dispatches scope-completeness only; additive, never subtracts); `webComponentGlobs` (the paths that route `a11y-reviewer` and the design-fidelity dimension; default the repo-wide `**/*.{tsx,jsx,vue,svelte,css,scss,less}`; `[]` declares no web-component surface); `tierMap` (retarget an abstract model tier); per-agent `modelOverrides` (`haiku` \| `sonnet` \| `opus` \| `fable`, or a tier name; Fable also ships as the `cross` tier — see [`model-tiering.md`](../plugins/review-toolkit/model-tiering.md)) | review-lead (the review session's panel); `check-model-tiers.sh` and `check-reviewer-references.sh` |
| `paths` | `plansDir` (default `docs/plans`: the committed intake record `<plansDir>/<repo>-<key>-decisions.md`); `pipelineStateDir` (default `.claude/pipeline-state`: run logs and the pre-flight receipt `<key>-ledger.md`); `runtimeData` (opt-in, no default: git pathspecs relative to the repo root where the app writes gitignored runtime data, e.g. `["apps/api/storage"]`. `git worktree remove` deletes ignored files, so when `git status --porcelain --ignored -- <paths>` shows anything, close-out keeps the worktree, prints the paths, and the run still ends `approved`) | `/dev-pipeline:run` |
| `design` | `provider`: `figma` \| `claude-design` — the design-fidelity axis; key absent = off. Optional `liveRender` `{ command, smokeCommand?, readyProbe? }`: after every build the scheduler renders each `## Design frames` row of the record with `command` (`{route}`, `{state}`, `{out}`), then runs `smokeCommand` (`{route}`, `{mustShow}`, optional `{textScale}`), which must fail unless the route shows the row's must-show value; with `{textScale}` it runs at `1` and at `2` and must also fail when any text overflows or is clipped (without it, the run notes `scaled smoke: not configured`). `readyProbe` is curl-checked first. A provider repo's record carries frames rows or `Design: none — <reason>`. See [`live-render.md`](live-render.md) | `/dev-pipeline:run` (the route smoke); the build and review sessions; the design-toolkit skills |
| `run` | Per-ticket caps, every key optional: `maxRounds` (3), `checksRedMax` (3), `buildTimeoutSeconds` (7200), `reviewTimeoutSeconds` (3600), `laneTimeoutSeconds` (1800, the bound on each setup lane, check and smoke command), `costCeilingUsd` (100). Env (`RUN_*`) beats config beats the default | `/dev-pipeline:run` |
| *(env only)* `RUN_WATCH_CMD`, `RUN_WATCH_EDITOR` | Per machine, never in the committed config: a way to watch a `--detach` run. `RUN_WATCH_CMD` (unset = off) is a path to an executable the detached run calls once, when its worktree is first ready, as `<cmd> <issue> <repo> <detach-log> <worktree>`, under a 10 s bound; whatever it does is one `watch:` line in the run log and changes no outcome. The bundled `skills/run/herdr-adapter.sh` opens a herdr workspace `<repo>#<issue>` with a tab per launch: the log live with a sidebar state, and the current BUILD/REVIEW session's transcript below it. `RUN_WATCH_EDITOR` (`code` \| `cursor`) makes the adapter open the worktree in that editor too | `/dev-pipeline:run --detach` |

Principles:

- **If two forks differed on a value, it's config.** If they differed on *behavior*, it's a config-selected adapter (`tracker`, or the `design` provider axis).
- **No domain knowledge in config.** Prose-shaped knowledge goes to extension files ([`extension-points.md`](extension-points.md)); config stays enumerable and lintable.
- **A published key has a reader.** [`check-config-shadowing.sh`](../plugins/dev-pipeline/tools/check-config-shadowing.sh) fails when a key's reader stops reading it; a key nothing reads is removed at the next major, and config-lint rejects it by name with the migration pointer.
- `configVersion` bumps only on breaking schema changes; plugins support one version per release. The migration contract and per-version upgrade docs live in [`migrations/`](migrations/README.md); config-lint fails older/newer configs with the pointer, never a bare "invalid".
- **The scheduler's environment knobs are spelled `RUN_*`:** `RUN_CLAUDE`, `RUN_GH` (alias `GH`), `RUN_WORKTREE_ROOT`, `RUN_BUILD_TIMEOUT`, `RUN_REVIEW_TIMEOUT`, `RUN_COST_CEILING`, `RUN_CHECKS_RED_MAX`, `RUN_LANE_TIMEOUT`, `RUN_WATCH_CMD`, `RUN_WATCH_EDITOR`. `run.sh -h` is the table of record.
- **The base branch is `baseBranch`, else the remote default branch** (`origin/HEAD`, falling back to `origin/main`, then `origin/master`). Set `baseBranch` (a bare name on origin, e.g. `"develop"`) when the repo integrates on a branch other than the host default: the lane forks from it, opens its PR against it and reviews against it, and a configured branch that does not resolve on origin refuses the run before the claim (`env-base-unreadable`) — never a silent fall back.

## Test runners: the fails-without-the-change check

A record whose `## Test intent` names acceptance criteria has the build tag each one on a test task
of its plan, naming the task's tests in its `(files)` parenthetical. After the checks and the
plan's coverage pass, `/dev-pipeline:run` proves each tagged test depends on the change: it puts the
worktree on the record commit's tree (the base code, none of the build's), applies the head's
tagged test files on top, with the `testSupport` files, and runs them through the first
`testRunners` entry whose `when` glob matches each file. Every named test must fail there; passing
at the head is the configured checks' job. Then it puts the worktree back on the branch.

```json
"commands": {
  "app": {
    "test": "yarn vitest run",
    "testRunners": [
      { "when": ["*.test.ts"], "format": "vitest-json", "timeoutSeconds": 300,
        "command": "yarn vitest run --reporter=json --outputFile={report} --bail=0 {files}" },
      { "when": ["*.spec.ts"], "format": "jest-json",
        "command": "yarn jest --ci --json --outputFile={report} --runTestsByPath --bail=0 {files}" },
      { "when": ["run*-selftest.sh"], "format": "cases", "command": "SELFTEST_CASES={cases} bash {file}" },
      { "when": ["*-selftest.sh"], "command": "bash {file}" }
    ],
    "testSupport": ["plugins/dev-pipeline/skills/run/run-selftest-lib.sh"]
  }
}
```

**The unit is the named test, unless the runner's `format` is `exit`.** A tagged task names a test
as `file::case`; the case is backtick-quoted whenever it holds a space, `>`, `(`, `)`, `,` or `[`:
``(src/a.test.ts::`Importer > dup > rejects (409)`, src/b.test.ts::adds)``. A case without
backticks runs to the next comma, so a space in it makes the task unparseable. A bare file is the
`exit` format's unit.

| `format` | Calls | Placeholders | What judges a test |
| --- | --- | --- | --- |
| `exit` (default) | one per file | `{file}` | the exit code: any non-zero exit counts as failing, and the file is the unit |
| `cases` | one per file | `{file}`, optional `{cases}` | the line `case<TAB><passed\|failed><TAB><id>` the test prints for its case at exit |
| `vitest-json` | one per runner, over all its files | `{files}`, `{report}` | the test's row in the JSON report |
| `jest-json` | one per runner, over all its files | `{files}`, `{report}` | the test's row in the JSON report |

- `{file}` becomes the file's repo-relative path, shell-quoted; `{files}` each file's realpath under
  the worktree, each shell-quoted; `{report}` a path the scheduler owns, deleted before the call and
  copied to the run's state (`fails-without-<attempt>-<leg>-<n>.json`) right after; `{cases}` the
  named cases of the file as one shell-quoted, space-separated word. Each placeholder belongs to
  its formats only. The command runs from the worktree root with the lane scrubs. The globs match
  as `extraLanes`' `when` does: `*` crosses `/`.
- config-lint keeps a report whole: `vitest-json` requires `--reporter=json`,
  `--outputFile={report}` and `--bail=0`; `jest-json` requires `--json`, `--outputFile={report}`,
  `--runTestsByPath` (jest reads positional paths as regexes) and `--bail=0` (a config `bail` cuts
  suites and writes no report). Each flag is written `--flag=value`; a space form, a second
  `--reporter`, or an `--outputFile.<x>` (which a config `outputFile` redirects) is refused.
- For vitest and jest, the case split on ` > ` must equal the row's `ancestorTitles` plus its
  `title`, exactly. An `it.each` title is matched as the runner renders it at the head. For
  `cases`, the case equals the id the test prints; in `run-selftest-lib.sh` the id is a fixture
  block's name, the block's `ok`/`bad` rows fold (any `bad` fails it), and a block with no row
  prints no line. With `{cases}` (this repo passes it as `SELFTEST_CASES={cases}`), an unselected
  block's `run_case` launches nothing and its rows are muted.
- The judge, in order. Per call: a timeout, a missing or unreadable report, or failed rows with exit
  0 is **one** red naming the runner. Per named test: a form its runner cannot judge (a bare file
  under a reporting runner, `file::case` under `exit`) is red; two matching rows are red
  ("ambiguous"); one row must be `failed` — `passed` is red, and `skipped`, `pending` or `todo` is
  red; no row is red ("not collected" when the file is not in the report, "did not run"
  otherwise). Two cases are **pending** instead: a file that reported no rows and failed with a
  message (it does not load), and, on vitest, a skipped row in a file that failed with an empty
  message and no failed row (a `beforeAll` failure; jest reports those rows `failed`). A `cases`
  file that prints no case line at all is red, naming `testSupport`.
- **The head leg.** After the restore, at the head — one call per json runner, one per file for
  `cases` — every pending test, and each selected test of a `{cases}` runner that failed on the
  record commit's tree, must report `passed`; anything else is red. A selected test that passed
  there is already red and is not run again. A pending test that passes is labeled `file-level` in the run
  block.
- `testSupport` (`commands.<id>.testSupport`): globs, matched as `when` is. A file changed since the
  record commit that matches one and exists at the head goes onto the record commit's tree from the
  head, beside the tagged files, and is never run. A matching file the head deleted is left as the
  record commit has it.
- Each call is bounded by `timeoutSeconds` (default 600): one file for `exit` and `cases`, the
  batch for a json format. The command leads its own process group, so the bound reaches every
  process a test starts: past it the group gets TERM, then KILL 10 s later, and its tests are red
  ("did not finish"), never counted as failing — a runner that hangs on every tree would otherwise
  pass every proof. A clean exit kills whatever the group left running, so nothing it backgrounded
  writes on the tree afterwards. Set the bound well above the call's normal runtime; the build is
  told to tag files that finish inside it.
- Under `exit`, any non-zero exit counts as failing — an assertion, a missing import and a setup
  error alike — and one failing case in the file carries every AC tagged on it. A file the runner
  never collects (excluded, outside its `rootDir`, a symlinked path) also exits non-zero, and so
  counts as failing: a reporting format closes that hole.
- A named test that passes there is red, naming its AC and the test: the next build strengthens
  the test on the checks-red counter. A tagged file no entry matches is red too, unless the record
  marks its AC `unchecked — <tier and reason>` (noted, not run). An AC marked `holds — <behavior>`
  (existing behavior) keeps its files off the check: the checks at the head prove it.
- A report is no weaker than the exit code it replaces: a test can print a false line or rewrite
  the report, as it can `exit 1` today. Deliberate forgery is the review's to catch.
- No `testRunners`: the check is not-applicable, a line in the run log and the run block. The key
  is optional and needs no `configVersion` bump. On a repo whose root `package.json` depends on
  vitest or jest (one, not both), the config grill's `T6.testRunners.<id>` finding proposes the
  entry: the `vitest-json` or `jest-json` format, the runner's default test-file pattern as `when`,
  and a command built on `commands.<id>.test` when its script is one plain run of the runner, else
  the runner called through the package manager. `/second-shift:doctor` reports it as a WARN, and
  `/second-shift:onboard` drafts it when the pattern matches a tracked file.
- The runners are read once, at launch, so a build cannot change them mid-run. The record commit's
  own package and runner config is what runs on that tree.
- `/dev-pipeline:build` (the handoff path) does not run it: its review notes the check as not run.

## Per-engineer override

The config is committed, so its values are the team's. Two values may be personal: the branch
namespace, and the bot's GitHub App identity. They go in `.claude/second-shift.config.local.json`,
beside the config, and the file stays out of git:

```json
{ "tracker": { "branchPrefix": "jdoe/" } }
```

- `/dev-pipeline:run` and `/dev-pipeline:build` use its `tracker.branchPrefix` in place of the
  committed one, and the run log names the override and the prefix it replaced. With
  `SECOND_SHIFT_CONFIG` set, the prefix is read from the `.local.json` beside that file.
- It may also carry `tracker.bot.app.{clientId, appName, privateKeyFilename, installationId}`.
  A repo that must not publish its app's ids keeps them here and commits the rest of `tracker.bot`
  (`enabled`, `envVar`, `wrapperPath`). Each local key overrides the same committed key, one key
  at a time. `bot-commit.sh`, the run's launch check and `install-gh-bot.sh` read these keys from
  the **main checkout's** `.local.json`, even with `SECOND_SHIFT_CONFIG` set: a lane worktree and
  a session's scratch copy of the config have no local file beside them.
- When `tracker.bot.enabled` is true and `appName` is in neither file, `/dev-pipeline:run` warns
  at launch that the run's commits will land as the operator, and the run still starts.
- It may set those keys and nothing else. A personal file must not change what the team's runs
  check or how they claim, so any other key is refused (`env-config-local`), as are an empty
  prefix, a file that is not a JSON object, and a file that is committed.
- `config-lint.sh` lints it beside the config, so doctor and onboard report the same problems
  before a run hits them.
- A cross-repo setup that finds one repo's branch by name from another (a UI CI looking for the
  backend branch) needs the same override in both repos.

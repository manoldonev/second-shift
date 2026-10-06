# Onboarding a repo

The [README's Get started](../README.md#get-started) is the first-run path. This page is the
detail behind it: what `/second-shift:onboard` writes and why, the config you may still need to
finish, and the manual path at the end.

## What onboard writes

`/second-shift:onboard` detects what git, `gh` and your package files can prove, asks the rest in
one batch, shows one accept-or-edit screen, and validates the config before anything lands. It
writes:

- `.claude/second-shift.config.json`: tracker, commands and caps. Its first key, `$schema`, points
  at the pinned release, so editors validate it as you type.
- `.claude/settings.json`: the marketplace pinned to a release tag and the plugins enabled
  (merged into your existing settings). This is what puts teammates on the same versions.
- `.claude/second-shift.lock.json`: the plugin versions `/second-shift:doctor` checks against.
- `.claude/tools/second-shift-doctor.sh`, wired as a SessionStart hook: on each session start it
  prints a "you're missing your accelerators" line and the install command if a pinned plugin is
  not installed. It never blocks.
- `.claude/SECOND-SHIFT.md`: what installs and which hooks run, so a teammate reads it before the
  trust prompt.
- On request (GitHub tracker): `.github/workflows/second-shift-unclaim.yml` and
  `.claude/tools/second-shift-unclaim.sh`, which remove the run-state labels when an issue closes
  ([team-rollout.md](team-rollout.md) has the permission it needs).

Commit those five files, plus the two unclaim files if you took them, in one PR, and merge it
before the first run: a run's sessions read the plugin settings from the default branch. Onboard also
prints a CONTRIBUTING snippet to paste; it does not write it.

If the settings write is blocked, the merged document goes to
`.claude/settings.json.second-shift-proposed` with instructions to apply it.

## Finish the command table and give it a setup step

Detection covers JS package managers plus a Makefile fallback. On any other stack (Python, Go,
Rust, bun) onboard does not guess: every command under `commands.<id>` is `null`. Fill in your
repo's real commands. After each build, second-shift runs every configured check itself, and each
one blocks; a round with no check configured anywhere (config or the intake record's `## Checks`)
is red, not green. If verifying nothing is genuinely intended, for example in a docs-only repo, set
`commands.<id>.allowUnverified: true`.

Then add a setup step, on every stack: onboard never writes one, it only shows a commented-out
line on the review screen. Each run works in a fresh `git worktree` with no `node_modules` and no
`.venv`, so checks that need dependencies fail unless an install runs first. That is
`commands.<id>.lanes[]`: steps that run in order before the checks, stopping at the first
failure. A Python service, for example:

```json
{
  "configVersion": 3,
  "tracker": { "type": "github", "branchPrefix": "claude/" },
  "commands": {
    "app": {
      "lint": "poetry run ruff check .",
      "typecheck": "poetry run mypy .",
      "test": "poetry run pytest",
      "format": null,
      "lanes": [{ "name": "install", "commands": ["poetry install"] }]
    }
  }
}
```

The JS equivalent of the setup step is `[{ "name": "install", "commands": ["npm ci"] }]`. A
`null` or absent `format` simply runs no format check. `commands` is keyed by an id you choose;
with several keys the run uses the one equal to the main checkout's directory name. A workspaces
monorepo is still one entry: put the root scripts that cover every package in
`lint`/`typecheck`/`test`, give a per-package setup step its own `cwd` under `lanes`, and scope a
one-package check with an `extraLanes` entry and its `when` globs. Every field is in [`config-schema.md`](config-schema.md).

The run does not lint the config at startup, so after editing it by hand run
`/second-shift:doctor`.

## GitHub: labels and an optional bot

Onboard offers to create the labels. If you skipped that, create them now:

```bash
for l in ready-for-dev in-progress opus sonnet needs-spec-work needs-plan-review needs-intake-review epic; do
  gh label create "$l" || true
done
```

- `ready-for-dev` queues a ticket. You add it; nothing else does for a ticket you filed.
- `in-progress` is the claimed label: the run swaps the queue label for it when it takes a
  ticket.
- `opus` or `sonnet` picks the build model. Add it with the queue label; without one,
  `/dev-pipeline:run` sizes the ticket itself and records that the choice was its own. Only
  tickets that intake splits out of an epic get both labels automatically.
- `epic`, `needs-spec-work`, `needs-plan-review` and `needs-intake-review` block a run.

The queue, claimed and blocker labels can be renamed under `tracker.labels`; `opus` and `sonnet`
are fixed names.

**Optional bot identity.** By default the run's claim, commits and PR are written as your own
`gh` identity. To have a GitHub App write them instead, create an App with issues, contents and
commit statuses write access, then:

1. Put the App's details under `tracker.bot.app`: `clientId` (required; or pass `--client-id`),
   plus `appName` and `privateKeyFilename`, whose defaults are placeholders.
2. Run the dev-pipeline plugin's `tools/install-gh-bot.sh <path-to-private-key>`. Find the plugin
   root with `claude plugin list --json` (`installPath`).
3. Set `tracker.bot.enabled: true`.

Once enabled, a broken bot stops the run (`env-bot`) rather than writing as you.

On JIRA none of this applies: the run reads tickets through the Atlassian MCP, and since there
is no sizing label the build model comes from `--build-model`. See
[the JIRA tracker README](../plugins/dev-pipeline/tools/tracker/jira/README.md).

## Reviewers and `review-context.md`

On a pipeline round the review runs `scope-completeness-reviewer`. `security-reviewer`,
`a11y-reviewer` and `unit-test-mutation-reviewer` join only when opted in: per ticket by a
`review panel` row in the intake record, or per repo in `reviewers.default`. Repo-local agents in
`.claude/agents/` join through `reviewers.add`. Other files the reviewers read when present are
listed in [`extension-points.md`](extension-points.md).

### Your first `review-context.md`

The one extension file worth writing early. Without it, every reviewer guesses your stack and
maturity from the diff and lowers its confidence. With it, reviewers key on the sections you
declare. Write only the sections that are true (all optional), using the exact names from
[extension-points.md → Authoring the review-context surface](extension-points.md#authoring-the-review-context-surface):

```markdown
# Review context — <your repo>

## Stack
Web framework + rendering model, job/queue system, data store(s), service languages.

## Maturity stage
E.g. "pre-auth MVP: no ownership parameter or tenant guards exist yet."
```

Two rules keep it honest: use the catalog's heading names exactly (a near-miss is flagged with
the rename), and never leave a heading with an empty or TODO body, since reviewers would quote it
back as policy. Onboard offers to scaffold this file from your answers.
`check-review-context-sections.sh --report` (review-toolkit `scripts/`) prints which reviewers are
running without context.

## Verify

`/second-shift:doctor` checks the installed plugins against the lockfile, the settings pin, the
config, and extension file names under `.claude/second-shift/`. Every FAIL prints its fix, and the
exit code is the FAIL count. Run it after cloning, after upgrades, and whenever the toolkit seems
missing.

Rolling out to the rest of the team, upgrades and rollback: [`team-rollout.md`](team-rollout.md).

## Reference

### Pair repos (BE/FE) under the pipeline

`/dev-pipeline:run` works on the checkout it is launched from; nothing fans a run out across
repos. A backend/frontend pair is two repos that each onboard on their own: `cd` into each and run
`/second-shift:onboard` there, for two configs and two separate runs. A ticket runs from the repo
that owns it, and cross-repo scope is split at intake into one ticket per repo.

### Building in your own session

`/dev-pipeline:build <ticket>` claims the ticket, cuts the worktree and commits the intake record
like a run, then hands the build to your current session instead of spawning one. The run's own
checks and caps do not apply there; review the PR with `/dev-pipeline:review <pr>` from a fresh
session.

### Manual install

What onboard automates. In the repo's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "second-shift": { "source": { "source": "github", "repo": "manoldonev/second-shift" } }
  },
  "enabledPlugins": {
    "second-shift@second-shift": true,
    "dev-pipeline@second-shift": true,
    "review-toolkit@second-shift": true,
    "intake-toolkit@second-shift": true,
    "audit-toolkit@second-shift": true
  }
}
```

Add `design-toolkit@second-shift` for a repo with a UI ([`live-render.md`](live-render.md) covers
its optional render check). A minimal config:

```json
{
  "configVersion": 3,
  "tracker": { "type": "github", "branchPrefix": "claude/your-repo-" },
  "commands": { "app": { "lint": "yarn lint", "typecheck": "yarn tsc --noEmit", "test": "yarn test" } }
}
```

Set `tracker.branchPrefix`: without it, and with no existing pipeline branches on the remote to
derive one from, every run, the dry run included, stops with `env-branch-prefix`. The base branch
is `baseBranch` when set, else the remote's default branch.

**The supported install is the full suite pinned to a release tag**, which is what onboard writes.
The one documented downgrade is review-only (`enabledPlugins` with just
`review-toolkit@second-shift`), which is not CI-tested. Any other plugin can be turned off with
`enabledPlugins: false`; doctor notes it as a warning.

### Pinning a release

Point the marketplace at a release tag so the catalog cannot drift:

```json
{
  "extraKnownMarketplaces": {
    "second-shift": {
      "source": { "source": "github", "repo": "manoldonev/second-shift", "ref": "v16.0.0" }
    }
  }
}
```

The lockfile carries the same `ref`; an upgrade bumps both in one PR. Recipe:
[team-rollout.md → Upgrades](team-rollout.md#upgrades). Breaking changes carry a migration doc in
[`migrations/`](migrations/README.md).

# Onboarding a repo

Onboarding = enable plugins + write one config file. No file copying. The one extension
file worth writing early is `review-context.md` — see [Your first `review-context.md`](#your-first-review-contextmd).

## 0. Fast path: `/second-shift:onboard`

The marketplace writes its own consumer config. Three commands:

```text
claude plugin marketplace add manoldonev/second-shift
claude plugin install second-shift@second-shift        # user scope
# in the target repo:
/second-shift:onboard
```

`onboard` detects the tracker and commands with provenance (never asking what git or
package.json can answer), presents ONE accept-or-edit screen, and emits:

- `.claude/second-shift.config.json` — with a `$schema` first key at the pinned ref, so editors validate live
- a pinned `.claude/settings.json` block — `extraKnownMarketplaces` at the release ref + the blessed-bundle `enabledPlugins` (merged into your existing settings, never clobbered)
- `.claude/second-shift.lock.json` — the plugin→version contract `/second-shift:doctor` verifies against
- the repo-committed thin check (`.claude/tools/second-shift-doctor.sh` + a SessionStart nudge)
- `.claude/SECOND-SHIFT.md` — the consent doc: what installs, what hooks fire, before the trust prompt
- **(on request, github tracker)** `.github/workflows/second-shift-unclaim.yml` + `.claude/tools/second-shift-unclaim.sh` — the close-out step the lane does not own: when an issue closes it removes the pipeline's two run-state labels (`tracker.labels.claimed` and `tracker.labels.queue`, resolved from your committed config at run time; never `tracker.labels.blockers`, which holds permanent classifications like `epic`). It **writes** — `issues: write`, two labels on one issue, which needs the repo's Actions workflow permissions set to read-and-write (a `permissions:` block narrows the repo maximum, it cannot widen it). The labels go stale when the issue closes, and no lane session is running then — the run ends at an approved PR, long before the merge closes the ticket; binding the release to the close event needs no live session and covers a hand-closed issue too.
- a paste-ready CONTRIBUTING snippet for teammates

The config is validated with the plugin-shipped `config-lint` in-loop before anything lands.
If the live settings write is blocked, the merged document goes to
`.claude/settings.json.second-shift-proposed` with exact apply instructions.

**Verify (any machine, any time): `/second-shift:doctor`.** It checks the installed state
against the committed lockfile and catches all five drift states — never-installed,
enabled-but-not-installed (the default state of a fresh clone whose owner accepted the
trust prompt but not the install prompts), version-behind, version-AHEAD (the rollback
case), and settings-ref↔lockfile-ref drift (a half-done upgrade PR) — plus ref-less
marketplace shadowing, repo-local skill/agent shadow collisions, opt-outs, and config keys or
CI files an earlier major left behind. Every FAIL prints its exact remediation command; the exit
code is the FAIL count.

The SessionStart nudge (`.claude/tools/second-shift-doctor.sh`) is the tiny committed
presence check wired into project settings: on session start it compares the lockfile
against the local plugin cache and prints one friendly "you're missing your accelerators"
line when the toolkit isn't installed — the only channel that reaches someone who skipped
the trust prompt, since project hooks run regardless of plugin install state. It always
exits 0 (it nudges, never blocks). Together with the lockfile it is the sanctioned
exception to no-vendoring: both files verify plugin presence, they are not plugin content.

Rolling this out to a whole team — trust flow, opt-outs, upgrades, rollback, the managed
variant — is its own playbook: [`team-rollout.md`](team-rollout.md).

### Pair repos (BE/FE) under the pipeline

`/dev-pipeline:run` works on the checkout it is launched from; nothing fans a run out across
repos. A backend/frontend pair is two repos that each onboard on their own: `cd` into each and
run `/second-shift:onboard` there — two configs, two bot identities, two lanes. A ticket runs from
the repo that owns it, and cross-repo scope is split at intake into one ticket per repo, each filed
in that repo's own tracker.

Sections 1–2 below are the manual/reference path — what the skill automates.

## 1. Enable the marketplace + plugins

In the repo's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "second-shift": { "source": { "source": "github", "repo": "manoldonev/second-shift" } }
  },
  "enabledPlugins": {
    "dev-pipeline@second-shift": true,
    "review-toolkit@second-shift": true,
    "intake-toolkit@second-shift": true,
    "audit-toolkit@second-shift": true
  }
}
```

**One supported artifact: the full suite, pinned to a release tag** — exactly what
`/second-shift:onboard` writes. `design-toolkit` is the single conditional, offered when the
repo is UI-shaped or a design MCP is connected (accepting it also offers the optional
`design.liveRender` render-command block when a harness is detected — [`live-render.md`](live-render.md)).
**One documented downgrade:** review-only
(`enabledPlugins` with just `review-toolkit@second-shift: true`) — review-toolkit ships its own
reviewer fan-out, so `review-lead` and its commit hooks run without dev-pipeline or
design-toolkit (the design reviewers degrade away). *Community-supported, not CI-tested.* Everything else is possible via `enabledPlugins: false` and yours to own, with **one
exception**: `audit-toolkit` off while `dev-pipeline` is on is not a supported combination.
`audit-toolkit` ships the hook that writes the per-session audit ledger — the record of what the
lane's unattended sessions actually ran — and `/second-shift:doctor` FAILs on the pairing rather
than warning. Disable both together if the repo does not run the lane.

Why so strict: five optional plugins is a 2^5 support matrix, and the seams between plugins
(pipeline → review panel, intake → the record the scheduler reads) break precisely at partial installs. One
blessed bundle keeps every CI-tested path identical to every consumer's path. Pin a release
wherever stability matters; track latest only in a canary. (The canary form: settings +
lockfile `ref: "main"` and every lockfile plugin version set to the literal `"latest"` —
doctor and the SessionStart nudge then check presence only. The marketplace repo itself is
onboarded this way; `/second-shift:onboard` applies it automatically when the target repo
is the marketplace's own checkout.)

### Pinning a release

Two mechanisms compose, and both are needed for a durable pin:

1. **Marketplace ref** — point `extraKnownMarketplaces` at the release tag so the catalog itself can't drift (`ref` accepts a branch or tag; per-plugin `sha` pinning exists only for plugin sources inside `marketplace.json`):

    ```json
    {
      "extraKnownMarketplaces": {
        "second-shift": {
          "source": { "source": "github", "repo": "manoldonev/second-shift", "ref": "v15.0.0" }
        }
      }
    }
    ```

2. **Plugin `version` field** — each plugin's `plugin.json` carries an explicit `version`; the install cache is keyed by it (`~/.claude/plugins/cache/second-shift/<plugin>/<version>/`) and an installed plugin only moves when that string changes. Third-party marketplaces do **not** auto-update, so an installed version stays put until an explicit `/plugin marketplace update` + reinstall.

    ```bash
    claude plugin install dev-pipeline@second-shift --scope project   # records version + git SHA
    ```

Upgrading = a PR that bumps the `ref` in settings **and** `.claude/second-shift.lock.json` together (the maintainer side: [`releasing.md`](releasing.md); verify with `/second-shift:doctor`), then `claude plugin marketplace update second-shift` + reinstall, then the repo's validation gates re-run (config-lint, selftests, a dry-run ticket). Breaking schema changes carry a migration doc in [`migrations/`](migrations/README.md) — config-lint points at it. Breaking changes that are not schema changes (a renamed script your repo vendors, a retired environment knob) are listed there too, and in each release's `CHANGELOG.md` entry; read both before bumping across a major. One caveat: a **user-level** marketplace registration with the same name (typical on the machine that developed the marketplace) is ref-less and takes precedence locally — the project-settings `ref` is what protects everyone else, and `claude plugin list` should confirm the expected version after any update.

## 2. Write the static context

Create `.claude/second-shift.config.json` (the schema: [`schema/second-shift.config.schema.json`](../schema/second-shift.config.schema.json), field-by-field guide: [`config-schema.md`](config-schema.md)). Minimal example:

```json
{
  "configVersion": 3,
  "tracker": { "type": "github" },
  "commands": { "app": { "lint": "yarn lint", "typecheck": "yarn tsc --noEmit", "test": "yarn test" } }
}
```

`commands` is keyed by an id of your choosing. The lane reads the sole key, or — when there are
several — the key equal to the main checkout's directory name. The base branch is `baseBranch` when
set, else the remote's default branch (`origin/HEAD`, falling back to `origin/main`, then `origin/master`).

Nothing here assumes JavaScript. The same shape for a Python service on JIRA
(poetry/pytest; note `"writes": false` — the documented JIRA default — and `format: null`,
which switches the format lane off entirely, no prettier, no node):

```json
{
  "configVersion": 3,
  "tracker": { "type": "jira", "writes": false, "branchPrefix": "acme-dev/" },
  "commands": {
    "app": {
      "lint": "poetry run ruff check .",
      "typecheck": "poetry run mypy .",
      "test": "poetry run pytest",
      "format": null
    }
  }
}
```

Validate it:

```bash
# config-lint ships INSIDE the dev-pipeline plugin (so installed-cache consumers can run it):
# a tier-named modelOverrides value reads review-toolkit's model-tiering.md, found beside it
# in the install cache or named by SECOND_SHIFT_TIER_DOC.
bash "${CLAUDE_PLUGIN_ROOT:-<dev-pipeline-plugin-root>}/tools/config-lint.sh" \
  .claude/second-shift.config.json
```

(`/second-shift:onboard` runs it before writing, and `/second-shift:doctor` runs it again. The
lane itself does not lint at startup, so re-run one of them after hand-editing the config.)

## 2b. Prerequisites the first run enforces (GitHub tracker)

`/second-shift:onboard` walks you through these; if you onboarded manually, the first run of
`/dev-pipeline:run` refuses without them, so handle them now rather than mid-run:

- **The labels.** The scheduler admits a ticket only with the queue label (`ready-for-dev`),
  swaps it for the claimed label (`in-progress`), refuses a ticket carrying a blocker label
  (`epic`, `needs-intake-review`, `needs-spec-work`, `needs-plan-review`), and takes the build
  model from a sizing label (`opus` or `sonnet`) that intake applies. All are overridable under
  `tracker.labels`; create the ones you keep:

  ```bash
  for l in ready-for-dev in-progress opus sonnet needs-spec-work needs-plan-review needs-intake-review epic; do
    gh label create "$l" || true
  done
  ```

- **Optional: a GitHub-App bot identity.** With one, the lane's own writes — the claim, commits,
  the run block on the PR — are authored by the bot rather than your personal identity. You need
  a GitHub App (issues+contents write) and its private key; the dev-pipeline plugin ships the
  bootstrap — resolve the plugin root via `claude plugin list --json` → `installPath`, then run
  its `tools/install-gh-bot.sh` — and set `tracker.bot.enabled: true`. Once enabled, a broken
  wrapper stops the run (`env-bot`) rather than writing as you in the bot's place.

Neither applies to the JIRA tracker (reads via the Atlassian MCP; `writes: false` is the
default posture; pass `--build-model` since there is no sizing label). Both trackers need `gh`,
`jq`, `git` and `claude` — the build opens the PR with `gh pr create` — plus `node` for the review
and intake Workflows.

### Finish the command table — and give it a setup lane

Detection only covers JS package managers plus a Makefile fallback. On any other stack
(Python/pip/poetry/uv, bun, cargo, go) onboard refuses to guess and drafts every
`commands.<id>` lane as `null`. **That table is a starting point, not a finished config** —
fill in your repo's real commands. The scheduler runs every configured check itself after each
build, and every one of them blocks; a round with no check configured anywhere (config or the
record's `## Checks`) is red, not green. If verifying nothing is genuinely intended (a docs-only
repo, say), set `commands.<id>.allowUnverified: true` so the choice is explicit rather than an
oversight.

Then add a **setup lane**. The pipeline works in a `git worktree` — a fresh checkout that
starts with no `node_modules` and no `.venv`, since both are gitignored. Checks that need
installed dependencies fail on the first real run unless the install runs first, and that is
what `commands.<id>.lanes[]` is for (sequential setup steps, run before the checks; the first
failure stops the rest):

```jsonc
"lanes": [{ "name": "install", "commands": ["python3 -m venv .venv", ".venv/bin/pip install -e '.[dev]'"] }]
// JS equivalent: [{ "name": "install", "commands": ["npm ci"] }]
```

Field reference — including `extraLanes` and `allowUnverified` — is in
[`config-schema.md`](config-schema.md).

## 3. Optional: dynamic context

- **Knowledge skills** — ordinary repo-local skills in `.claude/skills/`; discovered natively, no registration.
- **Domain reviewers** — repo-local agents in `.claude/agents/`, registered via config `reviewers.add`.
- **The pipeline's review panel** — `/dev-pipeline:review` dispatches `scope-completeness-reviewer` by default. `security-reviewer`, `a11y-reviewer` and `unit-test-mutation-reviewer` run on a pipeline round only when opted in: per ticket, by a `review panel` row in the ticket's intake record, or per repo, by listing them in `reviewers.default`. Standalone `review-lead` still routes by what the diff touches.
- **Extension files** — documented hook points the generic agents read when present ([`extension-points.md`](extension-points.md)): blocker-mutant lists, domain security rules, design-token references.
- `findings.md`, `CLAUDE.md` — as before; the plugins never require them but respect them.

### Your first `review-context.md`

The single highest-leverage extension file. Without it, every reviewer infers your stack and
maturity from the diff and lowers its confidence; with it, they key on **named sections** you
declare. Write only the sections that are true for your repo (all optional) — the exact names
and their readers are the catalog in [extension-points.md → Authoring the review-context
surface](extension-points.md#authoring-the-review-context-surface). A minimal start:

```markdown
# Review context — <your repo>

## Stack
Web framework + rendering model, job/queue system, data store(s), service languages.

## Maturity stage
E.g. "pre-auth MVP: no ownership parameter or tenant guards exist yet."
```

Two rules the tooling enforces so this file stays honest:

- **Use the exact catalog heading names.** `check-review-context-sections.sh` (review-toolkit
  `scripts/`) matches them exactly (no fuzzy guessing). A drifted spelling (e.g. `## Maturity
  calibration (MVP stage)` instead of `## Maturity stage`) is flagged with the exact rename
  command; an invented heading is fine — list it in `.claude/second-shift/.known-sections` to
  mark it intentional.
- **Never leave a heading with an empty or TODO body.** A present-but-hollow section reads as
  a policy declaration reviewers quote back — worse than an honest absence. The linter and
  every reviewer treat it as absent. Write the section, or omit the heading.

`/second-shift:onboard` offers to scaffold a starter file from your confirmed answers (never
mandatory, never a TODO-bodied stub). Run `check-review-context-sections.sh --report` any time
for a one-line coverage summary of which reviewers are running degraded.

## 4. Verify

Two layers, in order:

1. **Config**: config-lint (above) — green means the static context parses and every value
   is schema-legal.
2. **Install state**: `/second-shift:doctor` — installed plugins vs the lockfile, settings
   pin, shadow collisions, stale keys (see §0), and extension filenames under
   `.claude/second-shift/` against the shipped manifest (a typo'd extension filename is a FAIL,
   never silently ignored).

Then a first run on a small, self-contained ticket. Intake it first: `/intake-toolkit:intake`
puts the ticket's open decisions to you and records them in the intake record
(`.claude/pipeline-state/<ticket>-ledger.md`, written by `/intake-toolkit:plan-interview`); on a
GitHub tracker the ticket also needs the `ready-for-dev` queue label and a sizing label. Without
the record or the queue label the scheduler exits 3 and writes nothing — pay off intake and
re-launch the same command. On JIRA nothing checks the queue, so the discipline is yours.

`/dev-pipeline:run <ticket> --dry-run` is the read-only check once the record exists: it prints
the branch, worktree, record and checks it would use, and writes nothing to the tracker, git or
the remote. The whole sequence:

```text
/intake-toolkit:intake <ticket>
/dev-pipeline:run <ticket>
```

`/dev-pipeline:run` is a scheduler that authors nothing itself. It claims the ticket, commits the
intake record as the branch's first commit, then runs rounds: a fresh build session opens or
updates the PR; the scheduler runs every configured check and the record's `## Checks` (plus the
[route smoke](live-render.md) on a design ticket); a separate, fresh review session scores every
record row against the code and posts one PR comment whose first two lines are
`verdict: approve|needs-work` and `reviewed: <sha>`. The scheduler accepts that verdict only if it
was posted during the review session by a Bot or the account the scheduler writes with, is unedited
and names the current head, so a commit that
lands while the review runs voids that review. An approve ends the run: a later push is the human
merger's to judge, against the sha the approve names. A session grading its own work is not an
independent review, which is why they are two sessions.

It never asks and never guesses: every stop prints `terminal: <slug>` and exits with a code a
wrapper can route on (the table is in `run.sh -h`), and each session's log is kept under
`.claude/pipeline-state/run-<ticket>/`. Two tips for a clean first run: set
`tracker.branchPrefix` in config (skips deriving it from the remote's branches, which has nothing
to match in a repo with no prior pipeline branches), and pick a ticket with no
external-infrastructure ACs. The run ends at an approved PR; merging it stays a human's call.

**Sequencing note (migrating repos with vendored copies):** delete the repo-local files that shadow plugin-shipped names, commit, and **start a fresh session** before the dry-run — deleting same-named skills mid-session invalidates that session's skill registry and every `Skill(<plugin>:<name>)` call returns "Unknown skill" until restart ([`namespaces.md`](namespaces.md) rule 6).

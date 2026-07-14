# Onboarding a repo

Onboarding = enable plugins + write one config file (+ optional extension files). No file copying.

## 0. Fast path: `/second-shift:onboard`

The marketplace writes its own consumer config. Three commands:

```text
claude plugin marketplace add manoldonev/second-shift
claude plugin install second-shift@second-shift        # user scope
# in the target repo:
/second-shift:onboard
```

`onboard` detects tracker/topology/commands with provenance (never asking what git or
package.json can answer), presents ONE accept-or-edit screen, and emits:

- `.claude/second-shift.config.json` — with a `$schema` first key at the pinned ref, so editors validate live
- a pinned `.claude/settings.json` block — `extraKnownMarketplaces` at the release ref + the blessed-bundle `enabledPlugins` (merged into your existing settings, never clobbered)
- `.claude/second-shift.lock.json` — the plugin→version contract `/second-shift:doctor` verifies against
- the repo-committed thin check (`.claude/tools/second-shift-doctor.sh` + a SessionStart nudge)
- `.claude/SECOND-SHIFT.md` — the consent doc: what installs, what hooks fire, before the trust prompt
- a paste-ready CONTRIBUTING snippet for teammates

The config is validated with the plugin-shipped `config-lint` in-loop before anything lands.
If the live settings write is blocked, the merged document goes to
`.claude/settings.json.second-shift-proposed` with exact apply instructions.

**Verify (any machine, any time): `/second-shift:doctor`.** It checks the installed state
against the committed lockfile and catches all five drift states — never-installed,
enabled-but-not-installed (the default state of a fresh clone whose owner accepted the
trust prompt but not the install prompts), version-behind, version-AHEAD (the rollback
case), and settings-ref↔lockfile-ref drift (a half-done upgrade PR) — plus ref-less
marketplace shadowing, repo-local skill/agent shadow collisions, and opt-outs. Every FAIL
prints its exact remediation command; the exit code is the FAIL count.

The SessionStart nudge (`.claude/tools/second-shift-doctor.sh`) is the tiny committed
presence check wired into project settings: on session start it compares the lockfile
against the local plugin cache and prints one friendly "you're missing your accelerators"
line when the toolkit isn't installed — the only channel that reaches someone who skipped
the trust prompt, since project hooks run regardless of plugin install state. It always
exits 0 (it nudges, never blocks). Together with the lockfile it is the sanctioned
exception to no-vendoring: both files verify plugin presence, they are not plugin content.

Rolling this out to a whole team — trust flow, opt-outs, upgrades, rollback, the managed
variant — is its own playbook: [`team-rollout.md`](team-rollout.md).

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
(`enabledPlugins` with just `review-toolkit@second-shift: true`) — *community-supported, not
CI-tested*. Everything else is possible via `enabledPlugins: false` and yours to own.

Why so strict: five optional plugins is a 2^5 support matrix, and the seams between plugins
(pipeline → review panel, intake → plan gates) break precisely at partial installs. One
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
          "source": { "source": "github", "repo": "manoldonev/second-shift", "ref": "v2.2.0" }
        }
      }
    }
    ```

2. **Plugin `version` field** — each plugin's `plugin.json` carries an explicit `version`; the install cache is keyed by it (`~/.claude/plugins/cache/second-shift/<plugin>/<version>/`) and an installed plugin only moves when that string changes. Third-party marketplaces do **not** auto-update, so an installed version stays put until an explicit `/plugin marketplace update` + reinstall.

    ```bash
    claude plugin install dev-pipeline@second-shift --scope project   # records version + git SHA
    ```

Upgrading = a PR that bumps the `ref` in settings **and** `.claude/second-shift.lock.json` together (the full recipe: [`releasing.md`](releasing.md) §6; verify with `/second-shift:doctor`), then `claude plugin marketplace update second-shift` + reinstall, then the repo's validation gates re-run (config-lint, selftests, a dry-run ticket). Breaking schema changes carry a migration doc in [`migrations/`](migrations/README.md) — config-lint points at it. One caveat: a **user-level** marketplace registration with the same name (typical on the machine that developed the marketplace) is ref-less and takes precedence locally — the project-settings `ref` is what protects everyone else, and `claude plugin list` should confirm the expected version after any update.

## 2. Write the static context

Create `.claude/second-shift.config.json` (the schema: [`schema/second-shift.config.schema.json`](../schema/second-shift.config.schema.json), field-by-field guide: [`config-schema.md`](config-schema.md)). Minimal example:

```json
{
  "configVersion": 1,
  "tracker": { "type": "github" },
  "topology": { "type": "standalone", "repos": { "app": { "path": ".", "baseBranch": "main" } } },
  "commands": { "app": { "lint": "yarn lint", "typecheck": "yarn tsc --noEmit", "test": "yarn test" } }
}
```

Nothing here assumes JavaScript. The same shape for a Python service on JIRA
(poetry/pytest; note `"writes": false` — the documented JIRA default — and `format: null`,
which switches the format lane off entirely, no prettier, no node):

```json
{
  "configVersion": 1,
  "tracker": { "type": "jira", "writes": false, "branchPrefix": "acme-dev/" },
  "topology": { "type": "standalone", "repos": { "app": { "path": ".", "baseBranch": "develop" } } },
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
bash "${CLAUDE_PLUGIN_ROOT:-<dev-pipeline-plugin-root>}/skills/run/tools/config-lint.sh" \
  .claude/second-shift.config.json
```

(The pipeline runs this itself at startup — Pre-flight, `dev-pipeline` SKILL — and fails fast on violations.)

## 2b. Prerequisites the first run enforces (GitHub tracker)

`/second-shift:onboard` walks you through both of these; if you onboarded manually, the
first `/dev-pipeline:run` pre-flight enforces them, so handle them now rather than mid-run:

- **The six queue labels.** Pre-flight requires `ready-for-dev`, `needs-spec-work`,
  `needs-plan-review`, `needs-intake-review`, `in-progress`, `epic` to exist on the repo
  (shipped literals until `stageParams.requiredLabels` is authoritative end-to-end — issue #11):

  ```bash
  for l in ready-for-dev needs-spec-work needs-plan-review needs-intake-review in-progress epic; do
    gh label create "$l" || true
  done
  ```

- **A GitHub-App bot identity.** The pipeline claims issues and pushes commits as a bot
  (clean audit trail; your personal identity never authors autonomous writes). Pre-flight
  checks the bot wrapper FIRST, unconditionally, for the GitHub tracker. You need a GitHub
  App (issues+contents write) and its private key; the dev-pipeline plugin ships the
  bootstrap — resolve the plugin root via `claude plugin list --json` → `installPath`, then
  run its `skills/run/tools/install-gh-bot.sh`. No bot yet = the run aborts at pre-flight with a
  written reason; that is a pipeline requirement, not an onboarding failure.

Neither applies to the JIRA tracker (reads via the Atlassian MCP; `writes: false` is the
default posture). Both trackers need `gh` regardless — Stage 9 opens the PR with
`gh pr create` — plus `node` for the Stage-8 review and mutation Workflow gates.

Environment sanity for all of the above in one command: `pipeline-doctor.sh` (ships in the
dev-pipeline plugin at `skills/run/tools/pipeline-doctor.sh`, config-aware since 2.0.7 —
probes only what YOUR tracker and command table actually use).

## 3. Optional: dynamic context

- **Knowledge skills** — ordinary repo-local skills in `.claude/skills/`; discovered natively, no registration.
- **Domain reviewers** — repo-local agents in `.claude/agents/`, registered via config `reviewers.add`.
- **Extension files** — documented hook points the generic agents read when present ([`extension-points.md`](extension-points.md)): blocker-mutant lists, domain security rules, design-token references.
- `findings.md`, `CLAUDE.md` — as before; the plugins never require them but respect them.

## 4. Verify

Three layers, in order:

1. **Config**: config-lint (above) — green means the static context parses and every value
   is schema-legal.
2. **Install state**: `/second-shift:doctor` — installed plugins vs the lockfile, settings
   pin, shadow collisions (see §0).
3. **Runtime environment**: `pipeline-doctor.sh` (dev-pipeline plugin, `skills/run/tools/`)
   — tracker CLI/auth, bot wrapper, labels, node, statectl. Different layer from
   `/second-shift:doctor`; both exist on purpose. Extension files are checked at pre-flight
   by `check-extensions.sh` against the shipped manifest (a typo'd extension filename is
   loud, never silently ignored).

Then the read-only preflight — the onboarding finish line. `/second-shift:onboard` runs it as its final step; manually, resolve the dev-pipeline install path (`claude plugin list --json` → `.installPath`) and run `bash "<installPath>/skills/run/tools/preflight.sh"`. It echoes the resolved targets, runs the config gates and the environment doctor, performs one tracker READ (no claim), executes every non-null command lane once (source-mutating lanes are skipped with a note), and writes `.claude/pipeline-state/preflight-report.md` — zero tracker/git/remote mutations, so the first mutating contact happens only after everything else is proven green.

Then a first run on a small, self-contained ticket:

```text
/dev-pipeline:run <ticket>
```

Autonomous mode is safe to trust on day one because it never guesses: the Target Confirmation Gate echoes the resolved config (tracker, repos, base branches) at the top of the run, and every gate **fail-fasts with a written reason** instead of asking — a mis-declared repo aborts before anything is mutated, and `.claude/pipeline-state/<key>.json` tells you exactly why. Two tips for a clean first run: set `tracker.branchPrefix` in config (skips runtime branch-identity derivation, which has nothing to match in a repo with no prior pipeline branches), and pick a ticket with no external-infrastructure ACs. An interactive step-through mode exists for debugging aborted runs — see the `dev-pipeline` SKILL — but onboarding doesn't need it.

**Sequencing note (migrating repos with vendored copies):** delete the repo-local files that shadow plugin-shipped names, commit, and **start a fresh session** before the dry-run — deleting same-named skills mid-session invalidates that session's skill registry and every `Skill(<plugin>:<name>)` call returns "Unknown skill" until restart ([`namespaces.md`](namespaces.md) rule 6).

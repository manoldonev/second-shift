# Onboarding a repo

Onboarding = enable plugins + write one config file (+ optional extension files). No file copying.

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

Enable only what fits — a repo can adopt `review-toolkit` without the pipeline. Pin a release wherever stability matters; track latest only in a canary.

### Pinning a release

Two mechanisms compose, and both are needed for a durable pin:

1. **Marketplace ref** — point `extraKnownMarketplaces` at the release tag so the catalog itself can't drift (`ref` accepts a branch or tag; per-plugin `sha` pinning exists only for plugin sources inside `marketplace.json`):

    ```json
    {
      "extraKnownMarketplaces": {
        "second-shift": {
          "source": { "source": "github", "repo": "manoldonev/second-shift", "ref": "v1.1.0" }
        }
      }
    }
    ```

2. **Plugin `version` field** — each plugin's `plugin.json` carries an explicit `version`; the install cache is keyed by it (`~/.claude/plugins/cache/second-shift/<plugin>/<version>/`) and an installed plugin only moves when that string changes. Third-party marketplaces do **not** auto-update, so an installed version stays put until an explicit `/plugin marketplace update` + reinstall.

    ```bash
    claude plugin install dev-pipeline@second-shift --scope project   # records version + git SHA
    ```

Upgrading = a PR that bumps the `ref` in settings, then `claude plugin marketplace update second-shift` + reinstall, then the repo's validation gates re-run (config-lint, selftests, a dry-run ticket). One caveat: a **user-level** marketplace registration with the same name (typical on the machine that developed the marketplace) is ref-less and takes precedence locally — the project-settings `ref` is what protects everyone else, and `claude plugin list` should confirm the expected version after any update.

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

Validate it:

```bash
# config-lint ships INSIDE the dev-pipeline plugin (so installed-cache consumers can run it):
bash "${CLAUDE_PLUGIN_ROOT:-<dev-pipeline-plugin-root>}/skills/run/tools/config-lint.sh" \
  .claude/second-shift.config.json
```

(The pipeline runs this itself at startup — Pre-flight, `dev-pipeline` SKILL — and fails fast on violations.)

## 3. Optional: dynamic context

- **Knowledge skills** — ordinary repo-local skills in `.claude/skills/`; discovered natively, no registration.
- **Domain reviewers** — repo-local agents in `.claude/agents/`, registered via config `reviewers.add`.
- **Extension files** — documented hook points the generic agents read when present ([`extension-points.md`](extension-points.md)): blocker-mutant lists, domain security rules, design-token references.
- `findings.md`, `CLAUDE.md` — as before; the plugins never require them but respect them.

## 4. Verify

Run config-lint (above), then a first run on a small, self-contained ticket:

```text
/dev-pipeline:run <ticket>
```

Autonomous mode is safe to trust on day one because it never guesses: the Target Confirmation Gate echoes the resolved config (tracker, repos, base branches) at the top of the run, and every gate **fail-fasts with a written reason** instead of asking — a mis-declared repo aborts before anything is mutated, and `.claude/pipeline-state/<key>.json` tells you exactly why. Two tips for a clean first run: set `tracker.branchPrefix` in config (skips runtime branch-identity derivation, which has nothing to match in a repo with no prior pipeline branches), and pick a ticket with no external-infrastructure ACs. An interactive step-through mode exists for debugging aborted runs — see the `dev-pipeline` SKILL — but onboarding doesn't need it.

**Sequencing note (migrating repos with vendored copies):** delete the repo-local files that shadow plugin-shipped names, commit, and **start a fresh session** before the dry-run — deleting same-named skills mid-session invalidates that session's skill registry and every `Skill(<plugin>:<name>)` call returns "Unknown skill" until restart ([`namespaces.md`](namespaces.md) rule 6).

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

Enable only what fits — a repo can adopt `review-toolkit` without the pipeline. Team repos should **pin a release** (see version policy in the README); only a canary repo tracks latest.

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
bash "${CLAUDE_PLUGIN_ROOT:-<dev-pipeline-plugin-root>}/skills/dev-pipeline/tools/config-lint.sh" \
  .claude/second-shift.config.json
```

(The pipeline runs this itself at startup — Pre-flight, `dev-pipeline` SKILL — and fails fast on violations.)

## 3. Optional: dynamic context

- **Knowledge skills** — ordinary repo-local skills in `.claude/skills/`; discovered natively, no registration.
- **Domain reviewers** — repo-local agents in `.claude/agents/`, registered via config `reviewers.add`.
- **Extension files** — documented hook points the generic agents read when present ([`extension-points.md`](extension-points.md)): blocker-mutant lists, domain security rules, design-token references.
- `findings.md`, `CLAUDE.md` — as before; the plugins never require them but respect them.

## 4. Verify

Run the smoke checks: config-lint (above), then a `DEV_PIPELINE_MODE=interactive` dry-run on a small ticket. The pipeline's Target Confirmation Gate will echo the resolved config (tracker, repos, base branches) before doing anything.

**Sequencing note (migrating repos with vendored copies):** delete the repo-local files that shadow plugin-shipped names, commit, and **start a fresh session** before the dry-run — deleting same-named skills mid-session invalidates that session's skill registry and every `Skill(<plugin>:<name>)` call returns "Unknown skill" until restart ([`namespaces.md`](namespaces.md) rule 6). Pick a dry-run ticket with no external-infrastructure ACs (live DB, running services) unless the machine actually has them — otherwise the run exercises the degraded-verification path instead of the happy path.

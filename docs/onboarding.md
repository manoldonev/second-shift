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

`onboard` detects tracker/topology/commands with provenance (never asking what git or
package.json can answer), presents ONE accept-or-edit screen, and emits:

- `.claude/second-shift.config.json` — with a `$schema` first key at the pinned ref, so editors validate live
- a pinned `.claude/settings.json` block — `extraKnownMarketplaces` at the release ref + the blessed-bundle `enabledPlugins` (merged into your existing settings, never clobbered)
- `.claude/second-shift.lock.json` — the plugin→version contract `/second-shift:doctor` verifies against
- the repo-committed thin check (`.claude/tools/second-shift-doctor.sh` + a SessionStart nudge)
- `.claude/SECOND-SHIFT.md` — the consent doc: what installs, what hooks fire, before the trust prompt
- **(on request)** `.github/workflows/second-shift-ci.yml` + `.claude/tools/second-shift-ci-check.sh` — the server-side backstop: on every PR it config-lints the committed config with the linter shipped at the pinned marketplace ref and asserts the settings ref and lockfile ref agree, so a half-done upgrade PR is caught. Reports a red check; mark it a required status check in branch protection to block merges.
- **(same request, github tracker)** `.github/workflows/second-shift-unclaim.yml` + `.claude/tools/second-shift-unclaim.sh` — the close-out step neither lane owned: when an issue closes it removes the pipeline's two run-state labels (`tracker.labels.claimed` and `tracker.labels.queue`, resolved from your committed config at run time; never `tracker.labels.blockers`, which holds permanent classifications like `epic`). This is the one emitted workflow that **writes** — `issues: write`, two labels on one issue, which needs the repo's Actions workflow permissions set to read-and-write (a `permissions:` block narrows the repo maximum, it cannot widen it). The lean lane's exit milestone requires an open PR, so a session-side drop would fire while review is still in flight; binding the release to the close event needs no live session and covers a hand-closed issue too.
- **(same request)** `.github/workflows/second-shift-delta-guard.yml` + `.claude/tools/second-shift-delta-guard.sh` — the delta guard, which is about your **CI bill** rather than your evidence. `review-lean` must commit the verdict record to the PR head as the *last* commit, so on a `pull_request`-triggered CI every lean PR pays a second full run — lint, typecheck, build, the whole test suite — for a markdown file the pipeline wrote itself. The guard is a reusable workflow exposing a `skip` output; you gate your heavy jobs on it with two lines each:

  ```yaml
  jobs:
    second-shift-delta-guard:
      uses: ./.github/workflows/second-shift-delta-guard.yml

    test:
      needs: second-shift-delta-guard
      if: needs.second-shift-delta-guard.outputs.skip != 'true'
  ```

  `!= 'true'`, never `== 'false'`: a guard that produced no output at all leaves the string empty, and an empty string has to *run* the lane. **It skips only when the parent SHA already has a completed, successful run of that same workflow for that same event** — cancelled, failed, still running, absent, or unreadable all fall through to a full run, which is what stops the guard from laundering a green onto code nothing verified. This is the one emitted pair you must wire in yourself, because the jobs it shortens are yours; unwired it is inert.

  Two things it is deliberately *not*. It is not `[skip ci]`: that produces **no run at all** for the head SHA, so a repo with required status checks blocks on a check that stays `Expected` forever — whereas a job skipped by a job-level `if:` still produces a check run GitHub counts as passing. And it is not `paths-ignore`, which cannot work here at all: for `pull_request` events GitHub evaluates path filters against the whole PR diff (base…head), not the incremental push, so every PR containing a source change matches regardless of what the last commit touched.

- **Concurrency, whether or not you adopt the guard.** For `pull_request` events, do not key `cancel-in-progress: true` bare on the ref. The verdict push then cancels the code commit's in-flight run, and you are left with a **cancelled** run on the SHA carrying the code and a **completed** one on the SHA carrying only markdown — the evidence is inverted, not merely duplicated. Key the concurrency group on the head SHA, or set `cancel-in-progress: false`. Reachable any time review latency is under CI latency, which a fast panel on a small diff hits easily.

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

### Pair repos (BE/FE) under the lean lane

`/dev-pipeline:run-lean` routes by invocation cwd — it has no per-repo worktree map. A
confirmed pair's `topology.type: be-fe-pair` config (unchanged, `be`+`fe` entries) stays a
legal shape and other readers still honour it, but nothing fans a run out across both repos
any more: the staged lane that did, `/dev-pipeline:run`, was deleted in #348. Working the
pair therefore needs one thing: **the sibling repo onboards separately, on its own.** `cd` into it and run `/second-shift:onboard` there too — detection reports plain
`standalone` from that side (the sibling-candidate probe is directional), so it drafts its
own independent config (itself at `path: "."`), its own bot identity, its own worktrees
dir, with no further prompts. Two onboard runs, two configs, each serving a different lane
from the same pair.

`topology.repos.<id>.ticketTag` on the host's `be`/`fe` entries (e.g. `"[BE]"` / `"[FE]"`)
is **advisory only** — no gate reads it (a retired lane resolved `TARGET_REPOS`
from it as a gate input; that reader was deleted in #348). What it does is route the lane: whoever launches `/dev-pipeline:run-lean`
— an operator or the scheduler itself — reads the tag to pick the repo checkout to launch from. **FE-tagged tickets run from the FE
repo.** The `intake-orchestrator` skill enforces the corresponding discipline at
ticket-filing time: a title carrying both pair tags, or neither, is rejected before spec
review even starts, and genuine cross-repo scope splits into one BE ticket and one FE
ticket (BE first by default), the FE one filed in the FE repo's own tracker, rather than
entering the queue as one artifact.

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
CI-tested*. Everything else is possible via `enabledPlugins: false` and yours to own, with **one
exception**: `audit-toolkit` off while `dev-pipeline` is on is not a supported combination.
`audit-toolkit` ships the hook that writes the per-session audit ledger, the lean lane's entry
gate refuses to start without a live one, and `/second-shift:doctor` FAILs on the pairing rather
than warning. Disable both together if the repo does not run the lane.

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
          "source": { "source": "github", "repo": "manoldonev/second-shift", "ref": "v8.0.0" }
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
  "configVersion": 2,
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
  "configVersion": 2,
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
bash "${CLAUDE_PLUGIN_ROOT:-<dev-pipeline-plugin-root>}/tools/config-lint.sh" \
  .claude/second-shift.config.json
```

(The pipeline runs this itself at startup — Pre-flight, `dev-pipeline` SKILL — and fails fast on violations.)

## 2b. Prerequisites the first run enforces (GitHub tracker)

`/second-shift:onboard` walks you through both of these; if you onboarded manually, the
first pipeline run enforces them — the bot wrapper and the claim's queue label are
load-bearing for `/dev-pipeline:run-lean` and for `/dev-pipeline:build-lean` invoked
directly — so handle them now rather than mid-run:

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
  run its `tools/install-gh-bot.sh`. No bot yet = the run aborts at pre-flight with a
  written reason; that is a pipeline requirement, not an onboarding failure.

Neither applies to the JIRA tracker (reads via the Atlassian MCP; `writes: false` is the
default posture). Both trackers need `gh` regardless — the build block opens the PR with
`gh pr create` — plus `node` for the review and mutation Workflow gates.

### Finish the command table — and give it a setup lane

Detection only covers JS package managers plus a Makefile fallback. On any other stack
(Python/pip/poetry/uv, bun, cargo, go) onboard refuses to guess and drafts every
`commands.<id>` lane as `null`. **That table is a starting point, not a finished config** —
fill in your repo's real commands. Until at least one verifying lane (`lint`, `typecheck`,
`test`, or an `extraLanes` entry) is configured, `preflight` warns and withholds its
`pipeline-ready` verdict, and the lean gate's milestone 3 refuses a run that verified
nothing. If
verifying nothing is genuinely intended (a docs-only repo, say), set
`commands.<id>.allowUnverified: true` so the choice is explicit rather than an oversight.

**A configured lane can still never run.** The verify sweep skips the suite for an "inert" diff —
one whose every changed path is zero-coverage for a JS/TS suite — and the shipped inert
set includes `*.md` and `*.sh`. On a repo where those ARE the product (a shell toolchain,
a docs site, a Python project whose tooling lives in shell), every real diff classifies
inert, your correctly-configured `lint`/`test` never execute, and the sweep reports
`skipped (inert diff)` — a false green that looks like a pass. If that is your stack, set
`stageParams.inertPattern` to an ERE that leaves your product's file types OUT of the
inert set; it replaces the shipped default outright. `preflight` warns when the effective
pattern makes your configured lanes unreachable, so you find out before a run rather than
after one.

Then add a **setup lane**. The pipeline works in a `git worktree` — a fresh checkout that
starts with no `node_modules` and no `.venv`, since both are gitignored. Verify lanes that
need installed dependencies fail on the first real run unless the install runs first, and
that is what `commands.<id>.lanes[]` is for (sequential setup steps, run before the verify
lanes and classed as infrastructure on failure):

```jsonc
"lanes": [{ "name": "install", "commands": ["python3 -m venv .venv", ".venv/bin/pip install -e '.[dev]'"] }]
// JS equivalent: [{ "name": "install", "commands": ["npm ci"] }]
```

Field reference — including `extraLanes` and `allowUnverified` — is in
[`config-schema.md`](config-schema.md).

### Mutation: the repo-carried sweep

A passing suite proves the tests run, not that they would catch anything. The check for that is
**yours to carry and ours to run**: if your repo has an executable `tools/mutation-sweep.sh`, the
green gate executes it as the last step of the verification milestone.

```text
bash tools/mutation-sweep.sh --mode pr --base origin/<baseBranch>
```

- **Invocation** — run from your repo root, with `<baseBranch>` taken from your config's
  `topology.repos.<id>.baseBranch`. `--mode pr` means diff-scoped: only what this branch changed.
- **Exit code is the whole contract.** `0` passes; any non-zero **reds the milestone** and the
  run stops with the reason written to the progress file. Nothing else about the sweep is
  inspected — not its stdout, not a report file.
- **Absent is a printed skip, never a silent pass.** With no such file the gate says
  `mutation sweep SKIPPED` and records it. That is a legal state; `/second-shift:doctor` raises
  it as an adoption note once a `test` lane is configured, so the absence stays visible instead
  of being mistaken for coverage.
- **Deterministic, and no model calls.** It runs inside a gate on every ticket, so it must be
  reproducible from the tree alone and must not spend API budget. A sweep that needs the network
  or an LLM belongs in an `extraLanes` entry you opt into, not here.

What the sweep does inside is entirely your choice — a Stryker or `mutmut` wrapper, a per-spec
harness that flips operators and re-runs the affected file, a shell-guard sweep. The gate asserts
the outcome; it has no opinion on the method. `gates.mutation` and `commands.<id>.unitTestScope`
are rollback-lane keys and buy no sweep on their own.

Environment sanity for all of the above in one command: `pipeline-doctor.sh` (ships in the
dev-pipeline plugin at `tools/pipeline-doctor.sh`, config-aware since 2.0.7 —
probes only what YOUR tracker and command table actually use).

## 3. Optional: dynamic context

- **Knowledge skills** — ordinary repo-local skills in `.claude/skills/`; discovered natively, no registration.
- **Domain reviewers** — repo-local agents in `.claude/agents/`, registered via config `reviewers.add`.
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

- **Use the exact catalog heading names.** `check-review-context-sections.sh` matches them
  exactly (no fuzzy guessing). A drifted spelling (e.g. `## Maturity calibration (MVP stage)`
  instead of `## Maturity stage`) is flagged at the pre-work preflight with the exact rename
  command; an invented heading is fine — list it in `.claude/second-shift/.known-sections` to
  mark it intentional.
- **Never leave a heading with an empty or TODO body.** A present-but-hollow section reads as
  a policy declaration reviewers quote back — worse than an honest absence. The linter treats
  it as absent and fails preflight. Write the section, or omit the heading.

`/second-shift:onboard` offers to scaffold a starter file from your confirmed answers (never
mandatory, never a TODO-bodied stub). Run `check-review-context-sections.sh --report` any time
for a one-line coverage summary of which reviewers are running degraded.

## 4. Verify

Three layers, in order:

1. **Config**: config-lint (above) — green means the static context parses and every value
   is schema-legal.
2. **Install state**: `/second-shift:doctor` — installed plugins vs the lockfile, settings
   pin, shadow collisions (see §0).
3. **Runtime environment**: `pipeline-doctor.sh` (dev-pipeline plugin, `tools/`)
   — tracker CLI/auth, bot wrapper, labels, node, the lean gate. Different layer from
   `/second-shift:doctor`; both exist on purpose. Extension files are checked at pre-flight
   by `check-extensions.sh` against the shipped manifest (a typo'd extension filename is
   loud, never silently ignored).

Then the read-only preflight — the onboarding finish line. `/second-shift:onboard` runs it as its final step; manually, resolve the dev-pipeline install path (`claude plugin list --json` → `.installPath`) and run `bash "<installPath>/tools/preflight.sh"`. It echoes the resolved targets, runs the config gates and the environment doctor, performs one tracker READ (no claim), executes every non-null command lane once (source-mutating lanes are skipped with a note), and writes `.claude/pipeline-state/preflight-report.md` — zero tracker/git/remote mutations, so the first mutating contact happens only after everything else is proven green.

Then a first run on a small, self-contained ticket. The front door is a scheduler over the
lane's blocks — it spawns each in a fresh session and reads its outcome, authoring nothing:

```text
/dev-pipeline:run-lean <ticket>
```

**It takes two sessions, and that is the design.** The build block stops at milestone 4 and
hands off: the verdict is authored by a separate top-level session, because a session grading
its own work is not an independent review. The scheduler chains them for you, with no operator
wait in between. Driven by hand — the two-terminal flow, and the rescue path — it is the same
two blocks, unchanged:

```text
/dev-pipeline:build-lean <ticket>
/dev-pipeline:review-lean <pr>
```

— which produces findings on the PR and commits the verdict record that milestone 4 and the
merge boundary both read. Until it runs, the PR's `lean chain` check is red on purpose, and the
build session cannot shortcut it: `lean-gate.sh verdict` refuses to run inside the build
session at all. A verdict also has to cover the head it is read against, so pushing more
commits after an approve costs another review round.

Autonomous mode is safe to trust on day one because it never guesses: `build-lean`'s entry
gate refuses without a live audit ledger, and on a GitHub tracker the session also refuses
without the queue label (a read-only tracker has no queue). Both fire before any work begins,
and every milestone gate **fail-fasts with a written reason** instead of asking — `.claude/pipeline-state/<issue>-lean-progress.md` tells you exactly why. Two tips for a clean
first run: set `tracker.branchPrefix` in config (skips runtime branch-identity derivation,
which has nothing to match in a repo with no prior pipeline branches), and pick a ticket with
no external-infrastructure ACs. When a run stops mid-way, the debugging path is the two-terminal
manual flow — invoke `/dev-pipeline:build-lean` and `/dev-pipeline:review-lean` directly, which
is the same block the scheduler drives.

**Sequencing note (migrating repos with vendored copies):** delete the repo-local files that shadow plugin-shipped names, commit, and **start a fresh session** before the dry-run — deleting same-named skills mid-session invalidates that session's skill registry and every `Skill(<plugin>:<name>)` call returns "Unknown skill" until restart ([`namespaces.md`](namespaces.md) rule 6).

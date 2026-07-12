# Changelog

All notable changes to the second-shift marketplace. Versions are per-plugin (`plugins/*/.claude-plugin/plugin.json`);
this file tracks the marketplace release. `configVersion` stays `const 1` — v2 is fully backward-compatible for a
consumer with an empty config; the migration notes below are only for consumers using the changed features.

## v2.1.3 — release contract: configVersion migrations + release discipline (in progress)

### `dev-pipeline` 2.1.1 → 2.1.2
- **config-lint learns the migration contract (issue #32).** `configVersion` errors now carry pointers instead
  of the bare "must be 1": a number > 1 → "newer than this plugin understands — upgrade the marketplace pin
  (docs/releasing.md)"; < 1 → "predates this plugin — see docs/migrations/"; non-number → "required number
  (current: 1)". The two v1 keys removed in v2.0.0 are special-cased with their exact migration pointers
  (`gates.figma` → `design: {"provider": ...}`; `gates.apiTests` → EP-6/EP-7 companion pack — both →
  docs/migrations/v1-to-v2.md), and the generic gates unknown-keys message now names the offending keys.
  Three new invalid fixtures. Docs: `docs/releasing.md` (maintainer checklist: version-bump discipline,
  CHANGELOG step, metadata lockstep, mandatory "What breaks / what to do" Release body, official `renames`
  map (≥ v2.1.193, append-only), doc-pin-example refresh — the v1.1.0 lesson), `docs/migrations/README.md`
  (the contract + the honest v2.0.0 history line), and the retroactive `docs/migrations/v1-to-v2.md`.

## v2.1.2 — one blessed bundle + the consent doc (in progress)

### `second-shift` 1.0.0 → 1.1.0
- **One blessed bundle + the consent doc (issue #31).** Onboard now also emits `.claude/SECOND-SHIFT.md`
  (from `templates/consumer/SECOND-SHIFT.md`): per-plugin component inventory — what installs, which hooks
  fire on which events, when code actually runs — plus the sanctioned personal opt-out recipe
  (`settings.local.json`) and the support boundary, so the trust-dialog decision is made BEFORE the scary
  prompt. Docs now bless exactly one artifact (full suite at a pinned tag, design-toolkit sole conditional)
  with review-only as the single documented community-supported downgrade.

## v2.1.1 — be-fe-pair: target routing (#4, PR 2, in progress)

### `dev-pipeline` 2.1.0 → 2.1.1
- **#4 — Stage 1 `targetRepos` routing + the multi-repo failure reasons.** Added `targetRepos-ambiguous` + `fe-repo-unreachable` to the `valid_failure_reason` closed enum (state-schema.md table → regenerated `statectl.sh` via `gen-statectl-validators.sh`; drift-check byte-match verified). New topology-gated Stage-1 **Step 1.T** (runs only for `topology.type: be-fe-pair`) resolves `TARGET_REPOS` from the fetched ticket **title** matched against each repo's `topology.repos.<id>.ticketTag` — a single tag → that repo, both tags → cross-repo (`"be fe"`), no recognizable tag → fail closed `targetRepos-ambiguous` (never guess); each target repo's `path` must be reachable in the session (`claude --add-dir`), else `fe-repo-unreachable`. `ticketTag` finally has readers (was dead config). Strictly additive — a `standalone`/`monorepo` consumer skips Step 1.T entirely. Per-repo worktree creation (Stage 2) lands in the next PR.
## v2.1.0 — onboarding release: the marketplace writes its own consumer config (in progress)

### `second-shift` (new) 1.0.0
- **New sixth plugin: the user-scope onboarding micro-plugin (issue #28).** `/second-shift:onboard` runs in the
  target consumer repo: provenance-first detection (`detect.sh` — tracker from origin host + MCP evidence, topology
  from workspaces/siblings, baseBranch from origin/HEAD only — an undetectable base branch is a written abort,
  never a guess), release-pin resolution (`pin-resolve.sh` — latest GitHub Release, highest-semver-tag fallback,
  per-plugin versions read AT the pinned ref via the contents API), ONE accept-or-edit elicitation batch
  (branchPrefix, mutation/costTracking gates, design provider, reviewer deltas, and — github tracker — the
  bot-identity decision plus optional creation of the six queue labels, absorbing the previously undocumented
  first-run wall), then emits `.claude/second-shift.config.json` (with a `$schema` first key at the pinned ref),
  a merged `.claude/settings.json` pin block (`.second-shift-proposed` fallback when blocked), and
  `.claude/second-shift.lock.json` (lockfileVersion 1) — lint-looped green with the plugin-shipped config-lint
  before anything lands. Zero agents, zero hooks. Both shell tools ship hermetic bash-3.2-safe selftests.
- **`/second-shift:doctor` + the consumer lockfile contract (issue #29).** `doctor.sh` verifies install state
  against the committed lockfile — never-installed, enabled-but-not-installed (the v2.1.195 fresh-clone default,
  the most common finding), version-behind, version-AHEAD (rollback), settings-ref↔lockfile-ref drift — plus
  ref-less marketplace shadowing (via `claude plugin marketplace list --json`, text-parse fallback), repo-local
  skill/agent shadow collisions, opt-out scan, and config-lint. Every FAIL prints its exact remediation; exit
  code = FAIL count. Hermetic 8-scenario selftest with env-injected data sources. Onboard now also emits the
  repo-committed thin check (`.claude/tools/second-shift-doctor.sh` + SessionStart nudge — presence check only,
  always exits 0, <50ms) — with the lockfile, the sanctioned exception to no-vendoring.

### `dev-pipeline` 2.0.10 → 2.1.0
- **config-lint + schema accept a top-level `$schema` key.** `/second-shift:onboard` emits it for live editor
  validation at the pinned ref; both the lint's unknown-top-level-keys check and the JSON schema
  (`additionalProperties: false`) rejected it before. New `valid-schema-key-standalone.json` fixture.

## v2.0.10 — be-fe-pair foundation: additive per-repo state (#4/#5, PR 1 of 4, in progress)

First of a 4-PR series restoring full multi-repo (be-fe-pair) support to the generic core (the de-orging had collapsed it to single-repo). **Strictly additive and topology-gated** — no stage touched yet, so single-repo behavior is byte-for-byte unchanged.

### `dev-pipeline` 2.0.9 → 2.0.10
- **statectl `worktree-set --repo <id>` / `verify-attempts --repo <id>`** — a `be-fe-pair` run persists boundary fields and the per-class retry budget **per repo** at `worktrees.<repoId>.{worktreePath, branch, base, verifyAttempts}`, rather than the flat top-level `worktreePath`/`branch`/`verifyAttempts`. With `--repo` omitted (every standalone/monorepo consumer) the flat fields are written exactly as before — the `worktrees` map is absent. New `(va5)`/`(ws-repo)` selftests assert per-repo independence and that the flat path is untouched; the generated-validator drift-check is unaffected (no new enums). Documented in state-schema.md ("be-fe-pair note"). Stages 1/2/6/7/9/10 that consume the map land in PRs 2–4.

## v2.0.9 — docs hotfixes: onboarding path rot (in progress)

### `dev-pipeline` 2.0.8 → 2.0.9
- **Docs/comment-only: stale pre-v2 paths purged from tool headers and executed docs.** The README quick-start's
  config-lint step was unrunnable (`<dev-pipeline plugin root>/tools/` — the tool lives under `skills/run/tools/`;
  the command now resolves the install path via `claude plugin list --json`), and the settings-pin example in
  `docs/onboarding.md` pointed at the dead pre-recreation tag `v1.1.0` (→ `v2.0.0`). Inside the plugin, usage
  headers and generated banners still claimed the vendored `.claude/skills/run/` layout: `pipeline-doctor.sh`,
  `stage-times.sh`, `gen-statectl-validators.sh` (+ the three banners it prints into `statectl.sh`, kept in
  byte-lockstep for the regeneration selftest), `statectl-selftest.sh`, the cost-tracking fixtures README,
  `otel-collector-config.yaml`, and a `check-config-shadowing.sh` comment. `SKILL.md`'s model-tier section now
  names the real `check-model-tiers.sh` home (review-toolkit `scripts/`). Root docs: README no longer promises
  JIRA content in `docs/onboarding.md` (links the JIRA tracker README instead), `docs/extending.md` drops the
  phantom `second-shift sync` command (phase-1 vendoring is a manual copy), and the changelog's pre-2.0 pointer
  states the history was not carried over. The stale `.claude/scripts/` hook paths in `hooks.md` are left for
  #14 (review-toolkit commit-gate rework) to avoid a collision.

## v2.0.8 — generalization-audit fixes: JIRA scope-gate parity (in progress)

Restores the JIRA-aware ticket fetch the vendored (pre-second-shift) skills carried — the generic reviewer had regressed to GitHub-only.

### `dev-pipeline` 2.0.7 → 2.0.8
- **#16 (F13/F78) — the Stage-8 scope-completeness gate could only `gh issue view`, so every JIRA run returned BLOCKED→FAIL.** `code-review.mjs` now tracker-branches the scope-reviewer dispatch prompt on `config.tracker.type`: GitHub → `gh issue view #N`; JIRA → fetch via `mcp__atlassian__getJiraIssue` (key from `$ISSUE_NUMBER`, `cloudId` via `getAccessibleAtlassianResources`). Stage 8's reviewer-selection note generalized to spawn the gate on JIRA runs (always ticket-driven). README requirements corrected: `gh` is needed on **every** tracker (Stage 9 `gh pr create`), and `node` (the Workflow gates) is now listed.

### `review-toolkit` 2.0.1 → 2.0.2
- **#16 — `agents/scope-completeness-reviewer.md`** Step 1 now tracker-branches the fetch (github `gh issue view` / jira Atlassian MCP `getJiraIssue` + `getJiraIssueRemoteIssueLinks`, `cloudId` via `getAccessibleAtlassianResources`), with the MCP tools added to the agent frontmatter and the BLOCKED verdict + description generalized from "GitHub issue" to "issue/ticket". Mirrors the vendored JIRA reviewer (capability parity).

## v2.0.7 — generalization-audit fixes: config-aware doctor (in progress)

### `dev-pipeline` 2.0.6 → 2.0.7
- **#17 (F05 + tracker-blindness + wrapperPath drift) — `pipeline-doctor.sh` read no config and was permanently red for every non-yarn / non-GitHub consumer.** node + yarn were unconditional hard FAILs (a JIRA/pnpm/poetry consumer failed prerequisites it never uses, masking real FAILs by inflating the count); the gh/bot/label sections ran regardless of tracker; the label set was hardcoded; and the bot-wrapper path ignored `tracker.bot.wrapperPath` (reader/prober drift vs claim-issue.sh). Doctor now loads the consumer config first: **node** stays a real probe (the Workflow gates `code-review.mjs`/`mutation-gate.mjs` need it), but **package managers are probed from the configured command table** (first word of each `commands.<host>.*` entry — a pnpm repo probes pnpm, a poetry repo probes poetry) instead of a hardcoded yarn; the **gh auth / feature-probe / bot-wrapper / required-label** sections gate on `tracker.type == github`; **required labels** read from `stageParams.requiredLabels`; and the bot wrapper honors `tracker.bot.wrapperPath`. Green on a pnpm-GitHub repo and a poetry-JIRA repo; red only for genuinely missing prerequisites.

## v2.0.6 — generalization-audit fixes: config-driven format lane (in progress)

### `dev-pipeline` 2.0.5 → 2.0.6
- **#12 (F06/F20 + dead `commands.format`) — the format lane was hardwired to prettier and imposed node/npx on every consumer, on every run.** `resolve_prettier` was the only formatter path (with a `npx --yes prettier@x` fallback), so a Python consumer got `npx prettier --write src/app.py` (FORMAT fail, budget-charged) and a no-node machine got rc-127 → INFRA → run kill even on a docs-only diff (the plan `.md` Stage 3 always commits reached npx prettier). Meanwhile `commands.<host>.format` was published, fixture-set, config-lint-validated — and read by nothing. Now `verifyctl` resolves `FORMAT_MODE` from `commands.<host>.format`: **string** → run it verbatim as the repo's own formatter (`black .`, `yarn format`; no node assumption; the command owns its scope); **null** → skip the format lane entirely (prettier + npx never run); **absent** → the documented scoped-prettier default (byte-for-byte prior behavior — the ONLY path needing node/npx). The INERT-lane prettier check now runs only in prettier mode, so a config/`null` consumer's inert docs run never reaches npx. New `(v12)`/`(v13)` selftests assert the config command runs verbatim (not prettier) and that `null` skips with `verifySummary.format: "skipped"`.

## v2.0.5 — generalization-audit fixes: mutation-gate null-off semantics (in progress)

### `dev-pipeline` 2.0.4 → 2.0.5
- **#9 (F03) — null/absent `commands.<host>.testFile` / `unitTestScope` fell back to the acme yarn/`apps/api/src/**` literals, violating the schema's null=off contract.** The `//` operator mapped explicit-null AND absent to the acme literal, so a pytest consumer that left `testFile: null` per the schema got `yarn --cwd apps/api test tests/test_x.py` (rc 127 → every mutant INFRA → run halts), and a null `unitTestScope` scoped the diff to a nonexistent path (gate self-waives). Stage 5 now resolves both with `// empty`: null/absent `unitTestScope` ⇒ gate **OFF** (recorded, skipped); `unitTestScope` set but `testFile` null ⇒ **fail closed** (explicit config error, never a silent green or a hardcoded yarn). `mutation-gate.mjs` throws if executable mutants exist without a `testFileCommand` (defense-in-depth; dropped the `|| 'yarn …'` default). Genericized the Stage-3/4 prose gate rules to "the configured `unitTestScope` surface" (acme `apps/api/src/**` kept as illustration).

## v2.0.4 — generalization-audit fixes: Stage-3/4 state-path resolution (in progress)

### `dev-pipeline` 2.0.3 → 2.0.4
- **#10 (F24) — Stage-4 plan gate ignored `paths.pipelineStateDir` + used the raw uppercase ticket key.** Stages 3 and 4 handed plan-lint the reconstructed literal `$MAIN_ROOT/.claude/pipeline-state/${ISSUE_NUMBER}.json`, but statectl honors `paths.pipelineStateDir` and lowercases the key — so for a Jira-keyed ticket (`AB-123`) or a custom state dir the real file is elsewhere, plan-lint exits "state file not found", and the run aborts spuriously with `plan-structure-invalid`. Added a read-only `statectl state-path <ticket>` subcommand (prints the resolved absolute path via the existing `state_path()`/`state_dir()` logic) and switched both plan-lint call sites to it. New `(sp1)` selftest asserts default dir, custom `pipelineStateDir`, Jira-key lowercasing, and the no-arg usage error. Outside statectl's generated validator region — drift-check unaffected.

## v2.0.3 — generalization-audit fixes: residual base-branch literals (in progress)

Residual `main` base-branch literals off the C1 critical path — silent no-ops and rubric noise on non-`main`-based consumers.

### `dev-pipeline` 2.0.2 → 2.0.3
- **#13 (F31/F77) — `doc-update.md`** Steps 7.A/7.C diffed `git diff main...HEAD`, so a develop/alpha-based repo produced an empty changed-file set and the doc-staleness sweep silently reported "0 candidates" every run. Now resolves `$BASE_REF` from the host repo's configured `baseBranch` (default `main`).
- **#13 (F80) — `eval-criteria.md`** Autonomous-Pre-flight rubric required "a clean **`main`** base", so every legitimately non-`main` run scored a spurious FAIL into the pipeline-retro keep-or-revert loop. Reworded to "the configured base branch".

### `review-toolkit` 2.0.0 → 2.0.1
- **#13 — `review-lead/SKILL.md`** (base default) + **`agents/doc-updater.md`** (`git diff main...HEAD`) now resolve the base from the repo-local `.claude/second-shift.config.json` host `baseBranch` (default `main`), self-contained (no dev-pipeline path — honors the namespace-direction rule).

### `design-toolkit` 2.0.0 → 2.0.1
- **#13 — `agents/figma-faithful-reviewer.md`** `git diff main..HEAD` now resolves the configured base branch from repo-local config (default `main`).

## v2.0.2 — generalization-audit fixes: base/prefix generalization (Wave 1, in progress)

### `dev-pipeline` 2.0.1 → 2.0.2

- **#8 — executed stage bash hardcoded `main` + `claude/acme-` despite config `baseBranch`/`branchPrefix`.** Branch creation and verification disagreed about the base on the same run for any consumer whose mainline ≠ `main` or branch prefix ≠ `claude/acme-` (e.g. a `develop`-based, `team/`-prefixed repo). Threaded one shared resolution idiom — `PREFIX = tracker.branchPrefix // "claude/acme-"`, `BASE = state field // host(path==".").baseBranch // "main"` (the model verifyctl already uses) — through the executed blocks of **Stage 1** (outer-loop slice branch/base), **Stage 2** (single-PR fallback, resume-guard glob + `$BRANCH_PREFIX`, mainline cut-from-`origin/<base>` discriminator, worktree dir name now the branch basename `${BRANCH##*/}` instead of an `acme-` literal; **Stage 10** cleanup removes the worktree at the persisted `worktreePath` rather than reconstructing the `acme-` literal, which would orphan a non-default consumer's worktree), **Stage 5** (mutation-gate range base — a wrong base silently emptied the changed-file set and waived the blocking gate), and **Stage 9** (stale-branch freshness gate + `--base` PR target). Extended `check-config-shadowing.sh` to assert `tracker.branchPrefix` + `baseBranch` are read per owning stage, with a new selftest strip-case, so the class can't regress. Defaults reproduce prior behavior byte-for-byte (verified against empty and `main`-based configs).

## v2.0.1 — generalization-audit fixes (in progress)

Consumer-generalization fixes from the v2.0.0 audit. Patch-level: no schema change, `configVersion` stays `const 1`, all defaults reproduce prior behavior.

### `dev-pipeline` 2.0.0 → 2.0.1

- **#3 — Stage-6 verifyctl path rot (breaks every de-vendored consumer + blocked dogfooding).** Stage 6 resolved `verifyctl.sh` via the git-common-dir idiom, which points at the **consumer repo root** — but `verifyctl.sh` ships in the plugin checkout, so the path was nonexistent for every de-vendored consumer. Now anchored to `${CLAUDE_PLUGIN_ROOT}/skills/run/verifyctl.sh` (the resolution SKILL.md pre-flight already uses for `config-lint.sh`), with a `statectl.sh`-sibling fallback. Swept the same class across the executed stage blocks: `claim-issue.sh` (Stage 1), `max-pushed-slice.sh` (Stages 1/2), `plan-lint.sh` (Stages 3/4), `bot-commit.sh` (Stages 3/6), and the SKILL.md pre-flight onboarding hints — all now `${CLAUDE_PLUGIN_ROOT}`-anchored instead of CWD-relative.

## v2.0.0 — "the extensible core"

The de-orged, extensible core: a genuinely generic marketplace + the Extension Contract v1. Semver-major.

**Run the pipeline with `/dev-pipeline:run <issue>`** — the `dev-pipeline` plugin's flagship `run` skill (plugin = namespace, skill = action; consistent with the other toolkits).

### Extension Contract v1 (all optional; defaults reproduce v1 behavior byte-for-byte)
- **EP-1 `stageParams`** — stage-prose constants promoted to config (`planFilePattern`, `requiredLabels`,
  `visualCapture{baseUrl,devServerCommand,smokeRoutes,viewports,triggerGlobs}`, `formatGlob`). New lockstep
  validator `check-config-shadowing.sh` guards against a published-but-unread key.
- **EP-2 `commands.<repo>.extraLanes`** — additive, blocking verify lanes; run after the SUITE trio, `when`-glob
  gated, results under namespaced `ext:<name>` keys, `failureClass` from the existing closed taxonomy. No advisory mode.
- **EP-3 extension-file manifest + `check-extensions.sh`** — fail-closed lint of `.claude/second-shift/` against a
  shipped manifest (a typo'd `blocker-mutants.md.md` is loud). Companion/repo-local extensions declared in a
  `.known-extensions` allowlist.
- **EP-4 named-agent `modelOverrides`** — the mutation executor is now the logical agent `mutation-executor`,
  its tier overridable via `reviewers.modelOverrides`. `check-model-tiers.sh` asserts the lookup.
- **EP-5 companion packs** — the org-overlay distribution contract (two-pin model, namespaced agents/workflows,
  `.known-extensions` vendoring). See `docs/extending.md`.
- **EP-6 `stageWorkflows`** — register a blocking Workflow as a gate-owned stage sub-step; new closed reason
  `ext-workflow-failed`; `ext:`-namespaced state only. **EP-7 `implementDelegates`** — route Stage-5 work items to
  a delegate agent; output flows through the unchanged scope + downstream gates.
- **EP-8 `planGates`** — additive Stage-4 plan-review gates: register a plan-reviewer agent that runs after the
  built-in plan gates; additive-only (a `block` maps to `plan-reviewer-block`, never waives a gate). Completes the
  additive-gate symmetry: `planGates` (Stage 4) · `extraLanes` (Stage 6) · `reviewers.add` (Stage 8).
- New consumer guide **`docs/extending.md`**; `extension-points.md` is its field reference; the disposition test
  is codified in `context-model.md`.

### Design-provider axis (breaking)
- **`gates.figma` → top-level `design: { provider: "figma" | "claude-design" }`** (key absent = design fidelity off).
  The **figma** adapter is now internalized as a first-class provider (Stage 1/3/4/5/8), no longer consumer glue.

### De-org: removals (capabilities move, they don't disappear)
- **`skills/playwright-cli` removed** from design-toolkit → restore repo-local under `.claude/skills/playwright-cli/`.
- **api-test tier removed** (`api-test-{coder,reviewer,plan-reviewer}` + `api-testing` skill + `api-tests.mjs` +
  `gates.apiTests`) → re-attach as a companion pack via EP-6/EP-7 + `.known-extensions`.

### Genericization (stack specifics move to `review-context.md`)
- **db-reviewer** engine-agnostic (relational + document stores); **pipeline-reviewer** queue-agnostic;
  **performance / complexity / maintainability / test-coverage** reviewers stack-neutral; **design-faithful**
  reads its stack from `design-tokens`; **intake-toolkit** honors `tracker.type` (github default + jira deltas).
- `plugin.json` corrected: design-faithful / figma-faithful are the **claude-design / figma provider adapters**
  (dropped the false "(generic)" label on design-faithful).

### Fixes
- **`paths.plansDir` is now honored** by Stage 3 (was published but ignored — the config-drift defect).
- Base-branch, format-glob, viewport, and label constants routed through config (EP-1) instead of hardcoded.
- De-anonymization: removed a shipped private-repo inventory, real GitHub App identifiers, and domain-fingerprint
  substance from the stock and its examples.
- `pipeline-doctor.sh` locates sibling-plugin selftests in both the monorepo and the version-keyed install-cache
  layout (previously reported spurious FAILs from the cache; the checks always passed).

### v1 → v2 migration (consumers)
1. Bump the marketplace `ref` and each `plugin.json` version pin to `v2.0.0`.
2. **`gates.figma: true` → `design: { provider: "figma" }`** — **except** a Claude-Design (DesignSync) shop, which
   is **`design: { provider: "claude-design" }`** (the old `gates.figma` flag did not imply figma).
3. **`gates.apiTests`**: remove; carry the api-test tier as a companion pack / repo-local agents+workflow and wire
   it via `implementDelegates` + `stageWorkflows`, declaring `api-testing/*.md` in `.claude/second-shift/.known-extensions`.
4. If you relied on `design-toolkit:playwright-cli`, restore it repo-local under `.claude/skills/playwright-cli/`.
5. Declare your stack in `.claude/second-shift/review-context.md` (database engine/ORM, queue broker, FE stack,
   toolchain) so the now-generic reviewers keep their prior review depth.
6. If you set `paths.plansDir`, note it is now honored — plans move to that directory.

## v1.1.1 and earlier
Pre-extensible-core history (per-plugin evolution) was not carried over in the 2026-07 tree recreation — v2.0.0 is the earliest commit in this repository's history.

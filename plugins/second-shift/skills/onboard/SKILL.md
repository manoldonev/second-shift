---
name: onboard
description: Onboard the current repo onto the second-shift marketplace - detects tracker/topology/commands with provenance, drafts the config for one accept-or-edit review, writes settings pin + config + lockfile, validates with config-lint. Run from the target consumer repo. Requires jq, gh (authenticated), git.
---

You are `/second-shift:onboard`. You write the consumer repo's second-shift configuration
**from evidence, not from interview answers**. You never guess: anything provable from
git/package.json/gh is detected; anything unprovable but optional is asked ONCE in a single
batch; anything unprovable and required is a written abort.

Hard rules:
- Never copy plugin content (skills/agents/hooks) into the consumer repo. You emit config,
  a settings block, a lockfile, and the thin presence-check + its SessionStart hook (the
  sanctioned no-vendoring exception: it verifies plugin presence, it is not plugin content).
- Never ask the human to type or open a plugin-cache path.
- Never weaken a failing config-lint: fix the config until the lint is green.
- All example values you print must be the repo's real detected values; placeholders only
  where detection returned null.

## Step 0 — Preconditions
Run: `command -v jq gh git`; `gh auth status`; `git rev-parse --show-toplevel`.
Missing prerequisite → stop, print the install/login command, done.
If `.claude/second-shift.config.json` already exists: this is a RE-onboard — diff mode.
Load the existing file, run detection anyway, and present changes against the existing
values in the review screen instead of a fresh draft.

## Step 1 — Detect (provenance-first)
Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/onboard/tools/detect.sh"` and parse the JSON.
- `git.baseBranch.value` empty → ABORT with: "Cannot determine the default branch:
  origin/HEAD is unset and ls-remote failed. Run `git remote set-head origin --auto`
  and re-invoke. I do not guess base branches." (fail-fast; never default to main.)
- `topology.value == "be-fe-pair-candidate"` → the sibling candidates go into the
  elicitation batch as a confirm question (pair vs standalone).
- `tracker.value == "ambiguous"` → tracker choice goes into the elicitation batch,
  presenting the evidence (origin host, MCP presence) for each option.

## Step 2 — Resolve the pin
Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/onboard/tools/pin-resolve.sh" manoldonev/second-shift dev-pipeline review-toolkit intake-toolkit audit-toolkit second-shift` — add `design-toolkit` if (and only if) the design question below is answered yes.
`refSource == "tag-fallback"` → include one line in the review screen: "(pinned to tag
<ref>; this marketplace has not cut a GitHub Release yet)". Resolution failure → ABORT
with the stderr reason (likely offline or gh unauthenticated).

**Canary mode (self-consumption):** if detection's `git.originUrl` points at the
marketplace repo itself (`manoldonev/second-shift`), do NOT pin the release: use
`ref: "main"` in the settings block and the lockfile, and set every lockfile `plugins`
value to the literal `"latest"` (doctor and the thin check treat `"latest"` as
presence-only — any installed version is correct by definition, so no PR ever has to
touch the lockfile). This repo is the canary — it dogfoods every change; only real
consumers get the release pin. Say so on the review screen, and the consent doc must
state the canary exception explicitly.

## Step 3 — Draft + one-batch elicitation
Build the draft config from detection:
- `configVersion: 1`
- `tracker.type` from detection (or the elicited answer). JIRA → also set
  `"writes": false` in the draft (the documented JIRA default) — reviewable on the screen.
- `topology.type` + `topology.repos`: standalone/monorepo → single repo id (use the
  package.json `name` short form or directory basename), `path: "."`,
  `baseBranch` from detection. Confirmed pair → `be` + `fe` entries; the sibling's own
  baseBranch is detected by running detect.sh again with the sibling path as argument.
- `commands.<repo>` from detection: the emitted block contains EXACTLY these keys —
  `lint`, `lintAutofixes`, `typecheck`, `test`, `build`, `format` from detect.sh, PLUS
  `testFile`, `unitTestScope` always as explicit `null`
  (undetectable — their provenance comment reads "set when adopting the mutation
  gate"). **Undetected lanes are explicit `null`** — never omit, never invent.
  (Integration/API test tiers are NOT config command keys — removed in v2.1.6;
  ship them via `extraLanes` / extension points EP-6/EP-7. Never emit
  `integrationTest`/`apiTest` under `commands.<repo>`.)
Ask AT MOST one AskUserQuestion batch, containing ONLY (skip any that detection settled):
  1. tracker (only if ambiguous — show evidence per option)
  2. topology pair confirm (only if be-fe-pair-candidate)
  3. `tracker.branchPrefix` (recommended: `claude/<repo-basename>-` for github; `<user>/` for jira)
  4. gates to enable (**mutation** — defaults false; `gates.mutation:false` is an explicit
     off-switch for the Stage-5 unit-test mutation gate even when `unitTestScope` is set.
     It is the ONLY `gates` key the schema has as of v2.1.6 — `costTracking` was removed
     (cost attribution now runs unconditionally, passive) — never emit anything else under `gates`)
  5. design fidelity, two-part (only if detection saw a UI-shaped repo — sibling FE candidate,
     or framework deps like react/vue/svelte in package.json — or a design MCP in
     `claude mcp list`): include design-toolkit? If yes, WHICH provider — emit top-level
     `design: { "provider": "figma" }` or `{ "provider": "claude-design" }`.
     Declined or not UI-shaped → NO `design` key at all (absent = off).
     When design is accepted, also detect a render harness (#84): a `render:verify` script in
     the FE repo's package.json (or a script whose usage names `--route`/`--out`). Detected →
     offer `design.liveRender` pre-filled (`command: "yarn render:verify --route {route} --out {out}"`,
     `cwd: <fe repo id>`); the operator may add `readyProbe`. Undetected or declined → omit the
     `liveRender` key (the Stage-5 gate degrades to render-verify-unavailable; docs/live-render.md).
  6. reviewer deltas (`reviewers.add` for repo-local reviewer agents, `.remove` for shipped
     reviewers that don't fit — e.g. db-reviewer in an FE repo —, `.modelOverrides`).
     Recommended default: none. Emit the `reviewers` key ONLY when the answer is non-empty.
  7. **github tracker only — the first-run wall, absorbed here:**
     a. Bot identity: "Use a GitHub-App bot identity for pipeline writes? (Needs an App +
        private key; the pipeline pre-flight enforces the wrapper unconditionally for the
        github tracker.)" If yes, point at the dev-pipeline bot bootstrap
        (`install-gh-bot.sh` in the dev-pipeline tools) as the follow-up; if no, note that
        the first `/dev-pipeline:run` pre-flight will fail until one exists — this is a
        pipeline requirement, not an onboard requirement.
     b. Queue labels: "Create the six required queue labels now?" On yes, print AND run:
        `gh label create ready-for-dev`, `needs-spec-work`, `needs-plan-review`,
        `needs-intake-review`, `in-progress`, `epic` (skip ones that already exist).
        Note on the screen: these six are shipped literals until the marketplace makes
        `stageParams.requiredLabels` authoritative end-to-end.
  8. **`review-context.md` scaffold (accept-or-edit, never mandatory; default "later").**
     Offer to scaffold a starter `.claude/second-shift/review-context.md` so reviewers key on
     named sections instead of inferring from the diff. **The offer default is "later"** —
     onboarding stays green without it. Hard rules if accepted:
     - Emit **only sections whose content the human confirmed in this batch** — never a
       TODO-bodied heading (`scaffold-review-context.sh` refuses empty bodies; a present-but-
       hollow section is a fake policy reviewers quote back).
     - **Never scaffold `## Maturity stage` with example text** — a maturity declaration is a
       severity waiver; write it only from the human's real posture, else omit it.
     - `detect.sh` detects tracker/topology/pkg-manager/lanes — **not** stack/ORM — so every
       section body is elicited, not auto-filled; a value you can only guess goes in as a
       pointer line, not a fabricated fact.
     - Never regenerate: the tool refuses when the file already exists.
     Section names + readers come from the catalog (`docs/extension-points.md` "Authoring the
     review-context surface"). To write it, pipe confirmed H2 blocks to
     `bash "<installPath>/skills/onboard/tools/scaffold-review-context.sh" <repo-root> --title "<repo>"`,
     then run `check-review-context-sections.sh --preflight <repo-root>` to confirm it is clean.
  9. **CI evidence workflow (offer; the server-side backstop):** "Emit a consumer-repo CI
     workflow that, on every PR, (a) config-lints the committed config with the linter
     shipped AT the pinned marketplace ref and (b) asserts the settings ref and lockfile
     ref agree — so a half-done upgrade PR is caught server-side?" Recommended: yes for a
     repo that runs GitHub Actions. On yes, the two files below are emitted in Step 7; note
     that the workflow only REPORTS a red check — to make it *block* merges, the repo admin
     marks "second-shift evidence" a required status check in branch protection (onboard
     never edits branch protection). On no / a non-Actions repo, emit nothing (absent = off).
Then present the **complete draft as one accept-or-edit screen**: a JSONC block where every
line carries a provenance comment, e.g.
    "baseBranch": "alpha",        // from origin/HEAD
    "test": null,                 // no scripts.test in package.json — pipeline will skip this lane
The human accepts or edits values; loop the screen until accepted. This is a diff review
of a 90%-correct document, not a wizard.

## Step 4 — Emit `.claude/second-shift.config.json`
Write the accepted config as PURE JSON (comments stripped) with a `$schema` first key:
    "$schema": "https://raw.githubusercontent.com/manoldonev/second-shift/<ref>/schema/second-shift.config.schema.json"
(<ref> = the pinned ref from Step 2 — live editor validation forever, at the right version.)

## Step 5 — Validate in a loop
Resolve config-lint: `claude plugin list --json | jq -r '[.[] | select(.id=="dev-pipeline@second-shift")] | sort_by(.lastUpdated) | last | .installPath // empty'`.
- Found → `bash "<installPath>/skills/run/tools/config-lint.sh" .claude/second-shift.config.json`
- Not installed yet (normal on first onboard) → fetch the SAME file at the pinned ref:
  `gh api "repos/manoldonev/second-shift/contents/plugins/dev-pipeline/skills/run/tools/config-lint.sh?ref=<ref>" --jq .content | base64 --decode > "$TMPDIR/config-lint.sh"` and run that.
  (Any ref onboard can resolve is ≥ v2.1.0 — the first release that ships onboard also ships
  the `$schema`-aware config-lint, so the fetched lint always accepts the emitted config.)
Non-zero → fix the config (asking the human only if the fix needs a decision), re-run.
Loop until `config-lint: OK`.

## Step 6 — Settings: marketplace pin + blessed bundle
Target state in `.claude/settings.json` (MERGE — never clobber unrelated keys):
    "extraKnownMarketplaces": { "second-shift": { "source": { "source": "github", "repo": "manoldonev/second-shift", "ref": "<ref>" } } }
    "enabledPlugins": { "dev-pipeline@second-shift": true, "review-toolkit@second-shift": true,
                        "intake-toolkit@second-shift": true, "audit-toolkit@second-shift": true,
                        "second-shift@second-shift": true }
    (+ "design-toolkit@second-shift": true when accepted)
Mechanics: read the existing file (or start from `{}`), apply
    jq --arg ref "<ref>" '.extraKnownMarketplaces = ((.extraKnownMarketplaces // {}) + {...}) | .enabledPlugins = ((.enabledPlugins // {}) + {...})'
and WRITE the result back with the file-editing tool. If the write is blocked or denied:
write the full merged document to `.claude/settings.json.second-shift-proposed` instead and
print: "Live settings write was blocked. Review and apply:
`mv .claude/settings.json.second-shift-proposed .claude/settings.json` (or merge by hand if
you had local content), then restart the session."
(Installing a plugin via the CLI writes ONLY `enabledPlugins` — never the marketplace pin —
so this settings block is what protects teammates; it is load-bearing, not convenience.)

## Step 7 — Emit `.claude/second-shift.lock.json`
Exactly the lockfile schema v1 (the contract /second-shift:doctor and consumer CI read):
    { "lockfileVersion": 1,
      "marketplace": { "name": "second-shift", "repo": "manoldonev/second-shift", "ref": "<ref>" },
      "plugins": { "<name>": "<version>", ... },
      "generatedBy": "second-shift:onboard@<this plugin's version>" }
`plugins` = the pin-resolve `plugins` map verbatim — exact plugin.json versions AT the
pinned ref, never local cache values. `design-toolkit` appears only when accepted.

Also emit the thin check (presence-verification, the sanctioned no-vendoring exception):
1. Copy `${CLAUDE_PLUGIN_ROOT}/templates/consumer/second-shift-doctor.sh` to
   `.claude/tools/second-shift-doctor.sh` (create the dir; keep the executable bit).
2. Merge into `.claude/settings.json` (same merge mechanics + .proposed fallback as Step 6):
       "hooks": { "SessionStart": [ { "hooks": [ { "type": "command",
         "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/tools/second-shift-doctor.sh\"",
         "timeout": 10 } ] } ] }
   MERGE rule: if a SessionStart array already exists, APPEND the entry — never replace.
3. Tell the human these two files get committed with the config + lockfile.

Also emit the consent doc:
1. Copy `${CLAUDE_PLUGIN_ROOT}/templates/consumer/SECOND-SHIFT.md` to `.claude/SECOND-SHIFT.md`,
   substituting `{{REF}}` with the pinned ref and `{{PLUGIN_LIST}}` with the comma-separated
   backticked names of the enabled plugins from the lockfile's `plugins` map — names only,
   never versions: the lockfile owns those, and a rendered copy drifts on every release.
   Strip the design-toolkit section when design-toolkit was not accepted.
2. If the repo has a `CLAUDE.md`, offer (in the SAME final message — never a new interview,
   never silently): append `- Toolkit consent + inventory: .claude/SECOND-SHIFT.md` to it.

Also emit the CI evidence workflow — **only when accepted in Step 3 item 8** (skip this
entire block otherwise; it is opt-in, not part of the default emitted set):
1. Copy `${CLAUDE_PLUGIN_ROOT}/templates/consumer/second-shift-ci-check.sh` to
   `.claude/tools/second-shift-ci-check.sh` (create the dir; keep the executable bit) and
   `${CLAUDE_PLUGIN_ROOT}/templates/consumer/second-shift-ci.yml` to
   `.github/workflows/second-shift-ci.yml`. Both are copied **verbatim** — the check script
   reads the marketplace `repo` and `ref` from the committed lockfile at runtime, so there
   is nothing to substitute at emit time.
2. Tell the human: these two files get committed with the config + lockfile; the workflow
   runs `jq` + `gh` on every PR (both preinstalled on `ubuntu-latest`; `gh` uses the
   built-in `github.token`) and reports a red check on a half-done upgrade. To make that
   check **block** merges, mark "second-shift evidence" a required status check in this
   repo's branch protection — onboard emits the file but never configures branch protection.

## Step 8 — Verify and hand off
1. Run `claude plugin list` and `claude plugin marketplace list --json`, and check the
   second-shift marketplace registration: if a USER-scope registration of `second-shift`
   exists WITHOUT a ref while the project pins one (jq: `.[] | select(.name=="second-shift")
   | .ref // empty` is empty for that entry), warn:
   "Your user-level marketplace registration is ref-less and shadows the project pin ON
   THIS MACHINE ONLY — teammates are protected by the project ref. `/second-shift:doctor`
   tracks this."
2. Print the install commands for whatever the bundle needs that `claude plugin list --json`
   shows as not installed at this project:
   `claude plugin install <p>@second-shift --scope project` (one per missing plugin).
3. Print the paste-ready CONTRIBUTING snippet:
       ## second-shift toolkit
       This repo uses the second-shift plugins (see .claude/second-shift.lock.json for
       pinned versions). On first open, Claude Code will prompt you to trust the workspace
       and install the marketplace + plugins — accept the prompts. If you skipped them:
       `claude plugin install dev-pipeline@second-shift --scope project` (repeat per plugin).
       Health check: `/second-shift:doctor`.
4. State the restart verdict plainly: "Restart this Claude Code session after installing
   plugins — component registration happens at session start."
5. **Run the read-only preflight — the onboarding finish line.** Resolve the dev-pipeline
   install path (never a cache path from memory):
   `claude plugin list --json | jq -r '.[] | select(.id == "dev-pipeline@second-shift") | .installPath'`,
   then run `bash "<installPath>/skills/run/tools/preflight.sh"` from the repo root. It is
   zero-write (no claim, no branch/worktree, no push, no tracker comment): target echo,
   config gates, the environment doctor, one tracker READ, one pass over every non-null
   command lane, and a report at `.claude/pipeline-state/preflight-report.md`. Surface the
   report's verdict; exit code = failed checks. On FAILs, fix and re-run before handing off.
   (If the dev-pipeline plugin is not installed yet — restart pending — print the two
   commands above as the post-restart step instead.) Then print the first-run
   instructions: pick a small ticket with no external-infrastructure ACs;
   `tracker.branchPrefix` is already set (skips branch-identity derivation); the
   bot/labels wall was already handled in Step 3 for the github tracker; run
   `/dev-pipeline:run <ticket>`.
6. Remind: commit `.claude/settings.json`, `.claude/second-shift.config.json`,
   `.claude/second-shift.lock.json`, `.claude/tools/second-shift-doctor.sh`, and
   `.claude/SECOND-SHIFT.md` in one PR — **plus**, only if the CI evidence workflow was
   accepted (Step 3 item 8), `.github/workflows/second-shift-ci.yml` and
   `.claude/tools/second-shift-ci-check.sh` in the same PR.

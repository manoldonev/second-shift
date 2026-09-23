---
name: onboard
description: Onboard the current repo onto the second-shift marketplace - detects tracker/commands with provenance, drafts the configVersion 3 config for one accept-or-edit review, writes settings pin + config + lockfile + the consent doc (and, on request, the unclaim workflow), validates with config-lint. Run from the target consumer repo. Requires jq, gh (authenticated), git, claude.
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
An existing `configVersion` 2 config is migrated by the same pass: the draft is the v3 shape
(Step 3), the diff guard lists the removed keys as `retired[]`, and the review screen points at
`docs/migrations/v2-to-v3.md`.

## Step 1 — Detect (provenance-first)
Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/onboard/tools/detect.sh"` and parse the JSON.
- `tracker.value == "ambiguous"` → tracker choice goes into the elicitation batch,
  presenting the evidence (origin host, MCP presence) for each option.
- `topology` is evidence only — the config has no topology. Non-empty
  `topology.siblingCandidates` means a sibling checkout (e.g. the frontend of this backend) sits
  next door: say so on the review screen and offer its own onboard at Step 8. Every checkout
  carries its own config.
- `git.baseBranch` is evidence only too: the lane bases its branch on the remote default branch
  (`origin/HEAD`, falling back to `origin/main`, then `origin/master`), so there is nothing to write.

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
Build the draft config from detection — the configVersion 3 shape, and only that:
- `configVersion: 3`
- `tracker.type` from detection (or the elicited answer). JIRA → also set
  `"writes": false` in the draft (the documented JIRA default) — reviewable on the screen.
  Say what it does on the screen: the pipeline never comments on or transitions the ticket,
  and `/dev-pipeline:run` starts its sessions without Atlassian write tools.
- **Never emit `topology`, `gates`, `stageParams` or `grillWaivers`, and never
  `design.liveRender.cwd` or `design.liveRender.tolerancePx`** — configVersion 3 removed them and
  config-lint rejects each by name (`docs/migrations/v2-to-v3.md`).
- `commands.<key>`, where `<key>` is this checkout's directory name —
  `basename "$(git rev-parse --show-toplevel)"`, or in a linked worktree the MAIN checkout's
  directory name (`git rev-parse --git-common-dir`, one level up). That is the key
  `/dev-pipeline:run` reads when there is more than one; a sole key is read whatever it is
  called, so a RE-onboard whose existing config has exactly one `commands` key keeps that key
  rather than renaming it. A repo with two independently-verified surfaces (e.g. an
  npm-workspaces repo with `apps/api` + `apps/web`) is still ONE entry: root fan-out scripts
  (`yarn workspaces foreach ...`) in `lint`/`test`, or, if the surfaces need distinct verify
  commands, `lanes` (setup steps; each may carry a `cwd` under the worktree) and `extraLanes`
  (path-triggered extra checks, e.g. contract tests scoped to one workspace).
- `commands.<key>` from detection: the emitted block contains EXACTLY these keys —
  `lint`, `typecheck`, `test`, `format` from detect.sh. **Undetected
  lanes are explicit `null`** — never omit, never invent. Each non-null `lint`, `typecheck`,
  `test` and `format` is a blocking check the scheduler runs after each build, so `lint` must
  not rewrite files: when detect's `lint` provenance says the script runs `--fix`, flag it on the
  review screen and ask for the non-mutating command.
  (Integration/API test tiers, and `build`, are NOT config command keys — ship them via
  `extraLanes`. Never emit `integrationTest`/`apiTest`/`build` under `commands.<key>`, never
  emit `testFile`/`unitTestScope`, and never `stageWorkflows`/`implementDelegates`/`planGates`
  — a draft carrying one self-rejects at config-lint.)
  `lanes` (setup steps) is deliberately NOT in that key list — detection cannot prove a
  repo's install command, so onboard never writes one. It is raised on the review screen
  instead (below), where the human can supply it.
- **Build tier → drafted `extraLanes` entry, not a `commands.<key>.build` key.**
  When detection's `commands.build.value` is non-null, draft one `extraLanes` entry —
  `{"name": "build", "commands": [<detected build command>], "failureClass": "TYPE_ERROR"}`
  — on the review screen with the same provenance comment style as every other drafted
  field, appended to (or starting) `commands.<key>.extraLanes`. This is a DRAFT like
  lint/test/format: the human can remove it on the accept-or-edit screen. `commands.build.value`
  being null (undetected) means no `extraLanes` entry is drafted — never fabricate a build
  command.
- **`reviewers.webComponentGlobs` when detected.** The grill below measures the repo's rendering
  surface: when its `T2.webComponentGlobs` finding names a candidate glob that matches tracked
  files, draft that glob into `reviewers.webComponentGlobs` (provenance: the grill's count) and
  re-run the grill. It is the trigger review-lead routes a11y-reviewer and the design-fidelity
  dimension on; the shipped default (`apps/web/**/*.{tsx,jsx}`) matches nothing in most repos.
  A repo with no rendering surface gets no key.
- **When detection returned no command lanes at all** (every one `null` — the normal
  outcome for a stack `detect.sh` does not cover: Python/pip/poetry/uv, bun, cargo, go),
  say so plainly on the review screen rather than presenting the empty table as done:
  a run with no configured check (and no `## Checks` in its intake record) ends red on its
  checks. Offer the two honest exits — fill in the repo's real commands now, or set
  `allowUnverified: true` to declare the zero-check opt-out deliberately.
Ask AT MOST one AskUserQuestion batch, containing ONLY (skip any that detection settled):
  1. tracker (only if ambiguous — show evidence per option)
  2. `tracker.branchPrefix` (recommended: `claude/<repo-basename>-` for github; `<user>/` for jira)
  3. design fidelity, two-part — **what it buys: review gains a design-fidelity dimension, and
     with `liveRender` every declared route is rendered after each build and smoke-checked for
     the value it must show, instead of a reviewer's opinion of a diff** (docs/extending.md
     §3.5; docs/live-render.md).
     (only if detection saw a UI-shaped repo — sibling FE candidate,
     or framework deps like react/vue/svelte in package.json — or a design MCP in
     `claude mcp list`): include design-toolkit? If yes, WHICH provider — emit top-level
     `design: { "provider": "figma" }` or `{ "provider": "claude-design" }`.
     Declined or not UI-shaped → NO `design` key at all (absent = off).
     When design is accepted, also detect a render harness: a `render:verify` script in
     this repo's package.json (or a script whose usage names `--route`/`--out`). Detected →
     offer `design.liveRender` pre-filled (`command: "yarn render:verify --route {route} --state {state} --out {out}"`);
     the command runs in the ticket worktree, so a harness in a subdirectory carries its own
     `cd`. Ask for `smokeCommand` (`{route}` and `{mustShow}` placeholders; it must exit
     non-zero unless the route shows that data-test id or copy string) — detection cannot prove
     one, and a record that declares a must-show value with no `smokeCommand` stops the run. The
     operator may add `readyProbe`, and may drop `{state}` if the harness cannot drive one.
     Undetected or declined → omit the `liveRender` key (a ticket whose record declares design
     frames then has nothing to render with; docs/live-render.md).
  4. reviewer deltas — **what they buy: `add` puts a reviewer that knows this repo's domain on
     every review panel; `remove` stops a shipped reviewer whose findings you always dismiss
     from spending a slot** (docs/extending.md §3.3).
     (`reviewers.add` for repo-local reviewer agents, `.remove` for shipped
     reviewers that don't fit — e.g. db-reviewer in an FE repo —, `.default` to put a
     reviewer the pipeline no longer dispatches by default back in this repo's rounds,
     `.modelOverrides`, `.tierMap`).
     Say on the screen what the default panel is: `/dev-pipeline:review` dispatches
     scope-completeness-reviewer only, so security-reviewer, a11y-reviewer and
     unit-test-mutation-reviewer do not run on a pipeline round unless listed in
     `reviewers.default` (or opted in per ticket by a `review panel` Decision Ledger row).
     Recommended default: none. Emit the reviewer deltas ONLY when the answer is non-empty
     (`reviewers.webComponentGlobs`, drafted above, is independent of this answer).
  5. **github tracker only — the first-run wall, absorbed here:**
     a. Bot identity: "Use a GitHub-App bot identity for pipeline writes? (Needs an App +
        private key.)" If yes, add `"bot": { "enabled": true }` under `tracker` in the draft —
        the wrapper reads that key and defaults to off — and point at the dev-pipeline bot
        bootstrap (`install-gh-bot.sh` in the dev-pipeline tools) as the follow-up. Say that
        with `enabled: true` and no working bot the run refuses rather than writing as the
        operator. If no, say the lane's claim, commits and PR are written as the operator's own
        `gh` identity.
     b. Queue labels: "Create the lane's eight labels now?" On yes, print AND run:
        `gh label create ready-for-dev`, `in-progress`, `epic`, `needs-spec-work`,
        `needs-plan-review`, `needs-intake-review`, `opus`, `sonnet` (skip ones that already
        exist). The first six are the defaults of `tracker.labels.queue`,
        `tracker.labels.claimed` and `tracker.labels.blockers`; a repo that sets those keys
        creates its own names instead. `opus` and `sonnet` are the sizing labels the scheduler
        reads for the build model: a ticket carrying neither stops before its first round.
  6. **`review-context.md` scaffold (accept-or-edit, never mandatory; default "later").**
     Offer to scaffold a starter `.claude/second-shift/review-context.md` so reviewers key on
     named sections instead of inferring from the diff. **What it buys: every panel reviewer
     self-loads it, so stack, severity calibration and known-accepted patterns are stated once
     instead of re-inferred — and re-argued — on every review** (docs/extension-points.md,
     "Authoring the review-context surface"). **The offer default is "later"** —
     onboarding stays green without it. Hard rules if accepted:
     - Emit **only sections whose content the human confirmed in this batch** — never a
       TODO-bodied heading: a present-but-hollow section is a fake policy reviewers quote back.
     - **Never scaffold `## Maturity stage` with example text** — a maturity declaration is a
       severity waiver; write it only from the human's real posture, else omit it.
     - `detect.sh` detects tracker/topology/pkg-manager/lanes — **not** stack/ORM — so every
       section body is elicited, not auto-filled; a value you can only guess goes in as a
       pointer line, not a fabricated fact.
     Section names + readers come from the catalog (`docs/extension-points.md` "Authoring the
     review-context surface"). To write it, pipe confirmed H2 blocks to
     `bash "<installPath>/skills/onboard/tools/scaffold-review-context.sh" <repo-root> --title "<repo>"`,
     then run `check-review-context-sections.sh --preflight <repo-root>` to confirm it is clean.
  7. **The unclaim workflow (github tracker only; ONE offer):** "Emit the consumer-repo unclaim
     workflow — on issue close, release the pipeline's claimed and queue labels, which nothing
     else does?" Recommended: yes for a repo that runs GitHub Actions. **What it buys: a closed
     issue releases its labels without anyone remembering to** (docs/team-rollout.md). Say that
     it **writes**, holding `issues: write` to remove two labels from one closing issue, and needs
     the repo's Actions workflow permissions set to read-and-write. On no / a non-Actions repo /
     a non-github tracker, emit nothing (absent = off). There is no other consumer CI workflow
     to offer: the lane's verdict is a PR comment, not a committed record a CI job could check.
Then present the **complete draft as one accept-or-edit screen**: a JSONC block where every
line carries a provenance comment, e.g.
    "lint": "yarn lint",          // from package.json scripts.lint
    "test": null,                 // no scripts.test in package.json — pipeline will skip this lane
    // "lanes": [{"name": "install", "commands": ["npm ci"]}],
    //                            ^ setup steps, run before every verify. A pipeline worktree
    //                              is a FRESH checkout with no node_modules/.venv (gitignored),
    //                              so add this if your verify lanes need installed deps.
    //                              Undetectable — supply it here or leave it out.
Render that `lanes` line with the install command of the package manager detection actually
found — `yarn install --immutable` for yarn, `pnpm install --frozen-lockfile` for pnpm, `npm ci`
for npm — rather than the `npm ci` literal above; showing a pnpm adopter an npm command is a
wrong-but-plausible suggestion. When `packageManager` is null (the stack detection does not
cover), omit the example command and point at the onboarding guide instead of guessing one.
The `lanes` line is review-screen guidance only: it is shown commented, and Step 4 emits the
accepted config as pure JSON, so a stub the human does not fill in is simply absent from the
file (`config-lint` runs `jq empty` and would reject a comment).

**Before you render the screen, GRILL the draft.** Write the draft config (pure JSON, comments
stripped — the same document Step 4 would emit) to a temp file, then run
`bash "${CLAUDE_PLUGIN_ROOT}/skills/onboard/tools/config-grill.sh" <repo-root> "$TMPDIR/second-shift-draft.json"`
and parse its JSON. It reports what `config-lint` structurally cannot: a capability that is
detectably OFF. Absence is legal for every optional key, so the lint never looks at the tree,
and nothing downstream looks either — a capability that is off simply never runs and the run
still reports green.

- Every entry in `findings[]` renders as a **warning line** at the top of the accept-or-edit
  screen: the finding's `evidence`, then its `proposal` verbatim. The proposal names the
  benefit; do not paraphrase it down to a key name, which motivates nobody.
- Findings are **advisory**: the human adopts the proposal or accepts the screen with the
  finding standing. There is no waiver key — declining is a choice made on this screen, and
  doctor keeps reporting the finding as a WARN.
- Every entry in `notEvaluated[]` renders as an informational line. It has no proposal.
- The checker **re-runs on each loop iteration**, so an adopted proposal visibly clears.

**On a RE-onboard, also DIFF the draft against the existing config.** Same temp file, one more
call:
`bash "${CLAUDE_PLUGIN_ROOT}/skills/onboard/tools/config-diff-guard.sh" .claude/second-shift.config.json "$TMPDIR/second-shift-draft.json"`
— and parse its JSON. On a FRESH onboard there is nothing to diff; skip it. The guard protects
every existing non-null value, because there is no discriminator for "human-authored": detection
emits nothing at all for the keys the audited regression destroyed, and for keys it does produce,
an existing value is indistinguishable from a prior run's detected one.

- Every entry in `deltas[]` renders as a **blocking line** alongside the grill's findings, with
  the entry's `evidence` then its `proposal` verbatim.
- Every entry in `unmatchedAcks[]` renders informationally and never blocks — it means an
  acknowledgment named a path no delta carries, so nothing was dispositioned.
- Every entry in `retired[]` renders informationally and never blocks: a leaf under a key
  configVersion 3 removed, which the draft cannot carry (`docs/migrations/v2-to-v3.md`). The
  one key that MOVED, `stageParams.webComponentGlobs`, is compared at
  `reviewers.webComponentGlobs` instead, so dropping its value is still a delta.
- The guard **re-runs on each loop iteration**, and "no unacknowledged deltas" is the accept
  predicate.
- A delta is cleared by fixing the draft, or — when the human confirms the removal or a genuine
  re-detection — by re-running with `--ack <path>` for that one path. Acks are exact, per-run, and
  write nothing. **Never `--ack` a path the human has not confirmed**: the flag is typed by you,
  and it is the only thing standing between a silent destruction and a seen one.
- **Exit 3 stops the onboard; it is never a skip.** Proceeding would write a draft over a config
  nothing compared it against. Exit 3 covers every usage and IO error, so read the **message** and
  never key the remedy off the code alone: only `not a single JSON object` names the config itself
  — most often one damaged into two documents by a doubled write or a botched conflict resolution
  — and only that one is the human's to repair. Every other shape (a missing file, a malformed
  invocation, a `--ack` with no value, a comparison that could not run) is this call being wrong,
  and is yours to fix and re-run. **Never propose replacing a config on an exit 3 whose message
  did not name it**: that would be this guard causing the destruction it exists to prevent.

This adds **no question batch and no new surface**. Disposition is captured by the human
editing the screen they are already editing — fixing the key, adopting a proposal, or
confirming the removal — so the "at most one AskUserQuestion batch" rule above and the "not a
wizard" framing below both stand unamended.

The human accepts or edits values; loop the screen until accepted. This is a diff review
of a 90%-correct document, not a wizard.

## Step 4 — Emit `.claude/second-shift.config.json`
Write the accepted config as PURE JSON (comments stripped) with a `$schema` first key:
    "$schema": "https://raw.githubusercontent.com/manoldonev/second-shift/<ref>/schema/second-shift.config.schema.json"
(<ref> = the pinned ref from Step 2 — live editor validation forever, at the right version.)

## Step 5 — Validate in a loop
Resolve config-lint: `claude plugin list --json | jq -r '[.[] | select(.id=="dev-pipeline@second-shift")] | sort_by(.lastUpdated) | last | .installPath // empty'`.
- Found → `bash "<installPath>/tools/config-lint.sh" .claude/second-shift.config.json`
- Not installed yet (normal on first onboard) → fetch the SAME file at the pinned ref:
  `gh api "repos/manoldonev/second-shift/contents/plugins/dev-pipeline/tools/config-lint.sh?ref=<ref>" --jq .content | base64 --decode > "$TMPDIR/config-lint.sh"` and run that.
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
If the existing file already sets a bundle plugin to `false`, flag it on the review screen: the
merge below writes `true` over it, and an opt-out is the repo's call.
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
Exactly the lockfile schema v1 (the contract /second-shift:doctor and the SessionStart presence check read):
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

Also emit the unclaim workflow — **only when accepted in Step 3 item 7** (skip this block
otherwise; it is opt-in, not part of the default emitted set): copy
`${CLAUDE_PLUGIN_ROOT}/templates/consumer/second-shift-unclaim.sh` to
`.claude/tools/second-shift-unclaim.sh` (keep the executable bit) and
`${CLAUDE_PLUGIN_ROOT}/templates/consumer/second-shift-unclaim.yml` to
`.github/workflows/second-shift-unclaim.yml`. **Verbatim**: the script resolves
`.tracker.labels.claimed` and `.tracker.labels.queue` from the committed config at run time, so
a name substituted at install would only be a rendered copy that drifts. Tell the human it holds
`issues: write` and removes those two run-state labels from one closing issue (never `blockers`,
which holds permanent classifications like `epic`), and that nothing else releases them: the
labels go stale when the item CLOSES, and no lane session is guaranteed to be running at that
moment — a hand-closed item never had one. Also say that a `permissions:` block only narrows the
repo maximum — a repo whose Actions workflow permissions are read-only must switch to
read-and-write, or the removal 403s (visibly, as a red run).

A RE-onboard whose repo still carries `.github/workflows/second-shift-ci.yml`,
`.claude/tools/second-shift-ci-check.sh` or `second-shift-delta-guard.*` flags them on the
review screen for deletion: they read a verdict record the lane no longer writes
(`/second-shift:doctor` FAILs on them too).

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
   First run `bash "${CLAUDE_PLUGIN_ROOT}/skills/doctor/tools/scope-shadows.sh"` — for any
   plugin it reports `user-served` or `shadowed`, print
   `<p>: served at user scope (<version>) — no project install needed` **instead of** that
   plugin's install line. A user-scope record already satisfies the lockfile, so the install
   would only mint a per-repo record that then rots behind it. Say it rather than skipping
   silently: a silent skip is indistinguishable from "nothing was missing".
3. Print the paste-ready CONTRIBUTING snippet:
       ## second-shift toolkit
       This repo uses the second-shift plugins (see .claude/second-shift.lock.json for
       pinned versions). On first open, Claude Code will prompt you to trust the workspace
       and install the marketplace + plugins — accept the prompts. If you skipped them:
       `claude plugin install dev-pipeline@second-shift --scope project` (repeat per plugin).
       Health check: `/second-shift:doctor`.
4. State the restart verdict plainly: "Restart this Claude Code session after installing
   plugins — component registration happens at session start."
5. **Dry-run the lane — the onboarding finish line.** Once dev-pipeline is installed and the
   session restarted, pick a small queued ticket with no external-infrastructure ACs and run
   `/dev-pipeline:run <ticket> --dry-run`: it validates the config, checks the intake record,
   the lane's commands and the design declaration, then prints the branch, worktree, record and
   checks it would use, with no claim, no branch, no push and no tracker read or write (the
   ticket's state, labels and model are read only on a real launch; the checks and the smoke
   run only in a round). Surface its `terminal:` line; fix and re-run on any refusal. (If the plugin is not
   installed yet — restart pending — print that as the post-restart step instead.) Then print
   the first-run instructions: `tracker.branchPrefix` is already set; the bot/labels wall was
   already handled in Step 3 for the github tracker; run `/intake-toolkit:intake <ticket>`
   first — it puts the open decisions to the human, writes the intake record the lane commits
   as the branch's first commit, and on the github tracker applies the `ready-for-dev` label the
   lane requires (without it the scheduler exits 3, not-queued) — then `/dev-pipeline:run <ticket>`.
6. Remind: commit `.claude/settings.json`, `.claude/second-shift.config.json`,
   `.claude/second-shift.lock.json`, `.claude/tools/second-shift-doctor.sh`, and
   `.claude/SECOND-SHIFT.md` in one PR — **plus**, when the unclaim workflow was accepted at
   Step 3 item 7, `.github/workflows/second-shift-unclaim.yml` +
   `.claude/tools/second-shift-unclaim.sh` in the same PR.
7. **Sibling candidates → offer the sibling's own onboard.** When detection reported
   `topology.siblingCandidates`, print: "The sibling repo needs its own onboard for
   `/dev-pipeline:run`: `cd <sibling path>`, then run `/second-shift:onboard` there. Each checkout
   carries its own config, keyed by its own directory name, and a ticket runs from the checkout
   of the repo it belongs to — the lane routes by the directory it is launched in." Offer to `cd`
   and re-invoke onboard on the sibling now if the session can reach that path; otherwise leave
   it as the next step.

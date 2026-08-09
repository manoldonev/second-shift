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
`audit-toolkit` is not an optional bundle member alongside `dev-pipeline`: it ships the hook that
writes the per-session audit ledger, and the lean lane's entry gate refuses to start without a
live one. State that on the review screen, so the human knows why this one has no opt-out.
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
- `configVersion: 2`
- `tracker.type` from detection (or the elicited answer). JIRA → also set
  `"writes": false` in the draft (the documented JIRA default) — reviewable on the screen.
- `topology.type` + `topology.repos`: standalone/monorepo → single repo id (use the
  package.json `name` short form or directory basename), `path: "."`,
  `baseBranch` from detection. Confirmed pair → `be` + `fe` entries; the sibling's own
  baseBranch is detected by running detect.sh again with the sibling path as argument.
  **`monorepo` always takes exactly one `repos` entry with `path: "."`** —
  `config-lint` rejects a second entry. A repo with two independently-verified
  surfaces (e.g. an npm-workspaces repo with `apps/api` + `apps/web`) is NOT
  `be-fe-pair` unless it actually is a backend/frontend pair — model it as a
  single monorepo id with root fan-out scripts (`yarn workspaces foreach ...`)
  in `commands.<id>.lint`/`test`, or, if the two surfaces need distinct
  verify commands, via `commands.<id>.lanes` (parallel setup/verify lanes) and
  `commands.<id>.extraLanes` (path-triggered extra tiers, e.g. contract tests
  scoped to one workspace).
- `commands.<repo>` from detection: the emitted block contains EXACTLY these keys —
  `lint`, `lintAutofixes`, `typecheck`, `test`, `format` from detect.sh, PLUS
  `testFile`, `unitTestScope` always as explicit `null`
  (undetectable — their provenance comment reads "set when adopting the mutation
  gate"). **Undetected lanes are explicit `null`** — never omit, never invent.
  (Integration/API test tiers, and `build`, are NOT config command keys — removed in
  v2.1.6 / #113 respectively; ship them via `extraLanes` / extension points EP-6/EP-7.
  Never emit `integrationTest`/`apiTest`/`build` under `commands.<repo>`.)
  `lanes` (setup steps) is deliberately NOT in that key list — detection cannot prove a
  repo's install command, so onboard never writes one. It is raised on the review screen
  instead (below), where the human can supply it.
- **Build tier → drafted `extraLanes` entry, not a `commands.<repo>.build` key (#113).**
  When detection's `commands.build.value` is non-null, draft one `extraLanes` entry —
  `{"name": "build", "commands": [<detected build command>], "failureClass": "TYPE_ERROR"}`
  — on the review screen with the same provenance comment style as every other drafted
  field, appended to (or starting) `commands.<repo>.extraLanes`. This is a DRAFT like
  lint/test/format: the human can remove it on the accept-or-edit screen, satisfying the
  "opt-in" framing without a separate elicitation question. `commands.build.value` being
  null (undetected) means no `extraLanes` entry is drafted — never fabricate a build
  command. A RE-onboard (Step 0 diff mode) whose existing config still carries a dead
  `commands.<repo>.build` key flags it for removal on the same review screen, pointing at
  this replacement (`docs/migrations/v1-to-v2.md`).
- **When detection returned no command lanes at all** (every one `null` — the normal
  outcome for a stack `detect.sh` does not cover: Python/pip/poetry/uv, bun, cargo, go),
  say so plainly on the review screen rather than presenting the empty table as done:
  the pipeline verifies nothing until at least one lane is filled in, and `preflight`
  will withhold its `pipeline-ready` verdict until then. Offer the two honest exits —
  fill in the repo's real commands now, or set `allowUnverified: true` to declare the
  zero-lane opt-out deliberately.
Ask AT MOST one AskUserQuestion batch, containing ONLY (skip any that detection settled):
  1. tracker (only if ambiguous — show evidence per option)
  2. topology pair confirm (only if be-fe-pair-candidate)
  3. `tracker.branchPrefix` (recommended: `claude/<repo-basename>-` for github; `<user>/` for jira)
  4. gates to enable — **what mutation buys: it breaks your changed code on purpose and fails
     when the unit specs still pass, which is the difference between tests that exist and tests
     that would catch a regression** (`docs/config-schema.md`, `gates` row).
     (**mutation** — defaults false; `gates.mutation:false` is an explicit
     off-switch for the Stage-5 unit-test mutation gate even when `unitTestScope` is set.
     It is the ONLY `gates` key the schema has as of v2.1.6 — `costTracking` was removed
     (cost attribution now runs unconditionally, passive) — never emit anything else under `gates`)
  5. design fidelity, two-part — **what it buys: review gains a design-fidelity dimension, and
     with `liveRender` a per-route rendered-vs-handoff receipt replaces a reviewer's opinion of
     a diff** (docs/extending.md §3.5; docs/live-render.md).
     (only if detection saw a UI-shaped repo — sibling FE candidate,
     or framework deps like react/vue/svelte in package.json — or a design MCP in
     `claude mcp list`): include design-toolkit? If yes, WHICH provider — emit top-level
     `design: { "provider": "figma" }` or `{ "provider": "claude-design" }`.
     Declined or not UI-shaped → NO `design` key at all (absent = off).
     When design is accepted, also detect a render harness: a `render:verify` script in
     the FE repo's package.json (or a script whose usage names `--route`/`--out`). Detected →
     offer `design.liveRender` pre-filled (`command: "yarn render:verify --route {route} --state {state} --out {out}"`,
     `cwd: <fe repo id>`); the operator may add `readyProbe`, and may drop `{state}` if the
     harness cannot drive one — the lean lane then refuses any ticket declaring a non-default
     render state. Undetected or declined → omit the `liveRender` key (the Stage-5 gate degrades
     to render-verify-unavailable, and a lean ticket cannot arm its design lane at all;
     docs/live-render.md).
  6. reviewer deltas — **what they buy: `add` puts a reviewer that knows this repo's domain on
     every review panel; `remove` stops a shipped reviewer whose findings you always dismiss
     from spending a slot** (docs/extending.md §3.3).
     (`reviewers.add` for repo-local reviewer agents, `.remove` for shipped
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
     named sections instead of inferring from the diff. **What it buys: every panel reviewer
     self-loads it, so stack, severity calibration and known-accepted patterns are stated once
     instead of re-inferred — and re-argued — on every review** (docs/extension-points.md,
     "Authoring the review-context surface"). **The offer default is "later"** —
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
  9. **CI workflows (ONE offer; the server-side backstop plus the close-out step):** "Emit the
     consumer-repo CI workflows — (a) on every PR, config-lint the committed config with the
     linter shipped AT the pinned marketplace ref and assert the settings ref and lockfile ref
     agree, so a half-done upgrade PR is caught server-side; and (b) on issue close, release
     the pipeline's claimed and queue labels, which nothing else does?" Recommended: yes for a
     repo that runs GitHub Actions. **What they buy: a half-done upgrade is caught server-side
     on the PR that ships it rather than by whoever happens to notice, and a closed issue
     releases its labels without anyone remembering to** (docs/team-rollout.md).
     **One question, one acceptance** — on yes both file pairs
     are emitted in Step 7. Say which side of the write boundary each falls on: the evidence
     workflow only REPORTS a red check (to make it *block* merges the repo admin marks
     "second-shift evidence" a required status check in branch protection — onboard never
     edits branch protection), while the unclaim workflow **writes**, holding `issues: write`
     to remove two labels from one closing issue, and needs the repo's Actions workflow
     permissions set to read-and-write. Under a non-github tracker the unclaim half is skipped
     — there is no label vocabulary. On no / a non-Actions repo, emit nothing (absent = off).
Then present the **complete draft as one accept-or-edit screen**: a JSONC block where every
line carries a provenance comment, e.g.
    "baseBranch": "alpha",        // from origin/HEAD
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
detectably OFF, and a capability that was never adopted at all. Absence is legal for every
optional key, so the lint never looks at the tree, and nothing downstream looks either — a
capability that is off simply never runs and the run still reports green.

- Every entry in `findings[]` renders as a **blocking line** at the top of the accept-or-edit
  screen: the finding's `evidence`, then its `proposal` verbatim. The proposal names the
  benefit; do not paraphrase it down to a key name, which motivates nobody.
- Every entry in `unadopted[]` renders as a **blocking line too**, identically — evidence, then
  proposal verbatim. These are the extension points nothing else in this skill mentions, so the
  screen is the only place they are ever named; a human who has never heard of them cannot
  decline them. Doctor renders the same entries as informational notes (an optional key at its
  default is not a defect); onboard blocks on them because here one edit closes it.
- Every entry in `notEvaluated[]` renders as an informational line. It is **not** a finding —
  it has no proposal, cannot be waived, and must never block acceptance.
- The checker **re-runs on each loop iteration**, and "no unwaived `findings[]` and no unwaived
  `unadopted[]`" is the accept predicate: the screen cannot be accepted while either is neither
  adopted nor waived.
- A waiver is a `grillWaivers` entry — `{"<check id>": "<reason>"}`, keyed by the entry's
  `id` — typed into the draft on that same screen. **Never author a reason on the human's
  behalf and never propose one**: an invented reason is a waiver with no accountability. Offer
  the mechanism, not the text.

This adds **no question batch and no new surface**. Disposition is captured by the human
editing the screen they are already editing — fixing the key, or typing the waiver entry — so
the "at most one AskUserQuestion batch" rule above and the "not a wizard" framing below both
stand unamended.

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
`audit-toolkit@second-shift` is written unconditionally, so onboard itself has no opt-out path to
close. What it cannot stop is a later hand edit flipping it to `false` (or a `settings.local.json`
overriding it): that breaks the lean lane outright — its entry gate refuses to start without a
live audit ledger — and `/second-shift:doctor` FAILs on the combination rather than warning.
If the existing file already carries that `false`, do not silently preserve it: flag it on the
review screen and merge the `true` in.
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

Also emit the CI workflows — **only when accepted in Step 3 item 9** (skip this entire block
otherwise; they are opt-in, not part of the default emitted set). One acceptance covers both
pairs; there is no second question:
1. **evidence:** copy `${CLAUDE_PLUGIN_ROOT}/templates/consumer/second-shift-ci-check.sh` to
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
3. **unclaim** (github tracker only): copy
   `${CLAUDE_PLUGIN_ROOT}/templates/consumer/second-shift-unclaim.sh` to
   `.claude/tools/second-shift-unclaim.sh` (keep the executable bit) and
   `${CLAUDE_PLUGIN_ROOT}/templates/consumer/second-shift-unclaim.yml` to
   `.github/workflows/second-shift-unclaim.yml`. **Verbatim** too: the script resolves
   `.tracker.labels.claimed` and `.tracker.labels.queue` from the committed config at run
   time, so a name substituted at install would only be a rendered copy that drifts. Tell the
   human this is the write half of the pair — it holds `issues: write` and removes those two
   run-state labels from one closing issue (never `blockers`, which holds permanent
   classifications like `epic`) — and that it is what keeps them from going stale on every
   merged ticket. Nothing else in either lane releases them: the lean lane's milestone 5
   requires an OPEN pr, so a session-side drop would fire while review is still in flight.
   Also say that a `permissions:` block only narrows the repo maximum — a repo whose Actions
   workflow permissions are read-only must switch to read-and-write, or the removal 403s
   (visibly, as a red run).

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
   `/dev-pipeline:run-lean <ticket>`.
6. Remind: commit `.claude/settings.json`, `.claude/second-shift.config.json`,
   `.claude/second-shift.lock.json`, `.claude/tools/second-shift-doctor.sh`, and
   `.claude/SECOND-SHIFT.md` in one PR — **plus**, per CI workflow accepted at Step 3 item 9,
   its pair in the same PR: `.github/workflows/second-shift-ci.yml` +
   `.claude/tools/second-shift-ci-check.sh` for evidence,
   `.github/workflows/second-shift-unclaim.yml` + `.claude/tools/second-shift-unclaim.sh`
   for unclaim.
7. **Confirmed pair → offer the sibling's own onboard, and say the FE rule out loud.** This
   run's `be-fe-pair` config (drafted at Step 3) is unchanged and still covers both sides for the
   deprecated staged lane. The lean lane needs more: `/dev-pipeline:run-lean` routes by
   invocation cwd and has no per-repo worktree map, so the sibling ALSO needs its own
   standalone onboard to be worked from its own checkout. Print: "The sibling repo needs
   its own onboard too, for `/dev-pipeline:run-lean`: `cd <sibling path>` (from the
   detected sibling candidates), then run `/second-shift:onboard` there. Detection reports
   `standalone` from that side, so it drafts its own independent config, bot identity, and
   worktrees dir with no further prompts. **FE-tagged tickets run `/dev-pipeline:run-lean`
   from the FE repo**, not from here. This leaves the FE command table in two places on
   purpose: `commands.fe` here, read only by the staged lane, and `commands.<fe-id>` in the
   FE repo's own config — the same table with nothing keeping the two in sync. Edit the FE
   repo's own copy; this one loses its last reader when the staged lane goes." Offer to `cd`
   and re-invoke onboard on the sibling now if the session can reach that path; otherwise
   leave it as the next step.

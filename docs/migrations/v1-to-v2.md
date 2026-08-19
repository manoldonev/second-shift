# v1 → v2 — the migration doc for both "v1 → v2" boundaries

**One filename, two version namespaces.** The marketplace release version and
`configVersion` are numbered independently, and both happen to cross their 1 → 2 boundary
here. `check-configversion-migration-doc.sh` derives this filename from the schema's
`configVersion` consts, so the configVersion migration must live at this exact path — and
the retroactive marketplace-v2.0.0 migration was already here. Rather than split the name,
both are documented below under explicit headings. Read the one that applies to you; a
consumer upgrading across both applies part 1 then part 2.

- [Part 1 — marketplace v1.x → v2.0.0](#part-1--marketplace-v1x--v200-extensible-core-retroactive) (key removals shipped on `configVersion: 1`)
- [Part 2 — configVersion 1 → 2](#part-2--configversion-1--2-plan-pattern-slice-token-retired) (the plan-pattern slice token retired)

---

# Part 1 — marketplace v1.x → v2.0.0 ("extensible core"), retroactive

v2.0.0 rebuilt the marketplace around the Extension Contract and removed two config keys
without bumping `configVersion` (the contract in [README.md](README.md) did not exist yet;
it binds from the onboarding release on). This doc is that missing migration, promoted from
the CHANGELOG's v2.0.0 section to a durable reference — `config-lint` points here when it
sees the removed keys.

## Field-by-field

### `gates.figma` → `design: { "provider": ... }` (moved + generalized)

Design fidelity is no longer a boolean Figma gate; it is a top-level `design` object whose
`provider` selects the implementation — and it is **not necessarily Figma**:

```jsonc
// before (v1)
"gates": { "figma": true }

// after (v2) — pick ONE provider
"design": { "provider": "figma" }          // needs a Figma MCP connection
"design": { "provider": "claude-design" }  // no external design tool
```

Key absent = design fidelity off. As of **dev-pipeline 2.1.6** (marketplace release v2.1.8) `gates` retains exactly one key:
`mutation` (see the dead-key removals below).

### Dead-key removals (dev-pipeline 2.1.6, marketplace v2.1.8) — `commands.<repo>.integrationTest` / `apiTest`, `gates.costTracking`

Three published keys had **zero readers** — a consumer set them and nothing happened. They are
removed; config-lint now rejects them with a migration pointer (fail closed).

- **`commands.<repo>.integrationTest` / `commands.<repo>.apiTest`** — never executed by any
  verify lane. Ship an integration/API test tier via **`commands.<repo>.extraLanes`** (an
  additive verify lane with a real `failureClass`, so failures get the correct fix budget)
  See [`extending.md`](../extending.md) §3.2. (This entry used to offer EP-6/EP-7 as a second
  route; those keys were themselves retired in #569, below — `extraLanes` is the route.)
- **`gates.costTracking`** — the mutation gate keyed off `unitTestScope` presence, and cost
  attribution ran unconditionally regardless of this flag; it toggled nothing in either
  direction. Removed. Local OTel cost attribution is now simply always-on (passive, never
  blocks). Delete the key from your config.

### Dead-key removal — `commands.<repo>.build` (#113)

`commands.<repo>.build` was detected by onboarding and accepted by config-lint, but
**never executed by any verify lane** — the same dead-key shape as `integrationTest`/`apiTest`
above. Removed; config-lint rejects it with a migration pointer.

- **`commands.<repo>.build`** — ship a build/compile tier via **`commands.<repo>.extraLanes`**
  (e.g. `{"name": "build", "commands": ["yarn build"], "failureClass": "TYPE_ERROR"}`) instead.
  `/second-shift:onboard` drafts this automatically when it detects a build command. See
  [`extending.md`](../extending.md) §3.2.

`gates.mutation` is now **wired as a real off-switch**: `false` disables the Stage-5 unit-test
mutation gate even when `commands.<host>.unitTestScope` is set (previously ignored).

### Staged-lane removal (#348) — `/dev-pipeline:run` and `stageParams.visualCapture`

The ten-stage `statectl` lane is deleted. `/dev-pipeline:run` no longer exists in releases from
this one on; the lean lane (`/dev-pipeline:run-lean`, and the `build-lean`/`review-lean` blocks
it schedules) is the only lane. **A consumer that still needs the staged lane keeps it by
pinning the marketplace to the last stage-carrying release** — the concrete version is named in
the release notes for this change and in #348.

Two consumer-visible consequences beyond the lane itself:

- **`stageParams.visualCapture` is removed.** It configured Stage 6's *advisory* smoke-capture
  (base URL, dev-server command, smoke routes, viewports, trigger globs), which observed and
  never gated. Its only consumer died with the stage, so it became a dead key: set it and
  nothing happens. config-lint now rejects it with a pointer here. The **blocking**
  design-fidelity check is a different key and is unaffected — see
  [`live-render.md`](../live-render.md) for `design.liveRender`, which the lean gate's milestone
  3 runs per ticket and receipts. Delete `stageParams.visualCapture` from your config; there is
  no replacement for the advisory capture itself.

- **Paths inside the dev-pipeline plugin moved.** Shared tooling left the deleted skill for the
  plugin root: `skills/run/tools/*` → **`tools/*`**, `skills/run/workflows/*` →
  **`workflows/*`**. This matters to exactly one thing a consumer owns: the CI template's
  config-lint fetch, which hardcodes the path at your pinned ref. If you vendored
  `second-shift-ci-check.sh`, update its lint path to
  **`plugins/dev-pipeline/tools/config-lint.sh`** in the same commit that moves your pin
  forward. Repinning without that edit fails the check with a fetch error, loudly — the
  template treats a moved linter path as drift by design.

`stageWorkflows` (EP-6), `implementDelegates` (EP-7) and `planGates` (EP-8) also lost their
dispatcher here — the stages were it. They were left schema-legal in this release and retired
one release later; see the next entry.

### Dead-key removal (#569) — `stageWorkflows` / `implementDelegates` / `planGates`

The three extension-point keys #348 left schema-legal are **removed**. config-lint rejects each
by name with a pointer here (fail closed). **Delete them from your config**; there is no
drop-in replacement, and no `configVersion` bump.

Leaving them legal was the more cautious-looking option and was the worse one. All three
register a **blocking** thing — a stage workflow, a plan gate, a delegate that must author a
surface. A consumer with a license scan in `stageWorkflows` upgraded past #348, saw no error,
and kept believing it ran. It did not. The `INERT` banner lived in a doc nobody re-reads on an
upgrade, so a rejection was the only mechanism that actually reached them — the same reasoning
that retired `stageParams.visualCapture` in the entry above. And the keys were not merely inert:
`check-extensions.sh` still fail-closed-validated their references at pre-flight, so a missing
delegate agent file could **block a run** on behalf of a dispatcher that no longer existed. That
arm is gone too.

- **`stageWorkflows`** — for a blocking check of your own, use **`commands.<repo>.extraLanes`**:
  an additive verify lane with a real `failureClass`, run by `lean-gate.sh` milestone 3.
- **`implementDelegates`** — the lean lane is outcome-gated and says nothing about *how* a diff
  is produced, so a build session may still dispatch the same specialist agent by choice. What
  has no replacement is the declared, config-routed, pre-flight-validated form.
- **`planGates`** — no replacement. There is no plan gate on the lean lane for one to be
  additive to; the spec is judged at the merge boundary by `review-lean`, after the diff exists.

The shape of all three is kept as a **design record** in [`extending.md`](../extending.md)
§3.6-3.8, because whether the lean lane grows a consumer-pluggable blocking gate is an open
product question. Removing a key is the breaking change and re-adding one is a minor, so the
retirement happened inside the window #348 already opened — if the answer later turns out to be
yes, a key comes back for free (and EP-6 would need a new one regardless: `stageWorkflows[].stage`
was an integer constrained `1..10`, and its addressing scheme *was* the ten deleted stages).

`/second-shift:onboard`'s `T1.extension-points` grill check went with them: it proposed adopting
one of the three, and after the retirement its only remaining exits were a rejected config or a
waiver. Nothing else about the grill changes, and no waiver you already carry becomes invalid —
`grillWaivers` accepts any check id.

### Dead-key removal (#574) — `commands.<repo>.unitTestScope` / `commands.<repo>.testFile`

The two mutation-engine keys are **removed**. config-lint rejects each by name with a pointer
here (fail closed). **Delete them from your config**; there is no drop-in replacement, and no
`configVersion` bump.

Their only functional reader was `workflows/mutation-gate.mjs` — the LLM-proposed-mutants
engine over co-located unit tests — which lost its dispatcher when #348 deleted the staged
lane and was retired in #574. A configured `unitTestScope` therefore armed **nothing**: the
same silently-disarmed-gate class as the #569 entry above, reached the same way (a consumer
upgraded past #348, saw no error, and kept believing their mutation gate ran).

- **`unitTestScope`** — the mutation seam is repo-carried now: ship an executable
  `tools/mutation-sweep.sh` at your repo root. (As of #580 it is repo-**run** too — wire it on
  your own merge boundary; the `lean-gate.sh` milestone-3 lane that used to run it is retired)
  (`--mode pr --base origin/<baseBranch>` — `docs/onboarding.md`).
  `gates.mutation` remains the declared intent (`false` is the explicit off-switch a reader
  can see); it is unchanged by this removal.
- **`testFile`** — the retired engine's per-spec runner template, read by nothing else. No
  replacement: a repo-carried sweep invokes its own runner however it chooses.

The advisory-mode remnant of the capability needs no key: review-lead routes
`unit-test-mutation-reviewer` off the diff itself (LLM-predicted, no execution). Whether an
execution-verified starter sweep ships for co-located-unit-test consumers is #482's open
question, unchanged by this removal.

### `gates.apiTests` → removed (extension point)

The API-test tier left the core. Ship it as **`commands.<repo>.extraLanes`** (the blocking
suite) plus **`reviewers.add`** (a domain reviewer for the tests), with any companion-pack
knowledge files declared in `.claude/second-shift/.known-extensions` — see
[`extending.md`](../extending.md) §5 for the full worked example. That example used to name two
further seams, `planGates` and `implementDelegates`; both were retired in #569 and are kept
there only as a design record.

### `design-toolkit:playwright-cli` → removed

If you relied on it, restore it repo-local under `.claude/skills/playwright-cli/` (it was
always a helper, not a gate).

### `paths.plansDir` → now honored

Previously published but ignored; v2 reads it. If you set it, plans move to that directory
on your first v2 run.

### `review-context.md` → declare your stack

The v2 reviewers are generic. Declare your stack (database engine/ORM, queue broker, FE
stack, toolchain) in `.claude/second-shift/review-context.md` so they keep their prior
review depth.

## Recipe

One PR: apply the field changes above, bump the settings `ref` + `.claude/second-shift.lock.json`
to the v2 tag together, then `claude plugin marketplace update second-shift` + reinstall,
re-run config-lint (`/second-shift:doctor` runs it for you), and re-run your validation gates.

---

# Part 2 — configVersion 1 → 2: plan-pattern slice token retired

`configVersion: 2` retires the `{slice}` token from `stageParams.planFilePattern`. The token
existed only to name the `-pr<N>` suffix of a stacked-PR slice; stacked PRs are retired, so
the token names nothing. It was a published, documented part of the config surface, so its
removal is a real breaking change rather than a silent default edit.

## What changed

The shipped default drops the token:

```jsonc
// before (configVersion 1)
"stageParams": { "planFilePattern": "{plansDir}/acme-{issueKey}{slice}.md" }

// after (configVersion 2)
"stageParams": { "planFilePattern": "{plansDir}/acme-{issueKey}.md" }
```

The surviving token vocabulary is `{plansDir}` (from `paths.plansDir`) and `{issueKey}`.

## What you do

1. Set `"configVersion": 2` in `.claude/second-shift.config.json`.
2. **If — and only if — you override `stageParams.planFilePattern`**, delete the `{slice}`
   token from your pattern. Most consumers set no override and have nothing to do here.

   ```jsonc
   // before
   "planFilePattern": "{plansDir}/plan-{issueKey}{slice}.md"
   // after
   "planFilePattern": "{plansDir}/plan-{issueKey}.md"
   ```

Everything else in the file is unchanged; `configVersion: 2` is otherwise
byte-compatible with `configVersion: 1`.

## If you forget step 2

Pattern substitution **strips unknown tokens defensively**: after the known tokens are
substituted, any remaining `{...}` token is removed rather than left in the resolved path.
An unmigrated override therefore still resolves to a valid plan path — `plan-42.md`, not
`plan-42{slice}.md`. No `config-lint` token check is added; the defensive strip is the
guarantee. Migrate anyway, so your config says what it means.

## Why config-lint rejects `configVersion: 1`

Version bounds are exact — one `configVersion` per plugin release. A config below the bound
fails with a pointer back to this doc rather than a bare "invalid", so an upgrade PR reviews
itself:

```
configVersion 1 predates this plugin (current: 2) — see docs/migrations/v1-to-v2.md for the upgrade path
```

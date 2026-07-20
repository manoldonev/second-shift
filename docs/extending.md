# Extending second-shift

How to bend the pipeline to your repo, your org, and your domain **without forking it** — and how to tell, before you write a line, whether what you want is even an extension.

This is the funnel. The exhaustive field-by-field surface lives in [`extension-points.md`](extension-points.md) (the reference this doc cites) and [`config-schema.md`](config-schema.md); where each thing belongs in the layered model is [`context-model.md`](context-model.md). Start here.

## 1. The one rule

Everything below is one axiom:

> **Extensions ADD evidence or ADD work. They never MINT evidence, reinterpret it, or WAIVE a gate.**

A green run means every gate passed on its own terms. A red run means one did not. An extension is allowed to *add a new gate* (more ways to go red) or *add a new source of evidence and work* (more that has to pass) — it is never allowed to make an already-red run go green by softening, reinterpreting, or skipping a check the plugin owns.

The pocket test:

> **If your change could make a red run green, fork. If it can only make a green run red, extend.**

Concretely, extensions **cannot**: disable a shipped reviewer from inside a knowledge file, rewrite the failure taxonomy, mark a failing lane advisory, mutate canonical pipeline state, or hand a gate a verdict it didn't compute. The two places that *can* subtract — `reviewers.remove` and `gates` — are config keys, so a subtraction is a one-line, reviewable, auditable diff in `.claude/second-shift.config.json`, never a side effect buried in prose. Everything additive is fail-closed: an unresolvable reference is a config-lint or pre-flight failure, not a silent skip.

Hold onto that and the rest of this document is just *which mechanism*.

## 2. Decision guide — which mechanism

You have a repo-, org-, or domain-specific need. Walk it down this list; the first row that fits is your answer.

| You want to… | Use | Layer | Blocking? |
| --- | --- | --- | --- |
| Change a **value** the plugin hardcodes (a path, a URL, a command, a label set, a plan-file name) | `stageParams` / `commands` / `paths` config | config | n/a |
| Add a **verify command** that must pass (a linter, a contract check, a custom test suite) | `commands.<repo>.extraLanes` (EP-2) | config | always |
| Add **domain knowledge** a shipped agent should read (blocker mutants, security rules, review context, design tokens, doc routing) | an **extension file** under `.claude/second-shift/` | knowledge | additive to that agent |
| Add a **whole new reviewer** dimension for this repo | a repo-local agent in `.claude/agents/` + `reviewers.add` | config + agent | it's a reviewer |
| Turn on **design-fidelity** review against Figma or Claude-Design | `design.provider` config | config | fail-closed gate |
| Run a **blocking workflow at a specific stage** (a schema-diff gate, a license scan, a codegen-drift check) | `stageWorkflows` (EP-6) | config → workflow | always |
| Route certain **Stage-5 implementation work** to a specialist agent | `implementDelegates` (EP-7) | config → agent | passes the normal gates |
| Add a **blocking plan-review gate** (a QA-tier plan review, an ADR-compliance check on the plan) | `planGates` (EP-8) | config → agent | additive, runs after the built-in Stage-4 gates |
| Ship any of the above **across many repos in your org**, versioned and pinned | a **companion pack** plugin (EP-5) that the config points at | its own plugin | per the mechanism it uses |

Two cuts make almost every decision:

- **Value vs knowledge vs behavior.** If two repos would differ on a *string*, it's config. If they'd differ on *prose* (why/how/gotchas), it's an extension file. If they'd differ on *what runs*, it's an extraLane, a stageWorkflow, a delegate, or a reviewer — all registered from config so the behavior change is auditable. (This is the litmus test from [`context-model.md`](context-model.md), applied.)
- **One repo vs the whole org.** A single repo's knowledge lives in that repo (`.claude/second-shift/`, `.claude/agents/`). Knowledge or agents shared across an org's repos get **packaged once** as a companion pack (§4) instead of vendored N times — the same disease this marketplace cures for the tooling, one layer up.

When two rows both seem to fit, prefer the **narrower, more auditable** one: config over a file, a file over an agent, a repo-local agent over a companion pack. Reach for a companion pack only when the duplication across repos is real.

## 3. Worked examples

One minimal example per extension point. Throughout, `acme` is a stand-in for your org or repo — substitute freely.

### 3.1 `stageParams` — reparameterize a shipped literal

Every `stageParams` key defaults to the plugin's current literal, so an empty config reproduces today's behavior byte-for-byte. Set only what differs.

```jsonc
{
  "stageParams": {
    "planFilePattern": "{plansDir}/plan-{issueKey}{slice}.md",   // drop the shipped "acme-" prefix
    "requiredLabels": ["ready", "in-progress"],                   // your tracker's label vocabulary
    "formatGlob": "*.{ts,tsx,css,md}",
    "webComponentGlobs": ["src/**/*.vue"],                        // Stage-8 a11y + design-fidelity trigger — set when the FE isn't React under apps/web
    "visualCapture": {
      "baseUrl": "http://localhost:5173/",
      "devServerCommand": "pnpm dev",
      "smokeRoutes": ["/", "/dashboard"],
      "viewports": ["mobile", "desktop"]
    }
  }
}
```

Pure parameterization — no ordering, no logic. A published key that no stage actually reads is caught by `check-config-shadowing.sh` (surface rot is a lint failure, not a silent no-op).

### 3.2 `extraLanes` — add a blocking verify command

You have a check the built-in lanes don't cover (a custom lint, a contract test, an i18n audit). Add it as an extra lane on the relevant repo:

```jsonc
{
  "commands": {
    "app": {
      "lint": "pnpm lint", "typecheck": "pnpm tsc --noEmit", "test": "pnpm test",
      "extraLanes": [
        {
          "name": "openapi-drift",
          "when": ["src/api/**", "openapi.yaml"],   // changed-file globs; absent = always run
          "commands": ["pnpm openapi:check"],
          "failureClass": "TEST_FAILURE"             // MUST be an existing taxonomy value
        }
      ]
    }
  }
}
```

Extra lanes run **sequentially after** the built-in SUITE lanes, never interleaving or replacing them; results land under a namespaced `ext:openapi-drift` key so canonical lane keys stay unreachable. There is no advisory mode: a lane blocks Stage-6 completion or it doesn't exist. `failureClass` must be one of the closed taxonomy values (`FORMAT`, `LINT_AUTOFIX`, `TYPE_ERROR`, `TEST_FAILURE`, `PLAN_CMD_FAILURE`, `INFRA`) — extensions borrow the taxonomy, they never extend it — and the lane gets the standard 2-attempt fix budget.

### 3.3 `reviewers.add` — a repo-local reviewer

A whole review dimension the shipped panel doesn't cover. Write the agent where agents live, register it in config:

```
.claude/agents/acme-orders-reviewer.md      # ordinary Claude Code agent frontmatter + prompt
```

```jsonc
{
  "reviewers": {
    "add": [
      { "name": "acme-orders-reviewer", "dimensions": ["order-lifecycle", "idempotency"] }
    ]
  }
}
```

review-lead now dispatches it alongside the shipped reviewers under the same confidence protocol; `dimensions` is a dedup/routing hint. `check-reviewer-references.sh` unions the plugin registry with your `reviewers.add`, so a registered agent with no file (or a file registered nowhere, or one shadowing a shipped reviewer name) fails the lint. Repo-local agents are referenced **bare**; that's how the two roots disambiguate ([`namespaces.md`](namespaces.md) rule 2). To *drop* a shipped reviewer instead (e.g. db-reviewer in a pure-FE repo), that's `reviewers.remove` — a subtraction, hence config, hence one auditable line.

### 3.4 Extension file — domain knowledge for a shipped agent

The shipped agents are domain-blind by design; you feed them domain knowledge through fixed, documented paths under `.claude/second-shift/`. Missing file = generic behavior, so this is purely additive.

```
.claude/second-shift/security-rules.md      # read by security-reviewer, treated as additive rules
.claude/second-shift/blocker-mutants.md      # extra blocker-class mutants for unit-test review
.claude/second-shift/review-context.md       # repo-wide calibration core + ownership pointers
.claude/second-shift/review-context/<r>.md   # per-reviewer rules (basename = registry reviewer name)
.claude/second-shift/doc-routing.md          # change-category → doc-path map for Stage-7 doc updates
```

Each consuming agent's prompt names its own file and loads it *if present*, treating the contents as additive — they can tighten review, never weaken the generic protocol. What files exist and who reads them is the table in [`extension-points.md`](extension-points.md); this is the "add evidence" half of the axiom in its purest form. Every file you drop here must match the shipped **extension manifest** or your own `.known-extensions` allowlist (§4.3), or `check-extensions.sh` fails closed — a typo'd `security-rules.md.md` is loud, not silently ignored. The *named sections inside* `review-context.md` (and `review-context/<r>.md`) are linted too: `check-review-context-sections.sh` matches your H2 headings against the shipped section catalog, so a drifted spelling (`## Maturity calibration` vs `## Maturity stage`) or an empty section body is caught at pre-work preflight — see [extension-points.md → Authoring the review-context surface](extension-points.md#authoring-the-review-context-surface).

One class of extension prose is subtractive **in effect** despite the additive surface: maturity-calibration claims ("no auth system exists yet") that reviewers honor as severity downgrades. A stale claim is a standing waiver no diff ever re-reviews — the pocket test failing with nobody having changed anything. Those claims must be declared as **verified calibration claims** (the fenced `second-shift-claims` block — grammar and failure classes in [`extension-points.md`](extension-points.md)): a mandatory `reverify-by` expiry that FAILs pre-flight when passed, plus optional declarative probes. The mechanism itself honors the axiom — it adds ways to go red and none to go green (a passing probe reports `not-yet-contradicted`, never "verified").

### 3.5 `design.provider` — turn on design-fidelity review

An opt-in axis, off unless the key is present:

```jsonc
{ "design": { "provider": "figma" } }        // or "claude-design"
```

`figma` selects the figma-faithful skills and requires a Figma MCP connection; `claude-design` selects the design-faithful / design-sync path and requires DesignSync. Same fail-closed posture as every gate: if the provider's prerequisite is missing at run time, the design steps fail closed rather than degrading silently. Absent key = a run behaves exactly like a non-design run. The design-system reference itself (component catalog, token roles) is knowledge — it lives in `.claude/second-shift/design-tokens/*.md`, an extension file per §3.4. To make the Stage-5 live-render verify gate actually execute (a repo-owned render command the gate screenshots through), add the optional `design.liveRender` block — see [`live-render.md`](live-render.md).

### 3.6 `stageWorkflows` — a blocking gate owned by you (EP-6)

You need something heavier than a verify command: a real workflow that runs at a chosen stage and blocks completion. A schema-compatibility gate before implementation, a codegen-drift check, a license scan.

```jsonc
{
  "stageWorkflows": [
    { "stage": 5, "name": "schema-compat", "workflow": "acme-platform:workflows/schema-compat.mjs" },
    { "stage": 6, "name": "license-scan",  "workflow": "tools/license-scan.mjs" }
  ]
}
```

The `workflow` is either `"<plugin>:<relpath>"` (a companion pack's script, §4) or a repo-relative path. It's dispatched **after** the stage's built-in sub-steps and **before** the stage-completion write, as a blocking sub-step — no advisory field, because advisory gates don't exist here. The result is recorded under `stageCheckpoint[N].extWorkflows[<name>]`; a failure produces the stage's standard fail-fast write with reason **`ext-workflow-failed`** (your name in the detail field). Registration lives in *consumer config* (auditable, per-repo), never in the plugin manifest. The workflow may write state **only** via `statectl` checkpoint payloads namespaced `ext:` — it adds evidence, it never reinterprets what the pipeline already recorded. An unresolvable reference is a config-lint failure.

### 3.7 `implementDelegates` — route Stage-5 work to a specialist (EP-7)

You want certain implementation work done by a specialist agent instead of the inline implementer — a migrations specialist for schema changes, a codegen agent for a generated surface.

```jsonc
{
  "implementDelegates": [
    { "surface": "db/migrations/**", "agent": "acme-platform:migration-writer" },
    { "surface": "unit",             "agent": "acme-unit-author" }
  ]
}
```

`surface` is a path glob or the reserved key `unit`; matching work items route to the delegate. The delegate's output then passes through the **unchanged** Stage-5 scope-enforcement gate and every downstream gate — it *adds work* (a different author) and *waives nothing*. `agent` is `"<plugin>:<agent>"` (a companion pack) or a bare repo-local agent name. An unresolvable agent fails closed at pre-flight.

### 3.8 `planGates` — a blocking plan-review gate (EP-8)

You want an extra reviewer of the *plan itself* at Stage 4 — a QA-tier review of the test strategy for a surface, an ADR-compliance check — that can block a bad plan before any code is written.

```jsonc
{
  "planGates": [
    { "name": "api-plan", "surface": "tests/api/**", "agent": "acme-qa-pack:api-test-plan-reviewer" }
  ]
}
```

Each plan gate runs **after** the built-in Stage-4 gates (plan-reviewer, design FE-spec, unit-test-plan) as an additive trinary reviewer over the plan; it appears in the gate ledger as `plan-gate:<name>`. `surface` (optional) scopes it — Stage 4 runs the gate only when the plan touches that glob. A `block` maps to the existing `plan-reviewer-block` reason (no per-extension enum value) — it can only make a passing plan-review *block*, never waive a built-in gate. This is the Stage-4 counterpart of `extraLanes` (Stage-6 verify) and `reviewers.add` (Stage-8 code review): the three additive-gate seams, one per gating stage. `agent` is `"<plugin>:<agent>"` or a bare repo-local name; unresolvable fails closed at pre-flight.

### 3.9 Companion pack — package the above for the whole org

When the extension files, reviewers, workflows, or delegate agents above would be copied across many of your repos, package them once as a companion pack plugin and point config at it. That's §4.

## 4. The companion-pack contract (EP-5 / EP-6 / EP-7)

A **companion pack** is your own private plugin — same distribution mechanics as second-shift, different visibility — that carries the org-wide half of your extension surface: shared domain reviewers, shared workflow scripts (EP-6 targets), shared delegate agents (EP-7 targets), and shared knowledge files. It's the concrete form of the "org/platform overlay" (layer 2) named in [`context-model.md`](context-model.md): author org knowledge once, version it, pin it, instead of vendoring it into every repo.

A consumer repo enables the companion pack alongside second-shift and then *references* its contents from `.claude/second-shift.config.json` — `stageWorkflows[].workflow: "acme-platform:…"`, `implementDelegates[].agent: "acme-platform:…"`, `reviewers.add` for its reviewers. The pack itself never edits a consumer's config; wiring is always the consumer's auditable choice.

### 4.1 The two-pin model

A companion pack sits *between* the public second-shift release and your repo's own knowledge, so a consumer pins **two** independent things:

1. **second-shift** — the public marketplace, pinned by marketplace `ref` + per-plugin `version` (the mechanism in [`onboarding.md`](onboarding.md)).
2. **the companion pack** — your private marketplace, pinned the same way, on its own release cadence.

They upgrade independently: bumping your org pack's domain rules is a companion-pack release and a one-line `ref` bump in the consumer, touching neither the public plugins nor unrelated repos. Both pins are the durable kind — marketplace `ref` so the catalog can't drift, plus the plugin `version` the install cache is keyed by.

### 4.2 Namespaced agents and workflows

Everything a companion pack exposes is addressed `<pack>:<name>`, exactly like the shipped plugins ([`namespaces.md`](namespaces.md)):

- **Agents** referenced from config carry the qualifier: `implementDelegates[].agent: "acme-platform:migration-writer"`, and a pack reviewer registered via `reviewers.add` is dispatched by its qualified name. (A repo-*local* agent stays bare — that's the disambiguation between the two roots.)
- **Workflows** referenced from `stageWorkflows[].workflow` use the `"<pack>:<relpath>"` form; the Workflow tool resolves it against the installed-plugin search path — never hard-code a filesystem path into another plugin.

The qualifier is what lets `check-reviewer-references.sh` and the pre-flight resolver tell "shipped", "companion", and "repo-local" apart, and what keeps a pack from silently shadowing a shipped name.

### 4.3 Vendoring the pack's knowledge files: `.known-extensions`

Extension *files* a companion pack expects under `.claude/second-shift/` (say an `api-testing/*.md` set the pack's reviewers read) won't match the plugin-shipped extension manifest, so `check-extensions.sh` would fail closed on them. The consumer declares them, additive-only and auditable, in a repo-maintained allowlist:

```
# .claude/second-shift/.known-extensions   (one glob per line)
api-testing/*.md
platform/*.md
```

`check-extensions.sh` unions these globs onto the shipped manifest. This keeps "missing extension = generic behavior" a *checked* contract — a stray or typo'd file is still loud — while letting your org's companion/repo-local files live legitimately alongside the shipped set. The allowlist widens what's *recognized*; it never widens what any file is *allowed to do* — extension files remain additive-only no matter where they came from.

---

## 5. End-to-end case study: an API-test QA tier

The single snippets above each touch one seam. Real capabilities compose several. Here's a worked case a QA-minded org actually wants: **black-box API tests as a first-class pipeline concern** — the plan's API-test strategy gets reviewed *before* code is written, the tests are authored by a specialist, the suite runs as a blocking gate, and the tests themselves get code-reviewed. That's four different gating stages, so it's four seams — packaged once as a companion pack, `acme-qa-pack`, and wired from each consumer's config.

**What the pack ships** (authored once, versioned, pinned — §4):
- `agents/api-test-plan-reviewer.md` — reviews the plan's API-test strategy (trinary verdict).
- `agents/api-test-coder.md` — a write-only agent that authors black-box tests under `tests/api/`.
- `agents/api-test-reviewer.md` — reviews the written test code.
- `skills/api-testing/` — the shared "how we write API tests here" playbook the agents load.

**What each consumer repo puts in `.claude/second-shift.config.json`** — one block, every stage of the tier registered and auditable:

```jsonc
{
  // Stage 4 — gate the PLAN: block a ticket whose API-test strategy is wrong before any code exists
  "planGates": [
    { "name": "api-plan", "surface": "tests/api/**", "agent": "acme-qa-pack:api-test-plan-reviewer" }
  ],
  // Stage 5 — WRITE: route API-test work to the specialist instead of the inline implementer
  "implementDelegates": [
    { "surface": "tests/api/**", "agent": "acme-qa-pack:api-test-coder" }
  ],
  // Stage 6 — RUN: the API suite is a blocking verify lane, gated to when API surface changed
  "commands": {
    "<repo-id>": {
      "extraLanes": [
        { "name": "api-tests", "when": ["src/**", "tests/api/**"],
          "commands": ["<the repo's API-test command, e.g. yarn test:api>"], "failureClass": "TEST_FAILURE" }
      ]
    }
  },
  // Stage 8 — REVIEW: the written tests get a domain code review
  "reviewers": {
    "add": [{ "name": "acme-qa-pack:api-test-reviewer", "dimensions": ["api-testing"] }]
  }
}
```

Plus the pack's harness reference, declared so the manifest lint recognizes it (§4.3):

```
# .claude/second-shift/.known-extensions
api-testing/*.md
```

**How it maps — one seam per gating stage:**

| Pipeline stage | Seam | What runs | Fails how |
| --- | --- | --- | --- |
| 4 — plan review | `planGates` (EP-8) | `api-test-plan-reviewer` judges the plan's test strategy | `block` → `plan-reviewer-block` |
| 5 — implement | `implementDelegates` (EP-7) | `api-test-coder` writes `tests/api/**` | output passes the unchanged scope + downstream gates |
| 6 — verify | `extraLanes` (EP-2) | the API suite runs | nonzero → `TEST_FAILURE`, standard budget |
| 8 — code review | `reviewers.add` | `api-test-reviewer` reviews the tests | its verdict folds into the review round |

Every one of these **adds** a gate or a unit of work; not one can waive a shipped check — an API-test tier can only make a green run *red* (a bad plan, a failing suite, a rejected review), which is exactly the fork-vs-extend line from §1. And because the wiring lives in the consumer's config, anyone auditing the repo sees the whole tier in one file — while the *implementation* (agents, skill) is versioned and pinned in the pack, bumped independently.

> **Two-pin note (phase 1 vs phase 2).** Under the phase-1 vendoring model, the pack's agents/skill are copied by hand into the repo's `.claude/agents/` and `.claude/skills/` (referenced **bare** — `api-test-plan-reviewer`, not `acme-qa-pack:api-test-plan-reviewer`), so every byte influencing a run is visible in the repo's own history; there is no sync command — the copy step belongs in the pack's install notes. The namespaced `acme-qa-pack:…` form shown above is the phase-2 live-resolution target. Either way the *config shape* is identical; only the reference form differs.

---

**In one breath:** config for values and switches; extension files to add evidence; planGates / extraLanes / reviewers to add a gate at each of the three gating stages, and stageWorkflows / delegates to add work — all registered from config so they're auditable; a companion pack to ship any of it across an org, two-pinned and namespaced. And through all of it: extensions add, they never subtract; if your change could turn a red run green, you wanted a fork.

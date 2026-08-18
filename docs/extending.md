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
| Add a **blocking check of your own** that must pass (a linter, a contract check, a custom test suite, a schema-diff gate, a license scan, a codegen-drift check) | `commands.<repo>.extraLanes` (EP-2) | config | always |
| Add **domain knowledge** a shipped agent should read (blocker mutants, security rules, review context, design tokens, doc routing) | an **extension file** under `.claude/second-shift/` | knowledge | additive to that agent |
| Add a **whole new reviewer** dimension for this repo | a repo-local agent in `.claude/agents/` + `reviewers.add` | config + agent | it's a reviewer |
| Turn on **design-fidelity** review against Figma or Claude-Design | `design.provider` config | config | fail-closed gate |
| Ship any of the above **across many repos in your org**, versioned and pinned | a **companion pack** plugin (EP-5) that the config points at | its own plugin | per the mechanism it uses |

**Three rows used to sit in that table and no longer do.** `stageWorkflows` (EP-6),
`implementDelegates` (EP-7) and `planGates` (EP-8) were dispatched by the ten-stage lane #348
deleted, and #569 retired the config keys: `config-lint` now rejects each by name. They are not
an answer to anything, which is why they are out of a table whose contract is "the first row that
fits is your answer". Their shape is kept as a **design record** in §3.6–3.8, because whether the
lean lane grows a consumer-pluggable blocking gate is still an open product question and that
argument is worth not re-deriving. If you carry any of the three in a config today, delete
them — see [`migrations/v1-to-v2.md`](migrations/v1-to-v2.md).

Two cuts make almost every decision:

- **Value vs knowledge vs behavior.** If two repos would differ on a *string*, it's config. If they'd differ on *prose* (why/how/gotchas), it's an extension file. If they'd differ on *what runs*, it's an extraLane or a reviewer — both registered from config so the behavior change is auditable. (This is the litmus test from [`context-model.md`](context-model.md), applied.)
- **One repo vs the whole org.** A single repo's knowledge lives in that repo (`.claude/second-shift/`, `.claude/agents/`). Knowledge or agents shared across an org's repos get **packaged once** as a companion pack (§4) instead of vendored N times — the same disease this marketplace cures for the tooling, one layer up.

When two rows both seem to fit, prefer the **narrower, more auditable** one: config over a file, a file over an agent, a repo-local agent over a companion pack. Reach for a companion pack only when the duplication across repos is real.

## 3. Worked examples

One minimal example per extension point. Throughout, `acme` is a stand-in for your org or repo — substitute freely.

### 3.1 `stageParams` — reparameterize a shipped literal

Every `stageParams` key defaults to the plugin's current literal, so an empty config reproduces today's behavior byte-for-byte. Set only what differs.

```jsonc
{
  "stageParams": {
    "planFilePattern": "{plansDir}/plan-{issueKey}.md",   // drop the shipped "acme-" prefix
    "requiredLabels": ["ready", "in-progress"],                   // your tracker's label vocabulary
    "formatGlob": "*.{ts,tsx,css,md}",
    // INERT-lane classifier override. is-inert-diff.sh applies it when a caller passes
    // it in; the default set is JS/TS-centric and treats *.md and *.sh as zero-coverage —
    // true for a TS app, false when shell IS the product.
    // CURRENTLY UNCONSUMED: preflight.sh was the only runtime caller that resolved this
    // key, and that read went with the staged lane (#348). The lean lane's milestone-3
    // verify has deliberately no inert lane, and the pre-commit type-check hook carries
    // its own hardcoded carve-out instead of reading config. config-lint still accepts
    // the key, so setting it stays legal and today changes nothing.
    // REPLACES the default outright (only replacement can remove `\.sh$`), so it is a
    // hand-copy that won't inherit later additions. Omit the key to keep the default.
    "inertPattern": "(\\.md$|^\\.github/workflows/.*\\.yml$)",
    "webComponentGlobs": ["src/**/*.vue"]                          // a11y + design-fidelity reviewer trigger — set when the FE isn't React under apps/web
  }
}
```

Pure parameterization — no ordering, no logic. A published key that nothing actually reads is caught by `check-config-shadowing.sh` (surface rot is a lint failure, not a silent no-op).

The mirror-image rot — a key nothing *sets*, so the shipped default silently matches nothing in your repo — is caught by [`config-grill.sh`](../plugins/second-shift/skills/onboard/tools/config-grill.sh), which `/second-shift:onboard` runs on its draft before the accept-or-edit screen and `/second-shift:doctor` runs on the committed config. `config-lint` cannot see any of it: absence is legal for every optional key, so a structural validator never looks at the tree, and a capability that is off simply never runs while the run still reports green. The grill does look, names what you get for setting the key, and forces a disposition — fix it, or declare it in the top-level `grillWaivers` object (`{"<check id>": "<reason>"}`), the same deliberate-declared-opt-out shape as `commands.<repo>.allowUnverified`. Field reference: [`config-schema.md`](config-schema.md).

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

Extra lanes run **sequentially after** the built-in SUITE lanes, never interleaving or replacing them; results land under a namespaced `ext:openapi-drift` key so canonical lane keys stay unreachable. There is no advisory mode: a lane blocks `lean-gate.sh` milestone 3 or it doesn't exist. `failureClass` must be one of the closed taxonomy values (`FORMAT`, `LINT_AUTOFIX`, `TYPE_ERROR`, `TEST_FAILURE`, `PLAN_CMD_FAILURE`, `INFRA`) — extensions borrow the taxonomy, they never extend it — and the lane gets the standard 2-attempt fix budget.

A build/compile step (`ng build`, `tsc --noEmit --project ...`) is a common `extraLanes` use: it's blocking, runs after the trio, and — unlike a lint or unit-test lane — catches breaks a spec doesn't happen to exercise (e.g. an Angular AOT template referencing a nonexistent property, invisible to `typecheck`/`test` unless some spec transitively imports the broken component). `failureClass: "TYPE_ERROR"` fits: the class already covers compile-time breaks the type-check lane didn't catch. `/second-shift:onboard` drafts this automatically when it detects a build command.

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
.claude/second-shift/doc-routing.md          # change-category → doc-path map for doc updates
```

Each consuming agent's prompt names its own file and loads it *if present*, treating the contents as additive — they can tighten review, never weaken the generic protocol. What files exist and who reads them is the table in [`extension-points.md`](extension-points.md); this is the "add evidence" half of the axiom in its purest form. Every file you drop here must match the shipped **extension manifest** or your own `.known-extensions` allowlist (§4.3), or `check-extensions.sh` fails closed — a typo'd `security-rules.md.md` is loud, not silently ignored. The *named sections inside* `review-context.md` (and `review-context/<r>.md`) are linted too: `check-review-context-sections.sh` matches your H2 headings against the shipped section catalog, so a drifted spelling (`## Maturity calibration` vs `## Maturity stage`) or an empty section body is caught at pre-work preflight — see [extension-points.md → Authoring the review-context surface](extension-points.md#authoring-the-review-context-surface).

One class of extension prose is subtractive **in effect** despite the additive surface: maturity-calibration claims ("no auth system exists yet") that reviewers honor as severity downgrades. A stale claim is a standing waiver no diff ever re-reviews — the pocket test failing with nobody having changed anything. Those claims must be declared as **verified calibration claims** (the fenced `second-shift-claims` block — grammar and failure classes in [`extension-points.md`](extension-points.md)): a mandatory `reverify-by` expiry that FAILs pre-flight when passed, plus optional declarative probes. The mechanism itself honors the axiom — it adds ways to go red and none to go green (a passing probe reports `not-yet-contradicted`, never "verified").

### 3.5 `design.provider` — turn on design-fidelity review

An opt-in axis, off unless the key is present:

```jsonc
{ "design": { "provider": "figma" } }        // or "claude-design"
```

`figma` selects the figma-faithful skills and requires a Figma MCP connection; `claude-design` selects the design-faithful skills and requires DesignSync. Same fail-closed posture as every gate: if the provider's prerequisite is missing at run time, the design steps fail closed rather than degrading silently. Absent key = a run behaves exactly like a non-design run. The design-system reference itself (component catalog, token roles) is knowledge — it lives in `.claude/second-shift/design-tokens/*.md`, an extension file per §3.4. To make the live-render verify gate actually execute (a repo-owned render command the gate screenshots through, blocking on `build-lean` milestone 3), add the optional `design.liveRender` block — see [`live-render.md`](live-render.md).

### 3.6 `stageWorkflows` — a blocking gate owned by you (EP-6) — **RETIRED (#569)**

> **Historical record — retired in #569. The config key does not exist.** This extension point
> was dispatched by the staged lane, deleted in #348; #569 removed the key from the schema and
> `config-lint` now rejects it by name. The section is kept, in the **past tense**, because the
> shape argument is the legitimate part: whether second-shift keeps consumer-pluggable blocking
> gates and delegate seams at all, and what would dispatch them on the lean lane, is an open
> product decision, and
> this is the record it would start from. Everything below describes a mechanism **as it was
> designed**, not one you can turn on. Nothing here is current behavior.
>
> Keeping the key instead was considered and rejected. A dead-but-legal key **silently disarms**
> what a consumer registered: they upgrade, see no error, and believe their gate still runs. A
> rejection is the only mechanism that reaches them. Re-adding a key later is a minor release;
> removing one is breaking — so the retirement happened in the window #348 already opened.

The need it answered: something heavier than a verify command — a real workflow that ran at a chosen stage and blocked completion. A schema-compatibility gate before implementation, a codegen-drift check, a license scan. (For that need today, reach for `extraLanes` (§3.2): it is a blocking verify lane with a real `failureClass`, and it is read by `lean-gate.sh` milestone 3.)

```jsonc
// NOT VALID CONFIG — config-lint rejects this key by name (#569). Shown as designed.
{
  "stageWorkflows": [
    { "stage": 5, "name": "schema-compat", "workflow": "acme-platform:workflows/schema-compat.mjs" },
    { "stage": 6, "name": "license-scan",  "workflow": "tools/license-scan.mjs" }
  ]
}
```

The `workflow` was either `"<plugin>:<relpath>"` (a companion pack's script, §4) or a repo-relative path. As designed, it was dispatched **after** the named stage's built-in sub-steps and **before** that stage's completion write, as a blocking sub-step — no advisory field, because advisory gates don't exist here. The result was recorded under `stageCheckpoint[N].extWorkflows[<name>]`; a failure produced the stage's standard fail-fast write with reason **`ext-workflow-failed`** (your name in the detail field), and the workflow could write state **only** via the staged lane's checkpoint payloads namespaced `ext:` — adding evidence, never reinterpreting what the pipeline had recorded. Two things are still true today: registration lives in *consumer config* (auditable, per-repo) rather than the plugin manifest, and an unresolvable reference is a config-lint failure.

### 3.7 `implementDelegates` — route implementation work to a specialist (EP-7) — **RETIRED (#569)**

> **Historical record — retired in #569. The config key does not exist.** This extension point
> was dispatched by the staged lane, deleted in #348; #569 removed the key from the schema and
> `config-lint` now rejects it by name. The section is kept, in the **past tense**, because the
> shape argument is the legitimate part: whether second-shift keeps consumer-pluggable blocking
> gates and delegate seams at all, and what would dispatch them on the lean lane, is an open
> product decision, and
> this is the record it would start from. Everything below describes a mechanism **as it was
> designed**, not one you can turn on. Nothing here is current behavior.
>
> Keeping the key instead was considered and rejected. A dead-but-legal key **silently disarms**
> what a consumer registered: they upgrade, see no error, and believe their gate still runs. A
> rejection is the only mechanism that reaches them. Re-adding a key later is a minor release;
> removing one is breaking — so the retirement happened in the window #348 already opened.

The need it answered: certain implementation work done by a specialist agent instead of the inline implementer — a migrations specialist for schema changes, a codegen agent for a generated surface. (The lean lane is outcome-gated and silent on *how* a diff is produced, so a build session may still dispatch such an agent by choice. What has no lean home is the declared, config-routed, pre-flight-validated form.)

```jsonc
// NOT VALID CONFIG — config-lint rejects this key by name (#569). Shown as designed.
{
  "implementDelegates": [
    { "surface": "db/migrations/**", "agent": "acme-platform:migration-writer" },
    { "surface": "unit",             "agent": "acme-unit-author" }
  ]
}
```

`surface` was a path glob or the reserved key `unit`; matching work items routed to the delegate. The delegate's output then passed through the **unchanged** scope-enforcement gate and every downstream gate — it *added work* (a different author) and *waived nothing*. `agent` was `"<plugin>:<agent>"` (a companion pack) or a bare repo-local agent name, and an unresolvable one failed closed at pre-flight. That pre-flight arm went with the key in #569: `check-extensions.sh` had been enforcing referential integrity on behalf of a dispatcher that no longer existed, which could only ever block a run, never protect one.

### 3.8 `planGates` — a blocking plan-review gate (EP-8) — **RETIRED (#569)**

> **Historical record — retired in #569. The config key does not exist.** This extension point
> was dispatched by the staged lane, deleted in #348; #569 removed the key from the schema and
> `config-lint` now rejects it by name. The section is kept, in the **past tense**, because the
> shape argument is the legitimate part: whether second-shift keeps consumer-pluggable blocking
> gates and delegate seams at all, and what would dispatch them on the lean lane, is an open
> product decision, and
> this is the record it would start from. Everything below describes a mechanism **as it was
> designed**, not one you can turn on. Nothing here is current behavior.
>
> Keeping the key instead was considered and rejected. A dead-but-legal key **silently disarms**
> what a consumer registered: they upgrade, see no error, and believe their gate still runs. A
> rejection is the only mechanism that reaches them. Re-adding a key later is a minor release;
> removing one is breaking — so the retirement happened in the window #348 already opened.

The need it answered: an extra reviewer of the *plan itself* — a QA-tier review of the test strategy for a surface, an ADR-compliance check — able to block a bad plan before any code was written. The lean lane has no plan gate for one to be additive to; the spec is judged at the merge boundary by `review-lean`, after the diff exists.

```jsonc
// NOT VALID CONFIG — config-lint rejects this key by name (#569). Shown as designed.
{
  "planGates": [
    { "name": "api-plan", "surface": "tests/api/**", "agent": "acme-qa-pack:api-test-plan-reviewer" }
  ]
}
```

As designed, each plan gate ran **after** the built-in plan gates (plan-reviewer, design FE-spec, unit-test-plan) as an additive trinary reviewer over the plan, appearing in the gate ledger as `plan-gate:<name>`; `surface` (optional) scoped it to plans touching that glob, and a `block` mapped to the existing `plan-reviewer-block` reason (no per-extension enum value) — able to make a passing plan review *block*, never to waive a built-in gate. It was conceived as the plan-stage counterpart of `extraLanes` and `reviewers.add`, but that symmetry no longer holds: **those two still run** — `extraLanes` is read by `lean-gate.sh` milestone 3 and `reviewers.add` by `review-lead` — while this seam has no dispatcher. `agent` is `"<plugin>:<agent>"` or a bare repo-local name; unresolvable fails closed at pre-flight.

### 3.9 Companion pack — package the above for the whole org

When the extension files or reviewers above would be copied across many of your repos, package them once as a companion pack plugin and point config at it. That's §4.

## 4. The companion-pack contract (EP-5)

A **companion pack** is your own private plugin — same distribution mechanics as second-shift, different visibility — that carries the org-wide half of your extension surface: shared domain reviewers and shared knowledge files. (It used to carry shared workflow scripts and delegate agents too — the EP-6/EP-7 targets — but #569 retired the config keys that referenced them; see §3.6–3.7.) It's the concrete form of the "org/platform overlay" (layer 2) named in [`context-model.md`](context-model.md): author org knowledge once, version it, pin it, instead of vendoring it into every repo.

A consumer repo enables the companion pack alongside second-shift and then *references* its contents from `.claude/second-shift.config.json` — `reviewers.add` for its reviewers — and declares its knowledge files in `.known-extensions` (§4.3). The pack itself never edits a consumer's config; wiring is always the consumer's auditable choice.

### 4.1 The two-pin model

A companion pack sits *between* the public second-shift release and your repo's own knowledge, so a consumer pins **two** independent things:

1. **second-shift** — the public marketplace, pinned by marketplace `ref` + per-plugin `version` (the mechanism in [`onboarding.md`](onboarding.md)).
2. **the companion pack** — your private marketplace, pinned the same way, on its own release cadence.

They upgrade independently: bumping your org pack's domain rules is a companion-pack release and a one-line `ref` bump in the consumer, touching neither the public plugins nor unrelated repos. Both pins are the durable kind — marketplace `ref` so the catalog can't drift, plus the plugin `version` the install cache is keyed by.

### 4.2 Namespaced agents and workflows

Everything a companion pack exposes is addressed `<pack>:<name>`, exactly like the shipped plugins ([`namespaces.md`](namespaces.md)):

- **Agents** referenced from config carry the qualifier: a pack reviewer registered via `reviewers.add` is dispatched by its qualified name, `"acme-platform:api-test-reviewer"`. (A repo-*local* agent stays bare — that's the disambiguation between the two roots.)
- **Workflows** a pack ships use the same `"<pack>:<relpath>"` form wherever the Workflow tool resolves one; it searches the installed-plugin path, so never hard-code a filesystem path into another plugin. No *config* key points at one any more — the two that did (`stageWorkflows`, `implementDelegates`) were retired in #569.

The qualifier is what lets `check-reviewer-references.sh` tell "shipped", "companion", and "repo-local" apart, and what keeps a pack from silently shadowing a shipped name.

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

> **Half of this study is a historical record — read §3.6-3.8 first.** Three of the five
> mechanisms it composes (`stageWorkflows`, `implementDelegates`, `planGates`) lost their
> dispatcher in #348 and lost their config keys in #569: `config-lint` rejects them by name, so
> a config carrying them **fails pre-flight**. The `extraLanes`, `reviewers.add` and
> extension-file halves still run, and the config block below carries only those.
> The retired halves are shown separately, as design record, because this is the only worked
> example of how the five composed — and it is the argument any replacement dispatcher would
> have to satisfy.

The single snippets above each touch one seam. Real capabilities compose several. Here's a worked case a QA-minded org actually wants: **black-box API tests as a first-class pipeline concern** — the plan's API-test strategy gets reviewed *before* code is written, the tests are authored by a specialist, the suite runs as a blocking gate, and the tests themselves get code-reviewed. That's four different gating moments, so it's four seams — packaged once as a companion pack, `acme-qa-pack`, and wired from each consumer's config.

**What the pack ships** (authored once, versioned, pinned — §4):
- `agents/api-test-plan-reviewer.md` — reviews the plan's API-test strategy (trinary verdict).
- `agents/api-test-coder.md` — a write-only agent that authors black-box tests under `tests/api/`.
- `agents/api-test-reviewer.md` — reviews the written test code.
- `skills/api-testing/` — the shared "how we write API tests here" playbook the agents load.

**What each consumer repo puts in `.claude/second-shift.config.json`** — the two seams of the
tier that still dispatch, registered and auditable. This block is valid config; paste it and
`config-lint` passes:

```jsonc
{
  // RUN the suite — LIVE: read by lean-gate.sh milestone 3. The API suite is a blocking
  // verify lane, gated to when API surface changed.
  "commands": {
    "<repo-id>": {
      "extraLanes": [
        { "name": "api-tests", "when": ["src/**", "tests/api/**"],
          "commands": ["<the repo's API-test command, e.g. yarn test:api>"], "failureClass": "TEST_FAILURE" }
      ]
    }
  },
  // REVIEW the tests — LIVE: read by review-lead when it selects the panel. The written
  // tests get a domain code review.
  "reviewers": {
    "add": [{ "name": "acme-qa-pack:api-test-reviewer", "dimensions": ["api-testing"] }]
  }
}
```

**And the two seams that are gone.** The block below is **not valid config** — `config-lint`
rejects all three of these keys by name (#569). It is reproduced because the tier's *shape*
argument depends on it: the point of the study is that a QA tier wants a gating moment at the
plan and a different author at the implementation, and neither has a lean home today.

```jsonc
// RETIRED IN #569 — DO NOT PUT THIS IN A CONFIG. Design record only (§3.7-3.8).
{
  // gate the PLAN (§3.8). As designed: block a ticket whose API-test strategy is wrong
  // before any code exists. No lean equivalent — the spec is judged at the merge boundary.
  "planGates": [
    { "name": "api-plan", "surface": "tests/api/**", "agent": "acme-qa-pack:api-test-plan-reviewer" }
  ],
  // route the WRITING (§3.7). As designed: route API-test work to the specialist instead of
  // the inline implementer. A lean build session may still dispatch the same agent by
  // choice — what is gone is the declared, config-routed form.
  "implementDelegates": [
    { "surface": "tests/api/**", "agent": "acme-qa-pack:api-test-coder" }
  ]
}
```

Plus the pack's harness reference, declared so the manifest lint recognizes it (§4.3):

```
# .claude/second-shift/.known-extensions
api-testing/*.md
```

**How it maps — one seam per gating stage:**

| Gating moment | Seam | What runs | Fails how | Status |
| --- | --- | --- | --- | --- |
| plan review | `planGates` (EP-8) | `api-test-plan-reviewer` judges the plan's test strategy | `block` → `plan-reviewer-block` | **retired #569** — no lean equivalent |
| implement | `implementDelegates` (EP-7) | `api-test-coder` writes `tests/api/**` | output passes the unchanged scope + downstream gates | **retired #569** — a session may still choose the agent |
| verify | `extraLanes` (EP-2) | the API suite runs | nonzero → `TEST_FAILURE`, standard budget | live (`lean-gate.sh` milestone 3) |
| code review | `reviewers.add` | `api-test-reviewer` reviews the tests | its verdict folds into the review round | live (`review-lead`) |

Every one of these **adds** a gate or a unit of work; not one can waive a shipped check — an API-test tier can only make a green run *red* (a bad plan, a failing suite, a rejected review), which is exactly the fork-vs-extend line from §1. And because the wiring lives in the consumer's config, anyone auditing the repo sees the whole tier in one file — while the *implementation* (agents, skill) is versioned and pinned in the pack, bumped independently.

> **Two-pin note (phase 1 vs phase 2).** Under the phase-1 vendoring model, the pack's agents/skill are copied by hand into the repo's `.claude/agents/` and `.claude/skills/` (referenced **bare** — `api-test-plan-reviewer`, not `acme-qa-pack:api-test-plan-reviewer`), so every byte influencing a run is visible in the repo's own history; there is no sync command — the copy step belongs in the pack's install notes. The namespaced `acme-qa-pack:…` form shown above is the phase-2 live-resolution target. Either way the *config shape* is identical; only the reference form differs.

---

**In one breath:** config for values and switches; extension files to add evidence; `extraLanes` to add a blocking verify gate and `reviewers.add` to add a review dimension — both registered from config so they're auditable; a companion pack to ship any of it across an org, two-pinned and namespaced. (The plan-gate and delegate seams that once sat alongside them were retired in #569 and survive only as the design record in §3.6-3.8.) And through all of it: extensions add, they never subtract; if your change could turn a red run green, you wanted a fork.

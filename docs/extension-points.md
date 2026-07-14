# Extension points (dynamic context)

> This is the **reference** for the extension surface. If you're deciding *which* mechanism to use — config vs an extension file vs a repo-local reviewer vs a companion pack — start with the funnel in [`extending.md`](extending.md), which cites this page for the field-level detail.

The contract between generic plugin machinery and repo-local domain knowledge. Rule of thumb: **missing extension = generic behavior** — every extension is optional, so onboarding is incremental. (Where this sits in the overall taxonomy — and what belongs in config vs knowledge docs vs run state: [`context-model.md`](context-model.md).)

## Where extensions live

All extension files sit under the consumer repo's `.claude/second-shift/` directory (created on demand). Repo-local skills and agents stay in their normal homes (`.claude/skills/`, `.claude/agents/`).

## The extension surface

| Extension | Read by | Purpose |
| --- | --- | --- |
| `.claude/second-shift/blocker-mutants.md` | unit-test-mutation-reviewer, unit-test-plan-reviewer | Domain-specific blocker-class mutants (e.g. "account-scope filter removed", "financial rounding guard flipped") appended to the generic blocker list |
| `.claude/second-shift/security-rules.md` | security-reviewer | Domain security review rules (tenancy invariants, credential-handling rules, permission-set ↔ OAuth-scope mapping requirements) |
| `.claude/second-shift/review-context.md` | every panel reviewer + review-lead (each self-loads it) | Repo-wide review context: stack orientation, maturity/severity calibration, architectural invariants, known-accepted patterns, and an ownership table pointing at the docs that own enumerable values (the named-section catalog reviewers key on: "Authoring the review-context surface" below). **Database stack** (engine, ORM/ODM/driver, schema/model + data-access globs, migration tooling, special capabilities like vector search) — db-reviewer applies its checks in the terms this section (or `review-context/db-reviewer.md`) declares; absent = db-reviewer infers the stack and lowers confidence |
| `.claude/second-shift/review-context/<reviewer-name>.md` | exactly that reviewer (self-loaded after the shared file) | Per-reviewer repo rules: severity examples, what-not-to-flag lists, stack resolutions only that reviewer consumes. Basename must be a reviewer in the effective registry — linted fail-closed by `review-toolkit/scripts/check-review-context.sh` (review-lead pre-flight) on top of the manifest glob |
| `.claude/second-shift/doc-routing.md` | dev-pipeline `doc-update` (Stage-7 protocol), review-toolkit `doc-updater` | Change-category → doc-path routing map: for each conceptual code-area category (API/endpoint, DB schema, background worker, decision/domain-constant, frontend, …) the doc(s) that document it, plus which reviewer agents restate those constants. Supplements the repo's `CLAUDE.md` context router when a specific-enough category→doc map is wanted. Absent = fall back to CLAUDE.md's declared doc roots + basename grep |
| `.claude/second-shift/design-tokens/*.md` | design-toolkit `design-faithful`, `figma-faithful`, `figma-faithful-spec`, `figma-iterate` skills + `design-faithful-reviewer` / `figma-faithful-reviewer` / `figma-faithful-plan-reviewer` | Design-system reference: component catalog, token roles + arithmetic, primitives package, known-good analogs. May declare **multiple surfaces** (fixed-theme value tables vs a branded/host-relative surface) so the plugin stays surface-agnostic |
| `.claude/agents/*.md` + config `reviewers.add` | review-lead registry | Whole domain reviewers (e.g. an orders-reviewer); dimensions declared in config for routing/dedup |
| `.claude/skills/**` | native skill discovery | Knowledge skills (playbooks); no registration needed |
| `findings.md`, `CLAUDE.md` | session start / all agents | As before — the plugins respect but never require them |

Each consuming agent's prompt declares its extension files explicitly ("if `.claude/second-shift/security-rules.md` exists, load it and treat its rules as additive — they never weaken the generic protocol"). Extensions are **additive-only**: they cannot disable generic checks (use config `reviewers.remove` / `gates` for that — auditable in one file).

## Placement: shared file, per-reviewer file, or standalone?

- **Single-consumer prose** (rules exactly one reviewer uses) → `review-context/<reviewer-name>.md`.
- **Multi-consumer contracts** (read by several agents or by tools — `security-rules.md` has three plugin consumers, `blocker-mutants.md` four) → their own standalone well-known file.
- **Cross-cutting calibration** (maturity stage, severity ladders every reviewer needs to triage) → the shared `review-context.md` core.

Authoring litmus questions for the shared core (keep it small — owned facts point, they don't restate):

1. Is this an enumerable value a tool or config could ever own? → it belongs to that owner; the core gets a pointer row.
2. Does exactly one reviewer consume it? → per-reviewer file.
3. Would EVERY reviewer mis-triage without it? → core. Otherwise it is probably a per-reviewer rule.

## Authoring the review-context surface

The shipped reviewers key on **named sections**, not free prose — a section they can't find
means they infer conservatively from the diff and say so. A section with exactly one reader
belongs in that reviewer's own `review-context/<reviewer-name>.md` (same content, self-loaded
by exactly that reviewer); sections with multiple readers stay in the shared core — reviewers
honor both homes. These are the sections that have readers today (every one optional; write
only what's true for your repo):

```markdown
# Review context — <repo>

## Stack
Web framework + rendering model, background-job/queue system, data store(s) + special
index capabilities (vector/text search), service languages. Read by: performance-reviewer
(applies every check in this stack's terms).

## Database stack
Engine, ORM/ODM/driver, schema/model + data-access globs, migration tooling, special
capabilities. Read by: db-reviewer (engine-agnostic; this section IS its engine).

## Maturity stage
E.g. "pre-auth: no ownership parameter or guards exist yet". Read by: security-reviewer
(missing tenancy scoping in a declared pre-auth codebase files as forward-compatibility,
not a new Critical).

## Architectural invariants & deliberate deviations
The rules that must hold, and the places you knowingly break convention. Read by: all
reviewers via review-lead.

## Intentional complexity
Named pipelines, layered domain models, planned-swap seams — abstractions that exist on
purpose. Read by: complexity-reviewer (honors them as additive exemptions, never flags).

## Convention-required structure
Framework-mandated scaffolding that must NOT be flagged (module/DTO/model layout,
per-worker processor files, workspace-package separation). Read by: maintainability-reviewer.

## UI stack & design system
UI framework, the design-system/primitives package to prefer (headless primitives library
if any). Read by: complexity-reviewer (ad-hoc-primitive check), a11y-reviewer.

## Naming & structure conventions
Table/collection names, field casing, key naming — the prevailing convention new code is
held to. Read by: db-reviewer, maintainability-reviewer.

## Performance budgets
Per-layer latency budgets, hot paths. Read by: performance-reviewer.
```

Keep entries short and declarative — reviewers quote them back as exemption justifications,
so every line is effectively policy. (Doc routing does NOT go here; that's
`doc-routing.md` above.)

**This section is machine-mirrored.** The section names above are not just prose — they are
the exact keys reviewers match on, shipped as a machine-readable catalog at
[`plugins/review-toolkit/scripts/section-catalog.txt`](../plugins/review-toolkit/scripts/section-catalog.txt)
(`section-name | readers | status`). `check-review-context-sections.sh` lints a consumer's
`review-context.md` (and `review-context/<reviewer>.md`) H2+ headings against it — **exact
match, no fuzzy heuristics** — and a release selftest fails if this template and the catalog
drift apart. Two authoring consequences:

- **A renamed/drifted heading is caught, not silently ignored.** The catalog carries a
  **deprecated-alias-of** tombstone table for known drifted spellings (e.g.
  `## Maturity calibration (MVP stage)` → `## Maturity stage`); an alias hit FAILs the
  pre-work preflight and prints the exact rename command. An **empty/TODO-bodied** catalog
  section is likewise treated as absent (reviewers infer conservatively and say so) and FAILs
  preflight. A section that is simply missing is fine — that stays "generic behavior."
- **Off-catalog headings are your prerogative.** A heading the catalog doesn't know is not an
  error; mark it recognized-and-intentional in `.claude/second-shift/.known-sections` (one
  per line) or a `section:<name>` line in `.known-extensions` (mirrors the EP-3 escape hatch)
  to silence it in `--verbose`/preflight and count it toward coverage. `--report` prints a
  one-line context-coverage summary (which reviewers are running degraded) and never affects
  the exit code.


## Cross-cutting tool contracts

### `check-reviewer-references.sh` (two-root union)

Pre-pluginization the script asserted review-lead's registry ↔ `.claude/agents/` lockstep within one repo. Post-pluginization it must union **two roots**:

```
effective_registry = plugin_registry (review-lead SKILL.md, plugin root)
                   − config reviewers.remove
                   + config reviewers.add (must resolve to consumer .claude/agents/*.md)
```

Failures: registry entry with no agent file (either root); consumer agent file registered nowhere; `reviewers.remove` naming a nonexistent plugin reviewer; a consumer repo file **shadowing** a plugin-shipped agent name (the drift tripwire). Fixtures cover all four.

### `check-model-tiers.sh` (config-aware)

Asserts the `.mjs` workflow model tables ↔ agent frontmatter agreement, now with a third input: config `reviewers.modelOverrides`. Precedence: `modelOverrides` > agent frontmatter default. The observed need: security-reviewer runs `opus` in one repo and `sonnet` in another from the same plugin-shipped agent file.

**EP-4 covers named workflow agents too, not just panel reviewers.** `modelOverrides` keys
accept any agent the `.mjs` dispatch tables model — including `mutation-executor` (the
mutation gate's executor tier), not only `<name>-reviewer` entries. The schema description
says "per-reviewer" as the common case, not as a constraint; `check-model-tiers.sh`
validates whatever key you override against the actual tables.

### `check-extensions.sh` (manifest lint — EP-3)

The plugin ships a versioned **manifest** of known extension-file names/globs ([`tools/extension-manifest.txt`](../plugins/dev-pipeline/skills/run/tools/extension-manifest.txt)); `check-extensions.sh` runs at pre-flight and **fails closed** on any file under a consumer's `.claude/second-shift/` that matches no manifest entry. This converts "missing extension = generic behavior" from silent degradation into a checked contract — a typo'd `blocker-mutants.md.md` is loud, not silently ignored. A new well-known file in a future plugin version is discoverable via a manifest entry; an unrecognized file today is a config-lint failure.

**Companion-pack / repo-local extensions** the stock manifest doesn't ship (e.g. an org QA pack's `api-testing/*.md`) are declared, additive-only and auditable, in a consumer-maintained `.claude/second-shift/.known-extensions` file (one glob per line) that `check-extensions.sh` unions onto the shipped manifest.

### `check-config-shadowing.sh` (EP-1 companion)

Fails closed if any `stageParams` key the schema publishes is not actually read by its owning stage/tool file — the report's defect-#1 guard against "a published key the plugin ignores" (surface rot). Fixture-covered by its selftest.

# v1.x → v2.0.0 ("extensible core") — retroactive migration

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

Key absent = design fidelity off. As of **v2.1.6** `gates` retains exactly one key: `mutation`
(see the v2.1.6 removals below).

### v2.1.6 dead-key removals — `commands.<repo>.integrationTest` / `apiTest`, `gates.costTracking`

Three published keys had **zero readers** — a consumer set them and nothing happened. They are
removed; config-lint now rejects them with a migration pointer (fail closed).

- **`commands.<repo>.integrationTest` / `commands.<repo>.apiTest`** — never executed by any
  verify lane. Ship an integration/API test tier via **`commands.<repo>.extraLanes`** (an
  additive verify lane with a real `failureClass`, so failures get the correct fix budget)
  or as a companion pack through extension points EP-6/EP-7. See [`extending.md`](../extending.md).
- **`gates.costTracking`** — the mutation gate keyed off `unitTestScope` presence, and cost
  attribution ran unconditionally regardless of this flag; it toggled nothing in either
  direction. Removed. Local OTel cost attribution is now simply always-on (passive, never
  blocks). Delete the key from your config.

`gates.mutation` is now **wired as a real off-switch**: `false` disables the Stage-5 unit-test
mutation gate even when `commands.<host>.unitTestScope` is set (previously ignored).

### `gates.apiTests` → removed (extension point)

The API-test tier left the core. Ship it as a companion pack via extension points EP-6
(`implementDelegates`) / EP-7 (`stageWorkflows`/`extraLanes`), declaring its files in
`.claude/second-shift/.known-extensions` — see [`extending.md`](../extending.md) for the
full worked example (plan gate + coder delegate + verify lane + reviewer).

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

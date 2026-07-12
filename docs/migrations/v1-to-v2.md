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

Key absent = design fidelity off. `gates` retains exactly two keys in v2: `mutation` and
`costTracking`.

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

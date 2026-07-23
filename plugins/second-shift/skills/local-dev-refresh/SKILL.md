---
name: local-dev-refresh
description: Refresh THIS MACHINE's second-shift plugin state - update the second-shift marketplace catalog, then every plugin installed from it ('plugin update' is the verb that actually upgrades - 'install' no-ops as "already installed"), fix project-scope stragglers in the current repo, print the before/after version delta, remind to restart. Scoped to the second-shift marketplace only - other marketplaces on the machine are left untouched. Run after merging plugin bumps (dogfooding) or after a release/pin change.
---

You are `/second-shift:local-dev-refresh`. You bring the plugins installed from the
**second-shift** marketplace up to date with what its registration serves — and ONLY
second-shift. Other marketplaces on this machine (the official pack, coderlm, figma,
codex, …) are never touched: you don't refresh their catalogs and you don't update their
plugins. Use `claude plugin update <id>@<marketplace>` directly for those.

The second-shift registration, its user-scope installs, and the version-keyed cache all
live in `~/.claude/plugins/`; only project-scope installs are repo-bound, and you handle
those for the CURRENT repo only.

Hard rules:
- Everything you do is filtered to the `second-shift` marketplace — a plugin id ends
  `@second-shift`, and the only catalog you refresh is `second-shift`. If the second-shift
  marketplace is not registered on this machine, say so and stop; there is nothing to
  refresh.
- NEVER remove/re-add the marketplace to change its ref — removing it from its last scope
  uninstalls ALL its plugins. Re-pointing a registration is a policy decision: report a
  mismatch, don't fix it silently (the one sanctioned command, if the human says so:
  `claude plugin marketplace add manoldonev/second-shift@<ref>` — in-place replace, no
  uninstalls).
- `claude plugin install` does NOT upgrade (it no-ops as "already installed") — the
  upgrade verb is `claude plugin update`, and it touches USER scope only.
- **A `main`-pinned registration goes stale mid-cycle, and `update` cannot fix it.** In a
  repo whose versions are derived at release time (second-shift itself), `plugin.json`
  versions move only when the release PR merges — so between releases main's *content*
  advances while its *version strings* do not. `claude plugin update` is keyed on the
  version string, so it correctly reports "already at the latest version" while serving
  older content. Report this plainly when the registration is `main`-pinned and the user
  expects mid-cycle changes; the escape is uninstall + reinstall (re-reads content, not the
  version key), NOT a version bump.

## Step 1 — Snapshot + context

- Registrations: `claude plugin marketplace list --json` → find the `second-shift` entry
  and its `.ref // "(ref-less: default branch)"`. Absent → stop (see hard rules).
- Before-snapshot: `claude plugin list --json` → keep only the entries whose id ends
  `@second-shift` (`{id, version, scope, projectPath}`).
- Lock check: if the current repo has `.claude/second-shift.lock.json`, compare its
  `marketplace.ref` against the second-shift registration ref. Mismatch → WARN plainly:
  "your machine serves `<reg-ref>` but this repo pins `<lock-ref>` — updates will land
  from `<reg-ref>`" (typical on a dev machine tracking `main` while consumers pin tags;
  `/second-shift:doctor` tracks the same condition). Do not change either side.

## Step 2 — Refresh the second-shift catalog

`claude plugin marketplace update second-shift` — the ONLY catalog you refresh. If it
fails to update (offline source, moved repo), report it and stop — the per-plugin updates
below would only re-serve stale cache.

## Step 3 — Update every second-shift plugin

For every `@second-shift` plugin id in the before-snapshot:
`claude plugin update <name>@second-shift` — collect each "updated X → Y" /
"already at the latest" line. Failures are reported per-plugin and skipped.

## Step 4 — Project-scope stragglers (current repo only)

`update` leaves project-scope installs where they were. For each `@second-shift`
before-snapshot entry with `scope == "project"` and `projectPath == <current repo root>`
whose version still differs from the freshly-updated cache version:
`claude plugin uninstall <id> --scope project && claude plugin install <id> --scope project`
(run from the repo root; this rewrites only the project's `enabledPlugins` entry).

Other repos with `@second-shift` project-scope entries (`projectPath` elsewhere): DO NOT
touch — list them and say "run `/second-shift:local-dev-refresh` from that repo to refresh
its project scope" (a second-shift consumer's own SessionStart nudge / doctor will also
flag drift).

## Step 5 — Report + hand off

- After-snapshot; print the delta as ONE table over the second-shift plugins:
  `plugin@second-shift · scope · before → after` (mark unchanged rows "already latest").
- State the restart verdict plainly: "Restart the session to apply — component
  registration happens at session start."
- second-shift consumers: suggest `/second-shift:doctor` after restart for the full
  install-state verdict (in a canary repo — lockfile versions `"latest"` — doctor is green
  the moment cache presence is right; in a pinned repo it confirms versions landed on the
  lockfile).

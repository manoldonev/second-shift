---
name: local-dev-refresh
description: Refresh THIS MACHINE's local dev plugin state - update every registered marketplace, then every installed plugin (all marketplaces, not just second-shift; 'plugin update' is the verb that actually upgrades - 'install' no-ops as "already installed"), fix project-scope stragglers in the current repo, print the before/after version delta, remind to restart. Run after merging plugin bumps (dogfooding) or after a release/pin change.
---

You are `/second-shift:local-dev-refresh`. You bring this machine's installed plugins up
to date with what their marketplace registrations serve — ALL marketplaces and ALL
installed plugins, not only second-shift. Machine-level by design: registrations,
user-scope installs, and the version-keyed cache all live in `~/.claude/plugins/`; only
project-scope installs are repo-bound, and you handle those for the CURRENT repo only.

Hard rules:
- NEVER remove/re-add a marketplace to change its ref — removing a marketplace from its
  last scope uninstalls ALL its plugins. Re-pointing a registration is a policy decision:
  report a mismatch, don't fix it silently (the one sanctioned command, if the human says
  so: `claude plugin marketplace add <owner/repo>@<ref>` — in-place replace, no uninstalls).
- `claude plugin install` does NOT upgrade (it no-ops as "already installed") — the
  upgrade verb is `claude plugin update`, and it touches USER scope only.

## Step 1 — Snapshot + context

- Before-snapshot: `claude plugin list --json` → EVERY installed entry
  (`{id, version, scope, projectPath}`), all marketplaces.
- Registrations: `claude plugin marketplace list --json` → every name +
  `.ref // "(ref-less: default branch)"`.
- second-shift specific: if the current repo has `.claude/second-shift.lock.json`, compare
  its `marketplace.ref` against the second-shift registration ref. Mismatch → WARN plainly:
  "your machine serves `<reg-ref>` but this repo pins `<lock-ref>` — updates will land
  from `<reg-ref>`" (typical on a dev machine tracking `main` while consumers pin tags;
  `/second-shift:doctor` tracks the same condition). Do not change either side.

## Step 2 — Refresh every catalog

For each registered marketplace name from Step 1:
`claude plugin marketplace update <name>` — collect results. A marketplace that fails to
update (offline source, moved repo) is reported and skipped, never fatal.

## Step 3 — Update every installed plugin

For every distinct plugin id (`<name>@<marketplace>`) in the before-snapshot:
`claude plugin update <name>@<marketplace>` — collect each "updated X → Y" /
"already at the latest" line. Failures are reported per-plugin and skipped.

## Step 4 — Project-scope stragglers (current repo only)

`update` leaves project-scope installs where they were. For each before-snapshot entry
with `scope == "project"` and `projectPath == <current repo root>` whose version still
differs from the freshly-updated cache version:
`claude plugin uninstall <id> --scope project && claude plugin install <id> --scope project`
(run from the repo root; this rewrites only the project's `enabledPlugins` entry).

Other repos with project-scope entries (`projectPath` elsewhere): DO NOT touch — list
them and say "run `/second-shift:local-dev-refresh` from that repo to refresh its project
scope" (a second-shift consumer's own SessionStart nudge / doctor will also flag drift).

## Step 5 — Report + hand off

- After-snapshot; print the delta as ONE table across all marketplaces:
  `plugin@marketplace · scope · before → after` (mark unchanged rows "already latest").
- State the restart verdict plainly: "Restart the session to apply — component
  registration happens at session start."
- second-shift consumers: suggest `/second-shift:doctor` after restart for the full
  install-state verdict (in a canary repo — lockfile versions `"latest"` — doctor is green
  the moment cache presence is right; in a pinned repo it confirms versions landed on the
  lockfile).

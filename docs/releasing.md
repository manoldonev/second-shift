# Releasing

Every consumer upgrade is a deliberate PR (third-party marketplaces never auto-update), so
every release must make that PR easy to open and easy to trust.

**Versions and the CHANGELOG are derived at release time, not written in feature PRs.**
A feature PR never touches `plugins/*/.claude-plugin/plugin.json` `version` or
`CHANGELOG.md` — CI rejects it (`scripts/check-frozen-files.sh`). Both are computed by
[`scripts/derive-release.sh`](../scripts/derive-release.sh) from conventional commit types
and changed paths, and land on an accumulating **release PR**.

## The flow

1. **Feature PRs merge to `main` as squashes**, each carrying a `Changelog:` trailer in a
   commit body (or the explicit `Changelog: none` opt-out). CI enforces the trailer on any
   PR touching `plugins/**` (`scripts/check-changelog-trailer.sh`). The trailer is where
   migration prose lives — it becomes the CHANGELOG bullet body and the Release "What
   breaks" entry:

   ```
   fix(dev-pipeline): a mis-shaped setup lane must be loud, not a false green

   Changelog: config-lint now rejects a non-object lanes[]/extraLanes[] entry.
     Migration: a config using the undocumented string shorthand now fails
     config-lint. Rewrite ["npm ci"] as [{"name":"install","commands":["npm ci"]}].
   ```

   A `BREAKING CHANGE:` footer doubles as the major-bump signal and the migration prose.
   Trailers are extracted **grep-anywhere**, not via `git interpret-trailers`: this repo's
   squash prefill is `COMMIT_MESSAGES` (bodies are concatenated), and git only recognizes
   trailers in the final paragraph — so a mid-body trailer must still count.

2. **Every push to `main` re-derives the release PR** (`.github/workflows/release-pr.yml`).
   It computes which plugins changed (from paths under `plugins/<name>/`, never the commit
   scope), each plugin's bump level (`BREAKING CHANGE:`/`!` → major, `feat` → minor, else
   patch; max across that plugin's commits), the marketplace version (max level across all
   changed plugins applied to the previous release version), the CHANGELOG section, and the
   pinned-ref doc example. `release:` commits are excluded from the derivation.

3. **Human judgment lands on the release PR** — see the checklist it renders into its own
   body (migration prose, section-catalog breaking-class review, plugin renames). **Land
   those edits late** — after the last feature merge. The `release/next` branch is
   bot-owned: every re-derive regenerates it wholesale and force-pushes. Superseded human
   commits get a loud comment naming the previous head, which stays reachable from the PR
   history, but re-applying them is manual.

4. **Merging the release PR tags and publishes** (`.github/workflows/release-publish.yml`):
   it creates `vX.Y.Z` on the merge commit and the GitHub Release together, with the body
   assembled from `BREAKING CHANGE:`/`Changelog:` trailers ("Nothing breaks." rendered
   explicitly when there are none) plus the consumer upgrade recipe.
   `/second-shift:onboard` resolves `releases/latest` — cutting the Release IS the publish
   step.

There is no `/release` skill — the derivation is automated and the human checklist is
rendered into the release PR body, so a runbook skill would only be a third copy of this
document. The whole maintainer surface is:

```bash
# 1. Find (or force a fresh re-derive of) the release PR:
gh pr list --head release/next --state open --json number,title,url
gh workflow run release-pr.yml          # only if none is open, or to re-derive on demand

# 2. Resolve the checklist in the PR body, merge it (merging tags + publishes), then verify:
bash plugins/second-shift/skills/onboard/tools/pin-resolve.sh manoldonev/second-shift \
  dev-pipeline review-toolkit intake-toolkit design-toolkit audit-toolkit second-shift
# expect: refSource "release", ref = the new tag, per-plugin versions matching the tag

# 3. Refresh this machine's plugin state:
#    /second-shift:local-dev-refresh
```

**Never hand-edit versions or `CHANGELOG.md`.** On a feature branch CI rejects it
(`check-frozen-files.sh`); on the release branch the next re-derive erases it.

## Gates

| Gate | Where | What it enforces |
| --- | --- | --- |
| `check-frozen-files.sh` | every PR except `release/next` | no `plugin.json` version or `CHANGELOG.md` edits |
| `check-changelog-trailer.sh` | every PR except `release/next` | a `plugins/**` PR carries `Changelog:` or `Changelog: none` |
| `check-plugin-version-bumps.sh` | the release PR only | every content-changed plugin carries its derived bump (the version string is the update **cache key** — an unbumped plugin updates NOBODY) |
| configVersion migration-doc gate | the release PR only | a `configVersion` change ships `docs/migrations/vN-to-vN+1.md` (the contract in [`migrations/README.md`](migrations/README.md)) |

**The maintainer-local trace gate does not run on the release PR.** It is a pre-push hook on
the maintainer's machine; the release commit is authored by the bot in CI, so the hook never
fires for it. This is acceptable because the release commit is fully derived — every byte of
it comes from `derive-release.sh` operating on already-reviewed, already-gated commits. Trace
discipline still applies to every feature PR, where the hook does run.

## Things the derivation does NOT decide

- **Section-catalog changes are breaking-class.** Adding, renaming, or tombstoning a row in
  `plugins/review-toolkit/scripts/section-catalog.txt` changes what
  `check-review-context-sections.sh` accepts. Check the new catalog against known-consumer
  `review-context.md` headings (propagation is pull-only, so a consumer only sees it on
  their next bump) and list any heading that would newly flag in the What-breaks body, with
  the rename command. A rename ships as a `deprecated-alias-of:` row (never a bare
  deletion) so the linter can print the exact fix instead of a bare failure.
- **Plugin renames: never silently.** Use the official marketplace.json **`renames` map**
  (supported since Claude Code v2.1.193; append-only — `"old-name": "new-name"`, or `null`
  for a retirement) AND disclose the rename in the Release notes; consumer repos migrate in
  their own PR.

Both are rendered as checklist items in the release PR body; resolve them there before merge.

## Consumers tracking `main`

A registration pinned to `main` (rather than a release tag) **stops seeing updates
mid-cycle**: between releases, main's content moves but `plugin.json` versions do not, and
`claude plugin update` is keyed on the version string, so it reports "already at the latest
version". The staleness window is however long the release PR stays open. The escape is
uninstall + reinstall (which re-reads content, not the version key) — see
`/second-shift:local-dev-refresh`. Tag-pinned consumers (the lockfile + `/second-shift:doctor`
path) are unaffected: they read the same version fields, just written at a different time.

## One-time setup

The release workflows author the release PR with a **GitHub App token**, not the default
`GITHUB_TOKEN` — events caused by `GITHUB_TOKEN` do not trigger workflows, so a
default-token PR would get no CI and the release-PR gates would never run. Configure two
repo secrets for an App with `contents: write` + `pull_requests: write`:

- `RELEASE_APP_ID`
- `RELEASE_APP_PRIVATE_KEY`

`release-pr.yml` fails loud with this pointer when they are absent.

## Rollback

Consumers revert their upgrade PR. This works because catalog entries at the reverted tag
still resolve and the install cache is keyed by version string; doctor flags version-AHEAD
engineers symmetrically and prints the downgrade reinstall. An in-flight release PR can
simply be closed — it holds no state outside git.

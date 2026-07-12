---
name: release
description: Cut a second-shift marketplace release - completeness audit of everything merged since the last tag (CHANGELOG coverage + deferred version bumps), release commit, full green gate, tag + GitHub Release with the mandatory What-breaks body, post-release verification, and the maintainer-machine plugin refresh. Maintainer-only, repo-local; the checklist of record is docs/releasing.md.
---

You are `/release` for the second-shift marketplace. You execute `docs/releasing.md` end to
end, with the operational details that doc leaves implicit. Maintainer context only.

Hard rules:
- Work in a scratchpad **git worktree** off `origin/main` — never the maintainer's checkout.
  Every git command carries an explicit `-C <worktree-path>`.
- **Versions are consumed on merge in this repo.** `git fetch origin --tags` FIRST, re-derive
  everything live (metadata.version, every `plugins/*/plugin.json`, latest tag,
  `gh release list`), and re-derive AGAIN right before tagging if any time passed. Never
  reuse a number computed earlier.
- Nothing org-traceable in any committed or published text — acme placeholders only.
- STOP and ask (one paragraph + options) if: the release version is ambiguous, a wave PR
  lands mid-release, any gate fails, or the trace gate hits on content you believe clean.

## Step 1 — Completeness audit (before touching anything)

List every PR merged since the last tag: `git -C <wt> log <last-tag>..origin/main --oneline`.
For EACH merge verify two things:
1. **CHANGELOG coverage** — a bullet exists somewhere under a version heading.
2. **Version bumps** — every plugin whose content the PR touched bumped its `plugin.json`
   (`git show <sha>:plugins/<p>/.claude-plugin/plugin.json | jq -r .version` per commit
   walks the history). The pair-series convention ships logic-only PRs with the bump
   **deferred to release** — that is sanctioned; absorb all deferred/missed bumps NOW, in
   the release commit, with a new CHANGELOG section documenting them. An unbumped plugin
   updates NOBODY (the version string is the update cache key).

## Step 2 — Pick the release version

Release version = the highest CHANGELOG heading, reconciled with `metadata.version`
(bump metadata to it; they must be equal, and the tag is `v<that>`). If deferred bumps from
Step 1 warrant a new section, the new section's number is the release. Ambiguous → STOP,
present the candidates and why.

## Step 3 — The release commit (one commit, on a branch or straight to main per instruction)

- New CHANGELOG section for anything Step 1 found uncovered (deferred bumps, missing PRs).
- Strip EVERY "(in progress)" marker — including mid-parenthetical forms like
  `(#4, PR 2, in progress)`; grep for `in progress` until zero.
- `metadata.version` → the release version. Bumped `plugin.json`s from Step 1.
- Refresh the doc pin examples to the new tag: README quick start (if it names a version)
  and `docs/onboarding.md`'s settings-pin example (`"ref": "vX.Y.Z"`) — the v1.1.0 lesson.
- Remove any interim release-gated notes.

## Step 4 — Full green gate (locally, before push)

```bash
# in the worktree root; ALL must pass
find . -name '*-selftest.sh' -print0 | while read -d '' t; do SKIP_STRESS=1 bash "$t"; done
find . -name '*-selftest.sh' -print0 | while read -d '' t; do SKIP_STRESS=1 /bin/bash "$t"; done  # stock 3.2
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
bash scripts/check-plugin-version-bumps.sh
claude plugin validate . --strict
```
Plus the rule-3 namespace greps from ci.yml, and the repo's pre-push trace gate (run it
explicitly; it must print clean — never weaken it).

## Step 5 — Publish

1. Push the release commit to `main`; **wait for CI green on that exact SHA** before tagging.
2. `git -C <wt> tag vX.Y.Z <sha> && git -C <wt> push origin vX.Y.Z`.
3. `gh release create vX.Y.Z --title "..." --notes-file <body>` — the body per
   releasing.md: a mandatory **"What breaks / what to do"** section (write "Nothing
   breaks." explicitly when true), highlights, and the consumer upgrade recipe (ONE PR bumps
   the settings `ref` and `.claude/second-shift.lock.json` together, then
   `claude plugin marketplace update second-shift` + reinstall + restart + re-run gates).
   Cutting the Release IS the publish step — `/second-shift:onboard` pins `releases/latest`.

## Step 6 — Post-release verification (report both outputs)

```bash
bash plugins/second-shift/skills/onboard/tools/pin-resolve.sh manoldonev/second-shift \
  dev-pipeline review-toolkit intake-toolkit audit-toolkit second-shift
# expect: refSource "release", ref = the new tag, per-plugin versions matching the tag
bash scripts/check-plugin-version-bumps.sh   # now compares against the new tag
```

## Step 7 — Maintainer-machine refresh (dev registration + installed plugins)

1. Check the local registration:
   `claude plugin marketplace list --json | jq '.[] | select(.name=="second-shift")'`.
   If it pins an old ref, **do NOT remove/re-add the marketplace** (removing it from its
   last scope uninstalls ALL its plugins — including project-scope installs in real
   consumer checkouts on this machine). Instead: back up
   `~/.claude/plugins/known_marketplaces.json`, edit `."second-shift".source.ref` to the
   new tag with jq, then `claude plugin marketplace update second-shift` and confirm the
   cached catalog version moved.
2. Upgrade installed plugins — `claude plugin install` reports "already installed" and does
   NOT upgrade; the verb is **update**:
   `for p in dev-pipeline review-toolkit intake-toolkit design-toolkit audit-toolkit second-shift; do claude plugin update "$p@second-shift"; done`
   `update` touches user scope; **project-scope** installs in consumer repos need
   `claude plugin uninstall <p>@second-shift --scope project && claude plugin install <p>@second-shift --scope project`
   from that repo's root.
3. Verify `claude plugin list --json` shows the released versions at every scope that
   matters, and remind: **restart the session** — component registration happens at
   session start.

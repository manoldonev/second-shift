# Team rollout

How second-shift goes from your machine to the whole team. It assumes you onboarded the repo with
`/second-shift:onboard` and ran one ticket end to end (the [README's Get started](../README.md#get-started)).

## Day 0 — you

1. Merge the PR with what onboard wrote ([README step 3](../README.md#3-onboard-the-repo)). If you
   accepted the unclaim workflow on a GitHub tracker, it is in that PR too, and it writes
   (`issues: write`), so the repo's Actions workflow permissions must be set to read-and-write.
2. Paste the CONTRIBUTING snippet onboard printed.
3. Run one ticket end to end before inviting the team.

A BE/FE pair onboards each repo on its own:
[onboarding.md → Pair repos](onboarding.md#pair-repos-befe-under-the-pipeline).

## Every engineer — first contact

Clone, open in Claude Code, and you get the **trust dialog**, then the marketplace and plugin
install prompts. Accept them. Three things worth knowing:

- Read `.claude/SECOND-SHIFT.md` first. It says what installs and which hooks run, so the trust
  prompt is an informed decision.
- Skipping the prompts is remembered in **your user settings** and nothing re-prompts. The plugins
  are then enabled but not installed. The session-start check prints the command you need
  (`claude plugin install <plugin>@second-shift --scope project`); `/second-shift:doctor` prints
  the full diagnosis. Restart the session after installing.
- A repo whose `.claude/settings.json` enables no plugins shows no plugin prompts. Each engineer
  installs the lockfile's plugins at user scope (`claude plugin install <plugin>@second-shift`),
  not `--scope project`, which would write into the shared settings.

The same path, step by step: [README](../README.md#joining-a-repo-that-already-uses-it).

## Personal opt-out (sanctioned)

Put `"<plugin>@second-shift": false` in `.claude/settings.local.json`. That file is yours
(gitignored). Project settings take precedence over user settings, so a **user-scope** `false`
cannot override the project's enable; local scope is the right lever. The uninstall dialog's
"disable for you alone" writes exactly this. Never edit the shared `.claude/settings.json` for a
personal preference. Doctor notes what you opted out of, once.

## Upgrades

One PR bumps the `ref` in `.claude/settings.json` **and** `.claude/second-shift.lock.json`
together; doctor flags a PR that bumps only one. After it merges, each engineer runs
`/second-shift:local-dev-refresh`, which updates the marketplace and every installed plugin and
prints the before → after versions. By hand: `claude plugin marketplace update second-shift`, then
`claude plugin update <plugin>@second-shift` per plugin (`install` does nothing when a plugin is
already installed). Restart the session afterwards.

Across a major, read the release's `CHANGELOG.md` entry and [`migrations/`](migrations/README.md)
before merging: a breaking change can need a repo-side step no tool does for you.
`/second-shift:doctor` names the leftovers it can detect.

A repo whose lockfile tracks `main` (plugin versions `latest`) gets no upgrade PR: each engineer
runs `/second-shift:local-dev-refresh` when they want the current tip.

- **Laggards:** `/second-shift:doctor` prints the exact commands for anyone behind the pin. The
  team is done when doctor is clean for everyone.
- **Never enable autoUpdate** for the pinned marketplace: the pin is the point.
- **Your own machine:** a user-level marketplace registration without a `ref` overrides the
  project pin on that machine only. Doctor warns about it; teammates are unaffected. If you
  realign it, remove, re-add and reinstall in one sitting: removing a marketplace from its last
  scope uninstalls all its plugins.

## Rollback

Revert the upgrade PR. Engineers who already upgraded show as ahead of the lockfile in doctor,
with the downgrade command printed.

## Removing it

One PR deletes the files onboard wrote (plus the unclaim workflow, if you took it). Then, on each
machine, `claude plugin uninstall <plugin>@second-shift --scope project` per plugin and
`claude plugin marketplace remove second-shift`. The labels, the PRs and the `second-shift/review`
statuses stay; drop `second-shift/review` from branch protection if you required it.

## Managed settings

Orgs that need central control use managed settings (MDM): force-enable the bundle with managed
`enabledPlugins` (managed scope wins over everything), allowlist marketplaces with
`strictKnownMarketplaces`, ban them with `blockedMarketplaces`, and name the internal owner in the
trust dialog with `pluginTrustMessage`. A managed `enabledPlugins: false` is an org-wide ban.

## What is a gate here

Anything that depends on a plugin each engineer can decline is **fast local feedback, not a
gate**. The gate of record is server-side: required CI on your own checks, branch protection, and
a human merging every PR. second-shift never merges its own work.

It adds one server-side signal you can require: every verdict is posted as the
`second-shift/review` commit status on the commit it reviewed, `success` for approve and `failure`
for needs-work, linking the verdict comment. A commit pushed after the review has no status. To
require it, add `second-shift/review` to the default branch's required status checks (branch
protection or a ruleset); it appears in the picker once a run has posted it. Onboard never writes
protection rules, and `/second-shift:doctor` reports whether the default branch requires it.
Whoever holds the posting identity (the bot, or your own `gh`) can post it, so treat it as a
signal, not proof.

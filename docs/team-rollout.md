# Team rollout

How second-shift goes from one champion's machine to a whole team, and what each moment
looks like. Everything here assumes the repo was onboarded with `/second-shift:onboard`
(the six committed artifacts: config, settings pin, lockfile, thin check, consent doc,
CONTRIBUTING snippet).

## Day 0 — the champion

1. Bootstrap: `claude plugin marketplace add manoldonev/second-shift` +
   `claude plugin install second-shift@second-shift` (user scope).
2. Run `/second-shift:onboard` in the target repo; review the accept-or-edit screen —
   this is where the bot-identity and queue-label decisions happen for the GitHub tracker
   (see [onboarding.md §2b](onboarding.md)).
3. Review and commit the emitted files in one PR: `.claude/settings.json`,
   `.claude/second-shift.config.json`, `.claude/second-shift.lock.json`,
   `.claude/tools/second-shift-doctor.sh`, `.claude/SECOND-SHIFT.md` — plus, if you
   accepted the CI evidence workflow, `.github/workflows/second-shift-ci.yml` and
   `.claude/tools/second-shift-ci-check.sh`.
4. Dry-run: pick a small ticket with no external-infrastructure acceptance criteria and
   run `/dev-pipeline:run <ticket>` end to end before inviting the team.

**Champion's-machine caveat:** the machine that develops or first registers the
marketplace often carries a **ref-less user-scope registration**, which shadows the
project pin *on that machine only*. `/second-shift:doctor` flags it (WARN, not FAIL);
teammates are protected by the committed project ref either way. If you realign it,
do the remove + re-add + reinstall in one sitting — removing a marketplace from its last
scope uninstalls all its plugins.

## Every engineer — first contact

Clone → open in Claude Code → the **trust dialog**, then the marketplace + plugin install
prompts. Accept them. Two things worth knowing in advance:

- Read `.claude/SECOND-SHIFT.md` first — it exists precisely so the "arbitrary code with
  your privileges" prompt is an informed decision, not a leap.
- Skipping the prompts is remembered in **your user settings** and is invisible to the
  repo — nobody can tell you skipped, and nothing re-prompts. Tabbing past lands you in
  **enabled-but-not-installed** (the platform's default state for a fresh clone since
  v2.1.195): the plugins are enabled by project settings but no code is installed. The
  committed SessionStart nudge then prints the one command you need
  (`claude plugin install <plugin>@second-shift --scope project`); `/second-shift:doctor`
  prints the full diagnosis. After installing, restart the session — component
  registration happens at session start.

## Personal opt-out (sanctioned)

Put `"<plugin>@second-shift": false` in `.claude/settings.local.json`. That file is yours
(gitignored); project precedence means a **user-scope** `false` cannot override the
project-level enable — local scope is the right lever. The uninstall dialog's "disable
for you alone" (≥ v2.1.203) writes exactly this. Never edit the shared
`.claude/settings.json` for a personal preference. Doctor notes what you opted out of,
once, and stops there.

## Upgrades

One PR bumps the settings `ref` **and** `.claude/second-shift.lock.json` together —
atomically, never separately (doctor's ref-drift check exists because half-done upgrade
PRs happen). The full maintainer-side recipe is in [releasing.md](releasing.md); the
consumer side is: merge the upgrade PR, then
`claude plugin marketplace update second-shift` + reinstall, then re-run the repo's
validation gates — or just run `/second-shift:local-dev-refresh`, which does the
update + per-plugin upgrade (including project-scope stragglers in the current repo)
and prints the before → after version delta.

- **Laggards converge lazily:** anyone who hasn't updated gets doctor's two remediation
  commands next session (version-behind, exact commands printed). Completion signal =
  doctor silence across the team.
- **Never enable autoUpdate** for the pinned marketplace — the pin is the whole point;
  third-party marketplaces don't auto-update anyway.
- **Sharp edge:** removing a marketplace from its **last** scope uninstalls all its
  plugins. When realigning registrations, do remove + add + reinstall in one sitting;
  never leave it half done.

## Rollback

Revert the upgrade PR. This works because catalog entries at the reverted tag still
resolve and the install cache is keyed by version string. Engineers who already upgraded
show as **version-AHEAD** in doctor — symmetric to behind, with the downgrade reinstall
printed. Per-user cache divergence bites hardest under incident pressure, which is why
this section exists to be read *before* the incident.

## Regulated variant (managed settings)

Orgs that need this centrally use managed settings (MDM):

- force-enable the bundle via managed `enabledPlugins` (managed scope wins over everything),
- `strictKnownMarketplaces` to allowlist marketplaces,
- `blockedMarketplaces` to ban specific ones,
- `pluginTrustMessage` to put the internal owner's name in the trust dialog.

Managed `enabledPlugins: false` is an org-wide ban; individual repos can't re-enable.

## What is a gate here

Any control that depends on a voluntarily-installed, individually-declinable client
plugin is **fast local feedback, not a gate**. The gate of record is server-side —
required CI on the committed artifacts and branch protection. `/second-shift:onboard`
can emit that CI on request (`.github/workflows/second-shift-ci.yml` + the committed
`second-shift-ci-check.sh`): on every PR it config-lints the committed config at the
pinned marketplace ref and asserts the settings ref and lockfile ref agree, so a
half-done upgrade PR is caught server-side. It reports a red check; you make it a *gate*
by marking "second-shift evidence" a required status check in branch protection. That's
why doctor says "missing your accelerators" instead of anything compliance-shaped: 80%
adoption plus server-side enforcement beats 100% by nagging.

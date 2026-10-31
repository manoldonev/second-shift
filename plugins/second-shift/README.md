# second-shift

The setup and health plugin for the second-shift toolkit. Install it once per machine, then run it in each repo you want to use the toolkit in.

- `/second-shift:onboard` detects the repo's tracker (GitHub Issues or JIRA) and its install, lint, typecheck and test commands, shows you the whole config on one screen to accept or edit, and writes `.claude/second-shift.config.json`, the plugin pins in `.claude/settings.json`, `.claude/second-shift.lock.json` and a consent note, `.claude/SECOND-SHIFT.md`.
- `/second-shift:doctor` checks what is installed against the committed lockfile and prints the exact command for each problem it finds.
- `/second-shift:local-dev-refresh` updates this machine's second-shift plugins.

## Examples

1. **Set up a repo.** In the repo, run `/second-shift:onboard`. It finds your tracker and commands, asks its questions in one batch, shows the whole config for you to accept or edit, then writes it and pins the plugins. Restart Claude Code and accept the plugin prompts.
2. **A fresh clone where the commands are missing.** Run `/second-shift:doctor`. It lists each plugin the lockfile pins that this machine lacks or holds at the wrong version, with the exact install or update command for each.
3. **After a new second-shift release.** Run `/second-shift:local-dev-refresh`. It updates the marketplace catalog and every second-shift plugin on this machine, and prints each version before and after.

## Installed from the plugin directory?

The directory copy is the way in, not the copy a repo runs on. Each repo pins its plugins to a second-shift release, and the directory copy updates outside that pin. So `/second-shift:onboard` and `/second-shift:doctor` print the install of the pinned copy (`claude plugin marketplace add manoldonev/second-shift`, then `claude plugin install second-shift@second-shift`), followed by the uninstall of the directory copy.

## What it runs and sends

It runs `git`, `jq`, `gh` and the `claude plugin` commands on your machine. `gh` reads the second-shift releases on GitHub to pick a pin and, if you say yes, creates the tracker labels in your repo. Nothing is sent anywhere else. It has no hooks and no agents.

It reads no credentials. `gh` uses its own login, and onboard only checks whether `gh auth status` succeeds. When doctor prints the repo config for a bug report, it masks the value of every key named like a secret (token, password, API key and similar).

## More

Setup walkthrough: [the second-shift README](https://github.com/manoldonev/second-shift#get-started). License: MIT.

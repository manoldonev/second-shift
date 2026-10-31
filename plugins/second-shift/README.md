# second-shift

The setup and health plugin for the second-shift toolkit. Install it once per machine, then run it in each repo you want to use the toolkit in.

- `/second-shift:onboard` detects the repo's tracker (GitHub Issues or JIRA) and its install, lint, typecheck and test commands, shows you the whole config on one screen to accept or edit, and writes `.claude/second-shift.config.json`, the plugin pins in `.claude/settings.json`, `.claude/second-shift.lock.json` and a consent note, `.claude/SECOND-SHIFT.md`.
- `/second-shift:doctor` checks what is installed against the committed lockfile and prints the exact command for each problem it finds.
- `/second-shift:local-dev-refresh` updates this machine's second-shift plugins.

## What it runs and sends

It runs `git`, `jq`, `gh` and the `claude plugin` commands on your machine. `gh` reads the second-shift releases on GitHub to pick a pin and, if you say yes, creates the tracker labels in your repo. Nothing is sent anywhere else. It has no hooks and no agents.

## More

Setup walkthrough: [the second-shift README](https://github.com/manoldonev/second-shift#get-started). License: MIT.

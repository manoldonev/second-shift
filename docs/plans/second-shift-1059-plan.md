# Plan — #1059 this repo commits its config, keeping only the bot app identity machine-local

Record: docs/plans/second-shift-1059-decisions.md

## 1. The per-engineer file accepts the app keys

- [ ] 1.1 config-lint cases: a local file with the four `tracker.bot.app` keys and `tracker.branchPrefix` passes; one with `tracker.bot.enabled` or an unknown app key still fails (plugins/dev-pipeline/tools/config-lint-selftest.sh) [AC-4]
- [ ] 1.2 config-lint accepts `tracker.bot.app.{clientId,appName,privateKeyFilename,installationId}` in the local file, any value type, and names the widened rule in its error (plugins/dev-pipeline/tools/config-lint.sh)
- [ ] 1.3 run.sh cases: a local file with the app keys launches; one with `tracker.bot.enabled` or an unknown app key stops on `env-config-local` naming the key (plugins/dev-pipeline/skills/run/run-bot-local-selftest.sh) [AC-4]
- [ ] 1.4 run.sh C6a accepts the four app keys beside `tracker.branchPrefix` and refuses every other key (plugins/dev-pipeline/skills/run/run.sh)

## 2. bot-commit.sh reads the app keys from the main checkout

- [ ] 2.1 bot-commit cases: with the app block only in the main checkout's gitignored local file, a commit from a worktree whose committed config has no app block, and one with `SECOND_SHIFT_CONFIG` at a copy of that config, both carry `<appName>[bot]`; a local `appName` overrides a committed one; a local file beside the override copy is not read (plugins/dev-pipeline/tools/bot-commit-selftest.sh) [AC-1]
- [ ] 2.2 bot-commit.sh reads `<main checkout>/.claude/second-shift.config.local.json` whichever config candidate wins, honoring `SECOND_SHIFT_REPO_ROOT`; `enabled` stays from the config; the WARN names both files (plugins/dev-pipeline/tools/bot-commit.sh)

## 3. run.sh warns when no appName resolves

- [ ] 3.1 run.sh cases: bot enabled, wrapper working, `appName` in neither file prints the launch warning and the run still reaches a verdict; `appName` only in the main checkout's local file prints no warning and the record commit carries the bot identity (plugins/dev-pipeline/skills/run/run-bot-local-selftest.sh) [AC-3]
- [ ] 3.2 run.sh, where `BOT_OK` is set: resolve `appName` from the main checkout's local file, else the config, and warn without refusing when neither has it (plugins/dev-pipeline/skills/run/run.sh)

## 4. install-gh-bot.sh reads the local file

- [ ] 4.1 unchecked by the record (D-17), so no suite: the build probes the precedence and the `clientId` refusal by hand in its scratch dir, and the review reads the script (plugins/dev-pipeline/tools/install-gh-bot.sh) [AC-5]
- [ ] 4.2 install-gh-bot.sh: precedence flags, then the main checkout's local file, then the committed config, then defaults; refuse when no source supplies `clientId`, naming the three sources (plugins/dev-pipeline/tools/install-gh-bot.sh)

## 5. This repo commits its config

- [ ] 5.1 repo suite: the committed `.claude/second-shift.config.json` exists at HEAD and carries no `tracker.bot.app` block and no app key anywhere (scripts/committed-config-selftest.sh) [AC-2]
- [ ] 5.2 commit `.claude/second-shift.config.json` as the current config minus `tracker.bot.app`; drop its `.gitignore` entry and comment, keep the local-file entry (.claude/second-shift.config.json, .gitignore)

## 6. Docs and the gates that state the rule

- [ ] 6.1 the per-engineer rule names the app keys: config-schema doc, schema descriptions, onboard skill prose note, README stop table, shadowing check rows (docs/config-schema.md, schema/second-shift.config.schema.json, plugins/second-shift/skills/onboard/SKILL.md, README.md, plugins/dev-pipeline/tools/check-config-shadowing.sh)

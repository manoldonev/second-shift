# #1048 task plan — lane sessions still compose commands the allowlist cannot approve

## 1. The build's grants and prompt

- [ ] 1.1 Scenario in run-claim-selftest: the build spawn's --allowedTools carries Grep and Glob and no Bash grep, ls, wc or head rule (run-claim-selftest.sh) [AC-1]
- [ ] 1.2 Scenario in run-claim-selftest: a configured `… | xargs -0 shellcheck -e SC1091,…` check grants `shellcheck -e …` on its own under granted(), value-taking xargs options are skipped, and an xargs segment running rm, a shell, env, eval, exec, sudo, nohup, cd or python3 adds no derived grant; the review allowlist gains none (run-claim-selftest.sh) [AC-2]
- [ ] 1.3 Scenario in run-claim-selftest: granted() passes `gh pr edit 7 --body-file /x/b.md` on the build allowlist (run-claim-selftest.sh) [AC-3]
- [ ] 1.4 Scenario in run-claim-selftest: the build prompt says to run the listed checks and the tests the change touches, never a verification list from the repo's CLAUDE.md or docs (run-claim-selftest.sh) [AC-4]
- [ ] 1.5 Scenario in run-claim-selftest: the github prompt's ticket-fetch command, read out of the prompt, is granted by the build allowlist; the jira prompt names getJiraIssue (run-claim-selftest.sh) [AC-5]
- [ ] 1.6 run.sh: Grep and Glob and `Bash(gh pr edit * --body-file *)` on build_allowlist; cmd_grants derives the command an xargs segment runs (build only, option values skipped, never a bare word, under the existing exclusions); build_prompt names the ticket fetch and the never-CLAUDE.md verification sentence (plugins/dev-pipeline/skills/run/run.sh)

## 2. The PermissionRequest hook

- [ ] 2.1 Scenario in run-claim-selftest: the build spawn's --settings JSON holds a PermissionRequest hook whose command runs the dev-pipeline tools script; the review spawn's --settings has no hooks key (run-claim-selftest.sh) [AC-6]
- [ ] 2.2 lane-permission-hook-selftest: fed PermissionRequest input, the hook gives the withheld reason for a main-checkout file-tool path, a Bash absolute path and a `..` escape, the single-command reason for `$( )`, backticks, `|`, `;`, `&&`, `||` and cd, the tool reason for grep, find, ls, wc, head, cat and tail, the not-granted reason otherwise, and the first that applies when several do (plugins/dev-pipeline/tools/lane-permission-hook-selftest.sh) [AC-7]
- [ ] 2.3 lane-permission-hook-selftest: Edit and Write to <wt>/.claude/SECOND-SHIFT.md are allowed; <wt>/.claude/settings.json, settings.local.json, <wt>/.claude/agents/x.md and a `..` or symlink path that escapes are denied with a reason naming the path (plugins/dev-pipeline/tools/lane-permission-hook-selftest.sh) [AC-8]
- [ ] 2.4 The hook script, and the build spawn's --settings wiring it with the worktree and scratch roots (plugins/dev-pipeline/tools/lane-permission-hook.sh, plugins/dev-pipeline/skills/run/run.sh)

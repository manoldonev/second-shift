# Intake receipt — #1048 dev-pipeline: lane sessions still compose commands the allowlist cannot approve

Receipt: v4

## Intake steps

Requirements: the ticket body as written — spec-reviewer: needs-spec-work (2 blockers: no acceptance criteria, undecided directions; 7 gaps), closed in the interview; AC-1–AC-8 and PM-1 appended to the body on the operator's yes
Split: not triggered — no epic label, one deliverable; re-checked when the register reached 10 decisions: not split — every row lands in run.sh's build allowlist, prompt and spawn settings plus one hook script and its selftest
Explore: done — run.sh's build/review allowlists, cmd_grants, build prompt and spawn settings; run-claim-selftest's grant model; the post-#1007 denial logs; the CLI's --help and permission docs; an operator-run probe of PermissionRequest and PreToolUse hooks under the lane's spawn flags; the implementability probe (one round, 10 guess-points: 2 settled by the probe, 2 from code, 6 asked)
Fan-out: skipped — by the operator at the intake notice
Dup-scan: no candidates at or above threshold 12
Post-merge scan: the ticket's denial-count target moved out of acceptance into PM-1 on the operator's yes (D-9)
Sizing: opus

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the build looks things up | The build allowlist gains the Grep and Glob tools (as the review's already has); no Bash grep, ls, wc or head rule is added; `claude plugin list` stays denied | user-answered | intent |
| D-2 | Running one tool of a configured check on the files a change touches | cmd_grants' derivation also grants the command an xargs segment runs, by the same cut prefix, under the existing rm/shell/env/eval/exec/sudo/nohup/cd/python3 exclusions — generic for every consumer, not a shellcheck special case | user-answered | intent |
| D-3 | `gh pr edit --body-file` | Granted as `Bash(gh pr edit * --body-file *)`. The operator chose this over the recommendation (comment-only); the scheduler's PR-body shape check (run.sh `pr_conventions`, line-1 `built-by:`) stays the backstop | user-answered | intent |
| D-4 | Verification lists from the repo's CLAUDE.md or docs | One build-prompt line in run.sh: run the checks listed and the tests the change touches, never a verification list from the repo's CLAUDE.md or docs. This repo's CLAUDE.md is not edited | user-answered | intent |
| D-5 | How the build fetches its ticket | The build prompt names the literal command: github `gh issue view <issue> --json title,body,comments`; jira the getJiraIssue MCP tool (both denials of the `$( )` shape were this fetch, as the build's first command) | user-answered | intent |
| D-6 | Mechanism that turns an opaque denial into an instruction | A PermissionRequest hook, a dev-pipeline tools/ script wired into the build spawn's --settings. Weighed: a PreToolUse hook (the ticket's direction; fires on granted calls too, so it must re-implement the allowlist and exempt every configured check), prompt plus grants only (denials stay opaque), and this one (fires only on calls the allowlist would deny, so it can never block a granted command). The allowlist stays the only grant | user-answered | intent |
| D-7 | Edits under the worktree's `.claude/` | The hook allows Edit and Write to a file directly in <wt>/.claude/ except settings.json and settings.local.json; it denies those two and every file in a subdirectory (agents/, skills/, commands/, hooks/, rules/ …), which the session loads. Re-asked once after the first framing named only the settings files as session-altering | user-answered | intent |
| D-8 | Whether the review spawn gets the hook | Build only; the review spawn's --settings is unchanged (every denials-review file since #1007 is empty, and the .claude/ allow must never reach the review) | user-answered | intent |
| D-9 | How success is measured | PM-1, shape-based over the next 5 lane build sessions after the release; the ticket's raw denial-count target moved out of acceptance because no diff can satisfy it | user-answered | intent |
| D-10 | review panel | security | user-answered | intent |
| D-11 | How the hook classifies pipes and the other read helpers | `\|` joins `;` `&&` `\|\|` in the compound shape (run each command on its own); the lookup reason covers grep, find, ls, wc, head, cat and tail and points at the Grep, Glob or Read tool | user-answered | intent |
| D-12 | Which reason wins when a call matches several shapes | First that applies: withheld path, then compound shape, then lookup tools, then not granted — a withheld path first because no rewrite reaches it | user-answered | intent |
| D-13 | What the withheld-path check reads | File-tool inputs (file_path, path) and every absolute-path word of a Bash command, resolved for `..` and symlinks before comparing with the worktree and scratch roots; the same normalization guards D-7's allow | user-answered | intent |
| D-14 | AC-2's parser details: an uncut xargs segment, build-only vs in-place derivation, value-taking xargs options | parked under OR-1 with stated defaults the build takes and names in the PR (owner: operator, at the PR review) | deferred | open |
| D-15 | Whether a PermissionRequest hook fires under `-p --permission-prompts none` and can lift the .claude/ protection | Yes to both: it fired only for the ungranted .claude/ Edit, and its allow let that Edit through — run: `bash <scratchpad>/probe-1048.sh` → deny run: PermissionRequest fired for `Edit` only; allow run: `.claude/NOTES.md=new` (Claude Code 2.1.296, acceptEdits, --permission-prompts none) | codebase-derived | fact |
| D-16 | Whether hook denials reach the count read_denials takes | Yes: both a PermissionRequest deny and a PreToolUse deny land in the result JSON's permission_denials, with the reason shown to the model, so denials-*.txt keeps counting them unchanged — run: `jq -c '[.permission_denials[].tool_name]' out-deny.json out-allow.json` → `["Edit","Bash"]` `["Bash"]` | codebase-derived | fact |
| D-17 | Where the hook script lives | plugins/dev-pipeline/tools/, reached as $TOOLS, with a `*-selftest.sh` beside it that the sweep discovers by glob — run: `ls plugins/dev-pipeline/tools \| grep -c -- '-selftest.sh$'` → 13; `grep -n '^TOOLS=' run.sh` → 171 | codebase-derived | fact |
| D-18 | Wiring through the spawn, not the plugin's hooks.json | dev-pipeline's hooks.json loads in every session where the plugin is enabled, interactive ones included, so the hook is passed only in the build spawn's --settings — run: `jq -r '.hooks\|keys[]' plugins/dev-pipeline/hooks/hooks.json` → PreToolUse | codebase-derived | fact |
| D-19 | The jira half of AC-5 | Name getJiraIssue under whichever Atlassian namespace the session exposes, as the tracker README does; MCP_ALLOW already grants all three — run: `grep -c getJiraIssue plugins/dev-pipeline/tools/tracker/README.md` → 2 | codebase-derived | fact |
| D-20 | Whether AC-4 replaces the existing check lines | It adds one negative sentence beside the existing "rerun only the test file or suite your change touches" line — run: `grep -c 'rerun only the test file or suite your change touches' run.sh` → 1 | codebase-derived | fact |
| D-21 | Which absolute-path words of a Bash command the withheld check skips | `/dev/null`, `/dev/stdin`, `/dev/stdout` and `/dev/stderr` are no path: otherwise the `2>/dev/null \|\| …` ticket fetch, the ticket's top shape, would get the withheld reason instead of the single-command one. Every other absolute word is checked, as D-13 states | user-delegated | intent |
| D-22 | What the compound shape reads beyond D-11's list | A newline also counts as a chain; a `\|`, `;` or `&&` inside quotes is no operator, and `$( )` or a backtick inside single quotes is no substitution — so `grep -E 'a\|b'` gets the lookup reason D-11 names for grep, not the single-command one | user-delegated | intent |
| D-23 | Case on the D-7 settings files | The hook compares the basename case-insensitively, so `.claude/SETTINGS.JSON`, which a case-insensitive disk opens as settings.json, is denied like it | user-delegated | intent |
| D-24 | Where OR-1's value-skipping applies | Also to cmd_grants' existing xargs exclusion, which read the value of `-n 1` as the command xargs runs: `… \| xargs -n 1 rm -f a,b` no longer grants `Bash(xargs -n 1 rm -f*)`. The derivation runs on every build cmd_grants call — the configured checks and the render command — and on none of the review's | user-delegated | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | AC-2's parser details: an xargs segment cmd_grants does not cut, whether the derivation is build-only, and xargs options that take a value | reversible-default-and-flag |
| OR-2 | A PermissionRequest allow lifting the .claude/ protected-path denial is undocumented, measured on Claude Code 2.1.296 only | reversible-default-and-flag |

OR-1's defaults, chosen by the operator as defaults to flag: derived grants are build-only (AC-2 names the build allowlist; the review's render grant is unchanged); value-taking xargs options (`-n -P -L -I -d -s -E -a`) skip their value when finding the command xargs runs; an uncut segment grants its inner command's own text plus `*` when it is two words or more, never a bare word. Each is a one-line parser change to reverse; the PR body names them.

OR-2's default is to rely on it. If a later CLI stops honoring the allow, the edit falls back to a denial carrying the hook's reason, which opens nothing new, so reversing costs only the D-7 convenience.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The denial reason text a build session reads | decided (D-6) |
| S-2 | Which reason a call that matches several shapes gets | decided (D-12) |
| S-3 | denials-*.txt and the run block's per-session denial count in the watch | decided (D-16) |
| S-4 | The build prompt | decided (D-4) |
| S-5 | The build's first command, the ticket fetch | decided (D-5) |
| S-6 | The PR body after a later round edits it | decided (D-3) |
| S-7 | Files under <wt>/.claude/ in the PR diff | decided (D-7) |
| S-8 | The review session's prompt, grants and denials | decided (D-8) |
| S-9 | The review's specialist panel on this PR | decided (D-10) |
| S-10 | Interactive sessions where dev-pipeline is enabled | decided (D-18) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

## Knowledge source

Knowledge source: none declared

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7 AC-8

AC-1: the build spawn's --allowedTools carries Grep and Glob and no Bash rule granting grep, ls, wc or head
AC-2: a configured check `… | xargs -0 shellcheck -e SC1091,…` puts a rule granting `shellcheck -e …` on its own on the build allowlist, and an xargs segment that runs rm, a shell, env, eval, exec, sudo, nohup, cd or python3 adds no derived grant
AC-3: the build allowlist grants `gh pr edit 7 --body-file /x/b.md` under the selftest's granted() model
AC-4: the build prompt tells the session to run the listed checks and the tests its change touches, never a verification list from the repo's CLAUDE.md or docs
AC-5: the build prompt's ticket-fetch command on github is granted by the build allowlist, and under jira the prompt names getJiraIssue
AC-6: the build spawn's --settings JSON holds a PermissionRequest hook running the dev-pipeline tools script, and the review spawn's --settings holds no hooks key
AC-7: the hook script, fed PermissionRequest input, gives the withheld reason for a main-checkout path (a file tool, a Bash absolute path, a `..` escape), the single-command reason for `$( )`, backticks, `|`, `;`, `&&`, `||` and cd, the tool reason for grep, find, ls, wc, head, cat and tail, and the not-granted reason otherwise, in that precedence
AC-8: the hook script allows Edit and Write to <wt>/.claude/SECOND-SHIFT.md and denies <wt>/.claude/settings.json, settings.local.json, <wt>/.claude/agents/x.md and a `..` or symlink path that escapes, each with a reason naming it

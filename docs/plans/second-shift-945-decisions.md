# Intake receipt — #945 herdr launcher for parallel interactive builds

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Whether build mode gets herdr support at all | Yes, as a launcher (not a watcher): the operator asked to intake it after #939 scoped build out | user-answered | intent |
| D-2 | Lane admission | On the operator's word, stated in the body as a written departure from the consumer-evidence rule, as for #939 | user-answered | intent |
| D-3 | How the review session starts | An explicit `review <pr>` command, never automatic on draft PR | user-answered | intent |
| D-4 | Launch shape | One command for many tickets: `build <n>...`, each ticket independent, a failure reported per ticket | user-answered | intent |
| D-5 | Editor in build mode | Opened once the worktree appears, via the same opt-in `RUN_WATCH_EDITOR`, from a detached waiter with a 5-minute bound | user-answered | intent |
| D-6 | Where the review session opens | A new `review` tab in the ticket's workspace | user-answered | intent |
| D-7 | Where it lives | New `build` and `review` subcommands of plugins/dev-pipeline/skills/run/herdr-adapter.sh, dispatched before its four-argument watch call; reuses the label lookup and the fixed-text plus `--env` pane rule | codebase-derived | fact |
| D-8 | Main checkout and repo slug | Superseded by D-23: the literal run.sh derivation breaks from a subdirectory and through a symlink | codebase-derived | fact |
| D-9 | Worktree path for `--add-dir` | `${RUN_WORKTREE_ROOT:-<parent of main>/<repo>-worktrees}/<n>` (run.sh:213); `RUN_WORKTREE_ROOT` forwarded to the pane when set | codebase-derived | fact |
| D-10 | A missing `--add-dir` path at launch | claude 2.1.292 accepts it: probed, started and ended its turn normally, created nothing. Edits after the handoff creates it are parked under OR-1 | codebase-derived | fact |
| D-11 | Sidebar state | Not reported by second-shift: herdr's screen manifests read interactive Claude Code sessions natively | codebase-derived | fact |
| D-12 | Review's ticket lookup | Superseded by D-30: the repo's two `Closes` readers disagree, and Jira PRs use `Closes [KEY]` | codebase-derived | fact |
| D-13 | Recognizing a herdr-started build session in the skill | `SS_WT` set in its environment; step 5 prints `bash "<SS_ADAPTER>" review <pr>` with the path expanded | codebase-derived | fact |
| D-14 | Never-do list | No worktree create/remove, server, send-text/keys, agent start/prompt, integration, workspace close or report-agent; no pane-identity fallbacks; nothing written to run.sh, the record or the tracker | codebase-derived | fact |
| D-15 | Duplicate scan | dup-scan on the draft: no candidates | codebase-derived | fact |
| D-16 | Edits in the worktree without a prompt after `--add-dir` on a then-missing path | Parked under OR-1; the step-2 `/add-dir` instruction stays as the fallback | deferred | open |
| D-17 | Pane environment source | Panes take the herdr SERVER's environment, plus --env extras and identity vars (herdr src/workspace.rs:304-363), not the caller's; herdr strips CLAUDECODE/CLAUDE_CODE_* (src/pane.rs:176-184) but not CLAUDE_CONFIG_DIR | codebase-derived | fact |
| D-18 | Seat routing for pane sessions | Fixed texts start with `env -u CLAUDE_CONFIG_DIR` so the seat shim routes by the pane's cwd even when the server inherited a seat | codebase-derived | fact |
| D-19 | Sidebar state source | herdr's Claude manifest (src/detect/manifests/claude.toml) reads the interactive session's screen | codebase-derived | fact |
| D-20 | Duplicate scan | dup-scan --issue 945: no candidates | codebase-derived | fact |
| D-21 | Spec self-check | Two spec-review loops at intake, the second clean; this pre-flight amendment folds in the fan-out facts below | codebase-derived | fact |
| D-22 | Prompt position in the build pane text | Prompt before `--add-dir` (`claude "/dev-pipeline:build $SS_ISSUE" --add-dir "$SS_WT"`); `--add-dir <directories...>` is variadic and swallowed it (probed on 2.1.294) | codebase-derived | fact |
| D-23 | Main checkout and slug derivation | Physical parent of `git rev-parse --path-format=absolute --git-common-dir`, its basename as slug; correct from subdirectories, linked worktrees and symlinks (probed) | codebase-derived | fact |
| D-24 | Allowed herdr verbs in build/review | Allow-list: workspace list/create, tab create, pane wait-output, pane run with fixed text (`pane run` is PaneSendInput, a different wire method from the forbidden send-text, herdr src/cli/pane.rs:1025,1046-1050) | codebase-derived | fact |
| D-25 | Duplicate tickets in one build call | Opened once; herdr does not keep labels unique (src/app/api/workspaces.rs:39-80) | codebase-derived | fact |
| D-26 | Workspace cwd in build mode | The main checkout, which exists at launch (the worktree does not) | codebase-derived | fact |
| D-27 | Typing into a freshly spawned login shell | Wait up to 10 s for the pane's first output (pane wait-output) before pane run, then type anyway with one line; the race itself is parked under OR-2 | codebase-derived | fact |
| D-28 | How the session reads its signal | Bash-tool `printenv SS_WT SS_ADAPTER`; the --env extras survive herdr's strip and reach the Bash tool | codebase-derived | fact |
| D-29 | Selftest shape | Fake herdr gains a per-label failure switch, unique ids per call and the real server_not_running JSON on stderr; the forbidden-verb guard becomes per-mode (report-agent is legal in watch mode); a git fixture for AC-0/AC-3; a gh fake for review; editor waiter cases set SS_EDITOR_WAIT_SECS, a case-local TMPDIR, an appending fake editor, redirected stdio, and poll a file (bash 3.2 on CI, no wait on the waiter); AC-12 is model behavior and has no model-free guard | codebase-derived | fact |
| D-30 | Review's ticket resolution | GitHub: `gh pr view <pr> --json closingIssuesReferences`; Jira: `Closes [<KEY>]` under `### Jira Items`, the review skill's rule; exactly one ticket, else exit 1 naming what was found | codebase-derived | fact |
| D-31 | Tracker support | Both trackers: build accepts what the repo's tracker accepts (GitHub integers, Jira keys), review resolves per tracker | user-answered | intent |
| D-32 | Editor waiter detachment | run.sh's own idiom: nohup + perl POSIX::setsid + exec, stdio to /dev/null (probed: re-parented to pid 1, survives the launching group's HUP/TERM) | codebase-derived | fact |
| D-33 | Editor once per worktree | A per-ticket lock under TMPDIR; a re-launch while a waiter waits starts no second one (probed: two waiters opened two windows) | codebase-derived | fact |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether a session started with `--add-dir` on a not-yet-existing path edits inside it without prompting once the handoff creates it | reversible-default-and-flag |
| OR-2 | Whether text typed by `pane run` into a freshly spawned login shell can be lost while the operator's rc files load (watch mode shares the race; unmeasured) | reversible-default-and-flag |

OR-1's default is to pass `--add-dir` and keep the manual `/add-dir` as the documented fallback. If the operator's trial shows edits prompting, the cost is one typed command per build, and dropping the flag is a one-line change. OR-2's default waits for the pane's first output before typing; if the trial still loses keystrokes, the wait condition changes in one place and the operator retypes one line meanwhile.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The `<repo>#<n>` workspace and its `build` tab with the interactive build session | decided (D-4) |
| S-2 | The `review` tab with the fresh review session | decided (D-6) |
| S-3 | The VS Code window on the worktree | decided (D-5) |
| S-4 | The waiter's give-up log | decided (D-5) |
| S-5 | The adapter's per-ticket failure lines and exit codes | decided (D-4) |
| S-6 | The herdr sidebar state of each session | decided (D-11) |
| S-7 | build/SKILL.md step 2 and step 5 lines | decided (D-13) |
| S-9 | The 'did not see the shell ready' line and the review's 'no single ticket' message | decided (D-27) |
| S-10 | Jira workspaces labeled `<repo>#<KEY>` and Jira review resolution | decided (D-31) |
| S-8 | The tracker, PR, run block and decision record | out-of-scope — build and review mode write nothing there (AC-11) |

## Checks

- `bash plugins/dev-pipeline/skills/run/herdr-adapter-selftest.sh`

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: herdr-cli-contract opus 6/6 · pane-to-session-boundary fable 6/6 · input-derivation-parity opus 5/6 · waiter-lifecycle-and-testability fable 6/6 · premortem fable 4/5
Tally: rows added 12 · snapshot claims overturned 2 · questions added 1
Checkouts: herdr (/Users/manoldonev/work/herdr) read by every lens

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | herdr-cli-contract | tab create cannot start a command; the text reaches the pane only through pane run, typed into the default shell | new | became D-24 |
| F-2 | herdr-cli-contract | workspace create adds an idle first tab, so a fresh ticket workspace has two tabs | not material | not material — the same as watch mode |
| F-3 | herdr-cli-contract | Server down: about 12 ms, exit 1, a JSON error on stderr; the fake prints plain text | new | became D-29 |
| F-4 | herdr-cli-contract | Labels are not unique; tab create without ids falls back to the active workspace and focused cwd | new | became D-25 |
| F-5 | herdr-cli-contract | The fake cannot fail one ticket or tell ids apart; the forbidden-verb guard must become per-mode | new | became D-29 |
| F-6 | herdr-cli-contract | The workspace create cwd in build mode is unspecified while the worktree does not exist | new | became D-26 |
| F-7 | pane-to-session-boundary | `--add-dir` is variadic and swallows a prompt placed after it (probed on 2.1.294) | new | became D-22 |
| F-8 | pane-to-session-boundary | pane run is PaneSendInput, a different wire method from the forbidden send-text | new | became D-24 |
| F-9 | pane-to-session-boundary | The pane shell is a login zsh; rc files run before the typed text and may override --env | new | became D-27 |
| F-10 | pane-to-session-boundary | herdr strips CLAUDE_CODE_* from panes, the --env extras survive, and the Bash tool can read them | already-had | snapshot D-17 / D-18 |
| F-11 | pane-to-session-boundary | A missing `--add-dir` path is accepted on 2.1.294 when the prompt comes first | already-had | snapshot D-10 |
| F-12 | pane-to-session-boundary | The skill gives the session no way to read SS_WT; it needs a printenv step | new | became D-28 |
| F-13 | input-derivation-parity | The literal run.sh derivation breaks from a subdirectory (env-main-root) | overturned (snapshot D-8: parent of --git-common-dir as run.sh:140-143) | became D-23 |
| F-14 | input-derivation-parity | Through a symlink, the literal derivation gives a different slug from run.sh | new | became D-23 |
| F-15 | input-derivation-parity | The repo's two `Closes` readers disagree, and neither handles every form | overturned (snapshot D-12: the PR body's `Closes #<n>` line) | became D-30 |
| F-16 | input-derivation-parity | `gh pr view --json closingIssuesReferences` gives GitHub's own parse | new | became D-30 |
| F-17 | input-derivation-parity | Under Jira, build and review as written have no path | new | became D-31 |
| F-18 | waiter-lifecycle-and-testability | run.sh's setsid idiom gives a waiter that survives the launcher (probed) | new | became D-32 |
| F-19 | waiter-lifecycle-and-testability | A per-launch waiter opens the editor twice on a re-launch (probed) | new | became D-33 |
| F-20 | waiter-lifecycle-and-testability | CI runs bash 3.2 on macOS; waiter cases must poll a file | new | became D-29 |
| F-21 | waiter-lifecycle-and-testability | A model-free test sees only the argv the fake received, not shell expansion | new | became D-29 |
| F-22 | waiter-lifecycle-and-testability | Which ACs the fakes can observe; AC-12 is model behavior | new | became D-29 |
| F-23 | waiter-lifecycle-and-testability | Test hygiene: wait override, case-local TMPDIR, stdio redirect, trailing slash on darwin TMPDIR | new | became D-29 |
| F-24 | premortem | The swallowed prompt leaves every build tab a bare session | new | became D-22 |
| F-25 | premortem | Under Jira both subcommands refuse every ticket | new | became D-31 |
| F-26 | premortem | Typed text can race the login shell's rc load | new | became D-27 |
| F-27 | premortem | If the missing `--add-dir` path is dropped, the fallback becomes the normal path | already-had | snapshot OR-1 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1..D-16 | (the intake receipt's rows, unchanged) | as recorded in 945-ledger.md |
    | D-17 | Pane environment source | herdr panes take the herdr SERVER's environment plus --env extras plus identity vars (herdr src/workspace.rs:304-363), not the caller's: RUN_WORKTREE_ROOT must be forwarded explicitly |
    | D-18 | Seat routing for sessions started in panes | A server started with CLAUDE_CONFIG_DIR set would hand it to every pane and bypass the per-repo seat shim; the fixed pane text starts with `env -u CLAUDE_CONFIG_DIR` so the shim routes by the pane's cwd |
    | D-19 | herdr sidebar state for an interactive Claude session | herdr ships a Claude manifest (src/detect/manifests/claude.toml) that reads the session's screen |
    | D-20 | PR body's Closes line | Lane PRs carry `Closes #<n>` as a line of its own (PR #941 body line 30) |
    | D-21 | Duplicate scan | dup-scan --issue 945: no candidates |

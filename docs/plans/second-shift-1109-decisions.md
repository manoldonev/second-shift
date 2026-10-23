# Decision record — #1109 Lane BUILD cannot make a new script executable, and its workaround stops the run as build-inflight

Receipt: v4

## Summary

The BUILD's PermissionRequest hook allows `chmod +x` on files in the worktree. The session's own `chmod` then sets the bit on disk, `git add` commits `100755`, and the tree stays clean. `build_allowlist`, the build prompt and `worktree_inflight` do not change.

Open regions: OR-1, the denial text for a `chmod` outside the accepted form. The default is the hook's existing messages.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Route that sets the executable bit | `lane-permission-hook.sh` returns allow for an accepted `chmod +x` call. `build_allowlist`, the build prompt and `worktree_inflight` stay unchanged. A mode-only tracked entry stays in-flight work. | user-answered | intent |
| D-2 | Accepted chmod form | Exactly `chmod +x` followed by one or more operands. No operand starts with `-`. The allow applies only after the hook's withheld and compound checks pass. Every other `chmod` keeps today's denial. | user-answered | intent |
| D-3 | Paths an allowed chmod may touch | Every operand resolves inside the worktree, after `..` and symlinks resolve. The scratch dir is not allowed. A path in a subdirectory of the worktree's `.claude/` is denied, as for Edit and Write. | user-answered | intent |
| D-4 | AC wording for the hook route | AC-1 and AC-3 on #1109 were amended at intake, on the operator's yes. AC-1 bounds the route by path resolution. AC-3 names the hook selftest cases. AC-2 is unchanged. | user-answered | intent |
| D-5 | How AC-2 is proved | A `holds` test. A fake-claude build runs `chmod +x` on a new script, `git add` and commit, and the run reaches the review with a clean tree. | user-answered | intent |
| D-6 | A build prompt line for chmod | None. The observed session tried `chmod +x` first, and the allow makes that call work. The prompt and `run.sh` stay unchanged. | user-answered | intent |
| D-7 | Base for a relative operand | The input's `cwd`, else the worktree argument. The non-Bash branch already joins relative paths this way. run: `git show origin/main:plugins/dev-pipeline/tools/lane-permission-hook.sh \| grep -n 'CWD='` → `53:CWD="$(jq -r '.cwd // ""' <<<"$IN")"; case "$CWD" in /*) ;; *) CWD="$1" ;; esac` | codebase-derived | fact |
| D-8 | Session-launch test for the hook change | A `run-claim-selftest.sh` case runs the BUILD's hook as its `--settings` writes it, through `hook_says`. It fails unless the hook allows `chmod +x` on a worktree file. The lane-file allow shipped the same way. cited (convention): CLAUDE.md:71 | codebase-derived | fact |
| D-9 | Git mode behavior on the chosen route | `chmod +x` on disk, then `git add` and commit, records `100755` and leaves no tracked dirt. A later `git add` of a file set by `git update-index --chmod=+x` copies `100644` back. run: `bash gitmode.sh` → d.sh HEAD mode 100755, absent from status; c.sh index mode after a later git add 100644 | codebase-derived | fact |
| D-10 | Denial text for a chmod outside the accepted form | Parked under OR-1. Owner: the build, which uses the stated default. Resolve it before the PR leaves draft. | deferred | open |
| D-11 | Which operand words the allow accepts | Each operand is a plain word: letters, digits and `. _ / @ % + , : = -`. A word with a quote, `$`, `~`, a glob, a brace, a backslash, a redirect or `&` gets the not-granted message. Added in build: the shell expands such a word after the hook resolves it, so `l*nk/x` or `$HOME/x` would reach a path the hook never checked. A word that starts with `=` also gets the not-granted message. Changed in build: the build's Bash tool runs zsh, which expands a leading `=git` to the path of `git`, outside the worktree. | user-delegated | intent |
| D-12 | Case of the `.claude/` subdirectory check | The hook compares the operand's path below the worktree in lower case, so `.CLAUDE/hooks/x.sh` is denied as `.claude/hooks/x.sh`. Added in build: a case-insensitive disk opens both names as one file, and the hook's settings.json check already lowercases for that reason. | user-delegated | intent |

Options weighed:

- D-1: a hook allow, a `Bash(chmod +x $WT/*)` grant with a prompt line, the hook's denial text naming the git route, or scheduler collection with a `git checkout --` restore. The operator chose the hook allow.
- D-2: exactly `+x`, or also `u+x`, `a+x`, `755` and `-x`. The operator chose exactly `+x`.
- D-3: the worktree without `.claude/` subdirectories, the whole worktree, or the worktree and the scratch dir. The operator chose the worktree without `.claude/` subdirectories.
- D-4: amend the ticket's ACs, or keep them and record a departure. The operator chose to amend them.
- D-5: a `holds` run scenario, the same plus a post-merge check, or a behavior test that fails without the change. The operator chose the `holds` run scenario.
- D-6: no prompt line, or a line naming `chmod +x`. The operator chose no prompt line.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Denial text for a chmod outside the accepted form | reversible-default-and-flag |

OR-1 default: a `chmod` outside the accepted form gets the hook's existing withheld or not-granted message. This covers other modes, quoted operands and operands outside the worktree. The intake session chose it, from the probe's guess-point. Reversing it costs one message string and one selftest case.

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: the hook allows `chmod +x` when every operand resolves inside the worktree, and denies one whose operand resolves outside it or into a `.claude/` subdirectory
AC-2: holds — a fake-claude build that runs `chmod +x` on a new script, `git add` and commit leaves a clean tree and the run reaches the review
AC-3: `lane-permission-hook-selftest.sh` allows `chmod +x` on a relative and an absolute worktree path, and withholds an outside path and one through an outward symlink

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Hook decision on `chmod +x` inside the worktree | decided (D-1) |
| S-2 | Hook decision on `chmod +x` into `.claude/` subdirectories | decided (D-3) |
| S-3 | Hook denial message on a chmod outside the form | decided (D-10) |
| S-4 | BUILD prompt text | decided (D-6) |
| S-5 | `build-inflight` stop on the `update-index` route | decided (D-1) |
| S-6 | The review session's grants | out-of-scope — the ticket's Out section excludes them. |

## Checks

- `bash plugins/dev-pipeline/tools/lane-permission-hook-selftest.sh`
- `bash plugins/dev-pipeline/skills/run/run-claim-selftest.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: implementable, no blockers. Its option gaps went to the Interview.

Split: not triggered. No epic label and one deliverable.

Explore: done. Read the hook, its selftest, build_allowlist, worktree_inflight, fails_without_change, the fake claude and run-claim-selftest. Replayed the git mode behavior.

Fan-out: skipped — by the operator at the intake notice: no reason given

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

</details>

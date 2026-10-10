# Intake record — #973

A BUILD that commits, gets one permission denial and exits 0 without pushing ends the run as `build-inflight`, so a human has to push and `--resume`. Pre-flight interview with the operator, 2026-10-11. The ticket body is the operator's own; its Proposal and Acceptance are the inputs, and its acceptance item 2 leaves the mechanism to intake.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What the scheduler does when a BUILD exits 0 with a clean tree and commits not on `origin/$BRANCH` | Weighed: the prompt line alone; the ticket's proposal (the line plus a `build-inflight` detail that cites the denials, with a human still pushing); the scheduler pushing itself (it widens what the scheduler writes, and it would also have to open the PR with the body conventions, or the run ends `build-no-pr`); and re-spawning through the existing `red_attempt` primitive (`run.sh:918`). Chosen: re-spawn. `worktree_inflight` tells "unpushed commits on a clean tree" apart from "tree not clean". The unpushed case calls `red_attempt`. Its log names the unpushed commits, tells the build to push `$BRANCH` and open the draft PR, and lists the build's `denials-<A>.txt`. The re-spawn spends the checks-red counter (`CHECKS_RED_MAX`), never a round | user-answered | intent |
| D-2 | A tree that is not clean after the build | Stays terminal `build-inflight`, as today (`run.sh:1021`). When `denials-<A>.txt` is non-empty, the detail line cites its path. Uncommitted work is not handed to a new session | user-answered | intent |
| D-3 | The `build_prompt` line | A denied command is not a reason to end the turn. A command outside the allowlist is skipped and named in the PR body. Pushing `$BRANCH` and opening the draft PR are never skipped. The line sits beside #967's "run each shell command on its own … run a check below exactly as written" and does not restate it. Every listed check is already allowlisted (`build_allowlist`, `run.sh:580-590`, derives from `checks_list all`) | codebase-derived | fact |
| D-4 | Ordering against #967 (#964's fix) | Build from main after #967 merges. #967 rewrites the same `build_prompt` lines and replaces the denials read with `read_denials`, where a missing file means "unread", not "none". D-1 and D-2 read the denials file under those semantics: when it is unread, the log or detail says so instead of saying "(none)". The operator queues #973 only once #967 has landed | user-answered | intent |
| D-5 | Selftests | Each case in `run-selftest.sh` fails without its change. (1) `build_prompt` carries the denial-is-not-a-stop line. (2) Case z12 (`build-commit-nopush`) is re-pointed: a clean tree with an unpushed commit now re-spawns, and the next build's prompt carries the push instruction and the denials. The fake claude already records one denial on every build (`run-selftest.sh:122`). (3) Case d (`build-pr-dirty`) stays `build-inflight`, and its detail cites the denials file. (4) Repeated clean-tree-unpushed exits end as `checks-red-spent` | codebase-derived | fact |
| D-6 | PR form | `feat(dev-pipeline): …` title, since the run no longer stops for this case. A `Changelog:` trailer with `Migration: none`. No version or CHANGELOG edits (CLAUDE.md) | codebase-derived | fact |
| D-7 | Duplicate scan | `dup-scan.sh --issue 973`: rc 0, no candidates above the threshold. The #967 overlap is covered by D-4 | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The build prompt's instruction on a denied command | decided (D-3) |
| S-2 | The re-spawned build's log: unpushed commits, the push and draft-PR instruction, the denials | decided (D-1) |
| S-3 | The run's `say` line and the run block when the re-spawn spends the checks-red counter (`checks-red-spent`) | decided (D-1) |
| S-4 | The `build-inflight` detail line for a dirty tree, citing the denials file | decided (D-2) |
| S-5 | The PR body naming a skipped, denied command | decided (D-3) |
| S-6 | The unread-denials wording, when no denials file was written | decided (D-4) |
| S-7 | Release notes: the `Changelog:` trailer | decided (D-6) |
| S-8 | Reducing the denials themselves (compound shell, nohup, scratch dir) | out-of-scope — #964 / #967 owns it |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given

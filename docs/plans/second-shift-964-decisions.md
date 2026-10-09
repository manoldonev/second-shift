# Intake receipt — #964 Lane runs end with zero ERROR lines in the transcript

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Scratch dir location | `run.sh` creates one per run with `mktemp -d` under `${TMPDIR:-/tmp}`, outside `.claude/`, and passes it to both sessions with `--add-dir`. Both prompts name it as the only place for logs, probes, and PR/comment/verdict bodies. The build prompt's "Delete every probe or scratch file you created" sentence becomes "put scratch files there; the scheduler removes it" (the ticket's own fix; `$STATE` lives under `.claude/` per `run.sh:184,245`) | codebase-derived | fact |
| D-2 | Scratch dir at run end | On every exit (`terminal` and the HUP/INT/TERM traps), the scheduler archives the dir into `$STATE` as a tar, then removes it. `/tmp` is left clean and a blocked run's logs/probes survive as evidence. This mirrors the existing rule for untracked worktree files: archived, never discarded (`run.sh` `worktree_inflight`/`quarantine_untracked`) | user-answered | intent |
| D-3 | Review staging dir and the `$STATE` grant | The review stages `code-review.mjs` and writes its verdict draft in the scratch dir, and `--add-dir "$STATE"` is removed from the review spawn (`run.sh:938-940`; staging was its only stated reason). This sidesteps ticket cause 4 whether or not its `.claude/` inference is right. The `review_prompt` staging sentence changes to match | user-answered | intent |
| D-4 | Review-session denials: source and reader | After each review spawn, the same jq the build uses (`run.sh:978`) reads the review result JSON's `permission_denials` into `$STATE/denials-review-<RA>.txt`. The run block's per-session table (`cost_block`, `run.sh:763-767`) gains a `denials` column, one count per build and review session, so the operator sees it on the PR. Denials made inside the review Workflow's subagents are not in that JSON and stay uncounted. That is a known gap, stated in a code comment, not a fix in this PR | user-answered | intent |
| D-5 | Telling a denial from another tool error in `herdr-adapter.sh` | A `tool_result` with `is_error == true` is a denial when its text starts `Permission for this tool use was denied` or `Permission to use `. These are the two shapes seen in the lane transcripts under `~/.claude/projects/*second-shift-worktrees-921` / `-915`; a plain failure starts `Exit code N` | codebase-derived | fact |
| D-6 | How the adapter renders a non-denial error | A denial keeps `ERROR <first line>`. A result starting `Exit code N` renders `exit N <next non-empty line>`. Any other non-denial error (Edit's "String to replace not found", a Read of a missing file) renders `failed <first line>`. Neither form contains the token `ERROR` | user-answered | intent |
| D-7 | Reorder this repo's CLAUDE.md Verification paragraph | Included: the lane-BUILD foreground exception moves ahead of the `nohup` recipe, with no change of wording beyond what the move needs. This file is not frozen (`scripts/check-frozen-files.sh` covers versions and the changelog only) | user-answered | intent |
| D-8 | Test form for the new prompt lines | One `run-selftest.sh` case per prompt line, grepping the spawned prompt as the existing (dq) cases do (`run-selftest.sh:251-252`). The scratch-dir case drives a run and asserts the dir exists during the spawn, is in both spawns' `--add-dir` args, and is gone with its archive in `$STATE` after exit. The adapter cases feed a denial, an `Exit code` result and an Edit failure through `herdr-adapter-selftest.sh` | codebase-derived | fact |
| D-9 | Allowlists | Not widened: no `rm`, `cd`, `nohup` or `python3` (ticket "Not proposed"; `build_allowlist`/`review_allowlist`, `run.sh:545-561`) | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Transcript pane line for a permission denial | decided (D-5) |
| S-2 | Transcript pane line for a non-zero exit or other tool failure | decided (D-6) |
| S-3 | Build and review prompts (scratch dir, one-command-per-call, Edit/Write only, foreground, `--body-file`, review runs no CI suites) | decided (D-1) |
| S-4 | Scratch dir on disk during and after a run, including blocked and interrupted runs | decided (D-2) |
| S-5 | `$STATE` contents after a run (scratch archive, review denials file) | decided (D-2) |
| S-6 | Run block per-session table on the PR | decided (D-4) |
| S-7 | Review session's access to `$STATE` | decided (D-3) |
| S-8 | This repo's CLAUDE.md Verification paragraph | decided (D-7) |
| S-9 | Denials made inside review Workflow subagents | out-of-scope — they are not in the result JSON; named as a known gap under D-4, to be filed if the next run's transcript shows them |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given

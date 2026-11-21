# Headless build session ends its run when it backgrounds a long check and ends its turn

## What happened

`run.sh 907` (v15.2.0, run `20260926T212014Z-91491`) stopped in round 1 with `terminal: build-inflight`: the BUILD session exited 0 while its worktree held the whole uncommitted change. No commit, no push, no PR.

The spawned session's result JSON (`build-1.1.json`): `subtype: success`, `terminal_reason: completed`, 40 turns, 285 s, $1.30. Its final message: *"The run.sh selftest is still running; I'll continue once it finishes."*

## Why (measured from the session transcript)

1. The build prompt tells the session to make every configured check green before opening the PR. On this repo that includes the full selftest sweep, which takes minutes.
2. The session first tried `timeout 110 bash …run-selftest.sh` in the foreground, which failed with `env: timeout: No such file or directory` (rc 127: macOS ships no `timeout`). It then relaunched the sweep with `run_in_background: true`, as this repo's CLAUDE.md says to.
3. A later foreground wait loop hit the Bash tool's limit, and the tool returned `Command did not complete within its 120s timeout and was moved to the background`.
4. The model ended its turn, expecting to be woken when the background task finished. Under `claude -p`, ending the turn ends the process. The scheduler got exit 0 and a `success` result.
5. `worktree_inflight` (`run.sh:475`) then found the tree not clean and stopped with `build-inflight`. No data was lost, but the round was spent and the run needs someone to finish it by hand.

**Inference, not measured:** any consumer whose configured checks take longer than about 120 s drives the build session down the same path, because step 3 happens to any long check whatever its instructions say. To confirm, run a consumer ticket whose `commands.*.test` takes more than 2 minutes, and look for this terminal.

## Where the fix lands

Per CLAUDE.md, the fix goes in the scheduler (`plugins/dev-pipeline/skills/run/run.sh`), with a `run-selftest.sh` case that fails without it. Candidates, not yet evaluated:

- **Re-enter the session.** When BUILD exits 0 with a dirty tree or background tasks still pending, continue the same session (`claude -p --resume <session_id>`) with a bounded number of re-entries, before falling through to `build-inflight`.
- **Let long checks run in the foreground.** Set a larger Bash timeout for spawned sessions through the environment (`BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS`), so the checks never go to the background. Unverified: whether `-p`'s automatic backgrounding honors these variables.
- **Prompt only (weakest).** Add a line to the build prompt saying the session is headless: ending a turn ends the session, so it must never end a turn while waiting on a background task.

## Evidence

- Run log: `.claude/pipeline-state/907-lean-run-20260926T212014Z-91398.log`
- Result and denials: `.claude/pipeline-state/run-907/20260926T212014Z-91491/build-1.1.json`, `denials-1.1.txt`
- Session transcript: `~/.claude/projects/-…-second-shift-worktrees-907/7ae39cd5-82d1-4b3b-a66a-ba453802e02d.jsonl`

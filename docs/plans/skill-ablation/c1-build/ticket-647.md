# The lane worktree cannot inherit the operator's allowlist, so every build session gambles on the permission classifier

Found while running #641 through the lane on 2026-08-22. Cost one build session; it will cost one
on a random fraction of every future run, here and in every consumer that adopts the lane.

## Problem

The lane cuts its build worktree at `second-shift-worktrees/<issue>` and runs the payload session
with that worktree as cwd. **A git worktree receives tracked files only.** The operator's
permission allowlist lives in `.claude/settings.local.json`, which is gitignored — here by the
user's global ignore:

```
$ git check-ignore -v .claude/settings.local.json
/Users/…/.config/git/ignore:1:**/.claude/settings.local.json	.claude/settings.local.json
```

So the file structurally **cannot** exist in the worktree, and the build session runs with no
allowlist at all. Every tool call falls through to auto mode's classifier, which is probabilistic.

## Measured — the same command, twice, different verdicts

Two runs of `orchestrate-lean.sh 641 --build-model sonnet`, identical invocation, ~2 hours apart:

| run | start | outcome |
| --- | --- | --- |
| 1 | 2026-08-22T12:07:31Z | build session ran to completion; 3 rounds; PR #645 approved |
| 2 | 2026-08-22T14:16:57Z | build session denied `git fetch`, `gh api`, and `bash lean-gate.sh entry` — "Blocked by classifier" |

Run 2's transcript, verbatim:

> This session's permission mode (auto mode with a classifier) is denying Bash calls that touch
> GitHub or run the lean-gate script … including the very first gate call (`G entry`)

Note `Bash(git *)` **is** allowed in the operator's `.claude/settings.local.json`. It was denied
anyway, because the rule was not present in the worktree the session was running in.

## Why it is worse than a flaky run

The failure is nearly silent. A session that is denied every tool call still **exits 0** — it ends
its turn politely, having done nothing. Only the orchestrator's "exited 0, no PR" third-state check
(`orchestrate-lean.sh:43`) catches it:

```
terminal: build-idle — no open PR on 'claude/second-shift-641' after the BUILD session
```

That check exists for a different reason and happens to cover this. Without it the scheduler would
have spawned REVIEW against no PR.

**This also sharpens #643.** The scheduler's transport cannot distinguish "the session did the
work" from "the session was refused every tool and gave up" — both are exit 0. It is the same
defect that ticket is measuring, reached from a second direction.

## Remedies — one real, one interim

**1. The fix (this ticket).** `lean-gate.sh entry` copies the operator's Claude settings from the
origin checkout into the lane worktree when it cuts it — `.claude/settings.local.json` and any
untracked `.claude/settings.json`. The worktree then inherits the posture of the checkout it was
cut from, which is the only posture the operator ever consented to. This is the remedy that also
works for consumers, whose ignore rules and allowlists this repo cannot see.

Copy, never symlink: a symlink into the main checkout would let a lane session's writes reach the
operator's real settings file.

**2. The interim, this repo only, and NOT a substitute.** A tracked `.claude/settings.json`
carrying the three allows the dogfood lane needs (the gate script, `gh`, `git fetch`). It has to be
committed to take effect — an uncommitted one is invisible to the worktree for the identical
reason. Worth doing here because this repo's own lane runs constantly, but it fixes nothing for
anyone who installs the toolkit.

Out of scope: changing the default `LEAN_SPAWN_PERMISSION_MODE`. `bypassPermissions` unblocks a run
and is the right operator escape for one launch, but making it the lane's default trades a random
failure for a standing grant on every spawn, and that is a posture decision this slice does not own.

## Acceptance Criteria

- **AC-1** (oracle — selftest): after `entry` cuts a lane worktree, the worktree carries the
  operator's `.claude/settings.local.json` when the origin checkout had one; a fixture with no such
  file yields a worktree with none and no error.
- **AC-2** (oracle — selftest): the copied file is a regular file, not a symlink, and a write to
  the worktree copy does not alter the origin checkout's copy.
- **AC-3** (oracle — selftest): an existing worktree file is not clobbered on a re-entry that
  reuses the worktree.
- **AC-4** (proxy): the interim tracked `.claude/settings.json` lands with the three allows and a
  comment naming this ticket, so its removal after AC-1 ships is traceable.
- **AC-5** (oracle): `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
  is green.
- **AC-6** (critic): `Changelog:` trailer with a `Migration:` line — consumers gain a behavior they
  did not have.

Open regions: whether to copy `.claude/settings.json` when it is tracked (the worktree already has
it) — reversible default is to skip it and copy only what the worktree lacks, flagged in the PR.

Provenance: 2026-08-22, observed directly across two runs of #641. Transcripts under
`.claude/pipeline-state/archive-641-pr645-*/` on the operator's machine (gitignored, not committed).


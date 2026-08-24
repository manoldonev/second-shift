# #647 — the lane worktree inherits the operator's Claude settings

Issue: https://github.com/manoldonev/second-shift/issues/647

## The defect, restated from the mechanism

A git worktree receives **tracked files only**. The operator's permission allowlist lives in
`.claude/settings.local.json`, which is gitignored — here by the user's global ignore file. So the
allowlist *structurally cannot* exist in a lane worktree, and a session whose cwd is that worktree
starts with no allowlist at all. Every tool call then falls through to the harness's classifier,
which is probabilistic: two identical launches of `orchestrate-lean.sh 641 --build-model sonnet`
two hours apart produced a completed build in one case and, in the other, a session denied
`git fetch`, `gh api`, and its own first gate call — `Bash(git *)` was present in the operator's
allowlist and was denied anyway, because the rule was not visible from where the session ran.

The failure is near-silent: a session denied every tool call still **exits 0**.

The remedy is that the lane worktree inherits the posture of the checkout it was cut from — the
only posture the operator ever consented to — instead of inheriting nothing.

## Acceptance Criteria

- **AC-1** (oracle — selftest): after `entry`, a lane worktree on this run's branch carries the
  operator's `.claude/settings.local.json` when the origin checkout had one; a fixture with no such
  file yields a worktree with none, and no error.
- **AC-2** (oracle — selftest): the copied file is a regular file, not a symlink, and a write to
  the worktree copy does not alter the origin checkout's copy.
- **AC-3** (oracle — selftest): an existing worktree file is not clobbered on a re-entry that
  reuses the worktree.
- **AC-4** (proxy): the interim tracked `.claude/settings.json` lands with the allows the dogfood
  lane needs — the gate script, `git fetch`, and `gh` as an **enumeration** of the read verbs the
  lane invokes plus the PR-opening one, never a `gh:*` wildcard — and a note naming this ticket, so
  its removal after AC-1 ships is traceable. A tracked file in a public repo is a standing grant in
  every clone and every contributor session, so no verb that can merge, close, delete or edit
  outside the lane branch appears here at any width, and `gh api` cannot appear at all because an
  allow pattern matches a command PREFIX and no `gh api` prefix excludes a trailing `-X DELETE`.
  `D-8`.
- **AC-5** (oracle): `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
  is green.
- **AC-6** (critic): `Changelog:` trailer with a `Migration:` line — consumers gain a behavior they
  did not have.
- **AC-7** (oracle — selftest): the seed refuses to write where no ignore rule covers the
  destination — nothing lands, and the refusal names the `.gitignore` line that would earn the
  copy — and a lane worktree the seed has considered is still reaped by the next `entry`'s sweep.
  Its fixture repo must NOT carry the `.claude/` ignore line the other cases' fixture does, or the
  case shares the premise it exists to falsify. `D-9`.

## What is deliberately NOT here

- **`LEAN_SPAWN_PERMISSION_MODE`'s default is untouched.** `bypassPermissions` unblocks a launch
  and is the right per-launch operator escape; making it the lane's default would trade a random
  failure for a standing grant on every spawn, and that posture decision is not this slice's.
- **No symlink, under any flag.** A symlink into the main checkout would let a lane session's write
  reach the operator's real settings file. `D-2`.
- **No new gate refusal.** Nothing here may change `entry`'s verdict. `D-5` — and `D-9`'s refusal
  is a refusal to COPY, printed as a warning: `entry`'s exit status is the same on both branches
  of it.
- **No wide `gh` grant, at any scope this repo publishes.** The operator's own wider allowlist
  belongs in their untracked `settings.local.json` — which is precisely the file AC-1 now carries
  into the lane worktree, so the narrow tracked block costs the operator nothing. `D-8`.

## Decision Ledger

No pre-flight ledger exists for this ticket (`.claude/pipeline-state/647-ledger.md` is absent), so
every row below is authored in this session and carries its own basis.

| id | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Where the copy runs | In `cmd_entry`, after `cmd_entry_sweep`, over every registered worktree on this run's lane branch — resolved through the existing `lean_worktrees_for_branch`, never from a path convention. After the sweep so a worktree the sweep just removed is not seeded first. Source: https://github.com/manoldonev/second-shift/issues/647 | ticket-sourced |
| D-2 | Copy, never symlink | `cp`, which also dereferences a symlinked source into a regular destination file — so AC-2's two halves are one mechanic. Source: https://github.com/manoldonev/second-shift/issues/647 | ticket-sourced |
| D-3 | Never clobber | A destination that already exists (file, directory or symlink) is left alone. One rule doing two jobs: AC-3's re-entry case, and the Open Region below for free. | codebase-derived |
| D-4 | Which files | `.claude/settings.local.json` then `.claude/settings.json`. The second is copied only when the worktree lacks it, which is exactly the untracked case the issue names. Source: https://github.com/manoldonev/second-shift/issues/647 | ticket-sourced |
| D-5 | Advisory, never fatal | A settings file that could not be copied is a lost convenience, not evidence. The attestation is what `entry` exists to establish, and nothing added here may reach its exit status — the same rule `cmd_entry_sweep` already runs under. | codebase-derived |
| D-6 | AC-4's "comment" is a JSON key | JSON has no comment syntax and this repo's verification runs `jq empty` over every `*.json`, so the note lands as a top-level `"_comment"` string. Probed: the harness ignores the unknown key without complaint. | codebase-derived |
| D-7 | The remedy is not inert | A lane worktree is **not** a separate trust root — the harness resolves project identity through the git common dir, so a worktree of a trusted checkout inherits its trust and honours a project-scope allowlist. Probed directly in `second-shift-worktrees/647`: no `Ignoring N permissions.allow entry … has not been trusted` line, and no new `~/.claude.json` `projects` entry. Had it been a separate trust root, both AC-1's copy and AC-4's tracked file would have been ignored on arrival. | codebase-derived |

| D-8 | How wide the tracked `gh` grant may be | A PUBLISHED, project-scope wildcard is never acceptable: no `Bash(gh:*)` in any tracked settings file. It is replaced by the enumerated verbs the lane actually invokes, derived from the lane scripts and skills and cross-checked against what lane sessions have really run — read-only, plus `gh pr create` for checklist step 7. Any verb that can merge, close, delete or edit outside the lane branch is excluded categorically; the lane still makes those writes, as the bot wrapper's, inside the `lean-gate.sh` call the first allow already covers. `gh api` is excluded on the same rule and cannot be narrowed back in, because prefix matching cannot exclude `-X DELETE`. AC-4 names `gh` and is satisfied by the enumeration. Operator ruling, 2026-08-24, on round 1's B2. | user-answered |
| D-9 | What makes the copy safe for the reaper | `git check-ignore` on the DESTINATION PATH before any bytes are written, skipping with a named warning on a miss — the shape this file already uses before milestone 3 writes render bytes. Chosen over the two alternatives because it is the only one that holds in a CONSUMER repo: a repo-level ignore rule fixes this repo alone, and an in-flight carve-out would teach `worktree_inflight` — the one predicate the sweep and the scheduler's #531 D-3 boundary share — to overlook a real untracked file for every caller. This repo's `.gitignore` gains the line as well, so the dogfood lane takes the copy path rather than the warn path. | codebase-derived |

### Departures

None — there is no bound pre-flight row to depart from.

### Open Regions

| region | disposition | resolution |
| --- | --- | --- |
| Whether to copy `.claude/settings.json` when it is **tracked** (the worktree already has it) | reversible-default | Resolved by `D-3` rather than by a second rule: skip-if-present means a tracked `settings.json` is already in the worktree and is passed over, while an untracked one is copied. Nothing is written that reads on the file's tracked-ness. |

## The residual, named rather than left to be found

The seed runs in `entry`, and `entry` is the run's **first** call — before checklist step 3 cuts
the worktree. So on a fresh run the worktree that step 3 cuts is seeded by the run's **next**
`entry` call (a re-entry, or the next round's build session), not by the one that preceded it.

That ordering is not a gap in the common failure shape, because the session that cuts the worktree
read its own settings at launch, from the checkout it launched in; it is the *next* session — the
one spawned with the worktree already as cwd — that this repairs, and that is precisely the session
that failed on 2026-08-22. AC-4's tracked `.claude/settings.json` covers the remaining first-round
case here, and is tracked exactly so it needs no copy at all.

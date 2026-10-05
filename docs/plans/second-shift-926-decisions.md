# Intake receipt — #926

## Decision Ledger

| ID  | Decision | Resolution | Provenance | Kind |
| --- | -------- | ---------- | ---------- | ---- |
| D-1 | What run.sh does after a BUILD when the only dirt is untracked files and HEAD equals origin/<branch> | Archive them and carry on. Split the predicate: `git status --porcelain --untracked-files=no` non-empty (modified, staged, intent-to-add, submodule changes) still stops at build-inflight; unpushed commits still stop; tracked dirt plus untracked files still stops with nothing moved. When neither stops, list the untracked files with `git ls-files -z --others --exclude-standard` (raw NUL-separated paths, one entry per file, independent of the consumer's `status.showUntrackedFiles`; ignored files are never listed), excluding anything under a declared `paths.runtimeData`. Write them with `tar -C "$WT" -cf "$STATE/quarantine-<round.attempt>.tar" --null -T -`, verify the archive lists them, and only then delete the originals. Then continue to the PR lookup, sync_to_remote, checks and review. Weighed: a per-attempt archive (chosen; one file per attempt, so no round overwrites another's probe, and no `*.spec.ts` lands in the main checkout for a runner to find); `mv` into a `$STATE/quarantine/<attempt>/` tree (the ticket's form; a moved spec under the gitignored state dir is still a live spec file in the main checkout); leave in place and only relax the predicate (checks would run with the probe or a forgotten helper in the tree, and close-out's `worktree remove` still refuses); `git stash -u` (refs/stash is shared across worktrees and invisible); prompt-only (the ticket comment shows the leftovers are systematic) | user-answered | intent |
| D-2 | The same predicate at close-out (an approved run whose worktree holds only untracked files, such as a scratch file the REVIEW left) | Same archive, to `$STATE/quarantine-closeout.tar`, then the existing runtime_data_held check and `worktree remove`, and the run ends `approved`. Tracked dirt and unpushed commits still end `closeout-inflight`. The selftest case `rj` flips from closeout-inflight to approved, asserting the file is in the archive and gone from the tree. Without this, `git worktree remove` (no --force) refuses on any untracked file and run.sh:860 turns that into a "remove it by hand" line on every approved lane | user-answered | intent |
| D-3 | How the run surfaces what it archived | A `say` line naming the count and the archive path, and a new section in the REVIEW's scheduler input (`review_input`, beside "Build session permission denials") listing the archived repo-relative paths, so the reviewer can tell a stray probe from a forgotten `git add`. Nothing is added to the PR run block or the tracker comment. Weighed: log line only (the ticket's form; under --detach it only reaches the lane log); also a line in the PR run block | user-answered | intent |
| D-4 | What the BUILD prompt says about probe and scratch files | One sentence in build_prompt: delete every probe or scratch file you created before you end your turn; a probe you never committed is not a test the PR deletes (so the existing "do not delete a test" line does not forbid it). No new grant or scratch directory: `rm` inside the worktree already runs under the build's acceptEdits grants (fan-out probe F-15), and a test-runner probe has to sit in the tree for the runner to find it. Weighed: also granting a `$STATE/scratch` dir via --add-dir | user-answered | intent |
| D-5 | When the archive step fails (the list, tar, or the verify cannot complete) | The originals stay where they are and the run stops at build-inflight / closeout-inflight with the reason. Per run.sh's header rules: "a predicate that cannot be evaluated refuses under a named slug" and "nothing here discards work" (run.sh:40-42). No new slug | codebase-derived | fact |
| D-6 | Where the archive step sits in the post-build sequence | Inside the post-build in-flight check (run.sh:793), before the PR lookup, sync_to_remote (run.sh:812) and run_checks (run.sh:814). Every check runs with cwd=$WT (`lane()`, run.sh:256), and an untracked file at a path the remote adds aborts sync_to_remote's `merge --ff-only` as a misleading env-worktree-diverged (fan-out F-6, F-7) | codebase-derived | fact |
| D-7 | worktree_ready before a spawn | Unchanged. Dirt before a spawn is "the build's own resume state and is left alone" (run.sh:523), for example a timed-out build's new files, which the next BUILD continues | codebase-derived | fact |
| D-8 | The --handoff path (/dev-pipeline:build) | Gets the D-4 prompt sentence, because it reads the same build-$A.prompt. It gets no scheduler check after the build: the handoff exits before worktree_inflight (run.sh:781-787), as today | codebase-derived | fact |
| D-9 | The guards | Two run-selftest.sh scenarios that fail without the fix. (1) A new fake-claude plan word that leaves an untracked probe after `push; openpr`, run as `build-pr-untracked` then `review-approve`. It asserts the run ends `approved` (not build-inflight), the file is gone from the worktree, it is inside `quarantine-1.1.tar`, the log names the archive, and the review input lists the path. (2) `rj` flipped per D-2. Cases d and z12 stay as they are. Each site keeps exactly one `status --porcelain` read, so the ordinal-counting shim behind ar10/ar11/ar11b keeps its counts (fan-out F-20). The prompt sentence is asserted through the fake-recorded `prompt-1.txt` (the suite's existing shape). CLAUDE.md: a run.sh behavior change lands with a run-selftest.sh case that fails without it | codebase-derived | fact |
| D-10 | Commit verb and changelog | PR title `fix(dev-pipeline): …` (patch), plus a `Changelog:` trailer: a run no longer stops at build-inflight or closeout-inflight over untracked files alone; they are archived under the run's state dir, named in the log and the review input, and the build is told to delete its probes. Migration: none. CLAUDE.md, "Commit verbs decide the version bump" and "Every plugins/** PR needs a Changelog: trailer" | codebase-derived | fact |
| D-11 | Build model | opus. Operator standing rule for this repo: "only opus" (memory feedback-intake-sets-build-model-label, 2026-09-09) | user-answered | intent |
| D-12 | Lane admission | Admitted: the ticket body states a consumer run (dev-pipeline 15.3.0) that ended `build-inflight` twice over an untracked probe spec. Per CLAUDE.md, only the operator queues; no queue label is applied here | codebase-derived | fact |
| D-13 | Duplicate scan | dup-scan.sh --issue 926 returned rc 0: no candidates at or above threshold | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The build-inflight terminal and its detail line, for tracked dirt or unpushed commits | decided (D-1) |
| S-2 | The run log line naming the archive | decided (D-3) |
| S-3 | The archive file under the run's state dir, which the operator opens to recover a file | decided (D-1) |
| S-4 | The REVIEW session's scheduler input | decided (D-3) |
| S-5 | Close-out: the approved outcome, worktree removal, and closeout-inflight for tracked dirt | decided (D-2) |
| S-6 | The archive-failure outcome | decided (D-5) |
| S-7 | The build prompt the BUILD session reads | decided (D-4) |
| S-8 | The handoff build in the calling session | decided (D-8) |
| S-9 | The PR run block and the tracker closing comment | decided (D-3) |
| S-10 | The run SKILL.md exit table | out-of-scope — no slug or exit code changes; build-inflight and closeout-inflight keep their meaning for tracked dirt and unpushed commits |
| S-11 | Release notes a consumer reads | decided (D-10) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Design

Design: none — a scheduler change that renders nothing.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: what-untracked-can-mean opus 6/6 · worktree-lifecycle fable 5/6 · build-side-prevention opus 5/6 · contract-and-tests fable 6/6 · premortem fable 4/5
Tally: rows added 2 · snapshot claims overturned 2 · questions added 1

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | what-untracked-can-mean | An untracked-only rule lets through files, folded directories, symlinks and nested repos; staged, intent-to-add and submodule changes stay blocked (probes d1/d2) | new | became D-1 (the `--untracked-files=no` split keeps every staged and submodule form blocked) |
| F-2 | what-untracked-can-mean | Line-mode porcelain C-quotes odd paths; only `-z` gives raw paths | new | became D-1 (`ls-files -z`, `tar --null -T -`) |
| F-3 | what-untracked-can-mean | A forgotten `git add` passes the rule and makes checks green on code the pushed head lacks unless the files leave before run_checks (run.sh:256) | already-had | became D-3 and D-6 |
| F-4 | what-untracked-can-mean | Porcelain folds a directory that can hold gitignored runtimeData, so moving the folded path carries it out (run.sh:510-521) | new | became D-1 (`ls-files --exclude-standard` lists files, never ignored data) |
| F-5 | what-untracked-can-mean | `status.showUntrackedFiles=no` hides untracked files from the predicate; a non-ignored runtimeData path shows as `??` | new | became D-1 (explicit `ls-files`, runtimeData excluded) |
| F-6 | what-untracked-can-mean | An untracked file at a path the remote adds aborts the ff-merge as env-worktree-diverged; worktree_ready skips the ff when it sees `??` | new | became D-6 (archive before sync); worktree_ready unchanged per D-7 |
| F-7 | worktree-lifecycle | Sessions and checks run with cwd=$WT, so the move must happen at the post-build check (run.sh:241, :256, :793) | already-had | became D-6 |
| F-8 | worktree-lifecycle | $STATE is per run in the main checkout, gitignored, and A distinguishes attempts; REVIEW gets --add-dir $STATE | already-had | became D-1 (archive named per attempt) |
| F-9 | worktree-lifecycle | Relaxing the predicate alone leaves `worktree remove` refusing (rc 128); after the move it succeeds | new | became D-2 |
| F-10 | worktree-lifecycle | worktree_ready, both inflight sites, and close-out share one porcelain predicate | not material | not material — worktree_ready stays as is per D-7 |
| F-11 | worktree-lifecycle | Case d dirties a tracked file (stays); case rj leaves an untracked file (flips); no build-site untracked case exists | already-had | became D-9 |
| F-12 | build-side-prevention | BUILD is granted only $WT and the config dir; $STATE is review-only | new | became D-4 (no scratch-dir grant chosen) |
| F-13 | build-side-prevention | An out-of-tree Write works only because a bare `Write` is in the allowlist | not material | not material — D-4 adds no out-of-tree location |
| F-14 | build-side-prevention | Out-of-tree shell redirects are denied; allowlisted commands taking outside paths run | not material | not material — D-4 adds no out-of-tree location |
| F-15 | build-side-prevention | `rm` and `git clean -f` inside $WT run under the build's grants; nothing enforces cleanup | overturned (snapshot: "build allowlist has no `rm`; use `git clean -f`") | became D-4 |
| F-16 | build-side-prevention | The handoff gets the prompt text but none of the scheduler's post-build checks (run.sh:781-787) | new | became D-8 |
| F-17 | contract-and-tests | E17–E21/J6 row ids exist only as comments and case tags; read cases by what they assert | not material | not material — the guards are described by assertion in D-9 |
| F-18 | contract-and-tests | The Expected keeps d and z12 but contradicts rj; the closeout site needs its own decision | already-had | became D-2 (asked separately) |
| F-19 | contract-and-tests | No build-site untracked case exists; it needs a plan word that writes the probe after push | new | became D-9 |
| F-20 | contract-and-tests | The unreadable-status cases count `status --porcelain` reads by ordinal; an extra read shifts them | new | became D-9 |
| F-21 | contract-and-tests | `--untracked-files=no` and `ls-files --others --exclude-standard` split the dirt kinds without parsing | new | became D-1 |
| F-22 | contract-and-tests | The prompt has no probe sentence; prompt text is asserted by grepping the recorded prompt file | already-had | became D-4 and D-9 |
| F-23 | premortem | A forgotten new directory is indistinguishable from a probe, and the log line never reaches the reviewer | already-had | became D-3 |
| F-24 | premortem | A flat quarantine dir overwrites a same-named probe from an earlier round, and quoted porcelain paths make mv miss | overturned (snapshot: "move them, paths preserved, into a run-scoped quarantine under $STATE") | became D-1 (a per-attempt tar) |
| F-25 | premortem | A build-site-only fix leaves `worktree remove` refusing, so every approved lane leaves a worktree behind | already-had | became D-2 |
| F-26 | premortem | A quarantined `*.spec.ts` under the main checkout's state dir is a live spec file for whatever runner a human runs there | new | became D-1 (question added: archive vs tree) |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Mechanism when the only dirt after BUILD is untracked files and HEAD = origin/<branch> | Move them (paths preserved) into a run-scoped quarantine under $STATE, outside the worktree, log the dir, continue. Weighed: leave in place and ignore untracked (`status -uno`) — rejected: run_checks/route_smoke run in $WT after sync_to_remote, so a probe spec would run in the checks; `git stash -u` — rejected: refs/stash is shared across worktrees and invisible; prompt-only — rejected: the 2nd occurrence shows it is systematic |
    | D-2 | What still stops | Modified/staged tracked files, unpushed commits, and mixed dirt (untracked + tracked) stop as today, nothing moved |
    | D-3 | Ordering | Tracked-dirt and unpushed checks first, quarantine only after both pass; before the PR lookup / sync_to_remote / run_checks |
    | D-4 | Close-out | Same quarantine at close-out, then worktree removal and approved; flips the existing rj selftest case (review-left scratch -> closeout-inflight) |
    | D-5 | Visibility | Log line names the quarantine dir; review input gains a section listing the quarantined repo-relative paths (a forgotten `git add` is the risk case) |
    | D-6 | Build prompt | Tell BUILD to delete probe/scratch files it created with `git clean -f -- <path>` before ending (build allowlist has no `rm`; Bash(git *) is allowed), and that an uncommitted probe is not a test the PR deletes |
    | D-7 | Quarantine move failure | Stop as build-inflight / closeout-inflight with the reason; nothing discarded |
    | D-8 | Ignored files | Untouched (status --porcelain never lists them; paths.runtimeData covers close-out) |

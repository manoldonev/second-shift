# 539 — the milestone-3 runner outlives the turn that launched it

`lean-gate.sh` detaches milestone 3's evaluation and blocks on its marker, on the premise that the
harness's 120s tool reap kills only the waiter. Measured under a real `claude -p` child, that is
false: the runner dies with the turn. A sweep longer than 120s is therefore unreachable in a
headless BUILD child, and this repo's own sweep is ~5:22.

## Binding inputs

The pre-flight ledger (`.claude/pipeline-state/539-ledger.md`) ratified `set -m` as the escape
(D-1/D-6) with OR-1 — "is the teardown actually a process-group kill?" — left `pause-and-ask`.
The operator's resolving comment answers it: **no.** Scored by case id under a real `claude -p`
child, one launching call in the production spawn-then-block shape:

| case | runner pgid | runner session | verdict |
| --- | --- | --- | --- |
| today's shape | launcher's | launcher's | DEAD |
| `set -m` (the ratified escape) | own | launcher's | DEAD |
| new session (`setsid(2)`) | own | own | ALIVE (PPID 1) |

**The teardown is session-directed.** D-1's mechanism is falsified and must not ship; the ruling
replaces it with a new-session escape and leaves every other ledger row intact. The re-exec cost
that ruled this out in writing (`lean-gate.sh:2851-2853`, "1.4s of the 1.9s per-call overhead") did
not reproduce — five consecutive full startups measured `real 0.09–0.10`, ~15x off. The objection's
other half stands and is designed around: a re-exec needs a "you are the runner" handshake, and the
first shape of that was an **env var**, which milestone 3's own lane children inherited (this
repo's lane children are `lean-gate.sh`) so every nested call ran inline. A **positional
subcommand** is not inherited the way an exported var is.

## Acceptance criteria

- **AC-1 — the new-session escape ships behind an env seam that defaults to today's shape, with its
  own lower wait ceiling.** `LEAN_GATE_M3_NEW_SESSION=1` spawns the runner through a `python3 -c`
  wrapper that calls `os.setsid()` and `execv`s this gate back into itself on a dedicated
  positional subcommand carrying the launch token as an argv flag. Unset — the shipped default —
  the forked-subshell spawn is byte-for-byte what it is today, so no consumer inherits an unproven
  path. The escape path's wait ceiling is **300s**, not the 3600s default;
  `LEAN_GATE_WAIT_CEILING_SECS` still overrides either. The inversion is the point (D-4): a low
  ceiling is destructive today, because the runner dies anyway and giving up on the wait loses the
  work, and cheap on the escape path, because `m3_wait`'s ceiling arm returns 7, keeps the pid
  record deliberately, and the next call rejoins a runner that never stopped.

- **AC-2 — `cmd_teardown` reaps the recorded runner before `worktree_destroy`.** Escaping the
  session removes the runner's only reaper: `cmd_teardown` never touches it, so today the pgid
  teardown *is* what stops it, and without this a `worktree remove` can yank the tree out from
  under a live sweep — the orphan-fixture class CLAUDE.md warns reds later suites indefinitely.
  The reap is located by the **issue-keyed glob**, not `m3_paths`, for #527 D-4's reason: that key
  is `cksum($REPO_ROOT)` and teardown may be invoked from either checkout. `lean-gate-selftest.sh`
  **(if5b)** — *"the kill took the whole process group — no lane child left running"* — is
  re-derived to reap the recorded runner's pgid **explicitly** rather than resting on the gate's
  own group, which is the contract this ticket changes.

- **AC-3 — the residue read treats a live recorded runner with no marker as in-flight-and-joinable,
  not as "no infra death".** `infra_token` (#527) subtracts live runners from the unclosed count,
  justified in its own comment on the premise that no runner survives turn end. The escape makes
  that pid alive, so the predicate goes false exactly when the escape starts working: the scheduler
  reads an unmoved token, stops with continuations unspent, and the fix delivers nothing. A live
  recorded runner with no marker is not merely recoverable — it is the strongest recoverable
  signal, because the next spawn joins a sweep already minutes in.

- **AC-4 — the falsified prose is corrected wherever the gate asserts it.** `lean-gate.sh:2576-2577`
  ("the evaluation is a different process and keeps going"), `:2764` ("Re-invoking rejoins it WHILE
  IT RUNS"), and the header's "There is NO seam and no flag for milestone 3's detached runner"
  register all state the falsified premise as fact. Each is corrected to what was measured,
  including the `setsid`-is-unavailable and re-exec-cost notes at the spawn site.

- **AC-5 — a liveness scenario fails when the runner does not survive a simulated turn end.**
  In `scenario-liveness-selftest.sh`, reusing (if5)'s idiom verbatim: `set -m`, background the gate
  so it leads its own group, wait for the milestone-3 `started` row, `kill -9` the group. With the
  seam **on** the recorded runner is still `kill -0`-live afterwards and a second `bash G 3`
  **joins** it rather than launching a second sweep; with the seam **off** the same sequence leaves
  it dead. The scenario reaps whatever it left alive. Every existing milestone-3 guard passes today
  while the lane cannot reach milestone 3 at all, so a case that cannot fail on the seam being off
  is not a guard.

- **AC-6 — the mutation obligations on this diff are settled in this diff, either way.** Two
  obligations, and each is discharged by a check whose answer is recorded, not by assuming which
  way it goes. (i) The five `tools/mutation-catalog.tsv` rows anchored into the m3 region
  (`lean-gate-m3-no-join`, `-stale-marker`, `-death-blind`, `-pid-outlives`, `-samelaunch-join`)
  still match their `sed` anchors exactly once each, or are re-anchored here. (ii) The generic
  survivor ordinals for every guard this diff edits — `lean-gate.sh` at `cmp-eq::1`, `default::1`,
  `default::2` and `orchestrate-lean.sh` at `default::1` — still name the sites their baseline
  notes describe, or `tools/mutation-baseline.tsv` is re-keyed here. Ordinals are the operator's
  match order over the whole file, so an edit ABOVE a baselined site moves it and an edit below
  does not; the check is a `grep -nE` with the committed operator pattern against both revisions,
  and its result belongs in the PR body whichever way it comes out.

## Out of scope, stated

**A join still writes nothing (D-9), so two consecutive turn-end deaths over one live runner leave
the infra token unmoved.** Spawn 1 launches a sweep and dies → the token moves → the scheduler
spends a continuation. Spawn 2 *joins* that runner, and a join records no row by design, so if
spawn 2 also dies before the sweep finishes the token is unmoved and the scheduler stops. Making a
join observable means a new row kind and a re-reading of D-9's "counting a join would walk an
honestly-waiting run into `INTERRUPTED_BUDGET`" — a different ticket. AC-3 restores the signal on
the first death, which is what the ledger's "the next spawn joins a sweep already minutes in"
requires; the residual is recorded at the site rather than left to be rediscovered.

## Notes

- `m3_joinable` is retained, not deleted as dead code (D-9 of the ledger): it kills the
  duplicate-sweep livelock, #527 increases re-spawn frequency so that defense matters more
  afterwards, and four mutation-catalog rows anchor literal `sed` patterns into those sites.
- The seam is scrubbed out of the lane children's environment. `SEAM_SCRUB` itself is a `verbatim`
  lockstep row against `verifyctl.sh` and is not widenable from this side; the scrub is appended to
  `SEAM_SCRUB_ENV` beside `LEAN_JOB_CEILING`'s existing precedent. A nested lane child is not
  turn-bound and has nothing to escape from, and leaving the seam inheritable would make the sweep's
  own meaning depend on an ambient variable — the leak class this repo already carries a scar for.
- OR-2 (does a 300s escape-path ceiling hold outside this repo) stays a reversible default: one
  constant behind a seam that already defaults off, overridable per invocation, with the chosen
  value stated in the seam's own comment.

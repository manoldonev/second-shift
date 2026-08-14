# #511 — a BUILD session that hands its verification to a monitor is dead where it stands

`orchestrate-lean.sh` spawns every BUILD session under `claude -p`, where **turn end is process
exit**. A block facing a minutes-long green gate has one move that looks considerate — background
the work, sign off, collect it next turn — and here it is fatal, because there is no next turn. On
the #497 run both BUILD sessions did exactly that and neither ever reported: milestone 3 never ran,
the branch was never pushed, and the lane exited 1 with a continuation unspent.

The scheduler's stop was correct on its inputs and is out of scope. The defect is that the session
had a choice to yield at all, so this ticket removes the choice at the one milestone long enough to
matter, and writes the rule for everything else it structurally cannot reach.

Binding pre-flight input: `.claude/pipeline-state/511-ledger.md` (D-1..D-13, OR-1/OR-2). Where the
issue body and that receipt differ, the receipt wins — three of the issue's premises are corrected
there, including its question (3), which #497 already answered in merged code.

## Design

Design: none — this ticket ships process-lifecycle mechanics inside a shell gate plus two prose
rules. No user-visible surface renders, and this repo configures no `design.provider`.

## Acceptance criteria

- **AC-1 — milestone 3 evaluates in a different process, and the caller blocks on it.**
  `bash G 3 <issue>` spawns the evaluation detached (a forked subshell under `trap '' HUP`, per
  AC-12 — not `nohup`, which needs an external command to exec, and no `setsid`, which does not
  exist on macOS), the runner stamps its exit code into a marker file, and the invoking call
  BLOCKS on that marker rather than returning. The runner's output goes to a log the waiter replays to its
  own stdout when it lands, so every existing caller and every existing selftest case sees what it
  always saw. A tool-timeout reap then kills the waiter and not the evaluation.

- **AC-2 — launch-or-JOIN, never a second sweep.** An invocation that finds a LIVE runner for the
  same `(issue, milestone-3, worktree)` key attaches to it and starts nothing. This is what kills
  the #500 livelock, where a re-spawn launched a second sweep into the worktree the first orphan
  was still sweeping and the progress token could never move. Liveness is the recorded pid plus
  `kill -0` — never `pgrep -f`, whose self-matching deadlock is a scar this repo already carries.

- **AC-3 — a JOIN records nothing (D-9).** The runner writes exactly one
  `started`/`concluded | rc=<n>` pair per real evaluation. A join is not an evaluation beginning,
  so it appends no row; counting joins would inflate #497's unclosed diff toward
  `INTERRUPTED_BUDGET=5` and hard-stop a run for waiting correctly. `progress_token`'s row set is
  unchanged (D-11) — widening it is the issue's own "fix that must not be chosen".

- **AC-4 — three terminal states, and silence is not one of them (D-3).** The wait ends when
  (i) the marker appears — exit with its value; (ii) the recorded pid fails `kill -0` with no
  marker — the runner died; or (iii) the wall-clock ceiling is reached. A waiter that polled only
  for success would be silent through a crash, and silence reads identically to "still running".

- **AC-5 — a new `rc=7` for (ii) and (iii), which is not a failure (D-5).** Distinct from `1` (a
  milestone failed — wrong remedy, and it spends a fix attempt), from `2` (usage/environment,
  whose remedy is "call `entry` first") and from `4` (a hard stop that fires an abort comment at a
  sweep still very likely running). `rc=7` spends neither the fix budget nor the absent budget,
  and its remedy is to re-invoke — which joins a live runner or relaunches a dead one. It appears
  in the gate header's `Exit:` block, the taxonomy of record.

  **`7` is SHARED with `staleness`, which #534 landed on the base while this branch was in
  flight**, and the taxonomy entry now carries both readings rather than one of them silently
  winning. They do not conflate, and the reason is that neither reader is ever handed the other's
  code: `orchestrate-lean.sh` invokes `staleness` directly and branches on its rc at that call
  site, while a milestone-3 `7` is returned to the BUILD session that called `bash G 3` and never
  reaches the scheduler as a gate exit — a build phase's rc is `claude -p`'s, not the gate's. The
  two are also the same *kind* of answer, which is what makes one integer honest for both: nothing
  was evaluated, so neither is a milestone failure and neither spends a fix attempt.

- **AC-6 — the ceiling is 3600s, seamed at `LEAN_GATE_WAIT_CEILING_SECS` (D-4).** ~3× the longest
  milestone-3 evaluation on record (20m44s, #497). Deliberately generous: `CLAUDE.md` warns that
  `install-topology-selftest.sh` alone swings 319s/438s/584s and to treat the range rather than a
  point value, and a breach reclassifies an honest slow run as infrastructure. The seam is
  validated **before** anything is spawned, so a typo cannot leave a detached evaluation with no
  waiter. A breach gives up on the WAIT and never on the evaluation — the runner is not killed.

- **AC-7 — milestone 3 only (D-2).** Measured on #497's own progress record: milestone 1 concluded
  in 1s, milestone 2 in 2s, milestone 3 in **20m44s** (`11:38:04` → `11:58:48`). Every observed
  death is the sweep. `bash G 3` and `all`'s 3-leg share one key and therefore one runner;
  `LEAN_GATE_OBSERVE=1` stays inline, because observe promises to record nothing and the only
  caller that observes is the pre-pass that exists to avoid paying for milestone 3 at all.

- **AC-8 — the prose half, in BOTH blocks (D-6).** `build-lean/SKILL.md` and
  `review-lean/SKILL.md` each carry "never end a turn with work this turn started and has not
  collected", naming the shapes: a `&`-detached command, a probe to be reported on "when it
  lands", an armed `Monitor`. `build-lean/SKILL.md` stays under the 60-line cap
  `lean-gate-selftest.sh` case `(f)` asserts.

- **AC-9 — `review-lean`'s `Workflow` exposure is MEASURED, not assumed (D-7).** A `claude -p`
  child dispatching a one-agent `Workflow` was run and observed. **Result: it survives.** The
  session is re-entered when the workflow completes and reports its value normally — the probe's
  entire output was `RESULT: {"pong":"PONG"}`. So `review-lean`'s prose says to await the
  `review-lead` fan-out rather than restructure around a death it does not have. Assuming either
  direction was refused: assuming it dies forbids a path that already works, and assuming it
  survives would have left review's most likely death unexamined.

- **AC-10 — the mechanism is selftested, and one half deliberately is not.** `lean-gate-selftest.sh`
  gains a `(dj)` block covering AC-1..AC-7, AC-13 and AC-14, each case on its own fixture tree so
  the runner key is its own, plus `(x3d)` pinning that `all` reaches milestone 3 through the same
  wrapper.
  **The prose half of AC-8 has no guard, and that is the decision, not an omission**: `CLAUDE.md`
  forbids prose-presence guards, because grepping a rule out of a SKILL asserts only that prose
  contains words and cannot fail for a reason a reader of the diff would not already see. The gate
  mechanism is the guard for the milestone-3 half; the "any in-flight work" half has no kill
  criterion and none is manufactured for it.

- **AC-11 — the mutation obligations that ride on editing a guard.** Five
  `tools/mutation-catalog.tsv` rows pin the mutants whose survival would be silent:
  `lean-gate-m3-no-join` (#500's livelock restored), `lean-gate-m3-stale-marker` (a green gate
  certifying a tree it never ran against), `lean-gate-m3-death-blind` (#496's silence class at
  a second site), `lean-gate-m3-pid-outlives` (the dead pid that stale-marker needs as raw
  material) and `lean-gate-m3-samelaunch-join` (stale-marker's harm on the one state the token
  comparison cannot see). Each was applied and scored before being written down.

  **`lean-gate-m3-no-join` is RE-ANCHORED, and the re-anchor is the obligation rather than a
  cosmetic follow.** Its sed pinned the literal `if m3_runner_live; then`, which AC-14 replaces
  with `if m3_joinable; then` — a row left on the old text would match nothing, apply nothing, and
  report SURVIVED for a mutant that was never introduced. The mutant itself is unchanged (the join
  arm becomes unreachable) and `(dj4)` still kills it.

  **`lean-gate-m3-stale-marker` is RE-ANCHORED off the launch arm's `rm -f "$M3_RC"`**, and the
  reason is the AC-13 fix rather than drift: the token match refuses a stale marker wherever it is
  read, so removing that clearing is now survivable hygiene and a row anchored there would predict
  a kill that no longer happens. It moves to the token comparison, which is what enforces the
  invariant, and is killed by the case that covers the arm the clearing never reached. Every row's
  `sed` was apply-probed against the real file with BSD sed (`sed -E "$e" F | diff - F` changes
  exactly one line), which is the 5-second check that forecloses the ALL-SURVIVED harness-break
  class — and the two seds written this round avoid `\|` and bare `[` for the same reason.

  **`tools/mutation-baseline.tsv` is deliberately NOT edited, and that is the judgment call.**
  Editing a guard re-keys its generic survivor ordinals, and this edit did: the diff-scoped sweep
  now reports one survivor for this guard (`default::1`, already baselined) where three rows are
  committed. But the only sweep available here is the local one, which prints
  `ADVISORY RUN (GITHUB_ACTIONS unset) — kill verdicts are not comparable to the committed
  baseline`, and the baseline's own header pins its environment to `ubuntu-latest`. Re-keying
  from a non-comparable run risks deleting a row CI still needs, which converts a report-only
  survivor into a red — strictly worse than a stale row, which is report-only by construction.
  The enforcing run is the authority; if it reports a baseline-absent survivor, that is the
  re-baseline, made against a comparable environment.

- **AC-12 — the runner is a forked subshell, so there is no handshake at all.** Both prior shapes
  are recorded here because each was found by dogfooding rather than by review. First, an
  inherited `LEAN_GATE_M3_RUNNER=1` on a re-exec of this script: milestone 3's lane children in
  this repo are `lean-gate.sh` itself, so the variable reached the nested `lean-gate-selftest.sh`
  and every milestone-3 call inside it ran INLINE as a "runner" — no detach, no marker, the
  mechanism absent while the outer run looked healthy. An argv flag closed the inheritance but
  kept the re-exec, which re-read the config through a dozen `jq` forks per call to reach a
  function the process already had loaded: 1.4s of a measured 1.9s per-call overhead, enough to
  push the paired suite past `mutation-sweep.sh`'s 300s killer bound. A forked subshell has
  neither problem. `(dj10)` asserts the property both broken shapes violated — a milestone-3 lane
  child runs its own detached milestone 3, evidenced by **the inner call's own stdout announcing
  `spawned detached`**, which is printed between the fork and the wait on a path the inline arm
  returned before reaching. The two cheaper-looking discriminators are both vacuous and were both
  tried: the lane's exit code (the inline bug produced it too) and a `started`/`concluded` pair in
  the inner tree's record — `append_started`/`append_concluded` live INSIDE `m3_run_detached`, so
  the pair appears whether that function was forked or called inline, and calling it inline *is*
  the bug. Round 1 shipped the second one; it passed with the handshake reintroduced and firing.

- **AC-13 — a wait returns the exit code of the evaluation it is attached to, and nothing else.**
  The launch mints a token, the forked subshell inherits it as an ordinary shell variable, the
  runner stamps `<token> <rc>`, and a waiter consumes a marker only when the token matches the
  launch it is waiting on — the joined runner's own, read off its record, on the join arm.
  Round 1's stale-marker clearing was on the LAUNCH arm only, after `m3_runner_live` had already
  branched to the join, so a joiner returned a previous evaluation's code in 0s having evaluated
  nothing; with a real `0` in place of the probe's `99` that is a green milestone 3 certifying a
  tree it never ran against. The trigger is pid reuse, which is a day-scale event on this machine
  and not the "whole pid wraparound" the code claimed. Second half: **the pid record does not
  outlive the evaluation a waiter consumed** — it was the only one of the three runner-state paths
  with no `rm` anywhere, so every green milestone 3 left a dead pid in the state dir waiting to be
  recycled. `(dj11)` and `(dj12)`. The ceiling arm still deliberately keeps the pid — that runner is
  alive and a re-invocation must be able to rejoin it — and **that carve-out is where AC-14 lives**,
  because its premise expires the moment the runner finishes.

- **AC-14 — a runner is joinable only while its evaluation is UNFINISHED, and a live pid is not
  that fact.** The token is the discriminator against a stale marker, and it has one blind spot by
  construction: a retained pid record and a marker stamped by *the same launch* carry *the same
  token*, so the comparison matches and a join consumes a code it did not earn in 0s. Two ways in,
  neither contrived — AC-13's ceiling carve-out keeps the pid on purpose, and a waiter killed by
  the harness's reap keeps it by accident (both `rm -f "$M3_PID"` sites are inside `m3_wait`, there
  is no trap, and nothing clears it until the next launch on that key). In both, the runner then
  stamps on its own and only the pid *number* is left to recycle. `m3_joinable` closes it where the
  decision is made: a marker bearing the record's own token is proof that launch is over, because
  the stamp is the runner's last statement, so the call falls through to the launch arm — which
  clears the marker and evaluates the tree the caller actually has. `(dj13)`, which is `(dj11)`'s
  state with one token in place of two.
  **The completed-but-unconsumed evaluation is discarded, and that is the trade, not an oversight:**
  nothing proves it ran against this caller's tree, and the ceiling arm's remedy text is corrected
  to say a re-invocation rejoins the runner *while it runs* rather than unconditionally.
  **Rejected: having the runner delete its own pid record after stamping.** It depends on the runner
  surviving past its own last statement, so a `kill -9` in that window rebuilds the residue exactly;
  and an unconditional delete there can remove a *later* launch's record, whose waiter then reads
  the missing pidfile as a death and returns 7 having evaluated nothing.

## Out of scope

- **The scheduler's stop.** `orchestrate-lean.sh:491-492` states its own AC-3 premise and is
  correct on the information available to it (D-12). Verified rather than assumed: the scheduler
  invokes only `4` (under `LEAN_GATE_OBSERVE=1`) and `progress`, so `rc=7` reaches the block and
  never the loop.
- **A new milestone-scoped "mid-evaluation" record (D-8).** #497 shipped it — `append_started` /
  `append_concluded`, the unclosed difference, `INTERRUPTED_BUDGET` and `interrupted-exhausted`.
  This ticket adds no verb.
- **Extending launch-or-join past milestone 3** (OR-1) and **an in-turn retry loop on `rc=7`**
  (OR-2). Both are reversible defaults; the wrapper is keyed per milestone by construction, so
  extending it later is adding a key rather than revising a contract.

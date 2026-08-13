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
  `bash G 3 <issue>` spawns the evaluation detached (`nohup … &`, no `setsid` — it does not exist
  on macOS), the runner stamps its exit code into a marker file, and the invoking call BLOCKS on
  that marker rather than returning. The runner's output goes to a log the waiter replays to its
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
  gains a `(dj)` block covering AC-1..AC-7, each case on its own fixture tree so the runner key is
  its own, plus `(x3d)` pinning that `all` reaches milestone 3 through the same wrapper.
  **The prose half of AC-8 has no guard, and that is the decision, not an omission**: `CLAUDE.md`
  forbids prose-presence guards, because grepping a rule out of a SKILL asserts only that prose
  contains words and cannot fail for a reason a reader of the diff would not already see. The gate
  mechanism is the guard for the milestone-3 half; the "any in-flight work" half has no kill
  criterion and none is manufactured for it.

- **AC-11 — the mutation obligations that ride on editing a guard.** `tools/mutation-baseline.tsv`
  carries three generic-ordinal rows for `lean-gate.sh`; editing the guard re-keys them, so they
  are reconciled in this diff against what the sweep actually reports. Three new
  `tools/mutation-catalog.tsv` rows pin the mutants whose survival would be silent:
  `lean-gate-m3-no-join` (#500's livelock restored), `lean-gate-m3-stale-marker` (a green gate
  certifying a tree it never ran against) and `lean-gate-m3-death-blind` (#496's silence class at
  a second site).

- **AC-12 — the runner handshake is argv, not an environment variable.** Found by dogfooding, on
  this ticket's own first milestone-3 run. An exported `LEAN_GATE_M3_RUNNER=1` is INHERITED, and
  milestone 3's lane children in this repo are `lean-gate.sh` itself — so the flag reached the
  nested `lean-gate-selftest.sh` and every milestone-3 call inside it ran inline as a "runner":
  no detach, no marker, the mechanism absent while the outer run looked healthy. `--m3-runner`
  cannot reach a grandchild, and it is refused on any subcommand but `3`, where a stray one could
  stamp a marker some waiter is blocked on.

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

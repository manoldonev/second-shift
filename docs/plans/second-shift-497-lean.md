# second-shift #497 — an interrupted gate evaluation leaves a trace

A gate evaluation that is begun and never concluded currently writes **nothing**. `lean-gate.sh`
appends its milestone rows only _after_ the evaluation returns, so a process killed mid-run leaves
a record byte-identical to one where the milestone was never invoked. Every reader of that record —
`bash G all`, the resuming build session, the retro corpus — reads "not attempted" for a milestone
that ran for minutes and was cut off.

The fix is a pair of new line kinds around the milestone body, plus a bound on how often a
milestone may be interrupted.

Binding input: `.claude/pipeline-state/497-ledger.md` (pre-flight receipt, D-1 … D-12, OR-1/OR-2).
Where this spec and the issue body differ, the receipt is why.

## Design, in one paragraph

`run_milestone` — the single explicit `cmd_N` dispatch — wraps every milestone body:

```
validate n ∈ 1..5           (unchanged: an unknown subcommand still envfails writing nothing)
unclosed = started(n) − concluded(n)      # read BEFORE this call writes its own row
announce if unclosed > 0                  # announce, never refuse (D-4)
if unclosed ≥ INTERRUPTED_BUDGET:         # the one refusal (D-2)
    append `| milestone-n | interrupted-exhausted | <unclosed> unconcluded`; return 4
append `| milestone-n | started |`        # flushed before the long work (D-10)
rc = cmd_n
append `| milestone-n | concluded | rc=<rc>`   # non-idempotent, every return path (D-1)
return rc
```

The issue's own sketch — a `started` closed by the concluding `attempt`/`satisfied` line — is
unsound and is not built. `append_satisfied` writes at most one `satisfied` row per milestone ever
(D-41), and CLAUDE.md mandates a `bash G all` before the close-out step, which re-runs an
already-satisfied milestone. That design would leave a phantom unclosed row on **every honest run**.
Hence an explicit, non-idempotent `concluded` verb.

There is deliberately **no signal trap** (D-9). The design rests on the _absence_ of the concluding
line; a trap that wrote `concluded | rc=130` on SIGINT would make that absence mean two different
things, and SIGKILL — the case the guard must produce — cannot be trapped at all.

## Acceptance criteria

- **AC-1 — the pair is written around every milestone body.** `run_milestone` appends
  `<iso> | milestone-<n> | started |` before dispatching `cmd_<n>`, and
  `<iso> | milestone-<n> | concluded | rc=<rc>` on return, carrying the exit code the body
  produced. Applies generically to milestones 1–5 (D-5). An unknown subcommand still exits 2
  through `envfail` having written nothing.

- **AC-2 — `concluded` is non-idempotent.** N evaluations of one milestone append N `started` rows
  and N `concluded` rows, including on a milestone that already carries its single `satisfied` row.
  This is what makes the mandated pre-close-out `bash G all` leave a _closed_ record rather than a
  phantom unclosed one.

- **AC-3 — a killed evaluation is distinguishable from one that never ran.** A gate call SIGKILLed
  mid-evaluation leaves a `started` row for that milestone with no matching `concluded`; a
  milestone that was never invoked carries neither row. The suite drives this for real: a
  configured lane that blocks, `kill -9` on the gate's **process group**, then the record is read.

- **AC-4 — the next evaluation announces the unconcluded row, and still runs.** A subsequent
  `run_milestone` on that milestone prints a notice naming the unconcluded count and the budget,
  then dispatches the body normally (D-4: announce, never refuse — an interrupted milestone is
  precisely the one the resuming session must be able to re-run).

- **AC-5 — interruption is bounded on its own budget.** `INTERRUPTED_BUDGET=5` (D-7). A call made
  when the unconcluded count already stands at the budget appends
  `<iso> | milestone-<n> | interrupted-exhausted | <n> unconcluded` and returns 4 **without**
  running the body and **without** appending a `started` row. The number it reports is the
  unconcluded count it refused on, not a count of the lines it wrote itself. `rc=4` is reused
  rather than a new code invented, so `build-lean`'s existing hard-stop handling covers it.

- **AC-6 — no existing counter moves.** None of `started`, `concluded` or `interrupted-exhausted`
  is visible to `attempt_count`, `absent_count`, `design_was_armed`, `append_satisfied`'s
  idempotence check, or the `budget-exhausted` / `absent-exhausted` assertions. In particular the
  `progress` token is **unchanged** across a churn of started/concluded rows: the counted row set
  stays `satisfied$` and `attempt |` exactly (D-3). Counting the new verbs would make every dead
  spawn of a background-and-exit session read as advancement and burn the whole
  `--max-continuations` budget — strictly worse than today, where that pattern costs exactly one
  continuation.

- **AC-7 — an observed evaluation records nothing.** Neither `cmd_all`'s pre-pass nor a top-level
  `LEAN_GATE_OBSERVE=1 bash G <n> <issue>` writes a `started`, `concluded` or
  `interrupted-exhausted` row. Under observe the budget is **predicted** from the count already on
  file and reported as 4, mirroring `fail_milestone` / `block_milestone` exactly. Asserted for both
  paths, not assumed.

  **Deviation from the receipt, D-10.** That row concludes "Observe mode needs **no new guard** —
  `cmd_all`'s pre-pass calls `LEAN_GATE_OBSERVE=1 cmd_1` / `cmd_4` directly, bypassing
  `run_milestone` by construction." The bypass is real but it is not the only observe path: #496
  promoted the seam to a scheduler read, and `orchestrate-lean.sh:342` (`verdict_rc`) runs
  `LEAN_GATE_OBSERVE=1 bash "$GATE" 4 "$ISSUE"` as a **top-level** invocation, which the dispatch
  case routes straight through `run_milestone`. Unguarded, every round of every lean run would have
  the scheduler's read writing build-role rows — and it reds the existing `(ac4)` / `(ac6)` cases,
  whose contract is literally "records nothing". D-10 is a `codebase-derived` **fact** row and the
  fact is incomplete, so the guard is added rather than the contract bent.

- **AC-8 — the record's own documentation is current.** The pinned line-shape block at the head of
  the progress-file primitives section lists the two new verbs and the exhaustion line, and the
  budget constant is documented beside `FIX_BUDGET` / `ABSENT_BUDGET` with its sizing rationale.
  (Doc-scoped per CLAUDE.md; the pinned block is the record's schema, not prose.)

- **AC-9 — the mutation baseline is re-keyed in this diff.** Editing this guard re-keys its generic
  survivor ordinals; `tools/mutation-baseline.tsv` rows for `lean-gate.sh` are re-derived from a
  diff-scoped sweep on this branch, and any `tools/mutation-catalog.tsv` row addressing the guard
  is re-anchored if its pattern moved.

## Out of scope

- **Orchestrator consumption** (OR-2). `orchestrate-lean.sh` keeps its "gate exit codes and tracker
  state, nothing else" boundary. The record is useful to the resuming build session on its own, and
  the token is generation-prefixed `progress-v1:`, so adding a seam later is additive.
- **Concurrency disambiguation** (OR-1). Two concurrent gate calls on one milestone inflate the
  unclosed diff transiently and the predicate cannot tell in-flight from interrupted. Reaching the
  budget of 5 would need five simultaneous calls on one milestone, and the posture is
  announce-not-refuse, so the cost of an over-read is a spurious notice. A pid/lockfile liveness
  probe is narrowing, needs no contract revision, and is not pre-built — this repo already carries
  a `pgrep`-waiter deadlock scar.
- **A prose note in `build-lean/SKILL.md`** that a payload may be headless. Declined in #492 and
  still declined; it carries no possible guard, and `SKILL.md` is at 45 of its 60-line cap.
- **Special-casing an `exit` from inside a milestone body** (e.g. `envfail`). The row stays
  unclosed, identically to a kill (D-12): an aborted evaluation did not conclude, whichever way it
  aborted, and the honest record says so.

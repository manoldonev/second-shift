# second-shift #531 — every phase boundary infers completion from exit 0 instead of asserting terminal state

Part of #525. Absorbs #537, #529, and the milestone-5 half of #530.

The lane's four phase boundaries each read `claude -p`'s exit code — "the model stopped
talking" — as "the block finished", and the log has no vocabulary for the states that
distinguishes. `grep -c 'exit 1'` on `orchestrate-lean.sh` returns thirteen sites; `:477`
alone covers paused, crashed and orphaned-its-sweep. Fixed separately, each of the four
defects invents a partial vocabulary; fixed together they are one enum and four consumers.

Binding pre-flight input: `.claude/pipeline-state/531-ledger.md` (12 rows, D-1…D-12). Where
it and the ticket disagree the ledger wins — notably D-11 (only two of checklist step 9's
three obligations belong to milestone 5) and D-3 (the trap-based push named in the ticket's
Scope is not implementable and is dropped on mechanical grounds).

## Acceptance criteria

### The terminal-state vocabulary

- **AC-1** — `orchestrate-lean.sh` routes every run-ending exit through one helper that
  prints a control line carrying a stable machine-readable slug (`terminal: <slug>`) and
  then exits. No two distinct terminal conditions share a slug; every former bare
  `say …; exit N` pair that ends a run is one of them, the success path included. The
  script's **documented exit codes are unchanged** — 0/1/2/4/5/6/7 keep their meanings, and
  the taxonomy lives in the log rather than in the exit contract (D-1). `--help` prints
  usage and is not a run, so it carries no slug.

### Observability

- **AC-2** — `say` prefixes every control line with an ISO-8601 UTC instant in the gate's
  `now_iso` format, so scheduler lines and progress-file rows sort against each other
  without conversion (D-6). `envfail` is unified onto the same shape and the same stream as
  `say` — control lines are stdout, both of them (D-5).
- **AC-3** — each spawn's stdout and stderr are captured to a per-role log file under the
  pipeline-state dir and tee'd to the scheduler's **stderr**, so the run is three-way
  separable: the terminal stays live, a plain stdout redirect captures pure control lines,
  and the per-role file is pure payload and is the durable per-phase timeline (D-5). A
  capture that cannot be opened is reported and does not stop the run.

### The BUILD exit contract

- **AC-4** — the dirty-tree and unpushed-head tests move out of `worktree_destroy` into one
  shared predicate that `worktree_destroy` then calls, so teardown's decisions and its
  kept-worktree wording are unchanged. A new **read-only** gate subcommand exposes that same
  predicate: it records nothing, spends no fix budget, and does not create the progress file
  — the same posture `progress` and `staleness` hold. `0` = nothing in flight; a distinct
  non-zero = the lane worktree carries uncollected work, naming which arm fired and what it
  saw; `1` = the read could not be completed (fail closed).
- **AC-5** — the scheduler calls that subcommand on every BUILD spawn **that produced a PR**
  and after the close-out spawn, and treats uncollected work as its own named terminal rather
  than continuing. An answer it could not read is fail-closed, like `staleness` and
  `progress` beside it. It is a **scheduler-boundary** check only: nothing in `bash G all` or
  milestone 5 is gated on it, and the directly-invoked two-terminal flow is unchanged
  (D-3/D-4).

  *Amended mid-build, before milestone 5, per the checklist.* The ticket says "after every
  BUILD spawn"; that placement hard-stops the spawn #527 taught the loop to **continue** from.
  A build session legitimately holds unpushed commits for most of its life — milestone 3 runs
  long before checklist step 7 pushes — so an unconditional check reds an infrastructure kill
  mid-sweep. The harm the ticket actually describes is a review reading a PR's stale remote
  head, which needs a PR to exist; gating on that is where the check belongs, and it makes the
  unreadable arm a genuine environment error rather than the ordinary state of a young lane.
  Guarded in both directions (AC-12).

### The review phase

- **AC-6** — `verdict_rc` runs **before** the REVIEW spawn in every round. `rc=0` there logs
  a named terminal-vocabulary line, spawns no REVIEW, and falls into the close-out phase, so
  no second review is ever spawned against a head that already carries an approve — and no
  competing verdict record can be authored for it. Every other class routes exactly as it
  does today (D-7).

### The close-out

- **AC-7** — a close-out that records no NEW milestone-5 satisfaction but **advanced** the
  general progress token is continued in one fresh session. The budget is exactly one,
  hard-coded and not a flag, mirroring `MAX_REVIEW_RETRIES` (D-8). The advancement predicate
  is the general `progress_token` delta, reused verbatim from the build phase — no third
  token space (D-9). A close-out that advanced nothing is the named terminal immediately.

### Milestone 5 reports its obligations separately

- **AC-8** — `cmd_5` appends one row per obligation it owns — the closing comment and the PR
  exit artifacts — under a verb **distinct from** the aggregate `satisfied`, and appends the
  aggregate row only when every obligation it owns holds. The distinct verb is load-bearing:
  `progress_token` narrows by fixed-string substring match, so an obligation row echoing the
  aggregate verb would move the scheduler's satisfied token on a partially finished close-out
  and print `done` (D-10).
- **AC-9** — `cmd_teardown` appends its own **diagnostic** row recording `removed`,
  kept-with-reason, or nothing-to-remove, and still returns 0 on every path. Teardown is
  reported, never certified: step 9 runs it after milestone 5, and gating the aggregate on it
  would make the sanctioned kept-worktree state red a run that actually finished (D-11).
- **AC-10** — the scheduler's close-out failure message names the two obligations milestone 5
  owns, each with its own state read from the record, plus teardown's recorded outcome read
  separately. It no longer claims milestone 5 certifies the teardown (D-12).

### Tests

- **AC-11** — `scenario-liveness-selftest.sh` gains a leg composing the **real** scheduler,
  the **real** gate and a real `git worktree` through BUILD → REVIEW → close-out where the
  first close-out spawn leaves its obligations partly unmet, and the run still reaches its
  terminal write via the continuation arm. It carries a paired non-vacuity arm that varies
  the fixture and must reach no terminal write. This leg is the epic's acceptance evidence.
- **AC-12** — `orchestrate-lean-selftest.sh` gains cases at the orchestrator boundary for:
  a BUILD spawn that exits 0 with work in flight; the approved-head review skip and its
  non-vacuity direction; and the terminal slug vocabulary, asserted per terminal rather than
  by grepping the source.
- **AC-13** — `lean-gate-selftest.sh` gains cases for the shared predicate's new subcommand
  (both firing arms, the unreadable direction, and its read-only posture), for milestone-5
  **partial** satisfaction — obligation rows written, aggregate row withheld, and the
  scheduler's token unmoved — and for the teardown diagnostic row on each of its three
  outcomes.

### Register upkeep

- **AC-14** — `tools/mutation-baseline.tsv` rows whose ordinals this diff re-keys are
  re-baselined in this diff, and any `tools/mutation-catalog.tsv` row whose anchor D-3's
  extraction moves is re-anchored.
- **AC-15** — the two scripts' header usage blocks document what changed — the new gate
  subcommand and its exit code, and the scheduler's terminal-slug contract — and each
  script's `sed -n '2,Np'` help range is re-pinned so `--help` is not truncated.

## Out of scope

- A trap-based push on BUILD's exit paths (ticket Scope). SIGKILL is untrappable and under
  `claude -p` no build-session process persists to carry a trap, so its only host would be
  the scheduler's `spawn()` — which would make the scheduler a source-control writer against
  its own header (D-3).
- Documenting the thirteen conditions in `run-lean/SKILL.md`. It sits at exactly the 60-line
  cap its selftest asserts, the eight documented exit codes are unchanged, and nothing in the
  lane branches on an exit-1 subclass (D-1).
- #530's teardown criterion. #530 stays open for it; only its AC-1 comes here (D-2).

## Testing

Per the tier map: the composed BUILD → REVIEW → close-out path is a scenario
(`scenario-liveness-selftest.sh`); "exits 0 with work in flight" is genuinely new at the
orchestrator boundary (`orchestrate-lean-selftest.sh`), where `fake-gate.sh` would otherwise
make the case assert the fake's behavior; milestone-5 partial satisfaction, the teardown row
and the shared predicate are gate-side (`lean-gate-selftest.sh`). Editing these guards
re-keys their generic survivor ordinals — re-baselined in the same diff (AC-14).

# #759 — the milestone-3 kill guards red when a lane wins the fork race

Two selftest cases assert the same property — #566 AC-1, "milestone 3 detaches nothing" — against
the same `sleep 20` fixture, and both carry the same defect: they `kill -9` the gate's process
group without first establishing that the lane child exists. A child forked while `killpg` is
being delivered inherits the group and never receives the signal (reproduced: 21 escapes in 300
iterations), so it outlives a fixed 5s reap budget and the guard reports a lost race as a detach.

One property, one bug, two guards. `(if5b)` goes; the survivor in the liveness scenario is fixed
at its cause.

## Acceptance criteria

- **AC-1** — `(if5b)` is gone from `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`:
  no `pass` or `fail` line names it, and its own reap loop and comment go with it. `(if5)`,
  `(if5c)` and the kill scaffolding they share (`set -m`, the backgrounded gate, `kill -9 -PGID`,
  `wait`) are unchanged.
- **AC-2** — `(lean-inline-m3-nv)` in
  `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` signals the gate's
  process group only after the lane process is observed **in that group**, so no child can be
  forked into the group after the signal has been delivered. The remedy is at the cause: the
  reap budget is not widened, because a budget longer than the lane's own `sleep 20` would let
  the case pass because the lane expired rather than because it was killed.
- **AC-3** — the hardened case still reds on an injected detach. A lane run in a session of its
  own — the #547 `setsid(2)` escape shape, which no group-scoped check can see — is reported as
  a detach rather than passing. Demonstrated by an in-lane probe over an injected fixture, its
  command and output recorded in **Liveness probe** below.
- **AC-4** — every live suite comment that cross-references `(if5b)`
  (`lean-gate-selftest.sh:1470`, `scenario-liveness-selftest.sh:2342`) names only cases that
  still exist. Verdict records under `docs/plans/` are history and stay untouched.
- **AC-5** — the branch's net diff over `origin/main`, excluding this spec and the review
  verdict record, is **negative** (#717's stopping rule, D-10).
- **AC-6** — both suites pass: `bash plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`
  and `bash plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh`.

## OR-1 — the remediation shape (`reversible-default-and-flag`)

Chosen: **assert on the lane child, and signal only once it exists.** The other two were
considered and rejected:

- *Bound the wait by the lane's own lifetime* — the fixture lane is `sleep 20` and the reap
  budget is 5s. Widening past 20s makes every run green, including one where the gate genuinely
  detached a `sleep 20`: the case would pass because the lane expired. That retires #566 AC-1
  instead of fixing it, which D-8 forbids.
- *Re-signal after a settle* — reaps the in-group escapee, and nothing else. The escape #547
  actually shipped was `setsid(2)`: a new session and a new process group, which a second
  `killpg` on the old group misses exactly as the first did. It would fix the false red while
  leaving the case blind to the only detach the repo has ever had.

Waiting for the lane in the group does both jobs with one predicate. Present → the signal cannot
race a fork that has already happened. Absent → the lane is running somewhere the gate's group
cannot reach, which *is* the detach.

## Liveness probe

Recorded at implementation time; see the section appended below the ledger.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Is the red a content regression or a false red? | False red — `e83f93fefc63` (green, 22:31) and `153188f5806b` (red, 22:40) share tree `6cae53cbfa883cb5c7308211d2dd2352bd970405`; green again at `c10282472bee` (run 33502529274) | codebase-derived |
| D-2 | What the ticket is for | Remove the guard's false-red mode; the non-detachment assertion keeps its meaning | user-answered |
| D-3 | Fix scope | RE-CUT 2026-09-01 after #717's stopping rule was surfaced: DELETE `(if5b)` (`lean-gate-selftest.sh:8008-8026`, 19 lines) and harden the surviving `(lean-inline-m3-nv)` (`scenario-liveness-selftest.sh:2411-2417`). Supersedes the original "harden both" answer, which predated the constraint | user-answered |
| D-4 | The other `kill -9 -PGID` sites | Out of scope — `tools/mutation-sweep.sh:1277` and `tools/install-topology-selftest.sh:80` are cleanup paths with a plain-PID fallback; they assert no property, so they carry no false-red mode | user-answered |
| D-5 | Ticket identity | Re-title #759 in place; the SHA-pinned bot title describes an event, not a defect | user-answered |
| D-6 | Is bash 3.2 the causal axis? | No — the ubuntu job is Linux and bash 5, so OS and shell version are confounded; the ticket names the lane | codebase-derived |
| D-7 | Filer behavior once #759 is retitled | CORRECTED 2026-09-01: the D-5 retitle removes the substring `install-topology guard red` that `file-issue-on-red` dedupes on, so the next red files a DUPLICATE stub rather than being suppressed. The decision stands; its stated consequence was backwards | codebase-derived |
| D-8 | Non-vacuity obligation on the hardened guards | Required — the repo's `writing-tests` contract mandates a liveness demonstration, so the hardened case must still red on an injected detach | codebase-derived |
| D-9 | Build model sizing | `opus` — the deliverable is not a prose diff: it must remove a concurrency false-red across two suites while preserving the non-vacuity property #566 bought (D-8), and OR-1 leaves the remediation shape for the builder to choose. Per `intake-orchestrator`'s sizing contract, an open call plus a guard surface is `opus`, not `sonnet` | codebase-derived |
| D-10 | Ratification basis under #717 | A `harness-internal` ticket needs a negative net diff and an honest consumer story. "Harden both" had neither: no consumer runs `install-topology`, and it only adds shell. Deleting the duplicate assertion of #566 AC-1 yields net ≈ −14 and removes guard mass carrying a duplicated defect, so the ticket clears the bar with no exception claimed | user-answered |
| D-11 | Is the fork-escape mechanism real, or inferred? | REPRODUCED — 300 iterations of `(if5b)`'s structure, 21 escapes, survivor a `sleep 20` in the target PGID; race crossed bash 3.2 (outer) and bash 5 (inner), so it is a kernel `killpg` race. Attribution of THIS run to it remains by elimination | codebase-derived |

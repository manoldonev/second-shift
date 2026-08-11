# second-shift #492 — a BUILD session that stops early must not end the lane

`orchestrate-lean.sh` advances on the BUILD spawn's exit status. `claude -p` exits 0 whenever the
model ends its turn cleanly, which is "the model stopped talking", not "the block finished". The
loop models two post-spawn states — finished (a PR exists) or failed (non-zero) — and misses the
third an autonomous lane actually hits: **exited 0, no PR, but the run advanced**.

The same defect sits at the close-out site with the opposite polarity. `verdict_rc` runs *before*
that spawn and nothing evaluates after it, so a close-out that ends its turn early exits **0** and
prints `done` while step 9's obligations are unmet — no closing comment, milestone 5 unsatisfied,
the worktree still on disk, and the claimed label still set on a ticket the lane just declared
finished.

The pre-flight ledger for this ticket (`.claude/pipeline-state/492-ledger.md`, D-1 … D-10, OR-1) is
binding input and is transcribed into the ACs below where it resolves or overrides the issue text.

## Acceptance criteria

- **AC-1** — after a BUILD spawn that exits 0 and leaves no open PR, `orchestrate-lean.sh` consults
  the run's progress record and re-spawns BUILD when that record advanced during the spawn. A
  continuation is a fresh `-p` session, never `--resume` — the existing separation rule is
  unchanged, and the continuation prompt is the unchanged `/dev-pipeline:build-lean <issue>` (D-5).

- **AC-2** — continuations are bounded by `--max-continuations`, default **2** (D-3), and
  exhausting it exits 1 naming the cap. The bound is on *consecutive* spawns that leave no PR: the
  counter resets whenever a spawn yields a PR, so each build phase gets its own budget and a run
  that keeps advancing is not starved.

- **AC-3** — a BUILD spawn that exits 0, leaves no PR, and advanced **nothing** still exits 1 with
  today's message and one spawn. Existing case `(j2)` keeps passing unchanged.

- **AC-4** — the milestone fix budget stays the real bound on a looping build: a continuation that
  keeps redding a milestone reaches the gate's `rc=4` hard stop exactly as today. No new budget is
  introduced, and the scheduler never invokes a milestone evaluation of its own.

- **AC-5** — "advanced" is read from an artifact the gate already writes, not from spawn stdout,
  and the definition is pinned in one place. Concretely (D-1/D-2): a new
  `| milestone-<n> | satisfied` or `| milestone-<n> | attempt |` row in the progress record, with
  bookkeeping rows (`entry`, `| session |`) excluded — `record_build_session` appends a `session`
  row on every fresh session's `entry` call, so "the file changed" would be true for any spawn
  reaching checklist step 1 and would leave AC-3 unreachable. The predicate lives behind a new
  read-only `lean-gate.sh progress <issue>` subcommand that prints an **opaque token**; the
  scheduler compares the token before and after a spawn and interprets nothing, which keeps
  `orchestrate-lean.sh`'s stated boundary ("gate exit codes and tracker state") intact.

- **AC-6** — new `orchestrate-lean-selftest.sh` cases: exit-0 + no PR + progress advanced ⇒ a
  second BUILD spawn occurs and the run reaches REVIEW; exit-0 + no PR + no progress ⇒ rc=1, one
  spawn, message unchanged; the continuation cap is honored and named on exhaustion.

- **AC-7** — a close-out BUILD spawn is not credited on its exit status. Overriding the AC's
  literal text per D-8, the close-out is credited **iff a new `| milestone-5 | satisfied` row
  appears during its spawn**, read through AC-5's subcommand — not by the scheduler invoking
  `bash G 5`. Two reasons the literal mechanism is unreachable: step 9 ends with `bash G teardown`,
  which destroys the worktree, so on the happy path there is none to evaluate in; and a
  scheduler-invoked `cmd_5` that fails routes through `fail_milestone`, appending an attempt row
  and consuming milestone 5's fix budget, which AC-4 forbids. Requiring the row to be **new** keeps
  a re-entered lane from being credited with a prior run's milestone 5. An uncredited close-out is
  a non-zero exit naming what is unmet (D-9) — verify-only, no re-spawn; the continuation machinery
  of AC-2 is not extended to this site.

- **AC-8** — the new `progress` subcommand is exercised by `lean-gate-selftest.sh`, and the AC-7
  close-out cases by `orchestrate-lean-selftest.sh` (D-10). `progress` writes nothing and creates
  nothing — in particular it must not create the progress file it reads — and is **not** added to
  `require_entry_attested`'s subcommand set (D-2): it reads the very file that would prove entry.

## Out of scope

- **The REVIEW spawn.** A review session that stops early leaves no committed verdict, and
  milestone 4 already reds on that with a fix budget.
- **A prose note in `build-lean/SKILL.md`** that a payload may be headless. Cheap, but it carries
  no possible guard and must not be what this ticket rests on.
- **Documenting `--max-continuations` in `run-lean/SKILL.md`.** The flag's documented home is the
  script's `--help` header, exactly as for `--max-rounds`; the SKILL carries a 60-line
  anti-accretion cap that case `(n0)` asserts.

## Stated ceiling

`orchestrate-lean-selftest.sh` fakes the spawn, so no CI case can prove that a real `claude -p`
continuation completes `build-lean` unattended. Every AC here is provable against the fakes; the
end-to-end is an operator observation on the next live run.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | A continuation re-enters `build-lean` at checklist step 1, whose queue-label confirm ("a missing one is a reject, no prompting") is prose and now sees the claimed label the first spawn swapped in | reversible-default-and-flag |

OR-1's default: the continuation prompt is unchanged (AC-1), on the evidence that today's round-2
fix-round spawn already re-enters `build-lean` on an already-claimed ticket and does not
self-reject. It is reversible because the remedy is a one-line scope in `build-lean/SKILL.md` or a
follow-up ticket — nothing on disk needs undoing. The fake-spawn selftest cannot catch this class,
which is why it is declared rather than assumed away.

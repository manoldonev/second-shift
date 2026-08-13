# second-shift #515 — a build session never re-checks whether its ticket was resolved on main

The lean lane reads tracker and base state exactly once, at preflight, and never again. A run
whose premise expired mid-flight keeps spending continuations against a base that already
carries its fix. Measured on this repo: #510 landed the fix at 12:33Z, the #502 build session
worked until 13:03Z re-implementing it, and #502 itself was not closed until 13:36Z.

Detection is the ask. Remediation — rebasing, or any decision about what to do with a moved base
— is explicitly out of scope, as is any exclusion list for paths that do not count toward
overlap.

The pre-flight ledger at `.claude/pipeline-state/515-ledger.md` is binding input; D-n and OR-n
below refer to its rows.

## The two signals, and why the weaker one alone is not enough

**Ticket state lags.** #502 was open for the entire redundant hour. A ticket closing records a
human noticing, not the event. It is still worth reading — a launch onto an already-closed ticket
should not spend a run — but it cannot be the whole check.

**Bare base advancement over-fires.** 178 first-parent merges to main in 21 days ≈ 9.4/day ≈ one
every ~1.5 working hours, so "the base moved" is true on essentially every multi-hour run. The
predicate has to be file overlap (D-1):

```
files(merge-base..origin/<base>) ∩ files(merge-base..<branch>) ≠ ∅
```

Validated against the incident: #510 landed 7 files, 4 of which #502's branch was also touching.

## Acceptance criteria

**AC-1 — a read-only `staleness` subcommand on `lean-gate.sh`.** `bash lean-gate.sh staleness
<issue> [--arm ticket|base|both]` evaluates the two arms and returns a taxonomy: `0` clean or
stated skip, `7` stale, `1` a read that could not be completed, `2` usage. It is read-only in the
strict sense the scheduler's contract needs (D-3): it appends no progress row, consumes no fix
budget, writes no `satisfied` line, and creates no file — including the progress file, which it
never touches. It is NOT in `require_entry_attested`'s set: it is called before the first BUILD
spawn, when no `entry` row can exist yet.

**AC-2 — the base arm is file overlap, not advancement.** A base that advanced with no file in
common with the branch's own diff is `0`. A base whose new commits touch a file the branch also
touches is `7`, and the message names the overlapping paths. `--arm ticket` skips it.

**AC-3 — the ticket arm reads any closed state.** Under `tracker.type: github`, a `CLOSED` issue
is `7` whether its reason is `completed` or `not_planned` (D-7) — #502 itself closed
`NOT_PLANNED`. Under `jira` the arm prints a stated skip and returns `0` (D-8); the base arm still
runs. `--arm base` skips it.

**AC-4 — no branch yet is a skip, not a failure.** On round 1's first pass `refs/heads/<branch>`
does not exist, so there is no range to compare: the base arm states a skip and returns `0`, and
the ticket arm still runs (D-9). A skip must not route to AC-5's fail-closed exit.

**AC-5 — a read that cannot be completed stops the run.** A failed fetch of `origin/<base>`, an
unresolvable merge-base, or a failed/unparseable tracker read returns `1` naming which read failed
(D-5). A stale remote-tracking ref would make the base arm answer "nothing moved", which is
indistinguishable from a clean check.

**AC-6 — every BUILD spawn is preceded by the check, and only BUILD spawns are.** The scheduler
calls the subcommand at the top of its inner build loop, so round-1 entry, every continuation, and
every later round's build spawn are all covered (D-4). The REVIEW spawn and the close-out BUILD
spawn are deliberately NOT checked: an approved PR must still land, or the stop strands finished,
reviewed work.

**AC-7 — the stop is its own exit code.** `7`, for both arms, distinct from `1` (a phase failed)
and from every other class in the taxonomy (D-6). The scheduler's log line names which arm fired
and what it saw, and states the two operator actions — rebase and re-launch, or abandon the ticket
— including that a re-launch without rebasing re-fires exit 7 at the same point (D-10). The
worktree and the claim are left in place, as on every other non-zero exit. Any rc from the
subcommand other than `0` and `7` exits `1`.

**AC-8 — preflight re-checks the ticket arm.** A launch onto an already-closed ticket is rejected
by preflight with exit `2` and nothing spawned, reported alongside the other probes in one
invocation. Preflight runs `--arm ticket` only: the base arm belongs to the loop, so a re-launch
without a rebase fires exit 7 at the loop rather than exit 2 here (D-6, D-10).

**AC-9 — the documentation the operator reads at the stop.** `run-lean/SKILL.md` gains the `7`
row in its exit taxonomy and the operator instruction for it, and states OR-3 in "When it stops":
a spawn-boundary check cannot reach a session already running, so the incident's 30 redundant
in-session minutes would still be spent — the check bounds the damage at one session, not at zero.
The 60-line cap on that file holds. Both tools' `--help` ranges stay pinned to their headers.

**AC-10 — the arms are proven against the real predicate, not a fake.** `lean-gate-selftest.sh`
drives the REAL subcommand over a real fixture repo with a real local `origin` remote and a real
`git fetch`, covering: overlap fires, advancement-without-overlap does not, the closed/open ticket
pair, the jira skip, the no-branch skip, both fail-closed arms, `--arm` selection, and the
zero-write posture. `orchestrate-lean-selftest.sh` covers the scheduler's wiring against its fake
gate — call site and ordinal per spawn, the absence of a call before REVIEW and before the
close-out, the rc→exit mapping, and preflight's ticket arm. One case drives the scheduler with
`LEAN_GATE` pointed at the REAL gate, so exit 7 is produced end-to-end by the real predicate at
least once: the named vacuity risk is that a fake-gate suite can "cover" an arm no test ever
executes.

## Open Regions

Carried from the ledger, all three `reversible-default-and-flag`, all three shipped at their
default:

- **OR-1** — every release merge rewrites `docs/onboarding.md` (32 of 32 measured), and it is not
  a frozen file, so a branch editing it overlaps every release: ~7% of runs would take a
  release-driven stop. No exclusion list. The class is named in the subcommand's header and in the
  exit-7 message so an operator recognizes it in one read. Reversing it means a config key of
  paths that do not count — which re-introduces the "which paths don't count" judgment the
  mechanical predicate exists to avoid.
- **OR-2** — a standalone `build-lean` session gets no staleness check. The subcommand is callable
  and `build-lean/SKILL.md` is unchanged; both ACs in the ticket name scheduler concepts.
- **OR-3** — a spawn-boundary check cannot stop a session already running. Structural, and stated
  in `run-lean/SKILL.md` rather than engineered around; a mid-session check inside `build-lean` is
  a different ticket.

## Out of scope

Auto-rebasing or any remediation. Any exclusion list for paths that do not count toward overlap.
A staleness check inside a running build session.

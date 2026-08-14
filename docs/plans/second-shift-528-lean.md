# second-shift #528 — signal-killed suites orphan their fixtures, and same-issue progress writes are not atomic

Part of #525. Two seams that assume a lane is alone: fixture directories orphaned by
signal-killed suites, and progress-file writes that are idempotent but not atomic.

`#526` (the lane registry) has not landed at the time of this build — its unmerged PR is still
in review. AC-1 therefore takes the first of the ticket's two offered options: stamping
ownership directly into the two `mktemp` templates, rather than depending on unmerged code.

## Acceptance criteria

**AC-1 — orphan fixture directories are reaped, age-and-ownership guarded.**
`lean-gate-selftest.sh` and `orchestrate-lean-selftest.sh` each tag their `mktemp -d -t`
template with `<pid>.<stamp>`, where `<stamp>` is that pid's process start time from
`ps -o lstart=`, sanitized and treated as an opaque string — never parsed, never reformatted
(BSD/GNU render `lstart` differently). A new tool, `tools/reap-lean-fixtures.sh`, scans
`${TMPDIR:-/tmp}` for `leangate.*`/`orchestrate-lean-selftest.*` directories and removes one
only when BOTH hold:

- **Ownership says it is not live**: the embedded pid is gone, or a different process now holds
  a recycled pid (its current `ps -o lstart=` no longer matches the embedded stamp). "Cannot
  tell" — a pid that is alive while its start time is unreadable — is a third answer, and it
  keeps. Every failure to establish ownership resolves toward keeping.
- **Age clears a floor**: a short one (10 min) when ownership already answered the safety
  question, a long one (24h) for a name with no ownership signal at all (a legacy pre-fix
  orphan, or anything unparseable) — age is the floor beneath ownership, never a substitute.

**Writer and reader share ONE expression** — `tools/fixture-stamp.sh`, sourced by the reaper and
by both fixture-producing suites. Two spellings of the sanitization is not a style question: the
producer piping `ps` output *including its newline* into `tr` and the consumer letting `$()`
strip the newline first agree only on a `ps` that pads its `lstart` column with a trailing
blank. Under one that does not, the stamp read back never matches the stamp written, ownership
reads as "not mine", and the reaper deletes a live suite's working tree — the exact harm the
ownership check exists to prevent, and worse than shipping no reaper at all. The shared
sanitizer is also made insensitive to that difference in the first place (a run of non-alnum
squeezes to one separator, and leading/trailing separators are stripped), so the agreement does
not depend on which `ps` the machine has.

The producers treat the library as **optional**: a shipped plugin install carries no `tools/`
directory, so a suite that cannot find it builds an unstamped name and the reaper governs it by
the long legacy floor alone. No stamp beats a stamp the reader reads back as somebody else's.

`tools/run-selftests.sh` invokes the reaper once, near entry, guarded on the tool's presence
under the sweep's own `--root` — inert for a synthetic fixture tree (run-selftests-selftest.sh),
live for a real sweep. A reap failure is best-effort and never fails the sweep it runs from.

`lean-gate-selftest.sh` also moves its `trap` above its `mktemp` call, closing the second,
smaller window the ticket named: a signal in the five lines between the old order left `WORK`
unprotected even though a trap was about to be installed.

Cross-lane safety: the reaper's ownership check happens immediately before its `rm -rf`, and a
candidate that vanishes mid-walk (removed by a concurrent reaper) is reported as skipped, never
treated as fatal.

**AC-2 — `append_satisfied` and `heal_progress_run_id` are atomic against a concurrent
same-issue writer, introducing no blocking waiter.**

- `heal_progress_run_id` moves from a fixed `$PROGRESS_FILE.heal` sibling to a unique
  `mktemp`-generated temp file before its atomic rename — two concurrent heals no longer stomp
  each other's in-flight write. This is the seam the ticket's parenthetical mechanism (unique
  temp + atomic rename) fits: a heal genuinely has to rewrite the file.
- `append_satisfied` moves from a bare read-then-`>>`-append to a **released mutex around a
  re-check and an append**: `mkdir` (atomic, refuses an existing target) admits exactly one of
  any number of concurrent same-issue writers, the row's absence is re-read *inside* the critical
  section, and the claim is removed immediately after. Nothing waits and nothing retries — a
  writer that loses returns, because the winner is inside writing the very row it would have
  written. The re-check, not the `mkdir`, is what makes "exactly one satisfied line" hold however
  far apart two writers' checks and writes fall.

  **It deliberately does NOT take the unique-temp + atomic-rename shape**, though the ticket's
  AC-2 names that mechanism. Applied here it rebuilds the whole file, which makes
  `append_satisfied` a *second* rewriter of the record — and `progress_token()`'s written
  soundness argument (`lean-gate.sh`, "WHY A COUNT IS A SOUND TOKEN") depends on there being
  exactly one. That argument states these rows are append-only and so the selected count "cannot
  go up and back down within a spawn"; a rebuild built from a fresh-at-write-time read can drop a
  row a concurrent `append_attempt` wrote in the gap, which is precisely that movement, and the
  scheduler compares that token byte-for-byte to decide whether the BUILD phase advanced. A
  dropped `attempt` row also un-charges #494's fix budget by one, silently and permanently:
  `append_attempt` fires only on a fresh failure, so a re-evaluation never replays it. Keeping
  this function append-only keeps the invariant true rather than leaving it standing while false.
  AC-2's requirement — atomic against a concurrent same-issue writer, no blocking waiter — is met
  more strictly, not relaxed.

  A **persistent** per-milestone claim was tried and rejected, measurably: it cannot tell "held by
  a genuinely concurrent writer" from "orphaned by a record replaced since", and this repo replaces
  records routinely (the gate recreates a deleted one; an operator or a fixture writes one
  directly). Such a claim permanently blocks its milestone from ever being recorded satisfied
  again — it reded a full `all` sweep in `lean-gate-selftest.sh`'s own fixture. Releasing the mutex
  after the append is what removes that class.

  The residual risk this design accepts: a writer KILLED between `mkdir` and `rmdir` leaves a claim
  behind, blocking that milestone until swept. The window is microseconds wide and the run it kills
  is over anyway; `clear_satisfied_claims` sweeps orphans at `entry`, which every session runs
  before anything else, so recovery is the checklist's existing first step rather than a new one.

Tested with a genuine, controlled two-writer race (not timing-dependent): a test-only seam,
`LEAN_GATE_TEST_STALL_DIR` (never set in CI or by an operator, alongside the existing
`LEAN_GATE_OBSERVE`/`LEAN_GATE_WAIT_CEILING_SECS`/`RUN_SELFTESTS_DROP_LAST` precedents), pauses
the caller between its absence check and its write so two real background gate processes can be
forced to both observe "absent" before either commits.

**AC-3 — the resolved config path is announced.** `lean-gate.sh` prints `config: <path>` to
stderr once per invocation (via the existing `warn` helper), for every subcommand except
`progress` — whose own contract is a bare, machine-read token
(`orchestrate-lean.sh`'s `progress_token()` captures this script's stdout verbatim and compares
it byte-for-byte across two reads; even a stderr-only announcement would ride along in any
merged capture, so it is skipped there specifically). A config re-point mid-run is now visible
in the output of the next invocation, rather than needing to be inferred from file timestamps
afterward.

## Explicitly out of scope

Unchanged from the ticket: `cost-log.jsonl` atomicity, a marker-file naming contract pending
#511, and a shared fixture harness across ~64 suites. Also out of scope here: retroactively
reaping fixture orphans created by a pre-fix version of the two selftest templates (they carry
no ownership stamp and fall to the reaper's long, unstamped-name floor — a one-time manual
clearing, same as this repo's existing documented recipe, rather than a guarantee this reaper
makes).

## Tests

- `tools/reap-lean-fixtures-selftest.sh` (new): a live-owner fixture kept regardless of age; a
  dead-owner fixture removed once past the short floor and kept below it; a recycled-pid
  (stamp-mismatch) fixture treated as not-owned; an unstamped legacy name governed by the long
  floor alone; unrelated tmp content never touched; an unreadable ownership source degrades to
  not-owned rather than crashing; `--dry-run` reports without removing; a candidate removed by a
  concurrent reaper does not fail the run; the usage floor. Plus, for the safety half specifically:
  - a **writer→reader round trip** — the fixture name is built by `fixture_stamp_own`, the same
    function the producing suites call, and fed to the real reaper, which must keep it. It is not
    a re-derivation of the reader's expression: comparing the reader against a copy of itself is
    what let the two sides disagree unnoticed in the first place.
  - the sanitizer produces **one token** for a padded, a newline-terminated and a bare `lstart`
    string, so the round trip does not depend on which `ps` the machine has.
  - a live pid whose start time is unreadable is **kept** ("cannot tell" is not "not mine").
  - the **default floors** (600s / 86400s) decide, run with no flags — the sole production call
    site passes no overrides, so those two constants are what gate real deletions, and every other
    case passing explicit ones left them unexercised.
- `lean-gate-selftest.sh` (`(rc1)`-`(rc7)`, `(rc4a)`): two genuinely concurrent `append_satisfied`
  calls for the same milestone leave exactly one satisfied row; the mutex is released after its
  append and an orphaned one is swept at `entry` rather than blocking the milestone forever; two
  genuinely concurrent heals of the same frozen header leave it healed exactly once, and no temp
  survives; a heal leaves a **planted file at the pre-fix fixed `.heal` path untouched**, which is
  what makes the unique temp assertable at all — two racing heals resolve the same id and write
  byte-identical output, so the collision they used to have has no observable effect on the result
  and a race case cannot see it; the config path is announced on an ordinary subcommand and
  re-announced with a NEW path after a mid-run re-point; the announcement does not fire on
  `progress`.

  The two race coordinators bail as soon as a writer has exited rather than waiting out their full
  10s ceiling. That is not cosmetic: under `tools/mutation-sweep.sh` the ceiling is spun in full
  once per mutant that stops a writer short, which is wall-clock sleep on a 2-worker CI pool and
  pushed the PR-scoped sweep past its 15-minute budget.
- `run-selftests-selftest.sh`: a fixture root carrying an executable `tools/reap-lean-fixtures.sh`
  proves the call site fires and that a failing reaper leaves the sweep's verdict green, with an
  absent-tool control proving the case reads the guard's true branch. Every other root it builds
  lacks the tool, so the call is inert there without a dedicated seam. Stated precisely because it
  was measured: the green-on-failure property comes from this harness deliberately not being
  `set -e`, not from the call site's `|| true` — dropping that token leaves the case green, so the
  case pins the behavior and not the token.
